extends SmokeHarness


const MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT := preload(
	"res://scripts/gameplay/module_chunk_streaming_controller.gd"
)
const MODULE_CELL_TOKENS := preload(
	"res://scripts/contracts/module_cell_tokens.gd"
)
const MODULE_EDGE_DIRECTIONS := preload(
	"res://scripts/contracts/module_edge_directions.gd"
)
const MODULE_REVIEW_STATUSES := preload(
	"res://scripts/contracts/module_review_statuses.gd"
)
const MODULE_ROLES := preload("res://scripts/contracts/module_roles.gd")
const MODULE_WORLD_MANAGER_SCRIPT := preload(
	"res://scripts/gameplay/module_world_manager.gd"
)
const WORLD_COLUMNS: int = 7
const WORLD_ROWS: int = 7
const MODULE_COLUMNS: int = 11
const MODULE_ROWS: int = 11
const EXPECTED_CHUNK_COUNT: int = 12
const TEMPLATE_ID: String = "module_test"
const ALTERNATE_TEMPLATE_ID: String = "module_alternate"
const INVALID_TEMPLATE_ID: String = "module_invalid_neighbors"


func test_failed_candidate_prepare_does_not_mutate_live_cache() -> void:
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.new()
	)
	var live_scene: PackedScene = _generated_scene(TEMPLATE_ID)
	var stale_scene: PackedScene = _generated_scene(
		"module_stale",
		GeneratedModuleScene.BAKER_SCHEMA_VERSION - 1
	)
	assert_true(_configure_controller(
		controller,
		{
			TEMPLATE_ID: live_scene,
			"module_stale": stale_scene,
		},
		_recording_pool([])
	))
	var live_candidate: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PreparedAssignment = (
		controller.prepare_assignment([_assignment_entry(TEMPLATE_ID)])
	)
	assert_true(live_candidate.is_valid())
	assert_true(controller.commit_prepared(live_candidate))

	var failed_candidate: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PreparedAssignment = (
		controller.prepare_assignment([
			_assignment_entry("module_stale"),
		])
	)

	assert_false(failed_candidate.is_valid())
	assert_eq(
		failed_candidate.error_code(),
		MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PrepareError.METADATA_STALE
	)
	assert_eq(failed_candidate.scene_count(), 0)
	assert_eq(controller.preloaded_scene_count(), 1)
	assert_true(controller.has_preloaded_scene(TEMPLATE_ID))
	assert_false(controller.has_preloaded_scene("module_stale"))


func test_prepare_rejects_invalid_root_and_stale_metadata() -> void:
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.new()
	)
	var scene_paths: Dictionary = {
		"invalid_root": _plain_node_scene(),
		"bad_schema": _generated_scene(
			"bad_schema",
			GeneratedModuleScene.BAKER_SCHEMA_VERSION - 1
		),
		"wrong_id": _generated_scene("different_id"),
		"rotated": _generated_scene(
			"rotated",
			GeneratedModuleScene.BAKER_SCHEMA_VERSION,
			90
		),
	}
	assert_true(_configure_controller(
		controller,
		scene_paths,
		_recording_pool([])
	))
	var invalid_root: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PreparedAssignment = (
		controller.prepare_assignment([_assignment_entry("invalid_root")])
	)
	assert_false(invalid_root.is_valid())
	assert_eq(
		invalid_root.error_code(),
		MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PrepareError.ROOT_INVALID
	)
	for template_id: String in ["bad_schema", "wrong_id", "rotated"]:
		var stale: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PreparedAssignment = (
			controller.prepare_assignment([_assignment_entry(template_id)])
		)
		assert_false(stale.is_valid())
		assert_eq(
			stale.error_code(),
			MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PrepareError.METADATA_STALE
		)
	var missing: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PreparedAssignment = (
		controller.prepare_assignment([_assignment_entry("missing")])
	)
	assert_false(missing.is_valid())
	assert_eq(
		missing.error_code(),
		MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PrepareError.LOAD_FAILED
	)


func test_refresh_mounts_window_and_pin_union_in_world_row_major_order() -> void:
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		_configured_streaming_controller([])
	)
	var request: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamRequest = (
		_stream_request(
			Vector2i(1, 1),
			[Vector2i(6, 6)],
			1
		)
	)
	var change: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamChange = (
		controller.refresh(request)
	)

	var expected: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(2, 1),
		Vector2i(0, 2),
		Vector2i(1, 2),
		Vector2i(2, 2),
		Vector2i(6, 6),
	]
	assert_eq(change.activated_coords(), expected)
	assert_eq(change.deactivated_coords(), [])
	assert_eq(controller.active_module_coords(), expected)


