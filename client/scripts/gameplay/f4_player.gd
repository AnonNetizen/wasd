# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §3
class_name F4Player
extends CharacterBody2D


signal life_changed(current_life: float, max_life: float)
signal died()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const AIM_MARKER_LENGTH: float = 24.0
const DRAW_RADIUS: float = 12.0
const HIT_FLASH_DURATION: float = 0.18

var aim_direction: Vector2 = Vector2.RIGHT
var _base_stats: Dictionary = {}
var _damage_invulnerability_duration: float = 0.0
var _hit_flash_remaining: float = 0.0
var _invulnerable_remaining: float = 0.0
var _luck: float = 0.0
var _move_speed: float = 0.0
var _max_life: float = 1.0
var _life_points: float = 1.0
var _pickup_orb_speed: float = 0.0
var _pickup_range: float = 0.0
var _separation_radius: float = 0.0
var _stat_additions: Dictionary = {}
var _stat_multipliers: Dictionary = {}


func _ready() -> void:
	var camera: Camera2D = Camera2D.new()
	camera.name = "CenteredCamera"
	camera.enabled = true
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		velocity = Vector2.ZERO
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		velocity = Vector2.ZERO
		return

	_update_invulnerability(scaled_delta)
	_update_hit_flash(scaled_delta)

	var move_input: Vector2 = Input.get_vector(
		ACTIONS.MOVE_LEFT,
		ACTIONS.MOVE_RIGHT,
		ACTIONS.MOVE_UP,
		ACTIONS.MOVE_DOWN
	)
	var aim_input: Vector2 = Input.get_vector(
		ACTIONS.AIM_LEFT,
		ACTIONS.AIM_RIGHT,
		ACTIONS.AIM_UP,
		ACTIONS.AIM_DOWN
	)
	if aim_input.length_squared() > 0.0:
		var next_aim_direction: Vector2 = _snap_to_four_directions(aim_input)
		if next_aim_direction != aim_direction:
			aim_direction = next_aim_direction
			queue_redraw()

	velocity = move_input * _move_speed
	move_and_slide()


func configure(base_stats: Dictionary) -> void:
	_base_stats = base_stats.duplicate(true)
	_stat_additions.clear()
	_stat_multipliers.clear()
	_invulnerable_remaining = 0.0
	_rebuild_stats(true)


func current_life() -> float:
	return _life_points


func max_life() -> float:
	return _max_life


func invulnerability_remaining() -> float:
	return _invulnerable_remaining


func pickup_orb_speed() -> float:
	return _pickup_orb_speed


func pickup_range() -> float:
	return _pickup_range


func luck() -> float:
	return _luck


func separation_radius() -> float:
	return _separation_radius


func apply_modifiers(modifiers: Array) -> void:
	for raw_modifier: Variant in modifiers:
		if not raw_modifier is Dictionary:
			continue
		var modifier: Dictionary = raw_modifier as Dictionary
		var stat: String = String(modifier.get("stat", ""))
		var modifier_type: String = String(modifier.get("type", ""))
		var value: float = float(modifier.get("value", 0.0))
		if modifier_type == "add":
			_stat_additions[stat] = float(_stat_additions.get(stat, 0.0)) + value
		elif modifier_type == "mult":
			_stat_multipliers[stat] = float(_stat_multipliers.get(stat, 1.0)) * value
	_rebuild_stats(false)


func receive_damage(info: RefCounted) -> Dictionary:
	if _invulnerable_remaining > 0.0:
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": false,
			"reason": "invulnerable",
		}

	var amount: float = float(info.get("amount"))
	var applied_amount: float = minf(amount, _life_points)
	_life_points = maxf(_life_points - amount, 0.0)
	var is_defeated: bool = _life_points <= 0.0
	_start_invulnerability()
	_start_hit_flash()
	life_changed.emit(_life_points, _max_life)
	if is_defeated:
		died.emit()
	return {
		"applied": true,
		"amount": applied_amount,
		"defeated": is_defeated,
		"reason": "applied",
	}


func _draw() -> void:
	var body_color: Color = Color.WHITE if _hit_flash_remaining > 0.0 else Color(0.35, 0.72, 1.0)
	var marker_tip: Vector2 = aim_direction.normalized() * AIM_MARKER_LENGTH
	var marker_side: Vector2 = marker_tip.normalized().orthogonal() * 5.0
	draw_circle(Vector2.ZERO, DRAW_RADIUS, body_color)
	draw_line(Vector2.ZERO, marker_tip, Color.WHITE, 3.0)
	draw_colored_polygon(PackedVector2Array([
		marker_tip,
		marker_tip - aim_direction.normalized() * 8.0 + marker_side,
		marker_tip - aim_direction.normalized() * 8.0 - marker_side,
	]), Color.WHITE)


func _start_hit_flash() -> void:
	_hit_flash_remaining = HIT_FLASH_DURATION
	queue_redraw()


func _start_invulnerability() -> void:
	_invulnerable_remaining = _damage_invulnerability_duration


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_remaining <= 0.0:
		return
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	queue_redraw()


func _update_invulnerability(delta: float) -> void:
	if _invulnerable_remaining <= 0.0:
		return
	_invulnerable_remaining = maxf(_invulnerable_remaining - delta, 0.0)


func _rebuild_stats(reset_life: bool) -> void:
	var previous_max_life: float = _max_life
	_move_speed = _stat_value(STATS.MOVE_SPEED, 0.0)
	_max_life = _stat_value(STATS.MAX_HP, 1.0)
	_damage_invulnerability_duration = _stat_value(STATS.DAMAGE_INVULNERABILITY_DURATION, 0.0)
	_separation_radius = _stat_value(STATS.PLAYER_SEPARATION_RADIUS, 0.0)
	_pickup_range = _stat_value(STATS.PICKUP_RANGE, 0.0)
	_pickup_orb_speed = _stat_value(STATS.PICKUP_ORB_SPEED, 0.0)
	_luck = _stat_value(STATS.LUCK, 0.0)
	if reset_life:
		_life_points = _max_life
	elif _max_life > previous_max_life:
		_life_points += _max_life - previous_max_life
	_life_points = minf(_life_points, _max_life)
	life_changed.emit(_life_points, _max_life)


func _snap_to_four_directions(raw_direction: Vector2) -> Vector2:
	if absf(raw_direction.x) >= absf(raw_direction.y):
		return Vector2.RIGHT if raw_direction.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if raw_direction.y >= 0.0 else Vector2.UP


func _stat_value(stat: String, default_value: float) -> float:
	var base_value: float = float(_base_stats.get(stat, default_value))
	var added_value: float = float(_stat_additions.get(stat, 0.0))
	var multiplier: float = float(_stat_multipliers.get(stat, 1.0))
	return (base_value + added_value) * multiplier
