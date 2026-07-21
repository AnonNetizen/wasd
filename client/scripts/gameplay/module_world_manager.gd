# Doc: docs/代码/module_world_manager.md
class_name ModuleWorldManager
extends Node2D
## Deterministic 9 x 9 module-world assignment, coordinate conversion, fog state and 3 x 3 streaming.
## Gameplay entity spawning remains owned by GameplayRunLoop; this manager only streams reusable ModuleChunk nodes.

const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_EDGE_DIRECTIONS := preload("res://scripts/contracts/module_edge_directions.gd")
const MODULE_REVIEW_STATUSES := preload("res://scripts/contracts/module_review_statuses.gd")
const MODULE_ROLES := preload("res://scripts/contracts/module_roles.gd")
const RNG_STREAMS := preload("res://scripts/contracts/rng_streams.gd")
const ModuleChunkRuntime := preload("res://scripts/gameplay/module_chunk.gd")

const WORLD_COLUMNS: int = 9
const WORLD_ROWS: int = 9
const MODULE_COLUMNS: int = 11
const MODULE_ROWS: int = 11
const WORLD_CELL_COLUMNS: int = WORLD_COLUMNS * MODULE_COLUMNS
const WORLD_CELL_ROWS: int = WORLD_ROWS * MODULE_ROWS
const WORLD_CENTER_GLOBAL_CELL: Vector2i = Vector2i(49, 49)
const MAX_ACTIVE_CHUNKS: int = 9
const ROTATION_STEP: int = 90
const ROTATION_FULL: int = 360
const ASSIGNMENT_SEED_MODULUS: int = 2_147_483_647
const INVALID_COORD: Vector2i = Vector2i(-1, -1)
const MODULE_TERRAIN_Z_INDEX: int = -90

var _world_def: Dictionary = {}
var _registry_by_id: Dictionary = {}
var _templates_by_id: Dictionary = {}
var _run_seed: int = 1
var _cell_size: float = 160.0
var _world_origin: Vector2 = Vector2.ZERO
var _active_radius: int = 1
var _assignment: Dictionary = {}
var _map_hash: String = ""
var _current_module_coord: Vector2i = INVALID_COORD
var _revealed: Dictionary = {}
var _visited: Dictionary = {}
var _slot_states: Dictionary = {}
var _active_chunks: Dictionary = {}
var _chunk_pool: Array[ModuleChunkRuntime] = []
var _configured: bool = false


func _init() -> void:
	z_index = MODULE_TERRAIN_Z_INDEX


func configure(
	world_def: Dictionary,
	registry_by_id: Dictionary,
	templates_by_id: Dictionary,
	run_seed: int
) -> bool:
	_deactivate_all_chunks()
	_world_def = world_def.duplicate(true)
	_registry_by_id = registry_by_id.duplicate(true)
	_templates_by_id = templates_by_id.duplicate(true)
	_run_seed = run_seed
	_cell_size = float(_world_def.get("cell_size", 160.0))
	_world_origin = _vector_from_variant(_world_def.get("world_origin", {}), Vector2.ZERO)
	_active_radius = clampi(int(_world_def.get("active_radius", 1)), 0, 1)
	_configured = _has_supported_geometry() and _cell_size > 0.0
	if not _configured:
		push_error("[ModuleWorldManager] world geometry must be 9 x 9 modules of 11 x 11 cells with a positive cell size")
		return false
	_ensure_chunk_pool()
	return build_assignment()


func build_assignment() -> bool:
	if not _configured:
		return false
	_reset_world_state()
	if _build_seeded_assignment() and _finalize_assignment():
		return true
	push_warning("[ModuleWorldManager] generated assignment invalid; using checked-in fallback assignment")
	return build_fallback_assignment()


func build_fallback_assignment() -> bool:
	if not _configured:
		return false
	_reset_world_state()
	if not _load_explicit_assignment(_world_def.get("fallback_assignment", []), false):
		push_error("[ModuleWorldManager] fallback assignment could not be loaded")
		return false
	return _finalize_assignment()


func build_technical_slice_assignment() -> bool:
	if not _configured:
		return false
	_reset_world_state()
	if not _load_explicit_assignment(_world_def.get("technical_slice_assignment", []), true):
		push_error("[ModuleWorldManager] technical-slice assignment could not be loaded")
		return false
	return _finalize_assignment()