func test_refresh_supports_pins_only_when_center_is_invalid() -> void:
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		_configured_streaming_controller([])
	)
	var request: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamRequest = (
		_stream_request(
			Vector2i(-1, -1),
			[Vector2i(6, 6), Vector2i(0, 0), Vector2i(6, 6)],
			1
		)
	)
	var change: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamChange = (
		controller.refresh(request)
	)

	assert_eq(change.activated_coords(), [
		Vector2i(0, 0),
		Vector2i(6, 6),
	])
	assert_eq(controller.active_module_coords(), [
		Vector2i(0, 0),
		Vector2i(6, 6),
	])


func test_refresh_clears_departing_chunk_before_reusing_it() -> void:
	var call_log: Array[String] = []
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		_configured_streaming_controller(call_log)
	)
	controller.refresh(_stream_request(Vector2i(0, 0), [], 0))
	call_log.clear()

	var change: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamChange = (
		controller.refresh(_stream_request(Vector2i(1, 0), [], 0))
	)

	assert_eq(change.deactivated_coords(), [Vector2i(0, 0)])
	assert_eq(change.activated_coords(), [Vector2i(1, 0)])
	assert_eq(call_log, ["clear:0,0", "configure:1,0"])


func test_reconfigure_clears_active_before_replacing_pool_inputs() -> void:
	var call_log: Array[String] = []
	var pool: Array[ModuleChunk] = _recording_pool(call_log)
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		_configured_streaming_controller(call_log, pool)
	)
	controller.refresh(_stream_request(Vector2i(2, 3), [], 0))
	call_log.clear()

	assert_true(_configure_controller(
		controller,
		{TEMPLATE_ID: _generated_scene(TEMPLATE_ID)},
		pool
	))

	assert_eq(controller.active_module_coords(), [])
	assert_true(not call_log.is_empty())
	assert_eq(call_log[0], "clear:2,3")


func test_pool_requires_twelve_and_chunk_mount_failure_keeps_partial_success() -> void:
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.new()
	)
	assert_false(_configure_controller(
		controller,
		{TEMPLATE_ID: _generated_scene(TEMPLATE_ID)},
		_recording_pool([], EXPECTED_CHUNK_COUNT - 1)
	))
	assert_eq(controller.chunk_pool_size(), EXPECTED_CHUNK_COUNT - 1)

	var pool: Array[ModuleChunk] = _recording_pool([])
	var first_chunk: RecordingChunk = pool[0] as RecordingChunk
	first_chunk.configure_should_fail = true
	assert_true(_configure_controller(
		controller,
		{TEMPLATE_ID: _generated_scene(TEMPLATE_ID)},
		pool
	))
	_prepare_live_assignment(controller)
	var change: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamChange = (
		controller.refresh(_stream_request(Vector2i(1, 1), [], 1))
	)

	assert_eq(change.configure_failed_coords(), [Vector2i(0, 0)])
	assert_eq(change.pool_exhausted_count(), 0)
	assert_eq(change.activated_coords(), [
		Vector2i(1, 0),
		Vector2i(2, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(2, 1),
		Vector2i(0, 2),
		Vector2i(1, 2),
		Vector2i(2, 2),
	])
	assert_eq(controller.active_count(), 8)


func test_pool_exhaustion_keeps_chunks_mounted_before_failure() -> void:
	var shared_chunk := RecordingChunk.new()
	add_child_autofree(shared_chunk)
	var duplicate_pool: Array[ModuleChunk] = []
	for _chunk_index: int in range(EXPECTED_CHUNK_COUNT):
		duplicate_pool.append(shared_chunk)
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.new()
	)
	assert_true(_configure_controller(
		controller,
		{TEMPLATE_ID: _generated_scene(TEMPLATE_ID)},
		duplicate_pool
	))
	_prepare_live_assignment(controller)

	var change: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamChange = (
		controller.refresh(_stream_request(Vector2i(0, 0), [], 1))
	)

	assert_eq(change.activated_coords(), [Vector2i(0, 0)])
	assert_eq(change.pool_exhausted_count(), 3)
	assert_eq(controller.active_module_coords(), [Vector2i(0, 0)])


