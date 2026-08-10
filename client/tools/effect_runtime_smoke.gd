extends Node


const EFFECT_ACTIONS := preload("res://scripts/contracts/effect_actions.gd")
const EFFECT_CONDITIONS := preload("res://scripts/contracts/effect_conditions.gd")
const EFFECT_TRIGGERS := preload("res://scripts/contracts/effect_triggers.gd")
const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_TARGET_GROUPS := preload(
	"res://scripts/contracts/damage_target_groups.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const GOLD_TRANSACTION_REASONS := preload(
	"res://scripts/contracts/gold_transaction_reasons.gd"
)
const STATUS_EFFECTS := preload("res://scripts/contracts/status_effects.gd")
const STATUS_STACK_RULES := preload(
	"res://scripts/contracts/status_stack_rules.gd"
)
const STATS := preload("res://scripts/contracts/stats.gd")
const EFFECT_GATEWAY_SCRIPT := preload(
	"res://scripts/gameplay/effects/effect_execution_gateway.gd"
)
const EFFECT_REGISTRY_SCRIPT := preload(
	"res://scripts/gameplay/effects/effect_primitive_registry.gd"
)
const EFFECT_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/effects/gameplay_effect_runtime.gd"
)
const BULLET_SCRIPT := preload("res://scripts/gameplay/bullet.gd")
const PROJECTILE_BARRIER_SCRIPT := preload(
	"res://scripts/gameplay/projectile_barrier.gd"
)
const GAMEPLAY_RUN_LOOP_SCRIPT := preload(
	"res://scripts/gameplay/gameplay_run_loop.gd"
)
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")

var _action_count: int = 0
var _chain_runtime: GameplayEffectRuntime = null
var _failures: Array[String] = []
var _order: Array[String] = []
var _primitive_calls: Dictionary = {}
var _retained_plan_seen: Dictionary = {}


class PrimitiveTarget:
	extends Node2D

	var healed: float = 0.0
	var shield: float = 0.0
	var overshield: float = 0.0
	var damage_received: float = 0.0
	var statuses: int = 0
	var temporary_modifiers: int = 0
	var life: float = 40.0
	var life_maximum: float = 100.0
	var owned_tag: String = ""

	func heal(amount: float) -> float:
		healed += amount
		return amount

	func add_shield(amount: float) -> float:
		shield += amount
		return amount

	func add_overshield(amount: float) -> float:
		overshield += amount
		return amount

	func receive_damage(info: RefCounted) -> Dictionary:
		var amount: float = float(info.get("amount"))
		damage_received += amount
		return {
			"applied": true,
			"amount": amount,
			"defeated": false,
			"reason": "applied",
		}

	func apply_status_effect(_status_effect: RefCounted) -> Dictionary:
		statuses += 1
		return {"applied": true}

	func apply_temporary_modifiers(
		_modifiers: Array,
		_duration: float,
		_source_key: String
	) -> void:
		temporary_modifiers += 1

	func current_life() -> float:
		return life

	func max_life() -> float:
		return life_maximum

	func has_owned_tag(tag_id: String) -> bool:
		return tag_id == owned_tag


class ProjectileSource:
	extends Node2D

	var aim_direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_expect_stable_order_and_snapshot()
	_expect_all_triggers()
	_expect_all_conditions()
	_expect_all_actions()
	_expect_invalid_primitive_params_rejected()
	_expect_probability_cooldown_and_interval()
	_expect_interval_plan_retention()
	_expect_chain_depth_limit()
	_expect_action_budget()
	_finish()


func _expect_stable_order_and_snapshot() -> void:
	_order.clear()
	var runtime: GameplayEffectRuntime = _new_runtime(
		Callable(self, "_record_action")
	)
	var program: Dictionary = _program("stable_order")
	var programs: Array[Dictionary] = [program]
	_expect(
		runtime.register_source("gear_mod", "z_mod", 10, 0, programs),
		"source z should register"
	)
	_expect(
		runtime.register_source("gear_mod", "a_mod", 2, 0, programs),
		"source a should register"
	)
	runtime.emit_event(EFFECT_TRIGGERS.SKILL_ACTIVATED)
	_expect(
		_order == ["gear_mod|a_mod|2|00000000", "gear_mod|z_mod|10|00000000"],
		"sources should execute by type, content, instance and component order"
	)
	var saved: Dictionary = runtime.snapshot()
	_expect(runtime.restore_snapshot(saved), "runtime snapshot should roundtrip")


