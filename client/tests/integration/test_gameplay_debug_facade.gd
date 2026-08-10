extends SmokeHarness


const GOLD_TRANSACTION_REASONS := preload(
	"res://scripts/contracts/gold_transaction_reasons.gd"
)
const REWARD_CHOICE_TRIGGERS := preload(
	"res://scripts/contracts/reward_choice_triggers.gd"
)
const GAMEPLAY_RUN_LOOP_SCENE: PackedScene = preload(
	"res://scenes/gameplay/gameplay_run_loop.tscn"
)


func test_run_loop_wrappers_wire_current_runtime_state() -> void:
	var replay_was_enabled: bool = Replay.is_enabled()
	Replay.set_enabled(false)
	UIManager.clear(true)
	GameState.change_state(GameState.MAIN_MENU)

	var run_loop: GameplayRunLoop = (
		GAMEPLAY_RUN_LOOP_SCENE.instantiate() as GameplayRunLoop
	)
	assert_not_null(run_loop)
	if run_loop == null:
		Replay.set_enabled(replay_was_enabled)
		return
	run_loop.debug_enable_open_warzone()
	run_loop.configure_content_progress_commits_enabled(false)
	add_child_autofree(run_loop)
	run_loop.process_mode = Node.PROCESS_MODE_DISABLED

	var initial_summary: Dictionary = run_loop.debug_summary()
	assert_gt(float(initial_summary.get("player_max_life", 0.0)), 0.0)
	var initial_enemy_count: int = int(
		initial_summary.get("active_enemies", -1)
	)
	GameClock.restore_snapshot({
		"elapsed": 321.25,
		"tick": 19,
		"time_scale": 1.0,
	})
	assert_eq(
		run_loop.debug_spawn_enemy("enemy_chaser"),
		{"ok": true, "reason": "", "spawned": 1}
	)
	var first_snapshot: Dictionary = run_loop.create_run_snapshot()
	var first_spawn_states: Dictionary = first_snapshot.get(
		"spawn_states",
		{}
	) as Dictionary
	var first_debug_state: Dictionary = first_spawn_states.get(
		"debug_enemy_chaser",
		{}
	) as Dictionary
	assert_eq(first_debug_state.get("spawned"), 1)
	assert_eq(first_debug_state.get("alive"), 1)
	assert_almost_eq(
		float(first_debug_state.get("next_time", -1.0)),
		321.25,
		0.0001
	)

	var current_summary: Dictionary = run_loop.debug_summary()
	assert_eq(
		int(current_summary.get("active_enemies", -1)),
		initial_enemy_count + 1
	)
	assert_eq(
		current_summary.get("difficulty"),
		run_loop.debug_difficulty_snapshot()
	)

	var damage_capture := DamageSignalCapture.new()
	var damage_callback := Callable(damage_capture, "on_damage_applied")
	Combat.damage_applied.connect(damage_callback)
	var life_before_damage: float = float(
		run_loop.debug_summary().get("player_life", 0.0)
	)
	var damage_result: Dictionary = run_loop.debug_damage_player(1.0)
	assert_true(bool(damage_result.get("ok", false)))
	assert_eq(damage_capture.call_count, 1)
	assert_lt(
		float(run_loop.debug_summary().get("player_life", 0.0)),
		life_before_damage
	)
	assert_same(damage_capture.info.get("target"), damage_capture.target)
	assert_same(damage_capture.info.get("source"), run_loop)
	Combat.damage_applied.disconnect(damage_callback)

	run_loop.queue_free()
	UIManager.clear(true)
	GameState.change_state(GameState.MAIN_MENU)
	Replay.set_enabled(replay_was_enabled)
	await get_tree().process_frame
	PoolManager.clear_all()
	GUIDEInputFormatter.cleanup()
	await get_tree().process_frame
	await get_tree().process_frame


func test_invalid_parameters_are_rejected_without_side_effects() -> void:
	var facade := GameplayDebugFacade.new()
	var context := GameplayDebugFacade.ActiveRunContext.new()

	assert_eq(
		facade.spawn_enemy(context, "enemy_missing"),
		{"ok": false, "reason": "run_not_ready"}
	)
	context.active_world = Node2D.new()
	context.player = Node2D.new()
	assert_eq(
		facade.spawn_enemy(context, "enemy_missing"),
		{"ok": false, "reason": "unknown_enemy"}
	)
	assert_eq(
		facade.damage_player(context, 0.0),
		{"ok": false, "reason": "non_positive_amount"}
	)
	assert_eq(
		facade.heal_player(context, 10.0),
		{"ok": false, "reason": "player_unavailable"}
	)
	assert_eq(
		facade.set_player_hp(context, 10.0),
		{"ok": false, "reason": "player_unavailable"}
	)
	assert_eq(
		facade.cast_primary_skill(context),
		{"ok": false, "reason": "skill_system_unavailable"}
	)

	context.player.free()
	context.active_world.free()


