extends SmokeHarness


const GEAR_MOD_DROP_TABLE_VALIDATOR := preload(
	"res://scripts/data/gear_mod_drop_table_validator.gd"
)

var _reported_failures: Array[String] = []


func before_each() -> void:
	super()
	_reported_failures.clear()


func test_merged_rows_accept_boundary_values() -> void:
	var rows: Array[Dictionary] = [
		_valid_row("enemy_a", "mod_a", "0.0", "1", "1"),
		_valid_row("enemy_b", "mod_b", "1.0", "1", "999"),
	]

	assert_true(_validate_merged(rows, {
		"enemy_a": true,
		"enemy_b": true,
	}, {
		"mod_a": true,
		"mod_b": true,
	}))
	assert_eq(_reported_failures, [])


func test_merged_empty_table_keeps_legacy_failure() -> void:
	var rows: Array[Dictionary] = []

	assert_false(_validate_merged(rows, {}, {}))
	assert_eq(_reported_failures, [
		"rows|non-empty CSV",
	])


func test_merged_row_reports_multiple_failures_in_field_order() -> void:
	var rows: Array[Dictionary] = [
		_valid_row("", "", "bad", "0", "not_an_int"),
	]

	assert_false(_validate_merged(rows, {}, {}))
	assert_eq(_reported_failures, [
		"line 2.source_enemy_id|non-empty string",
		"line 2.mod_id|non-empty string",
		"line 2.drop_chance|number",
		"line 2.min_enemy_level|int >= 1",
		"line 2.max_enemy_level|int",
	])


func test_merged_unknown_ids_still_participate_in_duplicate_detection() -> void:
	var rows: Array[Dictionary] = [
		_valid_row("enemy_unknown", "mod_unknown", "0.5", "2", "4"),
		_valid_row("enemy_unknown", "mod_unknown", "0.5", "2", "4"),
	]

	assert_false(_validate_merged(rows, {}, {}))
	assert_eq(_reported_failures, [
		"line 2.source_enemy_id|enemy defined in enemies.csv",
		"line 2.mod_id|gear mod defined in gear_mods.json",
		"line 3.source_enemy_id|enemy defined in enemies.csv",
		"line 3.mod_id|gear mod defined in gear_mods.json",
		"line 3|unique source/mod/level range",
	])


func test_merged_inverted_range_still_participates_in_duplicates() -> void:
	var rows: Array[Dictionary] = [
		_valid_row("enemy_a", "mod_a", "0.5", "5", "4"),
		_valid_row("enemy_a", "mod_a", "0.5", "5", "4"),
	]

	assert_false(_validate_merged(rows, {"enemy_a": true}, {"mod_a": true}))
	assert_eq(_reported_failures, [
		"line 2.max_enemy_level|int >= min_enemy_level",
		"line 3.max_enemy_level|int >= min_enemy_level",
		"line 3|unique source/mod/level range",
	])


func test_merged_invalid_level_skips_range_and_duplicate_checks() -> void:
	var rows: Array[Dictionary] = [
		_valid_row("enemy_a", "mod_a", "0.5", "0", "1"),
		_valid_row("enemy_a", "mod_a", "0.5", "0", "1"),
		_valid_row("enemy_a", "mod_a", "0.5", "not_an_int", "1"),
	]

	assert_false(_validate_merged(rows, {"enemy_a": true}, {"mod_a": true}))
	assert_eq(_reported_failures, [
		"line 2.min_enemy_level|int >= 1",
		"line 3.min_enemy_level|int >= 1",
		"line 4.min_enemy_level|int",
	])


func test_package_rows_reject_bad_container_shapes_without_new_diagnostics() -> void:
	assert_false(_validate_package({}, "package_a", {}, {}))
	assert_eq(_reported_failures, [])

	assert_false(_validate_package([42], "package_a", {}, {}))
	assert_eq(_reported_failures, [])

	assert_true(_validate_package([], "package_a", {}, {}))
	assert_eq(_reported_failures, [])


func test_package_rows_keep_required_extra_and_numeric_failure_order() -> void:
	var malformed_row: Dictionary = {}
	malformed_row["extra_second"] = true
	malformed_row["drop_chance"] = "bad"
	malformed_row["extra_first"] = true

	assert_false(_validate_package(
		[malformed_row],
		"package_a",
		{},
		{}
	))
	assert_eq(_reported_failures, [
		"package_a.drop_rows[0].source_enemy_id|required field",
		"package_a.drop_rows[0].mod_id|required field",
		"package_a.drop_rows[0].min_enemy_level|required field",
		"package_a.drop_rows[0].max_enemy_level|required field",
		"package_a.drop_rows[0].extra_second|allowed schema field",
		"package_a.drop_rows[0].extra_first|allowed schema field",
		"package_a.drop_rows[0].drop_chance|number",
		"package_a.drop_rows[0].min_enemy_level|int",
		"package_a.drop_rows[0].max_enemy_level|int",
	])


func test_package_unknown_ids_and_inverted_range_remain_silent() -> void:
	var rows: Array = [
		_valid_row("enemy_unknown", "mod_unknown", "0.5", "5", "4"),
	]

	assert_false(_validate_package(rows, "package_a", {}, {}))
	assert_eq(_reported_failures, [])


func test_package_duplicate_rows_remain_legal() -> void:
	var row: Dictionary = _valid_row(
		"enemy_a",
		"mod_a",
		"0.5",
		"1",
		"4"
	)
	var rows: Array = [row, row.duplicate(true)]

	assert_true(_validate_package(
		rows,
		"package_a",
		{"enemy_a": true},
		{"mod_a": true}
	))
	assert_eq(_reported_failures, [])


func test_merged_calls_do_not_share_duplicate_state() -> void:
	var rows: Array[Dictionary] = [
		_valid_row("enemy_a", "mod_a", "0.5", "1", "4"),
	]
	var enemy_ids: Dictionary = {"enemy_a": true}
	var mod_ids: Dictionary = {"mod_a": true}

	assert_true(_validate_merged(rows, enemy_ids, mod_ids))
	assert_eq(_reported_failures, [])
	assert_true(_validate_merged(rows, enemy_ids, mod_ids))
	assert_eq(_reported_failures, [])


func _validate_merged(
	rows: Array[Dictionary],
	enemy_ids: Dictionary,
	mod_ids: Dictionary
) -> bool:
	return GEAR_MOD_DROP_TABLE_VALIDATOR.validate_merged_rows(
		rows,
		enemy_ids,
		mod_ids,
		Callable(self, "_record_failure")
	)


func _validate_package(
	rows: Variant,
	package_id: String,
	enemy_ids: Dictionary,
	mod_ids: Dictionary
) -> bool:
	return GEAR_MOD_DROP_TABLE_VALIDATOR.validate_package_rows(
		rows,
		package_id,
		enemy_ids,
		mod_ids,
		Callable(self, "_record_failure")
	)


func _record_failure(field: String, expected: String) -> void:
	_reported_failures.append("%s|%s" % [field, expected])


func _valid_row(
	source_enemy_id: String,
	mod_id: String,
	drop_chance: String,
	min_enemy_level: String,
	max_enemy_level: String
) -> Dictionary:
	return {
		"source_enemy_id": source_enemy_id,
		"mod_id": mod_id,
		"drop_chance": drop_chance,
		"min_enemy_level": min_enemy_level,
		"max_enemy_level": max_enemy_level,
	}
