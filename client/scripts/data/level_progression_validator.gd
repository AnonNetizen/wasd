# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name LevelProgressionValidator
extends RefCounted
## Validates already loaded level progression data without owning data sources.


static func validate(
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, "root", "Dictionary")
		return false

	var payload: Dictionary = raw_data as Dictionary
	var is_valid: bool = _require_exact_int(
		"schema_version",
		payload.get("schema_version"),
		1,
		report_failure
	)
	is_valid = _require_int(
		"first_level_cost",
		payload.get("first_level_cost"),
		1,
		report_failure
	) and is_valid
	is_valid = _require_int(
		"multiplier_numerator",
		payload.get("multiplier_numerator"),
		1,
		report_failure
	) and is_valid
	is_valid = _require_int(
		"multiplier_denominator",
		payload.get("multiplier_denominator"),
		1,
		report_failure
	) and is_valid
	if (
		_is_int_like(payload.get("multiplier_numerator"))
		and _is_int_like(payload.get("multiplier_denominator"))
		and int(payload.get("multiplier_numerator")) <= int(
			payload.get("multiplier_denominator")
		)
	):
		_report_failure(
			report_failure,
			"multiplier_numerator",
			"int greater than multiplier_denominator"
		)
		is_valid = false
	return is_valid


static func _require_exact_int(
	field: String,
	value: Variant,
	expected: int,
	report_failure: Callable
) -> bool:
	if not _require_int(field, value, null, report_failure):
		return false
	if int(value) != expected:
		_report_failure(
			report_failure,
			field,
			"int equal to %d" % expected
		)
		return false
	return true


static func _require_int(
	field: String,
	value: Variant,
	minimum: Variant,
	report_failure: Callable
) -> bool:
	if not _is_int_like(value):
		_report_failure(report_failure, field, "int")
		return false
	if minimum != null and int(value) < int(minimum):
		_report_failure(
			report_failure,
			field,
			"int >= %d" % int(minimum)
		)
		return false
	return true


static func _is_int_like(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_equal_approx(float(value), float(int(value)))
	return false


static func _report_failure(
	report_failure: Callable,
	field: String,
	expected: String
) -> void:
	report_failure.call(field, expected)
