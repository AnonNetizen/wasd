# Doc: docs/代码/module_world_manager.md
class_name ModuleChunk
extends Node2D
## Reusable visual/collision carrier for one 11 x 11 module assignment.
## It draws terrain and exposes converted placement data, but never creates gameplay entities.

const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_EDGE_DIRECTIONS := preload("res://scripts/contracts/module_edge_directions.gd")

const MODULE_SIZE: int = 11
const WORLD_CENTER_GLOBAL_CELL: Vector2i = Vector2i(49, 49)
const FLOOR_COLOR: Color = Color(0.075, 0.09, 0.105, 1.0)
const BLOCKED_COLOR: Color = Color(0.18, 0.205, 0.235, 1.0)
const GRID_COLOR: Color = Color(0.25, 0.29, 0.33, 0.28)
const TERRAIN_COLLISION_LAYER: int = 1 << 0

var _template: Dictionary = {}
var _module_coord: Vector2i = Vector2i(-1, -1)
var _rotation: int = 0
var _cell_size: float = 160.0
var _world_origin: Vector2 = Vector2.ZERO
var _columns: int = MODULE_SIZE
var _rows: int = MODULE_SIZE
var _terrain_rows: Array = []
var _placements: Array[Dictionary] = []
var _collision_body: StaticBody2D = null
var _collision_shape: CollisionShape2D = null


func _draw() -> void:
	if _terrain_rows.is_empty():
		return
	var half_cell: float = _cell_size * 0.5
	var module_rect := Rect2(
		Vector2(-half_cell, -half_cell),
		Vector2(float(_columns) * _cell_size, float(_rows) * _cell_size)
	)
	draw_rect(module_rect, FLOOR_COLOR)
	for row_index: int in range(_rows):
		var run_start: int = -1
		for column_index: int in range(_columns + 1):
			var blocked: bool = column_index < _columns and _is_blocked(Vector2i(column_index, row_index))
			if blocked and run_start < 0:
				run_start = column_index
			elif not blocked and run_start >= 0:
				var run_width: int = column_index - run_start
				var run_rect := Rect2(
					Vector2(float(run_start) * _cell_size - half_cell, float(row_index) * _cell_size - half_cell),
					Vector2(float(run_width) * _cell_size, _cell_size)
				)
				draw_rect(run_rect, BLOCKED_COLOR)
				run_start = -1
	for column_line: int in range(_columns + 1):
		var line_x: float = float(column_line) * _cell_size - half_cell
		draw_line(
			Vector2(line_x, -half_cell),
			Vector2(line_x, float(_rows) * _cell_size - half_cell),
			GRID_COLOR,
			1.0
		)
	for row_line: int in range(_rows + 1):
		var line_y: float = float(row_line) * _cell_size - half_cell
		draw_line(
			Vector2(-half_cell, line_y),
			Vector2(float(_columns) * _cell_size - half_cell, line_y),
			GRID_COLOR,
			1.0
		)


func configure(
	template: Dictionary,
	module_coord: Vector2i,
	rotation: int,
	cell_size: float,
	world_origin: Vector2
) -> void:
	clear()
	_template = template.duplicate(true)
	_module_coord = module_coord
	_rotation = _normalize_rotation(rotation)
	_cell_size = maxf(cell_size, 1.0)
	_world_origin = world_origin
	_columns = maxi(int(_template.get("columns", MODULE_SIZE)), 1)
	_rows = maxi(int(_template.get("rows", MODULE_SIZE)), 1)
	_terrain_rows = _rotate_terrain(_array_or_empty(_template.get("terrain_rows", [])), _rotation)
	_apply_masked_edges(_array_or_empty(_template.get("masked_edges", [])))
	_placements = _rotate_placements(_array_or_empty(_template.get("placements", [])), _rotation)
	position = _world_origin + Vector2(
		float(_module_coord.x * _columns - WORLD_CENTER_GLOBAL_CELL.x) * _cell_size,
		float(_module_coord.y * _rows - WORLD_CENTER_GLOBAL_CELL.y) * _cell_size
	)
	visible = true
	_rebuild_collision()
	queue_redraw()


