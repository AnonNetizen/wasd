# Doc: docs/代码/debug_test_arena.md
# Authority: docs/测试策略.md §2.2 / §5.10, docs/决策记录.md ADR #159 / #160
extends Node


const CONFIG_SCRIPT := preload(
	"res://scripts/debug/debug_test_arena_config.gd"
)
const ACTIONS := preload("res://scripts/contracts/actions.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const SENTINEL_META: Dictionary = {
	"debug_test_arena_sentinel": "meta",
}
const SENTINEL_RUN: Dictionary = {
	"debug_test_arena_sentinel": "run",
}

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var host: Node = get_parent()
	_check(
		host != null
		and host.has_method("debug_start_test_arena_for_smoke")
		and host.has_method("debug_active_setup")
		and host.has_method("debug_service_state_before"),
		"standalone host exposes smoke lifecycle"
	)
	if not _failures.is_empty():
		_finish()
		return

	var service_state_before: Dictionary = host.call(
		"debug_service_state_before"
	) as Dictionary
	var replay_enabled_before: bool = bool(
		service_state_before.get("replay_enabled", false)
	)
	var analytics_enabled_before: bool = bool(
		service_state_before.get("analytics_enabled", false)
	)
	var initial_setup: CanvasLayer = host.call(
		"debug_active_setup"
	) as CanvasLayer
	_check(
		initial_setup != null and UIManager.top() == initial_setup,
		"standalone scene opens loadout first"
	)
	_check(
		get_tree().root.find_child("TitleMenu", true, false) == null,
		"standalone scene does not mount the formal title"
	)
	_check(
		not Replay.is_enabled() and not Analytics.is_enabled(),
		"standalone host suspends Replay and Analytics"
	)
	_check(
		SaveManager.save(
			SaveManager.DEFAULT_SLOT,
			SAVE_KINDS.META,
			SENTINEL_META
		),
		"write isolated meta sentinel"
	)
	_check(
		SaveManager.save(
			SaveManager.DEFAULT_SLOT,
			SAVE_KINDS.RUN,
			SENTINEL_RUN
		),
		"write isolated run sentinel"
	)

	var config_manager: RefCounted = CONFIG_SCRIPT.new()
	var invalid: Dictionary = config_manager.call(
		"normalize_config",
		{
			"schema_version": 99,
			"seed": 0,
			"character_id": "missing_character",
			"weapon_id": "missing_weapon",
			"primary_skill_id": "missing_skill",
			"gear_mods": [
				{"mod_id": "missing_mod", "rank": 99},
			],
		}
	) as Dictionary
	_check(int(invalid.get("seed", 0)) > 0, "invalid seed falls back")
	_check(
		not String(invalid.get("character_id", "")).is_empty(),
		"invalid character falls back"
	)
	_check(
		(invalid.get("diagnostics", []) as Array).size() >= 4,
		"invalid config records diagnostics"
	)

	var config: Dictionary = config_manager.call(
		"save_config",
		{
			"seed": 159159,
			"character_id": "character_default",
			"weapon_id": "weapon_basic_blaster",
			"primary_skill_id": "skill_overdrive_rounds",
			"gear_mods": [
				{
					"mod_id": "gear_mod_weapon_damage_test",
					"rank": 2,
				},
			],
		}
	) as Dictionary
	_check(bool(config.get("saved", false)), "developer config saves")
	var preview: Dictionary = config.get(
		"modifier_preview",
		{}
	) as Dictionary
	_check(
		(preview.get("selected", []) as Array).size() == 1,
		"pure Gear Mod preview resolves selection"
	)
	_check(
		int(
			(preview.get("used_drain", {}) as Dictionary).get(
				"weapon",
				0
			)
		) == 4,
		"Gear Mod preview enforces rank drain"
	)
	var constrained_preview: Dictionary = GearModSystem.resolve_preview_loadout(
		[
			{
				"mod_id": "gear_mod_weapon_damage_test",
				"rank": 99,
			},
			{
				"mod_id": "gear_mod_weapon_damage_test",
				"rank": 1,
			},
		],
		8
	)
	var constrained_selected: Array = constrained_preview.get(
		"selected",
		[]
	) as Array
	_check(
		constrained_selected.size() == 1
		and int(
			(constrained_selected[0] as Dictionary).get("rank", -1)
		) == 5
		and (
			constrained_preview.get("diagnostics", []) as Array
		).size() >= 2,
		"Gear Mod preview clamps rank and enforces unique_by_id"
	)

	_verify_setup_panel(initial_setup, config)

	_check(
		bool(
			host.call(
				"debug_start_test_arena_for_smoke",
				config
			)
		),
		"smoke starts debug test arena"
	)
	var arena_ready: bool = await _wait_until(
		func() -> bool:
			var loop: Node = host.call("debug_active_run_loop") as Node
			return (
				loop != null
				and loop.has_method("debug_test_arena_summary")
				and bool(
					(
						loop.call(
							"debug_test_arena_summary"
						) as Dictionary
					).get("active", false)
				)
			),
		180
	)
	_check(arena_ready, "debug test arena becomes ready")
	if not arena_ready:
		_finish()
		return

	var run_loop: Node = host.call("debug_active_run_loop") as Node
	_check(not Replay.is_enabled(), "Replay disabled inside arena")
	_check(not Analytics.is_enabled(), "Analytics disabled inside arena")
	var summary: Dictionary = run_loop.call(
		"debug_test_arena_summary"
	) as Dictionary
	var controller_summary: Dictionary = summary.get(
		"controller",
		{}
	) as Dictionary
	_check(
		bool(controller_summary.get("panel_open", false)),
		"control panel opens on entry"
	)
	_check(
		GameState.is_state(GameState.PAUSED),
		"control panel pauses gameplay"
	)
	_check(
		not bool(controller_summary.get("god_mode", true))
		and not bool(controller_summary.get("free_skills", true)),
		"cheats default off"
	)
	_check(
		is_equal_approx(
			float(summary.get("weapon_damage", 0.0)),
			4.2
		),
		"preview Gear Mod applies to real weapon"
	)

	run_loop.call("debug_test_arena_close_panel")
	_check(
		await _wait_until(
			func() -> bool:
				return GameState.is_state(GameState.PLAYING),
			90
		),
		"closing panel resumes gameplay"
	)

	var controller: Node = run_loop.get_node_or_null(
		"DebugTestArenaController"
	)
	_check(controller != null, "arena controller exists")
	if controller == null:
		_finish()
		return
	var target_spawn: Dictionary = controller.call(
		"spawn_targets",
		"enemy_chaser",
		"stationary",
		1
	) as Dictionary
	var ai_spawn: Dictionary = controller.call(
		"spawn_targets",
		"enemy_chaser",
		"ai",
		1
	) as Dictionary
	_check(
		int(target_spawn.get("spawned", 0)) == 1,
		"stationary target spawns"
	)
	_check(int(ai_spawn.get("spawned", 0)) == 1, "normal AI spawns")
	var stationary: Node2D = _target_by_kind("stationary")
	var ai_target: Node2D = _target_by_kind("ai")
	_check(stationary != null, "stationary target is discoverable")
	_check(ai_target != null, "AI target is discoverable")
	if stationary != null and ai_target != null:
		var stationary_start: Vector2 = stationary.global_position
		var ai_start: Vector2 = ai_target.global_position
		for _frame: int in range(30):
			await get_tree().physics_frame
		_check(
			stationary.global_position.is_equal_approx(
				stationary_start
			),
			"stationary target does not move"
		)
		_check(
			not ai_target.global_position.is_equal_approx(ai_start),
			"normal AI keeps moving"
		)
		_check(
			float(stationary.call("max_life")) >= 1000000.0,
			"stationary target uses high life"
		)
		var attack_life_before: float = float(
			(
				run_loop.call(
					"debug_test_arena_summary"
				) as Dictionary
			).get("player_life", 0.0)
		)
		var ai_attacked: bool = false
		for _attack_frame: int in range(90):
			run_loop.call(
				"debug_set_player_position",
				ai_target.global_position
			)
			await get_tree().physics_frame
			var attack_summary: Dictionary = run_loop.call(
				"debug_test_arena_summary"
			) as Dictionary
			if (
				float(attack_summary.get("player_life", 0.0))
				< attack_life_before
			):
				ai_attacked = true
				break
		_check(
			ai_attacked,
			"normal AI keeps attacking through Combat"
		)
		controller.call("heal_player")
		controller.call("teleport_to_spawn")

	var damage_result: Dictionary = run_loop.call(
		"debug_test_arena_damage_first_target",
		"stationary",
		123.0
	) as Dictionary
	_check(bool(damage_result.get("ok", false)), "real Combat damage applies")
	var damage_stats: Dictionary = controller.call(
		"damage_stats"
	) as Dictionary
	_check(
		int(damage_stats.get("hit_count", 0)) == 1
		and is_equal_approx(
			float(damage_stats.get("total_damage", 0.0)),
			123.0
		),
		"damage HUD records player damage"
	)
	var reset_result: Dictionary = controller.call(
		"reset_stationary_targets"
	) as Dictionary
	_check(
		int(reset_result.get("count", 0)) == 1
		and stationary != null
		and is_equal_approx(
			float(stationary.call("current_life")),
			float(stationary.call("max_life"))
		),
		"stationary target resets manually"
	)

	run_loop.call("debug_test_arena_set_god_mode", true)
	var blocked_damage: Dictionary = run_loop.call(
		"debug_damage_player",
		100.0
	) as Dictionary
	_check(
		not bool(blocked_damage.get("ok", true))
		and String(blocked_damage.get("reason", ""))
		== "debug_invulnerable",
		"god mode blocks Combat damage"
	)
	run_loop.call("debug_test_arena_set_god_mode", false)

	run_loop.call("debug_test_arena_set_free_skills", true)
	var first_cast: Dictionary = run_loop.call(
		"debug_cast_primary_skill"
	) as Dictionary
	var second_cast: Dictionary = run_loop.call(
		"debug_cast_primary_skill"
	) as Dictionary
	_check(
		bool(first_cast.get("ok", false))
		and bool(second_cast.get("ok", false)),
		"free skills bypass cost and cooldown"
	)
	run_loop.call("debug_test_arena_refresh_skills")
	run_loop.call("debug_set_player_position", Vector2(320.0, 160.0))
	run_loop.call("debug_test_arena_teleport_to_spawn")
	summary = run_loop.call("debug_test_arena_summary") as Dictionary
	var player_position: Dictionary = summary.get(
		"player_position",
		{}
	) as Dictionary
	_check(
		is_zero_approx(float(player_position.get("x", 1.0)))
		and is_zero_approx(float(player_position.get("y", 1.0))),
		"teleport returns player to spawn"
	)

	InputService.action_pressed.emit(
		StringName(ACTIONS.PAUSE),
		"player_0"
	)
	_check(
		await _wait_until(
			func() -> bool:
				return GameState.is_state(GameState.PAUSED),
			60
		),
		"pause action panel path freezes gameplay"
	)
	var bullets_before: int = get_tree().get_nodes_in_group(
		"active_bullets"
	).size()
	await get_tree().process_frame
	var bullets_after: int = get_tree().get_nodes_in_group(
		"active_bullets"
	).size()
	_check(
		bullets_before == bullets_after,
		"paused panel does not trigger shooting"
	)
	run_loop.call("debug_test_arena_close_panel")
	await _wait_until(
		func() -> bool:
			return GameState.is_state(GameState.PLAYING),
		60
	)

	var kill_ai_result: Dictionary = controller.call("kill_ai") as Dictionary
	_check(
		int(kill_ai_result.get("count", 0)) == 1,
		"kill AI control uses the real defeat path"
	)
	controller.call("reset_arena")
	summary = run_loop.call("debug_test_arena_summary") as Dictionary
	controller_summary = summary.get("controller", {}) as Dictionary
	var reset_stats: Dictionary = controller_summary.get(
		"damage_stats",
		{}
	) as Dictionary
	_check(
		int(controller_summary.get("stationary_targets", -1)) == 0
		and int(controller_summary.get("ai_targets", -1)) == 0
		and int(reset_stats.get("hit_count", -1)) == 0
		and not bool(controller_summary.get("god_mode", true))
		and not bool(controller_summary.get("free_skills", true)),
		"reset arena clears targets stats and cheats"
	)
	var bulk_spawn: Dictionary = controller.call(
		"spawn_targets",
		"enemy_chaser",
		"stationary",
		50
	) as Dictionary
	var stationary_zone: Rect2 = Rect2(
		Vector2(-1480.0, -700.0),
		Vector2(1000.0, 1400.0)
	)
	var bulk_inside_zone: bool = true
	var bulk_target_count: int = 0
	for bulk_target: Node in get_tree().get_nodes_in_group(
		"active_enemies"
	):
		if (
			not bulk_target is Node2D
			or not bulk_target.has_meta(
				"debug_test_arena_kind"
			)
			or String(
				bulk_target.get_meta(
					"debug_test_arena_kind"
				)
			) != "stationary"
		):
			continue
		bulk_target_count += 1
		if not stationary_zone.has_point(
			(bulk_target as Node2D).global_position
		):
			bulk_inside_zone = false
	_check(
		int(bulk_spawn.get("spawned", 0)) == 50
		and bulk_target_count == 50
		and bulk_inside_zone,
		"count 50 spawns deterministically inside its zone"
	)
	controller.call("clear_targets", "stationary")
	controller.call(
		"spawn_targets",
		"enemy_chaser",
		"stationary",
		1
	)
	controller.call(
		"spawn_targets",
		"enemy_chaser",
		"ai",
		1
	)
	run_loop.call("debug_test_arena_set_free_skills", true)
	var death_result: Dictionary = run_loop.call(
		"debug_kill_player"
	) as Dictionary
	_check(
		bool(
			(death_result.get("combat_result", {}) as Dictionary).get(
				"defeated",
				false
			)
		),
		"player death uses real Combat path"
	)
	_check(
		await _wait_until(
			func() -> bool:
				var current: Dictionary = run_loop.call(
					"debug_test_arena_summary"
				) as Dictionary
				return (
					GameState.is_state(GameState.PAUSED)
					and bool(
						(
							current.get(
								"controller",
								{}
							) as Dictionary
						).get("panel_open", false)
					)
				),
			120
		),
		"player death resets and reopens panel"
	)
	summary = run_loop.call("debug_test_arena_summary") as Dictionary
	controller_summary = summary.get("controller", {}) as Dictionary
	_check(
		is_equal_approx(
			float(summary.get("player_life", 0.0)),
			float(summary.get("player_max_life", -1.0))
		),
		"player death restores full life"
	)
	_check(
		int(controller_summary.get("stationary_targets", -1)) == 0
		and int(controller_summary.get("ai_targets", -1)) == 0,
		"player death clears arena targets"
	)
	_check(
		not bool(controller_summary.get("god_mode", true))
		and not bool(controller_summary.get("free_skills", true))
		and not bool(
			(
				summary.get("skills", {}) as Dictionary
			).get("debug_free_casts", true)
		),
		"player death clears temporary cheat state"
	)

	var first_run_instance_id: int = run_loop.get_instance_id()
	run_loop.call("debug_test_arena_request_setup")
	_check(
		await _wait_until(
			func() -> bool:
				return (
					host.call("debug_active_run_loop") == null
					and host.call("debug_active_setup") != null
				),
			120
		),
		"return to loadout clears the current arena"
	)
	await get_tree().process_frame
	var returned_setup: CanvasLayer = host.call(
		"debug_active_setup"
	) as CanvasLayer
	_check(
		returned_setup != null and UIManager.top() == returned_setup,
		"return to loadout opens the standalone setup"
	)
	_check(
		not Replay.is_enabled() and not Analytics.is_enabled(),
		"services remain suspended while changing loadout"
	)
	_check(
		bool(
			host.call(
				"debug_start_test_arena_for_smoke",
				config
			)
		),
		"loadout can rebuild the arena"
	)
	_check(
		await _wait_until(
			func() -> bool:
				var rebuilt: Node = host.call(
					"debug_active_run_loop"
				) as Node
				return (
					rebuilt != null
					and rebuilt.get_instance_id()
					!= first_run_instance_id
					and bool(
						(
							rebuilt.call(
								"debug_test_arena_summary"
							) as Dictionary
						).get("active", false)
					)
				),
			180
		),
		"return to loadout creates a fresh runtime"
	)
	var rebuilt_run_loop: Node = host.call(
		"debug_active_run_loop"
	) as Node
	if rebuilt_run_loop == null:
		_finish()
		return
	rebuilt_run_loop.call("debug_test_arena_request_exit")
	_check(
		await _wait_until(
			func() -> bool:
				return (
					host.call("debug_active_run_loop") == null
					and bool(
						host.call("debug_exit_is_completed")
					)
				),
			120
		),
		"exit test clears the standalone runtime"
	)
	_check(
		UIManager.top() == null,
		"standalone exit clears the UI stack"
	)
	_check(
		Replay.is_enabled() == replay_enabled_before,
		"Replay state restores after standalone exit"
	)
	_check(
		Analytics.is_enabled() == analytics_enabled_before,
		"Analytics state restores after standalone exit"
	)
	_check(
		SaveManager.load(
			SaveManager.DEFAULT_SLOT,
			SAVE_KINDS.META
		) == SENTINEL_META,
		"formal meta sentinel remains unchanged"
	)
	_check(
		SaveManager.load(
			SaveManager.DEFAULT_SLOT,
			SAVE_KINDS.RUN
		) == SENTINEL_RUN,
		"formal run sentinel remains unchanged"
	)
	_finish()


func _verify_setup_panel(
	setup: CanvasLayer,
	config: Dictionary
) -> void:
	_check(setup != null, "standalone setup is available")
	if setup == null:
		return
	setup.call("configure", config)
	var summary: Dictionary = setup.call("debug_summary") as Dictionary
	_check(
		int(summary.get("character_options", 0)) >= 1
		and int(summary.get("weapon_options", 0)) >= 1
		and int(summary.get("skill_options", 0)) >= 1,
		"setup panel lists runtime content"
	)
	_check(
		bool(summary.get("relics_disabled", false))
		and bool(summary.get("active_items_disabled", false))
		and bool(summary.get("consumables_disabled", false)),
		"data-only content remains visibly disabled"
	)


func _target_by_kind(target_kind: String) -> Node2D:
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			enemy is Node2D
			and enemy.has_meta("debug_test_arena_kind")
			and String(enemy.get_meta("debug_test_arena_kind"))
			== target_kind
		):
			return enemy as Node2D
	return null


func _wait_until(condition: Callable, frame_limit: int) -> bool:
	for _frame: int in range(frame_limit):
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return bool(condition.call())


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[DebugTestArenaSmoke] PASS: %s" % label)
		return
	_failures.append(label)
	push_error("[DebugTestArenaSmoke] FAIL: %s" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("DEBUG TEST ARENA ALL PASS")
		get_tree().quit(0)
		return
	print(
		"[DebugTestArenaSmoke] failed checks: %s"
		% ", ".join(_failures)
	)
	get_tree().quit(1)
