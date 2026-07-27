# Doc: docs/代码/combat.md
# Authority: docs/游戏设计文档.md §9.15.1, docs/词表与契约.md §9
class_name CombatAutoload
extends Node


signal damage_applied(target: Node, info: RefCounted, result: Dictionary)

const ELEMENTS := preload("res://scripts/contracts/elements.gd")


func apply_damage(target: Node, info: RefCounted) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return _result(false, 0.0, false, "invalid_target")
	if info == null:
		return _result(false, 0.0, false, "invalid_info")
	var element_id: String = String(info.get("element_id"))
	var amount: float = float(info.get("amount"))
	if not ELEMENTS.VALUES.has(element_id):
		push_error("[Combat] unknown element: %s" % element_id)
		return _result(false, 0.0, false, "unknown_element")
	if amount <= 0.0:
		return _result(false, 0.0, false, "non_positive_amount")
	if not target.has_method("receive_damage"):
		push_error("[Combat] target lacks receive_damage(info): %s" % target.name)
		return _result(false, 0.0, false, "missing_receiver")

	info.set("target", target)
	if target.has_method("incoming_damage_multiplier"):
		var incoming_multiplier: float = maxf(
			float(target.call("incoming_damage_multiplier", info)),
			0.0
		)
		amount *= incoming_multiplier
		info.set("amount", amount)
	if amount <= 0.0:
		return _result(false, 0.0, false, "negated")
	var raw_result: Variant = target.call("receive_damage", info)
	var result: Dictionary = raw_result if raw_result is Dictionary else _result(true, amount, false, "applied")
	damage_applied.emit(target, info, result.duplicate(true))
	return result


func _result(applied: bool, amount: float, defeated: bool, reason: String) -> Dictionary:
	return {
		"applied": applied,
		"amount": amount,
		"defeated": defeated,
		"reason": reason,
	}
