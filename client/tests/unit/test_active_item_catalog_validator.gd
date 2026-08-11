extends SmokeHarness


const ACTIVE_ITEM_CATALOG_VALIDATOR := preload(
	"res://scripts/data/active_item_catalog_validator.gd"
)

var _reported_failures: Array[String] = []
var _locale_calls: Array[String] = []
var _tag_calls: Array[String] = []
var _effect_calls: Array[String] = []
var _events: Array[String] = []
var _locale_keys: Dictionary = {}
var _content_tags: Dictionary = {}
var _effects: Dictionary = {}


func before_each() -> void:
	super()
	_clear_diagnostics()
	_locale_keys = {
		"active_a_name": true,
		"active_a_desc": true,
		"active_b_name": true,
		"active_b_desc": true,
		"active_name": true,
		"active_desc": true,
	}
	_content_tags = {
		"tag_active_item": true,
		"tag_extra": true,
	}
	_effects = {
		"effect_active": true,
		"effect_secondary": true,
	}


func test_canonical_root_returns_count_and_ignores_extra_fields() -> void:
	var first_item: Dictionary = _valid_item(
		"active_a",
		"active_a_name",
		"active_a_desc"
	)
	first_item["presentation_profile_id"] = "presentation_active_default"
	first_item["future_field"] = "ignored"
	var first_charge: Dictionary = first_item["charge"] as Dictionary
	first_charge["future_charge_field"] = true
	var first_effects: Array = first_item["use_effects"] as Array
	var first_effect: Dictionary = first_effects[0] as Dictionary
	first_effect["params"] = {
		"future_param": {"nested": "ignored"},
	}
	var second_item: Dictionary = _valid_item(
		" active_b ",
		"active_b_name",
		"active_b_desc"
	)
	second_item["default_unlocked"] = false
	second_item["tags"] = ["tag_active_item", "tag_extra"]
	second_item["charge"] = {
		"mode": "cooldown",
		"cooldown": 0.0001,
		"max_charges": 1.0,
		"start_charges": 0.0,
	}
	second_item["use_effects"] = [
		{"effect": "effect_secondary", "params": {}},
	]
	var root: Dictionary = {
		"schema_version": 1.0,
		"active_items": [first_item, second_item],
		"future_root": "ignored",
	}
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)

	assert_true(result.is_valid)
	assert_eq(result.item_count, 2)
	assert_eq(_reported_failures, [])
	assert_eq(_events, [
		"locale:active_items[0].name_key|active_a_name",
		"locale:active_items[0].desc_key|active_a_desc",
		"tag:active_items[0].tags[0]|tag_active_item",
		"effect:active_items[0].use_effects[0].effect|effect_active",
		"locale:active_items[1].name_key|active_b_name",
		"locale:active_items[1].desc_key|active_b_desc",
		"tag:active_items[1].tags[0]|tag_active_item",
		"tag:active_items[1].tags[1]|tag_extra",
		"effect:active_items[1].use_effects[0].effect|effect_secondary",
	])


func test_non_dictionary_root_hard_returns_with_default_count() -> void:
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = _validate([])

	assert_false(result.is_valid)
	assert_eq(result.item_count, 0)
	assert_eq(_reported_failures, ["root|Dictionary"])
	assert_eq(_locale_calls, [])
	assert_eq(_tag_calls, [])
	assert_eq(_effect_calls, [])


func test_schema_int_like_and_normalized_active_items_count() -> void:
	var valid_result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 1.0,
			"active_items": [_valid_item("active_int_like")],
		})
	)
	assert_true(valid_result.is_valid)
	assert_eq(valid_result.item_count, 1)

	_clear_diagnostics()
	var invalid_result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 0.0,
			"active_items": "not_an_array",
		})
	)
	assert_false(invalid_result.is_valid)
	assert_eq(invalid_result.item_count, 0)
	assert_eq(_reported_failures, [
		"schema_version|int >= 1",
		"active_items|Array",
		"active_items|non-empty Array",
	])


