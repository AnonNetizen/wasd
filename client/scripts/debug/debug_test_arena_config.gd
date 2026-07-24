# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159
class_name DebugTestArenaConfig
extends RefCounted


const CONFIG_PATH: String = "user://debug_test_arena.cfg"
const DEFAULT_CAPACITY: int = 8
const DEFAULT_SEED: int = 424242
const SCHEMA_VERSION: int = 1
const SECTION: String = "arena"


func available_content() -> Dictionary:
	return {
		"characters": _load_items(DataLoader.CHARACTERS_PATH, "characters"),
		"weapons": _load_items(DataLoader.WEAPONS_PATH, "weapons"),
		"skills": _load_items(DataLoader.SKILLS_PATH, "skills"),
		"gear_mods": _load_items(DataLoader.GEAR_MODS_PATH, "mods"),
		"relics": _load_items(DataLoader.RELICS_PATH, "relics"),
		"active_items": _load_items(DataLoader.ACTIVE_ITEMS_PATH, "active_items"),
		"consumables": _load_items(DataLoader.CONSUMABLES_PATH, "consumables"),
	}


func default_config() -> Dictionary:
	return normalize_config({})


func load_config() -> Dictionary:
	var file: ConfigFile = ConfigFile.new()
	var load_error: Error = file.load(CONFIG_PATH)
	if load_error != OK:
		if load_error != ERR_FILE_NOT_FOUND:
			push_warning(
				"[DebugTestArenaConfig] failed to load config; using defaults: %s"
				% error_string(load_error)
			)
		return default_config()
	var raw_config: Dictionary = {
		"schema_version": int(file.get_value(SECTION, "schema_version", 0)),
		"seed": int(file.get_value(SECTION, "seed", DEFAULT_SEED)),
		"character_id": String(file.get_value(SECTION, "character_id", "")),
		"weapon_id": String(file.get_value(SECTION, "weapon_id", "")),
		"primary_skill_id": String(
			file.get_value(SECTION, "primary_skill_id", "")
		),
		"gear_mods": file.get_value(SECTION, "gear_mods", []),
	}
	var normalized: Dictionary = normalize_config(raw_config)
	for diagnostic: Dictionary in _typed_dictionary_array(
		normalized.get("diagnostics", [])
	):
		push_warning(
			"[DebugTestArenaConfig] %s"
			% JSON.stringify(diagnostic)
		)
	return normalized


func save_config(raw_config: Dictionary) -> Dictionary:
	var normalized: Dictionary = normalize_config(raw_config)
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION, "schema_version", SCHEMA_VERSION)
	file.set_value(SECTION, "seed", int(normalized.get("seed", DEFAULT_SEED)))
	file.set_value(
		SECTION,
		"character_id",
		String(normalized.get("character_id", ""))
	)
	file.set_value(
		SECTION,
		"weapon_id",
		String(normalized.get("weapon_id", ""))
	)
	file.set_value(
		SECTION,
		"primary_skill_id",
		String(normalized.get("primary_skill_id", ""))
	)
	file.set_value(
		SECTION,
		"gear_mods",
		normalized.get("gear_mods", []).duplicate(true)
	)
	var save_error: Error = file.save(CONFIG_PATH)
	normalized["saved"] = save_error == OK
	if save_error != OK:
		push_error(
			"[DebugTestArenaConfig] failed to save config: %s"
			% error_string(save_error)
		)
	return normalized


func normalize_config(raw_config: Dictionary) -> Dictionary:
	var content: Dictionary = available_content()
	var diagnostics: Array[Dictionary] = []
	var characters: Array[Dictionary] = _typed_dictionary_array(
		content.get("characters", [])
	)
	var weapons: Array[Dictionary] = _typed_dictionary_array(
		content.get("weapons", [])
	)
	var skills: Array[Dictionary] = _typed_dictionary_array(
		content.get("skills", [])
	)
	var requested_schema: int = int(
		raw_config.get("schema_version", SCHEMA_VERSION)
	)
	if requested_schema != SCHEMA_VERSION:
		diagnostics.append({
			"field": "schema_version",
			"reason": "unsupported_schema",
			"value": requested_schema,
			"fallback": SCHEMA_VERSION,
		})
	var seed: int = int(raw_config.get("seed", DEFAULT_SEED))
	if seed <= 0:
		diagnostics.append({
			"field": "seed",
			"reason": "non_positive_seed",
			"value": seed,
		})
		seed = DEFAULT_SEED
	var character_id: String = _validated_id(
		String(raw_config.get("character_id", "")),
		characters,
		"character_id",
		diagnostics
	)
	var weapon_id: String = _validated_id(
		String(raw_config.get("weapon_id", "")),
		weapons,
		"weapon_id",
		diagnostics
	)
	var skill_id: String = _validated_id(
		String(raw_config.get("primary_skill_id", "")),
		skills,
		"primary_skill_id",
		diagnostics
	)
	var preview: Dictionary = GearModSystem.resolve_preview_loadout(
		_array_or_empty(raw_config.get("gear_mods", [])),
		DEFAULT_CAPACITY
	)
	diagnostics.append_array(
		_typed_dictionary_array(preview.get("diagnostics", []))
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"seed": seed,
		"character_id": character_id,
		"weapon_id": weapon_id,
		"primary_skill_id": skill_id,
		"gear_mods": _config_selections(
			_typed_dictionary_array(preview.get("selected", []))
		),
		"capacity": DEFAULT_CAPACITY,
		"modifier_preview": preview,
		"diagnostics": diagnostics,
	}


func _validated_id(
	requested_id: String,
	items: Array[Dictionary],
	field: String,
	diagnostics: Array[Dictionary]
) -> String:
	for item: Dictionary in items:
		if String(item.get("id", "")) == requested_id:
			return requested_id
	var fallback: String = (
		String(items[0].get("id", ""))
		if not items.is_empty()
		else ""
	)
	if requested_id != fallback:
		diagnostics.append({
			"field": field,
			"reason": "unknown_id",
			"value": requested_id,
			"fallback": fallback,
		})
	return fallback


func _load_items(path: String, key: String) -> Array[Dictionary]:
	var payload: Dictionary = DataLoader.load_json(path)
	return _typed_dictionary_array(payload.get(key, []))


func _config_selections(
	resolved: Array[Dictionary]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for selection: Dictionary in resolved:
		result.append({
			"mod_id": String(selection.get("mod_id", "")),
			"rank": int(selection.get("rank", 0)),
		})
	return result


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []
