# Doc: docs/代码/data_table_editor.md
@tool
class_name DataTableDocument
extends RefCounted
## Editable JSON/CSV document with local history, linked locale rows, and drafts.

signal document_changed
signal document_loaded(dataset_id: String)
signal document_saved(dataset_id: String)

const DATA_TABLE_TRANSACTION := preload(
	"res://scripts/editor/data_table_transaction.gd"
)
const LOCALE_PATH: String = "res://locale/strings.csv"
const CONTRACTS_PATH: String = "res://data/_contracts.json"
const DRAFT_DIRECTORY: String = "user://data_table_editor/drafts"
const HISTORY_LIMIT: int = 100

var descriptor: Dictionary = {}
var data: Variant = {}
var csv_headers := PackedStringArray()
var locale_rows: Array[Dictionary] = []
var locale_headers := PackedStringArray(["keys", "zh_CN", "en"])
var pending_contract_changes: Array[Dictionary] = []
var dirty: bool = false
var locale_dirty: bool = false

var _source_hash: String = ""
var _locale_hash: String = ""
var _baseline_signature: String = ""
var _contract_values: Dictionary = {}
var _source_json_text: String = ""
var _source_json_baseline_signature: String = ""
var _source_json_array_styles: Dictionary = {}
var _source_json_number_lexemes: Dictionary = {}
var _source_json_number_signatures: Dictionary = {}
var _source_json_newline: String = "\n"
var _source_json_trailing_newline: bool = true
var _source_csv_layout: Dictionary = {}
var _locale_csv_layout: Dictionary = {}
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []


func open_dataset(next_descriptor: Dictionary) -> Dictionary:
	var recovery: Dictionary = DATA_TABLE_TRANSACTION.recover_pending_transaction()
	if not bool(recovery.get("ok", false)):
		return recovery
	descriptor = next_descriptor.duplicate(true)
	var path: String = source_path()
	var format: String = source_format()
	var load_result: Dictionary
	if format == "json":
		load_result = _load_json(path)
	else:
		load_result = _load_csv(path)
	if not bool(load_result.get("ok", false)):
		return load_result
	data = load_result.get("data", {})
	csv_headers = load_result.get("headers", PackedStringArray()) as PackedStringArray
	_source_json_text = ""
	_source_json_baseline_signature = ""
	_source_json_array_styles.clear()
	_source_json_number_lexemes.clear()
	_source_json_number_signatures.clear()
	_source_csv_layout.clear()
	if format == "json":
		_reset_json_layout(String(load_result.get("raw_text", "")), data)
	else:
		_source_csv_layout = _build_csv_layout(
			String(load_result.get("raw_text", "")), csv_headers, data as Array
		)
	_source_hash = _disk_hash(path)
	var locale_result: Dictionary = _load_csv(LOCALE_PATH)
	if not bool(locale_result.get("ok", false)):
		return locale_result
	locale_rows.clear()
	for raw_row: Variant in locale_result.get("data", []):
		if raw_row is Dictionary:
			locale_rows.append((raw_row as Dictionary).duplicate(true))
	locale_headers = locale_result.get("headers", locale_headers) as PackedStringArray
	_locale_csv_layout = _build_csv_layout(
		String(locale_result.get("raw_text", "")), locale_headers, locale_rows
	)
	_locale_hash = _disk_hash(LOCALE_PATH)
	_contract_values = _load_contract_values()
	pending_contract_changes.clear()
	_reset_history_and_baseline()
	document_loaded.emit(dataset_id())
	var result: Dictionary = _success_result()
	result["draft_status"] = draft_status()
	return result


func dataset_id() -> String:
	return String(descriptor.get("id", ""))


func source_path() -> String:
	return String(descriptor.get("path", ""))


func source_format() -> String:
	return String(descriptor.get("format", ""))


func section_descriptors() -> Array[Dictionary]:
	if source_format() == "csv":
		return [
			{
				"path": "$rows",
				"label": String(descriptor.get("label", dataset_id())),
				"primary_keys": descriptor.get("primary_keys", []),
			}
		]
	var raw_sections: Variant = descriptor.get("sections", [])
	var sections: Array[Dictionary] = []
	if raw_sections is Array:
		for raw_section: Variant in raw_sections as Array:
			if raw_section is Dictionary:
				var section: Dictionary = (raw_section as Dictionary).duplicate(true)
				if not section.has("label"):
					section["label"] = String(section.get("path", ""))
				sections.append(section)
	if sections.is_empty():
		sections.append(
			{
				"path": "$root",
				"label": String(descriptor.get("label", dataset_id())),
				"primary_keys": [],
			}
		)
	else:
		var root: Dictionary = data as Dictionary
		for key: Variant in root.keys():
			if key == "schema_version" or root[key] is Array:
				continue
			sections.push_front(
				{
					"path": "$root",
					"label": "全局设置",
					"primary_keys": [],
				}
			)
			break
	return sections


func records(section_path: String) -> Array:
	if section_path == "$rows":
		if data is Array:
			return data as Array
		return []
	if not data is Dictionary:
		return []
	if section_path == "$root":
		return [data as Dictionary]
	var value: Variant = (data as Dictionary).get(section_path, [])
	if value is Array:
		return value as Array
	return []


