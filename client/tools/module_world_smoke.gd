extends Node
## F13 headless smoke for deterministic composition, seamless streaming, fog,
## objective completion, threat-time combat gates and Run v18 restore.

const MODULE_WORLD_MANAGER_SCENE := preload("res://scenes/gameplay/module_world_manager.tscn")
const MODULE_NAVIGATION_FIELD_SCRIPT := preload("res://scripts/gameplay/module_navigation_field.gd")
const ACTIONS := preload("res://scripts/contracts/actions.gd")
const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_ROLES := preload("res://scripts/contracts/module_roles.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

const BOOT_FRAMES: int = 4
const NAVIGATION_FLOW_RADIUS_CELLS: int = 8
const SMOKE_SLOT: String = "slot_module_world_smoke"

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var run_loop: Node = await _wait_for_playing_run_loop()
	_expect(run_loop != null, "module-world run should reach PLAYING")
	if run_loop == null:
		_finish()
		return
	_expect(bool(run_loop.call("debug_module_world_enabled")), "module world should be the standard carrier")
	var player_node: Node = _find_node_by_name(get_tree().root, "Player")
	var module_world_node: Node = _find_node_by_name(get_tree().root, "ModuleWorldManager")
	var player_collision: CollisionShape2D = player_node.get_node_or_null("CollisionShape2D") as CollisionShape2D if player_node != null else null
	_expect(
		player_node is Node2D
		and module_world_node is Node2D
		and (module_world_node as Node2D).z_index < (player_node as Node2D).z_index,
		"module terrain should render below the player"
	)
	_expect(
		player_collision != null and player_collision.shape is CircleShape2D,
		"player should expose a physical collision shape for blocked module cells"
	)
	_expect(player_node != null and player_node.get_node_or_null("StatusEffectComponent") != null, "player status component should be scene-authored")
	var skill_system: Node = run_loop.get_node_or_null("SkillSystem")
	_expect(skill_system != null and skill_system.get_node_or_null("StatusEffectComponent") != null, "skill system and status component should be scene-authored")
	var gameplay_hud: Node = run_loop.get_node_or_null("GameplayHud")
	_expect(gameplay_hud != null and gameplay_hud.get_node_or_null("Root/ModuleMinimap") != null, "HUD minimap should be scene-authored")
	await _expect_start_module_difficulty_and_combat_gate(
		run_loop,
		skill_system
	)
	var visible_chunk_count: int = 0
	var visible_chunk_has_ground: bool = false
	var visible_chunk_has_collision: bool = false
	for child: Node in module_world_node.get_children():
		if not child is ModuleChunk or not (child as ModuleChunk).visible:
			continue
		visible_chunk_count += 1
		var generated: GeneratedModuleScene = (
			child as ModuleChunk
		).generated_instance()
		var ground: TileMapLayer = generated.get_node_or_null(
			"Ground"
		) as TileMapLayer
		var collision: CollisionShape2D = generated.get_node_or_null(
			"TerrainCollision/MergedBlockedCells"
		) as CollisionShape2D
		visible_chunk_has_ground = visible_chunk_has_ground or (ground != null and not ground.get_used_cells().is_empty())
		visible_chunk_has_collision = visible_chunk_has_collision or (collision != null and collision.shape is ConcavePolygonShape2D and not collision.disabled)
	var expected_initial_chunk_count: int = 9 if OS.get_cmdline_user_args().has("--module-world-technical-slice") else 4
	_expect(visible_chunk_count == expected_initial_chunk_count, "initial start streaming should activate the expected in-bounds chunks")
	_expect(visible_chunk_has_ground, "active chunks should mount generated ground TileMap data")
	_expect(visible_chunk_has_collision, "active chunks should mount generated merged collision resources")

	var summary: Dictionary = run_loop.call("debug_summary")
	var world_summary: Dictionary = summary.get("module_world", {}) as Dictionary
	_expect(int(world_summary.get("assignment_count", 0)) == 49, "world should assign exactly 49 slots")
	_expect(int(world_summary.get("active_count", 0)) <= 9, "streaming should activate at most nine chunks")
	_expect(int(world_summary.get("chunk_pool_size", 0)) == 12, "manager scene should provide exactly twelve reusable chunks")
	_expect(int(world_summary.get("world_event_assignment_count", 0)) == 3, "seeded world should place exactly three world event modules")
	_expect((world_summary.get("world_event_template_ids", []) as Array).size() == 3, "seeded world events should use three distinct templates")
	var world_event_summary: Dictionary = (
		run_loop.call("debug_world_event_summary") as Dictionary
	)
	_expect(
		int(world_event_summary.get("registered_node_count", 0)) == 3,
		"runtime should register one interactable for each selected event module"
	)
	_expect(
		(world_event_summary.get("instances", []) as Array).size() == 3,
		"world event controller should own exactly three runtime instances"
	)
	var fresh_run_snapshot: Dictionary = (
		run_loop.call("create_run_snapshot") as Dictionary
	)
	_expect(
		int(fresh_run_snapshot.get("schema_version", 0)) == 18
		and not (fresh_run_snapshot.get("world_events", {}) as Dictionary).is_empty(),
		"Run v18 should save registered world-event state"
	)
	_expect(String(world_summary.get("map_hash", "")).length() == 64, "world should expose a sha256 map hash")
	var expected_start_coord := Vector2i(3, 3) if OS.get_cmdline_user_args().has("--module-world-technical-slice") else Vector2i(0, 6)
	_expect(_coord_matches(world_summary.get("current_module", {}), expected_start_coord), "fresh run should start at the configured start module")
	var original_start_state: Dictionary = module_world_node.call(
		"slot_state",
		expected_start_coord
	) as Dictionary
	var shuffled_start_state: Dictionary = original_start_state.duplicate(true)
	shuffled_start_state["gear_mod_pickup_snapshots"] = [
		{
			"instance_id": 9002,
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"position": {"x": 0.0, "y": 0.0},
		},
		{
			"instance_id": 9001,
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"position": {"x": 0.0, "y": 0.0},
		},
	]
	module_world_node.call(
		"set_slot_state",
		expected_start_coord,
		shuffled_start_state
	)
	var normalized_module_snapshot: Dictionary = run_loop.call(
		"_module_world_snapshot"
	) as Dictionary
	var normalized_start_state: Dictionary = (
		(normalized_module_snapshot.get("slot_states", {}) as Dictionary).get(
			"%d,%d" % [expected_start_coord.x, expected_start_coord.y],
			{}
		) as Dictionary
	)
	var normalized_cached_pickups: Array = normalized_start_state.get(
		"gear_mod_pickup_snapshots",
		[]
	) as Array
	_expect(
		normalized_cached_pickups.size() == 2
		and int((normalized_cached_pickups[0] as Dictionary).get("instance_id", 0)) == 9001
		and int((normalized_cached_pickups[1] as Dictionary).get("instance_id", 0)) == 9002,
		"module cache pickup arrays should serialize in stable instance-id order"
	)
	module_world_node.call(
		"set_slot_state",
		expected_start_coord,
		original_start_state
	)
	var runtime_navigation: Dictionary = world_summary.get("navigation", {}) as Dictionary
	_expect(
		int(runtime_navigation.get("flow_radius_cells", 0)) == NAVIGATION_FLOW_RADIUS_CELLS,
		"runtime should derive an eight-cell flow radius from current EnemyAI sight data"
	)

	print("[ModuleWorldSmoke] stage=composition")
	_expect_deterministic_composition()
	_expect_enemy_unlock_boundaries(run_loop)
	print("[ModuleWorldSmoke] stage=streaming")
	await _expect_seamless_streaming(run_loop)
	await _expect_gear_mod_cage_behavior(run_loop)
	print("[ModuleWorldSmoke] stage=objective_restore")
	await _expect_objective_completion_and_restore(run_loop)
	print("[ModuleWorldSmoke] stage=finish")
	SaveManager.delete(SMOKE_SLOT, SAVE_KINDS.RUN)
	_finish()


func _expect_start_module_difficulty_and_combat_gate(
	run_loop: Node,
	skill_system: Node
) -> void:
	var difficulty_before: Dictionary = run_loop.call(
		"debug_difficulty_snapshot"
	)
	var elapsed_before: float = float(
		difficulty_before.get("elapsed", -1.0)
	)
	await _wait_frames(8)
	var difficulty_after: Dictionary = run_loop.call(
		"debug_difficulty_snapshot"
	)
	_expect(
		is_equal_approx(
			float(difficulty_after.get("elapsed", -2.0)),
			elapsed_before
		),
		"start module should pause difficulty time"
	)
	_expect(
		int(difficulty_after.get("difficulty_level", 0)) == 1,
		"start module should retain threat level one"
	)

	var skill_before: Dictionary = (
		skill_system.call("snapshot") as Dictionary
		if skill_system != null and skill_system.has_method("snapshot")
		else {}
	)
	var cast_result: Dictionary = run_loop.call(
		"debug_cast_primary_skill"
	)
	var skill_after: Dictionary = (
		skill_system.call("snapshot") as Dictionary
		if skill_system != null and skill_system.has_method("snapshot")
		else {}
	)
	_expect(
		not bool(cast_result.get("ok", true))
		and String(cast_result.get("reason", "")) == "combat_locked",
		"start module should reject skills with combat_locked"
	)
	_expect(
		skill_after.get("resources", {}) == skill_before.get("resources", {})
		and skill_after.get("cooldowns", {}) == skill_before.get(
			"cooldowns",
			{}
		),
		"combat-locked skills should not spend resources or start cooldowns"
	)

	var bullets_before: int = PoolManager.active_count(
		POOL_IDS.BULLET_BASIC
	)
	var combat_rng_before: Dictionary = RNG.combat.snapshot()
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	await _wait_frames(4)
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	InputService.set_playback_active(false)
	_expect(
		PoolManager.active_count(POOL_IDS.BULLET_BASIC)
		== bullets_before,
		"start module firing should not generate bullets"
	)
	_expect(
		RNG.combat.snapshot() == combat_rng_before,
		"start module firing should not consume combat RNG"
	)


func _expect_deterministic_composition() -> void:
	var data: Dictionary = _load_world_data()
	_expect_start_corner_contract(data)
	var manager_a: Node2D = MODULE_WORLD_MANAGER_SCENE.instantiate() as Node2D
	var manager_b: Node2D = MODULE_WORLD_MANAGER_SCENE.instantiate() as Node2D
	var manager_c: Node2D = MODULE_WORLD_MANAGER_SCENE.instantiate() as Node2D
	var manager_d: Node2D = MODULE_WORLD_MANAGER_SCENE.instantiate() as Node2D
	var manager_content: Node2D = MODULE_WORLD_MANAGER_SCENE.instantiate() as Node2D
	var manager_technical: Node2D = MODULE_WORLD_MANAGER_SCENE.instantiate() as Node2D
	add_child(manager_a)
	add_child(manager_b)
	add_child(manager_c)
	add_child(manager_d)
	add_child(manager_content)
	add_child(manager_technical)
	_expect(bool(manager_a.call("configure", data["world"], data["registry"], data["templates"], data["generated"], 13013, NAVIGATION_FLOW_RADIUS_CELLS)), "seed A world should configure")
	_expect(bool(manager_b.call("configure", data["world"], data["registry"], data["templates"], data["generated"], 13013, NAVIGATION_FLOW_RADIUS_CELLS)), "same-seed world should configure")
	_expect(bool(manager_c.call("configure", data["world"], data["registry"], data["templates"], data["generated"], 13014, NAVIGATION_FLOW_RADIUS_CELLS)), "different-seed world should configure")
	_expect(bool(manager_d.call("configure", data["world"], data["registry"], data["templates"], data["generated"], 13015, NAVIGATION_FLOW_RADIUS_CELLS)), "third-seed world should configure")
	_expect(String(manager_a.call("map_hash")) == String(manager_b.call("map_hash")), "same seed should reproduce assignment/hash")
	_expect(manager_a.call("assignment") == manager_b.call("assignment"), "same seed should reproduce all 49 assignments")
	var manager_a_summary: Dictionary = manager_a.call("debug_summary")
	_expect(
		int(manager_a_summary.get("preloaded_scene_count", 0))
		== _unique_assignment_scene_count(manager_a.call("assignment") as Dictionary),
		"world setup should preload each assigned canonical module scene exactly once"
	)
	var initial_stream: Dictionary = manager_a.call(
		"tick",
		manager_a.call("global_cell_to_world", Vector2i(38, 38))
	)
	_expect(
		(initial_stream.get("activated", []) as Array).size() == 9,
		"initial center stream should mount nine generated module scenes"
	)
	var edge_stream: Dictionary = manager_a.call(
		"tick",
		manager_a.call("global_cell_to_world", Vector2i(49, 38))
	)
	_expect(
		(edge_stream.get("activated", []) as Array).size() <= 3
		and (edge_stream.get("deactivated", []) as Array).size() <= 3,
		"one-module crossing should replace at most three edge chunks"
	)
	_expect(
		_formal_assignment_has_three_events_and_flat_fill(
			manager_a.call("assignment") as Dictionary
		),
		"formal assignment should contain three distinct event templates and flat-fill other ordinary slots"
	)
	_expect(
		String(manager_a.call("map_hash")) != String(manager_c.call("map_hash")),
		"different run seeds should produce different map hashes"
	)
	var event_coords: Array[Vector2i] = _world_event_coords(
		manager_c.call("assignment") as Dictionary
	)
	_expect(event_coords.size() == 3, "seeded assignment should expose three event coordinates")
	for event_coord: Vector2i in event_coords:
		_expect(bool(manager_c.call("set_slot_pinned", event_coord, true)), "each event module should be pinnable")
	manager_c.call("tick", Vector2(1_000_000.0, 1_000_000.0))
	var pinned_summary: Dictionary = manager_c.call("debug_summary")
	_expect(int(pinned_summary.get("pinned_count", 0)) == 3, "three pinned event modules should be retained")
	_expect(int(pinned_summary.get("active_count", 0)) == 3, "outside-world streaming should retain only pinned event modules")
	_expect(not bool(manager_c.call("set_slot_pinned", Vector2i(3, 3), true)), "pinning beyond the three-slot reserve should fail")
	_expect(
		(manager_a.call("empty_floor_positions_at", Vector2i(5, 4)) as Array).size()
		in [120, 121],
		"interior flat or event slots should expose 121 or 120 spawnable cell centers"
	)
	var flat_data: Dictionary = (
		data["templates"] as Dictionary
	).get("module_flat_ground", {}) as Dictionary
	_expect(
		_flat_module_is_empty_floor(flat_data),
		"flat-ground module should be 121 floor cells with no gameplay placements"
	)
	var changed_templates: Dictionary = (data["templates"] as Dictionary).duplicate(true)
	var changed_objective: Dictionary = (changed_templates["module_objective_core"] as Dictionary).duplicate(true)
	var changed_placements: Array = (changed_objective.get("placements", []) as Array).duplicate(true)
	var changed_target: Dictionary = (changed_placements[0] as Dictionary).duplicate(true)
	changed_target["target_hp"] = float(changed_target.get("target_hp", 0.0)) + 1.0
	changed_placements[0] = changed_target
	changed_objective["placements"] = changed_placements
	changed_templates["module_objective_core"] = changed_objective
	_expect(bool(manager_content.call("configure", data["world"], data["registry"], changed_templates, data["generated"], 13013, NAVIGATION_FLOW_RADIUS_CELLS)), "content-revision world should configure")
	_expect(manager_content.call("assignment") == manager_a.call("assignment"), "content revision should preserve the same seeded assignment")
	_expect(String(manager_content.call("map_hash")) != String(manager_a.call("map_hash")), "module content revision should invalidate map hash")
	_expect(bool(manager_technical.call("configure", data["world"], data["registry"], data["templates"], data["generated"], 13013, NAVIGATION_FLOW_RADIUS_CELLS)), "technical-slice manager should configure")
	_expect(bool(manager_technical.call("build_technical_slice_assignment")), "technical-slice opt-in should build its checked-in assignment")
	var sealed_count: int = 0
	for raw_entry: Variant in (manager_technical.call("assignment") as Dictionary).values():
		if not raw_entry is Dictionary:
			continue
		var template_id: String = String((raw_entry as Dictionary).get("template_id", ""))
		var registry_entry: Dictionary = (data["registry"] as Dictionary).get(template_id, {}) as Dictionary
		if String(registry_entry.get("role", "")) == MODULE_ROLES.MODULE_ROLE_SEALED:
			sealed_count += 1
	_expect(sealed_count == 40, "technical slice should seal exactly the outer 40 slots")
	var technical_summary: Dictionary = manager_technical.call("debug_summary")
	_expect(int(technical_summary.get("world_event_assignment_count", 0)) == 3, "technical slice should contain exactly three world events")
	_expect((technical_summary.get("world_event_template_ids", []) as Array).size() == 3, "technical slice world events should be distinct")
	_expect(manager_technical.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_START) == Vector2i(3, 3), "technical slice should retain the center start")
	_expect(manager_technical.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_OBJECTIVE) == Vector2i(2, 3), "technical slice should expose its in-slice objective anchor")
	_expect(bool(manager_b.call("build_technical_slice_assignment")), "second technical-slice manager should configure deterministic navigation")
	_expect_navigation_queries(manager_technical, manager_b, manager_technical)
	var tampered_snapshot: Dictionary = manager_a.call("snapshot")
	tampered_snapshot["map_hash"] = "0".repeat(64)
	_expect(not bool(manager_a.call("restore_state", tampered_snapshot)), "restore should reject a mismatched module map hash")
	var seeded_objective_coord: Vector2i = manager_d.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_OBJECTIVE) as Vector2i
	_expect(bool(manager_d.call("build_fallback_assignment")), "fallback assignment should build")
	var fallback_summary: Dictionary = manager_d.call("debug_summary")
	_expect(int(fallback_summary.get("world_event_assignment_count", 0)) == 3, "fallback assignment should contain exactly three world events")
	_expect((fallback_summary.get("world_event_template_ids", []) as Array).size() == 3, "fallback world events should be distinct")
	_expect(
		manager_d.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_OBJECTIVE) == seeded_objective_coord,
		"fallback should deterministically select the same objective corner for the run seed"
	)
	_expect_objective_candidate_seed_coverage(data)
	var center_world: Vector2 = manager_a.call("global_cell_to_world", Vector2i(38, 38))
	_expect(center_world.is_equal_approx(Vector2.ZERO), "global center cell should map to world origin")
	_expect(manager_a.call("world_to_global_cell", Vector2.ZERO) == Vector2i(38, 38), "world origin should map to global center cell")
	manager_a.queue_free()
	manager_b.queue_free()
	manager_c.queue_free()
	manager_d.queue_free()
	manager_content.queue_free()
	manager_technical.queue_free()


