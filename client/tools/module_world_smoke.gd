extends Node
## F13 headless smoke for deterministic composition, seamless streaming, fog,
## objective-to-extraction flow and run-v4 restore.

const MODULE_WORLD_MANAGER_SCRIPT := preload("res://scripts/gameplay/module_world_manager.gd")
const MODULE_NAVIGATION_FIELD_SCRIPT := preload("res://scripts/gameplay/module_navigation_field.gd")
const ACTIONS := preload("res://scripts/contracts/actions.gd")
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

	var summary: Dictionary = run_loop.call("debug_summary")
	var world_summary: Dictionary = summary.get("module_world", {}) as Dictionary
	_expect(int(world_summary.get("assignment_count", 0)) == 81, "world should assign exactly 81 slots")
	_expect(int(world_summary.get("active_count", 0)) <= 9, "streaming should activate at most nine chunks")
	_expect(String(world_summary.get("map_hash", "")).length() == 64, "world should expose a sha256 map hash")
	_expect(_coord_matches(world_summary.get("current_module", {}), Vector2i(4, 4)), "fresh run should start in center module")
	var runtime_navigation: Dictionary = world_summary.get("navigation", {}) as Dictionary
	_expect(
		int(runtime_navigation.get("flow_radius_cells", 0)) == NAVIGATION_FLOW_RADIUS_CELLS,
		"runtime should derive an eight-cell flow radius from current EnemyAI sight data"
	)

	print("[ModuleWorldSmoke] stage=composition")
	_expect_deterministic_composition()
	print("[ModuleWorldSmoke] stage=streaming")
	await _expect_seamless_streaming(run_loop)
	print("[ModuleWorldSmoke] stage=objective_restore")
	await _expect_objective_extraction_and_restore(run_loop)
	print("[ModuleWorldSmoke] stage=finish")
	SaveManager.delete(SMOKE_SLOT, SAVE_KINDS.RUN)
	_finish()