func record(section_path: String, index: int) -> Dictionary:
	var section_records: Array = records(section_path)
	if index < 0 or index >= section_records.size():
		return {}
	var value: Variant = section_records[index]
	if value is Dictionary:
		return value as Dictionary
	return {}


func primary_keys(section_path: String) -> Array[String]:
	for section: Dictionary in section_descriptors():
		if String(section.get("path", "")) != section_path:
			continue
		return _string_array(section.get("primary_keys", []))
	return []


func record_identity(section_path: String, index: int) -> String:
	var current: Dictionary = record(section_path, index)
	var parts := PackedStringArray()
	for key: String in primary_keys(section_path):
		parts.append(String(current.get(key, "")))
	if parts.is_empty():
		return "#%d" % index
	return "/".join(parts)


func set_record_value(
	section_path: String,
	record_index: int,
	value_path: Array,
	value: Variant
) -> bool:
	var current: Dictionary = record(section_path, record_index)
	if current.is_empty() or value_path.is_empty():
		return false
	if (
		value_path.size() == 1
		and primary_keys(section_path).has(String(value_path[0]))
		and not String(current.get(String(value_path[0]), "")).is_empty()
	):
		return false
	var original: Variant = _value_at_path(current, value_path)
	if not _can_convert_value(value, original):
		return false
	var converted: Variant = _convert_value(value, original)
	if not _field_value_is_valid(value_path, converted):
		return false
	if original == converted:
		return true
	_push_undo_state()
	if not _set_value_at_path(current, value_path, converted):
		_undo_stack.pop_back()
		return false
	if _has_duplicate_primary_keys(section_path):
		_apply_snapshot(_undo_stack.pop_back())
		return false
	_mark_changed()
	return true


func append_array_value(
	section_path: String,
	record_index: int,
	value_path: Array
) -> bool:
	var current: Dictionary = record(section_path, record_index)
	var value: Variant = _value_at_path(current, value_path)
	if not value is Array:
		return false
	_push_undo_state()
	var values: Array = value as Array
	values.append(_default_value(values[0]) if not values.is_empty() else {})
	_mark_changed()
	return true


func remove_array_value(
	section_path: String,
	record_index: int,
	value_path: Array,
	array_index: int
) -> bool:
	var current: Dictionary = record(section_path, record_index)
	var value: Variant = _value_at_path(current, value_path)
	if not value is Array:
		return false
	var values: Array = value as Array
	if array_index < 0 or array_index >= values.size():
		return false
	_push_undo_state()
	values.remove_at(array_index)
	_mark_changed()
	return true


func append_record(
	section_path: String,
	requested_id: String = "",
	copy_index: int = -1,
	contract_meaning: String = ""
) -> int:
	if section_path == "$root":
		return -1
	var section_records: Array = records(section_path)
	var template: Dictionary = {}
	if copy_index >= 0 and copy_index < section_records.size():
		var copied: Variant = section_records[copy_index]
		if copied is Dictionary:
			template = (copied as Dictionary).duplicate(true)
	else:
		var sample: Variant = section_records[0] if not section_records.is_empty() else null
		var default_template: Variant = _configured_default_template(section_path, sample)
		if default_template is Dictionary:
			template = default_template as Dictionary
	var keys: Array[String] = primary_keys(section_path)
	var requested_parts := PackedStringArray()
	if not keys.is_empty():
		if requested_id.is_empty():
			return -1
		requested_parts = requested_id.split("/", true)
		if requested_parts.size() != keys.size():
			return -1
		for part: String in requested_parts:
			if part.strip_edges().is_empty():
				return -1
	_push_undo_state()
	for key_index: int in range(keys.size()):
		template[keys[key_index]] = requested_parts[key_index].strip_edges()
	_clone_locale_keys_for_new_record(template, requested_id)
	section_records.append(template)
	if _has_duplicate_primary_keys(section_path):
		_apply_snapshot(_undo_stack.pop_back())
		return -1
	if source_path() == LOCALE_PATH:
		data = section_records
	var contract_key: String = _contract_key(section_path)
	if not contract_key.is_empty() and not requested_id.is_empty():
		_queue_contract_change(
			{
				"action": "register",
				"contract_key": contract_key,
				"id": requested_id,
				"meaning": contract_meaning if not contract_meaning.is_empty() else requested_id,
			}
		)
	_mark_changed()
	return section_records.size() - 1


func delete_record(
	section_path: String,
	record_index: int,
	locale_keys_to_remove: PackedStringArray = PackedStringArray()
) -> bool:
	if section_path == "$root":
		return false
	var section_records: Array = records(section_path)
	if record_index < 0 or record_index >= section_records.size():
		return false
	var removed: Dictionary = record(section_path, record_index).duplicate(true)
	_push_undo_state()
	section_records.remove_at(record_index)
	_remove_locale_rows(locale_keys_to_remove)
	var contract_key: String = _contract_key(section_path)
	var keys: Array[String] = primary_keys(section_path)
	if not contract_key.is_empty() and keys.size() == 1:
		var removed_id: String = String(removed.get(keys[0], ""))
		if not removed_id.is_empty():
			_queue_contract_change(
				{
					"action": "unregister",
					"contract_key": contract_key,
					"id": removed_id,
				}
			)
	_mark_changed()
	return true


