class_name SteamLabSlimeBullet
extends Node2D

const EMERGE_TIME: float = 0.085
const LIFETIME: float = 1.45
const BODY_EXIT_DISTANCE: float = 52.0
const INITIAL_INSIDE_DISTANCE: float = 10.0
const SPEED: float = 560.0
const TRAIL_LENGTH: float = 28.0

var _origin_center: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.RIGHT
var _age: float = 0.0
var _fill_color: Color = Color(0.82, 1.0, 0.70, 0.96)
var _edge_color: Color = Color(0.98, 1.0, 0.84, 0.98)


func configure(origin_center: Vector2, direction: Vector2, fill_color: Color, edge_color: Color) -> void:
	_origin_center = origin_center
	_direction = direction.normalized()
	if _direction.length_squared() <= 0.0001:
		_direction = Vector2.RIGHT
	_fill_color = fill_color
	_edge_color = edge_color
	global_position = _origin_center - _direction * INITIAL_INSIDE_DISTANCE
	rotation = _direction.angle()
	_age = 0.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return

	if _age < EMERGE_TIME:
		var emerge_ratio := _ease_out(_age / EMERGE_TIME)
		global_position = _origin_center + _direction * lerpf(-INITIAL_INSIDE_DISTANCE, BODY_EXIT_DISTANCE, emerge_ratio)
	else:
		var travel_time := _age - EMERGE_TIME
		global_position = _origin_center + _direction * (BODY_EXIT_DISTANCE + SPEED * travel_time)
	queue_redraw()


func _draw() -> void:
	var fade := clampf((LIFETIME - _age) / 0.28, 0.0, 1.0)
	var emerge_ratio := clampf(_age / EMERGE_TIME, 0.0, 1.0)
	var radius := lerpf(4.0, 8.5, _ease_out(emerge_ratio))
	var squash := lerpf(1.55, 1.0, emerge_ratio)
	var tail_alpha := 0.42 * fade
	var body_alpha := _fill_color.a * fade

	var tail_start := Vector2.LEFT * (TRAIL_LENGTH + radius * 0.5)
	draw_line(tail_start, Vector2.ZERO, Color(_fill_color, tail_alpha), radius * 0.95, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(squash, 1.0 / squash))
	draw_circle(Vector2.ZERO, radius, Color(_fill_color, body_alpha))
	draw_circle(Vector2.ZERO, radius, Color(_edge_color, _edge_color.a * fade), false, 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ease_out(value: float) -> float:
	var ratio := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - ratio, 3.0)
