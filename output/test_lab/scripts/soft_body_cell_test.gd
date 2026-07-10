extends Node2D

const CELL_SCRIPT := preload("res://scripts/soft_body_cell.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const OBSTACLE_RECT := Rect2(Vector2(700.0, 250.0), Vector2(160.0, 260.0))
const GRID_STEP := 40.0

var _cell: Node2D
var _time: float = 0.0
var _target_position: Vector2 = Vector2(360.0, 380.0)


func _ready() -> void:
	_cell = CELL_SCRIPT.new() as Node2D
	_cell.name = "SoftBodyCell"
	_cell.global_position = Vector2(330.0, 380.0)
	_cell.call("set_obstacle_rect", OBSTACLE_RECT)
	add_child(_cell)


func _process(delta: float) -> void:
	_time += delta
	_target_position = _path_target()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_target_position = get_global_mouse_position()

	_cell.call("set_follow_target", _target_position)
	_cell.call("set_obstacle_rect", OBSTACLE_RECT)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.035, 0.045, 0.048, 1.0), true)
	_draw_grid()
	_draw_path()
	_draw_obstacle()
	_draw_target_marker()


func _path_target() -> Vector2:
	return Vector2(
		545.0 + sin(_time * 0.58) * 340.0,
		380.0 + sin(_time * 1.12) * 118.0
	)


func _draw_grid() -> void:
	var grid_color := Color(0.25, 0.44, 0.43, 0.16)
	for x_index in range(int(VIEWPORT_SIZE.x / GRID_STEP) + 1):
		var x := float(x_index) * GRID_STEP
		draw_line(Vector2(x, 0.0), Vector2(x, VIEWPORT_SIZE.y), grid_color, 1.0)

	for y_index in range(int(VIEWPORT_SIZE.y / GRID_STEP) + 1):
		var y := float(y_index) * GRID_STEP
		draw_line(Vector2(0.0, y), Vector2(VIEWPORT_SIZE.x, y), grid_color, 1.0)


func _draw_path() -> void:
	var path_points := PackedVector2Array()
	for index in range(96):
		var preview_time := float(index) / 95.0 * TAU / 0.58
		path_points.append(Vector2(
			545.0 + sin(preview_time * 0.58) * 340.0,
			380.0 + sin(preview_time * 1.12) * 118.0
		))
	draw_polyline(path_points, Color(0.8, 0.98, 0.72, 0.14), 2.0, true)


func _draw_obstacle() -> void:
	var shadow_rect := OBSTACLE_RECT.grow(16.0)
	draw_rect(shadow_rect, Color(0.0, 0.0, 0.0, 0.24), true)
	draw_rect(OBSTACLE_RECT, Color(0.30, 0.19, 0.15, 1.0), true)
	draw_rect(OBSTACLE_RECT, Color(0.86, 0.55, 0.34, 1.0), false, 3.0)

	for stripe_index in range(6):
		var stripe_y := OBSTACLE_RECT.position.y + 32.0 + float(stripe_index) * 38.0
		draw_line(
			Vector2(OBSTACLE_RECT.position.x + 18.0, stripe_y),
			Vector2(OBSTACLE_RECT.position.x + OBSTACLE_RECT.size.x - 18.0, stripe_y + 24.0),
			Color(0.92, 0.67, 0.42, 0.28),
			2.0
		)


func _draw_target_marker() -> void:
	draw_circle(_target_position, 8.0, Color(1.0, 0.92, 0.42, 0.62))
	draw_arc(_target_position, 18.0, 0.0, TAU, 32, Color(1.0, 0.92, 0.42, 0.5), 2.0, true)
	if is_instance_valid(_cell):
		draw_line(_cell.global_position, _target_position, Color(1.0, 0.92, 0.42, 0.16), 1.0)
