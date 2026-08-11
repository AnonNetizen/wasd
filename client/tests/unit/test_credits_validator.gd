extends SmokeHarness


const CREDITS_VALIDATOR := preload(
	"res://scripts/data/credits_validator.gd"
)
const CREDITS_PATH: String = "res://data/credits.json"

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
	_registered_locale_prefixes.append("ui_credits_")
	for key: String in [
		"ui_credits_section_staff",
		"ui_credits_role_project_owner",
		"ui_credits_role_ai_assisted_development",
	]:
		_available_locale_keys[key] = true


func test_valid_payload_returns_source_counts_and_locale_order() -> void:
	var result: CREDITS_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)

	assert_true(result.is_valid)
	assert_eq(result.section_count, 1)
	assert_eq(result.entry_count, 2)
	assert_eq(_reported_failures, [])
	assert_eq(_locale_calls, [
		"sections[0].title_key|ui_credits_section_staff",
		(
			"sections[0].entries[0].role_key|"
			+ "ui_credits_role_project_owner"
		),
		(
			"sections[0].entries[1].role_key|"
			+ "ui_credits_role_ai_assisted_development"
		),
	])


func test_schema_keeps_int_like_minimum_and_extra_key_behavior() -> void:
	var payload: Dictionary = _valid_payload()
	var sections: Array = payload["sections"] as Array
	var section: Dictionary = sections[0] as Dictionary
	var entries: Array = section["entries"] as Array
	var entry: Dictionary = entries[0] as Dictionary
	payload["schema_version"] = 2.0
	payload["future_root"] = true
	section["future_section"] = true
	entry["future_entry"] = true

	var result: CREDITS_VALIDATOR.ValidationResult = _validate(payload)
	assert_true(result.is_valid)
	assert_eq(result.section_count, 1)
	assert_eq(result.entry_count, 2)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	payload["schema_version"] = 0
	result = _validate(payload)
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"schema_version|int >= 1",
	])

	_clear_diagnostics()
	payload["schema_version"] = 1.5
	result = _validate(payload)
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"schema_version|int",
	])


func test_root_and_sections_shapes_keep_legacy_short_circuits() -> void:
	var result: CREDITS_VALIDATOR.ValidationResult = _validate([])
	assert_false(result.is_valid)
	assert_eq(result.section_count, 0)
	assert_eq(result.entry_count, 0)
	assert_eq(_reported_failures, [
		"root|Dictionary",
	])
	assert_eq(_locale_calls, [])

	_clear_diagnostics()
	result = _validate({
		"schema_version": 1,
		"sections": "invalid",
	})
	assert_false(result.is_valid)
	assert_eq(result.section_count, 0)
	assert_eq(result.entry_count, 0)
	assert_eq(_reported_failures, [
		"sections|Array",
		"sections|non-empty Array",
	])

	_clear_diagnostics()
	result = _validate({
		"schema_version": 1,
		"sections": [],
	})
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"sections|non-empty Array",
	])


func test_mixed_shapes_keep_source_order_and_shape_counts() -> void:
	var result: CREDITS_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"sections": [
			null,
			{
				"id": "bad_entries",
				"title_key": "ui_credits_section_staff",
				"entries": "invalid",
			},
			{
				"id": "mixed_entries",
				"title_key": "ui_credits_section_staff",
				"entries": [
					[],
					_staff_entry(),
				],
			},
		],
	})

	assert_false(result.is_valid)
	assert_eq(result.section_count, 3)
	assert_eq(result.entry_count, 2)
	assert_eq(_reported_failures, [
		"sections[0]|Dictionary",
		"sections[1].entries|Array",
		"sections[1].entries|non-empty Array",
		"sections[2].entries[0]|Dictionary",
	])
	assert_eq(_locale_calls, [
		"sections[1].title_key|ui_credits_section_staff",
		"sections[2].title_key|ui_credits_section_staff",
		(
			"sections[2].entries[1].role_key|"
			+ "ui_credits_role_project_owner"
		),
	])


func test_string_section_ids_participate_in_duplicates() -> void:
	var result: CREDITS_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"sections": [
			_section("7", [_staff_entry()]),
			_section("7", [_staff_entry()]),
		],
	})

	assert_false(result.is_valid)
	assert_eq(result.section_count, 2)
	assert_eq(result.entry_count, 2)
	assert_eq(_reported_failures, [
		"sections[1].id|unique section id",
	])