func test_item_shape_id_duplicate_and_untrimmed_id_order() -> void:
	var root: Dictionary = _valid_root([
		"not_a_dictionary",
		_valid_item("active_duplicate"),
		_valid_item("active_duplicate"),
		_valid_item(""),
		_valid_item("   "),
	])
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)

	assert_false(result.is_valid)
	assert_eq(result.item_count, 5)
	assert_eq(_reported_failures, [
		"active_items[0]|Dictionary",
		"active_items[2].id|unique active item id",
		"active_items[3].id|non-empty string",
	])


func test_unknown_tag_keeps_legacy_bool_gap_and_stays_out_of_seen() -> void:
	var item: Dictionary = _valid_item("active_unknown_tag")
	item["tags"] = ["tag_active_item", "future_tag", "future_tag"]
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([item]))
	)

	assert_true(result.is_valid)
	assert_eq(_reported_failures, [
		"active_items[0].tags[1]|registered id in content_tags",
		"active_items[0].tags[2]|registered id in content_tags",
	])
	assert_false(
		_reported_failures.has("active_items[0].tags[2]|unique id")
	)
	assert_eq(_effect_calls, [
		"active_items[0].use_effects[0].effect|effect_active",
	])


func test_tags_shape_duplicate_and_required_tag_diagnostics() -> void:
	var wrong_shape: Dictionary = _valid_item("active_wrong_tags")
	wrong_shape["tags"] = "tag_active_item"
	var duplicate: Dictionary = _valid_item("active_duplicate_tags")
	duplicate["tags"] = ["tag_active_item", "tag_active_item"]
	var missing_required: Dictionary = _valid_item("active_missing_tag")
	missing_required["tags"] = ["tag_extra"]
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([
			wrong_shape,
			duplicate,
			missing_required,
		]))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"active_items[0].tags|Array",
		"active_items[0].tags|non-empty Array",
		"active_items[0].tags|tag_active_item",
		"active_items[1].tags[1]|unique id",
		"active_items[2].tags|tag_active_item",
	])


func test_charge_shape_only_short_circuits_charge_not_effects() -> void:
	var item: Dictionary = _valid_item("active_charge_shape")
	item["charge"] = "not_a_dictionary"
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([item]))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"active_items[0].charge|Dictionary",
	])
	assert_eq(_effect_calls, [
		"active_items[0].use_effects[0].effect|effect_active",
	])


func test_charge_mode_numeric_finite_boundaries_and_relation_order() -> void:
	var boundary: Dictionary = _valid_item("active_charge_boundary")
	boundary["charge"] = {
		"mode": "cooldown",
		"cooldown": 0.0001,
		"max_charges": 1.0,
		"start_charges": 0.0,
	}
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([boundary]))
	)
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var types: Dictionary = _valid_item("active_charge_types")
	types["charge"] = {
		"mode": "",
		"cooldown": "1.0",
		"max_charges": 1.5,
		"start_charges": -1,
	}
	result = _validate(_valid_root([types]))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"active_items[0].charge.mode|non-empty string",
		"active_items[0].charge.cooldown|number",
		"active_items[0].charge.max_charges|int",
		"active_items[0].charge.start_charges|int >= 0",
	])

	_clear_diagnostics()
	var ranges: Dictionary = _valid_item("active_charge_ranges")
	ranges["charge"] = {
		"mode": "future_mode",
		"cooldown": 0.0,
		"max_charges": -2,
		"start_charges": -1,
	}
	result = _validate(_valid_root([ranges]))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"active_items[0].charge.mode|cooldown",
		"active_items[0].charge.cooldown|number > 0.0",
		"active_items[0].charge.max_charges|int >= 1",
		"active_items[0].charge.start_charges|int >= 0",
		"active_items[0].charge.start_charges|<= max_charges",
	])

	_clear_diagnostics()
	var non_finite: Dictionary = _valid_item("active_charge_non_finite")
	var non_finite_charge: Dictionary = non_finite["charge"] as Dictionary
	non_finite_charge["cooldown"] = INF
	result = _validate(_valid_root([non_finite]))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"active_items[0].charge.cooldown|finite number",
	])


