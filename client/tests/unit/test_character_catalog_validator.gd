extends SmokeHarness


const CHARACTER_CATALOG_VALIDATOR := preload(
	"res://scripts/data/character_catalog_validator.gd"
)

var _failures: Array[String] = []
var _events: Array[String] = []
var _contract_values: Dictionary = {}
var _weapon_ids: Dictionary = {"weapon_main": true}
var _active_item_ids: Dictionary = {"active_main": true}
var _consumable_ids: Dictionary = {"consumable_main": true}
var _skill_ids: Dictionary = {"skill_a": true, "skill_b": true}
var _hero_passive_ids: Dictionary = {"passive_main": true}
var _rejected_scenes: Dictionary = {}
var _rejected_locale_keys: Dictionary = {}
var _rejected_stats: Dictionary = {}


func before_each() -> void:
	super()
	_failures.clear()
	_events.clear()
	_rejected_scenes.clear()
	_rejected_locale_keys.clear()
	_rejected_stats.clear()
	_contract_values = {
		"character_ids": {"character_main": true},
		"content_tags": {"tag_character": true},
		"capabilities": {"can_move": true},
		"elements": {"element_physical": true},
		"hero_passive_ids": {"passive_main": true},
		"skill_ids": {"skill_a": true, "skill_b": true},
		"skill_resources": {"energy": true},
		"stats": {"max_energy": true},
	}
	_weapon_ids = {"weapon_main": true}
	_active_item_ids = {"active_main": true}
	_consumable_ids = {"consumable_main": true}
	_skill_ids = {"skill_a": true, "skill_b": true}
	_hero_passive_ids = {"passive_main": true}


func test_canonical_root_returns_count_and_callback_order() -> void:
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(
		_valid_root()
	)

	assert_true(result.is_valid)
	assert_eq(result.character_count, 1)
	assert_eq(_failures, [])
	assert_eq(_events, [
		"contract|characters[0].id|character_ids|character_main",
		"scene|characters[0].scene_path|res://scenes/gameplay/actors/characters/character_main.tscn|res://scenes/gameplay/actors/characters/",
		"locale|characters[0].name_key|character.main.name",
		"locale|characters[0].desc_key|character.main.desc",
		"contract|characters[0].tags[0]|content_tags|tag_character",
		"contract|characters[0].capabilities[0]|capabilities|can_move",
		"contract|characters[0].element_id|elements|element_physical",
		"contract|characters[0].passive_id|hero_passive_ids|passive_main",
		"contract|characters[0].hero_skill_ids[0]|skill_ids|skill_a",
		"contract|characters[0].hero_skill_ids[1]|skill_ids|skill_b",
		"contract|characters[0].skill_resources[0].id|skill_resources|energy",
		"contract|characters[0].skill_resources[0].max_stat|stats|max_energy",
		"stat|characters[0].base_stats.max_hp|max_hp|100.0",
		"stat|characters[0].base_stats.move_speed|move_speed|200.0",
	])


func test_root_schema_shape_and_raw_count_keep_legacy_order() -> void:
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate([])
	assert_false(result.is_valid)
	assert_eq(result.character_count, 0)
	assert_eq(_failures, ["root|Dictionary"])
	assert_eq(_events, [])

	_clear_diagnostics()
	result = _validate({"schema_version": 4.0, "characters": "bad"})
	assert_false(result.is_valid)
	assert_eq(result.character_count, 0)
	assert_eq(_failures, [
		"characters|Array",
		"characters|non-empty Array",
	])

	_clear_diagnostics()
	result = _validate({"schema_version": 5, "characters": [null]})
	assert_false(result.is_valid)
	assert_eq(result.character_count, 1)
	assert_eq(_failures, [
		"schema_version|int equal to 4",
		"characters[0]|Dictionary",
	])


func test_contract_diagnostic_only_gaps_preserve_true_result() -> void:
	var character: Dictionary = _valid_character()
	character["id"] = "unknown_character"
	character["tags"] = ["tag_character", "unknown_tag"]
	character["capabilities"] = ["unknown_capability"]
	character["passive_id"] = "unknown_passive"
	character["skill_resources"][0]["id"] = "unknown_resource"
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([character])
	)

	assert_true(result.is_valid)
	assert_eq(_failures, [
		"characters[0].id|registered id in character_ids",
		"characters[0].tags[1]|registered id in content_tags",
		"characters[0].capabilities[0]|registered id in capabilities",
		"characters[0].passive_id|registered id in hero_passive_ids",
		"characters[0].skill_resources[0].id|registered id in skill_resources",
	])