func _expect_start_corner_contract(data: Dictionary) -> void:
	var world: Dictionary = data.get("world", {}) as Dictionary
	var fixed_slots: Array = world.get("fixed_slots", []) as Array
	_expect(fixed_slots.size() == 1, "formal world should keep only the fixed start slot")
	if fixed_slots.is_empty() or not fixed_slots[0] is Dictionary:
		return
	var start_entry: Dictionary = fixed_slots[0] as Dictionary
	_expect(
		String(start_entry.get("template_id", "")) == "module_start_corner"
		and _coord_matches(start_entry.get("slot", {}), Vector2i(0, 6))
		and int(start_entry.get("rotation", -1)) == 0,
		"formal lower-left start should use module_start_corner at zero rotation"
	)
	var start_template: Dictionary = (data.get("templates", {}) as Dictionary).get(
		"module_start_corner",
		{}
	) as Dictionary
	var placements: Array = start_template.get("placements", []) as Array
	var player_placements: Array[Dictionary] = []
	for raw_placement: Variant in placements:
		if raw_placement is Dictionary and String((raw_placement as Dictionary).get("type", "")) == "module_place_player_start":
			player_placements.append(raw_placement as Dictionary)
	_expect(
		player_placements.size() == 1
		and _coord_matches(player_placements[0].get("cell", {}), Vector2i(5, 5)),
		"corner start should place the player exactly at local cell 5,5"
	)
	var sockets: Dictionary = _derive_module_edge_sockets(
		start_template.get("terrain_rows", []) as Array
	)
	_expect(
		sockets.get("edge_north", []) == [5.0]
		and sockets.get("edge_east", []) == [5.0]
		and (sockets.get("edge_west", []) as Array).is_empty()
		and (sockets.get("edge_south", []) as Array).is_empty(),
		"corner start should expose only centered north and east sockets"
	)


