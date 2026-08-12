# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F13-ModularGridWorld.md
class_name ModuleMinimap
extends Control


const DEFAULT_COLUMNS: int = 7
const DEFAULT_ROWS: int = 7
const MODULE_PLACEMENT_TYPES := preload(
	"res://scripts/contracts/module_placement_types.gd"
)
const WORLD_EVENT_KINDS := preload(
	"res://scripts/contracts/world_event_kinds.gd"
)

enum MarkerKind {
	NONE,
	REWARD_CACHE,
	SHRINE,
	BEACON,
	TELEPORTER,
}

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
@export var reward_cache_marker_color: Color = Color(0.72, 0.90, 0.40, 1.0)
@export var shrine_marker_color: Color = Color(0.91, 0.53, 1.0, 1.0)
@export var beacon_marker_color: Color = Color(1.0, 0.66, 0.32, 1.0)
@export var teleporter_marker_color: Color = Color(0.36, 0.88, 1.0, 1.0)
@export var marker_outline_color: Color = Color(0.02, 0.03, 0.05, 0.96)
@export_range(0.5, 6.0, 0.1) var border_width: float = 1.0
@export_range(1.0, 8.0, 0.1) var objective_marker_radius: float = 3.0
@export_range(1.0, 6.0, 0.1) var interactable_marker_radius: float = 3.5
@export_range(0.5, 3.0, 0.1) var interactable_marker_outline_width: float = 1.0

var _visited: Dictionary = {}
var _interactable_markers: Dictionary = {}
var _current: Vector2i = Vector2i(-1, -1)
var _objective: Vector2i = Vector2i(-1, -1)
var _columns: int = DEFAULT_COLUMNS
var _rows: int = DEFAULT_ROWS

@onready var _selection_feedback: UISelectionFeedback = get_node_or_null(
	"SelectionFeedback"
) as UISelectionFeedback


func _ready() -> void:
	_refresh_minimum_size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure(state: Dictionary) -> void:
	var previous_current: Vector2i = _current
	var previous_dimensions := Vector2i(_columns, _rows)
	_columns = maxi(int(state.get("columns", DEFAULT_COLUMNS)), 1)
	_rows = maxi(int(state.get("rows", DEFAULT_ROWS)), 1)
	if Vector2i(_columns, _rows) != previous_dimensions:
		_refresh_minimum_size()
	_visited.clear()
	for raw_slot: Variant in state.get("visited_slots", []):
		var slot: Vector2i = _slot_from_variant(raw_slot)
		if _is_valid_slot(slot):
			_visited[_slot_key(slot)] = true
	_configure_interactable_markers(state.get("interactable_markers", []))
	_current = _slot_from_variant(state.get("current_slot", {}))
	_objective = _slot_from_variant(state.get("objective_slot", {}))
	queue_redraw()
	if (
		_selection_feedback != null
		and _is_valid_slot(previous_current)
		and _current != previous_current
	):
		_selection_feedback.play_selection(self)


func _refresh_minimum_size() -> void:
	custom_minimum_size = Vector2(
		padding * 2.0 + _columns * cell_size + (_columns - 1) * cell_gap,
		padding * 2.0 + _rows * cell_size + (_rows - 1) * cell_gap
	)


func _draw() -> void:
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, panel_color, true)
	draw_rect(panel_rect, border_color, false, border_width)
	for y: int in range(_rows):
		for x: int in range(_columns):
			var slot := Vector2i(x, y)
			var cell_rect := Rect2(
				Vector2(padding + x * (cell_size + cell_gap), padding + y * (cell_size + cell_gap)),
				Vector2(cell_size, cell_size)
			)
			var color: Color = revealed_color if _visited.has(_slot_key(slot)) else unknown_color
			if slot == _current:
				color = current_color
			draw_rect(cell_rect, color, true)
			if slot == _objective:
				draw_circle(cell_rect.get_center(), objective_marker_radius, objective_color)
			_draw_interactable_markers(cell_rect, slot)


func marker_kinds_at(slot: Vector2i) -> Array[int]:
	var result: Array[int] = []
	for raw_marker: Variant in _interactable_markers.get(_slot_key(slot), []):
		if raw_marker is not Dictionary:
			continue
		var marker_kind: MarkerKind = _marker_kind(raw_marker as Dictionary)
		if marker_kind != MarkerKind.NONE:
			result.append(marker_kind)
	return result


