# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F12-ShortLootRuns.md
class_name InterestPointCache
extends Node2D


const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 80.0)
const FOOTPRINT_FILL_COLOR: Color = Color(0.18, 0.16, 0.12, 0.22)
const OUTLINE_COLOR: Color = Color(0.06, 0.045, 0.04, 0.9)
const OPENED_COLOR: Color = Color(0.28, 0.28, 0.26, 0.68)
const KIND_COLORS: Dictionary = {
	"mod_cache": Color(0.34, 0.62, 1.0),
	"resource_cache": Color(0.92, 0.68, 0.24),
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
	queue_redraw()


func point_id() -> String:
	return _point_id


func mark_opened() -> void:
	_opened = true
	queue_redraw()


func _draw() -> void:
	var half_extents: Vector2 = _grid_cell_size * 0.5
	var footprint: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -half_extents.y),
		Vector2(half_extents.x, 0.0),
		Vector2(0.0, half_extents.y),
		Vector2(-half_extents.x, 0.0),
	])
	draw_colored_polygon(footprint, FOOTPRINT_FILL_COLOR)
	_draw_outline(footprint, OUTLINE_COLOR, 2.0)

	var chest_color: Color = OPENED_COLOR if _opened else KIND_COLORS.get(_kind, Color(0.72, 0.58, 0.32)) as Color
	var lid_offset: float = -15.0 if _opened else 0.0
	var body_rect: Rect2 = Rect2(Vector2(-36.0, -12.0), Vector2(72.0, 38.0))
	var lid_rect: Rect2 = Rect2(Vector2(-40.0, -28.0 + lid_offset), Vector2(80.0, 18.0))
	draw_rect(body_rect, chest_color)
	draw_rect(body_rect, OUTLINE_COLOR, false, 2.0)
	draw_rect(lid_rect, chest_color.lightened(0.18))
	draw_rect(lid_rect, OUTLINE_COLOR, false, 2.0)
	draw_line(Vector2(0.0, -10.0), Vector2(0.0, 26.0), OUTLINE_COLOR, 2.0)
	draw_rect(Rect2(Vector2(-7.0, -2.0), Vector2(14.0, 12.0)), OUTLINE_COLOR)


func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index: int in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width)
