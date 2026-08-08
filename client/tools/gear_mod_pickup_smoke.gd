extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const GEAR_MOD_PLACEMENT_OUTCOMES := preload(
	"res://scripts/contracts/gear_mod_placement_outcomes.gd"
)
const PICKUP_SCENE := preload(
	"res://scenes/gameplay/gear_mod_pickup.tscn"
)
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const WORLD_EVENT_IDS := preload(
	"res://scripts/contracts/world_event_ids.gd"
)
const WORLD_EVENT_KINDS := preload(
	"res://scripts/contracts/world_event_kinds.gd"
)
const WORLD_EVENT_REWARD_TYPES := preload(
	"res://scripts/contracts/world_event_reward_types.gd"
)

const BOOT_FRAMES: int = 10
const CPU_SVG_PATH: String = (
	"res://assets/icons/gear_mod_pickup_cpu.svg"
)
const PICKUP_GROUP: String = "active_gear_mod_pickups"
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

var _failures: Array[String] = []
var _last_placement_failure: Dictionary = {}
var _last_placement_result: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var run_loop: Node = null
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		run_loop = _find_node_by_name(
			get_tree().root,
			"GameplayRunLoop"
		)
		if run_loop != null:
			break
	_expect(run_loop != null, "formal gameplay run should be ready")
	if run_loop == null:
		_finish()
		return
	var player: Node2D = _find_node_by_name(
		run_loop,
		"Player"
	) as Node2D
	var hud: Node = _find_node_by_name(run_loop, "GameplayHud")
	_expect(player != null, "player should exist for pickup interaction")
	_expect(hud != null, "HUD should exist for pickup prompt")
	if player == null:
		_finish()
		return
	if run_loop.has_signal("gear_mod_placement_failed"):
		run_loop.connect(
			"gear_mod_placement_failed",
			_on_gear_mod_placement_failed
		)
	if run_loop.has_signal("gear_mod_placement_resolved"):
		run_loop.connect(
			"gear_mod_placement_resolved",
			_on_gear_mod_placement_resolved
		)

	_expect_asset_contract()
	_expect_scene_contract()
	_expect_fixed_modifier_contract()
	_expect_logical_cap_contract(run_loop)
	await _expect_interaction_contract(run_loop, player, hud)
	_expect_world_event_spawn_contract(run_loop)
	_expect_snapshot_validation_contract(run_loop)
	_release_active_pickups(run_loop)
	await _expect_full_death_replay_contract()
	_finish()


func _expect_asset_contract() -> void:
	var svg_text: String = FileAccess.get_file_as_string(CPU_SVG_PATH)
	_expect(not svg_text.is_empty(), "formal CPU SVG should be readable")
	_expect(
		svg_text.count("<path ") == 1
		and svg_text.contains("transform=\"translate(0.000000,800.000000) scale(0.100000,-0.100000)\"")
		and svg_text.contains("z\"/>")
		and not svg_text.to_lower().contains("rdf"),
		"formal CPU SVG should keep one closed transformed path without RDF metadata"
	)


func _expect_scene_contract() -> void:
	var pickup: GearModPickup = PICKUP_SCENE.instantiate() as GearModPickup
	_expect(pickup != null, "formal Gear Mod pickup scene should instantiate")
	if pickup == null:
		return
	add_child(pickup)
	var visual: Node2D = pickup.get_node_or_null("Visual") as Node2D
	var icon: Sprite2D = pickup.get_node_or_null(
		"Visual/Icon"
	) as Sprite2D
	_expect(visual != null and icon != null, "pickup should keep one visual-only child hierarchy")
	_expect(
		_find_collision_object(pickup) == null,
		"pickup should not contain physics collision or auto-pickup areas"
	)
	if icon != null:
		_expect(
			is_equal_approx(icon.scale.x, 0.084)
			and is_equal_approx(icon.scale.y, 0.084),
			"CPU icon scale should target the formal 40 px presentation"
		)
		var material: ShaderMaterial = icon.material as ShaderMaterial
		_expect(material != null, "CPU icon should use its dedicated ShaderMaterial")
		if material != null:
			var shader_path: String = material.shader.resource_path
			var outline_color: Color = material.get_shader_parameter(
				"outline_color"
			) as Color
			_expect(
				shader_path == "res://shaders/gear_mod_pickup_star_window.gdshader"
				and is_equal_approx(float(material.get_shader_parameter("star_scale")), 1.8)
				and is_equal_approx(float(material.get_shader_parameter("outline_texels")), 23.8)
				and outline_color.is_equal_approx(Color("68bcdd")),
				"CPU icon should use the fixed-space star window and 2 px cyan rim contract"
			)
	var root_position: Vector2 = pickup.position
	var topology_count: int = _descendant_count(pickup)
	_expect(
		pickup.configure(
			1,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			GearModSystem.pickup_config()
		),
		"pickup should accept a known unlocked Mod configuration"
	)
	_expect(
		pickup.gear_mod_instance_id() == 1
		and int(pickup.snapshot().get("instance_id", 0)) == 1,
		"pickup should retain its monotonic logical instance id"
	)
	await get_tree().process_frame
	_expect(
		pickup.position == root_position
		and visual != null
		and not visual.position.is_zero_approx(),
		"hover animation should move only the visual child"
	)
	pickup.call("_pool_release")
	pickup.call("_pool_reset")
	_expect(
		_descendant_count(pickup) == topology_count,
		"pool reset and release should not grow pickup topology"
	)
	pickup.queue_free()


