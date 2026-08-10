# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name DataReferenceIndexBuilder
extends RefCounted
## Builds source-ordered reference indexes from already loaded project data.


static func collect_camera_feedback_ids(data: Variant) -> Dictionary:
	var ids: Dictionary = {}
	if not data is Dictionary:
		return ids
	var payload: Dictionary = data as Dictionary
	for raw_key: Variant in payload.keys():
		var profile_id: String = String(raw_key)
		if profile_id == "schema_version":
			continue
		if payload.get(raw_key) is Dictionary:
			ids[profile_id] = true
	return ids


static func collect_visual_effect_ids(data: Variant) -> Dictionary:
	return _collect_converted_id_array(data, "effects")


static func collect_presentation_profile_ids(data: Variant) -> Dictionary:
	return _collect_converted_id_array(data, "profiles")


static func collect_hero_passive_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "passives")


static func collect_weapon_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "weapons")


static func collect_enemy_ai_profile_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "profiles")


static func collect_enemy_ids(rows: Variant) -> Dictionary:
	return _collect_csv_ids(rows)


static func collect_gear_mod_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "mods")


static func collect_world_event_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "events")


static func collect_hazard_ids(rows: Variant) -> Dictionary:
	var ids: Dictionary = {}
	if not rows is Array:
		return ids
	for raw_row: Variant in rows as Array:
		if not raw_row is Dictionary:
			continue
		var row: Dictionary = raw_row as Dictionary
		var hazard_id: String = String(row.get("id", ""))
		if not hazard_id.is_empty():
			ids[hazard_id] = maxi(
				String(row.get("radius_tiles", "1")).to_int(),
				1
			)
	return ids


static func collect_active_item_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "active_items")


static func collect_consumable_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "consumables")


static func collect_skill_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "skills")


static func collect_character_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "characters")


static func collect_difficulty_profile_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "profiles")


static func collect_game_mode_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "modes")


static func collect_spawn_wave_ids_by_mode(rows: Variant) -> Dictionary:
	var ids_by_mode: Dictionary = {}
	if not rows is Array:
		return ids_by_mode
	for raw_row: Variant in rows as Array:
		if not raw_row is Dictionary:
			continue
		var row: Dictionary = raw_row as Dictionary
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


static func collect_map_layout_ids(data: Variant) -> Dictionary:
	return _collect_strict_string_id_array(data, "layouts")


static func _collect_strict_string_id_array(
	data: Variant,
	collection_key: String
) -> Dictionary:
	var ids: Dictionary = {}
	if not data is Dictionary:
		return ids
	var entries: Variant = (data as Dictionary).get(collection_key)
	if not entries is Array:
		return ids
	for raw_entry: Variant in entries as Array:
		if (
			raw_entry is Dictionary
			and (raw_entry as Dictionary).get("id") is String
		):
			ids[String((raw_entry as Dictionary).get("id"))] = true
	return ids


static func _collect_converted_id_array(
	data: Variant,
	collection_key: String
) -> Dictionary:
	var ids: Dictionary = {}
	if not data is Dictionary:
		return ids
	var entries: Variant = (data as Dictionary).get(collection_key)
	if not entries is Array:
		return ids
	for raw_entry: Variant in entries as Array:
		if not raw_entry is Dictionary:
			continue
		var entry_id: String = String(
			(raw_entry as Dictionary).get("id", "")
		)
		if not entry_id.is_empty():
			ids[entry_id] = true
	return ids


static func _collect_csv_ids(rows: Variant) -> Dictionary:
	var ids: Dictionary = {}
	if not rows is Array:
		return ids
	for raw_row: Variant in rows as Array:
		if not raw_row is Dictionary:
			continue
		var row_id: String = String(
			(raw_row as Dictionary).get("id", "")
		)
		if not row_id.is_empty():
			ids[row_id] = true
	return ids
