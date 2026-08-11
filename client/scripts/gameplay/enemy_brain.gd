# Doc: docs/代码/enemy_ai.md
# Authority: docs/游戏设计文档.md §5.3, docs/决策记录.md ADR #197
class_name EnemyBrain
extends RefCounted


const ENEMY_AI_ACTIONS := preload("res://scripts/contracts/enemy_ai_actions.gd")

const PERCEPTION_MEMORY: String = "memory"
const PERCEPTION_PATH_AWARE: String = "path_aware"
const PERCEPTION_UNAWARE: String = "unaware"
const PERCEPTION_VISIBLE: String = "visible"
const SCORE_EPSILON: float = 0.001


class SenseInput:
	extends RefCounted

	var self_position: Vector2 = Vector2.ZERO
	var home_position: Vector2 = Vector2.ZERO
	var target_available: bool = false
	var target_position: Vector2 = Vector2.ZERO
	var direct_distance: float = 0.0
	var route_reachable: bool = false
	var path_distance: float = INF
	var has_line_of_sight: bool = false
	var has_clear_corridor: bool = false


class Decision:
	extends RefCounted

	var action_id: String = ""
	var focus_primary_target: bool = false
	var target_position: Vector2 = Vector2.ZERO
	var has_target_position: bool = false
	var score: float = 0.0


class PerceptionContext:
	extends RefCounted

	var target_score: float = 0.0
	var direct_distance: float = 0.0
	var path_distance: float = INF
	var target_position: Vector2 = Vector2.ZERO
	var has_target_position: bool = false
	var currently_perceived: bool = false
	var has_line_of_sight: bool = false
	var focus_primary_target: bool = false
	var has_clear_corridor: bool = false


class Candidate:
	extends RefCounted

	var score: float = 0.0
	var focus_primary_target: bool = false
	var target_position: Vector2 = Vector2.ZERO
	var has_target_position: bool = false


var _actions: Array[Dictionary] = []
var _ai_profile: Dictionary = {}
var _ai_profile_id: String = ""
var _decision_remaining: float = 0.0
var _has_last_known_position: bool = false
var _has_movement_target: bool = false
var _last_known_position: Vector2 = Vector2.ZERO
var _last_scores: Dictionary = {}
var _memory_remaining: float = 0.0
var _movement_target_position: Vector2 = Vector2.ZERO
var _path_distance: float = INF
var _perception_state: String = PERCEPTION_UNAWARE
var _terrain_line_of_sight: bool = false


func configure(profile_id: String, profile: Dictionary) -> void:
	reset()
	_ai_profile_id = profile_id
	_ai_profile = profile.duplicate(true)
	_actions = _typed_action_array(_ai_profile.get("actions", []))
	if _actions.is_empty():
		_actions.append({
			"id": ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
			"base_score": 1.0,
			"speed_scale": 1.0,
		})


func reset() -> void:
	_actions.clear()
	_ai_profile.clear()
	_ai_profile_id = ""
	clear_runtime_state()


func clear_runtime_state() -> void:
	_decision_remaining = 0.0
	_has_last_known_position = false
	_has_movement_target = false
	_last_known_position = Vector2.ZERO
	_last_scores.clear()
	_memory_remaining = 0.0
	_movement_target_position = Vector2.ZERO
	_path_distance = INF
	_perception_state = PERCEPTION_UNAWARE
	_terrain_line_of_sight = false


func advance_memory(delta: float) -> void:
	_memory_remaining = maxf(_memory_remaining - maxf(delta, 0.0), 0.0)


func advance_decision(delta: float) -> void:
	_decision_remaining -= maxf(delta, 0.0)


func request_decision_now() -> void:
	_decision_remaining = 0.0


func is_decision_due() -> bool:
	return _decision_remaining <= 0.0


