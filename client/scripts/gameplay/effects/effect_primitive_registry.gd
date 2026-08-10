# Doc: docs/代码/gameplay_effect_runtime.md
class_name EffectPrimitiveRegistry
extends RefCounted


const EFFECT_TRIGGERS := preload("res://scripts/contracts/effect_triggers.gd")
const EFFECT_CONDITIONS := preload("res://scripts/contracts/effect_conditions.gd")
const EFFECT_ACTIONS := preload("res://scripts/contracts/effect_actions.gd")
const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_TARGET_GROUPS := preload(
	"res://scripts/contracts/damage_target_groups.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const GOLD_TRANSACTION_REASONS := preload(
	"res://scripts/contracts/gold_transaction_reasons.gd"
)
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const STATUS_EFFECTS := preload("res://scripts/contracts/status_effects.gd")
const STATUS_STACK_RULES := preload(
	"res://scripts/contracts/status_stack_rules.gd"
)

const INT_STATS: Array[String] = [STATS.BULLET_COUNT, STATS.PIERCE_COUNT]
const NON_NEGATIVE_STATS: Array[String] = [
	STATS.DAMAGE,
	STATS.HEALTH_REGEN,
	STATS.PLAYER_SEPARATION_RADIUS,
	STATS.PICKUP_RANGE,
	STATS.LUCK,
	STATS.ARMOR,
	STATS.MAX_SHIELD,
	STATS.LIFESTEAL_RATIO,
	STATS.WALL_PIERCE,
	STATS.RECOIL,
	STATS.SPREAD_ANGLE_MAX,
]
const POSITIVE_STATS: Array[String] = [
	STATS.MAX_HP,
	STATS.MAX_ENERGY,
	STATS.MOVE_SPEED,
	STATS.ABILITY_STRENGTH,
	STATS.ABILITY_RANGE,
	STATS.ABILITY_EFFICIENCY,
	STATS.ABILITY_DURATION,
	STATS.FIRE_RATE,
	STATS.BULLET_SPEED,
	STATS.BULLET_RANGE,
	STATS.CRIT_MULT,
]
const RATIO_STATS: Array[String] = [
	STATS.CRIT_CHANCE,
	STATS.LIFESTEAL_RATIO,
]
const HERO_MODIFIER_STATS: Array[String] = [
	STATS.MAX_HP,
	STATS.MAX_SHIELD,
	STATS.MAX_ENERGY,
	STATS.HEALTH_REGEN,
	STATS.MOVE_SPEED,
	STATS.ABILITY_STRENGTH,
	STATS.ABILITY_RANGE,
	STATS.ABILITY_EFFICIENCY,
	STATS.ABILITY_DURATION,
	STATS.PLAYER_SEPARATION_RADIUS,
	STATS.PICKUP_RANGE,
	STATS.LUCK,
	STATS.ARMOR,
]
const WEAPON_MODIFIER_STATS: Array[String] = [
	STATS.DAMAGE,
	STATS.FIRE_RATE,
	STATS.BULLET_SPEED,
	STATS.BULLET_RANGE,
	STATS.BULLET_COUNT,
	STATS.PIERCE_COUNT,
	STATS.WALL_PIERCE,
	STATS.RECOIL,
	STATS.SPREAD_ANGLE_MAX,
	STATS.CRIT_CHANCE,
	STATS.CRIT_MULT,
]

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
var _condition_validators: Dictionary = {}
var _action_handlers: Dictionary = {}
var _action_validators: Dictionary = {}


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
	_condition_validators = {
		CONDITION_TEAM: Callable(self, "_validate_condition_team"),
		CONDITION_ELEMENT: Callable(self, "_validate_condition_element"),
		CONDITION_DAMAGE_FLAG: Callable(self, "_validate_condition_damage_flag"),
		CONDITION_ACTOR_TAG: Callable(self, "_validate_condition_actor_tag"),
		CONDITION_HEALTH_RATIO: Callable(self, "_validate_condition_health_ratio"),
		CONDITION_BOARD_CELL_RELATION: Callable(
			self,
			"_validate_condition_board_cell_relation"
		),
		CONDITION_MODULE_RELATION: Callable(
			self,
			"_validate_condition_module_relation"
		),
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
	_action_validators = {
		ACTION_DAMAGE: Callable(self, "_validate_action_damage"),
		ACTION_APPLY_STATUS: Callable(self, "_validate_action_apply_status"),
		ACTION_TEMPORARY_MODIFIER: Callable(
			self,
			"_validate_action_temporary_modifier"
		),
		ACTION_HEAL: Callable(self, "_validate_action_amount"),
		ACTION_GRANT_SHIELD: Callable(self, "_validate_action_amount"),
		ACTION_GRANT_OVERSHIELD: Callable(self, "_validate_action_amount"),
		ACTION_GRANT_GOLD: Callable(self, "_validate_action_grant_gold"),
		ACTION_SPAWN_PROJECTILE: Callable(
			self,
			"_validate_action_spawn_projectile"
		),
		ACTION_SPAWN_ENEMY: Callable(self, "_validate_action_spawn_enemy"),
		ACTION_SPAWN_BARRIER: Callable(self, "_validate_action_spawn_barrier"),
	}


func has_trigger(trigger_id: String) -> bool:
	return EFFECT_TRIGGERS.VALUES.has(trigger_id)


func has_condition(condition_id: String) -> bool:
	return _condition_handlers.has(condition_id)


func has_action(action_id: String) -> bool:
	return _action_handlers.has(action_id)


func validate_condition(condition: Dictionary) -> bool:
	if not _has_exact_keys(condition, ["condition", "params"]):
		return false
	var condition_id: String = String(condition.get("condition", ""))
	var validator: Callable = _condition_validators.get(
		condition_id,
		Callable()
	)
	return (
		has_condition(condition_id)
		and condition.get("params") is Dictionary
		and validator.is_valid()
		and bool(validator.call(condition.get("params") as Dictionary))
	)


func validate_action(action: Dictionary) -> bool:
	if not _has_exact_keys(action, ["action", "params"]):
		return false
	var action_id: String = String(action.get("action", ""))
	var validator: Callable = _action_validators.get(action_id, Callable())
	return (
		has_action(action_id)
		and action.get("params") is Dictionary
		and validator.is_valid()
		and bool(validator.call(action.get("params") as Dictionary))
	)


func _validate_condition_team(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["field", "value"])
		and String(params.get("field", "")) in ["source_team", "target_team"]
		and _is_non_empty_string(params.get("value"))
	)


