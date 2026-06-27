# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F12-ShortLootRuns.md
class_name InterestPointCache
extends Node2D


const ACTIVE_GROUP: String = "active_interest_point_caches"
const ACCENT_SCALE: float = 0.18
const BODY_BOTTOM_COLOR: Color = Color(0.34, 0.30, 0.23)
const BODY_LEFT_COLOR: Color = Color(0.42, 0.36, 0.27)
const BODY_RIGHT_COLOR: Color = Color(0.24, 0.22, 0.20)
const BODY_SCALE: Vector2 = Vector2(0.56, 0.34)
const BODY_TOP_COLOR: Color = Color(0.68, 0.58, 0.42)
const CRATE_HEIGHT_SCALE: float = 0.28
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 80.0)
const FOOTPRINT_FILL_COLOR: Color = Color(0.10, 0.09, 0.075, 0.18)
const FOOTPRINT_RING_COLOR: Color = Color(0.34, 0.29, 0.20, 0.44)
const LID_LIFT_SCALE: float = 0.18
const OUTLINE_COLOR: Color = Color(0.06, 0.045, 0.04, 0.9)
const OUTLINE_WIDTH: float = 3.0
const SHADOW_COLOR: Color = Color(0.02, 0.018, 0.015, 0.34)
const KIND_COLORS: Dictionary = {
	"mod_cache": Color(0.26, 0.56, 0.92),
	"resource_cache": Color(0.92, 0.66, 0.24),
}

var _grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE
var _kind: String = ""
var _opened: bool = false
var _point_id: String = ""


func configure(point_id: String, kind: String, grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE, opened: bool = false) -> void:
	_point_id = point_id
	_kind = kind
	_grid_cell_size = Vector2(maxf(grid_cell_size.x, 1.0), maxf(grid_cell_size.y, 1.0))
	_opened = opened
	add_to_group(ACTIVE_GROUP)
	queue_redraw()


func point_id() -> String:
	return _point_id


func mark_opened() -> void:
	_opened = true
	queue_redraw()


func spacing_radius() -> float:
	var half_extents: Vector2 = _footprint_half_extents()
	return maxf(half_extents.x, half_extents.y)


func _draw() -> void:
	var half_extents: Vector2 = _footprint_half_extents()
	var footprint: PackedVector2Array = _diamond_points(half_extents)
	var shadow_points: PackedVector2Array = _diamond_points(Vector2(half_extents.x * 0.62, half_extents.y * 0.36))
	draw_colored_polygon(shadow_points, SHADOW_COLOR)
	draw_colored_polygon(footprint, FOOTPRINT_FILL_COLOR)
	_draw_outline(footprint, FOOTPRINT_RING_COLOR, 2.0)
	if _opened:
		_draw_opened_cache(half_extents)
	else:
		_draw_closed_cache(half_extents)


func _footprint_half_extents() -> Vector2:
	return _grid_cell_size * 0.5


func _diamond_points(half_extents: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -half_extents.y),
		Vector2(half_extents.x, 0.0),
		Vector2(0.0, half_extents.y),
		Vector2(-half_extents.x, 0.0),
	])


func _draw_closed_cache(half_extents: Vector2) -> void:
	var body_extents: Vector2 = Vector2(half_extents.x * BODY_SCALE.x, half_extents.y * BODY_SCALE.y)
	var height: float = half_extents.y * CRATE_HEIGHT_SCALE
	var top_center: Vector2 = Vector2(0.0, -height)
	_draw_box_faces(top_center, body_extents, height, false)
	_draw_cache_accent(top_center, body_extents)


func _draw_opened_cache(half_extents: Vector2) -> void:
	var body_extents: Vector2 = Vector2(half_extents.x * BODY_SCALE.x, half_extents.y * BODY_SCALE.y)
	var height: float = half_extents.y * CRATE_HEIGHT_SCALE
	var top_center: Vector2 = Vector2(0.0, -height)
	_draw_box_faces(top_center, body_extents, height, true)
	var lid_offset: Vector2 = Vector2(0.0, -half_extents.y * LID_LIFT_SCALE)
	var lid_points: PackedVector2Array = _diamond_points_from_center(top_center + lid_offset, body_extents * Vector2(0.96, 0.72))
	draw_colored_polygon(lid_points, BODY_TOP_COLOR.darkened(0.18))
	_draw_outline(lid_points, OUTLINE_COLOR, 2.0)


func _draw_box_faces(top_center: Vector2, body_extents: Vector2, height: float, opened: bool) -> void:
	var top: PackedVector2Array = _diamond_points_from_center(top_center, body_extents)
	var bottom_center: Vector2 = top_center + Vector2(0.0, height)
	var bottom: PackedVector2Array = _diamond_points_from_center(bottom_center, body_extents)
	var left_face: PackedVector2Array = PackedVector2Array([top[3], top[2], bottom[2], bottom[3]])
	var right_face: PackedVector2Array = PackedVector2Array([top[1], top[2], bottom[2], bottom[1]])
	var front_face: PackedVector2Array = PackedVector2Array([top[2], bottom[2], bottom[3], top[3]])
	draw_colored_polygon(left_face, BODY_LEFT_COLOR)
	draw_colored_polygon(right_face, BODY_RIGHT_COLOR)
	draw_colored_polygon(front_face, BODY_BOTTOM_COLOR)
	if not opened:
		draw_colored_polygon(top, BODY_TOP_COLOR)
		_draw_outline(top, OUTLINE_COLOR, OUTLINE_WIDTH)
	_draw_outline(left_face, OUTLINE_COLOR, 2.0)
	_draw_outline(right_face, OUTLINE_COLOR, 2.0)
	_draw_outline(front_face, OUTLINE_COLOR, 2.0)


func _draw_cache_accent(top_center: Vector2, body_extents: Vector2) -> void:
	var accent_color: Color = KIND_COLORS.get(_kind, Color(0.76, 0.58, 0.32)) as Color
	var accent_points: PackedVector2Array = _diamond_points_from_center(
		top_center + Vector2(0.0, body_extents.y * 0.18),
		Vector2(body_extents.x * ACCENT_SCALE, body_extents.y * ACCENT_SCALE)
	)
	draw_colored_polygon(accent_points, accent_color)
	_draw_outline(accent_points, OUTLINE_COLOR, 1.5)


func _diamond_points_from_center(center: Vector2, half_extents: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = _diamond_points(half_extents)
	for index: int in range(points.size()):
		points[index] += center
	return points


func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index: int in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width)