func _expect_logical_cap_contract(run_loop: Node) -> void:
	_expect(
		bool(run_loop.call(
			"_ground_gear_mod_pickup_can_grow",
			65535
		)),
		"the 65536th ground Gear Mod instance should remain spawnable"
	)
	_expect(
		not bool(run_loop.call(
			"_ground_gear_mod_pickup_can_grow",
			65536
		)),
		"the 65537th ground Gear Mod instance should be rejected without preallocating nodes"
	)


func _expect_fixed_modifier_contract() -> void:
	var modifiers: Array[Dictionary] = GearModSystem.modifiers(
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
	)
	_expect(
		modifiers.size() == 1
		and is_equal_approx(
			float(modifiers[0].get("value", 0.0)),
			1.2
		),
		"fixed Mod query should expose the full +20% damage effect"
	)
	_expect(
		GearModSystem.pickup_config().get("pool_id", "")
		== POOL_IDS.GEAR_MOD_PICKUP,
		"Gear Mod pickup config should reference the registered pool"
	)


func _expect_interaction_contract(
	run_loop: Node,
	player: Node2D,
	hud: Node
) -> void:
	_release_active_pickups(run_loop)
	var start_mod_ids: Array[String] = _run_mod_ids(run_loop)
	var far_position: Vector2 = player.global_position + Vector2(100.0, 0.0)
	var spawn_result: Dictionary = run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		far_position
	) as Dictionary
	_expect(bool(spawn_result.get("ok", false)), "debug setup should spawn a Gear Mod pickup")
	_expect(_active_pickup_count(run_loop) == 1, "spawned pickup should remain active")
	await _push_action_once(ACTIONS.INTERACT)
	_expect(
		_active_pickup_count(run_loop) == 1
		and _run_mod_ids(run_loop) == start_mod_ids,
		"out-of-range interact should not consume or grant a pickup"
	)
	var pickup: GearModPickup = _first_active_pickup(run_loop)
	if pickup == null:
		return
	player.global_position = pickup.global_position
	for _index: int in range(3):
		await get_tree().process_frame
	_expect(
		_active_pickup_count(run_loop) == 1
		and _run_mod_ids(run_loop) == start_mod_ids,
		"standing on a pickup should never collect it automatically"
	)
	run_loop.call("_update_gear_mod_pickup_prompt", pickup)
	var prompt_text: String = _interaction_prompt_text(hud)
	_expect(
		prompt_text.contains(tr("gear_mod_weapon_damage_test_name"))
		and prompt_text.contains("+20%"),
		"pickup prompt should show the Mod name and full fixed signed effect: %s"
		% prompt_text
	)
	var first_pickup_result: bool = bool(run_loop.call(
		"_try_interact_gear_mod_pickup",
		pickup
	))
	var first_pending: Dictionary = run_loop.call(
		"debug_pending_gear_mod_placement"
	) as Dictionary
	_expect(
		first_pickup_result
		and _active_pickup_count(run_loop) == 1
		and _run_mod_ids(run_loop) == start_mod_ids
		and int(first_pending.get("instance_id", 0))
		== pickup.gear_mod_instance_id(),
		"interact should open one uncommitted placement and keep the pickup"
	)
	player.global_position += Vector2(200.0, 0.0)
	_last_placement_result.clear()
	var first_instance_id: int = int(first_pending.get("instance_id", 0))
	await _inject_physical_key_once(KEY_ENTER)
	var first_place_result: Dictionary = _last_placement_result.duplicate(true)
	var recorded_after_live_placement: Dictionary = Replay.snapshot()
	var first_mod_ids: Array[String] = _run_mod_ids(run_loop)
	_expect(
		bool(first_place_result.get("ok", false))
		and _active_pickup_count(run_loop) == 0
		and first_mod_ids.size() == start_mod_ids.size() + 1
		and _mod_id_count(
			first_mod_ids,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		) == _mod_id_count(
			start_mod_ids,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		) + 1,
		"placement confirm should consume the reserved pickup after knockback moves the player out of interaction range"
	)
	_expect(
		Replay.is_recording()
		and not _recording_has_input_press(
			recorded_after_live_placement,
			ACTIONS.UI_CONFIRM
		)
		and _recording_has_placement_decision(
			recorded_after_live_placement,
			first_instance_id,
			GEAR_MOD_PLACEMENT_OUTCOMES.PLACED
		),
		"a real pending UI confirm should record only its semantic placement decision, not a duplicate raw press"
	)

	var origin: Vector2 = player.global_position
	var mod_ids_before_nearest: Array[String] = _run_mod_ids(run_loop)
	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER,
		origin + Vector2(10.0, 0.0)
	)
	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
		origin + Vector2(20.0, 0.0)
	)
	var nearest_candidate: Dictionary = run_loop.call(
		"_nearest_gear_mod_pickup_candidate"
	) as Dictionary
	var nearest_pickup: GearModPickup = nearest_candidate.get(
		"pickup"
	) as GearModPickup
	if nearest_pickup != null:
		run_loop.call("_try_interact_gear_mod_pickup", nearest_pickup)
		_confirm_pending_first_legal(run_loop)
	var nearest_mod_ids: Array[String] = _run_mod_ids(run_loop)
	_expect(
		_active_pickup_count(run_loop) == 1
		and _mod_id_count(
			nearest_mod_ids,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER
		) == _mod_id_count(
			mod_ids_before_nearest,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER
		) + 1
		and _mod_id_count(
			nearest_mod_ids,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER
		) == _mod_id_count(
			mod_ids_before_nearest,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER
		),
		"one placement transaction should collect only the nearest of multiple pickups"
	)
	var cancelled_pickup: GearModPickup = _first_active_pickup(run_loop)
	var mod_ids_before_cancel: Array[String] = _run_mod_ids(run_loop)
	if cancelled_pickup != null:
		run_loop.call("_try_interact_gear_mod_pickup", cancelled_pickup)
	var cancelled_pending: Dictionary = run_loop.call(
		"debug_pending_gear_mod_placement"
	) as Dictionary
	var cancel_result: Dictionary = {}
	if not cancelled_pending.is_empty():
		InputService.set_playback_active(true)
		cancel_result = run_loop.call(
			"apply_replay_gear_mod_placement",
			{
				"instance_id": int(cancelled_pending.get("instance_id", 0)),
				"mod_id": String(cancelled_pending.get("mod_id", "")),
				"outcome": GEAR_MOD_PLACEMENT_OUTCOMES.CANCELLED,
			}
		) as Dictionary
		InputService.set_playback_active(false)
	_expect(
		bool(cancel_result.get("ok", false))
		and _active_pickup_count(run_loop) == 1
		and _run_mod_ids(run_loop) == mod_ids_before_cancel
		and (run_loop.call("debug_pending_gear_mod_placement") as Dictionary).is_empty(),
		"semantic replay cancellation should leave the pickup entity and board placements unchanged"
	)
	var auto_cancel_pickup: GearModPickup = _first_active_pickup(run_loop)
	if auto_cancel_pickup != null:
		run_loop.call("_try_interact_gear_mod_pickup", auto_cancel_pickup)
	var auto_cancel_pending: Dictionary = run_loop.call(
		"debug_pending_gear_mod_placement"
	) as Dictionary
	var auto_cancel_mod_ids: Array[String] = _run_mod_ids(run_loop)
	_expect(
		not auto_cancel_pending.is_empty(),
		"setup should create a pending placement before leaving PLAYING"
	)
	GameState.change_state(GameState.RESULT, {
		"source": "gear_mod_pickup_smoke_auto_cancel",
	})
	await get_tree().process_frame
	_expect(
		auto_cancel_pickup != null
		and is_instance_valid(auto_cancel_pickup)
		and auto_cancel_pickup.is_in_group(PICKUP_GROUP)
		and _run_mod_ids(run_loop) == auto_cancel_mod_ids
		and (run_loop.call("debug_pending_gear_mod_placement") as Dictionary).is_empty(),
		"leaving PLAYING should auto-cancel the pending transaction and leave its pickup on the ground"
	)
	GameState.change_state(GameState.PLAYING, {
		"source": "gear_mod_pickup_smoke_resume_after_auto_cancel",
	})
	UIManager.clear()
	await get_tree().process_frame
	_release_active_pickups(run_loop)

	var weapon_system: Node = _find_node_by_name(player, "WeaponSystem")
	var damage_before_duplicate: float = (
		float(weapon_system.call("stat_value", STATS.DAMAGE))
		if weapon_system != null
		else 0.0
	)
	var damage_count_before_duplicate: int = _mod_id_count(
		_run_mod_ids(run_loop),
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
	)
	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		player.global_position
	)
	for _index: int in range(2):
		await get_tree().process_frame
	var duplicate_pickup: GearModPickup = _first_active_pickup(run_loop)
	if duplicate_pickup != null:
		run_loop.call("_update_gear_mod_pickup_prompt", duplicate_pickup)
	_expect(
		_interaction_prompt_text(hud).contains("+20%"),
		"duplicate pickup prompt should show the same fixed effect: %s"
		% _interaction_prompt_text(hud)
	)
	var gold_before: int = int(run_loop.call("gold_balance"))
	var duplicate_collect_result: bool = false
	if duplicate_pickup != null:
		player.global_position = duplicate_pickup.global_position
		_expect(
			duplicate_pickup.can_player_interact(player),
			"duplicate pickup should be within interaction radius before collection: pickup=%s player=%s radius_config=%s"
			% [
				str(duplicate_pickup.global_position),
				str(player.global_position),
				str(GearModSystem.pickup_config()),
			]
		)
		duplicate_collect_result = bool(run_loop.call(
			"_try_interact_gear_mod_pickup",
			duplicate_pickup
		))
		if duplicate_collect_result:
			var replay_pending: Dictionary = run_loop.call(
				"debug_pending_gear_mod_placement"
			) as Dictionary
			var replay_targets: Array[Dictionary] = _dictionary_array(
				replay_pending.get("legal_targets", [])
			)
			if replay_targets.is_empty():
				duplicate_collect_result = false
			else:
				var replay_target: Dictionary = replay_targets[0]
				InputService.set_playback_active(true)
				var replay_place_result: Dictionary = run_loop.call(
					"apply_replay_gear_mod_placement",
					{
						"instance_id": int(replay_pending.get("instance_id", 0)),
						"mod_id": String(replay_pending.get("mod_id", "")),
						"outcome": GEAR_MOD_PLACEMENT_OUTCOMES.PLACED,
						"x": int(replay_target.get("x", -1)),
						"y": int(replay_target.get("y", -1)),
					}
				) as Dictionary
				InputService.set_playback_active(false)
				duplicate_collect_result = bool(
					replay_place_result.get("ok", false)
				)
	var gold_after: int = int(run_loop.call("gold_balance"))
	var mod_ids_after_duplicate: Array[String] = _run_mod_ids(run_loop)
	var damage_after_duplicate: float = (
		float(weapon_system.call("stat_value", STATS.DAMAGE))
		if weapon_system != null
		else 0.0
	)
	_expect(
		duplicate_collect_result
		and gold_after == gold_before
		and _mod_id_count(
			mod_ids_after_duplicate,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		) == damage_count_before_duplicate + 1
		and weapon_system != null
		and is_equal_approx(
			damage_after_duplicate,
			damage_before_duplicate * 1.2
		),
		"duplicate pickup should append an independently multiplying Mod without gold conversion"
	)

	var ids_before_extra_placement: Array[String] = _run_mod_ids(run_loop)
	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
		player.global_position
	)
	var extra_pickup: GearModPickup = _first_active_pickup(run_loop)
	var extra_place_result: Dictionary = {}
	if extra_pickup != null:
		run_loop.call("_try_interact_gear_mod_pickup", extra_pickup)
		extra_place_result = _confirm_pending_first_legal(run_loop)
	_expect(
		bool(extra_place_result.get("ok", false))
		and _run_mod_ids(run_loop).size()
		== ids_before_extra_placement.size() + 1,
		"an additional pickup transaction should append exactly one placement"
	)
	var gear_mod_snapshot: Dictionary = (
		run_loop.call("create_run_snapshot") as Dictionary
	).get("gear_mods", {}) as Dictionary
	var saved_placements: Array[Dictionary] = _dictionary_array(
		gear_mod_snapshot.get("placements", [])
	)
	var saved_mod_ids: Array[String] = _placement_mod_ids(saved_placements)
	_expect(
		_are_placements_row_major(saved_placements)
		and int(gear_mod_snapshot.get("next_instance_id", 0)) > 0
		and _mod_id_count(
			saved_mod_ids,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		) == damage_count_before_duplicate + 1,
		"run snapshot should retain repeated flat placements in row-major order with the next logical id"
	)
	var build_summary: Dictionary = run_loop.call(
		"_run_gear_mod_build_summary"
	) as Dictionary
	_expect(
		_build_count(
			build_summary,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		) == damage_count_before_duplicate + 1,
		"build summary should aggregate repeated Mod instances into count"
	)

	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
		player.global_position
	)
	var original_availability: Dictionary = (
		run_loop.get("_content_availability") as Dictionary
	).duplicate(true)
	var locked_availability: Dictionary = original_availability.duplicate(true)
	var available_mods: Array = (
		locked_availability.get(CONTENT_UNLOCK_TYPES.GEAR_MOD, []) as Array
	).duplicate()
	available_mods.erase(
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER
	)
	locked_availability[CONTENT_UNLOCK_TYPES.GEAR_MOD] = available_mods
	run_loop.set("_content_availability", locked_availability)
	var failing_pickup: GearModPickup = _first_active_pickup(run_loop)
	var failed_collect_result: bool = false
	var failed_confirm_result: Dictionary = {}
	if failing_pickup != null:
		player.global_position = failing_pickup.global_position
		failed_collect_result = bool(run_loop.call(
			"_try_interact_gear_mod_pickup",
			failing_pickup
		))
		if failed_collect_result:
			failed_confirm_result = _confirm_pending_first_legal(run_loop)
	_expect(
		failed_collect_result
		and not bool(failed_confirm_result.get("ok", false))
		and String(failed_confirm_result.get("reason", ""))
		== "content_unavailable"
		and failing_pickup != null
		and is_instance_valid(failing_pickup)
		and failing_pickup.is_in_group(PICKUP_GROUP),
		"confirm validation failure should leave the pickup active instead of swallowing it"
	)
	var failed_pending: Dictionary = run_loop.call(
		"debug_pending_gear_mod_placement"
	) as Dictionary
	if not failed_pending.is_empty():
		run_loop.call(
			"cancel_gear_mod_placement",
			int(failed_pending.get("instance_id", 0)),
			String(failed_pending.get("mod_id", ""))
		)
	run_loop.set("_content_availability", original_availability)
	_release_active_pickups(run_loop)

	var board: RefCounted = run_loop.get("_gear_mod_board") as RefCounted
	if board != null:
		while true:
			var legal_rocks: Array[Vector2i] = board.call(
				"legal_cells",
				GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK
			) as Array[Vector2i]
			if legal_rocks.is_empty():
				break
			var rock_instance_id: int = int(run_loop.call(
				"_allocate_gear_mod_instance_id"
			))
			var rock_result: Dictionary = board.call(
				"request_placement",
				rock_instance_id,
				GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK,
				legal_rocks[0]
			) as Dictionary
			if not bool(rock_result.get("ok", false)):
				break
		run_loop.call("_sync_run_gear_mod_ids_from_board")
	_last_placement_failure.clear()
	run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		player.global_position
	)
	var no_space_pickup: GearModPickup = _first_active_pickup(run_loop)
	var no_space_interaction: bool = false
	if no_space_pickup != null:
		no_space_interaction = bool(run_loop.call(
			"_try_interact_gear_mod_pickup",
			no_space_pickup
		))
	_expect(
		not no_space_interaction
		and no_space_pickup != null
		and is_instance_valid(no_space_pickup)
		and no_space_pickup.is_in_group(PICKUP_GROUP)
		and (run_loop.call("debug_pending_gear_mod_placement") as Dictionary).is_empty()
		and String(_last_placement_failure.get("reason", ""))
		== "no_legal_cell"
		and String(hud.get("_last_upgrade_feedback_key"))
		== "ui_gear_mod_board_no_space",
		"a full board should emit no_legal_cell, show HUD feedback, avoid opening placement, and leave the pickup"
	)
	_release_active_pickups(run_loop)

	var first_node: Node = PoolManager.acquire(POOL_IDS.GEAR_MOD_PICKUP)
	var first_id: int = first_node.get_instance_id() if first_node != null else 0
	if first_node != null:
		PoolManager.release(first_node)
	var reused_node: Node = PoolManager.acquire(POOL_IDS.GEAR_MOD_PICKUP)
	_expect(
		reused_node != null
		and reused_node.get_instance_id() == first_id,
		"pickup pool should reuse an existing node"
	)
	if reused_node != null:
		PoolManager.release(reused_node)


