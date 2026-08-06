# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §3
class_name Player
extends CharacterBody2D


signal life_changed(current_life: float, max_life: float)
signal shield_changed(
	current_shield: float,
	max_shield: float,
	overshield: float
)
signal dash_started(direction: Vector2)
signal dash_finished()
signal died()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const DEFAULT_BODY_RADIUS: float = 25.0
const MOUSE_AIM_MIN_DISTANCE_SQUARED: float = 16.0
const ACTIVE_PLAYER_GROUP: String = "active_player"
const INPUT_PARTICIPANT_ID: String = "player_0"
const TEAM_PLAYER: String = "team_player"

@export_group("Visual Style")
@export var hurt_flash_color: Color = Color(1.0, 0.34, 0.30)

var aim_direction: Vector2 = Vector2.RIGHT
var _armor: float = 0.0
var _armor_coefficient: float = 300.0
var _armor_maximum: float = 1200.0
var _base_stats: Dictionary = {}
var _body_radius: float = DEFAULT_BODY_RADIUS
var _camera_look_offset: Vector2 = Vector2.ZERO
var _current_shield: float = 0.0
var _dash_cooldown: float = 1.25
var _dash_cooldown_remaining: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO
var _dash_duration: float = 0.16
var _dash_invulnerability_duration: float = 0.12
var _dash_invulnerability_remaining: float = 0.0
var _dash_remaining: float = 0.0
var _dash_speed: float = 750.0
var _debug_invulnerable: bool = false
var _element_damage_taken_multipliers: Dictionary = {}
var _external_knockback_duration: float = 0.0
var _external_knockback_remaining: float = 0.0
var _external_knockback_velocity: Vector2 = Vector2.ZERO
var _has_movement_bounds: bool = false
var _health_regen: float = 0.0
var _luck: float = 0.0
var _movement_bounds: Rect2 = Rect2()
var _move_speed: float = 0.0
var _max_energy: float = 0.0
var _max_life: float = 1.0
var _max_shield: float = 0.0
var _life_points: float = 1.0
var _owned_tag_counts: Dictionary = {}
var _overshield: float = 0.0
var _overshield_decay_rate: float = 0.05
var _overshield_snap_threshold: float = 1.0
var _pickup_range: float = 0.0
var _separation_radius: float = 0.0
var _shield_gate_max_duration: float = 0.5
var _shield_gate_remaining: float = 0.0
var _shield_recharge_delay: float = 4.0
var _shield_recharge_delay_remaining: float = 0.0
var _shield_recharge_rate: float = 25.0
var _stat_additions: Dictionary = {}
var _stat_multipliers: Dictionary = {}
var _status_effect_component: Node = null
var _temporary_modifiers: Dictionary = {}
var _presentation: ActorPresentationController = null
var _slime_visual: Node2D = null
var _weapon_recoil_duration: float = 0.0
var _weapon_recoil_remaining: float = 0.0
var _weapon_recoil_velocity: Vector2 = Vector2.ZERO
var _weapon_recoil_velocity_cap: float = 0.0


func _ready() -> void:
	_ensure_status_effect_component()
	_ensure_presentation()
	_ensure_slime_visual()
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)
	_refresh_visuals()


func _exit_tree() -> void:
	if InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.disconnect(_on_input_action_pressed)


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		velocity = Vector2.ZERO
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		velocity = Vector2.ZERO
		return

	var suppress_recoil_movement: bool = is_dashing()
	_update_defense(scaled_delta)
	_update_dash_timers(scaled_delta)
	_update_temporary_modifiers(scaled_delta)
	_update_health_regen(scaled_delta)
	var recoil_velocity: Vector2 = _update_weapon_recoil(
		scaled_delta,
		suppress_recoil_movement
	)
	var external_knockback_velocity: Vector2 = _update_external_knockback(
		scaled_delta
	)

	var move_input: Vector2 = InputService.vector(ACTIONS.MOVE, INPUT_PARTICIPANT_ID)
	var aim_input: Vector2 = InputService.vector(ACTIONS.AIM, INPUT_PARTICIPANT_ID)
	if aim_input.length_squared() > 0.0:
		_set_aim_direction(aim_input)
	elif InputService.should_use_pointer_aim():
		_set_pointer_aim_from_viewport_position(InputService.pointer_viewport_position())
	InputService.publish_resolved_aim(aim_direction)

	if _dash_remaining > 0.0:
		velocity = (
			_dash_direction * _dash_speed
			+ external_knockback_velocity
		)
	else:
		velocity = (
			move_input * _effective_move_speed()
			+ recoil_velocity
			+ external_knockback_velocity
		)
	move_and_slide()
	_apply_movement_bounds()
	_advance_slime_visual(scaled_delta)


