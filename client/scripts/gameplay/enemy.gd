# Doc: docs/代码/enemy_ai.md
# Authority: docs/游戏设计文档.md §5.3, docs/词表与契约.md §12-B
class_name Enemy
extends CharacterBody2D


signal defeated(enemy: Node, exp_reward: int)

const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const ENEMY_AI_ACTIONS := preload("res://scripts/contracts/enemy_ai_actions.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

const ACTION_STATE_CHARGE_RELEASE: String = "charge_release"
const ACTION_STATE_CHARGE_WINDUP: String = "charge_windup"
const ACTIVE_PLAYER_GROUP: String = "active_player"
const NAVIGATION_MODE_DIRECT: String = "direct"
const NAVIGATION_MODE_FLOW_FIELD: String = "flow_field"
const NAVIGATION_MODE_LOCAL_ASTAR: String = "local_astar"
const NAVIGATION_MODE_NONE: String = "none"
const NAVIGATION_NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i(1, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]
const PATH_TANGENT_SCORE_WEIGHT: float = 0.2
const PERCEPTION_MEMORY: String = "memory"
const PERCEPTION_PATH_AWARE: String = "path_aware"
const PERCEPTION_UNAWARE: String = "unaware"
const PERCEPTION_VISIBLE: String = "visible"
const SCORE_EPSILON: float = 0.001
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

@export_group("Visual Style")
@export var fill_color: Color = Color(1.0, 0.38, 0.32)
@export var defeat_feedback_color: Color = Color(1.0, 0.62, 0.22)
@export var hit_flash_color: Color = Color(1.0, 0.96, 0.74)
@export_range(0.0, 1.0, 0.01) var outline_alpha: float = 0.88

var _actions: Array[Dictionary] = []
var _action_state: String = ""
var _action_timer: float = 0.0
var _ai_profile: Dictionary = {}
var _ai_profile_id: String = ""
var _charge_cooldown_remaining: float = 0.0
var _charge_direction: Vector2 = Vector2.ZERO
var _collision_shape: CollisionShape2D = null
var _contact_damage: float = 0.0
var _contact_damage_type: String = ""
var _current_action: String = ""
var _decision_remaining: float = 0.0
var _enemy_id: String = ""
var _exp_reward: int = 0
var _facing_sign: float = 1.0
var _focus_target: Node2D = null
var _hit_radius: float = 0.0
var _home_position: Vector2 = Vector2.ZERO
var _has_last_known_position: bool = false
var _has_movement_target: bool = false
var _last_damage_source_team: String = ""
var _last_known_position: Vector2 = Vector2.ZERO
var _last_scores: Dictionary = {}
var _life_points: float = 1.0
var _max_life: float = 1.0
var _has_movement_bounds: bool = false
var _movement_bounds: Rect2 = Rect2()
var _move_speed: float = 0.0
var _movement_target_position: Vector2 = Vector2.ZERO
var _navigation_mode: String = NAVIGATION_MODE_NONE
var _navigation_provider: Node = null
var _owned_tag_counts: Dictionary = {}
var _path_distance: float = INF
var _perception_state: String = PERCEPTION_UNAWARE
var _player_target: Node2D = null
var _ranged_cooldown_remaining: float = 0.0
var _separation_radius: float = 0.0
var _terrain_line_of_sight: bool = false
var _memory_remaining: float = 0.0
var _cached_navigation_waypoint: Vector2 = Vector2.ZERO
var _has_cached_navigation_waypoint: bool = false
var _status_effect_component: Node = null
var _presentation: ActorPresentationController = null


func _physics_process(delta: float) -> void:
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if is_defeat_feedback_active():
		return
	if _player_target == null or not is_instance_valid(_player_target):
		return
	if not GameState.is_state(GameState.PLAYING):
		return
	if scaled_delta <= 0.0:
		return

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


func configure(enemy_data: Dictionary, target: Node2D, navigation_provider: Node = null) -> void:
	velocity = Vector2.ZERO
	_clear_status_effects_for_reuse()
	_ensure_presentation()
	if _presentation != null:
		_presentation.configure_profile_id(
			String(enemy_data.get("presentation_profile_id", ""))
		)
		_presentation.reset_presentation()
	_player_target = target
	_focus_target = target
	_navigation_provider = navigation_provider
	_home_position = global_position
	_enemy_id = String(enemy_data.get("id", ""))
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
	_ranged_cooldown_remaining = _movement_value("ranged_initial_cooldown")
	_last_damage_source_team = ""
	_has_last_known_position = false
	_last_known_position = Vector2.ZERO
	_memory_remaining = 0.0
	_perception_state = PERCEPTION_UNAWARE
	_path_distance = INF
	_terrain_line_of_sight = false
	_navigation_mode = NAVIGATION_MODE_NONE
	_has_movement_target = false
	_movement_target_position = Vector2.ZERO
	_has_cached_navigation_waypoint = false
	_cached_navigation_waypoint = Vector2.ZERO
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
	_configure_collision_shape()
	if _player_target != null and is_instance_valid(_player_target):
		_update_facing(_player_target.global_position - global_position)
	_home_position = _clamp_to_movement_bounds(_home_position)
	_apply_movement_bounds()
	add_to_group("active_enemies")
	_refresh_visuals()


func hit_radius() -> float:
	return _hit_radius


func separation_radius() -> float:
	return _separation_radius


func visual_color() -> Color:
	return fill_color


func ai_debug_summary() -> Dictionary:
	return {
		"profile_id": _ai_profile_id,
		"action": _current_action,
		"action_state": _action_state,
		"focus_target": _focus_target.name if _focus_target != null and is_instance_valid(_focus_target) else "",
		"perception_state": _perception_state,
		"path_distance": _path_distance,
		"last_known_position": _vector_to_dict(_last_known_position) if _has_last_known_position else {},
		"memory_remaining": _memory_remaining,
		"navigation_mode": _navigation_mode,
		"scores": _last_scores.duplicate(true),
	}


func is_alive() -> bool:
	return _life_points > 0.0 and not is_defeat_feedback_active()


func enemy_id() -> String:
	return _enemy_id


func is_defeat_feedback_active() -> bool:
	return _presentation != null and _presentation.is_defeat_active()


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
	if String(info.get("source_team")) == TEAM_ENEMY:
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": false,
			"reason": "friendly_fire_blocked",
		}

	_last_damage_source_team = String(info.get("source_team"))
	var amount: float = float(info.get("amount"))
	var applied_amount: float = minf(amount, _life_points)
	_life_points = maxf(_life_points - amount, 0.0)
	var is_defeated: bool = _life_points <= 0.0
	if is_defeated:
		remove_from_group("active_enemies")
		defeated.emit(self, _exp_reward)
		_ensure_presentation()
		if _presentation != null:
			_presentation.play_defeat()
		else:
			PoolManager.release(self)
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
		"ranged_cooldown_remaining": _ranged_cooldown_remaining,
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
	_current_action = _validated_restored_action(String(snapshot_data.get("current_action", "")))
	if _current_action.is_empty():
		_action_state = ""
		_action_timer = 0.0
	else:
		_action_state = String(snapshot_data.get("action_state", ""))
		_action_timer = maxf(float(snapshot_data.get("action_timer", 0.0)), 0.0)
	_charge_cooldown_remaining = maxf(float(snapshot_data.get("charge_cooldown_remaining", 0.0)), 0.0)
	_charge_direction = _dict_to_vector(snapshot_data.get("charge_direction", {}), Vector2.ZERO)
	_ranged_cooldown_remaining = maxf(float(snapshot_data.get("ranged_cooldown_remaining", 0.0)), 0.0)
	_last_damage_source_team = String(snapshot_data.get("last_damage_source_team", ""))
	_restore_status_snapshot(snapshot_data)
	if _life_points <= 0.0:
		remove_from_group("active_enemies")
	_refresh_visuals()


