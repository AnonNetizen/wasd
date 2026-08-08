# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159
class_name DebugTestArenaConfig
extends RefCounted


const CONFIG_PATH: String = "user://debug_test_arena.cfg"
const DEFAULT_SEED: int = 424242
const SCHEMA_VERSION: int = 4
const SECTION: String = "arena"
const GEAR_MOD_BOARD_SCRIPT := preload(
	"res://scripts/gameplay/gear_mod_board.gd"
)


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
		"main_hero_id": String(
			file.get_value(
				SECTION,
				"main_hero_id",
				file.get_value(SECTION, "character_id", "")
			)
		),
		"sub_hero_id": String(file.get_value(SECTION, "sub_hero_id", "")),
		"weapon_id": String(file.get_value(SECTION, "weapon_id", "")),
		"primary_skill_id": String(
			file.get_value(SECTION, "primary_skill_id", "")
		),
		"gear_mod_placements": file.get_value(
			SECTION,
			"gear_mod_placements",
			[]
		),
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
		"main_hero_id",
		String(normalized.get("main_hero_id", ""))
	)
	file.set_value(
		SECTION,
		"sub_hero_id",
		String(normalized.get("sub_hero_id", ""))
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
		"gear_mod_placements",
		normalized.get("gear_mod_placements", []).duplicate(true)
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
	var source_config: Dictionary = raw_config
	if requested_schema != SCHEMA_VERSION:
		diagnostics.append({
			"field": "schema_version",
			"reason": "unsupported_schema",
			"value": requested_schema,
			"fallback": SCHEMA_VERSION,
		})
		source_config = {}
	var seed: int = int(source_config.get("seed", DEFAULT_SEED))
	if seed <= 0:
		diagnostics.append({
			"field": "seed",
			"reason": "non_positive_seed",
			"value": seed,
		})
		seed = DEFAULT_SEED
	var main_hero_id: String = _validated_id(
		String(
			source_config.get(
				"main_hero_id",
				source_config.get("character_id", "")
			)
		),
		characters,
		"main_hero_id",
		diagnostics
	)
	var sub_hero_id: String = _validated_id(
		String(source_config.get("sub_hero_id", "")),
		characters,
		"sub_hero_id",
		diagnostics
	)
	if sub_hero_id == main_hero_id and characters.size() > 1:
		for character: Dictionary in characters:
			var candidate_id: String = String(character.get("id", ""))
			if candidate_id != main_hero_id:
				sub_hero_id = candidate_id
				break
		diagnostics.append({
			"field": "sub_hero_id",
			"reason": "duplicate_hero",
			"value": main_hero_id,
			"fallback": sub_hero_id,
		})
	var weapon_id: String = _validated_id(
		String(source_config.get("weapon_id", "")),
		weapons,
		"weapon_id",
		diagnostics
	)
	var skill_id: String = _validated_id(
		String(source_config.get("primary_skill_id", "")),
		skills,
		"primary_skill_id",
		diagnostics
	)
	var placement_result: Dictionary = _normalized_gear_mod_placements(
		_array_or_empty(source_config.get("gear_mod_placements", [])),
		diagnostics
	)
	var placements: Array[Dictionary] = _typed_dictionary_array(
		placement_result.get("placements", [])
	)
	var preview_input: Array[Dictionary] = []
	for placement: Dictionary in placements:
		preview_input.append({"mod_id": String(placement.get("mod_id", ""))})
	var preview: Dictionary = GearModSystem.resolve_preview_loadout(preview_input)
	diagnostics.append_array(
		_typed_dictionary_array(preview.get("diagnostics", []))
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"seed": seed,
		"main_hero_id": main_hero_id,
		"sub_hero_id": sub_hero_id,
		"character_id": main_hero_id,
		"weapon_id": weapon_id,
		"primary_skill_id": skill_id,
		"gear_mod_placements": placements,
		"gear_mod_board": _dictionary_or_empty(
			placement_result.get("board_snapshot", {})
		),
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


func _normalized_gear_mod_placements(
	raw_placements: Array,
	diagnostics: Array[Dictionary]
) -> Dictionary:
	var board: GearModBoard = GEAR_MOD_BOARD_SCRIPT.new()
	if not board.configure(
		GearModSystem.board_config(),
		GearModSystem.mod_definitions()
	):
		diagnostics.append({
			"field": "gear_mod_placements",
			"reason": "invalid_board_config",
		})
		return {"placements": [], "board_snapshot": {}}
	var candidates: Array[Dictionary] = []
	var seen_mod_ids: Dictionary = {}
	var seen_cells: Dictionary = {}
	for raw_placement: Variant in raw_placements:
		if raw_placement is not Dictionary:
			diagnostics.append({
				"field": "gear_mod_placements",
				"reason": "invalid_placement",
			})
			continue
		var placement: Dictionary = raw_placement as Dictionary
		if not _has_exact_keys(placement, ["mod_id", "x", "y"]):
			diagnostics.append({
				"field": "gear_mod_placements",
				"reason": "invalid_placement_fields",
				"value": placement.duplicate(true),
			})
			continue
		var mod_id: String = String(placement.get("mod_id", "")).strip_edges()
		var x_value: Variant = placement.get("x")
		var y_value: Variant = placement.get("y")
		if (
			GearModSystem.mod_definition(mod_id).is_empty()
			or not x_value is int
			or not y_value is int
		):
			diagnostics.append({
				"field": "gear_mod_placements",
				"reason": "invalid_mod_or_coord",
				"value": placement.duplicate(true),
			})
			continue
		var cell := Vector2i(int(x_value), int(y_value))
		var cell_key: String = "%d,%d" % [cell.x, cell.y]
		if seen_mod_ids.has(mod_id):
			diagnostics.append({
				"field": "gear_mod_placements",
				"reason": "duplicate_mod",
				"value": mod_id,
			})
			continue
		if seen_cells.has(cell_key):
			diagnostics.append({
				"field": "gear_mod_placements",
				"reason": "occupied_cell",
				"value": {"x": cell.x, "y": cell.y},
			})
			continue
		seen_mod_ids[mod_id] = true
		seen_cells[cell_key] = true
		candidates.append({"mod_id": mod_id, "x": cell.x, "y": cell.y})
	candidates.sort_custom(_placement_less)
	var accepted: Array[Dictionary] = []
	var remaining: Array[Dictionary] = candidates.duplicate(true)
	var next_instance_id: int = 1
	while not remaining.is_empty():
		var placed_one: bool = false
		for index: int in range(remaining.size()):
			var candidate: Dictionary = remaining[index]
			var mod_id: String = String(candidate.get("mod_id", ""))
			var cell := Vector2i(
				int(candidate.get("x", -1)),
				int(candidate.get("y", -1))
			)
			if not board.legal_cells(mod_id).has(cell):
				continue
			if not bool(board.request_placement(
				next_instance_id,
				mod_id,
				cell
			).get("ok", false)):
				continue
			accepted.append(candidate.duplicate(true))
			remaining.remove_at(index)
			next_instance_id += 1
			placed_one = true
			break
		if placed_one:
			continue
		for rejected: Dictionary in remaining:
			diagnostics.append({
				"field": "gear_mod_placements",
				"reason": "illegal_or_disconnected_cell",
				"value": rejected.duplicate(true),
			})
		break
	accepted.sort_custom(_placement_less)
	return {
		"placements": accepted,
		"board_snapshot": board.snapshot(),
	}


func _placement_less(left: Dictionary, right: Dictionary) -> bool:
	var left_y: int = int(left.get("y", -1))
	var right_y: int = int(right.get("y", -1))
	if left_y != right_y:
		return left_y < right_y
	return int(left.get("x", -1)) < int(right.get("x", -1))


func _has_exact_keys(data: Dictionary, expected: Array[String]) -> bool:
	if data.size() != expected.size():
		return false
	for key: String in expected:
		if not data.has(key):
			return false
	return true


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


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}
