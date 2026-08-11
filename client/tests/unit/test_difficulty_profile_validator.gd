extends SmokeHarness


const DIFFICULTY_PROFILE_VALIDATOR := preload(
	"res://scripts/data/difficulty_profile_validator.gd"
)
const DIFFICULTY_PROFILES_PATH: String = (
	"res://data/difficulty_profiles.json"
)

var _reported_failures: Array[String] = []
var _locale_calls: Array[String] = []
var _available_locale_keys: Dictionary = {}
var _registered_locale_prefixes: Array[String] = []
var _data_loader_messages: Array[String] = []


func before_each() -> void:
	super()
	_reported_failures.clear()
	_locale_calls.clear()
	_available_locale_keys.clear()
	_registered_locale_prefixes.clear()
	_data_loader_messages.clear()
	_registered_locale_prefixes.append("ui_difficulty_")
	_available_locale_keys["ui_difficulty_standard_name"] = true
	for stage_number: int in range(1, 10):
		_available_locale_keys[
			"ui_difficulty_stage_%d" % stage_number
		] = true


func test_valid_payload_returns_profile_count_and_locale_order() -> void:
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)

	assert_true(result.is_valid)
	assert_eq(result.profile_count, 1)
	assert_eq(_reported_failures, [])
	assert_eq(_locale_calls, [
		"profiles[0].name_key|ui_difficulty_standard_name",
		"profiles[0].stage_name_keys[0]|ui_difficulty_stage_1",
		"profiles[0].stage_name_keys[1]|ui_difficulty_stage_2",
		"profiles[0].stage_name_keys[2]|ui_difficulty_stage_3",
		"profiles[0].stage_name_keys[3]|ui_difficulty_stage_4",
		"profiles[0].stage_name_keys[4]|ui_difficulty_stage_5",
		"profiles[0].stage_name_keys[5]|ui_difficulty_stage_6",
		"profiles[0].stage_name_keys[6]|ui_difficulty_stage_7",
		"profiles[0].stage_name_keys[7]|ui_difficulty_stage_8",
		"profiles[0].stage_name_keys[8]|ui_difficulty_stage_9",
	])


func test_root_shape_and_profiles_normalization_keep_legacy_counts() -> void:
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate([])
	assert_false(result.is_valid)
	assert_eq(result.profile_count, 0)
	assert_eq(_reported_failures, ["root|Dictionary"])

	_clear_diagnostics()
	result = _validate({
		"schema_version": 2,
		"profiles": "invalid",
	})
	assert_false(result.is_valid)
	assert_eq(result.profile_count, 0)
	assert_eq(_reported_failures, [
		"profiles|Array",
		"profiles|non-empty Array",
	])

	_clear_diagnostics()
	result = _validate({
		"schema_version": 2,
		"profiles": [],
	})
	assert_false(result.is_valid)
	assert_eq(result.profile_count, 0)
	assert_eq(_reported_failures, ["profiles|non-empty Array"])


func test_root_exact_keys_keep_required_then_extra_source_order() -> void:
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate({
		"future_first": true,
		"future_second": true,
	})

	assert_false(result.is_valid)
	assert_eq(result.profile_count, 0)
	assert_eq(_reported_failures, [
		"root.schema_version|required field",
		"root.profiles|required field",
		"root.future_first|allowed schema field",
		"root.future_second|allowed schema field",
		"schema_version|int",
		"profiles|Array",
		"profiles|non-empty Array",
	])


func test_profile_exact_keys_and_field_checks_keep_source_order() -> void:
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate({
		"schema_version": 2,
		"profiles": [{}],
	})

	assert_false(result.is_valid)
	assert_eq(result.profile_count, 1)
	assert_eq(_reported_failures, [
		"profiles[0].id|required field",
		"profiles[0].name_key|required field",
		"profiles[0].difficulty_coefficient|required field",
		"profiles[0].tier_interval_seconds|required field",
		(
			"profiles[0].continuous_growth_per_interval|"
			+ "required field"
		),
		"profiles[0].tier_step_growth|required field",
		"profiles[0].damage_growth_ratio|required field",
		"profiles[0].stage_name_keys|required field",
		"profiles[0].id|non-empty string",
		"profiles[0].name_key|non-empty locale key",
		"profiles[0].difficulty_coefficient|number",
		"profiles[0].tier_interval_seconds|number",
		"profiles[0].continuous_growth_per_interval|number",
		"profiles[0].tier_step_growth|number",
		"profiles[0].damage_growth_ratio|number",
		"profiles[0].stage_name_keys|Array",
		"profiles[0].stage_name_keys|Array with exactly 9 entries",
	])


func test_mixed_profile_shapes_keep_source_count_and_short_circuit() -> void:
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate({
		"schema_version": 2,
		"profiles": [null, _valid_profile("difficulty_standard")],
	})

	assert_false(result.is_valid)
	assert_eq(result.profile_count, 2)
	assert_eq(_reported_failures, ["profiles[0]|Dictionary"])
	assert_eq(_locale_calls.size(), 10)


func test_duplicate_string_profile_ids_keep_diagnostic_order() -> void:
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate({
		"schema_version": 2,
		"profiles": [
			_valid_profile("7"),
			_valid_profile("7"),
		],
	})

	assert_false(result.is_valid)
	assert_eq(result.profile_count, 2)
	assert_eq(_reported_failures, [
		"profiles[1].id|unique difficulty profile id",
	])


