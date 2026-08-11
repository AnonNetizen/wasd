extends SmokeHarness


const HAZARD_CATALOG_VALIDATOR := preload(
	"res://scripts/data/hazard_catalog_validator.gd"
)

var _reported_failures: Array[String] = []
var _locale_calls: Array[String] = []
var _contract_calls: Array[String] = []
var _events: Array[String] = []
var _locale_keys: Dictionary = {}
var _contract_values: Dictionary = {}


func before_each() -> void:
	super()
	_clear_diagnostics()
	_locale_keys = {
		"hazard_a_name": true,
		"hazard_b_name": true,
		"hazard_name": true,
	}
	_contract_values = {
		"content_tags:tag_hazard": true,
		"content_tags:tag_extra": true,
		"pool_ids:hazard_spike": true,
		"elements:element_neutral": true,
	}


func test_canonical_rows_return_source_count_and_ignore_extra_columns() -> void:
	var first_row: Dictionary = _valid_row("hazard_a", "hazard_a_name")
	first_row["presentation_profile_id"] = ""
	first_row["future_column"] = "ignored"
	var second_row: Dictionary = _valid_row("hazard_b", "hazard_b_name")
	second_row["damage"] = "0"
	second_row["trigger_interval"] = "0.0001"
	second_row["radius_tiles"] = "1"
	second_row["duration"] = "0"
	var rows: Array[Dictionary] = [
		first_row,
		second_row,
	]
	var result: HAZARD_CATALOG_VALIDATOR.ValidationResult = _validate(rows)

	assert_true(result.is_valid)
	assert_eq(result.row_count, 2)
	assert_eq(_reported_failures, [])
	assert_eq(_locale_calls, [
		"line 2.name_key|hazard_a_name",
		"line 3.name_key|hazard_b_name",
	])
	assert_eq(_contract_calls, [
		"content_tags|tag_hazard",
		"pool_ids|hazard_spike",
		"elements|element_neutral",
		"content_tags|tag_hazard",
		"pool_ids|hazard_spike",
		"elements|element_neutral",
	])


func test_empty_table_reports_legacy_failure_and_zero_count() -> void:
	var rows: Array[Dictionary] = []
	var result: HAZARD_CATALOG_VALIDATOR.ValidationResult = _validate(rows)

	assert_false(result.is_valid)
	assert_eq(result.row_count, 0)
	assert_eq(_reported_failures, [
		"rows|non-empty CSV",
	])
	assert_eq(_locale_calls, [])
	assert_eq(_contract_calls, [])


func test_id_duplicate_line_numbers_and_untrimmed_id_compatibility() -> void:
	var rows: Array[Dictionary] = [
		_valid_row("hazard_dup"),
		_valid_row("hazard_dup"),
		_valid_row(""),
		_valid_row("   "),
	]
	var result: HAZARD_CATALOG_VALIDATOR.ValidationResult = _validate(rows)

	assert_false(result.is_valid)
	assert_eq(result.row_count, 4)
	assert_eq(_reported_failures, [
		"line 3.id|unique hazard id",
		"line 4.id|non-empty string",
	])


func test_tags_trim_empty_duplicate_and_required_tag_order() -> void:
	var trimmed_row: Dictionary = _valid_row("hazard_trim")
	trimmed_row["tags"] = " tag_hazard | tag_extra || "
	var empty_row: Dictionary = _valid_row("hazard_empty_tags")
	empty_row["tags"] = "||"
	var duplicate_row: Dictionary = _valid_row("hazard_duplicate_tags")
	duplicate_row["tags"] = "tag_hazard| tag_hazard"
	var missing_row: Dictionary = _valid_row("hazard_missing_tag")
	missing_row["tags"] = "tag_extra"
	var rows: Array[Dictionary] = [
		trimmed_row,
		empty_row,
		duplicate_row,
		missing_row,
	]
	var result: HAZARD_CATALOG_VALIDATOR.ValidationResult = _validate(rows)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 3.tags|non-empty Array",
		"line 3.tags|tag_hazard",
		"line 4.tags[1]|unique id",
		"line 5.tags|tag_hazard",
	])
	assert_eq(_contract_calls[0], "content_tags|tag_hazard")
	assert_eq(_contract_calls[1], "content_tags|tag_extra")


func test_unknown_tag_keeps_legacy_bool_gap_and_stays_out_of_seen() -> void:
	var row: Dictionary = _valid_row("hazard_unknown_tag")
	row["tags"] = "tag_hazard|future_tag|future_tag"
	var result: HAZARD_CATALOG_VALIDATOR.ValidationResult = _validate(
		_single_row(row)
	)

	assert_true(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.tags[1]|registered id in content_tags",
		"line 2.tags[2]|registered id in content_tags",
	])
	assert_false(_reported_failures.has("line 2.tags[2]|unique id"))
	assert_eq(_contract_calls, [
		"content_tags|tag_hazard",
		"content_tags|future_tag",
		"content_tags|future_tag",
		"pool_ids|hazard_spike",
		"elements|element_neutral",
	])