func _expect_navigation_queries(manager_a: Node2D, manager_b: Node2D, manager_technical: Node2D) -> void:
	var target_position := Vector2(0.0, -800.0)
	var from_position := Vector2(-800.0, 0.0)
	manager_a.call("tick", target_position)
	manager_b.call("tick", target_position)
	var query_a: Dictionary = manager_a.call("navigation_query_to_active_target", from_position)
	var query_b: Dictionary = manager_b.call("navigation_query_to_active_target", from_position)
	var navigation_summary: Dictionary = (manager_a.call("debug_summary") as Dictionary).get("navigation", {}) as Dictionary
	_expect(int(navigation_summary.get("flow_radius_cells", 0)) == NAVIGATION_FLOW_RADIUS_CELLS, "active flow radius should derive to eight cells for current perception data")
	_expect(int(navigation_summary.get("flow_cell_capacity", 0)) == 289, "radius-eight active flow should have a 17 x 17 maximum window")
	_expect(int(navigation_summary.get("last_rebuild_visited_count", 0)) <= 289, "active flow rebuild should visit at most 289 cells")
	_expect(bool(query_a.get("reachable", false)), "shared flow field should route between reachable start-module arms")
	_expect(query_a == query_b, "same terrain and active target should produce an identical deterministic flow query")
	_expect(
		float(query_a.get("distance", 0.0)) > from_position.distance_to(target_position),
		"route distance should exceed straight-line distance when blocked cells force a detour"
	)
	_expect(
		not bool(manager_a.call("has_terrain_line_of_sight", from_position, target_position)),
		"supercover terrain sight should reject a diagonal crossing blocked cells"
	)
	_expect(
		(query_a.get("next_position", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(-640.0, 0.0)),
		"flow field should choose the legal corridor instead of moving straight through blocked terrain"
	)
	var local_query: Dictionary = manager_a.call("navigation_query", from_position, target_position)
	_expect(bool(local_query.get("reachable", false)), "local AStar query should reuse the same reachable static terrain mask")
	_expect(
		float(local_query.get("distance", 0.0)) > from_position.distance_to(target_position),
		"local AStar query should report route distance rather than straight-line distance"
	)
	var before_summary: Dictionary = manager_a.call("debug_summary")
	var before_navigation: Dictionary = before_summary.get("navigation", {}) as Dictionary
	manager_a.call("tick", target_position + Vector2(10.0, 0.0))
	var after_summary: Dictionary = manager_a.call("debug_summary")
	var after_navigation: Dictionary = after_summary.get("navigation", {}) as Dictionary
	_expect(
		int(before_navigation.get("flow_rebuild_count", -1)) == int(after_navigation.get("flow_rebuild_count", -2)),
		"moving the exact player target inside one global cell should not rebuild the shared flow field"
	)
	var exact_target_query: Dictionary = manager_a.call("navigation_query_to_active_target", from_position)
	_expect(
		(exact_target_query.get("target_position", Vector2.ZERO) as Vector2).is_equal_approx(target_position + Vector2(10.0, 0.0)),
		"active navigation query should retain the player's exact position inside the target cell"
	)
	_expect(
		not bool(manager_a.call("navigation_query", from_position, Vector2(-320.0, -160.0)).get("reachable", true)),
		"blocked targets should be unreachable"
	)
	_expect(
		not bool(manager_a.call("navigation_query", from_position, Vector2(-99_999.0, 0.0)).get("reachable", true)),
		"out-of-bounds targets should be unreachable"
	)
	_expect(
		not bool(manager_technical.call(
			"navigation_query",
			Vector2.ZERO,
			manager_technical.call("global_cell_to_world", Vector2i(0, 0))
		).get("reachable", true)),
		"technical-slice navigation should not enter its sealed outer modules"
	)

	var corner_mask := PackedByteArray([1, 0, 0, 1])
	var corner_field: RefCounted = MODULE_NAVIGATION_FIELD_SCRIPT.new()
	_expect(
		bool(corner_field.call("configure", corner_mask, 2, 2, 160.0, Vector2.ZERO, Vector2i.ZERO, 1)),
		"isolated corner navigation field should configure"
	)
	corner_field.call("set_active_target", Vector2(160.0, 160.0))
	_expect(
		not bool(corner_field.call("query_to_active_target", Vector2.ZERO).get("reachable", true)),
		"eight-way navigation should reject diagonal corner cutting when both orthogonal cells are blocked"
	)
	_expect_bounded_flow_rebuilds()


func _expect_objective_candidate_seed_coverage(data: Dictionary) -> void:
	var expected: Dictionary = {
		Vector2i(0, 0): true,
		Vector2i(6, 0): true,
		Vector2i(6, 6): true,
	}
	var observed: Dictionary = {}
	for run_seed: int in range(64):
		var manager: Node2D = MODULE_WORLD_MANAGER_SCENE.instantiate() as Node2D
		add_child(manager)
		var configured: bool = bool(manager.call(
			"configure",
			data["world"],
			data["registry"],
			data["templates"],
			data["generated"],
			run_seed,
			NAVIGATION_FLOW_RADIUS_CELLS
		))
		_expect(configured, "objective candidate coverage seed %d should configure" % run_seed)
		if configured:
			var objective_coord: Vector2i = manager.call(
				"role_module_coord",
				MODULE_ROLES.MODULE_ROLE_OBJECTIVE
			) as Vector2i
			_expect(expected.has(objective_coord), "objective should only use a configured corner candidate")
			var objective_count: int = 0
			for raw_entry: Variant in (manager.call("assignment") as Dictionary).values():
				if not raw_entry is Dictionary:
					continue
				var template_id: String = String((raw_entry as Dictionary).get("template_id", ""))
				var registry_entry: Dictionary = (data["registry"] as Dictionary).get(template_id, {}) as Dictionary
				if String(registry_entry.get("role", "")) == MODULE_ROLES.MODULE_ROLE_OBJECTIVE:
					objective_count += 1
			_expect(objective_count == 1, "each seeded assignment should contain exactly one objective")
			observed[objective_coord] = true
		manager.free()
		if observed.size() == expected.size():
			break
	_expect(observed.size() == expected.size(), "fixed seed coverage should reach all three objective corner candidates")


func _expect_bounded_flow_rebuilds() -> void:
	var full_mask := PackedByteArray()
	full_mask.resize(77 * 77)
	full_mask.fill(1)
	var field: RefCounted = MODULE_NAVIGATION_FIELD_SCRIPT.new()
	_expect(
		bool(field.call("configure", full_mask, 77, 77, 160.0, Vector2.ZERO, Vector2i(38, 38), NAVIGATION_FLOW_RADIUS_CELLS)),
		"bounded-flow navigation field should configure"
	)
	var all_rebuilds_bounded: bool = true
	for column: int in range(19, 39):
		field.call("set_active_target", field.call("cell_to_world", Vector2i(column, 38)))
		var summary: Dictionary = field.call("debug_summary")
		all_rebuilds_bounded = (
			all_rebuilds_bounded
			and int(summary.get("last_rebuild_visited_count", 0)) == 289
			and int(summary.get("flow_bound_cell_count", 0)) == 289
		)
	_expect(all_rebuilds_bounded, "twenty open-grid cell crossings should each remain at the 289-cell bound")
	var final_summary: Dictionary = field.call("debug_summary")
	_expect(int(final_summary.get("flow_rebuild_count", 0)) == 20, "twenty target-cell crossings should rebuild exactly twenty local fields")
	var outside_position: Vector2 = field.call("cell_to_world", Vector2i(47, 38))
	var target_position: Vector2 = field.call("cell_to_world", Vector2i(38, 38))
	_expect(
		not bool(field.call("query_to_active_target", outside_position).get("reachable", true)),
		"active flow query should be unreachable beyond the local radius"
	)
	_expect(
		bool(field.call("query", outside_position, target_position).get("reachable", false)),
		"full-world AStar should remain reachable for the same positions"
	)


func _expect_seamless_streaming(run_loop: Node) -> void:
	var technical_slice: bool = OS.get_cmdline_user_args().has("--module-world-technical-slice")
	var before: Dictionary = run_loop.call("debug_summary")
	var difficulty_at_start: Dictionary = run_loop.call(
		"debug_difficulty_snapshot"
	)
	var before_hash: String = String((before.get("module_world", {}) as Dictionary).get("map_hash", ""))
	var manager: Node = _find_node_by_name(get_tree().root, "ModuleWorldManager")
	_expect(manager != null, "module world manager should remain available during streaming")
	if manager == null:
		return
	var start_coord: Vector2i = manager.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_START) as Vector2i
	var encounter_coord: Vector2i = start_coord + Vector2i.RIGHT
	var encounter_slot_key: String = "%d,%d" % [encounter_coord.x, encounter_coord.y]
	var start_center_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(start_coord.x * 11 + 5, start_coord.y * 11 + 5)
	) as Vector2
	var start_west_floor_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(start_coord.x * 11 + 1, start_coord.y * 11 + 5)
	) as Vector2
	var start_west_wall_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(start_coord.x * 11, start_coord.y * 11 + 5)
	) as Vector2
	var start_east_door_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(start_coord.x * 11 + 10, start_coord.y * 11 + 5)
	) as Vector2
	var encounter_center_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(encounter_coord.x * 11 + 5, encounter_coord.y * 11 + 5)
	) as Vector2
	if technical_slice:
		start_west_floor_position = Vector2(-160.0, -160.0)
		start_west_wall_position = Vector2(-320.0, -160.0)
	var far_position := Vector2(-1760.0, 0.0) if technical_slice else Vector2.ZERO
	if manager != null:
		for active_coord: Vector2i in manager.call("active_module_coords"):
			var initial_slot_state: Dictionary = manager.call("slot_state", active_coord)
			_expect(
				not initial_slot_state.get("enemy_encounter") is Dictionary,
				"initial 3x3 streaming activation must not prepare neighboring encounters"
			)
		var initial_encounter_vfx: Dictionary = run_loop.get("_module_encounter_vfx")
		_expect(
			initial_encounter_vfx.is_empty(),
			"initial 3x3 streaming activation must not show neighboring telegraphs"
		)
		_expect(
			get_tree().get_nodes_in_group("active_enemies").is_empty(),
			"initial 3x3 streaming activation must not spawn neighboring enemies"
		)
		_expect(bool(manager.call("is_world_position_walkable", start_west_floor_position)), "known start-room floor cell should be walkable")
		_expect(not bool(manager.call("is_world_position_walkable", start_west_wall_position)), "known start-room west wall cell should not be walkable")
		for active_enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
			if active_enemy is Node2D and not String(active_enemy.get_meta("module_slot", "")).is_empty():
				_expect(
					bool(manager.call("is_world_position_walkable", (active_enemy as Node2D).global_position)),
					"module enemy should remain on floor terrain"
				)
	var blocked_spawned: bool = bool(run_loop.call(
		"_spawn_enemy_at",
		"enemy_chaser",
		start_west_wall_position,
		"module_blocked_spawn_test",
		encounter_slot_key
	))
	_expect(not blocked_spawned, "runtime should reject an enemy spawn on blocked module terrain")
	run_loop.call("_restore_enemy_snapshots", [{
		"enemy_id": "enemy_chaser",
		"module_slot": encounter_slot_key,
		"position": _vector_to_dict(start_west_wall_position),
		"wave_key": "module_blocked_restore_test",
	}])
	_expect(
		_find_active_enemy_by_wave_key("module_blocked_restore_test") == null,
		"runtime should reject an enemy snapshot restored on blocked module terrain"
	)


