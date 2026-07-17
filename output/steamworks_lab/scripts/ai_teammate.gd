class_name SteamLabAiTeammate
extends "res://scripts/slime_player.gd"

const DEFAULT_DURATION: float = 10.0
const FIRE_INTERVAL: float = 0.30
const FOLLOW_OFFSET := Vector2(0.0, 64.0)
const FOLLOW_DEADBAND: float = 10.0
const CATCH_UP_DISTANCE: float = 220.0

var remaining: float = DEFAULT_DURATION
var merge_consumed: bool = false

var _fire_cooldown: float = 0.0
var _aim_direction: Vector2 = Vector2.UP


func begin(duration: float = DEFAULT_DURATION) -> void:
	remaining = maxf(duration, 0.0)
	merge_consumed = false
	_fire_cooldown = 0.0
	_aim_direction = Vector2.UP
	revive_full()


func advance_ai(
	delta: float,
	leader_position: Vector2,
	follow_position: Vector2,
	target_position: Vector2,
	merged: bool
) -> Dictionary:
	remaining = maxf(0.0, remaining - maxf(delta, 0.0))
	_fire_cooldown = maxf(0.0, _fire_cooldown - maxf(delta, 0.0))

	if merged:
		set_input_vector(Vector2.ZERO)
	else:
		var offset := follow_position - body_center()
		if body_center().distance_to(leader_position) > CATCH_UP_DISTANCE:
			warp_to(follow_position)
			set_input_vector(Vector2.ZERO)
		elif offset.length() > FOLLOW_DEADBAND:
			set_input_vector(offset.normalized())
		else:
			set_input_vector(Vector2.ZERO)

	var has_target := target_position != Vector2.INF
	if has_target:
		var aim_origin := leader_position if merged else body_center()
		var target_direction := target_position - aim_origin
		if target_direction.length_squared() > 0.0001:
			_aim_direction = target_direction.normalized()

	var fire_ready := has_target and _fire_cooldown <= 0.0 and remaining > 0.0
	if fire_ready:
		_fire_cooldown = FIRE_INTERVAL
	return {
		"expired": remaining <= 0.0,
		"fire_ready": fire_ready,
		"aim_direction": _aim_direction,
	}


func can_merge() -> bool:
	return remaining > 0.0 and not merge_consumed


func mark_merge_consumed() -> void:
	merge_consumed = true


func remaining_seconds() -> float:
	return remaining


func aim_direction() -> Vector2:
	return _aim_direction
