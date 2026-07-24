# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §3
class_name Player
extends CharacterBody2D


signal life_changed(current_life: float, max_life: float)
signal died()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const DRAW_RADIUS: float = 12.0
const MOUSE_AIM_MIN_DISTANCE_SQUARED: float = 16.0
const ACTIVE_PLAYER_GROUP: String = "active_player"
const INPUT_PARTICIPANT_ID: String = "player_0"
const TEAM_PLAYER: String = "team_player"

@export_group("Visual Style")
@export var fill_color: Color = Color(0.35, 0.72, 1.0)
@export var hurt_flash_color: Color = Color(1.0, 0.34, 0.30)

var aim_direction: Vector2 = Vector2.RIGHT
var _base_stats: Dictionary = {}
var _damage_invulnerability_duration: float = 0.0
var _debug_invulnerable: bool = false
var _has_movement_bounds: bool = false
var _health_regen: float = 0.0
var _invulnerable_remaining: float = 0.0
var _luck: float = 0.0
var _movement_bounds: Rect2 = Rect2()
var _move_speed: float = 0.0
var _max_life: float = 1.0
var _life_points: float = 1.0
var _owned_tag_counts: Dictionary = {}
var _pickup_orb_speed: float = 0.0
var _pickup_range: float = 0.0
var _separation_radius: float = 0.0
var _stat_additions: Dictionary = {}
var _stat_multipliers: Dictionary = {}
var _status_effect_component: Node = null
var _presentation: ActorPresentationController = null


func _ready() -> void:
	_ensure_status_effect_component()
	_ensure_presentation()
	_refresh_visuals()


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		velocity = Vector2.ZERO
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		velocity = Vector2.ZERO
		return

	_update_invulnerability(scaled_delta)
	_update_health_regen(scaled_delta)

	var move_input: Vector2 = InputService.vector(ACTIONS.MOVE, INPUT_PARTICIPANT_ID)
	var aim_input: Vector2 = InputService.vector(ACTIONS.AIM, INPUT_PARTICIPANT_ID)
	if aim_input.length_squared() > 0.0:
		_set_aim_direction(aim_input)
	elif InputService.should_use_pointer_aim():
		_set_pointer_aim_from_viewport_position(InputService.pointer_viewport_position())
	InputService.publish_resolved_aim(aim_direction)

	velocity = move_input * _move_speed
	move_and_slide()
	_apply_movement_bounds()


func configure(base_stats: Dictionary) -> void:
	_base_stats = base_stats.duplicate(true)
	_stat_additions.clear()
	_stat_multipliers.clear()
	_clear_status_effects_for_reuse()
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()
	_has_movement_bounds = false
	_invulnerable_remaining = 0.0
	_debug_invulnerable = false
	_rebuild_stats(true)
	add_to_group(ACTIVE_PLAYER_GROUP)


func current_life() -> float:
	return _life_points


func max_life() -> float:
	return _max_life


func is_alive() -> bool:
	return _life_points > 0.0


func debug_heal(amount: float) -> Dictionary:
	var previous_life: float = _life_points
	_life_points = minf(_life_points + maxf(amount, 0.0), _max_life)
	life_changed.emit(_life_points, _max_life)
	_refresh_visuals()
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
	_refresh_visuals()
	if was_alive and _life_points <= 0.0:
		died.emit()
	return {
		"life": _life_points,
		"max_life": _max_life,
		"previous_life": previous_life,
	}


func debug_clear_invulnerability() -> void:
	_invulnerable_remaining = 0.0


func debug_set_invulnerable(enabled: bool) -> void:
	_debug_invulnerable = enabled
	if enabled:
		_invulnerable_remaining = 0.0


func debug_is_invulnerable() -> bool:
	return _debug_invulnerable


func debug_reset_transient_state(world_position: Vector2) -> void:
	global_position = world_position
	velocity = Vector2.ZERO
	_debug_invulnerable = false
	_invulnerable_remaining = 0.0
	_clear_status_effects_for_reuse()
	_life_points = _max_life
	_apply_movement_bounds()
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()
	life_changed.emit(_life_points, _max_life)
	_refresh_visuals()


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


func hit_radius() -> float:
	return DRAW_RADIUS


func stat_value(stat: String) -> float:
	return _stat_value(stat, 0.0)


func aim_at_world_position(world_position: Vector2) -> void:
	var mouse_direction: Vector2 = world_position - global_position
	if mouse_direction.length_squared() > MOUSE_AIM_MIN_DISTANCE_SQUARED:
		_set_aim_direction(mouse_direction)


func set_movement_bounds(bounds: Rect2) -> void:
	_movement_bounds = bounds
	_has_movement_bounds = bounds.size.x > 0.0 and bounds.size.y > 0.0
	_apply_movement_bounds()


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


