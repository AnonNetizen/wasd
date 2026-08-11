extends SmokeHarness


const ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_charge_attack_handler.gd"
)

var _runtime: ACTION_RUNTIME_SCRIPT = ACTION_RUNTIME_SCRIPT.new()
var _events: Array[String] = []
var _targets: Array[HANDLER_SCRIPT.TargetPort] = []
var _movement_result: HANDLER_SCRIPT.MovementResult = null
var _movement_snapshot: Dictionary = {}
var _commit_snapshot: Dictionary = {}
var _finish_snapshot: Dictionary = {}
var _sweep_results: Dictionary = {}
var _damage_results: Dictionary = {}
var _knockback_capabilities: Dictionary = {}
var _damage_snapshots: Dictionary = {}
var _knockbacks: Array[Dictionary] = []


func before_each() -> void:
	_runtime.reset()
	_events.clear()
	_targets.clear()
	_movement_result = HANDLER_SCRIPT.MovementResult.new()
	_movement_result.previous_position = Vector2.ZERO
	_movement_result.current_position = Vector2(40.0, 0.0)
	_movement_snapshot.clear()
	_commit_snapshot.clear()
	_finish_snapshot.clear()
	_sweep_results.clear()
	_damage_results.clear()
	_knockback_capabilities.clear()
	_damage_snapshots.clear()
	_knockbacks.clear()


func test_missing_focus_and_zero_direction_preserve_start_order() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	_runtime.set_locked_direction(Vector2.LEFT)
	_runtime.set_attack_hit_committed(true)
	_runtime.set_collateral_player_hit_committed(true)
	var no_focus: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start(
		_runtime,
		_config(),
		_start_request(false, Vector2.RIGHT),
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
		_start_request(true, Vector2.ZERO),
		_ports()
	)
	assert_true(zero_direction.handled)
	assert_false(zero_direction.started)
	assert_eq(zero_direction.reason, HANDLER_SCRIPT.REASON_INVALID_DIRECTION)
	assert_eq(_runtime.locked_direction(), Vector2.ZERO)
	assert_true(_runtime.attack_hit_committed())
	assert_true(_runtime.collateral_player_hit_committed())
	assert_true(_events.is_empty())


func test_windup_boundary_commits_before_first_release_movement() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	var config: HANDLER_SCRIPT.Config = _config()
	var started: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start(
		_runtime,
		config,
		_start_request(true, Vector2(4.0, 0.0)),
		_ports()
	)
	assert_true(started.started)
	assert_true(started.windup_started)
	assert_false(started.committed)
	assert_eq(_events, ["windup"])
	assert_eq(_runtime.locked_direction(), Vector2.RIGHT)
	assert_eq(
		_runtime.action_state(),
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_WINDUP
	)
	assert_almost_eq(_runtime.action_timer(), 0.3, 0.0)

	var released: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		_step_request(0.31),
		_ports()
	)
	assert_true(released.handled)
	assert_true(released.committed)
	assert_false(released.moved)
	assert_eq(_events, ["windup", "committed"])
	assert_eq(
		_runtime.action_state(),
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE
	)
	assert_almost_eq(_runtime.action_timer(), 0.8, 0.0)
	assert_eq(_commit_snapshot, {
		"action_state": ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE,
		"action_timer": 0.8,
		"attack_hit": false,
		"collateral_hit": false,
		"cooldown": 0.0,
		"current_action": ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET,
	})

	var moved: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		_step_request(0.2),
		_ports()
	)
	assert_true(moved.handled)
	assert_true(moved.moved)
	assert_eq(_events, ["windup", "committed", "move", "targets"])
	assert_almost_eq(_runtime.action_timer(), 0.6, 0.000_001)
	assert_eq(_movement_snapshot.get("direction"), Vector2.RIGHT)
	assert_eq(_movement_snapshot.get("motion"), Vector2(60.0, 0.0))
	assert_almost_eq(
		float(_movement_snapshot.get("action_timer", 0.0)),
		0.6,
		0.000_001
	)


