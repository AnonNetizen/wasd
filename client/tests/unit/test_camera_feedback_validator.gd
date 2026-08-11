extends SmokeHarness


const CAMERA_FEEDBACK_VALIDATOR := preload(
	"res://scripts/data/camera_feedback_validator.gd"
)
const CAMERA_FEEDBACK_PATH: String = "res://data/camera_feedback.json"

var _reported_failures: Array[String] = []
var _data_loader_messages: Array[String] = []


func before_each() -> void:
	super()
	_reported_failures.clear()
	_data_loader_messages.clear()


func test_canonical_payload_and_minimum_boundaries_are_accepted() -> void:
	assert_true(_validate(_valid_payload()))
	assert_true(_validate({
		"schema_version": 3.0,
		"aim_look": {
			"pointer_offset_ratio": 0.0001,
			"max_offset_px": 0.0,
			"pointer_dead_zone_px": 0.0,
			"smoothing_time_seconds": 0.0001,
		},
		"player_damage_shake": _minimum_shake_profile(),
		"weapon_recoil_shake": _minimum_weapon_shake_profile(),
	}))
	assert_eq(_reported_failures, [])


func test_root_requires_dictionary_with_legacy_failure() -> void:
	assert_false(_validate([]))
	assert_eq(_reported_failures, [
		"root|Dictionary",
	])


func test_nested_dictionary_failures_short_circuit_in_legacy_order() -> void:
	assert_false(_validate({
		"schema_version": 3,
		"aim_look": [],
		"player_damage_shake": null,
		"weapon_recoil_shake": "invalid",
	}))
	assert_eq(_reported_failures, [
		"aim_look|Dictionary",
		"player_damage_shake|Dictionary",
		"weapon_recoil_shake|Dictionary",
	])


func test_missing_scalar_fields_keep_full_legacy_order() -> void:
	assert_false(_validate({
		"schema_version": 3,
		"aim_look": {},
		"player_damage_shake": {},
		"weapon_recoil_shake": {},
	}))
	assert_eq(_reported_failures, [
		"aim_look.pointer_offset_ratio|number",
		"aim_look.max_offset_px|number",
		"aim_look.pointer_dead_zone_px|number",
		"aim_look.smoothing_time_seconds|number",
		"player_damage_shake.amplitude|number",
		"player_damage_shake.frequency|number",
		"player_damage_shake.growth_time|number",
		"player_damage_shake.duration|number",
		"player_damage_shake.decay_time|number",
		"player_damage_shake.positional_multiplier_x|number",
		"player_damage_shake.positional_multiplier_y|number",
		"weapon_recoil_shake.amplitude|number",
		"weapon_recoil_shake.frequency|number",
		"weapon_recoil_shake.growth_time|number",
		"weapon_recoil_shake.duration|number",
		"weapon_recoil_shake.decay_time|number",
		"weapon_recoil_shake.positional_multiplier_x|number",
		"weapon_recoil_shake.positional_multiplier_y|number",
		"weapon_recoil_shake.amplitude_exponent|number",
	])


func test_schema_keeps_int_like_and_legacy_bound_failures() -> void:
	var payload: Dictionary = _valid_payload()
	payload["schema_version"] = 3.0
	assert_true(_validate(payload))
	assert_eq(_reported_failures, [])

	_reported_failures.clear()
	payload["schema_version"] = 3.5
	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"schema_version|int",
	])

	_reported_failures.clear()
	payload["schema_version"] = 2.0
	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"schema_version|int >= 3",
	])

	_reported_failures.clear()
	payload["schema_version"] = 4
	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"schema_version|int <= 3",
	])


func test_numeric_fields_require_finite_numbers_in_group_order() -> void:
	var payload: Dictionary = _valid_payload()
	var aim_look: Dictionary = payload["aim_look"] as Dictionary
	var player_shake: Dictionary = (
		payload["player_damage_shake"] as Dictionary
	)
	var weapon_shake: Dictionary = (
		payload["weapon_recoil_shake"] as Dictionary
	)
	aim_look["pointer_offset_ratio"] = INF
	player_shake["amplitude"] = INF
	weapon_shake["positional_multiplier_y"] = INF
	weapon_shake["amplitude_exponent"] = INF

	assert_false(_validate(payload))
	assert_eq(_reported_failures, [
		"aim_look.pointer_offset_ratio|finite number",
		"player_damage_shake.amplitude|finite number",
		"weapon_recoil_shake.positional_multiplier_y|finite number",
		"weapon_recoil_shake.amplitude_exponent|finite number",
	])


