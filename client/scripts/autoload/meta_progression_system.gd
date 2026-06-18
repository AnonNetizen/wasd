# Doc: docs/代码/meta_progression_system.md
# Authority: docs/游戏设计文档.md §7.2 / §9.16, docs/AI协作/工作包/F6-MetaProgression.md
class_name MetaProgressionSystemAutoload
extends Node


const META_CURRENCIES := preload("res://scripts/contracts/meta_currencies.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const PROFILE_SCHEMA_VERSION: int = 1
const SUMMARY_KILLS: String = "kills"
const SUMMARY_RUN_TIME: String = "run_time"
const SUMMARY_FIRST_BOSS_DEFEATED: String = "first_boss_defeated"


func load_or_create_profile(slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var stored_profile: Dictionary = {}
	if SaveManager.has_save(slot, SAVE_KINDS.META):
		stored_profile = SaveManager.load(slot, SAVE_KINDS.META)
	var profile: Dictionary = _normalize_profile(stored_profile)
	if stored_profile.is_empty() or profile != stored_profile:
		if not SaveManager.save(slot, SAVE_KINDS.META, profile):
			push_error("[MetaProgressionSystem] failed to save meta profile: %s" % SaveManager.last_error())
	return profile


func save_profile(profile: Dictionary, slot: String = SaveManager.DEFAULT_SLOT) -> bool:
	var normalized_profile: Dictionary = _normalize_profile(profile)
	if not SaveManager.save(slot, SAVE_KINDS.META, normalized_profile):
		push_error("[MetaProgressionSystem] failed to save meta profile: %s" % SaveManager.last_error())
		return false
	return true


func apply_run_settlement(summary: Dictionary, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var previous_unlocks: Array[String] = _string_array(profile.get("unlocked_ids", []))
	var rewards: Dictionary = _calculate_run_rewards(summary)
	var currency_id: String = String(rewards.get("currency_id", META_CURRENCIES.META_ESSENCE))
	var currency_amount: int = int(rewards.get("currency_amount", 0))
	var account_xp: int = int(rewards.get("account_xp", 0))

	var currencies: Dictionary = _dictionary_or_empty(profile.get("currencies", {}))
	currencies[currency_id] = _clamped_currency_amount(currency_id, int(currencies.get(currency_id, 0)) + currency_amount)
	profile["currencies"] = currencies
	profile["account_xp"] = maxi(int(profile.get("account_xp", 0)) + account_xp, 0)
	profile["account_level"] = _account_level_for_xp(int(profile.get("account_xp", 0)))
	profile["unlocked_ids"] = _unlock_ids_after_level_rewards(profile)
	profile["stats"] = _stats_after_settlement(profile, summary, currency_amount)

	var saved: bool = save_profile(profile, slot)
	var current_unlocks: Array[String] = _string_array(profile.get("unlocked_ids", []))
	return {
		"ok": saved,
		"currency_id": currency_id,
		"currency_name_key": _currency_name_key(currency_id),
		"currency_amount": currency_amount,
		"account_xp": account_xp,
		"account_level": int(profile.get("account_level", 1)),
		"new_unlock_ids": _new_unlock_ids(previous_unlocks, current_unlocks),
		"profile": profile.duplicate(true),
	}


func purchase_upgrade(upgrade_id: String, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var track: Dictionary = _upgrade_track(upgrade_id)
	if track.is_empty():
		return _purchase_result(false, "unknown_upgrade", upgrade_id, profile)
	if not _is_track_unlocked(track, profile):
		return _purchase_result(false, "locked", upgrade_id, profile)

	var purchased_upgrades: Dictionary = _dictionary_or_empty(profile.get("purchased_upgrades", {}))
	var current_level: int = int(purchased_upgrades.get(upgrade_id, 0))
	var max_level: int = int(track.get("max_level", 0))
	if current_level >= max_level:
		return _purchase_result(false, "max_level", upgrade_id, profile)

	var costs: Array = _array_or_empty(track.get("costs", []))
	if current_level >= costs.size():
		return _purchase_result(false, "missing_cost", upgrade_id, profile)
	var cost: int = int(costs[current_level])
	var currency_id: String = String(track.get("currency_id", META_CURRENCIES.META_ESSENCE))
	var currencies: Dictionary = _dictionary_or_empty(profile.get("currencies", {}))
	var balance: int = int(currencies.get(currency_id, 0))
	if balance < cost:
		return _purchase_result(false, "insufficient_currency", upgrade_id, profile, cost)

	currencies[currency_id] = balance - cost
	purchased_upgrades[upgrade_id] = current_level + 1
	profile["currencies"] = currencies
	profile["purchased_upgrades"] = purchased_upgrades
	profile["unlocked_ids"] = _unlock_ids_after_upgrade_purchase(profile, track, current_level + 1)
	var saved: bool = save_profile(profile, slot)
	return {
		"ok": saved,
		"reason": "" if saved else "save_failed",
		"upgrade_id": upgrade_id,
		"level": current_level + 1,
		"cost": cost,
		"currency_id": currency_id,
		"profile": profile.duplicate(true),
	}


func current_modifiers(slot: String = SaveManager.DEFAULT_SLOT) -> Array[Dictionary]:
	var profile: Dictionary = load_or_create_profile(slot)
	var purchased_upgrades: Dictionary = _dictionary_or_empty(profile.get("purchased_upgrades", {}))
	var result: Array[Dictionary] = []
	for track: Dictionary in _upgrade_tracks():
		var upgrade_id: String = String(track.get("id", ""))
		var level: int = int(purchased_upgrades.get(upgrade_id, 0))
		if level <= 0:
			continue
		for raw_modifier: Variant in _array_or_empty(track.get("modifiers", [])):
			if not raw_modifier is Dictionary:
				continue
			var modifier: Dictionary = raw_modifier as Dictionary
			var value_per_level: float = float(modifier.get("value_per_level", 0.0))
			result.append({
				"stat": String(modifier.get("stat", "")),
				"type": String(modifier.get("type", "add")),
				"value": value_per_level * float(level),
			})
	return result


func profile_summary(slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var primary_currency_id: String = _primary_currency_id()
	var currencies: Dictionary = _dictionary_or_empty(profile.get("currencies", {}))
	return {
		"account_level": int(profile.get("account_level", 1)),
		"account_xp": int(profile.get("account_xp", 0)),
		"currency_id": primary_currency_id,
		"currency_name_key": _currency_name_key(primary_currency_id),
		"currency_amount": int(currencies.get(primary_currency_id, 0)),
	}


func upgrade_summaries(slot: String = SaveManager.DEFAULT_SLOT) -> Array[Dictionary]:
	var profile: Dictionary = load_or_create_profile(slot)
	var result: Array[Dictionary] = []
	for track: Dictionary in _upgrade_tracks():
		result.append(_upgrade_summary(track, profile))
	return result


func first_available_purchase(slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var currencies: Dictionary = _dictionary_or_empty(profile.get("currencies", {}))
	var purchased_upgrades: Dictionary = _dictionary_or_empty(profile.get("purchased_upgrades", {}))
	for track: Dictionary in _upgrade_tracks():
		if not _is_track_unlocked(track, profile):
			continue
		var upgrade_id: String = String(track.get("id", ""))
		var current_level: int = int(purchased_upgrades.get(upgrade_id, 0))
		if current_level >= int(track.get("max_level", 0)):
			continue
		var costs: Array = _array_or_empty(track.get("costs", []))
		if current_level >= costs.size():
			continue
		var currency_id: String = String(track.get("currency_id", META_CURRENCIES.META_ESSENCE))
		var cost: int = int(costs[current_level])
		if int(currencies.get(currency_id, 0)) < cost:
			continue
		return {
			"upgrade_id": upgrade_id,
			"name_key": String(track.get("name_key", "")),
			"currency_id": currency_id,
			"cost": cost,
			"current_level": current_level,
			"max_level": int(track.get("max_level", 0)),
		}
	return {}


func currency_name_key(currency_id: String) -> String:
	return _currency_name_key(currency_id)


func _normalize_profile(raw_profile: Dictionary) -> Dictionary:
	var defaults: Dictionary = _default_profile()
	var profile: Dictionary = raw_profile.duplicate(true)
	profile["schema_version"] = PROFILE_SCHEMA_VERSION

	var currencies: Dictionary = _dictionary_or_empty(defaults.get("currencies", {}))
	var raw_currencies: Dictionary = _dictionary_or_empty(profile.get("currencies", {}))
	for currency_id: String in currencies.keys():
		currencies[currency_id] = _clamped_currency_amount(currency_id, int(raw_currencies.get(currency_id, currencies[currency_id])))
	profile["currencies"] = currencies

	profile["account_xp"] = maxi(int(profile.get("account_xp", defaults.get("account_xp", 0))), 0)
	profile["account_level"] = _account_level_for_xp(int(profile.get("account_xp", 0)))
	profile["purchased_upgrades"] = _dictionary_or_empty(profile.get("purchased_upgrades", {}))

	var unlocked_ids: Array[String] = _string_array(profile.get("unlocked_ids", []))
	for default_unlock_id: String in _string_array(defaults.get("unlocked_ids", [])):
		if not unlocked_ids.has(default_unlock_id):
			unlocked_ids.append(default_unlock_id)
	unlocked_ids.sort()
	profile["unlocked_ids"] = unlocked_ids

	var stats: Dictionary = _dictionary_or_empty(defaults.get("stats", {}))
	stats.merge(_dictionary_or_empty(profile.get("stats", {})), true)
	profile["stats"] = stats
	return profile


func _default_profile() -> Dictionary:
	var currencies: Dictionary = {}
	for currency: Dictionary in _currencies():
		var currency_id: String = String(currency.get("id", ""))
		if not currency_id.is_empty():
			currencies[currency_id] = int(currency.get("default_amount", 0))

	var unlocked_ids: Array[String] = []
	for unlock: Dictionary in _unlocks():
		if bool(unlock.get("default_unlocked", false)):
			unlocked_ids.append(String(unlock.get("id", "")))
	unlocked_ids.sort()

	return {
		"schema_version": PROFILE_SCHEMA_VERSION,
		"currencies": currencies,
		"account_xp": 0,
		"account_level": 1,
		"purchased_upgrades": {},
		"unlocked_ids": unlocked_ids,
		"stats": {
			"runs_settled": 0,
			"total_kills": 0,
			"total_run_time": 0.0,
			"total_currency_earned": 0,
		},
	}


func _calculate_run_rewards(summary: Dictionary) -> Dictionary:
	var config: Dictionary = _meta_config()
	var run_rewards: Dictionary = _dictionary_or_empty(config.get("run_rewards", {}))
	var account_level: Dictionary = _dictionary_or_empty(config.get("account_level", {}))
	var minutes_survived: int = int(floorf(maxf(float(summary.get(SUMMARY_RUN_TIME, 0.0)), 0.0) / 60.0))
	var kill_blocks: int = floori(float(maxi(int(summary.get(SUMMARY_KILLS, 0)), 0)) / 50.0)

	var currency_amount: int = int(run_rewards.get("base_amount", 0))
	currency_amount += minutes_survived * int(run_rewards.get("per_minute_survived", 0))
	currency_amount += kill_blocks * int(run_rewards.get("per_50_kills", 0))
	if bool(summary.get(SUMMARY_FIRST_BOSS_DEFEATED, false)):
		currency_amount += int(run_rewards.get("first_boss_bonus", 0))
	var max_amount: int = int(run_rewards.get("max_amount_per_run", currency_amount))
	currency_amount = clampi(currency_amount, 0, max_amount)

	var account_xp: int = minutes_survived * int(account_level.get("xp_per_minute_survived", 0))
	account_xp += kill_blocks * int(account_level.get("xp_per_50_kills", 0))
	return {
		"currency_id": String(run_rewards.get("currency_id", META_CURRENCIES.META_ESSENCE)),
		"currency_amount": currency_amount,
		"account_xp": account_xp,
	}


func _stats_after_settlement(profile: Dictionary, summary: Dictionary, currency_amount: int) -> Dictionary:
	var stats: Dictionary = _dictionary_or_empty(profile.get("stats", {}))
	stats["runs_settled"] = int(stats.get("runs_settled", 0)) + 1
	stats["total_kills"] = int(stats.get("total_kills", 0)) + maxi(int(summary.get(SUMMARY_KILLS, 0)), 0)
	stats["total_run_time"] = float(stats.get("total_run_time", 0.0)) + maxf(float(summary.get(SUMMARY_RUN_TIME, 0.0)), 0.0)
	stats["total_currency_earned"] = int(stats.get("total_currency_earned", 0)) + currency_amount
	return stats


func _unlock_ids_after_level_rewards(profile: Dictionary) -> Array[String]:
	var unlocked_ids: Array[String] = _string_array(profile.get("unlocked_ids", []))
	var level: int = int(profile.get("account_level", 1))
	var account_level: Dictionary = _dictionary_or_empty(_meta_config().get("account_level", {}))
	for raw_reward: Variant in _array_or_empty(account_level.get("level_rewards", [])):
		if not raw_reward is Dictionary:
			continue
		var reward: Dictionary = raw_reward as Dictionary
		if int(reward.get("level", 0)) > level:
			continue
		for unlock_id: String in _string_array(reward.get("unlock_ids", [])):
			if not unlocked_ids.has(unlock_id):
				unlocked_ids.append(unlock_id)
	unlocked_ids.sort()
	return unlocked_ids


func _unlock_ids_after_upgrade_purchase(profile: Dictionary, track: Dictionary, purchased_level: int) -> Array[String]:
	var unlocked_ids: Array[String] = _string_array(profile.get("unlocked_ids", []))
	var unlocks_by_level: Array = _array_or_empty(track.get("unlock_ids_by_level", []))
	var index: int = purchased_level - 1
	if index >= 0 and index < unlocks_by_level.size():
		for unlock_id: String in _string_array(unlocks_by_level[index]):
			if not unlocked_ids.has(unlock_id):
				unlocked_ids.append(unlock_id)
	unlocked_ids.sort()
	return unlocked_ids


func _new_unlock_ids(previous_unlocks: Array[String], current_unlocks: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for unlock_id: String in current_unlocks:
		if not previous_unlocks.has(unlock_id):
			result.append(unlock_id)
	return result


func _purchase_result(ok: bool, reason: String, upgrade_id: String, profile: Dictionary, cost: int = 0) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"upgrade_id": upgrade_id,
		"cost": cost,
		"profile": profile.duplicate(true),
	}


func _upgrade_summary(track: Dictionary, profile: Dictionary) -> Dictionary:
	var upgrade_id: String = String(track.get("id", ""))
	var purchased_upgrades: Dictionary = _dictionary_or_empty(profile.get("purchased_upgrades", {}))
	var currencies: Dictionary = _dictionary_or_empty(profile.get("currencies", {}))
	var current_level: int = int(purchased_upgrades.get(upgrade_id, 0))
	var max_level: int = int(track.get("max_level", 0))
	var currency_id: String = String(track.get("currency_id", META_CURRENCIES.META_ESSENCE))
	var balance: int = int(currencies.get(currency_id, 0))
	var costs: Array = _array_or_empty(track.get("costs", []))
	var cost: int = 0
	if current_level < costs.size():
		cost = int(costs[current_level])

	var required_level: int = _required_account_level(track)
	var is_unlocked: bool = _is_track_unlocked(track, profile)
	var is_max_level: bool = current_level >= max_level
	var reason: String = ""
	if not is_unlocked:
		reason = "locked"
	elif is_max_level:
		reason = "max_level"
	elif current_level >= costs.size():
		reason = "missing_cost"
	elif balance < cost:
		reason = "insufficient_currency"

	return {
		"upgrade_id": upgrade_id,
		"name_key": String(track.get("name_key", "")),
		"desc_key": String(track.get("desc_key", "")),
		"currency_id": currency_id,
		"currency_name_key": _currency_name_key(currency_id),
		"current_level": current_level,
		"max_level": max_level,
		"cost": cost,
		"balance": balance,
		"account_level_required": required_level,
		"is_unlocked": is_unlocked,
		"is_max_level": is_max_level,
		"can_purchase": reason.is_empty(),
		"reason": reason,
	}


func _is_track_unlocked(track: Dictionary, profile: Dictionary) -> bool:
	return int(profile.get("account_level", 1)) >= _required_account_level(track)


func _required_account_level(track: Dictionary) -> int:
	var condition: Dictionary = _dictionary_or_empty(track.get("unlock_condition", {}))
	return int(condition.get("account_level", 1))


func _account_level_for_xp(account_xp: int) -> int:
	var account_level: Dictionary = _dictionary_or_empty(_meta_config().get("account_level", {}))
	var thresholds: Array = _array_or_empty(account_level.get("thresholds", []))
	var result: int = 1
	for index: int in range(thresholds.size()):
		if account_xp >= int(thresholds[index]):
			result = index + 1
	return maxi(result, 1)


func _clamped_currency_amount(currency_id: String, amount: int) -> int:
	var max_amount: int = 2_147_483_647
	for currency: Dictionary in _currencies():
		if String(currency.get("id", "")) == currency_id:
			max_amount = int(currency.get("max_amount", max_amount))
			break
	return clampi(amount, 0, max_amount)


func _currency_name_key(currency_id: String) -> String:
	for currency: Dictionary in _currencies():
		if String(currency.get("id", "")) == currency_id:
			return String(currency.get("name_key", currency_id))
	return currency_id


func _primary_currency_id() -> String:
	for currency: Dictionary in _currencies():
		var currency_id: String = String(currency.get("id", ""))
		if not currency_id.is_empty():
			return currency_id
	return META_CURRENCIES.META_ESSENCE


func _upgrade_track(upgrade_id: String) -> Dictionary:
	for track: Dictionary in _upgrade_tracks():
		if String(track.get("id", "")) == upgrade_id:
			return track.duplicate(true)
	return {}


func _meta_config() -> Dictionary:
	var data: Variant = DataLoader.load_json(DataLoader.META_PROGRESSION_PATH)
	return data if data is Dictionary else {}


func _currencies() -> Array[Dictionary]:
	return _typed_dictionary_array(_meta_config().get("currencies", []))


func _upgrade_tracks() -> Array[Dictionary]:
	return _typed_dictionary_array(_meta_config().get("upgrade_tracks", []))


func _unlocks() -> Array[Dictionary]:
	return _typed_dictionary_array(_meta_config().get("unlocks", []))


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in (raw_value as Array):
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for item: Variant in (raw_value as Array):
		var value: String = String(item)
		if not value.is_empty() and not result.has(value):
			result.append(value)
	return result
