# Doc: docs/代码/mod_loader.md
# Authority: docs/游戏设计文档.md §9.21
class_name ModLoaderAutoload
extends Node


signal mods_reloaded()
signal reload_rejected(reason: String)

const EFFECT_ACTIONS := preload("res://scripts/contracts/effect_actions.gd")
const EFFECT_CONDITIONS := preload("res://scripts/contracts/effect_conditions.gd")
const EFFECT_TRIGGERS := preload("res://scripts/contracts/effect_triggers.gd")
const GEAR_MOD_BOARD_RULES := preload("res://scripts/contracts/gear_mod_board_rules.gd")
const GEAR_MOD_COMPONENT_TYPES := preload("res://scripts/contracts/gear_mod_component_types.gd")
const GEAR_MOD_RARITIES := preload("res://scripts/contracts/gear_mod_rarities.gd")
const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")

const ALLOWED_CONTRACT_EXTENSION_KEYS: Array[String] = [
	"gear_mod_ids",
	"locale_prefixes",
]
const ALLOWED_JSON_PATCH_ARRAYS: Dictionary = {
	"gear_mods.json": ["mods", "reward_pool_contributions"],
}
const ALLOWED_CSV_PATCH_TARGETS: Array[String] = [
	"gear_mod_drop_tables.csv",
	"strings.csv",
]
const MANIFEST_FILE_NAME: String = "mod.json"
const MODS_ROOT: String = "user://mods"
const MOD_ID_PATTERN: String = "^[a-z0-9_]+$"
const SUPPORTED_PATCH_TYPES: Array[String] = [
	"csv_append",
	"json_array_append",
]
const SUPPORTED_SCHEMA_VERSION: int = 2

const MEDIA_KIND_IMAGE: String = "image"
const MEDIA_KIND_SFX: String = "sfx"
const SUPPORTED_IMAGE_EXTENSIONS: Array[String] = ["jpeg", "jpg", "png", "webp"]
const SUPPORTED_AUDIO_EXTENSIONS: Array[String] = ["mp3", "ogg", "wav"]
const MAX_MEDIA_COUNT: int = 128
const MAX_MEDIA_TOTAL_BYTES: int = 64 * 1024 * 1024
const MAX_IMAGE_BYTES: int = 4 * 1024 * 1024
const MAX_IMAGE_DIMENSION: int = 1024
const MAX_AUDIO_BYTES: int = 8 * 1024 * 1024
const MAX_AUDIO_SECONDS: float = 30.0

var _diagnostics: Array[String] = []
var _enabled_mods: Array[Dictionary] = []
var _packages: Array[Dictionary] = []
var _image_assets: Dictionary = {}
var _audio_assets: Dictionary = {}
var _run_active: bool = false
var _replay_active: bool = false


func _ready() -> void:
	reload_packages()


func set_runtime_activity(run_active: bool, replay_active: bool) -> void:
	_run_active = run_active
	_replay_active = replay_active


func can_reload_packages() -> bool:
	return not _run_active and not _replay_active


func reload_packages() -> bool:
	if not can_reload_packages():
		var reason: String = "local mods cannot reload during an active Run or Replay"
		_add_diagnostic(reason)
		reload_rejected.emit(reason)
		return false

	_enabled_mods.clear()
	_packages.clear()
	_diagnostics.clear()
	_image_assets.clear()
	_audio_assets.clear()
	_ensure_mods_root()

	var mods_dir: DirAccess = DirAccess.open(MODS_ROOT)
	if mods_dir == null:
		_add_diagnostic("%s is not readable" % MODS_ROOT)
		mods_reloaded.emit()
		return false

	var directory_names: Array[String] = []
	mods_dir.list_dir_begin()
	var entry_name: String = mods_dir.get_next()
	while not entry_name.is_empty():
		if mods_dir.current_is_dir() and not entry_name.begins_with("."):
			directory_names.append(entry_name)
		entry_name = mods_dir.get_next()
	mods_dir.list_dir_end()
	directory_names.sort()
	for directory_name: String in directory_names:
		_load_mod_directory(MODS_ROOT.path_join(directory_name))

	_enabled_mods.sort_custom(_sort_mods_by_load_order)
	_packages.sort_custom(_sort_mods_by_load_order)
	_rebuild_asset_registries()
	mods_reloaded.emit()
	return true


func enabled_mod_count() -> int:
	return _enabled_mods.size()


func package_statuses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for package: Dictionary in _packages:
		result.append({
			"id": String(package.get("id", "")),
			"name": String(package.get("name", "")),
			"version": String(package.get("version", "")),
			"enabled": bool(package.get("enabled", false)),
			"status": String(package.get("status", "")),
			"diagnostics": (package.get("diagnostics", []) as Array).duplicate(),
		})
	return result


func diagnostics() -> Array[String]:
	return _diagnostics.duplicate()


func mod_environment() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mod: Dictionary in _enabled_mods:
		result.append({
			"id": String(mod.get("id", "")),
			"version": String(mod.get("version", "")),
			"gameplay_hash": String(mod.get("gameplay_hash", "")),
		})
	return result


func package_gameplay_payloads() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mod: Dictionary in _enabled_mods:
		var package_payload: Dictionary = {
			"id": String(mod.get("id", "")),
			"mods": [],
			"reward_pool_contributions": [],
			"drop_rows": [],
		}
		for patch_variant: Variant in mod.get("cached_patches", []) as Array:
			if not patch_variant is Dictionary:
				continue
			var patch: Dictionary = patch_variant as Dictionary
			var array_key: String = String(patch.get("array_key", ""))
			if array_key == "mods" or array_key == "reward_pool_contributions":
				var target_items: Array = package_payload[array_key] as Array
				for item: Variant in patch.get("items", []) as Array:
					target_items.append(_copy_variant(item))
			elif String(patch.get("target", "")) == "gear_mod_drop_tables.csv":
				var drop_rows: Array = package_payload["drop_rows"] as Array
				for row: Variant in patch.get("rows", []) as Array:
					drop_rows.append(_copy_variant(row))
		result.append(package_payload)
	return result


