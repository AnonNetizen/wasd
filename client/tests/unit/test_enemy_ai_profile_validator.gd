extends SmokeHarness


const ENEMY_AI_PROFILE_VALIDATOR := preload(
	"res://scripts/data/enemy_ai_profile_validator.gd"
)

var _failures: Array[String] = []
var _contract_calls: Array[String] = []
var _contracts: Dictionary = {}


func before_each() -> void:
	super()
	_failures.clear()
	_contract_calls.clear()
	_contracts = {
		"enemy_ai_actions": {
			"ai_action_approach_target": true,
			"ai_action_orbit_target": true,
			"ai_action_charge_target": true,
			"ai_action_guard_home": true,
			"ai_action_ranged_attack": true,
			"ai_action_explode_target": true,
			"ai_action_melee_attack": true,
		},
		"elements": {"element_neutral": true},
		"pool_ids": {"bullet_basic": true},
	}


func test_all_attack_shapes_are_valid_and_counted() -> void:
	var root: Dictionary = _root([
		_profile("explode", _explode_action()),
		_profile("melee", _melee_action()),
		_profile("charge", _charge_action()),
		_profile("ranged", _ranged_action()),
	])
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(root)

	assert_true(result.is_valid)
	assert_eq(result.profile_count, 4)
	assert_eq(_failures, [])
	assert_eq(_contract_calls, [
		"profiles[0].actions[0].id|enemy_ai_actions|ai_action_explode_target",
		"profiles[0].actions[0].attack.element_id|elements|element_neutral",
		"profiles[1].actions[0].id|enemy_ai_actions|ai_action_melee_attack",
		"profiles[1].actions[0].attack.element_id|elements|element_neutral",
		"profiles[2].actions[0].id|enemy_ai_actions|ai_action_charge_target",
		"profiles[2].actions[0].attack.element_id|elements|element_neutral",
		"profiles[3].actions[0].id|enemy_ai_actions|ai_action_ranged_attack",
		"profiles[3].actions[0].attack.element_id|elements|element_neutral",
		"profiles[3].actions[0].attack.projectile.pool_id|pool_ids|bullet_basic",
	])


func test_root_and_profiles_type_short_circuits_preserve_count_semantics() -> void:
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate([])
	assert_false(result.is_valid)
	assert_eq(result.profile_count, 0)
	assert_eq(_failures, ["root|Dictionary"])

	_clear_diagnostics()
	result = _validate({"schema_version": 5, "profiles": {}})
	assert_false(result.is_valid)
	assert_eq(result.profile_count, 0)
	assert_eq(_failures, [
		"profiles|Array",
		"profiles|non-empty Array",
	])


func test_schema_is_exact_int_like_five_and_empty_profiles_still_fail() -> void:
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate({
		"schema_version": 5.0,
		"profiles": [],
	})
	assert_false(result.is_valid)
	assert_eq(_failures, ["profiles|non-empty Array"])

	_clear_diagnostics()
	result = _validate({"schema_version": 4, "profiles": []})
	assert_false(result.is_valid)
	assert_eq(_failures, [
		"schema_version|int >= 5",
		"profiles|non-empty Array",
	])


func test_profile_and_action_shapes_duplicates_and_raw_count_continue() -> void:
	var first: Dictionary = _profile("duplicate", _approach_action())
	var second: Dictionary = _profile("duplicate", _approach_action())
	second["actions"] = [
		null,
		_approach_action(),
		_approach_action(),
	]
	var third: Dictionary = _profile("bad_actions", _approach_action())
	third["actions"] = {}
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(
		_root([null, first, second, third])
	)

	assert_false(result.is_valid)
	assert_eq(result.profile_count, 4)
	assert_eq(_failures, [
		"profiles[0]|Dictionary",
		"profiles[2].id|unique profile id",
		"profiles[2].actions[0]|Dictionary",
		"profiles[2].actions[2].id|unique action id",
		"profiles[3].actions|Array",
		"profiles[3].actions|non-empty Array",
	])