func tick(player_position: Vector2) -> Dictionary:
	var global_cell: Vector2i = world_to_global_cell(player_position)
	var module_and_local: Dictionary = global_cell_to_module_and_local(global_cell)
	var next_coord: Vector2i = module_and_local.get("module_coord", INVALID_COORD) as Vector2i
	if not _is_module_coord_valid(next_coord):
		var outside_deactivated: Array[Dictionary] = _deactivate_all_chunks()
		_current_module_coord = INVALID_COORD
		return {
			"current_module": {},
			"entered": false,
			"revealed_now": false,
			"visited_now": false,
			"activated": [],
			"deactivated": outside_deactivated,
			"outside_world": true,
		}

	var entered: bool = next_coord != _current_module_coord
	_current_module_coord = next_coord
	var slot_key: String = _slot_key(next_coord)
	var revealed_now: bool = not _revealed.has(slot_key)
	var visited_now: bool = not _visited.has(slot_key)
	_revealed[slot_key] = true
	_visited[slot_key] = true
	var streaming_change: Dictionary = _refresh_active_modules(next_coord)
	return {
		"current_module": _coord_to_dict(next_coord),
		"local_cell": _coord_to_dict(module_and_local.get("local_cell", INVALID_COORD) as Vector2i),
		"entered": entered,
		"revealed_now": revealed_now,
		"visited_now": visited_now,
		"activated": streaming_change.get("activated", []),
		"deactivated": streaming_change.get("deactivated", []),
		"outside_world": false,
	}


func world_to_global_cell(world_position: Vector2) -> Vector2i:
	var relative_position: Vector2 = world_position - _world_origin
	return Vector2i(
		int(floorf(relative_position.x / _cell_size + float(WORLD_CENTER_GLOBAL_CELL.x) + 0.5)),
		int(floorf(relative_position.y / _cell_size + float(WORLD_CENTER_GLOBAL_CELL.y) + 0.5))
	)


func global_cell_to_world(global_cell: Vector2i) -> Vector2:
	return _world_origin + Vector2(
		float(global_cell.x - WORLD_CENTER_GLOBAL_CELL.x) * _cell_size,
		float(global_cell.y - WORLD_CENTER_GLOBAL_CELL.y) * _cell_size
	)


func is_world_position_walkable(world_position: Vector2) -> bool:
	var global_cell: Vector2i = world_to_global_cell(world_position)
	return _is_global_cell_valid(global_cell) and _terrain_at_global_cell(global_cell) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR


func global_cell_to_module_and_local(global_cell: Vector2i) -> Dictionary:
	if not _is_global_cell_valid(global_cell):
		return {
			"module_coord": INVALID_COORD,
			"local_cell": INVALID_COORD,
		}
	return {
		"module_coord": Vector2i(global_cell.x / MODULE_COLUMNS, global_cell.y / MODULE_ROWS),
		"local_cell": Vector2i(global_cell.x % MODULE_COLUMNS, global_cell.y % MODULE_ROWS),
	}


func module_local_to_global_cell(module_coord: Vector2i, local_cell: Vector2i) -> Vector2i:
	if not _is_module_coord_valid(module_coord) or not _is_local_cell_valid(local_cell):
		return INVALID_COORD
	return Vector2i(
		module_coord.x * MODULE_COLUMNS + local_cell.x,
		module_coord.y * MODULE_ROWS + local_cell.y
	)


func assignment() -> Dictionary:
	return _assignment.duplicate(true)


func assignment_at(module_coord: Vector2i) -> Dictionary:
	return _dictionary_or_empty(_assignment.get(_slot_key(module_coord), {}))


func role_module_coord(role: String) -> Vector2i:
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			var entry: Dictionary = assignment_at(module_coord)
			var template_id: String = String(entry.get("template_id", ""))
			if not _registry_by_id.has(template_id):
				continue
			if String((_registry_by_id[template_id] as Dictionary).get("role", "")) == role:
				return module_coord
	return INVALID_COORD