func configure(base_stats: Dictionary) -> void:
	_base_stats = base_stats.duplicate(true)
	_stat_additions.clear()
	_stat_multipliers.clear()
	_clear_status_effects_for_reuse()
	_camera_look_offset = Vector2.ZERO
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()
	_ensure_slime_visual()
	if _slime_visual != null and _slime_visual.has_method("reset_immediately"):
		_slime_visual.call("reset_immediately")
	_has_movement_bounds = false
	_dash_cooldown_remaining = 0.0
	_dash_direction = Vector2.ZERO
	_dash_invulnerability_remaining = 0.0
	_dash_remaining = 0.0
	_external_knockback_duration = 0.0
	_external_knockback_remaining = 0.0
	_external_knockback_velocity = Vector2.ZERO
	_debug_invulnerable = false
	_shield_gate_remaining = 0.0
	_shield_recharge_delay_remaining = 0.0
	_temporary_modifiers.clear()
	_weapon_recoil_duration = 0.0
	_weapon_recoil_remaining = 0.0
	_weapon_recoil_velocity = Vector2.ZERO
	_element_damage_taken_multipliers = _dictionary_or_empty(
		_base_stats.get("element_damage_taken_multipliers", {})
	)
	_rebuild_stats(true)
	add_to_group(ACTIVE_PLAYER_GROUP)


func current_life() -> float:
	return _life_points


func max_life() -> float:
	return _max_life


func current_shield() -> float:
	return _current_shield


func max_shield() -> float:
	return _max_shield


func current_overshield() -> float:
	return _overshield


func try_sacrifice_combined_health(
	amount: float,
	minimum_life: float = 1.0
) -> Dictionary:
	if not is_alive():
		return {
			"ok": false,
			"spent": 0.0,
			"reason": "not_alive",
		}
	if not is_finite(amount) or amount <= 0.0:
		return {
			"ok": false,
			"reason": "invalid_amount",
			"spent": 0.0,
		}
	var resolved_minimum_life: float = clampf(
		minimum_life,
		0.0,
		_max_life
	)
	var combined_health: float = (
		_life_points
		+ _current_shield
		+ _overshield
	)
	if combined_health - amount < resolved_minimum_life:
		return {
			"ok": false,
			"reason": "insufficient_combined_health",
			"spent": 0.0,
			"available": combined_health,
			"minimum_life": resolved_minimum_life,
		}

	var remaining: float = amount
	var overshield_spent: float = minf(_overshield, remaining)
	_overshield -= overshield_spent
	remaining -= overshield_spent
	var shield_spent: float = minf(_current_shield, remaining)
	_current_shield -= shield_spent
	remaining -= shield_spent
	var life_spent: float = minf(
		maxf(_life_points - resolved_minimum_life, 0.0),
		remaining
	)
	_life_points -= life_spent
	remaining -= life_spent
	var spent: float = amount - remaining
	if remaining > 0.001:
		_life_points += life_spent
		_current_shield += shield_spent
		_overshield += overshield_spent
		return {
			"ok": false,
			"reason": "sacrifice_incomplete",
			"spent": 0.0,
		}

	if shield_spent > 0.0:
		_shield_recharge_delay_remaining = _shield_recharge_delay
	life_changed.emit(_life_points, _max_life)
	_emit_shield_changed()
	_refresh_visuals()
	return {
		"ok": true,
		"reason": "",
		"spent": spent,
		"overshield_spent": overshield_spent,
		"shield_spent": shield_spent,
		"life_spent": life_spent,
		"life": _life_points,
		"shield": _current_shield,
		"overshield": _overshield,
	}


func max_energy() -> float:
	return _max_energy


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


func debug_set_shield(
	shield_points: float,
	overshield_points: float = 0.0
) -> Dictionary:
	_current_shield = clampf(shield_points, 0.0, _max_shield)
	_overshield = clampf(
		overshield_points,
		0.0,
		_overshield_capacity()
	)
	_shield_recharge_delay_remaining = 0.0
	_shield_gate_remaining = 0.0
	_emit_shield_changed()
	return {
		"shield": _current_shield,
		"max_shield": _max_shield,
		"overshield": _overshield,
	}


func debug_clear_invulnerability() -> void:
	_dash_invulnerability_remaining = 0.0
	_shield_gate_remaining = 0.0


func debug_set_invulnerable(enabled: bool) -> void:
	_debug_invulnerable = enabled
	if enabled:
		debug_clear_invulnerability()


func debug_is_invulnerable() -> bool:
	return _debug_invulnerable


func debug_reset_transient_state(world_position: Vector2) -> void:
	global_position = world_position
	velocity = Vector2.ZERO
	_debug_invulnerable = false
	_dash_cooldown_remaining = 0.0
	_dash_direction = Vector2.ZERO
	_dash_invulnerability_remaining = 0.0
	_dash_remaining = 0.0
	_external_knockback_duration = 0.0
	_external_knockback_remaining = 0.0
	_external_knockback_velocity = Vector2.ZERO
	_shield_gate_remaining = 0.0
	_shield_recharge_delay_remaining = 0.0
	_temporary_modifiers.clear()
	_clear_status_effects_for_reuse()
	_life_points = _max_life
	_current_shield = _max_shield
	_overshield = 0.0
	_apply_movement_bounds()
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()
	life_changed.emit(_life_points, _max_life)
	_emit_shield_changed()
	_refresh_visuals()


