# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name CharacterCatalogValidator
extends RefCounted
## Validates already loaded character catalog data without owning data sources.


const CHARACTER_SCENE_PREFIX: String = (
	"res://scenes/gameplay/actors/characters/"
)


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var character_count: int = 0


static func validate(
	raw_data: Variant,
	weapon_ids: Dictionary,
	active_item_ids: Dictionary,
	consumable_ids: Dictionary,
	skill_ids: Dictionary,
	hero_passive_ids: Dictionary,
	require_registered: Callable,
	validate_actor_scene_path: Callable,
	require_locale_key: Callable,
	validate_stat_value: Callable,
	report_failure: Callable
) -> ValidationResult:
	var result: ValidationResult = ValidationResult.new()
	if not raw_data is Dictionary:
		_report_failure(report_failure, "root", "Dictionary")
		result.is_valid = false
		return result

	var payload: Dictionary = raw_data as Dictionary
	result.is_valid = _require_exact_int(
		"schema_version",
		payload.get("schema_version"),
		4,
		report_failure
	) and result.is_valid
	var characters: Array = _require_array(
		"characters",
		payload.get("characters"),
		report_failure
	)
	if characters.is_empty():
		_report_failure(report_failure, "characters", "non-empty Array")
		result.is_valid = false
	result.character_count = characters.size()

	var seen: Dictionary = {}
	for index: int in range(characters.size()):
		result.is_valid = _validate_character(
			index,
			characters[index],
			seen,
			weapon_ids,
			active_item_ids,
			consumable_ids,
			skill_ids,
			hero_passive_ids,
			require_registered,
			validate_actor_scene_path,
			require_locale_key,
			validate_stat_value,
			report_failure
		) and result.is_valid
	return result


