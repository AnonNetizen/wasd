# Doc: docs/代码/data_loader.md
# Authority: docs/词表与契约.md §12.1, §12-H, §12-I
class_name HeroCompositionResolver
extends RefCounted

const SkillSlotsContract = preload("res://scripts/contracts/skill_slots.gd")


static func resolve(
	characters_payload: Variant,
	main_character_id: String,
	sub_character_id: String,
	element_resolver: ElementResolver,
	allow_duplicate: bool = false,
) -> Dictionary:
	if not characters_payload is Dictionary:
		return {}
	var payload: Dictionary = characters_payload
	var characters_value: Variant = payload.get("characters", [])
	if not characters_value is Array:
		return {}
	var characters: Array = characters_value
	if main_character_id == sub_character_id and not allow_duplicate:
		return {}
	var main_character: Dictionary = _find_character(characters, main_character_id)
	var sub_character: Dictionary = _find_character(characters, sub_character_id)
	if main_character.is_empty() or sub_character.is_empty():
		return {}
	var main_skills: Array = main_character.get("hero_skill_ids", [])
	var sub_skills: Array = sub_character.get("hero_skill_ids", [])
	if main_skills.size() != 2 or sub_skills.size() != 2:
		return {}
	var main_element_id: String = str(main_character.get("element_id", ""))
	var sub_element_id: String = str(sub_character.get("element_id", ""))
	if not element_resolver.has_element(main_element_id) or not element_resolver.has_element(sub_element_id):
		return {}
	var main_palette_value: Variant = main_character.get("palette", {})
	var sub_palette_value: Variant = sub_character.get("palette", {})
	if not main_palette_value is Dictionary or not sub_palette_value is Dictionary:
		return {}
	var main_palette: Dictionary = main_palette_value
	var sub_palette: Dictionary = sub_palette_value
	var skill_slots: Dictionary = {
		SkillSlotsContract.SKILL_1: str(main_skills[0]),
		SkillSlotsContract.SKILL_2: str(main_skills[1]),
		SkillSlotsContract.SKILL_3: str(sub_skills[0]),
		SkillSlotsContract.SKILL_4: str(sub_skills[1]),
	}
	var slot_definitions: Array[Dictionary] = []
	var seen_skills: Dictionary = {}
	for slot_id: String in [
		SkillSlotsContract.SKILL_1,
		SkillSlotsContract.SKILL_2,
		SkillSlotsContract.SKILL_3,
		SkillSlotsContract.SKILL_4,
	]:
		var skill_id: String = str(skill_slots[slot_id])
		var multiplier: float = 1.5 if seen_skills.has(skill_id) else 1.0
		slot_definitions.append({
			"slot_id": slot_id,
			"skill_id": skill_id,
			"energy_cost_multiplier": multiplier,
			"cooldown_multiplier": multiplier,
		})
		seen_skills[skill_id] = true
	return {
		"main_hero_id": main_character_id,
		"sub_hero_id": sub_character_id,
		"main_character_id": main_character_id,
		"sub_character_id": sub_character_id,
		"main_name_key": str(main_character.get("name_key", "")),
		"sub_name_key": str(sub_character.get("name_key", "")),
		"scene_path": str(main_character.get("scene_path", "")),
		"presentation_profile_id": str(main_character.get("presentation_profile_id", "")),
		"composition_element_id": element_resolver.combine(main_element_id, sub_element_id),
		"base_stats": main_character.get("base_stats", {}).duplicate(true),
		"passive_id": str(main_character.get("passive_id", "")),
		"starting_loadout": main_character.get("starting_loadout", {}).duplicate(true),
		"skill_resources": main_character.get("skill_resources", []).duplicate(true),
		"main_character": main_character.duplicate(true),
		"sub_character": sub_character.duplicate(true),
		"palette": {
			"main_primary": str(main_palette.get("primary", "")),
			"sub_primary": str(sub_palette.get("primary", "")),
		},
		"skill_slots": skill_slots,
		"slot_definitions": slot_definitions,
	}


static func _find_character(characters: Array, character_id: String) -> Dictionary:
	for entry_value: Variant in characters:
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value
			if str(entry.get("id", "")) == character_id:
				return entry
	return {}