func _validated_restored_action(action_id: String) -> String:
	if action_id.is_empty():
		return ""
	for action: Dictionary in _actions:
		if String(action.get("id", "")) == action_id:
			return action_id
	return ""


func _pool_reset() -> void:
	velocity = Vector2.ZERO
	_actions.clear()
	_action_state = ""
	_action_timer = 0.0
	_ai_profile.clear()
	_ai_profile_id = ""
	_charge_cooldown_remaining = 0.0
	_charge_direction = Vector2.ZERO
	_ranged_cooldown_remaining = 0.0
	_contact_damage = 0.0
	_contact_damage_type = ""
	_current_action = ""
	_decision_remaining = 0.0
	_enemy_id = ""
	_exp_reward = 0
	_facing_sign = 1.0
	_focus_target = null
	_has_last_known_position = false
	_has_movement_target = false
	_hit_radius = 0.0
	_home_position = Vector2.ZERO
	_last_known_position = Vector2.ZERO
	_last_damage_source_team = ""
	_last_scores.clear()
	_life_points = 1.0
	_max_life = 1.0
	clear_movement_bounds()
	_move_speed = 0.0
	_movement_target_position = Vector2.ZERO
	_navigation_mode = NAVIGATION_MODE_NONE
	_navigation_provider = null
	_path_distance = INF
	_perception_state = PERCEPTION_UNAWARE
	_clear_status_effects_for_reuse()
	_player_target = null
	_separation_radius = 0.0
	_terrain_line_of_sight = false
	_memory_remaining = 0.0
	_cached_navigation_waypoint = Vector2.ZERO
	_has_cached_navigation_waypoint = false
	visible = true
	_set_collision_enabled(false)
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()
	_refresh_visuals()