func _expect_chain_depth_limit() -> void:
	_action_count = 0
	_chain_runtime = _new_runtime(Callable(self, "_chain_action"))
	var program: Dictionary = _program("chain")
	var programs: Array[Dictionary] = [program]
	_expect(
		_chain_runtime.register_source("skill", "chain", "skill_1", 0, programs),
		"chain source should register"
	)
	_chain_runtime.emit_event(EFFECT_TRIGGERS.SKILL_ACTIVATED)
	_expect(_action_count == 9, "chain should execute depths zero through eight")
	_expect(
		not _chain_runtime.diagnostics().is_empty(),
		"chain overflow should record diagnostics"
	)


func _expect_all_triggers() -> void:
	_primitive_calls.clear()
	var runtime: GameplayEffectRuntime = _new_runtime(
		Callable(self, "_record_primitive_action")
	)
	var programs: Array[Dictionary] = []
	for trigger_id: String in EFFECT_TRIGGERS.VALUES:
		var program: Dictionary = _program("trigger_%s" % trigger_id)
		program["trigger"] = trigger_id
		if trigger_id == EFFECT_TRIGGERS.INTERVAL:
			program["interval_seconds"] = 0.1
		programs.append(program)
	_expect(
		runtime.register_source("test", "all_triggers", 1, 0, programs),
		"all trigger programs should register"
	)
	for trigger_id: String in EFFECT_TRIGGERS.VALUES:
		if trigger_id != EFFECT_TRIGGERS.INTERVAL:
			runtime.emit_event(trigger_id)
	runtime.tick(0.1)
	for trigger_id: String in EFFECT_TRIGGERS.VALUES:
		_expect(
			int(_primitive_calls.get("trigger_%s" % trigger_id, 0)) == 1,
			"trigger %s should execute" % trigger_id
		)


func _expect_all_conditions() -> void:
	var registry: EffectPrimitiveRegistry = EFFECT_REGISTRY_SCRIPT.new()
	var source := PrimitiveTarget.new()
	var target := PrimitiveTarget.new()
	source.owned_tag = ABILITY_TAGS.ABILITY_TAG_SKILL
	source.life = 80.0
	add_child(source)
	add_child(target)
	var cases: Array[Dictionary] = [
		{
			"id": EFFECT_CONDITIONS.TEAM,
			"params": {"field": "source_team", "value": "team_player"},
			"context": {"source_team": "team_player"},
			"negative": {"source_team": "team_enemy"},
		},
		{
			"id": EFFECT_CONDITIONS.ELEMENT,
			"params": {"value": ELEMENTS.ELEMENT_NEUTRAL},
			"context": {"element_id": ELEMENTS.ELEMENT_NEUTRAL},
			"negative": {"element_id": ELEMENTS.ELEMENT_PRIMARY_A},
		},
		{
			"id": EFFECT_CONDITIONS.DAMAGE_FLAG,
			"params": {"value": "is_dot", "present": true},
			"context": {"damage_flags": ["is_dot"]},
			"negative": {"damage_flags": []},
		},
		{
			"id": EFFECT_CONDITIONS.ACTOR_TAG,
			"params": {
				"actor": "source",
				"value": ABILITY_TAGS.ABILITY_TAG_SKILL,
				"present": true,
			},
			"context": {"source_actor": source},
			"negative": {"source_actor": target},
		},
		{
			"id": EFFECT_CONDITIONS.HEALTH_RATIO,
			"params": {"actor": "target", "comparison": "lte", "value": 0.5},
			"context": {"target_actor": target},
			"negative": {"target_actor": source},
		},
		{
			"id": EFFECT_CONDITIONS.BOARD_CELL_RELATION,
			"params": {"value": "same"},
			"context": {
				"source_board_cell": Vector2i(2, 3),
				"event_board_cell": Vector2i(2, 3),
			},
			"negative": {
				"source_board_cell": Vector2i(2, 3),
				"event_board_cell": Vector2i(3, 3),
			},
		},
		{
			"id": EFFECT_CONDITIONS.MODULE_RELATION,
			"params": {"value": "source_is_current"},
			"context": {
				"source_module": Vector2i(1, 1),
				"current_module": Vector2i(1, 1),
			},
			"negative": {
				"source_module": Vector2i(1, 1),
				"current_module": Vector2i(1, 2),
			},
		},
	]
	for condition_case: Dictionary in cases:
		var condition: Dictionary = {
			"condition": String(condition_case.get("id", "")),
			"params": (condition_case.get("params", {}) as Dictionary),
		}
		var conditions: Array[Dictionary] = [condition]
		_expect(
			registry.validate_condition(condition),
			"condition %s params should validate" % condition["condition"]
		)
		_expect(
			registry.conditions_met(
				conditions,
				condition_case.get("context", {}) as Dictionary
			),
			"condition %s should accept its positive context" % condition["condition"]
		)
		_expect(
			not registry.conditions_met(
				conditions,
				condition_case.get("negative", {}) as Dictionary
			),
			"condition %s should reject its negative context" % condition["condition"]
		)
	source.queue_free()
	target.queue_free()


