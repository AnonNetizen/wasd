# Doc: docs/代码/skill_system.md
# Authority: docs/游戏设计文档.md §9.15, docs/词表与契约.md §9-A~§9-B, §12-C~§12-G
class_name SkillSystem
extends Node


signal skill_cast(skill_id: String, result: Dictionary)
signal skill_failed(skill_id: String, result: Dictionary)
signal resource_changed(
	resource_id: String,
	current_amount: float,
	maximum_amount: float
)

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SKILL_EFFECTS := preload("res://scripts/contracts/skill_effects.gd")
const SKILL_RESOURCES := preload("res://scripts/contracts/skill_resources.gd")
const SKILL_SLOTS := preload("res://scripts/contracts/skill_slots.gd")
const SKILL_TARGETING := preload("res://scripts/contracts/skill_targeting.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const STATUS_EFFECT_SCRIPT := preload("res://scripts/combat/status_effect.gd")

const INPUT_PARTICIPANT_ID: String = "player_0"
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"
const SLOT_IDS: Array[String] = [
	SKILL_SLOTS.SKILL_1,
	SKILL_SLOTS.SKILL_2,
	SKILL_SLOTS.SKILL_3,
	SKILL_SLOTS.SKILL_4,
]

var _active_parent: Node = null
var _caster: Node2D = null
var _cooldowns: Dictionary = {}
var _debug_free_casts: bool = false
var _deployables_by_slot: Dictionary = {}
var _owned_tag_counts: Dictionary = {}
var _resources: Dictionary = {}
var _skills: Array[Dictionary] = []
var _status_effect_component: Node = null


func _ready() -> void:
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)


func _exit_tree() -> void:
	if InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.disconnect(_on_input_action_pressed)
	_clear_deployables()


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return
	_update_cooldowns(scaled_delta)
	_update_resources(scaled_delta)


func configure(
	caster: Node2D,
	active_parent: Node,
	skills: Variant,
	resources: Array
) -> void:
	_caster = caster
	_active_parent = active_parent
	_skills.clear()
	_cooldowns.clear()
	_debug_free_casts = false
	_clear_deployables()
	_ensure_status_effect_component()
	if _status_effect_component != null:
		_status_effect_component.call("clear", false)
	_owned_tag_counts.clear()
	var skill_index: int = 0
	for skill: Dictionary in _normalized_skill_definitions(skills):
		if skill_index >= SLOT_IDS.size():
			break
		var skill_copy: Dictionary = skill.duplicate(true)
		var slot_id: String = String(
			skill_copy.get("slot_id", SLOT_IDS[skill_index])
		)
		if not SLOT_IDS.has(slot_id):
			slot_id = SLOT_IDS[skill_index]
		skill_copy["slot_id"] = slot_id
		skill_copy["cost_multiplier"] = maxf(
			float(skill_copy.get("cost_multiplier", 1.0)),
			0.0
		)
		skill_copy["cooldown_multiplier"] = maxf(
			float(skill_copy.get("cooldown_multiplier", 1.0)),
			0.0
		)
		_skills.append(skill_copy)
		_cooldowns[slot_id] = 0.0
		skill_index += 1
	_configure_resources(resources)
	if _resources.is_empty() and _caster != null:
		var maximum_energy: float = maxf(
			float(_caster.call("max_energy"))
			if _caster.has_method("max_energy")
			else 0.0,
			0.0
		)
		if maximum_energy > 0.0:
			_resources[SKILL_RESOURCES.ENERGY] = {
				"max": maximum_energy,
				"current": maximum_energy,
				"regen_per_second": 0.0,
			}


func cast_primary_skill() -> Dictionary:
	return cast_slot(SLOT_IDS[0])