func _pool_release() -> void:
	velocity = Vector2.ZERO
	remove_from_group("active_enemies")
	_clear_status_effects_for_reuse()
	clear_movement_bounds()
	_focus_target = null
	_has_last_known_position = false
	_has_movement_target = false
	_memory_remaining = 0.0
	_navigation_mode = NAVIGATION_MODE_NONE
	_navigation_provider = null
	_path_distance = INF
	_perception_state = PERCEPTION_UNAWARE
	_player_target = null
	_terrain_line_of_sight = false
	_has_cached_navigation_waypoint = false
	_set_collision_enabled(false)
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()


func _choose_action() -> void:
	var context: Dictionary = _sense_context()
	var best_action: String = ""
	var best_target: Node2D = null
	var best_target_position: Vector2 = Vector2.ZERO
	var best_has_target_position: bool = false
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
			best_target_position = candidate.get("target_position", Vector2.ZERO) as Vector2
			best_has_target_position = bool(candidate.get("has_target_position", false))
			best_score = score
	_current_action = best_action
	_focus_target = best_target
	_movement_target_position = best_target_position
	_has_movement_target = best_has_target_position
	_decision_remaining = _decision_interval()
	_refresh_cached_navigation_waypoint()


func _sense_context() -> Dictionary:
	var player_candidate: Dictionary = _player_candidate()
	return {
		"target": player_candidate.get("target"),
		"target_score": float(player_candidate.get("score", 0.0)),
		"target_distance": float(player_candidate.get("direct_distance", 0.0)),
		"path_distance": float(player_candidate.get("path_distance", INF)),
		"target_position": player_candidate.get("target_position", Vector2.ZERO),
		"has_target_position": bool(player_candidate.get("has_target_position", false)),
		"currently_perceived": bool(player_candidate.get("currently_perceived", false)),
		"has_line_of_sight": bool(player_candidate.get("has_line_of_sight", false)),
	}


func _player_candidate() -> Dictionary:
	if _player_target == null or not is_instance_valid(_player_target):
		_set_unaware_perception()
		return _empty_candidate()
	var player_position: Vector2 = _player_target.global_position
	var direct_distance: float = global_position.distance_to(player_position)
	var weight: float = _player_weight()
	if weight <= 0.0:
		_set_unaware_perception()
		return _empty_candidate()
	var route_query: Dictionary = _active_navigation_query()
	var route_reachable: bool = bool(route_query.get("reachable", false))
	_path_distance = float(route_query.get("distance", INF)) if route_reachable else INF
	_terrain_line_of_sight = _has_terrain_line_of_sight(global_position, player_position)
	if _terrain_line_of_sight and direct_distance <= _sight_radius():
		return _current_player_candidate(
			PERCEPTION_VISIBLE,
			player_position,
			direct_distance,
			_path_distance,
			weight,
			_sight_radius(),
			true
		)
	if route_reachable and _path_distance <= _path_awareness_radius():
		return _current_player_candidate(
			PERCEPTION_PATH_AWARE,
			player_position,
			direct_distance,
			_path_distance,
			weight,
			_path_awareness_radius(),
			false
		)
	if _has_last_known_position and _memory_remaining > 0.0:
		_perception_state = PERCEPTION_MEMORY
		var memory_distance: float = global_position.distance_to(_last_known_position)
		return {
			"target": null,
			"score": weight * _proximity_score(memory_distance, _sight_radius()),
			"direct_distance": memory_distance,
			"path_distance": INF,
			"target_position": _last_known_position,
			"has_target_position": true,
			"currently_perceived": false,
			"has_line_of_sight": false,
		}
	_set_unaware_perception()
	return _empty_candidate()


