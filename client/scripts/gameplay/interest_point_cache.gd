# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F12-ShortLootRuns.md
class_name InterestPointCache
extends Node2D


const ACTIVE_GROUP: String = "active_interest_point_caches"
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 80.0)
const FOOTPRINT_FILL_COLOR: Color = Color(0.18, 0.16, 0.12, 0.22)
const INNER_DIAMOND_SCALE: float = 0.62
const CORE_DIAMOND_SCALE: float = 0.30
const OUTLINE_COLOR: Color = Color(0.06, 0.045, 0.04, 0.9)
const OPENED_COLOR: Color = Color(0.28, 0.28, 0.26, 0.68)
const OUTLINE_WIDTH: float = 3.0
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
	draw_colored_polygon(footprint, FOOTPRINT_FILL_COLOR)
	_draw_outline(footprint, OUTLINE_COLOR, 2.0)

	var fill_color: Color = OPENED_COLOR if _opened else KIND_COLORS.get(_kind, Color(0.72, 0.58, 0.32)) as Color
	var inner_points: PackedVector2Array = _diamond_points(half_extents * INNER_DIAMOND_SCALE)
	var core_points: PackedVector2Array = _diamond_points(half_extents * CORE_DIAMOND_SCALE)
	draw_colored_polygon(inner_points, fill_color)
	_draw_outline(inner_points, OUTLINE_COLOR, OUTLINE_WIDTH)
	if _opened:
		_draw_opened_glyph(half_extents, fill_color)
	else:
		draw_colored_polygon(core_points, fill_color.lightened(0.28))
		_draw_outline(core_points, OUTLINE_COLOR, 2.0)
		draw_line(Vector2(0.0, -half_extents.y * INNER_DIAMOND_SCALE), Vector2(0.0, half_extents.y * INNER_DIAMOND_SCALE), OUTLINE_COLOR, 1.5)
		draw_line(Vector2(-half_extents.x * INNER_DIAMOND_SCALE, 0.0), Vector2(half_extents.x * INNER_DIAMOND_SCALE, 0.0), OUTLINE_COLOR, 1.5)


func _footprint_half_extents() -> Vector2:
	return _grid_cell_size * 0.5


func _diamond_points(half_extents: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -half_extents.y),
		Vector2(half_extents.x, 0.0),
		Vector2(0.0, half_extents.y),
		Vector2(-half_extents.x, 0.0),
	])


func _draw_opened_glyph(half_extents: Vector2, fill_color: Color) -> void:
	var top_shard: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -half_extents.y * 0.74),
		Vector2(half_extents.x * 0.34, -half_extents.y * 0.10),
		Vector2(0.0, 0.0),
		Vector2(-half_extents.x * 0.34, -half_extents.y * 0.10),
	])
	var bottom_shard: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, half_extents.y * 0.74),
		Vector2(half_extents.x * 0.34, half_extents.y * 0.10),
		Vector2(0.0, 0.0),
		Vector2(-half_extents.x * 0.34, half_extents.y * 0.10),
	])
	draw_colored_polygon(top_shard, fill_color.lightened(0.16))
	draw_colored_polygon(bottom_shard, fill_color.darkened(0.18))
	_draw_outline(top_shard, OUTLINE_COLOR, 2.0)
	_draw_outline(bottom_shard, OUTLINE_COLOR, 2.0)


func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index: int in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width)