func _validate_condition_element(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["value"])
		and ELEMENTS.VALUES.has(String(params.get("value", "")))
	)


func _validate_condition_damage_flag(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["value", "present"])
		and _is_non_empty_string(params.get("value"))
		and params.get("present") is bool
	)


func _validate_condition_actor_tag(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["actor", "value", "present"])
		and String(params.get("actor", "")) in ["source", "target"]
		and ABILITY_TAGS.VALUES.has(String(params.get("value", "")))
		and params.get("present") is bool
	)


func _validate_condition_health_ratio(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["actor", "comparison", "value"])
		and String(params.get("actor", "")) in ["source", "target"]
		and String(params.get("comparison", "")) in ["lte", "gte"]
		and _is_number_between(params.get("value"), 0.0, 1.0)
	)


func _validate_condition_board_cell_relation(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["value"])
		and String(params.get("value", "")) in ["same", "different"]
	)


func _validate_condition_module_relation(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["value"])
		and String(params.get("value", ""))
		in ["source_is_current", "source_is_not_current"]
	)


func _validate_action_damage(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["amount", "element_id"])
		and _is_positive_number(params.get("amount"))
		and ELEMENTS.VALUES.has(String(params.get("element_id", "")))
	)


func _validate_action_apply_status(params: Dictionary) -> bool:
	if not _has_required_and_optional_keys(
		params,
		["status", "duration", "stack_rule", "granted_ability_tags"],
		[
			"magnitude",
			"magnitude_cap",
			"modifiers",
			"element_id",
			"tick_interval",
			"max_stacks",
			"incoming_damage_per_stack",
			"incoming_damage_source_team",
		]
	):
		return false
	if (
		not STATUS_EFFECTS.VALUES.has(String(params.get("status", "")))
		or not _is_positive_number(params.get("duration"))
		or not STATUS_STACK_RULES.VALUES.has(String(params.get("stack_rule", "")))
		or not _is_registered_string_array(
			params.get("granted_ability_tags"),
			ABILITY_TAGS.VALUES,
			true
		)
	):
		return false
	for optional_number: String in [
		"magnitude",
		"magnitude_cap",
		"incoming_damage_per_stack",
	]:
		if params.has(optional_number) and not _is_non_negative_number(
			params.get(optional_number)
		):
			return false
	if params.has("tick_interval") and not _is_positive_number(
		params.get("tick_interval")
	):
		return false
	if params.has("max_stacks") and not _is_int_at_least(
		params.get("max_stacks"),
		1
	):
		return false
	if params.has("element_id") and not ELEMENTS.VALUES.has(
		String(params.get("element_id", ""))
	):
		return false
	if (
		float(params.get("magnitude", 0.0)) > 0.0
		and float(params.get("tick_interval", 0.0)) > 0.0
		and not ELEMENTS.VALUES.has(String(params.get("element_id", "")))
	):
		return false
	if (
		params.has("modifiers")
		and not _validate_modifiers(
			params.get("modifiers"),
			params.has("magnitude"),
			true
		)
	):
		return false
	if params.has("incoming_damage_source_team") and not _is_non_empty_string(
		params.get("incoming_damage_source_team")
	):
		return false
	return true