func _current_player_candidate(
	state: String,
	player_position: Vector2,
	direct_distance: float,
	path_distance: float,
	weight: float,
	score_radius: float,
	has_line_of_sight: bool
) -> Dictionary:
	_perception_state = state
	_last_known_position = player_position
	_has_last_known_position = true
	_memory_remaining = _memory_duration()
	var score_distance: float = direct_distance if has_line_of_sight else path_distance
	return {
		"target": _player_target,
		"score": weight * _proximity_score(score_distance, score_radius),
		"direct_distance": direct_distance,
		"path_distance": path_distance,
		"target_position": player_position,
		"has_target_position": true,
		"currently_perceived": true,
		"has_line_of_sight": has_line_of_sight,
	}


func _set_unaware_perception() -> void:
	_perception_state = PERCEPTION_UNAWARE
	_path_distance = INF
	_terrain_line_of_sight = false
	_memory_remaining = 0.0
	_has_last_known_position = false


func _action_candidate(action: Dictionary, context: Dictionary) -> Dictionary:
	var action_id: String = String(action.get("id", ""))
	var base_score: float = float(action.get("base_score", 0.0))
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET:
		return _charge_candidate(base_score, context)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK:
		return _ranged_attack_candidate(base_score, context)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_ORBIT_TARGET:
		return _orbit_candidate(base_score, context)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME:
		return _guard_candidate(base_score, context)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET:
		return _candidate(
			base_score + float(context.get("target_score", 0.0)),
			context.get("target"),
			context.get("target_position", Vector2.ZERO) as Vector2,
			bool(context.get("has_target_position", false))
		)
	return _candidate(0.0, null)


func _charge_candidate(base_score: float, context: Dictionary) -> Dictionary:
	if _charge_cooldown_remaining > 0.0:
		return _candidate(0.0, null)
	if not bool(context.get("currently_perceived", false)):
		return _candidate(0.0, null)
	var target: Node2D = context.get("target") as Node2D
	if target == null or not is_instance_valid(target):
		return _candidate(0.0, null)
	var distance: float = float(context.get("target_distance", global_position.distance_to(target.global_position)))
	var charge_range: float = _movement_value("charge_range")
	if charge_range <= 0.0 or distance > charge_range:
		return _candidate(0.0, null)
	if not _has_clear_corridor(global_position, target.global_position, _hit_radius):
		return _candidate(0.0, null)
	var range_score: float = _proximity_score(distance, charge_range)
	return _candidate(base_score + float(context.get("target_score", 0.0)) + range_score, target, target.global_position, true)


func _ranged_attack_candidate(base_score: float, context: Dictionary) -> Dictionary:
	if not bool(context.get("currently_perceived", false)) or not bool(context.get("has_line_of_sight", false)):
		return _candidate(0.0, null)
	var target: Node2D = context.get("target") as Node2D
	if target == null or not is_instance_valid(target):
		return _candidate(0.0, null)
	var distance: float = float(context.get("target_distance", global_position.distance_to(target.global_position)))
	var attack_range: float = _movement_value("ranged_attack_range")
	if attack_range <= 0.0 or distance > attack_range:
		return _candidate(0.0, null)
	var range_score: float = _proximity_score(distance, attack_range)
	return _candidate(base_score + float(context.get("target_score", 0.0)) + range_score, target, target.global_position, true)


func _orbit_candidate(base_score: float, context: Dictionary) -> Dictionary:
	if not bool(context.get("currently_perceived", false)):
		return _candidate(0.0, null)
	var target: Node2D = context.get("target") as Node2D
	if target == null or not is_instance_valid(target):
		return _candidate(0.0, null)
	var distance: float = float(context.get("target_distance", global_position.distance_to(target.global_position)))
	var orbit_radius: float = maxf(_movement_value("orbit_radius"), 1.0)
	var radius_score: float = 1.0 - clampf(absf(distance - orbit_radius) / orbit_radius, 0.0, 1.0)
	return _candidate(base_score + float(context.get("target_score", 0.0)) + radius_score, target, target.global_position, true)


