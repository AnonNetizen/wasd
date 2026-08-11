extends SmokeHarness


const HERO_PASSIVE_CATALOG_VALIDATOR := preload(
	"res://scripts/data/hero_passive_catalog_validator.gd"
)

var _reported_failures: Array[String] = []
var _passive_id_calls: Array[String] = []
var _locale_calls: Array[String] = []
var _effect_calls: Array[String] = []
var _element_calls: Array[String] = []
var _events: Array[String] = []
var _passive_ids: Dictionary = {}
var _locale_keys: Dictionary = {}
var _effects: Dictionary = {}
var _elements: Dictionary = {}


func before_each() -> void:
	super()
	_clear_diagnostics()
	_passive_ids = {}
	_locale_keys = {
		"passive_name": true,
		"passive_desc": true,
		"passive_a_name": true,
		"passive_a_desc": true,
		"passive_b_name": true,
		"passive_b_desc": true,
	}
	_effects = {
		"element_damage_taken_multiplier": true,
		"effect_secondary": true,
	}
	_elements = {
		"element_primary_a": true,
		"element_primary_b": true,
	}


func test_canonical_root_returns_count_and_ignores_extra_fields() -> void:
	var first: Dictionary = _registered_passive(
		"passive_a",
		"passive_a_name",
		"passive_a_desc"
	)
	first["future_field"] = "ignored"
	var first_params: Dictionary = first["params"] as Dictionary
	first_params["future_param"] = {"nested": "ignored"}
	first_params["multiplier"] = 0
	var second: Dictionary = _registered_passive(
		"passive_b",
		"passive_b_name",
		"passive_b_desc"
	)
	second["effect"] = "effect_secondary"
	var second_params: Dictionary = second["params"] as Dictionary
	second_params["element_id"] = "element_primary_b"
	second_params["multiplier"] = 1.0
	var root: Dictionary = {
		"schema_version": 1.0,
		"passives": [first, second],
		"future_root": true,
	}

	var result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)

	assert_true(result.is_valid)
	assert_eq(result.passive_count, 2)
	assert_eq(_reported_failures, [])
	assert_eq(_events, [
		"passive_id:passives[0].id|passive_a",
		"locale:passives[0].name_key|passive_a_name",
		"locale:passives[0].desc_key|passive_a_desc",
		(
			"effect:passives[0].effect"
			+ "|element_damage_taken_multiplier"
		),
		"element:passives[0].params.element_id|element_primary_a",
		"passive_id:passives[1].id|passive_b",
		"locale:passives[1].name_key|passive_b_name",
		"locale:passives[1].desc_key|passive_b_desc",
		"effect:passives[1].effect|effect_secondary",
		"element:passives[1].params.element_id|element_primary_b",
	])


func test_non_dictionary_root_hard_returns_without_callbacks() -> void:
	var result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = _validate([])

	assert_false(result.is_valid)
	assert_eq(result.passive_count, 0)
	assert_eq(_reported_failures, ["root|Dictionary"])
	assert_eq(_passive_id_calls, [])
	assert_eq(_locale_calls, [])
	assert_eq(_effect_calls, [])
	assert_eq(_element_calls, [])


func test_schema_is_exact_int_like_one_and_empty_passives_are_valid() -> void:
	var valid_result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 1.0,
			"passives": [],
		})
	)
	assert_true(valid_result.is_valid)
	assert_eq(valid_result.passive_count, 0)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var wrong_version: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 2.0,
			"passives": [],
		})
	)
	assert_false(wrong_version.is_valid)
	assert_eq(_reported_failures, [
		"schema_version|int equal to 1",
	])

	_clear_diagnostics()
	var fractional: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 1.5,
			"passives": [],
		})
	)
	assert_false(fractional.is_valid)
	assert_eq(_reported_failures, ["schema_version|int"])


func test_non_array_passives_reports_but_keeps_legacy_bool_gap() -> void:
	var result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 1,
			"passives": "not_an_array",
		})
	)

	assert_true(result.is_valid)
	assert_eq(result.passive_count, 0)
	assert_eq(_reported_failures, ["passives|Array"])
	assert_eq(_passive_id_calls, [])
	assert_eq(_locale_calls, [])


func test_non_dictionary_item_invalidates_and_continues_source_order() -> void:
	var valid_after_shape: Dictionary = _registered_passive(
		"passive_valid_after_shape"
	)
	var result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([
			"not_a_dictionary",
			valid_after_shape,
		]))
	)

	assert_false(result.is_valid)
	assert_eq(result.passive_count, 2)
	assert_eq(_reported_failures, ["passives[0]|Dictionary"])
	assert_eq(_passive_id_calls, [
		"passives[1].id|passive_valid_after_shape",
	])
	assert_eq(_element_calls, [
		"passives[1].params.element_id|element_primary_a",
	])


