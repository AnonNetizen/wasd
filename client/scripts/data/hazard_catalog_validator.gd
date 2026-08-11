# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name HazardCatalogValidator
extends RefCounted
## Validates already loaded hazard catalog rows without owning data sources.


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var row_count: int = 0


static func validate(
	rows: Array[Dictionary],
	require_locale_key: Callable,
	has_contract_value: Callable,
	report_failure: Callable
) -> ValidationResult:
	var result: ValidationResult = ValidationResult.new()
	result.row_count = rows.size()
	if rows.is_empty():
		_report_failure(report_failure, "rows", "non-empty CSV")
		result.is_valid = false

	var seen_ids: Dictionary = {}
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var field: String = "line %d" % (index + 2)
		var hazard_id: String = String(row.get("id", ""))
		result.is_valid = _require_non_empty_string(
			"%s.id" % field,
			row.get("id"),
			report_failure
		) and result.is_valid
		if not hazard_id.is_empty():
			if seen_ids.has(hazard_id):
				_report_failure(
					report_failure,
					"%s.id" % field,
					"unique hazard id"
				)
				result.is_valid = false
			seen_ids[hazard_id] = true

		result.is_valid = bool(require_locale_key.call(
			"%s.name_key" % field,
			row.get("name_key")
		)) and result.is_valid

		var tags: Array[String] = _parse_tag_list(row.get("tags"))
		result.is_valid = _validate_registered_tags(
			"%s.tags" % field,
			tags,
			has_contract_value,
			report_failure
		) and result.is_valid
		if not tags.has("tag_hazard"):
			_report_failure(
				report_failure,
				"%s.tags" % field,
				"tag_hazard"
			)
			result.is_valid = false

		var pool_id: String = _require_registered(
			"%s.pool_id" % field,
			row.get("pool_id"),
			"pool_ids",
			has_contract_value,
			report_failure
		)
		result.is_valid = not pool_id.is_empty() and result.is_valid
		result.is_valid = _require_csv_int(
			"%s.damage" % field,
			row.get("damage"),
			0,
			report_failure
		) and result.is_valid
		var element_id: String = _require_registered(
			"%s.element_id" % field,
			row.get("element_id"),
			"elements",
			has_contract_value,
			report_failure
		)
		result.is_valid = not element_id.is_empty() and result.is_valid
		result.is_valid = _require_csv_number(
			"%s.trigger_interval" % field,
			row.get("trigger_interval"),
			0.0,
			true,
			report_failure
		) and result.is_valid
		result.is_valid = _require_csv_int(
			"%s.radius_tiles" % field,
			row.get("radius_tiles"),
			1,
			report_failure
		) and result.is_valid
		result.is_valid = _require_csv_number(
			"%s.duration" % field,
			row.get("duration"),
			0.0,
			false,
			report_failure
		) and result.is_valid
	return result


static func _validate_registered_tags(
	field: String,
	tags: Array[String],
	has_contract_value: Callable,
	report_failure: Callable
) -> bool:
	var is_valid: bool = true
	if tags.is_empty():
		_report_failure(report_failure, field, "non-empty Array")
		is_valid = false

	var seen: Dictionary = {}
	for index: int in range(tags.size()):
		var tag: String = _require_registered(
			"%s[%d]" % [field, index],
			tags[index],
			"content_tags",
			has_contract_value,
			report_failure
		)
		# Preserve the legacy helper's bool gap: an unknown tag reports an
		# error and stays out of duplicate detection, but does not by itself
		# make this helper return false.
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


static func _require_registered(
	field: String,
	value: Variant,
	contract_key: String,
	has_contract_value: Callable,
	report_failure: Callable
) -> String:
	if not value is String or String(value).is_empty():
		_report_failure(report_failure, field, "non-empty string")
		return ""
	var id_value: String = String(value)
	if not bool(has_contract_value.call(contract_key, id_value)):
		_report_failure(
			report_failure,
			field,
			"registered id in %s" % contract_key
		)
		return ""
	return id_value


static func _require_non_empty_string(
	field: String,
	value: Variant,
	report_failure: Callable
) -> bool:
	if not value is String or String(value).is_empty():
		_report_failure(report_failure, field, "non-empty string")
		return false
	return true


static func _require_csv_int(
	field: String,
	value: Variant,
	minimum: int,
	report_failure: Callable
) -> bool:
	var parsed: Variant = _parse_int(value)
	if parsed == null:
		_report_failure(report_failure, field, "int")
		return false
	if int(parsed) < minimum:
		_report_failure(
			report_failure,
			field,
			"int >= %d" % minimum
		)
		return false
	return true


static func _require_csv_number(
	field: String,
	value: Variant,
	minimum: Variant,
	exclusive_minimum: bool,
	report_failure: Callable
) -> bool:
	var parsed: Variant = _parse_float(value)
	if parsed == null:
		_report_failure(report_failure, field, "number")
		return false
	var numeric: float = float(parsed)
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


static func _parse_int(value: Variant) -> Variant:
	var text: String = String(value)
	if not text.is_valid_int():
		return null
	return text.to_int()


static func _parse_float(value: Variant) -> Variant:
	var text: String = String(value)
	if not text.is_valid_float():
		return null
	return text.to_float()


static func _parse_tag_list(value: Variant) -> Array[String]:
	var tags: Array[String] = []
	for raw_tag: String in String(value).split("|", false):
		var tag: String = raw_tag.strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	return tags


static func _report_failure(
	report_failure: Callable,
	field: String,
	expected: String
) -> void:
	report_failure.call(field, expected)