func _guard_candidate(base_score: float, context: Dictionary) -> Dictionary:
	var territory_radius: float = _territory_radius()
	var distance: float = global_position.distance_to(_home_position)
	if not bool(context.get("has_target_position", false)) and territory_radius > 0.0 and distance > 1.0:
		return _candidate(base_score + _territory_weight() + 1.0, null, _home_position, true)
	if territory_radius <= 0.0 or distance <= territory_radius:
		return _candidate(base_score, null, _home_position, true)
	var over_distance: float = (distance - territory_radius) / territory_radius
	return _candidate(base_score + over_distance * _territory_weight(), null, _home_position, true)


func _candidate(
	score: float,
	raw_target: Variant,
	target_position: Vector2 = Vector2.ZERO,
	has_target_position: bool = false
) -> Dictionary:
	return {
		"score": maxf(score, 0.0),
		"target": raw_target if raw_target is Node2D else null,
		"target_position": target_position,
		"has_target_position": has_target_position,
	}


func _empty_candidate() -> Dictionary:
	return {
		"target": null,
		"score": 0.0,
		"direct_distance": 0.0,
		"path_distance": INF,
		"target_position": Vector2.ZERO,
		"has_target_position": false,
		"currently_perceived": false,
		"has_line_of_sight": false,
	}


func _apply_current_action(delta: float) -> void:
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_ORBIT_TARGET:
		_move_in_direction(_path_band_direction(_movement_value("orbit_radius")), _action_speed_scale(_current_action), delta)
		return
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET:
		_start_charge()
		return
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK:
		_apply_ranged_attack(delta)
		return
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME:
		_move_in_direction(_direction_to_cached_target(_home_position), _action_speed_scale(_current_action), delta)
		return
	_move_in_direction(_movement_target_direction(), _action_speed_scale(_current_action), delta)


func _apply_ranged_attack(delta: float) -> void:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return
	var target_direction: Vector2 = _focus_target.global_position - global_position
	if target_direction.length_squared() > 0.0:
		_update_facing(target_direction)
	var distance: float = target_direction.length()
	var keep_distance: float = _movement_value("ranged_keep_distance")
	var attack_range: float = _movement_value("ranged_attack_range")
	var route_query: Dictionary = _active_navigation_query()
	var route_distance: float = float(route_query.get("distance", distance)) if bool(route_query.get("reachable", false)) else distance
	if keep_distance > 0.0 and route_distance < keep_distance:
		_move_in_direction(_path_band_direction(keep_distance), _action_speed_scale(_current_action), delta)
	elif attack_range > 0.0 and route_distance > attack_range * 0.82:
		_move_in_direction(_movement_direction_to(_focus_target.global_position, true), _action_speed_scale(_current_action), delta)
	else:
		_move_in_direction(_path_band_direction(maxf(keep_distance, 1.0)), _action_speed_scale(_current_action), delta)
	if (
		distance <= attack_range
		and _ranged_cooldown_remaining <= 0.0
		and _has_terrain_line_of_sight(global_position, _focus_target.global_position)
	):
		_fire_ranged_projectile(target_direction)


func _fire_ranged_projectile(target_direction: Vector2) -> void:
	if target_direction.length_squared() <= 0.0:
		return
	var raw_node: Node = PoolManager.acquire(POOL_IDS.BULLET_BASIC)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return
	var direction: Vector2 = target_direction.normalized()
	var muzzle_distance: float = _movement_value("ranged_projectile_muzzle_distance")
	var bullet: Node2D = raw_node as Node2D
	bullet.global_position = global_position + direction * muzzle_distance
	_reparent_to_parent(bullet)
	bullet.call("configure", {
		STATS.DAMAGE: _movement_value("ranged_projectile_damage"),
		STATS.BULLET_SPEED: _movement_value("ranged_projectile_speed"),
		STATS.BULLET_RANGE: _movement_value("ranged_projectile_range"),
		STATS.PIERCE_COUNT: 0,
	}, {
		"damage_type": _movement_string("ranged_projectile_damage_type", _contact_damage_type),
		"damage_target_groups": [ACTIVE_PLAYER_GROUP],
		"hit_radius": _movement_value("ranged_projectile_hit_radius"),
		"lifetime": _movement_value("ranged_projectile_lifetime"),
		"source_team": TEAM_ENEMY,
		"target_team": TEAM_PLAYER,
	}, direction, self)
	_ranged_cooldown_remaining = _movement_value("ranged_cooldown")