func cast_slot(slot_id: String) -> Dictionary:
	var skill: Dictionary = _skill_by_slot(slot_id)
	if skill.is_empty():
		return _failed_cast("", "no_skill", {"slot_id": slot_id})
	var skill_id: String = String(skill.get("id", ""))
	if _caster == null or not is_instance_valid(_caster):
		return _failed_cast(
			skill_id,
			"caster_unavailable",
			{"slot_id": slot_id}
		)
	if not _debug_free_casts and cooldown_remaining(slot_id) > 0.0:
		return _failed_cast(skill_id, "cooldown", {"slot_id": slot_id})
	var tag_check: Dictionary = _activation_tag_check(skill)
	if not bool(tag_check.get("ok", false)):
		return _failed_cast(skill_id, String(tag_check.get("reason", "tag_blocked")), {
			"slot_id": slot_id,
			"tag": String(tag_check.get("tag", "")),
			"owned_tags": owned_tags(),
		})
	if not _debug_free_casts and not _can_pay_costs(skill):
		return _failed_cast(
			skill_id,
			"insufficient_resource",
			{"slot_id": slot_id}
		)

	var targets: Array[Node] = _targets_for_skill(skill)
	if targets.is_empty():
		return _failed_cast(skill_id, "no_targets", {"slot_id": slot_id})

	if not _debug_free_casts:
		_pay_costs(skill)
	var transient_tags: Array[String] = _activation_tags(
		skill,
		"granted_tags"
	)
	_add_transient_tags(transient_tags)
	var applied_targets: int = _apply_effects(skill, targets, slot_id)
	_remove_transient_tags(transient_tags)
	_cooldowns[slot_id] = (
		0.0
		if _debug_free_casts
		else (
			maxf(float(skill.get("cooldown", 0.0)), 0.0)
			* maxf(float(skill.get("cooldown_multiplier", 1.0)), 0.0)
		)
	)
	var result: Dictionary = {
		"ok": applied_targets > 0,
		"reason": "applied" if applied_targets > 0 else "no_effect",
		"skill_id": skill_id,
		"slot_id": slot_id,
		"ability_tags": _string_array(skill.get("ability_tags", [])),
		"target_count": targets.size(),
		"applied_targets": applied_targets,
		"resources": resource_snapshot(),
		"cooldown": cooldown_remaining(slot_id),
		"owned_tags": owned_tags(),
		"presentation_profile_id": String(
			skill.get("presentation_profile_id", "")
		),
	}
	skill_cast.emit(skill_id, result.duplicate(true))
	return result


func cast_skill(skill_id: String) -> Dictionary:
	for skill: Dictionary in _skills:
		if String(skill.get("id", "")) == skill_id:
			return cast_slot(String(skill.get("slot_id", "")))
	return _failed_cast(skill_id, "unknown_skill")


func cooldown_remaining(slot_or_skill_id: String) -> float:
	if _cooldowns.has(slot_or_skill_id):
		return maxf(float(_cooldowns[slot_or_skill_id]), 0.0)
	var skill: Dictionary = _skill_by_id(slot_or_skill_id)
	if skill.is_empty():
		return 0.0
	return maxf(
		float(_cooldowns.get(String(skill.get("slot_id", "")), 0.0)),
		0.0
	)


func resource_amount(resource_id: String) -> float:
	var resource: Dictionary = _resources.get(resource_id, {}) as Dictionary
	return float(resource.get("current", 0.0))


func resource_maximum(resource_id: String) -> float:
	var resource: Dictionary = _resources.get(resource_id, {}) as Dictionary
	return float(resource.get("max", 0.0))


func add_resource(resource_id: String, amount: float) -> Dictionary:
	if not _resources.has(resource_id):
		return {
			"ok": false,
			"reason": "unknown_resource",
			"applied_amount": 0.0,
		}
	var resource: Dictionary = _resources[resource_id] as Dictionary
	var previous_amount: float = float(resource.get("current", 0.0))
	var maximum: float = float(resource.get("max", 0.0))
	var next_amount: float = clampf(
		previous_amount + maxf(amount, 0.0),
		0.0,
		maximum
	)
	resource["current"] = next_amount
	_resources[resource_id] = resource
	var applied_amount: float = next_amount - previous_amount
	if applied_amount > 0.0:
		resource_changed.emit(resource_id, next_amount, maximum)
	return {
		"ok": applied_amount > 0.0,
		"reason": "applied" if applied_amount > 0.0 else "full",
		"applied_amount": applied_amount,
		"current": next_amount,
		"max": maximum,
	}


func resource_snapshot() -> Dictionary:
	return _resources.duplicate(true)


func debug_set_free_casts(enabled: bool) -> void:
	_debug_free_casts = enabled
	if enabled:
		debug_refresh()


func debug_free_casts_enabled() -> bool:
	return _debug_free_casts


func debug_refresh() -> void:
	for slot_id: Variant in _cooldowns.keys():
		_cooldowns[slot_id] = 0.0
	for resource_id: Variant in _resources.keys():
		var resource: Dictionary = _resources[resource_id] as Dictionary
		resource["current"] = float(resource.get("max", 0.0))
		_resources[resource_id] = resource
		resource_changed.emit(
			String(resource_id),
			float(resource.get("current", 0.0)),
			float(resource.get("max", 0.0))
		)


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
		return _result(false, "status_component_unavailable")
	return _status_effect_component.call("apply", status_effect) as Dictionary


