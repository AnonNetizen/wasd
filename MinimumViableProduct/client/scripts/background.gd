# Doc: MinimumViableProduct/docs/代码/mvp_client.md
extends Node2D

const BG_COLOR := Color(0.035, 0.055, 0.105)
const GRID_COLOR := Color(0.14, 0.28, 0.42, 0.28)
const GRID_MAJOR_COLOR := Color(0.2, 0.45, 0.65, 0.36)
const LANE_COLOR := Color(0.25, 0.75, 1.0, 0.12)
const CENTER_COLOR := Color(0.35, 0.9, 1.0, 0.55)

@export var grid_size: int = 48
@export var lane_width: float = 64.0
@export var center_outer_radius: float = 74.0
@export var center_inner_radius: float = 52.0
@export var center_mark_inner: float = 60.0
@export var center_mark_outer: float = 95.0


func _ready() -> void:
	queue_redraw()


func apply_config(config: Dictionary) -> void:
	grid_size = max(4, _get_int(config, "grid_size", grid_size))
	lane_width = max(1.0, _get_number(config, "lane_width", lane_width))
	center_outer_radius = max(1.0, _get_number(config, "center_outer_radius", center_outer_radius))
	center_inner_radius = max(1.0, _get_number(config, "center_inner_radius", center_inner_radius))
	center_mark_inner = max(0.0, _get_number(config, "center_mark_inner", center_mark_inner))
	center_mark_outer = max(center_mark_inner, _get_number(config, "center_mark_outer", center_mark_outer))
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	var center := size * 0.5

	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR)
	_draw_grid(size)
	_draw_spawn_lanes(size, center)
	_draw_center_marks(center)


func _draw_grid(size: Vector2) -> void:
	for x in range(0, int(size.x) + grid_size, grid_size):
		var color := GRID_MAJOR_COLOR if x % (grid_size * 2) == 0 else GRID_COLOR
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), color, 1.0)

	for y in range(0, int(size.y) + grid_size, grid_size):
		var color := GRID_MAJOR_COLOR if y % (grid_size * 2) == 0 else GRID_COLOR
		draw_line(Vector2(0.0, y), Vector2(size.x, y), color, 1.0)


func _draw_spawn_lanes(size: Vector2, center: Vector2) -> void:
	var lane_half_width := lane_width * 0.5
	draw_rect(Rect2(Vector2(center.x - lane_half_width, 0.0), Vector2(lane_width, size.y)), LANE_COLOR)
	draw_rect(Rect2(Vector2(0.0, center.y - lane_half_width), Vector2(size.x, lane_width)), LANE_COLOR)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, size.y), Color(0.35, 0.95, 1.0, 0.18), 2.0)
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), Color(0.35, 0.95, 1.0, 0.18), 2.0)


func _draw_center_marks(center: Vector2) -> void:
	draw_arc(center, center_outer_radius, 0.0, TAU, 96, Color(0.2, 0.8, 1.0, 0.28), 2.0)
	draw_arc(center, center_inner_radius, 0.0, TAU, 96, CENTER_COLOR, 2.0)
	draw_line(center + Vector2(-center_mark_outer, 0.0), center + Vector2(-center_mark_inner, 0.0), CENTER_COLOR, 2.0)
	draw_line(center + Vector2(center_mark_inner, 0.0), center + Vector2(center_mark_outer, 0.0), CENTER_COLOR, 2.0)
	draw_line(center + Vector2(0.0, -center_mark_outer), center + Vector2(0.0, -center_mark_inner), CENTER_COLOR, 2.0)
	draw_line(center + Vector2(0.0, center_mark_inner), center + Vector2(0.0, center_mark_outer), CENTER_COLOR, 2.0)


func _get_number(section: Dictionary, key: String, default_value: float) -> float:
	var value: Variant = section.get(key, default_value)
	if value is int or value is float:
		return float(value)

	push_warning("[MvpBackground] config.%s must be a number, using %.2f" % [key, default_value])
	return default_value


func _get_int(section: Dictionary, key: String, default_value: int) -> int:
	var value: Variant = section.get(key, default_value)
	if value is int or value is float:
		return int(value)

	push_warning("[MvpBackground] config.%s must be a number, using %d" % [key, default_value])
	return default_value