func decide(input: SenseInput, attack_cooldown: float) -> Decision:
	var context: PerceptionContext = _sense(input)
	var best_candidate: Candidate = Candidate.new()
	var best_action: String = ""
	var best_score: float = -1.0
	_last_scores.clear()
	for action_data: Dictionary in _actions:
		var candidate: Candidate = _action_candidate(
			action_data,
			context,
			input,
			attack_cooldown
		)
		var action_id: String = String(action_data.get("id", ""))
		_last_scores[action_id] = candidate.score
		if candidate.score > best_score + SCORE_EPSILON:
			best_action = action_id
			best_candidate = candidate
			best_score = candidate.score

	_has_movement_target = best_candidate.has_target_position
	_movement_target_position = best_candidate.target_position
	_decision_remaining = _decision_interval()

	var decision: Decision = Decision.new()
	decision.action_id = best_action
	decision.focus_primary_target = best_candidate.focus_primary_target
	decision.target_position = best_candidate.target_position
	decision.has_target_position = best_candidate.has_target_position
	decision.score = maxf(best_score, 0.0)
	return decision


func action(action_id: String) -> Dictionary:
	for action_data: Dictionary in _actions:
		if String(action_data.get("id", "")) == action_id:
			return action_data.duplicate(true)
	return {}


func has_action(action_id: String) -> bool:
	for action_data: Dictionary in _actions:
		if String(action_data.get("id", "")) == action_id:
			return true
	return false


func action_speed_scale(action_id: String) -> float:
	for action_data: Dictionary in _actions:
		if String(action_data.get("id", "")) == action_id:
			return maxf(float(action_data.get("speed_scale", 1.0)), 0.0)
	return 1.0


func initial_attack_cooldown() -> float:
	for action_data: Dictionary in _actions:
		if (
			String(action_data.get("id", ""))
			== ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
		):
			return maxf(
				float(
					_attack_from_action(action_data).get(
						"initial_cooldown",
						0.0
					)
				),
				0.0
			)
	return 0.0


func movement_value(key: String) -> float:
	return float(_movement().get(key, 0.0))


func player_weight() -> float:
	return float(_targeting().get("player_weight", 1.0))


func profile_id() -> String:
	return _ai_profile_id


func perception_state() -> String:
	return _perception_state


func path_distance() -> float:
	return _path_distance


func has_last_known_position() -> bool:
	return _has_last_known_position


func last_known_position() -> Vector2:
	return _last_known_position


func memory_remaining() -> float:
	return _memory_remaining


func has_movement_target() -> bool:
	return _has_movement_target


func movement_target_position() -> Vector2:
	return _movement_target_position


func last_scores() -> Dictionary:
	return _last_scores.duplicate(true)


func debug_state() -> Dictionary:
	return {
		"profile_id": _ai_profile_id,
		"decision_remaining": _decision_remaining,
		"perception_state": _perception_state,
		"path_distance": _path_distance,
		"terrain_line_of_sight": _terrain_line_of_sight,
		"has_last_known_position": _has_last_known_position,
		"last_known_position": _last_known_position,
		"memory_remaining": _memory_remaining,
		"has_movement_target": _has_movement_target,
		"movement_target_position": _movement_target_position,
		"scores": _last_scores.duplicate(true),
	}


func _sense(input: SenseInput) -> PerceptionContext:
	if not input.target_available or player_weight() <= 0.0:
		_set_unaware_perception()
		return PerceptionContext.new()

	_path_distance = input.path_distance if input.route_reachable else INF
	_terrain_line_of_sight = input.has_line_of_sight
	if _terrain_line_of_sight and input.direct_distance <= _sight_radius():
		return _current_target_context(
			PERCEPTION_VISIBLE,
			input,
			_sight_radius(),
			true
		)
	if input.route_reachable and _path_distance <= _path_awareness_radius():
		return _current_target_context(
			PERCEPTION_PATH_AWARE,
			input,
			_path_awareness_radius(),
			false
		)
	if _has_last_known_position and _memory_remaining > 0.0:
		_perception_state = PERCEPTION_MEMORY
		var context: PerceptionContext = PerceptionContext.new()
		var memory_distance: float = input.self_position.distance_to(
			_last_known_position
		)
		context.target_score = player_weight() * _proximity_score(
			memory_distance,
			_sight_radius()
		)
		context.direct_distance = memory_distance
		context.target_position = _last_known_position
		context.has_target_position = true
		return context

	_set_unaware_perception()
	return PerceptionContext.new()


