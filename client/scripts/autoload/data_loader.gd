# Doc: docs/代码/data_loader.md
# Authority: docs/游戏设计文档.md §9.3, docs/词表与契约.md
class_name DataLoaderAutoload
extends Node


const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_EDGE_DIRECTIONS := preload("res://scripts/contracts/module_edge_directions.gd")
const MODULE_PLACEMENT_TYPES := preload("res://scripts/contracts/module_placement_types.gd")
const MODULE_REVIEW_STATUSES := preload("res://scripts/contracts/module_review_statuses.gd")
const MODULE_ROLES := preload("res://scripts/contracts/module_roles.gd")

signal data_reloaded()

const CONTRACTS_PATH: String = "res://data/_contracts.json"
const DATA_ROOT: String = "res://data/"
const LOCALE_STRINGS_PATH: String = "res://locale/strings.csv"
const PLAYER_DATA_PATH: String = "res://data/player.json"
const CHARACTERS_PATH: String = "res://data/characters.json"
const WEAPONS_PATH: String = "res://data/weapons.json"
const ENEMIES_PATH: String = "res://data/enemies.csv"
const ENEMY_AI_PROFILES_PATH: String = "res://data/enemy_ai_profiles.json"
const HAZARDS_PATH: String = "res://data/hazards.csv"
const SPAWN_WAVES_PATH: String = "res://data/spawn_waves.csv"
const RELICS_PATH: String = "res://data/relics.json"
const ACTIVE_ITEMS_PATH: String = "res://data/active_items.json"
const CONSUMABLES_PATH: String = "res://data/consumables.json"
const SKILLS_PATH: String = "res://data/skills.json"
const CREDITS_PATH: String = "res://data/credits.json"
const GROWTH_CURVE_PATH: String = "res://data/growth.csv"
const GROWTH_POOLS_PATH: String = "res://data/growth_pools.json"
const GAME_MODES_PATH: String = "res://data/game_modes.json"
const MAP_LAYOUTS_PATH: String = "res://data/map_layouts.json"
const WARZONE_DIRECTORS_PATH: String = "res://data/warzone_directors.json"
const MODULE_WORLDS_PATH: String = "res://data/module_worlds.json"
const MODULE_TEMPLATES_PATH: String = "res://data/module_templates.json"
const GEAR_MODS_PATH: String = "res://data/gear_mods.json"
const GEAR_MOD_DROP_TABLES_PATH: String = "res://data/gear_mod_drop_tables.csv"
const GEAR_MOD_FUSION_COSTS_PATH: String = "res://data/gear_mod_fusion_costs.csv"

const INT_STATS: Array[String] = ["bullet_count", "pierce_count"]
const NON_NEGATIVE_STATS: Array[String] = [
	"damage",
	"damage_invulnerability_duration",
	"health_regen",
	"player_separation_radius",
	"pickup_range",
	"luck",
	"armor",
	"lifesteal_ratio",
]
const POSITIVE_STATS: Array[String] = ["max_hp", "move_speed", "fire_rate", "bullet_speed", "bullet_range", "pickup_orb_speed", "crit_mult"]
const RATIO_STATS: Array[String] = ["crit_chance", "resist_fire", "resist_poison", "resist_lightning", "lifesteal_ratio"]
const WEAPON_STATS: Array[String] = ["damage", "fire_rate", "bullet_speed", "bullet_range", "bullet_count", "pierce_count", "crit_chance", "crit_mult"]
const REQUIRED_WEAPON_STATS: Array[String] = ["damage", "fire_rate", "bullet_speed", "bullet_range", "bullet_count"]

var _contracts: Dictionary = {}
var _last_schema_counts: Dictionary = {}


func _ready() -> void:
	reload_contracts()


func reload_contracts() -> void:
	var payload: Variant = load_json(CONTRACTS_PATH)
	if not payload is Dictionary:
		_fail(CONTRACTS_PATH, "root", "Dictionary")
		return

	var payload_dict: Dictionary = payload as Dictionary
	if not payload_dict.has("contracts") or not payload_dict["contracts"] is Dictionary:
		_fail(CONTRACTS_PATH, "contracts", "Dictionary")
		return

	_contracts = payload_dict["contracts"] as Dictionary
	data_reloaded.emit()


func contracts() -> Dictionary:
	var merged_contracts: Dictionary = _contracts.duplicate(true)
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("contract_extensions"):
		return merged_contracts

	for key_variant: Variant in merged_contracts.keys():
		var key: String = String(key_variant)
		var extensions: Array = loader.call("contract_extensions", key) as Array
		if extensions.is_empty():
			continue
		var values: Array = merged_contracts[key_variant] as Array
		for extension: Variant in extensions:
			if not values.has(extension):
				values.append(extension)
	return merged_contracts


func contract_values(contract_id: String) -> Array:
	var extensions: Array = _mod_contract_extensions(contract_id)
	if not _contracts.has(contract_id) and extensions.is_empty():
		_fail(CONTRACTS_PATH, "contracts.%s" % contract_id, "registered contract id")
		return []

	var values: Array = []
	if _contracts.has(contract_id):
		var base_values: Variant = _contracts[contract_id]
		if not base_values is Array:
			_fail(CONTRACTS_PATH, "contracts.%s" % contract_id, "Array")
			return []
		values = (base_values as Array).duplicate()

	for extension: Variant in extensions:
		if not values.has(extension):
			values.append(extension)

	if values.is_empty():
		_fail(CONTRACTS_PATH, "contracts.%s" % contract_id, "Array")
		return []

	return values


func has_contract_value(contract_id: String, value: String) -> bool:
	return contract_values(contract_id).has(value)


func validate_project_data() -> bool:
	var locale_keys: Dictionary = _collect_locale_keys()
	var is_valid: bool = true
	_last_schema_counts.clear()
	_last_schema_counts["mods"] = _mod_count()

	is_valid = _validate_locale_strings(locale_keys) and is_valid
	is_valid = _validate_player_json() and is_valid
	is_valid = _validate_weapons_json(locale_keys) and is_valid
	var weapon_ids: Dictionary = _collect_weapon_ids()
	is_valid = _validate_enemy_ai_profiles_json() and is_valid
	var enemy_ai_profile_ids: Dictionary = _collect_enemy_ai_profile_ids()
	is_valid = _validate_enemies_csv(locale_keys, enemy_ai_profile_ids) and is_valid
	var enemy_ids: Dictionary = _collect_enemy_ids()
	is_valid = _validate_gear_mods_json(locale_keys) and is_valid
	var gear_mod_ids: Dictionary = _collect_gear_mod_ids()
	var gear_mod_rarity_max_ranks: Dictionary = _collect_gear_mod_rarity_max_ranks()
	is_valid = _validate_gear_mod_drop_tables_csv(enemy_ids, gear_mod_ids) and is_valid
	is_valid = _validate_gear_mod_fusion_costs_csv(gear_mod_rarity_max_ranks) and is_valid
	is_valid = _validate_hazards_csv(locale_keys) and is_valid
	var hazard_ids: Dictionary = _collect_hazard_ids()
	is_valid = _validate_relics_json(locale_keys) and is_valid
	var relic_ids: Dictionary = _collect_relic_ids()
	is_valid = _validate_active_items_json(locale_keys) and is_valid
	var active_item_ids: Dictionary = _collect_active_item_ids()
	is_valid = _validate_consumables_json(locale_keys) and is_valid
	var consumable_ids: Dictionary = _collect_consumable_ids()
	is_valid = _validate_skills_json(locale_keys) and is_valid
	var skill_ids: Dictionary = _collect_skill_ids()
	is_valid = _validate_credits_json(locale_keys) and is_valid
	is_valid = _validate_characters_json(locale_keys, weapon_ids, active_item_ids, consumable_ids, skill_ids) and is_valid
	var character_ids: Dictionary = _collect_character_ids()
	is_valid = _validate_growth_csv() and is_valid
	is_valid = _validate_growth_pools(locale_keys) and is_valid
	is_valid = _validate_game_modes(locale_keys, character_ids, weapon_ids, enemy_ids, hazard_ids, relic_ids, active_item_ids, consumable_ids, skill_ids) and is_valid
	var game_mode_ids: Dictionary = _collect_game_mode_ids()
	is_valid = _validate_map_layouts_json(hazard_ids, game_mode_ids) and is_valid
	is_valid = _validate_spawn_waves_csv(enemy_ids, hazard_ids, game_mode_ids) and is_valid
	is_valid = _validate_warzone_directors_json(game_mode_ids, _collect_spawn_wave_ids_by_mode(), hazard_ids, _collect_map_layout_ids(), gear_mod_ids) and is_valid
	is_valid = _validate_module_world_data(enemy_ids, hazard_ids) and is_valid

	return is_valid


func schema_counts() -> Dictionary:
	return _last_schema_counts.duplicate(true)


func load_json(resource_path: String) -> Variant:
	var file: FileAccess = FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		_fail(resource_path, "file", "readable JSON file")
		return {}

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_fail(resource_path, "json", "valid JSON")
		return {}

	return _apply_json_mods(resource_path, parsed)


func load_csv(resource_path: String, has_header: bool = true) -> Array[Dictionary]:
	var file: FileAccess = FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		_fail(resource_path, "file", "readable CSV file")
		return []

	var rows: Array[Dictionary] = []
	var headers: PackedStringArray = PackedStringArray()

	if has_header and not file.eof_reached():
		headers = file.get_csv_line()

	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if _is_empty_csv_row(values):
			continue

		var row: Dictionary = {}
		if has_header:
			for index: int in range(headers.size()):
				row[String(headers[index])] = values[index] if index < values.size() else ""
		else:
			for index: int in range(values.size()):
				row[String.num_int64(index)] = values[index]
		rows.append(row)

	return _apply_csv_mods(resource_path, rows)


func data_path(file_name: String) -> String:
	return DATA_ROOT.path_join(file_name)


func mod_diagnostics() -> Array[String]:
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("diagnostics"):
		return []
	var raw_diagnostics: Array = loader.call("diagnostics") as Array
	var typed_diagnostics: Array[String] = []
	for diagnostic: Variant in raw_diagnostics:
		typed_diagnostics.append(String(diagnostic))
	return typed_diagnostics


func _apply_json_mods(resource_path: String, data: Variant) -> Variant:
	if resource_path == CONTRACTS_PATH:
		return data
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("apply_json_mods"):
		return data
	return loader.call("apply_json_mods", resource_path, data)


func _apply_csv_mods(resource_path: String, rows: Array[Dictionary]) -> Array[Dictionary]:
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("apply_csv_mods"):
		return rows
	var raw_rows: Array = loader.call("apply_csv_mods", resource_path, rows) as Array
	var typed_rows: Array[Dictionary] = []
	for row: Variant in raw_rows:
		if row is Dictionary:
			typed_rows.append(row as Dictionary)
	return typed_rows


func _mod_contract_extensions(contract_id: String) -> Array:
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("contract_extensions"):
		return []
	return loader.call("contract_extensions", contract_id) as Array


func _mod_count() -> int:
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("enabled_mod_count"):
		return 0
	return int(loader.call("enabled_mod_count"))


func _validate_locale_strings(_locale_keys: Dictionary) -> bool:
	var rows: Array[Dictionary] = _load_locale_string_rows()
	if rows.is_empty() and _should_collect_locale_keys_from_translations():
		_last_schema_counts["locale_keys"] = 0
		return true

	var is_valid: bool = true
	var seen_keys: Dictionary = {}
	_last_schema_counts["locale_keys"] = rows.size()
	for index: int in range(rows.size()):
		var field: String = "line %d" % (index + 2)
		var row: Dictionary = rows[index]
		var key: String = String(row.get("keys", ""))
		if key.is_empty():
			is_valid = _schema_fail(LOCALE_STRINGS_PATH, field, "non-empty keys") and is_valid
			continue
		if not _has_registered_prefix("locale_prefixes", key):
			is_valid = _schema_fail(LOCALE_STRINGS_PATH, field, "key prefix registered in locale_prefixes") and is_valid
		if String(row.get("zh_CN", "")).is_empty():
			is_valid = _schema_fail(LOCALE_STRINGS_PATH, "%s.zh_CN" % field, "non-empty translation") and is_valid
		if String(row.get("en", "")).is_empty():
			is_valid = _schema_fail(LOCALE_STRINGS_PATH, "%s.en" % field, "non-empty translation") and is_valid
		if seen_keys.has(key):
			is_valid = _schema_fail(LOCALE_STRINGS_PATH, field, "unique locale key") and is_valid
		seen_keys[key] = true
	return is_valid