func test_invalid_rebuild_clears_active_cache_and_map_before_tick() -> void:
	for rebuild_method: String in [
		"build_technical_slice_assignment",
		"build_fallback_assignment",
	]:
		var manager: MODULE_WORLD_MANAGER_SCRIPT = _configured_world_manager()
		var player_position: Vector2 = manager.global_cell_to_world(
			Vector2i(5, 5)
		)
		manager.tick(player_position)
		assert_eq(manager.assignment().size(), WORLD_COLUMNS * WORLD_ROWS)
		assert_false(manager.map_hash().is_empty())
		assert_eq(manager.active_module_coords(), [Vector2i(0, 0)])
		assert_eq(
			int(manager.debug_summary().get("preloaded_scene_count", 0)),
			1
		)

		assert_false(bool(manager.call(rebuild_method)))
		assert_true(manager.map_hash().is_empty())
		assert_eq(manager.active_module_coords(), [])
		assert_eq(
			int(manager.debug_summary().get("preloaded_scene_count", -1)),
			0
		)
		var tick_result: Dictionary = manager.tick(player_position)
		assert_eq(tick_result.get("activated"), [])
		assert_eq(manager.active_module_coords(), [])


func test_tampered_hash_restore_preserves_committed_world_and_streaming() -> void:
	var manager: MODULE_WORLD_MANAGER_SCRIPT = _configured_world_manager()
	var player_position: Vector2 = manager.global_cell_to_world(Vector2i(5, 5))
	manager.tick(player_position)
	assert_true(manager.set_slot_pinned(Vector2i(6, 6), true))
	manager.set_slot_state(Vector2i(4, 4), {
		"initialized": true,
		"future": {"nested": [1, 2, 3]},
	})
	var before: Dictionary = _capture_manager_state(
		manager,
		Vector2i(4, 4),
		Vector2i(0, 0)
	)
	assert_eq(int(before.get("preloaded_scene_count", 0)), 1)
	assert_true(int(before.get("active_scene_instance_id", 0)) != 0)
	var tampered_snapshot: Dictionary = manager.snapshot()
	var candidate_assignment: Array = (
		(tampered_snapshot.get("assignment", []) as Array).duplicate(true)
	)
	assert_true(_replace_assignment_template(
		candidate_assignment,
		Vector2i(3, 3),
		ALTERNATE_TEMPLATE_ID
	))
	tampered_snapshot["assignment"] = candidate_assignment
	tampered_snapshot["run_seed"] = int(before.get("run_seed", 0)) + 1
	tampered_snapshot["map_hash"] = "tampered-map-hash"
	tampered_snapshot["current_module"] = {"x": 6, "y": 6}
	tampered_snapshot["revealed"] = [{"x": 6, "y": 6}]
	tampered_snapshot["visited"] = [{"x": 5, "y": 5}]
	tampered_snapshot["pinned_slots"] = [{"x": 0, "y": 6}]
	tampered_snapshot["slot_states"] = {
		"5,5": {"candidate_only": true},
	}
	var valid_candidate: Dictionary = tampered_snapshot.duplicate(true)
	valid_candidate["map_hash"] = ""
	var candidate_probe: MODULE_WORLD_MANAGER_SCRIPT = _configured_world_manager()
	assert_true(candidate_probe.restore_state(valid_candidate))
	assert_eq(
		String(candidate_probe.assignment_at(Vector2i(3, 3)).get(
			"template_id",
			""
		)),
		ALTERNATE_TEMPLATE_ID
	)
	assert_eq(
		int(candidate_probe.snapshot().get("run_seed", 0)),
		int(before.get("run_seed", 0)) + 1
	)
	assert_eq(
		int(candidate_probe.debug_summary().get("preloaded_scene_count", 0)),
		2
	)

	var previous_print_error_messages: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	var restore_succeeded: bool = manager.restore_state(tampered_snapshot)
	Engine.print_error_messages = previous_print_error_messages

	assert_false(restore_succeeded)
	_assert_manager_state_unchanged(
		manager,
		before,
		Vector2i(4, 4),
		Vector2i(0, 0)
	)
	assert_eq(manager.slot_state(Vector2i(5, 5)), {})
	assert_true(manager.set_slot_pinned(Vector2i(6, 6), false))
	manager.tick(Vector2(1_000_000.0, 1_000_000.0))
	assert_eq(manager.active_module_coords(), [])
	manager.tick(player_position)
	assert_eq(manager.active_module_coords(), [Vector2i(0, 0)])
	assert_eq(
		_active_scene_instance_id(manager, Vector2i(0, 0)),
		int(before.get("active_scene_instance_id", 0))
	)
	assert_eq(int(manager.debug_summary().get("preloaded_scene_count", 0)), 1)