func test_range_failures_keep_schema_aim_shake_and_exponent_order() -> void:
	assert_false(_validate({
		"schema_version": 2,
		"aim_look": {
			"pointer_offset_ratio": 0.0,
			"max_offset_px": -1.0,
			"pointer_dead_zone_px": -1.0,
			"smoothing_time_seconds": 0.0,
		},
		"player_damage_shake": _invalid_shake_profile(),
		"weapon_recoil_shake": _invalid_weapon_shake_profile(),
	}))
	assert_eq(_reported_failures, [
		"schema_version|int >= 3",
		"aim_look.pointer_offset_ratio|number > 0.0",
		"aim_look.max_offset_px|number >= 0.0",
		"aim_look.pointer_dead_zone_px|number >= 0.0",
		"aim_look.smoothing_time_seconds|number > 0.0",
		"player_damage_shake.amplitude|number >= 0.0",
		"player_damage_shake.frequency|number > 0.0",
		"player_damage_shake.growth_time|number > 0.0",
		"player_damage_shake.duration|number > 0.0",
		"player_damage_shake.decay_time|number > 0.0",
		(
			"player_damage_shake.positional_multiplier_x|"
			+ "number >= 0.0"
		),
		(
			"player_damage_shake.positional_multiplier_y|"
			+ "number <= 1.0"
		),
		"weapon_recoil_shake.amplitude|number >= 0.0",
		"weapon_recoil_shake.frequency|number > 0.0",
		"weapon_recoil_shake.growth_time|number > 0.0",
		"weapon_recoil_shake.duration|number > 0.0",
		"weapon_recoil_shake.decay_time|number > 0.0",
		(
			"weapon_recoil_shake.positional_multiplier_x|"
			+ "number >= 0.0"
		),
		(
			"weapon_recoil_shake.positional_multiplier_y|"
			+ "number <= 1.0"
		),
		"weapon_recoil_shake.amplitude_exponent|number >= 0.0",
	])


func test_extra_keys_remain_allowed_at_every_dictionary_level() -> void:
	var payload: Dictionary = _valid_payload()
	var aim_look: Dictionary = payload["aim_look"] as Dictionary
	var player_shake: Dictionary = (
		payload["player_damage_shake"] as Dictionary
	)
	var weapon_shake: Dictionary = (
		payload["weapon_recoil_shake"] as Dictionary
	)
	payload["future_root"] = true
	aim_look["future_aim"] = true
	player_shake["future_player_shake"] = true
	weapon_shake["future_weapon_shake"] = true

	assert_true(_validate(payload))
	assert_eq(_reported_failures, [])


func test_success_and_failure_calls_do_not_share_state() -> void:
	assert_false(_validate([]))
	assert_eq(_reported_failures, ["root|Dictionary"])

	_reported_failures.clear()
	assert_true(_validate(_valid_payload()))
	assert_eq(_reported_failures, [])

	assert_false(_validate({}))
	assert_eq(_reported_failures, [
		"schema_version|int",
		"aim_look|Dictionary",
		"player_damage_shake|Dictionary",
		"weapon_recoil_shake|Dictionary",
	])


func test_report_failure_arguments_support_data_loader_text_adapter() -> void:
	assert_false(CAMERA_FEEDBACK_VALIDATOR.validate(
		[],
		Callable(self, "_record_data_loader_failure")
	))
	assert_eq(_data_loader_messages, [
		(
			"[DataLoader] res://data/camera_feedback.json:root "
			+ "expected Dictionary"
		),
	])


func _validate(raw_data: Variant) -> bool:
	return CAMERA_FEEDBACK_VALIDATOR.validate(
		raw_data,
		Callable(self, "_record_failure")
	)


func _record_failure(field: String, expected: String) -> void:
	_reported_failures.append("%s|%s" % [field, expected])


func _record_data_loader_failure(field: String, expected: String) -> void:
	_data_loader_messages.append(
		"[DataLoader] %s:%s expected %s" % [
			CAMERA_FEEDBACK_PATH,
			field,
			expected,
		]
	)


func _valid_payload() -> Dictionary:
	return {
		"schema_version": 3,
		"aim_look": {
			"pointer_offset_ratio": 0.3,
			"max_offset_px": 240.0,
			"pointer_dead_zone_px": 32.0,
			"smoothing_time_seconds": 0.18,
		},
		"player_damage_shake": {
			"amplitude": 8.0,
			"frequency": 20.0,
			"growth_time": 0.01,
			"duration": 0.08,
			"decay_time": 0.12,
			"positional_multiplier_x": 1.0,
			"positional_multiplier_y": 1.0,
		},
		"weapon_recoil_shake": {
			"amplitude": 6.0,
			"amplitude_exponent": 0.75,
			"frequency": 30.0,
			"growth_time": 0.005,
			"duration": 0.02,
			"decay_time": 0.055,
			"positional_multiplier_x": 1.0,
			"positional_multiplier_y": 1.0,
		},
	}


func _minimum_shake_profile() -> Dictionary:
	return {
		"amplitude": 0.0,
		"frequency": 0.0001,
		"growth_time": 0.0001,
		"duration": 0.0001,
		"decay_time": 0.0001,
		"positional_multiplier_x": 0.0,
		"positional_multiplier_y": 1.0,
	}


func _minimum_weapon_shake_profile() -> Dictionary:
	var profile: Dictionary = _minimum_shake_profile()
	profile["amplitude_exponent"] = 0.0
	return profile


func _invalid_shake_profile() -> Dictionary:
	return {
		"amplitude": -1.0,
		"frequency": 0.0,
		"growth_time": 0.0,
		"duration": 0.0,
		"decay_time": 0.0,
		"positional_multiplier_x": -0.1,
		"positional_multiplier_y": 1.1,
	}


func _invalid_weapon_shake_profile() -> Dictionary:
	var profile: Dictionary = _invalid_shake_profile()
	profile["amplitude_exponent"] = -1.0
	return profile