func _expect_gear_mod_cage_behavior(run_loop: Node) -> void:
	print("[ModuleWorldSmoke] stage=cage_setup")
	var manager: Node = _find_node_by_name(
		get_tree().root,
		"ModuleWorldManager"
	)
	var cage_player: Node2D = _find_node_by_name(
		get_tree().root,
		"Player"
	) as Node2D
	var board: RefCounted = run_loop.get("_gear_mod_board") as RefCounted
	_expect(
		manager != null and cage_player != null and board != null,
		"cage behavior smoke should have manager, player, and Gear Mod board"
	)
	if manager == null or cage_player == null or board == null:
		return
	var technical_slice: bool = OS.get_cmdline_user_args().has(
		"--module-world-technical-slice"
	)
	var before: Dictionary = run_loop.call("debug_summary") as Dictionary
	var difficulty_at_start: Dictionary = run_loop.call(
		"debug_difficulty_snapshot"
	) as Dictionary
	var before_hash: String = String(
		(before.get("module_world", {}) as Dictionary).get("map_hash", "")
	)
	var start_coord: Vector2i = manager.call(
		"role_module_coord",
		MODULE_ROLES.MODULE_ROLE_START
	) as Vector2i
	var encounter_coord: Vector2i = start_coord + Vector2i.RIGHT
	var encounter_slot_key: String = "%d,%d" % [
		encounter_coord.x,
		encounter_coord.y,
	]
	var start_center_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(start_coord.x * 11 + 5, start_coord.y * 11 + 5)
	) as Vector2
	var start_west_floor_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(start_coord.x * 11 + 1, start_coord.y * 11 + 5)
	) as Vector2
	var start_west_wall_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(start_coord.x * 11, start_coord.y * 11 + 5)
	) as Vector2
	var start_east_door_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(start_coord.x * 11 + 10, start_coord.y * 11 + 5)
	) as Vector2
	var encounter_center_position: Vector2 = manager.call(
		"global_cell_to_world",
		Vector2i(encounter_coord.x * 11 + 5, encounter_coord.y * 11 + 5)
	) as Vector2
	if technical_slice:
		start_west_floor_position = Vector2(-160.0, -160.0)
		start_west_wall_position = Vector2(-320.0, -160.0)
	var far_position := (
		Vector2(-1760.0, 0.0) if technical_slice else Vector2.ZERO
	)
	var original_player_position: Vector2 = cage_player.global_position
	var cage_coord := Vector2i(3, 2)
	var legal_cells: Array[Vector2i] = board.call(
		"legal_cells",
		GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE
	) as Array[Vector2i]
	_expect(
		legal_cells.has(cage_coord),
		"the cage should be placeable in the unlocked cell above the core"
	)
	if not legal_cells.has(cage_coord):
		return
	var cage_instance_id: int = int(run_loop.call(
		"_allocate_gear_mod_instance_id"
	))
	var placement_result: Dictionary = board.call(
		"request_placement",
		cage_instance_id,
		GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE,
		cage_coord
	) as Dictionary
	_expect(
		bool(placement_result.get("ok", false)),
		"cage smoke fixture should create one map placement without an entity"
	)
	if not bool(placement_result.get("ok", false)):
		return
	var other_cage_coord := Vector2i(2, 3)
	var other_legal_cells: Array[Vector2i] = board.call(
		"legal_cells",
		GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE
	) as Array[Vector2i]
	_expect(
		other_legal_cells.has(other_cage_coord),
		"a second cage should be independently placeable beside the core"
	)
	if not other_legal_cells.has(other_cage_coord):
		return
	var other_cage_instance_id: int = int(run_loop.call(
		"_allocate_gear_mod_instance_id"
	))
	var other_placement_result: Dictionary = board.call(
		"request_placement",
		other_cage_instance_id,
		GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE,
		other_cage_coord
	) as Dictionary
	_expect(
		bool(other_placement_result.get("ok", false)),
		"cage smoke fixture should create a second independent map placement"
	)
	if not bool(other_placement_result.get("ok", false)):
		return
	run_loop.call("_sync_run_gear_mod_ids_from_board")
	var cage_floor_positions: Array[Vector2] = manager.call(
		"empty_floor_positions_at",
		cage_coord
	) as Array[Vector2]
	_expect(
		not cage_floor_positions.is_empty(),
		"cage module should expose at least one static empty floor position"
	)
	if cage_floor_positions.is_empty():
		return
	run_loop.call("debug_set_player_position", cage_floor_positions[0])
	await _wait_frames(BOOT_FRAMES)
	print("[ModuleWorldSmoke] stage=cage_plan")
	run_loop.call("debug_clear_enemies")
	var locked_plan: Dictionary = run_loop.call(
		"_build_gear_mod_cage_spawn_plan",
		cage_coord
	) as Dictionary
	_expect(
		not locked_plan.is_empty(),
		"cage should build a plan from the current module enemy pool and empty floors"
	)
	if locked_plan.is_empty():
		return
	var raw_planned_position: Variant = locked_plan.get("position", {})
	var planned_position: Vector2 = (
		raw_planned_position as Vector2
		if raw_planned_position is Vector2
		else _dict_to_vector(raw_planned_position)
	)
	var player_cell: Vector2i = manager.call(
		"world_to_global_cell",
		cage_player.global_position
	) as Vector2i
	var planned_cell: Vector2i = manager.call(
		"world_to_global_cell",
		planned_position
	) as Vector2i
	_expect(
		planned_cell != player_cell,
		"cage plan generation should exclude the player-occupied floor cell"
	)

	var old_time_scale: float = GameClock.time_scale()
	GameClock.set_time_scale(0.5)
	board.call(
		"set_map_behavior_state",
		cage_instance_id,
		{"elapsed": 1.0, "pending_plan": {}}
	)
	board.call(
		"set_map_behavior_state",
		other_cage_instance_id,
		{"elapsed": 4.0, "pending_plan": {}}
	)
	run_loop.call("debug_tick_gear_mod_map_behaviors", 0.5)
	var scaled_state: Dictionary = board.call(
		"map_behavior_state",
		cage_instance_id
	) as Dictionary
	var other_scaled_state: Dictionary = board.call(
		"map_behavior_state",
		other_cage_instance_id
	) as Dictionary
	_expect(
		is_equal_approx(float(scaled_state.get("elapsed", 0.0)), 1.25)
		and is_equal_approx(
			float(other_scaled_state.get("elapsed", -1.0)),
			0.0
		),
		"only the cage under the player should advance while another instance resets independently"
	)
	GameClock.set_time_scale(old_time_scale)

	board.call(
		"set_map_behavior_state",
		cage_instance_id,
		{"elapsed": 10.0, "pending_plan": locked_plan}
	)
	locked_plan = (
		board.call("map_behavior_state", cage_instance_id) as Dictionary
	).get("pending_plan", {}) as Dictionary
	var board_snapshot: Dictionary = board.call("snapshot") as Dictionary
	board.call(
		"set_map_behavior_state",
		cage_instance_id,
		{"elapsed": 0.0, "pending_plan": {}}
	)
	var restored_board_state: bool = bool(board.call(
		"restore_snapshot",
		board_snapshot
	))
	_expect(
		restored_board_state
		and (
			board.call("map_behavior_state", cage_instance_id) as Dictionary
		).get("pending_plan", {}) == locked_plan,
		"board snapshot restore should preserve the cage locked plan"
	)
	var valid_plan_snapshot: Dictionary = run_loop.call(
		"create_run_snapshot"
	) as Dictionary
	var unknown_enemy_snapshot: Dictionary = valid_plan_snapshot.duplicate(true)
	var unknown_enemy_states: Array = (
		(unknown_enemy_snapshot.get("gear_mods", {}) as Dictionary).get(
			"map_behavior_states",
			[]
		) as Array
	)
	(
		(unknown_enemy_states[0] as Dictionary).get(
			"pending_plan",
			{}
		) as Dictionary
	)["enemy_id"] = "missing_enemy"
	var wrong_module_position_snapshot: Dictionary = (
		valid_plan_snapshot.duplicate(true)
	)
	var wrong_position_states: Array = (
		(
			wrong_module_position_snapshot.get(
				"gear_mods",
				{}
			) as Dictionary
		).get("map_behavior_states", []) as Array
	)
	(
		(wrong_position_states[0] as Dictionary).get(
			"pending_plan",
			{}
		) as Dictionary
	)["position"] = _vector_to_dict(original_player_position)
	_expect(
		bool(run_loop.call(
			"_validate_run_gear_mod_map_behavior_plans",
			valid_plan_snapshot
		))
		and not bool(run_loop.call(
			"_validate_run_gear_mod_map_behavior_plans",
			unknown_enemy_snapshot
		))
		and not bool(run_loop.call(
			"_validate_run_gear_mod_map_behavior_plans",
			wrong_module_position_snapshot
		)),
		"run restore validation should reject cage plans with an unavailable enemy or a position outside the cage module"
	)
	var enemy_id: String = String(locked_plan.get("enemy_id", ""))
	var cage_enemy_rows: Dictionary = run_loop.get("_enemy_rows") as Dictionary
	var saved_enemy_row: Dictionary = (
		cage_enemy_rows.get(enemy_id, {}) as Dictionary
	).duplicate(true)
	cage_enemy_rows.erase(enemy_id)
	run_loop.set("_enemy_rows", cage_enemy_rows)
	var rng_before_failed_spawn: Dictionary = RNG.snapshot()
	run_loop.call("debug_tick_gear_mod_map_behaviors", 0.0)
	print("[ModuleWorldSmoke] stage=cage_failed_retry")
	var failed_state: Dictionary = board.call(
		"map_behavior_state",
		cage_instance_id
	) as Dictionary
	_expect(
		failed_state.get("pending_plan", {}) == locked_plan
		and RNG.snapshot() == rng_before_failed_spawn,
		"failed cage spawn should retain its exact plan without consuming RNG for a reroll"
	)
	cage_enemy_rows[enemy_id] = saved_enemy_row
	run_loop.set("_enemy_rows", cage_enemy_rows)
	run_loop.call("debug_tick_gear_mod_map_behaviors", 0.0)
	print("[ModuleWorldSmoke] stage=cage_spawned")
	var success_state: Dictionary = board.call(
		"map_behavior_state",
		cage_instance_id
	) as Dictionary
	var spawned_enemy: Node2D = _find_active_entity_at(
		"active_enemies",
		planned_position
	)
	var spawned_enemy_snapshot: Dictionary = (
		spawned_enemy.call("snapshot") as Dictionary
		if spawned_enemy != null and spawned_enemy.has_method("snapshot")
		else {}
	)
	_expect(
		spawned_enemy != null
		and String(spawned_enemy.get_meta("module_slot", ""))
		== "%d,%d" % [cage_coord.x, cage_coord.y]
		and bool(
			(spawned_enemy_snapshot.get("reward_snapshot", {}) as Dictionary).get(
				"valid",
				false
			)
		)
		and is_equal_approx(float(success_state.get("elapsed", -1.0)), 0.0)
		and (success_state.get("pending_plan", {}) as Dictionary).is_empty(),
		"successful cage spawn should use normal rewards, bind to the module slot, and reset its timer: enemy=%s slot=%s reward=%s state=%s"
		% [
			str(spawned_enemy),
			String(
				spawned_enemy.get_meta("module_slot", "")
				if spawned_enemy != null
				else ""
			),
			str(spawned_enemy_snapshot.get("reward_snapshot", {})),
			str(success_state),
		]
	)

	board.call(
		"set_map_behavior_state",
		cage_instance_id,
		{"elapsed": 5.0, "pending_plan": locked_plan}
	)
	var away_positions: Array[Vector2] = manager.call(
		"empty_floor_positions_at",
		Vector2i(3, 3)
	) as Array[Vector2]
	if not away_positions.is_empty():
		run_loop.call("debug_set_player_position", away_positions[0])
		run_loop.call("debug_module_world_tick")
		run_loop.call("debug_tick_gear_mod_map_behaviors", 0.0)
	var left_state: Dictionary = board.call(
		"map_behavior_state",
		cage_instance_id
	) as Dictionary
	_expect(
		is_equal_approx(float(left_state.get("elapsed", -1.0)), 0.0)
		and (left_state.get("pending_plan", {}) as Dictionary).is_empty(),
		"leaving the cage module should clear elapsed time and its pending plan"
	)
	run_loop.call("debug_clear_enemies")
	run_loop.call("debug_set_player_position", original_player_position)
	await _wait_frames(BOOT_FRAMES)
	print("[ModuleWorldSmoke] stage=streaming_continuation")
	# The lower-left start room has a floor cell beside its solid west wall.
	run_loop.call("debug_set_player_position", start_west_floor_position)
	await get_tree().physics_frame
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.LEFT)
	for _physics_tick: int in range(45):
		await get_tree().physics_frame
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.ZERO)
	InputService.set_playback_active(false)
	var wall_test_player: Node = _find_node_by_name(get_tree().root, "Player")
	_expect(
		wall_test_player is Node2D and (wall_test_player as Node2D).global_position.x > (start_west_floor_position.x + start_west_wall_position.x) * 0.5,
		"player physics body should not enter a blocked module cell"
	)
	var debug_spawn: Dictionary = run_loop.call("debug_spawn_enemy", "enemy_chaser", 1)
	_expect(bool(debug_spawn.get("ok", false)), "enemy wall test should spawn a chaser")
	var wall_test_enemy: Node2D = _find_active_enemy_by_wave_key("debug_enemy_chaser")
	_expect(wall_test_enemy != null, "enemy wall test should find its spawned chaser")
	if wall_test_enemy != null:
		run_loop.call("debug_set_player_position", start_west_wall_position)
		wall_test_enemy.global_position = start_west_floor_position
		await get_tree().physics_frame
		for _physics_tick: int in range(120):
			await get_tree().physics_frame
		_expect(wall_test_enemy.global_position.x > (start_west_floor_position.x + start_west_wall_position.x) * 0.5, "enemy physics body should not enter a blocked module cell")
		PoolManager.release(wall_test_enemy)
	await _expect_bullet_terrain_rules(run_loop, start_west_floor_position, start_west_wall_position)
	# Start inside the lower-left room's east doorway and cross the shared seam using
	# normal CharacterBody2D movement so a bad collision merge cannot hide behind a teleport.
	run_loop.call("debug_set_player_position", start_east_door_position)
	var weapon_acquired_before_exit: int = int(
		PoolManager.stats(POOL_IDS.BULLET_BASIC).get("acquired", 0)
	)
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.RIGHT)
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	for _physics_tick: int in range(90):
		await get_tree().physics_frame
		var player: Node = _find_node_by_name(get_tree().root, "Player")
		if player is Node2D and (player as Node2D).global_position.x > start_east_door_position.x + 100.0:
			break
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.ZERO)
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	InputService.set_playback_active(false)
	await _wait_frames(BOOT_FRAMES)
	var crossed: Dictionary = run_loop.call("debug_summary")
	var crossed_world: Dictionary = crossed.get("module_world", {}) as Dictionary
	_expect(_coord_matches(crossed_world.get("current_module", {}), encounter_coord), "crossing the shared edge should enter the adjacent module without scene switch")
	var crossed_player: Node = _find_node_by_name(get_tree().root, "Player")
	_expect(crossed_player is Node2D and (crossed_player as Node2D).global_position.x > start_east_door_position.x + 100.0, "player physics body should pass through the shared module doorway")
	var difficulty_after_exit: Dictionary = run_loop.call(
		"debug_difficulty_snapshot"
	)
	_expect(
		float(difficulty_after_exit.get("elapsed", 0.0))
		> float(difficulty_at_start.get("elapsed", 0.0)),
		"difficulty time should advance immediately after leaving the start module"
	)
	_expect(
		int(PoolManager.stats(POOL_IDS.BULLET_BASIC).get("acquired", 0))
		> weapon_acquired_before_exit,
		"held fire should shoot immediately after leaving the start module"
	)
	_release_active_bullets()
	_expect(int(crossed_world.get("active_count", 0)) <= 9, "edge crossing should keep at most nine active chunks")
	_expect(int(crossed_world.get("visited_count", 0)) >= 2, "entering an adjacent module should reveal fog state")
	_expect(String(crossed_world.get("map_hash", "")) == before_hash, "streaming should not mutate map hash")
	var encounter_slot_state: Dictionary = manager.call(
		"slot_state",
		encounter_coord
	)
	var encounter: Dictionary = encounter_slot_state.get(
		"enemy_encounter",
		{}
	) as Dictionary
	var spawn_plan: Array = encounter.get("spawns", []) as Array
	_expect(
		String(encounter.get("state", "")) == "telegraphing",
		"first entry should immediately persist a telegraphing encounter"
	)
	_expect(
		spawn_plan.size() >= 4 and spawn_plan.size() <= 6,
		"first entry should choose four to six spawn positions"
	)
	_expect(
		_active_module_entity_count("active_enemies", encounter_slot_key) == 0,
		"stream activation and the telegraph window must not spawn enemies early"
	)
	var spawn_position_keys: Dictionary = {}
	var selected_spawn_position: Vector2 = Vector2.ZERO
	for raw_spawn: Variant in spawn_plan:
		if not raw_spawn is Dictionary:
			continue
		var spawn: Dictionary = raw_spawn as Dictionary
		var spawn_position: Vector2 = _dict_to_vector(
			spawn.get("world_position", {})
		)
		if selected_spawn_position == Vector2.ZERO:
			selected_spawn_position = spawn_position
		spawn_position_keys[_vector_key(spawn_position)] = true
		_expect(
			bool(manager.call("is_world_position_walkable", spawn_position)),
			"telegraphed enemy position should be effective floor terrain"
		)
	_expect(
		spawn_position_keys.size() == spawn_plan.size(),
		"first-visit spawn positions should be unique"
	)
	var encounter_vfx: Dictionary = run_loop.get("_module_encounter_vfx")
	_expect(
		(encounter_vfx.get(encounter_slot_key, []) as Array).size() == spawn_plan.size(),
		"every planned enemy should show a ground telegraph"
	)
	var run_snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var saved_slot_states: Dictionary = (
		(run_snapshot.get("module_world", {}) as Dictionary).get(
			"slot_states",
			{}
		) as Dictionary
	)
	_expect(
		_saved_slot_has_encounter(saved_slot_states, encounter_slot_key, spawn_plan),
		"Run v18 snapshot should persist the fixed telegraph plan"
	)
	var remaining_before_pause: float = float(
		encounter.get("remaining_telegraph", 0.0)
	)
	GameState.change_state(GameState.PAUSED, {"source": "module_world_smoke"})
	await _wait_frames(8)
	var paused_encounter: Dictionary = (
		manager.call("slot_state", encounter_coord) as Dictionary
	).get("enemy_encounter", {}) as Dictionary
	_expect(
		is_equal_approx(
			float(paused_encounter.get("remaining_telegraph", 0.0)),
			remaining_before_pause
		),
		"pausing should freeze the encounter telegraph countdown"
	)
	GameState.change_state(GameState.PLAYING, {"source": "module_world_smoke"})
	run_loop.call("debug_set_player_position", far_position)
	await _wait_frames(BOOT_FRAMES)
	var unloaded_remaining: float = float(
		(
			(manager.call("slot_state", encounter_coord) as Dictionary).get(
				"enemy_encounter",
				{}
			) as Dictionary
		).get("remaining_telegraph", 0.0)
	)
	await _wait_frames(8)
	var frozen_remaining: float = float(
		(
			(manager.call("slot_state", encounter_coord) as Dictionary).get(
				"enemy_encounter",
				{}
			) as Dictionary
		).get("remaining_telegraph", 0.0)
	)
	_expect(
		is_equal_approx(unloaded_remaining, frozen_remaining),
		"an unloaded module should freeze its remaining telegraph time"
	)
	run_loop.call("debug_set_player_position", selected_spawn_position)
	await get_tree().process_frame
	var resumed_encounter: Dictionary = (
		manager.call("slot_state", encounter_coord) as Dictionary
	).get("enemy_encounter", {}) as Dictionary
	_expect(
		(resumed_encounter.get("spawns", []) as Array) == spawn_plan,
		"reactivating a telegraphing module must not reroll its spawn plan"
	)
	run_loop.call(
		"_update_module_encounters",
		float(resumed_encounter.get("remaining_telegraph", 0.0))
	)
	var spawned_encounter: Dictionary = (
		manager.call("slot_state", encounter_coord) as Dictionary
	).get("enemy_encounter", {}) as Dictionary
	var first_visit_enemy_count: int = _active_module_entity_count(
		"active_enemies",
		encounter_slot_key
	)
	_expect(
		String(spawned_encounter.get("state", "")) == "spawned"
		and first_visit_enemy_count == spawn_plan.size(),
		"telegraph completion should spawn the fixed plan simultaneously"
	)
	_expect(
		_has_active_module_enemy_at(encounter_slot_key, selected_spawn_position),
		"standing on a selected cell must not reroll or suppress that enemy spawn"
	)
	var existing_enemy: Node2D = _find_active_enemy_by_wave_key(
		"module_%d_%d" % [encounter_coord.x, encounter_coord.y]
	)
	var existing_spawn_difficulty: Dictionary = (
		existing_enemy.call("enemy_spawn_snapshot") as Dictionary
		if existing_enemy != null
		and existing_enemy.has_method("enemy_spawn_snapshot")
		else {}
	)
	var difficulty_progression: DifficultyProgression = run_loop.get(
		"_difficulty_progression"
	) as DifficultyProgression
	_expect(
		difficulty_progression != null,
		"module-world run should expose mode-level difficulty progression"
	)
	if difficulty_progression != null:
		difficulty_progression.advance(720.0)
	_expect(
		existing_enemy != null
		and (
			existing_enemy.call("enemy_spawn_snapshot") as Dictionary
		) == existing_spawn_difficulty,
		"existing enemies should keep their original spawn multipliers"
	)
	var scaled_spawned: bool = bool(
		run_loop.call(
			"_spawn_enemy_at",
			"enemy_chaser",
			selected_spawn_position,
			"module_scaled_spawn_test",
			encounter_slot_key
		)
	)
	var scaled_enemy: Node2D = _find_active_enemy_by_wave_key(
		"module_scaled_spawn_test"
	)
	var scaled_spawn_difficulty: Dictionary = (
		scaled_enemy.call("enemy_spawn_snapshot") as Dictionary
		if scaled_enemy != null
		and scaled_enemy.has_method("enemy_spawn_snapshot")
		else {}
	)
	_expect(
		scaled_spawned
		and float(
			scaled_spawn_difficulty.get("health_multiplier", 0.0)
		) >= 2.04
		and float(
			scaled_spawn_difficulty.get("damage_multiplier", 0.0)
		) >= 1.4992,
		"new enemies should snapshot the current health and damage multipliers"
	)
	if scaled_enemy != null:
		var enemy_rows: Dictionary = run_loop.get("_enemy_rows") as Dictionary
		var chaser_data: Dictionary = enemy_rows.get(
			"enemy_chaser",
			{}
		) as Dictionary
		_expect(
			is_equal_approx(
				float(scaled_enemy.get("_move_speed")),
				float(chaser_data.get("move_speed", -1.0))
			),
			"difficulty progression should not change enemy movement speed"
		)
	var bullet_position := encounter_center_position + Vector2(160.0, 320.0)
	var gold_orb_position := encounter_center_position + Vector2(320.0, 320.0)
	var gear_mod_pickup_position := (
		encounter_center_position + Vector2(240.0, 320.0)
	)
	run_loop.call("_restore_bullet_snapshots", [{
		"position": _vector_to_dict(bullet_position),
		"damage": 0.0,
		"element_id": "",
		"damage_target_groups": [],
		"hit_radius": 0.0,
		"remaining_life": 90.0,
		"max_range": 99999.0,
		"pierce_remaining": 0,
		"source_team": "",
		"target_team": "",
		"wall_pierce_enabled": true,
		"travelled": 0.0,
		"velocity": _vector_to_dict(Vector2.ZERO),
	}])
	run_loop.call("_restore_gold_orb_snapshots", [{
		"position": _vector_to_dict(gold_orb_position),
		"amount": 7,
		"pickup_speed": 0.0,
	}])
	var gear_mod_spawn_result: Dictionary = run_loop.call(
		"_spawn_gear_mod_pickup",
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		gear_mod_pickup_position
	) as Dictionary
	await _wait_frames(BOOT_FRAMES)
	_expect(_has_active_entity_at("active_bullets", bullet_position), "test projectile should be active in the adjacent module")
	_expect(_has_active_entity_at("active_gold_orbs", gold_orb_position), "test gold orb should be active in the adjacent module")
	_expect(
		bool(gear_mod_spawn_result.get("ok", false))
		and _has_active_entity_at(
			"active_gear_mod_pickups",
			gear_mod_pickup_position
		),
		"test Gear Mod pickup should be active in the adjacent module"
	)
	# Move far enough that the east-neighbor slot leaves the active 3x3 neighborhood.
	run_loop.call("debug_set_player_position", far_position)
	await _wait_frames(BOOT_FRAMES)
	_expect(not _has_active_entity_at("active_bullets", bullet_position), "deactivated module should release its projectile")
	_expect(not _has_active_entity_at("active_gold_orbs", gold_orb_position), "deactivated module should release its gold orb")
	_expect(
		not _has_active_entity_at(
			"active_gear_mod_pickups",
			gear_mod_pickup_position
		),
		"deactivated module should release its Gear Mod pickup"
	)
	var stored_state: Dictionary = manager.call("slot_state", encounter_coord) if manager != null else {}
	_expect((stored_state.get("bullet_snapshots", []) as Array).size() == 1, "deactivated slot should retain one projectile snapshot")
	var stored_bullets: Array = stored_state.get("bullet_snapshots", []) as Array
	_expect(
		stored_bullets.size() == 1 and bool((stored_bullets[0] as Dictionary).get("wall_pierce_enabled", false)),
		"deactivated slot should preserve the projectile wall-pierce snapshot"
	)
	_expect((stored_state.get("gold_orb_snapshots", []) as Array).size() == 1, "deactivated slot should retain one gold-orb snapshot")
	var stored_mod_pickups: Array = stored_state.get(
		"gear_mod_pickup_snapshots",
		[]
	) as Array
	_expect(
		stored_mod_pickups.size() == 1
		and String((stored_mod_pickups[0] as Dictionary).get("mod_id", ""))
		== GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		"deactivated slot should retain the exact Gear Mod pickup snapshot"
	)
	run_loop.call("debug_set_player_position", encounter_center_position)
	await _wait_frames(BOOT_FRAMES)
	_expect(
		_active_module_entity_count("active_enemies", encounter_slot_key)
		== first_visit_enemy_count + 1,
		"leave/return should restore slot state without duplicate enemies"
	)
	var restored_scaled_enemy: Node2D = _find_active_enemy_by_wave_key(
		"module_scaled_spawn_test"
	)
	_expect(
		restored_scaled_enemy != null
		and (
			restored_scaled_enemy.call(
				"enemy_spawn_snapshot"
			) as Dictionary
		) == scaled_spawn_difficulty,
		"module unload and reload should preserve exact enemy spawn multipliers"
	)
	_expect(_has_active_entity_at("active_bullets", bullet_position), "returning should restore the slot projectile")
	var restored_bullet: Node2D = _find_active_entity_at("active_bullets", bullet_position)
	_expect(
		restored_bullet != null
		and restored_bullet.has_method("snapshot")
		and bool((restored_bullet.call("snapshot") as Dictionary).get("wall_pierce_enabled", false)),
		"returning should restore the projectile wall-pierce snapshot"
	)
	_expect(_has_active_entity_at("active_gold_orbs", gold_orb_position), "returning should restore the slot gold orb")
	_expect(
		_has_active_entity_at(
			"active_gear_mod_pickups",
			gear_mod_pickup_position
		),
		"returning should restore the slot Gear Mod pickup"
	)
	var clear_result: Dictionary = run_loop.call("debug_clear_enemies")
	_expect(
		int(clear_result.get("count", 0)) >= first_visit_enemy_count,
		"encounter cleanup should remove the spawned first-visit enemies"
	)
	run_loop.call("debug_set_player_position", far_position)
	await _wait_frames(BOOT_FRAMES)
	run_loop.call("debug_set_player_position", encounter_center_position)
	await _wait_frames(BOOT_FRAMES)
	_expect(
		_active_module_entity_count("active_enemies", encounter_slot_key) == 0,
		"a cleared spawned encounter must not refresh when its module is revisited"
	)
	run_loop.call("debug_set_player_position", start_center_position)
	await _wait_frames(BOOT_FRAMES)
	var returned_elapsed: float = float(
		(
			run_loop.call("debug_difficulty_snapshot") as Dictionary
		).get("elapsed", -1.0)
	)
	await _wait_frames(8)
	_expect(
		is_equal_approx(
			float(
				(
					run_loop.call(
						"debug_difficulty_snapshot"
					) as Dictionary
				).get("elapsed", -2.0)
			),
			returned_elapsed
		),
		"returning to the start module should pause difficulty time again"
	)


