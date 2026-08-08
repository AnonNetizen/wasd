# Doc: docs/代码/gear_mod_system.md
# Authority: docs/游戏设计文档.md §7.2 / §9.16
class_name GearModGridView
extends Control


signal cell_selected(coord: Vector2i)

const GEAR_MOD_KINDS := preload("res://scripts/contracts/gear_mod_kinds.gd")
const BOARD_SIZE: int = 7
const INVALID_COORD := Vector2i(-1, -1)
const CELL_GAP: float = 6.0
const GRID_PADDING: float = 12.0

@export var map_view: bool = false

var _snapshot: Dictionary = {}
var _selected: Vector2i = Vector2i(3, 3)
var _legal_targets: Dictionary = {}
var _unlocked: Dictionary = {}
var _placements: Dictionary = {}
var _visited: Dictionary = {}
var _current: Vector2i = INVALID_COORD
var _objective: Vector2i = INVALID_COORD
var _center: Vector2i = Vector2i(3, 3)


func _ready() -> void:
	custom_minimum_size = Vector2(420.0, 420.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func configure_board(
		snapshot: Dictionary,
		selected: Vector2i,
		legal_targets: Array[Vector2i] = []
	) -> void:
	map_view = false
	_snapshot = snapshot.duplicate(true)
	_selected = _clamp_coord(selected)
	_center = _coord_from_variant(_snapshot.get("center", Vector2i(3, 3)))
	if not _coord_is_valid(_center):
		_center = Vector2i(3, 3)
	_unlocked.clear()
	_placements.clear()
	_legal_targets.clear()
	for raw_coord: Variant in _snapshot.get("unlocked_cells", []):
		var coord: Vector2i = _coord_from_variant(raw_coord)
		if _coord_is_valid(coord):
			_unlocked[_coord_key(coord)] = true
	for raw_placement: Variant in _snapshot.get("placements", []):
		if raw_placement is not Dictionary:
			continue
		var placement: Dictionary = raw_placement as Dictionary
		var coord: Vector2i = _coord_from_variant(placement)
		if _coord_is_valid(coord):
			_placements[_coord_key(coord)] = placement.duplicate(true)
	for coord: Vector2i in legal_targets:
		if _coord_is_valid(coord):
			_legal_targets[_coord_key(coord)] = true
	queue_redraw()


func configure_map(snapshot: Dictionary, selected: Vector2i) -> void:
	map_view = true
	_snapshot = snapshot.duplicate(true)
	_selected = _clamp_coord(selected)
	_visited.clear()
	for raw_coord: Variant in _snapshot.get(
		"visited_slots",
		_snapshot.get("visited", [])
	):
		var coord: Vector2i = _coord_from_variant(raw_coord)
		if _coord_is_valid(coord):
			_visited[_coord_key(coord)] = true
	_current = _coord_from_variant(
		_snapshot.get("current_slot", _snapshot.get("current_module", {}))
	)
	_objective = _coord_from_variant(
		_snapshot.get("objective_slot", _snapshot.get("objective_module", {}))
	)
	queue_redraw()


func set_selected(coord: Vector2i) -> void:
	_selected = _clamp_coord(coord)
	queue_redraw()


func selected_coord() -> Vector2i:
	return _selected


func _gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button.button_index != MOUSE_BUTTON_LEFT or not mouse_button.pressed:
		return
	var coord: Vector2i = _coord_at_position(mouse_button.position)
	if not _coord_is_valid(coord):
		return
	accept_event()
	cell_selected.emit(coord)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.025, 0.04, 0.065, 0.96), true)
	for y: int in range(BOARD_SIZE):
		for x: int in range(BOARD_SIZE):
			_draw_cell(Vector2i(x, y))


