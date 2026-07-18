class_name SteamLabEnemyBullet
extends Node2D

const LIFETIME: float = 6.0
const HIT_RADIUS: float = 5.0
const BOUNDS_MARGIN: float = 60.0

var _direction: Vector2 = Vector2.DOWN
var _speed: float = 220.0
var _age: float = 0.0
var _world_rect: Rect2 = Rect2()


func configure(origin: Vector2, direction: Vector2, speed: float, world_rect: Rect2) -> void:
	global_position = origin
	_direction = direction.normalized()
	if _direction.length_squared() <= 0.0001:
		_direction = Vector2.DOWN
	_speed = maxf(speed, 1.0)
	_world_rect = world_rect
	_age = 0.0
	queue_redraw()


func set_battle_frozen(frozen: bool) -> void:
	set_physics_process(not frozen)


func hit_radius() -> float:
	return HIT_RADIUS


func motion_velocity() -> Vector2:
	return _direction * _speed


func is_expired() -> bool:
	if _age >= LIFETIME:
		return true
	if _world_rect.size.x <= 0.0:
		return false
	return not _world_rect.grow(BOUNDS_MARGIN).has_point(global_position)


func _physics_process(delta: float) -> void:
	_age += delta
	global_position += _direction * _speed * delta
	if is_expired():
		queue_free()


func _draw() -> void:
	var tail_start := -_direction * 14.0
	draw_line(tail_start, Vector2.ZERO, Color(1.0, 0.46, 0.30, 0.30), 3.4, true)
	draw_circle(Vector2.ZERO, HIT_RADIUS + 1.4, Color(0.98, 0.36, 0.24, 0.88))
	draw_circle(Vector2.ZERO, HIT_RADIUS - 1.6, Color(1.0, 0.82, 0.56, 0.95))