func _expect_objective_completion_and_restore(run_loop: Node) -> void:
	var technical_slice: bool = OS.get_cmdline_user_args().has("--module-world-technical-slice")
	var event_nodes: Dictionary = run_loop.get("_world_event_nodes") as Dictionary
	var event_controller: Node = run_loop.get("_world_event_controller") as Node
	var active_event_instance_id: String = ""
	var event_instance_ids: Array[String] = []
	for raw_instance_id: Variant in event_nodes.keys():
		event_instance_ids.append(String(raw_instance_id))
	event_instance_ids.sort()
	for instance_id: String in event_instance_ids:
		var event_node: Node = event_nodes.get(instance_id) as Node
		if event_node == null or not event_node.has_method("event_id"):
			continue
		var definition: Dictionary = event_controller.call(
			"definition",
			String(event_node.call("event_id"))
		) as Dictionary
		var kind: String = String(definition.get("kind", ""))
		if kind not in [
			"world_event_kind_defense",
			"world_event_kind_survival",
			"world_event_kind_capture",
		]:
			continue
		active_event_instance_id = instance_id
		run_loop.call(
			"debug_set_player_position",
			(event_node as Node2D).global_position
		)
		await _wait_frames(BOOT_FRAMES)
		var interaction: Dictionary = run_loop.call(
			"debug_interact_world_event",
			instance_id
		) as Dictionary
		_expect(
			bool(interaction.get("accepted", false)),
			"a selected continuous world event should activate"
		)
		await _wait_frames(8)
		break
	_expect(
		not active_event_instance_id.is_empty(),
		"every three-event selection should include a continuous event"
	)
	var objective_manager: Node = _find_node_by_name(
		get_tree().root,
		"ModuleWorldManager"
	)
	var objective_coord: Vector2i = objective_manager.call(
		"role_module_coord",
		MODULE_ROLES.MODULE_ROLE_OBJECTIVE
	) as Vector2i
	var objective_position: Vector2 = objective_manager.call(
		"global_cell_to_world",
		Vector2i(objective_coord.x * 11 + 5, objective_coord.y * 11 + 5)
	) as Vector2
	run_loop.call("debug_set_player_position", objective_position)
	await _wait_frames(BOOT_FRAMES * 2)
	var objective_id: String = "module_%d_%d_objective_5_5" % [objective_coord.x, objective_coord.y]
	var objective_encounter: Dictionary = (
		(objective_manager.call("slot_state", objective_coord) as Dictionary).get(
			"enemy_encounter",
			{}
		) as Dictionary
	)
	var objective_spawn_plan: Array = objective_encounter.get(
		"spawns",
		[]
	) as Array
	_expect(
		String(objective_encounter.get("state", "")) == "telegraphing"
		and not objective_spawn_plan.is_empty(),
		"objective first-entry encounter should still be telegraphing before save"
	)
	var saved_world_event_summary: Dictionary = (
		run_loop.call("debug_world_event_summary") as Dictionary
	)
	var saved_active_event: Dictionary = _world_event_instance_summary(
		saved_world_event_summary,
		active_event_instance_id
	)
	_expect(
		String(
			saved_world_event_summary.get(
				"active_continuous_instance_id",
				""
			)
		) == active_event_instance_id
		and String(saved_active_event.get("state", "")) == "world_event_state_active"
		and bool(saved_active_event.get("pinned", false))
		and int(saved_active_event.get("wave_cursor", 0)) >= 1
		and float(saved_active_event.get("elapsed", 0.0)) > 0.0,
		"active world event should retain progress, first wave cursor, and background pin"
	)

	# Save before completing the objective. Restore must recreate its live target and
	# preserve the same first-entry telegraph plan.
	run_loop.call("_show_pause_menu")
	await _wait_frames(2)
	_expect(
		GameState.is_state(GameState.PAUSED),
		"Run v18 difficulty roundtrip fixture should save from a frozen UI state"
	)
	var snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var saved_difficulty: Dictionary = run_loop.call(
		"debug_difficulty_snapshot"
	) as Dictionary
	_expect(int(snapshot.get("schema_version", 0)) == 18, "module run snapshot should use schema v18")
	_expect(SaveManager.save(SMOKE_SLOT, SAVE_KINDS.RUN, snapshot), "module run v18 should save")
	var loaded: Dictionary = SaveManager.load(SMOKE_SLOT, SAVE_KINDS.RUN)
	_expect(not loaded.is_empty(), "module run v18 should load")
	if loaded.is_empty():
		return
	var saved_hash: String = String((snapshot.get("module_world", {}) as Dictionary).get("map_hash", ""))
	var parent_boot: Node = get_parent()
	var previous_run_instance_id: int = run_loop.get_instance_id()
	parent_boot.call("_start_gameplay_run", loaded)
	var restored: Node = await _wait_for_replacement_run_loop(
		previous_run_instance_id
	)
	_expect(restored != null, "saved module world should restore into a playable run")
	if restored == null:
		return
	var restored_summary: Dictionary = restored.call("debug_summary")
	var restored_difficulty: Dictionary = restored.call(
		"debug_difficulty_snapshot"
	) as Dictionary
	var restored_world_event_summary: Dictionary = (
		restored.call("debug_world_event_summary") as Dictionary
	)
	var restored_active_event: Dictionary = _world_event_instance_summary(
		restored_world_event_summary,
		active_event_instance_id
	)
	_expect(
		String(
			restored_world_event_summary.get(
				"active_continuous_instance_id",
				""
			)
		) == active_event_instance_id
		and String(restored_active_event.get("state", ""))
		== "world_event_state_active"
		and bool(restored_active_event.get("pinned", false))
		and int(restored_active_event.get("wave_cursor", -1))
		== int(saved_active_event.get("wave_cursor", -2))
		and is_equal_approx(
			float(restored_active_event.get("elapsed", -1.0)),
			float(saved_active_event.get("elapsed", -2.0))
		)
		and int(
			restored_world_event_summary.get(
				"wave_plan_count",
				0
			)
		) >= 1,
		"Run v18 restore should preserve active event progress, pin, and fixed wave plan"
	)
	_expect(
		is_equal_approx(
			float(restored_difficulty.get("elapsed", -1.0)),
			float(saved_difficulty.get("elapsed", -2.0))
		)
		and int(restored_difficulty.get("difficulty_level", 0))
		== int(saved_difficulty.get("difficulty_level", -1))
		and is_equal_approx(
			float(restored_difficulty.get("health_multiplier", 0.0)),
			float(saved_difficulty.get("health_multiplier", -1.0))
		)
		and is_equal_approx(
			float(restored_difficulty.get("damage_multiplier", 0.0)),
			float(saved_difficulty.get("damage_multiplier", -1.0))
		),
		"Run v18 restore should preserve exact difficulty time, level, and multipliers"
	)
	restored.call("_on_pause_resume_requested")
	await _wait_frames(30)
	_expect(
		GameState.is_state(GameState.PLAYING),
		"restored paused Run v18 fixture should resume after difficulty comparison"
	)
	var restored_world: Dictionary = restored_summary.get("module_world", {}) as Dictionary
	_expect(String(restored_world.get("map_hash", "")) == saved_hash, "restore should validate and preserve map hash")
	if technical_slice:
		_expect(
			int(restored_world.get("active_count", 0)) == 9,
			"technical-slice restore should preload and mount all nine active generated scenes"
		)
	_expect(int(restored_world.get("visited_count", 0)) >= 2, "restore should preserve module fog/visited state")
	var restored_manager: Node = _find_node_by_name(
		get_tree().root,
		"ModuleWorldManager"
	)
	var restored_objective_encounter: Dictionary = (
		(restored_manager.call("slot_state", objective_coord) as Dictionary).get(
			"enemy_encounter",
			{}
		) as Dictionary
	)
	_expect(
		String(restored_objective_encounter.get("state", "")) == "telegraphing"
		and (
			restored_objective_encounter.get("spawns", []) as Array
		) == objective_spawn_plan
		and float(
			restored_objective_encounter.get("remaining_telegraph", 0.0)
		) > 0.0,
		"save restore should preserve a live telegraph plan and remaining time"
	)
	var restored_encounter_vfx: Dictionary = restored.get(
		"_module_encounter_vfx"
	)
	_expect(
		(
			restored_encounter_vfx.get(
				"%d,%d" % [objective_coord.x, objective_coord.y],
				[]
			) as Array
		).size() == objective_spawn_plan.size(),
		"save restore should rebuild every encounter telegraph VFX"
	)

	# A content/hash mismatch must stop before player and entity snapshots are
	# applied. FormalClientBoot consumes the false result via restore_failed and
	# returns to title; this direct assertion protects the run-loop fail-closed edge.
	var rejected_snapshot: Dictionary = restored.call("create_run_snapshot")
	var rejected_module_world: Dictionary = (rejected_snapshot.get("module_world", {}) as Dictionary).duplicate(true)
	rejected_module_world["map_hash"] = "f".repeat(64)
	rejected_snapshot["module_world"] = rejected_module_world
	var player: Node = _find_node_by_name(get_tree().root, "Player")
	var player_position_before: Vector2 = (player as Node2D).global_position if player is Node2D else Vector2.ZERO
	var rejected_player: Dictionary = (rejected_snapshot.get("player", {}) as Dictionary).duplicate(true)
	rejected_player["position"] = _vector_to_dict(Vector2(12345.0, 12345.0))
	rejected_snapshot["player"] = rejected_player
	_expect(not bool(restored.call("_restore_run_snapshot", rejected_snapshot)), "run-loop restore should reject mismatched module content/hash")
	_expect(player is Node2D and (player as Node2D).global_position.is_equal_approx(player_position_before), "rejected module restore must not apply the old player snapshot")

	var damage_result: Dictionary = restored.call(
		"debug_damage_interest_point_target",
		objective_id,
		99999.0
	)
	_expect(
		bool(damage_result.get("ok", false)),
		"module objective should use the existing damage primitive"
	)
	await _wait_frames(BOOT_FRAMES)
	var completed_summary: Dictionary = restored.call("debug_summary") as Dictionary
	var completed_points: Dictionary = (
		completed_summary.get("interest_points", {}) as Dictionary
	)
	var completed_objective: Dictionary = (
		completed_points.get(objective_id, {}) as Dictionary
	)
	_expect(
		bool(completed_objective.get("completes_run", false))
		and bool(completed_objective.get("claimed", false))
		and bool(completed_objective.get("target_destroyed", false)),
		"destroying the objective should claim the generic run-completion point"
	)
	_expect(
		GameState.is_state(GameState.GAME_OVER),
		"destroying the objective should complete the run directly"
	)