func _draw_cell(coord: Vector2i) -> void:
	var rect: Rect2 = _cell_rect(coord)
	var fill: Color = Color(0.055, 0.07, 0.095, 1.0)
	var border: Color = Color(0.20, 0.25, 0.31, 1.0)
	var label: String = ""
	if map_view:
		if _visited.has(_coord_key(coord)):
			fill = Color(0.20, 0.27, 0.34, 1.0)
		if coord == _current:
			fill = Color(0.12, 0.55, 0.45, 1.0)
			label = tr("ui_gear_mod_board_player_marker")
		if coord == _objective:
			border = Color(1.0, 0.71, 0.20, 1.0)
	else:
		var key: String = _coord_key(coord)
		if _unlocked.has(key):
			fill = Color(0.10, 0.14, 0.19, 1.0)
		else:
			label = "×"
		if _legal_targets.has(key):
			fill = Color(0.14, 0.38, 0.29, 1.0)
			border = Color(0.34, 0.93, 0.65, 1.0)
		if coord == _center:
			fill = Color(0.37, 0.24, 0.08, 1.0)
			border = Color(1.0, 0.70, 0.16, 1.0)
			label = tr("ui_gear_mod_board_core_short")
		var placement: Dictionary = _placements.get(key, {}) as Dictionary
		if not placement.is_empty():
			fill = Color(0.17, 0.29, 0.48, 1.0)
			label = _placement_label(placement)
	draw_rect(rect, fill, true)
	draw_rect(rect, border, false, 2.0)
	if coord == _selected:
		draw_rect(rect.grow(-2.0), Color(0.44, 0.91, 1.0, 1.0), false, 4.0)
	if not label.is_empty():
		var font: Font = ThemeDB.fallback_font
		var font_size: int = 15
		var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		var position := Vector2(
			rect.get_center().x - text_width * 0.5,
			rect.get_center().y + font_size * 0.36
		)
		draw_string(font, position, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color.WHITE)


func _placement_label(placement: Dictionary) -> String:
	var mod_id: String = String(placement.get("mod_id", ""))
	var definition: Dictionary = GearModSystem.mod_definition(mod_id)
	var kind: String = String(definition.get("kind", ""))
	match kind:
		GEAR_MOD_KINDS.EFFECT:
			return "E"
		GEAR_MOD_KINDS.MAP:
			return "M"
		GEAR_MOD_KINDS.GRID:
			return "G"
	return "?"


func _cell_rect(coord: Vector2i) -> Rect2:
	var side: float = minf(size.x, size.y) - GRID_PADDING * 2.0
	var cell_size: float = (side - CELL_GAP * float(BOARD_SIZE - 1)) / float(BOARD_SIZE)
	var grid_size: float = cell_size * BOARD_SIZE + CELL_GAP * float(BOARD_SIZE - 1)
	var origin := Vector2((size.x - grid_size) * 0.5, (size.y - grid_size) * 0.5)
	return Rect2(
		origin + Vector2(coord.x, coord.y) * (cell_size + CELL_GAP),
		Vector2(cell_size, cell_size)
	)


func _coord_at_position(position: Vector2) -> Vector2i:
	for y: int in range(BOARD_SIZE):
		for x: int in range(BOARD_SIZE):
			var coord := Vector2i(x, y)
			if _cell_rect(coord).has_point(position):
				return coord
	return INVALID_COORD


func _coord_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		var vector: Vector2 = value as Vector2
		return Vector2i(int(vector.x), int(vector.y))
	if value is Dictionary:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -1)), int(data.get("y", -1)))
	if value is Array:
		var parts: Array = value as Array
		if parts.size() == 2:
			return Vector2i(int(parts[0]), int(parts[1]))
	return INVALID_COORD


func _coord_is_valid(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.x < BOARD_SIZE and coord.y >= 0 and coord.y < BOARD_SIZE


func _clamp_coord(coord: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(coord.x, 0, BOARD_SIZE - 1),
		clampi(coord.y, 0, BOARD_SIZE - 1)
	)


func _coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]
