# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name PlayerDataValidator
extends RefCounted
## Validates already loaded player data without owning data sources.


const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var stat_count: int = 0
	var has_stat_count: bool = false


static func validate(
	raw_data: Variant,
	validate_stat_value: Callable,
	require_pool_id: Callable,
	report_failure: Callable
) -> ValidationResult:
	var result: ValidationResult = ValidationResult.new()
	if not raw_data is Dictionary:
		_report_failure(report_failure, "root", "Dictionary")
		result.is_valid = false
		return result

	var payload: Dictionary = raw_data as Dictionary
	result.is_valid = _require_exact_int(
		"schema_version",
		payload.get("schema_version"),
		4,
		report_failure
	) and result.is_valid
	result.is_valid = _validate_body(
		payload.get("body"),
		report_failure
	) and result.is_valid

	var base_stats: Variant = payload.get("base_stats")
	if not base_stats is Dictionary or (base_stats as Dictionary).is_empty():
		_report_failure(
			report_failure,
			"base_stats",
			"non-empty Dictionary"
		)
		result.is_valid = false
		return result

	var stats: Dictionary = base_stats as Dictionary
	if stats.has("pickup_orb_speed"):
		_report_failure(
			report_failure,
			"base_stats.pickup_orb_speed",
			"removed in schema_version 3"
		)
		result.is_valid = false
	result.stat_count = stats.size()
	result.has_stat_count = true
	for raw_stat: Variant in stats.keys():
		var stat: String = String(raw_stat)
		result.is_valid = bool(validate_stat_value.call(
			"base_stats.%s" % stat,
			stat,
			stats[raw_stat]
		)) and result.is_valid

	result.is_valid = _validate_gold_drop(
		payload.get("gold_drop"),
		require_pool_id,
		report_failure
	) and result.is_valid
	result.is_valid = _validate_energy_drop(
		payload.get("energy_drop"),
		report_failure
	) and result.is_valid
	return result


static func _validate_body(
	raw_body: Variant,
	report_failure: Callable
) -> bool:
	if not raw_body is Dictionary:
		_report_failure(report_failure, "body", "Dictionary")
		return false

	var body: Dictionary = raw_body as Dictionary
	var is_valid: bool = _validate_exact_dictionary_keys(
		"body",
		body,
		["radius"],
		report_failure
	)
	is_valid = _require_number(
		"body.radius",
		body.get("radius"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	return is_valid


static func _validate_gold_drop(
	raw_gold_drop: Variant,
	require_pool_id: Callable,
	report_failure: Callable
) -> bool:
	if not raw_gold_drop is Dictionary:
		_report_failure(report_failure, "gold_drop", "Dictionary")
		return false

	var gold_drop: Dictionary = raw_gold_drop as Dictionary
	var is_valid: bool = _require_number(
		"gold_drop.pickup_speed",
		gold_drop.get("pickup_speed"),
		0.0,
		null,
		true,
		report_failure
	)
	var gold_pool_id: String = String(require_pool_id.call(
		"gold_drop.pool_id",
		gold_drop.get("pool_id")
	))
	is_valid = not gold_pool_id.is_empty() and is_valid
	if gold_pool_id != POOL_IDS.GOLD_ORB:
		_report_failure(
			report_failure,
			"gold_drop.pool_id",
			POOL_IDS.GOLD_ORB
		)
		is_valid = false
	return is_valid


static func _validate_energy_drop(
	raw_energy_drop: Variant,
	report_failure: Callable
) -> bool:
	if not raw_energy_drop is Dictionary:
		_report_failure(report_failure, "energy_drop", "Dictionary")
		return false

	var energy_drop: Dictionary = raw_energy_drop as Dictionary
	return _require_number(
		"energy_drop.pickup_speed",
		energy_drop.get("pickup_speed"),
		0.0,
		null,
		true,
		report_failure
	)


static func _validate_exact_dictionary_keys(
	field: String,
	data: Dictionary,
	expected_keys: Array[String],
	report_failure: Callable
) -> bool:
	var is_valid: bool = true
	for expected_key: String in expected_keys:
		if not data.has(expected_key):
			_report_failure(
				report_failure,
				"%s.%s" % [field, expected_key],
				"required field"
			)
			is_valid = false
	for raw_key: Variant in data.keys():
		var key: String = String(raw_key)
		if not expected_keys.has(key):
			_report_failure(
				report_failure,
				"%s.%s" % [field, key],
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
	minimum: Variant,
	maximum: Variant,
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
	if minimum != null:
		var minimum_value: float = float(minimum)
		if exclusive_minimum and numeric <= minimum_value:
			_report_failure(
				report_failure,
				field,
				"number > %s" % str(minimum)
			)
			return false
		if not exclusive_minimum and numeric < minimum_value:
			_report_failure(
				report_failure,
				field,
				"number >= %s" % str(minimum)
			)
			return false
	if maximum != null and numeric > float(maximum):
		_report_failure(
			report_failure,
			field,
			"number <= %s" % str(maximum)
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