func _load_world_data() -> Dictionary:
	var worlds_payload: Dictionary = DataLoader.load_json(DataLoader.MODULE_WORLDS_PATH) as Dictionary
	var registry_payload: Dictionary = DataLoader.load_json(DataLoader.MODULE_TEMPLATES_PATH) as Dictionary
	var world: Dictionary = (worlds_payload.get("worlds", []) as Array)[0] as Dictionary
	var registry: Dictionary = {}
	var templates: Dictionary = {}
	var generated: Dictionary = {}
	for raw_entry: Variant in registry_payload.get("templates", []):
		var entry: Dictionary = raw_entry as Dictionary
		var template_id: String = String(entry.get("id", ""))
		registry[template_id] = entry.duplicate(true)
		templates[template_id] = _module_gameplay_projection(
			DataLoader.load_json(String(entry.get("path", ""))) as Dictionary
		)
		generated[template_id] = (
			"res://scenes/generated/modules/%s/rotation_0.tscn"
			% template_id
		)
	return {
		"world": world,
		"registry": registry,
		"templates": templates,
		"generated": generated,
	}


func _module_gameplay_projection(module_data: Dictionary) -> Dictionary:
	var terrain_rows: Array = (
		module_data.get("terrain_rows", []) as Array
	).duplicate(true)
	return {
		"schema_version": 1.0,
		"id": String(module_data.get("id", "")),
		"columns": 11.0,
		"rows": 11.0,
		"terrain_rows": terrain_rows,
		"edge_sockets": _derive_module_edge_sockets(terrain_rows),
		"placements": (
			module_data.get("placements", []) as Array
		).duplicate(true),
	}


