# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name CameraFeedbackValidator
extends RefCounted
## Validates already loaded camera feedback data without owning data sources.


static func validate(
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, "root", "Dictionary")
		return false

	var payload: Dictionary = raw_data as Dictionary
	var is_valid: bool = _require_int(
		"schema_version",
		payload.get("schema_version"),
		3,
		3,
		report_failure
	)
	var aim_look: Variant = payload.get("aim_look")
	if not aim_look is Dictionary:
		_report_failure(report_failure, "aim_look", "Dictionary")
		is_valid = false
	else:
		is_valid = _validate_aim_look(
			aim_look as Dictionary,
			report_failure
		) and is_valid
	for profile_id: String in [
		"player_damage_shake",
		"weapon_recoil_shake",
	]:
		var shake_data: Variant = payload.get(profile_id)
		if not shake_data is Dictionary:
			_report_failure(report_failure, profile_id, "Dictionary")
			is_valid = false
			continue
		is_valid = _validate_shake_profile(
			profile_id,
			shake_data as Dictionary,
			report_failure
		) and is_valid
	var recoil_profile: Variant = payload.get("weapon_recoil_shake")
	if recoil_profile is Dictionary:
		is_valid = _require_number(
			"weapon_recoil_shake.amplitude_exponent",
			(recoil_profile as Dictionary).get("amplitude_exponent"),
			0.0,
			null,
			false,
			report_failure
		) and is_valid
	return is_valid


static func _validate_aim_look(
	profile: Dictionary,
	report_failure: Callable
) -> bool:
	var is_valid: bool = _require_number(
		"aim_look.pointer_offset_ratio",
		profile.get("pointer_offset_ratio"),
		0.0,
		1.0,
		true,
		report_failure
	)
	is_valid = _require_number(
		"aim_look.max_offset_px",
		profile.get("max_offset_px"),
		0.0,
		null,
		false,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"aim_look.pointer_dead_zone_px",
		profile.get("pointer_dead_zone_px"),
		0.0,
		null,
		false,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"aim_look.smoothing_time_seconds",
		profile.get("smoothing_time_seconds"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	return is_valid


static func _validate_shake_profile(
	profile_id: String,
	profile: Dictionary,
	report_failure: Callable
) -> bool:
	var is_valid: bool = _require_number(
		"%s.amplitude" % profile_id,
		profile.get("amplitude"),
		0.0,
		null,
		false,
		report_failure
	)
	is_valid = _require_number(
		"%s.frequency" % profile_id,
		profile.get("frequency"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.growth_time" % profile_id,
		profile.get("growth_time"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.duration" % profile_id,
		profile.get("duration"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.decay_time" % profile_id,
		profile.get("decay_time"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.positional_multiplier_x" % profile_id,
		profile.get("positional_multiplier_x"),
		0.0,
		1.0,
		false,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.positional_multiplier_y" % profile_id,
		profile.get("positional_multiplier_y"),
		0.0,
		1.0,
		false,
		report_failure
	) and is_valid
	return is_valid


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
		var min_value: float = float(minimum)
		if exclusive_minimum and numeric <= min_value:
			_report_failure(
				report_failure,
				field,
				"number > %s" % str(minimum)
			)
			return false
		if not exclusive_minimum and numeric < min_value:
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
