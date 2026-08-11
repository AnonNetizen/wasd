extends SmokeHarness


const JSON_PATH: String = (
	"user://test_data_source_reader_adapter.json"
)
const CSV_PATH: String = (
	"user://test_data_source_reader_adapter.csv"
)
const MISSING_JSON_PATH: String = (
	"user://test_data_source_reader_adapter_missing.json"
)
const MISSING_CSV_PATH: String = (
	"user://test_data_source_reader_adapter_missing.csv"
)
const ORIGINAL_MOD_LOADER_NAME: String = (
	"DataSourceReaderAdapterOriginalModLoader"
)

var _probe: AdapterProbe = null
var _fake_mod_loader: FakeModLoader = null
var _original_mod_loader: Node = null


func before_each() -> void:
	super()
	_remove_test_files()
	_install_fake_mod_loader()
	_probe = AdapterProbe.new()
	add_child_autofree(_probe)


func after_each() -> void:
	_restore_original_mod_loader()
	_remove_test_files()
	_probe = null
	super()


func test_failures_keep_data_loader_diagnostics_and_skip_overlays() -> void:
	var missing_json: Variant = _probe.load_json(MISSING_JSON_PATH)
	var missing_csv: Array[Dictionary] = _probe.load_csv(
		MISSING_CSV_PATH
	)
	_write_text(JSON_PATH, "null")
	var null_json: Variant = _probe.load_json(JSON_PATH)

	assert_eq(missing_json, {})
	assert_eq(missing_csv, [])
	assert_eq(null_json, {})
	assert_eq(_probe.failures, [
		"%s|file|readable JSON file" % MISSING_JSON_PATH,
		"%s|file|readable CSV file" % MISSING_CSV_PATH,
		"%s|json|valid JSON" % JSON_PATH,
	])
	assert_eq(_fake_mod_loader.json_paths, [])
	assert_eq(_fake_mod_loader.csv_paths, [])


func test_success_applies_overlays_but_contracts_stay_base_only() -> void:
	_write_text(JSON_PATH, "{\"value\":\"base\"}")
	_write_text(CSV_PATH, "id,value\nbase,one\n")

	var json_result: Dictionary = _probe.load_json(JSON_PATH) as Dictionary
	var csv_result: Array[Dictionary] = _probe.load_csv(CSV_PATH)
	var contracts_result: Dictionary = (
		_probe.load_json(DataLoaderAutoload.CONTRACTS_PATH) as Dictionary
	)

	assert_eq(json_result, {
		"value": "base",
		"overlay_applied": true,
	})
	assert_eq(csv_result, [
		{
			"id": "base",
			"value": "one",
		},
		{
			"id": "mod_overlay",
			"value": "applied",
		},
	])
	assert_true(contracts_result.has("contracts"))
	assert_false(contracts_result.has("overlay_applied"))
	assert_eq(_fake_mod_loader.json_paths, [JSON_PATH])
	assert_eq(_fake_mod_loader.csv_paths, [CSV_PATH])
	assert_eq(_probe.failures, [])


func test_public_loaders_reread_base_sources_before_each_overlay() -> void:
	_write_text(JSON_PATH, "{\"value\":\"first\"}")
	var first_json: Dictionary = _probe.load_json(JSON_PATH) as Dictionary
	_write_text(JSON_PATH, "{\"value\":\"second\"}")
	var second_json: Dictionary = _probe.load_json(JSON_PATH) as Dictionary

	_write_text(CSV_PATH, "id,value\nbase,first\n")
	var first_csv: Array[Dictionary] = _probe.load_csv(CSV_PATH)
	_write_text(CSV_PATH, "id,value\nbase,second\n")
	var second_csv: Array[Dictionary] = _probe.load_csv(CSV_PATH)

	assert_eq(first_json["value"], "first")
	assert_eq(second_json["value"], "second")
	assert_true(bool(first_json["overlay_applied"]))
	assert_true(bool(second_json["overlay_applied"]))
	assert_eq(first_csv[0]["value"], "first")
	assert_eq(second_csv[0]["value"], "second")
	assert_eq(_fake_mod_loader.json_paths, [JSON_PATH, JSON_PATH])
	assert_eq(_fake_mod_loader.csv_paths, [CSV_PATH, CSV_PATH])
	assert_eq(_probe.failures, [])


func _install_fake_mod_loader() -> void:
	var root: Window = get_tree().root
	_original_mod_loader = root.get_node_or_null("ModLoader")
	if _original_mod_loader != null:
		_original_mod_loader.name = ORIGINAL_MOD_LOADER_NAME
	_fake_mod_loader = FakeModLoader.new()
	_fake_mod_loader.name = "ModLoader"
	root.add_child(_fake_mod_loader)


func _restore_original_mod_loader() -> void:
	var root: Window = get_tree().root
	if is_instance_valid(_fake_mod_loader):
		if _fake_mod_loader.get_parent() == root:
			root.remove_child(_fake_mod_loader)
		_fake_mod_loader.free()
	_fake_mod_loader = null
	if is_instance_valid(_original_mod_loader):
		_original_mod_loader.name = "ModLoader"
	_original_mod_loader = null


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


class AdapterProbe:
	extends DataLoaderAutoload

	var failures: Array[String] = []


	func _fail(
		resource_path: String,
		field_path: String,
		expected: String
	) -> void:
		failures.append(
			"%s|%s|%s" % [resource_path, field_path, expected]
		)


class FakeModLoader:
	extends Node

	var json_paths: Array[String] = []
	var csv_paths: Array[String] = []


	func apply_json_mods(resource_path: String, data: Variant) -> Variant:
		json_paths.append(resource_path)
		if not data is Dictionary:
			return data
		var overlaid: Dictionary = (data as Dictionary).duplicate(true)
		overlaid["overlay_applied"] = true
		return overlaid


	func apply_csv_mods(
		resource_path: String,
		rows: Array[Dictionary]
	) -> Array[Dictionary]:
		csv_paths.append(resource_path)
		var overlaid: Array[Dictionary] = []
		for row: Dictionary in rows:
			overlaid.append(row.duplicate(true))
		overlaid.append({
			"id": "mod_overlay",
			"value": "applied",
		})
		return overlaid
