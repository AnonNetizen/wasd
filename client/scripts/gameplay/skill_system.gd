# Doc: docs/代码/skill_system.md
# Authority: docs/词表与契约.md §9-A~§9-B, §12-C~12-G
class_name SkillSystem
extends Node


signal skill_cast(skill_id: String, result: Dictionary)

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const SKILL_EFFECTS := preload("res://scripts/contracts/skill_effects.gd")
const SKILL_TARGETING := preload("res://scripts/contracts/skill_targeting.gd")
const STATUS_EFFECT_SCRIPT := preload("res://scripts/combat/status_effect.gd")
const STATUS_EFFECT_COMPONENT_SCRIPT := preload("res://scripts/combat/status_effect_component.gd")

const REPLAY_PARTICIPANT_ID: String = "player_0"
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

var _active_parent: Node = null
var _caster: Node2D = null
var _cooldowns: Dictionary = {}
var _owned_tag_counts: Dictionary = {}
var _resources: Dictionary = {}
var _skills: Array[Dictionary] = []
var _status_effect_component: Node = null


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return
	_update_cooldowns(scaled_delta)
	_update_resources(scaled_delta)


func _unhandled_input(event: InputEvent) -> void:
	Replay.record_input_event(event, [ACTIONS.USE_ACTIVE_ITEM], REPLAY_PARTICIPANT_ID)
	if not GameState.is_state(GameState.PLAYING):
		return
	if event.is_action_pressed(ACTIONS.USE_ACTIVE_ITEM):
		get_viewport().set_input_as_handled()
		cast_primary_skill()


func configure(caster: Node2D, active_parent: Node, skills: Array, resources: Array) -> void:
	_caster = caster
	_active_parent = active_parent
	_skills = []
	_cooldowns.clear()
	_ensure_status_effect_component()
	if _status_effect_component != null:
		_status_effect_component.call("clear", false)
	_owned_tag_counts.clear()
	for skill: Dictionary in _typed_dictionary_array(skills):
		var skill_copy: Dictionary = skill.duplicate(true)
		_skills.append(skill_copy)
		_cooldowns[String(skill_copy.get("id", ""))] = 0.0
	_configure_resources(resources)


func cast_primary_skill() -> Dictionary:
	if _skills.is_empty():
		return _result(false, "no_skill")
	return cast_skill(String(_skills[0].get("id", "")))


func cast_skill(skill_id: String) -> Dictionary:
	var skill: Dictionary = _skill_by_id(skill_id)
	if skill.is_empty():
		return _result(false, "unknown_skill")
	if _caster == null or not is_instance_valid(_caster):
		return _result(false, "caster_unavailable")
	if cooldown_remaining(skill_id) > 0.0:
		return _result(false, "cooldown")
	var tag_check: Dictionary = _activation_tag_check(skill)
	if not bool(tag_check.get("ok", false)):
		return _result(false, String(tag_check.get("reason", "tag_blocked")), {
			"tag": String(tag_check.get("tag", "")),
			"owned_tags": owned_tags(),
		})
	if not _can_pay_costs(skill):
		return _result(false, "insufficient_resource")

	var targets: Array[Node] = _targets_for_skill(skill)
	if targets.is_empty():
		return _result(false, "no_targets")

	_pay_costs(skill)
	var transient_tags: Array[String] = _activation_tags(skill, "granted_tags")
	_add_transient_tags(transient_tags)
	var applied_targets: int = _apply_effects(skill, targets)
	_remove_transient_tags(transient_tags)
	_cooldowns[skill_id] = maxf(float(skill.get("cooldown", 0.0)), 0.0)
	var result: Dictionary = {
		"ok": applied_targets > 0,
		"reason": "applied" if applied_targets > 0 else "no_effect",
		"skill_id": skill_id,
		"ability_tags": _string_array(skill.get("ability_tags", [])),
		"target_count": targets.size(),
		"applied_targets": applied_targets,
		"resources": resource_snapshot(),
		"cooldown": cooldown_remaining(skill_id),
		"owned_tags": owned_tags(),
	}
	skill_cast.emit(skill_id, result.duplicate(true))
	return result


func cooldown_remaining(skill_id: String) -> float:
	return maxf(float(_cooldowns.get(skill_id, 0.0)), 0.0)


