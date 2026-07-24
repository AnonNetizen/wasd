# Doc: docs/代码/status_effect_component.md
# Authority: docs/游戏设计文档.md §9.15.2, docs/词表与契约.md §9-A~§9-B
class_name StatusEffectComponent
extends Node


signal effect_applied(status_id: String, snapshot: Dictionary)
signal effect_expired(status_id: String, snapshot: Dictionary)
signal effect_restored(status_id: String, snapshot: Dictionary)

const STATUS_EFFECT_SCRIPT := preload("res://scripts/combat/status_effect.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const STATUS_STACK_RULES := preload("res://scripts/contracts/status_stack_rules.gd")

const DOT_DAMAGE_FLAG: String = "is_dot"
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

var _ability_tag_owner: Node = null
var _active_effects: Dictionary = {}
var _granted_tags_by_key: Dictionary = {}
var _next_instance_id: int = 1


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return
	_tick_effects(scaled_delta)


func configure_ability_tag_owner(owner: Node) -> void:
	_ability_tag_owner = owner


func apply(effect: Variant) -> Dictionary:
	if effect == null or not (effect is Object):
		return {
			"applied": false,
			"reason": "invalid_status_effect",
		}
	var effect_object: Object = effect as Object
	if not effect_object.has_method("is_valid") or not effect_object.has_method("copy_runtime") or not bool(effect_object.call("is_valid")):
		return {
			"applied": false,
			"reason": "invalid_status_effect",
		}

	var runtime_effect: Variant = effect_object.call("copy_runtime")
	var effect_key: String = _effect_key_for(runtime_effect)
	if String(runtime_effect.get("stack_rule")) == STATUS_STACK_RULES.INDEPENDENT:
		effect_key = _independent_key(String(runtime_effect.get("status_id")))
		_set_effect(effect_key, runtime_effect, true)
	elif _active_effects.has(effect_key):
		_merge_effect(effect_key, runtime_effect)
	else:
		_set_effect(effect_key, runtime_effect, true)

	var active: Variant = _active_effects[effect_key]
	var active_snapshot: Dictionary = active.call("snapshot") as Dictionary
	effect_applied.emit(String(active.get("status_id")), active_snapshot)
	return {
		"applied": true,
		"reason": "applied",
		"status": String(active.get("status_id")),
		"active_statuses": active_statuses(),
	}


func clear(remove_granted_tags: bool = true) -> void:
	if remove_granted_tags:
		for effect_key: Variant in _granted_tags_by_key.keys():
			_release_effect_tags(String(effect_key))
	_active_effects.clear()
	_granted_tags_by_key.clear()


func active_statuses() -> Array[String]:
	var result: Array[String] = []
	for effect_key: Variant in _active_effects.keys():
		var effect: Variant = _active_effects[effect_key]
		var status_id: String = String(effect.get("status_id"))
		if not result.has(status_id):
			result.append(status_id)
	result.sort()
	return result


func snapshot() -> Dictionary:
	var effects: Array[Dictionary] = []
	var keys: Array[String] = _sorted_string_keys(_active_effects)
	for effect_key: String in keys:
		var effect: Variant = _active_effects[effect_key]
		var effect_snapshot: Dictionary = effect.call("snapshot") as Dictionary
		effect_snapshot["key"] = effect_key
		effects.append(effect_snapshot)
	return {
		"effects": effects,
	}


func restore_snapshot(snapshot_data: Dictionary, grant_existing_tags: bool = true) -> void:
	clear(grant_existing_tags)
	var effects: Variant = snapshot_data.get("effects", [])
	if not effects is Array:
		return
	for item: Variant in effects as Array:
		if not item is Dictionary:
			continue
		var effect: Variant = STATUS_EFFECT_SCRIPT.new()
		effect.call("restore_from_snapshot", item as Dictionary)
		if not bool(effect.call("is_valid")):
			continue
		var effect_key: String = String((item as Dictionary).get("key", _effect_key_for(effect)))
		if effect_key.is_empty():
			effect_key = _effect_key_for(effect)
		_set_effect(effect_key, effect, grant_existing_tags)
		effect_restored.emit(
			String(effect.get("status_id")),
			effect.call("snapshot") as Dictionary
		)


func _tick_effects(delta: float) -> void:
	var expired_keys: Array[String] = []
	for effect_key: Variant in _active_effects.keys():
		var effect: Variant = _active_effects[effect_key]
		var elapsed: float = minf(delta, float(effect.get("remaining")))
		_tick_damage(effect, elapsed)
		var next_remaining: float = maxf(float(effect.get("remaining")) - elapsed, 0.0)
		effect.set("remaining", next_remaining)
		if next_remaining <= 0.0:
			expired_keys.append(String(effect_key))
	for effect_key: String in expired_keys:
		_expire_effect(effect_key)


func _tick_damage(effect: Variant, elapsed: float) -> void:
	var tick_interval: float = float(effect.get("tick_interval"))
	var damage_amount: float = float(effect.get("magnitude"))
	var damage_type: String = String(effect.get("damage_type"))
	if elapsed <= 0.0 or tick_interval <= 0.0 or damage_amount <= 0.0 or damage_type.is_empty():
		return

	var tick_remaining: float = float(effect.get("tick_remaining"))
	if tick_remaining <= 0.0:
		tick_remaining = tick_interval
	tick_remaining -= elapsed
	while tick_remaining <= 0.0:
		_apply_tick_damage(effect, damage_amount, damage_type)
		tick_remaining += tick_interval
	effect.set("tick_remaining", tick_remaining)


func _apply_tick_damage(effect: Variant, damage_amount: float, damage_type: String) -> void:
	if _ability_tag_owner == null or not is_instance_valid(_ability_tag_owner):
		return
	if not _ability_tag_owner.has_method("receive_damage"):
		return

	var source_node: Node = _effect_source(effect)
	var source_team: String = String(effect.get("source_team"))
	var target_team: String = String(effect.get("target_team"))
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		damage_amount,
		damage_type,
		source_node,
		_ability_tag_owner,
		source_team,
		target_team,
		PackedStringArray([DOT_DAMAGE_FLAG])
	)
	Combat.apply_damage(_ability_tag_owner, info)