func locale_value(key: String, language: String) -> String:
	if key.is_empty():
		return ""
	for row: Dictionary in _active_locale_rows():
		if String(row.get("keys", "")) == key:
			return String(row.get(language, ""))
	return ""


func set_locale_value(key: String, language: String, text: String) -> bool:
	if key.is_empty() or (language != "zh_CN" and language != "en"):
		return false
	var rows: Array = data as Array if source_path() == LOCALE_PATH and data is Array else locale_rows
	for raw_row: Variant in rows:
		if not raw_row is Dictionary:
			continue
		var row: Dictionary = raw_row as Dictionary
		if String(row.get("keys", "")) == key:
			if String(row.get(language, "")) == text:
				return true
			_push_undo_state()
			row[language] = text
			locale_dirty = source_path() != LOCALE_PATH
			_mark_changed()
			return true
	_push_undo_state()
	rows.append({"keys": key, "zh_CN": "", "en": ""})
	rows[-1][language] = text
	locale_dirty = source_path() != LOCALE_PATH
	_mark_changed()
	return true


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_redo_stack.append(_snapshot())
	_apply_snapshot(_undo_stack.pop_back())
	_mark_changed()
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	_undo_stack.append(_snapshot())
	_apply_snapshot(_redo_stack.pop_back())
	_mark_changed()
	return true


func paste_tsv(
	section_path: String,
	start_record_index: int,
	column_paths: Array[Array],
	text: String
) -> Dictionary:
	var lines: PackedStringArray = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	while not lines.is_empty() and String(lines[-1]).is_empty():
		lines.remove_at(lines.size() - 1)
	if lines.is_empty() or column_paths.is_empty():
		return _error_result("TSV paste has no cells")
	var section_records: Array = records(section_path)
	if start_record_index < 0 or start_record_index + lines.size() > section_records.size():
		return _error_result("TSV paste exceeds existing rows")
	_push_undo_state()
	for row_offset: int in range(lines.size()):
		var values: PackedStringArray = String(lines[row_offset]).split("\t", true)
		var current: Dictionary = record(section_path, start_record_index + row_offset)
		for column_offset: int in range(mini(values.size(), column_paths.size())):
			var path: Array = column_paths[column_offset]
			if path.is_empty():
				continue
			if (
				path.size() == 1
				and primary_keys(section_path).has(String(path[0]))
				and not String(current.get(String(path[0]), "")).is_empty()
			):
				continue
			var original: Variant = _value_at_path(current, path)
			if not _can_convert_value(values[column_offset], original):
				_apply_snapshot(_undo_stack.pop_back())
				return _error_result("TSV paste contains an invalid typed value")
			var converted: Variant = _convert_value(values[column_offset], original)
			if not _field_value_is_valid(path, converted):
				_apply_snapshot(_undo_stack.pop_back())
				return _error_result("TSV paste violates a field type or range rule")
			_set_value_at_path(current, path, converted)
	if _has_duplicate_primary_keys(section_path):
		_apply_snapshot(_undo_stack.pop_back())
		return _error_result("TSV paste creates a duplicate primary or composite key")
	_mark_changed()
	return _success_result()


func has_undo() -> bool:
	return not _undo_stack.is_empty()


func has_redo() -> bool:
	return not _redo_stack.is_empty()


func save_project(
	before_validate: Callable = Callable(),
	extra_paths: Array[String] = [],
	allow_external_override: bool = false
) -> Dictionary:
	var source_output: String = source_text()
	var locale_output: String = ""
	var writes: Dictionary = {source_path(): source_output}
	var expected_hashes: Dictionary = {}
	if not allow_external_override:
		expected_hashes[source_path()] = _source_hash
	if locale_dirty and source_path() != LOCALE_PATH:
		locale_output = _csv_text_preserving_layout(
			locale_headers, locale_rows, _locale_csv_layout
		)
		writes[LOCALE_PATH] = locale_output
		if not allow_external_override:
			expected_hashes[LOCALE_PATH] = _locale_hash
	var result: Dictionary = DATA_TABLE_TRANSACTION.commit_texts(
		writes,
		expected_hashes,
		extra_paths,
		before_validate
	)
	if not bool(result.get("ok", false)):
		return result
	_source_hash = _disk_hash(source_path())
	_locale_hash = _disk_hash(LOCALE_PATH)
	if source_format() == "json":
		_reset_json_layout(source_output, data)
	else:
		_source_csv_layout = _build_csv_layout(source_output, csv_headers, data as Array)
	if source_path() == LOCALE_PATH:
		_locale_csv_layout = _source_csv_layout.duplicate(true)
	elif not locale_output.is_empty():
		_locale_csv_layout = _build_csv_layout(
			locale_output, locale_headers, locale_rows
		)
	pending_contract_changes.clear()
	_reset_history_and_baseline()
	discard_draft()
	document_saved.emit(dataset_id())
	return result


func disk_changed() -> bool:
	if descriptor.is_empty():
		return false
	if _disk_hash(source_path()) != _source_hash:
		return true
	return source_path() != LOCALE_PATH and _disk_hash(LOCALE_PATH) != _locale_hash