func _derive_module_edge_sockets(terrain_rows: Array) -> Dictionary:
	var result: Dictionary = {
		"edge_north": [],
		"edge_south": [],
		"edge_east": [],
		"edge_west": [],
	}
	for index: int in range(11):
		if String((terrain_rows[0] as Array)[index]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result["edge_north"] as Array).append(float(index))
		if String((terrain_rows[10] as Array)[index]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result["edge_south"] as Array).append(float(index))
		if String((terrain_rows[index] as Array)[10]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result["edge_east"] as Array).append(float(index))
		if String((terrain_rows[index] as Array)[0]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result["edge_west"] as Array).append(float(index))
	return result


func _unique_assignment_scene_count(assignment: Dictionary) -> int:
	var keys: Dictionary = {}
	for entry_value: Variant in assignment.values():
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value as Dictionary
		keys[String(entry.get("template_id", ""))] = true
	return keys.size()


func _expect_bullet_terrain_rules(
	run_loop: Node,
	floor_position: Vector2,
	wall_position: Vector2
) -> void:
	_release_active_bullets()
	var base_snapshot: Dictionary = {
		"position": _vector_to_dict(floor_position),
		"damage": 0.0,
		"element_id": "",
		"damage_target_groups": ["module_wall_smoke_targets"],
		"hit_radius": 8.0,
		"remaining_life": 5.0,
		"max_range": 1000.0,
		"pierce_remaining": 0,
		"source_team": "team_player",
		"target_team": "team_enemy",
		"travelled": 0.0,
		"velocity": _vector_to_dict(Vector2(-520.0, 0.0)),
	}
	# This legacy-shaped snapshot deliberately omits wall_pierce_enabled.
	run_loop.call("_restore_bullet_snapshots", [base_snapshot])
	var legacy_player_bullet: Node2D = _first_active_entity("active_bullets")
	_expect(legacy_player_bullet != null, "legacy player projectile snapshot should restore through the pool")
	await _wait_physics_frames(20)
	_expect(
		legacy_player_bullet != null and not legacy_player_bullet.is_in_group("active_bullets"),
		"legacy player projectile snapshots should default to terrain blocking"
	)

	var enemy_snapshot: Dictionary = base_snapshot.duplicate(true)
	enemy_snapshot["source_team"] = "team_enemy"
	enemy_snapshot["target_team"] = "team_player"
	enemy_snapshot["wall_pierce_enabled"] = false
	run_loop.call("_restore_bullet_snapshots", [enemy_snapshot])
	var enemy_bullet: Node2D = _first_active_entity("active_bullets")
	_expect(enemy_bullet != null, "enemy projectile snapshot should restore through the pool")
	await _wait_physics_frames(20)
	_expect(
		enemy_bullet != null and not enemy_bullet.is_in_group("active_bullets"),
		"enemy projectiles should default to terrain blocking"
	)

	var raw_wall_pierce_bullet: Node = PoolManager.acquire(POOL_IDS.BULLET_BASIC)
	var active_world: Node = run_loop.get_node_or_null("ActiveWorld")
	_expect(
		raw_wall_pierce_bullet is Node2D and active_world != null,
		"wall-pierce stat test should acquire a projectile in the active world"
	)
	if not raw_wall_pierce_bullet is Node2D or active_world == null:
		_release_active_bullets()
		return
	var configured_wall_pierce_bullet: Node2D = raw_wall_pierce_bullet as Node2D
	configured_wall_pierce_bullet.reparent(active_world)
	configured_wall_pierce_bullet.global_position = floor_position
	configured_wall_pierce_bullet.call("configure", {
		STATS.DAMAGE: 0.0,
		STATS.BULLET_RANGE: 1000.0,
		STATS.BULLET_SPEED: 520.0,
		STATS.PIERCE_COUNT: 0,
		STATS.WALL_PIERCE: 1.0,
	}, {
		"element_id": "",
		"damage_target_groups": ["module_wall_smoke_targets"],
		"hit_radius": 8.0,
		"lifetime": 5.0,
	}, Vector2.LEFT, null)
	await _wait_physics_frames(20)
	_expect(
		configured_wall_pierce_bullet.is_in_group("active_bullets")
		and configured_wall_pierce_bullet.global_position.x < wall_position.x,
		"wall-piercing projectiles should cross the same blocked cell"
	)
	_release_active_bullets()