func test_character_callbacks_fail_but_later_fields_still_run() -> void:
	var character: Dictionary = _valid_character()
	_rejected_scenes[character["scene_path"]] = true
	_rejected_locale_keys[character["name_key"]] = true
	_rejected_stats["move_speed"] = true
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([character])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"characters[0].scene_path|scene callback",
		"characters[0].name_key|locale callback",
		"characters[0].base_stats.move_speed|stat callback",
	])
	assert_true(_events.has(
		"contract|characters[0].skill_resources[0].max_stat|stats|max_energy"
	))
	assert_eq(_events[-1], (
		"stat|characters[0].base_stats.move_speed|move_speed|200.0"
	))


func test_duplicate_id_element_passive_and_hero_skill_rules() -> void:
	var first: Dictionary = _valid_character()
	var second: Dictionary = _valid_character()
	_contract_values["hero_passive_ids"]["passive_external"] = true
	_contract_values["skill_ids"]["skill_external"] = true
	second["element_id"] = "unknown_element"
	second["passive_id"] = "passive_external"
	second["hero_skill_ids"] = ["skill_a", "skill_a", "skill_external"]
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([first, second])
	)

	assert_false(result.is_valid)
	assert_eq(result.character_count, 2)
	assert_eq(_failures, [
		"characters[1].id|unique character id",
		"characters[1].element_id|registered id in elements",
		"characters[1].passive_id|passive defined in hero_passives.json",
		"characters[1].hero_skill_ids|Array with exactly two skill ids",
		"characters[1].hero_skill_ids[1]|unique hero skill id",
		"characters[1].hero_skill_ids[2]|skill defined in skills.json",
	])


func test_palette_exact_keys_color_and_character_extras() -> void:
	var character: Dictionary = _valid_character()
	character["future"] = true
	character["palette"] = {"future": true, "primary": "not-a-color"}
	var root: Dictionary = _root([character])
	root["future"] = true
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(
		root
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"characters[0].palette.future|allowed schema field",
		"characters[0].palette.primary|valid HTML color",
	])

	_clear_diagnostics()
	character["palette"] = null
	result = _validate(_root([character]))
	assert_false(result.is_valid)
	assert_eq(_failures, ["characters[0].palette|Dictionary"])


func test_starting_loadout_references_duplicates_and_removed_field() -> void:
	var character: Dictionary = _valid_character()
	character["starting_loadout"] = {
		"weapon_id": "weapon_external",
		"active_item_id": "active_external",
		"consumable_ids": ["consumable_main", "consumable_main", "other"],
		"skill_ids": [],
	}
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([character])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"characters[0].starting_loadout.weapon_id|weapon defined in weapons.json",
		"characters[0].starting_loadout.active_item_id|active item defined in active_items.json",
		"characters[0].starting_loadout.consumable_ids[1]|unique consumable id",
		"characters[0].starting_loadout.consumable_ids[2]|consumable defined in consumables.json",
		"characters[0].starting_loadout.skill_ids|removed field; use character.hero_skill_ids",
	])


func test_array_shape_diagnostic_only_gaps_remain_local() -> void:
	var character: Dictionary = _valid_character()
	character["capabilities"] = "bad"
	character["starting_loadout"]["consumable_ids"] = "bad"
	character["skill_resources"] = "bad"
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([character])
	)

	assert_true(result.is_valid)
	assert_eq(_failures, [
		"characters[0].capabilities|Array",
		"characters[0].starting_loadout.consumable_ids|Array",
		"characters[0].skill_resources|Array",
	])


func test_skill_resources_and_base_stats_keep_source_order() -> void:
	var character: Dictionary = _valid_character()
	character["skill_resources"] = [
		{"id": "energy", "max_stat": "max_energy", "start_ratio": -0.1, "regen_per_second": -1.0},
		{"id": "energy", "max_stat": "unknown_stat", "start_ratio": 1.1, "regen_per_second": NAN},
	]
	character["base_stats"] = {"move_speed": 200.0, "max_hp": 100.0}
	_rejected_stats["move_speed"] = true
	var result: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([character])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"characters[0].skill_resources[0].start_ratio|number >= 0.0",
		"characters[0].skill_resources[0].regen_per_second|number >= 0.0",
		"characters[0].skill_resources[1].id|unique skill resource id",
		"characters[0].skill_resources[1].max_stat|registered id in stats",
		"characters[0].skill_resources[1].start_ratio|number <= 1.0",
		"characters[0].skill_resources[1].regen_per_second|finite number",
		"characters[0].base_stats.move_speed|stat callback",
	])
	assert_eq(_events[-2], (
		"stat|characters[0].base_stats.move_speed|move_speed|200.0"
	))
	assert_eq(_events[-1], (
		"stat|characters[0].base_stats.max_hp|max_hp|100.0"
	))