func invulnerability_remaining() -> float:
	return maxf(_dash_invulnerability_remaining, _shield_gate_remaining)


func dash_cooldown_remaining() -> float:
	return _dash_cooldown_remaining


func is_dashing() -> bool:
	return _dash_remaining > 0.0


func pickup_range() -> float:
	return _pickup_range


func luck() -> float:
	return _luck


func separation_radius() -> float:
	return _separation_radius


func hit_radius() -> float:
	return _body_radius


func stat_value(stat: String) -> float:
	return _stat_value(stat, 0.0)


func configure_element_damage_taken_multipliers(
	multipliers: Dictionary
) -> void:
	_element_damage_taken_multipliers.clear()
	for raw_element_id: Variant in multipliers.keys():
		var element_id: String = String(raw_element_id)
		var multiplier: float = clampf(
			float(multipliers[raw_element_id]),
			0.0,
			1.0
		)
		if not element_id.is_empty():
			_element_damage_taken_multipliers[element_id] = multiplier


func configure_runtime_rules(player_data: Dictionary) -> void:
	var body: Dictionary = _dictionary_or_empty(player_data.get("body", {}))
	var defense: Dictionary = _dictionary_or_empty(
		player_data.get("defense", {})
	)
	var shield: Dictionary = _dictionary_or_empty(
		defense.get("shield", {})
	)
	var armor: Dictionary = _dictionary_or_empty(defense.get("armor", {}))
	var shield_gate: Dictionary = _dictionary_or_empty(
		defense.get("shield_gate", {})
	)
	var dash: Dictionary = _dictionary_or_empty(player_data.get("dash", {}))
	_body_radius = maxf(
		float(body.get("radius", DEFAULT_BODY_RADIUS)),
		1.0
	)
	_apply_body_radius()
	_shield_recharge_delay = maxf(
		float(shield.get("recharge_delay", _shield_recharge_delay)),
		0.0
	)
	_shield_recharge_rate = maxf(
		float(shield.get("recharge_rate", _shield_recharge_rate)),
		0.0
	)
	_overshield_decay_rate = clampf(
		float(
			shield.get(
				"overshield_decay_ratio_per_second",
				_overshield_decay_rate
			)
		),
		0.0,
		0.99
	)
	_overshield_snap_threshold = maxf(
		float(
			shield.get(
				"overshield_snap_threshold",
				_overshield_snap_threshold
			)
		),
		0.0
	)
	_armor_coefficient = maxf(
		float(armor.get("coefficient", _armor_coefficient)),
		0.001
	)
	_armor_maximum = maxf(
		float(armor.get("maximum", _armor_maximum)),
		0.0
	)
	_armor = clampf(_armor, 0.0, _armor_maximum)
	_shield_gate_max_duration = maxf(
		float(
			shield_gate.get(
				"max_duration",
				_shield_gate_max_duration
			)
		),
		0.0
	)
	_dash_speed = maxf(float(dash.get("speed", _dash_speed)), 0.0)
	_dash_duration = maxf(
		float(dash.get("duration", _dash_duration)),
		0.0
	)
	_dash_cooldown = maxf(
		float(dash.get("cooldown", _dash_cooldown)),
		0.0
	)
	_dash_invulnerability_duration = clampf(
		float(
			dash.get(
				"invulnerability_duration",
				_dash_invulnerability_duration
			)
		),
		0.0,
		_dash_duration
	)


func configure_weapon_recoil(recoil_model: Dictionary) -> void:
	_weapon_recoil_velocity_cap = maxf(
		float(recoil_model.get("kickback_velocity_cap", 0.0)),
		0.0
	)


func apply_weapon_recoil(
	direction: Vector2,
	initial_speed: float,
	duration: float
) -> void:
	if is_dashing():
		return
	if (
		direction.length_squared() <= 0.0
		or initial_speed <= 0.0
		or duration <= 0.0
		or _weapon_recoil_velocity_cap <= 0.0
	):
		return
	_weapon_recoil_velocity += (
		-direction.normalized()
		* minf(initial_speed, _weapon_recoil_velocity_cap)
	)
	_weapon_recoil_velocity = _weapon_recoil_velocity.limit_length(
		_weapon_recoil_velocity_cap
	)
	_weapon_recoil_duration = maxf(duration, 0.0)
	_weapon_recoil_remaining = maxf(
		_weapon_recoil_remaining,
		_weapon_recoil_duration
	)