func test_malformed_assignment_restore_preserves_world_and_dynamic_state() -> void:
	var manager: MODULE_WORLD_MANAGER_SCRIPT = _configured_world_manager()
	manager.tick(manager.global_cell_to_world(Vector2i(5, 5)))
	assert_true(manager.set_slot_pinned(Vector2i(6, 6), true))
	manager.set_slot_state(Vector2i(4, 4), {
		"initialized": true,
		"future": {"stable": true},
	})
	var before: Dictionary = _capture_manager_state(
		manager,
		Vector2i(4, 4),
		Vector2i(0, 0)
	)
	assert_eq(int(before.get("preloaded_scene_count", 0)), 1)
	assert_true(int(before.get("active_scene_instance_id", 0)) != 0)
	var malformed_snapshot: Dictionary = manager.snapshot()
	var malformed_assignment: Array = (
		(malformed_snapshot.get("assignment", []) as Array).duplicate(true)
	)
	malformed_assignment.pop_back()
	malformed_snapshot["assignment"] = malformed_assignment
	malformed_snapshot["run_seed"] = int(before.get("run_seed", 0)) + 1
	malformed_snapshot["current_module"] = {"x": 6, "y": 6}
	malformed_snapshot["revealed"] = [{"x": 6, "y": 6}]
	malformed_snapshot["visited"] = [{"x": 5, "y": 5}]
	malformed_snapshot["pinned_slots"] = [{"x": 0, "y": 6}]
	malformed_snapshot["slot_states"] = {
		"5,5": {"candidate_only": true},
	}

	assert_false(manager.restore_state(malformed_snapshot))
	_assert_manager_state_unchanged(
		manager,
		before,
		Vector2i(4, 4),
		Vector2i(0, 0)
	)
	assert_eq(manager.slot_state(Vector2i(5, 5)), {})


func _capture_manager_state(
	manager: MODULE_WORLD_MANAGER_SCRIPT,
	slot_state_coord: Vector2i,
	active_coord: Vector2i
) -> Dictionary:
	var snapshot_state: Dictionary = manager.snapshot()
	return {
		"assignment": manager.assignment(),
		"run_seed": int(snapshot_state.get("run_seed", 0)),
		"map_hash": manager.map_hash(),
		"active": manager.active_module_coords(),
		"current": manager.current_module_coord(),
		"revealed": manager.revealed_module_coords(),
		"visited": manager.visited_module_coords(),
		"pins": manager.pinned_module_coords(),
		"slot_state": manager.slot_state(slot_state_coord),
		"preloaded_scene_count": int(
			manager.debug_summary().get("preloaded_scene_count", 0)
		),
		"active_scene_instance_id": _active_scene_instance_id(
			manager,
			active_coord
		),
	}


func _assert_manager_state_unchanged(
	manager: MODULE_WORLD_MANAGER_SCRIPT,
	before: Dictionary,
	slot_state_coord: Vector2i,
	active_coord: Vector2i
) -> void:
	assert_eq(manager.assignment(), before.get("assignment"))
	assert_eq(
		int(manager.snapshot().get("run_seed", 0)),
		int(before.get("run_seed", 0))
	)
	assert_eq(manager.map_hash(), before.get("map_hash"))
	assert_eq(manager.active_module_coords(), before.get("active"))
	assert_eq(manager.current_module_coord(), before.get("current"))
	assert_eq(manager.revealed_module_coords(), before.get("revealed"))
	assert_eq(manager.visited_module_coords(), before.get("visited"))
	assert_eq(manager.pinned_module_coords(), before.get("pins"))
	assert_eq(
		manager.slot_state(slot_state_coord),
		before.get("slot_state")
	)
	assert_eq(
		int(manager.debug_summary().get("preloaded_scene_count", 0)),
		int(before.get("preloaded_scene_count", 0))
	)
	assert_eq(
		_active_scene_instance_id(manager, active_coord),
		int(before.get("active_scene_instance_id", 0))
	)


func _replace_assignment_template(
	assignment_entries: Array,
	module_coord: Vector2i,
	template_id: String
) -> bool:
	for raw_entry: Variant in assignment_entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var raw_slot: Variant = entry.get("slot", {})
		if not raw_slot is Dictionary:
			continue
		var slot: Dictionary = raw_slot as Dictionary
		if (
			int(slot.get("x", -1)) == module_coord.x
			and int(slot.get("y", -1)) == module_coord.y
		):
			entry["template_id"] = template_id
			return true
	return false