func _expect_full_death_replay_contract() -> void:
	var boot_node: Node = get_parent()
	_expect(
		boot_node != null
		and boot_node.has_method("_start_gameplay_run"),
		"full-death Replay fixture should be hosted by FormalClientBoot"
	)
	if boot_node == null or not boot_node.has_method("_start_gameplay_run"):
		return

	Replay.clear_recording()
	InputService.set_playback_active(false)
	var recording_runtime: Dictionary = await _start_fresh_run(
		boot_node,
		0
	)
	var recording_run_loop: Node = recording_runtime.get("run_loop") as Node
	var recording_player: Node2D = recording_runtime.get("player") as Node2D
	_expect(
		recording_run_loop != null
		and recording_player != null
		and Replay.is_recording(),
		"full-death recording run should mount with Replay active"
	)
	if recording_run_loop == null or recording_player == null:
		return

	var recording_pickup: GearModPickup = _spawn_target_instance_pickup(
		recording_run_loop,
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		1,
		recording_player.global_position
	)
	if recording_pickup != null:
		recording_run_loop.call(
			"_try_interact_gear_mod_pickup",
			recording_pickup
		)
	var recording_pending: Dictionary = recording_run_loop.call(
		"debug_pending_gear_mod_placement"
	) as Dictionary
	var recorded_instance_id: int = int(
		recording_pending.get("instance_id", 0)
	)
	_expect(
		recording_pickup != null
		and recorded_instance_id == 1
		and InputService.non_pausing_ui_capture_active(),
		"full-death recording should start with one pending placement Panel"
	)
	await _defeat_player_through_combat(
		recording_run_loop,
		recording_player
	)
	await get_tree().create_timer(0.2, true).timeout
	await get_tree().process_frame
	var completed_recording: Dictionary = Replay.snapshot()
	var recorded_cancel_payload: Dictionary = _placement_decision_payload(
		completed_recording,
		recorded_instance_id,
		GEAR_MOD_PLACEMENT_OUTCOMES.CANCELLED
	)
	_expect(
		not Replay.is_recording()
		and not recorded_cancel_payload.is_empty()
		and (recording_run_loop.call(
			"debug_pending_gear_mod_placement"
		) as Dictionary).is_empty()
		and _find_node_by_name(
			get_tree().root,
			"GearModBoardPanel"
		) == null
		and not InputService.non_pausing_ui_capture_active()
		and _only_game_over_panel_remains(),
		"live Combat death should record semantic cancellation before Replay stops and leave only GameOverPanel"
	)

	InputService.set_playback_active(true)
	var playback_runtime: Dictionary = await _start_fresh_run(
		boot_node,
		recording_run_loop.get_instance_id()
	)
	var playback_run_loop: Node = playback_runtime.get("run_loop") as Node
	var playback_player: Node2D = playback_runtime.get("player") as Node2D
	_expect(
		playback_run_loop != null
		and playback_player != null,
		"full-death playback run should mount"
	)
	if playback_run_loop == null or playback_player == null:
		InputService.set_playback_active(false)
		return
	var playback_pickup: GearModPickup = _spawn_target_instance_pickup(
		playback_run_loop,
		String(recorded_cancel_payload.get("mod_id", "")),
		int(recorded_cancel_payload.get("instance_id", 0)),
		playback_player.global_position
	)
	if playback_pickup != null:
		playback_run_loop.call(
			"_try_interact_gear_mod_pickup",
			playback_pickup
		)
	var playback_pending: Dictionary = playback_run_loop.call(
		"debug_pending_gear_mod_placement"
	) as Dictionary
	_expect(
		int(playback_pending.get("instance_id", 0))
		== recorded_instance_id
		and InputService.non_pausing_ui_capture_active(),
		"full-death playback should recreate the recorded pending transaction"
	)
	var replay_cancel_result: Dictionary = playback_run_loop.call(
		"apply_replay_gear_mod_placement",
		recorded_cancel_payload
	) as Dictionary
	await _defeat_player_through_combat(
		playback_run_loop,
		playback_player
	)
	await get_tree().create_timer(0.2, true).timeout
	await get_tree().process_frame
	_expect(
		bool(replay_cancel_result.get("ok", false))
		and (playback_run_loop.call(
			"debug_pending_gear_mod_placement"
		) as Dictionary).is_empty()
		and _find_node_by_name(
			get_tree().root,
			"GearModBoardPanel"
		) == null
		and not InputService.non_pausing_ui_capture_active()
		and _only_game_over_panel_remains(),
		"ReplayRunner decision-before-runtime order should survive actual Combat death without divergence or capture leaks"
	)

	var playback_run_instance_id: int = playback_run_loop.get_instance_id()
	var inspect_runtime: Dictionary = await _start_fresh_run(
		boot_node,
		playback_run_instance_id
	)
	var inspect_run_loop: Node = inspect_runtime.get("run_loop") as Node
	var inspect_player: Node2D = inspect_runtime.get("player") as Node2D
	InputService.set_playback_active(false)
	_expect(
		inspect_run_loop != null and inspect_player != null,
		"inspect full-death run should mount"
	)
	if inspect_run_loop == null or inspect_player == null:
		return
	await _inject_physical_key_press(KEY_TAB)
	_expect(
		_find_node_by_name(
			get_tree().root,
			"GearModBoardPanel"
		) != null
		and InputService.non_pausing_ui_capture_active(),
		"Tab should open the inspect Panel and capture non-pausing UI input"
	)
	await _defeat_player_through_combat(inspect_run_loop, inspect_player)
	await get_tree().create_timer(0.2, true).timeout
	await get_tree().process_frame
	_expect(
		_find_node_by_name(
			get_tree().root,
			"GearModBoardPanel"
		) == null
		and not InputService.non_pausing_ui_capture_active()
		and _only_game_over_panel_remains(),
		"held-Tab inspect should close before actual GameOverPanel is pushed and must not leak input capture"
	)
	await _inject_physical_key_release(KEY_TAB)
	_expect(
		not InputService.non_pausing_ui_capture_active()
		and _only_game_over_panel_remains(),
		"releasing Tab after full death should leave only GameOverPanel active"
	)