func test_zero_windup_commits_synchronously_without_windup_signal() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	var config: HANDLER_SCRIPT.Config = _config()
	config.windup = 0.0
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start(
		_runtime,
		config,
		_start_request(true, Vector2.RIGHT),
		_ports()
	)
	assert_true(result.started)
	assert_false(result.windup_started)
	assert_true(result.committed)
	assert_eq(_events, ["committed"])
	assert_eq(
		_runtime.action_state(),
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE
	)
	assert_almost_eq(_runtime.action_timer(), 0.8, 0.0)


func test_primary_then_distinct_player_sets_flags_before_damage() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE
	)
	_runtime.set_action_timer(0.7)
	_runtime.set_locked_direction(Vector2.RIGHT)
	_sweep_results = {"primary": true, "player": true}
	_damage_results = {"primary": true, "player": true}
	_knockback_capabilities = {"primary": true, "player": true}
	_targets = [
		_target("primary", false, false),
		_target("player", true, true),
	]
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		_config(),
		_step_request(0.1),
		_ports()
	)
	assert_true(result.handled)
	assert_eq(result.sweep_hits, 2)
	assert_eq(result.applied_hits, 2)
	assert_eq(result.knockbacks, 1)
	assert_eq(_events, [
		"move",
		"targets",
		"primary:sweep",
		"primary:damage",
		"player:sweep",
		"player:damage",
		"player:capability",
		"player:knockback",
	])
	assert_eq(_damage_snapshots.get("primary"), {
		"attack_hit": true,
		"collateral_hit": false,
	})
	assert_eq(_damage_snapshots.get("player"), {
		"attack_hit": true,
		"collateral_hit": true,
	})
	assert_eq(_knockbacks, [{
		"direction": Vector2.RIGHT,
		"distance": 24.0,
		"duration": 0.18,
		"target": "player",
	}])


func test_blocked_damage_still_stops_on_geometric_hit_without_knockback() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE
	)
	_runtime.set_action_timer(0.7)
	_runtime.set_locked_direction(Vector2.RIGHT)
	_sweep_results = {"player": true}
	_damage_results = {"player": false}
	_knockback_capabilities = {"player": true}
	_targets = [_target("player", false, true)]
	var config: HANDLER_SCRIPT.Config = _config()
	config.stop_on_hit = true
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		_step_request(0.1),
		_ports()
	)
	assert_true(result.finished)
	assert_eq(result.sweep_hits, 1)
	assert_eq(result.applied_hits, 0)
	assert_eq(result.knockbacks, 0)
	assert_true(_runtime.attack_hit_committed())
	assert_eq(_runtime.current_action(), "")
	assert_eq(_runtime.action_state(), "")
	assert_almost_eq(_runtime.attack_cooldown_remaining(), 0.9, 0.0)
	assert_eq(_events, [
		"move",
		"targets",
		"player:sweep",
		"player:damage",
		"finished",
	])


func test_collision_timeout_and_non_charge_state_keep_finish_boundaries() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	)
	_runtime.set_action_timer(0.4)
	var ignored: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		_config(),
		_step_request(0.2),
		_ports()
	)
	assert_false(ignored.handled)
	assert_almost_eq(_runtime.action_timer(), 0.4, 0.0)
	assert_true(_events.is_empty())

	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE
	)
	_runtime.set_action_timer(0.1)
	_runtime.set_locked_direction(Vector2.RIGHT)
	_movement_result.collided = true
	var finished: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		_config(),
		_step_request(0.01),
		_ports()
	)
	assert_true(finished.handled)
	assert_true(finished.finished)
	assert_eq(_events, ["move", "targets", "finished"])
	assert_eq(_finish_snapshot, {
		"action_state": "",
		"action_timer": 0.0,
		"attack_hit": false,
		"collateral_hit": false,
		"cooldown": 0.9,
		"current_action": "",
	})


func _config() -> HANDLER_SCRIPT.Config:
	var config: HANDLER_SCRIPT.Config = HANDLER_SCRIPT.Config.new()
	config.windup = 0.3
	config.cooldown = 0.9
	config.release_duration = 0.8
	config.speed_multiplier = 2.0
	config.base_damage = 14.0
	config.element_id = ELEMENTS.ELEMENT_NEUTRAL
	config.stop_on_hit = false
	config.knockback_distance = 24.0
	config.knockback_duration = 0.18
	return config


