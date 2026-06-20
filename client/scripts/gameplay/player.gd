# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §3
class_name Player
extends CharacterBody2D


signal life_changed(current_life: float, max_life: float)
signal died()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const DRAW_RADIUS: float = 12.0
const FACING_MARKER_LENGTH: float = 22.0
const HIT_FLASH_DURATION: float = 0.18
const MOUSE_AIM_MIN_DISTANCE_SQUARED: float = 16.0
const REPLAY_PARTICIPANT_ID: String = "player_0"
const REPLAY_STATE_ACTIONS: Array[String] = [
	ACTIONS.MOVE_LEFT,
	ACTIONS.MOVE_RIGHT,
	ACTIONS.MOVE_UP,
	ACTIONS.MOVE_DOWN,
	ACTIONS.AIM_LEFT,
	ACTIONS.AIM_RIGHT,
	ACTIONS.AIM_UP,
	ACTIONS.AIM_DOWN,
]

var aim_direction: Vector2 = Vector2.RIGHT
var _base_stats: Dictionary = {}
var _damage_invulnerability_duration: float = 0.0
var _facing_sign: float = 1.0
var _hit_flash_remaining: float = 0.0
var _invulnerable_remaining: float = 0.0
var _luck: float = 0.0
var _move_speed: float = 0.0
var _max_life: float = 1.0
var _life_points: float = 1.0
var _mouse_aim_active: bool = false
var _mouse_aim_viewport_offset: Vector2 = Vector2.ZERO
var _pickup_orb_speed: float = 0.0
var _pickup_range: float = 0.0
var _separation_radius: float = 0.0
var _replay_action_pressed: Dictionary = {}
var _stat_additions: Dictionary = {}
var _stat_multipliers: Dictionary = {}


func _ready() -> void:
	var camera: Camera2D = get_node_or_null("CenteredCamera") as Camera2D
	if camera == null:
		push_error("[Player] missing CenteredCamera scene node")
		return
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.make_current()


func _input(event: InputEvent) -> void:
	var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
	if mouse_motion != null and GameState.is_state(GameState.PLAYING):
		_mouse_aim_active = true
		_set_mouse_aim_from_viewport_position(mouse_motion.position)
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null and GameState.is_state(GameState.PLAYING):
		_mouse_aim_active = true
		_set_mouse_aim_from_viewport_position(mouse_button.position)


func _physics_process(delta: float) -> void:
	_record_replay_action_states()

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
		_set_aim_direction(aim_input)
	elif _mouse_aim_active:
		_set_mouse_aim_from_viewport_position(get_viewport().get_mouse_position())

	velocity = move_input * _move_speed
	move_and_slide()


func configure(base_stats: Dictionary) -> void:
	_base_stats = base_stats.duplicate(true)
	_replay_action_pressed.clear()
	_stat_additions.clear()
	_stat_multipliers.clear()
	_invulnerable_remaining = 0.0
	_mouse_aim_active = false
	_mouse_aim_viewport_offset = Vector2.ZERO
	_rebuild_stats(true)


func current_life() -> float:
	return _life_points


func max_life() -> float:
	return _max_life


func debug_heal(amount: float) -> Dictionary:
	var previous_life: float = _life_points
	_life_points = minf(_life_points + maxf(amount, 0.0), _max_life)
	life_changed.emit(_life_points, _max_life)
	queue_redraw()
	return {
		"life": _life_points,
		"max_life": _max_life,
		"previous_life": previous_life,
	}


func debug_set_life(life_points: float) -> Dictionary:
	var previous_life: float = _life_points
	var was_alive: bool = _life_points > 0.0
	_life_points = clampf(life_points, 0.0, _max_life)
	life_changed.emit(_life_points, _max_life)
	queue_redraw()
	if was_alive and _life_points <= 0.0:
		died.emit()
	return {
		"life": _life_points,
		"max_life": _max_life,
		"previous_life": previous_life,
	}


func debug_clear_invulnerability() -> void:
	_invulnerable_remaining = 0.0


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


