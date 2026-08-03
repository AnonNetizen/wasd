# Doc: docs/代码/data_table_editor.md
@tool
class_name DataSearchIndex
extends RefCounted
## In-memory literal search index for data sources owned by DataTableCatalog.

const MAX_JSON_DEPTH: int = 8
const LOCALE_DATASET_ID: String = "locale_strings"

var _entries: Array[Dictionary] = []
var _locale_by_key: Dictionary = {}


func rebuild(catalog: DataTableCatalog) -> Dictionary:
	_entries.clear()
	_locale_by_key.clear()
	var datasets: Array[Dictionary] = catalog.datasets()
	for descriptor: Dictionary in datasets:
		if String(descriptor.get("id", "")) == LOCALE_DATASET_ID:
			var locale_result: Dictionary = _load_dataset(descriptor)
			if not bool(locale_result.get("ok", false)):
				return locale_result
			_build_locale_lookup(locale_result.get("data", []))
			break
	for descriptor: Dictionary in datasets:
		var result: Dictionary = _index_dataset(descriptor)
		if not bool(result.get("ok", false)):
			return result
	return {"ok": true, "errors": PackedStringArray(), "entry_count": _entries.size()}


func query(
	text: String,
	dataset_id: String = "",
	format_filter: String = "",
	type_filter: String = ""
) -> Array[Dictionary]:
	var terms: PackedStringArray = _terms(text)
	var matches: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if not dataset_id.is_empty() and String(entry.get("dataset_id", "")) != dataset_id:
			continue
		if not format_filter.is_empty() and String(entry.get("format", "")) != format_filter:
			continue
		if not type_filter.is_empty() and String(entry.get("value_type", "")) != type_filter:
			continue
		var haystack: String = String(entry.get("search_text", ""))
		var has_every_term: bool = true
		for term: String in terms:
			if not haystack.contains(term):
				has_every_term = false
				break
		if not has_every_term:
			continue
		var match_entry: Dictionary = entry.duplicate(true)
		match_entry["score"] = _score(match_entry, terms)
		matches.append(match_entry)
	matches.sort_custom(_sort_matches)
	return matches


func references_to(
	value: String,
	ignore_dataset_id: String = "",
	ignore_section_path: String = "",
	ignore_record_index: int = -1
) -> Array[Dictionary]:
	var references: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if String(entry.get("scalar_text", "")) != value:
			continue
		if (
			String(entry.get("dataset_id", "")) == ignore_dataset_id
			and String(entry.get("section_path", "")) == ignore_section_path
			and int(entry.get("record_index", -1)) == ignore_record_index
		):
			continue
		references.append(entry.duplicate(true))
	return references


func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func _index_dataset(descriptor: Dictionary) -> Dictionary:
	var load_result: Dictionary = _load_dataset(descriptor)
	if not bool(load_result.get("ok", false)):
		return load_result
	var payload: Variant = load_result.get("data", {})
	if String(descriptor.get("format", "")) == "csv":
		var rows: Array = payload as Array
		for record_index: int in range(rows.size()):
			if not rows[record_index] is Dictionary:
				continue
			_index_record(descriptor, "$rows", record_index, rows[record_index], [])
		return {"ok": true, "errors": PackedStringArray()}
	var root: Dictionary = payload as Dictionary
	var raw_sections: Variant = descriptor.get("sections", [])
	var indexed_sections: Dictionary = {}
	if raw_sections is Array:
		for raw_section: Variant in raw_sections as Array:
			if not raw_section is Dictionary:
				continue
			var section: Dictionary = raw_section as Dictionary
			var section_path: String = String(section.get("path", ""))
			var records: Variant = root.get(section_path, [])
			if not records is Array:
				continue
			indexed_sections[section_path] = true
			for record_index: int in range((records as Array).size()):
				var record_data: Variant = (records as Array)[record_index]
				if record_data is Dictionary:
					_index_record(descriptor, section_path, record_index, record_data, [])
	var root_fields: Dictionary = {}
	for key: Variant in root.keys():
		if indexed_sections.has(String(key)):
			continue
		root_fields[key] = root[key]
	if not root_fields.is_empty():
		_index_record(descriptor, "$root", 0, root_fields, [])
	return {"ok": true, "errors": PackedStringArray()}


