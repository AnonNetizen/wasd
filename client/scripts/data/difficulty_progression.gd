# Doc: docs/代码/difficulty_progression.md
# Authority: docs/决策记录.md ADR #166
class_name DifficultyProgression
extends RefCounted
## Tracks mode-level threat time and resolves deterministic enemy spawn multipliers.


const SNAPSHOT_SCHEMA_VERSION: int = 1

var _profile_id: String = ""
var _tier_interval_seconds: float = 90.0
var _continuous_growth_per_interval: float = 0.04
var _tier_step_growth: float = 0.09
var _damage_growth_ratio: float = 0.48
var _stage_name_keys: Array[String] = []
var _elapsed: float = 0.0
var _enabled: bool = false


func configure(profile: Dictionary, enabled: bool = true) -> bool:
	var profile_id: String = String(profile.get("id", ""))
	var interval: float = float(profile.get("tier_interval_seconds", 0.0))
	var continuous_growth: float = float(
		profile.get("continuous_growth_per_interval", -1.0)
	)
	var tier_growth: float = float(profile.get("tier_step_growth", -1.0))
	var damage_ratio: float = float(profile.get("damage_growth_ratio", -1.0))
	var stage_name_values: Variant = profile.get("stage_name_keys")
	if (
		profile_id.is_empty()
		or not is_finite(interval)
		or interval <= 0.0
		or not is_finite(continuous_growth)
		or continuous_growth < 0.0
		or not is_finite(tier_growth)
		or tier_growth < 0.0
		or not is_finite(damage_ratio)
		or damage_ratio < 0.0
		or not stage_name_values is Array
		or (stage_name_values as Array).is_empty()
	):
		_clear()
		return false

	var parsed_stage_names: Array[String] = []
	for value: Variant in stage_name_values as Array:
		var name_key: String = String(value)
		if name_key.is_empty():
			_clear()
			return false
		parsed_stage_names.append(name_key)

	_profile_id = profile_id
	_tier_interval_seconds = interval
	_continuous_growth_per_interval = continuous_growth
	_tier_step_growth = tier_growth
	_damage_growth_ratio = damage_ratio
	_stage_name_keys = parsed_stage_names
	_elapsed = 0.0
	_enabled = enabled
	return true


func advance(delta: float) -> void:
	if not _enabled or delta <= 0.0 or not is_finite(delta):
		return
	var next_elapsed: float = _elapsed + delta
	if is_finite(next_elapsed):
		_elapsed = next_elapsed


func current_snapshot() -> Dictionary:
	var tier: int = floori(_elapsed / _tier_interval_seconds)
	var progress: float = fmod(_elapsed, _tier_interval_seconds) / _tier_interval_seconds
	var elapsed_intervals: float = _elapsed / _tier_interval_seconds
	var coefficient: float = (
		1.0
		+ _continuous_growth_per_interval * elapsed_intervals
		+ _tier_step_growth * float(tier)
	)
	var health_multiplier: float = coefficient
	var damage_multiplier: float = (
		1.0 + _damage_growth_ratio * (coefficient - 1.0)
	)
	var name_key: String = ""
	if not _stage_name_keys.is_empty():
		name_key = _stage_name_keys[mini(tier, _stage_name_keys.size() - 1)]
	return {
		"profile_id": _profile_id,
		"enabled": _enabled,
		"elapsed": _elapsed,
		"tier": tier,
		"progress": progress,
		"coefficient": coefficient,
		"health_multiplier": health_multiplier,
		"damage_multiplier": damage_multiplier,
		"difficulty_level": tier + 1,
		"name_key": name_key,
	}


func enemy_spawn_snapshot() -> Dictionary:
	var current: Dictionary = current_snapshot()
	return {
		"profile_id": current.get("profile_id", ""),
		"elapsed": current.get("elapsed", 0.0),
		"tier": current.get("tier", 0),
		"coefficient": current.get("coefficient", 1.0),
		"difficulty_level": current.get("difficulty_level", 1),
		"health_multiplier": current.get("health_multiplier", 1.0),
		"damage_multiplier": current.get("damage_multiplier", 1.0),
	}


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"profile_id": _profile_id,
		"elapsed": _elapsed,
		"enabled": _enabled,
	}


func restore_snapshot(saved_snapshot: Dictionary) -> bool:
	if int(saved_snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return false
	if String(saved_snapshot.get("profile_id", "")) != _profile_id:
		return false
	var enabled_value: Variant = saved_snapshot.get("enabled")
	if not enabled_value is bool:
		return false
	var elapsed_value: Variant = saved_snapshot.get("elapsed")
	if (
		not elapsed_value is int
		and not elapsed_value is float
	):
		return false
	var restored_elapsed: float = float(elapsed_value)
	if restored_elapsed < 0.0 or not is_finite(restored_elapsed):
		return false
	_elapsed = restored_elapsed
	_enabled = bool(enabled_value)
	return true


func _clear() -> void:
	_profile_id = ""
	_stage_name_keys.clear()
	_elapsed = 0.0
	_enabled = false