func test_pool_and_element_contract_failures_keep_field_order() -> void:
	var row: Dictionary = _valid_row("hazard_contracts")
	row["pool_id"] = "future_pool"
	row["element_id"] = "future_element"
	var result: HAZARD_CATALOG_VALIDATOR.ValidationResult = _validate(
		_single_row(row)
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.pool_id|registered id in pool_ids",
		"line 2.element_id|registered id in elements",
	])


func test_csv_parsers_finite_checks_and_numeric_boundaries() -> void:
	var boundary_row: Dictionary = _valid_row("hazard_boundary")
	boundary_row["damage"] = "0"
	boundary_row["trigger_interval"] = "0.0001"
	boundary_row["radius_tiles"] = "1"
	boundary_row["duration"] = "0"
	var result: HAZARD_CATALOG_VALIDATOR.ValidationResult = _validate(
		_single_row(boundary_row)
	)
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var parse_row: Dictionary = _valid_row("hazard_parse")
	parse_row["damage"] = "0.0"
	parse_row["trigger_interval"] = "not_a_number"
	parse_row["radius_tiles"] = "1.0"
	parse_row["duration"] = "not_a_number"
	result = _validate(_single_row(parse_row))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.damage|int",
		"line 2.trigger_interval|number",
		"line 2.radius_tiles|int",
		"line 2.duration|number",
	])

	_clear_diagnostics()
	var range_row: Dictionary = _valid_row("hazard_range")
	range_row["damage"] = "-1"
	range_row["trigger_interval"] = "0"
	range_row["radius_tiles"] = "0"
	range_row["duration"] = "-0.1"
	result = _validate(_single_row(range_row))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.damage|int >= 0",
		"line 2.trigger_interval|number > 0.0",
		"line 2.radius_tiles|int >= 1",
		"line 2.duration|number >= 0.0",
	])

	_clear_diagnostics()
	var finite_row: Dictionary = _valid_row("hazard_finite")
	finite_row["trigger_interval"] = "1e400"
	finite_row["duration"] = "1e400"
	result = _validate(_single_row(finite_row))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.trigger_interval|finite number",
		"line 2.duration|finite number",
	])


func test_callback_failures_do_not_short_circuit_later_fields() -> void:
	var row: Dictionary = _valid_row("hazard_callbacks", "missing_name")
	row["tags"] = "tag_hazard|future_tag"
	row["pool_id"] = "future_pool"
	row["damage"] = "bad"
	row["trigger_interval"] = "bad"
	row["radius_tiles"] = "bad"
	row["duration"] = "bad"
	var result: HAZARD_CATALOG_VALIDATOR.ValidationResult = _validate(
		_single_row(row)
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.name_key|known locale key",
		"line 2.tags[1]|registered id in content_tags",
		"line 2.pool_id|registered id in pool_ids",
		"line 2.damage|int",
		"line 2.trigger_interval|number",
		"line 2.radius_tiles|int",
		"line 2.duration|number",
	])
	assert_eq(_contract_calls, [
		"content_tags|tag_hazard",
		"content_tags|future_tag",
		"pool_ids|future_pool",
		"elements|element_neutral",
	])
	assert_eq(_events.back(), "failure:line 2.duration|number")


func test_calls_do_not_share_duplicate_state() -> void:
	var rows: Array[Dictionary] = [_valid_row("hazard_stateless")]
	var first_result: HAZARD_CATALOG_VALIDATOR.ValidationResult = (
		_validate(rows)
	)
	assert_true(first_result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var second_result: HAZARD_CATALOG_VALIDATOR.ValidationResult = (
		_validate(rows)
	)
	assert_true(second_result.is_valid)
	assert_eq(second_result.row_count, 1)
	assert_eq(_reported_failures, [])


func _validate(
	rows: Array[Dictionary]
) -> HAZARD_CATALOG_VALIDATOR.ValidationResult:
	return HAZARD_CATALOG_VALIDATOR.validate(
		rows,
		Callable(self, "_require_locale_key"),
		Callable(self, "_has_contract_value"),
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


func _has_contract_value(contract_key: String, value: String) -> bool:
	var call: String = "%s|%s" % [contract_key, value]
	_contract_calls.append(call)
	_events.append("contract:%s" % call)
	return _contract_values.has("%s:%s" % [contract_key, value])


func _record_failure(field: String, expected: String) -> void:
	var failure: String = "%s|%s" % [field, expected]
	_reported_failures.append(failure)
	_events.append("failure:%s" % failure)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_locale_calls.clear()
	_contract_calls.clear()
	_events.clear()


func _single_row(row: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [row]
	return rows


func _valid_row(
	hazard_id: String,
	name_key: String = "hazard_name"
) -> Dictionary:
	return {
		"id": hazard_id,
		"name_key": name_key,
		"tags": "tag_hazard",
		"pool_id": "hazard_spike",
		"presentation_profile_id": "presentation_hazard_default",
		"damage": "100",
		"element_id": "element_neutral",
		"trigger_interval": "1.0",
		"radius_tiles": "2",
		"duration": "0.35",
	}
