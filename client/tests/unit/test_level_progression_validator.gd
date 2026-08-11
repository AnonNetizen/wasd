extends SmokeHarness


const LEVEL_PROGRESSION_VALIDATOR := preload(
	"res://scripts/data/level_progression_validator.gd"
)
const LEVEL_PROGRESSION_PATH: String = "res://data/level_progression.json"

var _reported_failures: Array[String] = []
var _data_loader_messages: Array[String] = []


func before_each() -> void:
	super()
	_reported_failures.clear()
	_data_loader_messages.clear()


func test_valid_payload_and_minimum_boundary_are_accepted() -> void:
	assert_true(_validate(_valid_payload()))
	assert_true(_validate({
		"schema_version": 1,
		"first_level_cost": 1,
		"multiplier_numerator": 2,
		"multiplier_denominator": 1,
	}))
	assert_eq(_reported_failures, [])


func test_root_requires_dictionary_with_legacy_failure() -> void:
	assert_false(_validate([]))
	assert_eq(_reported_failures, [
		"root|Dictionary",
	])


func test_field_failures_keep_legacy_order_and_expected_text() -> void:
	assert_false(_validate({
		"schema_version": 2,
		"first_level_cost": 0,
		"multiplier_numerator": 0,
		"multiplier_denominator": 0,
	}))
	assert_eq(_reported_failures, [
		"schema_version|int equal to 1",
		"first_level_cost|int >= 1",
		"multiplier_numerator|int >= 1",
		"multiplier_denominator|int >= 1",
		(
			"multiplier_numerator|"
			+ "int greater than multiplier_denominator"
		),
	])


func test_missing_fields_report_int_errors_in_field_order() -> void:
	assert_false(_validate({}))
	assert_eq(_reported_failures, [
		"schema_version|int",
		"first_level_cost|int",
		"multiplier_numerator|int",
		"multiplier_denominator|int",
	])


func test_integral_float_values_remain_int_like() -> void:
	assert_true(_validate({
		"schema_version": 1.0,
		"first_level_cost": 1.0,
		"multiplier_numerator": 2.0,
		"multiplier_denominator": 1.0,
	}))
	assert_eq(_reported_failures, [])


func test_minimum_failure_still_runs_int_like_relationship_check() -> void:
	var payload: Dictionary = _valid_payload()
	payload["multiplier_numerator"] = 0

	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"multiplier_numerator|int >= 1",
		(
			"multiplier_numerator|"
			+ "int greater than multiplier_denominator"
		),
	])


func test_non_int_operand_skips_relationship_check() -> void:
	var payload: Dictionary = _valid_payload()
	payload["multiplier_numerator"] = "0"

	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"multiplier_numerator|int",
	])


func test_extra_root_key_remains_allowed() -> void:
	var payload: Dictionary = _valid_payload()
	payload["future_metadata"] = {"ignored": true}

	assert_true(_validate(payload))
	assert_eq(_reported_failures, [])


func test_success_and_failure_calls_do_not_share_state() -> void:
	assert_false(_validate([]))
	assert_eq(_reported_failures, ["root|Dictionary"])

	_reported_failures.clear()
	assert_true(_validate(_valid_payload()))
	assert_eq(_reported_failures, [])

	assert_false(_validate({}))
	assert_eq(_reported_failures, [
		"schema_version|int",
		"first_level_cost|int",
		"multiplier_numerator|int",
		"multiplier_denominator|int",
	])


func test_report_failure_arguments_support_data_loader_text_adapter() -> void:
	assert_false(LEVEL_PROGRESSION_VALIDATOR.validate(
		[],
		Callable(self, "_record_data_loader_failure")
	))
	assert_eq(_data_loader_messages, [
		(
			"[DataLoader] res://data/level_progression.json:root "
			+ "expected Dictionary"
		),
	])


func _validate(raw_data: Variant) -> bool:
	return LEVEL_PROGRESSION_VALIDATOR.validate(
		raw_data,
		Callable(self, "_record_failure")
	)


func _record_failure(field: String, expected: String) -> void:
	_reported_failures.append("%s|%s" % [field, expected])


func _record_data_loader_failure(field: String, expected: String) -> void:
	_data_loader_messages.append(
		"[DataLoader] %s:%s expected %s" % [
			LEVEL_PROGRESSION_PATH,
			field,
			expected,
		]
	)


func _valid_payload() -> Dictionary:
	return {
		"schema_version": 1,
		"first_level_cost": 100,
		"multiplier_numerator": 13,
		"multiplier_denominator": 10,
	}