func source_text() -> String:
	if source_format() == "json":
		if (
			not _source_json_text.is_empty()
			and _json_state_signature(data) == _source_json_baseline_signature
		):
			return _source_json_text
		var output: String = _json_encode(data, 0, [])
		if _source_json_trailing_newline:
			output += _source_json_newline
		return output
	return _csv_text_preserving_layout(csv_headers, data as Array, _source_csv_layout)


func save_draft() -> Dictionary:
	if descriptor.is_empty():
		return _error_result("no dataset is open")
	var make_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(DRAFT_DIRECTORY)
	)
	if make_error != OK:
		return _error_result("failed to create data-table draft directory")
	var file: FileAccess = FileAccess.open(_draft_path(), FileAccess.WRITE)
	if file == null:
		return _error_result("failed to write data-table draft")
	file.store_string(
		JSON.stringify(
			{
				"schema_version": 1,
				"dataset_id": dataset_id(),
				"source_hash": _source_hash,
				"locale_hash": _locale_hash,
				"data": data,
				"csv_headers": Array(csv_headers),
				"locale_rows": locale_rows,
				"locale_headers": Array(locale_headers),
				"pending_contract_changes": pending_contract_changes,
			},
			"  ",
			false,
			true
		)
		+ "\n"
	)
	file.close()
	return _success_result()


func draft_status() -> String:
	if not FileAccess.file_exists(_draft_path()):
		return "none"
	var draft_result: Dictionary = _load_json(_draft_path())
	if not bool(draft_result.get("ok", false)):
		return "invalid"
	var draft: Dictionary = draft_result.get("data", {}) as Dictionary
	if (
		String(draft.get("source_hash", "")) == _disk_hash(source_path())
		and String(draft.get("locale_hash", "")) == _disk_hash(LOCALE_PATH)
	):
		return "matching"
	return "conflict"


func restore_draft(allow_conflict: bool = false) -> Dictionary:
	var status: String = draft_status()
	if status == "none":
		return _error_result("no draft is available")
	if status == "conflict" and not allow_conflict:
		return _error_result("draft base changed; explicit conflict approval is required")
	var draft_result: Dictionary = _load_json(_draft_path())
	if not bool(draft_result.get("ok", false)):
		return draft_result
	var draft: Dictionary = draft_result.get("data", {}) as Dictionary
	data = _deep_duplicate(draft.get("data", {}))
	csv_headers = PackedStringArray(draft.get("csv_headers", []))
	locale_rows.clear()
	for raw_row: Variant in draft.get("locale_rows", []):
		if raw_row is Dictionary:
			locale_rows.append((raw_row as Dictionary).duplicate(true))
	locale_headers = PackedStringArray(draft.get("locale_headers", []))
	pending_contract_changes.clear()
	for raw_change: Variant in draft.get("pending_contract_changes", []):
		if raw_change is Dictionary:
			pending_contract_changes.append((raw_change as Dictionary).duplicate(true))
	_undo_stack.clear()
	_redo_stack.clear()
	dirty = true
	locale_dirty = source_path() != LOCALE_PATH
	document_changed.emit()
	return _success_result()


func discard_draft() -> void:
	if not FileAccess.file_exists(_draft_path()):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_draft_path()))


func _active_locale_rows() -> Array[Dictionary]:
	if source_path() == LOCALE_PATH and data is Array:
		var typed_rows: Array[Dictionary] = []
		for raw_row: Variant in data as Array:
			if raw_row is Dictionary:
				typed_rows.append(raw_row as Dictionary)
		return typed_rows
	return locale_rows


func _clone_locale_keys_for_new_record(record_data: Dictionary, requested_id: String) -> void:
	if requested_id.is_empty():
		return
	var raw_fields: Variant = descriptor.get("locale_fields", [])
	if not raw_fields is Array:
		return
	for raw_field: Variant in raw_fields as Array:
		var field: String = String(raw_field)
		if not record_data.has(field):
			continue
		var old_key: String = String(record_data.get(field, ""))
		var suffix: String = field.trim_suffix("_key")
		var new_key: String = "%s_%s" % [requested_id, suffix]
		record_data[field] = new_key
		var zh_text: String = locale_value(old_key, "zh_CN")
		var en_text: String = locale_value(old_key, "en")
		locale_rows.append({"keys": new_key, "zh_CN": zh_text, "en": en_text})
		locale_dirty = true


func _remove_locale_rows(locale_keys: PackedStringArray) -> void:
	for locale_key: String in locale_keys:
		for index: int in range(locale_rows.size() - 1, -1, -1):
			if String(locale_rows[index].get("keys", "")) == locale_key:
				locale_rows.remove_at(index)
				locale_dirty = true


func _contract_key(section_path: String) -> String:
	for section: Dictionary in section_descriptors():
		if String(section.get("path", "")) == section_path:
			return String(section.get("contract_key", ""))
	return ""


func _has_duplicate_primary_keys(section_path: String) -> bool:
	var keys: Array[String] = primary_keys(section_path)
	if keys.is_empty():
		return false
	var identities: Dictionary = {}
	var section_records: Array = records(section_path)
	for raw_record: Variant in section_records:
		if not raw_record is Dictionary:
			continue
		var current: Dictionary = raw_record as Dictionary
		var parts := PackedStringArray()
		var complete: bool = true
		for key: String in keys:
			var part: String = String(current.get(key, "")).strip_edges()
			if part.is_empty():
				complete = false
				break
			parts.append(part)
		if not complete:
			continue
		var identity: String = "\u001f".join(parts)
		if identities.has(identity):
			return true
		identities[identity] = true
	return false


