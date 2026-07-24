# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F13-ModularGridWorld.md
class_name ModuleMinimap
extends Control


const GRID_SIZE: int = 9

@export_group("Layout")
@export_range(4.0, 32.0, 1.0) var cell_size: float = 13.0
@export_range(0.0, 12.0, 0.5) var cell_gap: float = 2.0
@export_range(0.0, 32.0, 1.0) var padding: float = 10.0
@export_group("Visual Style")
@export var panel_color: Color = Color(0.025, 0.035, 0.05, 0.82)
@export var border_color: Color = Color(0.68, 0.74, 0.82, 0.62)
@export var unknown_color: Color = Color(0.08, 0.10, 0.13, 0.88)
@export var revealed_color: Color = Color(0.30, 0.36, 0.42, 0.94)
@export var current_color: Color = Color(0.35, 0.86, 0.72, 1.0)
@export var objective_color: Color = Color(1.0, 0.72, 0.20, 1.0)
@export var extraction_color: Color = Color(0.35, 0.92, 0.70, 1.0)
@export_range(0.5, 6.0, 0.1) var border_width: float = 1.0
@export_range(1.0, 8.0, 0.1) var objective_marker_radius: float = 3.0
@export_range(1.0, 8.0, 0.1) var extraction_marker_radius: float = 3.2

var _visited: Dictionary = {}
var _current: Vector2i = Vector2i(-1, -1)
var _objective: Vector2i = Vector2i(-1, -1)
var _extraction: Vector2i = Vector2i(-1, -1)
var _extraction_active: bool = false

@onready var _selection_feedback: UISelectionFeedback = get_node_or_null(
	"SelectionFeedback"
) as UISelectionFeedback


func _ready() -> void:
	custom_minimum_size = Vector2(
		padding * 2.0 + GRID_SIZE * cell_size + (GRID_SIZE - 1) * cell_gap,
		padding * 2.0 + GRID_SIZE * cell_size + (GRID_SIZE - 1) * cell_gap
	)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure(state: Dictionary) -> void:
	var previous_current: Vector2i = _current
	_visited.clear()
	for raw_slot: Variant in state.get("visited_slots", []):
		var slot: Vector2i = _slot_from_variant(raw_slot)
		if _is_valid_slot(slot):
			_visited[_slot_key(slot)] = true
	_current = _slot_from_variant(state.get("current_slot", {}))
	_objective = _slot_from_variant(state.get("objective_slot", {}))
	_extraction = _slot_from_variant(state.get("extraction_slot", {}))
	_extraction_active = bool(state.get("extraction_active", false))
	queue_redraw()
	if (
		_selection_feedback != null
		and _is_valid_slot(previous_current)
		and _current != previous_current
	):
		_selection_feedback.play_selection(self)


func _draw() -> void:
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, panel_color, true)
	draw_rect(panel_rect, border_color, false, border_width)
	for y: int in range(GRID_SIZE):
		for x: int in range(GRID_SIZE):
			var slot := Vector2i(x, y)
			var cell_rect := Rect2(
				Vector2(padding + x * (cell_size + cell_gap), padding + y * (cell_size + cell_gap)),
				Vector2(cell_size, cell_size)
			)
			var color: Color = revealed_color if _visited.has(_slot_key(slot)) else unknown_color
			if slot == _current:
				color = current_color
			draw_rect(cell_rect, color, true)
			if slot == _objective and not _extraction_active:
				draw_circle(cell_rect.get_center(), objective_marker_radius, objective_color)
			if _extraction_active and slot == _extraction:
				draw_circle(cell_rect.get_center(), extraction_marker_radius, extraction_color)


func _slot_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		var vector: Vector2 = value as Vector2
		return Vector2i(int(vector.x), int(vector.y))
	if value is Dictionary:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -1)), int(data.get("y", -1)))
	if value is String:
		var parts: PackedStringArray = String(value).split(",")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			return Vector2i(parts[0].to_int(), parts[1].to_int())
	return Vector2i(-1, -1)


func _is_valid_slot(slot: Vector2i) -> bool:
	return slot.x >= 0 and slot.x < GRID_SIZE and slot.y >= 0 and slot.y < GRID_SIZE


func _slot_key(slot: Vector2i) -> String:
	return "%d,%d" % [slot.x, slot.y]