func test_use_effect_shape_entries_contract_and_params_order() -> void:
	var wrong_shape: Dictionary = _valid_item("active_effect_shape")
	wrong_shape["use_effects"] = "not_an_array"
	var entries: Dictionary = _valid_item("active_effect_entries")
	entries["use_effects"] = [
		"not_a_dictionary",
		{"effect": "future_effect", "params": []},
		{
			"effect": "effect_active",
			"params": {"future_param": "ignored"},
			"future_entry_field": true,
		},
	]
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([wrong_shape, entries]))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"active_items[0].use_effects|Array",
		"active_items[0].use_effects|non-empty Array",
		"active_items[1].use_effects[0]|Dictionary",
		(
			"active_items[1].use_effects[1].effect"
			+ "|registered id in effects"
		),
		"active_items[1].use_effects[1].params|Dictionary",
	])
	assert_eq(_effect_calls, [
		"active_items[1].use_effects[1].effect|future_effect",
		"active_items[1].use_effects[2].effect|effect_active",
	])


func test_callback_failures_do_not_short_circuit_later_fields() -> void:
	var item: Dictionary = _valid_item(
		"active_callbacks",
		"missing_name",
		"missing_desc"
	)
	item["default_unlocked"] = "false"
	item["tags"] = ["tag_active_item", "future_tag"]
	item["charge"] = "not_a_dictionary"
	item["use_effects"] = [
		{"effect": "future_effect", "params": []},
	]
	var result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([item]))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"active_items[0].name_key|known locale key",
		"active_items[0].desc_key|known locale key",
		"active_items[0].default_unlocked|bool",
		"active_items[0].tags[1]|registered id in content_tags",
		"active_items[0].charge|Dictionary",
		(
			"active_items[0].use_effects[0].effect"
			+ "|registered id in effects"
		),
		"active_items[0].use_effects[0].params|Dictionary",
	])
	assert_eq(_events.back(), (
		"failure:active_items[0].use_effects[0].params|Dictionary"
	))


func test_calls_do_not_share_duplicate_state() -> void:
	var root: Dictionary = _valid_root([_valid_item("active_stateless")])
	var first_result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)
	assert_true(first_result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var second_result: ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)
	assert_true(second_result.is_valid)
	assert_eq(second_result.item_count, 1)
	assert_eq(_reported_failures, [])


func _validate(
	raw_data: Variant
) -> ACTIVE_ITEM_CATALOG_VALIDATOR.ValidationResult:
	return ACTIVE_ITEM_CATALOG_VALIDATOR.validate(
		raw_data,
		Callable(self, "_require_locale_key"),
		Callable(self, "_require_content_tag"),
		Callable(self, "_require_effect"),
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


func _require_content_tag(field: String, value: Variant) -> String:
	var tag: String = String(value) if value is String else "<non-string>"
	var call: String = "%s|%s" % [field, tag]
	_tag_calls.append(call)
	_events.append("tag:%s" % call)
	if not value is String or String(value).is_empty():
		_record_failure(field, "non-empty string")
		return ""
	if not _content_tags.has(tag):
		_record_failure(field, "registered id in content_tags")
		return ""
	return tag


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


func _record_failure(field: String, expected: String) -> void:
	var failure: String = "%s|%s" % [field, expected]
	_reported_failures.append(failure)
	_events.append("failure:%s" % failure)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_locale_calls.clear()
	_tag_calls.clear()
	_effect_calls.clear()
	_events.clear()


func _valid_root(items: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"active_items": items,
	}


func _valid_item(
	item_id: String,
	name_key: String = "active_name",
	desc_key: String = "active_desc"
) -> Dictionary:
	return {
		"id": item_id,
		"name_key": name_key,
		"desc_key": desc_key,
		"default_unlocked": true,
		"tags": ["tag_active_item"],
		"charge": {
			"mode": "cooldown",
			"cooldown": 5.0,
			"max_charges": 2,
			"start_charges": 1,
		},
		"use_effects": [
			{"effect": "effect_active", "params": {}},
		],
	}