func clear() -> void:
	_template.clear()
	_module_coord = Vector2i(-1, -1)
	_rotation = 0
	_terrain_rows.clear()
	_placements.clear()
	position = Vector2.ZERO
	visible = false
	if _collision_shape != null and is_instance_valid(_collision_shape):
		_collision_shape.shape = null
		_collision_shape.disabled = true
	queue_redraw()


func reset() -> void:
	clear()


func module_coord() -> Vector2i:
	return _module_coord


func rotation() -> int:
	return _rotation


func template_id() -> String:
	return String(_template.get("id", ""))


func terrain_at_local_cell(local_cell: Vector2i) -> String:
	if not _is_local_cell_valid(local_cell):
		return ""
	var row: Array = _terrain_rows[local_cell.y] as Array
	return String(row[local_cell.x])


func local_cell_to_world(local_cell: Vector2i) -> Vector2:
	return position + Vector2(float(local_cell.x) * _cell_size, float(local_cell.y) * _cell_size)


func world_to_local_cell(world_position: Vector2) -> Vector2i:
	var local_position: Vector2 = world_position - position
	return Vector2i(
		int(floorf(local_position.x / _cell_size + 0.5)),
		int(floorf(local_position.y / _cell_size + 0.5))
	)


func placements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement: Dictionary in _placements:
		var converted: Dictionary = placement.duplicate(true)
		var cell: Vector2i = _cell_from_variant(converted.get("cell", {}))
		converted["world_position"] = _vector_to_dict(local_cell_to_world(cell))
		result.append(converted)
	return result


