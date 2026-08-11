extends SmokeHarness


const WEAPON_CATALOG_VALIDATOR := preload(
	"res://scripts/data/weapon_catalog_validator.gd"
)
const SUPPORTED_STATS: Array[String] = [
	"damage",
	"fire_rate",
	"bullet_speed",
	"bullet_range",
	"bullet_count",
	"pierce_count",
	"wall_pierce",
	"recoil",
	"spread_angle_max",
	"crit_chance",
	"crit_mult",
]

var _failures: Array[String] = []
var _events: Array[String] = []
var _invalid_locale_keys: Dictionary = {}
var _invalid_audio_ids: Dictionary = {}
var _invalid_stats: Dictionary = {}
var _contracts: Dictionary = {}


func before_each() -> void:
	super()
	_failures.clear()
	_events.clear()
	_invalid_locale_keys.clear()
	_invalid_audio_ids.clear()
	_invalid_stats.clear()
	_contracts = {
		"pool_ids": {"bullet_basic": true},
		"elements": {"element_neutral": true},
	}


func test_canonical_root_returns_count_and_callback_order() -> void:
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([_weapon("weapon_a")])
	)

	assert_true(result.is_valid)
	assert_eq(result.weapon_count, 1)
	assert_eq(_failures, [])
	assert_eq(_events, [
		"locale|weapons[0].name_key|weapon_name",
		"locale|weapons[0].desc_key|weapon_desc",
		"audio|weapons[0].fire_audio_id|sfx_player_shoot",
		"stat|weapons[0].base_stats.damage|damage|1.0",
		"stat|weapons[0].base_stats.fire_rate|fire_rate|1.0",
		"stat|weapons[0].base_stats.bullet_speed|bullet_speed|1.0",
		"stat|weapons[0].base_stats.bullet_range|bullet_range|1.0",
		"stat|weapons[0].base_stats.bullet_count|bullet_count|1",
		"stat|weapons[0].base_stats.wall_pierce|wall_pierce|0.0",
		"stat|weapons[0].base_stats.crit_chance|crit_chance|0.0",
		"stat|weapons[0].base_stats.crit_mult|crit_mult|1.5",
		"contract|weapons[0].projectile.pool_id|pool_ids|bullet_basic",
		"contract|weapons[0].projectile.element_id|elements|element_neutral",
	])


func test_root_and_weapons_shape_keep_dictionary_count_semantics() -> void:
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate([])
	assert_false(result.is_valid)
	assert_eq(result.weapon_count, 0)
	assert_eq(_failures, ["root|Dictionary"])
	assert_eq(_events, [])

	_clear_diagnostics()
	result = _validate({
		"schema_version": 5,
		"recoil_model": _recoil_model(),
		"weapons": {},
	})
	assert_false(result.is_valid)
	assert_eq(result.weapon_count, 0)
	assert_eq(_failures, [
		"weapons|Array",
		"weapons|non-empty Array",
	])


func test_schema_is_exact_int_like_five_and_empty_weapons_fail() -> void:
	var root: Dictionary = _root([])
	root["schema_version"] = 5.0
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(root)
	assert_false(result.is_valid)
	assert_eq(_failures, ["weapons|non-empty Array"])

	_clear_diagnostics()
	root["schema_version"] = 4
	result = _validate(root)
	assert_false(result.is_valid)
	assert_eq(_failures, [
		"schema_version|int >= 5",
		"weapons|non-empty Array",
	])


func test_recoil_shape_bounds_relation_and_source_order() -> void:
	var root: Dictionary = _root([])
	root["recoil_model"] = {
		"recoil_max": 0.0,
		"spread_exponent": 0.0,
		"kickback_max_distance": -1.0,
		"kickback_duration": 0.0,
		"kickback_velocity_cap": 0.0,
		"base_spread_cap": 61.0,
		"runtime_spread_cap": 40.0,
	}
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"recoil_model.recoil_max|number > 0.0",
		"recoil_model.spread_exponent|number > 0.0",
		"recoil_model.kickback_max_distance|number >= 0.0",
		"recoil_model.kickback_duration|number > 0.0",
		"recoil_model.kickback_velocity_cap|number > 0.0",
		"recoil_model.base_spread_cap|number <= 60.0",
		"recoil_model.runtime_spread_cap|value greater than or equal to base_spread_cap",
		"weapons|non-empty Array",
	])

	_clear_diagnostics()
	root["recoil_model"] = null
	result = _validate(root)
	assert_false(result.is_valid)
	assert_eq(_failures, [
		"recoil_model|non-empty Dictionary",
		"weapons|non-empty Array",
	])