func _validate_action_temporary_modifier(params: Dictionary) -> bool:
	if not _has_required_and_optional_keys(
		params,
		["slot", "duration", "modifiers"],
		["stack_rule"]
	):
		return false
	var slot: String = String(params.get("slot", ""))
	if slot not in ["actor", "weapon", "both"]:
		return false
	return (
		_is_positive_number(params.get("duration"))
		and _validate_modifiers_for_slot(params.get("modifiers"), slot)
		and (
			not params.has("stack_rule")
			or String(params.get("stack_rule", ""))
			== STATUS_STACK_RULES.REFRESH
		)
	)


func _validate_action_amount(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["amount"])
		and _is_positive_number(params.get("amount"))
	)


func _validate_action_grant_gold(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["amount", "reason_id"])
		and _is_int_at_least(params.get("amount"), 1)
		and GOLD_TRANSACTION_REASONS.VALUES.has(
			String(params.get("reason_id", ""))
		)
	)


func _validate_action_spawn_projectile(params: Dictionary) -> bool:
	if not _has_required_and_optional_keys(
		params,
		[
			"pool_id",
			"amount",
			"element_id",
			"speed",
			"range",
			"hit_radius",
			"lifetime",
			"count",
			"spread_degrees",
			"pierce_count",
			"wall_pierce",
			"damage_target_groups",
		],
		["direction"]
	):
		return false
	if (
		String(params.get("pool_id", "")) != POOL_IDS.BULLET_BASIC
		or not ELEMENTS.VALUES.has(String(params.get("element_id", "")))
		or not _is_positive_number(params.get("amount"))
		or not _is_positive_number(params.get("speed"))
		or not _is_positive_number(params.get("range"))
		or not _is_positive_number(params.get("hit_radius"))
		or not _is_positive_number(params.get("lifetime"))
		or not _is_int_between(params.get("count"), 1, 64)
		or not _is_number_between(params.get("spread_degrees"), 0.0, 360.0)
		or not _is_int_at_least(params.get("pierce_count"), 0)
		or not params.get("wall_pierce") is bool
		or not _is_registered_string_array(
			params.get("damage_target_groups"),
			DAMAGE_TARGET_GROUPS.VALUES,
			false
		)
	):
		return false
	if params.has("direction"):
		var direction: Variant = params.get("direction")
		if not direction is Dictionary:
			return false
		var direction_dict: Dictionary = direction as Dictionary
		if (
			not _has_exact_keys(direction_dict, ["x", "y"])
			or not _is_finite_number(direction_dict.get("x"))
			or not _is_finite_number(direction_dict.get("y"))
		):
			return false
	return true


func _validate_action_spawn_enemy(params: Dictionary) -> bool:
	return (
		_has_exact_keys(params, ["normal_rewards", "current_layer_only"])
		and params.get("normal_rewards") is bool
		and bool(params.get("normal_rewards"))
		and params.get("current_layer_only") is bool
		and bool(params.get("current_layer_only"))
	)


func _validate_action_spawn_barrier(params: Dictionary) -> bool:
	return (
		_has_exact_keys(
			params,
			["pool_id", "radius", "hp", "max_active", "recast_policy"]
		)
		and String(params.get("pool_id", "")) == POOL_IDS.PROJECTILE_BARRIER
		and _is_positive_number(params.get("radius"))
		and _is_positive_number(params.get("hp"))
		and _is_int_at_least(params.get("max_active"), 1)
		and String(params.get("recast_policy", "")) == "replace"
	)