func weapon_recoil_velocity() -> Vector2:
	return _weapon_recoil_velocity


func weapon_recoil_remaining() -> float:
	return _weapon_recoil_remaining


func apply_external_knockback(
	direction: Vector2,
	distance: float,
	duration: float
) -> bool:
	if (
		not is_alive()
		or direction.length_squared() <= 0.0
		or distance <= 0.0
		or duration <= 0.0
	):
		return false
	_external_knockback_duration = duration
	_external_knockback_remaining = duration
	_external_knockback_velocity = (
		direction.normalized()
		* (distance * 2.0 / duration)
	)
	return true


func external_knockback_velocity() -> Vector2:
	return _external_knockback_velocity


func external_knockback_remaining() -> float:
	return _external_knockback_remaining


func set_element_damage_taken_multiplier(
	element_id: String,
	multiplier: float
) -> void:
	if element_id.is_empty():
		return
	_element_damage_taken_multipliers[element_id] = clampf(
		multiplier,
		0.0,
		1.0
	)


func add_overshield(amount: float) -> float:
	var requested_amount: float = maxf(amount, 0.0)
	if requested_amount <= 0.0:
		return 0.0
	var previous_overshield: float = _overshield
	_overshield = minf(
		_overshield + requested_amount,
		_overshield_capacity()
	)
	var applied_amount: float = _overshield - previous_overshield
	if applied_amount <= 0.0:
		return 0.0
	_emit_shield_changed()
	return applied_amount


func try_dash(direction: Vector2 = Vector2.ZERO) -> Dictionary:
	if not GameState.is_state(GameState.PLAYING):
		return _dash_result(false, "not_playing")
	if _dash_cooldown_remaining > 0.0 or _dash_remaining > 0.0:
		return _dash_result(false, "cooldown")
	var resolved_direction: Vector2 = direction
	if resolved_direction.length_squared() <= 0.0:
		resolved_direction = InputService.vector(
			ACTIONS.MOVE,
			INPUT_PARTICIPANT_ID
		)
	if resolved_direction.length_squared() <= 0.0:
		resolved_direction = aim_direction
	if resolved_direction.length_squared() <= 0.0:
		return _dash_result(false, "no_direction")
	_dash_direction = resolved_direction.normalized()
	_dash_remaining = _dash_duration
	_dash_cooldown_remaining = _dash_cooldown
	_dash_invulnerability_remaining = _dash_invulnerability_duration
	dash_started.emit(_dash_direction)
	return _dash_result(true, "started")


func apply_temporary_modifiers(
	modifiers: Array,
	duration: float,
	source_id: String
) -> void:
	var normalized_source: String = source_id
	if normalized_source.is_empty():
		normalized_source = "anonymous"
	var modifier_list: Array[Dictionary] = _typed_dictionary_array(modifiers)
	var remaining: float = maxf(duration, 0.0)
	if modifier_list.is_empty() or remaining <= 0.0:
		return
	_temporary_modifiers[normalized_source] = {
		"remaining": remaining,
		"modifiers": modifier_list,
	}
	_rebuild_stats(false)


func aim_at_world_position(world_position: Vector2) -> void:
	var mouse_direction: Vector2 = world_position - global_position
	if mouse_direction.length_squared() > MOUSE_AIM_MIN_DISTANCE_SQUARED:
		_set_aim_direction(mouse_direction)


func set_camera_look_offset(offset: Vector2) -> void:
	_camera_look_offset = offset


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


func status_summary() -> Array[Dictionary]:
	return _status_summary_from_snapshot(_status_effect_snapshot())