func _start_request(
	focus_available: bool,
	target_direction: Vector2
) -> HANDLER_SCRIPT.StartRequest:
	var request: HANDLER_SCRIPT.StartRequest = HANDLER_SCRIPT.StartRequest.new()
	request.focus_target_available = focus_available
	request.target_direction = target_direction
	return request


func _step_request(delta: float) -> HANDLER_SCRIPT.StepRequest:
	var request: HANDLER_SCRIPT.StepRequest = HANDLER_SCRIPT.StepRequest.new()
	request.delta = delta
	request.move_speed = 100.0
	request.move_speed_multiplier = 1.5
	return request


func _ports() -> HANDLER_SCRIPT.Ports:
	return HANDLER_SCRIPT.Ports.new(
		Callable(self, "_emit_windup"),
		Callable(self, "_emit_committed"),
		Callable(self, "_move_charge"),
		Callable(self, "_provide_targets"),
		Callable(self, "_finish_charge")
	)


func _target(
	target_id: String,
	uses_collateral_flag: bool,
	is_player_target: bool
) -> HANDLER_SCRIPT.TargetPort:
	return HANDLER_SCRIPT.TargetPort.new(
		uses_collateral_flag,
		is_player_target,
		Callable(self, "_sweep_hits").bind(target_id),
		Callable(self, "_apply_damage").bind(target_id),
		Callable(self, "_can_knockback").bind(target_id),
		Callable(self, "_apply_knockback").bind(target_id)
	)


func _emit_windup(_duration: float) -> void:
	_events.append("windup")


func _emit_committed() -> void:
	_events.append("committed")
	_commit_snapshot = _runtime_snapshot()


func _move_charge(
	motion: Vector2,
	direction: Vector2
) -> HANDLER_SCRIPT.MovementResult:
	_events.append("move")
	_movement_snapshot = {
		"action_timer": _runtime.action_timer(),
		"direction": direction,
		"motion": motion,
	}
	return _movement_result


func _provide_targets() -> Array[HANDLER_SCRIPT.TargetPort]:
	_events.append("targets")
	return _targets


func _finish_charge() -> void:
	_events.append("finished")
	_finish_snapshot = _runtime_snapshot()


func _sweep_hits(
	_from_position: Vector2,
	_to_position: Vector2,
	target_id: String
) -> bool:
	_events.append(target_id + ":sweep")
	return bool(_sweep_results.get(target_id, false))


func _apply_damage(
	base_damage: float,
	_element_id: String,
	target_id: String
) -> HANDLER_SCRIPT.DamageResult:
	_events.append(target_id + ":damage")
	_damage_snapshots[target_id] = {
		"attack_hit": _runtime.attack_hit_committed(),
		"collateral_hit": _runtime.collateral_player_hit_committed(),
	}
	var result: HANDLER_SCRIPT.DamageResult = HANDLER_SCRIPT.DamageResult.new()
	result.applied = bool(_damage_results.get(target_id, false))
	result.amount = base_damage if result.applied else 0.0
	result.reason = "applied" if result.applied else "rejected"
	return result


func _can_knockback(target_id: String) -> bool:
	_events.append(target_id + ":capability")
	return bool(_knockback_capabilities.get(target_id, false))


func _apply_knockback(
	direction: Vector2,
	distance: float,
	duration: float,
	target_id: String
) -> void:
	_events.append(target_id + ":knockback")
	_knockbacks.append({
		"direction": direction,
		"distance": distance,
		"duration": duration,
		"target": target_id,
	})


func _runtime_snapshot() -> Dictionary:
	return {
		"action_state": _runtime.action_state(),
		"action_timer": _runtime.action_timer(),
		"attack_hit": _runtime.attack_hit_committed(),
		"collateral_hit": _runtime.collateral_player_hit_committed(),
		"cooldown": _runtime.attack_cooldown_remaining(),
		"current_action": _runtime.current_action(),
	}
