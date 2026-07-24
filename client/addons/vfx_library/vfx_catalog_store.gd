# Doc: docs/代码/visual_effects.md
@tool
extends RefCounted
## Editor-only catalog reader, validator, and safe catalog-entry writer.

const EFFECT_CATALOG_PATH := "res://data/visual_effects.json"
const PROFILE_CATALOG_PATH := "res://data/presentation_profiles.json"
const EFFECT_KEYS := ["effects", "visual_effects"]
const PROFILE_KEYS := ["profiles", "presentation_profiles"]
const DOMAINS := [
	"ui",
	"actor",
	"combat",
	"skill",
	"status",
	"pickup",
	"environment",
	"screen",
]
const KINDS := ["spawned_scene", "target_animation", "screen_overlay"]
const SPACES := ["attached", "world", "ground", "screen", "ui"]
const LIFECYCLES := ["one_shot", "loop", "state"]
const FORBIDDEN_RUNTIME_PREFIXES := [
	"res://addons/vfx_library/",
	"res://scripts/editor/",
	"res://tools/",
	"res://output/test_lab/",
]
const NAKED_PRIMITIVE_PREFIX := "res://scenes/vfx/primitives/"

var effects: Array[Dictionary] = []
var profiles: Array[Dictionary] = []
var effect_root: Dictionary = {}
var profile_root: Dictionary = {}
var load_errors := PackedStringArray()


func reload() -> Dictionary:
	effects.clear()
	profiles.clear()
	effect_root.clear()
	profile_root.clear()
	load_errors.clear()
	var effect_result: Dictionary = _read_catalog(EFFECT_CATALOG_PATH, EFFECT_KEYS)
	if bool(effect_result.get("ok", false)):
		effect_root = effect_result.get("root", {}) as Dictionary
		effects = _dictionary_array(effect_result.get("entries", []))
	else:
		load_errors.append_array(_messages(effect_result))
	var profile_result: Dictionary = _read_catalog(PROFILE_CATALOG_PATH, PROFILE_KEYS)
	if bool(profile_result.get("ok", false)):
		profile_root = profile_result.get("root", {}) as Dictionary
		profiles = _dictionary_array(profile_result.get("entries", []))
	else:
		load_errors.append_array(_messages(profile_result))
	return {
		"ok": load_errors.is_empty(),
		"errors": load_errors,
		"effects": effects.size(),
		"profiles": profiles.size(),
	}


func effect_by_id(effect_id: String) -> Dictionary:
	for entry: Dictionary in effects:
		if String(entry.get("id", "")) == effect_id:
			return entry
	return {}


func profile_by_id(profile_id: String) -> Dictionary:
	for entry: Dictionary in profiles:
		if String(entry.get("id", "")) == profile_id:
			return entry
	return {}


func validate_all() -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	errors.append_array(load_errors)
	_validate_effects(errors, warnings)
	_validate_profiles(errors, warnings)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}


func append_effect(entry: Dictionary) -> Dictionary:
	if effect_root.is_empty():
		return _error("效果目录尚未加载，已禁止写入。")
	var effect_id: String = String(entry.get("id", ""))
	if not _is_valid_id(effect_id):
		return _error("效果 ID 必须匹配 ^[a-z][a-z0-9_]*$。")
	if not effect_by_id(effect_id).is_empty():
		return _error("效果 ID 已存在：%s" % effect_id)
	var root_copy: Dictionary = effect_root.duplicate(true)
	var key: String = _existing_key(root_copy, EFFECT_KEYS)
	if key.is_empty():
		key = EFFECT_KEYS[0]
	var entries: Array = root_copy.get(key, []) as Array
	entries.append(entry.duplicate(true))
	entries.sort_custom(_sort_entry_by_id)
	root_copy[key] = entries
	var save_result: Dictionary = _write_json(EFFECT_CATALOG_PATH, root_copy)
	if bool(save_result.get("ok", false)):
		effect_root = root_copy
		effects = _dictionary_array(entries)
	return save_result


func duplicate_effect_entry(source: Dictionary, new_id: String, resource_path: String) -> Dictionary:
	var duplicate: Dictionary = source.duplicate(true)
	duplicate["id"] = new_id
	duplicate["resource_path"] = resource_path
	duplicate["source_effect_id"] = String(source.get("id", ""))
	duplicate.erase("pool_id")
	duplicate.erase("prewarm")
	duplicate.erase("max_size")
	duplicate["high_frequency"] = false
	return duplicate


func _read_catalog(path: String, entry_keys: Array) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("缺少效果目录文件：%s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("无法读取效果目录文件：%s" % path)
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK:
		return _error(
			"%s:%d JSON 解析失败：%s" % [
				path,
				parser.get_error_line(),
				parser.get_error_message(),
			]
		)
	var parsed: Variant = parser.data
	if parsed is Array:
		return {
			"ok": true,
			"errors": PackedStringArray(),
			"root": {entry_keys[0]: parsed},
			"entries": parsed,
		}
	if not parsed is Dictionary:
		return _error("%s 根节点必须是对象或数组。" % path)
	var root: Dictionary = parsed as Dictionary
	var key: String = _existing_key(root, entry_keys)
	if key.is_empty():
		return _error("%s 缺少条目数组 %s。" % [path, "/".join(entry_keys)])
	var entries_value: Variant = root.get(key)
	if not entries_value is Array:
		return _error("%s.%s 必须是数组。" % [path, key])
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"root": root,
		"entries": entries_value,
	}


