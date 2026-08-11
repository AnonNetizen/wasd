extends SmokeHarness


const CONSUMABLE_CATALOG_VALIDATOR := preload(
	"res://scripts/data/consumable_catalog_validator.gd"
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
		"consumable_a_name": true,
		"consumable_a_desc": true,
		"consumable_b_name": true,
		"consumable_b_desc": true,
		"consumable_name": true,
		"consumable_desc": true,
	}
	_content_tags = {
		"tag_consumable": true,
		"tag_extra": true,
	}
	_effects = {
		"effect_consume": true,
		"effect_secondary": true,
	}


func test_canonical_root_returns_count_and_ignores_extra_fields() -> void:
	var first_item: Dictionary = _valid_consumable(
		"consumable_a",
		"consumable_a_name",
		"consumable_a_desc"
	)
	first_item["presentation_profile_id"] = "presentation_consumable"
	first_item["future_field"] = "ignored"
	var first_stack: Dictionary = first_item["stack"] as Dictionary
	first_stack["future_stack_field"] = true
	var first_effects: Array = first_item["use_effects"] as Array
	var first_effect: Dictionary = first_effects[0] as Dictionary
	first_effect["params"] = {
		"future_param": {"nested": "ignored"},
	}
	var second_item: Dictionary = _valid_consumable(
		" consumable_b ",
		"consumable_b_name",
		"consumable_b_desc"
	)
	second_item["default_unlocked"] = false
	second_item["tags"] = ["tag_consumable", "tag_extra"]
	second_item["stack"] = {
		"max_stack": 1.0,
		"start_count": 0.0,
		"pickup_count": 1.0,
	}
	second_item["use_effects"] = [
		{"effect": "effect_secondary", "params": {}},
	]
	var root: Dictionary = {
		"schema_version": 1.0,
		"consumables": [first_item, second_item],
		"future_root": "ignored",
	}
	var result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)

	assert_true(result.is_valid)
	assert_true(result.has_consumable_count)
	assert_eq(result.consumable_count, 2)
	assert_eq(_reported_failures, [])
	assert_eq(_events, [
		"locale:consumables[0].name_key|consumable_a_name",
		"locale:consumables[0].desc_key|consumable_a_desc",
		"tag:consumables[0].tags[0]|tag_consumable",
		"effect:consumables[0].use_effects[0].effect|effect_consume",
		"locale:consumables[1].name_key|consumable_b_name",
		"locale:consumables[1].desc_key|consumable_b_desc",
		"tag:consumables[1].tags[0]|tag_consumable",
		"tag:consumables[1].tags[1]|tag_extra",
		"effect:consumables[1].use_effects[0].effect|effect_secondary",
	])


func test_non_dictionary_root_hard_returns_without_count_or_callbacks() -> void:
	var result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = _validate([])

	assert_false(result.is_valid)
	assert_false(result.has_consumable_count)
	assert_eq(result.consumable_count, 0)
	assert_eq(_reported_failures, ["root|Dictionary"])
	assert_eq(_locale_calls, [])
	assert_eq(_tag_calls, [])
	assert_eq(_effect_calls, [])


func test_schema_int_like_and_normalized_consumable_count() -> void:
	var valid_result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 1.0,
			"consumables": [_valid_consumable("consumable_int_like")],
		})
	)
	assert_true(valid_result.is_valid)
	assert_true(valid_result.has_consumable_count)
	assert_eq(valid_result.consumable_count, 1)

	_clear_diagnostics()
	var invalid_result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate({
			"schema_version": 0.0,
			"consumables": "not_an_array",
		})
	)
	assert_false(invalid_result.is_valid)
	assert_true(invalid_result.has_consumable_count)
	assert_eq(invalid_result.consumable_count, 0)
	assert_eq(_reported_failures, [
		"schema_version|int >= 1",
		"consumables|Array",
		"consumables|non-empty Array",
	])


func test_item_shape_count_duplicate_and_untrimmed_id_order() -> void:
	var root: Dictionary = _valid_root([
		"not_a_dictionary",
		_valid_consumable("consumable_duplicate"),
		_valid_consumable("consumable_duplicate"),
		_valid_consumable(""),
		_valid_consumable("   "),
	])
	var result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)

	assert_false(result.is_valid)
	assert_true(result.has_consumable_count)
	assert_eq(result.consumable_count, 5)
	assert_eq(_reported_failures, [
		"consumables[0]|Dictionary",
		"consumables[2].id|unique consumable id",
		"consumables[3].id|non-empty string",
	])


func test_item_field_order_and_stack_local_return_still_runs_effects() -> void:
	var duplicate: Dictionary = _valid_consumable(
		"consumable_order",
		"missing_name",
		"missing_desc"
	)
	duplicate["default_unlocked"] = "true"
	duplicate["tags"] = "tag_consumable"
	duplicate["stack"] = "not_a_dictionary"
	duplicate["use_effects"] = "not_an_array"
	var result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([
			_valid_consumable("consumable_order"),
			duplicate,
		]))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"consumables[1].id|unique consumable id",
		"consumables[1].name_key|known locale key",
		"consumables[1].desc_key|known locale key",
		"consumables[1].default_unlocked|bool",
		"consumables[1].tags|Array",
		"consumables[1].tags|non-empty Array",
		"consumables[1].tags|tag_consumable",
		"consumables[1].stack|Dictionary",
		"consumables[1].use_effects|Array",
		"consumables[1].use_effects|non-empty Array",
	])


func test_unknown_tag_keeps_legacy_bool_gap_and_stays_out_of_seen() -> void:
	var item: Dictionary = _valid_consumable("consumable_unknown_tag")
	item["tags"] = ["tag_consumable", "future_tag", "future_tag"]
	var result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([item]))
	)

	assert_true(result.is_valid)
	assert_eq(_reported_failures, [
		"consumables[0].tags[1]|registered id in content_tags",
		"consumables[0].tags[2]|registered id in content_tags",
	])
	assert_false(_reported_failures.has(
		"consumables[0].tags[2]|unique id"
	))
	assert_eq(_effect_calls, [
		"consumables[0].use_effects[0].effect|effect_consume",
	])


func test_tags_shape_duplicate_and_required_tag_diagnostics() -> void:
	var wrong_shape: Dictionary = _valid_consumable(
		"consumable_wrong_tags"
	)
	wrong_shape["tags"] = "tag_consumable"
	var duplicate: Dictionary = _valid_consumable(
		"consumable_duplicate_tags"
	)
	duplicate["tags"] = ["tag_consumable", "tag_consumable"]
	var missing_required: Dictionary = _valid_consumable(
		"consumable_missing_tag"
	)
	missing_required["tags"] = ["tag_extra"]
	var result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([
			wrong_shape,
			duplicate,
			missing_required,
		]))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"consumables[0].tags|Array",
		"consumables[0].tags|non-empty Array",
		"consumables[0].tags|tag_consumable",
		"consumables[1].tags[1]|unique id",
		"consumables[2].tags|tag_consumable",
	])


func test_stack_int_like_boundaries_and_relations_after_lower_bounds() -> void:
	var boundary: Dictionary = _valid_consumable("consumable_stack_boundary")
	boundary["stack"] = {
		"max_stack": 1.0,
		"start_count": 0.0,
		"pickup_count": 1.0,
	}
	var result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([boundary]))
	)
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var invalid: Dictionary = _valid_consumable("consumable_stack_invalid")
	invalid["stack"] = {
		"max_stack": -2,
		"start_count": -1,
		"pickup_count": -1,
	}
	result = _validate(_valid_root([invalid]))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"consumables[0].stack.max_stack|int >= 1",
		"consumables[0].stack.start_count|int >= 0",
		"consumables[0].stack.pickup_count|int >= 1",
		"consumables[0].stack.start_count|<= max_stack",
		"consumables[0].stack.pickup_count|<= max_stack",
	])


func test_use_effect_shape_entries_contract_and_params_order() -> void:
	var wrong_shape: Dictionary = _valid_consumable(
		"consumable_effect_shape"
	)
	wrong_shape["use_effects"] = "not_an_array"
	var entries: Dictionary = _valid_consumable(
		"consumable_effect_entries"
	)
	entries["use_effects"] = [
		"not_a_dictionary",
		{"effect": "future_effect", "params": []},
		{
			"effect": "effect_consume",
			"params": {"future_param": "ignored"},
			"future_entry_field": true,
		},
	]
	var result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_valid_root([wrong_shape, entries]))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"consumables[0].use_effects|Array",
		"consumables[0].use_effects|non-empty Array",
		"consumables[1].use_effects[0]|Dictionary",
		(
			"consumables[1].use_effects[1].effect"
			+ "|registered id in effects"
		),
		"consumables[1].use_effects[1].params|Dictionary",
	])
	assert_eq(_effect_calls, [
		"consumables[1].use_effects[1].effect|future_effect",
		"consumables[1].use_effects[2].effect|effect_consume",
	])


func test_calls_do_not_share_duplicate_state() -> void:
	var root: Dictionary = _valid_root([
		_valid_consumable("consumable_stateless"),
	])
	var first_result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)
	assert_true(first_result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var second_result: CONSUMABLE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(root)
	)
	assert_true(second_result.is_valid)
	assert_true(second_result.has_consumable_count)
	assert_eq(second_result.consumable_count, 1)
	assert_eq(_reported_failures, [])


func _validate(
	raw_data: Variant
) -> CONSUMABLE_CATALOG_VALIDATOR.ValidationResult:
	return CONSUMABLE_CATALOG_VALIDATOR.validate(
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


func _valid_root(consumables: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"consumables": consumables,
	}


func _valid_consumable(
	consumable_id: String,
	name_key: String = "consumable_name",
	desc_key: String = "consumable_desc"
) -> Dictionary:
	return {
		"id": consumable_id,
		"name_key": name_key,
		"desc_key": desc_key,
		"default_unlocked": true,
		"tags": ["tag_consumable"],
		"stack": {
			"max_stack": 3,
			"start_count": 0,
			"pickup_count": 1,
		},
		"use_effects": [
			{"effect": "effect_consume", "params": {}},
		],
	}
