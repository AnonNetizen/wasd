# Doc: docs/代码/module_world_manager.md
class_name ModuleWorldLayout
extends RefCounted
## Pure assignment, geometry, terrain and stable-hash owner for ModuleWorldManager.
## Randomness is supplied through RandomPort; this class does not access autoloads, files or Nodes.

const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_EDGE_DIRECTIONS := preload("res://scripts/contracts/module_edge_directions.gd")
const MODULE_REVIEW_STATUSES := preload("res://scripts/contracts/module_review_statuses.gd")
const MODULE_ROLES := preload("res://scripts/contracts/module_roles.gd")

const WORLD_COLUMNS: int = 7
const WORLD_ROWS: int = 7
const MODULE_COLUMNS: int = 11
const MODULE_ROWS: int = 11
const WORLD_CELL_COLUMNS: int = WORLD_COLUMNS * MODULE_COLUMNS
const WORLD_CELL_ROWS: int = WORLD_ROWS * MODULE_ROWS
const WORLD_CENTER_GLOBAL_CELL: Vector2i = Vector2i(38, 38)
const ROTATION_STEP: int = 90
const ROTATION_FULL: int = 360
const ASSIGNMENT_SEED_MODULUS: int = 2_147_483_647
const INVALID_COORD: Vector2i = Vector2i(-1, -1)


class RandomPort extends RefCounted:
	var _snapshot_provider: Callable = Callable()
	var _configure_handler: Callable = Callable()
	var _restore_handler: Callable = Callable()
	var _next_u32_provider: Callable = Callable()
	var _range_f32_provider: Callable = Callable()


	func _init(
		snapshot_provider: Callable = Callable(),
		configure_handler: Callable = Callable(),
		restore_handler: Callable = Callable(),
		next_u32_provider: Callable = Callable(),
		range_f32_provider: Callable = Callable()
	) -> void:
		_snapshot_provider = snapshot_provider
		_configure_handler = configure_handler
		_restore_handler = restore_handler
		_next_u32_provider = next_u32_provider
		_range_f32_provider = range_f32_provider


	func is_valid() -> bool:
		return (
			_snapshot_provider.is_valid()
			and _configure_handler.is_valid()
			and _restore_handler.is_valid()
			and _next_u32_provider.is_valid()
			and _range_f32_provider.is_valid()
		)


	func snapshot() -> Dictionary:
		var raw_snapshot: Variant = _snapshot_provider.call()
		if raw_snapshot is Dictionary:
			return (raw_snapshot as Dictionary).duplicate(true)
		return {}


	func configure(stream_id: String, seed_value: int) -> void:
		_configure_handler.call(stream_id, seed_value)


	func restore_snapshot(snapshot_data: Dictionary) -> void:
		_restore_handler.call(snapshot_data)


	func next_u32() -> int:
		return int(_next_u32_provider.call())


	func range_f32(from: float, to: float) -> float:
		return float(_range_f32_provider.call(from, to))


class RestoreCandidate extends RefCounted:
	var _is_valid: bool = false
	var _layout_instance_id: int = 0
	var _run_seed: int = 1
	var _assignment: Dictionary = {}
	var _assignment_entries: Array[Dictionary] = []


	func is_valid() -> bool:
		return _is_valid


	func run_seed() -> int:
		return _run_seed


	func assignment() -> Dictionary:
		return _assignment.duplicate(true)


	func assignment_entries() -> Array[Dictionary]:
		return _assignment_entries.duplicate(true)


	func _succeed(
		layout_instance_id: int,
		run_seed_value: int,
		assignment_value: Dictionary,
		assignment_entries_value: Array[Dictionary]
	) -> void:
		_is_valid = true
		_layout_instance_id = layout_instance_id
		_run_seed = run_seed_value
		_assignment = assignment_value.duplicate(true)
		_assignment_entries = assignment_entries_value.duplicate(true)


var _world_def: Dictionary = {}
var _registry_by_id: Dictionary = {}
var _templates_by_id: Dictionary = {}
var _run_seed: int = 1
var _cell_size: float = 160.0
var _world_origin: Vector2 = Vector2.ZERO
var _assignment: Dictionary = {}
var _map_hash: String = ""


func configure(
	world_def: Dictionary,
	registry_by_id: Dictionary,
	templates_by_id: Dictionary,
	run_seed_value: int
) -> bool:
	_world_def = world_def.duplicate(true)
	_registry_by_id = registry_by_id.duplicate(true)
	_templates_by_id = templates_by_id.duplicate(true)
	_run_seed = run_seed_value
	_cell_size = float(_world_def.get("cell_size", 160.0))
	_world_origin = _vector_from_variant(
		_world_def.get("world_origin", {}),
		Vector2.ZERO
	)
	return _has_supported_geometry() and _cell_size > 0.0


func reset() -> void:
	_assignment.clear()
	_map_hash = ""


func run_seed() -> int:
	return _run_seed


func cell_size() -> float:
	return _cell_size


func world_origin() -> Vector2:
	return _world_origin


func assignment() -> Dictionary:
	return _assignment.duplicate(true)


func assignment_count() -> int:
	return _assignment.size()


func assignment_at(module_coord: Vector2i) -> Dictionary:
	return _assignment_at(_assignment, module_coord)


func has_assignment_at(module_coord: Vector2i) -> bool:
	return _assignment.has(_slot_key(module_coord))


func assignment_entries() -> Array[Dictionary]:
	return _assignment_entries_for(_assignment)


func template_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_template_id: Variant in _templates_by_id.keys():
		result.append(String(raw_template_id))
	return result


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


