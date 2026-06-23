# Doc: docs/代码/status_effect_component.md
# Authority: docs/游戏设计文档.md §9.15.2, docs/词表与契约.md §9-A~§9-B
class_name StatusEffectComponent
extends Node


signal effect_applied(status_id: String, snapshot: Dictionary)
signal effect_expired(status_id: String, snapshot: Dictionary)

const STATUS_EFFECT_SCRIPT := preload("res://scripts/combat/status_effect.gd")
const STATUS_STACK_RULES := preload("res://scripts/contracts/status_stack_rules.gd")

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


func _tick_effects(delta: float) -> void:
	var expired_keys: Array[String] = []
	for effect_key: Variant in _active_effects.keys():
		var effect: Variant = _active_effects[effect_key]
		var next_remaining: float = maxf(float(effect.get("remaining")) - delta, 0.0)
		effect.set("remaining", next_remaining)
		if next_remaining <= 0.0:
			expired_keys.append(String(effect_key))
	for effect_key: String in expired_keys:
		_expire_effect(effect_key)


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