func _active_scene_instance_id(
	manager: MODULE_WORLD_MANAGER_SCRIPT,
	module_coord: Vector2i
) -> int:
	for child: Node in manager.get_children():
		if not child is RecordingChunk:
			continue
		var chunk: RecordingChunk = child as RecordingChunk
		if chunk.module_coord() == module_coord:
			return chunk.configured_scene_instance_id()
	return 0


func _configured_world_manager() -> MODULE_WORLD_MANAGER_SCRIPT:
	var manager: MODULE_WORLD_MANAGER_SCRIPT = MODULE_WORLD_MANAGER_SCRIPT.new()
	for _chunk_index: int in range(EXPECTED_CHUNK_COUNT):
		manager.add_child(RecordingChunk.new())
	add_child_autofree(manager)
	assert_true(manager.configure(
		_manager_world_definition(),
		_manager_registry(),
		_manager_templates(),
		{
			TEMPLATE_ID: _generated_scene(TEMPLATE_ID),
			ALTERNATE_TEMPLATE_ID: _generated_scene(ALTERNATE_TEMPLATE_ID),
			INVALID_TEMPLATE_ID: _generated_scene(INVALID_TEMPLATE_ID),
		},
		8_109,
		1
	))
	return manager


func _manager_world_definition() -> Dictionary:
	var invalid_assignment: Array[Dictionary] = _world_assignment(
		Vector2i(3, 3)
	)
	return {
		"id": "module_streaming_test_world",
		"columns": WORLD_COLUMNS,
		"rows": WORLD_ROWS,
		"module_columns": MODULE_COLUMNS,
		"module_rows": MODULE_ROWS,
		"cell_size": 160.0,
		"world_origin": {"x": 0.0, "y": 0.0},
		"active_radius": 0,
		"seal_outer_edges": true,
		"template_pool": [TEMPLATE_ID],
		"fixed_slots": [],
		"limited_template_groups": [],
		"objective_spawn": {
			"template_id": TEMPLATE_ID,
			"rotation": 0,
			"candidate_slots": [{"x": 6, "y": 6}],
		},
		"fallback_assignment": invalid_assignment,
		"technical_slice_assignment": invalid_assignment.duplicate(true),
	}


func _manager_registry() -> Dictionary:
	return {
		TEMPLATE_ID: _registry_entry(TEMPLATE_ID),
		ALTERNATE_TEMPLATE_ID: _registry_entry(ALTERNATE_TEMPLATE_ID),
		INVALID_TEMPLATE_ID: _registry_entry(INVALID_TEMPLATE_ID),
	}


func _registry_entry(template_id: String) -> Dictionary:
	return {
		"id": template_id,
		"role": MODULE_ROLES.MODULE_ROLE_CONNECTOR,
		"review_status": MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED,
		"allowed_rotations": [0],
	}


func _manager_templates() -> Dictionary:
	return {
		TEMPLATE_ID: _template_data(TEMPLATE_ID, true),
		ALTERNATE_TEMPLATE_ID: _template_data(
			ALTERNATE_TEMPLATE_ID,
			true
		),
		INVALID_TEMPLATE_ID: _template_data(INVALID_TEMPLATE_ID, false),
	}


func _template_data(template_id: String, connected_edges: bool) -> Dictionary:
	var sockets: Array[int] = []
	if connected_edges:
		sockets.append(5)
	return {
		"id": template_id,
		"edge_sockets": {
			MODULE_EDGE_DIRECTIONS.EDGE_NORTH: sockets.duplicate(),
			MODULE_EDGE_DIRECTIONS.EDGE_EAST: sockets.duplicate(),
			MODULE_EDGE_DIRECTIONS.EDGE_SOUTH: sockets.duplicate(),
			MODULE_EDGE_DIRECTIONS.EDGE_WEST: sockets.duplicate(),
		},
		"terrain_rows": _floor_terrain_rows(),
		"placements": [],
	}


func _floor_terrain_rows() -> Array:
	var result: Array = []
	for _row_index: int in range(MODULE_ROWS):
		var row: Array[String] = []
		for _column_index: int in range(MODULE_COLUMNS):
			row.append(MODULE_CELL_TOKENS.MODULE_CELL_FLOOR)
		result.append(row)
	return result