func _queue_contract_change(change: Dictionary) -> void:
	var action: String = String(change.get("action", ""))
	var opposite: String = "unregister" if action == "register" else "register"
	for index: int in range(pending_contract_changes.size() - 1, -1, -1):
		var existing: Dictionary = pending_contract_changes[index]
		if (
			String(existing.get("contract_key", "")) == String(change.get("contract_key", ""))
			and String(existing.get("id", "")) == String(change.get("id", ""))
		):
			if String(existing.get("action", "")) == opposite:
				pending_contract_changes.remove_at(index)
				return
			if String(existing.get("action", "")) == action:
				return
	pending_contract_changes.append(change.duplicate(true))


func _push_undo_state() -> void:
	_undo_stack.append(_snapshot())
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _snapshot() -> Dictionary:
	return {
		"data": _deep_duplicate(data),
		"csv_headers": Array(csv_headers),
		"locale_rows": locale_rows.duplicate(true),
		"locale_headers": Array(locale_headers),
		"pending_contract_changes": pending_contract_changes.duplicate(true),
	}


func _apply_snapshot(snapshot: Dictionary) -> void:
	data = _deep_duplicate(snapshot.get("data", {}))
	csv_headers = PackedStringArray(snapshot.get("csv_headers", []))
	locale_rows.clear()
	for raw_row: Variant in snapshot.get("locale_rows", []):
		if raw_row is Dictionary:
			locale_rows.append((raw_row as Dictionary).duplicate(true))
	locale_headers = PackedStringArray(snapshot.get("locale_headers", []))
	pending_contract_changes.clear()
	for raw_change: Variant in snapshot.get("pending_contract_changes", []):
		if raw_change is Dictionary:
			pending_contract_changes.append((raw_change as Dictionary).duplicate(true))


func _mark_changed(write_draft: bool = true) -> void:
	dirty = _signature() != _baseline_signature
	if write_draft and dirty:
		save_draft()
	elif not dirty:
		discard_draft()
	document_changed.emit()


func _reset_history_and_baseline() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	_baseline_signature = _signature()
	dirty = false
	locale_dirty = false


func _signature() -> String:
	return JSON.stringify(
		{
			"data": data,
			"locale_rows": locale_rows if source_path() != LOCALE_PATH else [],
			"pending_contract_changes": pending_contract_changes,
		},
		"",
		false,
		true
	)


func _value_at_path(root: Variant, path: Array) -> Variant:
	var cursor: Variant = root
	for segment: Variant in path:
		if cursor is Dictionary:
			cursor = (cursor as Dictionary).get(String(segment))
		elif cursor is Array and segment is int:
			var index: int = int(segment)
			if index < 0 or index >= (cursor as Array).size():
				return null
			cursor = (cursor as Array)[index]
		else:
			return null
	return cursor


func _set_value_at_path(root: Variant, path: Array, value: Variant) -> bool:
	var cursor: Variant = root
	for index: int in range(path.size() - 1):
		var segment: Variant = path[index]
		if cursor is Dictionary:
			cursor = (cursor as Dictionary).get(String(segment))
		elif cursor is Array and segment is int:
			cursor = (cursor as Array)[int(segment)]
		else:
			return false
	var final_segment: Variant = path[-1]
	if cursor is Dictionary:
		(cursor as Dictionary)[String(final_segment)] = value
		return true
	if cursor is Array and final_segment is int:
		(cursor as Array)[int(final_segment)] = value
		return true
	return false


func _convert_value(value: Variant, original: Variant) -> Variant:
	if not value is String:
		return value
	var text: String = (value as String).strip_edges()
	match typeof(original):
		TYPE_BOOL:
			return text.to_lower() == "true" or text == "1"
		TYPE_INT:
			return int(text)
		TYPE_FLOAT:
			return float(text)
		_:
			return text


func _can_convert_value(value: Variant, original: Variant) -> bool:
	if not value is String:
		return true
	var text: String = (value as String).strip_edges()
	match typeof(original):
		TYPE_BOOL:
			return ["true", "false", "1", "0"].has(text.to_lower())
		TYPE_INT:
			return text.is_valid_int()
		TYPE_FLOAT:
			return text.is_valid_float()
		_:
			return true


func _default_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var output: Dictionary = {}
			for key: Variant in (value as Dictionary).keys():
				output[key] = _default_value((value as Dictionary)[key])
			return output
		TYPE_ARRAY:
			return []
		TYPE_BOOL:
			return false
		TYPE_INT:
			return 0
		TYPE_FLOAT:
			return 0.0
		TYPE_STRING:
			return ""
		_:
			return null


func _configured_default_template(section_path: String, sample: Variant) -> Variant:
	for section: Dictionary in section_descriptors():
		if String(section.get("path", "")) != section_path:
			continue
		if section.get("default_template", null) is Dictionary:
			return (section.get("default_template", {}) as Dictionary).duplicate(true)
	if descriptor.get("default_template", null) is Dictionary:
		return (descriptor.get("default_template", {}) as Dictionary).duplicate(true)
	return _default_value(sample)