func _reparent_to_parent(node: Node) -> void:
	var active_parent: Node = get_parent()
	if active_parent == null:
		return
	var old_parent: Node = node.get_parent()
	if old_parent == active_parent:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	active_parent.add_child(node)


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
	_move_with_collision(normalized * _move_speed * maxf(speed_scale, 0.0) * delta)
	_apply_movement_bounds()


func _movement_target_direction() -> Vector2:
	if not _has_movement_target:
		return Vector2.ZERO
	if _perception_state == PERCEPTION_MEMORY:
		return _direction_to_cached_target(_movement_target_position)
	if _focus_target != null and is_instance_valid(_focus_target):
		return _movement_direction_to(_focus_target.global_position, true)
	return _direction_to_cached_target(_movement_target_position)


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


func _movement_direction_to(target_position: Vector2, use_active_field: bool) -> Vector2:
	var direct_direction: Vector2 = target_position - global_position
	if _navigation_provider == null or not is_instance_valid(_navigation_provider):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if _has_clear_corridor(global_position, target_position, _hit_radius):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	var query: Dictionary = (
		_active_navigation_query()
		if use_active_field
		else _navigation_query(global_position, target_position)
	)
	if not bool(query.get("reachable", false)):
		_navigation_mode = NAVIGATION_MODE_NONE
		return Vector2.ZERO
	_navigation_mode = NAVIGATION_MODE_FLOW_FIELD if use_active_field else NAVIGATION_MODE_LOCAL_ASTAR
	return (query.get("next_position", global_position) as Vector2) - global_position


func _direction_to_cached_target(target_position: Vector2) -> Vector2:
	var direct_direction: Vector2 = target_position - global_position
	if _navigation_provider == null or not is_instance_valid(_navigation_provider):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if _has_clear_corridor(global_position, target_position, _hit_radius):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if not _has_cached_navigation_waypoint:
		_navigation_mode = NAVIGATION_MODE_NONE
		return Vector2.ZERO
	_navigation_mode = NAVIGATION_MODE_LOCAL_ASTAR
	return _cached_navigation_waypoint - global_position


func _path_band_direction(desired_distance: float) -> Vector2:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return Vector2.ZERO
	if _navigation_provider == null or not is_instance_valid(_navigation_provider):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return _orbit_direction()
	if not (
		_navigation_provider.has_method("world_to_global_cell")
		and _navigation_provider.has_method("global_cell_to_world")
	):
		return _movement_direction_to(_focus_target.global_position, true)
	var current_cell: Vector2i = _navigation_provider.call("world_to_global_cell", global_position) as Vector2i
	var from_target: Vector2 = global_position - _focus_target.global_position
	if from_target.length_squared() <= 0.0:
		from_target = Vector2.RIGHT
	var tangent: Vector2 = Vector2(-from_target.y, from_target.x).normalized() * _orbit_sign()
	var best_direction: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var safe_desired_distance: float = maxf(desired_distance, 1.0)
	for offset: Vector2i in NAVIGATION_NEIGHBOR_OFFSETS:
		var candidate_cell: Vector2i = current_cell + offset
		var candidate_position: Vector2 = _navigation_provider.call("global_cell_to_world", candidate_cell) as Vector2
		if not _has_clear_corridor(global_position, candidate_position, _hit_radius):
			continue
		var query: Dictionary = _navigation_provider.call("navigation_query_to_active_target", candidate_position) as Dictionary
		if not bool(query.get("reachable", false)):
			continue
		var route_distance: float = float(query.get("distance", INF))
		var direction: Vector2 = (candidate_position - global_position).normalized()
		var distance_score: float = -absf(route_distance - safe_desired_distance) / safe_desired_distance
		var tangent_score: float = direction.dot(tangent) * PATH_TANGENT_SCORE_WEIGHT
		var score: float = distance_score + tangent_score
		if score > best_score + SCORE_EPSILON:
			best_score = score
			best_direction = candidate_position - global_position
	if best_direction.length_squared() <= 0.0:
		return _movement_direction_to(_focus_target.global_position, true)
	_navigation_mode = NAVIGATION_MODE_FLOW_FIELD
	return best_direction