func package_locale_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mod: Dictionary in _enabled_mods:
		for patch_variant: Variant in mod.get("cached_patches", []) as Array:
			if not patch_variant is Dictionary:
				continue
			var patch: Dictionary = patch_variant as Dictionary
			if String(patch.get("target", "")) != "strings.csv":
				continue
			for row: Variant in patch.get("rows", []) as Array:
				if row is Dictionary:
					result.append((row as Dictionary).duplicate(true))
	return result


func validate_environment(expected: Array) -> Dictionary:
	var actual: Array[Dictionary] = mod_environment()
	if expected.size() != actual.size():
		return {
			"ok": false,
			"reason": "local mod environment count mismatch: expected %d, found %d" % [expected.size(), actual.size()],
		}
	for index: int in range(expected.size()):
		if not expected[index] is Dictionary:
			return {"ok": false, "reason": "local mod environment entry %d is invalid" % index}
		var expected_entry: Dictionary = expected[index] as Dictionary
		var actual_entry: Dictionary = actual[index]
		for field: String in ["id", "version", "gameplay_hash"]:
			if String(expected_entry.get(field, "")) != String(actual_entry.get(field, "")):
				return {
					"ok": false,
					"reason": "local mod environment mismatch at %d.%s: expected %s, found %s" % [
						index,
						field,
						String(expected_entry.get(field, "")),
						String(actual_entry.get(field, "")),
					],
				}
	return {"ok": true, "reason": ""}


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


func disable_package(package_id: String, reason: String) -> bool:
	for index: int in range(_enabled_mods.size()):
		var mod: Dictionary = _enabled_mods[index]
		if String(mod.get("id", "")) != package_id:
			continue
		_enabled_mods.remove_at(index)
		_set_package_disabled(package_id, reason)
		_rebuild_asset_registries()
		mods_reloaded.emit()
		return true
	return false


func apply_json_mods(resource_path: String, base_data: Variant) -> Variant:
	if not base_data is Dictionary:
		return base_data

	var result: Dictionary = (base_data as Dictionary).duplicate(true)
	for mod: Dictionary in _enabled_mods:
		var patches: Array = mod.get("cached_patches", []) as Array
		for patch_variant: Variant in patches:
			if not patch_variant is Dictionary:
				continue
			var patch: Dictionary = patch_variant as Dictionary
			if String(patch.get("type", "")) != "json_array_append":
				continue
			if not _patch_targets_resource(patch, resource_path):
				continue
			var array_key: String = String(patch.get("array_key", ""))
			if not result.get(array_key) is Array:
				_add_diagnostic("%s target array %s is missing" % [String(mod.get("id", "")), array_key])
				continue
			var target_items: Array = result[array_key] as Array
			for item: Variant in patch.get("items", []) as Array:
				target_items.append(_copy_variant(item))
	return result


func apply_csv_mods(resource_path: String, base_rows: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = base_rows.duplicate(true)
	for mod: Dictionary in _enabled_mods:
		var patches: Array = mod.get("cached_patches", []) as Array
		for patch_variant: Variant in patches:
			if not patch_variant is Dictionary:
				continue
			var patch: Dictionary = patch_variant as Dictionary
			if String(patch.get("type", "")) != "csv_append":
				continue
			if not _patch_targets_resource(patch, resource_path):
				continue
			for row_variant: Variant in patch.get("rows", []) as Array:
				if row_variant is Dictionary:
					result.append((row_variant as Dictionary).duplicate(true))
	return result


func has_image_asset(asset_id: String) -> bool:
	return _image_assets.has(asset_id)


func image_texture(asset_id: String) -> ImageTexture:
	return _image_assets.get(asset_id) as ImageTexture


func media_audio_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var asset_ids: Array = _audio_assets.keys()
	asset_ids.sort()
	for asset_id_variant: Variant in asset_ids:
		var asset_id: String = String(asset_id_variant)
		var entry: Dictionary = _audio_assets[asset_id] as Dictionary
		result.append({
			"id": asset_id,
			"package_id": String(entry.get("package_id", "")),
			"stream": entry.get("stream"),
			"max_polyphony": int(entry.get("max_polyphony", 8)),
		})
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

	var local_diagnostics: Array[String] = []
	var manifest: Variant = _load_json_file(manifest_path, local_diagnostics)
	if not manifest is Dictionary:
		_record_invalid_package(mod_root.get_file(), "", 0, local_diagnostics)
		return

	var mod: Dictionary = manifest as Dictionary
	var mod_id: String = String(mod.get("id", mod_root.get_file()))
	var version: String = String(mod.get("version", ""))
	var load_order: int = int(mod.get("load_order", 0))
	if not _validate_manifest(manifest_path, mod, local_diagnostics):
		_record_invalid_package(mod_id, version, load_order, local_diagnostics)
		return
	if mod_root.get_file() != mod_id:
		_package_fail(local_diagnostics, manifest_path, "id", "must match mod directory name %s" % mod_root.get_file())
		_record_invalid_package(mod_id, version, load_order, local_diagnostics)
		return
	if _has_package_id(mod_id):
		_package_fail(local_diagnostics, manifest_path, "id", "unique package id")
		_record_invalid_package(mod_id, version, load_order, local_diagnostics)
		return
	if not bool(mod.get("enabled", true)):
		_packages.append(_package_status(mod_id, String(mod.get("name", mod_id)), version, load_order, false, "disabled", []))
		return

	var normalized: Dictionary = mod.duplicate(true)
	normalized["root_path"] = mod_root
	normalized["load_order"] = load_order
	var cached_patches: Array[Dictionary] = []
	if not _cache_gameplay_patches(normalized, manifest_path, cached_patches, local_diagnostics):
		_record_invalid_package(mod_id, version, load_order, local_diagnostics)
		return
	normalized["cached_patches"] = cached_patches
	normalized["media_cache"] = _cache_media_assets(normalized, manifest_path, local_diagnostics)
	_sanitize_mod_media_references(normalized, manifest_path, local_diagnostics)
	normalized["gameplay_hash"] = _gameplay_hash(normalized)
	normalized["diagnostics"] = local_diagnostics.duplicate()
	_enabled_mods.append(normalized)
	_packages.append(_package_status(mod_id, String(mod.get("name", mod_id)), version, load_order, true, "enabled", local_diagnostics))
	_flush_package_diagnostics(mod_id, local_diagnostics)


func _validate_manifest(manifest_path: String, manifest: Dictionary, package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	var mod_id: String = String(manifest.get("id", ""))
	if not _has_only_keys(
		manifest,
		[
			"schema_version",
			"id",
			"name",
			"version",
			"enabled",
			"load_order",
			"contract_extensions",
			"data_patches",
			"media_assets",
		]
	):
		is_valid = _package_fail(
			package_diagnostics,
			manifest_path,
			"root",
			"manifest v2 fields only"
		) and is_valid
	if int(manifest.get("schema_version", 0)) != SUPPORTED_SCHEMA_VERSION:
		is_valid = _package_fail(package_diagnostics, manifest_path, "schema_version", "2") and is_valid
	if not _is_snake_id(mod_id):
		is_valid = _package_fail(package_diagnostics, manifest_path, "id", "snake_case package id") and is_valid
	if not manifest.get("name") is String or String(manifest.get("name", "")).is_empty():
		is_valid = _package_fail(package_diagnostics, manifest_path, "name", "non-empty string") and is_valid
	if not manifest.get("version") is String or String(manifest.get("version", "")).is_empty():
		is_valid = _package_fail(package_diagnostics, manifest_path, "version", "non-empty string") and is_valid
	if manifest.has("enabled") and not manifest.get("enabled") is bool:
		is_valid = _package_fail(package_diagnostics, manifest_path, "enabled", "bool") and is_valid
	if manifest.has("load_order") and not _is_int_like(manifest.get("load_order")):
		is_valid = _package_fail(package_diagnostics, manifest_path, "load_order", "int") and is_valid
	is_valid = _validate_contract_extensions(manifest_path, mod_id, manifest.get("contract_extensions", {}), package_diagnostics) and is_valid
	is_valid = _validate_data_patches(manifest_path, manifest.get("data_patches", []), package_diagnostics) and is_valid
	if manifest.has("media_assets") and not manifest.get("media_assets") is Array:
		is_valid = _package_fail(package_diagnostics, manifest_path, "media_assets", "Array") and is_valid
	return is_valid


func _validate_contract_extensions(manifest_path: String, mod_id: String, data: Variant, package_diagnostics: Array[String]) -> bool:
	if not data is Dictionary:
		return _package_fail(package_diagnostics, manifest_path, "contract_extensions", "Dictionary")

	var is_valid: bool = true
	var extensions: Dictionary = data as Dictionary
	var expected_prefix: String = _namespace_prefix(mod_id)
	for key_variant: Variant in extensions.keys():
		var key: String = String(key_variant)
		if not ALLOWED_CONTRACT_EXTENSION_KEYS.has(key):
			is_valid = _package_fail(package_diagnostics, manifest_path, "contract_extensions.%s" % key, "allowed extension key") and is_valid
			continue
		var values: Variant = extensions[key_variant]
		if not values is Array:
			is_valid = _package_fail(package_diagnostics, manifest_path, "contract_extensions.%s" % key, "Array") and is_valid
			continue
		var seen: Dictionary = {}
		for index: int in range((values as Array).size()):
			var field: String = "contract_extensions.%s[%d]" % [key, index]
			var value: String = String((values as Array)[index])
			if not _is_snake_id(value) or not value.begins_with(expected_prefix):
				is_valid = _package_fail(package_diagnostics, manifest_path, field, "id beginning with %s" % expected_prefix) and is_valid
			if seen.has(value):
				is_valid = _package_fail(package_diagnostics, manifest_path, field, "unique id") and is_valid
			seen[value] = true
	return is_valid


func _validate_data_patches(manifest_path: String, data: Variant, package_diagnostics: Array[String]) -> bool:
	if not data is Array:
		return _package_fail(package_diagnostics, manifest_path, "data_patches", "Array")

	var is_valid: bool = true
	for index: int in range((data as Array).size()):
		var field: String = "data_patches[%d]" % index
		var patch: Variant = (data as Array)[index]
		if not patch is Dictionary:
			is_valid = _package_fail(package_diagnostics, manifest_path, field, "Dictionary") and is_valid
			continue
		var patch_dict: Dictionary = patch as Dictionary
		var patch_type: String = String(patch_dict.get("type", ""))
		var target: String = String(patch_dict.get("target", "")).get_file()
		var allowed_patch_keys: Array[String] = ["type", "target", "path"]
		if patch_type == "json_array_append":
			allowed_patch_keys.append("array_key")
		if not _has_only_keys(patch_dict, allowed_patch_keys):
			is_valid = _package_fail(
				package_diagnostics,
				manifest_path,
				field,
				"fields supported by the declared patch type"
			) and is_valid
		if not SUPPORTED_PATCH_TYPES.has(patch_type):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.type" % field, "supported patch type") and is_valid
		if patch_type == "json_array_append":
			var array_key: String = String(patch_dict.get("array_key", ""))
			if not ALLOWED_JSON_PATCH_ARRAYS.has(target) or not (ALLOWED_JSON_PATCH_ARRAYS[target] as Array).has(array_key):
				is_valid = _package_fail(package_diagnostics, manifest_path, "%s.target" % field, "supported Gear Mod JSON append target and array") and is_valid
		elif patch_type == "csv_append" and not ALLOWED_CSV_PATCH_TARGETS.has(target):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.target" % field, "supported Gear Mod CSV or locale target") and is_valid
		var relative_path: String = String(patch_dict.get("path", ""))
		if not _is_safe_relative_path(relative_path):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.path" % field, "safe relative path") and is_valid
	return is_valid


func _cache_gameplay_patches(mod: Dictionary, manifest_path: String, cached_patches: Array[Dictionary], package_diagnostics: Array[String]) -> bool:
	var mod_id: String = String(mod.get("id", ""))
	var declared_ids: Array = (mod.get("contract_extensions", {}) as Dictionary).get("gear_mod_ids", []) as Array
	var is_valid: bool = true
	for index: int in range((mod.get("data_patches", []) as Array).size()):
		var patch: Dictionary = (mod.get("data_patches", []) as Array)[index] as Dictionary
		var cached: Dictionary = {
			"type": String(patch.get("type", "")),
			"target": String(patch.get("target", "")).get_file(),
			"array_key": String(patch.get("array_key", "")),
		}
		var patch_path: String = String(mod.get("root_path", "")).path_join(String(patch.get("path", "")))
		if not FileAccess.file_exists(patch_path):
			is_valid = _package_fail(package_diagnostics, manifest_path, "data_patches[%d].path" % index, "readable package file") and is_valid
			continue
		if String(patch.get("type", "")) == "json_array_append":
			var payload: Variant = _load_json_file(patch_path, package_diagnostics)
			var array_key: String = String(patch.get("array_key", ""))
			var items: Array = []
			if payload is Array:
				items = payload as Array
			elif payload is Dictionary and (payload as Dictionary).get(array_key) is Array:
				items = (payload as Dictionary).get(array_key) as Array
			else:
				is_valid = _package_fail(package_diagnostics, manifest_path, "data_patches[%d]" % index, "readable Array or Dictionary.%s Array" % array_key) and is_valid
				continue
			if array_key == "mods":
				is_valid = _validate_owned_mod_items(manifest_path, index, mod_id, declared_ids, items, package_diagnostics) and is_valid
			elif array_key == "reward_pool_contributions":
				is_valid = _validate_reward_pool_contributions(manifest_path, index, mod_id, declared_ids, items, package_diagnostics) and is_valid
			cached["items"] = items.duplicate(true)
		else:
			var rows: Array[Dictionary] = _load_csv_file(patch_path, package_diagnostics)
			var csv_target: String = String(patch.get("target", "")).get_file()
			if csv_target == "gear_mod_drop_tables.csv":
				is_valid = _validate_owned_drop_rows(manifest_path, index, mod_id, declared_ids, rows, package_diagnostics) and is_valid
			elif csv_target == "strings.csv":
				is_valid = _validate_locale_rows(manifest_path, index, mod_id, rows, package_diagnostics) and is_valid
			cached["rows"] = rows.duplicate(true)
		cached_patches.append(cached)
	var defined_ids: Dictionary = {}
	for cached_patch: Dictionary in cached_patches:
		if String(cached_patch.get("array_key", "")) != "mods":
			continue
		for item_variant: Variant in cached_patch.get("items", []) as Array:
			if item_variant is Dictionary:
				var defined_id: String = String((item_variant as Dictionary).get("id", ""))
				if defined_ids.has(defined_id):
					is_valid = _package_fail(package_diagnostics, manifest_path, "data_patches.mods.id", "unique definition across package; duplicated %s" % defined_id) and is_valid
				defined_ids[defined_id] = true
	for declared_id_variant: Variant in declared_ids:
		var declared_id: String = String(declared_id_variant)
		if not defined_ids.has(declared_id):
			is_valid = _package_fail(package_diagnostics, manifest_path, "contract_extensions.gear_mod_ids", "each declared id to have one mods[] definition; missing %s" % declared_id) and is_valid
	return is_valid


func _validate_owned_mod_items(manifest_path: String, patch_index: int, mod_id: String, declared_ids: Array, items: Array, package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	var seen: Dictionary = {}
	for item_index: int in range(items.size()):
		var field: String = "data_patches[%d].mods[%d]" % [patch_index, item_index]
		if not items[item_index] is Dictionary:
			is_valid = _package_fail(package_diagnostics, manifest_path, field, "Dictionary") and is_valid
			continue
		var gear_mod_id: String = String((items[item_index] as Dictionary).get("id", ""))
		if not gear_mod_id.begins_with(_namespace_prefix(mod_id)) or not declared_ids.has(gear_mod_id):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.id" % field, "declared package-owned gear_mod_id") and is_valid
		if seen.has(gear_mod_id):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.id" % field, "unique id") and is_valid
		seen[gear_mod_id] = true
		is_valid = _validate_gear_mod_definition(manifest_path, field, mod_id, items[item_index] as Dictionary, package_diagnostics) and is_valid
	return is_valid


func _validate_gear_mod_definition(manifest_path: String, field: String, mod_id: String, definition: Dictionary, package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	var allowed_keys: Array[String] = [
		"codex_icon_path",
		"components",
		"default_unlocked",
		"desc_key",
		"id",
		"name_key",
		"placement_sfx_id",
		"rarity",
	]
	if not _has_only_keys(definition, allowed_keys):
		is_valid = _package_fail(package_diagnostics, manifest_path, field, "only supported local Gear Mod fields") and is_valid
	if definition.has("unlock_rule_id"):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.unlock_rule_id" % field, "field to be absent for install-unlocked local content") and is_valid
	if definition.has("default_unlocked") and (not definition.get("default_unlocked") is bool or not bool(definition.get("default_unlocked"))):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.default_unlocked" % field, "true or omitted") and is_valid
	for locale_field: String in ["name_key", "desc_key"]:
		var locale_key: String = String(definition.get(locale_field, ""))
		if locale_key.is_empty() or not locale_key.begins_with(_namespace_prefix(mod_id)):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.%s" % [field, locale_field], "package-namespaced locale key") and is_valid
	if not GEAR_MOD_RARITIES.VALUES.has(String(definition.get("rarity", ""))):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.rarity" % field, "registered Gear Mod rarity") and is_valid
	if definition.has("codex_icon_path") and (not definition.get("codex_icon_path") is String or String(definition.get("codex_icon_path", "")).is_empty()):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.codex_icon_path" % field, "non-empty string") and is_valid
	if definition.has("placement_sfx_id") and (not definition.get("placement_sfx_id") is String or String(definition.get("placement_sfx_id", "")).is_empty()):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.placement_sfx_id" % field, "non-empty string") and is_valid
	if not definition.get("components") is Array or (definition.get("components") as Array).is_empty():
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.components" % field, "non-empty Array") and is_valid
		return is_valid

	var component_ids: Dictionary = {}
	for component_index: int in range((definition.get("components") as Array).size()):
		var component_field: String = "%s.components[%d]" % [field, component_index]
		var component_variant: Variant = (definition.get("components") as Array)[component_index]
		if not component_variant is Dictionary:
			is_valid = _package_fail(package_diagnostics, manifest_path, component_field, "Dictionary") and is_valid
			continue
		var component: Dictionary = component_variant as Dictionary
		var component_id: String = String(component.get("component_id", ""))
		if not _is_snake_id(component_id) or component_ids.has(component_id):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.component_id" % component_field, "unique snake_case id within Gear Mod") and is_valid
		component_ids[component_id] = true
		var component_type: String = String(component.get("type", ""))
		if not GEAR_MOD_COMPONENT_TYPES.VALUES.has(component_type):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.type" % component_field, "registered Gear Mod component type") and is_valid
			continue
		match component_type:
			GEAR_MOD_COMPONENT_TYPES.MODIFIER:
				is_valid = _validate_modifier_component(manifest_path, component_field, component, package_diagnostics) and is_valid
			GEAR_MOD_COMPONENT_TYPES.PROGRAM:
				is_valid = _validate_program_component(manifest_path, component_field, component, package_diagnostics) and is_valid
			GEAR_MOD_COMPONENT_TYPES.BOARD_RULE:
				is_valid = _validate_board_rule_component(manifest_path, component_field, component, package_diagnostics) and is_valid
			_:
				pass
	return is_valid


func _validate_modifier_component(manifest_path: String, field: String, component: Dictionary, package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	if not _has_only_keys(component, ["component_id", "modifiers", "slot", "type"]):
		is_valid = _package_fail(package_diagnostics, manifest_path, field, "only modifier component fields") and is_valid
	if not GEAR_MOD_SLOTS.VALUES.has(String(component.get("slot", ""))):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.slot" % field, "hero or weapon") and is_valid
	if not component.get("modifiers") is Array or (component.get("modifiers") as Array).is_empty():
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.modifiers" % field, "non-empty Array") and is_valid
	else:
		for modifier_index: int in range((component.get("modifiers") as Array).size()):
			if not (component.get("modifiers") as Array)[modifier_index] is Dictionary:
				is_valid = _package_fail(package_diagnostics, manifest_path, "%s.modifiers[%d]" % [field, modifier_index], "Dictionary") and is_valid
	return is_valid


func _validate_program_component(manifest_path: String, field: String, component: Dictionary, package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	if not _has_only_keys(component, ["component_id", "program", "type"]):
		is_valid = _package_fail(package_diagnostics, manifest_path, field, "only program component fields") and is_valid
	if not component.get("program") is Dictionary:
		return _package_fail(package_diagnostics, manifest_path, "%s.program" % field, "Dictionary") and is_valid
	var program: Dictionary = component.get("program") as Dictionary
	var allowed_keys: Array[String] = [
		"actions",
		"conditions",
		"internal_cooldown",
		"interval_seconds",
		"proc_chance",
		"program_id",
		"reset_on_condition_fail",
		"trigger",
	]
	if not _has_only_keys(program, allowed_keys):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program" % field, "only supported effect program fields") and is_valid
	if not _is_snake_id(String(program.get("program_id", ""))):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.program_id" % field, "snake_case id") and is_valid
	var trigger: String = String(program.get("trigger", ""))
	if not EFFECT_TRIGGERS.VALUES.has(trigger):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.trigger" % field, "registered effect trigger") and is_valid
	if not program.get("conditions", []) is Array:
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.conditions" % field, "Array") and is_valid
	else:
		is_valid = _validate_program_steps(manifest_path, "%s.program.conditions" % field, program.get("conditions", []) as Array, "condition", EFFECT_CONDITIONS.VALUES, false, package_diagnostics) and is_valid
	if not program.get("actions") is Array or (program.get("actions") as Array).is_empty():
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.actions" % field, "non-empty Array") and is_valid
	else:
		is_valid = _validate_program_steps(manifest_path, "%s.program.actions" % field, program.get("actions") as Array, "action", EFFECT_ACTIONS.VALUES, true, package_diagnostics) and is_valid
	var proc_chance_value: Variant = program.get("proc_chance", 1.0)
	if not _is_number(proc_chance_value) or float(proc_chance_value) < 0.0 or float(proc_chance_value) > 1.0:
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.proc_chance" % field, "number in [0, 1]") and is_valid
	var internal_cooldown_value: Variant = program.get("internal_cooldown", 0.0)
	if not _is_number(internal_cooldown_value) or float(internal_cooldown_value) < 0.0:
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.internal_cooldown" % field, "non-negative number") and is_valid
	if trigger == EFFECT_TRIGGERS.INTERVAL:
		if not _is_number(program.get("interval_seconds")) or float(program.get("interval_seconds", 0.0)) <= 0.0:
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.interval_seconds" % field, "positive number for interval trigger") and is_valid
	elif program.has("interval_seconds"):
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.interval_seconds" % field, "field only on interval trigger") and is_valid
	if program.has("reset_on_condition_fail") and not program.get("reset_on_condition_fail") is bool:
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.program.reset_on_condition_fail" % field, "bool") and is_valid
	return is_valid


func _validate_program_steps(manifest_path: String, field: String, steps: Array, id_key: String, allowed_ids: Array[String], require_non_empty: bool, package_diagnostics: Array[String]) -> bool:
	if require_non_empty and steps.is_empty():
		return _package_fail(package_diagnostics, manifest_path, field, "non-empty Array")
	var is_valid: bool = true
	for index: int in range(steps.size()):
		var step_field: String = "%s[%d]" % [field, index]
		if not steps[index] is Dictionary:
			is_valid = _package_fail(package_diagnostics, manifest_path, step_field, "Dictionary") and is_valid
			continue
		var step: Dictionary = steps[index] as Dictionary
		if not _has_only_keys(step, [id_key, "params"]):
			is_valid = _package_fail(package_diagnostics, manifest_path, step_field, "{%s, params}" % id_key) and is_valid
		if not allowed_ids.has(String(step.get(id_key, ""))):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.%s" % [step_field, id_key], "registered %s primitive" % id_key) and is_valid
		if not step.get("params") is Dictionary:
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.params" % step_field, "Dictionary") and is_valid
	return is_valid


func _validate_board_rule_component(manifest_path: String, field: String, component: Dictionary, package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	if not _has_only_keys(component, ["component_id", "rule_id", "type"]):
		is_valid = _package_fail(package_diagnostics, manifest_path, field, "only board_rule component fields") and is_valid
	if String(component.get("rule_id", "")) != GEAR_MOD_BOARD_RULES.OCCUPY_ONLY:
		is_valid = _package_fail(package_diagnostics, manifest_path, "%s.rule_id" % field, "occupy_only") and is_valid
	return is_valid


func _validate_owned_drop_rows(manifest_path: String, patch_index: int, mod_id: String, declared_ids: Array, rows: Array[Dictionary], package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	for row_index: int in range(rows.size()):
		var gear_mod_id: String = String(rows[row_index].get("mod_id", ""))
		if not gear_mod_id.begins_with(_namespace_prefix(mod_id)) or not declared_ids.has(gear_mod_id):
			is_valid = _package_fail(package_diagnostics, manifest_path, "data_patches[%d].rows[%d].mod_id" % [patch_index, row_index], "declared package-owned gear_mod_id") and is_valid
	return is_valid


func _validate_locale_rows(manifest_path: String, patch_index: int, mod_id: String, rows: Array[Dictionary], package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	var seen: Dictionary = {}
	for row_index: int in range(rows.size()):
		var field: String = "data_patches[%d].rows[%d]" % [patch_index, row_index]
		var locale_key: String = String(rows[row_index].get("keys", ""))
		if not locale_key.begins_with(_namespace_prefix(mod_id)) or seen.has(locale_key):
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.keys" % field, "unique package-namespaced locale key") and is_valid
		seen[locale_key] = true
		for locale: String in ["zh_CN", "en"]:
			if String(rows[row_index].get(locale, "")).is_empty():
				is_valid = _package_fail(package_diagnostics, manifest_path, "%s.%s" % [field, locale], "non-empty localized text") and is_valid
	return is_valid


func _validate_reward_pool_contributions(manifest_path: String, patch_index: int, mod_id: String, declared_ids: Array, items: Array, package_diagnostics: Array[String]) -> bool:
	var is_valid: bool = true
	for item_index: int in range(items.size()):
		var field: String = "data_patches[%d].reward_pool_contributions[%d]" % [patch_index, item_index]
		if not items[item_index] is Dictionary:
			is_valid = _package_fail(package_diagnostics, manifest_path, field, "Dictionary") and is_valid
			continue
		var contribution: Dictionary = items[item_index] as Dictionary
		if not contribution.get("mod_ids") is Array:
			is_valid = _package_fail(package_diagnostics, manifest_path, "%s.mod_ids" % field, "Array") and is_valid
			continue
		for mod_index: int in range((contribution.get("mod_ids") as Array).size()):
			var gear_mod_id: String = String((contribution.get("mod_ids") as Array)[mod_index])
			if not gear_mod_id.begins_with(_namespace_prefix(mod_id)) or not declared_ids.has(gear_mod_id):
				is_valid = _package_fail(package_diagnostics, manifest_path, "%s.mod_ids[%d]" % [field, mod_index], "declared package-owned gear_mod_id") and is_valid
	return is_valid


func _cache_media_assets(mod: Dictionary, manifest_path: String, package_diagnostics: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var media: Array = mod.get("media_assets", []) as Array
	if media.size() > MAX_MEDIA_COUNT:
		_media_fail(package_diagnostics, manifest_path, "media_assets", "at most %d entries" % MAX_MEDIA_COUNT)
		return result

	var package_bytes: int = 0
	var seen: Dictionary = {}
	for index: int in range(media.size()):
		var field: String = "media_assets[%d]" % index
		if not media[index] is Dictionary:
			_media_fail(package_diagnostics, manifest_path, field, "Dictionary")
			continue
		var entry: Dictionary = media[index] as Dictionary
		var asset_id: String = String(entry.get("id", ""))
		var kind: String = String(entry.get("type", ""))
		var relative_path: String = String(entry.get("path", ""))
		if not _is_snake_id(asset_id) or not asset_id.begins_with(_namespace_prefix(String(mod.get("id", "")))):
			_media_fail(package_diagnostics, manifest_path, "%s.id" % field, "namespaced snake_case id")
			continue
		if seen.has(asset_id):
			_media_fail(package_diagnostics, manifest_path, "%s.id" % field, "unique media id")
			continue
		seen[asset_id] = true
		if not _is_safe_relative_path(relative_path):
			_media_fail(package_diagnostics, manifest_path, "%s.path" % field, "safe relative path")
			continue
		var path: String = String(mod.get("root_path", "")).path_join(relative_path)
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			_media_fail(package_diagnostics, manifest_path, "%s.path" % field, "readable media file")
			continue
		var byte_count: int = file.get_length()
		package_bytes += byte_count
		if package_bytes > MAX_MEDIA_TOTAL_BYTES:
			_media_fail(package_diagnostics, manifest_path, "media_assets", "total size at most %d bytes" % MAX_MEDIA_TOTAL_BYTES)
			break
		var cached_entry: Dictionary = _decode_media_asset(mod, entry, path, byte_count, field, manifest_path, package_diagnostics)
		if not cached_entry.is_empty():
			result.append(cached_entry)
	return result


func _decode_media_asset(mod: Dictionary, entry: Dictionary, path: String, byte_count: int, field: String, manifest_path: String, package_diagnostics: Array[String]) -> Dictionary:
	var kind: String = String(entry.get("type", ""))
	var extension: String = path.get_extension().to_lower()
	var header: PackedByteArray = _read_header(path, 12)
	if kind == MEDIA_KIND_IMAGE:
		if byte_count > MAX_IMAGE_BYTES or not SUPPORTED_IMAGE_EXTENSIONS.has(extension) or not _header_matches_image(extension, header):
			_media_fail(package_diagnostics, manifest_path, field, "valid PNG/WebP/JPEG image at most %d bytes" % MAX_IMAGE_BYTES)
			return {}
		var image := Image.new()
		if image.load(path) != OK or image.is_empty() or image.get_width() > MAX_IMAGE_DIMENSION or image.get_height() > MAX_IMAGE_DIMENSION:
			_media_fail(package_diagnostics, manifest_path, field, "decodable image no larger than %dx%d" % [MAX_IMAGE_DIMENSION, MAX_IMAGE_DIMENSION])
			return {}
		return {
			"id": String(entry.get("id", "")),
			"type": kind,
			"texture": ImageTexture.create_from_image(image),
		}
	if kind == MEDIA_KIND_SFX:
		if byte_count > MAX_AUDIO_BYTES or not SUPPORTED_AUDIO_EXTENSIONS.has(extension) or not _header_matches_audio(extension, header):
			_media_fail(package_diagnostics, manifest_path, field, "valid Ogg Vorbis/MP3/WAV audio at most %d bytes" % MAX_AUDIO_BYTES)
			return {}
		var stream: AudioStream = _load_audio_stream(path, extension)
		if stream == null or stream.get_length() <= 0.0 or stream.get_length() > MAX_AUDIO_SECONDS:
			_media_fail(package_diagnostics, manifest_path, field, "decodable non-looping SFX no longer than %.0f seconds" % MAX_AUDIO_SECONDS)
			return {}
		_disable_audio_loop(stream)
		return {
			"id": String(entry.get("id", "")),
			"type": kind,
			"package_id": String(mod.get("id", "")),
			"stream": stream,
			"max_polyphony": maxi(int(entry.get("max_polyphony", 8)), 1),
		}
	_media_fail(package_diagnostics, manifest_path, "%s.type" % field, "image or sfx")
	return {}


func _load_audio_stream(path: String, extension: String) -> AudioStream:
	match extension:
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		_:
			return null


func _disable_audio_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED


func _rebuild_asset_registries() -> void:
	_image_assets.clear()
	_audio_assets.clear()
	for mod: Dictionary in _enabled_mods:
		for entry_variant: Variant in mod.get("media_cache", []) as Array:
			if not entry_variant is Dictionary:
				continue
			var entry: Dictionary = entry_variant as Dictionary
			var asset_id: String = String(entry.get("id", ""))
			if _image_assets.has(asset_id) or _audio_assets.has(asset_id):
				_add_diagnostic("%s duplicates a media asset id" % asset_id)
				continue
			if String(entry.get("type", "")) == MEDIA_KIND_IMAGE:
				_image_assets[asset_id] = entry.get("texture")
			elif String(entry.get("type", "")) == MEDIA_KIND_SFX:
				_audio_assets[asset_id] = entry.duplicate()


func _sanitize_mod_media_references(mod: Dictionary, manifest_path: String, package_diagnostics: Array[String]) -> void:
	var valid_image_ids: Dictionary = {}
	var valid_sfx_ids: Dictionary = {}
	for media_variant: Variant in mod.get("media_cache", []) as Array:
		if not media_variant is Dictionary:
			continue
		var media: Dictionary = media_variant as Dictionary
		if String(media.get("type", "")) == MEDIA_KIND_IMAGE:
			valid_image_ids[String(media.get("id", ""))] = true
		elif String(media.get("type", "")) == MEDIA_KIND_SFX:
			valid_sfx_ids[String(media.get("id", ""))] = true
	for patch_variant: Variant in mod.get("cached_patches", []) as Array:
		if not patch_variant is Dictionary:
			continue
		var patch: Dictionary = patch_variant as Dictionary
		if String(patch.get("array_key", "")) != "mods":
			continue
		for item_index: int in range((patch.get("items", []) as Array).size()):
			var item_variant: Variant = (patch.get("items", []) as Array)[item_index]
			if not item_variant is Dictionary:
				continue
			var definition: Dictionary = item_variant as Dictionary
			if definition.has("codex_icon_path"):
				var image_asset_id: String = String(
					definition.get("codex_icon_path", "")
				)
				if not (
					image_asset_id.begins_with(
						_namespace_prefix(String(mod.get("id", "")))
					)
					and valid_image_ids.has(image_asset_id)
				):
					_media_fail(
						package_diagnostics,
						manifest_path,
						"data_patches.mods[%d].codex_icon_path" % item_index,
						"valid package-namespaced image media id; using built-in icon"
					)
					definition.erase("codex_icon_path")
			if definition.has("placement_sfx_id"):
				var sfx_asset_id: String = String(
					definition.get("placement_sfx_id", "")
				)
				if not (
					sfx_asset_id.begins_with(
						_namespace_prefix(String(mod.get("id", "")))
					)
					and valid_sfx_ids.has(sfx_asset_id)
				):
					_media_fail(
						package_diagnostics,
						manifest_path,
						"data_patches.mods[%d].placement_sfx_id" % item_index,
						"valid package-namespaced non-looping SFX media id; using silence"
					)
					definition.erase("placement_sfx_id")


func _gameplay_hash(mod: Dictionary) -> String:
	var gameplay_patches: Array[Dictionary] = []
	for patch_variant: Variant in mod.get("cached_patches", []) as Array:
		if not patch_variant is Dictionary:
			continue
		var patch: Dictionary = patch_variant as Dictionary
		if String(patch.get("target", "")) == "strings.csv":
			continue
		var gameplay_patch: Dictionary = patch.duplicate(true)
		if String(gameplay_patch.get("array_key", "")) == "mods":
			for item_variant: Variant in gameplay_patch.get("items", []) as Array:
				if item_variant is Dictionary:
					var definition: Dictionary = item_variant as Dictionary
					for display_field: String in [
						"name_key",
						"desc_key",
						"codex_icon_path",
						"placement_sfx_id",
					]:
						definition.erase(display_field)
		gameplay_patches.append(gameplay_patch)
	var payload: Dictionary = {
		"id": String(mod.get("id", "")),
		"gear_mod_ids": ((mod.get("contract_extensions", {}) as Dictionary).get("gear_mod_ids", []) as Array).duplicate(),
		"cached_patches": gameplay_patches,
	}
	return JSON.stringify(_normalized_json_value(payload), "", false, true).sha256_text()


func _normalized_json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		var keys: Array = (value as Dictionary).keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
		for key: Variant in keys:
			normalized[String(key)] = _normalized_json_value((value as Dictionary)[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for item: Variant in value as Array:
			normalized_array.append(_normalized_json_value(item))
		return normalized_array
	return value


func _patch_targets_resource(patch: Dictionary, resource_path: String) -> bool:
	return String(patch.get("target", "")) == resource_path.get_file()


func _load_json_file(path: String, package_diagnostics: Array[String]) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		package_diagnostics.append("%s is not readable JSON" % path)
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		package_diagnostics.append("%s is not valid JSON" % path)
		return null
	return parsed


func _load_csv_file(path: String, package_diagnostics: Array[String]) -> Array[Dictionary]:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		package_diagnostics.append("%s is not readable CSV" % path)
		return []
	var rows: Array[Dictionary] = []
	var headers: PackedStringArray = PackedStringArray()
	if not file.eof_reached():
		headers = file.get_csv_line()
	if headers.is_empty():
		package_diagnostics.append("%s has no CSV header" % path)
		return rows
	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() == 0 or (values.size() == 1 and String(values[0]).strip_edges().is_empty()):
			continue
		var row: Dictionary = {}
		for index: int in range(headers.size()):
			row[String(headers[index])] = values[index] if index < values.size() else ""
		rows.append(row)
	return rows


func _read_header(path: String, byte_count: int) -> PackedByteArray:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	return file.get_buffer(mini(byte_count, file.get_length()))


func _header_matches_image(extension: String, header: PackedByteArray) -> bool:
	if extension == "png":
		return _bytes_equal(header, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], 0)
	if extension == "jpg" or extension == "jpeg":
		return _bytes_equal(header, [0xff, 0xd8, 0xff], 0)
	if extension == "webp":
		return _ascii_at(header, "RIFF", 0) and _ascii_at(header, "WEBP", 8)
	return false


func _header_matches_audio(extension: String, header: PackedByteArray) -> bool:
	if extension == "ogg":
		return _ascii_at(header, "OggS", 0)
	if extension == "wav":
		return _ascii_at(header, "RIFF", 0) and _ascii_at(header, "WAVE", 8)
	if extension == "mp3":
		return _ascii_at(header, "ID3", 0) or (header.size() >= 2 and header[0] == 0xff and (header[1] & 0xe0) == 0xe0)
	return false


func _ascii_at(bytes: PackedByteArray, expected: String, offset: int) -> bool:
	return _bytes_equal(bytes, expected.to_utf8_buffer(), offset)


func _bytes_equal(bytes: PackedByteArray, expected: Variant, offset: int) -> bool:
	var expected_bytes: PackedByteArray = expected if expected is PackedByteArray else PackedByteArray(expected)
	if bytes.size() < offset + expected_bytes.size():
		return false
	for index: int in range(expected_bytes.size()):
		if bytes[offset + index] != expected_bytes[index]:
			return false
	return true


func _sort_mods_by_load_order(left: Dictionary, right: Dictionary) -> bool:
	var left_order: int = int(left.get("load_order", 0))
	var right_order: int = int(right.get("load_order", 0))
	if left_order == right_order:
		return String(left.get("id", "")) < String(right.get("id", ""))
	return left_order < right_order


func _is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or path.contains("://") or path.contains(":") or path.contains("\\") or path.begins_with("/"):
		return false
	for segment: String in path.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
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


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func _has_only_keys(data: Dictionary, allowed_keys: Array[String]) -> bool:
	for key_variant: Variant in data.keys():
		if not allowed_keys.has(String(key_variant)):
			return false
	return true


func _namespace_prefix(mod_id: String) -> String:
	return "mod_%s_" % mod_id


func _has_package_id(mod_id: String) -> bool:
	for package: Dictionary in _packages:
		if String(package.get("id", "")) == mod_id:
			return true
	return false


func _record_invalid_package(mod_id: String, version: String, load_order: int, package_diagnostics: Array[String]) -> void:
	_packages.append(_package_status(mod_id, mod_id, version, load_order, false, "invalid", package_diagnostics))
	_flush_package_diagnostics(mod_id, package_diagnostics)


func _package_status(mod_id: String, display_name: String, version: String, load_order: int, enabled: bool, status: String, package_diagnostics: Array[String]) -> Dictionary:
	return {
		"id": mod_id,
		"name": display_name,
		"version": version,
		"load_order": load_order,
		"enabled": enabled,
		"status": status,
		"diagnostics": package_diagnostics.duplicate(),
	}


func _set_package_disabled(package_id: String, reason: String) -> void:
	for package: Dictionary in _packages:
		if String(package.get("id", "")) != package_id:
			continue
		package["enabled"] = false
		package["status"] = "invalid"
		var package_diagnostics: Array = package.get("diagnostics", []) as Array
		package_diagnostics.append(reason)
		_add_diagnostic("%s: %s" % [package_id, reason])
		return


func _package_fail(package_diagnostics: Array[String], manifest_path: String, field_path: String, expected: String) -> bool:
	package_diagnostics.append("%s:%s expected %s" % [manifest_path, field_path, expected])
	return false


func _media_fail(package_diagnostics: Array[String], manifest_path: String, field_path: String, expected: String) -> void:
	package_diagnostics.append("%s:%s media fallback; expected %s" % [manifest_path, field_path, expected])


func _flush_package_diagnostics(mod_id: String, package_diagnostics: Array[String]) -> void:
	for message: String in package_diagnostics:
		_add_diagnostic("%s: %s" % [mod_id, message])


func _copy_variant(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _add_diagnostic(message: String) -> void:
	_diagnostics.append(message)
	push_warning("[ModLoader] %s" % message)