func _start_fresh_run(
	boot_node: Node,
	previous_run_instance_id: int
	) -> Dictionary:
	boot_node.call(
		"_start_gameplay_run",
		{},
		false,
		{
			"content_availability": (
				ContentUnlockSystem.build_run_availability_snapshot()
			),
			"content_progress_commits_enabled": false,
		}
	)
	for _index: int in range(30):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(
			get_tree().root,
			"GameplayRunLoop"
		)
		if (
			run_loop != null
			and run_loop.get_instance_id() != previous_run_instance_id
			and GameState.is_state(GameState.PLAYING)
		):
			var player: Node2D = _find_node_by_name(
				run_loop,
				"Player"
			) as Node2D
			if player != null:
				return {
					"run_loop": run_loop,
					"player": player,
				}
	return {}


func _spawn_target_instance_pickup(
	run_loop: Node,
	mod_id: String,
	target_instance_id: int,
	position: Vector2
	) -> GearModPickup:
	if target_instance_id <= 0:
		return null
	for _index: int in range(target_instance_id):
		var spawn_result: Dictionary = run_loop.call(
			"_spawn_gear_mod_pickup",
			mod_id,
			position
		) as Dictionary
		if not bool(spawn_result.get("ok", false)):
			return null
		var pickup: GearModPickup = _first_active_pickup(run_loop)
		if pickup == null:
			return null
		var instance_id: int = pickup.gear_mod_instance_id()
		if instance_id == target_instance_id:
			return pickup
		PoolManager.release(pickup)
		if instance_id > target_instance_id:
			return null
	return null