func test_weapon_shape_exact_keys_duplicates_and_raw_count_continue() -> void:
	var first: Dictionary = _weapon("duplicate")
	var second: Dictionary = _weapon("duplicate")
	second.erase("desc_key")
	second["ammo"] = {}
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([null, first, second])
	)

	assert_false(result.is_valid)
	assert_eq(result.weapon_count, 3)
	assert_eq(_failures, [
		"weapons[0]|Dictionary",
		"weapons[2].desc_key|required field",
		"weapons[2].ammo|allowed schema field",
		"weapons[2].id|unique weapon id",
		"weapons[2].desc_key|locale callback",
	])


func test_callback_failures_continue_through_weapon_fields() -> void:
	_invalid_locale_keys = {"weapon_name": true, "weapon_desc": true}
	_invalid_audio_ids = {"sfx_player_shoot": true}
	_invalid_stats = {"damage": true}
	var weapon: Dictionary = _weapon("callbacks")
	weapon["default_unlocked"] = "true"
	weapon["fire_mode"] = ""
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([weapon])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"weapons[0].name_key|locale callback",
		"weapons[0].desc_key|locale callback",
		"weapons[0].default_unlocked|bool",
		"weapons[0].fire_mode|non-empty string",
		"weapons[0].fire_audio_id|audio callback",
		"weapons[0].base_stats.damage|stat callback",
	])
	assert_true(_events.has(
		"contract|weapons[0].projectile.element_id|elements|element_neutral"
	))


func test_required_supported_and_empty_stats_keep_local_short_circuit() -> void:
	var weapon: Dictionary = _weapon("stats")
	weapon["base_stats"] = {"future_stat": 1.0}
	weapon["projectile"]["hit_radius"] = 0.0
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([weapon])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"weapons[0].base_stats.damage|required weapon stat",
		"weapons[0].base_stats.fire_rate|required weapon stat",
		"weapons[0].base_stats.bullet_speed|required weapon stat",
		"weapons[0].base_stats.bullet_range|required weapon stat",
		"weapons[0].base_stats.bullet_count|required weapon stat",
		"weapons[0].base_stats.recoil|required weapon stat",
		"weapons[0].base_stats.spread_angle_max|required weapon stat",
		"weapons[0].base_stats.future_stat|supported weapon stat",
		"weapons[0].projectile.hit_radius|number > 0.0",
	])

	_clear_diagnostics()
	weapon["base_stats"] = {}
	result = _validate(_root([weapon]))
	assert_false(result.is_valid)
	assert_eq(_failures, [
		"weapons[0].base_stats|non-empty Dictionary",
		"weapons[0].projectile.hit_radius|number > 0.0",
	])


func test_special_stats_use_recoil_caps_and_int_like_rules() -> void:
	var weapon: Dictionary = _weapon("special")
	weapon["base_stats"]["pierce_count"] = -1
	weapon["base_stats"]["recoil"] = 101.0
	weapon["base_stats"]["spread_angle_max"] = 61.0
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([weapon])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"weapons[0].base_stats.pierce_count|int >= 0",
		"weapons[0].base_stats.recoil|number <= 100.0",
		"weapons[0].base_stats.spread_angle_max|number <= 60.0",
	])

	_clear_diagnostics()
	weapon["base_stats"]["pierce_count"] = 1.0
	weapon["base_stats"]["recoil"] = 100.0
	weapon["base_stats"]["spread_angle_max"] = 60.0
	result = _validate(_root([weapon]))
	assert_true(result.is_valid)


func test_projectile_shape_contracts_and_numbers_keep_order() -> void:
	var weapon: Dictionary = _weapon("projectile")
	weapon["projectile"] = {
		"pool_id": "pool_missing",
		"element_id": "element_missing",
		"hit_radius": 0.0,
		"muzzle_distance": 0.0,
		"lifetime": 0.0,
	}
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([weapon])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"weapons[0].projectile.pool_id|registered id in pool_ids",
		"weapons[0].projectile.element_id|registered id in elements",
		"weapons[0].projectile.hit_radius|number > 0.0",
		"weapons[0].projectile.muzzle_distance|number > 0.0",
		"weapons[0].projectile.lifetime|number > 0.0",
	])

	_clear_diagnostics()
	weapon["projectile"] = null
	result = _validate(_root([weapon]))
	assert_false(result.is_valid)
	assert_eq(_failures, ["weapons[0].projectile|Dictionary"])


func test_audio_key_is_required_but_callback_is_conditional() -> void:
	var weapon: Dictionary = _weapon("silent")
	weapon.erase("fire_audio_id")
	weapon["presentation_profile_id"] = null
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(
		_root([weapon])
	)

	assert_false(result.is_valid)
	assert_eq(_failures, [
		"weapons[0].fire_audio_id|required field",
	])
	for event: String in _events:
		assert_false(event.begins_with("audio|"))