func interactable_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for y: int in range(_rows):
		for x: int in range(_columns):
			for raw_marker: Variant in _interactable_markers.get("%d,%d" % [x, y], []):
				if raw_marker is Dictionary:
					result.append((raw_marker as Dictionary).duplicate(true))
	return result


func _configure_interactable_markers(raw_markers: Variant) -> void:
	_interactable_markers.clear()
	if raw_markers is not Array:
		return
	for raw_marker: Variant in raw_markers as Array:
		if raw_marker is not Dictionary:
			continue
		var marker: Dictionary = (raw_marker as Dictionary).duplicate(true)
		var slot: Vector2i = _slot_from_variant(marker.get("slot", {}))
		var slot_key: String = _slot_key(slot)
		if not _is_valid_slot(slot):
			continue
		if _marker_kind(marker) == MarkerKind.NONE:
			continue
		marker["slot"] = {"x": slot.x, "y": slot.y}
		var markers_at_slot: Array = _interactable_markers.get(slot_key, []) as Array
		markers_at_slot.append(marker)
		_interactable_markers[slot_key] = markers_at_slot


func _draw_interactable_markers(cell_rect: Rect2, slot: Vector2i) -> void:
	var markers: Array = _interactable_markers.get(_slot_key(slot), []) as Array
	if markers.is_empty():
		return
	var marker_kind: MarkerKind = _marker_kind(markers[0] as Dictionary)
	var center: Vector2 = cell_rect.get_center()
	match marker_kind:
		MarkerKind.REWARD_CACHE:
			_draw_square_marker(center, reward_cache_marker_color)
		MarkerKind.SHRINE:
			_draw_triangle_marker(center, shrine_marker_color)
		MarkerKind.BEACON:
			draw_arc(
				center,
				interactable_marker_radius,
				0.0,
				TAU,
				16,
				beacon_marker_color,
				interactable_marker_outline_width,
				true
			)
		MarkerKind.TELEPORTER:
			_draw_diamond_marker(center, teleporter_marker_color)
		_:
			pass


func _draw_square_marker(center: Vector2, color: Color) -> void:
	var outer_rect := Rect2(
		center - Vector2.ONE * interactable_marker_radius,
		Vector2.ONE * interactable_marker_radius * 2.0
	)
	draw_rect(outer_rect, marker_outline_color, true)
	var inner_rect: Rect2 = outer_rect.grow(-interactable_marker_outline_width)
	draw_rect(inner_rect, color, true)


func _draw_triangle_marker(center: Vector2, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -interactable_marker_radius),
		center + Vector2(interactable_marker_radius, interactable_marker_radius),
		center + Vector2(-interactable_marker_radius, interactable_marker_radius),
	])
	_draw_polygon_marker(points, color)


func _draw_diamond_marker(center: Vector2, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -interactable_marker_radius),
		center + Vector2(interactable_marker_radius, 0.0),
		center + Vector2(0.0, interactable_marker_radius),
		center + Vector2(-interactable_marker_radius, 0.0),
	])
	_draw_polygon_marker(points, color)


func _draw_polygon_marker(points: PackedVector2Array, color: Color) -> void:
	draw_colored_polygon(points, color)
	var outline_points: PackedVector2Array = points.duplicate()
	outline_points.append(points[0])
	draw_polyline(
		outline_points,
		marker_outline_color,
		interactable_marker_outline_width,
		true
	)


func _marker_kind(marker: Dictionary) -> MarkerKind:
	var placement_type: String = String(marker.get("type", ""))
	match placement_type:
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE:
			return MarkerKind.REWARD_CACHE
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_TELEPORTER:
			return MarkerKind.TELEPORTER
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT:
			var event_kind: String = String(marker.get("world_event_kind", ""))
			if event_kind in [
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_GOLD_SHRINE,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_BLOOD_SHRINE,
			]:
				return MarkerKind.SHRINE
			if event_kind in [
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_SURVIVAL,
				WORLD_EVENT_KINDS.WORLD_EVENT_KIND_CAPTURE,
			]:
				return MarkerKind.BEACON
			return MarkerKind.NONE
		_:
			return MarkerKind.NONE


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
	return slot.x >= 0 and slot.x < _columns and slot.y >= 0 and slot.y < _rows


func _slot_key(slot: Vector2i) -> String:
	return "%d,%d" % [slot.x, slot.y]