func _defeat_player_through_combat(
	run_loop: Node,
	player: Node
	) -> void:
	if player.has_method("debug_set_shield"):
		player.call("debug_set_shield", 0.0, 0.0)
	if player.has_method("debug_clear_invulnerability"):
		player.call("debug_clear_invulnerability")
	var damage_source: Node = Node.new()
	damage_source.name = "GearModReplayFullDeathDamageSource"
	run_loop.add_child(damage_source)
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		float(player.call("max_life")) * 10.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		damage_source,
		player,
		TEAM_ENEMY,
		TEAM_PLAYER
	)
	var result: Dictionary = Combat.apply_damage(player, info)
	_expect(
		bool(result.get("applied", false))
		and bool(result.get("defeated", false)),
		"full-death fixture should defeat Player through Combat.apply_damage"
	)
	damage_source.queue_free()
	await get_tree().process_frame


func _only_game_over_panel_remains() -> bool:
	return (
		UIManager.stack_size() == 1
		and _find_node_by_name(
			get_tree().root,
			"GameOverPanel"
		) != null
	)


func _expect_world_event_spawn_contract(run_loop: Node) -> void:
	_release_active_pickups(run_loop)
	var mod_ids_before: Array[String] = _run_mod_ids(run_loop)
	var event_cases: Array[Dictionary] = [
		{
			"event_id": WORLD_EVENT_IDS.WORLD_EVENT_DEFENSE,
			"source": WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE,
		},
		{
			"event_id": WORLD_EVENT_IDS.WORLD_EVENT_SURVIVAL,
			"source": WORLD_EVENT_KINDS.WORLD_EVENT_KIND_SURVIVAL,
		},
		{
			"event_id": WORLD_EVENT_IDS.WORLD_EVENT_CAPTURE,
			"source": WORLD_EVENT_KINDS.WORLD_EVENT_KIND_CAPTURE,
		},
		{
			"event_id": WORLD_EVENT_IDS.WORLD_EVENT_GOLD_SHRINE,
			"source": WORLD_EVENT_KINDS.WORLD_EVENT_KIND_GOLD_SHRINE,
		},
	]
	for index: int in range(event_cases.size()):
		var event_case: Dictionary = event_cases[index]
		run_loop.call(
			"_on_world_event_reward_requested",
			"pickup_smoke_%d" % index,
			String(event_case.get("event_id", "")),
			{
				"kind": WORLD_EVENT_REWARD_TYPES.WORLD_EVENT_REWARD_GEAR_MOD,
				"source": String(event_case.get("source", "")),
				"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER,
			}
		)
	_expect(
		_active_pickup_count(run_loop) == event_cases.size()
		and _run_mod_ids(run_loop) == mod_ids_before,
		"defense, survival, capture, and gold shrine rewards should spawn pickups without immediate grants"
	)
	var split_positions: Array[Vector2] = run_loop.call(
		"_gear_mod_reward_positions",
		Vector2.ZERO,
		2
	) as Array[Vector2]
	_expect(
		split_positions == [Vector2(-28.0, -36.0), Vector2(28.0, -36.0)],
		"two-drop rewards should use the configured left/right spread without RNG"
	)
	_release_active_pickups(run_loop)


