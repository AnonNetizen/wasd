extends SmokeHarness


const DATA_REFERENCE_INDEX_BUILDER_SCRIPT := preload(
	"res://scripts/data/data_reference_index_builder.gd"
)


func test_bad_roots_and_collection_types_return_fresh_empty_indexes() -> void:
	assert_eq(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_camera_feedback_ids([]),
		{}
	)
	assert_eq(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_visual_effect_ids({
			"effects": {},
		}),
		{}
	)
	assert_eq(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_character_ids({
			"characters": {},
		}),
		{}
	)
	assert_eq(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_enemy_ids({}),
		{}
	)
	assert_eq(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_spawn_wave_ids_by_mode(
			{}
		),
		{}
	)

	var first: Dictionary = (
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_weapon_ids({})
	)
	first["mutated"] = true
	assert_eq(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_weapon_ids({}),
		{}
	)


func test_camera_index_filters_schema_version_and_keeps_key_order() -> void:
	var data: Variant = JSON.parse_string(
		"{\"second\":{},\"schema_version\":{},"
		+ "\"ignored_wrong_type\":true,\"first\":{},\"\":{}}"
	)
	var index: Dictionary = (
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_camera_feedback_ids(data)
	)

	assert_eq(_string_keys(index), ["second", "first", ""])
	assert_eq(index, {
		"second": true,
		"first": true,
		"": true,
	})


func test_visual_and_presentation_indexes_filter_empty_and_keep_order() -> void:
	var visual_data: Variant = JSON.parse_string(
		"{\"effects\":[{\"id\":\"\"},{\"id\":\"shared\"},"
		+ "{\"id\":\"first\"},{\"id\":\"shared\"},{\"missing\":true},"
		+ "\"wrong_type\"]}"
	)
	var presentation_data: Variant = JSON.parse_string(
		"{\"profiles\":[{\"id\":\"\"},{\"id\":\"shared\"},"
		+ "{\"id\":\"first\"},{\"id\":\"shared\"},{\"missing\":true},"
		+ "\"wrong_type\"]}"
	)
	var visual: Dictionary = (
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_visual_effect_ids(
			visual_data
		)
	)
	var presentation: Dictionary = (
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_presentation_profile_ids(
			presentation_data
		)
	)

	assert_eq(_string_keys(visual), ["shared", "first"])
	assert_eq(visual, {
		"shared": true,
		"first": true,
	})
	assert_eq(_string_keys(presentation), ["shared", "first"])
	assert_eq(presentation, visual)


func test_strict_json_indexes_keep_empty_string_and_reject_other_id_types() -> void:
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_hero_passive_ids({
			"passives": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_weapon_ids({
			"weapons": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_enemy_ai_profile_ids({
			"profiles": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_gear_mod_ids({
			"mods": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_world_event_ids({
			"events": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_active_item_ids({
			"active_items": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_consumable_ids({
			"consumables": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_skill_ids({
			"skills": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_character_ids({
			"characters": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_difficulty_profile_ids({
			"profiles": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_game_mode_ids({
			"modes": _strict_json_entries(),
		})
	)
	_assert_strict_json_index(
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_map_layout_ids({
			"layouts": _strict_json_entries(),
		})
	)


func test_enemy_csv_index_filters_empty_and_folds_duplicates_in_order() -> void:
	var rows: Variant = JSON.parse_string(
		"[{\"id\":\"enemy_b\"},{\"id\":\"\"},{\"id\":\"enemy_a\"},"
		+ "{\"id\":\"enemy_b\"},{},\"wrong_type\"]"
	)
	var index: Dictionary = (
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_enemy_ids(rows)
	)

	assert_eq(_string_keys(index), ["enemy_b", "enemy_a"])
	assert_eq(index, {
		"enemy_b": true,
		"enemy_a": true,
	})


func test_hazard_index_clamps_radius_and_last_write_wins_without_reordering() -> void:
	var rows: Variant = JSON.parse_string(
		"[{\"id\":\"hazard_b\",\"radius_tiles\":\"0\"},"
		+ "{\"id\":\"\",\"radius_tiles\":\"8\"},"
		+ "{\"id\":\"hazard_a\",\"radius_tiles\":\"-2\"},"
		+ "{\"id\":\"hazard_b\",\"radius_tiles\":\"6\"},"
		+ "{\"id\":\"hazard_a\",\"radius_tiles\":\"not_an_int\"},"
		+ "\"wrong_type\"]"
	)
	var index: Dictionary = (
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_hazard_ids(rows)
	)

	assert_eq(_string_keys(index), ["hazard_b", "hazard_a"])
	assert_eq(index, {
		"hazard_b": 6,
		"hazard_a": 1,
	})


func test_wave_index_keeps_nested_order_and_has_no_cross_call_aliases() -> void:
	var rows: Variant = JSON.parse_string(
		"[{\"mode_id\":\"mode_b\",\"id\":\"wave_2\"},"
		+ "{\"mode_id\":\"mode_a\",\"id\":\"wave_3\"},"
		+ "{\"mode_id\":\"\",\"id\":\"ignored\"},"
		+ "{\"mode_id\":\"mode_b\",\"id\":\"\"},"
		+ "{\"mode_id\":\"mode_b\",\"id\":\"wave_1\"},"
		+ "{\"mode_id\":\"mode_b\",\"id\":\"wave_2\"},"
		+ "{\"mode_id\":\"mode_c\",\"id\":\"wave_x\"},"
		+ "\"wrong_type\"]"
	)
	var first: Dictionary = (
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_spawn_wave_ids_by_mode(
			rows
		)
	)

	assert_eq(_string_keys(first), ["mode_b", "mode_a", "mode_c"])
	assert_eq(_string_keys(first["mode_b"] as Dictionary), [
		"wave_2",
		"wave_1",
	])
	assert_eq(first, {
		"mode_b": {"wave_2": true, "wave_1": true},
		"mode_a": {"wave_3": true},
		"mode_c": {"wave_x": true},
	})

	(first["mode_b"] as Dictionary)["mutated"] = true
	assert_false((first["mode_a"] as Dictionary).has("mutated"))
	var second: Dictionary = (
		DATA_REFERENCE_INDEX_BUILDER_SCRIPT.collect_spawn_wave_ids_by_mode(
			rows
		)
	)
	assert_false((second["mode_b"] as Dictionary).has("mutated"))
	assert_eq(_string_keys(second["mode_b"] as Dictionary), [
		"wave_2",
		"wave_1",
	])


func _strict_json_entries() -> Array:
	return [
		{"id": "second"},
		{"id": ""},
		{"id": &"string_name_is_rejected"},
		{"id": 17},
		{"id": "first"},
		{"id": "second"},
		"wrong_type",
	]


func _assert_strict_json_index(index: Dictionary) -> void:
	assert_eq(_string_keys(index), ["second", "", "first"])
	assert_eq(index, {
		"second": true,
		"": true,
		"first": true,
	})


func _string_keys(index: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for raw_key: Variant in index.keys():
		keys.append(String(raw_key))
	return keys
