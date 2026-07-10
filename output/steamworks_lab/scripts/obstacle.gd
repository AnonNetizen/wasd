class_name SteamLabObstacle
extends Node2D

const REMOTE_INTERPOLATION: float = 14.0
const HIT_FLASH_DURATION: float = 0.12
const DRIFT_RANGE: float = 20.0
const DRIFT_CYCLE_SECONDS: float = 4.2
const CRACK_LINE_COUNT: int = 4

var obstacle_id: int = 0
var radius: float = 48.0
var hp: float = 12.0
var max_hp: float = 12.0
var fall_speed: float = 55.0

var _drift_anchor_x: float = 0.0
var _drift_time: float = 0.0
var _shape_points: PackedVector2Array = PackedVector2Array()
var _crack_lines: Array[PackedVector2Array] = []
var _remote_driven: bool = false
var _authoritative_position: Vector2 = Vector2.ZERO
var _hit_flash_remaining: float = 0.0


func configure(
	new_obstacle_id: int,
	new_radius: float,
	new_fall_speed: float,
	new_hp: float,
	spawn_position: Vector2,
	shape_seed: int
) -> void:
	obstacle_id = new_obstacle_id
	radius = new_radius
	fall_speed = new_fall_speed
	hp = new_hp
	max_hp = new_hp
	global_position = spawn_position
	_authoritative_position = spawn_position
	_drift_anchor_x = spawn_position.x
	_drift_time = 0.0
	_hit_flash_remaining = 0.0
	_generate_shape(shape_seed)
	queue_redraw()


func set_remote_driven(remote: bool) -> void:
	_remote_driven = remote


func set_authoritative_state(new_position: Vector2, new_hp: float, new_max_hp: float) -> void:
	_authoritative_position = new_position
	if new_hp < hp:
		flash_hit()
	hp = new_hp
	max_hp = maxf(new_max_hp, 1.0)
	queue_redraw()


func advance(delta: float) -> void:
	_drift_time += delta
	global_position.y += fall_speed * delta
	global_position.x = _drift_anchor_x + sin(_drift_time / DRIFT_CYCLE_SECONDS * TAU) * DRIFT_RANGE


func take_hit(amount: int) -> void:
	hp = maxf(0.0, hp - float(amount))
	flash_hit()
	queue_redraw()


func is_destroyed() -> bool:
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


func _generate_shape(shape_seed: int) -> void:
	var shape_rng := RandomNumberGenerator.new()
	shape_rng.seed = shape_seed
	_shape_points.clear()
	var sides := shape_rng.randi_range(9, 12)
	for index in range(sides):
		var angle := TAU * float(index) / float(sides)
		var wobble := shape_rng.randf_range(0.72, 1.05)
		_shape_points.append(Vector2(cos(angle), sin(angle)) * radius * wobble)
	_crack_lines.clear()
	for index in range(CRACK_LINE_COUNT):
		var line := PackedVector2Array()
		var start_angle := shape_rng.randf_range(0.0, TAU)
		var start := Vector2(cos(start_angle), sin(start_angle)) * radius * shape_rng.randf_range(0.15, 0.4)
		var end_angle := start_angle + shape_rng.randf_range(-1.2, 1.2)
		var end := Vector2(cos(end_angle), sin(end_angle)) * radius * shape_rng.randf_range(0.6, 0.92)
		var middle := (start + end) * 0.5 + Vector2(shape_rng.randf_range(-6.0, 6.0), shape_rng.randf_range(-6.0, 6.0))
		line.append(start)
		line.append(middle)
		line.append(end)
		_crack_lines.append(line)


func _draw() -> void:
	if _shape_points.size() < 3:
		return
	var flash := clampf(_hit_flash_remaining / HIT_FLASH_DURATION, 0.0, 1.0)
	var fill := Color(0.38, 0.36, 0.34, 0.94).lerp(Color(0.9, 0.9, 0.9, 0.95), flash * 0.6)
	draw_colored_polygon(_shape_points, fill)
	var closed := PackedVector2Array(_shape_points)
	closed.append(_shape_points[0])
	draw_polyline(closed, Color(0.62, 0.58, 0.52, 0.95), 2.6, true)
	var damage_ratio := 1.0 - clampf(hp / max_hp, 0.0, 1.0)
	var visible_cracks := ceili(damage_ratio * float(CRACK_LINE_COUNT))
	for index in range(mini(visible_cracks, _crack_lines.size())):
		draw_polyline(_crack_lines[index], Color(0.16, 0.14, 0.13, 0.9), 1.8, true)