func test_entry_branches_keep_legacy_error_order() -> void:
	var result: CREDITS_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"sections": [
			{
				"id": "entry_branches",
				"title_key": "ui_credits_section_staff",
				"entries": [
					[],
					{
						"kind": "external_future",
						"name": "",
						"role_key": "missing_role",
						"copyright": "",
					},
					{
						"kind": "future",
						"name": "Future",
						"role_key": (
							"ui_credits_role_project_owner"
						),
					},
					{
						"kind": "staff",
						"name": "Staff",
						"role_key": (
							"ui_credits_role_project_owner"
						),
						"url": false,
						"license": false,
						"included_in_build": "ignored",
						"requires_notice": "ignored",
						"review_required": "ignored",
					},
				],
			},
		],
	})

	assert_false(result.is_valid)
	assert_eq(result.section_count, 1)
	assert_eq(result.entry_count, 4)
	assert_eq(_reported_failures, [
		"sections[0].entries[0]|Dictionary",
		(
			"sections[0].entries[1].kind|staff, external_resource, "
			+ "external_library, or external_tool"
		),
		"sections[0].entries[1].name|non-empty string",
		(
			"sections[0].entries[1].role_key|"
			+ "registered locale key prefix"
		),
		(
			"sections[0].entries[1].role_key|"
			+ "key present in strings.csv"
		),
		"sections[0].entries[1].url|non-empty string",
		"sections[0].entries[1].license|non-empty string",
		"sections[0].entries[1].included_in_build|bool",
		"sections[0].entries[1].requires_notice|bool",
		"sections[0].entries[1].review_required|bool",
		"sections[0].entries[1].copyright|non-empty string",
		(
			"sections[0].entries[2].kind|staff, external_resource, "
			+ "external_library, or external_tool"
		),
	])


func test_locale_port_keeps_mod_aware_callback_ownership() -> void:
	_registered_locale_prefixes.append("mod_example_")
	_available_locale_keys["mod_example_credit_section"] = true
	_available_locale_keys["mod_example_credit_role"] = true
	var payload: Dictionary = {
		"schema_version": 1,
		"sections": [
			{
				"id": "mod_section",
				"title_key": "mod_example_credit_section",
				"entries": [
					{
						"kind": "staff",
						"name": "Mod Staff",
						"role_key": "mod_example_credit_role",
					},
				],
			},
		],
	}

	var result: CREDITS_VALIDATOR.ValidationResult = _validate(payload)
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])
	assert_eq(_locale_calls, [
		"sections[0].title_key|mod_example_credit_section",
		"sections[0].entries[0].role_key|mod_example_credit_role",
	])


func test_locale_non_string_short_circuit_keeps_field_order() -> void:
	var result: CREDITS_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"sections": [
			{
				"id": "locale_short_circuit",
				"title_key": null,
				"entries": [
					{
						"kind": "staff",
						"name": "Staff",
						"role_key": null,
					},
				],
			},
		],
	})

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"sections[0].title_key|non-empty locale key",
		"sections[0].entries[0].role_key|non-empty locale key",
	])


func test_success_and_failure_calls_do_not_share_state() -> void:
	var invalid_result: CREDITS_VALIDATOR.ValidationResult = _validate([])
	assert_false(invalid_result.is_valid)
	assert_eq(invalid_result.section_count, 0)

	_clear_diagnostics()
	var valid_result: CREDITS_VALIDATOR.ValidationResult = _validate(
		_valid_payload()
	)
	assert_true(valid_result.is_valid)
	assert_eq(valid_result.section_count, 1)
	assert_eq(valid_result.entry_count, 2)
	assert_eq(_reported_failures, [])
	assert_eq(invalid_result.section_count, 0)
	assert_eq(invalid_result.entry_count, 0)


func test_report_failure_arguments_support_data_loader_text_adapter() -> void:
	var result: CREDITS_VALIDATOR.ValidationResult = (
		CREDITS_VALIDATOR.validate(
			[],
			Callable(self, "_require_locale_key"),
			Callable(self, "_record_data_loader_failure")
		)
	)
	assert_false(result.is_valid)
	assert_eq(_data_loader_messages, [
		"[DataLoader] res://data/credits.json:root expected Dictionary",
	])


func _validate(raw_data: Variant) -> CREDITS_VALIDATOR.ValidationResult:
	return CREDITS_VALIDATOR.validate(
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
			CREDITS_PATH,
			field,
			expected,
		]
	)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_locale_calls.clear()


func _valid_payload() -> Dictionary:
	return {
		"schema_version": 1,
		"sections": [
			{
				"id": "staff",
				"title_key": "ui_credits_section_staff",
				"entries": [
					_staff_entry(),
					_external_entry(),
				],
			},
		],
	}


func _section(id: Variant, entries: Array) -> Dictionary:
	return {
		"id": id,
		"title_key": "ui_credits_section_staff",
		"entries": entries,
	}


func _staff_entry() -> Dictionary:
	return {
		"kind": "staff",
		"name": "Project Owner",
		"role_key": "ui_credits_role_project_owner",
	}


func _external_entry() -> Dictionary:
	return {
		"kind": "external_tool",
		"name": "OpenAI Codex",
		"role_key": "ui_credits_role_ai_assisted_development",
		"url": "https://openai.com/codex/",
		"license": "service/tool; not redistributed",
		"included_in_build": false,
		"requires_notice": false,
		"review_required": true,
	}
