extends SmokeHarness


const PLAYER_DATA_VALIDATOR := preload(
	"res://scripts/data/player_data_validator.gd"
)
const PLAYER_DATA_PATH: String = "res://data/player.json"

var _reported_failures: Array[String] = []
var _stat_calls: Array[String] = []
var _pool_calls: Array[String] = []
var _events: Array[String] = []
var _rejected_stats: Dictionary = {}
var _registered_pools: Dictionary = {}
var _data_loader_messages: Array[String] = []


func before_each() -> void:
	super()
	_reported_failures.clear()
	_stat_calls.clear()
	_pool_calls.clear()
	_events.clear()
	_rejected_stats.clear()
	_registered_pools.clear()
	_data_loader_messages.clear()
	_registered_pools["gold_orb"] = true
	_registered_pools["energy_orb"] = true


func test_canonical_payload_returns_raw_stat_count_and_callback_order() -> void:
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)

	assert_true(result.is_valid)
	assert_true(result.has_stat_count)
	assert_eq(result.stat_count, 3)
	assert_eq(_reported_failures, [])
	assert_eq(_stat_calls, [
		"base_stats.max_hp|max_hp",
		"base_stats.damage|damage",
		"base_stats.bullet_count|bullet_count",
	])
	assert_eq(_pool_calls, ["gold_drop.pool_id|gold_orb"])


func test_non_dictionary_root_hard_returns_without_callbacks_or_count() -> void:
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate([])

	assert_false(result.is_valid)
	assert_false(result.has_stat_count)
	assert_eq(result.stat_count, 0)
	assert_eq(_reported_failures, ["root|Dictionary"])
	assert_eq(_stat_calls, [])
	assert_eq(_pool_calls, [])


func test_integral_float_schema_version_remains_int_like() -> void:
	var payload: Dictionary = _valid_payload()
	payload["schema_version"] = 4.0
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(payload)

	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	payload["schema_version"] = 5.0
	result = _validate(payload)
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"schema_version|int equal to 4",
	])


func test_body_required_extra_and_radius_failures_keep_source_order() -> void:
	var payload: Dictionary = _valid_payload()
	var body: Dictionary = {}
	body["future_first"] = true
	body["future_second"] = true
	payload["body"] = body
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(payload)

	assert_false(result.is_valid)
	assert_true(result.has_stat_count)
	assert_eq(_reported_failures, [
		"body.radius|required field",
		"body.future_first|allowed schema field",
		"body.future_second|allowed schema field",
		"body.radius|number",
	])


func test_base_stats_shape_and_empty_dictionary_hard_return() -> void:
	var payload: Dictionary = _valid_payload()
	payload["schema_version"] = 5
	payload["body"] = []
	payload["base_stats"] = []
	payload["gold_drop"] = []
	payload["energy_drop"] = []
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(payload)

	assert_false(result.is_valid)
	assert_false(result.has_stat_count)
	assert_eq(_reported_failures, [
		"schema_version|int equal to 4",
		"body|Dictionary",
		"base_stats|non-empty Dictionary",
	])
	assert_eq(_stat_calls, [])
	assert_eq(_pool_calls, [])

	_clear_diagnostics()
	payload = _valid_payload()
	payload["base_stats"] = {}
	payload["gold_drop"] = []
	payload["energy_drop"] = []
	result = _validate(payload)
	assert_false(result.is_valid)
	assert_false(result.has_stat_count)
	assert_eq(_reported_failures, [
		"base_stats|non-empty Dictionary",
	])
	assert_eq(_pool_calls, [])


func test_legacy_stat_reports_before_source_order_callbacks_and_counts_raw_keys() -> void:
	var payload: Dictionary = _valid_payload()
	var stats: Dictionary = {}
	stats["damage"] = 3.5
	stats["pickup_orb_speed"] = 360.0
	stats["future_stat"] = "invalid value"
	payload["base_stats"] = stats
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(payload)

	assert_false(result.is_valid)
	assert_true(result.has_stat_count)
	assert_eq(result.stat_count, 3)
	assert_eq(_reported_failures, [
		"base_stats.pickup_orb_speed|removed in schema_version 3",
	])
	assert_eq(_stat_calls, [
		"base_stats.damage|damage",
		"base_stats.pickup_orb_speed|pickup_orb_speed",
		"base_stats.future_stat|future_stat",
	])
	assert_eq(_events, [
		(
			"failure:base_stats.pickup_orb_speed|"
			+ "removed in schema_version 3"
		),
		"stat:base_stats.damage|damage",
		"stat:base_stats.pickup_orb_speed|pickup_orb_speed",
		"stat:base_stats.future_stat|future_stat",
	])