func snapshot() -> Dictionary:
	return {
		"cooldowns": _cooldowns.duplicate(true),
		"resources": _resources.duplicate(true),
		"owned_tag_counts": _owned_tag_counts.duplicate(true),
		"status_effects": _status_effect_snapshot(),
		"deployables": _deployable_snapshots(),
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_ensure_status_effect_component()
	if _status_effect_component != null:
		_status_effect_component.call("clear", false)
	_clear_deployables()

	var raw_cooldowns: Variant = snapshot_data.get("cooldowns", {})
	if raw_cooldowns is Dictionary:
		for raw_key: Variant in (raw_cooldowns as Dictionary).keys():
			var key: String = String(raw_key)
			if _cooldowns.has(key):
				_cooldowns[key] = maxf(
					float((raw_cooldowns as Dictionary)[raw_key]),
					0.0
				)
				continue
			var legacy_skill: Dictionary = _skill_by_id(key)
			if not legacy_skill.is_empty():
				_cooldowns[String(legacy_skill.get("slot_id", ""))] = maxf(
					float((raw_cooldowns as Dictionary)[raw_key]),
					0.0
				)

	var raw_resources: Variant = snapshot_data.get("resources", {})
	if raw_resources is Dictionary:
		for resource_id: Variant in (raw_resources as Dictionary).keys():
			var key: String = String(resource_id)
			if not _resources.has(key):
				continue
			var restored: Variant = (raw_resources as Dictionary)[resource_id]
			if not restored is Dictionary:
				continue
			var resource: Dictionary = _resources[key] as Dictionary
			resource["current"] = clampf(
				float(
					(restored as Dictionary).get(
						"current",
						resource.get("current", 0.0)
					)
				),
				0.0,
				float(resource.get("max", 0.0))
			)
			_resources[key] = resource
			resource_changed.emit(
				key,
				float(resource.get("current", 0.0)),
				float(resource.get("max", 0.0))
			)

	_owned_tag_counts.clear()
	var raw_tag_counts: Variant = snapshot_data.get(
		"owned_tag_counts",
		{}
	)
	var has_owned_tag_snapshot: bool = (
		snapshot_data.has("owned_tag_counts")
		and raw_tag_counts is Dictionary
	)
	if has_owned_tag_snapshot:
		for tag_id: Variant in (raw_tag_counts as Dictionary).keys():
			var count: int = maxi(
				int((raw_tag_counts as Dictionary)[tag_id]),
				0
			)
			var tag: String = String(tag_id)
			if count > 0 and _is_valid_ability_tag(tag):
				_owned_tag_counts[tag] = count
	else:
		var raw_owned_tags: Variant = snapshot_data.get("owned_tags", [])
		has_owned_tag_snapshot = raw_owned_tags is Array
		if raw_owned_tags is Array:
			for tag_id: Variant in raw_owned_tags as Array:
				_add_owned_tag_count(String(tag_id))

	var raw_status_effects: Variant = snapshot_data.get("status_effects", {})
	if _status_effect_component != null and raw_status_effects is Dictionary:
		_status_effect_component.call(
			"restore_snapshot",
			raw_status_effects,
			not has_owned_tag_snapshot
		)
	_restore_deployables(snapshot_data.get("deployables", []))


func debug_summary() -> Dictionary:
	return {
		"skill_ids": _skill_ids(),
		"skill_slots": _skill_slot_summary(),
		"resources": resource_snapshot(),
		"cooldowns": _cooldowns.duplicate(true),
		"debug_free_casts": _debug_free_casts,
		"owned_tags": owned_tags(),
		"owned_tag_counts": _owned_tag_counts.duplicate(true),
		"status_effects": _status_effect_snapshot(),
		"deployables": _deployable_snapshots(),
	}


func _on_input_action_pressed(
	action_id: StringName,
	participant_id: String
) -> void:
	if participant_id != INPUT_PARTICIPANT_ID:
		return
	if not GameState.is_state(GameState.PLAYING):
		return
	var slot_id: String = _slot_for_action(action_id)
	if not slot_id.is_empty():
		cast_slot(slot_id)


func _slot_for_action(action_id: StringName) -> String:
	if action_id == StringName(ACTIONS.SKILL_1):
		return SLOT_IDS[0]
	if action_id == StringName(ACTIONS.SKILL_2):
		return SLOT_IDS[1]
	if action_id == StringName(ACTIONS.SKILL_3):
		return SLOT_IDS[2]
	if action_id == StringName(ACTIONS.SKILL_4):
		return SLOT_IDS[3]
	return ""


func _failed_cast(
	skill_id: String,
	reason: String,
	extra: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = _result(false, reason, extra)
	result["skill_id"] = skill_id
	var skill: Dictionary = _skill_by_id(skill_id)
	result["presentation_profile_id"] = String(
		skill.get("presentation_profile_id", "")
	)
	skill_failed.emit(skill_id, result.duplicate(true))
	return result


func _configure_resources(resources: Array) -> void:
	_resources.clear()
	for resource: Dictionary in _typed_dictionary_array(resources):
		var resource_id: String = String(resource.get("id", ""))
		if resource_id.is_empty():
			continue
		var maximum: float = maxf(float(resource.get("max", 0.0)), 0.0)
		var max_stat: String = String(resource.get("max_stat", ""))
		if not max_stat.is_empty():
			maximum = maxf(_ability_stat_value(max_stat), 0.0)
		var start_amount: float = float(resource.get("start", maximum))
		if resource.has("start_ratio"):
			start_amount = maximum * clampf(
				float(resource.get("start_ratio", 1.0)),
				0.0,
				1.0
			)
		_resources[resource_id] = {
			"max": maximum,
			"current": clampf(
				start_amount,
				0.0,
				maximum
			),
			"regen_per_second": maxf(
				float(resource.get("regen_per_second", 0.0)),
				0.0
			),
		}


func _update_cooldowns(delta: float) -> void:
	for slot_id: Variant in _cooldowns.keys():
		_cooldowns[slot_id] = maxf(
			float(_cooldowns[slot_id]) - delta,
			0.0
		)


func _update_resources(delta: float) -> void:
	for resource_id: Variant in _resources.keys():
		var resource: Dictionary = _resources[resource_id] as Dictionary
		var maximum: float = float(resource.get("max", 0.0))
		var current: float = float(resource.get("current", 0.0))
		var regen: float = float(resource.get("regen_per_second", 0.0))
		var next_amount: float = minf(current + regen * delta, maximum)
		resource["current"] = next_amount
		_resources[resource_id] = resource
		if not is_equal_approx(current, next_amount):
			resource_changed.emit(String(resource_id), next_amount, maximum)


func _skill_by_id(skill_id: String) -> Dictionary:
	for skill: Dictionary in _skills:
		if String(skill.get("id", "")) == skill_id:
			return skill
	return {}


func _skill_by_slot(slot_id: String) -> Dictionary:
	for skill: Dictionary in _skills:
		if String(skill.get("slot_id", "")) == slot_id:
			return skill
	return {}


func _can_pay_costs(skill: Dictionary) -> bool:
	for cost: Dictionary in _typed_dictionary_array(skill.get("costs", [])):
		var resource_id: String = String(cost.get("resource", ""))
		var amount: float = _scaled_cost_amount(skill, cost)
		if amount <= 0.0:
			continue
		if not _resources.has(resource_id):
			return false
		var resource: Dictionary = _resources[resource_id] as Dictionary
		if float(resource.get("current", 0.0)) < amount:
			return false
	return true


func _pay_costs(skill: Dictionary) -> void:
	for cost: Dictionary in _typed_dictionary_array(skill.get("costs", [])):
		var resource_id: String = String(cost.get("resource", ""))
		var amount: float = _scaled_cost_amount(skill, cost)
		if amount <= 0.0 or not _resources.has(resource_id):
			continue
		var resource: Dictionary = _resources[resource_id] as Dictionary
		resource["current"] = maxf(
			float(resource.get("current", 0.0)) - amount,
			0.0
		)
		_resources[resource_id] = resource
		resource_changed.emit(
			resource_id,
			float(resource.get("current", 0.0)),
			float(resource.get("max", 0.0))
		)


func _scaled_cost_amount(
	skill: Dictionary,
	cost: Dictionary
) -> float:
	var amount: float = maxf(float(cost.get("amount", 0.0)), 0.0)
	var scaling: Dictionary = _dictionary_or_empty(
		skill.get("scaling", {})
	)
	var efficiency_stat: String = String(
		scaling.get("cost_stat", "")
	)
	if not efficiency_stat.is_empty():
		var efficiency: float = clampf(
			_ability_stat_value(efficiency_stat),
			0.25,
			1.75
		)
		amount *= clampf(2.0 - efficiency, 0.25, 1.75)
	amount *= maxf(float(skill.get("cost_multiplier", 1.0)), 0.0)
	return amount


func _activation_tag_check(skill: Dictionary) -> Dictionary:
	for tag_id: String in _activation_tags(skill, "required_tags"):
		if not has_owned_tag(tag_id):
			return {
				"ok": false,
				"reason": "missing_required_tag",
				"tag": tag_id,
			}
	for tag_id: String in _activation_tags(skill, "blocked_tags"):
		if has_owned_tag(tag_id):
			return {
				"ok": false,
				"reason": "blocked_by_tag",
				"tag": tag_id,
			}
	return {"ok": true}


func _activation_tags(skill: Dictionary, field: String) -> Array[String]:
	var activation: Dictionary = _dictionary_or_empty(
		skill.get("activation", {})
	)
	return _string_array(activation.get(field, []))


func _targets_for_skill(skill: Dictionary) -> Array[Node]:
	var targeting: Dictionary = _dictionary_or_empty(
		skill.get("targeting", {})
	)
	var targeting_type: String = String(targeting.get("type", ""))
	var radius: float = maxf(float(targeting.get("radius", 0.0)), 0.0)
	var scaling: Dictionary = _dictionary_or_empty(
		skill.get("scaling", {})
	)
	var radius_stat: String = String(scaling.get("radius_stat", ""))
	if not radius_stat.is_empty():
		radius *= maxf(_ability_stat_value(radius_stat), 0.0)
	var max_targets: int = maxi(int(targeting.get("max_targets", 0)), 0)
	if targeting_type == SKILL_TARGETING.AOE_ENEMIES_AROUND_CASTER:
		return _enemy_targets_in_radius(radius, max_targets)
	if targeting_type == SKILL_TARGETING.TARGET_ENEMY:
		return _enemy_targets_in_radius(radius, 1)
	if targeting_type == SKILL_TARGETING.TARGET_ALLY:
		var allies: Array[Node] = []
		if _caster != null and is_instance_valid(_caster):
			allies.append(_caster)
		return allies
	if (
		targeting_type == SKILL_TARGETING.TARGET_SELF
		or targeting_type == SKILL_TARGETING.TARGET_AIM_POSITION
	):
		var self_targets: Array[Node] = []
		if _caster != null and is_instance_valid(_caster):
			self_targets.append(_caster)
		return self_targets
	return []


func _enemy_targets_in_radius(
	radius: float,
	max_targets: int
) -> Array[Node]:
	var candidates: Array[Node2D] = []
	for raw_enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if not raw_enemy is Node2D:
			continue
		if not _is_active_world_entity(raw_enemy):
			continue
		if (
			raw_enemy.has_method("is_alive")
			and not bool(raw_enemy.call("is_alive"))
		):
			continue
		var enemy: Node2D = raw_enemy as Node2D
		if (
			radius > 0.0
			and _caster != null
			and _caster.global_position.distance_to(enemy.global_position)
			> radius
		):
			continue
		candidates.append(enemy)
	candidates.sort_custom(_sort_targets_by_distance)

	var result: Array[Node] = []
	for enemy: Node2D in candidates:
		if max_targets > 0 and result.size() >= max_targets:
			break
		result.append(enemy)
	return result


func _sort_targets_by_distance(left: Node2D, right: Node2D) -> bool:
	if _caster == null:
		return left.get_instance_id() < right.get_instance_id()
	var left_distance: float = _caster.global_position.distance_squared_to(
		left.global_position
	)
	var right_distance: float = _caster.global_position.distance_squared_to(
		right.global_position
	)
	if is_equal_approx(left_distance, right_distance):
		return left.get_instance_id() < right.get_instance_id()
	return left_distance < right_distance


func _apply_effects(
	skill: Dictionary,
	targets: Array[Node],
	slot_id: String
) -> int:
	var applied_targets: int = 0
	for effect: Dictionary in _typed_dictionary_array(
		skill.get("effects", [])
	):
		var effect_id: String = String(effect.get("effect", ""))
		if effect_id == SKILL_EFFECTS.SKILL_EFFECT_DAMAGE:
			applied_targets += _apply_damage_effect(
				skill,
				effect,
				targets
			)
		elif effect_id == SKILL_EFFECTS.SKILL_EFFECT_APPLY_STATUS:
			applied_targets += _apply_status_effect(
				skill,
				effect,
				targets
			)
		elif effect_id == SKILL_EFFECTS.SKILL_EFFECT_WEAPON_MODIFIERS:
			applied_targets += _apply_weapon_modifiers_effect(
				skill,
				effect,
				targets,
				slot_id
			)
		elif effect_id == SKILL_EFFECTS.SKILL_EFFECT_ACTOR_MODIFIERS:
			applied_targets += _apply_actor_modifiers_effect(
				skill,
				effect,
				targets,
				slot_id
			)
		elif effect_id == SKILL_EFFECTS.SKILL_EFFECT_DEPLOY_BARRIER:
			applied_targets += _apply_deploy_barrier_effect(
				skill,
				effect,
				slot_id
			)
	return applied_targets


func _apply_damage_effect(
	skill: Dictionary,
	effect: Dictionary,
	targets: Array[Node]
) -> int:
	var params: Dictionary = _scaled_effect_params(skill, effect)
	var amount: float = maxf(float(params.get("amount", 0.0)), 0.0)
	var element_id: String = String(params.get("element_id", ""))
	if amount <= 0.0 or element_id.is_empty():
		return 0

	var applied_targets: int = 0
	for target: Node in targets:
		var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
			amount,
			element_id,
			_caster,
			target,
			TEAM_PLAYER,
			TEAM_ENEMY
		)
		var result: Dictionary = Combat.apply_damage(target, info)
		if bool(result.get("applied", false)):
			applied_targets += 1
	return applied_targets


func _apply_status_effect(
	skill: Dictionary,
	effect: Dictionary,
	targets: Array[Node]
) -> int:
	var params: Dictionary = _scaled_effect_params(skill, effect)
	var status_id: String = String(params.get("status", ""))
	if status_id.is_empty():
		return 0

	var applied_targets: int = 0
	for target: Node in targets:
		var status_effect: Variant = STATUS_EFFECT_SCRIPT.new()
		status_effect.call("setup", status_id, params, _caster)
		var result: Dictionary = _apply_status_to_target(
			target,
			status_effect
		)
		if bool(result.get("applied", false)):
			applied_targets += 1
	return applied_targets


func _apply_weapon_modifiers_effect(
	skill: Dictionary,
	effect: Dictionary,
	targets: Array[Node],
	slot_id: String
) -> int:
	var params: Dictionary = _scaled_effect_params(skill, effect)
	return _apply_weapon_modifiers_to_targets(params, targets, slot_id)


func _apply_actor_modifiers_effect(
	skill: Dictionary,
	effect: Dictionary,
	targets: Array[Node],
	slot_id: String
) -> int:
	var params: Dictionary = _scaled_effect_params(skill, effect)
	var duration: float = maxf(float(params.get("duration", 0.0)), 0.0)
	var modifiers: Array = _array_or_empty(params.get("modifiers", []))
	if duration <= 0.0 or modifiers.is_empty():
		return 0
	var source_id: String = "skill:%s" % slot_id
	var applied_targets: int = 0
	for target: Node in targets:
		var applied_to_target: bool = false
		if target.has_method("apply_temporary_modifiers"):
			target.call(
				"apply_temporary_modifiers",
				modifiers,
				duration,
				source_id
			)
			applied_to_target = true
		var weapon_system: Node = target.get_node_or_null("WeaponSystem")
		if (
			weapon_system != null
			and weapon_system.has_method("apply_temporary_modifiers")
		):
			weapon_system.call(
				"apply_temporary_modifiers",
				modifiers,
				duration,
				source_id
			)
			applied_to_target = true
		if applied_to_target:
			applied_targets += 1
	return applied_targets


func _apply_weapon_modifiers_to_targets(
	params: Dictionary,
	targets: Array[Node],
	slot_id: String
) -> int:
	var duration: float = maxf(float(params.get("duration", 0.0)), 0.0)
	var modifiers: Array = _array_or_empty(params.get("modifiers", []))
	if duration <= 0.0 or modifiers.is_empty():
		return 0
	var applied_targets: int = 0
	for target: Node in targets:
		var weapon_system: Node = target.get_node_or_null("WeaponSystem")
		if (
			weapon_system == null
			or not weapon_system.has_method("apply_temporary_modifiers")
		):
			continue
		weapon_system.call(
			"apply_temporary_modifiers",
			modifiers,
			duration,
			"skill:%s" % slot_id
		)
		applied_targets += 1
	return applied_targets


func _apply_deploy_barrier_effect(
	skill: Dictionary,
	effect: Dictionary,
	slot_id: String
) -> int:
	if _caster == null or not is_instance_valid(_caster):
		return 0
	var params: Dictionary = _scaled_effect_params(skill, effect)
	var max_health: float = maxf(float(params.get("hp", 0.0)), 0.0)
	var radius: float = maxf(float(params.get("radius", 0.0)), 0.0)
	if max_health <= 0.0 or radius <= 0.0:
		return 0
	# The initial barrier skill is a global singleton for its caster. Keeping
	# ownership by slot in the snapshot still lets a later duplicate slot become
	# the new owner without leaving two barriers active.
	_clear_deployables()
	var pool_id: String = String(
		params.get("pool_id", POOL_IDS.PROJECTILE_BARRIER)
	)
	var pooled: bool = PoolManager.has_pool(pool_id)
	if not pooled:
		return 0
	var barrier: Node2D = null
	var pooled_node: Node = PoolManager.acquire(pool_id)
	if pooled_node is Node2D:
		barrier = pooled_node as Node2D
	if barrier == null or not barrier.has_method("configure"):
		return 0
	_reparent_to_active_world(barrier)
	barrier.global_position = _caster.global_position
	barrier.call(
		"configure",
		max_health,
		radius,
		_caster,
		slot_id,
		pooled
	)
	_deployables_by_slot[slot_id] = barrier
	return 1


func _scaled_effect_params(
	skill: Dictionary,
	effect: Dictionary
) -> Dictionary:
	var params: Dictionary = _dictionary_or_empty(effect.get("params", {}))
	var scaling: Dictionary = _dictionary_or_empty(
		skill.get("scaling", {})
	)
	var duration_stat: String = String(
		scaling.get("duration_stat", "")
	)
	if not duration_stat.is_empty() and params.has("duration"):
		params["duration"] = (
			float(params.get("duration", 0.0))
			* maxf(_ability_stat_value(duration_stat), 0.0)
		)
	var radius_stat: String = String(scaling.get("radius_stat", ""))
	if not radius_stat.is_empty() and params.has("radius"):
		params["radius"] = (
			float(params.get("radius", 0.0))
			* maxf(_ability_stat_value(radius_stat), 0.0)
		)
	var strength_stat: String = String(
		scaling.get("strength_stat", "")
	)
	if not strength_stat.is_empty():
		var strength: float = maxf(
			_ability_stat_value(strength_stat),
			0.0
		)
		if params.has("hp"):
			params["hp"] = float(params.get("hp", 0.0)) * strength
		if params.has("amount"):
			params["amount"] = (
				float(params.get("amount", 0.0)) * strength
			)
		if params.has("magnitude"):
			var magnitude: float = (
				float(params.get("magnitude", 0.0)) * strength
			)
			if params.has("magnitude_cap"):
				magnitude = minf(
					magnitude,
					float(params.get("magnitude_cap", magnitude))
				)
			params["magnitude"] = magnitude
		params["modifiers"] = _scaled_modifiers(
			params.get("modifiers", []),
			strength,
			float(params.get("magnitude", 0.0))
		)
	return params


func _scaled_modifiers(
	raw_modifiers: Variant,
	strength: float,
	scaled_magnitude: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for modifier: Dictionary in _typed_dictionary_array(raw_modifiers):
		var scale_mode: String = String(
			modifier.get("scale_mode", "")
		)
		if scale_mode == "inverse_from_magnitude":
			modifier["value"] = maxf(1.0 - scaled_magnitude, 0.0)
		elif String(modifier.get("type", "")) == "mult":
			var value: float = float(modifier.get("value", 1.0))
			modifier["value"] = 1.0 + (value - 1.0) * strength
		elif String(modifier.get("type", "")) == "add":
			modifier["value"] = (
				float(modifier.get("value", 0.0)) * strength
			)
		result.append(modifier)
	return result


func _ability_stat_value(stat_id: String) -> float:
	var value: float = 1.0
	if (
		_caster != null
		and is_instance_valid(_caster)
		and _caster.has_method("stat_value")
	):
		value = float(_caster.call("stat_value", stat_id))
	if stat_id == STATS.ABILITY_STRENGTH:
		return clampf(value, 0.25, 4.0)
	if stat_id == STATS.ABILITY_RANGE:
		return clampf(value, 0.25, 2.5)
	if stat_id == STATS.ABILITY_DURATION:
		return clampf(value, 0.25, 3.0)
	if stat_id == STATS.ABILITY_EFFICIENCY:
		return clampf(value, 0.25, 1.75)
	return value


func _apply_status_to_target(
	target: Node,
	status_effect: Variant
) -> Dictionary:
	if target == _caster:
		return apply_status_effect(status_effect)
	if target != null and target.has_method("apply_status_effect"):
		return target.call("apply_status_effect", status_effect) as Dictionary
	return _result(false, "status_target_unavailable")


func _is_active_world_entity(node: Node) -> bool:
	if node == null or _active_parent == null:
		return false
	return node == _active_parent or _active_parent.is_ancestor_of(node)


func _reparent_to_active_world(node: Node) -> void:
	if _active_parent == null:
		return
	var old_parent: Node = node.get_parent()
	if old_parent == _active_parent:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	_active_parent.add_child(node)


func _release_deployable(slot_id: String) -> void:
	if not _deployables_by_slot.has(slot_id):
		return
	var deployable: Variant = _deployables_by_slot[slot_id]
	_deployables_by_slot.erase(slot_id)
	if (
		deployable is Node
		and is_instance_valid(deployable)
		and (deployable as Node).has_method("dismiss")
	):
		(deployable as Node).call("dismiss")


func _clear_deployables() -> void:
	for raw_slot_id: Variant in _deployables_by_slot.keys():
		_release_deployable(String(raw_slot_id))
	_deployables_by_slot.clear()


func _deployable_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_id: String in _sorted_string_keys(_deployables_by_slot):
		var deployable: Variant = _deployables_by_slot[slot_id]
		if (
			not deployable is Node
			or not is_instance_valid(deployable)
			or not (deployable as Node).has_method("snapshot")
		):
			continue
		if (
			(deployable as Node).has_method("is_alive")
			and not bool((deployable as Node).call("is_alive"))
		):
			continue
		var deployable_snapshot: Dictionary = (
			(deployable as Node).call("snapshot") as Dictionary
		)
		deployable_snapshot["slot_id"] = slot_id
		result.append(deployable_snapshot)
	return result


func _restore_deployables(raw_snapshots: Variant) -> void:
	if not raw_snapshots is Array or _caster == null:
		return
	for raw_snapshot: Variant in raw_snapshots as Array:
		if not raw_snapshot is Dictionary:
			continue
		var snapshot_data: Dictionary = raw_snapshot as Dictionary
		var slot_id: String = String(snapshot_data.get("slot_id", ""))
		if not SLOT_IDS.has(slot_id):
			continue
		var pool_id: String = POOL_IDS.PROJECTILE_BARRIER
		var pooled: bool = PoolManager.has_pool(pool_id)
		if not pooled:
			continue
		var barrier: Node2D = null
		var pooled_node: Node = PoolManager.acquire(pool_id)
		if pooled_node is Node2D:
			barrier = pooled_node as Node2D
		if barrier == null or not barrier.has_method("restore_snapshot"):
			continue
		_reparent_to_active_world(barrier)
		barrier.call("restore_snapshot", snapshot_data, _caster, pooled)
		_deployables_by_slot[slot_id] = barrier
		return


func _skill_ids() -> Array[String]:
	var result: Array[String] = []
	for skill: Dictionary in _skills:
		result.append(String(skill.get("id", "")))
	return result


func _skill_slot_summary() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for skill: Dictionary in _skills:
		var slot_id: String = String(skill.get("slot_id", ""))
		var energy_cost: float = 0.0
		for cost: Dictionary in _typed_dictionary_array(
			skill.get("costs", [])
		):
			if String(cost.get("resource", "")) == SKILL_RESOURCES.ENERGY:
				energy_cost = _scaled_cost_amount(skill, cost)
				break
		var remaining: float = cooldown_remaining(slot_id)
		result.append({
			"slot_id": slot_id,
			"skill_id": String(skill.get("id", "")),
			"name_key": String(skill.get("name_key", "")),
			"cooldown": remaining,
			"cooldown_remaining": remaining,
			"energy_cost": energy_cost,
		})
	return result


func _ensure_status_effect_component() -> void:
	if (
		_status_effect_component != null
		and is_instance_valid(_status_effect_component)
	):
		_status_effect_component.call(
			"configure_ability_tag_owner",
			self
		)
		return
	_status_effect_component = get_node_or_null("StatusEffectComponent")
	if _status_effect_component == null:
		push_error("[SkillSystem] missing scene-authored StatusEffectComponent")
		return
	_status_effect_component.call("configure_ability_tag_owner", self)


func _status_effect_snapshot() -> Dictionary:
	_ensure_status_effect_component()
	if _status_effect_component == null:
		return {}
	return _status_effect_component.call("snapshot") as Dictionary


func _add_transient_tags(tags: Array[String]) -> void:
	for tag_id: String in tags:
		_add_owned_tag_count(tag_id)


func _remove_transient_tags(tags: Array[String]) -> void:
	for tag_id: String in tags:
		_remove_owned_tag_count(tag_id)


func _add_owned_tag_count(tag_id: String) -> bool:
	if not _is_valid_ability_tag(tag_id):
		return false
	_owned_tag_counts[tag_id] = int(
		_owned_tag_counts.get(tag_id, 0)
	) + 1
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
	return not tag_id.is_empty() and ABILITY_TAGS.VALUES.has(tag_id)


func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source.keys():
		result.append(String(key))
	result.sort()
	return result


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		var value: String = String(item)
		if not value.is_empty():
			result.append(value)
	return result


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _normalized_skill_definitions(
	raw_value: Variant
) -> Array[Dictionary]:
	if raw_value is Array:
		return _typed_dictionary_array(raw_value)
	var result: Array[Dictionary] = []
	if not raw_value is Dictionary:
		return result
	for slot_id: String in SLOT_IDS:
		var raw_skill: Variant = (raw_value as Dictionary).get(slot_id, {})
		if not raw_skill is Dictionary:
			continue
		var skill: Dictionary = (raw_skill as Dictionary).duplicate(true)
		skill["slot_id"] = slot_id
		result.append(skill)
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _result(
	ok: bool,
	reason: String,
	extra: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = {
		"ok": ok,
		"reason": reason,
	}
	for key: Variant in extra.keys():
		result[key] = extra[key]
	return result
