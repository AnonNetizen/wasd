extends SmokeHarness


const SPAWN_WAVE_CATALOG_VALIDATOR := preload(
	"res://scripts/data/spawn_wave_catalog_validator.gd"
)

var _reported_failures: Array[String] = []
var _mode_calls: Array[String] = []
var _events: Array[String] = []
var _registered_modes: Dictionary = {}
var _enemy_ids: Dictionary = {}
var _hazard_ids: Dictionary = {}
var _game_mode_ids: Dictionary = {}


func before_each() -> void:
	super()
	_clear_diagnostics()
	_registered_modes = {
		"mode_a": true,
		"mode_b": true,
	}
	_enemy_ids = {
		"enemy_a": true,
		"enemy_b": true,
	}
	_hazard_ids = {
		"hazard_a": true,
	}
	_game_mode_ids = {
		"mode_a": true,
		"mode_b": true,
	}


func test_canonical_rows_return_raw_count_and_ignore_extra_columns() -> void:
	var first_row: Dictionary = _valid_row("wave_a", "mode_a", "1")
	first_row["future_column"] = "ignored"
	var second_row: Dictionary = _valid_row("wave_b", "mode_a", "2")
	second_row["enemy_id"] = "enemy_b"
	second_row["hazard_id"] = "hazard_a"
	second_row["hazard_weight"] = "3"
	var rows: Array[Dictionary] = [first_row, second_row]
	var enemy_ids_before: Dictionary = _enemy_ids.duplicate(true)
	var hazard_ids_before: Dictionary = _hazard_ids.duplicate(true)
	var mode_ids_before: Dictionary = _game_mode_ids.duplicate(true)
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(rows)
	)

	assert_true(result.is_valid)
	assert_eq(result.row_count, 2)
	assert_eq(_reported_failures, [])
	assert_eq(_mode_calls, [
		"line 2.mode_id|mode_a",
		"line 3.mode_id|mode_a",
	])
	assert_eq(_enemy_ids, enemy_ids_before)
	assert_eq(_hazard_ids, hazard_ids_before)
	assert_eq(_game_mode_ids, mode_ids_before)


func test_empty_table_reports_legacy_failure_and_zero_count() -> void:
	var rows: Array[Dictionary] = []
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(rows)
	)

	assert_false(result.is_valid)
	assert_eq(result.row_count, 0)
	assert_eq(_reported_failures, ["rows|non-empty CSV"])
	assert_eq(_mode_calls, [])


func test_wave_id_and_mode_index_duplicates_keep_source_order() -> void:
	var first_row: Dictionary = _valid_row("wave_dup", "mode_a", "1")
	var second_row: Dictionary = _valid_row("wave_dup", "mode_a", "2")
	var third_row: Dictionary = _valid_row("wave_other", "mode_a", "2")
	var fourth_row: Dictionary = _valid_row("   ", "mode_b", "2")
	var rows: Array[Dictionary] = [
		first_row,
		second_row,
		third_row,
		fourth_row,
	]
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(rows)
	)

	assert_false(result.is_valid)
	assert_eq(result.row_count, 4)
	assert_eq(_reported_failures, [
		"line 3.id|unique wave id",
		"line 4.wave_index|unique per mode",
	])


func test_unregistered_mode_reports_but_preserves_legacy_bool_gap() -> void:
	var row: Dictionary = _valid_row("wave_future", "mode_future", "1")
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_single_row(row))
	)

	assert_true(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.mode_id|registered id in game_modes",
	])
	assert_eq(_mode_calls, ["line 2.mode_id|mode_future"])


func test_registered_mode_missing_from_loaded_index_invalidates() -> void:
	_registered_modes["mode_missing"] = true
	var row: Dictionary = _valid_row("wave_missing_mode", "mode_missing", "1")
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_single_row(row))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.mode_id|mode defined in game_modes.json",
	])


func test_each_row_keeps_legacy_field_order_and_runs_all_checks() -> void:
	_registered_modes["mode_missing"] = true
	var row: Dictionary = _valid_row("", "mode_missing", "not_int")
	row["start_time"] = "not_number"
	row["end_time"] = "not_number"
	row["enemy_id"] = "enemy_missing"
	row["enemy_weight"] = "not_int"
	row["spawn_interval"] = "not_number"
	row["max_alive"] = "not_int"
	row["spawn_budget"] = "not_int"
	row["hazard_id"] = "hazard_missing"
	row["hazard_weight"] = "not_int"
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_single_row(row))
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.id|non-empty string",
		"line 2.mode_id|mode defined in game_modes.json",
		"line 2.wave_index|int",
		"line 2.start_time|number",
		"line 2.end_time|number",
		"line 2.enemy_id|enemy defined in enemies.csv",
		"line 2.enemy_weight|int",
		"line 2.spawn_interval|number",
		"line 2.max_alive|int",
		"line 2.spawn_budget|int",
		"line 2.hazard_weight|int",
		"line 2.hazard_id|hazard defined in hazards.csv",
	])
	assert_eq(_events.back(), "failure:line 2.hazard_id|hazard defined in hazards.csv")


