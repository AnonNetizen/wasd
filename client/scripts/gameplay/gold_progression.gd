# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5.2, docs/决策记录.md ADR #169
class_name GoldProgression
extends Node


const GOLD_TRANSACTION_REASONS := preload(
	"res://scripts/contracts/gold_transaction_reasons.gd"
)
const MAX_INT: int = 9_223_372_036_854_775_807

var _balance: int = 0
var _current_level: int = 1
var _current_level_cost: int = 0
var _current_level_threshold: int = 0
var _earned_total: int = 0
var _first_level_cost: int = 0
var _multiplier_denominator: int = 1
var _multiplier_numerator: int = 1


func configure(config: Dictionary) -> bool:
	var first_level_cost: Variant = config.get("first_level_cost")
	var multiplier_numerator: Variant = config.get("multiplier_numerator")
	var multiplier_denominator: Variant = config.get("multiplier_denominator")
	if (
		not _is_int_like(first_level_cost)
		or not _is_int_like(multiplier_numerator)
		or not _is_int_like(multiplier_denominator)
	):
		return false
	if (
		int(first_level_cost) <= 0
		or int(multiplier_denominator) <= 0
		or int(multiplier_numerator) <= int(multiplier_denominator)
	):
		return false
	_first_level_cost = int(first_level_cost)
	_multiplier_numerator = int(multiplier_numerator)
	_multiplier_denominator = int(multiplier_denominator)
	reset()
	return true


func reset() -> void:
	_balance = 0
	_earned_total = 0
	_current_level = 1
	_current_level_threshold = 0
	_current_level_cost = _first_level_cost


func restore(balance: int, earned_total: int) -> bool:
	if balance < 0 or earned_total < 0 or balance > earned_total:
		return false
	_balance = balance
	_earned_total = earned_total
	_recompute_level()
	return true


func add_gold(amount: int, reason_id: String) -> Dictionary:
	var old_level: int = _current_level
	if amount <= 0:
		return _result(false, "non_positive_amount", amount, old_level)
	if not _is_add_reason(reason_id):
		return _result(false, "invalid_reason", amount, old_level)
	if _balance > MAX_INT - amount or _earned_total > MAX_INT - amount:
		return _result(false, "integer_overflow", amount, old_level)
	_balance += amount
	_earned_total += amount
	_advance_level()
	return _result(true, "", amount, old_level)


func try_spend_gold(amount: int, reason_id: String) -> Dictionary:
	var old_level: int = _current_level
	if amount <= 0:
		return _result(false, "non_positive_amount", amount, old_level)
	if not _is_spend_reason(reason_id):
		return _result(false, "invalid_reason", amount, old_level)
	if amount > _balance:
		return _result(false, "insufficient_balance", amount, old_level)
	_balance -= amount
	return _result(true, "", amount, old_level)


func can_afford(amount: int) -> bool:
	return amount > 0 and amount <= _balance


func gold_balance() -> int:
	return _balance


func gold_earned_total() -> int:
	return _earned_total


func current_level() -> int:
	return _current_level


func current_level_gold() -> int:
	return maxi(_earned_total - _current_level_threshold, 0)


func current_level_gold_required() -> int:
	return _current_level_cost


func snapshot() -> Dictionary:
	return {
		"gold_balance": _balance,
		"gold_earned_total": _earned_total,
	}


func _recompute_level() -> void:
	_current_level = 1
	_current_level_threshold = 0
	_current_level_cost = _first_level_cost
	_advance_level()


func _advance_level() -> void:
	while (
		_current_level_cost > 0
		and _current_level_threshold <= MAX_INT - _current_level_cost
		and _earned_total >= _current_level_threshold + _current_level_cost
	):
		_current_level_threshold += _current_level_cost
		_current_level += 1
		_current_level_cost = _next_cost(_current_level_cost)


func _next_cost(current_cost: int) -> int:
	if current_cost <= 0:
		return 0
	@warning_ignore("integer_division")
	var multiplication_limit: int = (
		(MAX_INT - (_multiplier_denominator - 1))
		/ _multiplier_numerator
	)
	if current_cost > multiplication_limit:
		return 0
	@warning_ignore("integer_division")
	return (
		current_cost * _multiplier_numerator
		+ _multiplier_denominator
		- 1
	) / _multiplier_denominator


func _is_add_reason(reason_id: String) -> bool:
	return reason_id in [
		GOLD_TRANSACTION_REASONS.ENEMY_DROP,
		GOLD_TRANSACTION_REASONS.EVENT_REWARD,
		GOLD_TRANSACTION_REASONS.DEBUG_COMMAND,
	]


func _is_spend_reason(reason_id: String) -> bool:
	return reason_id in [
		GOLD_TRANSACTION_REASONS.EVENT_COST,
		GOLD_TRANSACTION_REASONS.DEBUG_COMMAND,
	]


func _is_int_like(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_equal_approx(
		float(value),
		roundf(float(value))
	)


func _result(
	ok: bool,
	reason: String,
	amount: int,
	old_level: int
) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"amount": amount,
		"gold_balance": _balance,
		"gold_earned_total": _earned_total,
		"old_level": old_level,
		"new_level": _current_level,
		"levels_gained": maxi(_current_level - old_level, 0),
	}
