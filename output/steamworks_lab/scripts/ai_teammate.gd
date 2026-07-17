class_name SteamLabAiTeammate
extends "res://scripts/slime_player.gd"

enum MovementMode { TACTICAL, DODGE, RECALL, MERGED }

const DEFAULT_DURATION: float = 10.0
const FIRE_INTERVAL: float = 0.30
const THREAT_QUERY_RADIUS: float = 280.0
const DECISION_INTERVAL: float = 0.08
const PREDICTION_HORIZON: float = 0.65
const SAFE_CENTER_DISTANCE: float = 48.0
const DODGE_LOCK_DURATION: float = 0.22
const TACTICAL_BACK_OFFSET: float = 36.0
const TACTICAL_FLANK_OFFSET: float = 104.0
const IDLE_BACK_OFFSET: float = 88.0
const IDLE_FLANK_OFFSET: float = 52.0
const FORMATION_DEADBAND: float = 10.0
const MAX_ROAM_DISTANCE: float = 210.0
const CATCH_UP_DISTANCE: float = 220.0
const RECALL_RADIUS: float = 64.0
const MERGE_DISTANCE: float = 92.0
const RECALL_FALLBACK_TIME: float = 0.85
const NORMAL_SPEED_SCALE: float = 1.18
const DODGE_SPEED_SCALE: float = 1.45
const RECALL_SPEED_SCALE: float = 1.75
const CANDIDATE_TRAVEL_TIME: float = 0.28
const BODY_CLEARANCE: float = 33.0
const WORLD_MARGIN: float = 29.0
const MIN_LEADER_SEPARATION: float = 46.0
const URGENT_THREAT_TIME: float = 0.18
const INPUT_RESPONSE_TACTICAL: float = 8.0
const INPUT_RESPONSE_DODGE: float = 16.0
const INPUT_RESPONSE_RECALL: float = 18.0

var remaining: float = DEFAULT_DURATION
var merge_consumed: bool = false

var _fire_cooldown: float = 0.0
var _aim_direction: Vector2 = Vector2.UP
var _base_move_speed: float = 340.0
var _movement_mode: int = MovementMode.TACTICAL
var _decision_remaining: float = 0.0
var _desired_move: Vector2 = Vector2.ZERO
var _smoothed_move: Vector2 = Vector2.ZERO
var _dodge_lock_remaining: float = 0.0
var _dodge_urgency: float = 0.0
var _last_leader_direction: Vector2 = Vector2.UP
var _flank_sign: float = 1.0
var _tactical_anchor: Vector2 = Vector2.ZERO
var _last_min_clearance: float = INF
var _recall_elapsed: float = 0.0
var _recall_last_distance: float = INF
var _recall_direction: Vector2 = Vector2.DOWN
var _recall_warped: bool = false


func begin(duration: float = DEFAULT_DURATION) -> void:
	remaining = maxf(duration, 0.0)
	merge_consumed = false
	_fire_cooldown = 0.0
	_aim_direction = Vector2.UP
	_movement_mode = MovementMode.TACTICAL
	_decision_remaining = 0.0
	_desired_move = Vector2.ZERO
	_smoothed_move = Vector2.ZERO
	_dodge_lock_remaining = 0.0
	_dodge_urgency = 0.0
	_last_leader_direction = Vector2.UP
	_flank_sign = 1.0
	_tactical_anchor = body_center()
	_last_min_clearance = INF
	_recall_elapsed = 0.0
	_recall_last_distance = INF
	_recall_direction = Vector2.DOWN
	_recall_warped = false
	revive_full()


func configure_movement_speeds(base_speed: float) -> void:
	_base_move_speed = maxf(base_speed, 1.0)
	_apply_mode_speed()


func advance_ai(
	delta: float,
	leader_position: Vector2,
	leader_velocity: Vector2,
	target_position: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2,
	merged: bool,
	recall_requested: bool
) -> Dictionary:
	var step := maxf(delta, 0.0)
	remaining = maxf(0.0, remaining - step)
	_fire_cooldown = maxf(0.0, _fire_cooldown - step)
	_dodge_lock_remaining = maxf(0.0, _dodge_lock_remaining - step)
	_decision_remaining -= step
	_recall_warped = false

	if leader_velocity.length_squared() > 64.0:
		_last_leader_direction = leader_velocity.normalized()

	if merged:
		_enter_mode(MovementMode.MERGED)
		_desired_move = Vector2.ZERO
		_smoothed_move = Vector2.ZERO
		set_input_vector(Vector2.ZERO)
		_recall_elapsed = 0.0
		_recall_last_distance = INF
	elif recall_requested:
		_update_recall(step, leader_position, movement_context, world_rect)
	else:
		_recall_elapsed = 0.0
		_recall_last_distance = body_center().distance_to(leader_position)
		_update_tactical(leader_position, target_position, movement_context, world_rect)
		_apply_smoothed_input(step)

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
		"movement_mode": _movement_mode,
		"recalling": _movement_mode == MovementMode.RECALL,
		"recall_warped": _recall_warped,
	}


func movement_mode() -> int:
	return _movement_mode


func movement_decision_state() -> Dictionary:
	return {
		"movement_mode": _movement_mode,
		"desired_move": _desired_move,
		"tactical_anchor": _tactical_anchor,
		"min_projected_clearance": _last_min_clearance,
		"dodge_lock_remaining": _dodge_lock_remaining,
		"recall_elapsed": _recall_elapsed,
		"recall_warped": _recall_warped,
	}


func can_merge() -> bool:
	return remaining > 0.0 and not merge_consumed


func mark_merge_consumed() -> void:
	merge_consumed = true


func remaining_seconds() -> float:
	return remaining


func aim_direction() -> Vector2:
	return _aim_direction


func _update_tactical(
	leader_position: Vector2,
	target_position: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2
) -> void:
	if body_center().distance_to(leader_position) > CATCH_UP_DISTANCE:
		warp_to(_best_safe_position(leader_position, RECALL_RADIUS, movement_context, world_rect))
		_desired_move = Vector2.ZERO
		_smoothed_move = Vector2.ZERO
		_decision_remaining = 0.0

	var threat := _most_urgent_threat(body_center(), Vector2.ZERO, movement_context)
	var threat_active := bool(threat.get("active", false))
	var threat_urgency := float(threat.get("urgency", 0.0))
	var emergency := threat_active and threat_urgency > _dodge_urgency + 0.25
	if _decision_remaining > 0.0 and not emergency:
		return
	_decision_remaining = DECISION_INTERVAL
	_tactical_anchor = _choose_tactical_anchor(
		leader_position,
		target_position,
		movement_context,
		world_rect
	)
	if threat_active or _dodge_lock_remaining > 0.0:
		_enter_mode(MovementMode.DODGE)
		if _dodge_lock_remaining <= 0.0 or emergency:
			_desired_move = _choose_dodge_direction(
				leader_position,
				_tactical_anchor,
				movement_context,
				world_rect
			)
			_dodge_lock_remaining = DODGE_LOCK_DURATION
			_dodge_urgency = threat_urgency
		return
	_enter_mode(MovementMode.TACTICAL)
	_dodge_urgency = 0.0
	_desired_move = _choose_tactical_direction(
		leader_position,
		_tactical_anchor,
		movement_context,
		world_rect
	)


func _update_recall(
	delta: float,
	leader_position: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2
) -> void:
	if _movement_mode != MovementMode.RECALL:
		var outward := body_center() - leader_position
		_recall_direction = outward.normalized() if outward.length_squared() > 0.0001 else -_last_leader_direction
		if _recall_direction.length_squared() <= 0.0001:
			_recall_direction = Vector2.DOWN
		_recall_elapsed = 0.0
		_recall_last_distance = body_center().distance_to(leader_position)
		_decision_remaining = 0.0
		_dodge_lock_remaining = 0.0
	_enter_mode(MovementMode.RECALL)
	var leader_distance := body_center().distance_to(leader_position)
	if leader_distance > MERGE_DISTANCE:
		if leader_distance < _recall_last_distance - 0.5:
			_recall_elapsed = 0.0
		else:
			_recall_elapsed += delta
		_recall_last_distance = leader_distance
	else:
		_recall_elapsed = 0.0
		_recall_last_distance = leader_distance
	if _recall_elapsed >= RECALL_FALLBACK_TIME:
		warp_to(_best_safe_position(leader_position, RECALL_RADIUS, movement_context, world_rect))
		_recall_elapsed = 0.0
		_recall_last_distance = body_center().distance_to(leader_position)
		_recall_warped = true
		_desired_move = Vector2.ZERO
		_smoothed_move = Vector2.ZERO
		set_input_vector(Vector2.ZERO)
		return
	if _decision_remaining <= 0.0:
		_decision_remaining = DECISION_INTERVAL
		var recall_target := _clamp_to_world(
			leader_position + _recall_direction * RECALL_RADIUS,
			world_rect
		)
		_desired_move = _choose_recall_direction(
			leader_position,
			recall_target,
			movement_context,
			world_rect
		)
	_apply_smoothed_input(delta)


func _choose_tactical_anchor(
	leader_position: Vector2,
	target_position: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2
) -> Vector2:
	var formation_direction := _last_leader_direction
	var back_offset := IDLE_BACK_OFFSET
	var flank_offset := IDLE_FLANK_OFFSET
	if target_position != Vector2.INF:
		var to_target := target_position - leader_position
		if to_target.length_squared() > 0.0001:
			formation_direction = to_target.normalized()
		back_offset = TACTICAL_BACK_OFFSET
		flank_offset = TACTICAL_FLANK_OFFSET
	var lateral := formation_direction.orthogonal()
	var preferred := _clamp_to_world(
		leader_position - formation_direction * back_offset + lateral * flank_offset * _flank_sign,
		world_rect
	)
	var alternate := _clamp_to_world(
		leader_position - formation_direction * back_offset - lateral * flank_offset * _flank_sign,
		world_rect
	)
	var preferred_score := _static_position_score(preferred, leader_position, movement_context, world_rect)
	var alternate_score := _static_position_score(alternate, leader_position, movement_context, world_rect)
	if alternate_score > preferred_score + 80.0:
		_flank_sign *= -1.0
		return alternate
	return preferred


func _choose_tactical_direction(
	leader_position: Vector2,
	anchor: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2
) -> Vector2:
	var to_anchor := anchor - body_center()
	if to_anchor.length() <= FORMATION_DEADBAND:
		return Vector2.ZERO
	var direct := to_anchor.normalized()
	return _best_direction(
		direct,
		leader_position,
		anchor,
		movement_context,
		world_rect,
		_base_move_speed * NORMAL_SPEED_SCALE,
		false
	)


func _choose_dodge_direction(
	leader_position: Vector2,
	anchor: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2
) -> Vector2:
	var preferred := (anchor - body_center()).normalized()
	var primary_threat := _most_urgent_threat(body_center(), Vector2.ZERO, movement_context)
	var threat_velocity: Vector2 = primary_threat.get("velocity", Vector2.ZERO)
	if threat_velocity.length_squared() > 0.0001:
		var lateral := threat_velocity.normalized().orthogonal()
		if (body_center() + lateral).distance_squared_to(anchor) > (
			body_center() - lateral
		).distance_squared_to(anchor):
			lateral *= -1.0
		preferred = lateral
	return _best_direction(
		preferred,
		leader_position,
		anchor,
		movement_context,
		world_rect,
		_base_move_speed * DODGE_SPEED_SCALE,
		true
	)


func _choose_recall_direction(
	leader_position: Vector2,
	recall_target: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2
) -> Vector2:
	var preferred := (recall_target - body_center()).normalized()
	return _best_direction(
		preferred,
		leader_position,
		recall_target,
		movement_context,
		world_rect,
		_base_move_speed * RECALL_SPEED_SCALE,
		false,
		true
	)


func _best_direction(
	preferred: Vector2,
	leader_position: Vector2,
	anchor: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2,
	speed: float,
	include_bullet_risk: bool,
	recalling: bool = false
) -> Vector2:
	var best_direction := Vector2.ZERO
	var best_score := -INF
	var best_clearance := -INF
	for candidate_index in range(9):
		var direction := Vector2.ZERO
		if candidate_index > 0:
			var angle := TAU * float(candidate_index - 1) / 8.0
			direction = Vector2(cos(angle), sin(angle))
		var endpoint := body_center() + direction * speed * CANDIDATE_TRAVEL_TIME
		var score := _static_position_score(endpoint, leader_position, movement_context, world_rect)
		var route_clearance := _blocker_path_clearance(
			body_center(),
			endpoint,
			movement_context
		)
		if route_clearance < BODY_CLEARANCE:
			score -= 900000000000.0 + (BODY_CLEARANCE - route_clearance) * 1000000.0
		var anchor_weight := 0.055 if recalling else 0.028
		score -= endpoint.distance_squared_to(anchor) * anchor_weight
		if preferred.length_squared() > 0.0001:
			score += direction.dot(preferred) * (190.0 if recalling else 80.0)
		if direction == Vector2.ZERO:
			score -= 12.0
		var clearance := INF
		if include_bullet_risk:
			var bullet_score := _projected_bullet_score(
				body_center(),
				direction * speed,
				movement_context
			)
			score += float(bullet_score.get("score", 0.0))
			clearance = float(bullet_score.get("min_clearance", INF))
		if score > best_score + 0.001:
			best_score = score
			best_direction = direction
			best_clearance = clearance
	_last_min_clearance = best_clearance
	return best_direction


func _static_position_score(
	position: Vector2,
	leader_position: Vector2,
	movement_context: Dictionary,
	world_rect: Rect2
) -> float:
	var world_clearance := _world_clearance(position, world_rect)
	if world_clearance < WORLD_MARGIN:
		return -1000000000000.0 - (WORLD_MARGIN - world_clearance) * 1000000.0
	var blocker_clearance := _blocker_clearance(position, movement_context)
	if blocker_clearance < BODY_CLEARANCE:
		return -900000000000.0 - (BODY_CLEARANCE - blocker_clearance) * 1000000.0
	var leader_distance := position.distance_to(leader_position)
	if leader_distance > MAX_ROAM_DISTANCE:
		return -800000000000.0 - (leader_distance - MAX_ROAM_DISTANCE) * 1000000.0
	var score := minf(world_clearance, 120.0) * 0.8 + minf(blocker_clearance, 120.0) * 1.2
	if leader_distance < MIN_LEADER_SEPARATION:
		score -= (MIN_LEADER_SEPARATION - leader_distance) * 12.0
	return score


func _most_urgent_threat(
	origin: Vector2,
	candidate_velocity: Vector2,
	movement_context: Dictionary
) -> Dictionary:
	var best_urgency := 0.0
	var best_clearance := INF
	var best_velocity := Vector2.ZERO
	var active := false
	var rows: Variant = movement_context.get("bullets", [])
	if not rows is Array:
		return {
			"active": false,
			"urgency": 0.0,
			"min_clearance": INF,
			"velocity": Vector2.ZERO,
		}
	for row_variant in rows:
		if not row_variant is Dictionary:
			continue
		var row := row_variant as Dictionary
		var bullet_velocity: Vector2 = row.get("velocity", Vector2.ZERO)
		if bullet_velocity.length_squared() <= 0.0001:
			continue
		var relative_position: Vector2 = row.get("position", Vector2.ZERO) - origin
		var relative_velocity := bullet_velocity - candidate_velocity
		var speed_squared := relative_velocity.length_squared()
		if speed_squared <= 0.0001 or relative_position.dot(relative_velocity) >= 0.0:
			continue
		var closest_time := clampf(
			-relative_position.dot(relative_velocity) / speed_squared,
			0.0,
			PREDICTION_HORIZON
		)
		var center_distance := (relative_position + relative_velocity * closest_time).length()
		var bullet_radius := maxf(float(row.get("radius", 0.0)), 0.0)
		var clearance := center_distance - bullet_radius
		best_clearance = minf(best_clearance, clearance)
		if clearance >= SAFE_CENTER_DISTANCE:
			continue
		var proximity := 1.0 - maxf(clearance, 0.0) / SAFE_CENTER_DISTANCE
		var time_urgency := 1.0 - closest_time / PREDICTION_HORIZON
		var urgency := proximity * 0.55 + time_urgency * 0.45
		if not active or urgency > best_urgency:
			active = true
			best_urgency = urgency
			best_velocity = bullet_velocity
	return {
		"active": active,
		"urgency": best_urgency,
		"min_clearance": best_clearance,
		"velocity": best_velocity,
	}


func _projected_bullet_score(
	origin: Vector2,
	candidate_velocity: Vector2,
	movement_context: Dictionary
) -> Dictionary:
	var score := 0.0
	var min_clearance := INF
	var rows: Variant = movement_context.get("bullets", [])
	if not rows is Array:
		return {"score": score, "min_clearance": min_clearance}
	for row_variant in rows:
		if not row_variant is Dictionary:
			continue
		var row := row_variant as Dictionary
		var bullet_velocity: Vector2 = row.get("velocity", Vector2.ZERO)
		if bullet_velocity.length_squared() <= 0.0001:
			continue
		var relative_position: Vector2 = row.get("position", Vector2.ZERO) - origin
		var relative_velocity := bullet_velocity - candidate_velocity
		var speed_squared := relative_velocity.length_squared()
		if speed_squared <= 0.0001:
			continue
		var closest_time := clampf(
			-relative_position.dot(relative_velocity) / speed_squared,
			0.0,
			PREDICTION_HORIZON
		)
		var center_distance := (relative_position + relative_velocity * closest_time).length()
		var bullet_radius := maxf(float(row.get("radius", 0.0)), 0.0)
		var clearance := center_distance - bullet_radius
		min_clearance = minf(min_clearance, clearance)
		if clearance < SAFE_CENTER_DISTANCE:
			var deficit := SAFE_CENTER_DISTANCE - clearance
			var time_weight := 1.0 + (PREDICTION_HORIZON - closest_time) * 5.0
			score -= deficit * deficit * 90.0 * time_weight
		elif clearance < SAFE_CENTER_DISTANCE * 1.6:
			score += (clearance - SAFE_CENTER_DISTANCE) * 2.0
	return {"score": score, "min_clearance": min_clearance}


func _best_safe_position(
	leader_position: Vector2,
	radius: float,
	movement_context: Dictionary,
	world_rect: Rect2
) -> Vector2:
	var best_position := _clamp_to_world(leader_position + Vector2.DOWN * radius, world_rect)
	var best_score := -INF
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var candidate := _clamp_to_world(
			leader_position + Vector2(cos(angle), sin(angle)) * radius,
			world_rect
		)
		var world_clearance := _world_clearance(candidate, world_rect)
		var blocker_clearance := _blocker_clearance(candidate, movement_context)
		var legal_bonus := 100000.0 if (
			world_clearance >= WORLD_MARGIN and blocker_clearance >= BODY_CLEARANCE
		) else 0.0
		var score := legal_bonus + minf(world_clearance, blocker_clearance)
		if score > best_score:
			best_score = score
			best_position = candidate
	return best_position


func _blocker_clearance(position: Vector2, movement_context: Dictionary) -> float:
	var clearance := INF
	var rows: Variant = movement_context.get("blockers", [])
	if not rows is Array:
		return clearance
	for row_variant in rows:
		if not row_variant is Dictionary:
			continue
		var row := row_variant as Dictionary
		var blocker_position: Vector2 = row.get("position", Vector2.ZERO)
		var blocker_radius := maxf(float(row.get("radius", 0.0)), 0.0)
		clearance = minf(clearance, position.distance_to(blocker_position) - blocker_radius)
	return clearance


func _blocker_path_clearance(
	start: Vector2,
	finish: Vector2,
	movement_context: Dictionary
) -> float:
	var clearance := INF
	var segment := finish - start
	var segment_length_squared := segment.length_squared()
	var rows: Variant = movement_context.get("blockers", [])
	if not rows is Array:
		return clearance
	for row_variant in rows:
		if not row_variant is Dictionary:
			continue
		var row := row_variant as Dictionary
		var blocker_position: Vector2 = row.get("position", Vector2.ZERO)
		var closest := start
		if segment_length_squared > 0.0001:
			var projection := clampf(
				(blocker_position - start).dot(segment) / segment_length_squared,
				0.0,
				1.0
			)
			closest = start + segment * projection
		var blocker_radius := maxf(float(row.get("radius", 0.0)), 0.0)
		clearance = minf(clearance, closest.distance_to(blocker_position) - blocker_radius)
	return clearance


func _world_clearance(position: Vector2, world_rect: Rect2) -> float:
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return INF
	return minf(
		minf(position.x - world_rect.position.x, world_rect.end.x - position.x),
		minf(position.y - world_rect.position.y, world_rect.end.y - position.y)
	)


func _clamp_to_world(position: Vector2, world_rect: Rect2) -> Vector2:
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return position
	return Vector2(
		clampf(
			position.x,
			world_rect.position.x + WORLD_MARGIN,
			world_rect.end.x - WORLD_MARGIN
		),
		clampf(
			position.y,
			world_rect.position.y + WORLD_MARGIN,
			world_rect.end.y - WORLD_MARGIN
		)
	)


func _enter_mode(mode: int) -> void:
	if _movement_mode == mode:
		return
	_movement_mode = mode
	_apply_mode_speed()


func _apply_mode_speed() -> void:
	var scale := NORMAL_SPEED_SCALE
	match _movement_mode:
		MovementMode.DODGE:
			scale = DODGE_SPEED_SCALE
		MovementMode.RECALL:
			scale = RECALL_SPEED_SCALE
		MovementMode.MERGED:
			scale = NORMAL_SPEED_SCALE
	set_move_speed(_base_move_speed * scale)


func _apply_smoothed_input(delta: float) -> void:
	var response := INPUT_RESPONSE_TACTICAL
	match _movement_mode:
		MovementMode.DODGE:
			response = INPUT_RESPONSE_DODGE
		MovementMode.RECALL:
			response = INPUT_RESPONSE_RECALL
	var blend := 1.0 - exp(-response * maxf(delta, 0.0))
	_smoothed_move = _smoothed_move.lerp(_desired_move, blend)
	if _smoothed_move.length_squared() < 0.0025:
		_smoothed_move = Vector2.ZERO
	set_input_vector(_smoothed_move.limit_length(1.0))