func _current_target_context(
	state: String,
	input: SenseInput,
	score_radius: float,
	has_line_of_sight: bool
) -> PerceptionContext:
	_perception_state = state
	_last_known_position = input.target_position
	_has_last_known_position = true
	_memory_remaining = _memory_duration()
	var score_distance: float = (
		input.direct_distance if has_line_of_sight else input.path_distance
	)
	var context: PerceptionContext = PerceptionContext.new()
	context.target_score = player_weight() * _proximity_score(
		score_distance,
		score_radius
	)
	context.direct_distance = input.direct_distance
	context.path_distance = input.path_distance
	context.target_position = input.target_position
	context.has_target_position = true
	context.currently_perceived = true
	context.has_line_of_sight = has_line_of_sight
	context.focus_primary_target = true
	context.has_clear_corridor = input.has_clear_corridor
	return context


func _set_unaware_perception() -> void:
	_perception_state = PERCEPTION_UNAWARE
	_path_distance = INF
	_terrain_line_of_sight = false
	_memory_remaining = 0.0
	_has_last_known_position = false


func _action_candidate(
	action_data: Dictionary,
	context: PerceptionContext,
	input: SenseInput,
	attack_cooldown: float
) -> Candidate:
	var action_id: String = String(action_data.get("id", ""))
	var base_score: float = float(action_data.get("base_score", 0.0))
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET:
		return _explicit_attack_candidate(
			base_score,
			context,
			action_data,
			attack_cooldown,
			true
		)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK:
		return _explicit_attack_candidate(
			base_score,
			context,
			action_data,
			attack_cooldown,
			true
		)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET:
		return _charge_candidate(
			base_score,
			context,
			action_data,
			attack_cooldown
		)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK:
		return _ranged_attack_candidate(base_score, context, action_data)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_ORBIT_TARGET:
		return _orbit_candidate(base_score, context)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME:
		return _guard_candidate(base_score, context, input)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET:
		return _candidate(
			base_score + context.target_score,
			context.focus_primary_target,
			context.target_position,
			context.has_target_position
		)
	return _candidate(0.0, false)


func _explicit_attack_candidate(
	base_score: float,
	context: PerceptionContext,
	action_data: Dictionary,
	attack_cooldown: float,
	require_line_of_sight: bool
) -> Candidate:
	if attack_cooldown > 0.0:
		return _candidate(0.0, false)
	if not context.currently_perceived:
		return _candidate(0.0, false)
	if require_line_of_sight and not context.has_line_of_sight:
		return _candidate(0.0, false)
	var attack: Dictionary = _attack_from_action(action_data)
	var trigger_range: float = float(attack.get("trigger_range", 0.0))
	if trigger_range <= 0.0 or context.direct_distance > trigger_range:
		return _candidate(0.0, false)
	var range_score: float = _proximity_score(
		context.direct_distance,
		trigger_range
	)
	return _candidate(
		base_score + context.target_score + range_score,
		true,
		context.target_position,
		true
	)


func _charge_candidate(
	base_score: float,
	context: PerceptionContext,
	action_data: Dictionary,
	attack_cooldown: float
) -> Candidate:
	var candidate: Candidate = _explicit_attack_candidate(
		base_score,
		context,
		action_data,
		attack_cooldown,
		false
	)
	if not candidate.focus_primary_target or not context.has_clear_corridor:
		return _candidate(0.0, false)
	return candidate