func resource_amount(resource_id: String) -> float:
	var resource: Dictionary = _resources.get(resource_id, {}) as Dictionary
	return float(resource.get("current", 0.0))


func resource_snapshot() -> Dictionary:
	return _resources.duplicate(true)


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
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_ensure_status_effect_component()
	if _status_effect_component != null:
		_status_effect_component.call("clear", false)

	var raw_cooldowns: Variant = snapshot_data.get("cooldowns", {})
	if raw_cooldowns is Dictionary:
		for skill_id: Variant in (raw_cooldowns as Dictionary).keys():
			_cooldowns[String(skill_id)] = maxf(float((raw_cooldowns as Dictionary)[skill_id]), 0.0)

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
			resource["current"] = clampf(float((restored as Dictionary).get("current", resource.get("current", 0.0))), 0.0, float(resource.get("max", 0.0)))
			_resources[key] = resource

	_owned_tag_counts.clear()
	var raw_tag_counts: Variant = snapshot_data.get("owned_tag_counts", {})
	var has_owned_tag_snapshot: bool = snapshot_data.has("owned_tag_counts") and raw_tag_counts is Dictionary
	if snapshot_data.has("owned_tag_counts") and raw_tag_counts is Dictionary:
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


func debug_summary() -> Dictionary:
	return {
		"skill_ids": _skill_ids(),
		"resources": resource_snapshot(),
		"cooldowns": _cooldowns.duplicate(true),
		"owned_tags": owned_tags(),
		"owned_tag_counts": _owned_tag_counts.duplicate(true),
		"status_effects": _status_effect_snapshot(),
	}


func _configure_resources(resources: Array) -> void:
	_resources.clear()
	for resource: Dictionary in _typed_dictionary_array(resources):
		var resource_id: String = String(resource.get("id", ""))
		if resource_id.is_empty():
			continue
		var maximum: float = maxf(float(resource.get("max", 0.0)), 0.0)
		_resources[resource_id] = {
			"max": maximum,
			"current": clampf(float(resource.get("start", maximum)), 0.0, maximum),
			"regen_per_second": maxf(float(resource.get("regen_per_second", 0.0)), 0.0),
		}


func _update_cooldowns(delta: float) -> void:
	for skill_id: Variant in _cooldowns.keys():
		_cooldowns[skill_id] = maxf(float(_cooldowns[skill_id]) - delta, 0.0)


func _update_resources(delta: float) -> void:
	for resource_id: Variant in _resources.keys():
		var resource: Dictionary = _resources[resource_id] as Dictionary
		var maximum: float = float(resource.get("max", 0.0))
		var current: float = float(resource.get("current", 0.0))
		var regen: float = float(resource.get("regen_per_second", 0.0))
		resource["current"] = minf(current + regen * delta, maximum)
		_resources[resource_id] = resource


func _skill_by_id(skill_id: String) -> Dictionary:
	for skill: Dictionary in _skills:
		if String(skill.get("id", "")) == skill_id:
			return skill
	return {}


func _can_pay_costs(skill: Dictionary) -> bool:
	for cost: Dictionary in _typed_dictionary_array(skill.get("costs", [])):
		var resource_id: String = String(cost.get("resource", ""))
		var amount: float = maxf(float(cost.get("amount", 0.0)), 0.0)
		if amount <= 0.0:
			continue
		if not _resources.has(resource_id):
			return false
		var resource: Dictionary = _resources[resource_id] as Dictionary
		if float(resource.get("current", 0.0)) < amount:
			return false
	return true


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
	var activation: Dictionary = _dictionary_or_empty(skill.get("activation", {}))
	return _string_array(activation.get(field, []))


func _pay_costs(skill: Dictionary) -> void:
	for cost: Dictionary in _typed_dictionary_array(skill.get("costs", [])):
		var resource_id: String = String(cost.get("resource", ""))
		var amount: float = maxf(float(cost.get("amount", 0.0)), 0.0)
		if amount <= 0.0 or not _resources.has(resource_id):
			continue
		var resource: Dictionary = _resources[resource_id] as Dictionary
		resource["current"] = maxf(float(resource.get("current", 0.0)) - amount, 0.0)
		_resources[resource_id] = resource