func _validate_modifiers(
	raw_modifiers: Variant,
	allow_inverse_from_magnitude: bool = false,
	allow_empty: bool = false
) -> bool:
	if not raw_modifiers is Array:
		return false
	if (raw_modifiers as Array).is_empty() and not allow_empty:
		return false
	for raw_modifier: Variant in raw_modifiers as Array:
		if not raw_modifier is Dictionary:
			return false
		var modifier: Dictionary = raw_modifier as Dictionary
		if not _has_required_and_optional_keys(
			modifier,
			["stat", "type", "value"],
			["scale_mode"]
		):
			return false
		if (
			not STATS.VALUES.has(String(modifier.get("stat", "")))
			or String(modifier.get("type", "")) not in ["add", "mult"]
			or not _is_valid_stat_value(
				String(modifier.get("stat", "")),
				modifier.get("value")
			)
		):
			return false
		if modifier.has("scale_mode"):
			if (
				String(modifier.get("scale_mode", ""))
				!= "inverse_from_magnitude"
				or not allow_inverse_from_magnitude
				or String(modifier.get("type", "")) != "mult"
			):
				return false
	return true


func _validate_modifiers_for_slot(
	raw_modifiers: Variant,
	slot: String
) -> bool:
	if not _validate_modifiers(raw_modifiers):
		return false
	for raw_modifier: Variant in raw_modifiers as Array:
		var modifier: Dictionary = raw_modifier as Dictionary
		if not _is_modifier_stat_supported_for_slot(
			String(modifier.get("stat", "")),
			slot
		):
			return false
	return true


func _is_modifier_stat_supported_for_slot(stat_id: String, slot: String) -> bool:
	if slot == "actor":
		return HERO_MODIFIER_STATS.has(stat_id)
	if slot == "weapon":
		return WEAPON_MODIFIER_STATS.has(stat_id)
	return (
		HERO_MODIFIER_STATS.has(stat_id)
		or WEAPON_MODIFIER_STATS.has(stat_id)
	)


func _is_valid_stat_value(stat_id: String, value: Variant) -> bool:
	if not _is_finite_number(value):
		return false
	if INT_STATS.has(stat_id):
		return _is_int_at_least(value, 1)
	if RATIO_STATS.has(stat_id):
		return _is_number_between(value, 0.0, 1.0)
	if POSITIVE_STATS.has(stat_id):
		return float(value) > 0.0
	if NON_NEGATIVE_STATS.has(stat_id):
		return float(value) >= 0.0
	return true


func _has_exact_keys(value: Dictionary, expected_keys: Array[String]) -> bool:
	if value.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not value.has(key):
			return false
	return true


func _has_required_and_optional_keys(
	value: Dictionary,
	required_keys: Array[String],
	optional_keys: Array[String]
) -> bool:
	for key: String in required_keys:
		if not value.has(key):
			return false
	for raw_key: Variant in value.keys():
		var key: String = String(raw_key)
		if not required_keys.has(key) and not optional_keys.has(key):
			return false
	return true


func _is_non_empty_string(value: Variant) -> bool:
	return value is String and not String(value).strip_edges().is_empty()


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _is_positive_number(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) > 0.0


func _is_non_negative_number(value: Variant) -> bool:
	return _is_finite_number(value) and float(value) >= 0.0


func _is_number_between(
	value: Variant,
	minimum: float,
	maximum: float
) -> bool:
	return (
		_is_finite_number(value)
		and float(value) >= minimum
		and float(value) <= maximum
	)


func _is_int_at_least(value: Variant, minimum: int) -> bool:
	return _is_int_like(value) and int(value) >= minimum


func _is_int_between(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		_is_int_like(value)
		and int(value) >= minimum
		and int(value) <= maximum
	)


func _is_int_like(value: Variant) -> bool:
	if value is int:
		return true
	if not value is float or not is_finite(float(value)):
		return false
	return is_equal_approx(float(value), float(int(value)))


func _is_registered_string_array(
	raw_values: Variant,
	allowed_values: Array[String],
	allow_empty: bool
) -> bool:
	if not raw_values is Array:
		return false
	var values: Array = raw_values as Array
	if values.is_empty() and not allow_empty:
		return false
	var seen: Dictionary = {}
	for raw_value: Variant in values:
		if not raw_value is String:
			return false
		var value: String = String(raw_value)
		if not allowed_values.has(value) or seen.has(value):
			return false
		seen[value] = true
	return true


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