func status_stat_multiplier(stat_id: String) -> float:
	_ensure_status_effect_component()
	if (
		_status_effect_component == null
		or not _status_effect_component.has_method("stat_multiplier")
	):
		return 1.0
	return maxf(
		float(
			_status_effect_component.call(
				"stat_multiplier",
				stat_id
			)
		),
		0.0
	)


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"aim_direction": _vector_to_dict(aim_direction),
		"life_points": _life_points,
		"current_shield": _current_shield,
		"overshield": _overshield,
		"shield_recharge_delay_remaining": _shield_recharge_delay_remaining,
		"shield_gate_remaining": _shield_gate_remaining,
		"dash_cooldown_remaining": _dash_cooldown_remaining,
		"dash_direction": _vector_to_dict(_dash_direction),
		"dash_invulnerability_remaining": _dash_invulnerability_remaining,
		"dash_remaining": _dash_remaining,
		"weapon_recoil_velocity": _vector_to_dict(_weapon_recoil_velocity),
		"weapon_recoil_remaining": _weapon_recoil_remaining,
		"weapon_recoil_duration": _weapon_recoil_duration,
		"external_knockback_velocity": _vector_to_dict(
			_external_knockback_velocity
		),
		"external_knockback_remaining": _external_knockback_remaining,
		"external_knockback_duration": _external_knockback_duration,
		"element_damage_taken_multipliers": _element_damage_taken_multipliers.duplicate(true),
		"stat_additions": _stat_additions.duplicate(true),
		"stat_multipliers": _stat_multipliers.duplicate(true),
		"temporary_modifiers": _temporary_modifiers.duplicate(true),
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
	_current_shield = clampf(
		float(snapshot_data.get("current_shield", _max_shield)),
		0.0,
		_max_shield
	)
	_overshield = clampf(
		float(snapshot_data.get("overshield", 0.0)),
		0.0,
		_overshield_capacity()
	)
	_shield_recharge_delay_remaining = maxf(
		float(snapshot_data.get("shield_recharge_delay_remaining", 0.0)),
		0.0
	)
	_shield_gate_remaining = maxf(
		float(snapshot_data.get("shield_gate_remaining", 0.0)),
		0.0
	)
	_dash_cooldown_remaining = maxf(
		float(snapshot_data.get("dash_cooldown_remaining", 0.0)),
		0.0
	)
	_dash_direction = _dict_to_vector(
		snapshot_data.get("dash_direction", {}),
		Vector2.ZERO
	)
	_dash_invulnerability_remaining = maxf(
		float(snapshot_data.get("dash_invulnerability_remaining", 0.0)),
		0.0
	)
	_dash_remaining = maxf(
		float(snapshot_data.get("dash_remaining", 0.0)),
		0.0
	)
	_weapon_recoil_velocity = _dict_to_vector(
		snapshot_data.get("weapon_recoil_velocity", {}),
		Vector2.ZERO
	).limit_length(_weapon_recoil_velocity_cap)
	_weapon_recoil_remaining = maxf(
		float(snapshot_data.get("weapon_recoil_remaining", 0.0)),
		0.0
	)
	_weapon_recoil_duration = maxf(
		float(snapshot_data.get("weapon_recoil_duration", 0.0)),
		0.0
	)
	if _weapon_recoil_duration <= 0.0 or _weapon_recoil_remaining <= 0.0:
		_weapon_recoil_duration = 0.0
		_weapon_recoil_remaining = 0.0
		_weapon_recoil_velocity = Vector2.ZERO
	else:
		_weapon_recoil_remaining = minf(
			_weapon_recoil_remaining,
			_weapon_recoil_duration
		)
	_external_knockback_velocity = _dict_to_vector(
		snapshot_data.get("external_knockback_velocity", {}),
		Vector2.ZERO
	)
	_external_knockback_remaining = maxf(
		float(snapshot_data.get("external_knockback_remaining", 0.0)),
		0.0
	)
	_external_knockback_duration = maxf(
		float(snapshot_data.get("external_knockback_duration", 0.0)),
		0.0
	)
	if (
		_external_knockback_duration <= 0.0
		or _external_knockback_remaining <= 0.0
	):
		_external_knockback_duration = 0.0
		_external_knockback_remaining = 0.0
		_external_knockback_velocity = Vector2.ZERO
	else:
		_external_knockback_remaining = minf(
			_external_knockback_remaining,
			_external_knockback_duration
		)
	_element_damage_taken_multipliers = _dictionary_or_empty(
		snapshot_data.get(
			"element_damage_taken_multipliers",
			_element_damage_taken_multipliers
		)
	)
	_temporary_modifiers = _dictionary_or_empty(
		snapshot_data.get("temporary_modifiers", {})
	)
	_rebuild_stats(false)
	_restore_status_snapshot(snapshot_data)
	_apply_movement_bounds()
	life_changed.emit(_life_points, _max_life)
	_emit_shield_changed()
	_refresh_visuals()


func receive_damage(info: RefCounted) -> Dictionary:
	if _debug_invulnerable:
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": false,
			"reason": "debug_invulnerable",
		}
	if invulnerability_remaining() > 0.0:
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": false,
			"reason": "invulnerable",
		}

	var remaining_damage: float = maxf(float(info.get("amount")), 0.0)
	var applied_amount: float = 0.0
	if _overshield > 0.0 and remaining_damage > 0.0:
		var overshield_damage: float = minf(remaining_damage, _overshield)
		_overshield -= overshield_damage
		remaining_damage -= overshield_damage
		applied_amount += overshield_damage

	if _current_shield > 0.0 and remaining_damage > 0.0:
		var shield_before_hit: float = _current_shield
		var shield_damage: float = minf(remaining_damage, _current_shield)
		_current_shield -= shield_damage
		remaining_damage -= shield_damage
		applied_amount += shield_damage
		_shield_recharge_delay_remaining = _shield_recharge_delay
		if _current_shield <= 0.0:
			_current_shield = 0.0
			remaining_damage = 0.0
			_start_shield_gate(shield_before_hit)

	if remaining_damage > 0.0:
		var element_id: String = String(info.get("element_id"))
		var element_multiplier: float = float(
			_element_damage_taken_multipliers.get(element_id, 1.0)
		)
		var health_damage: float = (
			remaining_damage
			* clampf(element_multiplier, 0.0, 1.0)
			* _armor_damage_multiplier()
		)
		var applied_health_damage: float = minf(health_damage, _life_points)
		_life_points = maxf(_life_points - health_damage, 0.0)
		applied_amount += applied_health_damage
	var is_defeated: bool = _life_points <= 0.0
	_start_hit_flash()
	life_changed.emit(_life_points, _max_life)
	_emit_shield_changed()
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

