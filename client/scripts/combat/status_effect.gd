# Doc: docs/代码/status_effect_component.md
# Authority: docs/游戏设计文档.md §9.15.2, docs/词表与契约.md §9-A~§9-B
class_name StatusEffect
extends Resource


const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const STATUS_EFFECTS := preload("res://scripts/contracts/status_effects.gd")
const STATUS_STACK_RULES := preload("res://scripts/contracts/status_stack_rules.gd")

var damage_type: String = ""
var duration: float = 0.0
var granted_ability_tags: Array[String] = []
var instance_key: String = ""
var magnitude: float = 0.0
var remaining: float = 0.0
var source: Node = null
var source_team: String = ""
var stack_rule: String = STATUS_STACK_RULES.REFRESH
var status_id: String = ""
var target_team: String = ""
var tick_interval: float = 0.0
var tick_remaining: float = 0.0


func setup(effect_id: String, params: Dictionary, source_node: Node = null) -> Resource:
	status_id = effect_id
	duration = maxf(float(params.get("duration", 0.0)), 0.0)
	remaining = duration
	damage_type = String(params.get("damage_type", ""))
	tick_interval = maxf(float(params.get("tick_interval", 0.0)), 0.0)
	tick_remaining = tick_interval
	magnitude = float(params.get("magnitude", 0.0))
	stack_rule = String(params.get("stack_rule", STATUS_STACK_RULES.REFRESH))
	source = source_node
	source_team = String(params.get("source_team", ""))
	target_team = String(params.get("target_team", ""))
	granted_ability_tags = _registered_ability_tags(params.get("granted_ability_tags", []))
	return self


func copy_runtime() -> Resource:
	var effect: Resource = get_script().new()
	effect.set("status_id", status_id)
	effect.set("duration", duration)
	effect.set("remaining", remaining)
	effect.set("damage_type", damage_type)
	effect.set("tick_interval", tick_interval)
	effect.set("tick_remaining", tick_remaining)
	effect.set("magnitude", magnitude)
	effect.set("stack_rule", stack_rule)
	effect.set("source", source)
	effect.set("source_team", source_team)
	effect.set("target_team", target_team)
	effect.set("granted_ability_tags", granted_ability_tags.duplicate())
	effect.set("instance_key", instance_key)
	return effect


func is_valid() -> bool:
	var has_valid_damage_type: bool = damage_type.is_empty() or DAMAGE_TYPES.VALUES.has(damage_type)
	var has_damage_tick: bool = magnitude > 0.0 and tick_interval > 0.0
	return (
		STATUS_EFFECTS.VALUES.has(status_id)
		and STATUS_STACK_RULES.VALUES.has(stack_rule)
		and duration > 0.0
		and remaining > 0.0
		and has_valid_damage_type
		and (not has_damage_tick or not damage_type.is_empty())
	)


func snapshot() -> Dictionary:
	return {
		"status": status_id,
		"duration": duration,
		"remaining": remaining,
		"damage_type": damage_type,
		"tick_interval": tick_interval,
		"tick_remaining": tick_remaining,
		"magnitude": magnitude,
		"stack_rule": stack_rule,
		"source_team": source_team,
		"target_team": target_team,
		"granted_ability_tags": granted_ability_tags.duplicate(),
	}


func restore_from_snapshot(snapshot_data: Dictionary) -> Resource:
	status_id = String(snapshot_data.get("status", ""))
	duration = maxf(float(snapshot_data.get("duration", 0.0)), 0.0)
	remaining = clampf(float(snapshot_data.get("remaining", duration)), 0.0, duration)
	damage_type = String(snapshot_data.get("damage_type", ""))
	tick_interval = maxf(float(snapshot_data.get("tick_interval", 0.0)), 0.0)
	tick_remaining = clampf(float(snapshot_data.get("tick_remaining", tick_interval)), 0.0, tick_interval)
	magnitude = float(snapshot_data.get("magnitude", 0.0))
	stack_rule = String(snapshot_data.get("stack_rule", STATUS_STACK_RULES.REFRESH))
	source_team = String(snapshot_data.get("source_team", ""))
	target_team = String(snapshot_data.get("target_team", ""))
	granted_ability_tags = _registered_ability_tags(snapshot_data.get("granted_ability_tags", []))
	return self


func _registered_ability_tags(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		var tag_id: String = String(item)
		if not tag_id.is_empty() and ABILITY_TAGS.VALUES.has(tag_id) and not result.has(tag_id):
			result.append(tag_id)
	return result