func _expect_invalid_primitive_params_rejected() -> void:
	var registry: EffectPrimitiveRegistry = EFFECT_REGISTRY_SCRIPT.new()
	_expect(
		registry.validate_action({
			"action": EFFECT_ACTIONS.APPLY_STATUS,
			"params": {
				"status": STATUS_EFFECTS.SILENCE,
				"duration": 1.0,
				"stack_rule": STATUS_STACK_RULES.REFRESH,
				"granted_ability_tags": [],
				"modifiers": [],
			},
		}),
		"apply_status should allow an empty optional modifier list"
	)
	var invalid_conditions: Array[Dictionary] = [
		{"condition": EFFECT_CONDITIONS.TEAM, "params": {"value": "team_player"}},
		{
			"condition": EFFECT_CONDITIONS.TEAM,
			"params": {"field": "source_team", "value": " "},
		},
		{"condition": EFFECT_CONDITIONS.ELEMENT, "params": {"value": "unknown"}},
		{
			"condition": EFFECT_CONDITIONS.DAMAGE_FLAG,
			"params": {"value": "is_dot", "present": "true"},
		},
		{
			"condition": EFFECT_CONDITIONS.DAMAGE_FLAG,
			"params": {"value": " ", "present": true},
		},
		{
			"condition": EFFECT_CONDITIONS.ACTOR_TAG,
			"params": {"actor": "other", "value": ABILITY_TAGS.ABILITY_TAG_SKILL, "present": true},
		},
		{
			"condition": EFFECT_CONDITIONS.HEALTH_RATIO,
			"params": {"actor": "target", "comparison": "lte", "value": 2.0},
		},
		{
			"condition": EFFECT_CONDITIONS.BOARD_CELL_RELATION,
			"params": {"value": "diagonal"},
		},
		{
			"condition": EFFECT_CONDITIONS.MODULE_RELATION,
			"params": {"value": "unknown"},
		},
	]
	for condition: Dictionary in invalid_conditions:
		_expect(
			not registry.validate_condition(condition),
			"condition %s should reject invalid params"
			% String(condition.get("condition", ""))
		)

	var invalid_actions: Array[Dictionary] = [
		{"action": EFFECT_ACTIONS.DAMAGE, "params": {"amount": 3.0}},
		{
			"action": EFFECT_ACTIONS.APPLY_STATUS,
			"params": {
				"status": STATUS_EFFECTS.SILENCE,
				"duration": 0.0,
				"stack_rule": STATUS_STACK_RULES.REFRESH,
				"granted_ability_tags": [],
			},
		},
		{
			"action": EFFECT_ACTIONS.APPLY_STATUS,
			"params": {
				"status": STATUS_EFFECTS.SILENCE,
				"duration": 1.0,
				"stack_rule": STATUS_STACK_RULES.REFRESH,
				"granted_ability_tags": [],
				"incoming_damage_source_team": " ",
			},
		},
		{
			"action": EFFECT_ACTIONS.APPLY_STATUS,
			"params": {
				"status": STATUS_EFFECTS.SILENCE,
				"duration": 1.0,
				"stack_rule": STATUS_STACK_RULES.REFRESH,
				"granted_ability_tags": [],
				"magnitude": 1.0,
				"tick_interval": 1.0,
			},
		},
		{
			"action": EFFECT_ACTIONS.APPLY_STATUS,
			"params": {
				"status": STATUS_EFFECTS.SILENCE,
				"duration": 1.0,
				"stack_rule": STATUS_STACK_RULES.REFRESH,
				"granted_ability_tags": [],
				"modifiers": [{
					"stat": STATS.MOVE_SPEED,
					"type": "mult",
					"value": 0.8,
					"scale_mode": "inverse_from_magnitude",
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.APPLY_STATUS,
			"params": {
				"status": STATUS_EFFECTS.SILENCE,
				"duration": 1.0,
				"stack_rule": STATUS_STACK_RULES.REFRESH,
				"granted_ability_tags": [],
				"magnitude": 0.2,
				"modifiers": [{
					"stat": STATS.MOVE_SPEED,
					"type": "add",
					"value": 0.8,
					"scale_mode": "inverse_from_magnitude",
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {"slot": "actor", "duration": 1.0, "modifiers": []},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "actor",
				"duration": 1.0,
				"modifiers": [{
					"stat": STATS.MOVE_SPEED,
					"type": "mult",
					"value": 0.8,
					"scale_mode": "unknown",
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "actor",
				"duration": 1.0,
				"modifiers": [{
					"stat": STATS.MOVE_SPEED,
					"type": "mult",
					"value": 0.8,
					"scale_mode": "inverse_from_magnitude",
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "actor",
				"duration": 1.0,
				"modifiers": [{
					"stat": STATS.MOVE_SPEED,
					"type": "mult",
					"value": 1.1,
					"typo": true,
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "actor",
				"duration": 1.0,
				"stack_rule": STATUS_STACK_RULES.ADD_DURATION,
				"modifiers": [{
					"stat": STATS.MOVE_SPEED,
					"type": "mult",
					"value": 1.1,
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "actor",
				"duration": 1.0,
				"modifiers": [{
					"stat": STATS.MOVE_SPEED,
					"type": "mult",
					"value": -1.0,
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "weapon",
				"duration": 1.0,
				"modifiers": [{
					"stat": STATS.BULLET_COUNT,
					"type": "add",
					"value": 1.5,
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "weapon",
				"duration": 1.0,
				"modifiers": [{
					"stat": STATS.MAX_HP,
					"type": "mult",
					"value": 2.0,
				}],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "actor",
				"duration": 1.0,
				"modifiers": [{
					"stat": STATS.FIRE_RATE,
					"type": "mult",
					"value": 1.1,
				}],
			},
		},
		{"action": EFFECT_ACTIONS.HEAL, "params": {"amount": 0.0}},
		{"action": EFFECT_ACTIONS.GRANT_SHIELD, "params": {"amount": -1.0}},
		{
			"action": EFFECT_ACTIONS.GRANT_OVERSHIELD,
			"params": {"amount": INF},
		},
		{
			"action": EFFECT_ACTIONS.GRANT_GOLD,
			"params": {"amount": 0, "reason_id": GOLD_TRANSACTION_REASONS.EVENT_REWARD},
		},
		{
			"action": EFFECT_ACTIONS.SPAWN_PROJECTILE,
			"params": {
				"pool_id": POOL_IDS.BULLET_BASIC,
				"amount": 3.0,
				"element_id": ELEMENTS.ELEMENT_NEUTRAL,
				"speed": 800.0,
				"range": 600.0,
				"hit_radius": 8.0,
				"lifetime": 2.0,
				"count": 0,
				"spread_degrees": 10.0,
				"pierce_count": 0,
				"wall_pierce": false,
				"damage_target_groups": [DAMAGE_TARGET_GROUPS.ACTIVE_ENEMIES],
			},
		},
		{
			"action": EFFECT_ACTIONS.SPAWN_ENEMY,
			"params": {"normal_rewards": true, "current_layer_only": false},
		},
		{
			"action": EFFECT_ACTIONS.SPAWN_BARRIER,
			"params": {
				"pool_id": POOL_IDS.PROJECTILE_BARRIER,
				"radius": 64.0,
				"hp": 100.0,
				"max_active": 0,
				"recast_policy": "replace",
			},
		},
	]
	for action: Dictionary in invalid_actions:
		_expect(
			not registry.validate_action(action),
			"action %s should reject invalid params"
			% String(action.get("action", ""))
		)
	var json_roundtrip_action: Variant = JSON.parse_string(JSON.stringify({
		"action": EFFECT_ACTIONS.SPAWN_BARRIER,
		"params": {
			"pool_id": POOL_IDS.PROJECTILE_BARRIER,
			"radius": 64.0,
			"hp": 100.0,
			"max_active": 1,
			"recast_policy": "replace",
		},
	}))
	_expect(
		json_roundtrip_action is Dictionary
		and registry.validate_action(json_roundtrip_action as Dictionary),
		"JSON int-like primitive fields should match DataLoader validation"
	)
	var both_slot_action: Dictionary = {
		"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
		"params": {
			"slot": "both",
			"duration": 1.0,
			"modifiers": [
				{"stat": STATS.MOVE_SPEED, "type": "mult", "value": 1.1},
				{"stat": STATS.FIRE_RATE, "type": "mult", "value": 1.1},
			],
		},
	}
	_expect(
		registry.validate_action(both_slot_action),
		"both temporary modifier slot should accept actor and weapon stats"
	)

	_primitive_calls.clear()
	var runtime: GameplayEffectRuntime = _new_runtime(
		Callable(self, "_record_primitive_action")
	)
	var invalid_program: Dictionary = _program("invalid_runtime_boundary")
	invalid_program["actions"] = [
		{"action": EFFECT_ACTIONS.DAMAGE, "params": {"amount": 3.0}},
	]
	var invalid_programs: Array[Dictionary] = [invalid_program]
	_expect(
		not runtime.register_source(
			"test",
			"invalid_runtime_boundary",
			1,
			0,
			invalid_programs
		),
		"runtime should reject invalid primitive params before dispatch"
	)
	var invalid_slot_stat_program: Dictionary = _program(
		"invalid_slot_stat_boundary"
	)
	invalid_slot_stat_program["actions"] = [{
		"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
		"params": {
			"slot": "weapon",
			"duration": 1.0,
			"modifiers": [{
				"stat": STATS.MAX_HP,
				"type": "mult",
				"value": 2.0,
			}],
		},
	}]
	var invalid_slot_stat_programs: Array[Dictionary] = [
		invalid_slot_stat_program,
	]
	_expect(
		not runtime.register_source(
			"test",
			"invalid_slot_stat_boundary",
			2,
			0,
			invalid_slot_stat_programs
		),
		"runtime should reject modifiers whose slot cannot consume the stat"
	)
	var invalid_damage_tick_program: Dictionary = _program(
		"invalid_damage_tick_boundary"
	)
	invalid_damage_tick_program["actions"] = [{
		"action": EFFECT_ACTIONS.APPLY_STATUS,
		"params": {
			"status": STATUS_EFFECTS.SILENCE,
			"duration": 1.0,
			"stack_rule": STATUS_STACK_RULES.REFRESH,
			"granted_ability_tags": [],
			"magnitude": 1.0,
			"tick_interval": 1.0,
		},
	}]
	var invalid_damage_tick_programs: Array[Dictionary] = [
		invalid_damage_tick_program,
	]
	_expect(
		not runtime.register_source(
			"test",
			"invalid_damage_tick_boundary",
			3,
			0,
			invalid_damage_tick_programs
		),
		"runtime should reject damage ticks without a registered element"
	)
	var empty_programs: Array[Dictionary] = []
	_expect(
		not runtime.register_source(
			"test",
			"empty_runtime_boundary",
			4,
			0,
			empty_programs
		),
		"runtime should reject sources without programs"
	)
	var invalid_envelopes: Array[Dictionary] = []
	var extra_field_program: Dictionary = _program("extra_field")
	extra_field_program["surprise"] = true
	invalid_envelopes.append(extra_field_program)
	var string_probability_program: Dictionary = _program("string_probability")
	string_probability_program["proc_chance"] = "1.0"
	invalid_envelopes.append(string_probability_program)
	var string_cooldown_program: Dictionary = _program("string_cooldown")
	string_cooldown_program["internal_cooldown"] = "0.0"
	invalid_envelopes.append(string_cooldown_program)
	var string_reset_program: Dictionary = _program("string_reset")
	string_reset_program["reset_on_condition_fail"] = "false"
	invalid_envelopes.append(string_reset_program)
	var non_interval_reset_program: Dictionary = _program("non_interval_reset")
	non_interval_reset_program["reset_on_condition_fail"] = true
	invalid_envelopes.append(non_interval_reset_program)
	var non_interval_program: Dictionary = _program("non_interval_seconds")
	non_interval_program["interval_seconds"] = 1.0
	invalid_envelopes.append(non_interval_program)
	var missing_interval_program: Dictionary = _program("missing_interval")
	missing_interval_program["trigger"] = EFFECT_TRIGGERS.INTERVAL
	invalid_envelopes.append(missing_interval_program)
	var invalid_id_program: Dictionary = _program("valid_id")
	invalid_id_program["program_id"] = "Invalid-Id"
	invalid_envelopes.append(invalid_id_program)
	var leading_digit_id_program: Dictionary = _program("valid_id")
	leading_digit_id_program["program_id"] = "1bad"
	invalid_envelopes.append(leading_digit_id_program)
	for index: int in range(invalid_envelopes.size()):
		var invalid_envelope_programs: Array[Dictionary] = [
			invalid_envelopes[index],
		]
		_expect(
			not runtime.register_source(
				"test",
				"invalid_envelope_%d" % index,
				index + 5,
				0,
				invalid_envelope_programs
			),
			"runtime should reject invalid program envelope %d" % index
		)
	var result: Dictionary = runtime.emit_event(EFFECT_TRIGGERS.SKILL_ACTIVATED)
	_expect(
		int(result.get("executed_actions", 0)) == 0
		and _primitive_calls.is_empty(),
		"rejected source should not consume action budget or set cooldown"
	)


func _expect_all_actions() -> void:
	_primitive_calls.clear()
	PoolManager.clear_pool(POOL_IDS.BULLET_BASIC)
	PoolManager.clear_pool(POOL_IDS.PROJECTILE_BARRIER)
	_expect(
		PoolManager.register_pool(
			POOL_IDS.BULLET_BASIC,
			Callable(self, "_create_test_bullet"),
			4
		),
		"projectile pool should register"
	)
	_expect(
		PoolManager.register_pool(
			POOL_IDS.PROJECTILE_BARRIER,
			Callable(self, "_create_test_barrier"),
			2
		),
		"barrier pool should register"
	)
	var active_world := Node2D.new()
	add_child(active_world)
	var source := ProjectileSource.new()
	active_world.add_child(source)
	var target := PrimitiveTarget.new()
	active_world.add_child(target)
	var run_loop: GameplayRunLoop = GAMEPLAY_RUN_LOOP_SCRIPT.new()
	run_loop.set("_active_world", active_world)
	var gateway: EffectExecutionGateway = EFFECT_GATEWAY_SCRIPT.new()
	gateway.configure({
		EFFECT_ACTIONS.GRANT_GOLD: Callable(self, "_record_gold_action"),
		EFFECT_ACTIONS.SPAWN_PROJECTILE: Callable(
			run_loop,
			"_execute_effect_spawn_projectile"
		),
		EFFECT_ACTIONS.SPAWN_ENEMY: Callable(self, "_record_enemy_action"),
		EFFECT_ACTIONS.SPAWN_BARRIER: Callable(
			run_loop,
			"_execute_effect_spawn_barrier"
		),
	})
	var runtime: GameplayEffectRuntime = EFFECT_RUNTIME_SCRIPT.new()
	runtime.configure(EFFECT_REGISTRY_SCRIPT.new(), gateway)
	var program: Dictionary = _program("all_actions")
	program["actions"] = _all_action_payloads()
	var programs: Array[Dictionary] = [program]
	_expect(
		runtime.register_source("test", "all_actions", 1, 0, programs),
		"all action program should register"
	)
	var result: Dictionary = runtime.emit_event(
		EFFECT_TRIGGERS.SKILL_ACTIVATED,
		{
			"source_actor": source,
			"target_actor": target,
			"targets": [target],
			"source_team": "team_player",
			"target_team": "team_enemy",
		}
	)
	_expect(
		int(result.get("executed_actions", 0)) == EFFECT_ACTIONS.VALUES.size(),
		"all ten actions should execute"
	)
	_expect(
		is_equal_approx(target.damage_received, 3.0)
		and target.statuses == 1
		and target.temporary_modifiers == 1
		and is_equal_approx(target.healed, 5.0)
		and is_equal_approx(target.shield, 7.0)
		and is_equal_approx(target.overshield, 9.0),
		"target actions should use Combat, status, modifier, and recovery gateways"
	)
	_expect(
		int(_primitive_calls.get(EFFECT_ACTIONS.GRANT_GOLD, 0)) == 1
		and int(_primitive_calls.get(EFFECT_ACTIONS.SPAWN_ENEMY, 0)) == 1,
		"gold and enemy actions should use configured gateway delegates"
	)
	_expect(
		PoolManager.active_count(POOL_IDS.BULLET_BASIC) == 2,
		"spawn_projectile should acquire and configure typed bullets"
	)
	_expect(
		PoolManager.active_count(POOL_IDS.PROJECTILE_BARRIER) == 1,
		"spawn_barrier should acquire and configure the formal barrier pool"
	)
	runtime.emit_event(
		EFFECT_TRIGGERS.SKILL_ACTIVATED,
		{"source_actor": source, "target_actor": target, "targets": [target]}
	)
	_expect(
		PoolManager.active_count(POOL_IDS.PROJECTILE_BARRIER) == 1,
		"replace recast policy should enforce max_active"
	)
	PoolManager.clear_pool(POOL_IDS.BULLET_BASIC)
	PoolManager.clear_pool(POOL_IDS.PROJECTILE_BARRIER)
	run_loop.free()
	active_world.queue_free()


func _expect_probability_cooldown_and_interval() -> void:
	_primitive_calls.clear()
	var runtime: GameplayEffectRuntime = _new_runtime(
		Callable(self, "_record_primitive_action")
	)
	var never_program: Dictionary = _program("never")
	never_program["proc_chance"] = 0.0
	var cooldown_program: Dictionary = _program("cooldown")
	cooldown_program["trigger"] = EFFECT_TRIGGERS.DASH
	cooldown_program["internal_cooldown"] = 1.0
	var interval_program: Dictionary = _program("interval_gate")
	interval_program["trigger"] = EFFECT_TRIGGERS.INTERVAL
	interval_program["interval_seconds"] = 0.5
	var programs: Array[Dictionary] = [
		never_program,
		cooldown_program,
		interval_program,
	]
	_expect(
		runtime.register_source("test", "gates", 1, 0, programs),
		"probability, cooldown, and interval programs should register"
	)
	runtime.emit_event(EFFECT_TRIGGERS.SKILL_ACTIVATED)
	runtime.emit_event(EFFECT_TRIGGERS.DASH)
	runtime.emit_event(EFFECT_TRIGGERS.DASH)
	runtime.tick(0.49)
	_expect(
		int(_primitive_calls.get("never", 0)) == 0
		and int(_primitive_calls.get("cooldown", 0)) == 1
		and int(_primitive_calls.get("interval_gate", 0)) == 0,
		"zero chance, active ICD, and incomplete interval should suppress actions"
	)
	runtime.tick(0.51)
	runtime.emit_event(EFFECT_TRIGGERS.DASH)
	_expect(
		int(_primitive_calls.get("cooldown", 0)) == 2
		and int(_primitive_calls.get("interval_gate", 0)) == 1,
		"GameClock tick should release ICD and fire completed intervals"
	)


func _expect_interval_plan_retention() -> void:
	_primitive_calls.clear()
	_retained_plan_seen.clear()
	var gateway: EffectExecutionGateway = EFFECT_GATEWAY_SCRIPT.new()
	gateway.configure({
		EFFECT_ACTIONS.SPAWN_ENEMY: Callable(self, "_retain_spawn_plan"),
	})
	var runtime: GameplayEffectRuntime = EFFECT_RUNTIME_SCRIPT.new()
	runtime.configure(EFFECT_REGISTRY_SCRIPT.new(), gateway)
	var program: Dictionary = _program("retained_spawn")
	program["trigger"] = EFFECT_TRIGGERS.INTERVAL
	program["interval_seconds"] = 0.1
	var programs: Array[Dictionary] = [program]
	_expect(
		runtime.register_source("gear_mod", "cage", 1, 0, programs),
		"retained interval program should register"
	)
	runtime.tick(0.1)
	runtime.tick(0.1)
	_expect(
		int(_primitive_calls.get("retained_spawn", 0)) == 2
		and String(_retained_plan_seen.get("token", "")) == "fixed_plan",
		"retained interval action_state should reuse the same spawn plan"
	)


func _expect_action_budget() -> void:
	_action_count = 0
	var runtime: GameplayEffectRuntime = _new_runtime(
		Callable(self, "_count_action")
	)
	var program: Dictionary = _program("budget")
	var actions: Array[Dictionary] = []
	for _index: int in GameplayEffectRuntime.MAX_ACTIONS_PER_TICK + 1:
		actions.append({
			"action": EFFECT_ACTIONS.SPAWN_ENEMY,
			"params": {
				"normal_rewards": true,
				"current_layer_only": true,
			},
		})
	program["actions"] = actions
	var programs: Array[Dictionary] = [program]
	_expect(
		runtime.register_source("gear_mod", "budget", 1, 0, programs),
		"budget source should register"
	)
	runtime.emit_event(EFFECT_TRIGGERS.SKILL_ACTIVATED)
	_expect(
		_action_count == GameplayEffectRuntime.MAX_ACTIONS_PER_TICK,
		"runtime should stop at the per-frame action budget"
	)
	_expect(not runtime.diagnostics().is_empty(), "budget overflow should diagnose")


func _new_runtime(callback: Callable) -> GameplayEffectRuntime:
	var gateway: EffectExecutionGateway = EFFECT_GATEWAY_SCRIPT.new()
	gateway.configure({EFFECT_ACTIONS.SPAWN_ENEMY: callback})
	var runtime: GameplayEffectRuntime = EFFECT_RUNTIME_SCRIPT.new()
	runtime.configure(EFFECT_REGISTRY_SCRIPT.new(), gateway)
	return runtime


func _create_test_bullet() -> Node:
	return BULLET_SCRIPT.new()


func _create_test_barrier() -> Node:
	return PROJECTILE_BARRIER_SCRIPT.new()


func _all_action_payloads() -> Array[Dictionary]:
	return [
		{
			"action": EFFECT_ACTIONS.DAMAGE,
			"params": {"amount": 3.0, "element_id": ELEMENTS.ELEMENT_NEUTRAL},
		},
		{
			"action": EFFECT_ACTIONS.APPLY_STATUS,
			"params": {
				"status": STATUS_EFFECTS.SILENCE,
				"duration": 1.0,
				"stack_rule": STATUS_STACK_RULES.REFRESH,
				"granted_ability_tags": [ABILITY_TAGS.ABILITY_TAG_SILENCED],
			},
		},
		{
			"action": EFFECT_ACTIONS.TEMPORARY_MODIFIER,
			"params": {
				"slot": "actor",
				"duration": 1.0,
				"modifiers": [
					{"stat": STATS.MOVE_SPEED, "type": "mult", "value": 1.1},
				],
			},
		},
		{"action": EFFECT_ACTIONS.HEAL, "params": {"amount": 5.0}},
		{"action": EFFECT_ACTIONS.GRANT_SHIELD, "params": {"amount": 7.0}},
		{
			"action": EFFECT_ACTIONS.GRANT_OVERSHIELD,
			"params": {"amount": 9.0},
		},
		{
			"action": EFFECT_ACTIONS.GRANT_GOLD,
			"params": {
				"amount": 11,
				"reason_id": GOLD_TRANSACTION_REASONS.EVENT_REWARD,
			},
		},
		{
			"action": EFFECT_ACTIONS.SPAWN_PROJECTILE,
			"params": {
				"pool_id": POOL_IDS.BULLET_BASIC,
				"amount": 3.0,
				"element_id": ELEMENTS.ELEMENT_NEUTRAL,
				"speed": 800.0,
				"range": 600.0,
				"hit_radius": 8.0,
				"lifetime": 2.0,
				"count": 2,
				"spread_degrees": 10.0,
				"pierce_count": 0,
				"wall_pierce": false,
				"damage_target_groups": [DAMAGE_TARGET_GROUPS.ACTIVE_ENEMIES],
			},
		},
		{
			"action": EFFECT_ACTIONS.SPAWN_ENEMY,
			"params": {"normal_rewards": true, "current_layer_only": true},
		},
		{
			"action": EFFECT_ACTIONS.SPAWN_BARRIER,
			"params": {
				"pool_id": POOL_IDS.PROJECTILE_BARRIER,
				"radius": 64.0,
				"hp": 100.0,
				"max_active": 1,
				"recast_policy": "replace",
			},
		},
	]


func _program(program_id: String) -> Dictionary:
	return {
		"program_id": program_id,
		"trigger": EFFECT_TRIGGERS.SKILL_ACTIVATED,
		"conditions": [],
		"actions": [
			{
				"action": EFFECT_ACTIONS.SPAWN_ENEMY,
				"params": {
					"normal_rewards": true,
					"current_layer_only": true,
				},
			},
		],
		"proc_chance": 1.0,
		"internal_cooldown": 0.0,
	}


func _record_action(_params: Dictionary, context: Dictionary) -> Dictionary:
	_order.append(String(context.get("source_key", "")))
	return {"ok": true, "applied_targets": 1}


func _record_primitive_action(
	_params: Dictionary,
	context: Dictionary
) -> Dictionary:
	var program_id: String = String(context.get("program_id", ""))
	_primitive_calls[program_id] = int(_primitive_calls.get(program_id, 0)) + 1
	return {"ok": true, "applied_targets": 1}


func _record_gold_action(
	_params: Dictionary,
	_context: Dictionary
) -> Dictionary:
	_primitive_calls[EFFECT_ACTIONS.GRANT_GOLD] = int(
		_primitive_calls.get(EFFECT_ACTIONS.GRANT_GOLD, 0)
	) + 1
	return {"ok": true, "applied_targets": 1}


func _record_enemy_action(
	_params: Dictionary,
	_context: Dictionary
) -> Dictionary:
	_primitive_calls[EFFECT_ACTIONS.SPAWN_ENEMY] = int(
		_primitive_calls.get(EFFECT_ACTIONS.SPAWN_ENEMY, 0)
	) + 1
	return {"ok": true, "applied_targets": 1}


func _retain_spawn_plan(
	_params: Dictionary,
	context: Dictionary
) -> Dictionary:
	var program_id: String = String(context.get("program_id", ""))
	var call_count: int = int(_primitive_calls.get(program_id, 0)) + 1
	_primitive_calls[program_id] = call_count
	var program_state: Dictionary = context.get("program_state", {}) as Dictionary
	if call_count == 1:
		return {
			"ok": false,
			"retain_interval": true,
			"action_state": {"pending_plan": {"token": "fixed_plan"}},
		}
	_retained_plan_seen = program_state.get("pending_plan", {}) as Dictionary
	return {"ok": true, "applied_targets": 1, "action_state": {}}


func _chain_action(_params: Dictionary, _context: Dictionary) -> Dictionary:
	_action_count += 1
	_chain_runtime.emit_event(EFFECT_TRIGGERS.SKILL_ACTIVATED)
	return {"ok": true, "applied_targets": 1}


func _count_action(_params: Dictionary, _context: Dictionary) -> Dictionary:
	_action_count += 1
	return {"ok": true, "applied_targets": 1}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[effect-runtime-smoke] passed")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[effect-runtime-smoke] %s" % failure)
	get_tree().quit(1)