func test_calls_are_stateless_and_do_not_mutate_inputs() -> void:
	var root: Dictionary = _valid_root()
	var before: Dictionary = root.duplicate(true)
	var first: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(root)
	assert_true(first.is_valid)
	assert_eq(root, before)

	_clear_diagnostics()
	var second: CHARACTER_CATALOG_VALIDATOR.ValidationResult = _validate(root)
	assert_true(second.is_valid)
	assert_eq(second.character_count, 1)
	assert_eq(root, before)


func _validate(raw_data: Variant) -> CHARACTER_CATALOG_VALIDATOR.ValidationResult:
	return CHARACTER_CATALOG_VALIDATOR.validate(
		raw_data,
		_weapon_ids,
		_active_item_ids,
		_consumable_ids,
		_skill_ids,
		_hero_passive_ids,
		Callable(self, "_require_registered"),
		Callable(self, "_validate_scene"),
		Callable(self, "_require_locale_key"),
		Callable(self, "_validate_stat_value"),
		Callable(self, "_record_failure")
	)


func _require_registered(
	field: String,
	value: Variant,
	contract_id: String
) -> String:
	var text_value: String = String(value) if value is String else ""
	_events.append(
		"contract|%s|%s|%s" % [field, contract_id, text_value]
	)
	var values: Dictionary = _contract_values.get(contract_id, {})
	if text_value.is_empty() or not values.has(text_value):
		_record_failure(field, "registered id in %s" % contract_id)
		return ""
	return text_value


func _validate_scene(
	field: String,
	value: Variant,
	required_prefix: String
) -> bool:
	var path: String = String(value) if value is String else ""
	_events.append("scene|%s|%s|%s" % [field, path, required_prefix])
	if path.is_empty() or _rejected_scenes.has(path):
		_record_failure(field, "scene callback")
		return false
	return true


func _require_locale_key(field: String, value: Variant) -> bool:
	var key: String = String(value) if value is String else ""
	_events.append("locale|%s|%s" % [field, key])
	if key.is_empty() or _rejected_locale_keys.has(key):
		_record_failure(field, "locale callback")
		return false
	return true


func _validate_stat_value(
	field: String,
	stat_id: String,
	value: Variant
) -> bool:
	_events.append("stat|%s|%s|%s" % [field, stat_id, str(value)])
	if _rejected_stats.has(stat_id):
		_record_failure(field, "stat callback")
		return false
	return true


func _record_failure(field: String, expected: String) -> bool:
	_failures.append("%s|%s" % [field, expected])
	return false


func _clear_diagnostics() -> void:
	_failures.clear()
	_events.clear()


func _valid_root() -> Dictionary:
	return _root([_valid_character()])


func _root(characters: Array) -> Dictionary:
	return {"schema_version": 4, "characters": characters}


func _valid_character() -> Dictionary:
	return {
		"id": "character_main",
		"scene_path": (
			"res://scenes/gameplay/actors/characters/character_main.tscn"
		),
		"name_key": "character.main.name",
		"desc_key": "character.main.desc",
		"default_unlocked": true,
		"tags": ["tag_character"],
		"capabilities": ["can_move"],
		"control_profile": "player",
		"element_id": "element_physical",
		"passive_id": "passive_main",
		"hero_skill_ids": ["skill_a", "skill_b"],
		"palette": {"primary": "#68BCDD"},
		"starting_loadout": {
			"weapon_id": "weapon_main",
			"active_item_id": "active_main",
			"consumable_ids": ["consumable_main"],
		},
		"skill_resources": [
			{
				"id": "energy",
				"max_stat": "max_energy",
				"start_ratio": 0.5,
				"regen_per_second": 1.0,
			},
		],
		"base_stats": {"max_hp": 100.0, "move_speed": 200.0},
	}
