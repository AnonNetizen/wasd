extends SmokeHarness


const ELEMENT_CATALOG_VALIDATOR := preload(
	"res://scripts/data/element_catalog_validator.gd"
)

var _reported_failures: Array[String] = []
var _locale_calls: Array[String] = []
var _element_id_calls: Array[String] = []
var _events: Array[String] = []
var _locale_keys: Dictionary = {}
var _element_ids: Dictionary = {}
var _registered_element_ids: Array = []


func before_each() -> void:
	super()
	_clear_diagnostics()
	_locale_keys = {
		"element_neutral_name": true,
		"element_primary_a_name": true,
		"element_primary_b_name": true,
		"element_composite_ab_name": true,
		"extra_element_name": true,
	}
	_registered_element_ids = [
		"element_neutral",
		"element_primary_a",
		"element_primary_b",
		"element_composite_ab",
	]
	_element_ids = {}
	for element_id: Variant in _registered_element_ids:
		_element_ids[String(element_id)] = true


func test_canonical_root_returns_counts_and_preserves_callback_order() -> void:
	var root: Dictionary = _canonical_root()
	root["future_root"] = true
	var elements: Array = root["elements"] as Array
	var first_element: Dictionary = elements[0] as Dictionary
	first_element["future_element_field"] = "ignored"
	var combinations: Array = root["combinations"] as Array
	var first_combination: Dictionary = combinations[0] as Dictionary
	first_combination["future_combination_field"] = "ignored"

	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_true(result.is_valid)
	assert_eq(result.element_count, 4)
	assert_eq(result.combination_count, 1)
	assert_eq(_reported_failures, [])
	assert_eq(_events, [
		"element_id:neutral_element_id|element_neutral",
		"element_id:elements[0].id|element_neutral",
		"locale:elements[0].name_key|element_neutral_name",
		"element_id:elements[1].id|element_primary_a",
		"locale:elements[1].name_key|element_primary_a_name",
		(
			"element_id:elements[1].components[0]"
			+ "|element_primary_a"
		),
		"element_id:elements[2].id|element_primary_b",
		"locale:elements[2].name_key|element_primary_b_name",
		(
			"element_id:elements[2].components[0]"
			+ "|element_primary_b"
		),
		"element_id:elements[3].id|element_composite_ab",
		"locale:elements[3].name_key|element_composite_ab_name",
		(
			"element_id:elements[3].components[0]"
			+ "|element_primary_a"
		),
		(
			"element_id:elements[3].components[1]"
			+ "|element_primary_b"
		),
		"registered_element_ids",
		"element_id:combinations[0].left|element_primary_a",
		"element_id:combinations[0].right|element_primary_b",
		"element_id:combinations[0].result|element_composite_ab",
	])


func test_non_dictionary_root_hard_returns_without_callbacks_or_counts() -> void:
	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate([])

	assert_false(result.is_valid)
	assert_eq(result.element_count, 0)
	assert_eq(result.combination_count, 0)
	assert_eq(_reported_failures, ["root|Dictionary"])
	assert_eq(_locale_calls, [])
	assert_eq(_element_id_calls, [])
	assert_eq(_events, ["failure:root|Dictionary"])


func test_schema_is_exact_int_like_one_and_top_fields_keep_order() -> void:
	var valid_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_canonical_root())
	)
	assert_true(valid_result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var wrong_top_fields: Dictionary = _canonical_root()
	wrong_top_fields["schema_version"] = 2.0
	wrong_top_fields["neutral_element_id"] = "future_element"
	wrong_top_fields["unmatched_result"] = 0
	var wrong_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(wrong_top_fields)
	)
	assert_false(wrong_result.is_valid)
	assert_eq(_reported_failures, [
		"schema_version|int equal to 1",
		"neutral_element_id|registered id in elements",
		"unmatched_result|String",
	])

	_clear_diagnostics()
	var fractional: Dictionary = _canonical_root()
	fractional["schema_version"] = 1.5
	var fractional_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(fractional)
	)
	assert_false(fractional_result.is_valid)
	assert_eq(_reported_failures[0], "schema_version|int")


func test_non_array_catalogs_normalize_without_changing_bool_by_themselves() -> void:
	_registered_element_ids = []
	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate({
		"schema_version": 1,
		"neutral_element_id": "element_neutral",
		"unmatched_result": "",
		"elements": "not_an_array",
		"combinations": "not_an_array",
	})

	assert_true(result.is_valid)
	assert_eq(result.element_count, 0)
	assert_eq(result.combination_count, 0)
	assert_eq(_reported_failures, [
		"elements|Array",
		"combinations|Array",
	])
	assert_eq(_events, [
		"element_id:neutral_element_id|element_neutral",
		"failure:elements|Array",
		"registered_element_ids",
		"failure:combinations|Array",
	])


