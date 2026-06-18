# Doc: docs/代码/combat.md
# Authority: docs/游戏设计文档.md §9.15.1, docs/词表与契约.md §9
class_name CombatAutoload
extends Node


signal damage_applied(target: Node, info: RefCounted, result: Dictionary)

const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")


func apply_damage(target: Node, info: RefCounted) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return _result(false, 0.0, false, "invalid_target")
	if info == null:
		return _result(false, 0.0, false, "invalid_info")
	var damage_type: String = String(info.get("damage_type"))
	var amount: float = float(info.get("amount"))
	if not DAMAGE_TYPES.VALUES.has(damage_type):
		push_error("[Combat] unknown damage type: %s" % damage_type)
		return _result(false, 0.0, false, "unknown_damage_type")
	if amount <= 0.0:
		return _result(false, 0.0, false, "non_positive_amount")
	if not target.has_method("receive_damage"):
		push_error("[Combat] target lacks receive_damage(info): %s" % target.name)
		return _result(false, 0.0, false, "missing_receiver")

	info.set("target", target)
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
