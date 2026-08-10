# Doc: docs/代码/gameplay_effect_runtime.md
class_name EffectPrimitiveRegistry
extends RefCounted


const EFFECT_TRIGGERS := preload("res://scripts/contracts/effect_triggers.gd")
const EFFECT_CONDITIONS := preload("res://scripts/contracts/effect_conditions.gd")
const EFFECT_ACTIONS := preload("res://scripts/contracts/effect_actions.gd")

const TRIGGER_SKILL_ACTIVATED: String = EFFECT_TRIGGERS.SKILL_ACTIVATED
const TRIGGER_DAMAGE_DEALT: String = EFFECT_TRIGGERS.DAMAGE_DEALT
const TRIGGER_KILL: String = EFFECT_TRIGGERS.KILL
const TRIGGER_DAMAGE_TAKEN: String = EFFECT_TRIGGERS.DAMAGE_TAKEN
const TRIGGER_DASH: String = EFFECT_TRIGGERS.DASH
const TRIGGER_MODULE_ENTERED: String = EFFECT_TRIGGERS.MODULE_ENTERED
const TRIGGER_INTERVAL: String = EFFECT_TRIGGERS.INTERVAL

const CONDITION_TEAM: String = EFFECT_CONDITIONS.TEAM
const CONDITION_ELEMENT: String = EFFECT_CONDITIONS.ELEMENT
const CONDITION_DAMAGE_FLAG: String = EFFECT_CONDITIONS.DAMAGE_FLAG
const CONDITION_ACTOR_TAG: String = EFFECT_CONDITIONS.ACTOR_TAG
const CONDITION_HEALTH_RATIO: String = EFFECT_CONDITIONS.HEALTH_RATIO
const CONDITION_BOARD_CELL_RELATION: String = EFFECT_CONDITIONS.BOARD_CELL_RELATION
const CONDITION_MODULE_RELATION: String = EFFECT_CONDITIONS.MODULE_RELATION

const ACTION_DAMAGE: String = EFFECT_ACTIONS.DAMAGE
const ACTION_APPLY_STATUS: String = EFFECT_ACTIONS.APPLY_STATUS
const ACTION_TEMPORARY_MODIFIER: String = EFFECT_ACTIONS.TEMPORARY_MODIFIER
const ACTION_HEAL: String = EFFECT_ACTIONS.HEAL
const ACTION_GRANT_SHIELD: String = EFFECT_ACTIONS.GRANT_SHIELD
const ACTION_GRANT_OVERSHIELD: String = EFFECT_ACTIONS.GRANT_OVERSHIELD
const ACTION_GRANT_GOLD: String = EFFECT_ACTIONS.GRANT_GOLD
const ACTION_SPAWN_PROJECTILE: String = EFFECT_ACTIONS.SPAWN_PROJECTILE
const ACTION_SPAWN_ENEMY: String = EFFECT_ACTIONS.SPAWN_ENEMY
const ACTION_SPAWN_BARRIER: String = EFFECT_ACTIONS.SPAWN_BARRIER

var _condition_handlers: Dictionary = {}
var _action_handlers: Dictionary = {}


func _init() -> void:
	_condition_handlers = {
		CONDITION_TEAM: Callable(self, "_condition_team"),
		CONDITION_ELEMENT: Callable(self, "_condition_element"),
		CONDITION_DAMAGE_FLAG: Callable(self, "_condition_damage_flag"),
		CONDITION_ACTOR_TAG: Callable(self, "_condition_actor_tag"),
		CONDITION_HEALTH_RATIO: Callable(self, "_condition_health_ratio"),
		CONDITION_BOARD_CELL_RELATION: Callable(
			self,
			"_condition_board_cell_relation"
		),
		CONDITION_MODULE_RELATION: Callable(self, "_condition_module_relation"),
	}
	_action_handlers = {
		ACTION_DAMAGE: Callable(self, "_execute_gateway_action"),
		ACTION_APPLY_STATUS: Callable(self, "_execute_gateway_action"),
		ACTION_TEMPORARY_MODIFIER: Callable(self, "_execute_gateway_action"),
		ACTION_HEAL: Callable(self, "_execute_gateway_action"),
		ACTION_GRANT_SHIELD: Callable(self, "_execute_gateway_action"),
		ACTION_GRANT_OVERSHIELD: Callable(self, "_execute_gateway_action"),
		ACTION_GRANT_GOLD: Callable(self, "_execute_gateway_action"),
		ACTION_SPAWN_PROJECTILE: Callable(self, "_execute_gateway_action"),
		ACTION_SPAWN_ENEMY: Callable(self, "_execute_gateway_action"),
		ACTION_SPAWN_BARRIER: Callable(self, "_execute_gateway_action"),
	}


