# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name HeroPassiveCatalogValidator
extends RefCounted
## Validates already loaded hero passive catalog data without owning data sources.


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var passive_count: int = 0


static func validate(
	raw_data: Variant,
	require_locale_key: Callable,
	require_passive_id: Callable,
	require_effect: Callable,
	require_element: Callable,
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
		1,
		report_failure
	) and result.is_valid
	var passives: Array = _require_array(
		"passives",
		payload.get("passives"),
		report_failure
	)
	result.passive_count = passives.size()

	var seen_ids: Dictionary = {}
	for index: int in range(passives.size()):
		result.is_valid = _validate_passive(
			index,
			passives[index],
			seen_ids,
			require_locale_key,
			require_passive_id,
			require_effect,
			require_element,
			report_failure
		) and result.is_valid
	return result


static func _validate_passive(
	index: int,
	raw_passive: Variant,
	seen_ids: Dictionary,
	require_locale_key: Callable,
	require_passive_id: Callable,
	require_effect: Callable,
	require_element: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "passives[%d]" % index
	if not raw_passive is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var passive: Dictionary = raw_passive as Dictionary
	var is_valid: bool = true
	var passive_id: String = String(require_passive_id.call(
		"%s.id" % field,
		passive.get("id")
	))
	# Preserve the legacy helper gap: invalid IDs report through the callback,
	# stay out of duplicate detection, and do not invalidate by themselves.
	if not passive_id.is_empty():
		if seen_ids.has(passive_id):
			_report_failure(
				report_failure,
				"%s.id" % field,
				"unique passive id"
			)
			is_valid = false
		seen_ids[passive_id] = true

	is_valid = bool(require_locale_key.call(
		"%s.name_key" % field,
		passive.get("name_key")
	)) and is_valid
	is_valid = bool(require_locale_key.call(
		"%s.desc_key" % field,
		passive.get("desc_key")
	)) and is_valid
	var effect_id: String = String(require_effect.call(
		"%s.effect" % field,
		passive.get("effect")
	))
	is_valid = not effect_id.is_empty() and is_valid

	var raw_params: Variant = passive.get("params")
	if not raw_params is Dictionary:
		_report_failure(report_failure, "%s.params" % field, "Dictionary")
		return false

	var params: Dictionary = raw_params as Dictionary
	var element_id: String = String(require_element.call(
		"%s.params.element_id" % field,
		params.get("element_id")
	))
	is_valid = not element_id.is_empty() and is_valid
	is_valid = _require_number(
		"%s.params.multiplier" % field,
		params.get("multiplier"),
		0.0,
		1.0,
		report_failure
	) and is_valid
	return is_valid


static func _require_exact_int(
	field: String,
	value: Variant,
	expected: int,
	report_failure: Callable
) -> bool:
	if not _is_int_like(value):
		_report_failure(report_failure, field, "int")
		return false
	if int(value) != expected:
		_report_failure(
			report_failure,
			field,
			"int equal to %d" % expected
		)
		return false
	return true


static func _require_array(
	field: String,
	value: Variant,
	report_failure: Callable
) -> Array:
	if not value is Array:
		_report_failure(report_failure, field, "Array")
		return []
	return value as Array


static func _require_number(
	field: String,
	value: Variant,
	minimum: float,
	maximum: float,
	report_failure: Callable
) -> bool:
	if not value is int and not value is float:
		_report_failure(report_failure, field, "number")
		return false
	var numeric: float = float(value)
	if not is_finite(numeric):
		_report_failure(report_failure, field, "finite number")
		return false
	if numeric < minimum:
		_report_failure(
			report_failure,
			field,
			"number >= %s" % str(minimum)
		)
		return false
	if numeric > maximum:
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
