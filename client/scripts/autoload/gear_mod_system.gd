# Doc: docs/代码/gear_mod_system.md
# Authority: docs/游戏设计文档.md §7.2 / §9.16
class_name GearModSystemAutoload
extends Node


const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")
const GEAR_MOD_KINDS := preload("res://scripts/contracts/gear_mod_kinds.gd")


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


func mod_definitions() -> Array[Dictionary]:
	return _typed_dictionary_array(_gear_data().get("mods", []))


func board_config() -> Dictionary:
	return _dictionary_or_empty(_gear_data().get("board", {}))


func modifiers(mod_id: String) -> Array[Dictionary]:
	var definition: Dictionary = mod_definition(mod_id)
	if (
		definition.is_empty()
		or String(definition.get("kind", "")) != GEAR_MOD_KINDS.EFFECT
	):
		return []
	var resolved_modifiers: Array[Dictionary] = []
	for modifier: Dictionary in _typed_dictionary_array(
		definition.get("modifiers", [])
	):
		var stat: String = String(modifier.get("stat", ""))
		var modifier_type: String = String(modifier.get("type", ""))
		if stat.is_empty() or not modifier_type in ["add", "mult"]:
			continue
		resolved_modifiers.append({
			"stat": stat,
			"type": modifier_type,
			"value": float(modifier.get("value", 0.0)),
		})
	return resolved_modifiers


func pickup_config() -> Dictionary:
	return _dictionary_or_empty(_gear_data().get("pickup", {}))


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
	var modifiers_by_slot: Dictionary = {}
	for loadout_slot: String in GEAR_MOD_SLOTS.VALUES:
		modifiers_by_slot[loadout_slot] = []

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
		var mod_kind: String = String(definition.get("kind", ""))
		var resolved_selection: Dictionary = {
			"mod_id": mod_id,
			"kind": mod_kind,
			"name_key": String(definition.get("name_key", "")),
			"desc_key": String(definition.get("desc_key", "")),
		}
		if mod_kind == GEAR_MOD_KINDS.EFFECT:
			var loadout_slot: String = String(definition.get("slot", ""))
			if not GEAR_MOD_SLOTS.VALUES.has(loadout_slot):
				diagnostics.append({
					"mod_id": mod_id,
					"reason": "unknown_loadout_slot",
				})
				continue
			resolved_selection["slot"] = loadout_slot
			var slot_modifiers: Array = modifiers_by_slot[loadout_slot] as Array
			slot_modifiers.append_array(modifiers(mod_id))
			modifiers_by_slot[loadout_slot] = slot_modifiers
		elif mod_kind == GEAR_MOD_KINDS.MAP:
			resolved_selection["map_behavior"] = _dictionary_or_empty(
				definition.get("map_behavior", {})
			)
		elif mod_kind == GEAR_MOD_KINDS.GRID:
			resolved_selection["grid_behavior"] = _dictionary_or_empty(
				definition.get("grid_behavior", {})
			)
		else:
			diagnostics.append({
				"mod_id": mod_id,
				"reason": "unknown_mod_kind",
			})
			continue
		selected.append(resolved_selection)

	return {
		"ok": true,
		"selected": selected,
		"modifiers": modifiers_by_slot,
		"diagnostics": diagnostics,
	}


func _gear_data() -> Dictionary:
	var payload: Variant = DataLoader.load_json(DataLoader.GEAR_MODS_PATH)
	if payload is Dictionary:
		return (payload as Dictionary).duplicate(true)
	return {}


func _mod_definitions() -> Array[Dictionary]:
	return mod_definitions()


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
