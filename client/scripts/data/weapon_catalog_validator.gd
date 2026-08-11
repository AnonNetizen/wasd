# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name WeaponCatalogValidator
extends RefCounted
## Validates already loaded weapon catalog data without owning data sources.


const REQUIRED_WEAPON_STATS: Array[String] = [
	"damage",
	"fire_rate",
	"bullet_speed",
	"bullet_range",
	"bullet_count",
	"recoil",
	"spread_angle_max",
]
const RECOIL_MAXIMUM: float = 100.0
const BASE_SPREAD_CAP_MAXIMUM: float = 60.0
const RUNTIME_SPREAD_CAP_MAXIMUM: float = 180.0


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var weapon_count: int = 0


static func validate(
	raw_data: Variant,
	supported_weapon_stats: Array[String],
	require_locale_key: Callable,
	require_audio_id: Callable,
	validate_stat_value: Callable,
	require_registered: Callable,
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
		5,
		5,
		report_failure
	) and result.is_valid
	var recoil_model: Dictionary = {}
	var raw_recoil_model: Variant = payload.get("recoil_model", {})
	if raw_recoil_model is Dictionary:
		recoil_model = (raw_recoil_model as Dictionary).duplicate(true)
	result.is_valid = _validate_recoil_model(
		recoil_model,
		report_failure
	) and result.is_valid
	var weapons: Array = _require_array(
		"weapons",
		payload.get("weapons"),
		report_failure
	)
	if weapons.is_empty():
		_report_failure(report_failure, "weapons", "non-empty Array")
		result.is_valid = false
	result.weapon_count = weapons.size()

	var seen: Dictionary = {}
	for index: int in range(weapons.size()):
		result.is_valid = _validate_weapon(
			index,
			weapons[index],
			seen,
			recoil_model,
			supported_weapon_stats,
			require_locale_key,
			require_audio_id,
			validate_stat_value,
			require_registered,
			report_failure
		) and result.is_valid
	return result


