class_name SteamLabEnemy
extends Node2D

const KIND_DART: int = 0
const KIND_GUNNER: int = 1
const KIND_STRAFER: int = 2

const REMOTE_INTERPOLATION: float = 14.0
const HIT_FLASH_DURATION: float = 0.12
const GUNNER_SWAY_RANGE: float = 60.0
const GUNNER_SWAY_SPEED: float = 0.9
const FAN_SPREAD_DEGREES: float = 10.0

var enemy_id: int = 0
var kind: int = KIND_DART
var hp: float = 3.0
var max_hp: float = 3.0
var radius: float = 16.0
var move_speed: float = 140.0
var fire_interval: float = 0.0
var bullet_speed: float = 220.0
var fire_fan_count: int = 1

var _remote_driven: bool = false
var _authoritative_position: Vector2 = Vector2.ZERO
var _fire_timer: float = 0.0
var _hover_y: float = 200.0
var _hover_anchor_x: float = 0.0
var _sway_time: float = 0.0
var _strafe_velocity: Vector2 = Vector2.ZERO
var _hit_flash_remaining: float = 0.0


func configure(new_enemy_id: int, new_kind: int, stats: Dictionary, spawn_position: Vector2) -> void:
	enemy_id = new_enemy_id
	kind = new_kind
	hp = float(stats.get("hp", 3.0))
	max_hp = float(stats.get("max_hp", hp))
	radius = float(stats.get("radius", 16.0))
	move_speed = float(stats.get("move_speed", 140.0))
	fire_interval = float(stats.get("fire_interval", 0.0))
	bullet_speed = float(stats.get("bullet_speed", 220.0))
	fire_fan_count = int(stats.get("fire_fan_count", 1))
	_hover_y = float(stats.get("hover_y", 200.0))
	_strafe_velocity = Vector2(
		float(stats.get("strafe_speed_x", 90.0)),
		float(stats.get("strafe_speed_y", 110.0))
	)
	_sway_time = float(stats.get("sway_phase", 0.0))
	global_position = spawn_position
	_authoritative_position = spawn_position
	_hover_anchor_x = spawn_position.x
	_fire_timer = maxf(fire_interval * 0.6, 0.35)
	_hit_flash_remaining = 0.0
	queue_redraw()


func set_remote_driven(remote: bool) -> void:
	_remote_driven = remote


func set_authoritative_state(new_position: Vector2, new_hp: float, new_max_hp: float) -> void:
	_authoritative_position = new_position
	if new_hp < hp:
		flash_hit()
	hp = new_hp
	max_hp = maxf(new_max_hp, 1.0)


func advance(delta: float, targets: Array[Vector2]) -> PackedVector2Array:
	var fire_directions := PackedVector2Array()
	var nearest := _nearest_target(targets)
	match kind:
		KIND_DART:
			var to_target := Vector2.DOWN
			if nearest != Vector2.INF:
				to_target = (nearest - global_position).normalized()
			global_position += to_target * move_speed * delta
		KIND_GUNNER:
			if global_position.y < _hover_y:
				global_position.y += move_speed * delta
			else:
				_sway_time += delta * GUNNER_SWAY_SPEED
				global_position.x = _hover_anchor_x + sin(_sway_time * TAU) * GUNNER_SWAY_RANGE
			if fire_interval > 0.0:
				_fire_timer -= delta
				if _fire_timer <= 0.0 and nearest != Vector2.INF:
					_fire_timer = fire_interval
					var aim := (nearest - global_position).normalized()
					fire_directions = _fan_directions(aim)
		KIND_STRAFER:
			global_position += _strafe_velocity * delta
			if fire_interval > 0.0:
				_fire_timer -= delta
				if _fire_timer <= 0.0:
					_fire_timer = fire_interval
					fire_directions.append(Vector2.DOWN)
	return fire_directions


func take_hit(amount: int) -> void:
	hp = maxf(0.0, hp - float(amount))
	flash_hit()


func is_dead() -> bool:
	return hp <= 0.0


func flash_hit() -> void:
	_hit_flash_remaining = HIT_FLASH_DURATION
	queue_redraw()


func _process(delta: float) -> void:
	if _remote_driven:
		var response := 1.0 - exp(-REMOTE_INTERPOLATION * delta)
		global_position = global_position.lerp(_authoritative_position, response)
	if _hit_flash_remaining > 0.0:
		_hit_flash_remaining = maxf(0.0, _hit_flash_remaining - delta)
		queue_redraw()


func _nearest_target(targets: Array[Vector2]) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for target in targets:
		var distance := global_position.distance_squared_to(target)
		if distance < best_distance:
			best_distance = distance
			best = target
	return best


func _fan_directions(aim: Vector2) -> PackedVector2Array:
	var directions := PackedVector2Array()
	if fire_fan_count <= 1:
		directions.append(aim)
		return directions
	var spread := deg_to_rad(FAN_SPREAD_DEGREES)
	var half := float(fire_fan_count - 1) * 0.5
	for index in range(fire_fan_count):
		directions.append(aim.rotated((float(index) - half) / maxf(half, 1.0) * spread))
	return directions


func _draw() -> void:
	var flash := clampf(_hit_flash_remaining / HIT_FLASH_DURATION, 0.0, 1.0)
	var low_hp := hp <= max_hp * 0.5
	var fill := Color(0.86, 0.44, 0.30, 0.88)
	var edge := Color(1.0, 0.68, 0.42, 0.95)
	match kind:
		KIND_DART:
			fill = Color(0.88, 0.38, 0.26, 0.88)
			_draw_polygon_shape(_dart_points(), fill, edge, flash, low_hp)
		KIND_GUNNER:
			fill = Color(0.72, 0.30, 0.40, 0.88)
			_draw_polygon_shape(_gunner_points(), fill, edge, flash, low_hp)
		KIND_STRAFER:
			fill = Color(0.90, 0.56, 0.24, 0.88)
			_draw_polygon_shape(_strafer_points(), fill, edge, flash, low_hp)


func _draw_polygon_shape(
	points: PackedVector2Array,
	fill: Color,
	edge: Color,
	flash: float,
	low_hp: bool
) -> void:
	var flash_fill := fill.lerp(Color(1.0, 1.0, 1.0, 0.95), flash * 0.75)
	draw_colored_polygon(points, flash_fill)
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	var outline := edge
	if low_hp:
		outline = Color(1.0, 0.22, 0.18, 0.98)
	draw_polyline(closed, outline, 2.4, true)


func _dart_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, radius),
		Vector2(-radius * 0.78, -radius * 0.72),
		Vector2(0.0, -radius * 0.32),
		Vector2(radius * 0.78, -radius * 0.72),
	])


func _gunner_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(6):
		var angle := TAU * float(index) / 6.0 + TAU / 12.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _strafer_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, radius * 0.9),
		Vector2(-radius, -radius * 0.35),
		Vector2(-radius * 0.30, -radius * 0.15),
		Vector2(0.0, -radius * 0.75),
		Vector2(radius * 0.30, -radius * 0.15),
		Vector2(radius, -radius * 0.35),
	])
