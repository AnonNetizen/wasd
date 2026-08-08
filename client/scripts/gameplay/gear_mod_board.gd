# Doc: docs/代码/gear_mod_system.md
# Authority: docs/游戏设计文档.md §7.2
class_name GearModBoard
extends RefCounted


const GEAR_MOD_GRID_BEHAVIORS := preload(
	"res://scripts/contracts/gear_mod_grid_behaviors.gd"
)
const GEAR_MOD_KINDS := preload("res://scripts/contracts/gear_mod_kinds.gd")
const GEAR_MOD_MAP_BEHAVIORS := preload(
	"res://scripts/contracts/gear_mod_map_behaviors.gd"
)
const GEAR_MOD_PLACEMENT_OUTCOMES := preload(
	"res://scripts/contracts/gear_mod_placement_outcomes.gd"
)

const INVALID_CELL := Vector2i(-1, -1)
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
]

var _width: int = 0
var _height: int = 0
var _center: Vector2i = INVALID_CELL
var _initial_unlocked: Dictionary = {}
var _unlocked: Dictionary = {}
var _unlock_sources: Dictionary = {}
var _definitions_by_id: Dictionary = {}
var _placements_by_instance: Dictionary = {}
var _instance_by_cell: Dictionary = {}
var _map_behavior_states: Dictionary = {}
var _configured: bool = false


func configure(
	board_config: Dictionary,
	definitions: Array[Dictionary]
) -> bool:
	if not _has_exact_keys(
		board_config,
		["width", "height", "center", "initial_unlocked_cells"]
	):
		return false
	var width: int = _int_or_invalid(board_config.get("width"))
	var height: int = _int_or_invalid(board_config.get("height"))
	if width <= 0 or height <= 0:
		return false
	var center: Vector2i = _board_cell_or_invalid(
		board_config.get("center"),
		width,
		height
	)
	if center == INVALID_CELL:
		return false
	var raw_initial_cells: Variant = board_config.get("initial_unlocked_cells")
	if not raw_initial_cells is Array:
		return false
	var initial_unlocked: Dictionary = {}
	for raw_cell: Variant in raw_initial_cells as Array:
		var cell: Vector2i = _board_cell_or_invalid(raw_cell, width, height)
		if cell == INVALID_CELL or initial_unlocked.has(cell):
			return false
		initial_unlocked[cell] = true
	if not initial_unlocked.has(center):
		return false
	var definitions_by_id: Dictionary = {}
	for definition: Dictionary in definitions:
		if not _is_valid_definition(definition):
			return false
		var mod_id: String = String(definition.get("id", ""))
		if definitions_by_id.has(mod_id):
			return false
		definitions_by_id[mod_id] = definition.duplicate(true)

	_width = width
	_height = height
	_center = center
	_initial_unlocked = initial_unlocked
	_unlocked = initial_unlocked.duplicate()
	_unlock_sources.clear()
	_definitions_by_id = definitions_by_id
	_placements_by_instance.clear()
	_instance_by_cell.clear()
	_map_behavior_states.clear()
	_configured = true
	return true


func center() -> Vector2i:
	return _center


func snapshot() -> Dictionary:
	return {
		"unlocked_cells": _serialize_cells(_sorted_dictionary_cells(_unlocked)),
		"unlock_sources": _unlock_source_snapshots(),
		"placements": placements(),
		"map_behavior_states": _map_behavior_state_snapshots(),
	}