func _rebuild_stats(reset_life: bool) -> void:
	var previous_max_life: float = _max_life
	var previous_max_shield: float = _max_shield
	_move_speed = _stat_value(STATS.MOVE_SPEED, 0.0)
	_max_life = _stat_value(STATS.MAX_HP, 1.0)
	_max_shield = maxf(_stat_value(STATS.MAX_SHIELD, 0.0), 0.0)
	_max_energy = maxf(_stat_value(STATS.MAX_ENERGY, 0.0), 0.0)
	_armor = clampf(
		_stat_value(STATS.ARMOR, 0.0),
		0.0,
		_armor_maximum
	)
	_health_regen = _stat_value(STATS.HEALTH_REGEN, 0.0)
	_separation_radius = _stat_value(STATS.PLAYER_SEPARATION_RADIUS, 0.0)
	_pickup_range = _stat_value(STATS.PICKUP_RANGE, 0.0)
	_luck = _stat_value(STATS.LUCK, 0.0)
	if reset_life:
		_life_points = _max_life
		_current_shield = _max_shield
		_overshield = 0.0
	elif _max_life > previous_max_life:
		_life_points += _max_life - previous_max_life
	if not reset_life and _max_shield > previous_max_shield:
		_current_shield += _max_shield - previous_max_shield
	_life_points = minf(_life_points, _max_life)
	_current_shield = minf(_current_shield, _max_shield)
	_overshield = minf(_overshield, _overshield_capacity())
	_read_runtime_tunables()
	life_changed.emit(_life_points, _max_life)
	_emit_shield_changed()


func _update_health_regen(delta: float) -> void:
	if _health_regen <= 0.0 or _life_points <= 0.0 or _life_points >= _max_life:
		return
	var previous_life: float = _life_points
	_life_points = minf(_life_points + _health_regen * delta, _max_life)
	if not is_equal_approx(_life_points, previous_life):
		life_changed.emit(_life_points, _max_life)


func _on_input_action_pressed(
	action_id: StringName,
	participant_id: String
) -> void:
	if (
		participant_id == INPUT_PARTICIPANT_ID
		and action_id == StringName(ACTIONS.DASH)
	):
		try_dash()


func _update_defense(delta: float) -> void:
	_dash_invulnerability_remaining = maxf(
		_dash_invulnerability_remaining - delta,
		0.0
	)
	_shield_gate_remaining = maxf(_shield_gate_remaining - delta, 0.0)
	_decay_overshield(delta)
	if _shield_recharge_delay_remaining > 0.0:
		_shield_recharge_delay_remaining = maxf(
			_shield_recharge_delay_remaining - delta,
			0.0
		)
		return
	if _current_shield >= _max_shield or _shield_recharge_rate <= 0.0:
		return
	var previous_shield: float = _current_shield
	_current_shield = minf(
		_current_shield + _shield_recharge_rate * delta,
		_max_shield
	)
	if not is_equal_approx(previous_shield, _current_shield):
		_emit_shield_changed()


func _decay_overshield(delta: float) -> void:
	if _overshield <= 0.0 or _overshield_decay_rate <= 0.0:
		return
	var previous_overshield: float = _overshield
	_overshield *= pow(1.0 - _overshield_decay_rate, delta)
	if _overshield < _overshield_snap_threshold:
		_overshield = 0.0
	if not is_equal_approx(previous_overshield, _overshield):
		_emit_shield_changed()


func _overshield_capacity() -> float:
	return maxf(_max_life + _max_shield, 0.0)


func _update_dash_timers(delta: float) -> void:
	_dash_cooldown_remaining = maxf(_dash_cooldown_remaining - delta, 0.0)
	if _dash_remaining <= 0.0:
		return
	_dash_remaining = maxf(_dash_remaining - delta, 0.0)
	if _dash_remaining <= 0.0:
		dash_finished.emit()


