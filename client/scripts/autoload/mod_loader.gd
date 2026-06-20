# Doc: docs/代码/mod_loader.md
# Authority: docs/游戏设计文档.md §9.21, docs/决策记录.md ADR #83
class_name ModLoaderAutoload
extends Node


signal mods_reloaded()

const ALLOWED_CONTRACT_EXTENSION_KEYS: Array[String] = [
	"character_ids",
	"content_tags",
	"game_modes",
	"locale_prefixes",
]
const MANIFEST_FILE_NAME: String = "mod.json"
const MODS_ROOT: String = "user://mods"
const MOD_ID_PATTERN: String = "^[a-z0-9_]+$"
const SUPPORTED_PATCH_TYPES: Array[String] = [
	"csv_append",
	"json_array_append",
]
const SUPPORTED_SCHEMA_VERSION: int = 1

var _diagnostics: Array[String] = []
var _enabled_mods: Array[Dictionary] = []


func _ready() -> void:
	reload_mods()


func reload_mods() -> void:
	_enabled_mods.clear()
	_diagnostics.clear()
	_ensure_mods_root()

	var mods_dir: DirAccess = DirAccess.open(MODS_ROOT)
	if mods_dir == null:
		_add_diagnostic("%s is not readable" % MODS_ROOT)
		mods_reloaded.emit()
		return

	mods_dir.list_dir_begin()
	var entry_name: String = mods_dir.get_next()
	while not entry_name.is_empty():
		if mods_dir.current_is_dir() and not entry_name.begins_with("."):
			_load_mod_directory(MODS_ROOT.path_join(entry_name))
		entry_name = mods_dir.get_next()
	mods_dir.list_dir_end()

	_enabled_mods.sort_custom(_sort_mods_by_load_order)
	mods_reloaded.emit()


func enabled_mod_count() -> int:
	return _enabled_mods.size()


func enabled_mods() -> Array[Dictionary]:
	return _enabled_mods.duplicate(true)


func diagnostics() -> Array[String]:
	return _diagnostics.duplicate()


func contract_extensions(contract_key: String) -> Array[String]:
	var extensions: Array[String] = []
	for mod: Dictionary in _enabled_mods:
		var mod_extensions: Dictionary = mod.get("contract_extensions", {}) as Dictionary
		if not mod_extensions.has(contract_key):
			continue
		var values: Variant = mod_extensions[contract_key]
		if not values is Array:
			continue
		for value: Variant in values:
			var extension_id: String = String(value)
			if not extension_id.is_empty() and not extensions.has(extension_id):
				extensions.append(extension_id)
	return extensions


func apply_json_mods(resource_path: String, base_data: Variant) -> Variant:
	if not base_data is Dictionary:
		return base_data

	var result: Dictionary = (base_data as Dictionary).duplicate(true)
	for mod: Dictionary in _enabled_mods:
		var patches: Array = mod.get("data_patches", []) as Array
		for patch: Variant in patches:
			if not patch is Dictionary:
				continue
			var patch_dict: Dictionary = patch as Dictionary
			if String(patch_dict.get("type", "")) != "json_array_append":
				continue
			if not _patch_targets_resource(patch_dict, resource_path):
				continue
			_apply_json_array_append(mod, patch_dict, result)
	return result


func apply_csv_mods(resource_path: String, base_rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = base_rows.duplicate(true)
	for mod: Dictionary in _enabled_mods:
		var patches: Array = mod.get("data_patches", []) as Array
		for patch: Variant in patches:
			if not patch is Dictionary:
				continue
			var patch_dict: Dictionary = patch as Dictionary
			if String(patch_dict.get("type", "")) != "csv_append":
				continue
			if not _patch_targets_resource(patch_dict, resource_path):
				continue
			_apply_csv_append(mod, patch_dict, result)
	return result


func _ensure_mods_root() -> void:
	if DirAccess.dir_exists_absolute(MODS_ROOT):
		return
	var error: Error = DirAccess.make_dir_recursive_absolute(MODS_ROOT)
	if error != OK:
		_add_diagnostic("failed to create %s error=%d" % [MODS_ROOT, error])


func _load_mod_directory(mod_root: String) -> void:
	var manifest_path: String = mod_root.path_join(MANIFEST_FILE_NAME)
	if not FileAccess.file_exists(manifest_path):
		return

	var manifest: Variant = _load_json_file(manifest_path)
	if not manifest is Dictionary:
		_add_diagnostic("%s root must be Dictionary" % manifest_path)
		return

	var mod: Dictionary = manifest as Dictionary
	if not _validate_manifest(manifest_path, mod):
		return
	var mod_id: String = String(mod.get("id", ""))
	if mod_root.get_file() != mod_id:
		_add_diagnostic("%s:id must match mod directory name %s" % [manifest_path, mod_root.get_file()])
		return
	if _has_enabled_mod_id(mod_id):
		_add_diagnostic("%s:id duplicates an already enabled mod" % manifest_path)
		return
	if not bool(mod.get("enabled", true)):
		return

	var normalized: Dictionary = mod.duplicate(true)
	normalized["root_path"] = mod_root
	normalized["load_order"] = int(mod.get("load_order", 0))
	_enabled_mods.append(normalized)


func _validate_manifest(manifest_path: String, manifest: Dictionary) -> bool:
	var is_valid: bool = true
	var mod_id: String = String(manifest.get("id", ""))
	if int(manifest.get("schema_version", 0)) != SUPPORTED_SCHEMA_VERSION:
		is_valid = _manifest_fail(manifest_path, "schema_version", "1") and is_valid
	if not _is_snake_id(mod_id):
		is_valid = _manifest_fail(manifest_path, "id", "snake_case mod id") and is_valid
	if not manifest.get("name") is String or String(manifest.get("name", "")).is_empty():
		is_valid = _manifest_fail(manifest_path, "name", "non-empty string") and is_valid
	if not manifest.get("version") is String or String(manifest.get("version", "")).is_empty():
		is_valid = _manifest_fail(manifest_path, "version", "non-empty string") and is_valid
	if manifest.has("enabled") and not manifest.get("enabled") is bool:
		is_valid = _manifest_fail(manifest_path, "enabled", "bool") and is_valid
	if manifest.has("load_order") and not _is_int_like(manifest.get("load_order")):
		is_valid = _manifest_fail(manifest_path, "load_order", "int") and is_valid
	is_valid = _validate_contract_extensions(manifest_path, mod_id, manifest.get("contract_extensions", {})) and is_valid
	is_valid = _validate_data_patches(manifest_path, manifest.get("data_patches", [])) and is_valid
	return is_valid


func _validate_contract_extensions(manifest_path: String, mod_id: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _manifest_fail(manifest_path, "contract_extensions", "Dictionary")

	var is_valid: bool = true
	var extensions: Dictionary = data as Dictionary
	var expected_prefix: String = "mod_%s_" % mod_id
	for key_variant: Variant in extensions.keys():
		var key: String = String(key_variant)
		if not ALLOWED_CONTRACT_EXTENSION_KEYS.has(key):
			is_valid = _manifest_fail(manifest_path, "contract_extensions.%s" % key, "allowed extension key") and is_valid
			continue
		var values: Variant = extensions[key_variant]
		if not values is Array:
			is_valid = _manifest_fail(manifest_path, "contract_extensions.%s" % key, "Array") and is_valid
			continue
		var seen: Dictionary = {}
		var values_array: Array = values as Array
		for index: int in range(values_array.size()):
			var field: String = "contract_extensions.%s[%d]" % [key, index]
			var value: String = String(values_array[index])
			if not _is_snake_id(value) or not value.begins_with(expected_prefix):
				is_valid = _manifest_fail(manifest_path, field, "id beginning with %s" % expected_prefix) and is_valid
			if seen.has(value):
				is_valid = _manifest_fail(manifest_path, field, "unique id") and is_valid
			seen[value] = true
	return is_valid


func _validate_data_patches(manifest_path: String, data: Variant) -> bool:
	if not data is Array:
		return _manifest_fail(manifest_path, "data_patches", "Array")

	var is_valid: bool = true
	var patches: Array = data as Array
	for index: int in range(patches.size()):
		var field: String = "data_patches[%d]" % index
		var patch: Variant = patches[index]
		if not patch is Dictionary:
			is_valid = _manifest_fail(manifest_path, field, "Dictionary") and is_valid
			continue
		var patch_dict: Dictionary = patch as Dictionary
		var patch_type: String = String(patch_dict.get("type", ""))
		if not SUPPORTED_PATCH_TYPES.has(patch_type):
			is_valid = _manifest_fail(manifest_path, "%s.type" % field, "supported patch type") and is_valid
		if not patch_dict.get("target") is String or String(patch_dict.get("target", "")).is_empty():
			is_valid = _manifest_fail(manifest_path, "%s.target" % field, "non-empty string") and is_valid
		var relative_path: String = String(patch_dict.get("path", ""))
		if not _is_safe_relative_path(relative_path):
			is_valid = _manifest_fail(manifest_path, "%s.path" % field, "safe relative path") and is_valid
		if patch_type == "json_array_append" and (not patch_dict.get("array_key") is String or String(patch_dict.get("array_key", "")).is_empty()):
			is_valid = _manifest_fail(manifest_path, "%s.array_key" % field, "non-empty string") and is_valid
	return is_valid


func _has_enabled_mod_id(mod_id: String) -> bool:
	for mod: Dictionary in _enabled_mods:
		if String(mod.get("id", "")) == mod_id:
			return true
	return false


func _apply_json_array_append(mod: Dictionary, patch: Dictionary, result: Dictionary) -> void:
	var array_key: String = String(patch.get("array_key", ""))
	if not result.get(array_key) is Array:
		_add_diagnostic("%s target array %s is missing" % [String(mod.get("id", "")), array_key])
		return

	var patch_path: String = _mod_file_path(mod, String(patch.get("path", "")))
	if patch_path.is_empty():
		return
	var patch_payload: Variant = _load_json_file(patch_path)
	var items: Array = []
	if patch_payload is Array:
		items = patch_payload as Array
	elif patch_payload is Dictionary and (patch_payload as Dictionary).get(array_key) is Array:
		items = (patch_payload as Dictionary).get(array_key) as Array
	else:
		_add_diagnostic("%s must contain Array or Dictionary.%s Array" % [patch_path, array_key])
		return

	var target_items: Array = result[array_key] as Array
	for item: Variant in items:
		target_items.append(item)


func _apply_csv_append(mod: Dictionary, patch: Dictionary, result: Array[Dictionary]) -> void:
	var patch_path: String = _mod_file_path(mod, String(patch.get("path", "")))
	if patch_path.is_empty():
		return
	var rows: Array[Dictionary] = _load_csv_file(patch_path)
	for row: Dictionary in rows:
		result.append(row)


func _patch_targets_resource(patch: Dictionary, resource_path: String) -> bool:
	var target: String = String(patch.get("target", ""))
	return target == resource_path or target == resource_path.get_file()


func _mod_file_path(mod: Dictionary, relative_path: String) -> String:
	if not _is_safe_relative_path(relative_path):
		_add_diagnostic("%s has unsafe path %s" % [String(mod.get("id", "")), relative_path])
		return ""
	return String(mod.get("root_path", "")).path_join(relative_path)


func _load_json_file(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_add_diagnostic("%s is not readable JSON" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		_add_diagnostic("%s is not valid JSON" % path)
		return {}
	return parsed


func _load_csv_file(path: String) -> Array[Dictionary]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_add_diagnostic("%s is not readable CSV" % path)
		return []

	var rows: Array[Dictionary] = []
	var headers: PackedStringArray = PackedStringArray()
	if not file.eof_reached():
		headers = file.get_csv_line()
	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 0 or (values.size() == 1 and String(values[0]).strip_edges().is_empty()):
			continue
		var row: Dictionary = {}
		for index: int in range(headers.size()):
			row[String(headers[index])] = values[index] if index < values.size() else ""
		rows.append(row)
	return rows


func _sort_mods_by_load_order(left: Dictionary, right: Dictionary) -> bool:
	var left_order: int = int(left.get("load_order", 0))
	var right_order: int = int(right.get("load_order", 0))
	if left_order == right_order:
		return String(left.get("id", "")) < String(right.get("id", ""))
	return left_order < right_order


func _is_safe_relative_path(path: String) -> bool:
	if path.is_empty():
		return false
	if path.contains("://") or path.contains("..") or path.begins_with("/") or path.begins_with("\\"):
		return false
	return true


func _is_snake_id(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile(MOD_ID_PATTERN)
	return regex.search(value) != null


func _is_int_like(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_equal_approx(float(value), float(int(value)))
	return false


func _manifest_fail(manifest_path: String, field_path: String, expected: String) -> bool:
	_add_diagnostic("%s:%s expected %s" % [manifest_path, field_path, expected])
	return false


func _add_diagnostic(message: String) -> void:
	_diagnostics.append(message)
	push_warning("[ModLoader] %s" % message)
