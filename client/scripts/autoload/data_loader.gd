# Doc: docs/代码/data_loader.md
# Authority: docs/游戏设计文档.md §9.3, docs/词表与契约.md
class_name DataLoaderAutoload
extends Node


signal data_reloaded()

const CONTRACTS_PATH: String = "res://data/_contracts.json"
const DATA_ROOT: String = "res://data/"
const LOCALE_STRINGS_PATH: String = "res://locale/strings.csv"
const PLAYER_DATA_PATH: String = "res://data/player.json"
const CHARACTERS_PATH: String = "res://data/characters.json"
const WEAPONS_PATH: String = "res://data/weapons.json"
const ENEMIES_PATH: String = "res://data/enemies.csv"
const HAZARDS_PATH: String = "res://data/hazards.csv"
const SPAWN_WAVES_PATH: String = "res://data/spawn_waves.csv"
const RELICS_PATH: String = "res://data/relics.json"
const ACTIVE_ITEMS_PATH: String = "res://data/active_items.json"
const CONSUMABLES_PATH: String = "res://data/consumables.json"
const CREDITS_PATH: String = "res://data/credits.json"
const META_PROGRESSION_PATH: String = "res://data/meta_progression.json"
const GROWTH_CURVE_PATH: String = "res://data/growth.csv"
const GROWTH_POOLS_PATH: String = "res://data/growth_pools.json"
const GAME_MODES_PATH: String = "res://data/game_modes.json"

const INT_STATS: Array[String] = ["max_hp", "bullet_count", "pierce_count"]
const NON_NEGATIVE_STATS: Array[String] = ["damage", "pickup_range", "luck", "armor", "lifesteal_ratio"]
const POSITIVE_STATS: Array[String] = ["move_speed", "fire_rate", "bullet_speed", "bullet_range", "crit_mult"]
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
	return _contracts.duplicate(true)


func contract_values(contract_id: String) -> Array:
	if not _contracts.has(contract_id):
		_fail(CONTRACTS_PATH, "contracts.%s" % contract_id, "registered contract id")
		return []

	var values: Variant = _contracts[contract_id]
	if not values is Array:
		_fail(CONTRACTS_PATH, "contracts.%s" % contract_id, "Array")
		return []

	return values as Array


func has_contract_value(contract_id: String, value: String) -> bool:
	return contract_values(contract_id).has(value)


func validate_project_data() -> bool:
	var locale_keys: Dictionary = _collect_locale_keys()
	var is_valid: bool = true
	_last_schema_counts.clear()

	is_valid = _validate_locale_strings(locale_keys) and is_valid
	is_valid = _validate_player_json() and is_valid
	is_valid = _validate_weapons_json(locale_keys) and is_valid
	var weapon_ids: Dictionary = _collect_weapon_ids()
	is_valid = _validate_enemies_csv(locale_keys) and is_valid
	var enemy_ids: Dictionary = _collect_enemy_ids()
	is_valid = _validate_hazards_csv(locale_keys) and is_valid
	var hazard_ids: Dictionary = _collect_hazard_ids()
	is_valid = _validate_relics_json(locale_keys) and is_valid
	var relic_ids: Dictionary = _collect_relic_ids()
	is_valid = _validate_active_items_json(locale_keys) and is_valid
	var active_item_ids: Dictionary = _collect_active_item_ids()
	is_valid = _validate_consumables_json(locale_keys) and is_valid
	var consumable_ids: Dictionary = _collect_consumable_ids()
	is_valid = _validate_credits_json(locale_keys) and is_valid
	is_valid = _validate_characters_json(locale_keys, weapon_ids) and is_valid
	var character_ids: Dictionary = _collect_character_ids()
	is_valid = _validate_meta_progression(locale_keys, character_ids) and is_valid
	is_valid = _validate_growth_csv() and is_valid
	is_valid = _validate_growth_pools() and is_valid
	is_valid = _validate_game_modes(locale_keys, character_ids, weapon_ids, enemy_ids, hazard_ids, relic_ids, active_item_ids, consumable_ids) and is_valid
	var game_mode_ids: Dictionary = _collect_game_mode_ids()
	is_valid = _validate_spawn_waves_csv(enemy_ids, hazard_ids, game_mode_ids) and is_valid

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

	return parsed


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

	return rows


func data_path(file_name: String) -> String:
	return DATA_ROOT.path_join(file_name)