func _expect_snapshot_validation_contract(run_loop: Node) -> void:
	_release_active_pickups(run_loop)
	for index: int in range(3):
		run_loop.call(
			"_spawn_gear_mod_pickup",
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			Vector2(float(index * 32), 0.0)
		)
	var ordered_pickups: Array = (
		(run_loop.call("create_run_snapshot") as Dictionary).get(
			"gear_mod_pickups",
			[]
		) as Array
	).duplicate(true)
	var active_nodes: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(PICKUP_GROUP):
		if run_loop.is_ancestor_of(node):
			active_nodes.append(node)
	for node: Node in active_nodes:
		node.remove_from_group(PICKUP_GROUP)
	active_nodes.reverse()
	for node: Node in active_nodes:
		node.add_to_group(PICKUP_GROUP)
	var reordered_pickups: Array = (
		(run_loop.call("create_run_snapshot") as Dictionary).get(
			"gear_mod_pickups",
			[]
		) as Array
	).duplicate(true)
	_expect(
		ordered_pickups == reordered_pickups
		and _pickup_snapshots_are_instance_sorted(reordered_pickups),
		"active pickup snapshots should stay instance-sorted after SceneTree group order is reversed"
	)
	_release_active_pickups(run_loop)
	var valid_snapshot: Dictionary = run_loop.call(
		"create_run_snapshot"
	) as Dictionary
	var invalid_mod_snapshot: Dictionary = valid_snapshot.duplicate(true)
	_set_snapshot_next_instance_id(invalid_mod_snapshot, 2)
	invalid_mod_snapshot["gear_mod_pickups"] = [
		{
			"instance_id": 1,
			"mod_id": "missing_gear_mod",
			"position": {"x": 0.0, "y": 0.0},
		},
	]
	_expect(
		not bool(run_loop.call(
			"_validate_run_gear_mod_pickup_snapshots",
			invalid_mod_snapshot
		)),
		"unknown pickup snapshots should fail run validation"
	)
	var original_availability: Dictionary = (
		run_loop.get("_content_availability") as Dictionary
	).duplicate(true)
	var locked_availability: Dictionary = original_availability.duplicate(true)
	var available_mods: Array = (
		locked_availability.get(CONTENT_UNLOCK_TYPES.GEAR_MOD, []) as Array
	).duplicate()
	available_mods.erase(GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST)
	locked_availability[CONTENT_UNLOCK_TYPES.GEAR_MOD] = available_mods
	run_loop.set("_content_availability", locked_availability)
	var locked_mod_snapshot: Dictionary = valid_snapshot.duplicate(true)
	_set_snapshot_next_instance_id(locked_mod_snapshot, 2)
	locked_mod_snapshot["gear_mod_pickups"] = [
		{
			"instance_id": 1,
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"position": {"x": 0.0, "y": 0.0},
		},
	]
	_expect(
		not bool(run_loop.call(
			"_validate_run_gear_mod_pickup_snapshots",
			locked_mod_snapshot
		)),
		"locked pickup snapshots should fail run validation"
	)
	run_loop.set("_content_availability", original_availability)
	var invalid_position_snapshot: Dictionary = valid_snapshot.duplicate(true)
	_set_snapshot_next_instance_id(invalid_position_snapshot, 2)
	invalid_position_snapshot["gear_mod_pickups"] = [
		{
			"instance_id": 1,
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"position": {"x": INF, "y": 0.0},
		},
	]
	_expect(
		not bool(run_loop.call(
			"_validate_run_gear_mod_pickup_snapshots",
			invalid_position_snapshot
		)),
		"non-finite pickup positions should fail run validation"
	)
	var extra_field_snapshot: Dictionary = valid_snapshot.duplicate(true)
	_set_snapshot_next_instance_id(extra_field_snapshot, 2)
	extra_field_snapshot["gear_mod_pickups"] = [
		{
			"instance_id": 1,
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"position": {"x": 0.0, "y": 0.0},
			"unexpected": true,
		},
	]
	_expect(
		not bool(run_loop.call(
			"_validate_run_gear_mod_pickup_snapshots",
			extra_field_snapshot
		)),
		"unknown pickup snapshot fields should fail run validation"
	)