func _field_value_is_valid(value_path: Array, value: Variant) -> bool:
	var path_text: String = _rule_path(value_path)
	var raw_rules: Variant = descriptor.get("field_rules", [])
	if not raw_rules is Array:
		return true
	for raw_rule: Variant in raw_rules as Array:
		if not raw_rule is Dictionary:
			continue
		var rule: Dictionary = raw_rule as Dictionary
		if String(rule.get("path", "")) != path_text:
			continue
		var expected_type: String = String(rule.get("type", ""))
		if expected_type == "number" and not (
			value is int or value is float or (value is String and (value as String).is_valid_float())
		):
			return false
		if expected_type == "string" and not value is String:
			return false
		if expected_type == "boolean" and not value is bool:
			return false
		if expected_type == "array" and not value is Array:
			return false
		if expected_type == "object" and not value is Dictionary:
			return false
		if rule.has("min") and float(value) < float(rule.get("min", 0.0)):
			return false
		if rule.has("max") and float(value) > float(rule.get("max", 0.0)):
			return false
		var raw_values: Variant = rule.get("values", [])
		if raw_values is Array and not (raw_values as Array).is_empty() and not (raw_values as Array).has(value):
			return false
	var raw_references: Variant = descriptor.get("references", [])
	if not raw_references is Array:
		return true
	for raw_reference: Variant in raw_references as Array:
		if not raw_reference is Dictionary:
			continue
		var reference: Dictionary = raw_reference as Dictionary
		if String(reference.get("path", "")) != path_text:
			continue
		var target: String = String(reference.get("target", ""))
		if not target.begins_with("contract:"):
			continue
		var contract_key: String = target.trim_prefix("contract:")
		var options: Variant = _contract_values.get(contract_key, [])
		if not options is Array or not (options as Array).has(value):
			return false
	return true


func _rule_path(value_path: Array) -> String:
	var output: String = ""
	for segment: Variant in value_path:
		if segment is int:
			output += "[]"
		elif output.is_empty():
			output = String(segment)
		else:
			output += ".%s" % String(segment)
	return output


