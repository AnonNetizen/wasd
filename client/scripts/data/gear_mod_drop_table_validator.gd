# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name GearModDropTableValidator
extends RefCounted
## Validates already loaded Gear Mod drop rows without owning data sources.


const REQUIRED_ROW_KEYS: Array[String] = [
	"source_enemy_id",
	"mod_id",
	"drop_chance",
	"min_enemy_level",
	"max_enemy_level",
]


static func validate_package_rows(
	raw_rows: Variant,
	package_id: String,
	enemy_ids: Dictionary,
	package_mod_ids: Dictionary,
	report_failure: Callable
) -> bool:
	if not raw_rows is Array:
		return false

	var is_valid: bool = true
	for row_index: int in range((raw_rows as Array).size()):
		var raw_row: Variant = (raw_rows as Array)[row_index]
		if not raw_row is Dictionary:
			is_valid = false
			continue
		var row: Dictionary = raw_row as Dictionary
		var row_field: String = "%s.drop_rows[%d]" % [
			package_id,
			row_index,
		]
		is_valid = _validate_exact_dictionary_keys(
			row_field,
			row,
			report_failure
		) and is_valid
		if not enemy_ids.has(String(row.get("source_enemy_id", ""))):
			is_valid = false
		if not package_mod_ids.has(String(row.get("mod_id", ""))):
			is_valid = false
		is_valid = _validate_csv_number(
			"%s.drop_chance" % row_field,
			row.get("drop_chance"),
			0.0,
			1.0,
			report_failure
		) and is_valid
		var min_level: Variant = _parse_int(row.get("min_enemy_level"))
		var max_level: Variant = _parse_int(row.get("max_enemy_level"))
		is_valid = _validate_parsed_int(
			"%s.min_enemy_level" % row_field,
			min_level,
			1,
			report_failure
		) and is_valid
		is_valid = _validate_parsed_int(
			"%s.max_enemy_level" % row_field,
			max_level,
			1,
			report_failure
		) and is_valid
		if (
			min_level != null
			and max_level != null
			and int(max_level) < int(min_level)
		):
			is_valid = false
	return is_valid


static func validate_merged_rows(
	rows: Array[Dictionary],
	enemy_ids: Dictionary,
	gear_mod_ids: Dictionary,
	report_failure: Callable
) -> bool:
	var is_valid: bool = true
	if rows.is_empty():
		_report_failure(report_failure, "rows", "non-empty CSV")
		is_valid = false

	var seen: Dictionary = {}
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var field: String = "line %d" % (index + 2)
		var source_enemy_id: String = String(
			row.get("source_enemy_id", "")
		)
		if source_enemy_id.is_empty():
			_report_failure(
				report_failure,
				"%s.source_enemy_id" % field,
				"non-empty string"
			)
			is_valid = false
		elif not enemy_ids.has(source_enemy_id):
			_report_failure(
				report_failure,
				"%s.source_enemy_id" % field,
				"enemy defined in enemies.csv"
			)
			is_valid = false

		var mod_id: String = String(row.get("mod_id", ""))
		if mod_id.is_empty():
			_report_failure(
				report_failure,
				"%s.mod_id" % field,
				"non-empty string"
			)
			is_valid = false
		elif not gear_mod_ids.has(mod_id):
			_report_failure(
				report_failure,
				"%s.mod_id" % field,
				"gear mod defined in gear_mods.json"
			)
			is_valid = false

		is_valid = _validate_csv_number(
			"%s.drop_chance" % field,
			row.get("drop_chance"),
			0.0,
			1.0,
			report_failure
		) and is_valid
		var min_level: Variant = _parse_int(row.get("min_enemy_level"))
		var max_level: Variant = _parse_int(row.get("max_enemy_level"))
		var min_level_ok: bool = _validate_parsed_int(
			"%s.min_enemy_level" % field,
			min_level,
			1,
			report_failure
		)
		var max_level_ok: bool = _validate_parsed_int(
			"%s.max_enemy_level" % field,
			max_level,
			1,
			report_failure
		)
		is_valid = min_level_ok and is_valid
		is_valid = max_level_ok and is_valid
		if min_level_ok and max_level_ok:
			var parsed_min_level: int = int(min_level)
			var parsed_max_level: int = int(max_level)
			if parsed_max_level < parsed_min_level:
				_report_failure(
					report_failure,
					"%s.max_enemy_level" % field,
					"int >= min_enemy_level"
				)
				is_valid = false
			if not source_enemy_id.is_empty() and not mod_id.is_empty():
				var key: String = "%s:%s:%d:%d" % [
					source_enemy_id,
					mod_id,
					parsed_min_level,
					parsed_max_level,
				]
				if seen.has(key):
					_report_failure(
						report_failure,
						field,
						"unique source/mod/level range"
					)
					is_valid = false
				seen[key] = true
	return is_valid


static func _validate_exact_dictionary_keys(
	field: String,
	row: Dictionary,
	report_failure: Callable
) -> bool:
	var is_valid: bool = true
	for required_key: String in REQUIRED_ROW_KEYS:
		if not row.has(required_key):
			_report_failure(
				report_failure,
				"%s.%s" % [field, required_key],
				"required field"
			)
			is_valid = false
	for raw_key: Variant in row.keys():
		var key: String = String(raw_key)
		if not REQUIRED_ROW_KEYS.has(key):
			_report_failure(
				report_failure,
				"%s.%s" % [field, key],
				"allowed schema field"
			)
			is_valid = false
	return is_valid


static func _validate_csv_number(
	field: String,
	value: Variant,
	minimum: Variant,
	maximum: Variant,
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
	if minimum != null and numeric < float(minimum):
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


static func _validate_parsed_int(
	field: String,
	parsed: Variant,
	minimum: int,
	report_failure: Callable
) -> bool:
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


static func _parse_int(value: Variant) -> Variant:
	if value == null:
		return null
	var text: String = String(value)
	if not text.is_valid_int():
		return null
	return text.to_int()


static func _parse_float(value: Variant) -> Variant:
	if value == null:
		return null
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