static func _validate_character(
	index: int,
	raw_character: Variant,
	seen: Dictionary,
	weapon_ids: Dictionary,
	active_item_ids: Dictionary,
	consumable_ids: Dictionary,
	skill_ids: Dictionary,
	hero_passive_ids: Dictionary,
	require_registered: Callable,
	validate_actor_scene_path: Callable,
	require_locale_key: Callable,
	validate_stat_value: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "characters[%d]" % index
	if not raw_character is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var character: Dictionary = raw_character as Dictionary
	var is_valid: bool = true
	var character_id: String = String(require_registered.call(
		"%s.id" % field,
		character.get("id"),
		"character_ids"
	))
	if not character_id.is_empty():
		if seen.has(character_id):
			_report_failure(
				report_failure,
				"%s.id" % field,
				"unique character id"
			)
			is_valid = false
		seen[character_id] = true
	is_valid = bool(validate_actor_scene_path.call(
		"%s.scene_path" % field,
		character.get("scene_path"),
		CHARACTER_SCENE_PREFIX
	)) and is_valid
	is_valid = bool(require_locale_key.call(
		"%s.name_key" % field,
		character.get("name_key")
	)) and is_valid
	is_valid = bool(require_locale_key.call(
		"%s.desc_key" % field,
		character.get("desc_key")
	)) and is_valid
	if character.has("default_unlocked"):
		is_valid = _require_bool(
			"%s.default_unlocked" % field,
			character.get("default_unlocked"),
			report_failure
		) and is_valid

	var tags: Array = _require_array(
		"%s.tags" % field,
		character.get("tags"),
		report_failure
	)
	is_valid = _validate_registered_string_array(
		"%s.tags" % field,
		tags,
		"content_tags",
		false,
		require_registered,
		report_failure
	) and is_valid
	if not tags.has("tag_character"):
		_report_failure(report_failure, "%s.tags" % field, "tag_character")
		is_valid = false
	is_valid = _validate_registered_string_array(
		"%s.capabilities" % field,
		character.get("capabilities", []),
		"capabilities",
		true,
		require_registered,
		report_failure
	) and is_valid
	is_valid = _require_non_empty_string(
		"%s.control_profile" % field,
		character.get("control_profile"),
		report_failure
	) and is_valid
	is_valid = not String(require_registered.call(
		"%s.element_id" % field,
		character.get("element_id"),
		"elements"
	)).is_empty() and is_valid

	var passive_id: String = String(require_registered.call(
		"%s.passive_id" % field,
		character.get("passive_id"),
		"hero_passive_ids"
	))
	if not passive_id.is_empty() and not hero_passive_ids.has(passive_id):
		_report_failure(
			report_failure,
			"%s.passive_id" % field,
			"passive defined in hero_passives.json"
		)
		is_valid = false
	is_valid = _validate_hero_skills(
		field,
		character.get("hero_skill_ids"),
		skill_ids,
		require_registered,
		report_failure
	) and is_valid
	is_valid = _validate_palette(
		"%s.palette" % field,
		character.get("palette"),
		report_failure
	) and is_valid
	is_valid = _validate_starting_loadout(
		"%s.starting_loadout" % field,
		character.get("starting_loadout"),
		weapon_ids,
		active_item_ids,
		consumable_ids,
		report_failure
	) and is_valid
	is_valid = _validate_skill_resources(
		"%s.skill_resources" % field,
		character.get("skill_resources", []),
		require_registered,
		report_failure
	) and is_valid
	is_valid = _validate_base_stats(
		"%s.base_stats" % field,
		character.get("base_stats"),
		validate_stat_value,
		report_failure
	) and is_valid
	return is_valid


static func _validate_hero_skills(
	character_field: String,
	raw_data: Variant,
	skill_ids: Dictionary,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "%s.hero_skill_ids" % character_field
	var values: Array = _require_array(field, raw_data, report_failure)
	var is_valid: bool = true
	if values.size() != 2:
		_report_failure(
			report_failure,
			field,
			"Array with exactly two skill ids"
		)
		is_valid = false
	var seen: Dictionary = {}
	for index: int in range(values.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var skill_id: String = String(require_registered.call(
			item_field,
			values[index],
			"skill_ids"
		))
		if skill_id.is_empty():
			is_valid = false
			continue
		if seen.has(skill_id):
			_report_failure(report_failure, item_field, "unique hero skill id")
			is_valid = false
		seen[skill_id] = true
		if not skill_ids.has(skill_id):
			_report_failure(
				report_failure,
				item_field,
				"skill defined in skills.json"
			)
			is_valid = false
	return is_valid


static func _validate_palette(
	field: String,
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false
	var palette: Dictionary = raw_data as Dictionary
	var is_valid: bool = _validate_exact_dictionary_keys(
		field,
		palette,
		["primary"],
		report_failure
	)
	var primary: Variant = palette.get("primary")
	is_valid = _require_non_empty_string(
		"%s.primary" % field,
		primary,
		report_failure
	) and is_valid
	if primary is String and not Color.html_is_valid(String(primary)):
		_report_failure(
			report_failure,
			"%s.primary" % field,
			"valid HTML color"
		)
		is_valid = false
	return is_valid


static func _validate_starting_loadout(
	field: String,
	raw_data: Variant,
	weapon_ids: Dictionary,
	active_item_ids: Dictionary,
	consumable_ids: Dictionary,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false
	var loadout: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	var weapon_id: String = String(loadout.get("weapon_id", ""))
	is_valid = _require_non_empty_string(
		"%s.weapon_id" % field,
		loadout.get("weapon_id"),
		report_failure
	) and is_valid
	if not weapon_id.is_empty() and not weapon_ids.has(weapon_id):
		_report_failure(
			report_failure,
			"%s.weapon_id" % field,
			"weapon defined in weapons.json"
		)
		is_valid = false
	var active_item_id: String = String(loadout.get("active_item_id", ""))
	is_valid = _require_non_empty_string(
		"%s.active_item_id" % field,
		loadout.get("active_item_id"),
		report_failure
	) and is_valid
	if not active_item_id.is_empty() and not active_item_ids.has(active_item_id):
		_report_failure(
			report_failure,
			"%s.active_item_id" % field,
			"active item defined in active_items.json"
		)
		is_valid = false

	var consumables: Array = _require_array(
		"%s.consumable_ids" % field,
		loadout.get("consumable_ids"),
		report_failure
	)
	var seen: Dictionary = {}
	for index: int in range(consumables.size()):
		var item_field: String = "%s.consumable_ids[%d]" % [field, index]
		var consumable_id: String = String(consumables[index])
		is_valid = _require_non_empty_string(
			item_field,
			consumables[index],
			report_failure
		) and is_valid
		if not consumable_id.is_empty():
			if seen.has(consumable_id):
				_report_failure(report_failure, item_field, "unique consumable id")
				is_valid = false
			seen[consumable_id] = true
			if not consumable_ids.has(consumable_id):
				_report_failure(
					report_failure,
					item_field,
					"consumable defined in consumables.json"
				)
				is_valid = false
	if loadout.has("skill_ids"):
		_report_failure(
			report_failure,
			"%s.skill_ids" % field,
			"removed field; use character.hero_skill_ids"
		)
		is_valid = false
	return is_valid


static func _validate_skill_resources(
	field: String,
	raw_data: Variant,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var resources: Array = _require_array(field, raw_data, report_failure)
	var is_valid: bool = true
	var seen: Dictionary = {}
	for index: int in range(resources.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var raw_resource: Variant = resources[index]
		if not raw_resource is Dictionary:
			_report_failure(report_failure, item_field, "Dictionary")
			is_valid = false
			continue
		var resource: Dictionary = raw_resource as Dictionary
		var resource_id: String = String(require_registered.call(
			"%s.id" % item_field,
			resource.get("id"),
			"skill_resources"
		))
		if not resource_id.is_empty():
			if seen.has(resource_id):
				_report_failure(
					report_failure,
					"%s.id" % item_field,
					"unique skill resource id"
				)
				is_valid = false
			seen[resource_id] = true
		var max_stat: String = String(require_registered.call(
			"%s.max_stat" % item_field,
			resource.get("max_stat"),
			"stats"
		))
		is_valid = not max_stat.is_empty() and is_valid
		is_valid = _require_number(
			"%s.start_ratio" % item_field,
			resource.get("start_ratio"),
			0.0,
			1.0,
			false,
			report_failure
		) and is_valid
		is_valid = _require_number(
			"%s.regen_per_second" % item_field,
			resource.get("regen_per_second"),
			0.0,
			null,
			false,
			report_failure
		) and is_valid
	return is_valid


static func _validate_base_stats(
	field: String,
	raw_data: Variant,
	validate_stat_value: Callable,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary or (raw_data as Dictionary).is_empty():
		_report_failure(report_failure, field, "non-empty Dictionary")
		return false
	var stats: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	for raw_stat: Variant in stats.keys():
		var stat: String = String(raw_stat)
		is_valid = bool(validate_stat_value.call(
			"%s.%s" % [field, stat],
			stat,
			stats[raw_stat]
		)) and is_valid
	return is_valid


static func _validate_registered_string_array(
	field: String,
	raw_data: Variant,
	contract_id: String,
	allow_empty: bool,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var values: Array = _require_array(field, raw_data, report_failure)
	var is_valid: bool = true
	if not allow_empty and values.is_empty():
		_report_failure(report_failure, field, "non-empty Array")
		is_valid = false
	var seen: Dictionary = {}
	for index: int in range(values.size()):
		var value: String = String(require_registered.call(
			"%s[%d]" % [field, index],
			values[index],
			contract_id
		))
		if not value.is_empty():
			if seen.has(value):
				_report_failure(
					report_failure,
					"%s[%d]" % [field, index],
					"unique id"
				)
				is_valid = false
			seen[value] = true
	return is_valid


static func _validate_exact_dictionary_keys(
	field: String,
	data: Dictionary,
	expected_keys: Array[String],
	report_failure: Callable
) -> bool:
	var is_valid: bool = true
	for expected_key: String in expected_keys:
		if not data.has(expected_key):
			_report_failure(
				report_failure,
				"%s.%s" % [field, expected_key],
				"required field"
			)
			is_valid = false
	for raw_key: Variant in data.keys():
		var key: String = String(raw_key)
		if not expected_keys.has(key):
			_report_failure(
				report_failure,
				"%s.%s" % [field, key],
				"allowed schema field"
			)
			is_valid = false
	return is_valid


static func _require_array(
	field: String,
	value: Variant,
	report_failure: Callable
) -> Array:
	if not value is Array:
		_report_failure(report_failure, field, "Array")
		return []
	return value as Array


static func _require_non_empty_string(
	field: String,
	value: Variant,
	report_failure: Callable
) -> bool:
	if not value is String or String(value).is_empty():
		_report_failure(report_failure, field, "non-empty string")
		return false
	return true


static func _require_bool(
	field: String,
	value: Variant,
	report_failure: Callable
) -> bool:
	if not value is bool:
		_report_failure(report_failure, field, "bool")
		return false
	return true


static func _require_exact_int(
	field: String,
	value: Variant,
	expected: int,
	report_failure: Callable
) -> bool:
	if not _is_int_like(value):
		_report_failure(report_failure, field, "int equal to %d" % expected)
		return false
	if int(value) != expected:
		_report_failure(report_failure, field, "int equal to %d" % expected)
		return false
	return true


static func _require_number(
	field: String,
	value: Variant,
	minimum: Variant,
	maximum: Variant,
	exclusive_minimum: bool,
	report_failure: Callable
) -> bool:
	if not value is int and not value is float:
		_report_failure(report_failure, field, "number")
		return false
	var numeric: float = float(value)
	if not is_finite(numeric):
		_report_failure(report_failure, field, "finite number")
		return false
	if minimum != null:
		var minimum_value: float = float(minimum)
		if exclusive_minimum and numeric <= minimum_value:
			_report_failure(
				report_failure,
				field,
				"number > %s" % str(minimum)
			)
			return false
		if not exclusive_minimum and numeric < minimum_value:
			_report_failure(
				report_failure,
				field,
				"number >= %s" % str(minimum)
			)
			return false
	if maximum != null and numeric > float(maximum):
		_report_failure(
			report_failure,
			field,
			"number <= %s" % str(maximum)
		)
		return false
	return true


static func _is_int_like(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_equal_approx(float(value), float(int(value)))
	return false


static func _report_failure(
	report_failure: Callable,
	field: String,
	expected: String
) -> void:
	report_failure.call(field, expected)
