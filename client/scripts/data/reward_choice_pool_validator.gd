# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name RewardChoicePoolValidator
extends RefCounted
## Validates already loaded reward choice pools without owning data sources.


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var pool_count: int = 0


static func validate(
	raw_data: Variant,
	require_locale_key: Callable,
	validate_modifiers: Callable,
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
	var pools: Array = _require_array(
		"pools",
		payload.get("pools"),
		report_failure
	)
	result.pool_count = pools.size()
	var pool_ids: Dictionary = {}
	for pool_index: int in range(pools.size()):
		result.is_valid = _validate_pool(
			pool_index,
			pools[pool_index],
			pool_ids,
			require_locale_key,
			validate_modifiers,
			report_failure
		) and result.is_valid
	return result


static func _validate_pool(
	pool_index: int,
	raw_pool: Variant,
	pool_ids: Dictionary,
	require_locale_key: Callable,
	validate_modifiers: Callable,
	report_failure: Callable
) -> bool:
	var pool_field: String = "pools[%d]" % pool_index
	if not raw_pool is Dictionary:
		_report_failure(report_failure, pool_field, "Dictionary")
		return false

	var pool: Dictionary = raw_pool as Dictionary
	var is_valid: bool = _require_non_empty_string(
		"%s.id" % pool_field,
		pool.get("id"),
		report_failure
	)
	var pool_id: String = String(pool.get("id", ""))
	if not pool_id.is_empty():
		if pool_ids.has(pool_id):
			_report_failure(
				report_failure,
				"%s.id" % pool_field,
				"unique pool id"
			)
			is_valid = false
		pool_ids[pool_id] = true
	var entries: Array = _require_array(
		"%s.entries" % pool_field,
		pool.get("entries"),
		report_failure
	)
	var entry_ids: Dictionary = {}
	for entry_index: int in range(entries.size()):
		is_valid = _validate_entry(
			pool_field,
			entry_index,
			entries[entry_index],
			entry_ids,
			require_locale_key,
			validate_modifiers,
			report_failure
		) and is_valid
	return is_valid


static func _validate_entry(
	pool_field: String,
	entry_index: int,
	raw_entry: Variant,
	entry_ids: Dictionary,
	require_locale_key: Callable,
	validate_modifiers: Callable,
	report_failure: Callable
) -> bool:
	var entry_field: String = "%s.entries[%d]" % [
		pool_field,
		entry_index,
	]
	if not raw_entry is Dictionary:
		_report_failure(report_failure, entry_field, "Dictionary")
		return false

	var entry: Dictionary = raw_entry as Dictionary
	var is_valid: bool = _require_non_empty_string(
		"%s.id" % entry_field,
		entry.get("id"),
		report_failure
	)
	is_valid = _call_validator(
		require_locale_key,
		"%s.name_key" % entry_field,
		entry.get("name_key")
	) and is_valid
	is_valid = _call_validator(
		require_locale_key,
		"%s.desc_key" % entry_field,
		entry.get("desc_key")
	) and is_valid
	var entry_id: String = String(entry.get("id", ""))
	if not entry_id.is_empty():
		if entry_ids.has(entry_id):
			_report_failure(
				report_failure,
				"%s.id" % entry_field,
				"unique entry id"
			)
			is_valid = false
		entry_ids[entry_id] = true
	var kind: String = String(entry.get("kind", ""))
	is_valid = _require_non_empty_string(
		"%s.kind" % entry_field,
		entry.get("kind"),
		report_failure
	) and is_valid
	if kind != "stat_modifier":
		_report_failure(
			report_failure,
			"%s.kind" % entry_field,
			"stat_modifier"
		)
		is_valid = false
	is_valid = _require_int(
		"%s.weight" % entry_field,
		entry.get("weight"),
		1,
		report_failure
	) and is_valid
	if entry.has("min_level"):
		is_valid = _require_int(
			"%s.min_level" % entry_field,
			entry.get("min_level"),
			1,
			report_failure
		) and is_valid
	is_valid = _call_validator(
		validate_modifiers,
		"%s.modifiers" % entry_field,
		entry.get("modifiers")
	) and is_valid
	return is_valid


static func _require_exact_int(
	field: String,
	value: Variant,
	expected: int,
	report_failure: Callable
) -> bool:
	if not _require_int(field, value, null, report_failure):
		return false
	if int(value) != expected:
		_report_failure(
			report_failure,
			field,
			"int equal to %d" % expected
		)
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


static func _call_validator(
	validator: Callable,
	field: String,
	value: Variant
) -> bool:
	return bool(validator.call(field, value))


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
