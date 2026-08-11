extends SmokeHarness


const ENEMY_REWARD_MODEL_VALIDATOR := preload(
	"res://scripts/data/enemy_reward_model_validator.gd"
)
const ENEMY_REWARDS_PATH: String = "res://data/enemy_rewards.json"

var _reported_failures: Array[String] = []
var _data_loader_messages: Array[String] = []


func before_each() -> void:
	super()
	_reported_failures.clear()
	_data_loader_messages.clear()


func test_canonical_payload_and_minimum_boundaries_are_accepted() -> void:
	assert_true(_validate(_valid_payload()))
	assert_true(_validate({
		"schema_version": 1,
		"base_coefficient": 0.0001,
		"time_growth_per_tier": 0.0,
		"random_multiplier_min": 0.0001,
		"random_multiplier_max": 0.0001,
	}))
	assert_eq(_reported_failures, [])


func test_root_requires_dictionary_with_legacy_failure() -> void:
	assert_false(_validate([]))
	assert_eq(_reported_failures, [
		"root|Dictionary",
	])


func test_empty_dictionary_reports_required_then_scalar_failures() -> void:
	assert_false(_validate({}))
	assert_eq(_reported_failures, [
		"root.schema_version|required field",
		"root.base_coefficient|required field",
		"root.time_growth_per_tier|required field",
		"root.random_multiplier_min|required field",
		"root.random_multiplier_max|required field",
		"schema_version|int",
		"base_coefficient|number",
		"time_growth_per_tier|number",
		"random_multiplier_min|number",
		"random_multiplier_max|number",
	])


func test_extra_keys_keep_dictionary_insertion_order() -> void:
	var payload: Dictionary = _valid_payload()
	payload["extra_second"] = true
	payload["extra_first"] = true

	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"root.extra_second|allowed schema field",
		"root.extra_first|allowed schema field",
	])


func test_schema_accepts_integral_float_and_keeps_legacy_failures() -> void:
	var payload: Dictionary = _valid_payload()
	payload["schema_version"] = 1.0
	assert_true(_validate(payload))
	assert_eq(_reported_failures, [])

	_reported_failures.clear()
	payload["schema_version"] = 1.5
	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"schema_version|int",
	])

	_reported_failures.clear()
	payload["schema_version"] = 2.0
	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"schema_version|int equal to 1",
	])


func test_numeric_fields_require_numbers_in_field_order() -> void:
	assert_false(_validate({
		"schema_version": 1,
		"base_coefficient": "10.0",
		"time_growth_per_tier": false,
		"random_multiplier_min": null,
		"random_multiplier_max": [],
	}))
	assert_eq(_reported_failures, [
		"base_coefficient|number",
		"time_growth_per_tier|number",
		"random_multiplier_min|number",
		"random_multiplier_max|number",
	])


func test_numeric_fields_require_finite_numbers_in_field_order() -> void:
	assert_false(_validate({
		"schema_version": 1,
		"base_coefficient": INF,
		"time_growth_per_tier": INF,
		"random_multiplier_min": INF,
		"random_multiplier_max": INF,
	}))
	assert_eq(_reported_failures, [
		"base_coefficient|finite number",
		"time_growth_per_tier|finite number",
		"random_multiplier_min|finite number",
		"random_multiplier_max|finite number",
	])


func test_positive_and_non_negative_limits_keep_legacy_text() -> void:
	assert_false(_validate({
		"schema_version": 1,
		"base_coefficient": 0.0,
		"time_growth_per_tier": -0.1,
		"random_multiplier_min": 0.0,
		"random_multiplier_max": 0.0,
	}))
	assert_eq(_reported_failures, [
		"base_coefficient|number > 0.0",
		"time_growth_per_tier|number >= 0.0",
		"random_multiplier_min|number > 0.0",
		"random_multiplier_max|number > 0.0",
	])


func test_inverted_range_keeps_legacy_failure() -> void:
	var payload: Dictionary = _valid_payload()
	payload["random_multiplier_min"] = 2.0
	payload["random_multiplier_max"] = 1.0

	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"random_multiplier_min|number <= random_multiplier_max",
	])


func test_numeric_bounds_compare_after_precondition_failures() -> void:
	var payload: Dictionary = _valid_payload()
	payload["random_multiplier_min"] = INF
	payload["random_multiplier_max"] = -1.0

	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"random_multiplier_min|finite number",
		"random_multiplier_max|number > 0.0",
		"random_multiplier_min|number <= random_multiplier_max",
	])


func test_success_and_failure_calls_do_not_share_state() -> void:
	assert_false(_validate([]))
	assert_eq(_reported_failures, ["root|Dictionary"])

	_reported_failures.clear()
	assert_true(_validate(_valid_payload()))
	assert_eq(_reported_failures, [])

	assert_false(_validate({}))
	assert_eq(_reported_failures.size(), 10)
	assert_eq(_reported_failures[0], "root.schema_version|required field")
	assert_eq(_reported_failures[9], "random_multiplier_max|number")


func test_report_failure_arguments_support_data_loader_text_adapter() -> void:
	assert_false(ENEMY_REWARD_MODEL_VALIDATOR.validate(
		[],
		Callable(self, "_record_data_loader_failure")
	))
	assert_eq(_data_loader_messages, [
		(
			"[DataLoader] res://data/enemy_rewards.json:root "
			+ "expected Dictionary"
		),
	])


func _validate(raw_data: Variant) -> bool:
	return ENEMY_REWARD_MODEL_VALIDATOR.validate(
		raw_data,
		Callable(self, "_record_failure")
	)


func _record_failure(field: String, expected: String) -> void:
	_reported_failures.append("%s|%s" % [field, expected])


func _record_data_loader_failure(field: String, expected: String) -> void:
	_data_loader_messages.append(
		"[DataLoader] %s:%s expected %s" % [
			ENEMY_REWARDS_PATH,
			field,
			expected,
		]
	)


func _valid_payload() -> Dictionary:
	return {
		"schema_version": 1,
		"base_coefficient": 10.0,
		"time_growth_per_tier": 0.1,
		"random_multiplier_min": 0.9,
		"random_multiplier_max": 1.1,
	}
