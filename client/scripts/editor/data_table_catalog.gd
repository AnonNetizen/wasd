# Doc: docs/代码/data_table_editor.md
@tool
class_name DataTableCatalog
extends RefCounted
## Loads the declarative list of data sources owned by the data-table editor.

const DEFAULT_CATALOG_PATH: String = (
	"res://addons/data_table_editor/data_table_catalog.json"
)
const DATA_DIRECTORY: String = "res://data"
const LOCALE_STRINGS_PATH: String = "res://locale/strings.csv"

var catalog_path: String = DEFAULT_CATALOG_PATH
var _datasets: Array[Dictionary] = []
var _excluded_sources: Array[Dictionary] = []


func load_catalog() -> Dictionary:
	_datasets.clear()
	_excluded_sources.clear()
	var parsed_result: Dictionary = _load_json_dictionary(catalog_path)
	if not bool(parsed_result.get("ok", false)):
		return parsed_result
	var payload: Dictionary = parsed_result.get("data", {}) as Dictionary
	if int(payload.get("schema_version", 0)) != 1:
		return _error_result("data table catalog schema_version must be 1")
	var raw_datasets: Variant = payload.get("datasets", [])
	if not raw_datasets is Array:
		return _error_result("data table catalog datasets must be an Array")
	var ids: Dictionary = {}
	var paths: Dictionary = {}
	var dataset_defaults: Dictionary = {}
	if payload.get("dataset_defaults", {}) is Dictionary:
		dataset_defaults = (payload.get("dataset_defaults", {}) as Dictionary).duplicate(true)
	for index: int in range((raw_datasets as Array).size()):
		var raw_dataset: Variant = (raw_datasets as Array)[index]
		if not raw_dataset is Dictionary:
			return _error_result("datasets[%d] must be a Dictionary" % index)
		var dataset: Dictionary = dataset_defaults.duplicate(true)
		dataset.merge((raw_dataset as Dictionary).duplicate(true), true)
		var dataset_id: String = String(dataset.get("id", ""))
		var path: String = String(dataset.get("path", ""))
		var format: String = String(dataset.get("format", ""))
		if dataset_id.is_empty() or ids.has(dataset_id):
			return _error_result("dataset id is empty or duplicated: %s" % dataset_id)
		if path.is_empty() or paths.has(path):
			return _error_result("dataset path is empty or duplicated: %s" % path)
		if format != "json" and format != "csv":
			return _error_result("dataset %s format must be json or csv" % dataset_id)
		var schema_error: String = _descriptor_schema_error(dataset)
		if not schema_error.is_empty():
			return _error_result("dataset %s %s" % [dataset_id, schema_error])
		if not FileAccess.file_exists(path):
			return _error_result("dataset source is missing: %s" % path)
		ids[dataset_id] = true
		paths[path] = true
		_datasets.append(dataset)
	var raw_excluded: Variant = payload.get("excluded_sources", [])
	if not raw_excluded is Array:
		return _error_result("excluded_sources must be an Array")
	for raw_entry: Variant in raw_excluded as Array:
		if raw_entry is Dictionary:
			_excluded_sources.append((raw_entry as Dictionary).duplicate(true))
	var coverage_errors: PackedStringArray = coverage_errors()
	if not coverage_errors.is_empty():
		return {
			"ok": false,
			"errors": coverage_errors,
		}
	return _success_result()


func datasets() -> Array[Dictionary]:
	return _datasets.duplicate(true)


func dataset_by_id(dataset_id: String) -> Dictionary:
	for dataset: Dictionary in _datasets:
		if String(dataset.get("id", "")) == dataset_id:
			return dataset.duplicate(true)
	return {}


func dataset_by_path(path: String) -> Dictionary:
	for dataset: Dictionary in _datasets:
		if String(dataset.get("path", "")) == path:
			return dataset.duplicate(true)
	return {}


func excluded_sources() -> Array[Dictionary]:
	return _excluded_sources.duplicate(true)


func coverage_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var owned_paths: Dictionary = {}
	for dataset: Dictionary in _datasets:
		owned_paths[String(dataset.get("path", ""))] = true
	for path: String in _project_data_paths():
		if owned_paths.has(path) or _is_excluded(path):
			continue
		errors.append("unregistered project data source: %s" % path)
	for dataset: Dictionary in _datasets:
		var dataset_path: String = String(dataset.get("path", ""))
		if _is_excluded(dataset_path):
			errors.append(
				"dataset cannot be both editable and excluded: %s" % dataset_path
			)
	return errors


func _project_data_paths() -> Array[String]:
	var paths: Array[String] = []
	_collect_data_paths(DATA_DIRECTORY, paths)
	if FileAccess.file_exists(LOCALE_STRINGS_PATH):
		paths.append(LOCALE_STRINGS_PATH)
	paths.sort()
	return paths


func _collect_data_paths(directory_path: String, output: Array[String]) -> void:
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry_name: String = directory.get_next()
	while not entry_name.is_empty():
		var entry_path: String = directory_path.path_join(entry_name)
		if directory.current_is_dir():
			if entry_name.to_lower() != "draft":
				_collect_data_paths(entry_path, output)
		elif entry_name.ends_with(".json") or entry_name.ends_with(".csv"):
			output.append(entry_path)
		entry_name = directory.get_next()
	directory.list_dir_end()


func _is_excluded(path: String) -> bool:
	for entry: Dictionary in _excluded_sources:
		var pattern: String = String(entry.get("path", ""))
		if pattern.ends_with("*.json"):
			var prefix: String = pattern.trim_suffix("*.json")
			if path.begins_with(prefix) and path.ends_with(".json"):
				return true
		elif path == pattern:
			return true
	return false


func _descriptor_schema_error(dataset: Dictionary) -> String:
	var default_mode: String = String(dataset.get("default_template_mode", "first_record"))
	if default_mode != "first_record" and not dataset.get("default_template", null) is Dictionary:
		return "requires a Dictionary default_template or first_record mode"
	var raw_rules: Variant = dataset.get("field_rules", [])
	if not raw_rules is Array:
		return "field_rules must be an Array"
	for raw_rule: Variant in raw_rules as Array:
		if not raw_rule is Dictionary:
			return "field_rules entries must be Dictionaries"
		var rule: Dictionary = raw_rule as Dictionary
		if String(rule.get("path", "")).is_empty():
			return "field rule path cannot be empty"
		if not ["string", "number", "boolean", "array", "object"].has(
			String(rule.get("type", ""))
		):
			return "field rule type is invalid"
		if rule.has("min") and rule.has("max") and float(rule.get("min")) > float(rule.get("max")):
			return "field rule min cannot exceed max"
	var raw_references: Variant = dataset.get("references", [])
	if not raw_references is Array:
		return "references must be an Array"
	for raw_reference: Variant in raw_references as Array:
		if not raw_reference is Dictionary:
			return "references entries must be Dictionaries"
		var reference: Dictionary = raw_reference as Dictionary
		if String(reference.get("path", "")).is_empty() or String(
			reference.get("target", "")
		).is_empty():
			return "reference path and target cannot be empty"
	return ""


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error_result("missing JSON file: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error_result("failed to open JSON file: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _error_result("JSON root must be a Dictionary: %s" % path)
	var result: Dictionary = _success_result()
	result["data"] = parsed as Dictionary
	return result


func _success_result() -> Dictionary:
	return {"ok": true, "errors": PackedStringArray()}


func _error_result(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