func _validate_effects(errors: PackedStringArray, warnings: PackedStringArray) -> void:
	var seen: Dictionary = {}
	for index: int in range(effects.size()):
		var entry: Dictionary = effects[index]
		var prefix := "visual_effects[%d]" % index
		var effect_id: String = String(entry.get("id", ""))
		if not _is_valid_id(effect_id):
			errors.append("%s.id 无效：%s" % [prefix, effect_id])
		elif seen.has(effect_id):
			errors.append("%s.id 重复：%s" % [prefix, effect_id])
		else:
			seen[effect_id] = true
		_validate_enum(entry, "domain", DOMAINS, prefix, errors)
		_validate_enum(entry, "kind", KINDS, prefix, errors)
		_validate_enum(entry, "space", SPACES, prefix, errors)
		_validate_enum(entry, "lifecycle", LIFECYCLES, prefix, errors)
		var duration: float = float(entry.get("duration", -1.0))
		if duration < 0.0:
			errors.append("%s.duration 必须大于或等于 0。" % prefix)
		var resource_path: String = String(entry.get("resource_path", ""))
		_validate_resource_path(resource_path, prefix, errors)
		if bool(entry.get("high_frequency", false)):
			if String(entry.get("pool_id", "")).is_empty():
				errors.append("%s 是高频效果，必须提供 pool_id。" % prefix)
		_validate_reduced_motion(entry, prefix, errors)
		_validate_quality_variants(entry, prefix, errors)
		_validate_preview(entry, prefix, errors)
		if not entry.get("tags", []) is Array:
			errors.append("%s.tags 必须是字符串数组。" % prefix)


func _validate_profiles(errors: PackedStringArray, warnings: PackedStringArray) -> void:
	var profile_ids: Dictionary = {}
	for index: int in range(profiles.size()):
		var profile: Dictionary = profiles[index]
		var profile_id: String = String(profile.get("id", ""))
		if not _is_valid_id(profile_id):
			errors.append("presentation_profiles[%d].id 无效：%s" % [index, profile_id])
		elif profile_ids.has(profile_id):
			errors.append("presentation_profiles[%d].id 重复：%s" % [index, profile_id])
		else:
			profile_ids[profile_id] = true
	for profile: Dictionary in profiles:
		var profile_id: String = String(profile.get("id", ""))
		var parent_id: String = String(
			profile.get(
				"parent_profile_id",
				profile.get("parent", profile.get("parent_id", ""))
			)
		)
		if not parent_id.is_empty() and not profile_ids.has(parent_id):
			errors.append("%s 引用了不存在的父 Profile %s。" % [profile_id, parent_id])
		var bindings: Dictionary = _profile_bindings(profile)
		if bindings.is_empty():
			warnings.append("%s 没有 cue 绑定。" % profile_id)
		for cue: Variant in bindings.keys():
			var binding_value: Variant = bindings.get(cue)
			var effect_id: String = _binding_effect_id(binding_value)
			if not effect_id.is_empty() and effect_by_id(effect_id).is_empty():
				errors.append("%s.%s 引用了不存在的效果 %s。" % [profile_id, cue, effect_id])
	_validate_profile_cycles(errors)


func _validate_reduced_motion(
	entry: Dictionary,
	prefix: String,
	errors: PackedStringArray
) -> void:
	var value: Variant = entry.get("reduced_motion")
	if not value is Dictionary:
		errors.append("%s.reduced_motion 必须是对象。" % prefix)
		return
	var policy: Dictionary = value as Dictionary
	var mode: String = String(policy.get("mode", ""))
	if not ["same", "variant", "suppress_optional"].has(mode):
		errors.append("%s.reduced_motion.mode 无效：%s" % [prefix, mode])
	if mode == "variant":
		var variant_id: String = String(policy.get("effect_id", ""))
		if variant_id.is_empty() or effect_by_id(variant_id).is_empty():
			errors.append("%s 的减少动态效果变体不存在：%s" % [prefix, variant_id])


func _validate_quality_variants(
	entry: Dictionary,
	prefix: String,
	errors: PackedStringArray
) -> void:
	var value: Variant = entry.get("quality_variants")
	if not value is Dictionary:
		errors.append("%s.quality_variants 必须是对象。" % prefix)
		return
	var variants: Dictionary = value as Dictionary
	for quality_value: Variant in variants.keys():
		var quality: String = String(quality_value)
		if not ["low", "medium", "high"].has(quality):
			errors.append("%s.quality_variants 包含无效质量 %s。" % [prefix, quality])
			continue
		var variant_id: String = String(variants.get(quality, ""))
		if variant_id.is_empty() or effect_by_id(variant_id).is_empty():
			errors.append("%s 的质量变体不存在：%s" % [prefix, variant_id])


func _validate_preview(
	entry: Dictionary,
	prefix: String,
	errors: PackedStringArray
) -> void:
	var value: Variant = entry.get("preview")
	if not value is Dictionary:
		errors.append("%s.preview 必须是对象。" % prefix)
		return
	var preview: Dictionary = value as Dictionary
	var background: String = String(preview.get("background", ""))
	if not ["dark", "combat", "light"].has(background):
		errors.append("%s.preview.background 无效：%s" % [prefix, background])
	var checkpoint: String = String(preview.get("checkpoint", ""))
	if not ["charge", "contact", "aftermath"].has(checkpoint):
		errors.append("%s.preview.checkpoint 无效：%s" % [prefix, checkpoint])
	if float(preview.get("scale", 0.0)) <= 0.0:
		errors.append("%s.preview.scale 必须大于 0。" % prefix)


func _validate_profile_cycles(errors: PackedStringArray) -> void:
	var parent_by_id: Dictionary = {}
	for profile: Dictionary in profiles:
		var profile_id: String = String(profile.get("id", ""))
		var parent_id: String = String(
			profile.get(
				"parent_profile_id",
				profile.get("parent", profile.get("parent_id", ""))
			)
		)
		if not profile_id.is_empty() and not parent_id.is_empty():
			parent_by_id[profile_id] = parent_id
	for profile_id_value: Variant in parent_by_id.keys():
		var profile_id: String = String(profile_id_value)
		var cursor := profile_id
		var visited: Dictionary = {}
		while parent_by_id.has(cursor):
			if visited.has(cursor):
				errors.append("表现 Profile 继承存在环：%s" % profile_id)
				break
			visited[cursor] = true
			cursor = String(parent_by_id.get(cursor, ""))


func _validate_resource_path(
	resource_path: String,
	prefix: String,
	errors: PackedStringArray
) -> void:
	if resource_path.is_empty():
		errors.append("%s.resource_path 不能为空。" % prefix)
		return
	if not resource_path.begins_with("res://"):
		errors.append("%s.resource_path 必须位于 res:// 下。" % prefix)
		return
	for forbidden_prefix: String in FORBIDDEN_RUNTIME_PREFIXES:
		if resource_path.begins_with(forbidden_prefix):
			errors.append("%s 引用了 editor-only 路径 %s。" % [prefix, resource_path])
	if resource_path.begins_with(NAKED_PRIMITIVE_PREFIX):
		errors.append("%s 不能直接登记裸程序几何原语。" % prefix)
	if not ResourceLoader.exists(resource_path):
		errors.append("%s 的资源不存在：%s" % [prefix, resource_path])


func _validate_enum(
	entry: Dictionary,
	field: String,
	allowed: Array,
	prefix: String,
	errors: PackedStringArray
) -> void:
	var value: String = String(entry.get(field, ""))
	if not allowed.has(value):
		errors.append("%s.%s 无效：%s" % [prefix, field, value])


func _write_json(path: String, data: Dictionary) -> Dictionary:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var file: FileAccess = FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return _error("无法打开文件进行写入：%s" % path)
	file.store_string(JSON.stringify(data, "  ", false, true))
	file.store_string("\n")
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _error("写入失败：%s（%s）" % [path, error_string(write_error)])
	return {"ok": true, "errors": PackedStringArray()}


func _profile_bindings(profile: Dictionary) -> Dictionary:
	var value: Variant = profile.get("bindings", profile.get("cues", {}))
	return value as Dictionary if value is Dictionary else {}


func _binding_effect_id(binding_value: Variant) -> String:
	if binding_value is String:
		return String(binding_value)
	if binding_value is Dictionary:
		var binding: Dictionary = binding_value as Dictionary
		return String(binding.get("effect_id", binding.get("effect", "")))
	return ""


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		if item is Dictionary:
			result.append(item as Dictionary)
	return result


func _messages(result: Dictionary) -> PackedStringArray:
	var result_value: Variant = result.get("errors", PackedStringArray())
	if result_value is PackedStringArray:
		return result_value as PackedStringArray
	var messages := PackedStringArray()
	if result_value is Array:
		for message: Variant in result_value as Array:
			messages.append(String(message))
	return messages


func _existing_key(root: Dictionary, keys: Array) -> String:
	for key_value: Variant in keys:
		var key := String(key_value)
		if root.has(key):
			return key
	return ""


func _is_valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	var expression := RegEx.new()
	if expression.compile("^[a-z][a-z0-9_]*$") != OK:
		return false
	return expression.search(value) != null


func _sort_entry_by_id(left: Variant, right: Variant) -> bool:
	if not left is Dictionary or not right is Dictionary:
		return false
	return String((left as Dictionary).get("id", "")) < String(
		(right as Dictionary).get("id", "")
	)


func _error(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