func aim_at_world_position(world_position: Vector2) -> void:
	var mouse_direction: Vector2 = world_position - global_position
	if mouse_direction.length_squared() > MOUSE_AIM_MIN_DISTANCE_SQUARED:
		_set_aim_direction(mouse_direction)


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


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"aim_direction": _vector_to_dict(aim_direction),
		"life_points": _life_points,
		"invulnerable_remaining": _invulnerable_remaining,
		"stat_additions": _stat_additions.duplicate(true),
		"stat_multipliers": _stat_multipliers.duplicate(true),
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_replay_action_pressed.clear()
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_mouse_aim_active = false
	_mouse_aim_viewport_offset = Vector2.ZERO
	_set_aim_direction(_dict_to_vector(snapshot_data.get("aim_direction", {}), aim_direction))
	_stat_additions = _dictionary_or_empty(snapshot_data.get("stat_additions", {}))
	_stat_multipliers = _dictionary_or_empty(snapshot_data.get("stat_multipliers", {}))
	_rebuild_stats(true)
	_life_points = clampf(float(snapshot_data.get("life_points", _max_life)), 0.0, _max_life)
	_invulnerable_remaining = maxf(float(snapshot_data.get("invulnerable_remaining", 0.0)), 0.0)
	life_changed.emit(_life_points, _max_life)
	queue_redraw()


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
	var marker_tip: Vector2 = Vector2(FACING_MARKER_LENGTH * _facing_sign, 0.0)
	var marker_tail: Vector2 = marker_tip - Vector2(8.0 * _facing_sign, 0.0)
	draw_circle(Vector2.ZERO, DRAW_RADIUS, body_color)
	draw_circle(Vector2(DRAW_RADIUS * 0.35 * _facing_sign, -3.5), 2.0, Color.WHITE)
	draw_line(Vector2.ZERO, marker_tip, Color.WHITE, 3.0)
	draw_colored_polygon(PackedVector2Array([
		marker_tip,
		marker_tail + Vector2(0.0, 5.0),
		marker_tail - Vector2(0.0, 5.0),
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


func _record_replay_action_states() -> void:
	if not Replay.is_recording():
		return

	for action_name: String in REPLAY_STATE_ACTIONS:
		var strength: float = Input.get_action_strength(action_name)
		var pressed: bool = strength > 0.0
		var was_pressed: bool = bool(_replay_action_pressed.get(action_name, false))
		if pressed == was_pressed:
			continue
		_replay_action_pressed[action_name] = pressed
		Replay.record_input_action(action_name, pressed, strength, REPLAY_PARTICIPANT_ID)


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


func _set_aim_direction(raw_direction: Vector2) -> void:
	if raw_direction.length_squared() <= 0.0:
		return

	var next_direction: Vector2 = raw_direction.normalized()
	var previous_direction: Vector2 = aim_direction
	var previous_facing_sign: float = _facing_sign
	aim_direction = next_direction
	if next_direction.x > 0.01:
		_facing_sign = 1.0
	elif next_direction.x < -0.01:
		_facing_sign = -1.0
	if previous_direction.distance_squared_to(aim_direction) > 0.0001 or not is_equal_approx(previous_facing_sign, _facing_sign):
		queue_redraw()


func _set_mouse_aim_from_viewport_position(viewport_position: Vector2) -> void:
	_mouse_aim_viewport_offset = viewport_position - get_viewport_rect().size * 0.5
	if _mouse_aim_viewport_offset.length_squared() > MOUSE_AIM_MIN_DISTANCE_SQUARED:
		_set_aim_direction(_mouse_aim_viewport_offset)


func _stat_value(stat: String, default_value: float) -> float:
	var base_value: float = float(_base_stats.get(stat, default_value))
	var added_value: float = float(_stat_additions.get(stat, 0.0))
	var multiplier: float = float(_stat_multipliers.get(stat, 1.0))
	return (base_value + added_value) * multiplier


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}
