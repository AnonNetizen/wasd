class_name SteamLabSlimeBullet
extends Node2D

const DETACH_TIME: float = 0.13
const LIFETIME: float = 1.45
const DETACH_DISTANCE: float = 28.0
const SPEED: float = 560.0
const TRAIL_LENGTH: float = 28.0

var _surface_anchor: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.RIGHT
var _age: float = 0.0
var _fill_color: Color = Color(0.82, 1.0, 0.70, 0.96)
var _edge_color: Color = Color(0.98, 1.0, 0.84, 0.98)


func configure(surface_anchor: Vector2, direction: Vector2, fill_color: Color, edge_color: Color) -> void:
	_surface_anchor = surface_anchor
	_direction = direction.normalized()
	if _direction.length_squared() <= 0.0001:
		_direction = Vector2.RIGHT
	_fill_color = fill_color
	_edge_color = edge_color
	global_position = _surface_anchor
	rotation = _direction.angle()
	_age = 0.0
	queue_redraw()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return

	if _age < DETACH_TIME:
		var detach_ratio := _ease_out(_age / DETACH_TIME)
		global_position = _surface_anchor + _direction * lerpf(0.0, DETACH_DISTANCE, detach_ratio)
	else:
		var travel_time := _age - DETACH_TIME
		global_position = _surface_anchor + _direction * (DETACH_DISTANCE + SPEED * travel_time)
	queue_redraw()


func _draw() -> void:
	var fade := clampf((LIFETIME - _age) / 0.28, 0.0, 1.0)
	var detach_ratio := clampf(_age / DETACH_TIME, 0.0, 1.0)
	var eased_detach := _ease_out(detach_ratio)
	var radius := lerpf(5.5, 8.5, eased_detach)
	var squash := lerpf(1.35, 1.0, detach_ratio)
	var tail_alpha := 0.42 * fade
	var body_alpha := _fill_color.a * fade

	if detach_ratio < 1.0:
		var anchor_local := to_local(_surface_anchor)
		var bridge_alpha := 0.68 * (1.0 - detach_ratio) * fade
		var bridge_width := lerpf(10.0, 2.0, eased_detach)
		draw_line(anchor_local, Vector2.ZERO, Color(_fill_color, bridge_alpha), bridge_width, true)
		draw_circle(anchor_local, bridge_width * 0.42, Color(_fill_color, bridge_alpha))
	else:
		var tail_start := Vector2.LEFT * (TRAIL_LENGTH + radius * 0.5)
		draw_line(tail_start, Vector2.ZERO, Color(_fill_color, tail_alpha), radius * 0.95, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(squash, 1.0 / squash))
	draw_circle(Vector2.ZERO, radius, Color(_fill_color, body_alpha))
	draw_circle(Vector2.ZERO, radius, Color(_edge_color, _edge_color.a * fade), false, 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ease_out(value: float) -> float:
	var ratio := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - ratio, 3.0)
