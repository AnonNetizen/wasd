# Doc: docs/代码/skill_system.md
# Authority: docs/游戏设计文档.md §9.15, docs/决策记录.md ADR #162
class_name SkillDescriptionFormatter
extends RefCounted


const SKILL_VALUE_RESOLVER := preload(
	"res://scripts/data/skill_value_resolver.gd"
)


static func format_skill(
	template: String,
	skill: Dictionary,
	ability_stats: Dictionary
) -> String:
	return template.format(
		skill_values(skill, ability_stats),
		"{_}"
	)


static func format_passive(
	template: String,
	passive: Dictionary
) -> String:
	var values: Dictionary = {}
	_add_numeric_dictionary_values(
		values,
		"param",
		_dictionary_or_empty(passive.get("params", {}))
	)
	return template.format(values, "{_}")


static func skill_values(
	skill: Dictionary,
	ability_stats: Dictionary
) -> Dictionary:
	var values: Dictionary = {
		"cooldown": _format_number(
			maxf(float(skill.get("cooldown", 0.0)), 0.0)
		),
		"target_radius": _format_number(
			SKILL_VALUE_RESOLVER.scaled_target_radius(
				skill,
				ability_stats
			)
		),
	}
	var raw_costs: Variant = skill.get("costs", [])
	if raw_costs is Array:
		for raw_cost: Variant in raw_costs as Array:
			if not raw_cost is Dictionary:
				continue
			var cost: Dictionary = raw_cost as Dictionary
			var resource_id: String = String(cost.get("resource", ""))
			if resource_id.is_empty():
				continue
			values["cost_%s" % resource_id] = _format_number(
				SKILL_VALUE_RESOLVER.scaled_cost_amount(
					skill,
					cost,
					ability_stats
				)
			)
	var raw_effects: Variant = skill.get("effects", [])
	if raw_effects is Array:
		for effect_index: int in range((raw_effects as Array).size()):
			var raw_effect: Variant = (raw_effects as Array)[effect_index]
			if not raw_effect is Dictionary:
				continue
			var params: Dictionary = (
				SKILL_VALUE_RESOLVER.scaled_effect_params(
					skill,
					raw_effect as Dictionary,
					ability_stats
				)
			)
			var effect_prefix: String = "effect_%d" % (effect_index + 1)
			_add_numeric_dictionary_values(values, effect_prefix, params)
			var raw_modifiers: Variant = params.get("modifiers", [])
			if not raw_modifiers is Array:
				continue
			for modifier_index: int in range(
				(raw_modifiers as Array).size()
			):
				var raw_modifier: Variant = (
					(raw_modifiers as Array)[modifier_index]
				)
				if not raw_modifier is Dictionary:
					continue
				_add_numeric_dictionary_values(
					values,
					"%s_modifier_%d" % [
						effect_prefix,
						modifier_index + 1,
					],
					raw_modifier as Dictionary
				)
	return values


static func _add_numeric_dictionary_values(
	output: Dictionary,
	prefix: String,
	source: Dictionary
) -> void:
	for raw_key: Variant in source.keys():
		var raw_value: Variant = source[raw_key]
		if (
			typeof(raw_value) != TYPE_INT
			and typeof(raw_value) != TYPE_FLOAT
		):
			continue
		var key: String = "%s_%s" % [prefix, String(raw_key)]
		var value: float = float(raw_value)
		output[key] = _format_number(value)
		output["%s_percent" % key] = _format_number(value * 100.0)
		output["%s_bonus_percent" % key] = _format_number(
			(value - 1.0) * 100.0
		)
		output["%s_reduction_percent" % key] = _format_number(
			(1.0 - value) * 100.0
		)


static func _format_number(value: float) -> String:
	var rounded: float = snappedf(value, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return str(int(roundf(rounded)))
	return ("%.2f" % rounded).trim_suffix("0")


static func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}