func placements_of_type(placement_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement: Dictionary in placements():
		if String(placement.get("type", "")) == placement_type:
			result.append(placement)
	return result


func placements_at_local_cell(local_cell: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement: Dictionary in placements():
		if _cell_from_variant(placement.get("cell", {})) == local_cell:
			result.append(placement)
	return result


func debug_summary() -> Dictionary:
	return {
		"template_id": template_id(),
		"module_coord": _coord_to_dict(_module_coord),
		"rotation": _rotation,
		"cell_size": _cell_size,
		"blocked_cells": _blocked_cell_count(),
		"placement_count": _placements.size(),
		"collision_shape_count": 1 if _collision_shape != null and _collision_shape.shape != null else 0,
	}


func _rotate_terrain(source_rows: Array, rotation_degrees: int) -> Array:
	var result: Array = []
	for row_index: int in range(_rows):
		var row: Array = []
		row.resize(_columns)
		row.fill(MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED)
		result.append(row)
	for source_y: int in range(mini(source_rows.size(), _rows)):
		if not source_rows[source_y] is Array:
			continue
		var source_row: Array = source_rows[source_y] as Array
		for source_x: int in range(mini(source_row.size(), _columns)):
			var rotated_cell: Vector2i = _rotate_cell(Vector2i(source_x, source_y), rotation_degrees)
			if _is_cell_inside(rotated_cell, _columns, _rows):
				(result[rotated_cell.y] as Array)[rotated_cell.x] = String(source_row[source_x])
	return result


func _rotate_placements(source_placements: Array, rotation_degrees: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_placement: Variant in source_placements:
		if not raw_placement is Dictionary:
			continue
		var placement: Dictionary = (raw_placement as Dictionary).duplicate(true)
		var source_cell: Vector2i = _cell_from_variant(placement.get("cell", {}))
		placement["cell"] = _coord_to_dict(_rotate_cell(source_cell, rotation_degrees))
		result.append(placement)
	return result


func _apply_masked_edges(raw_edges: Array) -> void:
	for raw_edge: Variant in raw_edges:
		var edge: String = String(raw_edge)
		match edge:
			MODULE_EDGE_DIRECTIONS.EDGE_NORTH:
				_fill_terrain_row(0)
			MODULE_EDGE_DIRECTIONS.EDGE_EAST:
				_fill_terrain_column(_columns - 1)
			MODULE_EDGE_DIRECTIONS.EDGE_SOUTH:
				_fill_terrain_row(_rows - 1)
			MODULE_EDGE_DIRECTIONS.EDGE_WEST:
				_fill_terrain_column(0)
			_:
				continue


func _fill_terrain_row(row_index: int) -> void:
	if row_index < 0 or row_index >= _terrain_rows.size() or not _terrain_rows[row_index] is Array:
		return
	var row: Array = _terrain_rows[row_index] as Array
	for column_index: int in range(row.size()):
		row[column_index] = MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED


func _fill_terrain_column(column_index: int) -> void:
	if column_index < 0 or column_index >= _columns:
		return
	for row_index: int in range(_terrain_rows.size()):
		if _terrain_rows[row_index] is Array and column_index < (_terrain_rows[row_index] as Array).size():
			(_terrain_rows[row_index] as Array)[column_index] = MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED


func _rotate_cell(source_cell: Vector2i, rotation_degrees: int) -> Vector2i:
	match rotation_degrees:
		90:
			return Vector2i(_rows - 1 - source_cell.y, source_cell.x)
		180:
			return Vector2i(_columns - 1 - source_cell.x, _rows - 1 - source_cell.y)
		270:
			return Vector2i(source_cell.y, _columns - 1 - source_cell.x)
		_:
			return source_cell


func _rebuild_collision() -> void:
	_ensure_collision_nodes()
	var segments: PackedVector2Array = PackedVector2Array()
	var half_cell: float = _cell_size * 0.5
	for row_index: int in range(_rows):
		for column_index: int in range(_columns):
			var cell := Vector2i(column_index, row_index)
			if not _is_blocked(cell):
				continue
			var left: float = float(column_index) * _cell_size - half_cell
			var right: float = left + _cell_size
			var top: float = float(row_index) * _cell_size - half_cell
			var bottom: float = top + _cell_size
			if not _is_blocked(cell + Vector2i.UP):
				_append_segment(segments, Vector2(left, top), Vector2(right, top))
			if not _is_blocked(cell + Vector2i.RIGHT):
				_append_segment(segments, Vector2(right, top), Vector2(right, bottom))
			if not _is_blocked(cell + Vector2i.DOWN):
				_append_segment(segments, Vector2(right, bottom), Vector2(left, bottom))
			if not _is_blocked(cell + Vector2i.LEFT):
				_append_segment(segments, Vector2(left, bottom), Vector2(left, top))
	if segments.is_empty():
		_collision_shape.shape = null
		_collision_shape.disabled = true
		return
	var concave_shape := ConcavePolygonShape2D.new()
	concave_shape.set_segments(segments)
	_collision_shape.shape = concave_shape
	_collision_shape.disabled = false


func _ensure_collision_nodes() -> void:
	if _collision_body == null or not is_instance_valid(_collision_body):
		_collision_body = StaticBody2D.new()
		_collision_body.name = "TerrainCollision"
		_collision_body.collision_layer = TERRAIN_COLLISION_LAYER
		_collision_body.collision_mask = 0
		add_child(_collision_body)
	if _collision_shape == null or not is_instance_valid(_collision_shape):
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "MergedBlockedCells"
		_collision_body.add_child(_collision_shape)


func _append_segment(segments: PackedVector2Array, from: Vector2, to: Vector2) -> void:
	segments.append(from)
	segments.append(to)


func _is_blocked(local_cell: Vector2i) -> bool:
	if not _is_local_cell_valid(local_cell):
		return false
	return terrain_at_local_cell(local_cell) == MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED


func _is_local_cell_valid(local_cell: Vector2i) -> bool:
	if not _is_cell_inside(local_cell, _columns, _rows):
		return false
	if local_cell.y >= _terrain_rows.size() or not _terrain_rows[local_cell.y] is Array:
		return false
	return local_cell.x < (_terrain_rows[local_cell.y] as Array).size()


func _blocked_cell_count() -> int:
	var count: int = 0
	for row_index: int in range(_rows):
		for column_index: int in range(_columns):
			if _is_blocked(Vector2i(column_index, row_index)):
				count += 1
	return count


func _normalize_rotation(rotation_degrees: int) -> int:
	var normalized: int = posmod(rotation_degrees, 360)
	if normalized % 90 != 0:
		return 0
	return normalized


func _cell_from_variant(raw_value: Variant) -> Vector2i:
	if not raw_value is Dictionary:
		return Vector2i(-1, -1)
	var value: Dictionary = raw_value as Dictionary
	return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))


func _coord_to_dict(coord: Vector2i) -> Dictionary:
	return {
		"x": coord.x,
		"y": coord.y,
	}


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _is_cell_inside(cell: Vector2i, columns: int, rows: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < columns and cell.y < rows