func test_root_recoil_projectile_extras_and_presentation_value_are_ignored() -> void:
	var weapon: Dictionary = _weapon("compatibility")
	weapon["presentation_profile_id"] = null
	weapon["projectile"]["future"] = true
	var root: Dictionary = _root([weapon])
	root["future"] = true
	root["recoil_model"]["future"] = true
	var result: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(root)

	assert_true(result.is_valid)
	assert_eq(result.weapon_count, 1)
	assert_eq(_failures, [])


func test_calls_are_stateless_and_do_not_mutate_inputs() -> void:
	var root: Dictionary = _root([_weapon("stable")])
	var before: Dictionary = root.duplicate(true)
	var first: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(root)
	assert_true(first.is_valid)
	assert_eq(root, before)

	_clear_diagnostics()
	var second: WEAPON_CATALOG_VALIDATOR.ValidationResult = _validate(root)
	assert_true(second.is_valid)
	assert_eq(second.weapon_count, 1)
	assert_eq(root, before)


func _validate(raw_data: Variant) -> WEAPON_CATALOG_VALIDATOR.ValidationResult:
	return WEAPON_CATALOG_VALIDATOR.validate(
		raw_data,
		SUPPORTED_STATS,
		Callable(self, "_require_locale_key"),
		Callable(self, "_require_audio_id"),
		Callable(self, "_validate_stat_value"),
		Callable(self, "_require_registered"),
		Callable(self, "_record_failure")
	)


func _require_locale_key(field: String, value: Variant) -> bool:
	var text_value: String = String(value) if value is String else ""
	_events.append("locale|%s|%s" % [field, text_value])
	if text_value.is_empty() or _invalid_locale_keys.has(text_value):
		_record_failure(field, "locale callback")
		return false
	return true


func _require_audio_id(field: String, value: Variant) -> bool:
	var text_value: String = String(value) if value is String else ""
	_events.append("audio|%s|%s" % [field, text_value])
	if text_value.is_empty() or _invalid_audio_ids.has(text_value):
		_record_failure(field, "audio callback")
		return false
	return true


func _validate_stat_value(
	field: String,
	stat: String,
	value: Variant
) -> bool:
	_events.append("stat|%s|%s|%s" % [field, stat, str(value)])
	if _invalid_stats.has(stat):
		_record_failure(field, "stat callback")
		return false
	return true


func _require_registered(
	field: String,
	value: Variant,
	contract_id: String
) -> String:
	var text_value: String = String(value) if value is String else ""
	_events.append(
		"contract|%s|%s|%s" % [field, contract_id, text_value]
	)
	if (
		text_value.is_empty()
		or not (_contracts.get(contract_id, {}) as Dictionary).has(text_value)
	):
		_record_failure(field, "registered id in %s" % contract_id)
		return ""
	return text_value


func _record_failure(field: String, expected: String) -> void:
	_failures.append("%s|%s" % [field, expected])


func _clear_diagnostics() -> void:
	_failures.clear()
	_events.clear()


func _root(weapons: Array) -> Dictionary:
	return {
		"schema_version": 5,
		"recoil_model": _recoil_model(),
		"weapons": weapons,
	}


func _recoil_model() -> Dictionary:
	return {
		"recoil_max": 100.0,
		"spread_exponent": 1.5,
		"kickback_max_distance": 14.0,
		"kickback_duration": 0.08,
		"kickback_velocity_cap": 500.0,
		"base_spread_cap": 60.0,
		"runtime_spread_cap": 180.0,
	}


func _weapon(weapon_id: String) -> Dictionary:
	return {
		"id": weapon_id,
		"name_key": "weapon_name",
		"desc_key": "weapon_desc",
		"default_unlocked": true,
		"fire_mode": "hold_mouse",
		"fire_audio_id": "sfx_player_shoot",
		"presentation_profile_id": "presentation_weapon_default",
		"base_stats": {
			"damage": 1.0,
			"fire_rate": 1.0,
			"bullet_speed": 1.0,
			"bullet_range": 1.0,
			"bullet_count": 1,
			"pierce_count": 0,
			"wall_pierce": 0.0,
			"recoil": 20.0,
			"spread_angle_max": 60.0,
			"crit_chance": 0.0,
			"crit_mult": 1.5,
		},
		"projectile": {
			"pool_id": "bullet_basic",
			"element_id": "element_neutral",
			"hit_radius": 1.0,
			"muzzle_distance": 1.0,
			"lifetime": 1.0,
		},
	}
