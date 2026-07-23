# Doc: docs/代码/module_authoring_pipeline.md
@tool
class_name ModuleJsonCanvas
extends Control
## Lightweight 11 x 11 editor canvas backed only by module JSON data.

signal cell_primary_requested(cell: Vector2i)
signal cell_secondary_requested(cell: Vector2i)
signal selected_cell_changed(cell: Vector2i)

const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")

const MODULE_SIZE: int = 11
const GRID_COLOR := Color(0.30, 0.34, 0.39, 1.0)
const FLOOR_COLOR := Color(0.18, 0.24, 0.28, 1.0)
const BLOCKED_COLOR := Color(0.09, 0.11, 0.14, 1.0)
const GROUND_OVERLAY_COLOR := Color(0.18, 0.55, 0.72, 0.28)
const OBSTACLE_OVERLAY_COLOR := Color(0.85, 0.32, 0.23, 0.42)
const DECORATION_COLOR := Color(0.90, 0.72, 0.24, 0.9)
const PLACEMENT_COLOR := Color(0.38, 0.90, 0.56, 1.0)
const FOOTPRINT_COLOR := Color(0.25, 0.82, 0.48, 0.26)
const SOCKET_COLOR := Color(0.28, 0.84, 1.0, 1.0)
const ERROR_COLOR := Color(1.0, 0.18, 0.25, 0.8)
const SELECTION_COLOR := Color(1.0, 0.94, 0.54, 1.0)

var active_layer: String = "ground"
var preview_rotation: int = 0
var selected_cell := Vector2i(-1, -1)
var error_cells: Dictionary = {}

var _module_data: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(440.0, 440.0)
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func set_module_data(value: Dictionary) -> void:
	_module_data = value.duplicate(true)
	if selected_cell.x >= MODULE_SIZE or selected_cell.y >= MODULE_SIZE:
		selected_cell = Vector2i(-1, -1)
	queue_redraw()


func set_active_layer(value: String) -> void:
	active_layer = value
	queue_redraw()


func set_preview_rotation(value: int) -> void:
	preview_rotation = posmod(value, 360)
	queue_redraw()


func set_error_cells(value: Dictionary) -> void:
	error_cells = value.duplicate()
	queue_redraw()