func _index_record(
	descriptor: Dictionary,
	section_path: String,
	record_index: int,
	record_data: Dictionary,
	base_path: Array
) -> void:
	var record_id: String = _record_identity(descriptor, section_path, record_index, record_data)
	var first_entry_index: int = _entries.size()
	_flatten_value(
		descriptor,
		section_path,
		record_index,
		record_id,
		record_data,
		base_path,
		0
	)
	var record_context: String = JSON.stringify(record_data).to_lower()
	var raw_locale_fields: Variant = descriptor.get("locale_fields", [])
	if raw_locale_fields is Array:
		for raw_field: Variant in raw_locale_fields as Array:
			var locale_key: String = String(record_data.get(String(raw_field), ""))
			if not _locale_by_key.has(locale_key):
				continue
			var row: Dictionary = _locale_by_key[locale_key] as Dictionary
			record_context += " %s %s" % [
				String(row.get("zh_CN", "")).to_lower(),
				String(row.get("en", "")).to_lower(),
			]
	for entry_index: int in range(first_entry_index, _entries.size()):
		_entries[entry_index]["search_text"] = "%s %s" % [
			String(_entries[entry_index].get("search_text", "")),
			record_context,
		]


func _flatten_value(
	descriptor: Dictionary,
	section_path: String,
	record_index: int,
	record_id: String,
	value: Variant,
	field_path: Array,
	depth: int
) -> void:
	if depth > MAX_JSON_DEPTH:
		return
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array = dictionary.keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
		for key: Variant in keys:
			var child_path: Array = field_path.duplicate()
			child_path.append(String(key))
			_flatten_value(
				descriptor,
				section_path,
				record_index,
				record_id,
				dictionary[key],
				child_path,
				depth + 1
			)
		return
	if value is Array:
		var values: Array = value as Array
		for index: int in range(values.size()):
			var child_path: Array = field_path.duplicate()
			child_path.append(index)
			_flatten_value(
				descriptor,
				section_path,
				record_index,
				record_id,
				values[index],
				child_path,
				depth + 1
			)
		return
	var field_name: String = str(field_path[-1]) if not field_path.is_empty() else "$value"
	var path_text: String = _path_text(field_path)
	var scalar_text: String = _scalar_text(value)
	var locale_text: String = ""
	if field_name.ends_with("_key") and _locale_by_key.has(scalar_text):
		var locale_row: Dictionary = _locale_by_key[scalar_text] as Dictionary
		locale_text = "%s %s" % [
			String(locale_row.get("zh_CN", "")),
			String(locale_row.get("en", "")),
		]
	var dataset_id: String = String(descriptor.get("id", ""))
	var dataset_label: String = String(descriptor.get("label", dataset_id))
	var source_path: String = String(descriptor.get("path", ""))
	var search_text: String = " ".join(
		[
			dataset_id,
			dataset_label,
			source_path,
			section_path,
			record_id,
			path_text,
			field_name,
			scalar_text,
			locale_text,
		]
	).to_lower()
	_entries.append(
		{
			"dataset_id": dataset_id,
			"dataset_label": dataset_label,
			"format": String(descriptor.get("format", "")),
			"source_path": source_path,
			"section_path": section_path,
			"record_index": record_index,
			"record_id": record_id,
			"field_path": field_path.duplicate(),
			"field_path_text": path_text,
			"field_name": field_name,
			"value": value,
			"value_summary": _summary(scalar_text, locale_text),
			"scalar_text": scalar_text,
			"value_type": _value_type(
				value, String(descriptor.get("format", "")) == "csv"
			),
			"search_text": search_text,
		}
	)


