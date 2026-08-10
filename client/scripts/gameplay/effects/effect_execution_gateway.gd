# Doc: docs/代码/gameplay_effect_runtime.md
class_name EffectExecutionGateway
extends RefCounted


const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const STATUS_EFFECT_SCRIPT := preload("res://scripts/combat/status_effect.gd")

var _callbacks: Dictionary = {}


func configure(callbacks: Dictionary = {}) -> void:
	_callbacks = callbacks.duplicate()


func set_callback(callback_id: String, callback: Callable) -> void:
	if callback_id.is_empty() or not callback.is_valid():
		return
	_callbacks[callback_id] = callback


func execute(
	action_id: String,
	action: Dictionary,
	context: Dictionary
) -> Dictionary:
	match action_id:
		EffectPrimitiveRegistry.ACTION_DAMAGE:
			return _damage(action, context)
		EffectPrimitiveRegistry.ACTION_APPLY_STATUS:
			if _callbacks.has(EffectPrimitiveRegistry.ACTION_APPLY_STATUS):
				return _call_delegate(
					EffectPrimitiveRegistry.ACTION_APPLY_STATUS,
					action,
					context
				)
			return _apply_status(action, context)
		EffectPrimitiveRegistry.ACTION_TEMPORARY_MODIFIER:
			return _temporary_modifier(action, context)
		EffectPrimitiveRegistry.ACTION_HEAL:
			return _call_target_amount("heal", "heal", action, context)
		EffectPrimitiveRegistry.ACTION_GRANT_SHIELD:
			return _call_target_amount("grant_shield", "add_shield", action, context)
		EffectPrimitiveRegistry.ACTION_GRANT_OVERSHIELD:
			return _call_target_amount(
				"grant_overshield",
				"add_overshield",
				action,
				context
			)
		EffectPrimitiveRegistry.ACTION_GRANT_GOLD:
			return _call_delegate(EffectPrimitiveRegistry.ACTION_GRANT_GOLD, action, context)
		EffectPrimitiveRegistry.ACTION_SPAWN_PROJECTILE:
			return _call_delegate(EffectPrimitiveRegistry.ACTION_SPAWN_PROJECTILE, action, context)
		EffectPrimitiveRegistry.ACTION_SPAWN_ENEMY:
			return _call_delegate(EffectPrimitiveRegistry.ACTION_SPAWN_ENEMY, action, context)
		EffectPrimitiveRegistry.ACTION_SPAWN_BARRIER:
			return _call_delegate(EffectPrimitiveRegistry.ACTION_SPAWN_BARRIER, action, context)
		_:
			return {"ok": false, "reason": "unknown_action", "action": action_id}


func _damage(action: Dictionary, context: Dictionary) -> Dictionary:
	var params: Dictionary = _params(action)
	var amount: float = maxf(float(params.get("amount", 0.0)), 0.0)
	var element_id: String = String(params.get("element_id", ""))
	if amount <= 0.0 or element_id.is_empty():
		return {"ok": false, "reason": "invalid_damage", "applied_targets": 0}
	var source: Variant = context.get("source_actor")
	var source_team: String = String(context.get("source_team", "team_player"))
	var target_team: String = String(context.get("target_team", "team_enemy"))
	var applied_targets: int = 0
	for target: Node in _targets(context):
		var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
			amount,
			element_id,
			source,
			target,
			source_team,
			target_team
		)
		var damage_result: Dictionary = Combat.apply_damage(target, info)
		if bool(damage_result.get("applied", false)):
			applied_targets += 1
	return {"ok": applied_targets > 0, "applied_targets": applied_targets}