func has_trigger(trigger_id: String) -> bool:
	return EFFECT_TRIGGERS.VALUES.has(trigger_id)


func has_condition(condition_id: String) -> bool:
	return _condition_handlers.has(condition_id)


func has_action(action_id: String) -> bool:
	return _action_handlers.has(action_id)


func validate_condition(condition: Dictionary) -> bool:
	return (
		has_condition(String(condition.get("condition", "")))
		and condition.get("params") is Dictionary
	)


func validate_action(action: Dictionary) -> bool:
	return (
		has_action(String(action.get("action", "")))
		and action.get("params") is Dictionary
	)


func conditions_met(conditions: Array[Dictionary], context: Dictionary) -> bool:
	for condition: Dictionary in conditions:
		var condition_id: String = String(condition.get("condition", ""))
		var handler: Callable = _condition_handlers.get(condition_id, Callable())
		var params: Dictionary = (
			(condition.get("params") as Dictionary).duplicate(true)
			if condition.get("params") is Dictionary
			else {}
		)
		if not handler.is_valid() or not bool(handler.call(params, context)):
			return false
	return true


func execute_action(
	action: Dictionary,
	context: Dictionary,
	gateway: EffectExecutionGateway
) -> Dictionary:
	var action_id: String = String(action.get("action", ""))
	var handler: Callable = _action_handlers.get(action_id, Callable())
	if not handler.is_valid():
		return {"ok": false, "reason": "unknown_action", "action": action_id}
	return handler.call(action_id, action, context, gateway) as Dictionary


func _condition_team(condition: Dictionary, context: Dictionary) -> bool:
	var field: String = String(condition.get("field", "source_team"))
	return String(context.get(field, "")) == String(condition.get("value", ""))


func _condition_element(condition: Dictionary, context: Dictionary) -> bool:
	return String(context.get("element_id", "")) == String(
		condition.get("value", "")
	)


func _condition_damage_flag(condition: Dictionary, context: Dictionary) -> bool:
	var flag_id: String = String(condition.get("value", ""))
	var flags: Array[String] = _string_array(context.get("damage_flags", []))
	return flags.has(flag_id) == bool(condition.get("present", true))


func _condition_actor_tag(condition: Dictionary, context: Dictionary) -> bool:
	var actor_field: String = String(condition.get("actor", "source"))
	var actor: Variant = context.get("%s_actor" % actor_field)
	var tag_id: String = String(condition.get("value", ""))
	var present: bool = false
	if actor is Node and is_instance_valid(actor):
		if (actor as Node).has_method("has_owned_tag"):
			present = bool((actor as Node).call("has_owned_tag", tag_id))
		elif (actor as Node).has_method("has_ability_tag"):
			present = bool((actor as Node).call("has_ability_tag", tag_id))
	return present == bool(condition.get("present", true))


func _condition_health_ratio(condition: Dictionary, context: Dictionary) -> bool:
	var actor_field: String = String(condition.get("actor", "target"))
	var actor: Variant = context.get("%s_actor" % actor_field)
	if not actor is Node or not is_instance_valid(actor):
		return false
	var node: Node = actor as Node
	if not node.has_method("current_life") or not node.has_method("max_life"):
		return false
	var maximum: float = maxf(float(node.call("max_life")), 0.0)
	if maximum <= 0.0:
		return false
	var ratio: float = clampf(float(node.call("current_life")) / maximum, 0.0, 1.0)
	var comparison: String = String(condition.get("comparison", "lte"))
	var expected: float = clampf(float(condition.get("value", 1.0)), 0.0, 1.0)
	if comparison == "gte":
		return ratio >= expected
	return ratio <= expected


func _condition_board_cell_relation(
	condition: Dictionary,
	context: Dictionary
) -> bool:
	var relation: String = String(condition.get("value", "same"))
	var source_cell: Vector2i = context.get("source_board_cell", Vector2i(-1, -1))
	var event_cell: Vector2i = context.get("event_board_cell", Vector2i(-2, -2))
	if relation == "same":
		return source_cell == event_cell
	if relation == "different":
		return source_cell != event_cell
	return false


func _condition_module_relation(condition: Dictionary, context: Dictionary) -> bool:
	var relation: String = String(condition.get("value", "source_is_current"))
	var source_module: Vector2i = context.get("source_module", Vector2i(-1, -1))
	var current_module: Vector2i = context.get("current_module", Vector2i(-2, -2))
	if relation == "source_is_current":
		return source_module == current_module
	if relation == "source_is_not_current":
		return source_module != current_module
	return false


func _execute_gateway_action(
	action_id: String,
	action: Dictionary,
	context: Dictionary,
	gateway: EffectExecutionGateway
) -> Dictionary:
	return gateway.execute(action_id, action, context)


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_value is Array:
		for item: Variant in raw_value as Array:
			result.append(String(item))
	return result
