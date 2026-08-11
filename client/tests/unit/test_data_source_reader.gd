extends SmokeHarness


const DATA_SOURCE_READER := preload(
	"res://scripts/data/data_source_reader.gd"
)
const JSON_PATH: String = "user://test_data_source_reader.json"
const CSV_PATH: String = "user://test_data_source_reader.csv"
const MISSING_JSON_PATH: String = (
	"user://test_data_source_reader_missing.json"
)
const MISSING_CSV_PATH: String = (
	"user://test_data_source_reader_missing.csv"
)


func before_each() -> void:
	super()
	_remove_test_files()


func after_each() -> void:
	_remove_test_files()
	super()


func test_json_reads_dictionary_array_and_scalar_values() -> void:
	_write_text(JSON_PATH, "{\"name\":\"base\",\"items\":[1,true]}")
	var dictionary_result: DATA_SOURCE_READER.JsonReadResult = (
		DATA_SOURCE_READER.read_json(JSON_PATH)
	)
	assert_true(dictionary_result.ok)
	assert_eq(dictionary_result.data, {
		"name": "base",
		"items": [1.0, true],
	})
	assert_eq(dictionary_result.failure_field, "")
	assert_eq(dictionary_result.failure_expected, "")

	_write_text(JSON_PATH, "[\"entry\",2]")
	var array_result: DATA_SOURCE_READER.JsonReadResult = (
		DATA_SOURCE_READER.read_json(JSON_PATH)
	)
	assert_true(array_result.ok)
	assert_eq(array_result.data, ["entry", 2.0])

	_write_text(JSON_PATH, "false")
	var scalar_result: DATA_SOURCE_READER.JsonReadResult = (
		DATA_SOURCE_READER.read_json(JSON_PATH)
	)
	assert_true(scalar_result.ok)
	assert_eq(scalar_result.data, false)


func test_json_missing_file_reports_legacy_failure_metadata() -> void:
	var result: DATA_SOURCE_READER.JsonReadResult = (
		DATA_SOURCE_READER.read_json(MISSING_JSON_PATH)
	)
	assert_false(result.ok)
	assert_eq(result.data, {})
	assert_eq(result.failure_field, "file")
	assert_eq(result.failure_expected, "readable JSON file")


func test_json_null_keeps_legacy_invalid_semantics() -> void:
	_write_text(JSON_PATH, "null")
	var null_result: DATA_SOURCE_READER.JsonReadResult = (
		DATA_SOURCE_READER.read_json(JSON_PATH)
	)
	assert_false(null_result.ok)
	assert_eq(null_result.failure_field, "json")
	assert_eq(null_result.failure_expected, "valid JSON")


func test_json_reloads_source_and_returns_fresh_values() -> void:
	_write_text(JSON_PATH, "{\"value\":1,\"nested\":{\"flag\":true}}")
	var first: DATA_SOURCE_READER.JsonReadResult = (
		DATA_SOURCE_READER.read_json(JSON_PATH)
	)
	assert_true(first.ok)
	var first_data: Dictionary = first.data as Dictionary
	var first_nested: Dictionary = first_data["nested"] as Dictionary
	first_nested["flag"] = false

	var second: DATA_SOURCE_READER.JsonReadResult = (
		DATA_SOURCE_READER.read_json(JSON_PATH)
	)
	assert_true(second.ok)
	var second_data: Dictionary = second.data as Dictionary
	assert_eq(second_data["value"], 1.0)
	assert_true((second_data["nested"] as Dictionary)["flag"])

	_write_text(JSON_PATH, "{\"value\":2}")
	var third: DATA_SOURCE_READER.JsonReadResult = (
		DATA_SOURCE_READER.read_json(JSON_PATH)
	)
	assert_true(third.ok)
	assert_eq((third.data as Dictionary)["value"], 2.0)


func test_csv_with_header_keeps_padding_truncation_and_blank_rows() -> void:
	_write_text(
		CSV_PATH,
		(
			"id,name,note\n"
			+ "one,Alpha\n"
			+ "two,\"Beta, Inc.\",kept,ignored\n"
			+ "   \n"
			+ ",,\n"
		)
	)
	var result: DATA_SOURCE_READER.CsvReadResult = (
		DATA_SOURCE_READER.read_csv(CSV_PATH)
	)

	assert_true(result.ok)
	assert_eq(result.failure_field, "")
	assert_eq(result.failure_expected, "")
	assert_eq(result.rows, [
		{
			"id": "one",
			"name": "Alpha",
			"note": "",
		},
		{
			"id": "two",
			"name": "Beta, Inc.",
			"note": "kept",
		},
		{
			"id": "",
			"name": "",
			"note": "",
		},
	])


func test_csv_without_header_uses_numeric_keys_and_keeps_row_widths() -> void:
	_write_text(
		CSV_PATH,
		"left,right\nsolo\n,,\n\n"
	)
	var result: DATA_SOURCE_READER.CsvReadResult = (
		DATA_SOURCE_READER.read_csv(CSV_PATH, false)
	)

	assert_true(result.ok)
	assert_eq(result.rows, [
		{
			"0": "left",
			"1": "right",
		},
		{
			"0": "solo",
		},
		{
			"0": "",
			"1": "",
			"2": "",
		},
	])


func test_csv_empty_and_header_only_sources_succeed_with_no_rows() -> void:
	_write_text(CSV_PATH, "")
	var empty_result: DATA_SOURCE_READER.CsvReadResult = (
		DATA_SOURCE_READER.read_csv(CSV_PATH)
	)
	assert_true(empty_result.ok)
	assert_eq(empty_result.rows, [])

	_write_text(CSV_PATH, "id,name\n")
	var header_result: DATA_SOURCE_READER.CsvReadResult = (
		DATA_SOURCE_READER.read_csv(CSV_PATH)
	)
	assert_true(header_result.ok)
	assert_eq(header_result.rows, [])


func test_csv_missing_file_reports_legacy_failure_metadata() -> void:
	var result: DATA_SOURCE_READER.CsvReadResult = (
		DATA_SOURCE_READER.read_csv(MISSING_CSV_PATH)
	)
	assert_false(result.ok)
	assert_eq(result.rows, [])
	assert_eq(result.failure_field, "file")
	assert_eq(result.failure_expected, "readable CSV file")


func test_csv_reloads_source_and_returns_fresh_rows() -> void:
	_write_text(CSV_PATH, "id,value\nentry,first\n")
	var first: DATA_SOURCE_READER.CsvReadResult = (
		DATA_SOURCE_READER.read_csv(CSV_PATH)
	)
	assert_true(first.ok)
	first.rows[0]["value"] = "mutated"

	var second: DATA_SOURCE_READER.CsvReadResult = (
		DATA_SOURCE_READER.read_csv(CSV_PATH)
	)
	assert_true(second.ok)
	assert_eq(second.rows[0]["value"], "first")

	_write_text(CSV_PATH, "id,value\nentry,second\n")
	var third: DATA_SOURCE_READER.CsvReadResult = (
		DATA_SOURCE_READER.read_csv(CSV_PATH)
	)
	assert_true(third.ok)
	assert_eq(third.rows[0]["value"], "second")


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file)
	if file == null:
		return
	file.store_string(text)
	file.close()


func _remove_test_files() -> void:
	for path: String in [
		JSON_PATH,
		CSV_PATH,
		MISSING_JSON_PATH,
		MISSING_CSV_PATH,
	]:
		var absolute_path: String = ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute_path)
