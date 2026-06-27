# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F12-ShortLootRuns.md
class_name InterestPointTarget
extends Node2D


signal destroyed(point_id: String)

const ACTIVE_GROUP: String = "active_interest_point_targets"
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 160.0)
const HIT_FLASH_COLOR: Color = Color(1.0, 0.92, 0.58)
const INNER_RECT_SCALE: float = 0.58
const KIND_COLORS: Dictionary = {
	"elite_nest": Color(0.84, 0.24, 0.28),
	"mod_cache": Color(0.34, 0.62, 1.0),
	"minor_nest_core": Color(0.86, 0.18, 0.46),
}
const OUTLINE_COLOR: Color = Color(0.06, 0.045, 0.04, 0.9)
const OUTLINE_WIDTH: float = 3.0
const TARGET_FILL_COLOR: Color = Color(0.82, 0.78, 0.62)

var _destroyed: bool = false
var _grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE
var _hit_flash_remaining: float = 0.0
var _hit_radius: float = 24.0
var _kind: String = ""
var _life_points: float = 1.0
var _max_life: float = 1.0
var _point_id: String = ""


func _process(delta: float) -> void:
	if _hit_flash_remaining <= 0.0:
		return
	_hit_flash_remaining = maxf(_hit_flash_remaining - GameClock.delta_scaled(delta), 0.0)
	queue_redraw()


func configure(point_id: String, kind: String, max_life: float, hit_radius: float, grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE) -> void:
	_point_id = point_id
	_kind = kind
	_grid_cell_size = Vector2(maxf(grid_cell_size.x, 1.0), maxf(grid_cell_size.y, 1.0))
	_max_life = maxf(max_life, 1.0)
	_life_points = _max_life
	_hit_radius = maxf(hit_radius, 1.0)
	_hit_radius = maxf(_hit_radius, _footprint_half_extents().x)
	_destroyed = false
	add_to_group(ACTIVE_GROUP)
	queue_redraw()


func point_id() -> String:
	return _point_id


func hit_radius() -> float:
	return _hit_radius


func is_alive() -> bool:
	return not _destroyed and _life_points > 0.0


func snapshot() -> Dictionary:
	return {
		"life_points": _life_points,
		"destroyed": _destroyed,
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_life_points = clampf(float(snapshot_data.get("life_points", _max_life)), 0.0, _max_life)
	_destroyed = bool(snapshot_data.get("destroyed", _life_points <= 0.0))
	if _destroyed:
		remove_from_group(ACTIVE_GROUP)
	queue_redraw()


func mark_claimed() -> void:
	_destroyed = true
	_life_points = 0.0
	remove_from_group(ACTIVE_GROUP)
	queue_redraw()


func receive_damage(info: RefCounted) -> Dictionary:
	if _destroyed or _life_points <= 0.0:
		return _damage_result(false, 0.0, true, "destroyed")

	var amount: float = float(info.get("amount"))
	var applied_amount: float = minf(amount, _life_points)
	_life_points = maxf(_life_points - amount, 0.0)
	var is_destroyed: bool = _life_points <= 0.0
	if is_destroyed:
		_destroyed = true
		remove_from_group(ACTIVE_GROUP)
		destroyed.emit(_point_id)
	else:
		_hit_flash_remaining = 0.14
	queue_redraw()
	return _damage_result(true, applied_amount, is_destroyed, "applied")


func debug_force_vulnerable() -> void:
	queue_redraw()


func _draw() -> void:
	var half_extents: Vector2 = _footprint_half_extents()
	var fill: Color = _fill_color()
	var outer_points: PackedVector2Array = _rect_points(half_extents)
	var inner_points: PackedVector2Array = _rect_points(half_extents * INNER_RECT_SCALE)
	draw_colored_polygon(outer_points, fill)
	_draw_outline(outer_points, OUTLINE_COLOR, OUTLINE_WIDTH)
	draw_colored_polygon(inner_points, fill.lightened(0.26))
	if _max_life > 0.0 and not _destroyed:
		var ratio: float = clampf(_life_points / _max_life, 0.0, 1.0)
		var bar_width: float = half_extents.x * 1.55
		var bar_y: float = -half_extents.y - 10.0
		draw_rect(Rect2(Vector2(-bar_width * 0.5, bar_y), Vector2(bar_width, 4.0)), OUTLINE_COLOR)
		draw_rect(Rect2(Vector2(-bar_width * 0.5, bar_y), Vector2(bar_width * ratio, 4.0)), Color(0.92, 0.78, 0.42))


func _fill_color() -> Color:
	if _destroyed:
		return Color(0.2, 0.18, 0.17, 0.55)
	if _hit_flash_remaining > 0.0:
		return HIT_FLASH_COLOR
	return KIND_COLORS.get(_kind, TARGET_FILL_COLOR) as Color


func _footprint_half_extents() -> Vector2:
	var hit_radius: float = maxf(_hit_radius, 1.0)
	var half_width: float = maxf(_grid_cell_size.x * 0.5, 1.0)
	var half_height: float = maxf(_grid_cell_size.y * 0.5, 1.0)
	var radius_tiles: int = maxi(int(ceilf(maxf(hit_radius / half_width, hit_radius / half_height))), 1)
	return _grid_cell_size * 0.5 * float(radius_tiles)


func _rect_points(half_extents: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half_extents.x, -half_extents.y),
		Vector2(half_extents.x, -half_extents.y),
		Vector2(half_extents.x, half_extents.y),
		Vector2(-half_extents.x, half_extents.y),
	])


func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index: int in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width)


func _damage_result(applied: bool, amount: float, defeated: bool, reason: String) -> Dictionary:
	return {
		"applied": applied,
		"amount": amount,
		"defeated": defeated,
		"reason": reason,
	}