func restore_snapshot(saved: Dictionary) -> bool:
	if not _configured or not _has_exact_keys(
		saved,
		[
			"unlocked_cells",
			"unlock_sources",
			"placements",
			"map_behavior_states",
		]
	):
		return false
	var restored_unlocked: Dictionary = _parse_unique_board_cells(
		saved.get("unlocked_cells")
	)
	if restored_unlocked.is_empty():
		return false
	for initial_cell: Variant in _initial_unlocked.keys():
		if not restored_unlocked.has(initial_cell):
			return false

	var restored_sources: Dictionary = {}
	var expected_unlocked: Dictionary = _initial_unlocked.duplicate()
	var raw_sources: Variant = saved.get("unlock_sources")
	if not raw_sources is Array:
		return false
	for raw_source: Variant in raw_sources as Array:
		if not raw_source is Dictionary:
			return false
		var source: Dictionary = raw_source as Dictionary
		if not _has_exact_keys(source, ["source_id", "cells"]):
			return false
		var source_id: String = String(source.get("source_id", "")).strip_edges()
		if source_id.is_empty() or restored_sources.has(source_id):
			return false
		var source_cells_by_key: Dictionary = _parse_unique_board_cells(
			source.get("cells")
		)
		if source_cells_by_key.is_empty():
			return false
		var source_cells: Array[Vector2i] = _sorted_dictionary_cells(
			source_cells_by_key
		)
		restored_sources[source_id] = source_cells
		for cell: Vector2i in source_cells:
			expected_unlocked[cell] = true
	if not _same_cell_sets(restored_unlocked, expected_unlocked):
		return false

	var restored_placements: Dictionary = {}
	var restored_instances_by_cell: Dictionary = {}
	var raw_placements: Variant = saved.get("placements")
	if not raw_placements is Array:
		return false
	for raw_placement: Variant in raw_placements as Array:
		if not raw_placement is Dictionary:
			return false
		var placement: Dictionary = raw_placement as Dictionary
		if not _has_exact_keys(
			placement,
			["instance_id", "mod_id", "x", "y"]
		):
			return false
		var instance_id: int = _positive_instance_id_or_invalid(
			placement.get("instance_id")
		)
		var mod_id: String = String(placement.get("mod_id", ""))
		var cell: Vector2i = _board_cell_or_invalid(
			{"x": placement.get("x"), "y": placement.get("y")},
			_width,
			_height
		)
		if (
			instance_id <= 0
			or restored_placements.has(instance_id)
			or not _definitions_by_id.has(mod_id)
			or cell == INVALID_CELL
			or cell == _center
			or not restored_unlocked.has(cell)
			or restored_instances_by_cell.has(cell)
		):
			return false
		var normalized: Dictionary = {
			"instance_id": instance_id,
			"mod_id": mod_id,
			"x": cell.x,
			"y": cell.y,
		}
		restored_placements[instance_id] = normalized
		restored_instances_by_cell[cell] = instance_id
	if not _placements_connect_to_core(restored_placements):
		return false

	var restored_map_states: Dictionary = {}
	var raw_states: Variant = saved.get("map_behavior_states")
	if not raw_states is Array:
		return false
	for raw_state: Variant in raw_states as Array:
		if not raw_state is Dictionary:
			return false
		var state_snapshot: Dictionary = raw_state as Dictionary
		if not _has_exact_keys(
			state_snapshot,
			["instance_id", "elapsed", "pending_plan"]
		):
			return false
		var instance_id: int = _positive_instance_id_or_invalid(
			state_snapshot.get("instance_id")
		)
		if (
			instance_id <= 0
			or restored_map_states.has(instance_id)
			or not restored_placements.has(instance_id)
		):
			return false
		var placement: Dictionary = restored_placements[instance_id] as Dictionary
		var definition: Dictionary = _definitions_by_id[
			String(placement.get("mod_id", ""))
		] as Dictionary
		if String(definition.get("kind", "")) != GEAR_MOD_KINDS.MAP:
			return false
		var placement_cell := Vector2i(
			int(placement.get("x", -1)),
			int(placement.get("y", -1))
		)
		var normalized_states: Array[Dictionary] = []
		if not _normalize_map_behavior_state(
			{
				"elapsed": state_snapshot.get("elapsed"),
				"pending_plan": state_snapshot.get("pending_plan"),
			},
			normalized_states,
			placement_cell
		):
			return false
		restored_map_states[instance_id] = normalized_states[0]
	var expected_map_instances: Dictionary = {}
	for raw_instance_id: Variant in restored_placements.keys():
		var placement: Dictionary = restored_placements[raw_instance_id] as Dictionary
		var definition: Dictionary = _definitions_by_id[
			String(placement.get("mod_id", ""))
		] as Dictionary
		if String(definition.get("kind", "")) == GEAR_MOD_KINDS.MAP:
			expected_map_instances[int(raw_instance_id)] = true
	if restored_map_states.size() != expected_map_instances.size():
		return false
	for raw_instance_id: Variant in expected_map_instances.keys():
		if not restored_map_states.has(raw_instance_id):
			return false

	_unlocked = restored_unlocked
	_unlock_sources = restored_sources
	_placements_by_instance = restored_placements
	_instance_by_cell = restored_instances_by_cell
	_map_behavior_states = restored_map_states
	return true