func _draw() -> void:
	var canvas_rect: Rect2 = _canvas_rect()
	var cell_size: float = canvas_rect.size.x / float(MODULE_SIZE)
	draw_rect(canvas_rect, BLOCKED_COLOR)
	for source_y: int in range(MODULE_SIZE):
		for source_x: int in range(MODULE_SIZE):
			var source_cell := Vector2i(source_x, source_y)
			var view_cell: Vector2i = _rotate_cell(source_cell, preview_rotation)
			var rect := Rect2(
				canvas_rect.position + Vector2(view_cell) * cell_size,
				Vector2.ONE * cell_size
			)
			draw_rect(rect, _terrain_color(source_cell))
			_draw_layer_overlay(source_cell, rect, cell_size)
			if error_cells.has(source_cell):
				draw_rect(rect.grow(-2.0), ERROR_COLOR, false, 3.0)

	_draw_grid(canvas_rect, cell_size)
	_draw_sockets(canvas_rect, cell_size)
	if _is_cell_inside(selected_cell):
		var selected_view: Vector2i = _rotate_cell(selected_cell, preview_rotation)
		var selected_rect := Rect2(
			canvas_rect.position + Vector2(selected_view) * cell_size,
			Vector2.ONE * cell_size
		)
		draw_rect(selected_rect.grow(-2.0), SELECTION_COLOR, false, 3.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var hovered_cell: Vector2i = _cell_from_position(motion.position)
		tooltip_text = "Cell (%d, %d)" % [hovered_cell.x, hovered_cell.y] if _is_cell_inside(hovered_cell) else ""
		return
	if not event is InputEventMouseButton:
		return
	var button_event: InputEventMouseButton = event as InputEventMouseButton
	if not button_event.pressed:
		return
	var cell: Vector2i = _cell_from_position(button_event.position)
	if not _is_cell_inside(cell):
		return
	selected_cell = cell
	selected_cell_changed.emit(cell)
	queue_redraw()
	if button_event.button_index == MOUSE_BUTTON_LEFT:
		cell_primary_requested.emit(cell)
		accept_event()
	elif button_event.button_index == MOUSE_BUTTON_RIGHT:
		cell_secondary_requested.emit(cell)
		accept_event()


func _draw_layer_overlay(source_cell: Vector2i, rect: Rect2, cell_size: float) -> void:
	if _should_draw_footprint(source_cell):
		draw_rect(rect.grow(-2.0), FOOTPRINT_COLOR)
	if active_layer == "ground" and not _visual_at("ground", source_cell).is_empty():
		draw_rect(rect.grow(-3.0), GROUND_OVERLAY_COLOR)
	elif active_layer == "obstacles" and not _visual_at("obstacles", source_cell).is_empty():
		draw_rect(rect.grow(-3.0), OBSTACLE_OVERLAY_COLOR)

	var decoration: Dictionary = _visual_at("decoration", source_cell)
	if not decoration.is_empty():
		var center: Vector2 = rect.get_center()
		var radius: float = cell_size * 0.16
		draw_colored_polygon(
			PackedVector2Array([
				center + Vector2(0.0, -radius),
				center + Vector2(radius, 0.0),
				center + Vector2(0.0, radius),
				center + Vector2(-radius, 0.0),
			]),
			DECORATION_COLOR
		)
	var placement: Dictionary = _placement_at(source_cell)
	if not placement.is_empty():
		draw_circle(rect.get_center(), cell_size * 0.13, PLACEMENT_COLOR)
		draw_arc(
			rect.get_center(),
			cell_size * 0.18,
			0.0,
			TAU,
			20,
			Color(0.05, 0.12, 0.08, 1.0),
			2.0
		)


func _should_draw_footprint(source_cell: Vector2i) -> bool:
	for value: Variant in _module_data.get("placements", []) as Array:
		if not value is Dictionary:
			continue
		var placement: Dictionary = value as Dictionary
		var anchor: Vector2i = _entry_cell(placement)
		if active_layer != "placements" and anchor != selected_cell:
			continue
		var footprint_value: Variant = placement.get("footprint", {})
		var width: int = 1
		var height: int = 1
		if footprint_value is Dictionary:
			var footprint: Dictionary = footprint_value as Dictionary
			width = maxi(1, int(footprint.get("width", 1)))
			height = maxi(1, int(footprint.get("height", 1)))
		if (
			source_cell.x >= anchor.x
			and source_cell.x < anchor.x + width
			and source_cell.y >= anchor.y
			and source_cell.y < anchor.y + height
		):
			return true
	return false


func _draw_grid(canvas_rect: Rect2, cell_size: float) -> void:
	for index: int in range(MODULE_SIZE + 1):
		var offset: float = float(index) * cell_size
		draw_line(
			canvas_rect.position + Vector2(offset, 0.0),
			canvas_rect.position + Vector2(offset, canvas_rect.size.y),
			GRID_COLOR
		)
		draw_line(
			canvas_rect.position + Vector2(0.0, offset),
			canvas_rect.position + Vector2(canvas_rect.size.x, offset),
			GRID_COLOR
		)


func _draw_sockets(canvas_rect: Rect2, cell_size: float) -> void:
	var sockets: Dictionary = _derive_sockets()
	for direction: String in ["edge_north", "edge_east", "edge_south", "edge_west"]:
		for index_value: Variant in sockets.get(direction, []) as Array:
			var source_cell: Vector2i
			match direction:
				"edge_north":
					source_cell = Vector2i(int(index_value), 0)
				"edge_east":
					source_cell = Vector2i(MODULE_SIZE - 1, int(index_value))
				"edge_south":
					source_cell = Vector2i(int(index_value), MODULE_SIZE - 1)
				"edge_west":
					source_cell = Vector2i(0, int(index_value))
				_:
					continue
			var view_cell: Vector2i = _rotate_cell(source_cell, preview_rotation)
			var center: Vector2 = (
				canvas_rect.position
				+ (Vector2(view_cell) + Vector2(0.5, 0.5)) * cell_size
			)
			draw_circle(center, maxf(2.5, cell_size * 0.07), SOCKET_COLOR)


func _canvas_rect() -> Rect2:
	var side: float = minf(size.x, size.y)
	var origin := Vector2((size.x - side) * 0.5, (size.y - side) * 0.5)
	return Rect2(origin, Vector2.ONE * side)


func _cell_from_position(position: Vector2) -> Vector2i:
	var canvas_rect: Rect2 = _canvas_rect()
	if not canvas_rect.has_point(position):
		return Vector2i(-1, -1)
	var cell_size: float = canvas_rect.size.x / float(MODULE_SIZE)
	var view_cell := Vector2i(
		floori((position.x - canvas_rect.position.x) / cell_size),
		floori((position.y - canvas_rect.position.y) / cell_size)
	)
	return _rotate_cell(view_cell, 360 - preview_rotation)


func _terrain_color(source_cell: Vector2i) -> Color:
	var terrain_rows: Array = _module_data.get("terrain_rows", []) as Array
	if source_cell.y < 0 or source_cell.y >= terrain_rows.size():
		return BLOCKED_COLOR
	if not terrain_rows[source_cell.y] is Array:
		return BLOCKED_COLOR
	var row: Array = terrain_rows[source_cell.y] as Array
	if source_cell.x < 0 or source_cell.x >= row.size():
		return BLOCKED_COLOR
	return (
		FLOOR_COLOR
		if String(row[source_cell.x]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR
		else BLOCKED_COLOR
	)


func _visual_at(layer_name: String, source_cell: Vector2i) -> Dictionary:
	var layers: Dictionary = _module_data.get("visual_layers", {}) as Dictionary
	var layer_data: Dictionary = layers.get(layer_name, {}) as Dictionary
	var list_key: String = "cells" if layer_name == "decoration" else "overrides"
	for value: Variant in layer_data.get(list_key, []) as Array:
		if value is Dictionary and _entry_cell(value as Dictionary) == source_cell:
			return value as Dictionary
	return {}


func _placement_at(source_cell: Vector2i) -> Dictionary:
	for value: Variant in _module_data.get("placements", []) as Array:
		if value is Dictionary and _entry_cell(value as Dictionary) == source_cell:
			return value as Dictionary
	return {}


func _derive_sockets() -> Dictionary:
	var north: Array[int] = []
	var south: Array[int] = []
	var east: Array[int] = []
	var west: Array[int] = []
	var terrain_rows: Array = _module_data.get("terrain_rows", []) as Array
	if terrain_rows.size() != MODULE_SIZE:
		return {}
	for index: int in range(MODULE_SIZE):
		if _terrain_token(Vector2i(index, 0)) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			north.append(index)
		if _terrain_token(Vector2i(MODULE_SIZE - 1, index)) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			east.append(index)
		if _terrain_token(Vector2i(index, MODULE_SIZE - 1)) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			south.append(index)
		if _terrain_token(Vector2i(0, index)) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			west.append(index)
	return {
		"edge_north": north,
		"edge_east": east,
		"edge_south": south,
		"edge_west": west,
	}


func _terrain_token(source_cell: Vector2i) -> String:
	var rows: Array = _module_data.get("terrain_rows", []) as Array
	if source_cell.y < 0 or source_cell.y >= rows.size() or not rows[source_cell.y] is Array:
		return ""
	var row: Array = rows[source_cell.y] as Array
	if source_cell.x < 0 or source_cell.x >= row.size():
		return ""
	return String(row[source_cell.x])


func _entry_cell(entry: Dictionary) -> Vector2i:
	var value: Variant = entry.get("cell", {})
	if not value is Dictionary:
		return Vector2i(-1, -1)
	var cell: Dictionary = value as Dictionary
	return Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))


func _rotate_cell(source_cell: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 360):
		90:
			return Vector2i(MODULE_SIZE - 1 - source_cell.y, source_cell.x)
		180:
			return Vector2i(
				MODULE_SIZE - 1 - source_cell.x,
				MODULE_SIZE - 1 - source_cell.y
			)
		270:
			return Vector2i(source_cell.y, MODULE_SIZE - 1 - source_cell.x)
		_:
			return source_cell


func _is_cell_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MODULE_SIZE and cell.y < MODULE_SIZE
