extends SmokeHarness


const ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_melee_attack_handler.gd"
)

var _runtime: ACTION_RUNTIME_SCRIPT = ACTION_RUNTIME_SCRIPT.new()
var _events: Array[String] = []
var _targets: Array[HANDLER_SCRIPT.TargetPort] = []
var _target_available: Dictionary = {}
var _target_positions: Dictionary = {}
var _target_los: Dictionary = {}
var _target_damage_applied: Dictionary = {}
var _los_order: Array[String] = []
var _damage_order: Array[String] = []
var _damage_calls: Array[Dictionary] = []
var _windup_snapshot: Dictionary = {}
var _commit_snapshot: Dictionary = {}
var _finish_snapshot: Dictionary = {}


func before_each() -> void:
	_runtime.reset()
	_events.clear()
	_targets.clear()
	_target_available.clear()
	_target_positions.clear()
	_target_los.clear()
	_target_damage_applied.clear()
	_los_order.clear()
	_damage_order.clear()
	_damage_calls.clear()
	_windup_snapshot.clear()
	_commit_snapshot.clear()
	_finish_snapshot.clear()


func test_missing_focus_and_zero_direction_preserve_start_order() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
	_runtime.set_locked_direction(Vector2.LEFT)
	_runtime.set_attack_hit_committed(true)
	_runtime.set_collateral_player_hit_committed(true)
	var no_focus: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start(
		_runtime,
		_config(),
		_request(false, Vector2.RIGHT),
		_ports()
	)
	assert_true(no_focus.handled)
	assert_false(no_focus.started)
	assert_eq(no_focus.reason, HANDLER_SCRIPT.REASON_FOCUS_UNAVAILABLE)
	assert_eq(_runtime.locked_direction(), Vector2.LEFT)
	assert_true(_runtime.attack_hit_committed())
	assert_true(_runtime.collateral_player_hit_committed())
	assert_true(_events.is_empty())

	var zero_direction: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start(
		_runtime,
		_config(),
		_request(true, Vector2.ZERO),
		_ports()
	)
	assert_true(zero_direction.handled)
	assert_false(zero_direction.started)
	assert_eq(
		zero_direction.reason,
		HANDLER_SCRIPT.REASON_INVALID_DIRECTION
	)
	assert_eq(_runtime.locked_direction(), Vector2.ZERO)
	assert_true(_runtime.attack_hit_committed())
	assert_true(_runtime.collateral_player_hit_committed())
	assert_eq(_runtime.action_state(), "")
	assert_true(_events.is_empty())


func test_start_and_timer_boundary_keep_windup_and_finish_order() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
	_runtime.set_attack_hit_committed(true)
	_runtime.set_collateral_player_hit_committed(true)
	var config: HANDLER_SCRIPT.Config = _config()
	var started: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start(
		_runtime,
		config,
		_request(true, Vector2(2.0, 0.0)),
		_ports()
	)
	assert_true(started.handled)
	assert_true(started.started)
	assert_true(started.windup_started)
	assert_false(started.committed)
	assert_eq(_runtime.locked_direction(), Vector2.RIGHT)
	assert_false(_runtime.attack_hit_committed())
	assert_false(_runtime.collateral_player_hit_committed())
	assert_eq(
		_runtime.action_state(),
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	)
	assert_almost_eq(_runtime.action_timer(), 0.32, 0.0)
	assert_eq(_events, ["windup"])
	assert_eq(_windup_snapshot, {
		"current_action": ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK,
		"action_state": ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP,
		"action_timer": 0.32,
		"cooldown": 0.0,
		"attack_hit_committed": false,
	})

	var before_due: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		0.319,
		_ports()
	)
	assert_true(before_due.handled)
	assert_false(before_due.committed)
	assert_almost_eq(_runtime.action_timer(), 0.001, 0.000_001)

	var due: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		0.0011,
		_ports()
	)
	assert_true(due.handled)
	assert_true(due.committed)
	assert_true(due.finished)
	assert_eq(due.damage_attempts, 0)
	assert_eq(_events, ["windup", "targets", "committed", "finished"])
	assert_eq(_commit_snapshot, {
		"current_action": ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK,
		"action_state": ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP,
		"action_timer": 0.0,
		"cooldown": 0.0,
		"attack_hit_committed": false,
		"attack_range": 56.0,
	})
	assert_eq(_finish_snapshot, {
		"current_action": "",
		"action_state": "",
		"action_timer": 0.0,
		"cooldown": 0.85,
		"attack_hit_committed": false,
	})


func test_zero_windup_commits_primary_then_collateral_before_signal() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
	_targets = [
		_target("primary", true, Vector2(20.0, 0.0), true, false),
		_target("collateral", true, Vector2(24.0, 2.0), true, true),
	]
	var config: HANDLER_SCRIPT.Config = _config()
	config.windup = 0.0
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start(
		_runtime,
		config,
		_request(true, Vector2.RIGHT),
		_ports()
	)
	assert_true(result.started)
	assert_true(result.committed)
	assert_true(result.finished)
	assert_eq(result.damage_attempts, 2)
	assert_eq(result.applied_hits, 1)
	assert_eq(_damage_order, ["primary", "collateral"])
	assert_eq(_damage_calls, [
		{
			"target": "primary",
			"base_damage": 18.0,
			"element_id": ELEMENTS.ELEMENT_NEUTRAL,
		},
		{
			"target": "collateral",
			"base_damage": 18.0,
			"element_id": ELEMENTS.ELEMENT_NEUTRAL,
		},
	])
	assert_eq(_events, [
		"windup",
		"targets",
		"primary:available",
		"primary:position",
		"primary:los",
		"primary:damage",
		"collateral:available",
		"collateral:position",
		"collateral:los",
		"collateral:damage",
		"committed",
		"finished",
	])
	assert_true(bool(_commit_snapshot.get("attack_hit_committed", false)))
	assert_false(_runtime.collateral_player_hit_committed())
	assert_eq(_runtime.current_action(), "")
	assert_almost_eq(_runtime.attack_cooldown_remaining(), 0.85, 0.0)


