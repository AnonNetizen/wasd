# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyAiProfileValidator
extends RefCounted
## Validates already loaded Enemy AI profile data without owning data sources.


const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)


class ValidationResult:
	extends RefCounted

	var is_valid: bool = true
	var profile_count: int = 0


static func validate(
	raw_data: Variant,
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
	var profiles: Array = _require_array(
		"profiles",
		payload.get("profiles"),
		report_failure
	)
	if profiles.is_empty():
		_report_failure(report_failure, "profiles", "non-empty Array")
		result.is_valid = false
	result.profile_count = profiles.size()

	var seen: Dictionary = {}
	for index: int in range(profiles.size()):
		result.is_valid = _validate_profile(
			index,
			profiles[index],
			seen,
			require_registered,
			report_failure
		) and result.is_valid
	return result


static func _validate_profile(
	index: int,
	raw_profile: Variant,
	seen: Dictionary,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var field: String = "profiles[%d]" % index
	if not raw_profile is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false

	var profile: Dictionary = raw_profile as Dictionary
	var is_valid: bool = true
	is_valid = _require_non_empty_string(
		"%s.id" % field,
		profile.get("id"),
		report_failure
	) and is_valid
	var profile_id: String = String(profile.get("id", ""))
	if not profile_id.is_empty():
		if seen.has(profile_id):
			_report_failure(
				report_failure,
				"%s.id" % field,
				"unique profile id"
			)
			is_valid = false
		seen[profile_id] = true
	is_valid = _reject_removed_field(
		field,
		profile,
		"contact_interval",
		2,
		report_failure
	) and is_valid
	is_valid = _reject_removed_field(
		field,
		profile,
		"sense_radius",
		3,
		report_failure
	) and is_valid
	is_valid = _validate_perception(
		"%s.perception" % field,
		profile.get("perception"),
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.decision_interval" % field,
		profile.get("decision_interval"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _validate_targeting(
		"%s.targeting" % field,
		profile.get("targeting"),
		report_failure
	) and is_valid
	is_valid = _validate_movement(
		"%s.movement" % field,
		profile.get("movement"),
		report_failure
	) and is_valid
	is_valid = _validate_actions(
		"%s.actions" % field,
		profile.get("actions"),
		require_registered,
		report_failure
	) and is_valid
	return is_valid


static func _validate_perception(
	field: String,
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false
	var payload: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	is_valid = _require_number(
		"%s.sight_radius" % field,
		payload.get("sight_radius"),
		0.0,
		null,
		true,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.path_awareness_radius" % field,
		payload.get("path_awareness_radius"),
		0.0,
		null,
		false,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.memory_duration" % field,
		payload.get("memory_duration"),
		0.0,
		null,
		false,
		report_failure
	) and is_valid
	var sight_radius: Variant = payload.get("sight_radius")
	var path_awareness_radius: Variant = payload.get(
		"path_awareness_radius"
	)
	if (
		(sight_radius is int or sight_radius is float)
		and (
			path_awareness_radius is int
			or path_awareness_radius is float
		)
		and float(path_awareness_radius) > float(sight_radius)
	):
		_report_failure(
			report_failure,
			"%s.path_awareness_radius" % field,
			"number <= sight_radius"
		)
		is_valid = false
	return is_valid


static func _validate_targeting(
	field: String,
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false
	var payload: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	is_valid = _reject_removed_field(
		field,
		payload,
		"hunt_tags",
		2,
		report_failure
	) and is_valid
	is_valid = _reject_removed_field(
		field,
		payload,
		"flee_tags",
		2,
		report_failure
	) and is_valid
	for key: String in [
		"player_weight",
		"territory_radius",
		"territory_weight",
	]:
		is_valid = _require_number(
			"%s.%s" % [field, key],
			payload.get(key),
			0.0,
			null,
			false,
			report_failure
		) and is_valid
	return is_valid


static func _validate_movement(
	field: String,
	raw_data: Variant,
	report_failure: Callable
) -> bool:
	if not raw_data is Dictionary:
		_report_failure(report_failure, field, "Dictionary")
		return false
	var payload: Dictionary = raw_data as Dictionary
	var is_valid: bool = true
	is_valid = _reject_removed_field(
		field,
		payload,
		"flee_distance",
		2,
		report_failure
	) and is_valid
	is_valid = _require_number(
		"%s.orbit_radius" % field,
		payload.get("orbit_radius"),
		0.0,
		null,
		false,
		report_failure
	) and is_valid
	for raw_key: Variant in payload.keys():
		var key: String = String(raw_key)
		if key != "orbit_radius":
			_report_failure(
				report_failure,
				"%s.%s" % [field, key],
				"removed from movement in schema v4; use actions[].attack"
			)
			is_valid = false
	return is_valid


static func _validate_actions(
	field: String,
	raw_data: Variant,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var entries: Array = _require_array(field, raw_data, report_failure)
	var is_valid: bool = true
	if entries.is_empty():
		_report_failure(report_failure, field, "non-empty Array")
		is_valid = false
	var seen: Dictionary = {}
	for index: int in range(entries.size()):
		var item_field: String = "%s[%d]" % [field, index]
		var raw_entry: Variant = entries[index]
		if not raw_entry is Dictionary:
			_report_failure(report_failure, item_field, "Dictionary")
			is_valid = false
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var action_id: String = String(require_registered.call(
			"%s.id" % item_field,
			entry.get("id"),
			"enemy_ai_actions"
		))
		if not action_id.is_empty():
			if seen.has(action_id):
				_report_failure(
					report_failure,
					"%s.id" % item_field,
					"unique action id"
				)
				is_valid = false
			seen[action_id] = true
		is_valid = _require_number(
			"%s.base_score" % item_field,
			entry.get("base_score"),
			0.0,
			null,
			false,
			report_failure
		) and is_valid
		is_valid = _require_number(
			"%s.speed_scale" % item_field,
			entry.get("speed_scale"),
			0.0,
			null,
			true,
			report_failure
		) and is_valid
		is_valid = _validate_attack(
			item_field,
			action_id,
			entry,
			require_registered,
			report_failure
		) and is_valid
	return is_valid


static func _validate_attack(
	item_field: String,
	action_id: String,
	action: Dictionary,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	if not _is_attack_action(action_id):
		if action.has("attack"):
			_report_failure(
				report_failure,
				"%s.attack" % item_field,
				"forbidden for non-attack action"
			)
			return false
		return true
	var raw_attack: Variant = action.get("attack")
	if not raw_attack is Dictionary:
		_report_failure(
			report_failure,
			"%s.attack" % item_field,
			"Dictionary"
		)
		return false
	var attack: Dictionary = raw_attack as Dictionary
	var field: String = "%s.attack" % item_field
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET:
		return _validate_explode_attack(
			field,
			attack,
			require_registered,
			report_failure
		)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK:
		return _validate_melee_attack(
			field,
			attack,
			require_registered,
			report_failure
		)
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET:
		return _validate_charge_attack(
			field,
			attack,
			require_registered,
			report_failure
		)
	return _validate_ranged_attack(
		field,
		attack,
		require_registered,
		report_failure
	)


static func _validate_explode_attack(
	field: String,
	attack: Dictionary,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var is_valid: bool = _validate_exact_dictionary_keys(
		field,
		attack,
		["trigger_range", "windup", "damage", "element_id", "radius"],
		report_failure
	)
	for key: String in ["trigger_range", "windup", "damage", "radius"]:
		is_valid = _require_number(
			"%s.%s" % [field, key],
			attack.get(key),
			0.0,
			null,
			true,
			report_failure
		) and is_valid
	is_valid = not String(require_registered.call(
		"%s.element_id" % field,
		attack.get("element_id"),
		"elements"
	)).is_empty() and is_valid
	return is_valid


static func _validate_melee_attack(
	field: String,
	attack: Dictionary,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var is_valid: bool = _validate_exact_dictionary_keys(
		field,
		attack,
		[
			"trigger_range",
			"windup",
			"cooldown",
			"damage",
			"element_id",
			"range",
			"arc_degrees",
		],
		report_failure
	)
	for key: String in [
		"trigger_range",
		"windup",
		"cooldown",
		"damage",
		"range",
	]:
		is_valid = _require_number(
			"%s.%s" % [field, key],
			attack.get(key),
			0.0,
			null,
			true,
			report_failure
		) and is_valid
	is_valid = _require_number(
		"%s.arc_degrees" % field,
		attack.get("arc_degrees"),
		0.0,
		360.0,
		true,
		report_failure
	) and is_valid
	is_valid = not String(require_registered.call(
		"%s.element_id" % field,
		attack.get("element_id"),
		"elements"
	)).is_empty() and is_valid
	return is_valid


static func _validate_charge_attack(
	field: String,
	attack: Dictionary,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var is_valid: bool = _validate_exact_dictionary_keys(
		field,
		attack,
		[
			"trigger_range",
			"windup",
			"release_duration",
			"cooldown",
			"damage",
			"element_id",
			"speed_multiplier",
			"stop_on_hit",
			"knockback_distance",
			"knockback_duration",
		],
		report_failure
	)
	for key: String in [
		"trigger_range",
		"windup",
		"release_duration",
		"cooldown",
		"damage",
		"speed_multiplier",
	]:
		is_valid = _require_number(
			"%s.%s" % [field, key],
			attack.get(key),
			0.0,
			null,
			true,
			report_failure
		) and is_valid
	for key: String in ["knockback_distance", "knockback_duration"]:
		is_valid = _require_number(
			"%s.%s" % [field, key],
			attack.get(key),
			0.0,
			null,
			false,
			report_failure
		) and is_valid
	var knockback_distance: float = float(
		attack.get("knockback_distance", 0.0)
	)
	var knockback_duration: float = float(
		attack.get("knockback_duration", 0.0)
	)
	if (knockback_distance > 0.0) != (knockback_duration > 0.0):
		_report_failure(
			report_failure,
			"%s.knockback_duration" % field,
			"positive exactly when knockback_distance is positive"
		)
		is_valid = false
	is_valid = _require_bool(
		"%s.stop_on_hit" % field,
		attack.get("stop_on_hit"),
		report_failure
	) and is_valid
	is_valid = not String(require_registered.call(
		"%s.element_id" % field,
		attack.get("element_id"),
		"elements"
	)).is_empty() and is_valid
	return is_valid


static func _validate_ranged_attack(
	field: String,
	attack: Dictionary,
	require_registered: Callable,
	report_failure: Callable
) -> bool:
	var is_valid: bool = _validate_exact_dictionary_keys(
		field,
		attack,
		[
			"attack_range",
			"keep_distance",
			"windup",
			"burst_count",
			"shot_interval",
			"cooldown",
			"initial_cooldown",
			"damage",
			"element_id",
			"projectile",
		],
		report_failure
	)
	for key: String in [
		"attack_range",
		"windup",
		"shot_interval",
		"cooldown",
		"damage",
	]:
		is_valid = _require_number(
			"%s.%s" % [field, key],
			attack.get(key),
			0.0,
			null,
			true,
			report_failure
		) and is_valid
	is_valid = _require_int(
		"%s.burst_count" % field,
		attack.get("burst_count"),
		1,
		null,
		report_failure
	) and is_valid
	for key: String in ["keep_distance", "initial_cooldown"]:
		is_valid = _require_number(
			"%s.%s" % [field, key],
			attack.get(key),
			0.0,
			null,
			false,
			report_failure
		) and is_valid
	is_valid = not String(require_registered.call(
		"%s.element_id" % field,
		attack.get("element_id"),
		"elements"
	)).is_empty() and is_valid
	var raw_projectile: Variant = attack.get("projectile")
	if not raw_projectile is Dictionary:
		_report_failure(
			report_failure,
			"%s.projectile" % field,
			"Dictionary"
		)
		return false
	var projectile: Dictionary = raw_projectile as Dictionary
	var projectile_field: String = "%s.projectile" % field
	is_valid = _validate_exact_dictionary_keys(
		projectile_field,
		projectile,
		["pool_id", "speed", "range", "hit_radius", "lifetime", "muzzle_distance"],
		report_failure
	) and is_valid
	is_valid = not String(require_registered.call(
		"%s.pool_id" % projectile_field,
		projectile.get("pool_id"),
		"pool_ids"
	)).is_empty() and is_valid
	for key: String in ["speed", "range", "hit_radius", "lifetime"]:
		is_valid = _require_number(
			"%s.%s" % [projectile_field, key],
			projectile.get(key),
			0.0,
			null,
			true,
			report_failure
		) and is_valid
	is_valid = _require_number(
		"%s.muzzle_distance" % projectile_field,
		projectile.get("muzzle_distance"),
		0.0,
		null,
		false,
		report_failure
	) and is_valid
	return is_valid


static func _is_attack_action(action_id: String) -> bool:
	return action_id in [
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
		ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK,
		ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET,
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK,
	]


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


static func _reject_removed_field(
	parent_field: String,
	payload: Dictionary,
	key: String,
	schema_version: int,
	report_failure: Callable
) -> bool:
	if not payload.has(key):
		return true
	_report_failure(
		report_failure,
		"%s.%s" % [parent_field, key],
		"field removed in schema v%d" % schema_version
	)
	return false


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