func _world_assignment(invalid_coord: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			result.append({
				"slot": {"x": column_index, "y": row_index},
				"template_id": (
					INVALID_TEMPLATE_ID
					if module_coord == invalid_coord
					else TEMPLATE_ID
				),
				"rotation": 0,
			})
	return result


func _configured_streaming_controller(
	call_log: Array[String],
	pool: Array[ModuleChunk] = []
) -> MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT:
	var controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT = (
		MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.new()
	)
	var configured_pool: Array[ModuleChunk] = pool
	if configured_pool.is_empty():
		configured_pool = _recording_pool(call_log)
	assert_true(_configure_controller(
		controller,
		{TEMPLATE_ID: _generated_scene(TEMPLATE_ID)},
		configured_pool
	))
	_prepare_live_assignment(controller)
	return controller


func _configure_controller(
	controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT,
	generated_scene_paths_by_id: Dictionary,
	pool: Array[ModuleChunk]
) -> bool:
	var configuration := MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.Configure.new()
	configuration.generated_scene_paths_by_id = generated_scene_paths_by_id
	configuration.chunk_pool = pool
	configuration.expected_chunk_count = EXPECTED_CHUNK_COUNT
	return controller.configure(configuration)


func _prepare_live_assignment(
	controller: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT
) -> void:
	var prepared: MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.PreparedAssignment = (
		controller.prepare_assignment([_assignment_entry(TEMPLATE_ID)])
	)
	assert_true(prepared.is_valid())
	assert_true(controller.commit_prepared(prepared))


func _stream_request(
	center_coord: Vector2i,
	pinned_coords: Array[Vector2i],
	active_radius: int
) -> MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamRequest:
	var request := MODULE_CHUNK_STREAMING_CONTROLLER_SCRIPT.StreamRequest.new()
	request.center_coord = center_coord
	request.pinned_coords = pinned_coords
	request.columns = WORLD_COLUMNS
	request.rows = WORLD_ROWS
	request.active_radius = active_radius
	request.cell_size = 160.0
	request.world_origin = Vector2.ZERO
	request.assignment_provider = func(_module_coord: Vector2i) -> Dictionary:
		return _assignment_entry(TEMPLATE_ID)
	request.masked_edges_provider = func(_module_coord: Vector2i) -> Array:
		return []
	return request


func _assignment_entry(template_id: String) -> Dictionary:
	return {
		"template_id": template_id,
		"rotation": 0,
	}


func _recording_pool(
	call_log: Array[String],
	count: int = EXPECTED_CHUNK_COUNT
) -> Array[ModuleChunk]:
	var result: Array[ModuleChunk] = []
	for _chunk_index: int in range(count):
		var chunk := RecordingChunk.new()
		chunk.call_log = call_log
		add_child_autofree(chunk)
		result.append(chunk)
	return result


func _generated_scene(
	module_id: String,
	baker_schema_version: int = GeneratedModuleScene.BAKER_SCHEMA_VERSION,
	rotation_degrees: int = 0
) -> PackedScene:
	var generated := GeneratedModuleScene.new()
	generated.module_id = module_id
	generated.baker_schema_version = baker_schema_version
	generated.module_rotation_degrees = rotation_degrees
	var packed := PackedScene.new()
	assert_eq(packed.pack(generated), OK)
	generated.free()
	return packed


func _plain_node_scene() -> PackedScene:
	var root := Node2D.new()
	var packed := PackedScene.new()
	assert_eq(packed.pack(root), OK)
	root.free()
	return packed


class RecordingChunk:
	extends ModuleChunk

	var configure_should_fail: bool = false
	var call_log: Array[String] = []
	var _recorded_coord: Vector2i = Vector2i(-1, -1)
	var _configured_scene_instance_id: int = 0


	func configure(
		_generated_scene: PackedScene,
		module_coord_value: Vector2i,
		_rotation: int,
		_masked_edges: Array,
		_cell_size: float,
		_world_origin: Vector2
	) -> bool:
		call_log.append(
			"configure:%d,%d"
			% [module_coord_value.x, module_coord_value.y]
		)
		if _generated_scene == null or configure_should_fail:
			return false
		_recorded_coord = module_coord_value
		_configured_scene_instance_id = _generated_scene.get_instance_id()
		return true


	func clear() -> void:
		call_log.append(
			"clear:%d,%d" % [_recorded_coord.x, _recorded_coord.y]
		)
		_recorded_coord = Vector2i(-1, -1)
		_configured_scene_instance_id = 0


	func module_coord() -> Vector2i:
		return _recorded_coord


	func configured_scene_instance_id() -> int:
		return _configured_scene_instance_id