func test_arc_range_and_los_short_circuit_with_same_position_hit() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	)
	_runtime.set_action_timer(0.0)
	_runtime.set_locked_direction(Vector2.RIGHT)
	_targets = [
		_target("unavailable", false, Vector2.RIGHT, true, true),
		_target("same", true, Vector2.ZERO, false, true),
		_target("far", true, Vector2(60.0, 0.0), true, true),
		_target("outside_arc", true, Vector2(0.0, 30.0), true, true),
		_target("blocked", true, Vector2(30.0, 0.0), false, true),
		_target("valid", true, Vector2(40.0, 0.0), true, true),
	]
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		_config(),
		0.0,
		_ports()
	)
	assert_true(result.committed)
	assert_eq(result.damage_attempts, 2)
	assert_eq(result.applied_hits, 2)
	assert_eq(_los_order, ["blocked", "valid"])
	assert_eq(_damage_order, ["same", "valid"])
	assert_true(_runtime.attack_hit_committed())


func test_non_melee_state_is_not_handled_or_advanced() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_WINDUP
	)
	_runtime.set_action_timer(0.25)
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		_config(),
		0.1,
		_ports()
	)
	assert_false(result.handled)
	assert_almost_eq(_runtime.action_timer(), 0.25, 0.0)
	assert_true(_events.is_empty())


func test_target_port_output_does_not_alias_actor_array() -> void:
	_targets = [
		_target("primary", true, Vector2.RIGHT, true, true),
	]
	var copied_targets: Array[HANDLER_SCRIPT.TargetPort] = (
		_ports().targets()
	)
	copied_targets.clear()
	assert_eq(_targets.size(), 1)


func _config() -> HANDLER_SCRIPT.Config:
	var config: HANDLER_SCRIPT.Config = HANDLER_SCRIPT.Config.new()
	config.windup = 0.32
	config.cooldown = 0.85
	config.attack_range = 56.0
	config.arc_degrees = 100.0
	config.base_damage = 18.0
	config.element_id = ELEMENTS.ELEMENT_NEUTRAL
	return config


func _request(
	focus_target_available: bool,
	target_direction: Vector2
) -> HANDLER_SCRIPT.StartRequest:
	var request: HANDLER_SCRIPT.StartRequest = (
		HANDLER_SCRIPT.StartRequest.new()
	)
	request.focus_target_available = focus_target_available
	request.target_direction = target_direction
	return request


func _ports() -> HANDLER_SCRIPT.Ports:
	return HANDLER_SCRIPT.Ports.new(
		Callable(self, "_emit_windup"),
		Callable(self, "_provide_targets"),
		Callable(self, "_emit_committed"),
		Callable(self, "_finish_attack")
	)


func _target(
	target_id: String,
	available: bool,
	relative_position: Vector2,
	has_los: bool,
	damage_applied: bool
) -> HANDLER_SCRIPT.TargetPort:
	_target_available[target_id] = available
	_target_positions[target_id] = relative_position
	_target_los[target_id] = has_los
	_target_damage_applied[target_id] = damage_applied
	return HANDLER_SCRIPT.TargetPort.new(
		Callable(self, "_target_is_available").bind(target_id),
		Callable(self, "_target_relative_position").bind(target_id),
		Callable(self, "_target_has_los").bind(target_id),
		Callable(self, "_apply_damage").bind(target_id)
	)


func _emit_windup(_duration: float) -> void:
	_events.append("windup")
	_windup_snapshot = _runtime_snapshot()


func _provide_targets() -> Array[HANDLER_SCRIPT.TargetPort]:
	_events.append("targets")
	return _targets


func _emit_committed(attack_range: float) -> void:
	_events.append("committed")
	_commit_snapshot = _runtime_snapshot()
	_commit_snapshot["attack_range"] = attack_range


func _finish_attack() -> void:
	_events.append("finished")
	_finish_snapshot = _runtime_snapshot()


func _target_is_available(target_id: String) -> bool:
	_events.append(target_id + ":available")
	return bool(_target_available.get(target_id, false))


func _target_relative_position(target_id: String) -> Vector2:
	_events.append(target_id + ":position")
	var raw_position: Variant = _target_positions.get(
		target_id,
		Vector2.ZERO
	)
	return raw_position as Vector2


func _target_has_los(target_id: String) -> bool:
	_events.append(target_id + ":los")
	_los_order.append(target_id)
	return bool(_target_los.get(target_id, false))


func _apply_damage(
	base_damage: float,
	element_id: String,
	target_id: String
) -> HANDLER_SCRIPT.DamageResult:
	_events.append(target_id + ":damage")
	_damage_order.append(target_id)
	_damage_calls.append({
		"target": target_id,
		"base_damage": base_damage,
		"element_id": element_id,
	})
	var result: HANDLER_SCRIPT.DamageResult = (
		HANDLER_SCRIPT.DamageResult.new()
	)
	result.applied = bool(_target_damage_applied.get(target_id, false))
	result.amount = base_damage if result.applied else 0.0
	result.reason = "applied" if result.applied else "rejected"
	return result


func _runtime_snapshot() -> Dictionary:
	return {
		"current_action": _runtime.current_action(),
		"action_state": _runtime.action_state(),
		"action_timer": _runtime.action_timer(),
		"cooldown": _runtime.attack_cooldown_remaining(),
		"attack_hit_committed": _runtime.attack_hit_committed(),
	}
