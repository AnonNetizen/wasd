extends SmokeHarness


const MODULE_WORLD_LAYOUT_SCRIPT := preload(
	"res://scripts/gameplay/module_world_layout.gd"
)
const MODULE_WORLD_MANAGER_SCRIPT := preload(
	"res://scripts/gameplay/module_world_manager.gd"
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

const WORLD_COLUMNS: int = 7
const WORLD_ROWS: int = 7
const MODULE_COLUMNS: int = 11
const MODULE_ROWS: int = 11
const EXPECTED_CHUNK_COUNT: int = 12
const FLAT_ID: String = "module_layout_flat"
const FIXED_ID: String = "module_layout_fixed"
const OBJECTIVE_ID: String = "module_layout_objective"
const EVENT_ID: String = "module_layout_event"
const TELEPORTER_ID: String = "module_layout_teleporter"
const ALTERNATE_ID: String = "module_layout_alternate"


func test_seeded_assignment_preserves_rng_order_and_dictionary_order() -> void:
	var layout: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(
		_seeded_world_definition()
	)
	var recorder := RandomRecorder.new()
	var port: MODULE_WORLD_LAYOUT_SCRIPT.RandomPort = _random_port(recorder)

	assert_true(layout.build_seeded_assignment(port, "world"))
	assert_true(layout.is_assignment_valid())
	assert_eq(layout.assignment().size(), WORLD_COLUMNS * WORLD_ROWS)
	assert_eq(_assignment_keys(layout).slice(0, 3), [
		"0,6",
		"6,6",
		"0,0",
	])
	var snapshot_entries: Array[Dictionary] = layout.assignment_entries()
	assert_eq(snapshot_entries[0].get("slot"), {"x": 0, "y": 0})
	assert_eq(snapshot_entries[-1].get("slot"), {"x": 6, "y": 6})
	assert_eq(recorder.calls[0], "snapshot")
	assert_true(recorder.calls[1].begins_with("configure:world:"))
	assert_eq(recorder.calls.slice(2, 6), [
		"next",
		"range:0.0:1.0",
		"next",
		"next",
	])
	assert_eq(recorder.calls[-1], "restore")
	assert_eq(recorder.calls.count("next"), 95)
	assert_eq(recorder.calls.count("range:0.0:1.0"), 1)
	assert_eq(recorder.restored_snapshot, {
		"seed": "17",
		"state": "29",
	})


func test_seeded_fixed_and_pool_prechecks_do_not_touch_rng_port() -> void:
	var invalid_fixed_world: Dictionary = _seeded_world_definition()
	invalid_fixed_world["fixed_slots"] = [{
		"slot": {"x": 0, "y": 6},
		"template_id": "missing_template",
		"rotation": 0,
	}]
	var invalid_fixed: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(
		invalid_fixed_world
	)
	var invalid_fixed_recorder := RandomRecorder.new()
	assert_false(invalid_fixed.build_seeded_assignment(
		_random_port(invalid_fixed_recorder),
		"world"
	))
	assert_eq(invalid_fixed_recorder.calls, [])

	var empty_pool_world: Dictionary = _seeded_world_definition()
	empty_pool_world["template_pool"] = []
	var empty_pool: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(
		empty_pool_world
	)
	var empty_pool_recorder := RandomRecorder.new()
	assert_false(empty_pool.build_seeded_assignment(
		_random_port(empty_pool_recorder),
		"world"
	))
	assert_eq(empty_pool_recorder.calls, [])


func test_constrained_limited_group_is_deterministic_and_keeps_minimum_distance() -> void:
	var first_layout: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(
		_teleporter_world_definition(4)
	)
	var second_layout: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(
		_teleporter_world_definition(4)
	)
	assert_true(first_layout.build_seeded_assignment(
		_random_port(RandomRecorder.new()),
		"world"
	))
	assert_true(second_layout.build_seeded_assignment(
		_random_port(RandomRecorder.new()),
		"world"
	))
	assert_eq(first_layout.assignment_entries(), second_layout.assignment_entries())
	var teleporter_coords: Array[Vector2i] = _coords_for_template(
		first_layout,
		TELEPORTER_ID
	)
	assert_eq(teleporter_coords.size(), 3)
	for left_index: int in range(teleporter_coords.size()):
		for right_index: int in range(left_index + 1, teleporter_coords.size()):
			var left: Vector2i = teleporter_coords[left_index]
			var right: Vector2i = teleporter_coords[right_index]
			assert_gte(
				absi(left.x - right.x) + absi(left.y - right.y),
				4
			)


func test_constrained_limited_group_failure_has_no_partial_group_commit() -> void:
	var layout: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(
		_teleporter_world_definition(12)
	)
	assert_false(layout.build_seeded_assignment(
		_random_port(RandomRecorder.new()),
		"world"
	))
	assert_eq(_coords_for_template(layout, TELEPORTER_ID), [])


func test_fallback_rejects_incomplete_or_too_close_constrained_group() -> void:
	var valid_world: Dictionary = _teleporter_world_definition(4)
	var valid_fallback: Array[Dictionary] = _row_major_assignment(FLAT_ID)
	_replace_template(valid_fallback, Vector2i(0, 2), TELEPORTER_ID)
	_replace_template(valid_fallback, Vector2i(3, 3), TELEPORTER_ID)
	_replace_template(valid_fallback, Vector2i(6, 4), TELEPORTER_ID)
	valid_world["fallback_assignment"] = valid_fallback
	var valid_layout: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(valid_world)
	assert_true(valid_layout.load_fallback_assignment())
	assert_eq(_coords_for_template(valid_layout, TELEPORTER_ID).size(), 3)

	var invalid_world: Dictionary = valid_world.duplicate(true)
	var invalid_fallback: Array[Dictionary] = valid_fallback.duplicate(true)
	_replace_template(invalid_fallback, Vector2i(3, 3), FLAT_ID)
	_replace_template(invalid_fallback, Vector2i(1, 2), TELEPORTER_ID)
	invalid_world["fallback_assignment"] = invalid_fallback
	var invalid_layout: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(invalid_world)
	assert_false(invalid_layout.load_fallback_assignment())
	assert_eq(invalid_layout.assignment_count(), 0)


func test_fallback_load_precedes_objective_rng_and_keeps_row_major_order() -> void:
	var layout: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(
		_seeded_world_definition()
	)
	var recorder := RandomRecorder.new()

	assert_true(layout.load_fallback_assignment())
	assert_eq(recorder.calls, [])
	assert_eq(_assignment_keys(layout)[0], "0,0")
	assert_eq(_assignment_keys(layout)[-1], "6,6")
	assert_true(layout.assign_fallback_objective(
		_random_port(recorder),
		"world"
	))

	assert_eq(recorder.calls.size(), 4)
	assert_eq(recorder.calls[0], "snapshot")
	assert_true(recorder.calls[1].begins_with("configure:world:"))
	assert_eq(recorder.calls[2], "next")
	assert_eq(recorder.calls[3], "restore")
	assert_eq(_assignment_keys(layout)[0], "0,0")
	assert_eq(_assignment_keys(layout)[-1], "6,6")
	assert_eq(
		String(layout.assignment_at(Vector2i(6, 6)).get("template_id", "")),
		OBJECTIVE_ID
	)


func test_manager_preserves_fallback_assignment_failure_diagnostic() -> void:
	var world_def: Dictionary = _manager_fallback_world_definition()
	var malformed_fallback: Array[Dictionary] = _row_major_assignment(FLAT_ID)
	malformed_fallback.pop_back()
	world_def["fallback_assignment"] = malformed_fallback
	var manager: RecordingManager = _manager_for_fallback_failure(world_def)

	assert_false(manager.configure_result)
	assert_push_warning(
		"[ModuleWorldManager] generated assignment invalid; using checked-in fallback assignment"
	)
	assert_eq(manager.reported_errors, [
		"[ModuleWorldManager] fallback assignment could not be loaded"
	])


func test_manager_preserves_fallback_objective_failure_diagnostic() -> void:
	var world_def: Dictionary = _manager_fallback_world_definition()
	var manager: RecordingManager = _manager_for_fallback_failure(world_def)

	assert_false(manager.configure_result)
	assert_push_warning(
		"[ModuleWorldManager] generated assignment invalid; using checked-in fallback assignment"
	)
	assert_eq(manager.reported_errors, [
		"[ModuleWorldManager] fallback objective spawn could not be selected"
	])


func test_restore_candidate_is_atomic_and_map_hash_is_content_sensitive() -> void:
	var layout: MODULE_WORLD_LAYOUT_SCRIPT = _configured_layout(
		_seeded_world_definition()
	)
	assert_true(layout.build_technical_slice_assignment())
	assert_true(layout.is_assignment_valid())
	var live_hash: String = layout.compute_map_hash()
	layout.commit_map_hash(live_hash)
	var live_assignment: Dictionary = layout.assignment()
	var live_seed: int = layout.run_seed()
	var candidate_entries: Array[Dictionary] = layout.assignment_entries()
	_replace_template(candidate_entries, Vector2i(3, 3), ALTERNATE_ID)

	var candidate: MODULE_WORLD_LAYOUT_SCRIPT.RestoreCandidate = (
		layout.prepare_restore_assignment(candidate_entries, live_seed + 1)
	)
	assert_true(candidate.is_valid())
	var candidate_hash: String = layout.map_hash_for_candidate(candidate)
	assert_false(candidate_hash.is_empty())
	assert_ne(candidate_hash, live_hash)
	assert_eq(layout.assignment(), live_assignment)
	assert_eq(layout.run_seed(), live_seed)
	assert_eq(layout.map_hash(), live_hash)
	var exposed_candidate: Dictionary = candidate.assignment()
	exposed_candidate.clear()
	assert_eq(candidate.assignment().size(), WORLD_COLUMNS * WORLD_ROWS)

	var malformed_entries: Array[Dictionary] = candidate_entries.duplicate(true)
	malformed_entries.pop_back()
	var malformed: MODULE_WORLD_LAYOUT_SCRIPT.RestoreCandidate = (
		layout.prepare_restore_assignment(malformed_entries, live_seed + 2)
	)
	assert_false(malformed.is_valid())
	assert_eq(layout.assignment(), live_assignment)
	assert_eq(layout.map_hash(), live_hash)

	layout.commit_restore(candidate, candidate_hash)
	assert_eq(layout.run_seed(), live_seed + 1)
	assert_eq(layout.map_hash(), candidate_hash)
	assert_eq(
		String(layout.assignment_at(Vector2i(3, 3)).get("template_id", "")),
		ALTERNATE_ID
	)


func test_coordinate_rotation_terrain_footprint_and_hash_are_pure() -> void:
	var world_def: Dictionary = _seeded_world_definition()
	world_def["world_origin"] = {"x": 40.0, "y": -80.0}
	var technical_entries: Array[Dictionary] = _row_major_assignment(FLAT_ID)
	_replace_template(technical_entries, Vector2i(3, 3), ALTERNATE_ID, 90)
	world_def["technical_slice_assignment"] = technical_entries
	var templates: Dictionary = _templates()
	(templates[ALTERNATE_ID] as Dictionary)["placements"] = [{
		"kind": "test_placement",
		"cell": {"x": 1, "y": 2},
		"footprint": {"width": 2, "height": 1},
	}]
	var layout := MODULE_WORLD_LAYOUT_SCRIPT.new()
	assert_true(layout.configure(
		world_def,
		_registry(),
		templates,
		8_109
	))
	assert_true(layout.build_technical_slice_assignment())
	assert_true(layout.is_assignment_valid())

	assert_eq(layout.global_cell_to_world(Vector2i(38, 38)), Vector2(40.0, -80.0))
	assert_eq(layout.world_to_global_cell(Vector2(40.0, -80.0)), Vector2i(38, 38))
	assert_eq(layout.global_cell_to_module_and_local(Vector2i(38, 38)), {
		"module_coord": Vector2i(3, 3),
		"local_cell": Vector2i(5, 5),
	})
	assert_eq(layout.masked_edges_for_coord(Vector2i(0, 0)), [
		MODULE_EDGE_DIRECTIONS.EDGE_NORTH,
		MODULE_EDGE_DIRECTIONS.EDGE_WEST,
	])
	assert_false(layout.is_global_cell_walkable(Vector2i(0, 0)))
	assert_true(layout.is_global_cell_walkable(Vector2i(38, 38)))

	var placements: Array[Dictionary] = layout.placements_at(Vector2i(3, 3))
	assert_eq(placements.size(), 1)
	assert_eq(placements[0].get("cell"), {"x": 8, "y": 1})
	assert_eq(placements[0].get("module_coord"), {"x": 3, "y": 3})
	var occupied_a: Vector2 = layout.global_cell_to_world(
		layout.module_local_to_global_cell(Vector2i(3, 3), Vector2i(8, 1))
	)
	var occupied_b: Vector2 = layout.global_cell_to_world(
		layout.module_local_to_global_cell(Vector2i(3, 3), Vector2i(8, 2))
	)
	assert_eq(placements[0].get("world_position"), {
		"x": occupied_a.x,
		"y": occupied_a.y,
	})
	var empty_positions: Array[Vector2] = layout.empty_floor_positions_at(
		Vector2i(3, 3)
	)
	assert_eq(empty_positions.size(), MODULE_COLUMNS * MODULE_ROWS - 2)
	assert_false(empty_positions.has(occupied_a))
	assert_false(empty_positions.has(occupied_b))

	var first_hash: String = layout.compute_map_hash()
	var second_layout := MODULE_WORLD_LAYOUT_SCRIPT.new()
	assert_true(second_layout.configure(
		world_def,
		_registry(),
		templates,
		8_109
	))
	assert_true(second_layout.build_technical_slice_assignment())
	assert_eq(second_layout.compute_map_hash(), first_hash)
	(templates[ALTERNATE_ID] as Dictionary)["future_geometry"] = {"version": 2}
	var changed_layout := MODULE_WORLD_LAYOUT_SCRIPT.new()
	assert_true(changed_layout.configure(
		world_def,
		_registry(),
		templates,
		8_109
	))
	assert_true(changed_layout.build_technical_slice_assignment())
	assert_ne(changed_layout.compute_map_hash(), first_hash)


func _configured_layout(world_def: Dictionary) -> MODULE_WORLD_LAYOUT_SCRIPT:
	var layout := MODULE_WORLD_LAYOUT_SCRIPT.new()
	assert_true(layout.configure(
		world_def,
		_registry(),
		_templates(),
		8_109
	))
	return layout


func _manager_for_fallback_failure(world_def: Dictionary) -> RecordingManager:
	var manager := RecordingManager.new()
	for _chunk_index: int in range(EXPECTED_CHUNK_COUNT):
		manager.add_child(ModuleChunk.new())
	add_child_autofree(manager)
	manager.configure_result = manager.configure(
		world_def,
		{FLAT_ID: _registry_entry(MODULE_ROLES.MODULE_ROLE_CONNECTOR, [0])},
		{FLAT_ID: _template_data(FLAT_ID)},
		{FLAT_ID: _generated_scene(FLAT_ID)},
		8_109,
		1
	)
	return manager


func _manager_fallback_world_definition() -> Dictionary:
	return {
		"id": "module_layout_fallback_failure_world",
		"columns": WORLD_COLUMNS,
		"rows": WORLD_ROWS,
		"module_columns": MODULE_COLUMNS,
		"module_rows": MODULE_ROWS,
		"cell_size": 160.0,
		"world_origin": {"x": 0.0, "y": 0.0},
		"active_radius": 0,
		"seal_outer_edges": true,
		"template_pool": [FLAT_ID],
		"fixed_slots": [],
		"limited_template_groups": [],
		"objective_spawn": {
			"template_id": FLAT_ID,
			"rotation": 0,
			"candidate_slots": [],
		},
		"fallback_assignment": _row_major_assignment(FLAT_ID),
		"technical_slice_assignment": _row_major_assignment(FLAT_ID),
	}


func _generated_scene(template_id: String) -> PackedScene:
	var generated := GeneratedModuleScene.new()
	generated.module_id = template_id
	generated.baker_schema_version = GeneratedModuleScene.BAKER_SCHEMA_VERSION
	generated.module_rotation_degrees = 0
	var packed := PackedScene.new()
	assert_eq(packed.pack(generated), OK)
	generated.free()
	return packed


func _seeded_world_definition() -> Dictionary:
	var fallback: Array[Dictionary] = _row_major_assignment(FLAT_ID)
	return {
		"id": "module_layout_test_world",
		"columns": WORLD_COLUMNS,
		"rows": WORLD_ROWS,
		"module_columns": MODULE_COLUMNS,
		"module_rows": MODULE_ROWS,
		"cell_size": 160.0,
		"world_origin": {"x": 0.0, "y": 0.0},
		"seal_outer_edges": true,
		"template_pool": [FLAT_ID],
		"fixed_slots": [{
			"slot": {"x": 0, "y": 6},
			"template_id": FIXED_ID,
			"rotation": 0,
		}],
		"limited_template_groups": [{
			"pick_distinct": 1,
			"minimum_manhattan_distance": 0,
			"entries": [{
				"template_id": EVENT_ID,
				"count_per_floor": 1,
				"weight": 1.0,
			}],
		}],
		"objective_spawn": {
			"template_id": OBJECTIVE_ID,
			"rotation": 0,
			"candidate_slots": [{"x": 6, "y": 6}],
		},
		"fallback_assignment": fallback,
		"technical_slice_assignment": fallback.duplicate(true),
	}


func _teleporter_world_definition(minimum_distance: int) -> Dictionary:
	var world_def: Dictionary = _seeded_world_definition()
	var event_group: Dictionary = (
		(world_def.get("limited_template_groups", []) as Array)[0]
		as Dictionary
	).duplicate(true)
	world_def["limited_template_groups"] = [
		event_group,
		{
			"pick_distinct": 1,
			"minimum_manhattan_distance": minimum_distance,
			"entries": [{
				"template_id": TELEPORTER_ID,
				"count_per_floor": 3,
				"weight": 1.0,
			}],
		},
	]
	return world_def


func _registry() -> Dictionary:
	return {
		FLAT_ID: _registry_entry(MODULE_ROLES.MODULE_ROLE_CONNECTOR, [0]),
		FIXED_ID: _registry_entry(MODULE_ROLES.MODULE_ROLE_START, [0]),
		OBJECTIVE_ID: _registry_entry(MODULE_ROLES.MODULE_ROLE_OBJECTIVE, [0]),
		EVENT_ID: _registry_entry(MODULE_ROLES.MODULE_ROLE_WORLD_EVENT, [0]),
		TELEPORTER_ID: _registry_entry(MODULE_ROLES.MODULE_ROLE_CONNECTOR, [0]),
		ALTERNATE_ID: _registry_entry(MODULE_ROLES.MODULE_ROLE_CONNECTOR, [0, 90]),
	}


func _registry_entry(role: String, rotations: Array[int]) -> Dictionary:
	return {
		"role": role,
		"review_status": MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED,
		"allowed_rotations": rotations,
	}


func _templates() -> Dictionary:
	return {
		FLAT_ID: _template_data(FLAT_ID),
		FIXED_ID: _template_data(FIXED_ID),
		OBJECTIVE_ID: _template_data(OBJECTIVE_ID),
		EVENT_ID: _template_data(EVENT_ID),
		TELEPORTER_ID: _template_data(TELEPORTER_ID),
		ALTERNATE_ID: _template_data(ALTERNATE_ID),
	}


func _template_data(template_id: String) -> Dictionary:
	return {
		"id": template_id,
		"edge_sockets": {
			MODULE_EDGE_DIRECTIONS.EDGE_NORTH: [5],
			MODULE_EDGE_DIRECTIONS.EDGE_EAST: [5],
			MODULE_EDGE_DIRECTIONS.EDGE_SOUTH: [5],
			MODULE_EDGE_DIRECTIONS.EDGE_WEST: [5],
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


func _row_major_assignment(template_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			result.append({
				"slot": {"x": column_index, "y": row_index},
				"template_id": template_id,
				"rotation": 0,
			})
	return result


func _replace_template(
	entries: Array[Dictionary],
	module_coord: Vector2i,
	template_id: String,
	rotation: int = 0
) -> void:
	for entry: Dictionary in entries:
		var slot: Dictionary = entry.get("slot", {}) as Dictionary
		if (
			int(slot.get("x", -1)) == module_coord.x
			and int(slot.get("y", -1)) == module_coord.y
		):
			entry["template_id"] = template_id
			entry["rotation"] = rotation
			return


func _assignment_keys(layout: MODULE_WORLD_LAYOUT_SCRIPT) -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in layout.assignment().keys():
		result.append(String(raw_key))
	return result


func _coords_for_template(
	layout: MODULE_WORLD_LAYOUT_SCRIPT,
	template_id: String
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for entry: Dictionary in layout.assignment_entries():
		if String(entry.get("template_id", "")) != template_id:
			continue
		var slot: Dictionary = entry.get("slot", {}) as Dictionary
		result.append(Vector2i(
			int(slot.get("x", -1)),
			int(slot.get("y", -1))
		))
	return result


func _random_port(
	recorder: RandomRecorder
) -> MODULE_WORLD_LAYOUT_SCRIPT.RandomPort:
	return MODULE_WORLD_LAYOUT_SCRIPT.RandomPort.new(
		Callable(recorder, "snapshot"),
		Callable(recorder, "configure"),
		Callable(recorder, "restore_snapshot"),
		Callable(recorder, "next_u32"),
		Callable(recorder, "range_f32")
	)


class RandomRecorder extends RefCounted:
	var calls: Array[String] = []
	var restored_snapshot: Dictionary = {}


	func snapshot() -> Dictionary:
		calls.append("snapshot")
		return {
			"seed": "17",
			"state": "29",
		}


	func configure(stream_id: String, seed_value: int) -> void:
		calls.append("configure:%s:%d" % [stream_id, seed_value])


	func restore_snapshot(snapshot_data: Dictionary) -> void:
		calls.append("restore")
		restored_snapshot = snapshot_data.duplicate(true)


	func next_u32() -> int:
		calls.append("next")
		return 0


	func range_f32(from: float, to: float) -> float:
		calls.append("range:%.1f:%.1f" % [from, to])
		return from


class RecordingManager:
	extends ModuleWorldManager

	var configure_result: bool = false
	var reported_errors: Array[String] = []


	func _report_fallback_error(message: String) -> void:
		reported_errors.append(message)