func test_numeric_boundaries_keep_csv_string_parsing() -> void:
	var boundary_row: Dictionary = _valid_row("wave_boundary")
	boundary_row["wave_index"] = "1"
	boundary_row["start_time"] = "0.0"
	boundary_row["end_time"] = "0.0001"
	boundary_row["enemy_weight"] = "1"
	boundary_row["spawn_interval"] = "0.0001"
	boundary_row["max_alive"] = "1"
	boundary_row["spawn_budget"] = "0"
	boundary_row["hazard_weight"] = "0"
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_single_row(boundary_row))
	)
	assert_true(result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var decimal_int_row: Dictionary = _valid_row("wave_decimal_int")
	decimal_int_row["wave_index"] = "1.0"
	decimal_int_row["enemy_weight"] = "1.0"
	decimal_int_row["max_alive"] = "1.0"
	decimal_int_row["spawn_budget"] = "0.0"
	decimal_int_row["hazard_weight"] = "0.0"
	result = _validate(_single_row(decimal_int_row))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.wave_index|int",
		"line 2.enemy_weight|int",
		"line 2.max_alive|int",
		"line 2.spawn_budget|int",
		"line 2.hazard_weight|int",
	])

	_clear_diagnostics()
	var finite_row: Dictionary = _valid_row("wave_finite")
	finite_row["end_time"] = "1e400"
	finite_row["spawn_interval"] = "1e400"
	result = _validate(_single_row(finite_row))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.end_time|finite number",
		"line 2.spawn_interval|finite number",
	])


func test_numeric_ranges_and_time_relation_collect_in_order() -> void:
	var range_row: Dictionary = _valid_row("wave_range")
	range_row["wave_index"] = "0"
	range_row["start_time"] = "-1.0"
	range_row["end_time"] = "0.0"
	range_row["enemy_weight"] = "0"
	range_row["spawn_interval"] = "0.0"
	range_row["max_alive"] = "0"
	range_row["spawn_budget"] = "-1"
	range_row["hazard_weight"] = "-1"
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(_single_row(range_row))
	)
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.wave_index|int >= 1",
		"line 2.start_time|number >= 0.0",
		"line 2.end_time|number > 0.0",
		"line 2.enemy_weight|int >= 1",
		"line 2.spawn_interval|number > 0.0",
		"line 2.max_alive|int >= 1",
		"line 2.spawn_budget|int >= 0",
		"line 2.hazard_weight|int >= 0",
	])

	_clear_diagnostics()
	var relation_row: Dictionary = _valid_row("wave_relation")
	relation_row["start_time"] = "2.0"
	relation_row["end_time"] = "1.0"
	result = _validate(_single_row(relation_row))
	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.end_time|greater than start_time",
	])


func test_optional_hazard_checks_weight_before_reference_and_pair_rule() -> void:
	var missing_pair_row: Dictionary = _valid_row("wave_missing_pair")
	missing_pair_row["hazard_weight"] = "2"
	var unknown_row: Dictionary = _valid_row("wave_unknown_hazard")
	unknown_row["wave_index"] = "2"
	unknown_row["hazard_id"] = "hazard_missing"
	unknown_row["hazard_weight"] = "bad"
	var valid_row: Dictionary = _valid_row("wave_valid_hazard")
	valid_row["wave_index"] = "3"
	valid_row["hazard_id"] = "hazard_a"
	valid_row["hazard_weight"] = "1"
	var rows: Array[Dictionary] = [missing_pair_row, unknown_row, valid_row]
	var result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(rows)
	)

	assert_false(result.is_valid)
	assert_eq(_reported_failures, [
		"line 2.hazard_id|non-empty when hazard_weight > 0",
		"line 3.hazard_weight|int",
		"line 3.hazard_id|hazard defined in hazards.csv",
	])


func test_mode_wave_duplicate_state_does_not_leak_between_calls() -> void:
	var rows: Array[Dictionary] = [_valid_row("wave_stateless")]
	var first_result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(rows)
	)
	assert_true(first_result.is_valid)
	assert_eq(_reported_failures, [])

	_clear_diagnostics()
	var second_result: SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult = (
		_validate(rows)
	)
	assert_true(second_result.is_valid)
	assert_eq(second_result.row_count, 1)
	assert_eq(_reported_failures, [])


func _validate(
	rows: Array[Dictionary]
) -> SPAWN_WAVE_CATALOG_VALIDATOR.ValidationResult:
	return SPAWN_WAVE_CATALOG_VALIDATOR.validate(
		rows,
		_enemy_ids,
		_hazard_ids,
		_game_mode_ids,
		Callable(self, "_require_mode_id"),
		Callable(self, "_record_failure")
	)


func _require_mode_id(field: String, value: Variant) -> String:
	var mode_id: String = String(value)
	var call: String = "%s|%s" % [field, mode_id]
	_mode_calls.append(call)
	_events.append("mode:%s" % call)
	if not value is String or mode_id.is_empty():
		_record_failure(field, "non-empty string")
		return ""
	if not _registered_modes.has(mode_id):
		_record_failure(field, "registered id in game_modes")
		return ""
	return mode_id


func _record_failure(field: String, expected: String) -> void:
	var failure: String = "%s|%s" % [field, expected]
	_reported_failures.append(failure)
	_events.append("failure:%s" % failure)


func _clear_diagnostics() -> void:
	_reported_failures.clear()
	_mode_calls.clear()
	_events.clear()


func _single_row(row: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [row]
	return rows


func _valid_row(
	wave_id: String,
	mode_id: String = "mode_a",
	wave_index: String = "1"
) -> Dictionary:
	return {
		"id": wave_id,
		"mode_id": mode_id,
		"wave_index": wave_index,
		"start_time": "0.0",
		"end_time": "10.0",
		"enemy_id": "enemy_a",
		"enemy_weight": "1",
		"spawn_interval": "1.0",
		"max_alive": "1",
		"spawn_budget": "0",
		"hazard_id": "",
		"hazard_weight": "0",
	}
