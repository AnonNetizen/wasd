# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name CreditsValidator
extends RefCounted
## Validates already loaded credits data without owning data sources.


const VALID_ENTRY_KINDS: Array[String] = [
	"staff",
	"external_resource",
	"external_library",
	"external_tool",
]


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var section_count: int = 0
	var entry_count: int = 0


static func validate(
	raw_data: Variant,
	require_locale_key: Callable,
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
	var sections: Array = _require_array(
		"sections",
		payload.get("sections"),
		report_failure
	)
	if sections.is_empty():
		_report_failure(report_failure, "sections", "non-empty Array")
		result.is_valid = false
	result.section_count = sections.size()
	var seen_sections: Dictionary = {}
	for section_index: int in range(sections.size()):
		var section_field: String = "sections[%d]" % section_index
		var section: Variant = sections[section_index]
		if not section is Dictionary:
			_report_failure(report_failure, section_field, "Dictionary")
			result.is_valid = false
			continue
		var section_dict: Dictionary = section as Dictionary
		var section_id: String = String(section_dict.get("id", ""))
		result.is_valid = _require_non_empty_string(
			"%s.id" % section_field,
			section_dict.get("id"),
			report_failure
		) and result.is_valid
		if not section_id.is_empty():
			if seen_sections.has(section_id):
				_report_failure(
					report_failure,
					"%s.id" % section_field,
					"unique section id"
				)
				result.is_valid = false
			seen_sections[section_id] = true
		result.is_valid = _call_locale_validator(
			"%s.title_key" % section_field,
			section_dict.get("title_key"),
			require_locale_key
		) and result.is_valid
		var entries: Array = _require_array(
			"%s.entries" % section_field,
			section_dict.get("entries"),
			report_failure
		)
		if entries.is_empty():
			_report_failure(
				report_failure,
				"%s.entries" % section_field,
				"non-empty Array"
			)
			result.is_valid = false
		result.entry_count += entries.size()
		for entry_index: int in range(entries.size()):
			result.is_valid = _validate_entry(
				"%s.entries[%d]" % [section_field, entry_index],
				entries[entry_index],
				require_locale_key,
				report_failure
			) and result.is_valid
	return result


static func _validate_entry(
	field: String,
	data: Variant,
	require_locale_key: Callable,
	report_failure: Callable
) -> bool:
	if not data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false
	var entry: Dictionary = data as Dictionary
	var is_valid: bool = true
	var kind: String = String(entry.get("kind", ""))
	if not VALID_ENTRY_KINDS.has(kind):
		_report_failure(
			report_failure,
			"%s.kind" % field,
			(
				"staff, external_resource, external_library, "
				+ "or external_tool"
			)
		)
		is_valid = false
	is_valid = _require_non_empty_string(
		"%s.name" % field,
		entry.get("name"),
		report_failure
	) and is_valid
	is_valid = _call_locale_validator(
		"%s.role_key" % field,
		entry.get("role_key"),
		require_locale_key
	) and is_valid
	if kind.begins_with("external_"):
		is_valid = _require_non_empty_string(
			"%s.url" % field,
			entry.get("url"),
			report_failure
		) and is_valid
		is_valid = _require_non_empty_string(
			"%s.license" % field,
			entry.get("license"),
			report_failure
		) and is_valid
		is_valid = _require_bool(
			"%s.included_in_build" % field,
			entry.get("included_in_build"),
			report_failure
		) and is_valid
		is_valid = _require_bool(
			"%s.requires_notice" % field,
			entry.get("requires_notice"),
			report_failure
		) and is_valid
		is_valid = _require_bool(
			"%s.review_required" % field,
			entry.get("review_required"),
			report_failure
		) and is_valid
	if entry.has("copyright"):
		is_valid = _require_non_empty_string(
			"%s.copyright" % field,
			entry.get("copyright"),
			report_failure
		) and is_valid
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
	minimum: int,
	report_failure: Callable
) -> bool:
	if not _is_int_like(value):
		_report_failure(report_failure, field, "int")
		return false
	if int(value) < minimum:
		_report_failure(
			report_failure,
			field,
			"int >= %d" % minimum
		)
		return false
	return true


static func _call_locale_validator(
	field: String,
	value: Variant,
	require_locale_key: Callable
) -> bool:
	return bool(require_locale_key.call(field, value))


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