func _refresh_cached_navigation_waypoint() -> void:
	_has_cached_navigation_waypoint = false
	_cached_navigation_waypoint = Vector2.ZERO
	if _navigation_provider == null or not is_instance_valid(_navigation_provider):
		return
	var target_position: Vector2 = Vector2.ZERO
	if _current_action == ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME:
		target_position = _home_position
	elif _perception_state == PERCEPTION_MEMORY and _has_movement_target:
		target_position = _movement_target_position
	else:
		return
	var query: Dictionary = _navigation_query(global_position, target_position)
	if not bool(query.get("reachable", false)):
		return
	_cached_navigation_waypoint = query.get("next_position", Vector2.ZERO) as Vector2
	_has_cached_navigation_waypoint = true


func _update_ai_timers(delta: float) -> void:
	_charge_cooldown_remaining = maxf(_charge_cooldown_remaining - delta, 0.0)
	_ranged_cooldown_remaining = maxf(_ranged_cooldown_remaining - delta, 0.0)
	_memory_remaining = maxf(_memory_remaining - delta, 0.0)


func _is_charge_state_active() -> bool:
	return _action_state == ACTION_STATE_CHARGE_WINDUP or _action_state == ACTION_STATE_CHARGE_RELEASE


func _start_hit_flash() -> void:
	_ensure_presentation()
	if _presentation != null:
		_presentation.play_hit()


func _update_facing(direction: Vector2) -> void:
	var previous_sign: float = _facing_sign
	if direction.x > 0.01:
		_facing_sign = 1.0
	elif direction.x < -0.01:
		_facing_sign = -1.0
	if not is_equal_approx(previous_sign, _facing_sign):
		_refresh_visuals()


func _refresh_visuals() -> void:
	_ensure_presentation()
	if _presentation == null:
		return
	var radius: float = maxf(_hit_radius, 8.0)
	_presentation.configure_visual(
		fill_color,
		hit_flash_color,
		defeat_feedback_color,
		outline_alpha,
		Vector2(radius * _facing_sign, radius)
	)


func _ensure_presentation() -> void:
	if _presentation != null and is_instance_valid(_presentation):
		return
	_presentation = get_node_or_null("Presentation") as ActorPresentationController
	if _presentation == null:
		push_error("[Enemy] missing scene-authored Presentation")
		return
	if not _presentation.defeat_finished.is_connected(_on_defeat_presentation_finished):
		_presentation.defeat_finished.connect(_on_defeat_presentation_finished)


func _on_defeat_presentation_finished() -> void:
	if is_inside_tree() and is_defeat_feedback_active():
		PoolManager.release(self)


func _check_contact() -> void:
	var contact_target: Node2D = _contact_target()
	if contact_target == null or not is_instance_valid(contact_target):
		return
	if contact_target.has_method("is_alive") and not bool(contact_target.call("is_alive")):
		return
	var distance: float = global_position.distance_to(contact_target.global_position)
	if distance > _contact_distance(contact_target):
		return
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(_contact_damage, _contact_damage_type, self, contact_target, TEAM_ENEMY, TEAM_PLAYER)
	Combat.apply_damage(contact_target, info)


func _contact_target() -> Node2D:
	if _player_target != null and is_instance_valid(_player_target):
		return _player_target
	return null


func _contact_distance(target: Node2D) -> float:
	var distance: float = _hit_radius
	if target.has_method("separation_radius"):
		distance = maxf(distance, _separation_radius + float(target.call("separation_radius")))
	return distance


func _apply_center_separation() -> void:
	var offset: Vector2 = Vector2.ZERO
	if _separation_radius > 0.0:
		for other: Node in get_tree().get_nodes_in_group("active_enemies"):
			offset += _enemy_separation_offset(other)
	offset += _target_separation_offset()

	if offset.length_squared() > 0.0:
		_move_with_collision(offset)
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


func _perception() -> Dictionary:
	return _dictionary_or_empty(_ai_profile.get("perception", {}))


func _movement_value(key: String) -> float:
	return float(_movement().get(key, 0.0))


func _movement_string(key: String, fallback: String = "") -> String:
	return String(_movement().get(key, fallback))


func _player_weight() -> float:
	return float(_targeting().get("player_weight", 1.0))