func test_invalid_ids_report_without_invalidating_or_entering_seen() -> void:
	var result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([
			_valid_passive("passive_future"),
			_valid_passive("passive_future"),
			_valid_passive(""),
		]))
	)

	assert_true(result.is_valid)
	assert_eq(result.passive_count, 3)
	assert_eq(_reported_failures, [
		"passives[0].id|registered id in hero_passive_ids",
		"passives[1].id|registered id in hero_passive_ids",
		"passives[2].id|non-empty string",
	])
	assert_false(_reported_failures.has(
		"passives[1].id|unique passive id"
	))


func test_registered_duplicate_id_invalidates_second_item() -> void:
	var first: Dictionary = _registered_passive("passive_duplicate")
	var second: Dictionary = _registered_passive("passive_duplicate")
	var result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([first, second]))
	)

	assert_false(result.is_valid)
	assert_eq(result.passive_count, 2)
	assert_eq(_reported_failures, [
		"passives[1].id|unique passive id",
	])


func test_full_failure_mapping_preserves_field_and_callback_order() -> void:
	var callback_failures: Dictionary = _valid_passive(
		"passive_future_mapping"
	)
	callback_failures["name_key"] = "missing_name"
	callback_failures["desc_key"] = "missing_desc"
	callback_failures["effect"] = "future_effect"
	callback_failures["params"] = "not_a_dictionary"
	var nested_failures: Dictionary = _registered_passive(
		"passive_valid_mapping"
	)
	var nested_params: Dictionary = nested_failures["params"] as Dictionary
	nested_params["element_id"] = "future_element"
	nested_params["multiplier"] = "0.5"

	var result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 2,
			"passives": [
				"not_a_dictionary",
				callback_failures,
				nested_failures,
			],
		})
	)

	assert_false(result.is_valid)
	assert_eq(result.passive_count, 3)
	assert_eq(_reported_failures, [
		"schema_version|int equal to 1",
		"passives[0]|Dictionary",
		"passives[1].id|registered id in hero_passive_ids",
		"passives[1].name_key|known locale key",
		"passives[1].desc_key|known locale key",
		"passives[1].effect|registered id in effects",
		"passives[1].params|Dictionary",
		"passives[2].params.element_id|registered id in elements",
		"passives[2].params.multiplier|number",
	])
	assert_eq(_events, [
		"failure:schema_version|int equal to 1",
		"failure:passives[0]|Dictionary",
		"passive_id:passives[1].id|passive_future_mapping",
		(
			"failure:passives[1].id"
			+ "|registered id in hero_passive_ids"
		),
		"locale:passives[1].name_key|missing_name",
		"failure:passives[1].name_key|known locale key",
		"locale:passives[1].desc_key|missing_desc",
		"failure:passives[1].desc_key|known locale key",
		"effect:passives[1].effect|future_effect",
		"failure:passives[1].effect|registered id in effects",
		"failure:passives[1].params|Dictionary",
		"passive_id:passives[2].id|passive_valid_mapping",
		"locale:passives[2].name_key|passive_name",
		"locale:passives[2].desc_key|passive_desc",
		(
			"effect:passives[2].effect"
			+ "|element_damage_taken_multiplier"
		),
		"element:passives[2].params.element_id|future_element",
		(
			"failure:passives[2].params.element_id"
			+ "|registered id in elements"
		),
		"failure:passives[2].params.multiplier|number",
	])
	assert_eq(_element_calls, [
		"passives[2].params.element_id|future_element",
	])


