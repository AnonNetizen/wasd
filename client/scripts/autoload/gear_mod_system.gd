# Doc: docs/代码/gear_mod_system.md
# Authority: docs/游戏设计文档.md §7.2 / §9.16, docs/AI协作/工作包/F11-GearModLoadout.md
class_name GearModSystemAutoload
extends Node


const GEAR_MOD_RESOURCES := preload("res://scripts/contracts/gear_mod_resources.gd")
const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")
const GEAR_MOD_STACK_RULES := preload("res://scripts/contracts/gear_mod_stack_rules.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const DEFAULT_CAPACITY: int = 8
const INSTANCE_PREFIX: String = "gear_mod_"
const PROFILE_KEY: String = "gear_mods"
const PROFILE_SCHEMA_VERSION: int = 1


func load_or_create_profile(slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var stored_profile: Dictionary = _load_meta_profile(slot)
	var profile: Dictionary = _normalize_profile(stored_profile)
	if stored_profile.is_empty() or profile != stored_profile:
		if not _save_meta_profile(profile, slot):
			push_error("[GearModSystem] failed to save profile: %s" % SaveManager.last_error())
	return profile


func profile_summary(slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var loadout_summaries: Dictionary = {}
	for loadout_slot: String in GEAR_MOD_SLOTS.VALUES:
		loadout_summaries[loadout_slot] = _loadout_summary(gear_state, loadout_slot)
	return {
		"schema_version": int(gear_state.get("schema_version", PROFILE_SCHEMA_VERSION)),
		"resources": _dictionary_or_empty(gear_state.get("resources", {})),
		"inventory_count": _array_or_empty(gear_state.get("inventory", [])).size(),
		"loadouts": loadout_summaries,
	}


func mod_summaries(loadout_slot: String, slot: String = SaveManager.DEFAULT_SLOT) -> Array[Dictionary]:
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var summaries: Array[Dictionary] = []
	for item: Dictionary in _inventory(gear_state):
		var mod_id: String = String(item.get("mod_id", ""))
		var definition: Dictionary = _mod_definition(mod_id)
		if definition.is_empty():
			continue
		var instance_id: String = String(item.get("instance_id", ""))
		var is_equipped: bool = _loadout_equipped_ids(gear_state, loadout_slot).has(instance_id)
		var rank: int = int(item.get("rank", 0))
		var drain: int = _mod_drain(definition, rank)
		var next_rank: int = rank + 1
		summaries.append({
			"instance_id": instance_id,
			"mod_id": mod_id,
			"name_key": String(definition.get("name_key", "")),
			"desc_key": String(definition.get("desc_key", "")),
			"slot": String(definition.get("slot", "")),
			"rarity": String(definition.get("rarity", "")),
			"rank": rank,
			"max_rank": int(definition.get("max_rank", 0)),
			"drain": drain,
			"equipped": is_equipped,
			"can_equip": _can_equip(gear_state, loadout_slot, item, definition).get("ok", false),
			"upgrade_cost": _fusion_cost(String(definition.get("rarity", "")), next_rank) if next_rank <= int(definition.get("max_rank", 0)) else {},
			"dismantle": _dictionary_or_empty(definition.get("dismantle", {})),
			"modifiers": _modifiers_for_item(item, definition, loadout_slot),
		})
	return summaries


func grant_mod(mod_id: String, count: int = 1, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var definition: Dictionary = _mod_definition(mod_id)
	if definition.is_empty():
		return _result(false, "unknown_mod")
	var grant_count: int = maxi(count, 1)
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var inventory: Array = _array_or_empty(gear_state.get("inventory", []))
	var instance_ids: Array[String] = []
	var next_index: int = maxi(int(gear_state.get("next_instance_index", 1)), 1)
	for _index: int in range(grant_count):
		var instance_id: String = _instance_id(next_index)
		next_index += 1
		inventory.append({
			"instance_id": instance_id,
			"mod_id": mod_id,
			"rank": 0,
			"count": 1,
		})
		instance_ids.append(instance_id)
	gear_state["inventory"] = inventory
	gear_state["next_instance_index"] = next_index
	profile[PROFILE_KEY] = gear_state
	return _save_result(profile, slot, {
		"mod_id": mod_id,
		"instance_ids": instance_ids,
	})


func equip_mod(loadout_slot: String, instance_id: String, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var item: Dictionary = _inventory_item(gear_state, instance_id)
	if item.is_empty():
		return _result(false, "unknown_instance")
	var definition: Dictionary = _mod_definition(String(item.get("mod_id", "")))
	var allowed: Dictionary = _can_equip(gear_state, loadout_slot, item, definition)
	if not bool(allowed.get("ok", false)):
		return allowed
	var loadout: Dictionary = _loadout(gear_state, loadout_slot)
	var equipped: Array[String] = _loadout_equipped_ids(gear_state, loadout_slot)
	if not equipped.has(instance_id):
		equipped.append(instance_id)
	loadout["equipped"] = equipped
	_set_loadout(gear_state, loadout_slot, loadout)
	profile[PROFILE_KEY] = gear_state
	return _save_result(profile, slot, {
		"loadout_slot": loadout_slot,
		"instance_id": instance_id,
	})


func unequip_mod(loadout_slot: String, instance_id: String, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var loadout: Dictionary = _loadout(gear_state, loadout_slot)
	if loadout.is_empty():
		return _result(false, "unknown_loadout_slot")
	var equipped: Array[String] = _loadout_equipped_ids(gear_state, loadout_slot)
	if not equipped.has(instance_id):
		return _result(false, "not_equipped")
	equipped.erase(instance_id)
	loadout["equipped"] = equipped
	_set_loadout(gear_state, loadout_slot, loadout)
	profile[PROFILE_KEY] = gear_state
	return _save_result(profile, slot, {
		"loadout_slot": loadout_slot,
		"instance_id": instance_id,
	})


func upgrade_mod(instance_id: String, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var item_index: int = _inventory_index(gear_state, instance_id)
	if item_index < 0:
		return _result(false, "unknown_instance")
	var inventory: Array = _array_or_empty(gear_state.get("inventory", []))
	var item: Dictionary = (inventory[item_index] as Dictionary).duplicate(true)
	var definition: Dictionary = _mod_definition(String(item.get("mod_id", "")))
	if definition.is_empty():
		return _result(false, "unknown_mod")
	var current_rank: int = int(item.get("rank", 0))
	var next_rank: int = current_rank + 1
	if next_rank > int(definition.get("max_rank", 0)):
		return _result(false, "max_rank")
	var equipped_slot: String = _equipped_loadout_slot(gear_state, instance_id)
	if not equipped_slot.is_empty():
		var projected_drain: int = _loadout_used_drain(gear_state, equipped_slot, {instance_id: next_rank})
		if projected_drain > _loadout_capacity(gear_state, equipped_slot):
			return _result(false, "capacity_exceeded", {
				"loadout_slot": equipped_slot,
				"used_drain": projected_drain,
				"capacity": _loadout_capacity(gear_state, equipped_slot),
			})
	var cost: Dictionary = _fusion_cost(String(definition.get("rarity", "")), next_rank)
	if cost.is_empty():
		return _result(false, "missing_cost")
	var resource_id: String = String(cost.get("resource_id", ""))
	var cost_amount: int = int(cost.get("cost", 0))
	var resources: Dictionary = _dictionary_or_empty(gear_state.get("resources", {}))
	var balance: int = int(resources.get(resource_id, 0))
	if balance < cost_amount:
		return _result(false, "insufficient_resource", {
			"resource_id": resource_id,
			"cost": cost_amount,
			"balance": balance,
		})
	resources[resource_id] = balance - cost_amount
	item["rank"] = next_rank
	inventory[item_index] = item
	gear_state["resources"] = resources
	gear_state["inventory"] = inventory
	profile[PROFILE_KEY] = gear_state
	return _save_result(profile, slot, {
		"instance_id": instance_id,
		"rank": next_rank,
		"resource_id": resource_id,
		"cost": cost_amount,
	})


func dismantle_mod(instance_id: String, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	if not _equipped_loadout_slot(gear_state, instance_id).is_empty():
		return _result(false, "equipped")
	var item_index: int = _inventory_index(gear_state, instance_id)
	if item_index < 0:
		return _result(false, "unknown_instance")
	var inventory: Array = _array_or_empty(gear_state.get("inventory", []))
	var item: Dictionary = inventory[item_index] as Dictionary
	var definition: Dictionary = _mod_definition(String(item.get("mod_id", "")))
	var dismantle: Dictionary = _dictionary_or_empty(definition.get("dismantle", {}))
	var resource_id: String = String(dismantle.get("resource_id", ""))
	var amount: int = maxi(int(dismantle.get("amount", 0)), 0)
	var resources: Dictionary = _dictionary_or_empty(gear_state.get("resources", {}))
	resources[resource_id] = maxi(int(resources.get(resource_id, 0)) + amount, 0)
	inventory.remove_at(item_index)
	gear_state["resources"] = resources
	gear_state["inventory"] = inventory
	profile[PROFILE_KEY] = gear_state
	return _save_result(profile, slot, {
		"instance_id": instance_id,
		"resource_id": resource_id,
		"amount": amount,
	})


func roll_drop_for_enemy(enemy_id: String, enemy_level: int = 1, slot: String = SaveManager.DEFAULT_SLOT, forced_roll: float = -1.0) -> Dictionary:
	var drops: Array[Dictionary] = []
	var attempts: int = 0
	for row: Dictionary in _drop_rows_for_enemy(enemy_id, enemy_level):
		attempts += 1
		var chance: float = clampf(float(row.get("drop_chance", 0.0)), 0.0, 1.0)
		var roll: float = forced_roll if forced_roll >= 0.0 else RNG.drop.randf()
		if roll > chance:
			continue
		var mod_id: String = String(row.get("mod_id", ""))
		var definition: Dictionary = _mod_definition(mod_id)
		var grant: Dictionary = grant_mod(mod_id, 1, slot)
		if bool(grant.get("ok", false)):
			drops.append({
				"mod_id": mod_id,
				"name_key": String(definition.get("name_key", "")),
				"instance_ids": grant.get("instance_ids", []),
				"chance": chance,
				"roll": roll,
			})
	return {
		"ok": true,
		"enemy_id": enemy_id,
		"enemy_level": enemy_level,
		"attempts": attempts,
		"drops": drops,
	}


func current_modifiers(loadout_slot: String, slot: String = SaveManager.DEFAULT_SLOT) -> Array[Dictionary]:
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var modifiers: Array[Dictionary] = []
	for instance_id: String in _loadout_equipped_ids(gear_state, loadout_slot):
		var item: Dictionary = _inventory_item(gear_state, instance_id)
		var definition: Dictionary = _mod_definition(String(item.get("mod_id", "")))
		if item.is_empty() or definition.is_empty():
			continue
		modifiers.append_array(_modifiers_for_item(item, definition, loadout_slot))
	return modifiers


func current_all_modifiers(slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var result: Dictionary = {}
	for loadout_slot: String in GEAR_MOD_SLOTS.VALUES:
		result[loadout_slot] = current_modifiers(loadout_slot, slot)
	return result


func debug_grant_resource(resource_id: String, amount: int, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	if not GEAR_MOD_RESOURCES.VALUES.has(resource_id):
		return _result(false, "unknown_resource")
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var resources: Dictionary = _dictionary_or_empty(gear_state.get("resources", {}))
	var previous_balance: int = int(resources.get(resource_id, 0))
	resources[resource_id] = maxi(previous_balance + maxi(amount, 0), 0)
	gear_state["resources"] = resources
	profile[PROFILE_KEY] = gear_state
	return _save_result(profile, slot, {
		"resource_id": resource_id,
		"previous_balance": previous_balance,
		"balance": int(resources.get(resource_id, 0)),
	})


func debug_set_loadout_capacity(loadout_slot: String, capacity: int, slot: String = SaveManager.DEFAULT_SLOT) -> Dictionary:
	var profile: Dictionary = load_or_create_profile(slot)
	var gear_state: Dictionary = _gear_state(profile)
	var loadout: Dictionary = _loadout(gear_state, loadout_slot)
	if loadout.is_empty():
		return _result(false, "unknown_loadout_slot")
	loadout["capacity"] = maxi(capacity, 0)
	_set_loadout(gear_state, loadout_slot, loadout)
	profile[PROFILE_KEY] = gear_state
	return _save_result(profile, slot, {
		"loadout_slot": loadout_slot,
		"capacity": int(loadout.get("capacity", 0)),
	})


func _normalize_profile(raw_profile: Dictionary) -> Dictionary:
	var profile: Dictionary = raw_profile.duplicate(true)
	profile[PROFILE_KEY] = _normalize_gear_state(_dictionary_or_empty(profile.get(PROFILE_KEY, {})))
	return profile


func _normalize_gear_state(raw_state: Dictionary) -> Dictionary:
	var resources: Dictionary = {}
	var raw_resources: Dictionary = _dictionary_or_empty(raw_state.get("resources", {}))
	for resource_id: String in GEAR_MOD_RESOURCES.VALUES:
		resources[resource_id] = maxi(int(raw_resources.get(resource_id, 0)), 0)

	var next_index: int = maxi(int(raw_state.get("next_instance_index", 1)), 1)
	var used_instance_ids: Array[String] = []
	var inventory: Array[Dictionary] = []
	for raw_item: Variant in _array_or_empty(raw_state.get("inventory", [])):
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item as Dictionary
		var mod_id: String = String(item.get("mod_id", ""))
		var definition: Dictionary = _mod_definition(mod_id)
		if definition.is_empty():
			continue
		var instance_id: String = String(item.get("instance_id", ""))
		if instance_id.is_empty() or used_instance_ids.has(instance_id):
			instance_id = _instance_id(next_index)
			next_index += 1
		used_instance_ids.append(instance_id)
		inventory.append({
			"instance_id": instance_id,
			"mod_id": mod_id,
			"rank": clampi(int(item.get("rank", 0)), 0, int(definition.get("max_rank", 0))),
			"count": maxi(int(item.get("count", 1)), 1),
		})

	var state: Dictionary = {
		"schema_version": PROFILE_SCHEMA_VERSION,
		"resources": resources,
		"inventory": inventory,
		"loadouts": {},
		"next_instance_index": next_index,
	}
	var raw_loadouts: Dictionary = _dictionary_or_empty(raw_state.get("loadouts", {}))
	for loadout_slot: String in GEAR_MOD_SLOTS.VALUES:
		var raw_loadout: Dictionary = _dictionary_or_empty(raw_loadouts.get(loadout_slot, {}))
		var loadout: Dictionary = {
			"capacity": maxi(int(raw_loadout.get("capacity", DEFAULT_CAPACITY)), 0),
			"equipped": _normalized_equipped_ids(loadout_slot, raw_loadout, inventory),
		}
		(state["loadouts"] as Dictionary)[loadout_slot] = _trim_equipped_to_capacity(loadout_slot, loadout, state)
	return state


func _normalized_equipped_ids(loadout_slot: String, raw_loadout: Dictionary, inventory: Array[Dictionary]) -> Array[String]:
	var equipped: Array[String] = []
	var equipped_mod_ids: Array[String] = []
	for raw_instance_id: Variant in _array_or_empty(raw_loadout.get("equipped", [])):
		var instance_id: String = String(raw_instance_id)
		if instance_id.is_empty() or equipped.has(instance_id):
			continue
		var item: Dictionary = _inventory_item_from_array(inventory, instance_id)
		var definition: Dictionary = _mod_definition(String(item.get("mod_id", "")))
		if item.is_empty() or definition.is_empty():
			continue
		if String(definition.get("slot", "")) != loadout_slot:
			continue
		if String(definition.get("stack_rule", "")) == GEAR_MOD_STACK_RULES.UNIQUE_BY_ID:
			var mod_id: String = String(item.get("mod_id", ""))
			if equipped_mod_ids.has(mod_id):
				continue
			equipped_mod_ids.append(mod_id)
		equipped.append(instance_id)
	return equipped


func _trim_equipped_to_capacity(loadout_slot: String, loadout: Dictionary, gear_state: Dictionary) -> Dictionary:
	var kept: Array[String] = []
	var used_drain: int = 0
	for instance_id: String in _string_array(loadout.get("equipped", [])):
		var item: Dictionary = _inventory_item(gear_state, instance_id)
		var definition: Dictionary = _mod_definition(String(item.get("mod_id", "")))
		if item.is_empty() or definition.is_empty():
			continue
		var next_drain: int = used_drain + _mod_drain(definition, int(item.get("rank", 0)))
		if next_drain > int(loadout.get("capacity", DEFAULT_CAPACITY)):
			continue
		used_drain = next_drain
		kept.append(instance_id)
	var result: Dictionary = loadout.duplicate(true)
	result["equipped"] = kept
	return result


func _load_meta_profile(slot: String) -> Dictionary:
	if SaveManager.has_save(slot, SAVE_KINDS.META):
		return SaveManager.load(slot, SAVE_KINDS.META)
	return {}


func _save_meta_profile(profile: Dictionary, slot: String) -> bool:
	return SaveManager.save(slot, SAVE_KINDS.META, profile)


func _save_result(profile: Dictionary, slot: String, payload: Dictionary) -> Dictionary:
	var saved: bool = _save_meta_profile(profile, slot)
	var result: Dictionary = payload.duplicate(true)
	result["ok"] = saved
	result["reason"] = "" if saved else "save_failed"
	result["profile"] = profile.duplicate(true)
	return result


func _can_equip(gear_state: Dictionary, loadout_slot: String, item: Dictionary, definition: Dictionary) -> Dictionary:
	if not GEAR_MOD_SLOTS.VALUES.has(loadout_slot):
		return _result(false, "unknown_loadout_slot")
	if item.is_empty():
		return _result(false, "unknown_instance")
	if definition.is_empty():
		return _result(false, "unknown_mod")
	if String(definition.get("slot", "")) != loadout_slot:
		return _result(false, "slot_mismatch")
	var instance_id: String = String(item.get("instance_id", ""))
	var equipped: Array[String] = _loadout_equipped_ids(gear_state, loadout_slot)
	if equipped.has(instance_id):
		return _result(true, "")
	if String(definition.get("stack_rule", "")) == GEAR_MOD_STACK_RULES.UNIQUE_BY_ID:
		for equipped_id: String in equipped:
			var equipped_item: Dictionary = _inventory_item(gear_state, equipped_id)
			if String(equipped_item.get("mod_id", "")) == String(item.get("mod_id", "")):
				return _result(false, "duplicate_mod")
	var used_drain: int = _loadout_used_drain(gear_state, loadout_slot)
	var next_drain: int = used_drain + _mod_drain(definition, int(item.get("rank", 0)))
	var capacity: int = _loadout_capacity(gear_state, loadout_slot)
	if next_drain > capacity:
		return _result(false, "capacity_exceeded", {
			"used_drain": next_drain,
			"capacity": capacity,
		})
	return _result(true, "")


func _loadout_summary(gear_state: Dictionary, loadout_slot: String) -> Dictionary:
	return {
		"capacity": _loadout_capacity(gear_state, loadout_slot),
		"used_drain": _loadout_used_drain(gear_state, loadout_slot),
		"equipped": _loadout_equipped_ids(gear_state, loadout_slot),
	}


func _modifiers_for_item(item: Dictionary, definition: Dictionary, loadout_slot: String) -> Array[Dictionary]:
	var modifiers: Array[Dictionary] = []
	var rank: int = int(item.get("rank", 0))
	for raw_modifier: Variant in _array_or_empty(definition.get("rank_modifiers", [])):
		if not raw_modifier is Dictionary:
			continue
		var modifier: Dictionary = raw_modifier as Dictionary
		modifiers.append({
			"stat": String(modifier.get("stat", "")),
			"type": String(modifier.get("type", "")),
			"value": float(modifier.get("base_value", 0.0)) + float(modifier.get("value_per_rank", 0.0)) * float(rank),
			"source": "gear_mod",
			"mod_id": String(item.get("mod_id", "")),
			"instance_id": String(item.get("instance_id", "")),
			"rank": rank,
			"loadout_slot": loadout_slot,
		})
	return modifiers


func _mod_drain(definition: Dictionary, rank: int) -> int:
	return maxi(int(definition.get("base_drain", 0)) + int(definition.get("drain_per_rank", 0)) * maxi(rank, 0), 0)


func _loadout_used_drain(gear_state: Dictionary, loadout_slot: String, rank_overrides: Dictionary = {}) -> int:
	var used_drain: int = 0
	for instance_id: String in _loadout_equipped_ids(gear_state, loadout_slot):
		var item: Dictionary = _inventory_item(gear_state, instance_id)
		var definition: Dictionary = _mod_definition(String(item.get("mod_id", "")))
		if item.is_empty() or definition.is_empty():
			continue
		var rank: int = int(rank_overrides.get(instance_id, item.get("rank", 0)))
		used_drain += _mod_drain(definition, rank)
	return used_drain


func _loadout_capacity(gear_state: Dictionary, loadout_slot: String) -> int:
	return int(_loadout(gear_state, loadout_slot).get("capacity", DEFAULT_CAPACITY))


func _equipped_loadout_slot(gear_state: Dictionary, instance_id: String) -> String:
	for loadout_slot: String in GEAR_MOD_SLOTS.VALUES:
		if _loadout_equipped_ids(gear_state, loadout_slot).has(instance_id):
			return loadout_slot
	return ""


func _loadout_equipped_ids(gear_state: Dictionary, loadout_slot: String) -> Array[String]:
	return _string_array(_loadout(gear_state, loadout_slot).get("equipped", []))


func _loadout(gear_state: Dictionary, loadout_slot: String) -> Dictionary:
	var loadouts: Dictionary = _dictionary_or_empty(gear_state.get("loadouts", {}))
	return _dictionary_or_empty(loadouts.get(loadout_slot, {}))


func _set_loadout(gear_state: Dictionary, loadout_slot: String, loadout: Dictionary) -> void:
	var loadouts: Dictionary = _dictionary_or_empty(gear_state.get("loadouts", {}))
	loadouts[loadout_slot] = loadout
	gear_state["loadouts"] = loadouts


func _gear_state(profile: Dictionary) -> Dictionary:
	return _dictionary_or_empty(profile.get(PROFILE_KEY, {}))


func _inventory(gear_state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Variant in _array_or_empty(gear_state.get("inventory", [])):
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _inventory_index(gear_state: Dictionary, instance_id: String) -> int:
	var inventory: Array = _array_or_empty(gear_state.get("inventory", []))
	for index: int in range(inventory.size()):
		if not inventory[index] is Dictionary:
			continue
		if String((inventory[index] as Dictionary).get("instance_id", "")) == instance_id:
			return index
	return -1


func _inventory_item(gear_state: Dictionary, instance_id: String) -> Dictionary:
	return _inventory_item_from_array(_inventory(gear_state), instance_id)


func _inventory_item_from_array(inventory: Array[Dictionary], instance_id: String) -> Dictionary:
	for item: Dictionary in inventory:
		if String(item.get("instance_id", "")) == instance_id:
			return item.duplicate(true)
	return {}


func _mod_definition(mod_id: String) -> Dictionary:
	if mod_id.is_empty():
		return {}
	for definition: Dictionary in _mod_definitions():
		if String(definition.get("id", "")) == mod_id:
			return definition.duplicate(true)
	return {}


func _mod_definitions() -> Array[Dictionary]:
	var data: Variant = DataLoader.load_json(DataLoader.GEAR_MODS_PATH)
	if not data is Dictionary:
		return []
	return _typed_dictionary_array((data as Dictionary).get("mods", []))


func _drop_rows_for_enemy(enemy_id: String, enemy_level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in DataLoader.load_csv(DataLoader.GEAR_MOD_DROP_TABLES_PATH):
		if String(row.get("source_enemy_id", "")) != enemy_id:
			continue
		if enemy_level < int(row.get("min_enemy_level", 1)):
			continue
		if enemy_level > int(row.get("max_enemy_level", 999)):
			continue
		result.append(row.duplicate(true))
	return result


func _fusion_cost(rarity: String, rank: int) -> Dictionary:
	for row: Dictionary in DataLoader.load_csv(DataLoader.GEAR_MOD_FUSION_COSTS_PATH):
		if String(row.get("rarity", "")) == rarity and int(row.get("rank", 0)) == rank:
			return {
				"resource_id": String(row.get("resource_id", "")),
				"cost": int(row.get("cost", 0)),
			}
	return {}


func _instance_id(index: int) -> String:
	return "%s%d" % [INSTANCE_PREFIX, maxi(index, 1)]


func _result(ok: bool, reason: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = extra.duplicate(true)
	result["ok"] = ok
	result["reason"] = reason
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		var value: String = String(item)
		if not value.is_empty() and not result.has(value):
			result.append(value)
	return result