func test_spawn_clamps_count_updates_successes_and_uses_current_context() -> void:
	var facade := GameplayDebugFacade.new()
	var context := GameplayDebugFacade.ActiveRunContext.new()
	var ports := SpawnPorts.new()
	context.active_world = Node2D.new()
	context.player = Node2D.new()
	context.enemy_rows = {"enemy_alpha": {}}
	context.spawn_states = {
		"debug_enemy_alpha": {
			"next_time": 1.0,
			"spawned": 5,
			"alive": 2,
		},
	}
	context.max_spawn_count = 96
	context.now = Callable(ports, "now")
	context.spawn_enemy = Callable(ports, "spawn_enemy")
	ports.now_values = [12.0, 13.0]
	ports.spawn_results = [true, false, true]

	var result: Dictionary = facade.spawn_enemy(
		context,
		"enemy_alpha",
		999
	)

	assert_eq(result, {"ok": true, "reason": "", "spawned": 2})
	assert_eq(ports.spawn_specs.size(), 96)
	assert_eq(ports.wave_keys.size(), 96)
	for spec: Dictionary in ports.spawn_specs:
		assert_eq(spec, {"enemy_id": "enemy_alpha"})
	for wave_key: String in ports.wave_keys:
		assert_eq(wave_key, "debug_enemy_alpha")
	assert_eq(ports.now_call_count, 2)
	assert_eq(context.spawn_states.get("debug_enemy_alpha"), {
		"next_time": 13.0,
		"spawned": 7,
		"alive": 4,
	})

	# Replacing the borrowed dictionaries between calls must take effect
	# immediately; the facade never keeps a prior smoke/runtime dictionary.
	context.enemy_rows = {"enemy_beta": {}}
	context.spawn_states = {}
	ports.now_values = [20.0, 21.0]
	ports.spawn_results = [true]
	ports.spawn_specs.clear()
	ports.wave_keys.clear()
	ports.now_call_count = 0
	result = facade.spawn_enemy(context, "enemy_beta", 0)
	assert_eq(result, {"ok": true, "reason": "", "spawned": 1})
	assert_true(context.spawn_states.has("debug_enemy_beta"))
	assert_false(context.spawn_states.has("debug_enemy_alpha"))
	assert_eq(ports.spawn_specs.size(), 1)
	assert_eq(ports.now_call_count, 2)

	context.player.free()
	context.active_world.free()


func test_standard_delegates_preserve_contract_arguments_and_position() -> void:
	var facade := GameplayDebugFacade.new()
	var context := GameplayDebugFacade.ActiveRunContext.new()
	var ports := StandardPorts.new()
	var player := FakeDebugPlayer.new()
	var skill_system := FakeSkillSystem.new()
	context.player = player
	context.skill_system = skill_system
	context.add_gold = Callable(ports, "add_gold")
	context.request_reward_choice = Callable(
		ports,
		"request_reward_choice"
	)

	assert_eq(
		facade.request_reward_choice(context, 5, "pool_debug"),
		{"ok": true, "choices": []}
	)
	assert_eq(ports.reward_pool_id, "pool_debug")
	assert_eq(
		ports.reward_trigger_id,
		REWARD_CHOICE_TRIGGERS.DEBUG_COMMAND
	)
	assert_eq(ports.reward_candidate_count, 5)

	assert_eq(
		facade.give_gold(context, 42),
		{"ok": true, "amount": 42}
	)
	assert_eq(ports.gold_amount, 42)
	assert_eq(
		ports.gold_reason_id,
		GOLD_TRANSACTION_REASONS.DEBUG_COMMAND
	)

	assert_eq(
		facade.heal_player(context, 8.0),
		{"life": 100.0, "ok": true}
	)
	assert_eq(
		facade.set_player_hp(context, 35.0),
		{"life": 35.0, "ok": true}
	)
	facade.set_player_position(context, Vector2(300.0, -120.0))
	assert_eq(player.global_position, Vector2(300.0, -120.0))
	assert_eq(
		facade.cast_primary_skill(context),
		{"ok": true, "slot": "primary"}
	)

	skill_system.free()
	player.free()


func test_damage_info_is_created_by_port_with_runloop_owner_source() -> void:
	var facade := GameplayDebugFacade.new()
	var context := GameplayDebugFacade.ActiveRunContext.new()
	var owner := Node.new()
	var player := FakeDebugPlayer.new()
	var ports := DamagePorts.new()
	ports.owner = owner
	context.owner = owner
	context.player = player
	context.make_damage_info = Callable(ports, "make_damage_info")

	var result: Dictionary = facade.damage_player(context, 25.0)

	assert_true(bool(result.get("ok", false)))
	assert_eq(float(result.get("life", 0.0)), 75.0)
	assert_eq(float(result.get("max_life", 0.0)), 100.0)
	assert_eq(ports.last_amount, 25.0)
	assert_same(ports.last_target, player)
	assert_same(player.last_damage_info.get("source"), owner)
	assert_same(player.last_damage_info.get("target"), player)
	assert_eq(player.clear_invulnerability_calls, 1)

	player.life = 100.0
	result = facade.kill_player(context)
	assert_true(bool(result.get("ok", false)))
	assert_eq(player.life, 0.0)
	assert_eq(player.shield, 0.0)
	assert_eq(player.overshield, 0.0)
	assert_eq(ports.last_amount, 1_000.0)
	assert_eq(player.clear_invulnerability_calls, 3)

	player.free()
	owner.free()


func test_kill_and_clear_only_touch_active_world_enemies() -> void:
	var facade := GameplayDebugFacade.new()
	var context := GameplayDebugFacade.ActiveRunContext.new()
	var active_world := Node2D.new()
	var active_enemy := FakeDamageTarget.new()
	var outside_enemy := FakeDamageTarget.new()
	var owner := Node.new()
	var ports := WorldPorts.new()
	ports.active_world = active_world
	ports.owner = owner
	add_child_autofree(active_world)
	active_world.add_child(active_enemy)
	add_child_autofree(outside_enemy)
	active_enemy.add_to_group("active_enemies")
	outside_enemy.add_to_group("active_enemies")
	context.owner = owner
	context.tree = get_tree()
	context.active_world = active_world
	context.spawn_states = {
		"debug_enemy_alpha": {"alive": 4},
		"wave_regular": {"alive": 7},
	}
	context.make_damage_info = Callable(ports, "make_damage_info")
	context.is_active_world_entity = Callable(
		ports,
		"is_active_world_entity"
	)
	context.release_entity = Callable(ports, "release_entity")

	assert_eq(
		facade.kill_enemies(context),
		{"ok": true, "count": 1}
	)
	assert_eq(active_enemy.damage_calls, 1)
	assert_eq(outside_enemy.damage_calls, 0)
	assert_same(active_enemy.last_damage_info.get("source"), owner)

	assert_eq(
		facade.clear_enemies(context),
		{"ok": true, "count": 1}
	)
	assert_eq(ports.released_entities, [active_enemy])
	assert_eq(
		int((context.spawn_states["debug_enemy_alpha"] as Dictionary).get(
			"alive",
			-1
		)),
		0
	)
	assert_eq(
		int((context.spawn_states["wave_regular"] as Dictionary).get(
			"alive",
			-1
		)),
		7
	)

	owner.free()


func test_summary_preserves_key_order_and_deep_copy_boundaries() -> void:
	var facade := GameplayDebugFacade.new()
	var state := GameplayDebugFacade.SummaryState.new()
	state.level = 3
	state.gold_balance = 40
	state.gold_earned_total = 140
	state.level_gold = 20
	state.level_gold_required = 169
	state.reward_choice_active = true
	state.kills = 9
	state.main_hero_id = "hero_main"
	state.sub_hero_id = "hero_sub"
	state.composition_name = "Main + Sub"
	state.composition_palette = {"nested": {"tone": "blue"}}
	state.passive_id = "passive_main"
	state.player_life = 75.0
	state.player_max_life = 100.0
	state.player_shield = 4.0
	state.player_max_shield = 10.0
	state.player_overshield = 8.0
	state.active_enemies = 2
	state.active_hazards = 1
	state.interest_points = {"poi": {"claimed": false}}
	state.gear_mods = {"mod_ids": ["gear_mod_a"]}
	state.difficulty = {"level": 4}
	state.map = {"hazards": ["hazard_a"]}
	state.module_world = {"current": "1,2"}
	state.skills = {"cooldowns": {"slot_1": 1.0}}
	state.warzone_director = {"phase_id": "phase_a"}

	var summary: Dictionary = facade.summary(state)
	assert_eq(summary.keys(), [
		"level",
		"gold_balance",
		"gold_earned_total",
		"level_gold",
		"level_gold_required",
		"reward_choice_active",
		"kills",
		"hero_composition",
		"player_life",
		"player_max_life",
		"player_shield",
		"player_max_shield",
		"player_overshield",
		"active_enemies",
		"active_hazards",
		"interest_points",
		"gear_mods",
		"difficulty",
		"map",
		"module_world",
		"skills",
		"warzone_director",
	])
	assert_eq(summary.get("hero_composition"), {
		"main_hero_id": "hero_main",
		"sub_hero_id": "hero_sub",
		"name": "Main + Sub",
		"palette": {"nested": {"tone": "blue"}},
		"passive_id": "passive_main",
	})
	((summary["hero_composition"] as Dictionary)["palette"] as Dictionary)[
		"nested"
	]["tone"] = "changed"
	(summary["interest_points"] as Dictionary)["poi"]["claimed"] = true
	(summary["gear_mods"] as Dictionary)["mod_ids"].append("gear_mod_b")
	assert_eq(state.composition_palette, {"nested": {"tone": "blue"}})
	assert_eq(state.interest_points, {"poi": {"claimed": false}})
	assert_eq(state.gear_mods, {"mod_ids": ["gear_mod_a"]})

	var difficulty: Dictionary = facade.difficulty_snapshot(state.difficulty)
	difficulty["level"] = 99
	assert_eq(state.difficulty, {"level": 4})