func test_non_dictionary_items_invalidate_and_keep_source_counts() -> void:
	var root: Dictionary = _canonical_root()
	var elements: Array = root["elements"] as Array
	elements.insert(0, "not_a_dictionary")
	var combinations: Array = root["combinations"] as Array
	combinations.insert(0, "not_a_dictionary")

	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_false(result.is_valid)
	assert_eq(result.element_count, 5)
	assert_eq(result.combination_count, 2)
	assert_eq(_reported_failures, [
		"elements[0]|Dictionary",
		"combinations[0]|Dictionary",
	])
	assert_true(_element_id_calls.has(
		"elements[1].id|element_neutral"
	))
	assert_true(_element_id_calls.has(
		"combinations[1].result|element_composite_ab"
	))


func test_invalid_element_ids_only_diagnose_and_stay_out_of_seen() -> void:
	var root: Dictionary = _canonical_root()
	var elements: Array = root["elements"] as Array
	elements.append(_element(
		"future_element",
		"extra_element_name",
		"neutral",
		[]
	))
	elements.append(_element(
		"future_element",
		"extra_element_name",
		"neutral",
		[]
	))

	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_true(result.is_valid)
	assert_eq(result.element_count, 6)
	assert_eq(_reported_failures, [
		"elements[4].id|registered id in elements",
		"elements[5].id|registered id in elements",
	])
	assert_false(_reported_failures.has(
		"elements[5].id|unique element id"
	))


func test_registered_duplicate_element_id_invalidates_second_definition() -> void:
	var root: Dictionary = _canonical_root()
	var elements: Array = root["elements"] as Array
	elements.append(_element(
		"element_primary_a",
		"extra_element_name",
		"primary",
		["element_primary_a"]
	))

	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"elements[4].id|unique element id",
	])


func test_component_shape_and_unknown_ids_preserve_legacy_bool_gap() -> void:
	var non_array_root: Dictionary = _canonical_root()
	var non_array_elements: Array = non_array_root["elements"] as Array
	var non_array_element: Dictionary = non_array_elements[1] as Dictionary
	non_array_element["components"] = "not_an_array"
	var non_array_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(non_array_root)
	)
	assert_true(non_array_result.is_valid)
	assert_eq(_reported_failures, [
		"elements[1].components|Array",
	])

	_clear_diagnostics()
	var unknown_root: Dictionary = _canonical_root()
	var unknown_elements: Array = unknown_root["elements"] as Array
	var unknown_element: Dictionary = unknown_elements[1] as Dictionary
	unknown_element["components"] = ["future_element", "future_element"]
	var unknown_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(unknown_root)
	)
	assert_true(unknown_result.is_valid)
	assert_eq(_reported_failures, [
		"elements[1].components[0]|registered id in elements",
		"elements[1].components[1]|registered id in elements",
	])
	assert_false(_reported_failures.has(
		"elements[1].components[1]|unique id"
	))


func test_registered_duplicate_component_invalidates_current_element() -> void:
	var root: Dictionary = _canonical_root()
	var elements: Array = root["elements"] as Array
	var element: Dictionary = elements[1] as Dictionary
	element["components"] = ["element_primary_a", "element_primary_a"]

	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"elements[1].components[1]|unique id",
	])


func test_locale_failure_continues_through_kind_and_components_in_order() -> void:
	var locale_only_root: Dictionary = _canonical_root()
	var locale_only_elements: Array = locale_only_root["elements"] as Array
	var locale_only_element: Dictionary = locale_only_elements[1] as Dictionary
	locale_only_element["name_key"] = "missing_element_name"

	var locale_only_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(locale_only_root)
	)

	assert_false(locale_only_result.is_valid)
	assert_eq(_reported_failures, [
		"elements[1].name_key|known locale key",
	])

	_clear_diagnostics()
	var root: Dictionary = _canonical_root()
	var elements: Array = root["elements"] as Array
	var element: Dictionary = elements[1] as Dictionary
	element["name_key"] = "missing_element_name"
	element["kind"] = "hybrid"
	element["components"] = ["future_element"]

	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"elements[1].name_key|known locale key",
		(
			"elements[1].kind"
			+ "|neutral, primary, or composite"
		),
		"elements[1].components[0]|registered id in elements",
	])
	var locale_callback: int = _events.find(
		"locale:elements[1].name_key|missing_element_name"
	)
	assert_true(locale_callback >= 0)
	assert_eq(
		_events[locale_callback + 1],
		"failure:elements[1].name_key|known locale key"
	)
	assert_eq(
		_events[locale_callback + 2],
		(
			"failure:elements[1].kind"
			+ "|neutral, primary, or composite"
		)
	)
	assert_eq(
		_events[locale_callback + 3],
		"element_id:elements[1].components[0]|future_element"
	)
	assert_eq(
		_events[locale_callback + 4],
		(
			"failure:elements[1].components[0]"
			+ "|registered id in elements"
		)
	)