func _ranged_attack_candidate(
	base_score: float,
	context: PerceptionContext,
	action_data: Dictionary
) -> Candidate:
	if not context.currently_perceived or not context.has_line_of_sight:
		return _candidate(0.0, false)
	var attack_range: float = float(
		_attack_from_action(action_data).get("attack_range", 0.0)
	)
	if attack_range <= 0.0 or context.direct_distance > attack_range:
		return _candidate(0.0, false)
	var range_score: float = _proximity_score(
		context.direct_distance,
		attack_range
	)
	return _candidate(
		base_score + context.target_score + range_score,
		true,
		context.target_position,
		true
	)


func _orbit_candidate(
	base_score: float,
	context: PerceptionContext
) -> Candidate:
	if not context.currently_perceived:
		return _candidate(0.0, false)
	var orbit_radius: float = maxf(movement_value("orbit_radius"), 1.0)
	var radius_score: float = 1.0 - clampf(
		absf(context.direct_distance - orbit_radius) / orbit_radius,
		0.0,
		1.0
	)
	return _candidate(
		base_score + context.target_score + radius_score,
		true,
		context.target_position,
		true
	)


func _guard_candidate(
	base_score: float,
	context: PerceptionContext,
	input: SenseInput
) -> Candidate:
	var territory_radius: float = _territory_radius()
	var distance: float = input.self_position.distance_to(input.home_position)
	if (
		not context.has_target_position
		and territory_radius > 0.0
		and distance > 1.0
	):
		return _candidate(
			base_score + _territory_weight() + 1.0,
			false,
			input.home_position,
			true
		)
	if territory_radius <= 0.0 or distance <= territory_radius:
		return _candidate(base_score, false, input.home_position, true)
	var over_distance: float = (
		(distance - territory_radius) / territory_radius
	)
	return _candidate(
		base_score + over_distance * _territory_weight(),
		false,
		input.home_position,
		true
	)


func _candidate(
	score: float,
	focus_primary_target: bool,
	target_position: Vector2 = Vector2.ZERO,
	has_target_position: bool = false
) -> Candidate:
	var candidate: Candidate = Candidate.new()
	candidate.score = maxf(score, 0.0)
	candidate.focus_primary_target = focus_primary_target
	candidate.target_position = target_position
	candidate.has_target_position = has_target_position
	return candidate


func _targeting() -> Dictionary:
	return _dictionary_or_empty(_ai_profile.get("targeting", {}))


func _movement() -> Dictionary:
	return _dictionary_or_empty(_ai_profile.get("movement", {}))


func _perception() -> Dictionary:
	return _dictionary_or_empty(_ai_profile.get("perception", {}))


func _territory_radius() -> float:
	return float(_targeting().get("territory_radius", 0.0))


func _territory_weight() -> float:
	return float(_targeting().get("territory_weight", 0.0))


func _sight_radius() -> float:
	return maxf(float(_perception().get("sight_radius", 640.0)), 1.0)


func _path_awareness_radius() -> float:
	return maxf(
		float(_perception().get("path_awareness_radius", 0.0)),
		0.0
	)


func _memory_duration() -> float:
	return maxf(float(_perception().get("memory_duration", 0.0)), 0.0)


func _decision_interval() -> float:
	return maxf(float(_ai_profile.get("decision_interval", 0.12)), 0.01)


func _attack_from_action(action_data: Dictionary) -> Dictionary:
	return _dictionary_or_empty(action_data.get("attack", {}))


func _proximity_score(distance: float, radius: float) -> float:
	return 0.25 + (
		1.0 - clampf(distance / maxf(radius, 1.0), 0.0, 1.0)
	)


func _typed_action_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for raw_action: Variant in raw_value as Array:
		if raw_action is Dictionary:
			result.append((raw_action as Dictionary).duplicate(true))
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return raw_value as Dictionary
	return {}
