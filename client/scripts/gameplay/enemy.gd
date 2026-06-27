# Doc: docs/代码/enemy_ai.md
# Authority: docs/游戏设计文档.md §5.3, docs/词表与契约.md §12-B
class_name Enemy
extends Node2D


signal defeated(enemy: Node, exp_reward: int)

const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const ENEMY_AI_ACTIONS := preload("res://scripts/contracts/enemy_ai_actions.gd")
const STATUS_EFFECT_COMPONENT_SCRIPT := preload("res://scripts/combat/status_effect_component.gd")

const ACTION_STATE_CHARGE_RELEASE: String = "charge_release"
const ACTION_STATE_CHARGE_WINDUP: String = "charge_windup"
const DEFEAT_FEEDBACK_DURATION: float = 0.18
const DEFEAT_FEEDBACK_COLOR: Color = Color(1.0, 0.62, 0.22)
const EYE_OUTLINE_SCALE: float = 1.65
const HIT_FLASH_DURATION: float = 0.16
const HIT_FLASH_COLOR: Color = Color(1.0, 0.96, 0.74)
const PLACEHOLDER_OUTLINE_COLOR: Color = Color(0.07, 0.06, 0.05, 0.88)
const PLACEHOLDER_OUTLINE_SCALE: float = 1.14
const SCORE_EPSILON: float = 0.001
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

var _actions: Array[Dictionary] = []
var _action_state: String = ""
var _action_timer: float = 0.0
var _ai_profile: Dictionary = {}
var _ai_profile_id: String = ""
var _charge_cooldown_remaining: float = 0.0
var _charge_direction: Vector2 = Vector2.ZERO
var _contact_cooldowns: Dictionary = {}
var _contact_damage: float = 0.0
var _contact_damage_type: String = ""
var _current_action: String = ""
var _decision_remaining: float = 0.0
var _defeat_feedback_remaining: float = 0.0
var _enemy_id: String = ""
var _exp_reward: int = 0
var _facing_sign: float = 1.0
var _focus_target: Node2D = null
var _hit_flash_remaining: float = 0.0
var _hit_radius: float = 0.0
var _home_position: Vector2 = Vector2.ZERO
var _last_damage_source_team: String = ""
var _last_scores: Dictionary = {}
var _life_points: float = 1.0
var _max_life: float = 1.0
var _has_movement_bounds: bool = false
var _movement_bounds: Rect2 = Rect2()
var _move_speed: float = 0.0
var _owned_tag_counts: Dictionary = {}
var _player_target: Node2D = null
var _separation_radius: float = 0.0
var _status_effect_component: Node = null
var _tags: Array[String] = []
var _visual_color: Color = Color(1.0, 0.38, 0.32)


func _physics_process(delta: float) -> void:
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if _defeat_feedback_remaining > 0.0:
		_update_defeat_feedback(scaled_delta)
		return
	if _player_target == null or not is_instance_valid(_player_target):
		return
	if not GameState.is_state(GameState.PLAYING):
		return
	if scaled_delta <= 0.0:
		return

	_update_hit_flash(scaled_delta)
	_update_ai_timers(scaled_delta)

	if _is_charge_state_active():
		_update_charge_state(scaled_delta)
	else:
		_decision_remaining -= scaled_delta
		if _current_action.is_empty() or _decision_remaining <= 0.0:
			_choose_action()
		_apply_current_action(scaled_delta)

	_apply_center_separation()
	_check_contact()