func _merge_effect(effect_key: String, incoming: Variant) -> void:
	var active: Variant = _active_effects[effect_key]
	var stack_rule: String = String(incoming.get("stack_rule"))
	if stack_rule == STATUS_STACK_RULES.REPLACE:
		_release_effect_tags(effect_key)
		_set_effect(effect_key, incoming, true)
	elif stack_rule == STATUS_STACK_RULES.ADD_DURATION:
		var added_remaining: float = float(active.get("remaining")) + float(incoming.get("duration"))
		active.set("remaining", added_remaining)
		active.set("duration", maxf(float(active.get("duration")), added_remaining))
	elif stack_rule == STATUS_STACK_RULES.MAX_MAGNITUDE:
		if float(incoming.get("magnitude")) >= float(active.get("magnitude")):
			_release_effect_tags(effect_key)
			_set_effect(effect_key, incoming, true)
		else:
			var max_magnitude_remaining: float = maxf(float(active.get("remaining")), float(incoming.get("duration")))
			active.set("remaining", max_magnitude_remaining)
			active.set("duration", maxf(float(active.get("duration")), max_magnitude_remaining))
	elif stack_rule == STATUS_STACK_RULES.REFRESH:
		var refreshed_remaining: float = maxf(float(active.get("remaining")), float(incoming.get("duration")))
		active.set("remaining", refreshed_remaining)
		active.set("duration", maxf(float(active.get("duration")), refreshed_remaining))
	else:
		_release_effect_tags(effect_key)
		_set_effect(effect_key, incoming, true)


func _set_effect(effect_key: String, effect: Variant, grant_tags: bool) -> void:
	effect.set("instance_key", effect_key)
	_update_effect_damage_context(effect)
	_active_effects[effect_key] = effect
	_register_effect_tags(effect_key, _string_array(effect.get("granted_ability_tags")), grant_tags)


func _expire_effect(effect_key: String) -> void:
	if not _active_effects.has(effect_key):
		return
	var effect: Variant = _active_effects[effect_key]
	var effect_snapshot: Dictionary = effect.call("snapshot") as Dictionary
	_release_effect_tags(effect_key)
	_active_effects.erase(effect_key)
	effect_expired.emit(String(effect.get("status_id")), effect_snapshot)


func _register_effect_tags(effect_key: String, tags: Array[String], grant_tags: bool) -> void:
	_granted_tags_by_key[effect_key] = tags.duplicate()
	if not grant_tags:
		return
	for tag_id: String in tags:
		_call_tag_owner("add_owned_tag", tag_id)


func _release_effect_tags(effect_key: String) -> void:
	if not _granted_tags_by_key.has(effect_key):
		return
	var tags: Array = _granted_tags_by_key[effect_key] as Array
	for tag_id: Variant in tags:
		_call_tag_owner("remove_owned_tag", String(tag_id))
	_granted_tags_by_key.erase(effect_key)


func _call_tag_owner(method_name: String, tag_id: String) -> void:
	if _ability_tag_owner == null or not is_instance_valid(_ability_tag_owner):
		return
	if _ability_tag_owner.has_method(method_name):
		_ability_tag_owner.call(method_name, tag_id)


func _update_effect_damage_context(effect: Variant) -> void:
	if String(effect.get("target_team")).is_empty():
		effect.set("target_team", _team_id_for(_ability_tag_owner))
	if String(effect.get("source_team")).is_empty():
		effect.set("source_team", _team_id_for(_effect_source(effect)))


func _effect_source(effect: Variant) -> Node:
	var raw_source: Variant = effect.get("source")
	if raw_source is Node and is_instance_valid(raw_source):
		return raw_source as Node
	return null


func _team_id_for(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return ""
	if node.has_method("combat_team_id"):
		return String(node.call("combat_team_id"))
	if node.is_in_group("active_enemies"):
		return TEAM_ENEMY
	if node.has_method("current_life") and node.has_method("max_life"):
		return TEAM_PLAYER
	return ""


func _effect_key_for(effect: Variant) -> String:
	return String(effect.get("status_id"))


func _independent_key(status_id: String) -> String:
	var effect_key: String = "%s#%d" % [status_id, _next_instance_id]
	_next_instance_id += 1
	return effect_key


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
		result.append(String(item))
	return result