func _update_weapon_recoil(
	delta: float,
	suppress_movement: bool = false
) -> Vector2:
	if (
		_weapon_recoil_remaining <= 0.0
		or _weapon_recoil_velocity.length_squared() <= 0.0
		or delta <= 0.0
	):
		_weapon_recoil_duration = 0.0
		_weapon_recoil_remaining = 0.0
		_weapon_recoil_velocity = Vector2.ZERO
		return Vector2.ZERO
	var elapsed: float = minf(delta, _weapon_recoil_remaining)
	var previous_velocity: Vector2 = _weapon_recoil_velocity
	var next_remaining: float = maxf(
		_weapon_recoil_remaining - elapsed,
		0.0
	)
	var remaining_ratio: float = (
		next_remaining / _weapon_recoil_remaining
		if _weapon_recoil_remaining > 0.0
		else 0.0
	)
	_weapon_recoil_velocity *= remaining_ratio
	_weapon_recoil_remaining = next_remaining
	var average_velocity: Vector2 = (
		(previous_velocity + _weapon_recoil_velocity) * 0.5
		* (elapsed / delta)
	)
	if _weapon_recoil_remaining <= 0.0:
		_weapon_recoil_duration = 0.0
		_weapon_recoil_velocity = Vector2.ZERO
	if suppress_movement or is_dashing():
		return Vector2.ZERO
	return average_velocity


func _update_external_knockback(delta: float) -> Vector2:
	if (
		_external_knockback_remaining <= 0.0
		or _external_knockback_velocity.length_squared() <= 0.0
		or delta <= 0.0
	):
		_external_knockback_duration = 0.0
		_external_knockback_remaining = 0.0
		_external_knockback_velocity = Vector2.ZERO
		return Vector2.ZERO
	var elapsed: float = minf(delta, _external_knockback_remaining)
	var previous_velocity: Vector2 = _external_knockback_velocity
	var next_remaining: float = maxf(
		_external_knockback_remaining - elapsed,
		0.0
	)
	var remaining_ratio: float = (
		next_remaining / _external_knockback_remaining
		if _external_knockback_remaining > 0.0
		else 0.0
	)
	_external_knockback_velocity *= remaining_ratio
	_external_knockback_remaining = next_remaining
	var average_velocity: Vector2 = (
		(previous_velocity + _external_knockback_velocity) * 0.5
		* (elapsed / delta)
	)
	if _external_knockback_remaining <= 0.0:
		_external_knockback_duration = 0.0
		_external_knockback_velocity = Vector2.ZERO
	return average_velocity


func _update_temporary_modifiers(delta: float) -> void:
	var expired_sources: Array[String] = []
	for raw_source_id: Variant in _temporary_modifiers.keys():
		var source_id: String = String(raw_source_id)
		var entry: Dictionary = _temporary_modifiers[raw_source_id] as Dictionary
		var remaining: float = maxf(
			float(entry.get("remaining", 0.0)) - delta,
			0.0
		)
		if remaining <= 0.0:
			expired_sources.append(source_id)
		else:
			entry["remaining"] = remaining
			_temporary_modifiers[raw_source_id] = entry
	if expired_sources.is_empty():
		return
	for source_id: String in expired_sources:
		_temporary_modifiers.erase(source_id)
	_rebuild_stats(false)


func _effective_move_speed() -> float:
	return _move_speed * status_stat_multiplier(STATS.MOVE_SPEED)


func _start_shield_gate(shield_before_hit: float) -> void:
	if _max_shield <= 0.0 or shield_before_hit <= 0.0:
		return
	_shield_gate_remaining = maxf(
		_shield_gate_remaining,
		_shield_gate_max_duration
		* clampf(shield_before_hit / _max_shield, 0.0, 1.0)
	)


func _armor_damage_multiplier() -> float:
	if _armor <= 0.0:
		return 1.0
	var damage_reduction: float = clampf(
		_armor / (_armor + _armor_coefficient),
		0.0,
		(
			_armor_maximum
			/ (_armor_maximum + _armor_coefficient)
			if _armor_maximum > 0.0
			else 0.0
		)
	)
	return 1.0 - damage_reduction


func _read_runtime_tunables() -> void:
	_shield_recharge_delay = maxf(
		float(_base_stats.get("shield_recharge_delay", 4.0)),
		0.0
	)
	_shield_recharge_rate = maxf(
		float(_base_stats.get("shield_recharge_rate", 25.0)),
		0.0
	)
	_overshield_decay_rate = clampf(
		float(_base_stats.get("overshield_decay_rate", 0.05)),
		0.0,
		0.99
	)
	_overshield_snap_threshold = maxf(
		float(_base_stats.get("overshield_snap_threshold", 1.0)),
		0.0
	)
	_shield_gate_max_duration = maxf(
		float(_base_stats.get("shield_gate_max_duration", 0.5)),
		0.0
	)
	_dash_speed = maxf(float(_base_stats.get("dash_speed", 750.0)), 0.0)
	_dash_duration = maxf(float(_base_stats.get("dash_duration", 0.16)), 0.0)
	_dash_cooldown = maxf(float(_base_stats.get("dash_cooldown", 1.25)), 0.0)
	_dash_invulnerability_duration = clampf(
		float(_base_stats.get("dash_invulnerability_duration", 0.12)),
		0.0,
		_dash_duration
	)


