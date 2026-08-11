# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name SpawnWaveCatalogValidator
extends RefCounted
## Validates already loaded spawn wave rows without owning data sources.


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var row_count: int = 0


static func validate(
	rows: Array[Dictionary],
	enemy_ids: Dictionary,
	hazard_ids: Dictionary,
	game_mode_ids: Dictionary,
	require_mode_id: Callable,
	report_failure: Callable
) -> ValidationResult:
	var result: ValidationResult = ValidationResult.new()
	result.row_count = rows.size()
	if rows.is_empty():
		_report_failure(report_failure, "rows", "non-empty CSV")
		result.is_valid = false

	var seen_ids: Dictionary = {}
	var seen_mode_waves: Dictionary = {}
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var field: String = "line %d" % (index + 2)
		var wave_id: String = String(row.get("id", ""))
		result.is_valid = _require_non_empty_string(
			"%s.id" % field,
			row.get("id"),
			report_failure
		) and result.is_valid
		if not wave_id.is_empty():
			if seen_ids.has(wave_id):
				_report_failure(
					report_failure,
					"%s.id" % field,
					"unique wave id"
				)
				result.is_valid = false
			seen_ids[wave_id] = true

		var mode_id: String = String(require_mode_id.call(
			"%s.mode_id" % field,
			row.get("mode_id")
		))
		# Preserve the legacy helper's aggregate-bool gap: an unregistered
		# mode reports through the callback but does not invalidate this result.
		if not mode_id.is_empty() and not game_mode_ids.has(mode_id):
			_report_failure(
				report_failure,
				"%s.mode_id" % field,
				"mode defined in game_modes.json"
			)
			result.is_valid = false

		var wave_index: Variant = _parse_int(row.get("wave_index"))
		result.is_valid = _require_int(
			"%s.wave_index" % field,
			wave_index,
			1,
			report_failure
		) and result.is_valid
		if not mode_id.is_empty() and _is_int_like(wave_index):
			var mode_wave_key: String = "%s:%d" % [
				mode_id,
				_variant_to_int(wave_index),
			]
			if seen_mode_waves.has(mode_wave_key):
				_report_failure(
					report_failure,
					"%s.wave_index" % field,
					"unique per mode"
				)
				result.is_valid = false
			seen_mode_waves[mode_wave_key] = true

		var start_time: Variant = _parse_float(row.get("start_time"))
		var end_time: Variant = _parse_float(row.get("end_time"))
		result.is_valid = _require_number(
			"%s.start_time" % field,
			start_time,
			0.0,
			null,
			false,
			report_failure
		) and result.is_valid
		result.is_valid = _require_number(
			"%s.end_time" % field,
			end_time,
			0.0,
			null,
			true,
			report_failure
		) and result.is_valid
		if (
			(start_time is int or start_time is float)
			and (end_time is int or end_time is float)
			and float(end_time) <= float(start_time)
		):
			_report_failure(
				report_failure,
				"%s.end_time" % field,
				"greater than start_time"
			)
			result.is_valid = false

		var enemy_id: String = String(row.get("enemy_id", ""))
		result.is_valid = _require_non_empty_string(
			"%s.enemy_id" % field,
			row.get("enemy_id"),
			report_failure
		) and result.is_valid
		if not enemy_id.is_empty() and not enemy_ids.has(enemy_id):
			_report_failure(
				report_failure,
				"%s.enemy_id" % field,
				"enemy defined in enemies.csv"
			)
			result.is_valid = false

		result.is_valid = _require_csv_int(
			"%s.enemy_weight" % field,
			row.get("enemy_weight"),
			1,
			report_failure
		) and result.is_valid
		result.is_valid = _require_csv_number(
			"%s.spawn_interval" % field,
			row.get("spawn_interval"),
			0.0,
			null,
			true,
			report_failure
		) and result.is_valid
		result.is_valid = _require_csv_int(
			"%s.max_alive" % field,
			row.get("max_alive"),
			1,
			report_failure
		) and result.is_valid
		result.is_valid = _require_csv_int(
			"%s.spawn_budget" % field,
			row.get("spawn_budget"),
			0,
			report_failure
		) and result.is_valid

		var hazard_id: String = String(row.get("hazard_id", ""))
		var hazard_weight: Variant = _parse_int(row.get("hazard_weight"))
		result.is_valid = _require_int(
			"%s.hazard_weight" % field,
			hazard_weight,
			0,
			report_failure
		) and result.is_valid
		if not hazard_id.is_empty() and not hazard_ids.has(hazard_id):
			_report_failure(
				report_failure,
				"%s.hazard_id" % field,
				"hazard defined in hazards.csv"
			)
			result.is_valid = false
		if (
			hazard_id.is_empty()
			and _is_int_like(hazard_weight)
			and _variant_to_int(hazard_weight) > 0
		):
			_report_failure(
				report_failure,
				"%s.hazard_id" % field,
				"non-empty when hazard_weight > 0"
			)
			result.is_valid = false
	return result


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
	minimum: Variant,
	report_failure: Callable
) -> bool:
	var parsed: Variant = _parse_int(value)
	if parsed == null:
		_report_failure(report_failure, field, "int")
		return false
	return _require_int(field, parsed, minimum, report_failure)


static func _require_csv_number(
	field: String,
	value: Variant,
	minimum: Variant,
	maximum: Variant,
	exclusive_minimum: bool,
	report_failure: Callable
) -> bool:
	var parsed: Variant = _parse_float(value)
	if parsed == null:
		_report_failure(report_failure, field, "number")
		return false
	return _require_number(
		field,
		parsed,
		minimum,
		maximum,
		exclusive_minimum,
		report_failure
	)


static func _require_int(
	field: String,
	value: Variant,
	minimum: Variant,
	report_failure: Callable
) -> bool:
	if not _is_int_like(value):
		_report_failure(report_failure, field, "int")
		return false
	if minimum != null and _variant_to_int(value) < int(minimum):
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


static func _variant_to_int(value: Variant) -> int:
	return int(value)


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


static func _report_failure(
	report_failure: Callable,
	field: String,
	expected: String
) -> void:
	report_failure.call(field, expected)
