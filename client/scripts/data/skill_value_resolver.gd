# Doc: docs/代码/skill_system.md
# Authority: docs/游戏设计文档.md §9.15
class_name SkillValueResolver
extends RefCounted


const STATS := preload("res://scripts/contracts/stats.gd")


static func ability_stat_value(
	ability_stats: Dictionary,
	stat_id: String
) -> float:
	var value: float = float(ability_stats.get(stat_id, 1.0))
	if stat_id == STATS.ABILITY_STRENGTH:
		return clampf(value, 0.25, 4.0)
	if stat_id == STATS.ABILITY_RANGE:
		return clampf(value, 0.25, 2.5)
	if stat_id == STATS.ABILITY_DURATION:
		return clampf(value, 0.25, 3.0)
	if stat_id == STATS.ABILITY_EFFICIENCY:
		return clampf(value, 0.25, 1.75)
	return value


static func scaled_cost_amount(
	skill: Dictionary,
	cost: Dictionary,
	ability_stats: Dictionary
) -> float:
	var amount: float = maxf(float(cost.get("amount", 0.0)), 0.0)
	var scaling: Dictionary = _dictionary_or_empty(skill.get("scaling", {}))
	var efficiency_stat: String = String(scaling.get("cost_stat", ""))
	if not efficiency_stat.is_empty():
		var efficiency: float = ability_stat_value(
			ability_stats,
			efficiency_stat
		)
		amount *= clampf(2.0 - efficiency, 0.25, 1.75)
	amount *= maxf(float(skill.get("cost_multiplier", 1.0)), 0.0)
	return amount


static func scaled_target_radius(
	skill: Dictionary,
	ability_stats: Dictionary
) -> float:
	var targeting: Dictionary = _dictionary_or_empty(
		skill.get("targeting", {})
	)
	var radius: float = maxf(float(targeting.get("radius", 0.0)), 0.0)
	var scaling: Dictionary = _dictionary_or_empty(skill.get("scaling", {}))
	var radius_stat: String = String(scaling.get("radius_stat", ""))
	if not radius_stat.is_empty():
		radius *= maxf(
			ability_stat_value(ability_stats, radius_stat),
			0.0
		)
	return radius


static func scaled_effect_params(
	skill: Dictionary,
	effect: Dictionary,
	ability_stats: Dictionary
) -> Dictionary:
	var params: Dictionary = _dictionary_or_empty(effect.get("params", {}))
	var scaling: Dictionary = _dictionary_or_empty(skill.get("scaling", {}))
	var duration_stat: String = String(scaling.get("duration_stat", ""))
	if not duration_stat.is_empty() and params.has("duration"):
		params["duration"] = (
			float(params.get("duration", 0.0))
			* maxf(ability_stat_value(ability_stats, duration_stat), 0.0)
		)
	var radius_stat: String = String(scaling.get("radius_stat", ""))
	if not radius_stat.is_empty() and params.has("radius"):
		params["radius"] = (
			float(params.get("radius", 0.0))
			* maxf(ability_stat_value(ability_stats, radius_stat), 0.0)
		)
	var strength_stat: String = String(scaling.get("strength_stat", ""))
	if not strength_stat.is_empty():
		var strength: float = maxf(
			ability_stat_value(ability_stats, strength_stat),
			0.0
		)
		if params.has("hp"):
			params["hp"] = float(params.get("hp", 0.0)) * strength
		if params.has("amount"):
			params["amount"] = (
				float(params.get("amount", 0.0)) * strength
			)
		if params.has("magnitude"):
			var magnitude: float = (
				float(params.get("magnitude", 0.0)) * strength
			)
			if params.has("magnitude_cap"):
				magnitude = minf(
					magnitude,
					float(params.get("magnitude_cap", magnitude))
				)
			params["magnitude"] = magnitude
		params["modifiers"] = _scaled_modifiers(
			params.get("modifiers", []),
			strength,
			float(params.get("magnitude", 0.0))
		)
	return params


static func _scaled_modifiers(
	raw_modifiers: Variant,
	strength: float,
	scaled_magnitude: float
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_modifiers is Array:
		return result
	for raw_modifier: Variant in raw_modifiers as Array:
		if not raw_modifier is Dictionary:
			continue
		var modifier: Dictionary = (raw_modifier as Dictionary).duplicate(true)
		var scale_mode: String = String(modifier.get("scale_mode", ""))
		if scale_mode == "inverse_from_magnitude":
			modifier["value"] = maxf(1.0 - scaled_magnitude, 0.0)
		elif String(modifier.get("type", "")) == "mult":
			var value: float = float(modifier.get("value", 1.0))
			modifier["value"] = 1.0 + (value - 1.0) * strength
		elif String(modifier.get("type", "")) == "add":
			modifier["value"] = (
				float(modifier.get("value", 0.0)) * strength
			)
		result.append(modifier)
	return result


static func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}
