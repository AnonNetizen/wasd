extends SmokeHarness


const REWARD_CHOICE_POOL_VALIDATOR := preload(
	"res://scripts/data/reward_choice_pool_validator.gd"
)
const REWARD_CHOICE_POOLS_PATH: String = (
	"res://data/reward_choice_pools.json"
)

var _reported_failures: Array[String] = []
var _locale_calls: Array[String] = []
var _modifier_calls: Array[String] = []
var _available_locale_keys: Dictionary = {}
var _registered_locale_prefixes: Array[String] = []
var _registered_stats: Dictionary = {}
var _data_loader_messages: Array[String] = []


func before_each() -> void:
	super()
	_reported_failures.clear()
	_locale_calls.clear()
	_modifier_calls.clear()
	_available_locale_keys.clear()
	_registered_locale_prefixes.clear()
	_registered_stats.clear()
	_data_loader_messages.clear()
	_registered_locale_prefixes.append("ui_reward_")
	for key: String in [
		"ui_reward_damage_small_name",
		"ui_reward_damage_small_desc",
	]:
		_available_locale_keys[key] = true
	for stat: String in ["damage", "fire_rate", "pickup_range"]:
		_registered_stats[stat] = true


func test_valid_payload_returns_pool_count_and_callback_order() -> void:
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)

	assert_true(result.is_valid)
	assert_eq(result.pool_count, 1)
	assert_eq(_reported_failures, [])
	assert_eq(_locale_calls, [
		"pools[0].entries[0].name_key|ui_reward_damage_small_name",
		"pools[0].entries[0].desc_key|ui_reward_damage_small_desc",
	])
	assert_eq(_modifier_calls, ["pools[0].entries[0].modifiers"])


func test_root_short_circuit_and_schema_version_keep_legacy_rules() -> void:
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate([])
	assert_false(result.is_valid)
	assert_eq(result.pool_count, 0)
	assert_eq(_reported_failures, ["root|Dictionary"])

	_clear_diagnostics()
	result = _validate({
		"schema_version": 2,
		"pools": [],
		"future_metadata": true,
	})
	assert_false(result.is_valid)
	assert_eq(result.pool_count, 0)
	assert_eq(_reported_failures, ["schema_version|int equal to 1"])

	_clear_diagnostics()
	result = _validate({
		"schema_version": 1.0,
		"pools": [],
		"future_metadata": true,
	})
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])


func test_non_array_pools_reports_but_keeps_legacy_true_result() -> void:
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"pools": "invalid",
	})

	assert_true(result.is_valid)
	assert_eq(result.pool_count, 0)
	assert_eq(_reported_failures, ["pools|Array"])


func test_source_pool_count_and_non_dictionary_pool_continue() -> void:
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"pools": [
			null,
			_valid_pool("first_pool", []),
			_valid_pool("second_pool", []),
		],
	})

	assert_false(result.is_valid)
	assert_eq(result.pool_count, 3)
	assert_eq(_reported_failures, ["pools[0]|Dictionary"])


func test_duplicate_string_pool_ids_keep_diagnostic_order() -> void:
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"pools": [
			_valid_pool("duplicate_pool", []),
			_valid_pool("duplicate_pool", []),
		],
	})

	assert_false(result.is_valid)
	assert_eq(result.pool_count, 2)
	assert_eq(_reported_failures, [
		"pools[1].id|unique pool id",
	])


func test_non_array_entries_reports_but_keeps_legacy_true_result() -> void:
	var pool: Dictionary = _valid_pool("invalid_entries", [])
	pool["entries"] = "invalid"
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"pools": [pool],
	})

	assert_true(result.is_valid)
	assert_eq(_reported_failures, ["pools[0].entries|Array"])


func test_entry_failures_keep_locale_duplicate_and_field_order() -> void:
	var first_entry: Dictionary = _valid_entry("duplicate_entry")
	var second_entry: Dictionary = {
		"id": "duplicate_entry",
		"name_key": "",
		"desc_key": "",
		"kind": "",
		"weight": 0,
		"min_level": 0,
		"modifiers": [],
	}
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"pools": [
			_valid_pool("entry_order", [first_entry, second_entry]),
		],
	})

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"pools[0].entries[1].name_key|non-empty locale key",
		"pools[0].entries[1].desc_key|non-empty locale key",
		"pools[0].entries[1].id|unique entry id",
		"pools[0].entries[1].kind|non-empty string",
		"pools[0].entries[1].kind|stat_modifier",
		"pools[0].entries[1].weight|int >= 1",
		"pools[0].entries[1].min_level|int >= 1",
	])
	assert_eq(_modifier_calls, [
		"pools[0].entries[0].modifiers",
		"pools[0].entries[1].modifiers",
	])


func test_modifier_shape_and_stat_diagnostics_keep_legacy_bool_gaps() -> void:
	var entry: Dictionary = _valid_entry("invalid_modifier_container")
	entry["modifiers"] = "invalid"
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"pools": [_valid_pool("modifier_gaps", [entry])],
	})
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [
		"pools[0].entries[0].modifiers|Array",
	])

	_clear_diagnostics()
	entry = _valid_entry("missing_stat")
	entry["modifiers"] = [{"type": "add", "value": 1.0}]
	result = _validate({
		"schema_version": 1,
		"pools": [_valid_pool("modifier_gaps", [entry])],
	})
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [
		"pools[0].entries[0].modifiers[0].stat|non-empty string",
	])

	_clear_diagnostics()
	entry = _valid_entry("unknown_stat")
	entry["modifiers"] = [
		{"stat": "future_stat", "type": "mult", "value": "ignored"},
	]
	result = _validate({
		"schema_version": 1,
		"pools": [_valid_pool("modifier_gaps", [entry])],
	})
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [
		"pools[0].entries[0].modifiers[0].stat|registered id in stats",
	])