func _territory_radius() -> float:
	return float(_targeting().get("territory_radius", 0.0))


func _territory_weight() -> float:
	return float(_targeting().get("territory_weight", 0.0))


func _sight_radius() -> float:
	return maxf(float(_perception().get("sight_radius", 640.0)), 1.0)


func _path_awareness_radius() -> float:
	return maxf(float(_perception().get("path_awareness_radius", 0.0)), 0.0)


func _memory_duration() -> float:
	return maxf(float(_perception().get("memory_duration", 0.0)), 0.0)


func _decision_interval() -> float:
	return maxf(float(_ai_profile.get("decision_interval", 0.12)), 0.01)


func _active_navigation_query() -> Dictionary:
	if (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
		and _navigation_provider.has_method("navigation_query_to_active_target")
	):
		return _navigation_provider.call("navigation_query_to_active_target", global_position) as Dictionary
	if _player_target == null or not is_instance_valid(_player_target):
		return {"reachable": false, "distance": INF}
	return {
		"reachable": true,
		"distance": global_position.distance_to(_player_target.global_position),
		"next_position": _player_target.global_position,
		"target_position": _player_target.global_position,
	}


func _navigation_query(from_position: Vector2, target_position: Vector2) -> Dictionary:
	if (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
		and _navigation_provider.has_method("navigation_query")
	):
		return _navigation_provider.call("navigation_query", from_position, target_position) as Dictionary
	return {
		"reachable": true,
		"distance": from_position.distance_to(target_position),
		"next_position": target_position,
		"target_position": target_position,
	}


func _has_terrain_line_of_sight(from_position: Vector2, target_position: Vector2) -> bool:
	if (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
		and _navigation_provider.has_method("has_terrain_line_of_sight")
	):
		return bool(_navigation_provider.call("has_terrain_line_of_sight", from_position, target_position))
	return true


func _has_clear_corridor(from_position: Vector2, target_position: Vector2, clearance: float) -> bool:
	if (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
		and _navigation_provider.has_method("has_clear_corridor")
	):
		return bool(_navigation_provider.call("has_clear_corridor", from_position, target_position, clearance))
	return true


func _action_speed_scale(action_id: String) -> float:
	for action: Dictionary in _actions:
		if String(action.get("id", "")) == action_id:
			return maxf(float(action.get("speed_scale", 1.0)), 0.0)
	return 1.0


func _proximity_score(distance: float, radius: float) -> float:
	return 0.25 + (1.0 - clampf(distance / maxf(radius, 1.0), 0.0, 1.0))


func _orbit_sign() -> float:
	return 1.0 if int(get_instance_id()) % 2 == 0 else -1.0


func _typed_action_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_action: Variant in _array_or_empty(raw_value):
		if raw_action is Dictionary:
			result.append((raw_action as Dictionary).duplicate(true))
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


func _move_with_collision(motion: Vector2) -> void:
	if motion.length_squared() <= 0.0:
		return
	var collision: KinematicCollision2D = move_and_collide(motion)
	if collision == null:
		return
	var slide_motion: Vector2 = collision.get_remainder().slide(collision.get_normal())
	if slide_motion.length_squared() > 0.0:
		move_and_collide(slide_motion)


func _configure_collision_shape() -> void:
	var collision_shape: CollisionShape2D = _collision_shape_node()
	if collision_shape == null:
		push_error("[Enemy] missing CollisionShape2D scene node")
		return
	var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
	if circle_shape == null:
		circle_shape = CircleShape2D.new()
		collision_shape.shape = circle_shape
	circle_shape.radius = maxf(_hit_radius, 1.0)
	collision_shape.disabled = false


func _set_collision_enabled(enabled: bool) -> void:
	var collision_shape: CollisionShape2D = _collision_shape_node()
	if collision_shape != null:
		collision_shape.disabled = not enabled


func _collision_shape_node() -> CollisionShape2D:
	if _collision_shape == null or not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	return _collision_shape


func _ensure_status_effect_component() -> void:
	if _status_effect_component != null and is_instance_valid(_status_effect_component):
		_status_effect_component.call("configure_ability_tag_owner", self)
		return
	_status_effect_component = get_node_or_null("StatusEffectComponent")
	if _status_effect_component == null:
		push_error("[Enemy] missing scene-authored StatusEffectComponent")
		return
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