func combat_team_id() -> String:
	return TEAM_PLAYER


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


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"aim_direction": _vector_to_dict(aim_direction),
		"life_points": _life_points,
		"invulnerable_remaining": _invulnerable_remaining,
		"stat_additions": _stat_additions.duplicate(true),
		"stat_multipliers": _stat_multipliers.duplicate(true),
		"owned_tag_counts": _owned_tag_counts.duplicate(true),
		"status_effects": _status_effect_snapshot(),
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_ensure_status_effect_component()
	if _status_effect_component != null:
		_status_effect_component.call("clear", false)
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_set_aim_direction(_dict_to_vector(snapshot_data.get("aim_direction", {}), aim_direction))
	_stat_additions = _dictionary_or_empty(snapshot_data.get("stat_additions", {}))
	_stat_multipliers = _dictionary_or_empty(snapshot_data.get("stat_multipliers", {}))
	_rebuild_stats(true)
	_life_points = clampf(float(snapshot_data.get("life_points", _max_life)), 0.0, _max_life)
	_invulnerable_remaining = maxf(float(snapshot_data.get("invulnerable_remaining", 0.0)), 0.0)
	_restore_status_snapshot(snapshot_data)
	_apply_movement_bounds()
	life_changed.emit(_life_points, _max_life)
	_refresh_visuals()


func receive_damage(info: RefCounted) -> Dictionary:
	if _debug_invulnerable:
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": false,
			"reason": "debug_invulnerable",
		}
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


func _start_hit_flash() -> void:
	_ensure_presentation()
	if _presentation != null:
		_presentation.play_hit()


func _start_invulnerability() -> void:
	_invulnerable_remaining = _damage_invulnerability_duration


func _update_invulnerability(delta: float) -> void:
	if _invulnerable_remaining <= 0.0:
		return
	_invulnerable_remaining = maxf(_invulnerable_remaining - delta, 0.0)


func _rebuild_stats(reset_life: bool) -> void:
	var previous_max_life: float = _max_life
	_move_speed = _stat_value(STATS.MOVE_SPEED, 0.0)
	_max_life = _stat_value(STATS.MAX_HP, 1.0)
	_health_regen = _stat_value(STATS.HEALTH_REGEN, 0.0)
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


func _update_health_regen(delta: float) -> void:
	if _health_regen <= 0.0 or _life_points <= 0.0 or _life_points >= _max_life:
		return
	var previous_life: float = _life_points
	_life_points = minf(_life_points + _health_regen * delta, _max_life)
	if not is_equal_approx(_life_points, previous_life):
		life_changed.emit(_life_points, _max_life)


func _set_aim_direction(raw_direction: Vector2) -> void:
	if raw_direction.length_squared() <= 0.0:
		return

	var next_direction: Vector2 = raw_direction.normalized()
	var previous_direction: Vector2 = aim_direction
	aim_direction = next_direction
	if previous_direction.distance_squared_to(aim_direction) > 0.0001:
		_refresh_visuals()


func _refresh_visuals() -> void:
	_ensure_presentation()
	if _presentation == null:
		return
	_presentation.configure_visual(
		fill_color,
		hurt_flash_color,
		hurt_flash_color,
		1.0,
		Vector2.ONE
	)
	_presentation.set_direction(aim_direction)


func _ensure_presentation() -> void:
	if _presentation != null and is_instance_valid(_presentation):
		return
	_presentation = get_node_or_null("Presentation") as ActorPresentationController
	if _presentation == null:
		push_error("[Player] missing scene-authored Presentation")


func _set_pointer_aim_from_viewport_position(viewport_position: Vector2) -> void:
	var viewport_offset: Vector2 = viewport_position - get_viewport().get_visible_rect().size * 0.5
	if viewport_offset.length_squared() > MOUSE_AIM_MIN_DISTANCE_SQUARED:
		_set_aim_direction(InputService.pointer_world_position(get_viewport()) - global_position)


func _apply_movement_bounds() -> void:
	if not _has_movement_bounds:
		return
	global_position = Vector2(
		clampf(global_position.x, _movement_bounds.position.x, _movement_bounds.end.x),
		clampf(global_position.y, _movement_bounds.position.y, _movement_bounds.end.y)
	)

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


func _ensure_status_effect_component() -> void:
	if _status_effect_component != null and is_instance_valid(_status_effect_component):
		_status_effect_component.call("configure_ability_tag_owner", self)
		return
	_status_effect_component = get_node_or_null("StatusEffectComponent")
	if _status_effect_component == null:
		push_error("[Player] missing scene-authored StatusEffectComponent")
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
	_ensure_status_effect_component()
	if _status_effect_component != null:
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
