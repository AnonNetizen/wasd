# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyRewardModelValidator
extends RefCounted
## Validates already loaded enemy reward model data without owning data sources.


const REQUIRED_KEYS: Array[String] = [
	"schema_version",
	"base_coefficient",
	"time_growth_per_tier",
	"random_multiplier_min",
	"random_multiplier_max",
]


static func validate(
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, "root", "Dictionary")
		return false

	var payload: Dictionary = raw_data as Dictionary
	var is_valid: bool = _validate_exact_dictionary_keys(
		payload,
		report_failure
	)
	is_valid = _require_exact_int(
		"schema_version",
		payload.get("schema_version"),
		1,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"base_coefficient",
		payload.get("base_coefficient"),
		0.0,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"time_growth_per_tier",
		payload.get("time_growth_per_tier"),
		0.0,
		false,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"random_multiplier_min",
		payload.get("random_multiplier_min"),
		0.0,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"random_multiplier_max",
		payload.get("random_multiplier_max"),
		0.0,
		true,
		report_failure
	) and is_valid
	if (
		payload.get("random_multiplier_min") is int
		or payload.get("random_multiplier_min") is float
	) and (
		payload.get("random_multiplier_max") is int
		or payload.get("random_multiplier_max") is float
	) and float(payload.get("random_multiplier_min")) > float(
		payload.get("random_multiplier_max")
	):
		_report_failure(
			report_failure,
			"random_multiplier_min",
			"number <= random_multiplier_max"
		)
		is_valid = false
	return is_valid


static func _validate_exact_dictionary_keys(
	payload: Dictionary,
	report_failure: Callable
) -> bool:
	var is_valid: bool = true
	for required_key: String in REQUIRED_KEYS:
		if not payload.has(required_key):
			_report_failure(
				report_failure,
				"root.%s" % required_key,
				"required field"
			)
			is_valid = false
	for raw_key: Variant in payload.keys():
		var key: String = String(raw_key)
		if not REQUIRED_KEYS.has(key):
			_report_failure(
				report_failure,
				"root.%s" % key,
				"allowed schema field"
			)
			is_valid = false
	return is_valid


static func _require_exact_int(
	field: String,
	value: Variant,
	expected: int,
	report_failure: Callable
) -> bool:
	if not _is_int_like(value):
		_report_failure(report_failure, field, "int")
		return false
	if int(value) != expected:
		_report_failure(
			report_failure,
			field,
			"int equal to %d" % expected
		)
		return false
	return true


static func _require_number(
	field: String,
	value: Variant,
	minimum: float,
	exclusive_minimum: bool,
	report_failure: Callable
) -> bool:
	if not value is int and not value is float:
		_report_failure(report_failure, field, "number")
		return false
	var numeric: float = float(value)
	if not is_finite(numeric):
		_report_failure(report_failure, field, "finite number")
		return false
	if exclusive_minimum and numeric <= minimum:
		_report_failure(
			report_failure,
			field,
			"number > %s" % str(minimum)
		)
		return false
	if not exclusive_minimum and numeric < minimum:
		_report_failure(
			report_failure,
			field,
			"number >= %s" % str(minimum)
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