func test_numeric_boundaries_and_failures_keep_field_order() -> void:
	var profile: Dictionary = _valid_profile("difficulty_boundary")
	profile["difficulty_coefficient"] = 0.001
	profile["tier_interval_seconds"] = 3600.0
	profile["continuous_growth_per_interval"] = 0.0
	profile["tier_step_growth"] = 10.0
	profile["damage_growth_ratio"] = 0
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate({
		"schema_version": 2.0,
		"profiles": [profile],
	})
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	profile["difficulty_coefficient"] = 0.0
	profile["tier_interval_seconds"] = 0.0
	profile["continuous_growth_per_interval"] = -0.1
	profile["tier_step_growth"] = 10.1
	profile["damage_growth_ratio"] = INF
	result = _validate({
		"schema_version": 2,
		"profiles": [profile],
	})
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"profiles[0].difficulty_coefficient|number > 0.0",
		"profiles[0].tier_interval_seconds|number > 0.0",
		(
			"profiles[0].continuous_growth_per_interval|"
			+ "number >= 0.0"
		),
		"profiles[0].tier_step_growth|number <= 10.0",
		"profiles[0].damage_growth_ratio|finite number",
	])


func test_duplicate_string_stage_keys_follow_locale_validation() -> void:
	var profile: Dictionary = _valid_profile("difficulty_stage_keys")
	profile["stage_name_keys"] = [
		"ui_difficulty_stage_1",
		"ui_difficulty_stage_1",
		"missing_stage",
		"ui_difficulty_stage_2",
		"ui_difficulty_stage_3",
		"ui_difficulty_stage_4",
		"ui_difficulty_stage_5",
		"ui_difficulty_stage_6",
		"ui_difficulty_stage_7",
	]
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate({
		"schema_version": 2,
		"profiles": [profile],
	})

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"profiles[0].stage_name_keys[1]|unique stage name key",
		(
			"profiles[0].stage_name_keys[2]|"
			+ "registered locale key prefix"
		),
		"profiles[0].stage_name_keys[2]|key present in strings.csv",
	])


func test_locale_port_accepts_mod_aware_keys() -> void:
	_registered_locale_prefixes.append("mod_example_")
	_available_locale_keys["mod_example_difficulty_name"] = true
	var mod_stage_keys: Array = []
	for stage_number: int in range(1, 10):
		var stage_key: String = "mod_example_difficulty_stage_%d" % (
			stage_number
		)
		_available_locale_keys[stage_key] = true
		mod_stage_keys.append(stage_key)
	var profile: Dictionary = _valid_profile("mod_example_difficulty")
	profile["name_key"] = "mod_example_difficulty_name"
	profile["stage_name_keys"] = mod_stage_keys

	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate({
		"schema_version": 2,
		"profiles": [profile],
	})
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])
	assert_eq(_locale_calls.size(), 10)


func test_success_and_failure_calls_do_not_share_state() -> void:
	var invalid_result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = (
		_validate([])
	)
	assert_false(invalid_result.is_valid)
	assert_eq(invalid_result.profile_count, 0)

	_clear_diagnostics()
	var valid_result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)
	assert_true(valid_result.is_valid)
	assert_eq(valid_result.profile_count, 1)
	assert_eq(_reported_failures, [])
	assert_eq(invalid_result.profile_count, 0)


func test_report_failure_arguments_support_data_loader_text_adapter() -> void:
	var result: DIFFICULTY_PROFILE_VALIDATOR.ValidationResult = (
		DIFFICULTY_PROFILE_VALIDATOR.validate(
			[],
			Callable(self, "_require_locale_key"),
			Callable(self, "_record_data_loader_failure")
		)
	)
	assert_false(result.is_valid)
	assert_eq(_data_loader_messages, [
		(
			"[DataLoader] res://data/difficulty_profiles.json:root "
			+ "expected Dictionary"
		),
	])


func _validate(
	raw_data: Variant
) -> DIFFICULTY_PROFILE_VALIDATOR.ValidationResult:
	return DIFFICULTY_PROFILE_VALIDATOR.validate(
		raw_data,
		Callable(self, "_require_locale_key"),
		Callable(self, "_record_failure")
	)


func _require_locale_key(field: String, value: Variant) -> bool:
	if not value is String or String(value).is_empty():
		_locale_calls.append("%s|<non-string>" % field)
		_record_failure(field, "non-empty locale key")
		return false

	var key: String = String(value)
	_locale_calls.append("%s|%s" % [field, key])
	var is_valid: bool = true
	var has_registered_prefix: bool = false
	for prefix: String in _registered_locale_prefixes:
		if key.begins_with(prefix):
			has_registered_prefix = true
			break
	if not has_registered_prefix:
		_record_failure(field, "registered locale key prefix")
		is_valid = false
	if not _available_locale_keys.has(key):
		_record_failure(field, "key present in strings.csv")
		is_valid = false
	return is_valid


func _record_failure(field: String, expected: String) -> void:
	_reported_failures.append("%s|%s" % [field, expected])


func _record_data_loader_failure(field: String, expected: String) -> void:
	_data_loader_messages.append(
		"[DataLoader] %s:%s expected %s" % [
			DIFFICULTY_PROFILES_PATH,
			field,
			expected,
		]
	)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_locale_calls.clear()


func _valid_payload() -> Dictionary:
	return {
		"schema_version": 2,
		"profiles": [_valid_profile("difficulty_standard")],
	}


func _valid_profile(id: String) -> Dictionary:
	var stage_name_keys: Array = []
	for stage_number: int in range(1, 10):
		stage_name_keys.append("ui_difficulty_stage_%d" % stage_number)
	return {
		"id": id,
		"name_key": "ui_difficulty_standard_name",
		"difficulty_coefficient": 1.0,
		"tier_interval_seconds": 90.0,
		"continuous_growth_per_interval": 0.04,
		"tier_step_growth": 0.09,
		"damage_growth_ratio": 0.48,
		"stage_name_keys": stage_name_keys,
	}
