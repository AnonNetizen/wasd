class_name SteamLabBoss
extends Node2D

const REMOTE_INTERPOLATION: float = 14.0
const HIT_FLASH_DURATION: float = 0.12
const ENRAGE_HP_RATIO: float = 0.3
const ENRAGE_INTERVAL_SCALE: float = 0.7
const AIMED_FAN_COUNT: int = 5
const AIMED_FAN_SPREAD_DEGREES: float = 12.0
const RING_BULLET_COUNT: int = 16
const RING_BULLET_SPEED: float = 200.0
const RING_INTERVAL: float = 6.0
const HOVER_SWAY_RANGE: float = 120.0
const HOVER_SWAY_CYCLE_SECONDS: float = 5.5
const ENTRY_SPEED: float = 170.0

var boss_index: int = 1
var hp: float = 60.0
var max_hp: float = 60.0
var radius: float = 64.0

var _hover_position: Vector2 = Vector2.ZERO
var _entered: bool = false
var _sway_time: float = 0.0
var _aimed_interval: float = 1.8
var _aimed_bullet_speed: float = 260.0
var _aimed_timer: float = 1.2
var _ring_timer: float = RING_INTERVAL
var _remote_driven: bool = false
var _authoritative_position: Vector2 = Vector2.ZERO
var _hit_flash_remaining: float = 0.0


func configure(new_boss_index: int, tier: int, hover_position: Vector2) -> void:
	boss_index = maxi(1, new_boss_index)
	max_hp = 60.0 * float(boss_index) * (1.0 + 0.2 * float(tier))
	hp = max_hp
	_aimed_interval = maxf(1.8 * pow(0.95, float(boss_index - 1)), 1.0)
	_aimed_bullet_speed = 240.0 + 20.0 * float(boss_index)
	_hover_position = hover_position
	global_position = hover_position + Vector2(0.0, -(radius * 2.0 + 220.0))
	_authoritative_position = global_position
	_entered = false
	_sway_time = 0.0
	_aimed_timer = 1.2
	_ring_timer = RING_INTERVAL
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


func advance(delta: float, targets: Array[Vector2]) -> Array[Dictionary]:
	var volleys: Array[Dictionary] = []
	if not _entered:
		var to_hover := _hover_position - global_position
		if to_hover.length() <= ENTRY_SPEED * delta:
			global_position = _hover_position
			_entered = true
		else:
			global_position += to_hover.normalized() * ENTRY_SPEED * delta
		return volleys

	_sway_time += delta
	var sway_phase := _sway_time / HOVER_SWAY_CYCLE_SECONDS * TAU
	global_position.x = _hover_position.x + sin(sway_phase) * HOVER_SWAY_RANGE

	var interval_scale := ENRAGE_INTERVAL_SCALE if is_enraged() else 1.0
	_aimed_timer -= delta
	if _aimed_timer <= 0.0:
		_aimed_timer = _aimed_interval * interval_scale
		var nearest := _nearest_target(targets)
		if nearest != Vector2.INF:
			var aim := (nearest - global_position).normalized()
			volleys.append({
				"directions": _fan_directions(aim),
				"speed": _aimed_bullet_speed,
			})
	_ring_timer -= delta
	if _ring_timer <= 0.0:
		_ring_timer = RING_INTERVAL * interval_scale
		volleys.append({
			"directions": _ring_directions(),
			"speed": RING_BULLET_SPEED,
		})
	return volleys


func take_hit(amount: int) -> void:
	hp = maxf(0.0, hp - float(amount))
	flash_hit()


func is_dead() -> bool:
	return hp <= 0.0


func is_enraged() -> bool:
	return hp > 0.0 and hp < max_hp * ENRAGE_HP_RATIO


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
	var spread := deg_to_rad(AIMED_FAN_SPREAD_DEGREES)
	var half := float(AIMED_FAN_COUNT - 1) * 0.5
	for index in range(AIMED_FAN_COUNT):
		directions.append(aim.rotated((float(index) - half) / half * spread))
	return directions


func _ring_directions() -> PackedVector2Array:
	var directions := PackedVector2Array()
	for index in range(RING_BULLET_COUNT):
		var angle := TAU * float(index) / float(RING_BULLET_COUNT)
		directions.append(Vector2(cos(angle), sin(angle)))
	return directions


func _draw() -> void:
	var flash := clampf(_hit_flash_remaining / HIT_FLASH_DURATION, 0.0, 1.0)
	var enraged := is_enraged()
	var fill := Color(0.56, 0.22, 0.34, 0.92)
	var core := Color(0.86, 0.34, 0.30, 0.9)
	if enraged:
		fill = Color(0.68, 0.16, 0.20, 0.94)
		core = Color(1.0, 0.42, 0.28, 0.95)
	fill = fill.lerp(Color(1.0, 1.0, 1.0, 0.95), flash * 0.7)

	var outer := _hull_points(radius, 8, 0.16)
	draw_colored_polygon(outer, fill)
	var closed := PackedVector2Array(outer)
	closed.append(outer[0])
	draw_polyline(closed, Color(1.0, 0.62, 0.48, 0.95), 3.2, true)
	draw_circle(Vector2.ZERO, radius * 0.42, core)
	draw_circle(Vector2.ZERO, radius * 0.42, Color(1.0, 0.82, 0.62, 0.9), false, 2.2, true)
	draw_circle(Vector2.ZERO, radius * 0.18, Color(1.0, 0.92, 0.72, 0.95))


func _hull_points(hull_radius: float, sides: int, pinch: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(sides):
		var angle := TAU * float(index) / float(sides) - TAU * 0.25
		var wobble := 1.0 - pinch * float(index % 2)
		points.append(Vector2(cos(angle), sin(angle)) * hull_radius * wobble)
	return points
