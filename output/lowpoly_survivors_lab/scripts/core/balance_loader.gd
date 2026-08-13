class_name LowpolyBalanceLoader
extends RefCounted

const DEFAULT_PATH: String = "res://data/balance.json"
const REQUIRED_ENEMY_IDS: Array[String] = [
	"enemy_small", "enemy_flying", "enemy_large", "enemy_fox_mech", "final_boss"
]
const REQUIRED_WEAPON_IDS: Array[String] = ["pulse_rifle", "orbital_drone", "ion_pulse"]
const REQUIRED_PASSIVE_IDS: Array[String] = [
	"passive_damage", "passive_cooldown", "passive_move_speed",
	"passive_max_health", "passive_pickup_range"
]
const REQUIRED_ANIMATION_PROFILE_IDS: Array[String] = [
	"player", "enemy_small", "enemy_flying", "enemy_large", "enemy_fox_mech", "final_boss"
]

var _data: Dictionary = {}
var _errors: PackedStringArray = []


func load_balance(path: String = DEFAULT_PATH) -> bool:
	_data.clear()
	_errors.clear()
	if not FileAccess.file_exists(path):
		_errors.append("balance file does not exist: %s" % path)
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_errors.append("balance file cannot be opened: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_errors.append("balance root must be an object: %s" % path)
		return false
	_data = parsed as Dictionary
	_validate()
	if not _errors.is_empty():
		_data.clear()
	return _errors.is_empty()


func get_data() -> Dictionary:
	return _data.duplicate(true)


func get_run_config() -> Dictionary:
	return _section("run")


func get_player_config() -> Dictionary:
	return _section("player")


func get_enemy_config(enemy_id: StringName) -> Dictionary:
	return _nested_section("enemies", String(enemy_id))


func get_weapon_config(weapon_id: StringName) -> Dictionary:
	return _nested_section("weapons", String(weapon_id))


func get_passive_config(passive_id: StringName) -> Dictionary:
	return _nested_section("passives", String(passive_id))


func get_animation_config(profile_id: StringName) -> Dictionary:
	return _nested_section("animations", String(profile_id))


func get_stages() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in _data.get("stages", []):
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


func get_experience_config() -> Dictionary:
	return _section("experience")


func get_errors() -> PackedStringArray:
	return _errors.duplicate()


func is_loaded() -> bool:
	return not _data.is_empty() and _errors.is_empty()


func _section(key: String) -> Dictionary:
	var value: Variant = _data.get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _nested_section(section: String, key: String) -> Dictionary:
	var parent: Variant = _data.get(section, {})
	if not parent is Dictionary:
		return {}
	var value: Variant = (parent as Dictionary).get(key, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _validate() -> void:
	_require_int("schema_version", 1, 1)
	for section: String in ["run", "player", "enemies", "weapons", "passives", "animations", "experience"]:
		_require_dictionary(section)
	_validate_run()
	_validate_player()
	_validate_stages()
	_validate_enemies()
	_validate_upgrades("weapons", REQUIRED_WEAPON_IDS)
	_validate_upgrades("passives", REQUIRED_PASSIVE_IDS)
	_validate_animation_profiles()
	var experience: Dictionary = _section("experience")
	_require_positive_number_in(experience, "experience", "base_required")
	_require_positive_number_in(experience, "experience", "growth")
	_require_positive_number_in(experience, "experience", "flat_growth")


func _validate_run() -> void:
	var run: Dictionary = _section("run")
	for key: String in ["duration_seconds", "arena_half_extent", "spawn_min_distance", "spawn_max_distance"]:
		_require_positive_number_in(run, "run", key)
	_require_nonnegative_int_in(run, "run", "fixed_test_seed")
	for key: String in ["regular_enemy_cap", "enemy_projectile_cap", "player_projectile_cap", "pickup_cap", "effect_cap"]:
		_require_positive_int_in(run, "run", key)
	if float(run.get("spawn_max_distance", 0.0)) <= float(run.get("spawn_min_distance", 0.0)):
		_errors.append("run.spawn_max_distance must exceed spawn_min_distance")
	var elite_times: Variant = run.get("elite_times")
	if not elite_times is Array or (elite_times as Array).size() != 3:
		_errors.append("run.elite_times must contain exactly three values")
	else:
		var previous: float = 0.0
		var duration: float = float(run.get("duration_seconds", 0.0))
		for index: int in range((elite_times as Array).size()):
			var value: Variant = (elite_times as Array)[index]
			if not value is int and not value is float:
				_errors.append("run.elite_times[%d] must be a number" % index)
				continue
			var time: float = float(value)
			if time <= previous or time >= duration:
				_errors.append("run.elite_times must be strictly ordered within the run")
				break
			previous = time


func _validate_player() -> void:
	var player: Dictionary = _section("player")
	for key: String in ["max_health", "move_speed", "pickup_radius", "contact_invulnerability"]:
		_require_positive_number_in(player, "player", key)
	_require_resource_in(player, "player", "model_path")
	_require_animation_profile_in(player, "player")


func _validate_stages() -> void:
	var stages: Variant = _data.get("stages")
	if not stages is Array or (stages as Array).size() != 4:
		_errors.append("stages must contain exactly four stage objects")
		return
	var expected_start: float = 0.0
	for index: int in range((stages as Array).size()):
		var value: Variant = (stages as Array)[index]
		if not value is Dictionary:
			_errors.append("stages[%d] must be an object" % index)
			continue
		var stage: Dictionary = value as Dictionary
		var start: float = float(stage.get("start", -1.0))
		var end: float = float(stage.get("end", -1.0))
		if not is_equal_approx(start, expected_start) or end <= start:
			_errors.append("stages[%d] has a gap, overlap, or invalid range" % index)
		expected_start = end
		_require_positive_number_in(stage, "stages[%d]" % index, "spawn_interval")
		_require_positive_int_in(stage, "stages[%d]" % index, "batch")
		var weights: Variant = stage.get("weights")
		if not weights is Dictionary or (weights as Dictionary).is_empty():
			_errors.append("stages[%d].weights must not be empty" % index)
			continue
		for enemy_id: Variant in (weights as Dictionary).keys():
			if not REQUIRED_ENEMY_IDS.has(String(enemy_id)) or String(enemy_id) == "final_boss":
				_errors.append("stages[%d] contains unknown regular enemy: %s" % [index, enemy_id])
			if float((weights as Dictionary)[enemy_id]) <= 0.0:
				_errors.append("stages[%d].weights.%s must be positive" % [index, enemy_id])
	var duration: float = float(_section("run").get("duration_seconds", 0.0))
	if not is_equal_approx(expected_start, duration):
		_errors.append("last stage must end at run.duration_seconds")


func _validate_enemies() -> void:
	var enemies: Dictionary = _section("enemies")
	for enemy_id: String in REQUIRED_ENEMY_IDS:
		var value: Variant = enemies.get(enemy_id)
		if not value is Dictionary:
			_errors.append("enemies.%s must be an object" % enemy_id)
			continue
		var config: Dictionary = value as Dictionary
		for key: String in ["health", "speed", "damage", "attack_cooldown", "radius"]:
			_require_positive_number_in(config, "enemies.%s" % enemy_id, key)
		_require_nonnegative_int_in(config, "enemies.%s" % enemy_id, "xp")
		_require_positive_int_in(config, "enemies.%s" % enemy_id, "pool")
		_require_resource_in(config, "enemies.%s" % enemy_id, "model_path")
		_require_animation_profile_in(config, "enemies.%s" % enemy_id)
		if enemy_id == "enemy_flying":
			_require_positive_number_in(config, "enemies.%s" % enemy_id, "flying_height")
		if enemy_id == "enemy_fox_mech" or enemy_id == "final_boss":
			_require_positive_number_in(config, "enemies.%s" % enemy_id, "preferred_range")
			_require_positive_number_in(config, "enemies.%s" % enemy_id, "projectile_speed")


func _validate_upgrades(section_name: String, required_ids: Array[String]) -> void:
	var section: Dictionary = _section(section_name)
	for item_id: String in required_ids:
		var value: Variant = section.get(item_id)
		if not value is Dictionary:
			_errors.append("%s.%s must be an object" % [section_name, item_id])
			continue
		var config: Dictionary = value as Dictionary
		for key: String in ["name", "description"]:
			if not config.get(key) is String or String(config.get(key)).is_empty():
				_errors.append("%s.%s.%s must be a non-empty string" % [section_name, item_id, key])
		_require_positive_int_in(config, "%s.%s" % [section_name, item_id], "max_level")
		if int(config.get("max_level", 0)) != 5:
			_errors.append("%s.%s.max_level must be 5" % [section_name, item_id])
		if section_name == "weapons":
			_require_positive_number_in(config, "%s.%s" % [section_name, item_id], "base_damage")
			_require_positive_number_in(config, "%s.%s" % [section_name, item_id], "cooldown")
			if item_id == "pulse_rifle":
				_require_positive_number_in(config, "weapons.pulse_rifle", "projectile_speed")
				_require_positive_number_in(config, "weapons.pulse_rifle", "range")
				_require_resource_in(config, "weapons.pulse_rifle", "model_path")
			elif item_id == "orbital_drone" or item_id == "ion_pulse":
				_require_positive_number_in(config, "weapons.%s" % item_id, "radius")
		else:
			_require_positive_number_in(config, "%s.%s" % [section_name, item_id], "per_level")


func _validate_animation_profiles() -> void:
	var animations: Dictionary = _section("animations")
	for profile_id: String in REQUIRED_ANIMATION_PROFILE_IDS:
		var value: Variant = animations.get(profile_id)
		if not value is Dictionary:
			_errors.append("animations.%s must be an object" % profile_id)
			continue
		var profile := value as Dictionary
		var required_states: Array[String] = ["idle", "move", "hit", "death"]
		required_states.append("fire" if profile_id == "player" else "attack")
		if profile_id == "final_boss":
			required_states.append_array(["attack_aimed", "attack_radial", "summon"])
		for state: String in required_states:
			_require_nonempty_string_in(profile, "animations.%s" % profile_id, state)
		for key: String in ["blend_seconds", "move_speed_scale", "hit_cooldown"]:
			_require_positive_number_in(profile, "animations.%s" % profile_id, key)
		if profile_id != "player":
			_require_positive_number_in(profile, "animations.%s" % profile_id, "death_hold")


func _require_dictionary(key: String) -> void:
	if not _data.get(key) is Dictionary:
		_errors.append("%s must be an object" % key)


func _require_int(key: String, minimum: int, maximum: int) -> void:
	var value: Variant = _data.get(key)
	if not _is_integral_number(value) or int(value) < minimum or int(value) > maximum:
		_errors.append("%s must be an integer in [%d, %d]" % [key, minimum, maximum])


func _require_positive_number_in(data: Dictionary, path: String, key: String) -> void:
	var value: Variant = data.get(key)
	if not value is int and not value is float or float(value) <= 0.0:
		_errors.append("%s.%s must be a positive number" % [path, key])


func _require_positive_int_in(data: Dictionary, path: String, key: String) -> void:
	var value: Variant = data.get(key)
	if not _is_integral_number(value) or int(value) <= 0:
		_errors.append("%s.%s must be a positive integer" % [path, key])


func _require_nonnegative_int_in(data: Dictionary, path: String, key: String) -> void:
	var value: Variant = data.get(key)
	if not _is_integral_number(value) or int(value) < 0:
		_errors.append("%s.%s must be a nonnegative integer" % [path, key])


func _require_nonempty_string_in(data: Dictionary, path: String, key: String) -> void:
	var value: Variant = data.get(key)
	if not value is String or String(value).is_empty():
		_errors.append("%s.%s must be a non-empty string" % [path, key])


func _require_animation_profile_in(data: Dictionary, path: String) -> void:
	var value: Variant = data.get("animation_profile")
	if not value is String or String(value).is_empty():
		_errors.append("%s.animation_profile must be a non-empty string" % path)
		return
	var animations: Dictionary = _section("animations")
	if not animations.get(String(value)) is Dictionary:
		_errors.append("%s.animation_profile references an unknown profile: %s" % [path, value])


func _is_integral_number(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_equal_approx(value, roundf(value))
	return false


func _require_resource_in(data: Dictionary, path: String, key: String) -> void:
	var value: Variant = data.get(key)
	if not value is String or String(value).is_empty():
		_errors.append("%s.%s must be a resource path" % [path, key])
		return
	if not ResourceLoader.exists(String(value)):
		_errors.append("%s.%s resource does not exist: %s" % [path, key, value])