func test_modifier_callback_false_still_propagates() -> void:
	var entry: Dictionary = _valid_entry("invalid_modifier")
	entry["modifiers"] = [null]
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"pools": [_valid_pool("modifier_failure", [entry])],
	})

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"pools[0].entries[0].modifiers[0]|Dictionary",
	])


func test_locale_port_accepts_mod_aware_keys() -> void:
	_registered_locale_prefixes.append("mod_example_")
	_available_locale_keys["mod_example_reward_name"] = true
	_available_locale_keys["mod_example_reward_desc"] = true
	var entry: Dictionary = _valid_entry("mod_example_reward")
	entry["name_key"] = "mod_example_reward_name"
	entry["desc_key"] = "mod_example_reward_desc"
	var result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"pools": [_valid_pool("mod_example_pool", [entry])],
	})

	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])
	assert_eq(_locale_calls, [
		"pools[0].entries[0].name_key|mod_example_reward_name",
		"pools[0].entries[0].desc_key|mod_example_reward_desc",
	])


func test_success_failure_calls_and_data_loader_adapter_are_isolated() -> void:
	var invalid_result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = (
		_validate([])
	)
	assert_false(invalid_result.is_valid)
	assert_eq(invalid_result.pool_count, 0)

	_clear_diagnostics()
	var valid_result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)
	assert_true(valid_result.is_valid)
	assert_eq(valid_result.pool_count, 1)
	assert_eq(_reported_failures, [])

	var adapter_result: REWARD_CHOICE_POOL_VALIDATOR.ValidationResult = (
		REWARD_CHOICE_POOL_VALIDATOR.validate(
			[],
			Callable(self, "_require_locale_key"),
			Callable(self, "_validate_modifiers"),
			Callable(self, "_record_data_loader_failure")
		)
	)
	assert_false(adapter_result.is_valid)
	assert_eq(_data_loader_messages, [
		(
			"[DataLoader] res://data/reward_choice_pools.json:root "
			+ "expected Dictionary"
		),
	])


func _validate(
	raw_data: Variant
) -> REWARD_CHOICE_POOL_VALIDATOR.ValidationResult:
	return REWARD_CHOICE_POOL_VALIDATOR.validate(
		raw_data,
		Callable(self, "_require_locale_key"),
		Callable(self, "_validate_modifiers"),
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


func _validate_modifiers(field: String, data: Variant) -> bool:
	_modifier_calls.append(field)
	if not data is Array:
		_record_failure(field, "Array")
		return true

	var modifiers: Array = data as Array
	var is_valid: bool = true
	for index: int in range(modifiers.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var raw_modifier: Variant = modifiers[index]
		if not raw_modifier is Dictionary:
			_record_failure(item_field, "Dictionary")
			is_valid = false
			continue
		var modifier: Dictionary = raw_modifier as Dictionary
		var stat: String = _require_registered_stat(
			"%s.stat" % item_field,
			modifier.get("stat")
		)
		var modifier_type: String = String(modifier.get("type", ""))
		if modifier_type != "add" and modifier_type != "mult":
			_record_failure("%s.type" % item_field, "add or mult")
			is_valid = false
		if not modifier.has("value"):
			_record_failure("%s.value" % item_field, "number")
			is_valid = false
		elif (
			not stat.is_empty()
			and not modifier.get("value") is float
			and not modifier.get("value") is int
		):
			_record_failure("%s.value" % item_field, "number")
			is_valid = false
	return is_valid


func _require_registered_stat(field: String, value: Variant) -> String:
	if not value is String or String(value).is_empty():
		_record_failure(field, "non-empty string")
		return ""
	var stat: String = String(value)
	if not _registered_stats.has(stat):
		_record_failure(field, "registered id in stats")
		return ""
	return stat


func _record_failure(field: String, expected: String) -> void:
	_reported_failures.append("%s|%s" % [field, expected])


func _record_data_loader_failure(field: String, expected: String) -> void:
	_data_loader_messages.append(
		"[DataLoader] %s:%s expected %s" % [
			REWARD_CHOICE_POOLS_PATH,
			field,
			expected,
		]
	)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_locale_calls.clear()
	_modifier_calls.clear()


func _valid_payload() -> Dictionary:
	return {
		"schema_version": 1,
		"pools": [
			_valid_pool("default_reward_choice", [
				_valid_entry("reward_damage_small"),
			]),
		],
	}


func _valid_pool(id: String, entries: Array) -> Dictionary:
	return {
		"id": id,
		"entries": entries,
	}


func _valid_entry(id: String) -> Dictionary:
	return {
		"id": id,
		"name_key": "ui_reward_damage_small_name",
		"desc_key": "ui_reward_damage_small_desc",
		"kind": "stat_modifier",
		"weight": 100,
		"min_level": 1,
		"modifiers": [
			{"stat": "damage", "type": "add", "value": 0.5},
		],
	}