func _active_module_entity_count(group_name: String, slot_key: String) -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if node is Node2D and is_instance_valid(node) and String(node.get_meta("module_slot", "")) == slot_key:
			count += 1
	return count


func _has_active_entity_at(group_name: String, expected_position: Vector2) -> bool:
	return _find_active_entity_at(group_name, expected_position) != null


func _find_active_entity_at(group_name: String, expected_position: Vector2) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if node is Node2D and is_instance_valid(node) and (node as Node2D).global_position.is_equal_approx(expected_position):
			return node as Node2D
	return null


func _first_active_entity(group_name: String) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if node is Node2D and is_instance_valid(node):
			return node as Node2D
	return null


func _release_active_bullets() -> void:
	for bullet: Node in get_tree().get_nodes_in_group("active_bullets").duplicate():
		if is_instance_valid(bullet):
			PoolManager.release(bullet)


func _find_active_enemy_by_wave_key(wave_key: String) -> Node2D:
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if enemy is Node2D and String(enemy.get_meta("wave_key", "")) == wave_key:
			return enemy as Node2D
	return null


func _expect_enemy_unlock_boundaries(run_loop: Node) -> void:
	var world: Dictionary = _load_world_data().get("world", {}) as Dictionary
	var config: Dictionary = world.get(
		"first_visit_enemy_spawn",
		{}
	) as Dictionary
	var cases: Array[Dictionary] = [
		{"time": 0.0, "count": 2},
		{"time": 60.0, "count": 3},
		{"time": 240.0, "count": 4},
		{"time": 300.0, "count": 4},
		{"time": 420.0, "count": 5},
	]
	for boundary: Dictionary in cases:
		var eligible: Dictionary = run_loop.call(
			"_eligible_first_visit_enemy_pool",
			config,
			float(boundary.get("time", 0.0))
		)
		_expect(
			(eligible.get("enemy_ids", []) as Array).size()
			== int(boundary.get("count", 0)),
			"enemy unlock boundary %.1f should expose exactly %d entries"
			% [
				float(boundary.get("time", 0.0)),
				int(boundary.get("count", 0)),
			]
		)
	var opening_pool: Dictionary = run_loop.call(
		"_eligible_first_visit_enemy_pool",
		config,
		0.0
	)
	var opening_ids: Array = opening_pool.get("enemy_ids", []) as Array
	var opening_weights: Array = opening_pool.get("weights", []) as Array
	var gunner_index: int = opening_ids.find("enemy_spitter")
	_expect(
		gunner_index >= 0
		and is_equal_approx(float(opening_weights[gunner_index]), 100.0),
		"Assault Gunner should unlock at 0 seconds with weight 100"
	)
	var full_pool: Dictionary = run_loop.call(
		"_eligible_first_visit_enemy_pool",
		config,
		420.0
	)
	var full_ids: Array = full_pool.get("enemy_ids", []) as Array
	var full_weights: Array = full_pool.get("weights", []) as Array
	var full_gunner_index: int = full_ids.find("enemy_spitter")
	var total_weight: float = 0.0
	var highest_other_weight: float = 0.0
	for index: int in range(full_weights.size()):
		var weight: float = float(full_weights[index])
		total_weight += weight
		if index != full_gunner_index:
			highest_other_weight = maxf(highest_other_weight, weight)
	_expect(
		full_gunner_index >= 0
		and is_equal_approx(
			float(full_weights[full_gunner_index]),
			100.0
		)
		and is_equal_approx(total_weight, 220.0)
		and float(full_weights[full_gunner_index])
		> highest_other_weight,
		"full encounter pool should keep Assault Gunner as its highest weight"
	)


func _formal_assignment_has_three_events_and_flat_fill(
	assignment: Dictionary
) -> bool:
	var event_template_ids: Array[String] = []
	for raw_slot: Variant in assignment.keys():
		var entry: Dictionary = assignment[raw_slot] as Dictionary
		if int(entry.get("rotation", -1)) != 0:
			return false
		var role: String = String(entry.get("role", ""))
		if role in [MODULE_ROLES.MODULE_ROLE_START, MODULE_ROLES.MODULE_ROLE_OBJECTIVE]:
			continue
		if role == MODULE_ROLES.MODULE_ROLE_WORLD_EVENT:
			var template_id: String = String(entry.get("template_id", ""))
			if event_template_ids.has(template_id):
				return false
			event_template_ids.append(template_id)
		elif String(entry.get("template_id", "")) != "module_flat_ground":
			return false
	return event_template_ids.size() == 3


func _world_event_coords(assignment: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw_entry: Variant in assignment.values():
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		if String(entry.get("role", "")) != MODULE_ROLES.MODULE_ROLE_WORLD_EVENT:
			continue
		var slot: Dictionary = entry.get("slot", {}) as Dictionary
		result.append(Vector2i(int(slot.get("x", -1)), int(slot.get("y", -1))))
	result.sort_custom(
		func(left: Vector2i, right: Vector2i) -> bool:
			return left.y < right.y or (left.y == right.y and left.x < right.x)
	)
	return result


func _world_event_instance_summary(
	summary: Dictionary,
	instance_id: String
) -> Dictionary:
	for raw_instance: Variant in summary.get("instances", []) as Array:
		if (
			raw_instance is Dictionary
			and String((raw_instance as Dictionary).get("instance_id", ""))
			== instance_id
		):
			return (raw_instance as Dictionary).duplicate(true)
	return {}


func _flat_module_is_empty_floor(module_data: Dictionary) -> bool:
	var terrain_rows: Array = module_data.get("terrain_rows", []) as Array
	if terrain_rows.size() != 11:
		return false
	for raw_row: Variant in terrain_rows:
		if not raw_row is Array or (raw_row as Array).size() != 11:
			return false
		for raw_cell: Variant in raw_row as Array:
			if String(raw_cell) != MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
				return false
	return (module_data.get("placements", []) as Array).is_empty()


func _saved_slot_has_encounter(
	slot_states: Dictionary,
	slot_key: String,
	expected_plan: Array
) -> bool:
	var slot_state: Variant = slot_states.get(slot_key)
	if not slot_state is Dictionary:
		return false
	var encounter: Variant = (slot_state as Dictionary).get("enemy_encounter")
	return (
		encounter is Dictionary
		and ((encounter as Dictionary).get("spawns", []) as Array)
		== expected_plan
	)


func _has_active_module_enemy_at(
	slot_key: String,
	world_position: Vector2
) -> bool:
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			enemy is Node2D
			and String(enemy.get_meta("module_slot", "")) == slot_key
			and (enemy as Node2D).global_position.is_equal_approx(world_position)
		):
			return true
	return false


func _dict_to_vector(value: Variant) -> Vector2:
	if not value is Dictionary:
		return Vector2.ZERO
	return Vector2(
		float((value as Dictionary).get("x", 0.0)),
		float((value as Dictionary).get("y", 0.0))
	)


func _vector_key(value: Vector2) -> String:
	return "%.3f,%.3f" % [value.x, value.y]


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _coord_matches(raw_value: Variant, expected: Vector2i) -> bool:
	if not raw_value is Dictionary:
		return false
	var value: Dictionary = raw_value as Dictionary
	return int(value.get("x", -1)) == expected.x and int(value.get("y", -1)) == expected.y


func _wait_for_playing_run_loop() -> Node:
	for _frame: int in range(BOOT_FRAMES * 12):
		await get_tree().process_frame
		if GameState.is_state(GameState.PLAYING):
			var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
			if run_loop != null:
				return run_loop
	return _find_node_by_name(get_tree().root, "GameplayRunLoop")


func _wait_for_replacement_run_loop(previous_instance_id: int) -> Node:
	for _frame: int in range(BOOT_FRAMES * 12):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(
			get_tree().root,
			"GameplayRunLoop"
		)
		if (
			run_loop != null
			and run_loop.get_instance_id() != previous_instance_id
			and bool(run_loop.get("_run_activated"))
		):
			return run_loop
	return null


func _wait_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await get_tree().process_frame


func _wait_physics_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await get_tree().physics_frame


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var result: Node = _find_node_by_name(child, target_name)
		if result != null:
			return result
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[ModuleWorldSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[ModuleWorldSmoke] PASS")
		get_tree().quit(0)
		return
	print("[ModuleWorldSmoke] FAIL count=%d" % _failures.size())
	get_tree().quit(1)