func _validate_locale_strings(_locale_keys: Dictionary) -> bool:
	var rows: Array[Dictionary] = load_csv(LOCALE_STRINGS_PATH)
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


func _validate_characters_json(locale_keys: Dictionary, weapon_ids: Dictionary) -> bool:
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
		var starting_weapon_id: String = String(character_dict.get("starting_weapon_id", ""))
		is_valid = _require_non_empty_string(CHARACTERS_PATH, "%s.starting_weapon_id" % field, character_dict.get("starting_weapon_id")) and is_valid
		if not starting_weapon_id.is_empty() and not weapon_ids.has(starting_weapon_id):
			is_valid = _schema_fail(CHARACTERS_PATH, "%s.starting_weapon_id" % field, "weapon defined in weapons.json") and is_valid
		var base_stats: Variant = character_dict.get("base_stats")
		if not base_stats is Dictionary or (base_stats as Dictionary).is_empty():
			is_valid = _schema_fail(CHARACTERS_PATH, "%s.base_stats" % field, "non-empty Dictionary") and is_valid
		else:
			var stats_dict: Dictionary = base_stats as Dictionary
			for stat_key: Variant in stats_dict.keys():
				var stat: String = String(stat_key)
				is_valid = _validate_stat_value(CHARACTERS_PATH, "%s.base_stats.%s" % [field, stat], stat, stats_dict[stat_key]) and is_valid
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


func _validate_enemies_csv(locale_keys: Dictionary) -> bool:
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
		is_valid = _require_csv_int(ENEMIES_PATH, "%s.max_hp" % field, row.get("max_hp"), 1) and is_valid
		is_valid = _require_csv_number(ENEMIES_PATH, "%s.move_speed" % field, row.get("move_speed"), 0.0, null, true) and is_valid
		is_valid = _require_csv_int(ENEMIES_PATH, "%s.contact_damage" % field, row.get("contact_damage"), 0) and is_valid
		is_valid = _require_registered(ENEMIES_PATH, "%s.contact_damage_type" % field, row.get("contact_damage_type"), "damage_types") != "" and is_valid
		is_valid = _require_csv_int(ENEMIES_PATH, "%s.exp_reward" % field, row.get("exp_reward"), 0) and is_valid
		is_valid = _require_csv_number(ENEMIES_PATH, "%s.hit_radius" % field, row.get("hit_radius"), 0.0, null, true) and is_valid
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
		is_valid = _require_csv_number(HAZARDS_PATH, "%s.radius" % field, row.get("radius"), 0.0, null, true) and is_valid
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


