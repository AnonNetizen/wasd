# Doc: docs/代码/data_loader.md
# Authority: docs/游戏设计文档.md §9.3, docs/词表与契约.md
extends Node
class_name DataLoaderAutoload


signal data_reloaded()

const CONTRACTS_PATH: String = "res://data/_contracts.json"
const DATA_ROOT: String = "res://data/"
const LOCALE_STRINGS_PATH: String = "res://locale/strings.csv"
const PLAYER_DATA_PATH: String = "res://data/player.json"
const META_PROGRESSION_PATH: String = "res://data/meta_progression.json"
const GROWTH_CURVE_PATH: String = "res://data/growth.csv"
const GROWTH_POOLS_PATH: String = "res://data/growth_pools.json"

const INT_STATS: Array[String] = ["max_hp", "bullet_count", "pierce_count"]
const NON_NEGATIVE_STATS: Array[String] = ["damage", "pickup_range", "luck", "armor", "lifesteal_ratio"]
const POSITIVE_STATS: Array[String] = ["move_speed", "fire_rate", "bullet_speed", "bullet_range", "crit_mult"]
const RATIO_STATS: Array[String] = ["crit_chance", "resist_fire", "resist_poison", "resist_lightning", "lifesteal_ratio"]

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
	is_valid = _validate_meta_progression(locale_keys) and is_valid
	is_valid = _validate_growth_csv() and is_valid
	is_valid = _validate_growth_pools() and is_valid

	return is_valid


func schema_counts() -> Dictionary:
	return _last_schema_counts.duplicate(true)


func load_json(resource_path: String) -> Variant:
	var file := FileAccess.open(resource_path, FileAccess.READ)
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
	var file := FileAccess.open(resource_path, FileAccess.READ)
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


func _validate_meta_progression(locale_keys: Dictionary) -> bool:
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
	is_valid = _validate_unlocks(payload.get("unlocks"), locale_keys) and is_valid
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


func _validate_unlocks(data: Variant, locale_keys: Dictionary) -> bool:
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
			elif unlock_dict.get("kind") == "character" and not has_contract_value("character_ids", target_id):
				is_valid = _schema_fail(META_PROGRESSION_PATH, "%s.target_id" % field, "registered character id") and is_valid
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


func _is_empty_csv_row(values: PackedStringArray) -> bool:
	return values.size() == 0 or (values.size() == 1 and String(values[0]).strip_edges().is_empty())


func _schema_fail(resource_path: String, field_path: String, expected: String) -> bool:
	_fail(resource_path, field_path, expected)
	return false


func _fail(resource_path: String, field_path: String, expected: String) -> void:
	push_error("[DataLoader] %s:%s expected %s" % [resource_path, field_path, expected])