func _load_dataset(descriptor: Dictionary) -> Dictionary:
	var path: String = String(descriptor.get("path", ""))
	if not FileAccess.file_exists(path):
		return _error("missing data source: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("failed to open data source: %s" % path)
	if String(descriptor.get("format", "")) == "json":
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not parsed is Dictionary:
			return _error("JSON root must be a Dictionary: %s" % path)
		return {"ok": true, "errors": PackedStringArray(), "data": parsed}
	var headers: PackedStringArray = file.get_csv_line()
	var rows: Array[Dictionary] = []
	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 1 and String(values[0]).is_empty():
			continue
		var row: Dictionary = {}
		for index: int in range(headers.size()):
			row[String(headers[index])] = values[index] if index < values.size() else ""
		rows.append(row)
	return {"ok": true, "errors": PackedStringArray(), "data": rows}


func _build_locale_lookup(raw_rows: Variant) -> void:
	if not raw_rows is Array:
		return
	for raw_row: Variant in raw_rows as Array:
		if not raw_row is Dictionary:
			continue
		var row: Dictionary = raw_row as Dictionary
		var key: String = String(row.get("keys", ""))
		if not key.is_empty():
			_locale_by_key[key] = row.duplicate(true)


func _record_identity(
	descriptor: Dictionary,
	section_path: String,
	record_index: int,
	record_data: Dictionary
) -> String:
	var raw_keys: Variant = descriptor.get("primary_keys", [])
	for raw_section: Variant in descriptor.get("sections", []):
		if raw_section is Dictionary and String((raw_section as Dictionary).get("path", "")) == section_path:
			raw_keys = (raw_section as Dictionary).get("primary_keys", [])
			break
	var parts := PackedStringArray()
	if raw_keys is Array:
		for raw_key: Variant in raw_keys as Array:
			parts.append(String(record_data.get(String(raw_key), "")))
	if parts.is_empty():
		return "#%d" % record_index
	return "/".join(parts)


func _terms(text: String) -> PackedStringArray:
	var output := PackedStringArray()
	for raw_term: String in text.strip_edges().to_lower().split(" ", false):
		var term: String = raw_term.strip_edges()
		if not term.is_empty() and not output.has(term):
			output.append(term)
	return output


func _score(entry: Dictionary, terms: PackedStringArray) -> int:
	if terms.is_empty():
		return 30
	var query_text: String = " ".join(terms)
	var record_id: String = String(entry.get("record_id", "")).to_lower()
	var field_name: String = String(entry.get("field_name", "")).to_lower()
	var scalar_text: String = String(entry.get("scalar_text", "")).to_lower()
	if record_id == query_text or scalar_text == query_text:
		return 0
	if record_id.begins_with(query_text) or scalar_text.begins_with(query_text):
		return 10
	if field_name == query_text:
		return 15
	return 20


func _sort_matches(left: Dictionary, right: Dictionary) -> bool:
	var left_key: String = "%03d|%s|%s|%08d|%s" % [
		int(left.get("score", 99)),
		String(left.get("dataset_id", "")),
		String(left.get("section_path", "")),
		int(left.get("record_index", -1)),
		String(left.get("field_path_text", "")),
	]
	var right_key: String = "%03d|%s|%s|%08d|%s" % [
		int(right.get("score", 99)),
		String(right.get("dataset_id", "")),
		String(right.get("section_path", "")),
		int(right.get("record_index", -1)),
		String(right.get("field_path_text", "")),
	]
	return left_key < right_key


func _path_text(path: Array) -> String:
	var output: String = ""
	for segment: Variant in path:
		if segment is int:
			output += "[%d]" % int(segment)
		elif output.is_empty():
			output = String(segment)
		else:
			output += ".%s" % String(segment)
	return output


func _scalar_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	return str(value)


func _value_type(value: Variant, infer_csv_scalar: bool = false) -> String:
	match typeof(value):
		TYPE_STRING:
			if infer_csv_scalar:
				var text: String = (value as String).strip_edges().to_lower()
				if text == "true" or text == "false":
					return "boolean"
				if text.is_valid_int() or text.is_valid_float():
					return "number"
			return "string"
		TYPE_INT, TYPE_FLOAT:
			return "number"
		TYPE_BOOL:
			return "boolean"
		TYPE_NIL:
			return "null"
		_:
			return "other"


func _summary(scalar_text: String, locale_text: String) -> String:
	var output: String = scalar_text
	if not locale_text.strip_edges().is_empty():
		output += " · %s" % locale_text.strip_edges()
	output = output.replace("\n", " ↵ ").replace("\r", "")
	return output.left(160)


func _error(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
