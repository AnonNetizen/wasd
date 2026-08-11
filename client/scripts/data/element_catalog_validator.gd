# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name ElementCatalogValidator
extends RefCounted
## Validates already loaded element catalog data without owning data sources.


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var element_count: int = 0
	var combination_count: int = 0


static func validate(
	raw_data: Variant,
	require_locale_key: Callable,
	require_element_id: Callable,
	list_registered_element_ids: Callable,
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
	var neutral_element_id: String = String(require_element_id.call(
		"neutral_element_id",
		payload.get("neutral_element_id")
	))
	result.is_valid = not neutral_element_id.is_empty() and result.is_valid
	if not payload.get("unmatched_result") is String:
		_report_failure(report_failure, "unmatched_result", "String")
		result.is_valid = false

	var elements: Array = _require_array(
		"elements",
		payload.get("elements"),
		report_failure
	)
	result.element_count = elements.size()
	var seen_element_ids: Dictionary = {}
	for index: int in range(elements.size()):
		result.is_valid = _validate_element(
			index,
			elements[index],
			seen_element_ids,
			require_locale_key,
			require_element_id,
			report_failure
		) and result.is_valid

	var registered_element_ids: Array = (
		list_registered_element_ids.call() as Array
	)
	for registered_element: Variant in registered_element_ids:
		if not seen_element_ids.has(String(registered_element)):
			_report_failure(
				report_failure,
				"elements",
				"definition for %s" % String(registered_element)
			)
			result.is_valid = false

	var combinations: Array = _require_array(
		"combinations",
		payload.get("combinations"),
		report_failure
	)
	result.combination_count = combinations.size()
	var seen_pairs: Dictionary = {}
	for index: int in range(combinations.size()):
		result.is_valid = _validate_combination(
			index,
			combinations[index],
			seen_pairs,
			require_element_id,
			report_failure
		) and result.is_valid
	return result


static func _validate_element(
	index: int,
	raw_element: Variant,
	seen_element_ids: Dictionary,
	require_locale_key: Callable,
	require_element_id: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "elements[%d]" % index
	if not raw_element is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var element: Dictionary = raw_element as Dictionary
	var is_valid: bool = true
	var element_id: String = String(require_element_id.call(
		"%s.id" % field,
		element.get("id")
	))
	# Preserve the legacy helper gap: invalid IDs only diagnose, stay out of
	# duplicate detection, and do not invalidate by themselves.
	if not element_id.is_empty():
		if seen_element_ids.has(element_id):
			_report_failure(
				report_failure,
				"%s.id" % field,
				"unique element id"
			)
			is_valid = false
		seen_element_ids[element_id] = true

	is_valid = bool(require_locale_key.call(
		"%s.name_key" % field,
		element.get("name_key")
	)) and is_valid
	var kind: String = String(element.get("kind", ""))
	if not ["neutral", "primary", "composite"].has(kind):
		_report_failure(
			report_failure,
			"%s.kind" % field,
			"neutral, primary, or composite"
		)
		is_valid = false
	is_valid = _validate_registered_element_array(
		"%s.components" % field,
		element.get("components", []),
		require_element_id,
		report_failure
	) and is_valid
	return is_valid


static func _validate_registered_element_array(
	field: String,
	raw_values: Variant,
	require_element_id: Callable,
	report_failure: Callable
) -> bool:
	var values: Array = _require_array(field, raw_values, report_failure)
	var is_valid: bool = true
	var seen_ids: Dictionary = {}
	for index: int in range(values.size()):
		var value: String = String(require_element_id.call(
			"%s[%d]" % [field, index],
			values[index]
		))
		# Invalid component IDs keep the same diagnostic-only compatibility gap.
		if not value.is_empty():
			if seen_ids.has(value):
				_report_failure(
					report_failure,
					"%s[%d]" % [field, index],
					"unique id"
				)
				is_valid = false
			seen_ids[value] = true
	return is_valid


static func _validate_combination(
	index: int,
	raw_combination: Variant,
	seen_pairs: Dictionary,
	require_element_id: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "combinations[%d]" % index
	if not raw_combination is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var combination: Dictionary = raw_combination as Dictionary
	var is_valid: bool = true
	var left: String = String(require_element_id.call(
		"%s.left" % field,
		combination.get("left")
	))
	var right: String = String(require_element_id.call(
		"%s.right" % field,
		combination.get("right")
	))
	var result_id: String = String(require_element_id.call(
		"%s.result" % field,
		combination.get("result")
	))
	is_valid = not result_id.is_empty() and is_valid

	var pair: Array[String] = [left, right]
	pair.sort()
	var pair_key: String = "|".join(pair)
	if not pair_key.is_empty() and seen_pairs.has(pair_key):
		_report_failure(
			report_failure,
			field,
			"unique unordered element pair"
		)
		is_valid = false
	seen_pairs[pair_key] = true
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