func _apply_status(action: Dictionary, context: Dictionary) -> Dictionary:
	var params: Dictionary = _params(action)
	var status_id: String = String(params.get("status", ""))
	if status_id.is_empty():
		return {"ok": false, "reason": "invalid_status", "applied_targets": 0}
	var source: Variant = context.get("source_actor")
	var applied_targets: int = 0
	for target: Node in _targets(context):
		var status_effect: Variant = STATUS_EFFECT_SCRIPT.new()
		status_effect.call("setup", status_id, params, source)
		var result: Dictionary = {}
		if target.has_method("apply_status_effect"):
			result = target.call("apply_status_effect", status_effect) as Dictionary
		elif target.has_method("apply"):
			result = target.call("apply", status_effect) as Dictionary
		if bool(result.get("applied", false)):
			applied_targets += 1
	return {"ok": applied_targets > 0, "applied_targets": applied_targets}


func _temporary_modifier(action: Dictionary, context: Dictionary) -> Dictionary:
	var params: Dictionary = _params(action)
	var duration: float = maxf(float(params.get("duration", 0.0)), 0.0)
	var modifiers: Array = _array_or_empty(params.get("modifiers", []))
	if duration <= 0.0 or modifiers.is_empty():
		return {"ok": false, "reason": "invalid_modifier", "applied_targets": 0}
	var target_slot: String = String(params.get("slot", "actor"))
	var source_key: String = String(context.get("source_key", "effect"))
	var applied_targets: int = 0
	for target: Node in _targets(context):
		var applied: bool = false
		if target_slot in ["actor", "hero", "both"] and target.has_method(
			"apply_temporary_modifiers"
		):
			target.call("apply_temporary_modifiers", modifiers, duration, source_key)
			applied = true
		if target_slot in ["weapon", "both"]:
			var weapon_system: Node = target.get_node_or_null("WeaponSystem")
			if weapon_system != null and weapon_system.has_method(
				"apply_temporary_modifiers"
			):
				weapon_system.call(
					"apply_temporary_modifiers",
					modifiers,
					duration,
					source_key
				)
				applied = true
		if applied:
			applied_targets += 1
	return {"ok": applied_targets > 0, "applied_targets": applied_targets}


func _call_target_amount(
	action_id: String,
	method_name: String,
	action: Dictionary,
	context: Dictionary
) -> Dictionary:
	var amount: float = maxf(float(_params(action).get("amount", 0.0)), 0.0)
	if amount <= 0.0:
		return {"ok": false, "reason": "invalid_amount", "applied_targets": 0}
	var applied_targets: int = 0
	for target: Node in _targets(context):
		if not target.has_method(method_name):
			continue
		var applied: Variant = target.call(method_name, amount)
		if applied is float and float(applied) <= 0.0:
			continue
		applied_targets += 1
	return {
		"ok": applied_targets > 0,
		"action": action_id,
		"applied_targets": applied_targets,
	}


func _call_delegate(
	callback_id: String,
	action: Dictionary,
	context: Dictionary
) -> Dictionary:
	var callback: Callable = _callbacks.get(callback_id, Callable())
	if not callback.is_valid():
		return {"ok": false, "reason": "gateway_unavailable", "action": callback_id}
	var result: Variant = callback.call(_params(action), context)
	if result is Dictionary:
		return (result as Dictionary).duplicate(true)
	return {"ok": bool(result), "applied_targets": 1 if bool(result) else 0}


func _targets(context: Dictionary) -> Array[Node]:
	var result: Array[Node] = []
	var raw_targets: Variant = context.get("targets", [])
	if raw_targets is Array:
		for raw_target: Variant in raw_targets as Array:
			if raw_target is Node and is_instance_valid(raw_target):
				result.append(raw_target as Node)
	if result.is_empty():
		var target: Variant = context.get("target_actor")
		if target is Node and is_instance_valid(target):
			result.append(target as Node)
	return result


func _params(action: Dictionary) -> Dictionary:
	var raw_params: Variant = action.get("params", {})
	return (raw_params as Dictionary).duplicate(true) if raw_params is Dictionary else {}


func _array_or_empty(raw_value: Variant) -> Array:
	return (raw_value as Array).duplicate(true) if raw_value is Array else []
