# Doc: docs/代码/gear_mod_system.md
# Authority: docs/游戏设计文档.md §7.2 / §9.16
class_name GearModSystemAutoload
extends Node


const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")
const GEAR_MOD_COMPONENT_TYPES := preload(
	"res://scripts/contracts/gear_mod_component_types.gd"
)


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
	if definition.is_empty():
		return []
	var resolved_modifiers: Array[Dictionary] = []
	for component: Dictionary in modifier_components(mod_id):
		for modifier: Dictionary in _typed_dictionary_array(
			component.get("modifiers", [])
		):
			var stat: String = String(modifier.get("stat", ""))
			var modifier_type: String = String(modifier.get("type", ""))
			if stat.is_empty() or not modifier_type in ["add", "mult"]:
				continue
			resolved_modifiers.append({
				"slot": String(component.get("slot", "")),
				"component_id": String(component.get("component_id", "")),
				"stat": stat,
				"type": modifier_type,
				"value": float(modifier.get("value", 0.0)),
			})
	return resolved_modifiers


func components(mod_id: String) -> Array[Dictionary]:
	return _typed_dictionary_array(mod_definition(mod_id).get("components", []))


func modifier_components(mod_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for component: Dictionary in components(mod_id):
		if String(component.get("type", "")) == GEAR_MOD_COMPONENT_TYPES.MODIFIER:
			result.append(component)
	return result


func program_components(mod_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for component: Dictionary in components(mod_id):
		if String(component.get("type", "")) == GEAR_MOD_COMPONENT_TYPES.PROGRAM:
			result.append(component)
	return result


func board_rule_components(mod_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for component: Dictionary in components(mod_id):
		if String(component.get("type", "")) == GEAR_MOD_COMPONENT_TYPES.BOARD_RULE:
			result.append(component)
	return result


func component_summary(mod_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for component: Dictionary in components(mod_id):
		var summary: Dictionary = {
			"component_id": String(component.get("component_id", "")),
			"type": String(component.get("type", "")),
		}
		if component.has("slot"):
			summary["slot"] = String(component.get("slot", ""))
		result.append(summary)
	return result


func pickup_config() -> Dictionary:
	return _dictionary_or_empty(_gear_data().get("pickup", {}))


func reward_pool_ids(
	pool_id: String,
	allowed_mod_ids: Array[String] = []
) -> Array[String]:
	var result: Array[String] = []
	for pool: Dictionary in _typed_dictionary_array(
		_gear_data().get("reward_pools", [])
	):
		if String(pool.get("id", "")) != pool_id:
			continue
		for mod_id: String in _string_array(pool.get("mod_ids", [])):
			if (
				(allowed_mod_ids.is_empty() or allowed_mod_ids.has(mod_id))
				and not result.has(mod_id)
			):
				result.append(mod_id)
		break
	for contribution: Dictionary in _typed_dictionary_array(
		_gear_data().get("reward_pool_contributions", [])
	):
		if String(contribution.get("pool_id", "")) != pool_id:
			continue
		for mod_id: String in _string_array(contribution.get("mod_ids", [])):
			if (
				(allowed_mod_ids.is_empty() or allowed_mod_ids.has(mod_id))
				and not result.has(mod_id)
			):
				result.append(mod_id)
	return result


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
		var resolved_selection: Dictionary = {
			"mod_id": mod_id,
			"name_key": String(definition.get("name_key", "")),
			"desc_key": String(definition.get("desc_key", "")),
			"components": component_summary(mod_id),
		}
		for component: Dictionary in modifier_components(mod_id):
			var loadout_slot: String = String(component.get("slot", ""))
			if not GEAR_MOD_SLOTS.VALUES.has(loadout_slot):
				diagnostics.append({
					"mod_id": mod_id,
					"component_id": String(component.get("component_id", "")),
					"reason": "unknown_loadout_slot",
				})
				continue
			var slot_modifiers: Array = modifiers_by_slot[loadout_slot] as Array
			for modifier: Dictionary in _typed_dictionary_array(
				component.get("modifiers", [])
			):
				var resolved_modifier: Dictionary = modifier.duplicate(true)
				resolved_modifier["slot"] = loadout_slot
				resolved_modifier["component_id"] = String(
					component.get("component_id", "")
				)
				slot_modifiers.append(resolved_modifier)
			modifiers_by_slot[loadout_slot] = slot_modifiers
		if components(mod_id).is_empty():
			diagnostics.append({
				"mod_id": mod_id,
				"reason": "missing_components",
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