func _push_action_once(action_id: String) -> void:
	InputService.set_playback_active(true)
	InputService.inject_playback_value(action_id, true)
	await get_tree().process_frame
	await get_tree().physics_frame
	InputService.inject_playback_value(action_id, false)
	await get_tree().process_frame
	await get_tree().physics_frame
	InputService.set_playback_active(false)


func _on_gear_mod_placement_failed(result: Dictionary) -> void:
	_last_placement_failure = result.duplicate(true)


func _on_gear_mod_placement_resolved(result: Dictionary) -> void:
	_last_placement_result = result.duplicate(true)


func _inject_physical_key_once(keycode: Key) -> void:
	await _inject_physical_key_press(keycode)
	await _inject_physical_key_release(keycode)


func _inject_physical_key_press(keycode: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = keycode
	press.pressed = true
	InputService.debug_inject_input(press)
	await get_tree().physics_frame
	await get_tree().process_frame


func _inject_physical_key_release(keycode: Key) -> void:
	var release := InputEventKey.new()
	release.physical_keycode = keycode
	release.pressed = false
	InputService.debug_inject_input(release)
	await get_tree().physics_frame
	await get_tree().process_frame


func _recording_has_input_press(
	recording: Dictionary,
	action_id: String
	) -> bool:
	for raw_event: Variant in recording.get("input_events", []) as Array:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event as Dictionary
		if (
			String(event.get("action", "")) == action_id
			and String(event.get("value_type", "")) == "bool"
			and bool(event.get("value", false))
		):
			return true
	return false


func _recording_has_placement_decision(
	recording: Dictionary,
	instance_id: int,
	outcome: String
	) -> bool:
	for raw_event: Variant in recording.get("decision_events", []) as Array:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event as Dictionary
		if String(event.get("event", "")) != ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT:
			continue
		var payload: Dictionary = event.get("payload", {}) as Dictionary
		if (
			int(payload.get("instance_id", 0)) == instance_id
			and String(payload.get("outcome", "")) == outcome
		):
			return true
	return false


func _placement_decision_payload(
	recording: Dictionary,
	instance_id: int,
	outcome: String
	) -> Dictionary:
	for raw_event: Variant in recording.get("decision_events", []) as Array:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event as Dictionary
		if String(event.get("event", "")) != ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT:
			continue
		var payload: Dictionary = event.get("payload", {}) as Dictionary
		if (
			int(payload.get("instance_id", 0)) == instance_id
			and String(payload.get("outcome", "")) == outcome
		):
			return payload.duplicate(true)
	return {}


func _confirm_pending_first_legal(run_loop: Node) -> Dictionary:
	var pending: Dictionary = run_loop.call(
		"debug_pending_gear_mod_placement"
	) as Dictionary
	var legal_targets: Array[Dictionary] = _dictionary_array(
		pending.get("legal_targets", [])
	)
	if pending.is_empty() or legal_targets.is_empty():
		return {"ok": false, "reason": "missing_pending_target"}
	var target: Dictionary = legal_targets[0]
	return run_loop.call(
		"confirm_gear_mod_placement",
		int(pending.get("instance_id", 0)),
		String(pending.get("mod_id", "")),
		Vector2i(
			int(target.get("x", -1)),
			int(target.get("y", -1))
		)
	) as Dictionary


func _run_mod_ids(run_loop: Node) -> Array[String]:
	var snapshot_data: Dictionary = run_loop.call(
		"create_run_snapshot"
	) as Dictionary
	return _placement_mod_ids(
		_dictionary_array(
			(snapshot_data.get("gear_mods", {}) as Dictionary).get(
				"placements",
				[]
			)
		)
	)


func _placement_mod_ids(placements: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for placement: Dictionary in placements:
		result.append(String(placement.get("mod_id", "")))
	return result


func _are_placements_row_major(placements: Array[Dictionary]) -> bool:
	for index: int in range(1, placements.size()):
		var previous: Dictionary = placements[index - 1]
		var current: Dictionary = placements[index]
		var previous_y: int = int(previous.get("y", -1))
		var current_y: int = int(current.get("y", -1))
		if current_y < previous_y:
			return false
		if (
			current_y == previous_y
			and int(current.get("x", -1))
			< int(previous.get("x", -1))
		):
			return false
	return true


func _set_snapshot_next_instance_id(
	snapshot_data: Dictionary,
	value: int
) -> void:
	var gear_mods: Dictionary = _dictionary_or_empty(
		snapshot_data.get("gear_mods", {})
	).duplicate(true)
	gear_mods["next_instance_id"] = value
	snapshot_data["gear_mods"] = gear_mods


func _dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for raw_item: Variant in raw_value as Array:
		if raw_item is Dictionary:
			result.append((raw_item as Dictionary).duplicate(true))
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	return raw_value as Dictionary if raw_value is Dictionary else {}


func _pickup_snapshots_are_instance_sorted(raw_pickups: Array) -> bool:
	var previous_instance_id: int = 0
	for raw_pickup: Variant in raw_pickups:
		if not raw_pickup is Dictionary:
			return false
		var instance_id: int = int(
			(raw_pickup as Dictionary).get("instance_id", 0)
		)
		if instance_id <= previous_instance_id:
			return false
		previous_instance_id = instance_id
	return true


func _mod_id_count(mod_ids: Array[String], mod_id: String) -> int:
	var count: int = 0
	for candidate_id: String in mod_ids:
		if candidate_id == mod_id:
			count += 1
	return count


func _build_count(build_summary: Dictionary, mod_id: String) -> int:
	for raw_entry: Variant in build_summary.get("gear_mods", []) as Array:
		if (
			raw_entry is Dictionary
			and String((raw_entry as Dictionary).get("mod_id", ""))
			== mod_id
		):
			return int((raw_entry as Dictionary).get("count", 0))
	return 0


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for raw_item: Variant in raw_value as Array:
		if raw_item is String:
			result.append(raw_item as String)
	return result


func _active_pickup_count(run_loop: Node) -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(PICKUP_GROUP):
		if run_loop.is_ancestor_of(node):
			count += 1
	return count


func _first_active_pickup(run_loop: Node) -> GearModPickup:
	for node: Node in get_tree().get_nodes_in_group(PICKUP_GROUP):
		if node is GearModPickup and run_loop.is_ancestor_of(node):
			return node as GearModPickup
	return null


func _release_active_pickups(run_loop: Node) -> void:
	for node: Node in get_tree().get_nodes_in_group(PICKUP_GROUP):
		if run_loop.is_ancestor_of(node):
			PoolManager.release(node)


func _interaction_prompt_text(hud: Node) -> String:
	var label: RichTextLabel = _find_node_by_name(
		hud,
		"MessageLabel"
	) as RichTextLabel
	return label.text if label != null and label.visible else ""


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _find_collision_object(root: Node) -> CollisionObject2D:
	if root is CollisionObject2D:
		return root as CollisionObject2D
	for child: Node in root.get_children():
		var found: CollisionObject2D = _find_collision_object(child)
		if found != null:
			return found
	return null


func _descendant_count(root: Node) -> int:
	var count: int = 0
	for child: Node in root.get_children():
		count += 1 + _descendant_count(child)
	return count


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[GearModPickupSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[GearModPickupSmoke] passed")
		get_tree().quit(0)
		return
	print(
		"[GearModPickupSmoke] failed; failures=%d"
		% _failures.size()
	)
	get_tree().quit(1)
