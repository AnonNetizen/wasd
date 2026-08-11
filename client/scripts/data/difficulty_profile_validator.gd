# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name DifficultyProfileValidator
extends RefCounted
## Validates already loaded difficulty profile data without owning data sources.


const ROOT_KEYS: Array[String] = ["schema_version", "profiles"]
const PROFILE_KEYS: Array[String] = [
	"id",
	"name_key",
	"difficulty_coefficient",
	"tier_interval_seconds",
	"continuous_growth_per_interval",
	"tier_step_growth",
	"damage_growth_ratio",
	"stage_name_keys",
]
const GROWTH_FIELDS: Array[String] = [
	"continuous_growth_per_interval",
	"tier_step_growth",
	"damage_growth_ratio",
]


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var profile_count: int = 0


static func validate(
	raw_data: Variant,
	require_locale_key: Callable,
	report_failure: Callable
) -> ValidationResult:
	var result: ValidationResult = ValidationResult.new()
	if not raw_data is Dictionary:
		_report_failure(report_failure, "root", "Dictionary")
		result.is_valid = false
		return result

	var payload: Dictionary = raw_data as Dictionary
	result.is_valid = _validate_exact_dictionary_keys(
		"root",
		payload,
		ROOT_KEYS,
		report_failure
	)
	result.is_valid = _require_exact_int(
		"schema_version",
		payload.get("schema_version"),
		2,
		report_failure
	) and result.is_valid
	var profiles: Array = _require_array(
		"profiles",
		payload.get("profiles"),
		report_failure
	)
	if profiles.is_empty():
		_report_failure(report_failure, "profiles", "non-empty Array")
		result.is_valid = false
	result.profile_count = profiles.size()
	var seen_ids: Dictionary = {}
	for profile_index: int in range(profiles.size()):
		result.is_valid = _validate_profile(
			profile_index,
			profiles[profile_index],
			seen_ids,
			require_locale_key,
			report_failure
		) and result.is_valid
	return result


static func _validate_profile(
	profile_index: int,
	raw_profile: Variant,
	seen_ids: Dictionary,
	require_locale_key: Callable,
	report_failure: Callable
) -> bool:
	var profile_field: String = "profiles[%d]" % profile_index
	if not raw_profile is Dictionary:
		_report_failure(report_failure, profile_field, "Dictionary")
		return false

	var profile: Dictionary = raw_profile as Dictionary
	var is_valid: bool = _validate_exact_dictionary_keys(
		profile_field,
		profile,
		PROFILE_KEYS,
		report_failure
	)
	var profile_id: String = String(profile.get("id", ""))
	is_valid = _require_non_empty_string(
		"%s.id" % profile_field,
		profile.get("id"),
		report_failure
	) and is_valid
	if not profile_id.is_empty():
		if seen_ids.has(profile_id):
			_report_failure(
				report_failure,
				"%s.id" % profile_field,
				"unique difficulty profile id"
			)
			is_valid = false
		seen_ids[profile_id] = true
	is_valid = _call_locale_validator(
		"%s.name_key" % profile_field,
		profile.get("name_key"),
		require_locale_key
	) and is_valid
	is_valid = _require_number(
		"%s.difficulty_coefficient" % profile_field,
		profile.get("difficulty_coefficient"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.tier_interval_seconds" % profile_field,
		profile.get("tier_interval_seconds"),
		0.0,
		3600.0,
		true,
		report_failure
	) and is_valid
	for field_name: String in GROWTH_FIELDS:
		is_valid = _require_number(
			"%s.%s" % [profile_field, field_name],
			profile.get(field_name),
			0.0,
			10.0,
			false,
			report_failure
		) and is_valid
	var stage_name_keys: Array = _require_array(
		"%s.stage_name_keys" % profile_field,
		profile.get("stage_name_keys"),
		report_failure
	)
	if stage_name_keys.size() != 9:
		_report_failure(
			report_failure,
			"%s.stage_name_keys" % profile_field,
			"Array with exactly 9 entries"
		)
		is_valid = false
	var seen_name_keys: Dictionary = {}
	for key_index: int in range(stage_name_keys.size()):
		is_valid = _call_locale_validator(
			"%s.stage_name_keys[%d]" % [profile_field, key_index],
			stage_name_keys[key_index],
			require_locale_key
		) and is_valid
		var stage_name_key: String = String(stage_name_keys[key_index])
		if not stage_name_key.is_empty():
			if seen_name_keys.has(stage_name_key):
				_report_failure(
					report_failure,
					"%s.stage_name_keys[%d]" % [
						profile_field,
						key_index,
					],
					"unique stage name key"
				)
				is_valid = false
			seen_name_keys[stage_name_key] = true
	return is_valid


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
	if not _require_int(field, value, report_failure):
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
	report_failure: Callable
) -> bool:
	if not _is_int_like(value):
		_report_failure(report_failure, field, "int")
		return false
	return true


static func _require_array(
	field: String,
	value: Variant,
	report_failure: Callable
) -> Array:
	if not value is Array:
		_report_failure(report_failure, field, "Array")
		return []
	return value as Array


static func _require_non_empty_string(
	field: String,
	value: Variant,
	report_failure: Callable
) -> bool:
	if not value is String or String(value).is_empty():
		_report_failure(report_failure, field, "non-empty string")
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
		var min_value: float = float(minimum)
		if exclusive_minimum and numeric <= min_value:
			_report_failure(
				report_failure,
				field,
				"number > %s" % str(minimum)
			)
			return false
		if not exclusive_minimum and numeric < min_value:
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


static func _call_locale_validator(
	field: String,
	value: Variant,
	require_locale_key: Callable
) -> bool:
	return bool(require_locale_key.call(field, value))


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