func test_stat_callback_false_propagates_without_short_circuiting_later_stats() -> void:
	_rejected_stats["damage"] = "valid stat value"
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"base_stats.damage|valid stat value",
	])
	assert_eq(_stat_calls, [
		"base_stats.max_hp|max_hp",
		"base_stats.damage|damage",
		"base_stats.bullet_count|bullet_count",
	])


func test_gold_pool_empty_unknown_and_wrong_registered_keep_legacy_diagnostics() -> void:
	var payload: Dictionary = _valid_payload()
	payload["gold_drop"] = {"pickup_speed": 360.0}
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(payload)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"gold_drop.pool_id|non-empty string",
		"gold_drop.pool_id|gold_orb",
	])

	_clear_diagnostics()
	payload["gold_drop"] = {
		"pickup_speed": 360.0,
		"pool_id": "future_orb",
	}
	result = _validate(payload)
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"gold_drop.pool_id|registered id in pool_ids",
		"gold_drop.pool_id|gold_orb",
	])

	_clear_diagnostics()
	payload["gold_drop"] = {
		"pickup_speed": 360.0,
		"pool_id": "energy_orb",
	}
	result = _validate(payload)
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"gold_drop.pool_id|gold_orb",
	])


func test_energy_and_other_root_sections_keep_legacy_under_validation() -> void:
	var payload: Dictionary = _valid_payload()
	payload["defense"] = "not validated here"
	payload["dash"] = {"future": true}
	payload["future_root"] = true
	var gold_drop: Dictionary = payload["gold_drop"] as Dictionary
	gold_drop["future_gold_field"] = []
	payload["energy_drop"] = {
		"pickup_speed": 1.0,
		"chance": "not validated",
		"amount": null,
		"pool_id": "future_orb",
		"rng_stream": [],
		"future_energy_field": {},
	}
	var result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(payload)

	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])


func test_success_failure_calls_and_data_loader_adapter_are_isolated() -> void:
	var invalid_result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate([])
	assert_false(invalid_result.is_valid)
	assert_false(invalid_result.has_stat_count)

	_clear_diagnostics()
	var valid_result: PLAYER_DATA_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)
	assert_true(valid_result.is_valid)
	assert_true(valid_result.has_stat_count)
	assert_eq(valid_result.stat_count, 3)
	assert_eq(_reported_failures, [])

	var adapter_result: PLAYER_DATA_VALIDATOR.ValidationResult = (
		PLAYER_DATA_VALIDATOR.validate(
			[],
			Callable(self, "_validate_stat_value"),
			Callable(self, "_require_pool_id"),
			Callable(self, "_record_data_loader_failure")
		)
	)
	assert_false(adapter_result.is_valid)
	assert_eq(_data_loader_messages, [
		"[DataLoader] res://data/player.json:root expected Dictionary",
	])


func _validate(
	raw_data: Variant
) -> PLAYER_DATA_VALIDATOR.ValidationResult:
	return PLAYER_DATA_VALIDATOR.validate(
		raw_data,
		Callable(self, "_validate_stat_value"),
		Callable(self, "_require_pool_id"),
		Callable(self, "_record_failure")
	)


func _validate_stat_value(
	field: String,
	stat: String,
	_value: Variant
) -> bool:
	var call: String = "%s|%s" % [field, stat]
	_stat_calls.append(call)
	_events.append("stat:%s" % call)
	if not _rejected_stats.has(stat):
		return true
	_record_failure(field, String(_rejected_stats[stat]))
	return false


func _require_pool_id(field: String, value: Variant) -> String:
	if not value is String or String(value).is_empty():
		_pool_calls.append("%s|<non-string>" % field)
		_record_failure(field, "non-empty string")
		return ""
	var pool_id: String = String(value)
	_pool_calls.append("%s|%s" % [field, pool_id])
	if not _registered_pools.has(pool_id):
		_record_failure(field, "registered id in pool_ids")
		return ""
	return pool_id


func _record_failure(field: String, expected: String) -> void:
	var failure: String = "%s|%s" % [field, expected]
	_reported_failures.append(failure)
	_events.append("failure:%s" % failure)


func _record_data_loader_failure(field: String, expected: String) -> void:
	_data_loader_messages.append(
		"[DataLoader] %s:%s expected %s" % [
			PLAYER_DATA_PATH,
			field,
			expected,
		]
	)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_stat_calls.clear()
	_pool_calls.clear()
	_events.clear()


func _valid_payload() -> Dictionary:
	return {
		"schema_version": 4,
		"body": {"radius": 25.0},
		"base_stats": {
			"max_hp": 600.0,
			"damage": 3.5,
			"bullet_count": 1,
		},
		"defense": {},
		"dash": {},
		"gold_drop": {
			"pickup_speed": 360.0,
			"pool_id": "gold_orb",
		},
		"energy_drop": {
			"pickup_speed": 360.0,
		},
	}