func test_profile_fields_keep_source_order_and_continue_after_failures() -> void:
	var action: Dictionary = _approach_action()
	action["base_score"] = -1.0
	action["speed_scale"] = 0.0
	var profile: Dictionary = _profile("", action)
	profile["contact_interval"] = 1.0
	profile["sense_radius"] = 20.0
	profile["perception"] = null
	profile["decision_interval"] = 0.0
	profile["targeting"] = null
	profile["movement"] = null
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(
		_root([profile])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"profiles[0].id|non-empty string",
		"profiles[0].contact_interval|field removed in schema v2",
		"profiles[0].sense_radius|field removed in schema v3",
		"profiles[0].perception|Dictionary",
		"profiles[0].decision_interval|number > 0.0",
		"profiles[0].targeting|Dictionary",
		"profiles[0].movement|Dictionary",
		"profiles[0].actions[0].base_score|number >= 0.0",
		"profiles[0].actions[0].speed_scale|number > 0.0",
	])


func test_perception_relation_and_targeting_movement_legacy_order() -> void:
	var profile: Dictionary = _profile("legacy", _approach_action())
	profile["perception"] = {
		"sight_radius": 5.0,
		"path_awareness_radius": 6.0,
		"memory_duration": 0.0,
	}
	profile["targeting"] = {
		"hunt_tags": [],
		"flee_tags": [],
		"player_weight": -1.0,
		"territory_radius": -1.0,
		"territory_weight": -1.0,
	}
	profile["movement"] = {
		"orbit_radius": -1.0,
		"flee_distance": 4.0,
		"charge_range": 8.0,
	}
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(
		_root([profile])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"profiles[0].perception.path_awareness_radius|number <= sight_radius",
		"profiles[0].targeting.hunt_tags|field removed in schema v2",
		"profiles[0].targeting.flee_tags|field removed in schema v2",
		"profiles[0].targeting.player_weight|number >= 0.0",
		"profiles[0].targeting.territory_radius|number >= 0.0",
		"profiles[0].targeting.territory_weight|number >= 0.0",
		"profiles[0].movement.flee_distance|field removed in schema v2",
		"profiles[0].movement.orbit_radius|number >= 0.0",
		"profiles[0].movement.flee_distance|removed from movement in schema v4; use actions[].attack",
		"profiles[0].movement.charge_range|removed from movement in schema v4; use actions[].attack",
	])


func test_unknown_non_attack_action_preserves_legacy_bool_gap() -> void:
	var action: Dictionary = _approach_action()
	action["id"] = "ai_action_future"
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(
		_root([_profile("future", action)])
	)

	assert_true(result.is_valid)
	assert_eq(_failures, [
		"profiles[0].actions[0].id|registered id in enemy_ai_actions",
	])


func test_non_attack_action_rejects_attack_after_action_callback() -> void:
	var action: Dictionary = _approach_action()
	action["attack"] = {}
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(
		_root([_profile("forbidden", action)])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"profiles[0].actions[0].attack|forbidden for non-attack action",
	])


func test_attack_failures_continue_across_profiles_in_source_order() -> void:
	var explode: Dictionary = _explode_action()
	explode["attack"]["damage"] = 0.0
	explode["attack"]["future"] = true
	var melee: Dictionary = _melee_action()
	melee["attack"]["arc_degrees"] = 361.0
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(
		_root([
			_profile("explode_bad", explode),
			_profile("melee_bad", melee),
		])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"profiles[0].actions[0].attack.future|allowed schema field",
		"profiles[0].actions[0].attack.damage|number > 0.0",
		"profiles[1].actions[0].attack.arc_degrees|number <= 360.0",
	])


func test_charge_pair_bool_and_element_checks_keep_order() -> void:
	var action: Dictionary = _charge_action()
	action["attack"]["knockback_distance"] = 5.0
	action["attack"]["knockback_duration"] = 0.0
	action["attack"]["stop_on_hit"] = "false"
	action["attack"]["element_id"] = "element_missing"
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(
		_root([_profile("charge_bad", action)])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"profiles[0].actions[0].attack.knockback_duration|positive exactly when knockback_distance is positive",
		"profiles[0].actions[0].attack.stop_on_hit|bool",
		"profiles[0].actions[0].attack.element_id|registered id in elements",
	])


func test_ranged_projectile_type_short_circuits_after_prior_fields() -> void:
	var action: Dictionary = _ranged_action()
	action["attack"]["burst_count"] = 0
	action["attack"]["element_id"] = "element_missing"
	action["attack"]["projectile"] = null
	var result: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(
		_root([_profile("ranged_bad", action)])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"profiles[0].actions[0].attack.burst_count|int >= 1",
		"profiles[0].actions[0].attack.element_id|registered id in elements",
		"profiles[0].actions[0].attack.projectile|Dictionary",
	])