func test_registered_definition_check_runs_after_element_traversal() -> void:
	var root: Dictionary = _canonical_root()
	var elements: Array = root["elements"] as Array
	elements.remove_at(3)

	var result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"elements|definition for element_composite_ab",
	])
	var final_element_callback: int = _events.find(
		"element_id:elements[2].components[0]|element_primary_b"
	)
	var contract_callback: int = _events.find("registered_element_ids")
	var definition_failure: int = _events.find(
		"failure:elements|definition for element_composite_ab"
	)
	var first_combination_callback: int = _events.find(
		"element_id:combinations[0].left|element_primary_a"
	)
	assert_true(final_element_callback < contract_callback)
	assert_true(contract_callback < definition_failure)
	assert_true(definition_failure < first_combination_callback)


func test_combination_callbacks_keep_side_gap_and_result_and_pair_rules() -> void:
	var invalid_side_root: Dictionary = _canonical_root()
	var invalid_side_combinations: Array = (
		invalid_side_root["combinations"] as Array
	)
	var invalid_side: Dictionary = invalid_side_combinations[0] as Dictionary
	invalid_side["left"] = "future_element"
	var invalid_side_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(invalid_side_root)
	)
	assert_true(invalid_side_result.is_valid)
	assert_eq(_reported_failures, [
		"combinations[0].left|registered id in elements",
	])

	_clear_diagnostics()
	var invalid_result_root: Dictionary = _canonical_root()
	var invalid_result_combinations: Array = (
		invalid_result_root["combinations"] as Array
	)
	var invalid_result: Dictionary = invalid_result_combinations[0] as Dictionary
	invalid_result["result"] = "future_element"
	var invalid_result_validation: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(invalid_result_root)
	)
	assert_false(invalid_result_validation.is_valid)
	assert_eq(_reported_failures, [
		"combinations[0].result|registered id in elements",
	])

	_clear_diagnostics()
	var duplicate_root: Dictionary = _canonical_root()
	var duplicate_combinations: Array = duplicate_root["combinations"] as Array
	duplicate_combinations.append({
		"left": "element_primary_b",
		"right": "element_primary_a",
		"result": "element_composite_ab",
	})
	var duplicate_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(duplicate_root)
	)
	assert_false(duplicate_result.is_valid)
	assert_eq(duplicate_result.combination_count, 2)
	assert_eq(_reported_failures, [
		"combinations[1]|unique unordered element pair",
	])


func test_calls_do_not_share_element_or_pair_duplicate_state() -> void:
	var root: Dictionary = _canonical_root()
	var first_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)
	assert_true(first_result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var second_result: ELEMENT_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)
	assert_true(second_result.is_valid)
	assert_eq(second_result.element_count, 4)
	assert_eq(second_result.combination_count, 1)
	assert_eq(_reported_failures, [])


func _validate(
	raw_data: Variant
) -> ELEMENT_CATALOG_VALIDATOR.ValidationResult:
	return ELEMENT_CATALOG_VALIDATOR.validate(
		raw_data,
		Callable(self, "_require_locale_key"),
		Callable(self, "_require_element_id"),
		Callable(self, "_list_registered_element_ids"),
		Callable(self, "_record_failure")
	)


func _require_locale_key(field: String, value: Variant) -> bool:
	var key: String = String(value)
	var call: String = "%s|%s" % [field, key]
	_locale_calls.append(call)
	_events.append("locale:%s" % call)
	if _locale_keys.has(key):
		return true
	_record_failure(field, "known locale key")
	return false


func _require_element_id(field: String, value: Variant) -> String:
	var element_id: String = (
		String(value) if value is String else "<non-string>"
	)
	var call: String = "%s|%s" % [field, element_id]
	_element_id_calls.append(call)
	_events.append("element_id:%s" % call)
	if not value is String or String(value).is_empty():
		_record_failure(field, "non-empty string")
		return ""
	if not _element_ids.has(element_id):
		_record_failure(field, "registered id in elements")
		return ""
	return element_id


func _list_registered_element_ids() -> Array:
	_events.append("registered_element_ids")
	return _registered_element_ids.duplicate()


func _record_failure(field: String, expected: String) -> void:
	var failure: String = "%s|%s" % [field, expected]
	_reported_failures.append(failure)
	_events.append("failure:%s" % failure)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_locale_calls.clear()
	_element_id_calls.clear()
	_events.clear()


func _canonical_root() -> Dictionary:
	return {
		"schema_version": 1.0,
		"neutral_element_id": "element_neutral",
		"unmatched_result": "",
		"elements": [
			_element(
				"element_neutral",
				"element_neutral_name",
				"neutral",
				[]
			),
			_element(
				"element_primary_a",
				"element_primary_a_name",
				"primary",
				["element_primary_a"]
			),
			_element(
				"element_primary_b",
				"element_primary_b_name",
				"primary",
				["element_primary_b"]
			),
			_element(
				"element_composite_ab",
				"element_composite_ab_name",
				"composite",
				["element_primary_a", "element_primary_b"]
			),
		],
		"combinations": [
			{
				"left": "element_primary_a",
				"right": "element_primary_b",
				"result": "element_composite_ab",
			},
		],
	}


func _element(
	element_id: String,
	name_key: String,
	kind: String,
	components: Variant
) -> Dictionary:
	return {
		"id": element_id,
		"name_key": name_key,
		"kind": kind,
		"components": components,
	}
