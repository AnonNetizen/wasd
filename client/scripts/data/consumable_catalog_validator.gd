# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name ConsumableCatalogValidator
extends RefCounted
## Validates already loaded consumable catalog data without owning data sources.


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var consumable_count: int = 0
	var has_consumable_count: bool = false


static func validate(
	raw_data: Variant,
	require_locale_key: Callable,
	require_content_tag: Callable,
	require_effect: Callable,
	report_failure: Callable
) -> ValidationResult:
	var result: ValidationResult = ValidationResult.new()
	if not raw_data is Dictionary:
		_report_failure(report_failure, "root", "Dictionary")
		result.is_valid = false
		return result

	var payload: Dictionary = raw_data as Dictionary
	result.is_valid = _require_int(
		"schema_version",
		payload.get("schema_version"),
		1,
		report_failure
	) and result.is_valid
	var consumables: Array = _require_array(
		"consumables",
		payload.get("consumables"),
		report_failure
	)
	if consumables.is_empty():
		_report_failure(report_failure, "consumables", "non-empty Array")
		result.is_valid = false
	result.consumable_count = consumables.size()
	result.has_consumable_count = true

	var seen_ids: Dictionary = {}
	for index: int in range(consumables.size()):
		result.is_valid = _validate_consumable(
			index,
			consumables[index],
			seen_ids,
			require_locale_key,
			require_content_tag,
			require_effect,
			report_failure
		) and result.is_valid
	return result


static func _validate_consumable(
	index: int,
	raw_consumable: Variant,
	seen_ids: Dictionary,
	require_locale_key: Callable,
	require_content_tag: Callable,
	require_effect: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "consumables[%d]" % index
	if not raw_consumable is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var consumable: Dictionary = raw_consumable as Dictionary
	var is_valid: bool = _require_non_empty_string(
		"%s.id" % field,
		consumable.get("id"),
		report_failure
	)
	var consumable_id: String = String(consumable.get("id", ""))
	if not consumable_id.is_empty():
		if seen_ids.has(consumable_id):
			_report_failure(
				report_failure,
				"%s.id" % field,
				"unique consumable id"
			)
			is_valid = false
		seen_ids[consumable_id] = true

	is_valid = bool(require_locale_key.call(
		"%s.name_key" % field,
		consumable.get("name_key")
	)) and is_valid
	is_valid = bool(require_locale_key.call(
		"%s.desc_key" % field,
		consumable.get("desc_key")
	)) and is_valid
	is_valid = _require_bool(
		"%s.default_unlocked" % field,
		consumable.get("default_unlocked"),
		report_failure
	) and is_valid

	var tags: Array = _require_array(
		"%s.tags" % field,
		consumable.get("tags"),
		report_failure
	)
	is_valid = _validate_registered_tags(
		"%s.tags" % field,
		tags,
		require_content_tag,
		report_failure
	) and is_valid
	if not tags.has("tag_consumable"):
		_report_failure(report_failure, "%s.tags" % field, "tag_consumable")
		is_valid = false

	is_valid = _validate_stack(
		"%s.stack" % field,
		consumable.get("stack"),
		report_failure
	) and is_valid
	is_valid = _validate_use_effects(
		"%s.use_effects" % field,
		consumable.get("use_effects"),
		require_effect,
		report_failure
	) and is_valid
	return is_valid


static func _validate_registered_tags(
	field: String,
	tags: Array,
	require_content_tag: Callable,
	report_failure: Callable
) -> bool:
	var is_valid: bool = true
	if tags.is_empty():
		_report_failure(report_failure, field, "non-empty Array")
		is_valid = false

	var seen: Dictionary = {}
	for index: int in range(tags.size()):
		var tag: String = String(require_content_tag.call(
			"%s[%d]" % [field, index],
			tags[index]
		))
		# Preserve the legacy helper's bool gap: an unknown tag reports an
		# error and stays out of duplicate detection without invalidating the
		# catalog by itself.
		if not tag.is_empty():
			if seen.has(tag):
				_report_failure(
					report_failure,
					"%s[%d]" % [field, index],
					"unique id"
				)
				is_valid = false
			seen[tag] = true
	return is_valid


static func _validate_stack(
	field: String,
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var stack: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	is_valid = _require_int(
		"%s.max_stack" % field,
		stack.get("max_stack"),
		1,
		report_failure
	) and is_valid
	is_valid = _require_int(
		"%s.start_count" % field,
		stack.get("start_count"),
		0,
		report_failure
	) and is_valid
	is_valid = _require_int(
		"%s.pickup_count" % field,
		stack.get("pickup_count"),
		1,
		report_failure
	) and is_valid

	var max_stack: Variant = stack.get("max_stack")
	var start_count: Variant = stack.get("start_count")
	var pickup_count: Variant = stack.get("pickup_count")
	if (
		_is_int_like(max_stack)
		and _is_int_like(start_count)
		and int(start_count) > int(max_stack)
	):
		_report_failure(
			report_failure,
			"%s.start_count" % field,
			"<= max_stack"
		)
		is_valid = false
	if (
		_is_int_like(max_stack)
		and _is_int_like(pickup_count)
		and int(pickup_count) > int(max_stack)
	):
		_report_failure(
			report_failure,
			"%s.pickup_count" % field,
			"<= max_stack"
		)
		is_valid = false
	return is_valid


static func _validate_use_effects(
	field: String,
	raw_data: Variant,
	require_effect: Callable,
	report_failure: Callable
) -> bool:
	var effects: Array = _require_array(field, raw_data, report_failure)
	var is_valid: bool = true
	if effects.is_empty():
		_report_failure(report_failure, field, "non-empty Array")
		is_valid = false
	for index: int in range(effects.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var raw_effect: Variant = effects[index]
		if not raw_effect is Dictionary:
			_report_failure(report_failure, item_field, "Dictionary")
			is_valid = false
			continue
		var effect: Dictionary = raw_effect as Dictionary
		var effect_id: String = String(require_effect.call(
			"%s.effect" % item_field,
			effect.get("effect")
		))
		is_valid = not effect_id.is_empty() and is_valid
		if not effect.get("params") is Dictionary:
			_report_failure(
				report_failure,
				"%s.params" % item_field,
				"Dictionary"
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


static func _require_int(
	field: String,
	value: Variant,
	minimum: Variant,
	report_failure: Callable
) -> bool:
	if not _is_int_like(value):
		_report_failure(report_failure, field, "int")
		return false
	if minimum != null and int(value) < int(minimum):
		_report_failure(
			report_failure,
			field,
			"int >= %d" % int(minimum)
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