func test_validation_is_stateless_and_does_not_mutate_input() -> void:
	var root: Dictionary = _root([
		_profile("stable", _approach_action()),
	])
	var before: Dictionary = root.duplicate(true)
	var first: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(root)
	assert_true(first.is_valid)
	assert_eq(root, before)

	_clear_diagnostics()
	var second: ENEMY_AI_PROFILE_VALIDATOR.ValidationResult = _validate(root)
	assert_true(second.is_valid)
	assert_eq(second.profile_count, 1)
	assert_eq(_failures, [])


func _validate(raw_data: Variant) -> ENEMY_AI_PROFILE_VALIDATOR.ValidationResult:
	return ENEMY_AI_PROFILE_VALIDATOR.validate(
		raw_data,
		Callable(self, "_require_registered"),
		Callable(self, "_record_failure")
	)


func _require_registered(
	field: String,
	value: Variant,
	contract_id: String
) -> String:
	var text_value: String = String(value)
	_contract_calls.append("%s|%s|%s" % [field, contract_id, text_value])
	if (
		not value is String
		or text_value.is_empty()
		or not (_contracts.get(contract_id, {}) as Dictionary).has(text_value)
	):
		_record_failure(field, "registered id in %s" % contract_id)
		return ""
	return text_value


func _record_failure(field: String, expected: String) -> void:
	_failures.append("%s|%s" % [field, expected])


func _clear_diagnostics() -> void:
	_failures.clear()
	_contract_calls.clear()


func _root(profiles: Array) -> Dictionary:
	return {"schema_version": 5, "profiles": profiles}


func _profile(profile_id: String, action: Dictionary) -> Dictionary:
	return {
		"id": profile_id,
		"perception": {
			"sight_radius": 10.0,
			"path_awareness_radius": 5.0,
			"memory_duration": 0.0,
		},
		"decision_interval": 0.1,
		"targeting": {
			"player_weight": 1.0,
			"territory_radius": 0.0,
			"territory_weight": 0.0,
		},
		"movement": {"orbit_radius": 0.0},
		"actions": [action],
	}


func _approach_action() -> Dictionary:
	return {
		"id": "ai_action_approach_target",
		"base_score": 1.0,
		"speed_scale": 1.0,
	}


func _explode_action() -> Dictionary:
	return {
		"id": "ai_action_explode_target",
		"base_score": 1.0,
		"speed_scale": 1.0,
		"attack": {
			"trigger_range": 1.0,
			"windup": 1.0,
			"damage": 1.0,
			"element_id": "element_neutral",
			"radius": 1.0,
		},
	}


func _melee_action() -> Dictionary:
	return {
		"id": "ai_action_melee_attack",
		"base_score": 1.0,
		"speed_scale": 1.0,
		"attack": {
			"trigger_range": 1.0,
			"windup": 1.0,
			"cooldown": 1.0,
			"damage": 1.0,
			"element_id": "element_neutral",
			"range": 1.0,
			"arc_degrees": 360.0,
		},
	}


func _charge_action() -> Dictionary:
	return {
		"id": "ai_action_charge_target",
		"base_score": 1.0,
		"speed_scale": 1.0,
		"attack": {
			"trigger_range": 1.0,
			"windup": 1.0,
			"release_duration": 1.0,
			"cooldown": 1.0,
			"damage": 1.0,
			"element_id": "element_neutral",
			"speed_multiplier": 1.0,
			"stop_on_hit": false,
			"knockback_distance": 0.0,
			"knockback_duration": 0.0,
		},
	}


func _ranged_action() -> Dictionary:
	return {
		"id": "ai_action_ranged_attack",
		"base_score": 1.0,
		"speed_scale": 1.0,
		"attack": {
			"attack_range": 1.0,
			"keep_distance": 0.0,
			"windup": 1.0,
			"burst_count": 1,
			"shot_interval": 1.0,
			"cooldown": 1.0,
			"initial_cooldown": 0.0,
			"damage": 1.0,
			"element_id": "element_neutral",
			"projectile": {
				"pool_id": "bullet_basic",
				"speed": 1.0,
				"range": 1.0,
				"hit_radius": 1.0,
				"lifetime": 1.0,
				"muzzle_distance": 0.0,
			},
		},
	}