func _expect_deterministic_composition() -> void:
	var data: Dictionary = _load_world_data()
	var manager_a: Node2D = MODULE_WORLD_MANAGER_SCRIPT.new() as Node2D
	var manager_b: Node2D = MODULE_WORLD_MANAGER_SCRIPT.new() as Node2D
	var manager_c: Node2D = MODULE_WORLD_MANAGER_SCRIPT.new() as Node2D
	var manager_d: Node2D = MODULE_WORLD_MANAGER_SCRIPT.new() as Node2D
	var manager_content: Node2D = MODULE_WORLD_MANAGER_SCRIPT.new() as Node2D
	var manager_technical: Node2D = MODULE_WORLD_MANAGER_SCRIPT.new() as Node2D
	add_child(manager_a)
	add_child(manager_b)
	add_child(manager_c)
	add_child(manager_d)
	add_child(manager_content)
	add_child(manager_technical)
	_expect(bool(manager_a.call("configure", data["world"], data["registry"], data["templates"], 13013, NAVIGATION_FLOW_RADIUS_CELLS)), "seed A world should configure")
	_expect(bool(manager_b.call("configure", data["world"], data["registry"], data["templates"], 13013, NAVIGATION_FLOW_RADIUS_CELLS)), "same-seed world should configure")
	_expect(bool(manager_c.call("configure", data["world"], data["registry"], data["templates"], 13014, NAVIGATION_FLOW_RADIUS_CELLS)), "different-seed world should configure")
	_expect(bool(manager_d.call("configure", data["world"], data["registry"], data["templates"], 13015, NAVIGATION_FLOW_RADIUS_CELLS)), "third-seed world should configure")
	_expect(String(manager_a.call("map_hash")) == String(manager_b.call("map_hash")), "same seed should reproduce assignment/hash")
	_expect(manager_a.call("assignment") == manager_b.call("assignment"), "same seed should reproduce all 81 assignments")
	_expect(manager_a.call("assignment") != manager_c.call("assignment"), "different seed should change ordinary module assignments")
	_expect(manager_c.call("assignment") != manager_d.call("assignment"), "three-seed audit should produce distinct ordinary assignments")
	_expect(String(manager_a.call("map_hash")) != String(manager_c.call("map_hash")), "different seed should change ordinary module assignment")
	var changed_templates: Dictionary = (data["templates"] as Dictionary).duplicate(true)
	var changed_objective: Dictionary = (changed_templates["module_objective_core"] as Dictionary).duplicate(true)
	var changed_placements: Array = (changed_objective.get("placements", []) as Array).duplicate(true)
	var changed_target: Dictionary = (changed_placements[0] as Dictionary).duplicate(true)
	changed_target["target_hp"] = float(changed_target.get("target_hp", 0.0)) + 1.0
	changed_placements[0] = changed_target
	changed_objective["placements"] = changed_placements
	changed_templates["module_objective_core"] = changed_objective
	_expect(bool(manager_content.call("configure", data["world"], data["registry"], changed_templates, 13013, NAVIGATION_FLOW_RADIUS_CELLS)), "content-revision world should configure")
	_expect(manager_content.call("assignment") == manager_a.call("assignment"), "content revision should preserve the same seeded assignment")
	_expect(String(manager_content.call("map_hash")) != String(manager_a.call("map_hash")), "module content revision should invalidate map hash")
	_expect(bool(manager_technical.call("configure", data["world"], data["registry"], data["templates"], 13013, NAVIGATION_FLOW_RADIUS_CELLS)), "technical-slice manager should configure")
	_expect(bool(manager_technical.call("build_technical_slice_assignment")), "technical-slice opt-in should build its checked-in assignment")
	var sealed_count: int = 0
	for raw_entry: Variant in (manager_technical.call("assignment") as Dictionary).values():
		if not raw_entry is Dictionary:
			continue
		var template_id: String = String((raw_entry as Dictionary).get("template_id", ""))
		var registry_entry: Dictionary = (data["registry"] as Dictionary).get(template_id, {}) as Dictionary
		if String(registry_entry.get("role", "")) == MODULE_ROLES.MODULE_ROLE_SEALED:
			sealed_count += 1
	_expect(sealed_count == 72, "technical slice should seal exactly the outer 72 slots")
	_expect(manager_technical.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_START) == Vector2i(4, 4), "technical slice should retain the center start")
	_expect(manager_technical.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_OBJECTIVE) == Vector2i(3, 4), "technical slice should expose its in-slice objective anchor")
	_expect(manager_technical.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_EXTRACTION) == Vector2i(3, 3), "technical slice should expose its in-slice extraction anchor")
	_expect_navigation_queries(manager_a, manager_b, manager_technical)
	var tampered_snapshot: Dictionary = manager_a.call("snapshot")
	tampered_snapshot["map_hash"] = "0".repeat(64)
	_expect(not bool(manager_a.call("restore_state", tampered_snapshot)), "restore should reject a mismatched module map hash")
	var center_world: Vector2 = manager_a.call("global_cell_to_world", Vector2i(49, 49))
	_expect(center_world.is_equal_approx(Vector2.ZERO), "global center cell should map to world origin")
	_expect(manager_a.call("world_to_global_cell", Vector2.ZERO) == Vector2i(49, 49), "world origin should map to global center cell")
	manager_a.queue_free()
	manager_b.queue_free()
	manager_c.queue_free()
	manager_d.queue_free()
	manager_content.queue_free()
	manager_technical.queue_free()


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


