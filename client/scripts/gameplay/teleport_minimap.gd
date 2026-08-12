# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5, docs/决策记录.md ADR #199
class_name TeleportMinimap
extends Control


const GRID_SIZE: Vector2i = Vector2i(7, 7)
const GRID_COLOR: Color = Color(0.34, 0.46, 0.52, 0.54)
const BACKGROUND_COLOR: Color = Color(0.035, 0.07, 0.09, 0.94)
const STATION_COLOR: Color = Color(0.25, 0.82, 1.0, 1.0)
const CURRENT_COLOR: Color = Color(1.0, 0.78, 0.24, 1.0)
const SELECTED_COLOR: Color = Color(0.42, 1.0, 0.62, 1.0)
const MARKER_RADIUS_RATIO: float = 0.25

var _selected_station_id: String = ""
var _source_station_id: String = ""
var _stations: Array[Dictionary] = []


func configure(source_station_id: String, stations: Array[Dictionary]) -> void:
	_source_station_id = source_station_id
	_selected_station_id = ""
	_stations.clear()
	for station: Dictionary in stations:
		var station_id: String = String(station.get("station_id", ""))
		var module_coord: Vector2i = _module_coord(station)
		if station_id.is_empty() or not _is_valid_coord(module_coord):
			continue
		_stations.append(station.duplicate(true))
	queue_redraw()


func set_selected_station(station_id: String) -> void:
	_selected_station_id = station_id
	queue_redraw()


func station_ids() -> Array[String]:
	var ids: Array[String] = []
	for station: Dictionary in _stations:
		ids.append(String(station.get("station_id", "")))
	return ids


func module_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for station: Dictionary in _stations:
		cells.append(_module_coord(station))
	return cells


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var cell_size: Vector2 = Vector2(
		size.x / float(GRID_SIZE.x),
		size.y / float(GRID_SIZE.y)
	)
	for x: int in range(GRID_SIZE.x + 1):
		var line_x: float = cell_size.x * float(x)
		draw_line(Vector2(line_x, 0.0), Vector2(line_x, size.y), GRID_COLOR, 1.0)
	for y: int in range(GRID_SIZE.y + 1):
		var line_y: float = cell_size.y * float(y)
		draw_line(Vector2(0.0, line_y), Vector2(size.x, line_y), GRID_COLOR, 1.0)

	var marker_radius: float = minf(cell_size.x, cell_size.y) * MARKER_RADIUS_RATIO
	for station: Dictionary in _stations:
		var station_id: String = String(station.get("station_id", ""))
		var module_coord: Vector2i = _module_coord(station)
		var marker_center: Vector2 = Vector2(
			(float(module_coord.x) + 0.5) * cell_size.x,
			(float(module_coord.y) + 0.5) * cell_size.y
		)
		var marker_color: Color = STATION_COLOR
		if station_id == _source_station_id:
			marker_color = CURRENT_COLOR
		elif station_id == _selected_station_id:
			marker_color = SELECTED_COLOR
		draw_circle(marker_center, marker_radius, marker_color)
		var station_number: int = int(station.get("station_number", 0))
		if station_number > 0:
			var font_size: int = maxi(int(marker_radius * 1.15), 12)
			draw_string(
				ThemeDB.fallback_font,
				marker_center + Vector2(-marker_radius, font_size * 0.36),
				str(station_number),
				HORIZONTAL_ALIGNMENT_CENTER,
				marker_radius * 2.0,
				font_size,
				Color(0.02, 0.05, 0.07, 1.0)
			)


func _module_coord(station: Dictionary) -> Vector2i:
	var raw_coord: Variant = station.get("module_coord", {})
	if raw_coord is Vector2i:
		return raw_coord as Vector2i
	if raw_coord is Vector2:
		var vector_coord: Vector2 = raw_coord as Vector2
		return Vector2i(int(vector_coord.x), int(vector_coord.y))
	if raw_coord is Dictionary:
		var coord: Dictionary = raw_coord as Dictionary
		return Vector2i(int(coord.get("x", -1)), int(coord.get("y", -1)))
	return Vector2i(-1, -1)


func _is_valid_coord(module_coord: Vector2i) -> bool:
	return (
		module_coord.x >= 0
		and module_coord.x < GRID_SIZE.x
		and module_coord.y >= 0
		and module_coord.y < GRID_SIZE.y
	)