func _targets_for_skill(skill: Dictionary) -> Array[Node]:
	var targeting: Dictionary = _dictionary_or_empty(skill.get("targeting", {}))
	var targeting_type: String = String(targeting.get("type", ""))
	var radius: float = maxf(float(targeting.get("radius", 0.0)), 0.0)
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
	return []


func _enemy_targets_in_radius(radius: float, max_targets: int) -> Array[Node]:
	var candidates: Array[Node2D] = []
	for raw_enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if not raw_enemy is Node2D:
			continue
		if not _is_active_world_entity(raw_enemy):
			continue
		if raw_enemy.has_method("is_alive") and not bool(raw_enemy.call("is_alive")):
			continue
		var enemy: Node2D = raw_enemy as Node2D
		if radius > 0.0 and _caster != null and _caster.global_position.distance_to(enemy.global_position) > radius:
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
	var left_distance: float = _caster.global_position.distance_squared_to(left.global_position)
	var right_distance: float = _caster.global_position.distance_squared_to(right.global_position)
	if is_equal_approx(left_distance, right_distance):
		return left.get_instance_id() < right.get_instance_id()
	return left_distance < right_distance


func _apply_effects(skill: Dictionary, targets: Array[Node]) -> int:
	var applied_targets: int = 0
	for effect: Dictionary in _typed_dictionary_array(skill.get("effects", [])):
		var effect_id: String = String(effect.get("effect", ""))
		if effect_id == SKILL_EFFECTS.SKILL_EFFECT_DAMAGE:
			applied_targets += _apply_damage_effect(effect, targets)
		elif effect_id == SKILL_EFFECTS.SKILL_EFFECT_APPLY_STATUS:
			applied_targets += _apply_status_effect(effect, targets)
	return applied_targets


func _apply_damage_effect(effect: Dictionary, targets: Array[Node]) -> int:
	var params: Dictionary = _dictionary_or_empty(effect.get("params", {}))
	var amount: float = maxf(float(params.get("amount", 0.0)), 0.0)
	var damage_type: String = String(params.get("damage_type", ""))
	if amount <= 0.0 or damage_type.is_empty():
		return 0

	var applied_targets: int = 0
	for target: Node in targets:
		var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(amount, damage_type, _caster, target, TEAM_PLAYER, TEAM_ENEMY)
		var result: Dictionary = Combat.apply_damage(target, info)
		if bool(result.get("applied", false)):
			applied_targets += 1
	return applied_targets


func _apply_status_effect(effect: Dictionary, targets: Array[Node]) -> int:
	var params: Dictionary = _dictionary_or_empty(effect.get("params", {}))
	var status_id: String = String(params.get("status", ""))
	if status_id.is_empty():
		return 0

	var applied_targets: int = 0
	for target: Node in targets:
		var status_effect: Variant = STATUS_EFFECT_SCRIPT.new()
		status_effect.call("setup", status_id, params, _caster)
		var result: Dictionary = _apply_status_to_target(target, status_effect)
		if bool(result.get("applied", false)):
			applied_targets += 1
	return applied_targets


func _apply_status_to_target(target: Node, status_effect: Variant) -> Dictionary:
	if target == _caster:
		return apply_status_effect(status_effect)
	if target != null and target.has_method("apply_status_effect"):
		return target.call("apply_status_effect", status_effect) as Dictionary
	return _result(false, "status_target_unavailable")


func _is_active_world_entity(node: Node) -> bool:
	if node == null or _active_parent == null:
		return false
	return node == _active_parent or _active_parent.is_ancestor_of(node)


func _skill_ids() -> Array[String]:
	var result: Array[String] = []
	for skill: Dictionary in _skills:
		result.append(String(skill.get("id", "")))
	return result


func _ensure_status_effect_component() -> void:
	if _status_effect_component != null and is_instance_valid(_status_effect_component):
		return
	_status_effect_component = STATUS_EFFECT_COMPONENT_SCRIPT.new()
	_status_effect_component.name = "StatusEffectComponent"
	add_child(_status_effect_component)
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


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is String and not String(item).is_empty():
			result.append(String(item))
	return result


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _result(ok: bool, reason: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": ok,
		"reason": reason,
	}
	for key: Variant in extra.keys():
		result[key] = extra[key]
	return result