func _emit_shield_changed() -> void:
	shield_changed.emit(_current_shield, _max_shield, _overshield)


func _dash_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"cooldown": _dash_cooldown_remaining,
		"remaining": _dash_remaining,
		"direction": _vector_to_dict(_dash_direction),
	}


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
		Color.WHITE,
		hurt_flash_color,
		hurt_flash_color,
		Vector2.ONE
	)
	_presentation.set_direction(aim_direction)


func _ensure_presentation() -> void:
	if _presentation != null and is_instance_valid(_presentation):
		return
	_presentation = get_node_or_null("Presentation") as ActorPresentationController
	if _presentation == null:
		push_error("[Player] missing scene-authored Presentation")


func _ensure_slime_visual() -> void:
	if _slime_visual != null and is_instance_valid(_slime_visual):
		return
	_slime_visual = null
	var candidate: Node2D = get_node_or_null("Visual") as Node2D
	if (
		candidate == null
		or not candidate.has_method("advance_visual")
		or not candidate.has_method("configure_radius")
	):
		push_error("[Player] missing scene-authored PlayerSlimeVisual")
		return
	_slime_visual = candidate


func _apply_body_radius() -> void:
	var collision: CollisionShape2D = (
		get_node_or_null("CollisionShape2D") as CollisionShape2D
	)
	if collision == null:
		push_error("[Player] missing CollisionShape2D")
		return
	var circle: CircleShape2D = collision.shape as CircleShape2D
	if circle == null:
		push_error("[Player] CollisionShape2D must use CircleShape2D")
		return
	circle.radius = _body_radius
	_ensure_slime_visual()
	if _slime_visual != null and _slime_visual.has_method("configure_radius"):
		_slime_visual.call("configure_radius", _body_radius)


func _advance_slime_visual(delta: float) -> void:
	_ensure_slime_visual()
	if _slime_visual == null or not _slime_visual.has_method("advance_visual"):
		return
	_slime_visual.call("advance_visual", delta, velocity, aim_direction)


func _set_pointer_aim_from_viewport_position(viewport_position: Vector2) -> void:
	var viewport_offset: Vector2 = viewport_position - get_viewport().get_visible_rect().size * 0.5
	var camera: Camera2D = get_viewport().get_camera_2d()
	var world_viewport_offset: Vector2 = viewport_offset
	if camera != null:
		world_viewport_offset = Vector2(
			viewport_offset.x / camera.zoom.x,
			viewport_offset.y / camera.zoom.y
		).rotated(camera.global_rotation)
	var mouse_direction: Vector2 = world_viewport_offset + _camera_look_offset
	if mouse_direction.length_squared() > MOUSE_AIM_MIN_DISTANCE_SQUARED:
		_set_aim_direction(mouse_direction)


func _apply_movement_bounds() -> void:
	if not _has_movement_bounds:
		return
	global_position = Vector2(
		_clamp_axis_to_radius_bounds(
			global_position.x,
			_movement_bounds.position.x,
			_movement_bounds.end.x
		),
		_clamp_axis_to_radius_bounds(
			global_position.y,
			_movement_bounds.position.y,
			_movement_bounds.end.y
		)
	)


func _clamp_axis_to_radius_bounds(
	value: float,
	minimum: float,
	maximum: float
) -> float:
	if maximum - minimum < _body_radius * 2.0:
		return (minimum + maximum) * 0.5
	return clampf(value, minimum + _body_radius, maximum - _body_radius)

func _stat_value(stat: String, default_value: float) -> float:
	var base_value: float = float(_base_stats.get(stat, default_value))
	var added_value: float = float(_stat_additions.get(stat, 0.0))
	var multiplier: float = float(_stat_multipliers.get(stat, 1.0))
	for entry: Variant in _temporary_modifiers.values():
		if not entry is Dictionary:
			continue
		for modifier: Dictionary in _typed_dictionary_array(
			(entry as Dictionary).get("modifiers", [])
		):
			if String(modifier.get("stat", "")) != stat:
				continue
			var modifier_type: String = String(modifier.get("type", ""))
			if modifier_type == "add":
				added_value += float(modifier.get("value", 0.0))
			elif modifier_type == "mult":
				multiplier *= float(modifier.get("value", 1.0))
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


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


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


func _status_summary_from_snapshot(
	snapshot_data: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_effects: Variant = snapshot_data.get("effects", [])
	if not raw_effects is Array:
		return result
	for raw_effect: Variant in raw_effects as Array:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect as Dictionary
		var status_id: String = String(effect.get("status", ""))
		if status_id.is_empty():
			continue
		result.append({
			"id": status_id,
			"name_key": "status_%s_name" % status_id,
			"stacks": maxi(int(effect.get("stack_count", 1)), 1),
			"remaining": maxf(float(effect.get("remaining", 0.0)), 0.0),
		})
	return result


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