func build_seeded_assignment(
	random_port: RandomPort,
	stream_id: String
) -> bool:
	if not _load_partial_assignment(
		_world_def.get("fixed_slots", []),
		false,
		_assignment
	):
		return false
	var pool_ids: Array[String] = _approved_pool_ids()
	if pool_ids.is_empty() or random_port == null or not random_port.is_valid():
		return false
	var world_rng_snapshot: Dictionary = random_port.snapshot()
	random_port.configure(stream_id, _assignment_seed())
	var generated_all_slots: bool = _assign_objective_spawn(
		false,
		_assignment,
		random_port
	)
	if generated_all_slots:
		generated_all_slots = _assign_limited_template_groups(
			_world_def.get("limited_template_groups", []),
			_assignment,
			random_port
		)
	for row_index: int in range(WORLD_ROWS):
		if not generated_all_slots:
			break
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			if _assignment.has(_slot_key(module_coord)):
				continue
			if not _assign_random_pool_template(
				module_coord,
				pool_ids,
				_assignment,
				random_port
			):
				generated_all_slots = false
				break
		if not generated_all_slots:
			break
	random_port.restore_snapshot(world_rng_snapshot)
	return generated_all_slots


func build_fallback_assignment(
	random_port: RandomPort,
	stream_id: String
) -> bool:
	return (
		load_fallback_assignment()
		and assign_fallback_objective(random_port, stream_id)
	)


func load_fallback_assignment() -> bool:
	if not _load_explicit_assignment(
		_world_def.get("fallback_assignment", []),
		false,
		_assignment
	):
		return false
	if not _assignment_matches_constrained_limited_groups(_assignment):
		_assignment.clear()
		return false
	return true


func assign_fallback_objective(
	random_port: RandomPort,
	stream_id: String
) -> bool:
	if random_port == null or not random_port.is_valid():
		return false
	var world_rng_snapshot: Dictionary = random_port.snapshot()
	random_port.configure(stream_id, _assignment_seed())
	var objective_assigned: bool = _assign_objective_spawn(
		true,
		_assignment,
		random_port
	)
	random_port.restore_snapshot(world_rng_snapshot)
	return objective_assigned


func build_technical_slice_assignment() -> bool:
	return _load_explicit_assignment(
		_world_def.get("technical_slice_assignment", []),
		true,
		_assignment
	)


func is_assignment_valid() -> bool:
	return _assignment_is_valid(_assignment)


func prepare_restore_assignment(
	raw_entries: Variant,
	run_seed_value: int
) -> RestoreCandidate:
	var candidate := RestoreCandidate.new()
	var restored_assignment: Dictionary = {}
	if not _load_explicit_assignment(
		raw_entries,
		true,
		restored_assignment
	):
		return candidate
	if not _assignment_is_valid(restored_assignment):
		return candidate
	candidate._succeed(
		get_instance_id(),
		run_seed_value,
		restored_assignment,
		_assignment_entries_for(restored_assignment)
	)
	return candidate


func map_hash_for_candidate(candidate: RestoreCandidate) -> String:
	if (
		candidate == null
		or not candidate.is_valid()
		or candidate._layout_instance_id != get_instance_id()
	):
		return ""
	return _compute_map_hash_for(candidate._assignment, candidate._run_seed)


func commit_restore(candidate: RestoreCandidate, map_hash_value: String) -> void:
	if (
		candidate == null
		or not candidate.is_valid()
		or candidate._layout_instance_id != get_instance_id()
	):
		return
	_assignment = candidate._assignment.duplicate(true)
	_run_seed = candidate._run_seed
	_map_hash = map_hash_value


func compute_map_hash() -> String:
	return _compute_map_hash_for(_assignment, _run_seed)


func commit_map_hash(map_hash_value: String) -> void:
	_map_hash = map_hash_value


func map_hash() -> String:
	return _map_hash


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


func global_cell_to_module_and_local(global_cell: Vector2i) -> Dictionary:
	if not is_global_cell_valid(global_cell):
		return {
			"module_coord": INVALID_COORD,
			"local_cell": INVALID_COORD,
		}
	return {
		"module_coord": Vector2i(
			global_cell.x / MODULE_COLUMNS,
			global_cell.y / MODULE_ROWS
		),
		"local_cell": Vector2i(
			global_cell.x % MODULE_COLUMNS,
			global_cell.y % MODULE_ROWS
		),
	}


func module_local_to_global_cell(
	module_coord: Vector2i,
	local_cell: Vector2i
) -> Vector2i:
	if not is_module_coord_valid(module_coord) or not is_local_cell_valid(local_cell):
		return INVALID_COORD
	return Vector2i(
		module_coord.x * MODULE_COLUMNS + local_cell.x,
		module_coord.y * MODULE_ROWS + local_cell.y
	)


func is_world_position_walkable(world_position: Vector2) -> bool:
	var global_cell: Vector2i = world_to_global_cell(world_position)
	return is_global_cell_walkable(global_cell)


func is_global_cell_walkable(global_cell: Vector2i) -> bool:
	return (
		is_global_cell_valid(global_cell)
		and terrain_at_global_cell(global_cell)
		== MODULE_CELL_TOKENS.MODULE_CELL_FLOOR
	)