func configure(enemy_data: Dictionary, target: Node2D) -> void:
	_defeat_feedback_remaining = 0.0
	_clear_status_effects_for_reuse()
	_player_target = target
	_focus_target = target
	_home_position = global_position
	_enemy_id = String(enemy_data.get("id", ""))
	_tags = _string_array(enemy_data.get("tags", []))
	_ai_profile_id = String(enemy_data.get("ai_profile_id", ""))
	_ai_profile = _dictionary_or_empty(enemy_data.get("ai_profile", {}))
	_actions = _typed_action_array(_ai_profile.get("actions", []))
	if _actions.is_empty():
		_actions.append({
			"id": ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
			"base_score": 1.0,
			"speed_scale": 1.0,
		})
	_current_action = ""
	_action_state = ""
	_action_timer = 0.0
	_charge_cooldown_remaining = 0.0
	_charge_direction = Vector2.ZERO
	_contact_cooldowns.clear()
	_last_damage_source_team = ""
	_last_scores.clear()
	_decision_remaining = 0.0
	_max_life = float(enemy_data.get("max_hp", 1))
	_life_points = _max_life
	_move_speed = float(enemy_data.get("move_speed", 0.0))
	_contact_damage = float(enemy_data.get("contact_damage", 0))
	_contact_damage_type = String(enemy_data.get("contact_damage_type", ""))
	_exp_reward = int(enemy_data.get("exp_reward", 0))
	_hit_radius = float(enemy_data.get("hit_radius", 0.0))
	_separation_radius = float(enemy_data.get("separation_radius", 0.0))
	_visual_color = _parse_visual_color(String(enemy_data.get("visual_color", "#ff6152")))
	if _player_target != null and is_instance_valid(_player_target):
		_update_facing(_player_target.global_position - global_position)
	_home_position = _clamp_to_movement_bounds(_home_position)
	_apply_movement_bounds()
	add_to_group("active_enemies")
	queue_redraw()


func hit_radius() -> float:
	return _hit_radius


func separation_radius() -> float:
	return _separation_radius


func visual_color() -> Color:
	return _visual_color


func content_tags() -> Array[String]:
	return _tags.duplicate()


func ai_debug_summary() -> Dictionary:
	return {
		"profile_id": _ai_profile_id,
		"action": _current_action,
		"action_state": _action_state,
		"focus_target": _focus_target.name if _focus_target != null and is_instance_valid(_focus_target) else "",
		"scores": _last_scores.duplicate(true),
	}


func is_alive() -> bool:
	return _life_points > 0.0 and _defeat_feedback_remaining <= 0.0


func enemy_id() -> String:
	return _enemy_id


func is_defeat_feedback_active() -> bool:
	return _defeat_feedback_remaining > 0.0


func was_defeated_by_player() -> bool:
	return _last_damage_source_team == TEAM_PLAYER


func combat_team_id() -> String:
	return TEAM_ENEMY


func add_owned_tag(tag_id: String) -> bool:
	return _add_owned_tag_count(tag_id)


func remove_owned_tag(tag_id: String) -> bool:
	return _remove_owned_tag_count(tag_id)


func has_owned_tag(tag_id: String) -> bool:
	return int(_owned_tag_counts.get(tag_id, 0)) > 0


func owned_tags() -> Array[String]:
	return _sorted_string_keys(_owned_tag_counts)


func apply_status_effect(status_effect: Variant) -> Dictionary:
	_ensure_status_effect_component()
	if _status_effect_component == null:
		return {
			"applied": false,
			"reason": "status_component_unavailable",
		}
	return _status_effect_component.call("apply", status_effect) as Dictionary


func active_statuses() -> Array[String]:
	_ensure_status_effect_component()
	if _status_effect_component == null:
		return []
	return _status_effect_component.call("active_statuses") as Array[String]


func set_movement_bounds(bounds: Rect2) -> void:
	_movement_bounds = bounds
	_has_movement_bounds = bounds.size.x > 0.0 and bounds.size.y > 0.0
	_home_position = _clamp_to_movement_bounds(_home_position)
	_apply_movement_bounds()


func clear_movement_bounds() -> void:
	_has_movement_bounds = false
	_movement_bounds = Rect2()


func receive_damage(info: RefCounted) -> Dictionary:
	if not is_alive():
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": true,
			"reason": "defeated",
		}

	_last_damage_source_team = String(info.get("source_team"))
	var amount: float = float(info.get("amount"))
	var applied_amount: float = minf(amount, _life_points)
	_life_points = maxf(_life_points - amount, 0.0)
	var is_defeated: bool = _life_points <= 0.0
	if is_defeated:
		remove_from_group("active_enemies")
		_defeat_feedback_remaining = DEFEAT_FEEDBACK_DURATION
		defeated.emit(self, _exp_reward)
		queue_redraw()
	else:
		_start_hit_flash()
	return {
		"applied": true,
		"amount": applied_amount,
		"defeated": is_defeated,
		"reason": "applied",
	}


func snapshot() -> Dictionary:
	return {
		"enemy_id": _enemy_id,
		"position": _vector_to_dict(global_position),
		"life_points": _life_points,
		"home_position": _vector_to_dict(_home_position),
		"current_action": _current_action,
		"action_state": _action_state,
		"action_timer": _action_timer,
		"charge_cooldown_remaining": _charge_cooldown_remaining,
		"charge_direction": _vector_to_dict(_charge_direction),
		"last_damage_source_team": _last_damage_source_team,
		"owned_tag_counts": _owned_tag_counts.duplicate(true),
		"status_effects": _status_effect_snapshot(),
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_ensure_status_effect_component()
	if _status_effect_component != null:
		_status_effect_component.call("clear", false)
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_home_position = _dict_to_vector(snapshot_data.get("home_position", {}), global_position)
	_home_position = _clamp_to_movement_bounds(_home_position)
	_apply_movement_bounds()
	_life_points = clampf(float(snapshot_data.get("life_points", _max_life)), 0.0, _max_life)
	_current_action = String(snapshot_data.get("current_action", ""))
	_action_state = String(snapshot_data.get("action_state", ""))
	_action_timer = maxf(float(snapshot_data.get("action_timer", 0.0)), 0.0)
	_charge_cooldown_remaining = maxf(float(snapshot_data.get("charge_cooldown_remaining", 0.0)), 0.0)
	_charge_direction = _dict_to_vector(snapshot_data.get("charge_direction", {}), Vector2.ZERO)
	_last_damage_source_team = String(snapshot_data.get("last_damage_source_team", ""))
	_restore_status_snapshot(snapshot_data)
	if _life_points <= 0.0:
		remove_from_group("active_enemies")
	queue_redraw()


func _pool_reset() -> void:
	_actions.clear()
	_action_state = ""
	_action_timer = 0.0
	_ai_profile.clear()
	_ai_profile_id = ""
	_charge_cooldown_remaining = 0.0
	_charge_direction = Vector2.ZERO
	_contact_cooldowns.clear()
	_contact_damage = 0.0
	_contact_damage_type = ""
	_current_action = ""
	_decision_remaining = 0.0
	_defeat_feedback_remaining = 0.0
	_enemy_id = ""
	_exp_reward = 0
	_facing_sign = 1.0
	_focus_target = null
	_hit_flash_remaining = 0.0
	_hit_radius = 0.0
	_home_position = Vector2.ZERO
	_last_damage_source_team = ""
	_last_scores.clear()
	_life_points = 1.0
	_max_life = 1.0
	clear_movement_bounds()
	_move_speed = 0.0
	_clear_status_effects_for_reuse()
	_player_target = null
	_separation_radius = 0.0
	_tags.clear()
	_visual_color = Color(1.0, 0.38, 0.32)
	visible = true


func _pool_release() -> void:
	remove_from_group("active_enemies")
	_defeat_feedback_remaining = 0.0
	_clear_status_effects_for_reuse()
	clear_movement_bounds()
	_focus_target = null
	_player_target = null


func _draw() -> void:
	var radius: float = maxf(_hit_radius, 8.0)
	var color: Color = _enemy_color()
	var visual_radius: float = radius * _defeat_scale()
	var nose: Vector2 = Vector2(visual_radius * _facing_sign, 0.0)
	var tail_x: float = -visual_radius * 0.75 * _facing_sign
	var points: PackedVector2Array = PackedVector2Array([
		nose,
		Vector2(tail_x, -visual_radius * 0.85),
		Vector2(tail_x, visual_radius * 0.85),
	])
	var outline_color: Color = _outline_color(color)
	draw_colored_polygon(_scaled_points(points, PLACEHOLDER_OUTLINE_SCALE), outline_color)
	draw_colored_polygon(points, color)
	var eye_radius: float = maxf(2.0, visual_radius * 0.12)
	var eye_position: Vector2 = Vector2(visual_radius * 0.35 * _facing_sign, -visual_radius * 0.2)
	draw_circle(eye_position, eye_radius * EYE_OUTLINE_SCALE, outline_color)
	draw_circle(eye_position, eye_radius, Color.WHITE)


func _choose_action() -> void:
	var context: Dictionary = _sense_context()
	var best_action: String = ""
	var best_target: Node2D = null
	var best_score: float = -1.0
	_last_scores.clear()
	for action: Dictionary in _actions:
		var candidate: Dictionary = _action_candidate(action, context)
		var action_id: String = String(action.get("id", ""))
		var score: float = float(candidate.get("score", 0.0))
		_last_scores[action_id] = score
		if score > best_score + SCORE_EPSILON:
			best_action = action_id
			best_target = candidate.get("target") as Node2D
			best_score = score
	_current_action = best_action
	_focus_target = best_target
	_decision_remaining = _decision_interval()


func _sense_context() -> Dictionary:
	var player_candidate: Dictionary = _player_candidate()
	var target_candidate: Dictionary = player_candidate.duplicate()
	var hunt_candidate: Dictionary = _tagged_candidate(_targeting_array("hunt_tags"))
	if float(hunt_candidate.get("score", 0.0)) > float(target_candidate.get("score", 0.0)) + SCORE_EPSILON:
		target_candidate = hunt_candidate
	var threat_candidate: Dictionary = _tagged_candidate(_targeting_array("flee_tags"))
	return {
		"target": target_candidate.get("target"),
		"target_score": float(target_candidate.get("score", 0.0)),
		"target_distance": float(target_candidate.get("distance", 0.0)),
		"threat": threat_candidate.get("target"),
		"threat_score": float(threat_candidate.get("score", 0.0)),
		"threat_distance": float(threat_candidate.get("distance", 0.0)),
	}


func _player_candidate() -> Dictionary:
	if _player_target == null or not is_instance_valid(_player_target):
		return _empty_candidate()
	var distance: float = global_position.distance_to(_player_target.global_position)
	var weight: float = _player_weight()
	if weight <= 0.0 or distance > _sense_radius():
		return _empty_candidate()
	return {
		"target": _player_target,
		"score": weight * _proximity_score(distance, _sense_radius()),
		"distance": distance,
	}


func _tagged_candidate(entries: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = _empty_candidate()
	if entries.is_empty():
		return best
	for raw_enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if raw_enemy == self or not raw_enemy is Node2D or not raw_enemy.has_method("is_alive"):
			continue
		if not bool(raw_enemy.call("is_alive")):
			continue
		var enemy: Node2D = raw_enemy as Node2D
		var weight: float = _matching_tag_weight(raw_enemy, entries)
		if weight <= 0.0:
			continue
		var distance: float = global_position.distance_to(enemy.global_position)
		if distance > _sense_radius():
			continue
		var score: float = weight * _proximity_score(distance, _sense_radius())
		if score > float(best.get("score", 0.0)) + SCORE_EPSILON:
			best = {
				"target": enemy,
				"score": score,
				"distance": distance,
			}
	return best


func _matching_tag_weight(candidate: Node, entries: Array[Dictionary]) -> float:
	if not candidate.has_method("content_tags"):
		return 0.0
	var candidate_tags: Array[String] = candidate.call("content_tags")
	var result: float = 0.0
	for entry: Dictionary in entries:
		var tag: String = String(entry.get("tag", ""))
		if candidate_tags.has(tag):
			result = maxf(result, float(entry.get("weight", 0.0)))
	return result


func _action_candidate(action: Dictionary, context: Dictionary) -> Dictionary:
	var action_id: String = String(action.get("id", ""))
	var base_score: float = float(action.get("base_score", 0.0))
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_FLEE_THREAT:
		return _flee_candidate(base_score, context)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET:
		return _charge_candidate(base_score, context)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_ORBIT_TARGET:
		return _orbit_candidate(base_score, context)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME:
		return _guard_candidate(base_score)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET:
		return _candidate(base_score + float(context.get("target_score", 0.0)), context.get("target"))
	return _candidate(0.0, null)


func _flee_candidate(base_score: float, context: Dictionary) -> Dictionary:
	var threat: Node2D = context.get("threat") as Node2D
	if threat == null or not is_instance_valid(threat):
		return _candidate(0.0, null)
	var distance: float = float(context.get("threat_distance", global_position.distance_to(threat.global_position)))
	var flee_distance: float = _movement_value("flee_distance")
	if flee_distance > 0.0 and distance > flee_distance:
		return _candidate(0.0, null)
	var distance_score: float = _proximity_score(distance, flee_distance if flee_distance > 0.0 else _sense_radius())
	return _candidate(base_score + float(context.get("threat_score", 0.0)) + distance_score, threat)


func _charge_candidate(base_score: float, context: Dictionary) -> Dictionary:
	if _charge_cooldown_remaining > 0.0:
		return _candidate(0.0, null)
	var target: Node2D = context.get("target") as Node2D
	if target == null or not is_instance_valid(target):
		return _candidate(0.0, null)
	var distance: float = float(context.get("target_distance", global_position.distance_to(target.global_position)))
	var charge_range: float = _movement_value("charge_range")
	if charge_range <= 0.0 or distance > charge_range:
		return _candidate(0.0, null)
	var range_score: float = _proximity_score(distance, charge_range)
	return _candidate(base_score + float(context.get("target_score", 0.0)) + range_score, target)


func _orbit_candidate(base_score: float, context: Dictionary) -> Dictionary:
	var target: Node2D = context.get("target") as Node2D
	if target == null or not is_instance_valid(target):
		return _candidate(0.0, null)
	var distance: float = float(context.get("target_distance", global_position.distance_to(target.global_position)))
	var orbit_radius: float = maxf(_movement_value("orbit_radius"), 1.0)
	var radius_score: float = 1.0 - clampf(absf(distance - orbit_radius) / orbit_radius, 0.0, 1.0)
	return _candidate(base_score + float(context.get("target_score", 0.0)) + radius_score, target)


func _guard_candidate(base_score: float) -> Dictionary:
	var territory_radius: float = _territory_radius()
	var distance: float = global_position.distance_to(_home_position)
	if territory_radius <= 0.0 or distance <= territory_radius:
		return _candidate(base_score, null)
	var over_distance: float = (distance - territory_radius) / territory_radius
	return _candidate(base_score + over_distance * _territory_weight(), null)


func _candidate(score: float, raw_target: Variant) -> Dictionary:
	return {
		"score": maxf(score, 0.0),
		"target": raw_target if raw_target is Node2D else null,
	}


func _empty_candidate() -> Dictionary:
	return {
		"target": null,
		"score": 0.0,
		"distance": 0.0,
	}


func _apply_current_action(delta: float) -> void:
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_FLEE_THREAT:
		_move_in_direction(_flee_direction(), _action_speed_scale(_current_action), delta)
		return
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_ORBIT_TARGET:
		_move_in_direction(_orbit_direction(), _action_speed_scale(_current_action), delta)
		return
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET:
		_start_charge()
		return
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME:
		_move_in_direction(_home_position - global_position, _action_speed_scale(_current_action), delta)
		return
	_move_in_direction(_target_direction(), _action_speed_scale(_current_action), delta)


func _start_charge() -> void:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return
	_charge_direction = (_focus_target.global_position - global_position).normalized()
	if _charge_direction.length_squared() <= 0.0:
		return
	var windup: float = _movement_value("charge_windup")
	if windup > 0.0:
		_action_state = ACTION_STATE_CHARGE_WINDUP
		_action_timer = windup
	else:
		_action_state = ACTION_STATE_CHARGE_RELEASE
		_action_timer = _movement_value("charge_duration")


func _update_charge_state(delta: float) -> void:
	_action_timer = maxf(_action_timer - delta, 0.0)
	if _action_state == ACTION_STATE_CHARGE_WINDUP:
		if _action_timer <= 0.0:
			_action_state = ACTION_STATE_CHARGE_RELEASE
			_action_timer = _movement_value("charge_duration")
		return
	if _action_state == ACTION_STATE_CHARGE_RELEASE:
		_move_in_direction(_charge_direction, _movement_value("charge_speed_scale"), delta)
		if _action_timer <= 0.0:
			_action_state = ""
			_current_action = ""
			_charge_cooldown_remaining = _movement_value("charge_cooldown")


func _move_in_direction(direction: Vector2, speed_scale: float, delta: float) -> void:
	if direction.length_squared() <= 0.0:
		return
	var normalized: Vector2 = direction.normalized()
	_update_facing(normalized)
	global_position += normalized * _move_speed * maxf(speed_scale, 0.0) * delta
	_apply_movement_bounds()


func _target_direction() -> Vector2:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return Vector2.ZERO
	return _focus_target.global_position - global_position


func _flee_direction() -> Vector2:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return Vector2.ZERO
	return global_position - _focus_target.global_position


func _orbit_direction() -> Vector2:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return Vector2.ZERO
	var from_target: Vector2 = global_position - _focus_target.global_position
	if from_target.length_squared() <= 0.0:
		from_target = Vector2.RIGHT
	var radial: Vector2 = from_target.normalized()
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * _orbit_sign()
	var orbit_radius: float = maxf(_movement_value("orbit_radius"), 1.0)
	var distance: float = global_position.distance_to(_focus_target.global_position)
	if distance > orbit_radius:
		return (_focus_target.global_position - global_position).normalized() + tangent * 0.7
	return radial + tangent * 0.85


func _update_ai_timers(delta: float) -> void:
	_charge_cooldown_remaining = maxf(_charge_cooldown_remaining - delta, 0.0)
	var cooldown_keys: Array = _contact_cooldowns.keys()
	for key: Variant in cooldown_keys:
		var remaining: float = maxf(float(_contact_cooldowns[key]) - delta, 0.0)
		if remaining <= 0.0:
			_contact_cooldowns.erase(key)
		else:
			_contact_cooldowns[key] = remaining


func _is_charge_state_active() -> bool:
	return _action_state == ACTION_STATE_CHARGE_WINDUP or _action_state == ACTION_STATE_CHARGE_RELEASE


func _start_hit_flash() -> void:
	_hit_flash_remaining = HIT_FLASH_DURATION
	queue_redraw()


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_remaining <= 0.0:
		return
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	queue_redraw()


func _update_defeat_feedback(delta: float) -> void:
	_defeat_feedback_remaining = maxf(_defeat_feedback_remaining - delta, 0.0)
	if _defeat_feedback_remaining <= 0.0:
		PoolManager.release(self)
		return
	queue_redraw()


func _update_facing(direction: Vector2) -> void:
	var previous_sign: float = _facing_sign
	if direction.x > 0.01:
		_facing_sign = 1.0
	elif direction.x < -0.01:
		_facing_sign = -1.0
	if not is_equal_approx(previous_sign, _facing_sign):
		queue_redraw()


func _enemy_color() -> Color:
	if _defeat_feedback_remaining > 0.0:
		var remaining_ratio: float = _defeat_feedback_remaining / DEFEAT_FEEDBACK_DURATION
		var result: Color = DEFEAT_FEEDBACK_COLOR
		result.a = remaining_ratio
		return result
	if _hit_flash_remaining > 0.0:
		return HIT_FLASH_COLOR
	return _visual_color


func _outline_color(fill_color: Color) -> Color:
	var result: Color = PLACEHOLDER_OUTLINE_COLOR
	result.a *= fill_color.a
	return result


func _scaled_points(points: PackedVector2Array, scale: float) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		result.append(point * scale)
	return result


func _defeat_scale() -> float:
	if _defeat_feedback_remaining <= 0.0:
		return 1.0
	var elapsed_ratio: float = 1.0 - (_defeat_feedback_remaining / DEFEAT_FEEDBACK_DURATION)
	return lerpf(1.0, 1.35, elapsed_ratio)


func _check_contact() -> void:
	var contact_target: Node2D = _contact_target()
	if contact_target == null or not is_instance_valid(contact_target):
		return
	if contact_target.has_method("is_alive") and not bool(contact_target.call("is_alive")):
		return
	var distance: float = global_position.distance_to(contact_target.global_position)
	if distance > _contact_distance(contact_target):
		return
	if contact_target != _player_target and _is_contact_on_cooldown(contact_target):
		return

	var target_team: String = TEAM_PLAYER if contact_target == _player_target else TEAM_ENEMY
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(_contact_damage, _contact_damage_type, self, contact_target, TEAM_ENEMY, target_team)
	var result: Dictionary = Combat.apply_damage(contact_target, info)
	if contact_target != _player_target and bool(result.get("applied", false)):
		_contact_cooldowns[contact_target.get_instance_id()] = _contact_interval()


func _contact_target() -> Node2D:
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_FLEE_THREAT:
		return null
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME and _focus_target == null:
		return null
	if _focus_target != null and is_instance_valid(_focus_target):
		return _focus_target
	if _player_target != null and is_instance_valid(_player_target):
		return _player_target
	return null


func _contact_distance(target: Node2D) -> float:
	var distance: float = _hit_radius
	if target.has_method("separation_radius"):
		distance = maxf(distance, _separation_radius + float(target.call("separation_radius")))
	return distance


func _is_contact_on_cooldown(target: Node2D) -> bool:
	var instance_id: int = target.get_instance_id()
	return _contact_cooldowns.has(instance_id) and float(_contact_cooldowns[instance_id]) > 0.0


func _apply_center_separation() -> void:
	var offset: Vector2 = Vector2.ZERO
	if _separation_radius > 0.0:
		for other: Node in get_tree().get_nodes_in_group("active_enemies"):
			offset += _enemy_separation_offset(other)
	offset += _target_separation_offset()

	if offset.length_squared() > 0.0:
		global_position += offset
		_apply_movement_bounds()


func _enemy_separation_offset(other: Node) -> Vector2:
	if other == self or not other is Node2D or not other.has_method("separation_radius"):
		return Vector2.ZERO
	if other.has_method("is_alive") and not bool(other.call("is_alive")):
		return Vector2.ZERO

	var other_enemy: Node2D = other as Node2D
	var minimum_distance: float = _separation_radius + float(other.call("separation_radius"))
	return _separation_offset_from(other_enemy.global_position, minimum_distance, 0.5)


func _target_separation_offset() -> Vector2:
	if _player_target == null or not is_instance_valid(_player_target) or not _player_target.has_method("separation_radius"):
		return Vector2.ZERO

	var target_separation_radius: float = float(_player_target.call("separation_radius"))
	var minimum_distance: float = _separation_radius + target_separation_radius
	return _separation_offset_from(_player_target.global_position, minimum_distance, 1.0)


func _separation_offset_from(other_position: Vector2, minimum_distance: float, strength: float) -> Vector2:
	if minimum_distance <= 0.0:
		return Vector2.ZERO

	var to_self: Vector2 = global_position - other_position
	var current_distance: float = to_self.length()
	if current_distance >= minimum_distance:
		return Vector2.ZERO

	var direction: Vector2 = _separation_direction(to_self)
	return direction * (minimum_distance - current_distance) * strength


func _separation_direction(to_self: Vector2) -> Vector2:
	if to_self.length_squared() > 0.0:
		return to_self.normalized()
	var angle: float = float(int(get_instance_id()) % 360) * TAU / 360.0
	return Vector2.RIGHT.rotated(angle)


func _targeting() -> Dictionary:
	return _dictionary_or_empty(_ai_profile.get("targeting", {}))


func _movement() -> Dictionary:
	return _dictionary_or_empty(_ai_profile.get("movement", {}))


func _targeting_array(key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_entries: Array = _array_or_empty(_targeting().get(key, []))
	for entry: Variant in raw_entries:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


func _movement_value(key: String) -> float:
	return float(_movement().get(key, 0.0))


func _player_weight() -> float:
	return float(_targeting().get("player_weight", 1.0))


func _territory_radius() -> float:
	return float(_targeting().get("territory_radius", 0.0))


func _territory_weight() -> float:
	return float(_targeting().get("territory_weight", 0.0))


func _sense_radius() -> float:
	return maxf(float(_ai_profile.get("sense_radius", 640.0)), 1.0)


func _decision_interval() -> float:
	return maxf(float(_ai_profile.get("decision_interval", 0.12)), 0.01)


func _contact_interval() -> float:
	return maxf(float(_ai_profile.get("contact_interval", 0.45)), 0.0)


func _action_speed_scale(action_id: String) -> float:
	for action: Dictionary in _actions:
		if String(action.get("id", "")) == action_id:
			return maxf(float(action.get("speed_scale", 1.0)), 0.0)
	return 1.0


func _proximity_score(distance: float, radius: float) -> float:
	return 0.25 + (1.0 - clampf(distance / maxf(radius, 1.0), 0.0, 1.0))


func _orbit_sign() -> float:
	return 1.0 if int(get_instance_id()) % 2 == 0 else -1.0


func _parse_visual_color(color_text: String) -> Color:
	if Color.html_is_valid(color_text):
		return Color.html(color_text)
	return Color(1.0, 0.38, 0.32)


func _typed_action_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_action: Variant in _array_or_empty(raw_value):
		if raw_action is Dictionary:
			result.append((raw_action as Dictionary).duplicate(true))
	return result


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_value is Array:
		for item: Variant in raw_value as Array:
			var text: String = String(item)
			if not text.is_empty():
				result.append(text)
		return result
	if raw_value is String:
		for raw_item: String in String(raw_value).split("|", false):
			var text: String = raw_item.strip_edges()
			if not text.is_empty():
				result.append(text)
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


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


func _apply_movement_bounds() -> void:
	if not _has_movement_bounds:
		return
	global_position = _clamp_to_movement_bounds(global_position)


func _clamp_to_movement_bounds(world_position: Vector2) -> Vector2:
	if not _has_movement_bounds:
		return world_position
	return Vector2(
		clampf(world_position.x, _movement_bounds.position.x, _movement_bounds.end.x),
		clampf(world_position.y, _movement_bounds.position.y, _movement_bounds.end.y)
	)

func _ensure_status_effect_component() -> void:
	if _status_effect_component != null and is_instance_valid(_status_effect_component):
		_status_effect_component.call("configure_ability_tag_owner", self)
		return
	_status_effect_component = get_node_or_null("StatusEffectComponent")
	if _status_effect_component == null:
		_status_effect_component = STATUS_EFFECT_COMPONENT_SCRIPT.new()
		_status_effect_component.name = "StatusEffectComponent"
		add_child(_status_effect_component)
	_status_effect_component.call("configure_ability_tag_owner", self)


func _status_effect_snapshot() -> Dictionary:
	_ensure_status_effect_component()
	if _status_effect_component == null:
		return {}
	return _status_effect_component.call("snapshot") as Dictionary


func _restore_status_snapshot(snapshot_data: Dictionary) -> void:
	_owned_tag_counts.clear()
	var raw_tag_counts: Variant = snapshot_data.get("owned_tag_counts", {})
	var has_owned_tag_snapshot: bool = snapshot_data.has("owned_tag_counts") and raw_tag_counts is Dictionary
	if has_owned_tag_snapshot:
		for tag_id: Variant in (raw_tag_counts as Dictionary).keys():
			var count: int = maxi(int((raw_tag_counts as Dictionary)[tag_id]), 0)
			if count <= 0:
				continue
			var tag: String = String(tag_id)
			if _is_valid_ability_tag(tag):
				_owned_tag_counts[tag] = count
	else:
		var raw_owned_tags: Variant = snapshot_data.get("owned_tags", [])
		has_owned_tag_snapshot = raw_owned_tags is Array
		if raw_owned_tags is Array:
			for tag_id: Variant in raw_owned_tags as Array:
				_add_owned_tag_count(String(tag_id))

	var raw_status_effects: Variant = snapshot_data.get("status_effects", {})
	if _status_effect_component != null and raw_status_effects is Dictionary:
		_status_effect_component.call("restore_snapshot", raw_status_effects, not has_owned_tag_snapshot)


func _clear_status_effects_for_reuse() -> void:
	if _status_effect_component != null and is_instance_valid(_status_effect_component):
		_status_effect_component.call("clear", false)
	_owned_tag_counts.clear()


func _add_owned_tag_count(tag_id: String) -> bool:
	if not _is_valid_ability_tag(tag_id):
		return false
	_owned_tag_counts[tag_id] = int(_owned_tag_counts.get(tag_id, 0)) + 1
	return true


func _remove_owned_tag_count(tag_id: String) -> bool:
	if not _owned_tag_counts.has(tag_id):
		return false
	var next_count: int = int(_owned_tag_counts[tag_id]) - 1
	if next_count <= 0:
		_owned_tag_counts.erase(tag_id)
	else:
		_owned_tag_counts[tag_id] = next_count
	return true


func _is_valid_ability_tag(tag_id: String) -> bool:
	if tag_id.is_empty():
		return false
	return ABILITY_TAGS.VALUES.has(tag_id)


func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source.keys():
		result.append(String(key))
	result.sort()
	return result
