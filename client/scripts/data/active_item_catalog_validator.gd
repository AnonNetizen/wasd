# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name ActiveItemCatalogValidator
extends RefCounted
## Validates already loaded active item catalog data without owning data sources.


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var item_count: int = 0


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
	var active_items: Array = _require_array(
		"active_items",
		payload.get("active_items"),
		report_failure
	)
	if active_items.is_empty():
		_report_failure(report_failure, "active_items", "non-empty Array")
		result.is_valid = false
	result.item_count = active_items.size()

	var seen_ids: Dictionary = {}
	for index: int in range(active_items.size()):
		result.is_valid = _validate_item(
			index,
			active_items[index],
			seen_ids,
			require_locale_key,
			require_content_tag,
			require_effect,
			report_failure
		) and result.is_valid
	return result


static func _validate_item(
	index: int,
	raw_item: Variant,
	seen_ids: Dictionary,
	require_locale_key: Callable,
	require_content_tag: Callable,
	require_effect: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "active_items[%d]" % index
	if not raw_item is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var item: Dictionary = raw_item as Dictionary
	var is_valid: bool = _require_non_empty_string(
		"%s.id" % field,
		item.get("id"),
		report_failure
	)
	var item_id: String = String(item.get("id", ""))
	if not item_id.is_empty():
		if seen_ids.has(item_id):
			_report_failure(
				report_failure,
				"%s.id" % field,
				"unique active item id"
			)
			is_valid = false
		seen_ids[item_id] = true

	is_valid = bool(require_locale_key.call(
		"%s.name_key" % field,
		item.get("name_key")
	)) and is_valid
	is_valid = bool(require_locale_key.call(
		"%s.desc_key" % field,
		item.get("desc_key")
	)) and is_valid
	is_valid = _require_bool(
		"%s.default_unlocked" % field,
		item.get("default_unlocked"),
		report_failure
	) and is_valid

	var tags: Array = _require_array(
		"%s.tags" % field,
		item.get("tags"),
		report_failure
	)
	is_valid = _validate_registered_tags(
		"%s.tags" % field,
		tags,
		require_content_tag,
		report_failure
	) and is_valid
	if not tags.has("tag_active_item"):
		_report_failure(report_failure, "%s.tags" % field, "tag_active_item")
		is_valid = false

	is_valid = _validate_charge(
		"%s.charge" % field,
		item.get("charge"),
		report_failure
	) and is_valid
	is_valid = _validate_use_effects(
		"%s.use_effects" % field,
		item.get("use_effects"),
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


static func _validate_charge(
	field: String,
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var charge: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	var mode: String = String(charge.get("mode", ""))
	is_valid = _require_non_empty_string(
		"%s.mode" % field,
		charge.get("mode"),
		report_failure
	) and is_valid
	if not mode.is_empty() and mode != "cooldown":
		_report_failure(report_failure, "%s.mode" % field, "cooldown")
		is_valid = false
	is_valid = _require_number(
		"%s.cooldown" % field,
		charge.get("cooldown"),
		0.0,
		true,
		report_failure
	) and is_valid
	is_valid = _require_int(
		"%s.max_charges" % field,
		charge.get("max_charges"),
		1,
		report_failure
	) and is_valid
	is_valid = _require_int(
		"%s.start_charges" % field,
		charge.get("start_charges"),
		0,
		report_failure
	) and is_valid

	var max_charges: Variant = charge.get("max_charges")
	var start_charges: Variant = charge.get("start_charges")
	if (
		_is_int_like(max_charges)
		and _is_int_like(start_charges)
		and int(start_charges) > int(max_charges)
	):
		_report_failure(
			report_failure,
			"%s.start_charges" % field,
			"<= max_charges"
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


static func _require_number(
	field: String,
	value: Variant,
	minimum: Variant,
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