func _validate_player_json() -> bool:
	var data: Variant = load_json(PLAYER_DATA_PATH)
	if not data is Dictionary:
		return _schema_fail(PLAYER_DATA_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(PLAYER_DATA_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var base_stats: Variant = payload.get("base_stats")
	if not base_stats is Dictionary or (base_stats as Dictionary).is_empty():
		return _schema_fail(PLAYER_DATA_PATH, "base_stats", "non-empty Dictionary")

	var stats_dict: Dictionary = base_stats as Dictionary
	_last_schema_counts["player_stats"] = stats_dict.size()
	for stat_key: Variant in stats_dict.keys():
		var stat: String = String(stat_key)
		is_valid = _validate_stat_value(PLAYER_DATA_PATH, "base_stats.%s" % stat, stat, stats_dict[stat_key]) and is_valid
	return is_valid


func _validate_characters_json(locale_keys: Dictionary, weapon_ids: Dictionary, active_item_ids: Dictionary, consumable_ids: Dictionary, skill_ids: Dictionary) -> bool:
	var data: Variant = load_json(CHARACTERS_PATH)
	if not data is Dictionary:
		return _schema_fail(CHARACTERS_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(CHARACTERS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var characters: Array = _require_array(CHARACTERS_PATH, "characters", payload.get("characters"))
	if characters.is_empty():
		is_valid = _schema_fail(CHARACTERS_PATH, "characters", "non-empty Array") and is_valid
	var seen: Dictionary = {}
	_last_schema_counts["characters"] = characters.size()
	for index: int in range(characters.size()):
		var field: String = "characters[%d]" % index
		var character: Variant = characters[index]
		if not character is Dictionary:
			is_valid = _schema_fail(CHARACTERS_PATH, field, "Dictionary") and is_valid
			continue
		var character_dict: Dictionary = character as Dictionary
		var character_id: String = _require_registered(CHARACTERS_PATH, "%s.id" % field, character_dict.get("id"), "character_ids")
		if not character_id.is_empty():
			if seen.has(character_id):
				is_valid = _schema_fail(CHARACTERS_PATH, "%s.id" % field, "unique character id") and is_valid
			seen[character_id] = true
		is_valid = _require_locale_key(CHARACTERS_PATH, "%s.name_key" % field, character_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(CHARACTERS_PATH, "%s.desc_key" % field, character_dict.get("desc_key"), locale_keys) and is_valid
		is_valid = _require_bool(CHARACTERS_PATH, "%s.default_unlocked" % field, character_dict.get("default_unlocked")) and is_valid
		var tags: Array = _require_array(CHARACTERS_PATH, "%s.tags" % field, character_dict.get("tags"))
		is_valid = _validate_registered_string_array(CHARACTERS_PATH, "%s.tags" % field, tags, "content_tags", false) and is_valid
		if not tags.has("tag_character"):
			is_valid = _schema_fail(CHARACTERS_PATH, "%s.tags" % field, "tag_character") and is_valid
		is_valid = _validate_registered_string_array(CHARACTERS_PATH, "%s.capabilities" % field, character_dict.get("capabilities", []), "capabilities", true) and is_valid
		is_valid = _require_non_empty_string(CHARACTERS_PATH, "%s.control_profile" % field, character_dict.get("control_profile")) and is_valid
		is_valid = _validate_character_starting_loadout("%s.starting_loadout" % field, character_dict.get("starting_loadout"), weapon_ids, active_item_ids, consumable_ids, skill_ids) and is_valid
		is_valid = _validate_character_skill_resources("%s.skill_resources" % field, character_dict.get("skill_resources", [])) and is_valid
		var base_stats: Variant = character_dict.get("base_stats")
		if not base_stats is Dictionary or (base_stats as Dictionary).is_empty():
			is_valid = _schema_fail(CHARACTERS_PATH, "%s.base_stats" % field, "non-empty Dictionary") and is_valid
		else:
			var stats_dict: Dictionary = base_stats as Dictionary
			for stat_key: Variant in stats_dict.keys():
				var stat: String = String(stat_key)
				is_valid = _validate_stat_value(CHARACTERS_PATH, "%s.base_stats.%s" % [field, stat], stat, stats_dict[stat_key]) and is_valid
	return is_valid


func _validate_character_starting_loadout(field: String, data: Variant, weapon_ids: Dictionary, active_item_ids: Dictionary, consumable_ids: Dictionary, skill_ids: Dictionary) -> bool:
	if not data is Dictionary:
		return _schema_fail(CHARACTERS_PATH, field, "Dictionary")
	var loadout: Dictionary = data as Dictionary
	var is_valid: bool = true
	var weapon_id: String = String(loadout.get("weapon_id", ""))
	is_valid = _require_non_empty_string(CHARACTERS_PATH, "%s.weapon_id" % field, loadout.get("weapon_id")) and is_valid
	if not weapon_id.is_empty() and not weapon_ids.has(weapon_id):
		is_valid = _schema_fail(CHARACTERS_PATH, "%s.weapon_id" % field, "weapon defined in weapons.json") and is_valid
	var active_item_id: String = String(loadout.get("active_item_id", ""))
	is_valid = _require_non_empty_string(CHARACTERS_PATH, "%s.active_item_id" % field, loadout.get("active_item_id")) and is_valid
	if not active_item_id.is_empty() and not active_item_ids.has(active_item_id):
		is_valid = _schema_fail(CHARACTERS_PATH, "%s.active_item_id" % field, "active item defined in active_items.json") and is_valid
	var starting_consumables: Array = _require_array(CHARACTERS_PATH, "%s.consumable_ids" % field, loadout.get("consumable_ids"))
	var seen_consumables: Dictionary = {}
	for index: int in range(starting_consumables.size()):
		var item_field: String = "%s.consumable_ids[%d]" % [field, index]
		var consumable_id: String = String(starting_consumables[index])
		is_valid = _require_non_empty_string(CHARACTERS_PATH, item_field, starting_consumables[index]) and is_valid
		if not consumable_id.is_empty():
			if seen_consumables.has(consumable_id):
				is_valid = _schema_fail(CHARACTERS_PATH, item_field, "unique consumable id") and is_valid
			seen_consumables[consumable_id] = true
			if not consumable_ids.has(consumable_id):
				is_valid = _schema_fail(CHARACTERS_PATH, item_field, "consumable defined in consumables.json") and is_valid
	var starting_skills: Array = _require_array(CHARACTERS_PATH, "%s.skill_ids" % field, loadout.get("skill_ids", []))
	var seen_skills: Dictionary = {}
	for index: int in range(starting_skills.size()):
		var skill_field: String = "%s.skill_ids[%d]" % [field, index]
		var skill_id: String = _require_registered(CHARACTERS_PATH, skill_field, starting_skills[index], "skill_ids")
		if skill_id.is_empty():
			is_valid = false
			continue
		if seen_skills.has(skill_id):
			is_valid = _schema_fail(CHARACTERS_PATH, skill_field, "unique skill id") and is_valid
		seen_skills[skill_id] = true
		if not skill_ids.has(skill_id):
			is_valid = _schema_fail(CHARACTERS_PATH, skill_field, "skill defined in skills.json") and is_valid
	return is_valid


func _validate_character_skill_resources(field: String, data: Variant) -> bool:
	var resources: Array = _require_array(CHARACTERS_PATH, field, data)
	var is_valid: bool = true
	var seen: Dictionary = {}
	for index: int in range(resources.size()):
		var resource_field: String = "%s[%d]" % [field, index]
		var resource: Variant = resources[index]
		if not resource is Dictionary:
			is_valid = _schema_fail(CHARACTERS_PATH, resource_field, "Dictionary") and is_valid
			continue
		var resource_dict: Dictionary = resource as Dictionary
		var resource_id: String = _require_registered(CHARACTERS_PATH, "%s.id" % resource_field, resource_dict.get("id"), "skill_resources")
		if not resource_id.is_empty():
			if seen.has(resource_id):
				is_valid = _schema_fail(CHARACTERS_PATH, "%s.id" % resource_field, "unique skill resource id") and is_valid
			seen[resource_id] = true
		is_valid = _require_number(CHARACTERS_PATH, "%s.max" % resource_field, resource_dict.get("max"), 0.0, null, true) and is_valid
		is_valid = _require_number(CHARACTERS_PATH, "%s.start" % resource_field, resource_dict.get("start"), 0.0) and is_valid
		is_valid = _require_number(CHARACTERS_PATH, "%s.regen_per_second" % resource_field, resource_dict.get("regen_per_second"), 0.0) and is_valid
		var max_value: Variant = resource_dict.get("max")
		var start_value: Variant = resource_dict.get("start")
		if (max_value is int or max_value is float) and (start_value is int or start_value is float) and float(start_value) > float(max_value):
			is_valid = _schema_fail(CHARACTERS_PATH, "%s.start" % resource_field, "<= max") and is_valid
	return is_valid


func _validate_weapons_json(locale_keys: Dictionary) -> bool:
	var data: Variant = load_json(WEAPONS_PATH)
	if not data is Dictionary:
		return _schema_fail(WEAPONS_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(WEAPONS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var weapons: Array = _require_array(WEAPONS_PATH, "weapons", payload.get("weapons"))
	if weapons.is_empty():
		is_valid = _schema_fail(WEAPONS_PATH, "weapons", "non-empty Array") and is_valid
	var seen: Dictionary = {}
	_last_schema_counts["weapons"] = weapons.size()
	for index: int in range(weapons.size()):
		var field: String = "weapons[%d]" % index
		var weapon: Variant = weapons[index]
		if not weapon is Dictionary:
			is_valid = _schema_fail(WEAPONS_PATH, field, "Dictionary") and is_valid
			continue
		var weapon_dict: Dictionary = weapon as Dictionary
		is_valid = _require_non_empty_string(WEAPONS_PATH, "%s.id" % field, weapon_dict.get("id")) and is_valid
		var weapon_id: String = String(weapon_dict.get("id", ""))
		if not weapon_id.is_empty():
			if seen.has(weapon_id):
				is_valid = _schema_fail(WEAPONS_PATH, "%s.id" % field, "unique weapon id") and is_valid
			seen[weapon_id] = true
		is_valid = _require_locale_key(WEAPONS_PATH, "%s.name_key" % field, weapon_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(WEAPONS_PATH, "%s.desc_key" % field, weapon_dict.get("desc_key"), locale_keys) and is_valid
		is_valid = _require_bool(WEAPONS_PATH, "%s.default_unlocked" % field, weapon_dict.get("default_unlocked")) and is_valid
		is_valid = _require_non_empty_string(WEAPONS_PATH, "%s.fire_mode" % field, weapon_dict.get("fire_mode")) and is_valid
		if weapon_dict.has("fire_audio_id"):
			is_valid = _require_audio_id(WEAPONS_PATH, "%s.fire_audio_id" % field, weapon_dict.get("fire_audio_id")) and is_valid
		is_valid = _validate_weapon_stats("%s.base_stats" % field, weapon_dict.get("base_stats")) and is_valid
		is_valid = _validate_weapon_projectile("%s.projectile" % field, weapon_dict.get("projectile")) and is_valid
	return is_valid


func _validate_weapon_stats(field: String, data: Variant) -> bool:
	if not data is Dictionary or (data as Dictionary).is_empty():
		return _schema_fail(WEAPONS_PATH, field, "non-empty Dictionary")
	var stats: Dictionary = data as Dictionary
	var is_valid: bool = true
	for required_stat: String in REQUIRED_WEAPON_STATS:
		if not stats.has(required_stat):
			is_valid = _schema_fail(WEAPONS_PATH, "%s.%s" % [field, required_stat], "required weapon stat") and is_valid
	for stat_key: Variant in stats.keys():
		var stat: String = String(stat_key)
		if not WEAPON_STATS.has(stat):
			is_valid = _schema_fail(WEAPONS_PATH, "%s.%s" % [field, stat], "supported weapon stat") and is_valid
			continue
		if stat == "pierce_count":
			is_valid = _require_int(WEAPONS_PATH, "%s.%s" % [field, stat], stats[stat_key], 0) and is_valid
		else:
			is_valid = _validate_stat_value(WEAPONS_PATH, "%s.%s" % [field, stat], stat, stats[stat_key]) and is_valid
	return is_valid


func _validate_weapon_projectile(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(WEAPONS_PATH, field, "Dictionary")
	var projectile: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_registered(WEAPONS_PATH, "%s.pool_id" % field, projectile.get("pool_id"), "pool_ids") != "" and is_valid
	is_valid = _require_registered(WEAPONS_PATH, "%s.damage_type" % field, projectile.get("damage_type"), "damage_types") != "" and is_valid
	is_valid = _require_number(WEAPONS_PATH, "%s.hit_radius" % field, projectile.get("hit_radius"), 0.0, null, true) and is_valid
	is_valid = _require_number(WEAPONS_PATH, "%s.muzzle_distance" % field, projectile.get("muzzle_distance"), 0.0, null, true) and is_valid
	is_valid = _require_number(WEAPONS_PATH, "%s.lifetime" % field, projectile.get("lifetime"), 0.0, null, true) and is_valid
	return is_valid


func _validate_enemy_ai_profiles_json() -> bool:
	var data: Variant = load_json(ENEMY_AI_PROFILES_PATH)
	if not data is Dictionary:
		return _schema_fail(ENEMY_AI_PROFILES_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(ENEMY_AI_PROFILES_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var profiles: Array = _require_array(ENEMY_AI_PROFILES_PATH, "profiles", payload.get("profiles"))
	if profiles.is_empty():
		is_valid = _schema_fail(ENEMY_AI_PROFILES_PATH, "profiles", "non-empty Array") and is_valid
	_last_schema_counts["enemy_ai_profiles"] = profiles.size()
	var seen: Dictionary = {}
	for index: int in range(profiles.size()):
		var field: String = "profiles[%d]" % index
		var profile: Variant = profiles[index]
		if not profile is Dictionary:
			is_valid = _schema_fail(ENEMY_AI_PROFILES_PATH, field, "Dictionary") and is_valid
			continue
		var profile_dict: Dictionary = profile as Dictionary
		is_valid = _require_non_empty_string(ENEMY_AI_PROFILES_PATH, "%s.id" % field, profile_dict.get("id")) and is_valid
		var profile_id: String = String(profile_dict.get("id", ""))
		if not profile_id.is_empty():
			if seen.has(profile_id):
				is_valid = _schema_fail(ENEMY_AI_PROFILES_PATH, "%s.id" % field, "unique profile id") and is_valid
			seen[profile_id] = true
		is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.sense_radius" % field, profile_dict.get("sense_radius"), 0.0, null, true) and is_valid
		is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.decision_interval" % field, profile_dict.get("decision_interval"), 0.0, null, true) and is_valid
		is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.contact_interval" % field, profile_dict.get("contact_interval"), 0.0) and is_valid
		is_valid = _validate_enemy_ai_targeting("%s.targeting" % field, profile_dict.get("targeting")) and is_valid
		is_valid = _validate_enemy_ai_movement("%s.movement" % field, profile_dict.get("movement")) and is_valid
		is_valid = _validate_enemy_ai_actions("%s.actions" % field, profile_dict.get("actions")) and is_valid
	return is_valid


func _validate_enemy_ai_targeting(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(ENEMY_AI_PROFILES_PATH, field, "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.player_weight" % field, payload.get("player_weight"), 0.0) and is_valid
	is_valid = _validate_enemy_ai_tag_weights("%s.hunt_tags" % field, payload.get("hunt_tags")) and is_valid
	is_valid = _validate_enemy_ai_tag_weights("%s.flee_tags" % field, payload.get("flee_tags")) and is_valid
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.territory_radius" % field, payload.get("territory_radius"), 0.0) and is_valid
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.territory_weight" % field, payload.get("territory_weight"), 0.0) and is_valid
	return is_valid


func _validate_enemy_ai_tag_weights(field: String, data: Variant) -> bool:
	var entries: Array = _require_array(ENEMY_AI_PROFILES_PATH, field, data)
	var is_valid: bool = true
	var seen: Dictionary = {}
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(ENEMY_AI_PROFILES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		var tag: String = _require_registered(ENEMY_AI_PROFILES_PATH, "%s.tag" % item_field, entry_dict.get("tag"), "content_tags")
		if not tag.is_empty():
			if seen.has(tag):
				is_valid = _schema_fail(ENEMY_AI_PROFILES_PATH, "%s.tag" % item_field, "unique tag") and is_valid
			seen[tag] = true
		is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0.0) and is_valid
	return is_valid


func _validate_enemy_ai_movement(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(ENEMY_AI_PROFILES_PATH, field, "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.orbit_radius" % field, payload.get("orbit_radius"), 0.0) and is_valid
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.flee_distance" % field, payload.get("flee_distance"), 0.0, null, true) and is_valid
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.charge_range" % field, payload.get("charge_range"), 0.0) and is_valid
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.charge_windup" % field, payload.get("charge_windup"), 0.0) and is_valid
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.charge_duration" % field, payload.get("charge_duration"), 0.0) and is_valid
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.charge_cooldown" % field, payload.get("charge_cooldown"), 0.0) and is_valid
	is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.charge_speed_scale" % field, payload.get("charge_speed_scale"), 0.0, null, true) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_attack_range", 0.0, true) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_keep_distance", 0.0, false) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_cooldown", 0.0, true) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_initial_cooldown", 0.0, false) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_projectile_damage", 0.0, true) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_projectile_speed", 0.0, true) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_projectile_range", 0.0, true) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_projectile_hit_radius", 0.0, true) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_projectile_lifetime", 0.0, true) and is_valid
	is_valid = _validate_optional_enemy_ai_movement_number(field, payload, "ranged_projectile_muzzle_distance", 0.0, false) and is_valid
	if payload.has("ranged_projectile_damage_type"):
		is_valid = _require_registered(ENEMY_AI_PROFILES_PATH, "%s.ranged_projectile_damage_type" % field, payload.get("ranged_projectile_damage_type"), "damage_types") != "" and is_valid
	return is_valid


func _validate_optional_enemy_ai_movement_number(field: String, payload: Dictionary, key: String, minimum: float, exclusive_minimum: bool) -> bool:
	if not payload.has(key):
		return true
	return _require_number(ENEMY_AI_PROFILES_PATH, "%s.%s" % [field, key], payload.get(key), minimum, null, exclusive_minimum)


func _validate_enemy_ai_actions(field: String, data: Variant) -> bool:
	var entries: Array = _require_array(ENEMY_AI_PROFILES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(ENEMY_AI_PROFILES_PATH, field, "non-empty Array") and is_valid
	var seen: Dictionary = {}
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(ENEMY_AI_PROFILES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		var action_id: String = _require_registered(ENEMY_AI_PROFILES_PATH, "%s.id" % item_field, entry_dict.get("id"), "enemy_ai_actions")
		if not action_id.is_empty():
			if seen.has(action_id):
				is_valid = _schema_fail(ENEMY_AI_PROFILES_PATH, "%s.id" % item_field, "unique action id") and is_valid
			seen[action_id] = true
		is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.base_score" % item_field, entry_dict.get("base_score"), 0.0) and is_valid
		is_valid = _require_number(ENEMY_AI_PROFILES_PATH, "%s.speed_scale" % item_field, entry_dict.get("speed_scale"), 0.0, null, true) and is_valid
	return is_valid


func _validate_enemies_csv(locale_keys: Dictionary, enemy_ai_profile_ids: Dictionary) -> bool:
	var rows: Array[Dictionary] = load_csv(ENEMIES_PATH)
	var is_valid: bool = true
	var seen: Dictionary = {}
	if rows.is_empty():
		is_valid = _schema_fail(ENEMIES_PATH, "rows", "non-empty CSV") and is_valid
	_last_schema_counts["enemies"] = rows.size()
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var field: String = "line %d" % (index + 2)
		var enemy_id: String = String(row.get("id", ""))
		is_valid = _require_non_empty_string(ENEMIES_PATH, "%s.id" % field, row.get("id")) and is_valid
		if not enemy_id.is_empty():
			if seen.has(enemy_id):
				is_valid = _schema_fail(ENEMIES_PATH, "%s.id" % field, "unique enemy id") and is_valid
			seen[enemy_id] = true
		is_valid = _require_locale_key(ENEMIES_PATH, "%s.name_key" % field, row.get("name_key"), locale_keys) and is_valid
		var tags: Array[String] = _parse_tag_list(row.get("tags"))
		is_valid = _validate_registered_string_array(ENEMIES_PATH, "%s.tags" % field, tags, "content_tags", false) and is_valid
		if not tags.has("tag_enemy"):
			is_valid = _schema_fail(ENEMIES_PATH, "%s.tags" % field, "tag_enemy") and is_valid
		is_valid = _require_registered(ENEMIES_PATH, "%s.pool_id" % field, row.get("pool_id"), "pool_ids") != "" and is_valid
		var ai_profile_id: String = String(row.get("ai_profile_id", ""))
		is_valid = _require_non_empty_string(ENEMIES_PATH, "%s.ai_profile_id" % field, row.get("ai_profile_id")) and is_valid
		if not ai_profile_id.is_empty() and not enemy_ai_profile_ids.has(ai_profile_id):
			is_valid = _schema_fail(ENEMIES_PATH, "%s.ai_profile_id" % field, "profile defined in enemy_ai_profiles.json") and is_valid
		is_valid = _require_csv_int(ENEMIES_PATH, "%s.max_hp" % field, row.get("max_hp"), 1) and is_valid
		is_valid = _require_csv_number(ENEMIES_PATH, "%s.move_speed" % field, row.get("move_speed"), 0.0, null, true) and is_valid
		is_valid = _require_csv_int(ENEMIES_PATH, "%s.contact_damage" % field, row.get("contact_damage"), 0) and is_valid
		is_valid = _require_registered(ENEMIES_PATH, "%s.contact_damage_type" % field, row.get("contact_damage_type"), "damage_types") != "" and is_valid
		is_valid = _require_csv_int(ENEMIES_PATH, "%s.exp_reward" % field, row.get("exp_reward"), 0) and is_valid
		is_valid = _require_csv_number(ENEMIES_PATH, "%s.hit_radius" % field, row.get("hit_radius"), 0.0, null, true) and is_valid
		is_valid = _require_csv_number(ENEMIES_PATH, "%s.separation_radius" % field, row.get("separation_radius"), 0.0) and is_valid
		is_valid = _require_html_color(ENEMIES_PATH, "%s.visual_color" % field, row.get("visual_color")) and is_valid
	return is_valid


func _validate_hazards_csv(locale_keys: Dictionary) -> bool:
	var rows: Array[Dictionary] = load_csv(HAZARDS_PATH)
	var is_valid: bool = true
	var seen: Dictionary = {}
	if rows.is_empty():
		is_valid = _schema_fail(HAZARDS_PATH, "rows", "non-empty CSV") and is_valid
	_last_schema_counts["hazards"] = rows.size()
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var field: String = "line %d" % (index + 2)
		var hazard_id: String = String(row.get("id", ""))
		is_valid = _require_non_empty_string(HAZARDS_PATH, "%s.id" % field, row.get("id")) and is_valid
		if not hazard_id.is_empty():
			if seen.has(hazard_id):
				is_valid = _schema_fail(HAZARDS_PATH, "%s.id" % field, "unique hazard id") and is_valid
			seen[hazard_id] = true
		is_valid = _require_locale_key(HAZARDS_PATH, "%s.name_key" % field, row.get("name_key"), locale_keys) and is_valid
		var tags: Array[String] = _parse_tag_list(row.get("tags"))
		is_valid = _validate_registered_string_array(HAZARDS_PATH, "%s.tags" % field, tags, "content_tags", false) and is_valid
		if not tags.has("tag_hazard"):
			is_valid = _schema_fail(HAZARDS_PATH, "%s.tags" % field, "tag_hazard") and is_valid
		is_valid = _require_registered(HAZARDS_PATH, "%s.pool_id" % field, row.get("pool_id"), "pool_ids") != "" and is_valid
		is_valid = _require_csv_int(HAZARDS_PATH, "%s.damage" % field, row.get("damage"), 0) and is_valid
		is_valid = _require_registered(HAZARDS_PATH, "%s.damage_type" % field, row.get("damage_type"), "damage_types") != "" and is_valid
		is_valid = _require_csv_number(HAZARDS_PATH, "%s.trigger_interval" % field, row.get("trigger_interval"), 0.0, null, true) and is_valid
		is_valid = _require_csv_int(HAZARDS_PATH, "%s.radius_tiles" % field, row.get("radius_tiles"), 1) and is_valid
		is_valid = _require_csv_number(HAZARDS_PATH, "%s.duration" % field, row.get("duration"), 0.0) and is_valid
	return is_valid


func _validate_spawn_waves_csv(enemy_ids: Dictionary, hazard_ids: Dictionary, game_mode_ids: Dictionary) -> bool:
	var rows: Array[Dictionary] = load_csv(SPAWN_WAVES_PATH)
	var is_valid: bool = true
	var seen_ids: Dictionary = {}
	var seen_mode_waves: Dictionary = {}
	if rows.is_empty():
		is_valid = _schema_fail(SPAWN_WAVES_PATH, "rows", "non-empty CSV") and is_valid
	_last_schema_counts["spawn_waves"] = rows.size()
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var field: String = "line %d" % (index + 2)
		var wave_id: String = String(row.get("id", ""))
		is_valid = _require_non_empty_string(SPAWN_WAVES_PATH, "%s.id" % field, row.get("id")) and is_valid
		if not wave_id.is_empty():
			if seen_ids.has(wave_id):
				is_valid = _schema_fail(SPAWN_WAVES_PATH, "%s.id" % field, "unique wave id") and is_valid
			seen_ids[wave_id] = true
		var mode_id: String = _require_registered(SPAWN_WAVES_PATH, "%s.mode_id" % field, row.get("mode_id"), "game_modes")
		if not mode_id.is_empty() and not game_mode_ids.has(mode_id):
			is_valid = _schema_fail(SPAWN_WAVES_PATH, "%s.mode_id" % field, "mode defined in game_modes.json") and is_valid
		var wave_index: Variant = _parse_int(row.get("wave_index"))
		is_valid = _require_int(SPAWN_WAVES_PATH, "%s.wave_index" % field, wave_index, 1) and is_valid
		if not mode_id.is_empty() and _is_int_like(wave_index):
			var mode_wave_key: String = "%s:%d" % [mode_id, _variant_to_int(wave_index)]
			if seen_mode_waves.has(mode_wave_key):
				is_valid = _schema_fail(SPAWN_WAVES_PATH, "%s.wave_index" % field, "unique per mode") and is_valid
			seen_mode_waves[mode_wave_key] = true
		var start_time: Variant = _parse_float(row.get("start_time"))
		var end_time: Variant = _parse_float(row.get("end_time"))
		is_valid = _require_number(SPAWN_WAVES_PATH, "%s.start_time" % field, start_time, 0.0) and is_valid
		is_valid = _require_number(SPAWN_WAVES_PATH, "%s.end_time" % field, end_time, 0.0, null, true) and is_valid
		if (start_time is int or start_time is float) and (end_time is int or end_time is float) and float(end_time) <= float(start_time):
			is_valid = _schema_fail(SPAWN_WAVES_PATH, "%s.end_time" % field, "greater than start_time") and is_valid
		var enemy_id: String = String(row.get("enemy_id", ""))
		is_valid = _require_non_empty_string(SPAWN_WAVES_PATH, "%s.enemy_id" % field, row.get("enemy_id")) and is_valid
		if not enemy_id.is_empty() and not enemy_ids.has(enemy_id):
			is_valid = _schema_fail(SPAWN_WAVES_PATH, "%s.enemy_id" % field, "enemy defined in enemies.csv") and is_valid
		is_valid = _require_csv_int(SPAWN_WAVES_PATH, "%s.enemy_weight" % field, row.get("enemy_weight"), 1) and is_valid
		is_valid = _require_csv_number(SPAWN_WAVES_PATH, "%s.spawn_interval" % field, row.get("spawn_interval"), 0.0, null, true) and is_valid
		is_valid = _require_csv_int(SPAWN_WAVES_PATH, "%s.max_alive" % field, row.get("max_alive"), 1) and is_valid
		is_valid = _require_csv_int(SPAWN_WAVES_PATH, "%s.spawn_budget" % field, row.get("spawn_budget"), 0) and is_valid
		var hazard_id: String = String(row.get("hazard_id", ""))
		var hazard_weight: Variant = _parse_int(row.get("hazard_weight"))
		is_valid = _require_int(SPAWN_WAVES_PATH, "%s.hazard_weight" % field, hazard_weight, 0) and is_valid
		if not hazard_id.is_empty() and not hazard_ids.has(hazard_id):
			is_valid = _schema_fail(SPAWN_WAVES_PATH, "%s.hazard_id" % field, "hazard defined in hazards.csv") and is_valid
		if hazard_id.is_empty() and _is_int_like(hazard_weight) and _variant_to_int(hazard_weight) > 0:
			is_valid = _schema_fail(SPAWN_WAVES_PATH, "%s.hazard_id" % field, "non-empty when hazard_weight > 0") and is_valid
	return is_valid


func _validate_relics_json(locale_keys: Dictionary) -> bool:
	var data: Variant = load_json(RELICS_PATH)
	if not data is Dictionary:
		return _schema_fail(RELICS_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(RELICS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var relics: Array = _require_array(RELICS_PATH, "relics", payload.get("relics"))
	if relics.is_empty():
		is_valid = _schema_fail(RELICS_PATH, "relics", "non-empty Array") and is_valid
	var seen: Dictionary = {}
	_last_schema_counts["relics"] = relics.size()
	for index: int in range(relics.size()):
		var field: String = "relics[%d]" % index
		var relic: Variant = relics[index]
		if not relic is Dictionary:
			is_valid = _schema_fail(RELICS_PATH, field, "Dictionary") and is_valid
			continue
		var relic_dict: Dictionary = relic as Dictionary
		is_valid = _require_non_empty_string(RELICS_PATH, "%s.id" % field, relic_dict.get("id")) and is_valid
		var relic_id: String = String(relic_dict.get("id", ""))
		if not relic_id.is_empty():
			if seen.has(relic_id):
				is_valid = _schema_fail(RELICS_PATH, "%s.id" % field, "unique relic id") and is_valid
			seen[relic_id] = true
		is_valid = _require_locale_key(RELICS_PATH, "%s.name_key" % field, relic_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(RELICS_PATH, "%s.desc_key" % field, relic_dict.get("desc_key"), locale_keys) and is_valid
		is_valid = _require_bool(RELICS_PATH, "%s.default_unlocked" % field, relic_dict.get("default_unlocked")) and is_valid
		var tags: Array = _require_array(RELICS_PATH, "%s.tags" % field, relic_dict.get("tags"))
		is_valid = _validate_registered_string_array(RELICS_PATH, "%s.tags" % field, tags, "content_tags", false) and is_valid
		if not tags.has("tag_relic"):
			is_valid = _schema_fail(RELICS_PATH, "%s.tags" % field, "tag_relic") and is_valid
		var modifiers: Array = _require_array(RELICS_PATH, "%s.modifiers" % field, relic_dict.get("modifiers"))
		var behaviors: Array = _require_array(RELICS_PATH, "%s.behaviors" % field, relic_dict.get("behaviors"))
		is_valid = _validate_modifiers(RELICS_PATH, "%s.modifiers" % field, modifiers, false) and is_valid
		is_valid = _validate_behaviors(RELICS_PATH, "%s.behaviors" % field, behaviors) and is_valid
		if modifiers.is_empty() and behaviors.is_empty():
			is_valid = _schema_fail(RELICS_PATH, field, "at least one modifier or behavior") and is_valid
	return is_valid


func _validate_active_items_json(locale_keys: Dictionary) -> bool:
	var data: Variant = load_json(ACTIVE_ITEMS_PATH)
	if not data is Dictionary:
		return _schema_fail(ACTIVE_ITEMS_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(ACTIVE_ITEMS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var active_items: Array = _require_array(ACTIVE_ITEMS_PATH, "active_items", payload.get("active_items"))
	if active_items.is_empty():
		is_valid = _schema_fail(ACTIVE_ITEMS_PATH, "active_items", "non-empty Array") and is_valid
	var seen: Dictionary = {}
	_last_schema_counts["active_items"] = active_items.size()
	for index: int in range(active_items.size()):
		var field: String = "active_items[%d]" % index
		var active_item: Variant = active_items[index]
		if not active_item is Dictionary:
			is_valid = _schema_fail(ACTIVE_ITEMS_PATH, field, "Dictionary") and is_valid
			continue
		var item_dict: Dictionary = active_item as Dictionary
		is_valid = _require_non_empty_string(ACTIVE_ITEMS_PATH, "%s.id" % field, item_dict.get("id")) and is_valid
		var item_id: String = String(item_dict.get("id", ""))
		if not item_id.is_empty():
			if seen.has(item_id):
				is_valid = _schema_fail(ACTIVE_ITEMS_PATH, "%s.id" % field, "unique active item id") and is_valid
			seen[item_id] = true
		is_valid = _require_locale_key(ACTIVE_ITEMS_PATH, "%s.name_key" % field, item_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(ACTIVE_ITEMS_PATH, "%s.desc_key" % field, item_dict.get("desc_key"), locale_keys) and is_valid
		is_valid = _require_bool(ACTIVE_ITEMS_PATH, "%s.default_unlocked" % field, item_dict.get("default_unlocked")) and is_valid
		var tags: Array = _require_array(ACTIVE_ITEMS_PATH, "%s.tags" % field, item_dict.get("tags"))
		is_valid = _validate_registered_string_array(ACTIVE_ITEMS_PATH, "%s.tags" % field, tags, "content_tags", false) and is_valid
		if not tags.has("tag_active_item"):
			is_valid = _schema_fail(ACTIVE_ITEMS_PATH, "%s.tags" % field, "tag_active_item") and is_valid
		is_valid = _validate_active_item_charge("%s.charge" % field, item_dict.get("charge")) and is_valid
		is_valid = _validate_active_item_use_effects("%s.use_effects" % field, item_dict.get("use_effects")) and is_valid
	return is_valid


func _validate_active_item_charge(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(ACTIVE_ITEMS_PATH, field, "Dictionary")
	var charge: Dictionary = data as Dictionary
	var is_valid: bool = true
	var mode: String = String(charge.get("mode", ""))
	is_valid = _require_non_empty_string(ACTIVE_ITEMS_PATH, "%s.mode" % field, charge.get("mode")) and is_valid
	if not mode.is_empty() and mode != "cooldown":
		is_valid = _schema_fail(ACTIVE_ITEMS_PATH, "%s.mode" % field, "cooldown") and is_valid
	is_valid = _require_number(ACTIVE_ITEMS_PATH, "%s.cooldown" % field, charge.get("cooldown"), 0.0, null, true) and is_valid
	is_valid = _require_int(ACTIVE_ITEMS_PATH, "%s.max_charges" % field, charge.get("max_charges"), 1) and is_valid
	is_valid = _require_int(ACTIVE_ITEMS_PATH, "%s.start_charges" % field, charge.get("start_charges"), 0) and is_valid
	var max_charges: Variant = charge.get("max_charges")
	var start_charges: Variant = charge.get("start_charges")
	if _is_int_like(max_charges) and _is_int_like(start_charges) and _variant_to_int(start_charges) > _variant_to_int(max_charges):
		is_valid = _schema_fail(ACTIVE_ITEMS_PATH, "%s.start_charges" % field, "<= max_charges") and is_valid
	return is_valid


func _validate_active_item_use_effects(field: String, data: Variant) -> bool:
	var effects: Array = _require_array(ACTIVE_ITEMS_PATH, field, data)
	var is_valid: bool = true
	if effects.is_empty():
		is_valid = _schema_fail(ACTIVE_ITEMS_PATH, field, "non-empty Array") and is_valid
	for index: int in range(effects.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var effect: Variant = effects[index]
		if not effect is Dictionary:
			is_valid = _schema_fail(ACTIVE_ITEMS_PATH, item_field, "Dictionary") and is_valid
			continue
		var effect_dict: Dictionary = effect as Dictionary
		is_valid = _require_registered(ACTIVE_ITEMS_PATH, "%s.effect" % item_field, effect_dict.get("effect"), "effects") != "" and is_valid
		if not effect_dict.get("params") is Dictionary:
			is_valid = _schema_fail(ACTIVE_ITEMS_PATH, "%s.params" % item_field, "Dictionary") and is_valid
	return is_valid


func _validate_skills_json(locale_keys: Dictionary) -> bool:
	var data: Variant = load_json(SKILLS_PATH)
	if not data is Dictionary:
		return _schema_fail(SKILLS_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(SKILLS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var skills: Array = _require_array(SKILLS_PATH, "skills", payload.get("skills"))
	if skills.is_empty():
		is_valid = _schema_fail(SKILLS_PATH, "skills", "non-empty Array") and is_valid
	var seen: Dictionary = {}
	_last_schema_counts["skills"] = skills.size()
	for index: int in range(skills.size()):
		var field: String = "skills[%d]" % index
		var skill: Variant = skills[index]
		if not skill is Dictionary:
			is_valid = _schema_fail(SKILLS_PATH, field, "Dictionary") and is_valid
			continue
		var skill_dict: Dictionary = skill as Dictionary
		var skill_id: String = _require_registered(SKILLS_PATH, "%s.id" % field, skill_dict.get("id"), "skill_ids")
		if not skill_id.is_empty():
			if seen.has(skill_id):
				is_valid = _schema_fail(SKILLS_PATH, "%s.id" % field, "unique skill id") and is_valid
			seen[skill_id] = true
		is_valid = _require_locale_key(SKILLS_PATH, "%s.name_key" % field, skill_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(SKILLS_PATH, "%s.desc_key" % field, skill_dict.get("desc_key"), locale_keys) and is_valid
		is_valid = _require_bool(SKILLS_PATH, "%s.default_unlocked" % field, skill_dict.get("default_unlocked")) and is_valid
		var tags: Array = _require_array(SKILLS_PATH, "%s.tags" % field, skill_dict.get("tags"))
		is_valid = _validate_registered_string_array(SKILLS_PATH, "%s.tags" % field, tags, "content_tags", false) and is_valid
		if not tags.has("tag_skill"):
			is_valid = _schema_fail(SKILLS_PATH, "%s.tags" % field, "tag_skill") and is_valid
		is_valid = _validate_registered_string_array(SKILLS_PATH, "%s.ability_tags" % field, skill_dict.get("ability_tags"), "ability_tags", false) and is_valid
		is_valid = _validate_skill_activation("%s.activation" % field, skill_dict.get("activation")) and is_valid
		is_valid = _require_number(SKILLS_PATH, "%s.cooldown" % field, skill_dict.get("cooldown"), 0.0) and is_valid
		is_valid = _validate_skill_costs("%s.costs" % field, skill_dict.get("costs")) and is_valid
		is_valid = _validate_skill_targeting("%s.targeting" % field, skill_dict.get("targeting")) and is_valid
		is_valid = _validate_skill_effects("%s.effects" % field, skill_dict.get("effects")) and is_valid
	return is_valid


func _validate_skill_activation(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(SKILLS_PATH, field, "Dictionary")
	var activation: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _validate_registered_string_array(SKILLS_PATH, "%s.required_tags" % field, activation.get("required_tags"), "ability_tags", true) and is_valid
	is_valid = _validate_registered_string_array(SKILLS_PATH, "%s.blocked_tags" % field, activation.get("blocked_tags"), "ability_tags", true) and is_valid
	is_valid = _validate_registered_string_array(SKILLS_PATH, "%s.granted_tags" % field, activation.get("granted_tags"), "ability_tags", true) and is_valid
	return is_valid


func _validate_skill_costs(field: String, data: Variant) -> bool:
	var costs: Array = _require_array(SKILLS_PATH, field, data)
	var is_valid: bool = true
	var seen: Dictionary = {}
	for index: int in range(costs.size()):
		var cost_field: String = "%s[%d]" % [field, index]
		var cost: Variant = costs[index]
		if not cost is Dictionary:
			is_valid = _schema_fail(SKILLS_PATH, cost_field, "Dictionary") and is_valid
			continue
		var cost_dict: Dictionary = cost as Dictionary
		var resource_id: String = _require_registered(SKILLS_PATH, "%s.resource" % cost_field, cost_dict.get("resource"), "skill_resources")
		if not resource_id.is_empty():
			if seen.has(resource_id):
				is_valid = _schema_fail(SKILLS_PATH, "%s.resource" % cost_field, "unique resource id") and is_valid
			seen[resource_id] = true
		is_valid = _require_number(SKILLS_PATH, "%s.amount" % cost_field, cost_dict.get("amount"), 0.0) and is_valid
	return is_valid


func _validate_skill_targeting(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(SKILLS_PATH, field, "Dictionary")
	var targeting: Dictionary = data as Dictionary
	var is_valid: bool = true
	var targeting_type: String = _require_registered(SKILLS_PATH, "%s.type" % field, targeting.get("type"), "skill_targeting")
	if targeting_type == "aoe_enemies_around_caster":
		is_valid = _require_number(SKILLS_PATH, "%s.radius" % field, targeting.get("radius"), 0.0, null, true) and is_valid
	if targeting.has("max_targets"):
		is_valid = _require_int(SKILLS_PATH, "%s.max_targets" % field, targeting.get("max_targets"), 0) and is_valid
	return is_valid


func _validate_skill_effects(field: String, data: Variant) -> bool:
	var effects: Array = _require_array(SKILLS_PATH, field, data)
	var is_valid: bool = true
	if effects.is_empty():
		is_valid = _schema_fail(SKILLS_PATH, field, "non-empty Array") and is_valid
	for index: int in range(effects.size()):
		var effect_field: String = "%s[%d]" % [field, index]
		var effect: Variant = effects[index]
		if not effect is Dictionary:
			is_valid = _schema_fail(SKILLS_PATH, effect_field, "Dictionary") and is_valid
			continue
		var effect_dict: Dictionary = effect as Dictionary
		var effect_id: String = _require_registered(SKILLS_PATH, "%s.effect" % effect_field, effect_dict.get("effect"), "skill_effects")
		var params: Variant = effect_dict.get("params")
		if not params is Dictionary:
			is_valid = _schema_fail(SKILLS_PATH, "%s.params" % effect_field, "Dictionary") and is_valid
			continue
		if effect_id == "skill_effect_damage":
			var params_dict: Dictionary = params as Dictionary
			is_valid = _require_number(SKILLS_PATH, "%s.params.amount" % effect_field, params_dict.get("amount"), 0.0, null, true) and is_valid
			is_valid = _require_registered(SKILLS_PATH, "%s.params.damage_type" % effect_field, params_dict.get("damage_type"), "damage_types") != "" and is_valid
		if effect_id == "skill_effect_apply_status":
			var status_params: Dictionary = params as Dictionary
			is_valid = _require_registered(SKILLS_PATH, "%s.params.status" % effect_field, status_params.get("status"), "status_effects") != "" and is_valid
			is_valid = _require_number(SKILLS_PATH, "%s.params.duration" % effect_field, status_params.get("duration"), 0.0, null, true) and is_valid
			is_valid = _require_registered(SKILLS_PATH, "%s.params.stack_rule" % effect_field, status_params.get("stack_rule"), "status_stack_rules") != "" and is_valid
			is_valid = _validate_registered_string_array(SKILLS_PATH, "%s.params.granted_ability_tags" % effect_field, status_params.get("granted_ability_tags"), "ability_tags", true) and is_valid
			if status_params.has("magnitude"):
				is_valid = _require_number(SKILLS_PATH, "%s.params.magnitude" % effect_field, status_params.get("magnitude")) and is_valid
			if status_params.has("tick_interval"):
				is_valid = _require_number(SKILLS_PATH, "%s.params.tick_interval" % effect_field, status_params.get("tick_interval"), 0.0) and is_valid
			if status_params.has("damage_type"):
				is_valid = _require_registered(SKILLS_PATH, "%s.params.damage_type" % effect_field, status_params.get("damage_type"), "damage_types") != "" and is_valid
			elif _status_params_has_damage_tick(status_params):
				is_valid = _schema_fail(SKILLS_PATH, "%s.params.damage_type" % effect_field, "registered damage_type when magnitude and tick_interval are positive") and is_valid
		if effect_id == "skill_effect_weapon_modifiers":
			var modifier_params: Dictionary = params as Dictionary
			is_valid = _require_number(SKILLS_PATH, "%s.params.duration" % effect_field, modifier_params.get("duration"), 0.0, null, true) and is_valid
			is_valid = _validate_modifiers(SKILLS_PATH, "%s.params.modifiers" % effect_field, modifier_params.get("modifiers"), false) and is_valid
	return is_valid


func _validate_gear_mods_json(locale_keys: Dictionary) -> bool:
	var data: Variant = load_json(GEAR_MODS_PATH)
	if not data is Dictionary:
		return _schema_fail(GEAR_MODS_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(GEAR_MODS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var mods: Array = _require_array(GEAR_MODS_PATH, "mods", payload.get("mods"))
	if mods.is_empty():
		is_valid = _schema_fail(GEAR_MODS_PATH, "mods", "non-empty Array") and is_valid
	var seen: Dictionary = {}
	_last_schema_counts["gear_mods"] = mods.size()
	for index: int in range(mods.size()):
		var field: String = "mods[%d]" % index
		var mod: Variant = mods[index]
		if not mod is Dictionary:
			is_valid = _schema_fail(GEAR_MODS_PATH, field, "Dictionary") and is_valid
			continue
		var mod_dict: Dictionary = mod as Dictionary
		var mod_id: String = _require_registered(GEAR_MODS_PATH, "%s.id" % field, mod_dict.get("id"), "gear_mod_ids")
		if not mod_id.is_empty():
			if seen.has(mod_id):
				is_valid = _schema_fail(GEAR_MODS_PATH, "%s.id" % field, "unique gear_mod_id") and is_valid
			seen[mod_id] = true
		is_valid = _require_locale_key(GEAR_MODS_PATH, "%s.name_key" % field, mod_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(GEAR_MODS_PATH, "%s.desc_key" % field, mod_dict.get("desc_key"), locale_keys) and is_valid
		is_valid = _require_registered(GEAR_MODS_PATH, "%s.slot" % field, mod_dict.get("slot"), "gear_mod_slots") != "" and is_valid
		is_valid = _require_registered(GEAR_MODS_PATH, "%s.rarity" % field, mod_dict.get("rarity"), "gear_mod_rarities") != "" and is_valid
		is_valid = _require_int(GEAR_MODS_PATH, "%s.max_rank" % field, mod_dict.get("max_rank"), 0) and is_valid
		is_valid = _require_int(GEAR_MODS_PATH, "%s.base_drain" % field, mod_dict.get("base_drain"), 0) and is_valid
		is_valid = _require_int(GEAR_MODS_PATH, "%s.drain_per_rank" % field, mod_dict.get("drain_per_rank"), 0) and is_valid
		is_valid = _validate_gear_mod_rank_modifiers("%s.rank_modifiers" % field, mod_dict.get("rank_modifiers")) and is_valid
		is_valid = _require_registered(GEAR_MODS_PATH, "%s.stack_rule" % field, mod_dict.get("stack_rule"), "gear_mod_stack_rules") != "" and is_valid
		is_valid = _validate_gear_mod_dismantle("%s.dismantle" % field, mod_dict.get("dismantle")) and is_valid
	return is_valid


func _validate_gear_mod_rank_modifiers(field: String, data: Variant) -> bool:
	var modifiers: Array = _require_array(GEAR_MODS_PATH, field, data)
	var is_valid: bool = true
	if modifiers.is_empty():
		is_valid = _schema_fail(GEAR_MODS_PATH, field, "non-empty Array") and is_valid
	for index: int in range(modifiers.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var modifier: Variant = modifiers[index]
		if not modifier is Dictionary:
			is_valid = _schema_fail(GEAR_MODS_PATH, item_field, "Dictionary") and is_valid
			continue
		var modifier_dict: Dictionary = modifier as Dictionary
		is_valid = _require_registered(GEAR_MODS_PATH, "%s.stat" % item_field, modifier_dict.get("stat"), "stats") != "" and is_valid
		var modifier_type: String = String(modifier_dict.get("type", ""))
		if modifier_type != "add" and modifier_type != "mult":
			is_valid = _schema_fail(GEAR_MODS_PATH, "%s.type" % item_field, "add or mult") and is_valid
		is_valid = _require_number(GEAR_MODS_PATH, "%s.base_value" % item_field, modifier_dict.get("base_value")) and is_valid
		is_valid = _require_number(GEAR_MODS_PATH, "%s.value_per_rank" % item_field, modifier_dict.get("value_per_rank")) and is_valid
	return is_valid


func _validate_gear_mod_dismantle(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(GEAR_MODS_PATH, field, "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_registered(GEAR_MODS_PATH, "%s.resource_id" % field, payload.get("resource_id"), "gear_mod_resources") != "" and is_valid
	is_valid = _require_int(GEAR_MODS_PATH, "%s.amount" % field, payload.get("amount"), 0) and is_valid
	return is_valid


func _validate_gear_mod_drop_tables_csv(enemy_ids: Dictionary, gear_mod_ids: Dictionary) -> bool:
	var rows: Array[Dictionary] = load_csv(GEAR_MOD_DROP_TABLES_PATH)
	var is_valid: bool = true
	if rows.is_empty():
		is_valid = _schema_fail(GEAR_MOD_DROP_TABLES_PATH, "rows", "non-empty CSV") and is_valid
	var seen: Dictionary = {}
	_last_schema_counts["gear_mod_drop_rows"] = rows.size()
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var field: String = "line %d" % (index + 2)
		var source_enemy_id: String = String(row.get("source_enemy_id", ""))
		if source_enemy_id.is_empty():
			is_valid = _schema_fail(GEAR_MOD_DROP_TABLES_PATH, "%s.source_enemy_id" % field, "non-empty string") and is_valid
		elif not enemy_ids.has(source_enemy_id):
			is_valid = _schema_fail(GEAR_MOD_DROP_TABLES_PATH, "%s.source_enemy_id" % field, "enemy defined in enemies.csv") and is_valid
		var mod_id: String = String(row.get("mod_id", ""))
		if mod_id.is_empty():
			is_valid = _schema_fail(GEAR_MOD_DROP_TABLES_PATH, "%s.mod_id" % field, "non-empty string") and is_valid
		elif not gear_mod_ids.has(mod_id):
			is_valid = _schema_fail(GEAR_MOD_DROP_TABLES_PATH, "%s.mod_id" % field, "gear mod defined in gear_mods.json") and is_valid
		is_valid = _require_csv_number(GEAR_MOD_DROP_TABLES_PATH, "%s.drop_chance" % field, row.get("drop_chance"), 0.0, 1.0) and is_valid
		var min_level_ok: bool = _require_csv_int(GEAR_MOD_DROP_TABLES_PATH, "%s.min_enemy_level" % field, row.get("min_enemy_level"), 1)
		var max_level_ok: bool = _require_csv_int(GEAR_MOD_DROP_TABLES_PATH, "%s.max_enemy_level" % field, row.get("max_enemy_level"), 1)
		is_valid = min_level_ok and is_valid
		is_valid = max_level_ok and is_valid
		if min_level_ok and max_level_ok:
			var min_level: int = int(String(row.get("min_enemy_level", "0")))
			var max_level: int = int(String(row.get("max_enemy_level", "0")))
			if max_level < min_level:
				is_valid = _schema_fail(GEAR_MOD_DROP_TABLES_PATH, "%s.max_enemy_level" % field, "int >= min_enemy_level") and is_valid
			if not source_enemy_id.is_empty() and not mod_id.is_empty():
				var key: String = "%s:%s:%d:%d" % [source_enemy_id, mod_id, min_level, max_level]
				if seen.has(key):
					is_valid = _schema_fail(GEAR_MOD_DROP_TABLES_PATH, field, "unique source/mod/level range") and is_valid
				seen[key] = true
	return is_valid


func _validate_gear_mod_fusion_costs_csv(rarity_max_ranks: Dictionary) -> bool:
	var rows: Array[Dictionary] = load_csv(GEAR_MOD_FUSION_COSTS_PATH)
	var is_valid: bool = true
	if rows.is_empty():
		is_valid = _schema_fail(GEAR_MOD_FUSION_COSTS_PATH, "rows", "non-empty CSV") and is_valid
	var seen: Dictionary = {}
	var costs_by_rarity: Dictionary = {}
	_last_schema_counts["gear_mod_fusion_costs"] = rows.size()
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var field: String = "line %d" % (index + 2)
		var rarity: String = _require_registered(GEAR_MOD_FUSION_COSTS_PATH, "%s.rarity" % field, row.get("rarity"), "gear_mod_rarities")
		var rank_ok: bool = _require_csv_int(GEAR_MOD_FUSION_COSTS_PATH, "%s.rank" % field, row.get("rank"), 1)
		is_valid = not rarity.is_empty() and is_valid
		is_valid = rank_ok and is_valid
		is_valid = _require_registered(GEAR_MOD_FUSION_COSTS_PATH, "%s.resource_id" % field, row.get("resource_id"), "gear_mod_resources") != "" and is_valid
		is_valid = _require_csv_int(GEAR_MOD_FUSION_COSTS_PATH, "%s.cost" % field, row.get("cost"), 0) and is_valid
		if not rarity.is_empty() and rank_ok:
			var rank: int = int(String(row.get("rank", "0")))
			var key: String = "%s:%d" % [rarity, rank]
			if seen.has(key):
				is_valid = _schema_fail(GEAR_MOD_FUSION_COSTS_PATH, field, "unique rarity/rank") and is_valid
			seen[key] = true
			if not costs_by_rarity.has(rarity):
				costs_by_rarity[rarity] = {}
			var rarity_costs: Dictionary = costs_by_rarity[rarity]
			rarity_costs[rank] = true
			costs_by_rarity[rarity] = rarity_costs

	for rarity_key: Variant in rarity_max_ranks.keys():
		var rarity_id: String = String(rarity_key)
		var max_rank: int = int(rarity_max_ranks[rarity_key])
		var covered: Dictionary = costs_by_rarity.get(rarity_id, {}) as Dictionary
		for rank: int in range(1, max_rank + 1):
			if not covered.has(rank):
				is_valid = _schema_fail(GEAR_MOD_FUSION_COSTS_PATH, "%s.rank_%d" % [rarity_id, rank], "fusion cost row") and is_valid
	return is_valid


func _status_params_has_damage_tick(status_params: Dictionary) -> bool:
	var magnitude_value: Variant = status_params.get("magnitude", 0.0)
	var tick_interval_value: Variant = status_params.get("tick_interval", 0.0)
	if not (magnitude_value is int or magnitude_value is float):
		return false
	if not (tick_interval_value is int or tick_interval_value is float):
		return false
	return float(magnitude_value) > 0.0 and float(tick_interval_value) > 0.0


func _validate_consumables_json(locale_keys: Dictionary) -> bool:
	var data: Variant = load_json(CONSUMABLES_PATH)
	if not data is Dictionary:
		return _schema_fail(CONSUMABLES_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(CONSUMABLES_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var consumables: Array = _require_array(CONSUMABLES_PATH, "consumables", payload.get("consumables"))
	if consumables.is_empty():
		is_valid = _schema_fail(CONSUMABLES_PATH, "consumables", "non-empty Array") and is_valid
	var seen: Dictionary = {}
	_last_schema_counts["consumables"] = consumables.size()
	for index: int in range(consumables.size()):
		var field: String = "consumables[%d]" % index
		var consumable: Variant = consumables[index]
		if not consumable is Dictionary:
			is_valid = _schema_fail(CONSUMABLES_PATH, field, "Dictionary") and is_valid
			continue
		var consumable_dict: Dictionary = consumable as Dictionary
		is_valid = _require_non_empty_string(CONSUMABLES_PATH, "%s.id" % field, consumable_dict.get("id")) and is_valid
		var consumable_id: String = String(consumable_dict.get("id", ""))
		if not consumable_id.is_empty():
			if seen.has(consumable_id):
				is_valid = _schema_fail(CONSUMABLES_PATH, "%s.id" % field, "unique consumable id") and is_valid
			seen[consumable_id] = true
		is_valid = _require_locale_key(CONSUMABLES_PATH, "%s.name_key" % field, consumable_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(CONSUMABLES_PATH, "%s.desc_key" % field, consumable_dict.get("desc_key"), locale_keys) and is_valid
		is_valid = _require_bool(CONSUMABLES_PATH, "%s.default_unlocked" % field, consumable_dict.get("default_unlocked")) and is_valid
		var tags: Array = _require_array(CONSUMABLES_PATH, "%s.tags" % field, consumable_dict.get("tags"))
		is_valid = _validate_registered_string_array(CONSUMABLES_PATH, "%s.tags" % field, tags, "content_tags", false) and is_valid
		if not tags.has("tag_consumable"):
			is_valid = _schema_fail(CONSUMABLES_PATH, "%s.tags" % field, "tag_consumable") and is_valid
		is_valid = _validate_consumable_stack("%s.stack" % field, consumable_dict.get("stack")) and is_valid
		is_valid = _validate_consumable_use_effects("%s.use_effects" % field, consumable_dict.get("use_effects")) and is_valid
	return is_valid


func _validate_consumable_stack(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(CONSUMABLES_PATH, field, "Dictionary")
	var stack: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(CONSUMABLES_PATH, "%s.max_stack" % field, stack.get("max_stack"), 1) and is_valid
	is_valid = _require_int(CONSUMABLES_PATH, "%s.start_count" % field, stack.get("start_count"), 0) and is_valid
	is_valid = _require_int(CONSUMABLES_PATH, "%s.pickup_count" % field, stack.get("pickup_count"), 1) and is_valid
	var max_stack: Variant = stack.get("max_stack")
	var start_count: Variant = stack.get("start_count")
	var pickup_count: Variant = stack.get("pickup_count")
	if _is_int_like(max_stack) and _is_int_like(start_count) and _variant_to_int(start_count) > _variant_to_int(max_stack):
		is_valid = _schema_fail(CONSUMABLES_PATH, "%s.start_count" % field, "<= max_stack") and is_valid
	if _is_int_like(max_stack) and _is_int_like(pickup_count) and _variant_to_int(pickup_count) > _variant_to_int(max_stack):
		is_valid = _schema_fail(CONSUMABLES_PATH, "%s.pickup_count" % field, "<= max_stack") and is_valid
	return is_valid


func _validate_consumable_use_effects(field: String, data: Variant) -> bool:
	var effects: Array = _require_array(CONSUMABLES_PATH, field, data)
	var is_valid: bool = true
	if effects.is_empty():
		is_valid = _schema_fail(CONSUMABLES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(effects.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var effect: Variant = effects[index]
		if not effect is Dictionary:
			is_valid = _schema_fail(CONSUMABLES_PATH, item_field, "Dictionary") and is_valid
			continue
		var effect_dict: Dictionary = effect as Dictionary
		is_valid = _require_registered(CONSUMABLES_PATH, "%s.effect" % item_field, effect_dict.get("effect"), "effects") != "" and is_valid
		if not effect_dict.get("params") is Dictionary:
			is_valid = _schema_fail(CONSUMABLES_PATH, "%s.params" % item_field, "Dictionary") and is_valid
	return is_valid


func _validate_credits_json(locale_keys: Dictionary) -> bool:
	var data: Variant = load_json(CREDITS_PATH)
	if not data is Dictionary:
		return _schema_fail(CREDITS_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(CREDITS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var sections: Array = _require_array(CREDITS_PATH, "sections", payload.get("sections"))
	if sections.is_empty():
		is_valid = _schema_fail(CREDITS_PATH, "sections", "non-empty Array") and is_valid
	var seen_sections: Dictionary = {}
	var entry_count: int = 0
	_last_schema_counts["credit_sections"] = sections.size()
	for section_index: int in range(sections.size()):
		var section_field: String = "sections[%d]" % section_index
		var section: Variant = sections[section_index]
		if not section is Dictionary:
			is_valid = _schema_fail(CREDITS_PATH, section_field, "Dictionary") and is_valid
			continue
		var section_dict: Dictionary = section as Dictionary
		var section_id: String = String(section_dict.get("id", ""))
		is_valid = _require_non_empty_string(CREDITS_PATH, "%s.id" % section_field, section_dict.get("id")) and is_valid
		if not section_id.is_empty():
			if seen_sections.has(section_id):
				is_valid = _schema_fail(CREDITS_PATH, "%s.id" % section_field, "unique section id") and is_valid
			seen_sections[section_id] = true
		is_valid = _require_locale_key(CREDITS_PATH, "%s.title_key" % section_field, section_dict.get("title_key"), locale_keys) and is_valid
		var entries: Array = _require_array(CREDITS_PATH, "%s.entries" % section_field, section_dict.get("entries"))
		if entries.is_empty():
			is_valid = _schema_fail(CREDITS_PATH, "%s.entries" % section_field, "non-empty Array") and is_valid
		entry_count += entries.size()
		for entry_index: int in range(entries.size()):
			is_valid = _validate_credit_entry("%s.entries[%d]" % [section_field, entry_index], entries[entry_index], locale_keys) and is_valid
	_last_schema_counts["credit_entries"] = entry_count
	return is_valid


func _validate_credit_entry(field: String, data: Variant, locale_keys: Dictionary) -> bool:
	if not data is Dictionary:
		return _schema_fail(CREDITS_PATH, field, "Dictionary")
	var entry: Dictionary = data as Dictionary
	var is_valid: bool = true
	var kind: String = String(entry.get("kind", ""))
	if not ["staff", "external_resource", "external_library", "external_tool"].has(kind):
		is_valid = _schema_fail(CREDITS_PATH, "%s.kind" % field, "staff, external_resource, external_library, or external_tool") and is_valid
	is_valid = _require_non_empty_string(CREDITS_PATH, "%s.name" % field, entry.get("name")) and is_valid
	is_valid = _require_locale_key(CREDITS_PATH, "%s.role_key" % field, entry.get("role_key"), locale_keys) and is_valid
	if kind.begins_with("external_"):
		is_valid = _require_non_empty_string(CREDITS_PATH, "%s.url" % field, entry.get("url")) and is_valid
		is_valid = _require_non_empty_string(CREDITS_PATH, "%s.license" % field, entry.get("license")) and is_valid
		is_valid = _require_bool(CREDITS_PATH, "%s.included_in_build" % field, entry.get("included_in_build")) and is_valid
		is_valid = _require_bool(CREDITS_PATH, "%s.requires_notice" % field, entry.get("requires_notice")) and is_valid
		is_valid = _require_bool(CREDITS_PATH, "%s.review_required" % field, entry.get("review_required")) and is_valid
	if entry.has("copyright"):
		is_valid = _require_non_empty_string(CREDITS_PATH, "%s.copyright" % field, entry.get("copyright")) and is_valid
	return is_valid


func _validate_growth_csv() -> bool:
	var rows: Array[Dictionary] = load_csv(GROWTH_CURVE_PATH)
	var is_valid: bool = true
	var previous_level: int = 0
	var previous_xp: int = -1
	_last_schema_counts["growth_levels"] = rows.size()
	for index: int in range(rows.size()):
		var field: String = "line %d" % (index + 2)
		var row: Dictionary = rows[index]
		var level: Variant = _parse_int(row.get("level"))
		var total_xp: Variant = _parse_int(row.get("total_xp_required"))
		is_valid = _require_int(GROWTH_CURVE_PATH, "%s.level" % field, level, 1) and is_valid
		is_valid = _require_int(GROWTH_CURVE_PATH, "%s.total_xp_required" % field, total_xp, 0) and is_valid
		is_valid = _require_int(GROWTH_CURVE_PATH, "%s.candidate_count" % field, _parse_int(row.get("candidate_count")), 1) and is_valid
		is_valid = _require_number(GROWTH_CURVE_PATH, "%s.bonus_candidate_chance_per_luck" % field, _parse_float(row.get("bonus_candidate_chance_per_luck")), 0.0, 1.0) and is_valid
		is_valid = _require_number(GROWTH_CURVE_PATH, "%s.bonus_candidate_chance_cap" % field, _parse_float(row.get("bonus_candidate_chance_cap")), 0.0, 1.0) and is_valid
		if _is_int_like(level):
			if _variant_to_int(level) <= previous_level:
				is_valid = _schema_fail(GROWTH_CURVE_PATH, "%s.level" % field, "strictly increasing int") and is_valid
			previous_level = _variant_to_int(level)
		if _is_int_like(total_xp):
			if _variant_to_int(total_xp) <= previous_xp:
				is_valid = _schema_fail(GROWTH_CURVE_PATH, "%s.total_xp_required" % field, "strictly increasing int") and is_valid
			previous_xp = _variant_to_int(total_xp)
	return is_valid


func _validate_growth_pools(locale_keys: Dictionary) -> bool:
	var data: Variant = load_json(GROWTH_POOLS_PATH)
	if not data is Dictionary:
		return _schema_fail(GROWTH_POOLS_PATH, "root", "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(GROWTH_POOLS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var pools: Array = _require_array(GROWTH_POOLS_PATH, "pools", payload.get("pools"))
	var pool_ids: Dictionary = {}
	_last_schema_counts["growth_pools"] = pools.size()
	for pool_index: int in range(pools.size()):
		var pool_field: String = "pools[%d]" % pool_index
		var pool: Variant = pools[pool_index]
		if not pool is Dictionary:
			is_valid = _schema_fail(GROWTH_POOLS_PATH, pool_field, "Dictionary") and is_valid
			continue
		var pool_dict: Dictionary = pool as Dictionary
		is_valid = _require_non_empty_string(GROWTH_POOLS_PATH, "%s.id" % pool_field, pool_dict.get("id")) and is_valid
		var pool_id: String = String(pool_dict.get("id", ""))
		if not pool_id.is_empty():
			if pool_ids.has(pool_id):
				is_valid = _schema_fail(GROWTH_POOLS_PATH, "%s.id" % pool_field, "unique pool id") and is_valid
			pool_ids[pool_id] = true
		var entries: Array = _require_array(GROWTH_POOLS_PATH, "%s.entries" % pool_field, pool_dict.get("entries"))
		var entry_ids: Dictionary = {}
		for entry_index: int in range(entries.size()):
			var entry_field: String = "%s.entries[%d]" % [pool_field, entry_index]
			var entry: Variant = entries[entry_index]
			if not entry is Dictionary:
				is_valid = _schema_fail(GROWTH_POOLS_PATH, entry_field, "Dictionary") and is_valid
				continue
			var entry_dict: Dictionary = entry as Dictionary
			is_valid = _require_non_empty_string(GROWTH_POOLS_PATH, "%s.id" % entry_field, entry_dict.get("id")) and is_valid
			is_valid = _require_locale_key(GROWTH_POOLS_PATH, "%s.name_key" % entry_field, entry_dict.get("name_key"), locale_keys) and is_valid
			is_valid = _require_locale_key(GROWTH_POOLS_PATH, "%s.desc_key" % entry_field, entry_dict.get("desc_key"), locale_keys) and is_valid
			var entry_id: String = String(entry_dict.get("id", ""))
			if not entry_id.is_empty():
				if entry_ids.has(entry_id):
					is_valid = _schema_fail(GROWTH_POOLS_PATH, "%s.id" % entry_field, "unique entry id") and is_valid
				entry_ids[entry_id] = true
			is_valid = _require_non_empty_string(GROWTH_POOLS_PATH, "%s.kind" % entry_field, entry_dict.get("kind")) and is_valid
			is_valid = _require_int(GROWTH_POOLS_PATH, "%s.weight" % entry_field, entry_dict.get("weight"), 0) and is_valid
			if entry_dict.has("min_level"):
				is_valid = _require_int(GROWTH_POOLS_PATH, "%s.min_level" % entry_field, entry_dict.get("min_level"), 1) and is_valid
			if entry_dict.has("modifiers"):
				is_valid = _validate_modifiers(GROWTH_POOLS_PATH, "%s.modifiers" % entry_field, entry_dict.get("modifiers"), false) and is_valid
	return is_valid


func _validate_game_modes(locale_keys: Dictionary, character_ids: Dictionary, weapon_ids: Dictionary, enemy_ids: Dictionary, hazard_ids: Dictionary, relic_ids: Dictionary, active_item_ids: Dictionary, consumable_ids: Dictionary, skill_ids: Dictionary) -> bool:
	var data: Variant = load_json(GAME_MODES_PATH)
	if not data is Dictionary:
		return _schema_fail(GAME_MODES_PATH, "root", "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(GAME_MODES_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var modes: Array = _require_array(GAME_MODES_PATH, "modes", payload.get("modes"))
	if modes.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, "modes", "non-empty Array") and is_valid
	var seen_modes: Dictionary = {}
	var growth_pool_ids: Dictionary = _collect_growth_pool_ids()
	_last_schema_counts["game_modes"] = modes.size()
	for mode_index: int in range(modes.size()):
		var mode_field: String = "modes[%d]" % mode_index
		var mode: Variant = modes[mode_index]
		if not mode is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, mode_field, "Dictionary") and is_valid
			continue
		var mode_dict: Dictionary = mode as Dictionary
		var mode_id: String = _require_registered(GAME_MODES_PATH, "%s.id" % mode_field, mode_dict.get("id"), "game_modes")
		if not mode_id.is_empty():
			if seen_modes.has(mode_id):
				is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % mode_field, "unique game mode id") and is_valid
			seen_modes[mode_id] = true
		is_valid = _require_locale_key(GAME_MODES_PATH, "%s.name_key" % mode_field, mode_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(GAME_MODES_PATH, "%s.desc_key" % mode_field, mode_dict.get("desc_key"), locale_keys) and is_valid
		is_valid = _require_bool(GAME_MODES_PATH, "%s.default_unlocked" % mode_field, mode_dict.get("default_unlocked")) and is_valid
		var team_result: Dictionary = _validate_mode_teams(mode_field, mode_dict.get("teams"))
		var team_ids: Dictionary = team_result.get("ids", {}) as Dictionary
		is_valid = bool(team_result.get("is_valid", false)) and is_valid
		is_valid = _validate_mode_participants(mode_field, mode_dict.get("participants"), team_ids) and is_valid
		is_valid = _validate_mode_resource_pools(mode_field, mode_dict.get("resource_pools"), growth_pool_ids, character_ids, weapon_ids, enemy_ids, hazard_ids, relic_ids, active_item_ids, consumable_ids, skill_ids) and is_valid
		if mode_dict.has("blocklists"):
			is_valid = _validate_mode_blocklists("%s.blocklists" % mode_field, mode_dict.get("blocklists")) and is_valid
		if mode_dict.has("overrides"):
			is_valid = _validate_mode_overrides("%s.overrides" % mode_field, mode_dict.get("overrides")) and is_valid
	return is_valid


func _validate_map_layouts_json(hazard_ids: Dictionary, game_mode_ids: Dictionary) -> bool:
	var data: Variant = load_json(MAP_LAYOUTS_PATH)
	if not data is Dictionary:
		return _schema_fail(MAP_LAYOUTS_PATH, "root", "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(MAP_LAYOUTS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var layouts: Array = _require_array(MAP_LAYOUTS_PATH, "layouts", payload.get("layouts"))
	if layouts.is_empty():
		is_valid = _schema_fail(MAP_LAYOUTS_PATH, "layouts", "non-empty Array") and is_valid
	var seen_layouts: Dictionary = {}
	_last_schema_counts["map_layouts"] = layouts.size()
	for layout_index: int in range(layouts.size()):
		var layout_field: String = "layouts[%d]" % layout_index
		var layout: Variant = layouts[layout_index]
		if not layout is Dictionary:
			is_valid = _schema_fail(MAP_LAYOUTS_PATH, layout_field, "Dictionary") and is_valid
			continue
		var layout_dict: Dictionary = layout as Dictionary
		var layout_id: String = String(layout_dict.get("id", ""))
		is_valid = _require_non_empty_string(MAP_LAYOUTS_PATH, "%s.id" % layout_field, layout_dict.get("id")) and is_valid
		if not layout_id.is_empty():
			if seen_layouts.has(layout_id):
				is_valid = _schema_fail(MAP_LAYOUTS_PATH, "%s.id" % layout_field, "unique map layout id") and is_valid
			seen_layouts[layout_id] = true
		var mode_id: String = _require_registered(MAP_LAYOUTS_PATH, "%s.mode_id" % layout_field, layout_dict.get("mode_id"), "game_modes")
		if not mode_id.is_empty() and not game_mode_ids.has(mode_id):
			is_valid = _schema_fail(MAP_LAYOUTS_PATH, "%s.mode_id" % layout_field, "mode defined in game_modes.json") and is_valid
		is_valid = _validate_map_bounds("%s.bounds" % layout_field, layout_dict.get("bounds")) and is_valid
		is_valid = _validate_map_grid("%s.grid" % layout_field, layout_dict.get("grid")) and is_valid
		is_valid = _validate_map_bounds_grid_alignment(layout_field, layout_dict.get("bounds"), layout_dict.get("grid")) and is_valid
		is_valid = _validate_map_point("%s.player_start" % layout_field, layout_dict.get("player_start")) and is_valid
		is_valid = _validate_map_point_on_grid("%s.player_start" % layout_field, layout_dict.get("player_start"), layout_dict.get("grid")) and is_valid
		is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.safe_radius" % layout_field, layout_dict.get("safe_radius"), 0.0) and is_valid
		is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.enemy_spawn_margin" % layout_field, layout_dict.get("enemy_spawn_margin"), 0.0) and is_valid
		is_valid = _validate_map_pcg("%s.pcg" % layout_field, layout_dict.get("pcg", {}), hazard_ids) and is_valid
		is_valid = _validate_map_manual_hazards("%s.manual_hazards" % layout_field, layout_dict.get("manual_hazards", []), hazard_ids, layout_dict.get("grid")) and is_valid
	return is_valid


func _validate_warzone_directors_json(game_mode_ids: Dictionary, wave_ids_by_mode: Dictionary, hazard_ids: Dictionary, map_layout_ids: Dictionary, gear_mod_ids: Dictionary) -> bool:
	var data: Variant = load_json(WARZONE_DIRECTORS_PATH)
	if not data is Dictionary:
		return _schema_fail(WARZONE_DIRECTORS_PATH, "root", "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(WARZONE_DIRECTORS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var directors: Array = _require_array(WARZONE_DIRECTORS_PATH, "directors", payload.get("directors"))
	if directors.is_empty():
		is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "directors", "non-empty Array") and is_valid
	var seen_directors: Dictionary = {}
	var seen_modes: Dictionary = {}
	_last_schema_counts["warzone_directors"] = directors.size()
	for director_index: int in range(directors.size()):
		var director_field: String = "directors[%d]" % director_index
		var director: Variant = directors[director_index]
		if not director is Dictionary:
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, director_field, "Dictionary") and is_valid
			continue
		var director_dict: Dictionary = director as Dictionary
		var director_id: String = String(director_dict.get("id", ""))
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.id" % director_field, director_dict.get("id")) and is_valid
		if not director_id.is_empty():
			if seen_directors.has(director_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.id" % director_field, "unique director id") and is_valid
			seen_directors[director_id] = true
		var mode_id: String = _require_registered(WARZONE_DIRECTORS_PATH, "%s.mode_id" % director_field, director_dict.get("mode_id"), "game_modes")
		if not mode_id.is_empty():
			if not game_mode_ids.has(mode_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.mode_id" % director_field, "mode defined in game_modes.json") and is_valid
			if seen_modes.has(mode_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.mode_id" % director_field, "unique director per mode") and is_valid
			seen_modes[mode_id] = true
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.mutation_id" % director_field, director_dict.get("mutation_id")) and is_valid
		if director_dict.has("description"):
			is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.description" % director_field, director_dict.get("description")) and is_valid

		var encounter_result: Dictionary = _validate_warzone_encounters("%s.encounters" % director_field, director_dict.get("encounters"))
		var encounter_ids: Dictionary = encounter_result.get("ids", {}) as Dictionary
		is_valid = bool(encounter_result.get("is_valid", false)) and is_valid
		is_valid = _validate_warzone_interest_points("%s.interest_points" % director_field, director_dict.get("interest_points"), hazard_ids, map_layout_ids, gear_mod_ids) and is_valid

		var mode_wave_ids: Dictionary = {}
		if wave_ids_by_mode.get(mode_id, {}) is Dictionary:
			mode_wave_ids = wave_ids_by_mode.get(mode_id, {}) as Dictionary
		var phase_result: Dictionary = _validate_warzone_phases(director_field, director_dict.get("phases"), mode_id, mode_wave_ids, encounter_ids)
		var referenced_waves: Dictionary = phase_result.get("referenced_waves", {}) as Dictionary
		is_valid = bool(phase_result.get("is_valid", false)) and is_valid
		for wave_key: Variant in mode_wave_ids.keys():
			var wave_id: String = String(wave_key)
			if not referenced_waves.has(wave_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.phases" % director_field, "reference wave %s at least once" % wave_id) and is_valid
	return is_valid


func _validate_warzone_phases(director_field: String, data: Variant, mode_id: String, mode_wave_ids: Dictionary, encounter_ids: Dictionary) -> Dictionary:
	var phases: Array = _require_array(WARZONE_DIRECTORS_PATH, "%s.phases" % director_field, data)
	var is_valid: bool = true
	if phases.is_empty():
		is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.phases" % director_field, "non-empty Array") and is_valid
	var seen_phases: Dictionary = {}
	var referenced_waves: Dictionary = {}
	var previous_end: Variant = null
	for phase_index: int in range(phases.size()):
		var phase_field: String = "%s.phases[%d]" % [director_field, phase_index]
		var phase: Variant = phases[phase_index]
		if not phase is Dictionary:
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, phase_field, "Dictionary") and is_valid
			continue
		var phase_dict: Dictionary = phase as Dictionary
		var phase_id: String = String(phase_dict.get("id", ""))
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.id" % phase_field, phase_dict.get("id")) and is_valid
		if not phase_id.is_empty():
			if seen_phases.has(phase_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.id" % phase_field, "unique phase id") and is_valid
			seen_phases[phase_id] = true
		is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.start_time" % phase_field, phase_dict.get("start_time"), 0.0) and is_valid
		is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.end_time" % phase_field, phase_dict.get("end_time"), 0.0, null, true) and is_valid
		var start_time: Variant = phase_dict.get("start_time")
		var end_time: Variant = phase_dict.get("end_time")
		if (start_time is int or start_time is float) and (end_time is int or end_time is float):
			if float(end_time) <= float(start_time):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.end_time" % phase_field, "greater than start_time") and is_valid
			if previous_end != null and float(start_time) < float(previous_end):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.start_time" % phase_field, "ascending non-overlapping time window") and is_valid
			previous_end = float(end_time)
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.pressure_tag" % phase_field, phase_dict.get("pressure_tag")) and is_valid
		var wave_ids: Array = _require_array(WARZONE_DIRECTORS_PATH, "%s.wave_ids" % phase_field, phase_dict.get("wave_ids"))
		is_valid = _validate_warzone_phase_wave_ids("%s.wave_ids" % phase_field, wave_ids, mode_id, mode_wave_ids, referenced_waves) and is_valid
		var phase_encounters: Array = _require_array(WARZONE_DIRECTORS_PATH, "%s.encounter_ids" % phase_field, phase_dict.get("encounter_ids"))
		is_valid = _validate_warzone_phase_encounter_ids("%s.encounter_ids" % phase_field, phase_encounters, encounter_ids) and is_valid
	return {
		"is_valid": is_valid,
		"referenced_waves": referenced_waves,
	}


func _validate_warzone_phase_wave_ids(field: String, wave_ids: Array, mode_id: String, mode_wave_ids: Dictionary, referenced_waves: Dictionary) -> bool:
	var is_valid: bool = true
	if wave_ids.is_empty():
		is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, field, "non-empty Array") and is_valid
	var seen: Dictionary = {}
	for index: int in range(wave_ids.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var raw_wave_id: Variant = wave_ids[index]
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, item_field, raw_wave_id) and is_valid
		var wave_id: String = String(raw_wave_id)
		if wave_id.is_empty():
			continue
		if seen.has(wave_id):
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, item_field, "unique wave id") and is_valid
		seen[wave_id] = true
		if not mode_wave_ids.has(wave_id):
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, item_field, "wave defined in spawn_waves.csv for mode %s" % mode_id) and is_valid
		referenced_waves[wave_id] = true
	return is_valid


func _validate_warzone_phase_encounter_ids(field: String, phase_encounters: Array, encounter_ids: Dictionary) -> bool:
	var is_valid: bool = true
	if phase_encounters.is_empty():
		is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, field, "non-empty Array") and is_valid
	var seen: Dictionary = {}
	for index: int in range(phase_encounters.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var raw_encounter_id: Variant = phase_encounters[index]
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, item_field, raw_encounter_id) and is_valid
		var encounter_id: String = String(raw_encounter_id)
		if encounter_id.is_empty():
			continue
		if seen.has(encounter_id):
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, item_field, "unique encounter id") and is_valid
		seen[encounter_id] = true
		if not encounter_ids.has(encounter_id):
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, item_field, "encounter defined in encounters") and is_valid
	return is_valid


func _validate_warzone_encounters(field: String, data: Variant) -> Dictionary:
	var encounters: Array = _require_array(WARZONE_DIRECTORS_PATH, field, data)
	var is_valid: bool = true
	if encounters.is_empty():
		is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, field, "non-empty Array") and is_valid
	var seen: Dictionary = {}
	for index: int in range(encounters.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var encounter: Variant = encounters[index]
		if not encounter is Dictionary:
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, item_field, "Dictionary") and is_valid
			continue
		var encounter_dict: Dictionary = encounter as Dictionary
		var encounter_id: String = String(encounter_dict.get("id", ""))
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.id" % item_field, encounter_dict.get("id")) and is_valid
		if not encounter_id.is_empty():
			if seen.has(encounter_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.id" % item_field, "unique encounter id") and is_valid
			seen[encounter_id] = true
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.kind" % item_field, encounter_dict.get("kind")) and is_valid
		is_valid = _validate_registered_string_array(WARZONE_DIRECTORS_PATH, "%s.enemy_tags" % item_field, encounter_dict.get("enemy_tags"), "content_tags", false) and is_valid
		if encounter_dict.has("notes"):
			is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.notes" % item_field, encounter_dict.get("notes")) and is_valid
	return {
		"ids": seen,
		"is_valid": is_valid,
	}


func _validate_warzone_interest_points(field: String, data: Variant, hazard_ids: Dictionary, map_layout_ids: Dictionary, gear_mod_ids: Dictionary) -> bool:
	var points: Array = _require_array(WARZONE_DIRECTORS_PATH, field, data)
	var is_valid: bool = true
	if points.is_empty():
		is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, field, "non-empty Array") and is_valid
	var seen: Dictionary = {}
	for index: int in range(points.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var point: Variant = points[index]
		if not point is Dictionary:
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, item_field, "Dictionary") and is_valid
			continue
		var point_dict: Dictionary = point as Dictionary
		var point_id: String = String(point_dict.get("id", ""))
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.id" % item_field, point_dict.get("id")) and is_valid
		if not point_id.is_empty():
			if seen.has(point_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.id" % item_field, "unique interest point id") and is_valid
			seen[point_id] = true
		is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.kind" % item_field, point_dict.get("kind")) and is_valid
		var point_hazards: Array = _require_array(WARZONE_DIRECTORS_PATH, "%s.hazard_ids" % item_field, point_dict.get("hazard_ids", []))
		if point_hazards.is_empty():
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.hazard_ids" % item_field, "non-empty Array") and is_valid
		for hazard_index: int in range(point_hazards.size()):
			var hazard_field: String = "%s.hazard_ids[%d]" % [item_field, hazard_index]
			var raw_hazard_id: Variant = point_hazards[hazard_index]
			is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, hazard_field, raw_hazard_id) and is_valid
			var hazard_id: String = String(raw_hazard_id)
			if not hazard_id.is_empty() and not hazard_ids.has(hazard_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, hazard_field, "hazard defined in hazards.csv") and is_valid
		if point_dict.has("map_layout_id"):
			var map_layout_id: String = String(point_dict.get("map_layout_id", ""))
			is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.map_layout_id" % item_field, point_dict.get("map_layout_id")) and is_valid
			if not map_layout_id.is_empty() and not map_layout_ids.has(map_layout_id):
				is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.map_layout_id" % item_field, "map layout defined in map_layouts.json") and is_valid
		if point_dict.has("min_distance_from_player"):
			is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.min_distance_from_player" % item_field, point_dict.get("min_distance_from_player"), 0.0) and is_valid
		if point_dict.has("min_spacing"):
			is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.min_spacing" % item_field, point_dict.get("min_spacing"), 0.0) and is_valid
		var completes_run: bool = bool(point_dict.get("completes_run", false))
		var has_reward_payload: bool = point_dict.has("resource_rewards") or point_dict.has("gear_mod_rewards") or completes_run
		if point_dict.has("claim_radius") or has_reward_payload:
			is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.claim_radius" % item_field, point_dict.get("claim_radius"), 0.0, null, true) and is_valid
		if point_dict.has("claim_start_time"):
			is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.claim_start_time" % item_field, point_dict.get("claim_start_time"), 0.0) and is_valid
		if point_dict.has("requires_interaction"):
			is_valid = _require_bool(WARZONE_DIRECTORS_PATH, "%s.requires_interaction" % item_field, point_dict.get("requires_interaction")) and is_valid
		if point_dict.has("completes_run"):
			is_valid = _require_bool(WARZONE_DIRECTORS_PATH, "%s.completes_run" % item_field, point_dict.get("completes_run")) and is_valid
		if point_dict.has("extraction_radius") or completes_run:
			is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.extraction_radius" % item_field, point_dict.get("extraction_radius"), 0.0, null, true) and is_valid
		if point_dict.has("extraction_hold_time") or completes_run:
			is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.extraction_hold_time" % item_field, point_dict.get("extraction_hold_time"), 0.0, null, true) and is_valid
		if point_dict.has("target_hp"):
			is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.target_hp" % item_field, point_dict.get("target_hp"), 0.0, null, true) and is_valid
		if point_dict.has("target_hit_radius"):
			is_valid = _require_number(WARZONE_DIRECTORS_PATH, "%s.target_hit_radius" % item_field, point_dict.get("target_hit_radius"), 0.0, null, true) and is_valid
		if point_dict.has("resource_rewards"):
			is_valid = _validate_warzone_resource_rewards("%s.resource_rewards" % item_field, point_dict.get("resource_rewards")) and is_valid
		if point_dict.has("gear_mod_rewards"):
			is_valid = _validate_warzone_gear_mod_rewards("%s.gear_mod_rewards" % item_field, point_dict.get("gear_mod_rewards"), gear_mod_ids) and is_valid
		if point_dict.has("notes"):
			is_valid = _require_non_empty_string(WARZONE_DIRECTORS_PATH, "%s.notes" % item_field, point_dict.get("notes")) and is_valid
	return is_valid


func _validate_warzone_resource_rewards(field: String, data: Variant) -> bool:
	var rewards: Array = _require_array(WARZONE_DIRECTORS_PATH, field, data)
	var is_valid: bool = true
	if rewards.is_empty():
		is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, field, "non-empty Array") and is_valid
	for reward_index: int in range(rewards.size()):
		var reward_field: String = "%s[%d]" % [field, reward_index]
		var reward: Variant = rewards[reward_index]
		if not reward is Dictionary:
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, reward_field, "Dictionary") and is_valid
			continue
		var reward_dict: Dictionary = reward as Dictionary
		is_valid = _require_registered(WARZONE_DIRECTORS_PATH, "%s.resource_id" % reward_field, reward_dict.get("resource_id"), "gear_mod_resources") != "" and is_valid
		is_valid = _require_int(WARZONE_DIRECTORS_PATH, "%s.amount" % reward_field, reward_dict.get("amount"), 1) and is_valid
	return is_valid


func _validate_warzone_gear_mod_rewards(field: String, data: Variant, gear_mod_ids: Dictionary) -> bool:
	var rewards: Array = _require_array(WARZONE_DIRECTORS_PATH, field, data)
	var is_valid: bool = true
	if rewards.is_empty():
		is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, field, "non-empty Array") and is_valid
	for reward_index: int in range(rewards.size()):
		var reward_field: String = "%s[%d]" % [field, reward_index]
		var reward: Variant = rewards[reward_index]
		if not reward is Dictionary:
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, reward_field, "Dictionary") and is_valid
			continue
		var reward_dict: Dictionary = reward as Dictionary
		var mod_id: String = _require_registered(WARZONE_DIRECTORS_PATH, "%s.mod_id" % reward_field, reward_dict.get("mod_id"), "gear_mod_ids")
		if not mod_id.is_empty() and not gear_mod_ids.has(mod_id):
			is_valid = _schema_fail(WARZONE_DIRECTORS_PATH, "%s.mod_id" % reward_field, "mod defined in gear_mods.json") and is_valid
		is_valid = _require_int(WARZONE_DIRECTORS_PATH, "%s.count" % reward_field, reward_dict.get("count"), 1) and is_valid
	return is_valid


func _validate_map_bounds(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(MAP_LAYOUTS_PATH, field, "Dictionary")
	var bounds: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.width" % field, bounds.get("width"), 0.0, null, true) and is_valid
	is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.height" % field, bounds.get("height"), 0.0, null, true) and is_valid
	return is_valid


func _validate_map_grid(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(MAP_LAYOUTS_PATH, field, "Dictionary")
	var grid: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.cell_width" % field, grid.get("cell_width"), 0.0, null, true) and is_valid
	is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.cell_height" % field, grid.get("cell_height"), 0.0, null, true) and is_valid
	return is_valid


func _validate_map_bounds_grid_alignment(field: String, bounds_data: Variant, grid_data: Variant) -> bool:
	if not bounds_data is Dictionary or not grid_data is Dictionary:
		return true
	var bounds: Dictionary = bounds_data as Dictionary
	var grid: Dictionary = grid_data as Dictionary
	var is_valid: bool = true
	if (bounds.get("width") is int or bounds.get("width") is float) and (grid.get("cell_width") is int or grid.get("cell_width") is float):
		if not _is_nearly_grid_multiple(float(bounds.get("width")), float(grid.get("cell_width"))):
			is_valid = _schema_fail(MAP_LAYOUTS_PATH, "%s.bounds.width" % field, "integer multiple of grid.cell_width") and is_valid
	if (bounds.get("height") is int or bounds.get("height") is float) and (grid.get("cell_height") is int or grid.get("cell_height") is float):
		if not _is_nearly_grid_multiple(float(bounds.get("height")), float(grid.get("cell_height"))):
			is_valid = _schema_fail(MAP_LAYOUTS_PATH, "%s.bounds.height" % field, "integer multiple of grid.cell_height") and is_valid
	return is_valid


func _validate_map_point(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(MAP_LAYOUTS_PATH, field, "Dictionary")
	var point: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.x" % field, point.get("x")) and is_valid
	is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.y" % field, point.get("y")) and is_valid
	return is_valid


func _validate_map_point_on_grid(field: String, point_data: Variant, grid_data: Variant) -> bool:
	if _is_map_point_on_grid_center(point_data, grid_data):
		return true
	return _schema_fail(MAP_LAYOUTS_PATH, field, "rectangular grid center")


func _validate_map_point_on_hazard_anchor(field: String, point_data: Variant, grid_data: Variant, radius_tiles: int) -> bool:
	if radius_tiles % 2 == 1:
		if _is_map_point_on_grid_center(point_data, grid_data):
			return true
		return _schema_fail(MAP_LAYOUTS_PATH, field, "rectangular grid center for odd radius_tiles")
	if _is_map_point_on_grid_vertex(point_data, grid_data):
		return true
	return _schema_fail(MAP_LAYOUTS_PATH, field, "rectangular grid vertex for even radius_tiles")


func _is_map_point_on_grid_center(point_data: Variant, grid_data: Variant) -> bool:
	if not point_data is Dictionary or not grid_data is Dictionary:
		return true
	var point: Dictionary = point_data as Dictionary
	var grid: Dictionary = grid_data as Dictionary
	if not (point.get("x") is int or point.get("x") is float):
		return true
	if not (point.get("y") is int or point.get("y") is float):
		return true
	if not (grid.get("cell_width") is int or grid.get("cell_width") is float):
		return true
	if not (grid.get("cell_height") is int or grid.get("cell_height") is float):
		return true
	var column: float = float(point.get("x")) / maxf(float(grid.get("cell_width")), 1.0)
	var row: float = float(point.get("y")) / maxf(float(grid.get("cell_height")), 1.0)
	if _is_nearly_integer(column) and _is_nearly_integer(row):
		return true
	return false


func _is_map_point_on_grid_vertex(point_data: Variant, grid_data: Variant) -> bool:
	if not point_data is Dictionary or not grid_data is Dictionary:
		return true
	var point: Dictionary = point_data as Dictionary
	var grid: Dictionary = grid_data as Dictionary
	if not (point.get("x") is int or point.get("x") is float):
		return true
	if not (point.get("y") is int or point.get("y") is float):
		return true
	if not (grid.get("cell_width") is int or grid.get("cell_width") is float):
		return true
	if not (grid.get("cell_height") is int or grid.get("cell_height") is float):
		return true
	var column: float = float(point.get("x")) / maxf(float(grid.get("cell_width")), 1.0) - 0.5
	var row: float = float(point.get("y")) / maxf(float(grid.get("cell_height")), 1.0) - 0.5
	return _is_nearly_integer(column) and _is_nearly_integer(row)


func _validate_map_pcg(field: String, data: Variant, hazard_ids: Dictionary) -> bool:
	if not data is Dictionary:
		return _schema_fail(MAP_LAYOUTS_PATH, field, "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	var hazards: Array = _require_array(MAP_LAYOUTS_PATH, "%s.hazards" % field, payload.get("hazards", []))
	for index: int in range(hazards.size()):
		var item_field: String = "%s.hazards[%d]" % [field, index]
		var hazard: Variant = hazards[index]
		if not hazard is Dictionary:
			is_valid = _schema_fail(MAP_LAYOUTS_PATH, item_field, "Dictionary") and is_valid
			continue
		var hazard_dict: Dictionary = hazard as Dictionary
		var hazard_id: String = String(hazard_dict.get("id", ""))
		is_valid = _require_non_empty_string(MAP_LAYOUTS_PATH, "%s.id" % item_field, hazard_dict.get("id")) and is_valid
		if not hazard_id.is_empty() and not hazard_ids.has(hazard_id):
			is_valid = _schema_fail(MAP_LAYOUTS_PATH, "%s.id" % item_field, "hazard defined in hazards.csv") and is_valid
		is_valid = _require_int(MAP_LAYOUTS_PATH, "%s.count" % item_field, hazard_dict.get("count"), 0) and is_valid
		is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.min_distance_from_player" % item_field, hazard_dict.get("min_distance_from_player"), 0.0) and is_valid
		is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.min_spacing" % item_field, hazard_dict.get("min_spacing"), 0.0) and is_valid
	return is_valid


func _validate_map_manual_hazards(field: String, data: Variant, hazard_ids: Dictionary, grid_data: Variant) -> bool:
	var hazards: Array = _require_array(MAP_LAYOUTS_PATH, field, data)
	var is_valid: bool = true
	for index: int in range(hazards.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var hazard: Variant = hazards[index]
		if not hazard is Dictionary:
			is_valid = _schema_fail(MAP_LAYOUTS_PATH, item_field, "Dictionary") and is_valid
			continue
		var hazard_dict: Dictionary = hazard as Dictionary
		var hazard_id: String = String(hazard_dict.get("id", ""))
		is_valid = _require_non_empty_string(MAP_LAYOUTS_PATH, "%s.id" % item_field, hazard_dict.get("id")) and is_valid
		if not hazard_id.is_empty() and not hazard_ids.has(hazard_id):
			is_valid = _schema_fail(MAP_LAYOUTS_PATH, "%s.id" % item_field, "hazard defined in hazards.csv") and is_valid
		is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.x" % item_field, hazard_dict.get("x")) and is_valid
		is_valid = _require_number(MAP_LAYOUTS_PATH, "%s.y" % item_field, hazard_dict.get("y")) and is_valid
		var radius_tiles: int = int(hazard_ids.get(hazard_id, 1))
		is_valid = _validate_map_point_on_hazard_anchor(item_field, hazard_dict, grid_data, radius_tiles) and is_valid
	return is_valid


func _validate_mode_teams(mode_field: String, data: Variant) -> Dictionary:
	var teams: Array = _require_array(GAME_MODES_PATH, "%s.teams" % mode_field, data)
	var is_valid: bool = true
	var team_ids: Dictionary = {}
	for index: int in range(teams.size()):
		var field: String = "%s.teams[%d]" % [mode_field, index]
		var team: Variant = teams[index]
		if not team is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, field, "Dictionary") and is_valid
			continue
		var team_dict: Dictionary = team as Dictionary
		var team_id: String = String(team_dict.get("id", ""))
		if _require_non_empty_string(GAME_MODES_PATH, "%s.id" % field, team_dict.get("id")):
			if team_ids.has(team_id):
				is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % field, "unique team id") and is_valid
			team_ids[team_id] = true
		else:
			is_valid = false
		is_valid = _require_bool(GAME_MODES_PATH, "%s.friendly_fire" % field, team_dict.get("friendly_fire")) and is_valid
	if teams.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, "%s.teams" % mode_field, "non-empty Array") and is_valid
	return {
		"ids": team_ids,
		"is_valid": is_valid,
	}


func _validate_mode_participants(mode_field: String, data: Variant, team_ids: Dictionary) -> bool:
	var participants: Array = _require_array(GAME_MODES_PATH, "%s.participants" % mode_field, data)
	var is_valid: bool = true
	var participant_ids: Dictionary = {}
	if participants.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, "%s.participants" % mode_field, "non-empty Array") and is_valid
	for index: int in range(participants.size()):
		var field: String = "%s.participants[%d]" % [mode_field, index]
		var participant: Variant = participants[index]
		if not participant is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, field, "Dictionary") and is_valid
			continue
		var participant_dict: Dictionary = participant as Dictionary
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.id" % field, participant_dict.get("id")) and is_valid
		var participant_id: String = String(participant_dict.get("id", ""))
		if not participant_id.is_empty():
			if participant_ids.has(participant_id):
				is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % field, "unique participant id") and is_valid
			participant_ids[participant_id] = true
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.kind" % field, participant_dict.get("kind")) and is_valid
		var team_id: String = String(participant_dict.get("team_id", ""))
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.team_id" % field, participant_dict.get("team_id")) and is_valid
		if not team_id.is_empty() and not team_ids.has(team_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.team_id" % field, "team defined in teams") and is_valid
		if participant_dict.has("control"):
			is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.control" % field, participant_dict.get("control")) and is_valid
	return is_valid


func _validate_mode_resource_pools(mode_field: String, data: Variant, growth_pool_ids: Dictionary, character_ids: Dictionary, weapon_ids: Dictionary, enemy_ids: Dictionary, hazard_ids: Dictionary, relic_ids: Dictionary, active_item_ids: Dictionary, consumable_ids: Dictionary, skill_ids: Dictionary) -> bool:
	if not data is Dictionary:
		return _schema_fail(GAME_MODES_PATH, "%s.resource_pools" % mode_field, "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	if payload.has("characters"):
		is_valid = _validate_weighted_character_entries("%s.resource_pools.characters" % mode_field, payload.get("characters"), character_ids) and is_valid
	if payload.has("weapons"):
		is_valid = _validate_weighted_weapon_entries("%s.resource_pools.weapons" % mode_field, payload.get("weapons"), weapon_ids) and is_valid
	if payload.has("enemies"):
		is_valid = _validate_weighted_enemy_entries("%s.resource_pools.enemies" % mode_field, payload.get("enemies"), enemy_ids) and is_valid
	if payload.has("hazards"):
		is_valid = _validate_weighted_hazard_entries("%s.resource_pools.hazards" % mode_field, payload.get("hazards"), hazard_ids) and is_valid
	if payload.has("relics"):
		is_valid = _validate_weighted_relic_entries("%s.resource_pools.relics" % mode_field, payload.get("relics"), relic_ids) and is_valid
	if payload.has("active_items"):
		is_valid = _validate_weighted_active_item_entries("%s.resource_pools.active_items" % mode_field, payload.get("active_items"), active_item_ids) and is_valid
	if payload.has("skills"):
		is_valid = _validate_weighted_skill_entries("%s.resource_pools.skills" % mode_field, payload.get("skills"), skill_ids) and is_valid
	if payload.has("consumables"):
		is_valid = _validate_weighted_consumable_entries("%s.resource_pools.consumables" % mode_field, payload.get("consumables"), consumable_ids) and is_valid
	if payload.has("growth_pools"):
		is_valid = _validate_weighted_growth_pool_entries("%s.resource_pools.growth_pools" % mode_field, payload.get("growth_pools"), growth_pool_ids) and is_valid
	if not payload.has("characters") and not payload.has("weapons") and not payload.has("enemies") and not payload.has("hazards") and not payload.has("relics") and not payload.has("active_items") and not payload.has("skills") and not payload.has("consumables") and not payload.has("growth_pools"):
		is_valid = _schema_fail(GAME_MODES_PATH, "%s.resource_pools" % mode_field, "at least one supported pool") and is_valid
	return is_valid


func _validate_weighted_character_entries(field: String, data: Variant, character_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		var character_id: String = _require_registered(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id"), "character_ids")
		if not character_id.is_empty() and not character_ids.has(character_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "character defined in characters.json") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_weapon_entries(field: String, data: Variant, weapon_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id")) and is_valid
		var weapon_id: String = String(entry_dict.get("id", ""))
		if not weapon_id.is_empty() and not weapon_ids.has(weapon_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "weapon defined in weapons.json") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_enemy_entries(field: String, data: Variant, enemy_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id")) and is_valid
		var enemy_id: String = String(entry_dict.get("id", ""))
		if not enemy_id.is_empty() and not enemy_ids.has(enemy_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "enemy defined in enemies.csv") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_hazard_entries(field: String, data: Variant, hazard_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id")) and is_valid
		var hazard_id: String = String(entry_dict.get("id", ""))
		if not hazard_id.is_empty() and not hazard_ids.has(hazard_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "hazard defined in hazards.csv") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_relic_entries(field: String, data: Variant, relic_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id")) and is_valid
		var relic_id: String = String(entry_dict.get("id", ""))
		if not relic_id.is_empty() and not relic_ids.has(relic_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "relic defined in relics.json") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_active_item_entries(field: String, data: Variant, active_item_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id")) and is_valid
		var active_item_id: String = String(entry_dict.get("id", ""))
		if not active_item_id.is_empty() and not active_item_ids.has(active_item_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "active item defined in active_items.json") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_skill_entries(field: String, data: Variant, skill_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		var skill_id: String = _require_registered(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id"), "skill_ids")
		if not skill_id.is_empty() and not skill_ids.has(skill_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "skill defined in skills.json") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_consumable_entries(field: String, data: Variant, consumable_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id")) and is_valid
		var consumable_id: String = String(entry_dict.get("id", ""))
		if not consumable_id.is_empty() and not consumable_ids.has(consumable_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "consumable defined in consumables.json") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_contract_entries(field: String, data: Variant, contract_key: String) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		is_valid = _require_registered(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id"), contract_key) != "" and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_weighted_growth_pool_entries(field: String, data: Variant, growth_pool_ids: Dictionary) -> bool:
	var entries: Array = _require_array(GAME_MODES_PATH, field, data)
	var is_valid: bool = true
	if entries.is_empty():
		is_valid = _schema_fail(GAME_MODES_PATH, field, "non-empty Array") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry_dict: Dictionary = entry as Dictionary
		is_valid = _require_non_empty_string(GAME_MODES_PATH, "%s.id" % item_field, entry_dict.get("id")) and is_valid
		var pool_id: String = String(entry_dict.get("id", ""))
		if not pool_id.is_empty() and not growth_pool_ids.has(pool_id):
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.id" % item_field, "pool id defined in growth_pools.json") and is_valid
		is_valid = _require_int(GAME_MODES_PATH, "%s.weight" % item_field, entry_dict.get("weight"), 0) and is_valid
	return is_valid


func _validate_mode_blocklists(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(GAME_MODES_PATH, field, "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	if payload.has("content_tags"):
		var tags: Array = _require_array(GAME_MODES_PATH, "%s.content_tags" % field, payload.get("content_tags"))
		for index: int in range(tags.size()):
			is_valid = _require_registered(GAME_MODES_PATH, "%s.content_tags[%d]" % [field, index], tags[index], "content_tags") != "" and is_valid
	return is_valid


func _validate_mode_overrides(field: String, data: Variant) -> bool:
	if not data is Dictionary:
		return _schema_fail(GAME_MODES_PATH, field, "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	if payload.has("player_base_stats"):
		var stats: Variant = payload.get("player_base_stats")
		if not stats is Dictionary:
			is_valid = _schema_fail(GAME_MODES_PATH, "%s.player_base_stats" % field, "Dictionary") and is_valid
		else:
			var stats_dict: Dictionary = stats as Dictionary
			for stat_key: Variant in stats_dict.keys():
				var stat: String = String(stat_key)
				is_valid = _validate_stat_value(GAME_MODES_PATH, "%s.player_base_stats.%s" % [field, stat], stat, stats_dict[stat_key]) and is_valid
	return is_valid


func _validate_modifiers(resource_path: String, field: String, data: Variant, require_value_per_level: bool) -> bool:
	var modifiers: Array = _require_array(resource_path, field, data)
	var is_valid: bool = true
	for index: int in range(modifiers.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var modifier: Variant = modifiers[index]
		if not modifier is Dictionary:
			is_valid = _schema_fail(resource_path, item_field, "Dictionary") and is_valid
			continue
		var modifier_dict: Dictionary = modifier as Dictionary
		var stat: String = _require_registered(resource_path, "%s.stat" % item_field, modifier_dict.get("stat"), "stats")
		var modifier_type: String = String(modifier_dict.get("type", ""))
		if modifier_type != "add" and modifier_type != "mult":
			is_valid = _schema_fail(resource_path, "%s.type" % item_field, "add or mult") and is_valid
		var value_field: String = "value_per_level" if require_value_per_level else "value"
		if not modifier_dict.has(value_field):
			is_valid = _schema_fail(resource_path, "%s.%s" % [item_field, value_field], "number") and is_valid
		elif require_value_per_level:
			is_valid = _require_number(resource_path, "%s.%s" % [item_field, value_field], modifier_dict.get(value_field), 0.0) and is_valid
		elif not stat.is_empty():
			is_valid = _validate_stat_value(resource_path, "%s.%s" % [item_field, value_field], stat, modifier_dict.get(value_field)) and is_valid
	return is_valid


func _validate_behaviors(resource_path: String, field: String, data: Variant) -> bool:
	var behaviors: Array = _require_array(resource_path, field, data)
	var is_valid: bool = true
	for index: int in range(behaviors.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var behavior: Variant = behaviors[index]
		if not behavior is Dictionary:
			is_valid = _schema_fail(resource_path, item_field, "Dictionary") and is_valid
			continue
		var behavior_dict: Dictionary = behavior as Dictionary
		is_valid = _require_registered(resource_path, "%s.event" % item_field, behavior_dict.get("event"), "events") != "" and is_valid
		is_valid = _require_registered(resource_path, "%s.effect" % item_field, behavior_dict.get("effect"), "effects") != "" and is_valid
		if not behavior_dict.get("params") is Dictionary:
			is_valid = _schema_fail(resource_path, "%s.params" % item_field, "Dictionary") and is_valid
	return is_valid


func _validate_registered_string_array(resource_path: String, field: String, data: Variant, contract_key: String, allow_empty: bool) -> bool:
	var values: Array = _require_array(resource_path, field, data)
	var is_valid: bool = true
	if not allow_empty and values.is_empty():
		is_valid = _schema_fail(resource_path, field, "non-empty Array") and is_valid
	var seen: Dictionary = {}
	for index: int in range(values.size()):
		var value: String = _require_registered(resource_path, "%s[%d]" % [field, index], values[index], contract_key)
		if not value.is_empty():
			if seen.has(value):
				is_valid = _schema_fail(resource_path, "%s[%d]" % [field, index], "unique id") and is_valid
			seen[value] = true
	return is_valid


func _require_csv_int(resource_path: String, field: String, value: Variant, minimum: Variant = null) -> bool:
	var parsed: Variant = _parse_int(value)
	if parsed == null:
		return _schema_fail(resource_path, field, "int")
	return _require_int(resource_path, field, parsed, minimum)


func _require_csv_number(resource_path: String, field: String, value: Variant, minimum: Variant = null, maximum: Variant = null, exclusive_minimum: bool = false) -> bool:
	var parsed: Variant = _parse_float(value)
	if parsed == null:
		return _schema_fail(resource_path, field, "number")
	return _require_number(resource_path, field, parsed, minimum, maximum, exclusive_minimum)


func _validate_stat_value(resource_path: String, field: String, stat: String, value: Variant) -> bool:
	if not has_contract_value("stats", stat):
		return _schema_fail(resource_path, field, "registered stat id")
	if INT_STATS.has(stat):
		return _require_int(resource_path, field, value, 1)
	if RATIO_STATS.has(stat):
		return _require_number(resource_path, field, value, 0.0, 1.0)
	if POSITIVE_STATS.has(stat):
		return _require_number(resource_path, field, value, 0.0, null, true)
	if NON_NEGATIVE_STATS.has(stat):
		return _require_number(resource_path, field, value, 0.0)
	return _require_number(resource_path, field, value)


func _collect_character_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(CHARACTERS_PATH)
	if not data is Dictionary:
		return ids
	var characters: Variant = (data as Dictionary).get("characters")
	if not characters is Array:
		return ids
	for character: Variant in characters:
		if character is Dictionary and (character as Dictionary).get("id") is String:
			ids[String((character as Dictionary).get("id"))] = true
	return ids


func _collect_weapon_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(WEAPONS_PATH)
	if not data is Dictionary:
		return ids
	var weapons: Variant = (data as Dictionary).get("weapons")
	if not weapons is Array:
		return ids
	for weapon: Variant in weapons:
		if weapon is Dictionary and (weapon as Dictionary).get("id") is String:
			ids[String((weapon as Dictionary).get("id"))] = true
	return ids


func _collect_enemy_ids() -> Dictionary:
	var ids: Dictionary = {}
	var rows: Array[Dictionary] = load_csv(ENEMIES_PATH)
	for row: Dictionary in rows:
		var enemy_id: String = String(row.get("id", ""))
		if not enemy_id.is_empty():
			ids[enemy_id] = true
	return ids


func _collect_enemy_ai_profile_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(ENEMY_AI_PROFILES_PATH)
	if not data is Dictionary:
		return ids
	var profiles: Variant = (data as Dictionary).get("profiles")
	if not profiles is Array:
		return ids
	for profile: Variant in profiles:
		if profile is Dictionary and (profile as Dictionary).get("id") is String:
			ids[String((profile as Dictionary).get("id"))] = true
	return ids


func _collect_hazard_ids() -> Dictionary:
	var ids: Dictionary = {}
	var rows: Array[Dictionary] = load_csv(HAZARDS_PATH)
	for row: Dictionary in rows:
		var hazard_id: String = String(row.get("id", ""))
		if not hazard_id.is_empty():
			ids[hazard_id] = maxi(String(row.get("radius_tiles", "1")).to_int(), 1)
	return ids


func _collect_relic_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(RELICS_PATH)
	if not data is Dictionary:
		return ids
	var relics: Variant = (data as Dictionary).get("relics")
	if not relics is Array:
		return ids
	for relic: Variant in relics:
		if relic is Dictionary and (relic as Dictionary).get("id") is String:
			ids[String((relic as Dictionary).get("id"))] = true
	return ids


func _collect_active_item_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(ACTIVE_ITEMS_PATH)
	if not data is Dictionary:
		return ids
	var active_items: Variant = (data as Dictionary).get("active_items")
	if not active_items is Array:
		return ids
	for active_item: Variant in active_items:
		if active_item is Dictionary and (active_item as Dictionary).get("id") is String:
			ids[String((active_item as Dictionary).get("id"))] = true
	return ids


func _collect_consumable_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(CONSUMABLES_PATH)
	if not data is Dictionary:
		return ids
	var consumables: Variant = (data as Dictionary).get("consumables")
	if not consumables is Array:
		return ids
	for consumable: Variant in consumables:
		if consumable is Dictionary and (consumable as Dictionary).get("id") is String:
			ids[String((consumable as Dictionary).get("id"))] = true
	return ids


func _collect_skill_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(SKILLS_PATH)
	if not data is Dictionary:
		return ids
	var skills: Variant = (data as Dictionary).get("skills")
	if not skills is Array:
		return ids
	for skill: Variant in skills:
		if skill is Dictionary and (skill as Dictionary).get("id") is String:
			ids[String((skill as Dictionary).get("id"))] = true
	return ids


func _collect_gear_mod_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(GEAR_MODS_PATH)
	if not data is Dictionary:
		return ids
	var mods: Variant = (data as Dictionary).get("mods")
	if not mods is Array:
		return ids
	for mod: Variant in mods:
		if mod is Dictionary and (mod as Dictionary).get("id") is String:
			ids[String((mod as Dictionary).get("id"))] = true
	return ids


func _collect_gear_mod_rarity_max_ranks() -> Dictionary:
	var ranks: Dictionary = {}
	var data: Variant = load_json(GEAR_MODS_PATH)
	if not data is Dictionary:
		return ranks
	var mods: Variant = (data as Dictionary).get("mods")
	if not mods is Array:
		return ranks
	for mod: Variant in mods:
		if not mod is Dictionary:
			continue
		var mod_dict: Dictionary = mod as Dictionary
		if not mod_dict.get("rarity") is String or not _is_int_like(mod_dict.get("max_rank")):
			continue
		var rarity: String = String(mod_dict.get("rarity"))
		var max_rank: int = _variant_to_int(mod_dict.get("max_rank"))
		ranks[rarity] = maxi(int(ranks.get(rarity, 0)), max_rank)
	return ranks


func _collect_growth_pool_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(GROWTH_POOLS_PATH)
	if not data is Dictionary:
		return ids
	var pools: Variant = (data as Dictionary).get("pools")
	if not pools is Array:
		return ids
	for pool: Variant in pools:
		if pool is Dictionary and (pool as Dictionary).get("id") is String:
			ids[String((pool as Dictionary).get("id"))] = true
	return ids


func _validate_content_tags(resource_path: String, field: String, value: Variant) -> bool:
	var tags: Array = _require_array(resource_path, field, value)
	var is_valid: bool = true
	for tag_index: int in range(tags.size()):
		var tag_value: String = _require_registered(resource_path, "%s[%d]" % [field, tag_index], tags[tag_index], "content_tags")
		if tag_value.is_empty():
			is_valid = false
	return is_valid


func _validate_module_world_data(enemy_ids: Dictionary, hazard_ids: Dictionary) -> bool:
	var template_result: Dictionary = _validate_module_templates_json(enemy_ids, hazard_ids)
	var templates: Dictionary = template_result.get("templates", {}) as Dictionary
	var is_valid: bool = bool(template_result.get("is_valid", false))
	var data: Variant = load_json(MODULE_WORLDS_PATH)
	if not data is Dictionary:
		return _schema_fail(MODULE_WORLDS_PATH, "root", "Dictionary") and is_valid
	var payload: Dictionary = data as Dictionary
	is_valid = _require_exact_int(MODULE_WORLDS_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var worlds: Array = _require_array(MODULE_WORLDS_PATH, "worlds", payload.get("worlds"))
	if worlds.is_empty():
		is_valid = _schema_fail(MODULE_WORLDS_PATH, "worlds", "non-empty Array") and is_valid
	_last_schema_counts["module_worlds"] = worlds.size()
	var seen_worlds: Dictionary = {}
	for world_index: int in range(worlds.size()):
		var field: String = "worlds[%d]" % world_index
		var world_value: Variant = worlds[world_index]
		if not world_value is Dictionary:
			is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "Dictionary") and is_valid
			continue
		var world: Dictionary = world_value as Dictionary
		var world_id: String = String(world.get("id", ""))
		is_valid = _require_non_empty_string(MODULE_WORLDS_PATH, "%s.id" % field, world.get("id")) and is_valid
		if not world_id.is_empty():
			if seen_worlds.has(world_id):
				is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.id" % field, "unique module world id") and is_valid
			seen_worlds[world_id] = true
		for dimension: String in ["columns", "rows"]:
			is_valid = _require_exact_int(MODULE_WORLDS_PATH, "%s.%s" % [field, dimension], world.get(dimension), 9) and is_valid
		for module_dimension: String in ["module_columns", "module_rows"]:
			is_valid = _require_exact_int(MODULE_WORLDS_PATH, "%s.%s" % [field, module_dimension], world.get(module_dimension), 11) and is_valid
		is_valid = _require_number(MODULE_WORLDS_PATH, "%s.cell_size" % field, world.get("cell_size"), 0.0, null, true) and is_valid
		is_valid = _require_exact_int(MODULE_WORLDS_PATH, "%s.active_radius" % field, world.get("active_radius"), 1) and is_valid
		is_valid = _require_bool(MODULE_WORLDS_PATH, "%s.seal_outer_edges" % field, world.get("seal_outer_edges")) and is_valid
		if world.get("seal_outer_edges") is bool and not bool(world.get("seal_outer_edges")):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.seal_outer_edges" % field, "true") and is_valid

		var anchors: Dictionary = {}
		for anchor_name: String in ["start_slot", "objective_slot", "extraction_slot"]:
			var anchor: Variant = _validate_module_cell(MODULE_WORLDS_PATH, "%s.%s" % [field, anchor_name], world.get(anchor_name), 9, 9)
			if anchor == null:
				is_valid = false
			else:
				anchors[anchor_name] = anchor
		var route_result: Dictionary = _validate_module_route_budget("%s.route_budget" % field, world.get("route_budget"))
		is_valid = bool(route_result.get("is_valid", false)) and is_valid

		var fixed_slots: Array = _require_array(MODULE_WORLDS_PATH, "%s.fixed_slots" % field, world.get("fixed_slots"))
		var fixed_result: Dictionary = _validate_module_assignment_entries("%s.fixed_slots" % field, fixed_slots, templates, false, false)
		is_valid = bool(fixed_result.get("is_valid", false)) and is_valid
		is_valid = _validate_module_fixed_anchor_roles(
			"%s.fixed_slots" % field,
			fixed_result.get("assignment", {}) as Dictionary,
			templates,
			anchors
		) and is_valid

		var template_pool: Array = _require_array(MODULE_WORLDS_PATH, "%s.template_pool" % field, world.get("template_pool"))
		var seen_pool: Dictionary = {}
		for pool_index: int in range(template_pool.size()):
			var pool_field: String = "%s.template_pool[%d]" % [field, pool_index]
			var template_id: String = String(template_pool[pool_index])
			is_valid = _require_non_empty_string(MODULE_WORLDS_PATH, pool_field, template_pool[pool_index]) and is_valid
			if seen_pool.has(template_id):
				is_valid = _schema_fail(MODULE_WORLDS_PATH, pool_field, "unique template id") and is_valid
			seen_pool[template_id] = true
			if not templates.has(template_id):
				is_valid = _schema_fail(MODULE_WORLDS_PATH, pool_field, "template defined in module_templates.json") and is_valid
				continue
			var template: Dictionary = templates[template_id] as Dictionary
			if String(template.get("review_status", "")) != MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED:
				is_valid = _schema_fail(MODULE_WORLDS_PATH, pool_field, "approved template") and is_valid
			if String(template.get("role", "")) == MODULE_ROLES.MODULE_ROLE_SEALED:
				is_valid = _schema_fail(MODULE_WORLDS_PATH, pool_field, "non-sealed template") and is_valid

		for assignment_name: String in ["fallback_assignment", "technical_slice_assignment"]:
			var technical: bool = assignment_name == "technical_slice_assignment"
			var assignment_values: Array = _require_array(MODULE_WORLDS_PATH, "%s.%s" % [field, assignment_name], world.get(assignment_name))
			var assignment_result: Dictionary = _validate_module_assignment_entries("%s.%s" % [field, assignment_name], assignment_values, templates, true, technical)
			is_valid = bool(assignment_result.get("is_valid", false)) and is_valid
			var assignment: Dictionary = assignment_result.get("assignment", {}) as Dictionary
			var world_result: Dictionary = _validate_module_assignment_world("%s.%s" % [field, assignment_name], assignment, templates, anchors, route_result, technical)
			is_valid = bool(world_result.get("is_valid", false)) and is_valid
	return is_valid


func _validate_module_templates_json(enemy_ids: Dictionary, hazard_ids: Dictionary) -> Dictionary:
	var is_valid: bool = true
	var templates: Dictionary = {}
	var data: Variant = load_json(MODULE_TEMPLATES_PATH)
	if not data is Dictionary:
		return {"is_valid": _schema_fail(MODULE_TEMPLATES_PATH, "root", "Dictionary"), "templates": templates}
	var payload: Dictionary = data as Dictionary
	is_valid = _require_exact_int(MODULE_TEMPLATES_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid
	var entries: Array = _require_array(MODULE_TEMPLATES_PATH, "templates", payload.get("templates"))
	if entries.is_empty():
		is_valid = _schema_fail(MODULE_TEMPLATES_PATH, "templates", "non-empty Array") and is_valid
	_last_schema_counts["module_templates"] = entries.size()
	var seen_paths: Dictionary = {}
	for index: int in range(entries.size()):
		var field: String = "templates[%d]" % index
		var entry_value: Variant = entries[index]
		if not entry_value is Dictionary:
			is_valid = _schema_fail(MODULE_TEMPLATES_PATH, field, "Dictionary") and is_valid
			continue
		var entry: Dictionary = entry_value as Dictionary
		var template_id: String = String(entry.get("id", ""))
		is_valid = _require_non_empty_string(MODULE_TEMPLATES_PATH, "%s.id" % field, entry.get("id")) and is_valid
		if templates.has(template_id):
			is_valid = _schema_fail(MODULE_TEMPLATES_PATH, "%s.id" % field, "unique template id") and is_valid
		var role: String = _require_registered(MODULE_TEMPLATES_PATH, "%s.role" % field, entry.get("role"), "module_roles")
		if role.is_empty():
			is_valid = false
		is_valid = _require_non_empty_string(MODULE_TEMPLATES_PATH, "%s.source" % field, entry.get("source")) and is_valid
		if String(entry.get("source", "")) != "ai":
			is_valid = _schema_fail(MODULE_TEMPLATES_PATH, "%s.source" % field, "ai") and is_valid
		var review_status: String = _require_registered(MODULE_TEMPLATES_PATH, "%s.review_status" % field, entry.get("review_status"), "module_review_statuses")
		if review_status.is_empty():
			is_valid = false
		is_valid = _validate_content_tags(MODULE_TEMPLATES_PATH, "%s.tags" % field, entry.get("tags", [])) and is_valid
		var allowed_values: Array = _require_array(MODULE_TEMPLATES_PATH, "%s.allowed_rotations" % field, entry.get("allowed_rotations"))
		var allowed_rotations: Dictionary = {}
		if allowed_values.is_empty():
			is_valid = _schema_fail(MODULE_TEMPLATES_PATH, "%s.allowed_rotations" % field, "non-empty Array") and is_valid
		for rotation_index: int in range(allowed_values.size()):
			var rotation_value: Variant = allowed_values[rotation_index]
			var rotation_field: String = "%s.allowed_rotations[%d]" % [field, rotation_index]
			if not _is_int_like(rotation_value) or not [0, 90, 180, 270].has(int(rotation_value)):
				is_valid = _schema_fail(MODULE_TEMPLATES_PATH, rotation_field, "one of 0, 90, 180, 270") and is_valid
				continue
			var rotation: int = int(rotation_value)
			if allowed_rotations.has(rotation):
				is_valid = _schema_fail(MODULE_TEMPLATES_PATH, rotation_field, "unique rotation") and is_valid
			allowed_rotations[rotation] = true
		var module_path: String = String(entry.get("path", ""))
		is_valid = _require_non_empty_string(MODULE_TEMPLATES_PATH, "%s.path" % field, entry.get("path")) and is_valid
		if not module_path.begins_with("res://data/modules/") or not module_path.ends_with(".json") or module_path.contains(".."):
			is_valid = _schema_fail(MODULE_TEMPLATES_PATH, "%s.path" % field, "res://data/modules/*.json path") and is_valid
		elif not FileAccess.file_exists(module_path):
			is_valid = _schema_fail(MODULE_TEMPLATES_PATH, "%s.path" % field, "existing module JSON file") and is_valid
		elif seen_paths.has(module_path):
			is_valid = _schema_fail(MODULE_TEMPLATES_PATH, "%s.path" % field, "unique module path") and is_valid
		else:
			seen_paths[module_path] = true
			var module_data: Variant = load_json(module_path)
			if module_data is Dictionary:
				is_valid = _validate_module_file(module_path, module_data as Dictionary, template_id, role, enemy_ids, hazard_ids) and is_valid
			else:
				is_valid = _schema_fail(module_path, "root", "Dictionary") and is_valid
		if not template_id.is_empty():
			var loaded_module: Variant = load_json(module_path) if FileAccess.file_exists(module_path) else {}
			templates[template_id] = {
				"role": role,
				"review_status": review_status,
				"allowed_rotations": allowed_rotations,
				"data": loaded_module if loaded_module is Dictionary else {},
			}
	_last_schema_counts["module_files"] = seen_paths.size()
	return {"is_valid": is_valid, "templates": templates}


func _validate_module_file(resource_path: String, data: Dictionary, expected_id: String, role: String, enemy_ids: Dictionary, hazard_ids: Dictionary) -> bool:
	var is_valid: bool = true
	is_valid = _require_exact_int(resource_path, "schema_version", data.get("schema_version"), 1) and is_valid
	is_valid = _require_non_empty_string(resource_path, "id", data.get("id")) and is_valid
	if String(data.get("id", "")) != expected_id:
		is_valid = _schema_fail(resource_path, "id", "id matching module template registry") and is_valid
	is_valid = _require_exact_int(resource_path, "columns", data.get("columns"), 11) and is_valid
	is_valid = _require_exact_int(resource_path, "rows", data.get("rows"), 11) and is_valid
	var terrain_rows: Array = _require_array(resource_path, "terrain_rows", data.get("terrain_rows"))
	if terrain_rows.size() != 11:
		is_valid = _schema_fail(resource_path, "terrain_rows", "exactly 11 rows") and is_valid
	for y: int in range(terrain_rows.size()):
		var row: Array = _require_array(resource_path, "terrain_rows[%d]" % y, terrain_rows[y])
		if row.size() != 11:
			is_valid = _schema_fail(resource_path, "terrain_rows[%d]" % y, "exactly 11 terrain tokens") and is_valid
		for x: int in range(row.size()):
			if _require_registered(resource_path, "terrain_rows[%d][%d]" % [y, x], row[x], "module_cell_tokens").is_empty():
				is_valid = false
	var edge_sockets: Variant = data.get("edge_sockets")
	if not edge_sockets is Dictionary:
		is_valid = _schema_fail(resource_path, "edge_sockets", "Dictionary") and is_valid
	else:
		var socket_dict: Dictionary = edge_sockets as Dictionary
		var edge_values: Array = contract_values("module_edge_directions")
		if socket_dict.size() != edge_values.size():
			is_valid = _schema_fail(resource_path, "edge_sockets", "exactly four registered edges") and is_valid
		for edge_value: Variant in edge_values:
			var edge: String = String(edge_value)
			var sockets: Array = _require_array(resource_path, "edge_sockets.%s" % edge, socket_dict.get(edge))
			var seen: Dictionary = {}
			for socket_index: int in range(sockets.size()):
				var socket: Variant = sockets[socket_index]
				if not _is_int_like(socket) or int(socket) < 0 or int(socket) > 10 or seen.has(int(socket)):
					is_valid = _schema_fail(resource_path, "edge_sockets.%s[%d]" % [edge, socket_index], "unique integer 0..10") and is_valid
				elif _is_int_like(socket):
					seen[int(socket)] = true
	var placement_result: Dictionary = _validate_module_placements(resource_path, data.get("placements"), terrain_rows, role, enemy_ids, hazard_ids)
	return bool(placement_result.get("is_valid", false)) and is_valid


func _validate_module_placements(resource_path: String, value: Variant, terrain_rows: Array, role: String, enemy_ids: Dictionary, hazard_ids: Dictionary) -> Dictionary:
	var placements: Array = _require_array(resource_path, "placements", value)
	var is_valid: bool = value is Array
	var counts: Dictionary = {}
	var enemy_count: int = 0
	var occupied: Array[Dictionary] = []
	var danger_cells: Dictionary = {}
	var start_cell: Variant = null
	for index: int in range(placements.size()):
		var field: String = "placements[%d]" % index
		var placement_value: Variant = placements[index]
		if not placement_value is Dictionary:
			is_valid = _schema_fail(resource_path, field, "Dictionary") and is_valid
			continue
		var placement: Dictionary = placement_value as Dictionary
		var placement_type: String = _require_registered(resource_path, "%s.type" % field, placement.get("type"), "module_placement_types")
		if placement_type.is_empty():
			is_valid = false
		var cell: Variant = _validate_module_cell(resource_path, "%s.cell" % field, placement.get("cell"), 11, 11)
		if cell == null:
			is_valid = false
			continue
		var cells: Dictionary = _validate_module_footprint(resource_path, "%s.footprint" % field, placement.get("footprint"), cell as Vector2i)
		if cells.has("invalid"):
			is_valid = false
			cells.erase("invalid")
		counts[placement_type] = int(counts.get(placement_type, 0)) + 1
		occupied.append({"type": placement_type, "cells": cells})
		match placement_type:
			MODULE_PLACEMENT_TYPES.MODULE_PLACE_PLAYER_START:
				start_cell = cell
			MODULE_PLACEMENT_TYPES.MODULE_PLACE_ENEMY_SPAWN:
				var enemy_id: String = String(placement.get("enemy_id", ""))
				is_valid = _require_non_empty_string(resource_path, "%s.enemy_id" % field, placement.get("enemy_id")) and is_valid
				if not enemy_ids.has(enemy_id):
					is_valid = _schema_fail(resource_path, "%s.enemy_id" % field, "enemy defined in enemies.csv") and is_valid
				is_valid = _require_int(resource_path, "%s.count" % field, placement.get("count"), 1) and is_valid
				if _is_int_like(placement.get("count")):
					enemy_count += int(placement.get("count"))
				if not _module_cells_are_floor(terrain_rows, cells):
					is_valid = _schema_fail(resource_path, "%s.cell" % field, "enemy spawn footprint on module_cell_floor terrain") and is_valid
				for danger: Variant in cells.keys():
					danger_cells[danger] = true
			MODULE_PLACEMENT_TYPES.MODULE_PLACE_HAZARD:
				var hazard_id: String = String(placement.get("hazard_id", ""))
				is_valid = _require_non_empty_string(resource_path, "%s.hazard_id" % field, placement.get("hazard_id")) and is_valid
				if not hazard_ids.has(hazard_id):
					is_valid = _schema_fail(resource_path, "%s.hazard_id" % field, "hazard defined in hazards.csv") and is_valid
				for danger: Variant in cells.keys():
					danger_cells[danger] = true
			MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE:
				var rewards: Array = _require_array(resource_path, "%s.resource_rewards" % field, placement.get("resource_rewards"))
				if rewards.is_empty():
					is_valid = _schema_fail(resource_path, "%s.resource_rewards" % field, "non-empty Array") and is_valid
				for reward_index: int in range(rewards.size()):
					if not rewards[reward_index] is Dictionary:
						is_valid = _schema_fail(resource_path, "%s.resource_rewards[%d]" % [field, reward_index], "Dictionary") and is_valid
						continue
					var reward: Dictionary = rewards[reward_index] as Dictionary
					if _require_registered(resource_path, "%s.resource_rewards[%d].id" % [field, reward_index], reward.get("id"), "gear_mod_resources").is_empty():
						is_valid = false
					is_valid = _require_int(resource_path, "%s.resource_rewards[%d].amount" % [field, reward_index], reward.get("amount"), 1) and is_valid
				is_valid = _require_number(resource_path, "%s.claim_radius" % field, placement.get("claim_radius"), 0.0, null, true) and is_valid
			MODULE_PLACEMENT_TYPES.MODULE_PLACE_OBJECTIVE:
				is_valid = _require_number(resource_path, "%s.target_hp" % field, placement.get("target_hp"), 0.0, null, true) and is_valid
				is_valid = _require_number(resource_path, "%s.target_hit_radius" % field, placement.get("target_hit_radius"), 0.0, null, true) and is_valid
			MODULE_PLACEMENT_TYPES.MODULE_PLACE_EXTRACTION:
				is_valid = _require_number(resource_path, "%s.radius" % field, placement.get("radius"), 0.0, null, true) and is_valid
				is_valid = _require_number(resource_path, "%s.hold_time" % field, placement.get("hold_time"), 0.0, null, true) and is_valid
			_:
				pass
	var danger_types: Array[String] = [MODULE_PLACEMENT_TYPES.MODULE_PLACE_ENEMY_SPAWN, MODULE_PLACEMENT_TYPES.MODULE_PLACE_HAZARD]
	var protected_types: Array[String] = [MODULE_PLACEMENT_TYPES.MODULE_PLACE_PLAYER_START, MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE, MODULE_PLACEMENT_TYPES.MODULE_PLACE_OBJECTIVE, MODULE_PLACEMENT_TYPES.MODULE_PLACE_EXTRACTION]
	for left_index: int in range(occupied.size()):
		var left: Dictionary = occupied[left_index]
		for right_index: int in range(left_index + 1, occupied.size()):
			var right: Dictionary = occupied[right_index]
			var conflicting: bool = (danger_types.has(String(left.get("type"))) and protected_types.has(String(right.get("type")))) or (danger_types.has(String(right.get("type"))) and protected_types.has(String(left.get("type"))))
			if conflicting and _dictionaries_share_key(left.get("cells", {}) as Dictionary, right.get("cells", {}) as Dictionary):
				is_valid = _schema_fail(resource_path, "placements", "no danger overlap with player start, objective, extraction, or reward") and is_valid
	is_valid = _validate_module_role_budget(resource_path, role, counts, enemy_count) and is_valid
	if role == MODULE_ROLES.MODULE_ROLE_START and start_cell is Vector2i:
		for danger: Variant in danger_cells.keys():
			var danger_cell: Vector2i = danger as Vector2i
			if maxi(absi(danger_cell.x - (start_cell as Vector2i).x), absi(danger_cell.y - (start_cell as Vector2i).y)) <= 2:
				is_valid = _schema_fail(resource_path, "placements", "2-cell danger-free player start radius") and is_valid
	return {"is_valid": is_valid}


func _module_cells_are_floor(terrain_rows: Array, cells: Dictionary) -> bool:
	for raw_cell: Variant in cells.keys():
		if not raw_cell is Vector2i:
			return false
		var cell: Vector2i = raw_cell as Vector2i
		if cell.y < 0 or cell.y >= terrain_rows.size() or not terrain_rows[cell.y] is Array:
			return false
		var row: Array = terrain_rows[cell.y] as Array
		if cell.x < 0 or cell.x >= row.size() or String(row[cell.x]) != MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			return false
	return true


func _validate_module_footprint(resource_path: String, field: String, value: Variant, cell: Vector2i) -> Dictionary:
	var width: int = 1
	var height: int = 1
	var cells: Dictionary = {}
	if value != null:
		if not value is Dictionary:
			_schema_fail(resource_path, field, "Dictionary")
			cells["invalid"] = true
		else:
			var footprint: Dictionary = value as Dictionary
			if not _require_int(resource_path, "%s.width" % field, footprint.get("width"), 1):
				cells["invalid"] = true
			if not _require_int(resource_path, "%s.height" % field, footprint.get("height"), 1):
				cells["invalid"] = true
			if _is_int_like(footprint.get("width")):
				width = int(footprint.get("width"))
			if _is_int_like(footprint.get("height")):
				height = int(footprint.get("height"))
	for y: int in range(height):
		for x: int in range(width):
			var occupied_cell := Vector2i(cell.x + x, cell.y + y)
			if occupied_cell.x < 0 or occupied_cell.x >= 11 or occupied_cell.y < 0 or occupied_cell.y >= 11:
				_schema_fail(resource_path, field, "footprint inside 11x11 module")
				cells["invalid"] = true
			else:
				cells[occupied_cell] = true
	return cells


func _validate_module_role_budget(resource_path: String, role: String, counts: Dictionary, enemy_count: int) -> bool:
	var hazards: int = int(counts.get(MODULE_PLACEMENT_TYPES.MODULE_PLACE_HAZARD, 0))
	var rewards: int = int(counts.get(MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE, 0))
	match role:
		MODULE_ROLES.MODULE_ROLE_START:
			if enemy_count != 0 or hazards != 0 or int(counts.get(MODULE_PLACEMENT_TYPES.MODULE_PLACE_PLAYER_START, 0)) != 1:
				return _schema_fail(resource_path, "placements", "one player start and no enemies or hazards")
		MODULE_ROLES.MODULE_ROLE_CONNECTOR:
			if enemy_count > 4 or hazards > 1:
				return _schema_fail(resource_path, "placements", "connector budget")
		MODULE_ROLES.MODULE_ROLE_COMBAT:
			if enemy_count < 6 or enemy_count > 12 or hazards > 2:
				return _schema_fail(resource_path, "placements", "combat budget")
		MODULE_ROLES.MODULE_ROLE_RESOURCE:
			if enemy_count < 2 or enemy_count > 6 or rewards != 1:
				return _schema_fail(resource_path, "placements", "resource budget")
		MODULE_ROLES.MODULE_ROLE_HAZARD:
			if enemy_count < 2 or enemy_count > 6 or hazards < 2 or hazards > 4:
				return _schema_fail(resource_path, "placements", "hazard budget")
		MODULE_ROLES.MODULE_ROLE_OBJECTIVE:
			if int(counts.get(MODULE_PLACEMENT_TYPES.MODULE_PLACE_OBJECTIVE, 0)) != 1:
				return _schema_fail(resource_path, "placements", "exactly one objective")
		MODULE_ROLES.MODULE_ROLE_EXTRACTION:
			if int(counts.get(MODULE_PLACEMENT_TYPES.MODULE_PLACE_EXTRACTION, 0)) != 1:
				return _schema_fail(resource_path, "placements", "exactly one extraction")
		MODULE_ROLES.MODULE_ROLE_SEALED:
			if not counts.is_empty():
				return _schema_fail(resource_path, "placements", "no placements in sealed module")
		_:
			pass
	return true


func _validate_module_route_budget(field: String, value: Variant) -> Dictionary:
	var result: Dictionary = {"is_valid": true}
	if not value is Dictionary:
		result["is_valid"] = _schema_fail(MODULE_WORLDS_PATH, field, "Dictionary")
		return result
	var budget: Dictionary = value as Dictionary
	for segment: String in ["start_to_objective", "objective_to_extraction"]:
		var segment_value: Variant = budget.get(segment)
		if not segment_value is Dictionary:
			result["is_valid"] = _schema_fail(MODULE_WORLDS_PATH, "%s.%s" % [field, segment], "Dictionary") and bool(result["is_valid"])
			continue
		var segment_dict: Dictionary = segment_value as Dictionary
		var minimum: Variant = segment_dict.get("min_crossings")
		var maximum: Variant = segment_dict.get("max_crossings")
		result["is_valid"] = _require_int(MODULE_WORLDS_PATH, "%s.%s.min_crossings" % [field, segment], minimum, 0) and bool(result["is_valid"])
		result["is_valid"] = _require_int(MODULE_WORLDS_PATH, "%s.%s.max_crossings" % [field, segment], maximum, 0) and bool(result["is_valid"])
		if _is_int_like(minimum) and _is_int_like(maximum) and int(minimum) > int(maximum):
			result["is_valid"] = _schema_fail(MODULE_WORLDS_PATH, "%s.%s" % [field, segment], "min_crossings <= max_crossings") and bool(result["is_valid"])
		result[segment] = Vector2i(int(minimum) if _is_int_like(minimum) else -1, int(maximum) if _is_int_like(maximum) else -1)
	var main_value: Variant = budget.get("main_route_modules")
	if not main_value is Dictionary:
		result["is_valid"] = _schema_fail(MODULE_WORLDS_PATH, "%s.main_route_modules" % field, "Dictionary") and bool(result["is_valid"])
	else:
		var main: Dictionary = main_value as Dictionary
		result["is_valid"] = _require_int(MODULE_WORLDS_PATH, "%s.main_route_modules.min" % field, main.get("min"), 1) and bool(result["is_valid"])
		result["is_valid"] = _require_int(MODULE_WORLDS_PATH, "%s.main_route_modules.max" % field, main.get("max"), 1) and bool(result["is_valid"])
		if _is_int_like(main.get("min")) and _is_int_like(main.get("max")):
			result["main_route_modules"] = Vector2i(int(main.get("min")), int(main.get("max")))
			if int(main.get("min")) > int(main.get("max")):
				result["is_valid"] = _schema_fail(MODULE_WORLDS_PATH, "%s.main_route_modules" % field, "min <= max") and bool(result["is_valid"])
	var optional: Variant = budget.get("optional_exploration_modules")
	if not optional is Dictionary:
		result["is_valid"] = _schema_fail(MODULE_WORLDS_PATH, "%s.optional_exploration_modules" % field, "Dictionary") and bool(result["is_valid"])
	else:
		result["is_valid"] = _require_int(MODULE_WORLDS_PATH, "%s.optional_exploration_modules.max" % field, (optional as Dictionary).get("max"), 0, 14) and bool(result["is_valid"])
	return result


func _validate_module_assignment_entries(field: String, entries: Array, templates: Dictionary, exact_81: bool, technical: bool) -> Dictionary:
	var is_valid: bool = true
	var assignment: Dictionary = {}
	if exact_81 and entries.size() != 81:
		is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "exactly 81 slot assignments") and is_valid
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		if not entries[index] is Dictionary:
			is_valid = _schema_fail(MODULE_WORLDS_PATH, item_field, "Dictionary") and is_valid
			continue
		var entry: Dictionary = entries[index] as Dictionary
		var slot: Variant = _validate_module_cell(MODULE_WORLDS_PATH, "%s.slot" % item_field, entry.get("slot"), 9, 9)
		if slot == null:
			is_valid = false
			continue
		var template_id: String = String(entry.get("template_id", ""))
		is_valid = _require_non_empty_string(MODULE_WORLDS_PATH, "%s.template_id" % item_field, entry.get("template_id")) and is_valid
		var rotation: int = int(entry.get("rotation", -1)) if _is_int_like(entry.get("rotation")) else -1
		if not [0, 90, 180, 270].has(rotation):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.rotation" % item_field, "one of 0, 90, 180, 270") and is_valid
		if assignment.has(slot):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.slot" % item_field, "unique slot") and is_valid
		else:
			assignment[slot] = {"template_id": template_id, "rotation": rotation}
		if not templates.has(template_id):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.template_id" % item_field, "template defined in module_templates.json") and is_valid
			continue
		var template: Dictionary = templates[template_id] as Dictionary
		var allowed: Dictionary = template.get("allowed_rotations", {}) as Dictionary
		if not allowed.has(rotation):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.rotation" % item_field, "rotation allowed by template") and is_valid
		var role: String = String(template.get("role", ""))
		var approved: bool = String(template.get("review_status", "")) == MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED
		var inside_slice: bool = (slot as Vector2i).x >= 3 and (slot as Vector2i).x <= 5 and (slot as Vector2i).y >= 3 and (slot as Vector2i).y <= 5
		var technical_exception: bool = technical and role == MODULE_ROLES.MODULE_ROLE_SEALED and not inside_slice
		if not approved and not technical_exception:
			is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.template_id" % item_field, "approved template") and is_valid
		if exact_81 and not technical and role == MODULE_ROLES.MODULE_ROLE_SEALED:
			is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.template_id" % item_field, "non-sealed fallback template") and is_valid
		if exact_81 and technical and ((inside_slice and role == MODULE_ROLES.MODULE_ROLE_SEALED) or (not inside_slice and role != MODULE_ROLES.MODULE_ROLE_SEALED)):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, "%s.template_id" % item_field, "open center 3x3 and sealed outer 72 slots") and is_valid
	if exact_81 and assignment.size() != 81:
		is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "all 81 unique slots") and is_valid
	return {"is_valid": is_valid, "assignment": assignment}


func _validate_module_fixed_anchor_roles(field: String, assignment: Dictionary, templates: Dictionary, anchors: Dictionary) -> bool:
	var is_valid: bool = true
	for anchor_role: Array in [
		["start_slot", MODULE_ROLES.MODULE_ROLE_START],
		["objective_slot", MODULE_ROLES.MODULE_ROLE_OBJECTIVE],
		["extraction_slot", MODULE_ROLES.MODULE_ROLE_EXTRACTION],
	]:
		var anchor_name: String = String(anchor_role[0])
		var role_count: int = 0
		for assigned_value: Variant in assignment.values():
			var assigned_entry: Dictionary = assigned_value as Dictionary
			var assigned_template_id: String = String(assigned_entry.get("template_id", ""))
			if templates.has(assigned_template_id) and String((templates[assigned_template_id] as Dictionary).get("role", "")) == String(anchor_role[1]):
				role_count += 1
		if role_count != 1:
			is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "exactly one %s" % String(anchor_role[1])) and is_valid
		if not anchors.has(anchor_name):
			continue
		var anchor: Vector2i = anchors[anchor_name] as Vector2i
		if not assignment.has(anchor):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "assignment for configured %s" % anchor_name) and is_valid
			continue
		var assigned: Dictionary = assignment[anchor] as Dictionary
		var template_id: String = String(assigned.get("template_id", ""))
		if templates.has(template_id) and String((templates[template_id] as Dictionary).get("role", "")) != String(anchor_role[1]):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "%s uses %s" % [anchor_name, String(anchor_role[1])]) and is_valid
	return is_valid


func _validate_module_assignment_world(field: String, assignment: Dictionary, templates: Dictionary, anchors: Dictionary, route_budget: Dictionary, technical: bool) -> Dictionary:
	var is_valid: bool = true
	if assignment.size() != 81:
		return {"is_valid": false}
	var effective_anchors: Dictionary = anchors.duplicate()
	if technical:
		for anchor_role: Array in [["start_slot", MODULE_ROLES.MODULE_ROLE_START], ["objective_slot", MODULE_ROLES.MODULE_ROLE_OBJECTIVE], ["extraction_slot", MODULE_ROLES.MODULE_ROLE_EXTRACTION]]:
			var role_slots: Array[Vector2i] = []
			for slot_value: Variant in assignment.keys():
				var assigned: Dictionary = assignment[slot_value] as Dictionary
				if templates.has(String(assigned.get("template_id"))) and String((templates[String(assigned.get("template_id"))] as Dictionary).get("role")) == String(anchor_role[1]):
					role_slots.append(slot_value as Vector2i)
			if role_slots.size() != 1:
				is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "exactly one %s in technical slice" % String(anchor_role[1])) and is_valid
			else:
				effective_anchors[String(anchor_role[0])] = role_slots[0]
	for anchor_role: Array in [["start_slot", MODULE_ROLES.MODULE_ROLE_START], ["objective_slot", MODULE_ROLES.MODULE_ROLE_OBJECTIVE], ["extraction_slot", MODULE_ROLES.MODULE_ROLE_EXTRACTION]]:
		if not effective_anchors.has(String(anchor_role[0])):
			continue
		var anchor: Vector2i = effective_anchors[String(anchor_role[0])] as Vector2i
		var assigned: Dictionary = assignment[anchor] as Dictionary
		if templates.has(String(assigned.get("template_id"))) and String((templates[String(assigned.get("template_id"))] as Dictionary).get("role")) != String(anchor_role[1]):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "%s uses %s" % [String(anchor_role[0]), String(anchor_role[1])]) and is_valid
	var graph: Dictionary = {}
	for slot_value: Variant in assignment.keys():
		graph[slot_value] = []
	for y: int in range(9):
		for x: int in range(9):
			var slot := Vector2i(x, y)
			for neighbor_info: Array in [[Vector2i(x + 1, y), MODULE_EDGE_DIRECTIONS.EDGE_EAST, MODULE_EDGE_DIRECTIONS.EDGE_WEST], [Vector2i(x, y + 1), MODULE_EDGE_DIRECTIONS.EDGE_SOUTH, MODULE_EDGE_DIRECTIONS.EDGE_NORTH]]:
				var neighbor: Vector2i = neighbor_info[0] as Vector2i
				if not assignment.has(neighbor):
					continue
				var left_role: String = _assignment_role(assignment[slot] as Dictionary, templates)
				var right_role: String = _assignment_role(assignment[neighbor] as Dictionary, templates)
				if left_role == MODULE_ROLES.MODULE_ROLE_SEALED or right_role == MODULE_ROLES.MODULE_ROLE_SEALED:
					continue
				var left_sockets: Dictionary = _effective_module_sockets(assignment[slot] as Dictionary, templates, String(neighbor_info[1]))
				var right_sockets: Dictionary = _effective_module_sockets(assignment[neighbor] as Dictionary, templates, String(neighbor_info[2]))
				if left_sockets != right_sockets:
					is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "matching adjacent sockets") and is_valid
				elif not left_sockets.is_empty():
					(graph[slot] as Array).append(neighbor)
					(graph[neighbor] as Array).append(slot)
	var start: Variant = effective_anchors.get("start_slot")
	var objective: Variant = effective_anchors.get("objective_slot")
	var extraction: Variant = effective_anchors.get("extraction_slot")
	if not start is Vector2i or not objective is Vector2i or not extraction is Vector2i:
		return {"is_valid": false}
	var start_distances: Dictionary = _module_graph_distances(graph, start as Vector2i)
	for slot_value: Variant in assignment.keys():
		if _assignment_role(assignment[slot_value] as Dictionary, templates) != MODULE_ROLES.MODULE_ROLE_SEALED and not start_distances.has(slot_value):
			is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "all non-sealed slots reachable from start") and is_valid
			break
	if not start_distances.has(objective):
		is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "reachable start -> objective") and is_valid
		return {"is_valid": is_valid}
	var objective_distances: Dictionary = _module_graph_distances(graph, objective as Vector2i)
	if not objective_distances.has(extraction):
		is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "reachable objective -> extraction") and is_valid
		return {"is_valid": is_valid}
	if not technical:
		is_valid = _validate_module_route_distance(field, "start_to_objective", int(start_distances[objective]), route_budget.get("start_to_objective")) and is_valid
		is_valid = _validate_module_route_distance(field, "objective_to_extraction", int(objective_distances[extraction]), route_budget.get("objective_to_extraction")) and is_valid
		if route_budget.get("main_route_modules") is Vector2i:
			var main_range: Vector2i = route_budget.get("main_route_modules") as Vector2i
			var main_count: int = int(start_distances[objective]) + int(objective_distances[extraction]) + 1
			if main_count < main_range.x or main_count > main_range.y:
				is_valid = _schema_fail(MODULE_WORLDS_PATH, field, "main route module count inside budget") and is_valid
	return {"is_valid": is_valid}


func _validate_module_route_distance(field: String, label: String, distance: int, budget: Variant) -> bool:
	if not budget is Vector2i:
		return false
	var range_value: Vector2i = budget as Vector2i
	if distance < range_value.x or distance > range_value.y:
		return _schema_fail(MODULE_WORLDS_PATH, field, "%s crossings inside budget" % label)
	return true


func _assignment_role(assigned: Dictionary, templates: Dictionary) -> String:
	var template_id: String = String(assigned.get("template_id", ""))
	if not templates.has(template_id):
		return ""
	return String((templates[template_id] as Dictionary).get("role", ""))


func _effective_module_sockets(assigned: Dictionary, templates: Dictionary, requested_edge: String) -> Dictionary:
	var result: Dictionary = {}
	var template_id: String = String(assigned.get("template_id", ""))
	if not templates.has(template_id):
		return result
	var module_data: Variant = (templates[template_id] as Dictionary).get("data")
	if not module_data is Dictionary or not (module_data as Dictionary).get("edge_sockets") is Dictionary:
		return result
	var sockets: Dictionary = (module_data as Dictionary).get("edge_sockets") as Dictionary
	var rotation: int = int(assigned.get("rotation", 0))
	for source_edge: String in MODULE_EDGE_DIRECTIONS.VALUES:
		if not sockets.get(source_edge) is Array:
			continue
		for socket: Variant in sockets.get(source_edge) as Array:
			if not _is_int_like(socket) or int(socket) < 0 or int(socket) > 10:
				continue
			var rotated: Array = _rotate_module_socket(source_edge, int(socket), rotation)
			if String(rotated[0]) == requested_edge:
				result[int(rotated[1])] = true
	return result


func _rotate_module_socket(edge: String, index: int, rotation: int) -> Array:
	var point := Vector2i(0, index)
	match edge:
		MODULE_EDGE_DIRECTIONS.EDGE_NORTH: point = Vector2i(index, 0)
		MODULE_EDGE_DIRECTIONS.EDGE_SOUTH: point = Vector2i(index, 10)
		MODULE_EDGE_DIRECTIONS.EDGE_EAST: point = Vector2i(10, index)
		_: point = Vector2i(0, index)
	for _step: int in range(int(posmod(rotation, 360) / 90)):
		point = Vector2i(10 - point.y, point.x)
	if point.y == 0:
		return [MODULE_EDGE_DIRECTIONS.EDGE_NORTH, point.x]
	if point.y == 10:
		return [MODULE_EDGE_DIRECTIONS.EDGE_SOUTH, point.x]
	if point.x == 10:
		return [MODULE_EDGE_DIRECTIONS.EDGE_EAST, point.y]
	return [MODULE_EDGE_DIRECTIONS.EDGE_WEST, point.y]


func _module_graph_distances(graph: Dictionary, start: Vector2i) -> Dictionary:
	var distances: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	var cursor: int = 0
	while cursor < queue.size():
		var slot: Vector2i = queue[cursor]
		cursor += 1
		for neighbor: Variant in graph.get(slot, []) as Array:
			if not distances.has(neighbor):
				distances[neighbor] = int(distances[slot]) + 1
				queue.append(neighbor as Vector2i)
	return distances


func _validate_module_cell(resource_path: String, field: String, value: Variant, columns: int, rows: int) -> Variant:
	if not value is Dictionary:
		_schema_fail(resource_path, field, "Dictionary with x/y")
		return null
	var cell: Dictionary = value as Dictionary
	if not _require_int(resource_path, "%s.x" % field, cell.get("x"), 0):
		return null
	if not _require_int(resource_path, "%s.y" % field, cell.get("y"), 0):
		return null
	var x: int = int(cell.get("x"))
	var y: int = int(cell.get("y"))
	if x >= columns or y >= rows:
		_schema_fail(resource_path, field, "cell inside %dx%d bounds" % [columns, rows])
		return null
	return Vector2i(x, y)


func _require_exact_int(resource_path: String, field: String, value: Variant, expected: int) -> bool:
	if not _require_int(resource_path, field, value):
		return false
	if int(value) != expected:
		return _schema_fail(resource_path, field, "int equal to %d" % expected)
	return true


func _dictionaries_share_key(left: Dictionary, right: Dictionary) -> bool:
	for key: Variant in left.keys():
		if right.has(key):
			return true
	return false


func _collect_game_mode_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(GAME_MODES_PATH)
	if not data is Dictionary:
		return ids
	var modes: Variant = (data as Dictionary).get("modes")
	if not modes is Array:
		return ids
	for mode: Variant in modes:
		if mode is Dictionary and (mode as Dictionary).get("id") is String:
			ids[String((mode as Dictionary).get("id"))] = true
	return ids


func _collect_map_layout_ids() -> Dictionary:
	var ids: Dictionary = {}
	var data: Variant = load_json(MAP_LAYOUTS_PATH)
	if not data is Dictionary:
		return ids
	var layouts: Variant = (data as Dictionary).get("layouts")
	if not layouts is Array:
		return ids
	for layout: Variant in layouts:
		if layout is Dictionary and (layout as Dictionary).get("id") is String:
			ids[String((layout as Dictionary).get("id"))] = true
	return ids


func _collect_spawn_wave_ids_by_mode() -> Dictionary:
	var ids_by_mode: Dictionary = {}
	var rows: Array[Dictionary] = load_csv(SPAWN_WAVES_PATH)
	for row: Dictionary in rows:
		var mode_id: String = String(row.get("mode_id", ""))
		var wave_id: String = String(row.get("id", ""))
		if mode_id.is_empty() or wave_id.is_empty():
			continue
		if not ids_by_mode.has(mode_id):
			ids_by_mode[mode_id] = {}
		var mode_waves: Dictionary = ids_by_mode[mode_id]
		mode_waves[wave_id] = true
		ids_by_mode[mode_id] = mode_waves
	return ids_by_mode


func _collect_locale_keys() -> Dictionary:
	var rows: Array[Dictionary] = _load_locale_string_rows()
	if rows.is_empty() and _should_collect_locale_keys_from_translations():
		return {}

	var keys: Dictionary = {}
	for row: Dictionary in rows:
		var key: String = String(row.get("keys", ""))
		if key.is_empty() or keys.has(key):
			continue
		keys[key] = true
	return keys


func _load_locale_string_rows() -> Array[Dictionary]:
	if _should_collect_locale_keys_from_translations():
		return []
	return load_csv(LOCALE_STRINGS_PATH)


func _should_collect_locale_keys_from_translations() -> bool:
	return not OS.has_feature("editor") and not FileAccess.file_exists(LOCALE_STRINGS_PATH)


func _has_locale_key(key: String, locale_keys: Dictionary) -> bool:
	if locale_keys.has(key):
		return true
	if not _should_collect_locale_keys_from_translations():
		return false
	return tr(key) != key


func _locale_key_source_label() -> String:
	if _should_collect_locale_keys_from_translations():
		return "key present in active translation resources"
	return "key present in strings.csv"


func _require_registered(resource_path: String, field: String, value: Variant, contract_key: String) -> String:
	if not value is String or String(value).is_empty():
		_schema_fail(resource_path, field, "non-empty string")
		return ""
	var id_value: String = String(value)
	if not has_contract_value(contract_key, id_value):
		_schema_fail(resource_path, field, "registered id in %s" % contract_key)
		return ""
	return id_value


func _require_audio_id(resource_path: String, field: String, value: Variant) -> bool:
	if not value is String or String(value).is_empty():
		return _schema_fail(resource_path, field, "non-empty audio id")
	var audio_id: String = String(value)
	if not _has_registered_prefix("audio_prefixes", audio_id):
		return _schema_fail(resource_path, field, "registered audio id prefix")
	return true


func _require_html_color(resource_path: String, field: String, value: Variant) -> bool:
	if not value is String or not Color.html_is_valid(String(value)):
		return _schema_fail(resource_path, field, "HTML color string")
	return true


func _require_locale_key(resource_path: String, field: String, value: Variant, locale_keys: Dictionary) -> bool:
	if not value is String or String(value).is_empty():
		return _schema_fail(resource_path, field, "non-empty locale key")
	var key: String = String(value)
	var is_valid: bool = true
	if not _has_registered_prefix("locale_prefixes", key):
		is_valid = _schema_fail(resource_path, field, "registered locale key prefix") and is_valid
	if not _has_locale_key(key, locale_keys):
		is_valid = _schema_fail(resource_path, field, _locale_key_source_label()) and is_valid
	return is_valid


func _require_array(resource_path: String, field: String, value: Variant) -> Array:
	if not value is Array:
		_schema_fail(resource_path, field, "Array")
		return []
	return value as Array


func _require_non_empty_string(resource_path: String, field: String, value: Variant) -> bool:
	if not value is String or String(value).is_empty():
		return _schema_fail(resource_path, field, "non-empty string")
	return true


func _require_bool(resource_path: String, field: String, value: Variant) -> bool:
	if not value is bool:
		return _schema_fail(resource_path, field, "bool")
	return true


func _require_int(resource_path: String, field: String, value: Variant, minimum: Variant = null, maximum: Variant = null) -> bool:
	if not _is_int_like(value):
		return _schema_fail(resource_path, field, "int")
	if minimum != null and _variant_to_int(value) < int(minimum):
		return _schema_fail(resource_path, field, "int >= %d" % int(minimum))
	if maximum != null and _variant_to_int(value) > int(maximum):
		return _schema_fail(resource_path, field, "int <= %d" % int(maximum))
	return true


func _require_number(resource_path: String, field: String, value: Variant, minimum: Variant = null, maximum: Variant = null, exclusive_minimum: bool = false) -> bool:
	if not value is int and not value is float:
		return _schema_fail(resource_path, field, "number")
	var numeric: float = float(value)
	if minimum != null:
		var min_value: float = float(minimum)
		if exclusive_minimum and numeric <= min_value:
			return _schema_fail(resource_path, field, "number > %s" % str(minimum))
		if not exclusive_minimum and numeric < min_value:
			return _schema_fail(resource_path, field, "number >= %s" % str(minimum))
	if maximum != null and numeric > float(maximum):
		return _schema_fail(resource_path, field, "number <= %s" % str(maximum))
	return true


func _is_nearly_grid_multiple(value: float, unit: float) -> bool:
	if unit <= 0.0:
		return true
	return _is_nearly_integer(value / unit)


func _is_nearly_integer(value: float) -> bool:
	return absf(value - round(value)) <= 0.001


func _is_int_like(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_equal_approx(float(value), float(int(value)))
	return false


func _variant_to_int(value: Variant) -> int:
	return int(value)


func _has_registered_prefix(contract_key: String, value: String) -> bool:
	for prefix: Variant in contract_values(contract_key):
		if value.begins_with(String(prefix)):
			return true
	return false


func _parse_int(value: Variant) -> Variant:
	var text: String = String(value)
	if not text.is_valid_int():
		return null
	return text.to_int()


func _parse_float(value: Variant) -> Variant:
	var text: String = String(value)
	if not text.is_valid_float():
		return null
	return text.to_float()


func _parse_tag_list(value: Variant) -> Array[String]:
	var tags: Array[String] = []
	for raw_tag: String in String(value).split("|", false):
		var tag: String = raw_tag.strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	return tags


func _is_empty_csv_row(values: PackedStringArray) -> bool:
	return values.size() == 0 or (values.size() == 1 and String(values[0]).strip_edges().is_empty())


func _schema_fail(resource_path: String, field_path: String, expected: String) -> bool:
	_fail(resource_path, field_path, expected)
	return false


func _fail(resource_path: String, field_path: String, expected: String) -> void:
	push_error("[DataLoader] %s:%s expected %s" % [resource_path, field_path, expected])