func _expect_bounded_flow_rebuilds() -> void:
	var full_mask := PackedByteArray()
	full_mask.resize(99 * 99)
	full_mask.fill(1)
	var field: RefCounted = MODULE_NAVIGATION_FIELD_SCRIPT.new()
	_expect(
		bool(field.call("configure", full_mask, 99, 99, 160.0, Vector2.ZERO, Vector2i(49, 49), NAVIGATION_FLOW_RADIUS_CELLS)),
		"bounded-flow navigation field should configure"
	)
	var all_rebuilds_bounded: bool = true
	for column: int in range(30, 50):
		field.call("set_active_target", field.call("cell_to_world", Vector2i(column, 49)))
		var summary: Dictionary = field.call("debug_summary")
		all_rebuilds_bounded = (
			all_rebuilds_bounded
			and int(summary.get("last_rebuild_visited_count", 0)) == 289
			and int(summary.get("flow_bound_cell_count", 0)) == 289
		)
	_expect(all_rebuilds_bounded, "twenty open-grid cell crossings should each remain at the 289-cell bound")
	var final_summary: Dictionary = field.call("debug_summary")
	_expect(int(final_summary.get("flow_rebuild_count", 0)) == 20, "twenty target-cell crossings should rebuild exactly twenty local fields")
	var outside_position: Vector2 = field.call("cell_to_world", Vector2i(58, 49))
	var target_position: Vector2 = field.call("cell_to_world", Vector2i(49, 49))
	_expect(
		not bool(field.call("query_to_active_target", outside_position).get("reachable", true)),
		"active flow query should be unreachable beyond the local radius"
	)
	_expect(
		bool(field.call("query", outside_position, target_position).get("reachable", false)),
		"full-world AStar should remain reachable for the same positions"
	)


func _expect_seamless_streaming(run_loop: Node) -> void:
	var before: Dictionary = run_loop.call("debug_summary")
	var before_hash: String = String((before.get("module_world", {}) as Dictionary).get("map_hash", ""))
	var manager: Node = _find_node_by_name(get_tree().root, "ModuleWorldManager")
	_expect(manager != null, "module world manager should remain available during streaming")
	if manager != null:
		_expect(bool(manager.call("is_world_position_walkable", Vector2(-160.0, -160.0))), "known center floor cell should be walkable")
		_expect(not bool(manager.call("is_world_position_walkable", Vector2(-320.0, -160.0))), "known center blocked cell should not be walkable")
		for active_enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
			if active_enemy is Node2D and not String(active_enemy.get_meta("module_slot", "")).is_empty():
				_expect(
					bool(manager.call("is_world_position_walkable", (active_enemy as Node2D).global_position)),
					"module enemy placement should spawn on floor terrain"
				)
	var blocked_spawned: bool = bool(run_loop.call(
		"_spawn_enemy_at",
		"enemy_chaser",
		Vector2(-320.0, -160.0),
		"module_blocked_spawn_test",
		"4,4"
	))
	_expect(not blocked_spawned, "runtime should reject an enemy spawn on blocked module terrain")
	run_loop.call("_restore_enemy_snapshots", [{
		"enemy_id": "enemy_chaser",
		"module_slot": "4,4",
		"position": _vector_to_dict(Vector2(-320.0, -160.0)),
		"wave_key": "module_blocked_restore_test",
	}])
	_expect(
		_find_active_enemy_by_wave_key("module_blocked_restore_test") == null,
		"runtime should reject an enemy snapshot restored on blocked module terrain"
	)
	# The center start module has a floor cell at (-160, -160) and a blocked cell
	# directly to its left. Real CharacterBody2D movement must stop at that wall.
	run_loop.call("debug_set_player_position", Vector2(-160.0, -160.0))
	await get_tree().physics_frame
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.LEFT)
	for _physics_tick: int in range(45):
		await get_tree().physics_frame
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.ZERO)
	InputService.set_playback_active(false)
	var wall_test_player: Node = _find_node_by_name(get_tree().root, "Player")
	_expect(
		wall_test_player is Node2D and (wall_test_player as Node2D).global_position.x > -240.0,
		"player physics body should not enter a blocked module cell"
	)
	var debug_spawn: Dictionary = run_loop.call("debug_spawn_enemy", "enemy_chaser", 1)
	_expect(bool(debug_spawn.get("ok", false)), "enemy wall test should spawn a chaser")
	var wall_test_enemy: Node2D = _find_active_enemy_by_wave_key("debug_enemy_chaser")
	_expect(wall_test_enemy != null, "enemy wall test should find its spawned chaser")
	if wall_test_enemy != null:
		run_loop.call("debug_set_player_position", Vector2(-320.0, -160.0))
		wall_test_enemy.global_position = Vector2(-160.0, -160.0)
		await get_tree().physics_frame
		for _physics_tick: int in range(120):
			await get_tree().physics_frame
		_expect(wall_test_enemy.global_position.x > -240.0, "enemy physics body should not enter a blocked module cell")
		PoolManager.release(wall_test_enemy)
	await _expect_bullet_terrain_rules(run_loop)
	var detour_spawned: bool = bool(run_loop.call(
		"_spawn_enemy_at",
		"enemy_chaser",
		Vector2(-160.0, -160.0),
		"module_navigation_detour_test",
		"4,4"
	))
	_expect(detour_spawned, "module navigation detour test should spawn a chaser on floor terrain")
	var detour_enemy: Node2D = _find_active_enemy_by_wave_key("module_navigation_detour_test")
	if detour_enemy != null:
		run_loop.call("debug_set_player_position", Vector2(-320.0, 0.0))
		# Pooled enemies may have just reset their decision accumulator; wait past
		# the configured decision interval in physics time before asserting state.
		for _physics_tick: int in range(12):
			await get_tree().physics_frame
		var navigation_summary: Dictionary = detour_enemy.call("ai_debug_summary")
		_expect(String(navigation_summary.get("perception_state", "")) == "path_aware", "nearby player across a blocked corner should be sensed by route distance")
		_expect(String(navigation_summary.get("navigation_mode", "")) == "flow_field", "blocked module pursuit should use the shared flow field")
		var detour_start: Vector2 = detour_enemy.global_position
		for _physics_tick: int in range(35):
			await get_tree().physics_frame
		_expect(detour_enemy.global_position.y > detour_start.y, "enemy should enter the legal south corridor instead of pushing diagonally through the blocked corner")
		_expect(bool(manager.call("is_world_position_walkable", detour_enemy.global_position)), "flow-guided enemy should remain on walkable module terrain")
		PoolManager.release(detour_enemy)
	# Start inside the center module's east doorway and cross the shared seam using
	# normal CharacterBody2D movement so a bad collision merge cannot hide behind a teleport.
	run_loop.call("debug_set_player_position", Vector2(800.0, 0.0))
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.RIGHT)
	for _physics_tick: int in range(90):
		await get_tree().physics_frame
		var player: Node = _find_node_by_name(get_tree().root, "Player")
		if player is Node2D and (player as Node2D).global_position.x > 900.0:
			break
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.ZERO)
	InputService.set_playback_active(false)
	await _wait_frames(BOOT_FRAMES)
	var crossed: Dictionary = run_loop.call("debug_summary")
	var crossed_world: Dictionary = crossed.get("module_world", {}) as Dictionary
	_expect(_coord_matches(crossed_world.get("current_module", {}), Vector2i(5, 4)), "crossing the shared edge should enter the adjacent module without scene switch")
	var crossed_player: Node = _find_node_by_name(get_tree().root, "Player")
	_expect(crossed_player is Node2D and (crossed_player as Node2D).global_position.x > 900.0, "player physics body should pass through the shared module doorway")
	_expect(int(crossed_world.get("active_count", 0)) <= 9, "edge crossing should keep at most nine active chunks")
	_expect(int(crossed_world.get("visited_count", 0)) >= 2, "entering an adjacent module should reveal fog state")
	_expect(String(crossed_world.get("map_hash", "")) == before_hash, "streaming should not mutate map hash")
	var first_visit_enemy_count: int = _active_module_entity_count("active_enemies", "5,4")
	var bullet_position := Vector2(1120.0, 700.0)
	var pickup_position := Vector2(1280.0, 700.0)
	run_loop.call("_restore_bullet_snapshots", [{
		"position": _vector_to_dict(bullet_position),
		"damage": 0.0,
		"damage_type": "",
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
	run_loop.call("_restore_pickup_snapshots", [{
		"position": _vector_to_dict(pickup_position),
		"amount": 7,
		"pickup_speed": 0.0,
	}])
	await _wait_frames(BOOT_FRAMES)
	_expect(_has_active_entity_at("active_bullets", bullet_position), "test projectile should be active in the adjacent module")
	_expect(_has_active_entity_at("active_pickups", pickup_position), "test pickup should be active in the adjacent module")
	# Move far enough that slot 5,4 leaves the active 3x3 neighborhood.
	run_loop.call("debug_set_player_position", Vector2(-1760.0, 0.0))
	await _wait_frames(BOOT_FRAMES)
	_expect(not _has_active_entity_at("active_bullets", bullet_position), "deactivated module should release its projectile")
	_expect(not _has_active_entity_at("active_pickups", pickup_position), "deactivated module should release its pickup")
	var stored_state: Dictionary = manager.call("slot_state", Vector2i(5, 4)) if manager != null else {}
	_expect((stored_state.get("bullet_snapshots", []) as Array).size() == 1, "deactivated slot should retain one projectile snapshot")
	var stored_bullets: Array = stored_state.get("bullet_snapshots", []) as Array
	_expect(
		stored_bullets.size() == 1 and bool((stored_bullets[0] as Dictionary).get("wall_pierce_enabled", false)),
		"deactivated slot should preserve the projectile wall-pierce snapshot"
	)
	_expect((stored_state.get("pickup_snapshots", []) as Array).size() == 1, "deactivated slot should retain one pickup snapshot")
	run_loop.call("debug_set_player_position", Vector2(960.0, 0.0))
	await _wait_frames(BOOT_FRAMES)
	_expect(_active_module_entity_count("active_enemies", "5,4") == first_visit_enemy_count, "leave/return should restore slot state without duplicate enemies")
	_expect(_has_active_entity_at("active_bullets", bullet_position), "returning should restore the slot projectile")
	var restored_bullet: Node2D = _find_active_entity_at("active_bullets", bullet_position)
	_expect(
		restored_bullet != null
		and restored_bullet.has_method("snapshot")
		and bool((restored_bullet.call("snapshot") as Dictionary).get("wall_pierce_enabled", false)),
		"returning should restore the projectile wall-pierce snapshot"
	)
	_expect(_has_active_entity_at("active_pickups", pickup_position), "returning should restore the slot pickup")


func _expect_objective_extraction_and_restore(run_loop: Node) -> void:
	var technical_slice: bool = OS.get_cmdline_user_args().has("--module-world-technical-slice")
	# Full world objective is (0,4); technical-slice objective is (3,4).
	var objective_coord := Vector2i(3, 4) if technical_slice else Vector2i(0, 4)
	var objective_position := Vector2(-1760.0, 0.0) if technical_slice else Vector2(-7040.0, 0.0)
	run_loop.call("debug_set_player_position", objective_position)
	await _wait_frames(BOOT_FRAMES * 2)
	var objective_id: String = "module_%d_%d_objective_5_5" % [objective_coord.x, objective_coord.y]
	var damage_result: Dictionary = run_loop.call("debug_damage_interest_point_target", objective_id, 99999.0)
	_expect(bool(damage_result.get("ok", false)), "module objective should use the existing damage primitive")
	await _wait_frames(BOOT_FRAMES)
	var objective_summary: Dictionary = run_loop.call("debug_summary")
	_expect(bool((objective_summary.get("extraction", {}) as Dictionary).get("active", false)), "destroying objective should activate the separate extraction module")

	# Save while the completed objective module is still active. Restore must not recreate
	# its destroyed target with default HP before applying the interest-point snapshot.
	var snapshot: Dictionary = run_loop.call("create_run_snapshot")
	_expect(int(snapshot.get("schema_version", 0)) == 4, "module run snapshot should use schema v4")
	_expect(SaveManager.save(SMOKE_SLOT, SAVE_KINDS.RUN, snapshot), "module run v4 should save")
	var loaded: Dictionary = SaveManager.load(SMOKE_SLOT, SAVE_KINDS.RUN)
	_expect(not loaded.is_empty(), "module run v4 should load")
	if loaded.is_empty():
		return
	var saved_hash: String = String((snapshot.get("module_world", {}) as Dictionary).get("map_hash", ""))
	var parent_boot: Node = get_parent()
	parent_boot.call("_start_gameplay_run", loaded)
	var restored: Node = await _wait_for_playing_run_loop()
	_expect(restored != null, "saved module world should restore into a playable run")
	if restored == null:
		return
	var restored_summary: Dictionary = restored.call("debug_summary")
	var restored_world: Dictionary = restored_summary.get("module_world", {}) as Dictionary
	_expect(String(restored_world.get("map_hash", "")) == saved_hash, "restore should validate and preserve map hash")
	_expect(int(restored_world.get("visited_count", 0)) >= 2, "restore should preserve module fog/visited state")
	_expect(bool((restored_summary.get("extraction", {}) as Dictionary).get("active", false)), "restore should preserve objective-to-extraction state")
	_expect(
		_find_node_by_name(get_tree().root, "InterestPointTarget_%s" % objective_id) == null,
		"restore should not recreate an already-destroyed objective target"
	)

	# Full world extraction is (0,0); technical-slice extraction is (3,3).
	var extraction_coord := Vector2i(3, 3) if technical_slice else Vector2i(0, 0)
	var extraction_position := Vector2(-1760.0, -1760.0) if technical_slice else Vector2(-7040.0, -7040.0)
	restored.call("debug_set_player_position", extraction_position)
	await _wait_frames(BOOT_FRAMES)
	var extraction_world: Dictionary = (restored.call("debug_summary") as Dictionary).get("module_world", {}) as Dictionary
	_expect(_coord_matches(extraction_world.get("current_module", {}), extraction_coord), "player should stream into the extraction slot")
	_expect(int(extraction_world.get("active_count", 0)) <= 9, "corner streaming should stay inside the chunk budget")

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


func _load_world_data() -> Dictionary:
	var worlds_payload: Dictionary = DataLoader.load_json(DataLoader.MODULE_WORLDS_PATH) as Dictionary
	var registry_payload: Dictionary = DataLoader.load_json(DataLoader.MODULE_TEMPLATES_PATH) as Dictionary
	var world: Dictionary = (worlds_payload.get("worlds", []) as Array)[0] as Dictionary
	var registry: Dictionary = {}
	var templates: Dictionary = {}
	for raw_entry: Variant in registry_payload.get("templates", []):
		var entry: Dictionary = raw_entry as Dictionary
		var template_id: String = String(entry.get("id", ""))
		registry[template_id] = entry.duplicate(true)
		templates[template_id] = DataLoader.load_json(String(entry.get("path", "")))
	return {"world": world, "registry": registry, "templates": templates}


func _expect_bullet_terrain_rules(run_loop: Node) -> void:
	_release_active_bullets()
	var base_snapshot: Dictionary = {
		"position": _vector_to_dict(Vector2(-160.0, -160.0)),
		"damage": 0.0,
		"damage_type": "",
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
	configured_wall_pierce_bullet.global_position = Vector2(-160.0, -160.0)
	configured_wall_pierce_bullet.call("configure", {
		STATS.DAMAGE: 0.0,
		STATS.BULLET_RANGE: 1000.0,
		STATS.BULLET_SPEED: 520.0,
		STATS.PIERCE_COUNT: 0,
		STATS.WALL_PIERCE: 1.0,
	}, {
		"damage_type": "",
		"damage_target_groups": ["module_wall_smoke_targets"],
		"hit_radius": 8.0,
		"lifetime": 5.0,
	}, Vector2.LEFT, null)
	await _wait_physics_frames(20)
	_expect(
		configured_wall_pierce_bullet.is_in_group("active_bullets")
		and configured_wall_pierce_bullet.global_position.x < -320.0,
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