func placements_at(module_coord: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_module_coord_valid(module_coord):
		return result
	var entry: Dictionary = assignment_at(module_coord)
	var template_data: Dictionary = _dictionary_or_empty(
		_templates_by_id.get(String(entry.get("template_id", "")), {})
	)
	var rotation_degrees: int = int(entry.get("rotation", 0))
	for raw_placement: Variant in _array_or_empty(
		template_data.get("placements", [])
	):
		if not raw_placement is Dictionary:
			continue
		var placement: Dictionary = (raw_placement as Dictionary).duplicate(true)
		var source_cell: Vector2i = _coord_from_variant(
			placement.get("cell", {}),
			INVALID_COORD
		)
		var local_cell: Vector2i = _rotate_local_cell(
			source_cell,
			rotation_degrees
		)
		if not is_local_cell_valid(local_cell) or _cell_is_masked(
			module_coord,
			local_cell,
			_assignment
		):
			continue
		var global_cell: Vector2i = module_local_to_global_cell(
			module_coord,
			local_cell
		)
		placement["cell"] = _coord_to_dict(local_cell)
		placement["module_coord"] = _coord_to_dict(module_coord)
		placement["world_position"] = _vector_to_dict(
			global_cell_to_world(global_cell)
		)
		result.append(placement)
	return result


## Returns effective, unoccupied floor-cell centers in stable row-major order.
## Static gameplay placement footprints are excluded after module rotation.
func empty_floor_positions_at(module_coord: Vector2i) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not is_module_coord_valid(module_coord):
		return result
	var occupied: Dictionary = _occupied_local_cells(module_coord)
	for local_y: int in range(MODULE_ROWS):
		for local_x: int in range(MODULE_COLUMNS):
			var local_cell := Vector2i(local_x, local_y)
			if occupied.has(local_cell):
				continue
			var global_cell: Vector2i = module_local_to_global_cell(
				module_coord,
				local_cell
			)
			if (
				terrain_at_global_cell(global_cell)
				!= MODULE_CELL_TOKENS.MODULE_CELL_FLOOR
			):
				continue
			result.append(global_cell_to_world(global_cell))
	return result


func terrain_at_global_cell(global_cell: Vector2i) -> String:
	return _terrain_at_global_cell(global_cell, _assignment)


func masked_edges_for_coord(module_coord: Vector2i) -> Array[String]:
	return _masked_edges_for_coord(module_coord, _assignment)


func world_event_template_ids() -> Array[String]:
	var template_ids: Array[String] = []
	for raw_entry: Variant in _assignment.values():
		var entry: Dictionary = raw_entry as Dictionary
		if String(entry.get("role", "")) != MODULE_ROLES.MODULE_ROLE_WORLD_EVENT:
			continue
		var template_id: String = String(entry.get("template_id", ""))
		if not template_id.is_empty() and not template_ids.has(template_id):
			template_ids.append(template_id)
	template_ids.sort()
	return template_ids


func world_event_assignment_count() -> int:
	var count: int = 0
	for raw_entry: Variant in _assignment.values():
		var entry: Dictionary = raw_entry as Dictionary
		if String(entry.get("role", "")) == MODULE_ROLES.MODULE_ROLE_WORLD_EVENT:
			count += 1
	return count


func is_global_cell_valid(global_cell: Vector2i) -> bool:
	return (
		global_cell.x >= 0
		and global_cell.y >= 0
		and global_cell.x < WORLD_CELL_COLUMNS
		and global_cell.y < WORLD_CELL_ROWS
	)


func is_module_coord_valid(module_coord: Vector2i) -> bool:
	return (
		module_coord.x >= 0
		and module_coord.y >= 0
		and module_coord.x < WORLD_COLUMNS
		and module_coord.y < WORLD_ROWS
	)


func is_local_cell_valid(local_cell: Vector2i) -> bool:
	return (
		local_cell.x >= 0
		and local_cell.y >= 0
		and local_cell.x < MODULE_COLUMNS
		and local_cell.y < MODULE_ROWS
	)


func _approved_pool_ids() -> Array[String]:
	var result: Array[String] = []
	for raw_template_id: Variant in _array_or_empty(
		_world_def.get("template_pool", [])
	):
		var template_id: String = String(raw_template_id)
		var registry_entry: Dictionary = _dictionary_or_empty(
			_registry_by_id.get(template_id, {})
		)
		if (
			String(registry_entry.get("review_status", ""))
			!= MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED
		):
			continue
		if not _templates_by_id.has(template_id):
			continue
		if not result.has(template_id):
			result.append(template_id)
	return result


func _allowed_rotations(template_id: String) -> Array[int]:
	var result: Array[int] = []
	var registry_entry: Dictionary = _dictionary_or_empty(
		_registry_by_id.get(template_id, {})
	)
	for raw_rotation: Variant in _array_or_empty(
		registry_entry.get("allowed_rotations", [0])
	):
		var rotation_degrees: int = _normalize_rotation(int(raw_rotation))
		if not result.has(rotation_degrees):
			result.append(rotation_degrees)
	if result.is_empty():
		result.append(0)
	return result


func _assign_objective_spawn(
	replace_existing: bool,
	assignment_value: Dictionary,
	random_port: RandomPort
) -> bool:
	var objective_spawn: Dictionary = _dictionary_or_empty(
		_world_def.get("objective_spawn", {})
	)
	var template_id: String = String(objective_spawn.get("template_id", ""))
	var rotation_degrees: int = _normalize_rotation(
		int(objective_spawn.get("rotation", 0))
	)
	var candidates: Array = _array_or_empty(
		objective_spawn.get("candidate_slots", [])
	)
	if template_id.is_empty() or candidates.is_empty():
		return false
	if not _templates_by_id.has(template_id):
		return false
	var registry_entry: Dictionary = _dictionary_or_empty(
		_registry_by_id.get(template_id, {})
	)
	if (
		registry_entry.is_empty()
		or not _is_assignment_template_allowed(registry_entry, false)
		or not _allowed_rotations(template_id).has(rotation_degrees)
	):
		return false
	# Consume the injected stream explicitly; no global random API is used here.
	var selected_index: int = int(random_port.next_u32() % candidates.size())
	var selected_candidate: Variant = candidates[selected_index]
	var module_coord: Vector2i = _coord_from_variant(
		selected_candidate,
		INVALID_COORD
	)
	if not is_module_coord_valid(module_coord):
		return false
	var slot_key: String = _slot_key(module_coord)
	if assignment_value.has(slot_key) and not replace_existing:
		return false
	assignment_value[slot_key] = _make_assignment_entry(
		module_coord,
		template_id,
		rotation_degrees
	)
	return true


func _assign_limited_template_groups(
	raw_groups: Variant,
	assignment_value: Dictionary,
	random_port: RandomPort
) -> bool:
	if not raw_groups is Array:
		return false
	var ordered_groups: Array[Dictionary] = []
	for constrained_pass: bool in [true, false]:
		for raw_group: Variant in raw_groups as Array:
			if not raw_group is Dictionary:
				return false
			var candidate_group: Dictionary = raw_group as Dictionary
			var is_constrained: bool = int(
				candidate_group.get("minimum_manhattan_distance", 0)
			) > 0
			if is_constrained == constrained_pass:
				ordered_groups.append(candidate_group)
	for group: Dictionary in ordered_groups:
		var raw_entries: Variant = group.get("entries", [])
		if not raw_entries is Array:
			return false
		var candidates: Array[Dictionary] = []
		for raw_entry: Variant in raw_entries as Array:
			if raw_entry is Dictionary:
				candidates.append((raw_entry as Dictionary).duplicate(true))
		var pick_distinct: int = int(group.get("pick_distinct", 0))
		if pick_distinct < 1 or pick_distinct > candidates.size():
			return false
		var selected_entries: Array[Dictionary] = []
		for _selection_index: int in range(pick_distinct):
			var selected_index: int = _weighted_limited_entry_index(
				candidates,
				random_port
			)
			if selected_index < 0:
				return false
			var selected: Dictionary = candidates[selected_index]
			candidates.remove_at(selected_index)
			selected_entries.append(selected)
		var minimum_distance: int = int(
			group.get("minimum_manhattan_distance", 0)
		)
		if minimum_distance > 0:
			if not _assign_constrained_limited_group(
				selected_entries,
				minimum_distance,
				assignment_value,
				random_port
			):
				return false
			continue
		for selected: Dictionary in selected_entries:
			var template_id: String = String(selected.get("template_id", ""))
			var count_per_floor: int = int(
				selected.get("count_per_floor", 0)
			)
			for _count_index: int in range(count_per_floor):
				if not _assign_limited_template_to_random_slot(
					template_id,
					assignment_value,
					random_port
				):
					return false
	return true


func _assign_constrained_limited_group(
	selected_entries: Array[Dictionary],
	minimum_distance: int,
	assignment_value: Dictionary,
	random_port: RandomPort
) -> bool:
	var template_jobs: Array[String] = []
	for selected: Dictionary in selected_entries:
		var template_id: String = String(selected.get("template_id", ""))
		var count_per_floor: int = int(selected.get("count_per_floor", 0))
		if template_id.is_empty() or count_per_floor < 1:
			return false
		for _count_index: int in range(count_per_floor):
			template_jobs.append(template_id)
	var free_coords: Array[Vector2i] = []
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			if not assignment_value.has(_slot_key(module_coord)):
				free_coords.append(module_coord)
	if template_jobs.is_empty() or template_jobs.size() > free_coords.size():
		return false
	var options_by_job: Array = []
	for template_id: String in template_jobs:
		var rotations: Array[int] = _allowed_rotations(template_id)
		if rotations.is_empty():
			return false
		var options: Array[Dictionary] = []
		for module_coord: Vector2i in free_coords:
			for rotation_degrees: int in rotations:
				options.append({
					"module_coord": module_coord,
					"rotation": rotation_degrees,
				})
		_shuffle_assignment_options(options, random_port)
		options_by_job.append(options)
	var temporary_assignment: Dictionary = assignment_value.duplicate(true)
	var placed_coords: Array[Vector2i] = []
	if not _backtrack_constrained_limited_group(
		0,
		template_jobs,
		options_by_job,
		minimum_distance,
		temporary_assignment,
		placed_coords
	):
		return false
	assignment_value.clear()
	assignment_value.merge(temporary_assignment, true)
	return true


func _shuffle_assignment_options(
	options: Array[Dictionary],
	random_port: RandomPort
) -> void:
	for index: int in range(options.size() - 1, 0, -1):
		var swap_index: int = int(random_port.next_u32() % (index + 1))
		var temporary: Dictionary = options[index]
		options[index] = options[swap_index]
		options[swap_index] = temporary


func _backtrack_constrained_limited_group(
	job_index: int,
	template_jobs: Array[String],
	options_by_job: Array,
	minimum_distance: int,
	temporary_assignment: Dictionary,
	placed_coords: Array[Vector2i]
) -> bool:
	if job_index >= template_jobs.size():
		return true
	var template_id: String = template_jobs[job_index]
	var options: Array = options_by_job[job_index] as Array
	for raw_option: Variant in options:
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option as Dictionary
		var module_coord: Vector2i = option.get(
			"module_coord",
			INVALID_COORD
		) as Vector2i
		var slot_key: String = _slot_key(module_coord)
		if temporary_assignment.has(slot_key):
			continue
		var respects_distance: bool = true
		for placed_coord: Vector2i in placed_coords:
			if (
				absi(module_coord.x - placed_coord.x)
				+ absi(module_coord.y - placed_coord.y)
				< minimum_distance
			):
				respects_distance = false
				break
		if not respects_distance:
			continue
		temporary_assignment[slot_key] = _make_assignment_entry(
			module_coord,
			template_id,
			int(option.get("rotation", 0))
		)
		if _entry_fits_assigned_neighbors(
			module_coord,
			temporary_assignment
		):
			placed_coords.append(module_coord)
			if _backtrack_constrained_limited_group(
				job_index + 1,
				template_jobs,
				options_by_job,
				minimum_distance,
				temporary_assignment,
				placed_coords
			):
				return true
			placed_coords.pop_back()
		temporary_assignment.erase(slot_key)
	return false


func _weighted_limited_entry_index(
	candidates: Array[Dictionary],
	random_port: RandomPort
) -> int:
	var total_weight: float = 0.0
	for candidate: Dictionary in candidates:
		total_weight += maxf(float(candidate.get("weight", 0.0)), 0.0)
	if total_weight <= 0.0:
		return -1
	var roll: float = random_port.range_f32(0.0, total_weight)
	var cumulative: float = 0.0
	for candidate_index: int in range(candidates.size()):
		cumulative += maxf(
			float(candidates[candidate_index].get("weight", 0.0)),
			0.0
		)
		if roll <= cumulative:
			return candidate_index
	return candidates.size() - 1


func _assign_limited_template_to_random_slot(
	template_id: String,
	assignment_value: Dictionary,
	random_port: RandomPort
) -> bool:
	var rotations: Array[int] = _allowed_rotations(template_id)
	if rotations.is_empty():
		return false
	var free_coords: Array[Vector2i] = []
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			if not assignment_value.has(_slot_key(module_coord)):
				free_coords.append(module_coord)
	while not free_coords.is_empty():
		var coord_index: int = int(
			random_port.next_u32() % free_coords.size()
		)
		var module_coord: Vector2i = free_coords[coord_index]
		free_coords.remove_at(coord_index)
		var rotation_start: int = int(
			random_port.next_u32() % rotations.size()
		)
		for rotation_offset: int in range(rotations.size()):
			var rotation_degrees: int = rotations[
				(rotation_start + rotation_offset) % rotations.size()
			]
			assignment_value[_slot_key(module_coord)] = _make_assignment_entry(
				module_coord,
				template_id,
				rotation_degrees
			)
			if _entry_fits_assigned_neighbors(
				module_coord,
				assignment_value
			):
				return true
			assignment_value.erase(_slot_key(module_coord))
	return false


func _assign_random_pool_template(
	module_coord: Vector2i,
	pool_ids: Array[String],
	assignment_value: Dictionary,
	random_port: RandomPort
) -> bool:
	var template_start: int = int(random_port.next_u32() % pool_ids.size())
	for template_offset: int in range(pool_ids.size()):
		var template_id: String = pool_ids[
			(template_start + template_offset) % pool_ids.size()
		]
		var rotations: Array[int] = _allowed_rotations(template_id)
		if rotations.is_empty():
			continue
		var rotation_start: int = int(
			random_port.next_u32() % rotations.size()
		)
		for rotation_offset: int in range(rotations.size()):
			var rotation_degrees: int = rotations[
				(rotation_start + rotation_offset) % rotations.size()
			]
			assignment_value[_slot_key(module_coord)] = _make_assignment_entry(
				module_coord,
				template_id,
				rotation_degrees
			)
			if _entry_fits_assigned_neighbors(
				module_coord,
				assignment_value
			):
				return true
			assignment_value.erase(_slot_key(module_coord))
	return false


func _load_explicit_assignment(
	raw_entries: Variant,
	allow_unapproved: bool,
	assignment_value: Dictionary
) -> bool:
	assignment_value.clear()
	if not _load_partial_assignment(
		raw_entries,
		allow_unapproved,
		assignment_value
	):
		return false
	return assignment_value.size() == WORLD_COLUMNS * WORLD_ROWS


func _load_partial_assignment(
	raw_entries: Variant,
	allow_unapproved: bool,
	assignment_value: Dictionary
) -> bool:
	if not raw_entries is Array:
		return false
	for raw_entry: Variant in raw_entries as Array:
		if not raw_entry is Dictionary:
			return false
		var entry_data: Dictionary = raw_entry as Dictionary
		var module_coord: Vector2i = _coord_from_variant(
			entry_data.get("slot", {}),
			INVALID_COORD
		)
		var template_id: String = String(entry_data.get("template_id", ""))
		var rotation_degrees: int = _normalize_rotation(
			int(entry_data.get("rotation", 0))
		)
		if (
			not is_module_coord_valid(module_coord)
			or not _templates_by_id.has(template_id)
		):
			return false
		var registry_entry: Dictionary = _dictionary_or_empty(
			_registry_by_id.get(template_id, {})
		)
		if registry_entry.is_empty():
			return false
		if not _is_assignment_template_allowed(
			registry_entry,
			allow_unapproved
		):
			return false
		if not _allowed_rotations(template_id).has(rotation_degrees):
			return false
		var slot_key: String = _slot_key(module_coord)
		if assignment_value.has(slot_key):
			return false
		assignment_value[slot_key] = _make_assignment_entry(
			module_coord,
			template_id,
			rotation_degrees
		)
	return true


func _is_assignment_template_allowed(
	registry_entry: Dictionary,
	allow_unapproved: bool
) -> bool:
	if (
		String(registry_entry.get("review_status", ""))
		== MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED
	):
		return true
	return (
		allow_unapproved
		and String(registry_entry.get("role", ""))
		== MODULE_ROLES.MODULE_ROLE_SEALED
	)


func _make_assignment_entry(
	module_coord: Vector2i,
	template_id: String,
	rotation_degrees: int
) -> Dictionary:
	var registry_entry: Dictionary = _dictionary_or_empty(
		_registry_by_id.get(template_id, {})
	)
	return {
		"slot": _coord_to_dict(module_coord),
		"template_id": template_id,
		"role": String(registry_entry.get("role", "")),
		"rotation": _normalize_rotation(rotation_degrees),
	}


func _assignment_is_valid(assignment_value: Dictionary) -> bool:
	if assignment_value.size() != WORLD_COLUMNS * WORLD_ROWS:
		return false
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			var entry: Dictionary = _assignment_at(
				assignment_value,
				module_coord
			)
			if (
				entry.is_empty()
				or not _templates_by_id.has(
					String(entry.get("template_id", ""))
				)
			):
				return false
			if not _entry_fits_assigned_neighbors(
				module_coord,
				assignment_value
			):
				return false
	return (
		_all_floor_cells_reachable(assignment_value)
		and _assignment_matches_constrained_limited_groups(assignment_value)
	)


func _assignment_matches_constrained_limited_groups(
	assignment_value: Dictionary
) -> bool:
	for raw_entry: Variant in assignment_value.values():
		if not raw_entry is Dictionary:
			return false
		if (
			String((raw_entry as Dictionary).get("role", ""))
			== MODULE_ROLES.MODULE_ROLE_SEALED
		):
			# The checked-in technical slice intentionally contains no network.
			return true
	var raw_groups: Variant = _world_def.get("limited_template_groups", [])
	if not raw_groups is Array:
		return false
	for raw_group: Variant in raw_groups as Array:
		if not raw_group is Dictionary:
			return false
		var group: Dictionary = raw_group as Dictionary
		var minimum_distance: int = int(
			group.get("minimum_manhattan_distance", 0)
		)
		if minimum_distance <= 0:
			continue
		var raw_entries: Variant = group.get("entries", [])
		if not raw_entries is Array:
			return false
		var expected_counts: Dictionary = {}
		for raw_limited_entry: Variant in raw_entries as Array:
			if not raw_limited_entry is Dictionary:
				return false
			var limited_entry: Dictionary = raw_limited_entry as Dictionary
			expected_counts[String(limited_entry.get("template_id", ""))] = int(
				limited_entry.get("count_per_floor", 0)
			)
		var coords_by_template: Dictionary = {}
		var all_coords: Array[Vector2i] = []
		for raw_assignment_entry: Variant in assignment_value.values():
			var assignment_entry: Dictionary = raw_assignment_entry as Dictionary
			var template_id: String = String(
				assignment_entry.get("template_id", "")
			)
			if not expected_counts.has(template_id):
				continue
			if not coords_by_template.has(template_id):
				coords_by_template[template_id] = []
			var coord: Vector2i = _coord_from_variant(
				assignment_entry.get("slot", {}),
				INVALID_COORD
			)
			if not is_module_coord_valid(coord):
				return false
			(coords_by_template[template_id] as Array).append(coord)
			all_coords.append(coord)
		if coords_by_template.size() != int(group.get("pick_distinct", 0)):
			return false
		for raw_template_id: Variant in coords_by_template.keys():
			var template_id: String = String(raw_template_id)
			if (coords_by_template[template_id] as Array).size() != int(
				expected_counts.get(template_id, 0)
			):
				return false
		for left_index: int in range(all_coords.size()):
			for right_index: int in range(left_index + 1, all_coords.size()):
				var left: Vector2i = all_coords[left_index]
				var right: Vector2i = all_coords[right_index]
				if (
					absi(left.x - right.x) + absi(left.y - right.y)
					< minimum_distance
				):
					return false
	return true


func _entry_fits_assigned_neighbors(
	module_coord: Vector2i,
	assignment_value: Dictionary
) -> bool:
	if _is_sealed_module(module_coord, assignment_value):
		return true
	var neighbor_checks: Array[Dictionary] = [
		{
			"offset": Vector2i.UP,
			"edge": MODULE_EDGE_DIRECTIONS.EDGE_NORTH,
			"opposite": MODULE_EDGE_DIRECTIONS.EDGE_SOUTH,
		},
		{
			"offset": Vector2i.RIGHT,
			"edge": MODULE_EDGE_DIRECTIONS.EDGE_EAST,
			"opposite": MODULE_EDGE_DIRECTIONS.EDGE_WEST,
		},
		{
			"offset": Vector2i.DOWN,
			"edge": MODULE_EDGE_DIRECTIONS.EDGE_SOUTH,
			"opposite": MODULE_EDGE_DIRECTIONS.EDGE_NORTH,
		},
		{
			"offset": Vector2i.LEFT,
			"edge": MODULE_EDGE_DIRECTIONS.EDGE_WEST,
			"opposite": MODULE_EDGE_DIRECTIONS.EDGE_EAST,
		},
	]
	for check: Dictionary in neighbor_checks:
		var neighbor_coord: Vector2i = module_coord + (
			check.get("offset", Vector2i.ZERO) as Vector2i
		)
		if not is_module_coord_valid(neighbor_coord):
			if (
				not bool(_world_def.get("seal_outer_edges", false))
				and not _rotated_edge_sockets(
					module_coord,
					String(check.get("edge", "")),
					assignment_value
				).is_empty()
			):
				return false
			continue
		if not assignment_value.has(_slot_key(neighbor_coord)):
			continue
		if _is_sealed_module(neighbor_coord, assignment_value):
			continue
		var current_sockets: Array[int] = _rotated_edge_sockets(
			module_coord,
			String(check.get("edge", "")),
			assignment_value
		)
		var neighbor_sockets: Array[int] = _rotated_edge_sockets(
			neighbor_coord,
			String(check.get("opposite", "")),
			assignment_value
		)
		if not _socket_arrays_overlap(current_sockets, neighbor_sockets):
			return false
	return true


func _socket_arrays_overlap(left: Array[int], right: Array[int]) -> bool:
	for socket_index: int in left:
		if right.has(socket_index):
			return true
	return false


func _rotated_edge_sockets(
	module_coord: Vector2i,
	world_edge: String,
	assignment_value: Dictionary
) -> Array[int]:
	var entry: Dictionary = _assignment_at(assignment_value, module_coord)
	var template_data: Dictionary = _dictionary_or_empty(
		_templates_by_id.get(String(entry.get("template_id", "")), {})
	)
	var edge_sockets: Dictionary = _dictionary_or_empty(
		template_data.get("edge_sockets", {})
	)
	var rotation_degrees: int = int(entry.get("rotation", 0))
	var result: Array[int] = []
	for source_edge: String in MODULE_EDGE_DIRECTIONS.VALUES:
		for raw_index: Variant in _array_or_empty(
			edge_sockets.get(source_edge, [])
		):
			var source_cell: Vector2i = _edge_cell(
				source_edge,
				int(raw_index)
			)
			var rotated_cell: Vector2i = _rotate_local_cell(
				source_cell,
				rotation_degrees
			)
			if _edge_for_cell(rotated_cell) == world_edge:
				result.append(_edge_index(world_edge, rotated_cell))
	result.sort()
	return result


func _all_floor_cells_reachable(assignment_value: Dictionary) -> bool:
	var start_cell: Vector2i = INVALID_COORD
	var passable_count: int = 0
	for global_y: int in range(WORLD_CELL_ROWS):
		for global_x: int in range(WORLD_CELL_COLUMNS):
			var global_cell := Vector2i(global_x, global_y)
			if (
				_terrain_at_global_cell(global_cell, assignment_value)
				== MODULE_CELL_TOKENS.MODULE_CELL_FLOOR
			):
				passable_count += 1
				if start_cell == INVALID_COORD:
					start_cell = global_cell
	if passable_count == 0:
		return false
	var pending: Array[Vector2i] = [start_cell]
	var visited_cells: Dictionary = {_global_cell_key(start_cell): true}
	var cursor: int = 0
	var cardinal_offsets: Array[Vector2i] = [
		Vector2i.UP,
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
	]
	while cursor < pending.size():
		var cell: Vector2i = pending[cursor]
		cursor += 1
		for offset: Vector2i in cardinal_offsets:
			var neighbor: Vector2i = cell + offset
			var neighbor_key: String = _global_cell_key(neighbor)
			if (
				not is_global_cell_valid(neighbor)
				or visited_cells.has(neighbor_key)
			):
				continue
			if (
				_terrain_at_global_cell(neighbor, assignment_value)
				!= MODULE_CELL_TOKENS.MODULE_CELL_FLOOR
			):
				continue
			visited_cells[neighbor_key] = true
			pending.append(neighbor)
	return visited_cells.size() == passable_count


func _terrain_at_global_cell(
	global_cell: Vector2i,
	assignment_value: Dictionary
) -> String:
	var module_and_local: Dictionary = global_cell_to_module_and_local(
		global_cell
	)
	var module_coord: Vector2i = module_and_local.get(
		"module_coord",
		INVALID_COORD
	) as Vector2i
	var local_cell: Vector2i = module_and_local.get(
		"local_cell",
		INVALID_COORD
	) as Vector2i
	if (
		not is_module_coord_valid(module_coord)
		or _cell_is_masked(module_coord, local_cell, assignment_value)
	):
		return MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED
	var entry: Dictionary = _assignment_at(assignment_value, module_coord)
	var template_data: Dictionary = _dictionary_or_empty(
		_templates_by_id.get(String(entry.get("template_id", "")), {})
	)
	var terrain_rows: Array = _array_or_empty(
		template_data.get("terrain_rows", [])
	)
	var source_cell: Vector2i = _inverse_rotate_local_cell(
		local_cell,
		int(entry.get("rotation", 0))
	)
	if (
		source_cell.y < 0
		or source_cell.y >= terrain_rows.size()
		or not terrain_rows[source_cell.y] is Array
	):
		return MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED
	var source_row: Array = terrain_rows[source_cell.y] as Array
	if source_cell.x < 0 or source_cell.x >= source_row.size():
		return MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED
	return String(source_row[source_cell.x])


func _cell_is_masked(
	module_coord: Vector2i,
	local_cell: Vector2i,
	assignment_value: Dictionary
) -> bool:
	var masked_edges: Array[String] = _masked_edges_for_coord(
		module_coord,
		assignment_value
	)
	if (
		local_cell.y == 0
		and masked_edges.has(MODULE_EDGE_DIRECTIONS.EDGE_NORTH)
	):
		return true
	if (
		local_cell.x == MODULE_COLUMNS - 1
		and masked_edges.has(MODULE_EDGE_DIRECTIONS.EDGE_EAST)
	):
		return true
	if (
		local_cell.y == MODULE_ROWS - 1
		and masked_edges.has(MODULE_EDGE_DIRECTIONS.EDGE_SOUTH)
	):
		return true
	if (
		local_cell.x == 0
		and masked_edges.has(MODULE_EDGE_DIRECTIONS.EDGE_WEST)
	):
		return true
	return false


func _masked_edges_for_coord(
	module_coord: Vector2i,
	assignment_value: Dictionary
) -> Array[String]:
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
	if _is_sealed_module(module_coord + Vector2i.UP, assignment_value):
		result.append(MODULE_EDGE_DIRECTIONS.EDGE_NORTH)
	if _is_sealed_module(module_coord + Vector2i.RIGHT, assignment_value):
		result.append(MODULE_EDGE_DIRECTIONS.EDGE_EAST)
	if _is_sealed_module(module_coord + Vector2i.DOWN, assignment_value):
		result.append(MODULE_EDGE_DIRECTIONS.EDGE_SOUTH)
	if _is_sealed_module(module_coord + Vector2i.LEFT, assignment_value):
		result.append(MODULE_EDGE_DIRECTIONS.EDGE_WEST)
	return result


func _is_sealed_module(
	module_coord: Vector2i,
	assignment_value: Dictionary
) -> bool:
	if not is_module_coord_valid(module_coord):
		return false
	return (
		String(
			_assignment_at(assignment_value, module_coord).get("role", "")
		)
		== MODULE_ROLES.MODULE_ROLE_SEALED
	)


func _compute_map_hash_for(
	assignment_value: Dictionary,
	run_seed_value: int
) -> String:
	var hash_payload: Dictionary = {
		# Include authoritative content as well as the slot assignment. A run
		# fails closed if geometry, sockets, terrain or placements change.
		"world": _world_def,
		"run_seed": run_seed_value,
		"assignment": _assignment_entries_for(assignment_value),
		"assigned_templates": _assigned_template_payloads(assignment_value),
	}
	return _stable_serialize(hash_payload).sha256_text()


func _assigned_template_payloads(assignment_value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for assignment_entry: Dictionary in _assignment_entries_for(
		assignment_value
	):
		var template_id: String = String(
			assignment_entry.get("template_id", "")
		)
		if (
			template_id.is_empty()
			or result.has(template_id)
			or not _templates_by_id.has(template_id)
		):
			continue
		result[template_id] = (
			_templates_by_id[template_id] as Dictionary
		).duplicate(true)
	return result


func _assignment_entries_for(
	assignment_value: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row_index: int in range(WORLD_ROWS):
		for column_index: int in range(WORLD_COLUMNS):
			var module_coord := Vector2i(column_index, row_index)
			if assignment_value.has(_slot_key(module_coord)):
				result.append(_assignment_at(assignment_value, module_coord))
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
			pairs.append(
				"%s:%s"
				% [JSON.stringify(key), _stable_serialize(dictionary.get(key))]
			)
		return "{%s}" % ",".join(pairs)
	if value is Array:
		var items: PackedStringArray = PackedStringArray()
		for item: Variant in value as Array:
			items.append(_stable_serialize(item))
		return "[%s]" % ",".join(items)
	return JSON.stringify(value)


func _assignment_seed() -> int:
	var seed_text: String = (
		"wasd:module-world-assignment:v1:%s:%d"
		% [String(_world_def.get("id", "")), _run_seed]
	)
	var digest_text: String = seed_text.sha256_text()
	var derived_seed: int = 0
	for index: int in range(digest_text.length()):
		derived_seed = (
			derived_seed * 16 + _hex_value(digest_text.unicode_at(index))
		) % ASSIGNMENT_SEED_MODULUS
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
	if (
		edge == MODULE_EDGE_DIRECTIONS.EDGE_NORTH
		or edge == MODULE_EDGE_DIRECTIONS.EDGE_SOUTH
	):
		return local_cell.x
	return local_cell.y


func _rotate_local_cell(
	local_cell: Vector2i,
	rotation_degrees: int
) -> Vector2i:
	match _normalize_rotation(rotation_degrees):
		90:
			return Vector2i(MODULE_ROWS - 1 - local_cell.y, local_cell.x)
		180:
			return Vector2i(
				MODULE_COLUMNS - 1 - local_cell.x,
				MODULE_ROWS - 1 - local_cell.y
			)
		270:
			return Vector2i(local_cell.y, MODULE_COLUMNS - 1 - local_cell.x)
		_:
			return local_cell


func _occupied_local_cells(module_coord: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	var entry: Dictionary = assignment_at(module_coord)
	var template_data: Dictionary = _dictionary_or_empty(
		_templates_by_id.get(String(entry.get("template_id", "")), {})
	)
	var rotation_degrees: int = int(entry.get("rotation", 0))
	for raw_placement: Variant in _array_or_empty(
		template_data.get("placements", [])
	):
		if not raw_placement is Dictionary:
			continue
		var placement: Dictionary = raw_placement as Dictionary
		var source_cell: Vector2i = _coord_from_variant(
			placement.get("cell", {}),
			INVALID_COORD
		)
		if not is_local_cell_valid(source_cell):
			continue
		var footprint: Dictionary = _dictionary_or_empty(
			placement.get("footprint", {})
		)
		var width: int = maxi(int(footprint.get("width", 1)), 1)
		var height: int = maxi(int(footprint.get("height", 1)), 1)
		for offset_y: int in range(height):
			for offset_x: int in range(width):
				var rotated_cell: Vector2i = _rotate_local_cell(
					source_cell + Vector2i(offset_x, offset_y),
					rotation_degrees
				)
				if is_local_cell_valid(rotated_cell):
					result[rotated_cell] = true
	return result


func _inverse_rotate_local_cell(
	local_cell: Vector2i,
	rotation_degrees: int
) -> Vector2i:
	return _rotate_local_cell(
		local_cell,
		posmod(
			ROTATION_FULL - _normalize_rotation(rotation_degrees),
			ROTATION_FULL
		)
	)


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


func _assignment_at(
	assignment_value: Dictionary,
	module_coord: Vector2i
) -> Dictionary:
	return _dictionary_or_empty(
		assignment_value.get(_slot_key(module_coord), {})
	)


func _slot_key(module_coord: Vector2i) -> String:
	return "%d,%d" % [module_coord.x, module_coord.y]


func _global_cell_key(global_cell: Vector2i) -> String:
	return "%d,%d" % [global_cell.x, global_cell.y]


func _coord_to_dict(coord: Vector2i) -> Dictionary:
	return {
		"x": coord.x,
		"y": coord.y,
	}


func _coord_from_variant(
	raw_value: Variant,
	fallback: Vector2i
) -> Vector2i:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2i(
		int(value.get("x", fallback.x)),
		int(value.get("y", fallback.y))
	)


func _vector_from_variant(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(
		float(value.get("x", fallback.x)),
		float(value.get("y", fallback.y))
	)


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []
