# Doc: docs/代码/gear_mod_system.md
# Authority: docs/游戏设计文档.md §7.2 / §9.16
class_name GearModSystemAutoload
extends Node


const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")


## Rolls every matching enemy drop row without mutating run or meta state.
func roll_drop_for_enemy(
	enemy_id: String,
	enemy_level: int = 1,
	forced_roll: float = -1.0,
	allowed_mod_ids: Array[String] = []
) -> Dictionary:
	var drops: Array[Dictionary] = []
	var attempts: int = 0
	for row: Dictionary in _drop_rows_for_enemy(enemy_id, enemy_level):
		var mod_id: String = String(row.get("mod_id", ""))
		if not allowed_mod_ids.is_empty() and not allowed_mod_ids.has(mod_id):
			continue
		attempts += 1
		var chance: float = clampf(
			float(row.get("drop_chance", 0.0)),
			0.0,
			1.0
		)
		var roll: float = (
			forced_roll
			if forced_roll >= 0.0
			else RNG.drop.randf()
		)
		if roll > chance:
			continue
		var definition: Dictionary = mod_definition(mod_id)
		if definition.is_empty():
			continue
		drops.append({
			"mod_id": mod_id,
			"name_key": String(definition.get("name_key", "")),
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


func mod_definition(mod_id: String) -> Dictionary:
	for definition: Dictionary in _mod_definitions():
		if String(definition.get("id", "")) == mod_id:
			return definition.duplicate(true)
	return {}


func rank_modifiers(mod_id: String, rank: int) -> Array[Dictionary]:
	var definition: Dictionary = mod_definition(mod_id)
	if definition.is_empty():
		return []
	var resolved_rank: int = clampi(rank, 0, max_rank(mod_id))
	var modifiers: Array[Dictionary] = []
	for modifier: Dictionary in _typed_dictionary_array(
		definition.get("rank_modifiers", [])
	):
		var stat: String = String(modifier.get("stat", ""))
		var modifier_type: String = String(modifier.get("type", ""))
		if stat.is_empty() or not modifier_type in ["add", "mult"]:
			continue
		modifiers.append({
			"stat": stat,
			"type": modifier_type,
			"value": (
				float(modifier.get("base_value", 0.0))
				+ float(modifier.get("value_per_rank", 0.0))
				* float(resolved_rank)
			),
		})
	return modifiers


func max_rank(mod_id: String) -> int:
	var definition: Dictionary = mod_definition(mod_id)
	if definition.is_empty():
		return -1
	return maxi(int(definition.get("max_rank", 0)), 0)


func overflow_gold() -> int:
	return maxi(int(_gear_data().get("overflow_gold", 0)), 0)


func pickup_config() -> Dictionary:
	return _dictionary_or_empty(_gear_data().get("pickup", {}))


func next_grant_preview(mod_id: String, current_rank: int) -> Dictionary:
	var definition: Dictionary = mod_definition(mod_id)
	if definition.is_empty():
		return {"ok": false, "reason": "unknown_gear_mod"}
	var maximum_rank: int = max_rank(mod_id)
	var resolved_current_rank: int = clampi(current_rank, -1, maximum_rank)
	if resolved_current_rank >= maximum_rank:
		return {
			"ok": true,
			"mod_id": mod_id,
			"name_key": String(definition.get("name_key", "")),
			"rank": maximum_rank,
			"display_rank": maximum_rank + 1,
			"overflow_gold": overflow_gold(),
			"modifiers": [],
		}
	var next_rank: int = resolved_current_rank + 1
	return {
		"ok": true,
		"mod_id": mod_id,
		"name_key": String(definition.get("name_key", "")),
		"rank": next_rank,
		"display_rank": next_rank + 1,
		"overflow_gold": 0,
		"modifiers": rank_modifiers(mod_id, next_rank),
	}


func reward_pool_ids(
	pool_id: String,
	allowed_mod_ids: Array[String] = []
) -> Array[String]:
	for pool: Dictionary in _typed_dictionary_array(
		_gear_data().get("reward_pools", [])
	):
		if String(pool.get("id", "")) != pool_id:
			continue
		var result: Array[String] = []
		for mod_id: String in _string_array(pool.get("mod_ids", [])):
			if allowed_mod_ids.is_empty() or allowed_mod_ids.has(mod_id):
				result.append(mod_id)
		return result
	return []


## Resolves an in-memory developer selection without inventory or save access.
## Invalid entries are omitted and described in diagnostics.
func resolve_preview_loadout(selections: Array) -> Dictionary:
	var selected: Array[Dictionary] = []
	var diagnostics: Array[Dictionary] = []
	var seen_mod_ids: Dictionary = {}
	var modifiers: Dictionary = {}
	for loadout_slot: String in GEAR_MOD_SLOTS.VALUES:
		modifiers[loadout_slot] = []

	for raw_selection: Variant in selections:
		if not raw_selection is Dictionary:
			diagnostics.append({"reason": "invalid_selection"})
			continue
		var selection: Dictionary = raw_selection as Dictionary
		var mod_id: String = String(
			selection.get("mod_id", "")
		).strip_edges()
		var definition: Dictionary = mod_definition(mod_id)
		if definition.is_empty():
			diagnostics.append({
				"mod_id": mod_id,
				"reason": "unknown_mod",
			})
			continue
		if seen_mod_ids.has(mod_id):
			diagnostics.append({
				"mod_id": mod_id,
				"reason": "duplicate_unique_mod",
			})
			continue
		var loadout_slot: String = String(definition.get("slot", ""))
		if not GEAR_MOD_SLOTS.VALUES.has(loadout_slot):
			diagnostics.append({
				"mod_id": mod_id,
				"reason": "unknown_loadout_slot",
			})
			continue
		var maximum_rank: int = max_rank(mod_id)
		var requested_rank: int = int(selection.get("rank", 0))
		var rank: int = clampi(requested_rank, 0, maximum_rank)
		if rank != requested_rank:
			diagnostics.append({
				"mod_id": mod_id,
				"reason": "rank_clamped",
				"requested_rank": requested_rank,
				"rank": rank,
			})
		selected.append({
			"mod_id": mod_id,
			"rank": rank,
			"slot": loadout_slot,
			"name_key": String(definition.get("name_key", "")),
			"desc_key": String(definition.get("desc_key", "")),
		})
		seen_mod_ids[mod_id] = true
		var slot_modifiers: Array = modifiers[loadout_slot] as Array
		slot_modifiers.append_array(rank_modifiers(mod_id, rank))
		modifiers[loadout_slot] = slot_modifiers

	return {
		"ok": true,
		"selected": selected,
		"modifiers": modifiers,
		"diagnostics": diagnostics,
	}


func _gear_data() -> Dictionary:
	var payload: Variant = DataLoader.load_json(DataLoader.GEAR_MODS_PATH)
	if payload is Dictionary:
		return (payload as Dictionary).duplicate(true)
	return {}


func _mod_definitions() -> Array[Dictionary]:
	return _typed_dictionary_array(_gear_data().get("mods", []))


func _drop_rows_for_enemy(
	enemy_id: String,
	enemy_level: int
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in DataLoader.load_csv(
		DataLoader.GEAR_MOD_DROP_TABLES_PATH
	):
		if String(row.get("source_enemy_id", "")) != enemy_id:
			continue
		var minimum_level: int = int(String(row.get("min_enemy_level", "1")))
		var maximum_level: int = int(String(row.get("max_enemy_level", "1")))
		if enemy_level < minimum_level or enemy_level > maximum_level:
			continue
		rows.append(row.duplicate(true))
	return rows


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for value: Variant in raw_value as Array:
		var item: String = String(value)
		if not item.is_empty():
			result.append(item)
	return result
