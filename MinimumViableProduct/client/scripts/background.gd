extends Node2D

const BG_COLOR := Color(0.035, 0.055, 0.105)
const GRID_COLOR := Color(0.14, 0.28, 0.42, 0.28)
const GRID_MAJOR_COLOR := Color(0.2, 0.45, 0.65, 0.36)
const LANE_COLOR := Color(0.25, 0.75, 1.0, 0.12)
const CENTER_COLOR := Color(0.35, 0.9, 1.0, 0.55)

@export var grid_size: int = 48


func _ready() -> void:
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
	draw_rect(Rect2(Vector2(center.x - 32.0, 0.0), Vector2(64.0, size.y)), LANE_COLOR)
	draw_rect(Rect2(Vector2(0.0, center.y - 32.0), Vector2(size.x, 64.0)), LANE_COLOR)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, size.y), Color(0.35, 0.95, 1.0, 0.18), 2.0)
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), Color(0.35, 0.95, 1.0, 0.18), 2.0)


func _draw_center_marks(center: Vector2) -> void:
	draw_arc(center, 74.0, 0.0, TAU, 96, Color(0.2, 0.8, 1.0, 0.28), 2.0)
	draw_arc(center, 52.0, 0.0, TAU, 96, CENTER_COLOR, 2.0)
	draw_line(center + Vector2(-95.0, 0.0), center + Vector2(-60.0, 0.0), CENTER_COLOR, 2.0)
	draw_line(center + Vector2(60.0, 0.0), center + Vector2(95.0, 0.0), CENTER_COLOR, 2.0)
	draw_line(center + Vector2(0.0, -95.0), center + Vector2(0.0, -60.0), CENTER_COLOR, 2.0)
	draw_line(center + Vector2(0.0, 60.0), center + Vector2(0.0, 95.0), CENTER_COLOR, 2.0)