func test_multiplier_accepts_inclusive_bounds_and_reports_number_matrix() -> void:
	var zero: Dictionary = _registered_passive("passive_multiplier_zero")
	var zero_params: Dictionary = zero["params"] as Dictionary
	zero_params["multiplier"] = 0
	var one: Dictionary = _registered_passive("passive_multiplier_one")
	var one_params: Dictionary = one["params"] as Dictionary
	one_params["multiplier"] = 1.0
	var negative: Dictionary = _registered_passive(
		"passive_multiplier_negative"
	)
	var negative_params: Dictionary = negative["params"] as Dictionary
	negative_params["multiplier"] = -0.01
	var above: Dictionary = _registered_passive("passive_multiplier_above")
	var above_params: Dictionary = above["params"] as Dictionary
	above_params["multiplier"] = 1.01
	var non_finite: Dictionary = _registered_passive(
		"passive_multiplier_non_finite"
	)
	var non_finite_params: Dictionary = non_finite["params"] as Dictionary
	non_finite_params["multiplier"] = INF
	var wrong_type: Dictionary = _registered_passive(
		"passive_multiplier_wrong_type"
	)
	var wrong_type_params: Dictionary = wrong_type["params"] as Dictionary
	wrong_type_params["multiplier"] = "0.5"

	var result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([
			zero,
			one,
			negative,
			above,
			non_finite,
			wrong_type,
		]))
	)

	assert_false(result.is_valid)
	assert_eq(result.passive_count, 6)
	assert_eq(_reported_failures, [
		"passives[2].params.multiplier|number >= 0.0",
		"passives[3].params.multiplier|number <= 1.0",
		"passives[4].params.multiplier|finite number",
		"passives[5].params.multiplier|number",
	])


func test_calls_do_not_share_duplicate_state() -> void:
	var root: Dictionary = _valid_root([
		_registered_passive("passive_stateless"),
	])
	var first_result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)
	assert_true(first_result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var second_result: HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)
	assert_true(second_result.is_valid)
	assert_eq(second_result.passive_count, 1)
	assert_eq(_reported_failures, [])


func _validate(
	raw_data: Variant
) -> HERO_PASSIVE_CATALOG_VALIDATOR.ValidationResult:
	return HERO_PASSIVE_CATALOG_VALIDATOR.validate(
		raw_data,
		Callable(self, "_require_locale_key"),
		Callable(self, "_require_passive_id"),
		Callable(self, "_require_effect"),
		Callable(self, "_require_element"),
		Callable(self, "_record_failure")
	)


func _require_passive_id(field: String, value: Variant) -> String:
	var passive_id: String = (
		String(value) if value is String else "<non-string>"
	)
	var call: String = "%s|%s" % [field, passive_id]
	_passive_id_calls.append(call)
	_events.append("passive_id:%s" % call)
	if not value is String or String(value).is_empty():
		_record_failure(field, "non-empty string")
		return ""
	if not _passive_ids.has(passive_id):
		_record_failure(field, "registered id in hero_passive_ids")
		return ""
	return passive_id


func _require_locale_key(field: String, value: Variant) -> bool:
	var key: String = String(value)
	var call: String = "%s|%s" % [field, key]
	_locale_calls.append(call)
	_events.append("locale:%s" % call)
	if _locale_keys.has(key):
		return true
	_record_failure(field, "known locale key")
	return false


func _require_effect(field: String, value: Variant) -> String:
	var effect: String = (
		String(value) if value is String else "<non-string>"
	)
	var call: String = "%s|%s" % [field, effect]
	_effect_calls.append(call)
	_events.append("effect:%s" % call)
	if not value is String or String(value).is_empty():
		_record_failure(field, "non-empty string")
		return ""
	if not _effects.has(effect):
		_record_failure(field, "registered id in effects")
		return ""
	return effect


func _require_element(field: String, value: Variant) -> String:
	var element: String = (
		String(value) if value is String else "<non-string>"
	)
	var call: String = "%s|%s" % [field, element]
	_element_calls.append(call)
	_events.append("element:%s" % call)
	if not value is String or String(value).is_empty():
		_record_failure(field, "non-empty string")
		return ""
	if not _elements.has(element):
		_record_failure(field, "registered id in elements")
		return ""
	return element


func _record_failure(field: String, expected: String) -> void:
	var failure: String = "%s|%s" % [field, expected]
	_reported_failures.append(failure)
	_events.append("failure:%s" % failure)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_passive_id_calls.clear()
	_locale_calls.clear()
	_effect_calls.clear()
	_element_calls.clear()
	_events.clear()


func _valid_root(passives: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"passives": passives,
	}


func _registered_passive(
	passive_id: String,
	name_key: String = "passive_name",
	desc_key: String = "passive_desc"
) -> Dictionary:
	_passive_ids[passive_id] = true
	return _valid_passive(passive_id, name_key, desc_key)


func _valid_passive(
	passive_id: String,
	name_key: String = "passive_name",
	desc_key: String = "passive_desc"
) -> Dictionary:
	return {
		"id": passive_id,
		"name_key": name_key,
		"desc_key": desc_key,
		"effect": "element_damage_taken_multiplier",
		"params": {
			"element_id": "element_primary_a",
			"multiplier": 0.6,
		},
	}