func _deep_duplicate(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error_result("missing JSON file: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error_result("failed to open JSON file: %s" % path)
	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if not parsed is Dictionary:
		return _error_result("JSON root must be a Dictionary: %s" % path)
	var number_tokens: PackedStringArray = _json_number_tokens(raw_text)
	var number_cursor: Dictionary = {"index": 0}
	parsed = _restore_json_number_types(parsed, number_tokens, number_cursor)
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"data": parsed,
		"headers": PackedStringArray(),
		"raw_text": raw_text,
	}


func _reset_json_layout(raw_text: String, value: Variant) -> void:
	_source_json_text = raw_text
	_source_json_baseline_signature = _json_state_signature(value)
	_source_json_newline = "\r\n" if raw_text.contains("\r\n") else "\n"
	_source_json_trailing_newline = raw_text.ends_with("\n") or raw_text.ends_with("\r")
	_source_json_array_styles.clear()
	_collect_json_array_styles(value, [], raw_text)
	_source_json_number_lexemes.clear()
	_source_json_number_signatures.clear()
	var number_tokens: PackedStringArray = _json_number_tokens(raw_text)
	var number_cursor: Dictionary = {"index": 0}
	_collect_json_number_layout(value, [], number_tokens, number_cursor)


func _json_state_signature(value: Variant) -> String:
	return JSON.stringify(value, "", false, true)


func _json_number_tokens(raw_text: String) -> PackedStringArray:
	var tokens := PackedStringArray()
	var inside_string: bool = false
	var escaped: bool = false
	var index: int = 0
	while index < raw_text.length():
		var character: String = raw_text.substr(index, 1)
		if inside_string:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == "\"":
				inside_string = false
			index += 1
			continue
		if character == "\"":
			inside_string = true
			index += 1
			continue
		if character == "-" or (character >= "0" and character <= "9"):
			var start: int = index
			index += 1
			while index < raw_text.length():
				var next_character: String = raw_text.substr(index, 1)
				if not (
					(next_character >= "0" and next_character <= "9")
					or [".", "e", "E", "+", "-"].has(next_character)
				):
					break
				index += 1
			tokens.append(raw_text.substr(start, index - start))
			continue
		index += 1
	return tokens


func _restore_json_number_types(
	value: Variant,
	tokens: PackedStringArray,
	cursor: Dictionary
) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		for raw_key: Variant in dictionary.keys():
			var key: String = String(raw_key)
			dictionary[key] = _restore_json_number_types(dictionary[key], tokens, cursor)
		return dictionary
	if value is Array:
		var array: Array = value as Array
		for index: int in range(array.size()):
			array[index] = _restore_json_number_types(array[index], tokens, cursor)
		return array
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return value
	var token_index: int = int(cursor.get("index", 0))
	cursor["index"] = token_index + 1
	if token_index >= tokens.size():
		return value
	var token: String = tokens[token_index]
	if token.is_valid_int() and not token.contains(".") and not token.to_lower().contains("e"):
		return token.to_int()
	return token.to_float()


func _collect_json_array_styles(value: Variant, path: Array, raw_text: String) -> void:
	if value is Dictionary:
		for raw_key: Variant in (value as Dictionary).keys():
			var key: String = String(raw_key)
			var child_path: Array = path.duplicate()
			child_path.append(key)
			_collect_json_array_styles((value as Dictionary)[key], child_path, raw_text)
		return
	if not value is Array:
		return
	var array: Array = value as Array
	var path_key: String = JSON.stringify(path)
	if _json_array_is_scalar(array):
		var compact: String = _json_inline_array(array, false, path)
		var spaced: String = _json_inline_array(array, true, path)
		if raw_text.contains(spaced):
			_source_json_array_styles[path_key] = "inline_spaced"
		elif raw_text.contains(compact):
			_source_json_array_styles[path_key] = "inline_compact"
		else:
			_source_json_array_styles[path_key] = "multiline"
	for index: int in range(array.size()):
		var child_path: Array = path.duplicate()
		child_path.append(index)
		_collect_json_array_styles(array[index], child_path, raw_text)


func _collect_json_number_layout(
	value: Variant,
	path: Array,
	tokens: PackedStringArray,
	cursor: Dictionary
) -> void:
	if value is Dictionary:
		for raw_key: Variant in (value as Dictionary).keys():
			var key: String = String(raw_key)
			var child_path: Array = path.duplicate()
			child_path.append(key)
			_collect_json_number_layout((value as Dictionary)[key], child_path, tokens, cursor)
		return
	if value is Array:
		for index: int in range((value as Array).size()):
			var child_path: Array = path.duplicate()
			child_path.append(index)
			_collect_json_number_layout((value as Array)[index], child_path, tokens, cursor)
		return
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return
	var token_index: int = int(cursor.get("index", 0))
	cursor["index"] = token_index + 1
	if token_index >= tokens.size():
		return
	var path_key: String = JSON.stringify(path)
	_source_json_number_lexemes[path_key] = tokens[token_index]
	_source_json_number_signatures[path_key] = JSON.stringify(value)


func _json_encode(value: Variant, depth: int, path: Array) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		if dictionary.is_empty():
			return "{}"
		var entries := PackedStringArray()
		for raw_key: Variant in dictionary.keys():
			var key: String = String(raw_key)
			var child_path: Array = path.duplicate()
			child_path.append(key)
			entries.append(
				"%s%s: %s"
				% [
					"  ".repeat(depth + 1),
					JSON.stringify(key),
					_json_encode(dictionary[key], depth + 1, child_path),
				]
			)
		return (
			"{" + _source_json_newline
			+ ("," + _source_json_newline).join(entries)
			+ _source_json_newline + "  ".repeat(depth) + "}"
		)
	if value is Array:
		var array: Array = value as Array
		if array.is_empty():
			return "[]"
		var style: String = String(
			_source_json_array_styles.get(JSON.stringify(path), "inline_spaced")
		)
		if _json_array_is_scalar(array) and style.begins_with("inline"):
			return _json_inline_array(array, style == "inline_spaced", path)
		var entries := PackedStringArray()
		for index: int in range(array.size()):
			var child_path: Array = path.duplicate()
			child_path.append(index)
			entries.append(
				"  ".repeat(depth + 1) + _json_encode(array[index], depth + 1, child_path)
			)
		return (
			"[" + _source_json_newline
			+ ("," + _source_json_newline).join(entries)
			+ _source_json_newline + "  ".repeat(depth) + "]"
		)
	return _json_scalar_text(value, path)


func _json_array_is_scalar(array: Array) -> bool:
	for value: Variant in array:
		if value is Dictionary or value is Array:
			return false
	return true


func _json_inline_array(array: Array, spaced: bool, path: Array) -> String:
	var values := PackedStringArray()
	for index: int in range(array.size()):
		var child_path: Array = path.duplicate()
		child_path.append(index)
		values.append(_json_scalar_text(array[index], child_path))
	return "[" + (", " if spaced else ",").join(values) + "]"


func _json_scalar_text(value: Variant, path: Array) -> String:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		var path_key: String = JSON.stringify(path)
		if (
			_source_json_number_lexemes.has(path_key)
			and String(_source_json_number_signatures.get(path_key, ""))
			== JSON.stringify(value)
		):
			return String(_source_json_number_lexemes[path_key])
	return JSON.stringify(value)


func _load_contract_values() -> Dictionary:
	if not FileAccess.file_exists(CONTRACTS_PATH):
		return {}
	var file: FileAccess = FileAccess.open(CONTRACTS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var contracts: Variant = (parsed as Dictionary).get("contracts", {})
	return (contracts as Dictionary).duplicate(true) if contracts is Dictionary else {}


func _load_csv(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error_result("missing CSV file: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error_result("failed to open CSV file: %s" % path)
	var raw_text: String = file.get_as_text()
	file.seek(0)
	var headers: PackedStringArray = file.get_csv_line()
	var rows: Array[Dictionary] = []
	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 1 and String(values[0]).is_empty():
			continue
		if values.size() > headers.size():
			return _error_result(
				"CSV record %d in %s has %d columns; expected %d. Quote values containing commas."
				% [rows.size() + 2, path, values.size(), headers.size()]
			)
		var row: Dictionary = {}
		for index: int in range(headers.size()):
			row[String(headers[index])] = values[index] if index < values.size() else ""
		rows.append(row)
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"data": rows,
		"headers": headers,
		"raw_text": raw_text,
	}


func _csv_text(headers: PackedStringArray, rows: Array) -> String:
	var lines := PackedStringArray()
	lines.append(_csv_line(Array(headers)))
	for raw_row: Variant in rows:
		if not raw_row is Dictionary:
			continue
		var row: Dictionary = raw_row as Dictionary
		var values: Array[String] = []
		for header: String in headers:
			values.append(String(row.get(header, "")))
		lines.append(_csv_line(values))
	return "\n".join(lines) + "\n"


func _csv_text_preserving_layout(
	headers: PackedStringArray,
	rows: Array,
	layout: Dictionary
) -> String:
	if layout.is_empty():
		return _csv_text(headers, rows)
	var baseline_headers := PackedStringArray(layout.get("headers", []))
	var baseline_rows: Array = layout.get("rows", []) as Array
	if (
		headers == baseline_headers
		and _csv_state_signature(headers, rows)
		== _csv_state_signature(baseline_headers, baseline_rows)
	):
		return String(layout.get("raw_text", _csv_text(headers, rows)))
	var lines := PackedStringArray()
	var headers_match: bool = headers == baseline_headers
	var raw_header: String = String(layout.get("raw_header", ""))
	lines.append(raw_header if headers_match and not raw_header.is_empty() else _csv_line(Array(headers)))
	var available_raw_records: Dictionary = {}
	if headers_match:
		var raw_records: Array = layout.get("raw_records", []) as Array
		for index: int in range(mini(baseline_rows.size(), raw_records.size())):
			if not baseline_rows[index] is Dictionary:
				continue
			var signature: String = _csv_row_signature(
				baseline_headers, baseline_rows[index] as Dictionary
			)
			var bucket: Array = available_raw_records.get(signature, []) as Array
			bucket.append(String(raw_records[index]))
			available_raw_records[signature] = bucket
	for raw_row: Variant in rows:
		if not raw_row is Dictionary:
			continue
		var row: Dictionary = raw_row as Dictionary
		var signature: String = _csv_row_signature(headers, row)
		var bucket: Array = available_raw_records.get(signature, []) as Array
		if not bucket.is_empty():
			lines.append(String(bucket.pop_front()))
			available_raw_records[signature] = bucket
			continue
		var values: Array[String] = []
		for header: String in headers:
			values.append(String(row.get(header, "")))
		lines.append(_csv_line(values))
	var line_ending: String = String(layout.get("line_ending", "\n"))
	var output: String = line_ending.join(lines)
	if bool(layout.get("trailing_newline", true)):
		output += line_ending
	return output


func _build_csv_layout(
	raw_text: String,
	headers: PackedStringArray,
	rows: Array
) -> Dictionary:
	var records: Array[String] = _split_csv_records(raw_text)
	var raw_records: Array[String] = []
	for index: int in range(1, records.size()):
		if not records[index].is_empty():
			raw_records.append(records[index])
	return {
		"raw_text": raw_text,
		"raw_header": records[0] if not records.is_empty() else "",
		"raw_records": raw_records,
		"line_ending": "\r\n" if raw_text.contains("\r\n") else "\n",
		"trailing_newline": raw_text.ends_with("\n") or raw_text.ends_with("\r"),
		"headers": Array(headers),
		"rows": _deep_duplicate(rows),
	}


func _split_csv_records(raw_text: String) -> Array[String]:
	var records: Array[String] = []
	var current: String = ""
	var inside_quotes: bool = false
	var index: int = 0
	while index < raw_text.length():
		var character: String = raw_text.substr(index, 1)
		if character == "\"":
			current += character
			if (
				inside_quotes
				and index + 1 < raw_text.length()
				and raw_text.substr(index + 1, 1) == "\""
			):
				current += "\""
				index += 2
				continue
			inside_quotes = not inside_quotes
		elif character == "\n" and not inside_quotes:
			records.append(current.trim_suffix("\r"))
			current = ""
		else:
			current += character
		index += 1
	if not current.is_empty() or not raw_text.ends_with("\n"):
		records.append(current.trim_suffix("\r"))
	return records


func _csv_state_signature(headers: PackedStringArray, rows: Array) -> String:
	return JSON.stringify(
		{"headers": Array(headers), "rows": rows}, "", false, true
	)


func _csv_row_signature(headers: PackedStringArray, row: Dictionary) -> String:
	var values: Array[String] = []
	for header: String in headers:
		values.append(String(row.get(header, "")))
	return JSON.stringify(values)


func _csv_line(values: Array) -> String:
	var encoded := PackedStringArray()
	for raw_value: Variant in values:
		var value: String = String(raw_value)
		if value.contains(",") or value.contains("\"") or value.contains("\n") or value.contains("\r"):
			value = "\"%s\"" % value.replace("\"", "\"\"")
		encoded.append(value)
	return ",".join(encoded)


func _draft_path() -> String:
	return DRAFT_DIRECTORY.path_join("%s.json" % dataset_id())


func _disk_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


func _string_array(raw_value: Variant) -> Array[String]:
	var values: Array[String] = []
	if raw_value is Array:
		for value: Variant in raw_value as Array:
			values.append(String(value))
	return values


func _success_result() -> Dictionary:
	return {"ok": true, "errors": PackedStringArray()}


func _error_result(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