func placements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_placement: Variant in _placements_by_instance.values():
		if raw_placement is Dictionary:
			result.append((raw_placement as Dictionary).duplicate(true))
	result.sort_custom(_placement_less)
	return result


func legal_cells(mod_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _configured or not _definitions_by_id.has(mod_id):
		return result
	for cell: Vector2i in _sorted_dictionary_cells(_unlocked):
		if _is_legal_new_cell(cell):
			result.append(cell)
	return result


func request_placement(
	instance_id: int,
	mod_id: String,
	target: Vector2i
) -> Dictionary:
	if (
		not _configured
		or instance_id <= 0
		or _placements_by_instance.has(instance_id)
		or not _definitions_by_id.has(mod_id)
		or not _is_legal_new_cell(target)
	):
		return _cancelled_result()
	var definition: Dictionary = _definitions_by_id[mod_id] as Dictionary
	var kind: String = String(definition.get("kind", ""))
	var placement: Dictionary = {
		"instance_id": instance_id,
		"mod_id": mod_id,
		"x": target.x,
		"y": target.y,
	}
	_placements_by_instance[instance_id] = placement
	_instance_by_cell[target] = instance_id
	if kind == GEAR_MOD_KINDS.MAP:
		_map_behavior_states[instance_id] = _default_map_behavior_state()
	return {
		"ok": true,
		"outcome": GEAR_MOD_PLACEMENT_OUTCOMES.PLACED,
		"placement": placement.duplicate(true),
	}


func unlock_cells(
	coords: Array[Vector2i],
	source_id: String
) -> Dictionary:
	var normalized_source: String = source_id.strip_edges()
	if not _configured or normalized_source.is_empty() or coords.is_empty():
		return {"ok": false, "changed": false, "cells": []}
	var requested: Dictionary = {}
	for cell: Vector2i in coords:
		if not _cell_is_inside(cell) or requested.has(cell):
			return {"ok": false, "changed": false, "cells": []}
		requested[cell] = true
	var requested_cells: Array[Vector2i] = _sorted_dictionary_cells(requested)
	if _unlock_sources.has(normalized_source):
		var existing_cells: Array[Vector2i] = _copy_cell_array(
			_unlock_sources[normalized_source]
		)
		if existing_cells != requested_cells:
			return {"ok": false, "changed": false, "cells": []}
		return {
			"ok": true,
			"changed": false,
			"cells": [],
		}
	var newly_unlocked: Array[Vector2i] = []
	for cell: Vector2i in requested_cells:
		if not _unlocked.has(cell):
			newly_unlocked.append(cell)
		_unlocked[cell] = true
	_unlock_sources[normalized_source] = requested_cells
	return {
		"ok": true,
		"changed": not newly_unlocked.is_empty(),
		"cells": _serialize_cells(newly_unlocked),
	}


func request_relocation(
	instance_id: int,
	target: Vector2i,
	cost_authorizer: Callable = Callable()
) -> Dictionary:
	if (
		not _configured
		or instance_id <= 0
		or not _placements_by_instance.has(instance_id)
		or not cost_authorizer.is_valid()
		or not _cell_is_inside(target)
		or target == _center
		or not _unlocked.has(target)
	):
		return _cancelled_result()
	var placement: Dictionary = _placements_by_instance[instance_id] as Dictionary
	var old_cell: Vector2i = _board_cell_or_invalid(
		{"x": placement.get("x"), "y": placement.get("y")},
		_width,
		_height
	)
	if target == old_cell:
		return _cancelled_result()
	if _instance_by_cell.has(target) and int(_instance_by_cell[target]) != instance_id:
		return _cancelled_result()
	var candidate_placements: Dictionary = _placements_by_instance.duplicate(true)
	var candidate: Dictionary = placement.duplicate(true)
	candidate["x"] = target.x
	candidate["y"] = target.y
	candidate_placements[instance_id] = candidate
	if not _placements_connect_to_core(candidate_placements):
		return _cancelled_result()
	var authorization: Variant = cost_authorizer.call(instance_id, target)
	var authorized: bool = false
	if authorization is bool:
		authorized = bool(authorization)
	elif authorization is Dictionary:
		authorized = bool((authorization as Dictionary).get("ok", false))
	if not authorized:
		return _cancelled_result()
	_instance_by_cell.erase(old_cell)
	_instance_by_cell[target] = instance_id
	_placements_by_instance[instance_id] = candidate
	var definition: Dictionary = _definitions_by_id[
		String(candidate.get("mod_id", ""))
	] as Dictionary
	if String(definition.get("kind", "")) == GEAR_MOD_KINDS.MAP:
		_map_behavior_states[instance_id] = _default_map_behavior_state()
	return {
		"ok": true,
		"outcome": GEAR_MOD_PLACEMENT_OUTCOMES.PLACED,
		"placement": candidate.duplicate(true),
	}


func set_map_behavior_state(instance_id: int, state: Dictionary) -> bool:
	if not _map_behavior_states.has(instance_id):
		return false
	var placement: Dictionary = _placements_by_instance.get(
		instance_id,
		{}
	) as Dictionary
	var placement_cell := Vector2i(
		int(placement.get("x", -1)),
		int(placement.get("y", -1))
	)
	var normalized: Array[Dictionary] = []
	if not _normalize_map_behavior_state(
		state,
		normalized,
		placement_cell
	):
		return false
	_map_behavior_states[instance_id] = normalized[0]
	return true


func map_behavior_state(instance_id: int) -> Dictionary:
	if not _map_behavior_states.has(instance_id):
		return {}
	return (_map_behavior_states[instance_id] as Dictionary).duplicate(true)


func map_behavior_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement: Dictionary in placements():
		var instance_id: int = int(placement.get("instance_id", 0))
		var mod_id: String = String(placement.get("mod_id", ""))
		var definition: Dictionary = _definitions_by_id[mod_id] as Dictionary
		if String(definition.get("kind", "")) != GEAR_MOD_KINDS.MAP:
			continue
		result.append({
			"instance_id": instance_id,
			"mod_id": mod_id,
			"x": int(placement.get("x", -1)),
			"y": int(placement.get("y", -1)),
			"behavior": (
				definition.get("map_behavior", {}) as Dictionary
			).duplicate(true),
			"state": map_behavior_state(instance_id),
		})
	return result


func _is_valid_definition(definition: Dictionary) -> bool:
	var mod_id: String = String(definition.get("id", "")).strip_edges()
	var kind: String = String(definition.get("kind", ""))
	if mod_id.is_empty() or not GEAR_MOD_KINDS.VALUES.has(kind):
		return false
	if kind == GEAR_MOD_KINDS.EFFECT:
		return (
			definition.get("slot") is String
			and not String(definition.get("slot", "")).is_empty()
			and definition.get("modifiers") is Array
			and not (definition.get("modifiers") as Array).is_empty()
			and not definition.has("map_behavior")
			and not definition.has("grid_behavior")
		)
	if kind == GEAR_MOD_KINDS.MAP:
		if (
			definition.has("slot")
			or definition.has("modifiers")
			or definition.has("grid_behavior")
			or not definition.get("map_behavior") is Dictionary
		):
			return false
		var map_behavior: Dictionary = definition.get("map_behavior") as Dictionary
		return (
			String(map_behavior.get("id", ""))
			== GEAR_MOD_MAP_BEHAVIORS.PERIODIC_ENEMY_SPAWN
		)
	if kind == GEAR_MOD_KINDS.GRID:
		if (
			definition.has("slot")
			or definition.has("modifiers")
			or definition.has("map_behavior")
			or not definition.get("grid_behavior") is Dictionary
		):
			return false
		var grid_behavior: Dictionary = definition.get("grid_behavior") as Dictionary
		return (
			String(grid_behavior.get("id", ""))
			== GEAR_MOD_GRID_BEHAVIORS.OCCUPY_ONLY
		)
	return false


func _is_legal_new_cell(cell: Vector2i) -> bool:
	if (
		not _cell_is_inside(cell)
		or cell == _center
		or not _unlocked.has(cell)
		or _instance_by_cell.has(cell)
	):
		return false
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = cell + direction
		if neighbor == _center or _instance_by_cell.has(neighbor):
			return true
	return false


func _placements_connect_to_core(candidate_placements: Dictionary) -> bool:
	if candidate_placements.is_empty():
		return true
	var occupied: Dictionary = {}
	for raw_placement: Variant in candidate_placements.values():
		if not raw_placement is Dictionary:
			return false
		var placement: Dictionary = raw_placement as Dictionary
		var cell: Vector2i = _board_cell_or_invalid(
			{"x": placement.get("x"), "y": placement.get("y")},
			_width,
			_height
		)
		if cell == INVALID_CELL or cell == _center or occupied.has(cell):
			return false
		occupied[cell] = true
	var reached: Dictionary = {}
	var frontier: Array[Vector2i] = [_center]
	var cursor: int = 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if not occupied.has(neighbor) or reached.has(neighbor):
				continue
			reached[neighbor] = true
			frontier.append(neighbor)
	return reached.size() == occupied.size()


func _normalize_map_behavior_state(
	state: Dictionary,
	output: Array[Dictionary],
	expected_module_coord: Vector2i
) -> bool:
	if not _has_exact_keys(state, ["elapsed", "pending_plan"]):
		return false
	var raw_elapsed: Variant = state.get("elapsed")
	if (
		not raw_elapsed is int
		and not raw_elapsed is float
	):
		return false
	var elapsed: float = float(raw_elapsed)
	if elapsed < 0.0 or not is_finite(elapsed):
		return false
	var raw_plan: Variant = state.get("pending_plan")
	if not raw_plan is Dictionary:
		return false
	var pending_plan: Dictionary = raw_plan as Dictionary
	var normalized_plan: Dictionary = {}
	if not pending_plan.is_empty():
		if not _has_exact_keys(
			pending_plan,
			["enemy_id", "position", "module_coord"]
		):
			return false
		var enemy_id: String = String(pending_plan.get("enemy_id", "")).strip_edges()
		var position: Dictionary = _serialized_position_or_empty(
			pending_plan.get("position")
		)
		var module_coord: Dictionary = _serialized_integer_coordinate_or_empty(
			pending_plan.get("module_coord")
		)
		var normalized_module_coord: Vector2i = _board_cell_or_invalid(
			module_coord,
			_width,
			_height
		)
		if (
			enemy_id.is_empty()
			or position.is_empty()
			or normalized_module_coord == INVALID_CELL
			or normalized_module_coord != expected_module_coord
		):
			return false
		normalized_plan = {
			"enemy_id": enemy_id,
			"position": position,
			"module_coord": {
				"x": normalized_module_coord.x,
				"y": normalized_module_coord.y,
			},
		}
	output.append({
		"elapsed": elapsed,
		"pending_plan": normalized_plan,
	})
	return true


func _default_map_behavior_state() -> Dictionary:
	return {"elapsed": 0.0, "pending_plan": {}}


func _unlock_source_snapshots() -> Array[Dictionary]:
	var source_ids: Array[String] = []
	for raw_source_id: Variant in _unlock_sources.keys():
		source_ids.append(String(raw_source_id))
	source_ids.sort()
	var result: Array[Dictionary] = []
	for source_id: String in source_ids:
		result.append({
			"source_id": source_id,
			"cells": _serialize_cells(_copy_cell_array(_unlock_sources[source_id])),
		})
	return result


func _map_behavior_state_snapshots() -> Array[Dictionary]:
	var instance_ids: Array[int] = []
	for raw_instance_id: Variant in _map_behavior_states.keys():
		instance_ids.append(int(raw_instance_id))
	instance_ids.sort()
	var result: Array[Dictionary] = []
	for instance_id: int in instance_ids:
		var state: Dictionary = _map_behavior_states[instance_id] as Dictionary
		result.append({
			"instance_id": instance_id,
			"elapsed": float(state.get("elapsed", 0.0)),
			"pending_plan": (
				state.get("pending_plan", {}) as Dictionary
			).duplicate(true),
		})
	return result


func _parse_unique_board_cells(raw_cells: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not raw_cells is Array:
		return result
	for raw_cell: Variant in raw_cells as Array:
		var cell: Vector2i = _board_cell_or_invalid(raw_cell, _width, _height)
		if cell == INVALID_CELL or result.has(cell):
			return {}
		result[cell] = true
	return result


func _sorted_dictionary_cells(cells: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw_cell: Variant in cells.keys():
		if raw_cell is Vector2i:
			result.append(raw_cell as Vector2i)
	result.sort_custom(_cell_less)
	return result


func _copy_cell_array(raw_cells: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not raw_cells is Array:
		return result
	for raw_cell: Variant in raw_cells as Array:
		if raw_cell is Vector2i:
			result.append(raw_cell as Vector2i)
	result.sort_custom(_cell_less)
	return result


func _serialize_cells(cells: Array[Vector2i]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell: Vector2i in cells:
		result.append(_serialize_cell(cell))
	return result


func _serialize_cell(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


func _board_cell_or_invalid(
	raw_cell: Variant,
	width: int,
	height: int
) -> Vector2i:
	if not raw_cell is Dictionary:
		return INVALID_CELL
	var cell: Dictionary = raw_cell as Dictionary
	if not _has_exact_keys(cell, ["x", "y"]):
		return INVALID_CELL
	var x: int = _int_or_invalid(cell.get("x"))
	var y: int = _int_or_invalid(cell.get("y"))
	if x < 0 or x >= width or y < 0 or y >= height:
		return INVALID_CELL
	return Vector2i(x, y)


func _serialized_position_or_empty(raw_position: Variant) -> Dictionary:
	var x_value: Variant
	var y_value: Variant
	if raw_position is Vector2:
		x_value = (raw_position as Vector2).x
		y_value = (raw_position as Vector2).y
	elif raw_position is Dictionary:
		var position: Dictionary = raw_position as Dictionary
		if not _has_exact_keys(position, ["x", "y"]):
			return {}
		x_value = position.get("x")
		y_value = position.get("y")
	else:
		return {}
	if (
		(not x_value is int and not x_value is float)
		or (not y_value is int and not y_value is float)
	):
		return {}
	var x: float = float(x_value)
	var y: float = float(y_value)
	if not is_finite(x) or not is_finite(y):
		return {}
	return {"x": x, "y": y}


func _serialized_integer_coordinate_or_empty(raw_coord: Variant) -> Dictionary:
	var x_value: Variant
	var y_value: Variant
	if raw_coord is Vector2i:
		x_value = (raw_coord as Vector2i).x
		y_value = (raw_coord as Vector2i).y
	elif raw_coord is Dictionary:
		var coord: Dictionary = raw_coord as Dictionary
		if not _has_exact_keys(coord, ["x", "y"]):
			return {}
		x_value = coord.get("x")
		y_value = coord.get("y")
	else:
		return {}
	var x: int = _int_or_invalid(x_value)
	var y: int = _int_or_invalid(y_value)
	if x == -1 or y == -1:
		return {}
	return {"x": x, "y": y}


func _positive_instance_id_or_invalid(raw_value: Variant) -> int:
	if not raw_value is int or int(raw_value) <= 0:
		return -1
	return int(raw_value)


func _int_or_invalid(raw_value: Variant) -> int:
	if raw_value is int:
		return int(raw_value)
	if raw_value is float:
		var numeric: float = float(raw_value)
		if is_finite(numeric) and numeric == floor(numeric):
			return int(numeric)
	return -1


func _cell_is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _width and cell.y >= 0 and cell.y < _height


func _same_cell_sets(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for raw_cell: Variant in left.keys():
		if not right.has(raw_cell):
			return false
	return true


func _has_exact_keys(data: Dictionary, expected_keys: Array[String]) -> bool:
	if data.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not data.has(key):
			return false
	return true


func _cancelled_result() -> Dictionary:
	return {
		"ok": false,
		"outcome": GEAR_MOD_PLACEMENT_OUTCOMES.CANCELLED,
	}


func _cell_less(left: Vector2i, right: Vector2i) -> bool:
	if left.y != right.y:
		return left.y < right.y
	return left.x < right.x


func _placement_less(left: Dictionary, right: Dictionary) -> bool:
	var left_cell: Vector2i = _board_cell_or_invalid(
		{"x": left.get("x"), "y": left.get("y")},
		_width,
		_height
	)
	var right_cell: Vector2i = _board_cell_or_invalid(
		{"x": right.get("x"), "y": right.get("y")},
		_width,
		_height
	)
	if left_cell != right_cell:
		return _cell_less(left_cell, right_cell)
	return int(left.get("instance_id", 0)) < int(right.get("instance_id", 0))