func _validate_meta_progression(locale_keys: Dictionary, character_ids: Dictionary) -> bool:
	var data: Variant = load_json(META_PROGRESSION_PATH)
	if not data is Dictionary:
		return _schema_fail(META_PROGRESSION_PATH, "root", "Dictionary")

	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(META_PROGRESSION_PATH, "schema_version", payload.get("schema_version"), 1) and is_valid

	var currencies: Array = _require_array(META_PROGRESSION_PATH, "currencies", payload.get("currencies"))
	var currency_ids: Dictionary = {}
	_last_schema_counts["meta_currencies"] = currencies.size()
	for index: int in range(currencies.size()):
		var field: String = "currencies[%d]" % index
		var currency: Variant = currencies[index]
		if not currency is Dictionary:
			is_valid = _schema_fail(META_PROGRESSION_PATH, field, "Dictionary") and is_valid
			continue
		var currency_dict: Dictionary = currency as Dictionary
		var currency_id: String = _require_registered(META_PROGRESSION_PATH, "%s.id" % field, currency_dict.get("id"), "meta_currencies")
		if not currency_id.is_empty():
			if currency_ids.has(currency_id):
				is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.id" % field, "unique currency id") and is_valid
			currency_ids[currency_id] = true
		is_valid = _require_locale_key(META_PROGRESSION_PATH, "%s.name_key" % field, currency_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_int(META_PROGRESSION_PATH, "%s.default_amount" % field, currency_dict.get("default_amount"), 0) and is_valid
		is_valid = _require_int(META_PROGRESSION_PATH, "%s.max_amount" % field, currency_dict.get("max_amount"), 1) and is_valid
		if _is_int_like(currency_dict.get("default_amount")) and _is_int_like(currency_dict.get("max_amount")) and _variant_to_int(currency_dict.get("max_amount")) <= _variant_to_int(currency_dict.get("default_amount")):
			is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.max_amount" % field, "greater than default_amount") and is_valid

	is_valid = _validate_run_rewards(payload.get("run_rewards"), currency_ids) and is_valid
	var unlock_ids: Dictionary = _collect_defined_unlock_ids(payload.get("unlocks"))
	is_valid = _validate_account_level(payload.get("account_level"), unlock_ids) and is_valid
	is_valid = _validate_upgrade_tracks(payload.get("upgrade_tracks"), currency_ids, unlock_ids, locale_keys) and is_valid
	is_valid = _validate_unlocks(payload.get("unlocks"), locale_keys, character_ids) and is_valid
	return is_valid


func _validate_run_rewards(data: Variant, currency_ids: Dictionary) -> bool:
	if not data is Dictionary:
		return _schema_fail(META_PROGRESSION_PATH, "run_rewards", "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	var currency_id: String = _require_registered(META_PROGRESSION_PATH, "run_rewards.currency_id", payload.get("currency_id"), "meta_currencies")
	if not currency_id.is_empty() and not currency_ids.has(currency_id):
		is_valid = _schema_fail(META_PROGRESSION_PATH, "run_rewards.currency_id", "currency defined in currencies") and is_valid
	for field: String in ["base_amount", "per_minute_survived", "per_50_kills", "first_boss_bonus"]:
		is_valid = _require_int(META_PROGRESSION_PATH, "run_rewards.%s" % field, payload.get(field), 0) and is_valid
	is_valid = _require_int(META_PROGRESSION_PATH, "run_rewards.max_amount_per_run", payload.get("max_amount_per_run"), 1) and is_valid
	return is_valid


func _validate_account_level(data: Variant, unlock_ids: Dictionary) -> bool:
	if not data is Dictionary:
		return _schema_fail(META_PROGRESSION_PATH, "account_level", "Dictionary")
	var payload: Dictionary = data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(META_PROGRESSION_PATH, "account_level.xp_per_minute_survived", payload.get("xp_per_minute_survived"), 0) and is_valid
	is_valid = _require_int(META_PROGRESSION_PATH, "account_level.xp_per_50_kills", payload.get("xp_per_50_kills"), 0) and is_valid
	var thresholds: Array = _require_array(META_PROGRESSION_PATH, "account_level.thresholds", payload.get("thresholds"))
	var previous: int = -1
	for index: int in range(thresholds.size()):
		var value: Variant = thresholds[index]
		is_valid = _require_int(META_PROGRESSION_PATH, "account_level.thresholds[%d]" % index, value, 0) and is_valid
		if _is_int_like(value):
			if _variant_to_int(value) <= previous:
				is_valid = _schema_fail(META_PROGRESSION_PATH, "account_level.thresholds[%d]" % index, "strictly increasing int") and is_valid
			previous = _variant_to_int(value)
	var rewards: Array = _require_array(META_PROGRESSION_PATH, "account_level.level_rewards", payload.get("level_rewards"))
	for index: int in range(rewards.size()):
		var field: String = "account_level.level_rewards[%d]" % index
		var reward: Variant = rewards[index]
		if not reward is Dictionary:
			is_valid = _schema_fail(META_PROGRESSION_PATH, field, "Dictionary") and is_valid
			continue
		var reward_dict: Dictionary = reward as Dictionary
		is_valid = _require_int(META_PROGRESSION_PATH, "%s.level" % field, reward_dict.get("level"), 1) and is_valid
		is_valid = _validate_unlock_id_list("%s.unlock_ids" % field, reward_dict.get("unlock_ids"), unlock_ids) and is_valid
	return is_valid


func _validate_upgrade_tracks(data: Variant, currency_ids: Dictionary, unlock_ids: Dictionary, locale_keys: Dictionary) -> bool:
	var tracks: Array = _require_array(META_PROGRESSION_PATH, "upgrade_tracks", data)
	var is_valid: bool = true
	var seen: Dictionary = {}
	_last_schema_counts["meta_upgrade_tracks"] = tracks.size()
	for index: int in range(tracks.size()):
		var field: String = "upgrade_tracks[%d]" % index
		var track: Variant = tracks[index]
		if not track is Dictionary:
			is_valid = _schema_fail(META_PROGRESSION_PATH, field, "Dictionary") and is_valid
			continue
		var track_dict: Dictionary = track as Dictionary
		var track_id: String = _require_registered(META_PROGRESSION_PATH, "%s.id" % field, track_dict.get("id"), "meta_upgrades")
		if not track_id.is_empty():
			if seen.has(track_id):
				is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.id" % field, "unique upgrade id") and is_valid
			seen[track_id] = true
		is_valid = _require_locale_key(META_PROGRESSION_PATH, "%s.name_key" % field, track_dict.get("name_key"), locale_keys) and is_valid
		is_valid = _require_locale_key(META_PROGRESSION_PATH, "%s.desc_key" % field, track_dict.get("desc_key"), locale_keys) and is_valid
		var currency_id: String = _require_registered(META_PROGRESSION_PATH, "%s.currency_id" % field, track_dict.get("currency_id"), "meta_currencies")
		if not currency_id.is_empty() and not currency_ids.has(currency_id):
			is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.currency_id" % field, "currency defined in currencies") and is_valid
		var max_level: Variant = track_dict.get("max_level")
		is_valid = _require_int(META_PROGRESSION_PATH, "%s.max_level" % field, max_level, 1) and is_valid
		var costs: Array = _require_array(META_PROGRESSION_PATH, "%s.costs" % field, track_dict.get("costs"))
		if _is_int_like(max_level) and costs.size() != _variant_to_int(max_level):
			is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.costs" % field, "length equals max_level") and is_valid
		for cost_index: int in range(costs.size()):
			is_valid = _require_int(META_PROGRESSION_PATH, "%s.costs[%d]" % [field, cost_index], costs[cost_index], 0) and is_valid
		is_valid = _validate_modifiers(META_PROGRESSION_PATH, "%s.modifiers" % field, track_dict.get("modifiers", []), true) and is_valid
		if track_dict.has("unlock_ids_by_level"):
			var by_level: Array = _require_array(META_PROGRESSION_PATH, "%s.unlock_ids_by_level" % field, track_dict.get("unlock_ids_by_level"))
			if _is_int_like(max_level) and by_level.size() != _variant_to_int(max_level):
				is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.unlock_ids_by_level" % field, "length equals max_level") and is_valid
			for level_index: int in range(by_level.size()):
				is_valid = _validate_unlock_id_list("%s.unlock_ids_by_level[%d]" % [field, level_index], by_level[level_index], unlock_ids) and is_valid
	return is_valid


func _validate_unlocks(data: Variant, locale_keys: Dictionary, character_ids: Dictionary) -> bool:
	var unlocks: Array = _require_array(META_PROGRESSION_PATH, "unlocks", data)
	var is_valid: bool = true
	var seen: Dictionary = {}
	_last_schema_counts["meta_unlocks"] = unlocks.size()
	for index: int in range(unlocks.size()):
		var field: String = "unlocks[%d]" % index
		var unlock: Variant = unlocks[index]
		if not unlock is Dictionary:
			is_valid = _schema_fail(META_PROGRESSION_PATH, field, "Dictionary") and is_valid
			continue
		var unlock_dict: Dictionary = unlock as Dictionary
		var unlock_id: String = _require_registered(META_PROGRESSION_PATH, "%s.id" % field, unlock_dict.get("id"), "meta_unlocks")
		if not unlock_id.is_empty():
			if seen.has(unlock_id):
				is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.id" % field, "unique unlock id") and is_valid
			seen[unlock_id] = true
		is_valid = _require_registered(META_PROGRESSION_PATH, "%s.kind" % field, unlock_dict.get("kind"), "meta_unlock_kinds") != "" and is_valid
		if unlock_dict.has("target_id"):
			var target_id: String = String(unlock_dict.get("target_id", ""))
			if target_id.is_empty():
				is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.target_id" % field, "non-empty string") and is_valid
			elif unlock_dict.get("kind") == "character" and not character_ids.has(target_id):
				is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.target_id" % field, "character defined in characters.json") and is_valid
		if unlock_dict.has("name_key"):
			is_valid = _require_locale_key(META_PROGRESSION_PATH, "%s.name_key" % field, unlock_dict.get("name_key"), locale_keys) and is_valid
		if not unlock_dict.get("default_unlocked") is bool:
			is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.default_unlocked" % field, "bool") and is_valid
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


func _validate_growth_pools() -> bool:
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


func _validate_game_modes(locale_keys: Dictionary, character_ids: Dictionary, weapon_ids: Dictionary, enemy_ids: Dictionary, hazard_ids: Dictionary, relic_ids: Dictionary, active_item_ids: Dictionary, consumable_ids: Dictionary) -> bool:
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
		is_valid = _validate_mode_resource_pools(mode_field, mode_dict.get("resource_pools"), growth_pool_ids, character_ids, weapon_ids, enemy_ids, hazard_ids, relic_ids, active_item_ids, consumable_ids) and is_valid
		if mode_dict.has("blocklists"):
			is_valid = _validate_mode_blocklists("%s.blocklists" % mode_field, mode_dict.get("blocklists")) and is_valid
		if mode_dict.has("overrides"):
			is_valid = _validate_mode_overrides("%s.overrides" % mode_field, mode_dict.get("overrides")) and is_valid
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


func _validate_mode_resource_pools(mode_field: String, data: Variant, growth_pool_ids: Dictionary, character_ids: Dictionary, weapon_ids: Dictionary, enemy_ids: Dictionary, hazard_ids: Dictionary, relic_ids: Dictionary, active_item_ids: Dictionary, consumable_ids: Dictionary) -> bool:
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
	if payload.has("consumables"):
		is_valid = _validate_weighted_consumable_entries("%s.resource_pools.consumables" % mode_field, payload.get("consumables"), consumable_ids) and is_valid
	if payload.has("growth_pools"):
		is_valid = _validate_weighted_growth_pool_entries("%s.resource_pools.growth_pools" % mode_field, payload.get("growth_pools"), growth_pool_ids) and is_valid
	if not payload.has("characters") and not payload.has("weapons") and not payload.has("enemies") and not payload.has("hazards") and not payload.has("relics") and not payload.has("active_items") and not payload.has("consumables") and not payload.has("growth_pools"):
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


func _validate_unlock_id_list(field: String, data: Variant, defined_unlock_ids: Dictionary) -> bool:
	var ids: Array = _require_array(META_PROGRESSION_PATH, field, data)
	var is_valid: bool = true
	for index: int in range(ids.size()):
		var unlock_id: String = _require_registered(META_PROGRESSION_PATH, "%s[%d]" % [field, index], ids[index], "meta_unlocks")
		if not unlock_id.is_empty() and not defined_unlock_ids.has(unlock_id):
			is_valid = _schema_fail(META_PROGRESSION_PATH, "%s[%d]" % [field, index], "unlock defined in unlocks") and is_valid
	return is_valid


func _collect_defined_unlock_ids(data: Variant) -> Dictionary:
	var ids: Dictionary = {}
	if not data is Array:
		return ids
	for item: Variant in data:
		if item is Dictionary and (item as Dictionary).get("id") is String:
			ids[String((item as Dictionary).get("id"))] = true
	return ids


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


func _collect_hazard_ids() -> Dictionary:
	var ids: Dictionary = {}
	var rows: Array[Dictionary] = load_csv(HAZARDS_PATH)
	for row: Dictionary in rows:
		var hazard_id: String = String(row.get("id", ""))
		if not hazard_id.is_empty():
			ids[hazard_id] = true
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


func _collect_locale_keys() -> Dictionary:
	var rows: Array[Dictionary] = load_csv(LOCALE_STRINGS_PATH)
	var keys: Dictionary = {}
	for row: Dictionary in rows:
		var key: String = String(row.get("keys", ""))
		if key.is_empty() or keys.has(key):
			continue
		keys[key] = true
	return keys


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


func _require_locale_key(resource_path: String, field: String, value: Variant, locale_keys: Dictionary) -> bool:
	if not value is String or String(value).is_empty():
		return _schema_fail(resource_path, field, "non-empty locale key")
	var key: String = String(value)
	var is_valid: bool = true
	if not _has_registered_prefix("locale_prefixes", key):
		is_valid = _schema_fail(resource_path, field, "registered locale key prefix") and is_valid
	if not locale_keys.has(key):
		is_valid = _schema_fail(resource_path, field, "key present in strings.csv") and is_valid
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


func _require_int(resource_path: String, field: String, value: Variant, minimum: Variant = null) -> bool:
	if not _is_int_like(value):
		return _schema_fail(resource_path, field, "int")
	if minimum != null and _variant_to_int(value) < int(minimum):
		return _schema_fail(resource_path, field, "int >= %d" % int(minimum))
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
