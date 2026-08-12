# Doc: docs/代码/data_loader.md
class_name DeclarativeDataCatalog
extends RefCounted


const VALIDATOR := preload(
	"res://scripts/data/declarative_schema_validator.gd"
)
const DATA_ROOT: String = "res://data/"
const SCHEMA_ROOT: String = "res://data/schemas/"
const CATALOG_PATH: String = SCHEMA_ROOT + "catalog.json"


static func validate_project_sources() -> Dictionary:
	var errors: Array[Dictionary] = []
	var counts: Dictionary = {}
	var references: Dictionary = _catalog_references()
	var catalog: Variant = _read_json(CATALOG_PATH)
	if not catalog is Dictionary:
		return _result([_error(CATALOG_PATH, "root", "readable JSON")], counts)
	var catalog_data: Dictionary = catalog as Dictionary
	if catalog_data.get("schema_version") != 1:
		return _result([_error(CATALOG_PATH, "schema_version", "must equal 1")], counts)
	if not catalog_data.get("sources") is Array:
		return _result([_error(CATALOG_PATH, "sources", "must be an array")], counts)
	var seen_sources: Dictionary = {}
	var seen_schemas: Dictionary = {}
	var sources: Array = catalog_data["sources"] as Array
	for index: int in sources.size():
		var raw_entry: Variant = sources[index]
		var entry_path: String = "sources[%d]" % index
		if not raw_entry is Dictionary:
			errors.append(_error(CATALOG_PATH, entry_path, "must be an object"))
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var source: String = String(entry.get("source", ""))
		var format_id: String = String(entry.get("format", ""))
		var schema_name: String = String(entry.get("schema", ""))
		if source.is_empty() or format_id.is_empty() or schema_name.is_empty():
			errors.append(_error(CATALOG_PATH, entry_path, "must name source, format, and schema"))
			continue
		if format_id not in ["csv", "json", "json-glob"]:
			errors.append(_error(CATALOG_PATH, entry_path + ".format", "must be csv, json, or json-glob"))
			continue
		if seen_sources.has(source) or seen_schemas.has(schema_name):
			errors.append(_error(CATALOG_PATH, entry_path, "must be unique"))
			continue
		seen_sources[source] = true
		seen_schemas[schema_name] = true
		var schema_path: String = SCHEMA_ROOT + schema_name
		var raw_schema: Variant = _read_json(schema_path)
		if not raw_schema is Dictionary:
			errors.append(_error(schema_path, "root", "readable JSON"))
			continue
		var paths: Array[String] = _source_paths(source, format_id)
		if paths.is_empty():
			errors.append(_error(DATA_ROOT + source, "root", "existing data source"))
			continue
		for source_path: String in paths:
			var read_result: Dictionary = _read_source(source_path, format_id)
			if not bool(read_result.get("ok", false)):
				errors.append(_error(source_path, "root", "readable %s" % format_id))
				continue
			var context: Dictionary = {
				"headers": read_result.get("headers", {}),
				"references": references,
			}
			var validation: Dictionary = VALIDATOR.validate(
				raw_schema as Dictionary,
				read_result.get("value"),
				context
			)
			for raw_key: Variant in (validation.get("counts", {}) as Dictionary):
				counts[raw_key] = (validation["counts"] as Dictionary)[raw_key]
			for raw_issue: Variant in validation.get("errors", []) as Array:
				if raw_issue is Dictionary:
					var issue: Dictionary = raw_issue as Dictionary
					errors.append(_error(
						source_path,
						String(issue.get("field", "root")),
						String(issue.get("expected", "valid schema value"))
					))
	return _result(errors, counts)


static func _source_paths(source: String, format_id: String) -> Array[String]:
	if format_id != "json-glob":
		var direct_paths: Array[String] = []
		if FileAccess.file_exists(DATA_ROOT + source):
			direct_paths.append(DATA_ROOT + source)
		return direct_paths
	var slash_index: int = source.rfind("/")
	var directory_path: String = DATA_ROOT + source.substr(0, slash_index)
	var extension: String = source.get_extension()
	var directory: DirAccess = DirAccess.open(directory_path)
	if directory == null:
		return []
	var paths: Array[String] = []
	for file_name: String in directory.get_files():
		if file_name.get_extension() == extension:
			paths.append(directory_path + "/" + file_name)
	paths.sort()
	return paths


static func _read_source(path: String, format_id: String) -> Dictionary:
	if format_id != "csv":
		var value: Variant = _read_json(path)
		return {"ok": value != null, "value": value, "headers": {}}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	var headers: PackedStringArray = file.get_csv_line()
	var rows: Array[Dictionary] = []
	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 1 and values[0].is_empty() and file.eof_reached():
			break
		if values.size() != headers.size():
			return {"ok": false}
		var row: Dictionary = {}
		for index: int in headers.size():
			row[headers[index]] = values[index]
		rows.append(row)
	return {
		"ok": true,
		"value": rows,
		"headers": {path.get_file(): Array(headers)},
	}


static func _read_json(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	return parser.data


static func _catalog_references() -> Dictionary:
	var references: Dictionary = {}
	var contracts: Variant = _read_json(DATA_ROOT + "_contracts.json")
	if contracts is Dictionary:
		var contract_values: Variant = (contracts as Dictionary).get(
			"contracts",
			{}
		)
		if contract_values is Dictionary:
			for raw_key: Variant in contract_values:
				var values: Variant = (contract_values as Dictionary)[raw_key]
				if values is Array:
					references["contract:%s" % raw_key] = values
	var locale_file: FileAccess = FileAccess.open(
		"res://locale/strings.csv",
		FileAccess.READ
	)
	var locale_keys: Array[String] = []
	if locale_file != null:
		locale_file.get_csv_line()
		while not locale_file.eof_reached():
			var row: PackedStringArray = locale_file.get_csv_line()
			if not row.is_empty() and not row[0].is_empty():
				locale_keys.append(row[0])
	references["locale"] = locale_keys
	return references


static func _error(path: String, field: String, expected: String) -> Dictionary:
	return {"path": path, "field": field, "expected": expected}


static func _result(errors: Array[Dictionary], counts: Dictionary) -> Dictionary:
	return {"ok": errors.is_empty(), "errors": errors, "counts": counts}