static func _validate_weapon(
	index: int,
	raw_weapon: Variant,
	seen: Dictionary,
	recoil_model: Dictionary,
	supported_weapon_stats: Array[String],
	require_locale_key: Callable,
	require_audio_id: Callable,
	validate_stat_value: Callable,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "weapons[%d]" % index
	if not raw_weapon is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var weapon: Dictionary = raw_weapon as Dictionary
	var is_valid: bool = _validate_exact_dictionary_keys(
		field,
		weapon,
		[
			"id",
			"name_key",
			"desc_key",
			"default_unlocked",
			"fire_mode",
			"fire_audio_id",
			"presentation_profile_id",
			"base_stats",
			"projectile",
		],
		report_failure
	)
	is_valid = _require_non_empty_string(
		"%s.id" % field,
		weapon.get("id"),
		report_failure
	) and is_valid
	var weapon_id: String = String(weapon.get("id", ""))
	if not weapon_id.is_empty():
		if seen.has(weapon_id):
			_report_failure(
				report_failure,
				"%s.id" % field,
				"unique weapon id"
			)
			is_valid = false
		seen[weapon_id] = true
	is_valid = bool(require_locale_key.call(
		"%s.name_key" % field,
		weapon.get("name_key")
	)) and is_valid
	is_valid = bool(require_locale_key.call(
		"%s.desc_key" % field,
		weapon.get("desc_key")
	)) and is_valid
	is_valid = _require_bool(
		"%s.default_unlocked" % field,
		weapon.get("default_unlocked"),
		report_failure
	) and is_valid
	is_valid = _require_non_empty_string(
		"%s.fire_mode" % field,
		weapon.get("fire_mode"),
		report_failure
	) and is_valid
	if weapon.has("fire_audio_id"):
		is_valid = bool(require_audio_id.call(
			"%s.fire_audio_id" % field,
			weapon.get("fire_audio_id")
		)) and is_valid
	is_valid = _validate_weapon_stats(
		"%s.base_stats" % field,
		weapon.get("base_stats"),
		recoil_model,
		supported_weapon_stats,
		validate_stat_value,
		report_failure
	) and is_valid
	is_valid = _validate_projectile(
		"%s.projectile" % field,
		weapon.get("projectile"),
		require_registered,
		report_failure
	) and is_valid
	return is_valid


static func _validate_recoil_model(
	model: Dictionary,
	report_failure: Callable
) -> bool:
	if model.is_empty():
		_report_failure(
			report_failure,
			"recoil_model",
			"non-empty Dictionary"
		)
		return false
	var is_valid: bool = true
	is_valid = _require_number(
		"recoil_model.recoil_max",
		model.get("recoil_max"),
		0.0,
		RECOIL_MAXIMUM,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"recoil_model.spread_exponent",
		model.get("spread_exponent"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"recoil_model.kickback_max_distance",
		model.get("kickback_max_distance"),
		0.0,
		null,
		false,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"recoil_model.kickback_duration",
		model.get("kickback_duration"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"recoil_model.kickback_velocity_cap",
		model.get("kickback_velocity_cap"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"recoil_model.base_spread_cap",
		model.get("base_spread_cap"),
		0.0,
		BASE_SPREAD_CAP_MAXIMUM,
		false,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"recoil_model.runtime_spread_cap",
		model.get("runtime_spread_cap"),
		0.0,
		RUNTIME_SPREAD_CAP_MAXIMUM,
		false,
		report_failure
	) and is_valid
	if (
		model.get("base_spread_cap") is float
		or model.get("base_spread_cap") is int
	) and (
		model.get("runtime_spread_cap") is float
		or model.get("runtime_spread_cap") is int
	) and (
		float(model.get("runtime_spread_cap"))
		< float(model.get("base_spread_cap"))
	):
		_report_failure(
			report_failure,
			"recoil_model.runtime_spread_cap",
			"value greater than or equal to base_spread_cap"
		)
		is_valid = false
	return is_valid


static func _validate_weapon_stats(
	field: String,
	raw_data: Variant,
	recoil_model: Dictionary,
	supported_weapon_stats: Array[String],
	validate_stat_value: Callable,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary or (raw_data as Dictionary).is_empty():
		_report_failure(report_failure, field, "non-empty Dictionary")
		return false
	var stats: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	for required_stat: String in REQUIRED_WEAPON_STATS:
		if not stats.has(required_stat):
			_report_failure(
				report_failure,
				"%s.%s" % [field, required_stat],
				"required weapon stat"
			)
			is_valid = false
	for raw_stat: Variant in stats.keys():
		var stat: String = String(raw_stat)
		if not supported_weapon_stats.has(stat):
			_report_failure(
				report_failure,
				"%s.%s" % [field, stat],
				"supported weapon stat"
			)
			is_valid = false
			continue
		if stat == "pierce_count":
			is_valid = _require_int(
				"%s.%s" % [field, stat],
				stats[raw_stat],
				0,
				null,
				report_failure
			) and is_valid
		elif stat == "recoil":
			is_valid = _require_number(
				"%s.%s" % [field, stat],
				stats[raw_stat],
				0.0,
				float(recoil_model.get("recoil_max", 0.0)),
				false,
				report_failure
			) and is_valid
		elif stat == "spread_angle_max":
			is_valid = _require_number(
				"%s.%s" % [field, stat],
				stats[raw_stat],
				0.0,
				float(recoil_model.get("base_spread_cap", 0.0)),
				false,
				report_failure
			) and is_valid
		else:
			is_valid = bool(validate_stat_value.call(
				"%s.%s" % [field, stat],
				stat,
				stats[raw_stat]
			)) and is_valid
	return is_valid


static func _validate_projectile(
	field: String,
	raw_data: Variant,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false
	var projectile: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	is_valid = not String(require_registered.call(
		"%s.pool_id" % field,
		projectile.get("pool_id"),
		"pool_ids"
	)).is_empty() and is_valid
	is_valid = not String(require_registered.call(
		"%s.element_id" % field,
		projectile.get("element_id"),
		"elements"
	)).is_empty() and is_valid
	for key: String in ["hit_radius", "muzzle_distance", "lifetime"]:
		is_valid = _require_number(
			"%s.%s" % [field, key],
			projectile.get(key),
			0.0,
			null,
			true,
			report_failure
		) and is_valid
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


static func _require_int(
	field: String,
	value: Variant,
	minimum: Variant,
	maximum: Variant,
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
	if maximum != null and int(value) > int(maximum):
		_report_failure(
			report_failure,
			field,
			"int <= %d" % int(maximum)
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


static func _report_failure(
	report_failure: Callable,
	field: String,
	expected: String
) -> void:
	report_failure.call(field, expected)