class SpawnPorts:
	extends RefCounted

	var now_values: Array[float] = []
	var spawn_results: Array[bool] = []
	var spawn_specs: Array[Dictionary] = []
	var wave_keys: Array[String] = []
	var now_call_count: int = 0


	func now() -> float:
		var value: float = now_values[now_call_count]
		now_call_count += 1
		return value


	func spawn_enemy(spec: Dictionary, wave_key: String) -> bool:
		spawn_specs.append(spec.duplicate(true))
		wave_keys.append(wave_key)
		if spawn_results.is_empty():
			return false
		return spawn_results.pop_front()


class StandardPorts:
	extends RefCounted

	var gold_amount: int = 0
	var gold_reason_id: String = ""
	var reward_pool_id: String = ""
	var reward_trigger_id: String = ""
	var reward_candidate_count: int = 0


	func add_gold(amount: int, reason_id: String) -> Dictionary:
		gold_amount = amount
		gold_reason_id = reason_id
		return {"ok": true, "amount": amount}


	func request_reward_choice(
		pool_id: String,
		trigger_id: String,
		candidate_count: int
	) -> Dictionary:
		reward_pool_id = pool_id
		reward_trigger_id = trigger_id
		reward_candidate_count = candidate_count
		return {"ok": true, "choices": []}


class DamagePorts:
	extends RefCounted

	const ELEMENTS := preload("res://scripts/contracts/elements.gd")

	var owner: Node = null
	var last_amount: float = 0.0
	var last_target: Node = null


	func make_damage_info(amount: float, target: Node) -> RefCounted:
		last_amount = amount
		last_target = target
		return DamageInfo.new().setup(
			amount,
			ELEMENTS.ELEMENT_NEUTRAL,
			owner,
			target,
			"team_debug",
			"team_target"
		)


class WorldPorts:
	extends DamagePorts

	var active_world: Node2D = null
	var released_entities: Array[Node] = []


	func is_active_world_entity(entity: Node) -> bool:
		return (
			entity == active_world
			or active_world.is_ancestor_of(entity)
		)


	func release_entity(entity: Node) -> bool:
		released_entities.append(entity)
		return true


class FakeDebugPlayer:
	extends Node2D

	var life: float = 100.0
	var maximum_life: float = 100.0
	var shield: float = 10.0
	var overshield: float = 5.0
	var clear_invulnerability_calls: int = 0
	var last_damage_info: RefCounted = null


	func debug_heal(amount: float) -> Dictionary:
		life = minf(life + maxf(amount, 0.0), maximum_life)
		return {"life": life}


	func debug_set_life(amount: float) -> Dictionary:
		life = clampf(amount, 0.0, maximum_life)
		return {"life": life}


	func debug_set_shield(next_shield: float, next_overshield: float) -> void:
		shield = next_shield
		overshield = next_overshield


	func debug_clear_invulnerability() -> void:
		clear_invulnerability_calls += 1


	func current_life() -> float:
		return life


	func max_life() -> float:
		return maximum_life


	func receive_damage(info: RefCounted) -> Dictionary:
		last_damage_info = info
		var amount: float = float(info.get("amount"))
		life = maxf(life - amount, 0.0)
		return {
			"applied": true,
			"amount": amount,
			"defeated": life <= 0.0,
			"reason": "applied",
		}


class FakeDamageTarget:
	extends Node2D

	var damage_calls: int = 0
	var last_damage_info: RefCounted = null


	func receive_damage(info: RefCounted) -> Dictionary:
		damage_calls += 1
		last_damage_info = info
		return {
			"applied": true,
			"amount": float(info.get("amount")),
			"defeated": true,
			"reason": "applied",
		}


class FakeSkillSystem:
	extends Node


	func cast_primary_skill() -> Dictionary:
		return {"ok": true, "slot": "primary"}


class DamageSignalCapture:
	extends RefCounted

	var call_count: int = 0
	var target: Node = null
	var info: RefCounted = null


	func on_damage_applied(
		damage_target: Node,
		damage_info: RefCounted,
		_result: Dictionary
	) -> void:
		call_count += 1
		target = damage_target
		info = damage_info
