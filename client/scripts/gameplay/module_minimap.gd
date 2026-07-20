# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F13-ModularGridWorld.md
class_name ModuleMinimap
extends Control


const GRID_SIZE: int = 9
const CELL_SIZE: float = 13.0
const CELL_GAP: float = 2.0
const PADDING: float = 10.0
const UNKNOWN_COLOR: Color = Color(0.08, 0.10, 0.13, 0.88)
const REVEALED_COLOR: Color = Color(0.30, 0.36, 0.42, 0.94)
const CURRENT_COLOR: Color = Color(0.35, 0.86, 0.72, 1.0)
const OBJECTIVE_COLOR: Color = Color(1.0, 0.72, 0.20, 1.0)
const EXTRACTION_COLOR: Color = Color(0.35, 0.92, 0.70, 1.0)
const BORDER_COLOR: Color = Color(0.68, 0.74, 0.82, 0.62)

var _visited: Dictionary = {}
var _current: Vector2i = Vector2i(-1, -1)
var _objective: Vector2i = Vector2i(-1, -1)
var _extraction: Vector2i = Vector2i(-1, -1)
var _extraction_active: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(
		PADDING * 2.0 + GRID_SIZE * CELL_SIZE + (GRID_SIZE - 1) * CELL_GAP,
		PADDING * 2.0 + GRID_SIZE * CELL_SIZE + (GRID_SIZE - 1) * CELL_GAP
	)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure(state: Dictionary) -> void:
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


func _draw() -> void:
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, Color(0.025, 0.035, 0.05, 0.82), true)
	draw_rect(panel_rect, BORDER_COLOR, false, 1.0)
	for y: int in range(GRID_SIZE):
		for x: int in range(GRID_SIZE):
			var slot := Vector2i(x, y)
			var cell_rect := Rect2(
				Vector2(PADDING + x * (CELL_SIZE + CELL_GAP), PADDING + y * (CELL_SIZE + CELL_GAP)),
				Vector2(CELL_SIZE, CELL_SIZE)
			)
			var color: Color = REVEALED_COLOR if _visited.has(_slot_key(slot)) else UNKNOWN_COLOR
			if slot == _current:
				color = CURRENT_COLOR
			draw_rect(cell_rect, color, true)
			if slot == _objective and not _extraction_active:
				draw_circle(cell_rect.get_center(), 3.0, OBJECTIVE_COLOR)
			if _extraction_active and slot == _extraction:
				draw_circle(cell_rect.get_center(), 3.2, EXTRACTION_COLOR)


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