func placements_at(module_coord: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _is_module_coord_valid(module_coord):
		return result
	var entry: Dictionary = assignment_at(module_coord)
	var template_data: Dictionary = _dictionary_or_empty(_templates_by_id.get(String(entry.get("template_id", "")), {}))
	var rotation_degrees: int = int(entry.get("rotation", 0))
	for raw_placement: Variant in _array_or_empty(template_data.get("placements", [])):
		if not raw_placement is Dictionary:
			continue
		var placement: Dictionary = (raw_placement as Dictionary).duplicate(true)
		var source_cell: Vector2i = _coord_from_variant(placement.get("cell", {}), INVALID_COORD)
		var local_cell: Vector2i = _rotate_local_cell(source_cell, rotation_degrees)
		if not _is_local_cell_valid(local_cell) or _cell_is_masked(module_coord, local_cell):
			continue
		var global_cell: Vector2i = module_local_to_global_cell(module_coord, local_cell)
		placement["cell"] = _coord_to_dict(local_cell)
		placement["module_coord"] = _coord_to_dict(module_coord)
		placement["world_position"] = _vector_to_dict(global_cell_to_world(global_cell))
		result.append(placement)
	return result


func map_hash() -> String:
	return _map_hash


func current_module_coord() -> Vector2i:
	return _current_module_coord


func revealed_module_coords() -> Array[Vector2i]:
	return _coords_from_set(_revealed)


func visited_module_coords() -> Array[Vector2i]:
	return _coords_from_set(_visited)


func active_module_coords() -> Array[Vector2i]:
	return _coords_from_set(_active_chunks)


func is_module_revealed(module_coord: Vector2i) -> bool:
	return _revealed.has(_slot_key(module_coord))


func is_module_visited(module_coord: Vector2i) -> bool:
	return _visited.has(_slot_key(module_coord))


func is_module_active(module_coord: Vector2i) -> bool:
	return _active_chunks.has(_slot_key(module_coord))


func set_slot_state(module_coord: Vector2i, state: Dictionary) -> void:
	if not _is_module_coord_valid(module_coord):
		return
	_slot_states[_slot_key(module_coord)] = state.duplicate(true)


func slot_state(module_coord: Vector2i) -> Dictionary:
	return _dictionary_or_empty(_slot_states.get(_slot_key(module_coord), {}))


func snapshot() -> Dictionary:
	return {
		"world_id": String(_world_def.get("id", "")),
		"run_seed": _run_seed,
		"assignment": _assignment_entries(),
		"map_hash": _map_hash,
		"current_module": _coord_to_dict(_current_module_coord) if _is_module_coord_valid(_current_module_coord) else {},
		"revealed": _coords_to_dict_array(revealed_module_coords()),
		"visited": _coords_to_dict_array(visited_module_coords()),
		"slot_states": _ordered_slot_states(),
	}


func restore_state(state: Dictionary) -> bool:
	if not _configured:
		return false
	var saved_world_id: String = String(state.get("world_id", ""))
	var configured_world_id: String = String(_world_def.get("id", ""))
	if not saved_world_id.is_empty() and saved_world_id != configured_world_id:
		push_error("[ModuleWorldManager] snapshot world id does not match configured world")
		return false
	var restored_assignment: Dictionary = {}
	var previous_assignment: Dictionary = _assignment
	_assignment = restored_assignment
	if not _load_explicit_assignment(state.get("assignment", []), true):
		_assignment = previous_assignment
		return false
	if not _assignment_is_valid():
		_assignment = previous_assignment
		return false
	var previous_run_seed: int = _run_seed
	_run_seed = int(state.get("run_seed", _run_seed))
	var restored_hash: String = _compute_map_hash()
	var saved_hash: String = String(state.get("map_hash", ""))
	if not saved_hash.is_empty() and saved_hash != restored_hash:
		push_error("[ModuleWorldManager] snapshot map hash does not match assignment")
		_assignment = previous_assignment
		_run_seed = previous_run_seed
		return false

	_deactivate_all_chunks()
	_map_hash = restored_hash
	_revealed = _set_from_coord_array(state.get("revealed", []))
	_visited = _set_from_coord_array(state.get("visited", []))
	_slot_states = _validated_slot_states(state.get("slot_states", {}))
	_current_module_coord = _coord_from_variant(state.get("current_module", {}), INVALID_COORD)
	if _is_module_coord_valid(_current_module_coord):
		_refresh_active_modules(_current_module_coord)
	return true


func debug_summary() -> Dictionary:
	return {
		"world_id": String(_world_def.get("id", "")),
		"configured": _configured,
		"run_seed": _run_seed,
		"columns": WORLD_COLUMNS,
		"rows": WORLD_ROWS,
		"module_columns": MODULE_COLUMNS,
		"module_rows": MODULE_ROWS,
		"global_columns": WORLD_CELL_COLUMNS,
		"global_rows": WORLD_CELL_ROWS,
		"cell_size": _cell_size,
		"world_origin": _vector_to_dict(_world_origin),
		"assignment_count": _assignment.size(),
		"map_hash": _map_hash,
		"current_module": _coord_to_dict(_current_module_coord) if _is_module_coord_valid(_current_module_coord) else {},
		"revealed_count": _revealed.size(),
		"visited_count": _visited.size(),
		"active_count": _active_chunks.size(),
		"revealed_slots": _coords_to_dict_array(revealed_module_coords()),
		"visited_slots": _coords_to_dict_array(visited_module_coords()),
		"active_slots": _coords_to_dict_array(active_module_coords()),
		"chunk_pool_size": _chunk_pool.size(),
	}


func _build_seeded_assignment() -> bool:
	if not _load_partial_assignment(_world_def.get("fixed_slots", []), false):
		return false
	var pool_ids: Array[String] = _approved_pool_ids()
	if pool_ids.is_empty():
		return false
	var world_rng_snapshot: Dictionary = RNG.world.snapshot()
	RNG.world.configure(RNG_STREAMS.WORLD, _assignment_seed())
	var generated_all_slots: bool = true
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			if _assignment.has(_slot_key(module_coord)):
				continue
			if not _assign_random_pool_template(module_coord, pool_ids):
				generated_all_slots = false
				break
		if not generated_all_slots:
			break
	RNG.world.restore_snapshot(world_rng_snapshot)
	return generated_all_slots


func _assign_random_pool_template(module_coord: Vector2i, pool_ids: Array[String]) -> bool:
	var template_start: int = int(RNG.world.randi() % pool_ids.size())
	for template_offset: int in range(pool_ids.size()):
		var template_id: String = pool_ids[(template_start + template_offset) % pool_ids.size()]
		var rotations: Array[int] = _allowed_rotations(template_id)
		if rotations.is_empty():
			continue
		var rotation_start: int = int(RNG.world.randi() % rotations.size())
		for rotation_offset: int in range(rotations.size()):
			var rotation_degrees: int = rotations[(rotation_start + rotation_offset) % rotations.size()]
			var entry: Dictionary = _make_assignment_entry(module_coord, template_id, rotation_degrees)
			_assignment[_slot_key(module_coord)] = entry
			if _entry_fits_assigned_neighbors(module_coord):
				return true
			_assignment.erase(_slot_key(module_coord))
	return false


func _approved_pool_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_template_id: Variant in _array_or_empty(_world_def.get("template_pool", [])):
		var template_id: String = String(raw_template_id)
		var registry_entry: Dictionary = _dictionary_or_empty(_registry_by_id.get(template_id, {}))
		if String(registry_entry.get("review_status", "")) != MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED:
			continue
		if not _templates_by_id.has(template_id):
			continue
		if not result.has(template_id):
			result.append(template_id)
	return result


func _allowed_rotations(template_id: String) -> Array[int]:
	var result: Array[int] = []
	var registry_entry: Dictionary = _dictionary_or_empty(_registry_by_id.get(template_id, {}))
	for raw_rotation: Variant in _array_or_empty(registry_entry.get("allowed_rotations", [0])):
		var rotation_degrees: int = _normalize_rotation(int(raw_rotation))
		if not result.has(rotation_degrees):
			result.append(rotation_degrees)
	if result.is_empty():
		result.append(0)
	return result


func _load_explicit_assignment(raw_entries: Variant, allow_unapproved: bool) -> bool:
	_assignment.clear()
	if not _load_partial_assignment(raw_entries, allow_unapproved):
		return false
	return _assignment.size() == WORLD_COLUMNS * WORLD_ROWS


func _load_partial_assignment(raw_entries: Variant, allow_unapproved: bool) -> bool:
	if not raw_entries is Array:
		return false
	for raw_entry: Variant in raw_entries as Array:
		if not raw_entry is Dictionary:
			return false
		var entry_data: Dictionary = raw_entry as Dictionary
		var module_coord: Vector2i = _coord_from_variant(entry_data.get("slot", {}), INVALID_COORD)
		var template_id: String = String(entry_data.get("template_id", ""))
		var rotation_degrees: int = _normalize_rotation(int(entry_data.get("rotation", 0)))
		if not _is_module_coord_valid(module_coord) or not _templates_by_id.has(template_id):
			return false
		var registry_entry: Dictionary = _dictionary_or_empty(_registry_by_id.get(template_id, {}))
		if registry_entry.is_empty():
			return false
		if not _is_assignment_template_allowed(registry_entry, allow_unapproved):
			return false
		if not _allowed_rotations(template_id).has(rotation_degrees):
			return false
		var slot_key: String = _slot_key(module_coord)
		if _assignment.has(slot_key):
			return false
		_assignment[slot_key] = _make_assignment_entry(module_coord, template_id, rotation_degrees)
	return true


func _is_assignment_template_allowed(registry_entry: Dictionary, allow_unapproved: bool) -> bool:
	if String(registry_entry.get("review_status", "")) == MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED:
		return true
	return allow_unapproved and String(registry_entry.get("role", "")) == MODULE_ROLES.MODULE_ROLE_SEALED


func _make_assignment_entry(module_coord: Vector2i, template_id: String, rotation_degrees: int) -> Dictionary:
	var registry_entry: Dictionary = _dictionary_or_empty(_registry_by_id.get(template_id, {}))
	return {
		"slot": _coord_to_dict(module_coord),
		"template_id": template_id,
		"role": String(registry_entry.get("role", "")),
		"rotation": _normalize_rotation(rotation_degrees),
	}


func _finalize_assignment() -> bool:
	if not _assignment_is_valid():
		return false
	_map_hash = _compute_map_hash()
	return true


func _assignment_is_valid() -> bool:
	if _assignment.size() != WORLD_COLUMNS * WORLD_ROWS:
		return false
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			var entry: Dictionary = assignment_at(module_coord)
			if entry.is_empty() or not _templates_by_id.has(String(entry.get("template_id", ""))):
				return false
			if not _entry_fits_assigned_neighbors(module_coord):
				return false
	return _all_floor_cells_reachable()


func _entry_fits_assigned_neighbors(module_coord: Vector2i) -> bool:
	if _is_sealed_module(module_coord):
		return true
	var neighbor_checks: Array[Dictionary] = [
		{"offset": Vector2i.UP, "edge": MODULE_EDGE_DIRECTIONS.EDGE_NORTH, "opposite": MODULE_EDGE_DIRECTIONS.EDGE_SOUTH},
		{"offset": Vector2i.RIGHT, "edge": MODULE_EDGE_DIRECTIONS.EDGE_EAST, "opposite": MODULE_EDGE_DIRECTIONS.EDGE_WEST},
		{"offset": Vector2i.DOWN, "edge": MODULE_EDGE_DIRECTIONS.EDGE_SOUTH, "opposite": MODULE_EDGE_DIRECTIONS.EDGE_NORTH},
		{"offset": Vector2i.LEFT, "edge": MODULE_EDGE_DIRECTIONS.EDGE_WEST, "opposite": MODULE_EDGE_DIRECTIONS.EDGE_EAST},
	]
	for check: Dictionary in neighbor_checks:
		var neighbor_coord: Vector2i = module_coord + (check.get("offset", Vector2i.ZERO) as Vector2i)
		if not _is_module_coord_valid(neighbor_coord):
			if not bool(_world_def.get("seal_outer_edges", false)) and not _rotated_edge_sockets(module_coord, String(check.get("edge", ""))).is_empty():
				return false
			continue
		if not _assignment.has(_slot_key(neighbor_coord)):
			continue
		if _is_sealed_module(neighbor_coord):
			continue
		var current_sockets: Array[int] = _rotated_edge_sockets(module_coord, String(check.get("edge", "")))
		var neighbor_sockets: Array[int] = _rotated_edge_sockets(neighbor_coord, String(check.get("opposite", "")))
		if current_sockets != neighbor_sockets:
			return false
	return true


func _rotated_edge_sockets(module_coord: Vector2i, world_edge: String) -> Array[int]:
	var entry: Dictionary = assignment_at(module_coord)
	var template_data: Dictionary = _dictionary_or_empty(_templates_by_id.get(String(entry.get("template_id", "")), {}))
	var edge_sockets: Dictionary = _dictionary_or_empty(template_data.get("edge_sockets", {}))
	var rotation_degrees: int = int(entry.get("rotation", 0))
	var result: Array[int] = []
	for source_edge: String in MODULE_EDGE_DIRECTIONS.VALUES:
		for raw_index: Variant in _array_or_empty(edge_sockets.get(source_edge, [])):
			var source_cell: Vector2i = _edge_cell(source_edge, int(raw_index))
			var rotated_cell: Vector2i = _rotate_local_cell(source_cell, rotation_degrees)
			if _edge_for_cell(rotated_cell) == world_edge:
				result.append(_edge_index(world_edge, rotated_cell))
	result.sort()
	return result


func _all_floor_cells_reachable() -> bool:
	var start_cell: Vector2i = INVALID_COORD
	var passable_count: int = 0
	for global_y: int in range(WORLD_CELL_ROWS):
		for global_x: int in range(WORLD_CELL_COLUMNS):
			var global_cell := Vector2i(global_x, global_y)
			if _terrain_at_global_cell(global_cell) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
				passable_count += 1
				if start_cell == INVALID_COORD:
					start_cell = global_cell
	if passable_count == 0:
		return false
	var pending: Array[Vector2i] = [start_cell]
	var visited_cells: Dictionary = {_global_cell_key(start_cell): true}
	var cursor: int = 0
	var cardinal_offsets: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	while cursor < pending.size():
		var cell: Vector2i = pending[cursor]
		cursor += 1
		for offset: Vector2i in cardinal_offsets:
			var neighbor: Vector2i = cell + offset
			var neighbor_key: String = _global_cell_key(neighbor)
			if not _is_global_cell_valid(neighbor) or visited_cells.has(neighbor_key):
				continue
			if _terrain_at_global_cell(neighbor) != MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
				continue
			visited_cells[neighbor_key] = true
			pending.append(neighbor)
	return visited_cells.size() == passable_count


func _terrain_at_global_cell(global_cell: Vector2i) -> String:
	var module_and_local: Dictionary = global_cell_to_module_and_local(global_cell)
	var module_coord: Vector2i = module_and_local.get("module_coord", INVALID_COORD) as Vector2i
	var local_cell: Vector2i = module_and_local.get("local_cell", INVALID_COORD) as Vector2i
	if not _is_module_coord_valid(module_coord) or _cell_is_masked(module_coord, local_cell):
		return MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED
	var entry: Dictionary = assignment_at(module_coord)
	var template_data: Dictionary = _dictionary_or_empty(_templates_by_id.get(String(entry.get("template_id", "")), {}))
	var terrain_rows: Array = _array_or_empty(template_data.get("terrain_rows", []))
	var source_cell: Vector2i = _inverse_rotate_local_cell(local_cell, int(entry.get("rotation", 0)))
	if source_cell.y < 0 or source_cell.y >= terrain_rows.size() or not terrain_rows[source_cell.y] is Array:
		return MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED
	var source_row: Array = terrain_rows[source_cell.y] as Array
	if source_cell.x < 0 or source_cell.x >= source_row.size():
		return MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED
	return String(source_row[source_cell.x])


func _cell_is_masked(module_coord: Vector2i, local_cell: Vector2i) -> bool:
	var masked_edges: Array[String] = _masked_edges_for_coord(module_coord)
	if local_cell.y == 0 and masked_edges.has(MODULE_EDGE_DIRECTIONS.EDGE_NORTH):
		return true
	if local_cell.x == MODULE_COLUMNS - 1 and masked_edges.has(MODULE_EDGE_DIRECTIONS.EDGE_EAST):
		return true
	if local_cell.y == MODULE_ROWS - 1 and masked_edges.has(MODULE_EDGE_DIRECTIONS.EDGE_SOUTH):
		return true
	if local_cell.x == 0 and masked_edges.has(MODULE_EDGE_DIRECTIONS.EDGE_WEST):
		return true
	return false


func _masked_edges_for_coord(module_coord: Vector2i) -> Array[String]:
	var result: Array[String] = []
	if bool(_world_def.get("seal_outer_edges", false)):
		if module_coord.y == 0:
			result.append(MODULE_EDGE_DIRECTIONS.EDGE_NORTH)
		if module_coord.x == WORLD_COLUMNS - 1:
			result.append(MODULE_EDGE_DIRECTIONS.EDGE_EAST)
		if module_coord.y == WORLD_ROWS - 1:
			result.append(MODULE_EDGE_DIRECTIONS.EDGE_SOUTH)
		if module_coord.x == 0:
			result.append(MODULE_EDGE_DIRECTIONS.EDGE_WEST)
	if _is_sealed_module(module_coord + Vector2i.UP):
		result.append(MODULE_EDGE_DIRECTIONS.EDGE_NORTH)
	if _is_sealed_module(module_coord + Vector2i.RIGHT):
		result.append(MODULE_EDGE_DIRECTIONS.EDGE_EAST)
	if _is_sealed_module(module_coord + Vector2i.DOWN):
		result.append(MODULE_EDGE_DIRECTIONS.EDGE_SOUTH)
	if _is_sealed_module(module_coord + Vector2i.LEFT):
		result.append(MODULE_EDGE_DIRECTIONS.EDGE_WEST)
	return result


func _is_sealed_module(module_coord: Vector2i) -> bool:
	if not _is_module_coord_valid(module_coord):
		return false
	return String(assignment_at(module_coord).get("role", "")) == MODULE_ROLES.MODULE_ROLE_SEALED


func _refresh_active_modules(center_coord: Vector2i) -> Dictionary:
	var desired_keys: Dictionary = {}
	for row_offset: int in range(-_active_radius, _active_radius + 1):
		for column_offset: int in range(-_active_radius, _active_radius + 1):
			var module_coord: Vector2i = center_coord + Vector2i(column_offset, row_offset)
			if _is_module_coord_valid(module_coord):
				desired_keys[_slot_key(module_coord)] = true
	var deactivated: Array[Dictionary] = []
	for active_key: String in _active_chunks.keys():
		if desired_keys.has(active_key):
			continue
		var chunk: ModuleChunkRuntime = _active_chunks[active_key] as ModuleChunkRuntime
		deactivated.append(_coord_to_dict(chunk.module_coord()))
		chunk.clear()
		_active_chunks.erase(active_key)
	var activated: Array[Dictionary] = []
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			var slot_key: String = _slot_key(module_coord)
			if not desired_keys.has(slot_key) or _active_chunks.has(slot_key):
				continue
			var available_chunk: ModuleChunkRuntime = _available_chunk()
			if available_chunk == null:
				push_error("[ModuleWorldManager] active chunk pool exhausted")
				continue
			var entry: Dictionary = assignment_at(module_coord)
			var template_data: Dictionary = _effective_template_for_coord(module_coord)
			available_chunk.configure(
				template_data,
				module_coord,
				int(entry.get("rotation", 0)),
				_cell_size,
				_world_origin
			)
			_active_chunks[slot_key] = available_chunk
			activated.append(_coord_to_dict(module_coord))
	return {
		"activated": activated,
		"deactivated": deactivated,
	}


func _effective_template_for_coord(module_coord: Vector2i) -> Dictionary:
	var entry: Dictionary = assignment_at(module_coord)
	var template_data: Dictionary = _dictionary_or_empty(_templates_by_id.get(String(entry.get("template_id", "")), {}))
	template_data["masked_edges"] = _masked_edges_for_coord(module_coord)
	return template_data


func _ensure_chunk_pool() -> void:
	while _chunk_pool.size() < MAX_ACTIVE_CHUNKS:
		var chunk: ModuleChunkRuntime = ModuleChunkRuntime.new()
		chunk.name = "ModuleChunk%02d" % _chunk_pool.size()
		chunk.visible = false
		add_child(chunk)
		_chunk_pool.append(chunk)


func _available_chunk() -> ModuleChunkRuntime:
	for chunk: ModuleChunkRuntime in _chunk_pool:
		if not _active_chunks.values().has(chunk):
			return chunk
	return null


func _deactivate_all_chunks() -> Array[Dictionary]:
	var deactivated: Array[Dictionary] = []
	for active_key: String in _active_chunks.keys():
		var chunk: ModuleChunkRuntime = _active_chunks[active_key] as ModuleChunkRuntime
		deactivated.append(_coord_to_dict(chunk.module_coord()))
		chunk.clear()
	_active_chunks.clear()
	return deactivated


func _reset_world_state() -> void:
	_deactivate_all_chunks()
	_assignment.clear()
	_map_hash = ""
	_current_module_coord = INVALID_COORD
	_revealed.clear()
	_visited.clear()
	_slot_states.clear()


func _compute_map_hash() -> String:
	var hash_payload: Dictionary = {
		# Include the authoritative content as well as the slot assignment. A run
		# must fail closed when geometry, sockets, terrain or placements change,
		# even if the seed still produces the same template ids and rotations.
		"world": _world_def,
		"run_seed": _run_seed,
		"assignment": _assignment_entries(),
		"assigned_templates": _assigned_template_payloads(),
	}
	return _stable_serialize(hash_payload).sha256_text()


func _assigned_template_payloads() -> Dictionary:
	var result: Dictionary = {}
	for assignment_entry: Dictionary in _assignment_entries():
		var template_id: String = String(assignment_entry.get("template_id", ""))
		if template_id.is_empty() or result.has(template_id) or not _templates_by_id.has(template_id):
			continue
		result[template_id] = (_templates_by_id[template_id] as Dictionary).duplicate(true)
	return result


func _assignment_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			if _assignment.has(_slot_key(module_coord)):
				result.append(assignment_at(module_coord))
	return result


func _stable_serialize(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array[String] = []
		for raw_key: Variant in dictionary.keys():
			keys.append(String(raw_key))
		keys.sort()
		var pairs: PackedStringArray = PackedStringArray()
		for key: String in keys:
			pairs.append("%s:%s" % [JSON.stringify(key), _stable_serialize(dictionary.get(key))])
		return "{%s}" % ",".join(pairs)
	if value is Array:
		var items: PackedStringArray = PackedStringArray()
		for item: Variant in value as Array:
			items.append(_stable_serialize(item))
		return "[%s]" % ",".join(items)
	return JSON.stringify(value)


func _assignment_seed() -> int:
	var seed_text: String = "wasd:module-world-assignment:v1:%s:%d" % [String(_world_def.get("id", "")), _run_seed]
	var digest_text: String = seed_text.sha256_text()
	var derived_seed: int = 0
	for index: int in range(digest_text.length()):
		derived_seed = (derived_seed * 16 + _hex_value(digest_text.unicode_at(index))) % ASSIGNMENT_SEED_MODULUS
	return maxi(derived_seed, 1)


func _hex_value(codepoint: int) -> int:
	if codepoint >= 48 and codepoint <= 57:
		return codepoint - 48
	if codepoint >= 97 and codepoint <= 102:
		return codepoint - 87
	if codepoint >= 65 and codepoint <= 70:
		return codepoint - 55
	return 0


func _edge_cell(edge: String, index: int) -> Vector2i:
	match edge:
		MODULE_EDGE_DIRECTIONS.EDGE_NORTH:
			return Vector2i(index, 0)
		MODULE_EDGE_DIRECTIONS.EDGE_EAST:
			return Vector2i(MODULE_COLUMNS - 1, index)
		MODULE_EDGE_DIRECTIONS.EDGE_SOUTH:
			return Vector2i(index, MODULE_ROWS - 1)
		MODULE_EDGE_DIRECTIONS.EDGE_WEST:
			return Vector2i(0, index)
		_:
			return INVALID_COORD


func _edge_for_cell(local_cell: Vector2i) -> String:
	if local_cell.y == 0:
		return MODULE_EDGE_DIRECTIONS.EDGE_NORTH
	if local_cell.x == MODULE_COLUMNS - 1:
		return MODULE_EDGE_DIRECTIONS.EDGE_EAST
	if local_cell.y == MODULE_ROWS - 1:
		return MODULE_EDGE_DIRECTIONS.EDGE_SOUTH
	if local_cell.x == 0:
		return MODULE_EDGE_DIRECTIONS.EDGE_WEST
	return ""


func _edge_index(edge: String, local_cell: Vector2i) -> int:
	if edge == MODULE_EDGE_DIRECTIONS.EDGE_NORTH or edge == MODULE_EDGE_DIRECTIONS.EDGE_SOUTH:
		return local_cell.x
	return local_cell.y


func _rotate_local_cell(local_cell: Vector2i, rotation_degrees: int) -> Vector2i:
	match _normalize_rotation(rotation_degrees):
		90:
			return Vector2i(MODULE_ROWS - 1 - local_cell.y, local_cell.x)
		180:
			return Vector2i(MODULE_COLUMNS - 1 - local_cell.x, MODULE_ROWS - 1 - local_cell.y)
		270:
			return Vector2i(local_cell.y, MODULE_COLUMNS - 1 - local_cell.x)
		_:
			return local_cell


func _inverse_rotate_local_cell(local_cell: Vector2i, rotation_degrees: int) -> Vector2i:
	return _rotate_local_cell(local_cell, posmod(ROTATION_FULL - _normalize_rotation(rotation_degrees), ROTATION_FULL))


func _normalize_rotation(rotation_degrees: int) -> int:
	var normalized: int = posmod(rotation_degrees, ROTATION_FULL)
	if normalized % ROTATION_STEP != 0:
		return 0
	return normalized


func _has_supported_geometry() -> bool:
	return (
		int(_world_def.get("columns", 0)) == WORLD_COLUMNS
		and int(_world_def.get("rows", 0)) == WORLD_ROWS
		and int(_world_def.get("module_columns", 0)) == MODULE_COLUMNS
		and int(_world_def.get("module_rows", 0)) == MODULE_ROWS
	)


func _is_global_cell_valid(global_cell: Vector2i) -> bool:
	return global_cell.x >= 0 and global_cell.y >= 0 and global_cell.x < WORLD_CELL_COLUMNS and global_cell.y < WORLD_CELL_ROWS


func _is_module_coord_valid(module_coord: Vector2i) -> bool:
	return module_coord.x >= 0 and module_coord.y >= 0 and module_coord.x < WORLD_COLUMNS and module_coord.y < WORLD_ROWS


func _is_local_cell_valid(local_cell: Vector2i) -> bool:
	return local_cell.x >= 0 and local_cell.y >= 0 and local_cell.x < MODULE_COLUMNS and local_cell.y < MODULE_ROWS


func _slot_key(module_coord: Vector2i) -> String:
	return "%d,%d" % [module_coord.x, module_coord.y]


func _global_cell_key(global_cell: Vector2i) -> String:
	return "%d,%d" % [global_cell.x, global_cell.y]


func _coord_to_dict(coord: Vector2i) -> Dictionary:
	return {
		"x": coord.x,
		"y": coord.y,
	}


func _coords_to_dict_array(coords: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for coord: Vector2i in coords:
		result.append(_coord_to_dict(coord))
	return result


func _coord_from_variant(raw_value: Variant, fallback: Vector2i) -> Vector2i:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2i(int(value.get("x", fallback.x)), int(value.get("y", fallback.y)))


func _vector_from_variant(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _coords_from_set(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			if source.has(_slot_key(module_coord)):
				result.append(module_coord)
	return result


func _set_from_coord_array(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not raw_value is Array:
		return result
	for raw_coord: Variant in raw_value as Array:
		var module_coord: Vector2i = _coord_from_variant(raw_coord, INVALID_COORD)
		if _is_module_coord_valid(module_coord):
			result[_slot_key(module_coord)] = true
	return result


func _validated_slot_states(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not raw_value is Dictionary:
		return result
	var source: Dictionary = raw_value as Dictionary
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var slot_key: String = _slot_key(Vector2i(column_index, row_index))
			if source.get(slot_key) is Dictionary:
				result[slot_key] = (source.get(slot_key) as Dictionary).duplicate(true)
	return result


func _ordered_slot_states() -> Dictionary:
	var result: Dictionary = {}
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var slot_key: String = _slot_key(Vector2i(column_index, row_index))
			if _slot_states.get(slot_key) is Dictionary:
				result[slot_key] = (_slot_states.get(slot_key) as Dictionary).duplicate(true)
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []
