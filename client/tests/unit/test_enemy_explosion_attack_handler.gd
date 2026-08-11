extends SmokeHarness


const ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_explosion_attack_handler.gd"
)

var _runtime: ACTION_RUNTIME_SCRIPT = ACTION_RUNTIME_SCRIPT.new()
var _events: Array[String] = []
var _source_position: Vector2 = Vector2.ZERO
var _move_source_on_commit: bool = false
var _direct_targets: Array[HANDLER_SCRIPT.DirectTargetPort] = []
var _enemy_targets: Array[HANDLER_SCRIPT.EnemyTargetPort] = []
var _append_enemy_on_commit: HANDLER_SCRIPT.EnemyTargetPort = null
var _target_valid: Dictionary = {}
var _target_positions: Dictionary = {}
var _enemy_source: Dictionary = {}
var _enemy_armed: Dictionary = {}
var _enemy_alive: Dictionary = {}
var _enemy_serial: Dictionary = {}
var _blocked_position_x: Dictionary = {}
var _damage_order: Array[String] = []
var _damage_snapshots: Array[Dictionary] = []
var _windup_snapshot: Dictionary = {}
var _commit_snapshot: Dictionary = {}
var _finish_snapshot: Dictionary = {}


func before_each() -> void:
	_runtime.reset()
	_events.clear()
	_source_position = Vector2.ZERO
	_move_source_on_commit = false
	_direct_targets.clear()
	_enemy_targets.clear()
	_append_enemy_on_commit = null
	_target_valid.clear()
	_target_positions.clear()
	_enemy_source.clear()
	_enemy_armed.clear()
	_enemy_alive.clear()
	_enemy_serial.clear()
	_blocked_position_x.clear()
	_damage_order.clear()
	_damage_snapshots.clear()
	_windup_snapshot.clear()
	_commit_snapshot.clear()
	_finish_snapshot.clear()


func test_arm_rejections_do_not_mutate_runtime_or_call_ports() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
	_runtime.set_attack_hit_committed(true)
	var unavailable: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.arm(
		_runtime,
		_config(),
		_arm_request(false, false),
		_ports()
	)
	assert_true(unavailable.handled)
	assert_eq(unavailable.reason, HANDLER_SCRIPT.REASON_ACTION_UNAVAILABLE)
	assert_eq(
		_runtime.current_action(),
		ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK
	)
	assert_true(_runtime.attack_hit_committed())
	assert_true(_events.is_empty())

	_runtime.set_armed(true)
	var already_armed: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.arm(
		_runtime,
		_config(),
		_arm_request(true, false),
		_ports()
	)
	assert_eq(already_armed.reason, HANDLER_SCRIPT.REASON_ALREADY_ARMED)
	assert_true(_events.is_empty())

	_runtime.set_armed(false)
	_runtime.set_has_exploded(true)
	var exploded: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.arm(
		_runtime,
		_config(),
		_arm_request(true, false),
		_ports()
	)
	assert_eq(exploded.reason, HANDLER_SCRIPT.REASON_ALREADY_EXPLODED)
	assert_true(_events.is_empty())


func test_fresh_arm_keeps_runtime_port_and_signal_order() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
	_runtime.set_attack_cooldown_remaining(1.25)
	_runtime.set_burst_shots_remaining(3)
	_runtime.set_locked_direction(Vector2.DOWN)
	_runtime.set_attack_hit_committed(true)
	_runtime.set_collateral_player_hit_committed(true)
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.arm(
		_runtime,
		_config(),
		_arm_request(true, true),
		_ports()
	)
	assert_true(result.handled)
	assert_true(result.armed)
	assert_true(result.windup_emitted)
	assert_false(result.detonated)
	assert_eq(_events, [
		"clear_focus",
		"stop_movement",
		"collision:false",
		"windup",
		"refresh",
	])
	assert_eq(_windup_snapshot, {
		"action_state": ACTION_RUNTIME_SCRIPT.ACTION_STATE_ARMED_WINDUP,
		"action_timer": 0.4,
		"armed": true,
		"armed_from_chain": true,
		"attack_hit": false,
		"collateral_hit": false,
		"current_action": ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
		"exploded": false,
		"locked_direction": Vector2.ZERO,
	})
	assert_almost_eq(_runtime.attack_cooldown_remaining(), 1.25, 0.0)
	assert_eq(_runtime.burst_shots_remaining(), 3)


func test_zero_windup_detonates_synchronously_and_preserves_state() -> void:
	var config: HANDLER_SCRIPT.Config = _config()
	config.windup = 0.0
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.arm(
		_runtime,
		config,
		_arm_request(true, false),
		_ports()
	)
	assert_true(result.armed)
	assert_true(result.detonated)
	assert_true(result.finished)
	assert_eq(_events, [
		"clear_focus",
		"stop_movement",
		"collision:false",
		"windup",
		"refresh",
		"committed",
		"direct_targets",
		"enemy_targets",
		"finished",
	])
	assert_eq(_commit_snapshot, {
		"action_state": ACTION_RUNTIME_SCRIPT.ACTION_STATE_ARMED_WINDUP,
		"action_timer": 0.0,
		"armed": true,
		"armed_from_chain": false,
		"attack_hit": true,
		"collateral_hit": false,
		"current_action": ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
		"exploded": true,
		"locked_direction": Vector2.ZERO,
	})
	assert_eq(_finish_snapshot, _commit_snapshot)
	assert_true(_runtime.is_armed())
	assert_true(_runtime.has_exploded())
	assert_eq(
		_runtime.current_action(),
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)


func test_advance_uses_timer_boundary_and_exploded_noop() -> void:
	HANDLER_SCRIPT.arm(
		_runtime,
		_config(),
		_arm_request(true, false),
		_ports()
	)
	_events.clear()
	var before_due: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		_config(),
		0.39,
		_ports()
	)
	assert_true(before_due.handled)
	assert_false(before_due.detonated)
	assert_almost_eq(_runtime.action_timer(), 0.01, 0.000_001)
	assert_true(_events.is_empty())

	var due: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		_config(),
		0.011,
		_ports()
	)
	assert_true(due.detonated)
	assert_true(due.finished)
	assert_almost_eq(_runtime.action_timer(), 0.0, 0.0)
	var event_count: int = _events.size()
	var exploded: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		_config(),
		1.0,
		_ports()
	)
	assert_true(exploded.handled)
	assert_eq(exploded.reason, HANDLER_SCRIPT.REASON_ALREADY_EXPLODED)
	assert_eq(_events.size(), event_count)
	assert_almost_eq(_runtime.action_timer(), 0.0, 0.0)


func test_direct_uses_live_source_enemy_uses_frozen_origin_without_dedup() -> void:
	var shared_direct: HANDLER_SCRIPT.DirectTargetPort = _direct_target(
		"shared",
		Vector2(100.0, 0.0)
	)
	var shared_enemy: HANDLER_SCRIPT.EnemyTargetPort = _enemy_target(
		"shared",
		Vector2(100.0, 0.0),
		4
	)
	_direct_targets = [shared_direct]
	_append_enemy_on_commit = shared_enemy
	_move_source_on_commit = true
	var config: HANDLER_SCRIPT.Config = _config()
	config.windup = 0.0
	config.radius = 120.0
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.arm(
		_runtime,
		config,
		_arm_request(true, false),
		_ports()
	)
	assert_true(result.detonated)
	assert_eq(result.direct_damage_attempts, 1)
	assert_eq(result.enemy_damage_attempts, 1)
	assert_eq(_damage_order, ["shared", "shared"])
	assert_eq(_events.slice(5), [
		"committed",
		"direct_targets",
		"los:100:100",
		"shared:damage",
		"enemy_targets",
		"los:0:100",
		"shared:damage",
		"finished",
	])


func test_enemy_collection_filters_then_sorts_by_serial_only() -> void:
	_enemy_targets = [
		_enemy_target("source", Vector2.ZERO, 1, true),
		_enemy_target("armed", Vector2.RIGHT, 3, false, true),
		_enemy_target("dead", Vector2.RIGHT * 2.0, 4, false, false, false),
		_enemy_target("far", Vector2.RIGHT * 80.0, 5),
		_enemy_target("blocked", Vector2.RIGHT * 3.0, 6),
		_enemy_target("late", Vector2.RIGHT * 5.0, 9),
		_enemy_target("early", Vector2.RIGHT * 4.0, 2),
	]
	_blocked_position_x[3] = true
	var config: HANDLER_SCRIPT.Config = _config()
	config.windup = 0.0
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.arm(
		_runtime,
		config,
		_arm_request(true, false),
		_ports()
	)
	assert_eq(result.enemy_damage_attempts, 2)
	assert_eq(_damage_order, ["early", "late"])
	assert_true(_events.has("los:0:3"))
	assert_false(_events.has("far:damage"))
	assert_false(_events.has("armed:damage"))
	assert_false(_events.has("dead:damage"))


func test_restore_armed_does_not_reuse_fresh_arm_or_auto_detonate() -> void:
	_runtime.set_current_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE
	)
	_runtime.set_action_timer(0.0)
	_runtime.set_attack_cooldown_remaining(1.5)
	_runtime.set_burst_shots_remaining(2)
	_runtime.set_attack_hit_committed(false)
	_runtime.set_collateral_player_hit_committed(true)
	_runtime.set_locked_direction(Vector2.DOWN)
	_runtime.set_armed(true)
	_runtime.set_armed_from_chain(true)
	_runtime.set_has_exploded(false)
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.restore_armed(
		_runtime,
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
		_ports()
	)
	assert_true(result.handled)
	assert_true(result.restored)
	assert_true(result.windup_emitted)
	assert_false(result.detonated)
	assert_eq(_events, ["collision:false", "windup"])
	assert_eq(
		_runtime.current_action(),
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)
	assert_eq(
		_runtime.action_state(),
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_ARMED_WINDUP
	)
	assert_almost_eq(_runtime.action_timer(), 0.0, 0.0)
	assert_almost_eq(_runtime.attack_cooldown_remaining(), 1.5, 0.0)
	assert_eq(_runtime.burst_shots_remaining(), 2)
	assert_false(_runtime.attack_hit_committed())
	assert_true(_runtime.collateral_player_hit_committed())
	assert_eq(_runtime.locked_direction(), Vector2.DOWN)
	assert_true(_runtime.armed_from_chain())
	assert_false(_runtime.has_exploded())


func _config() -> HANDLER_SCRIPT.Config:
	var config: HANDLER_SCRIPT.Config = HANDLER_SCRIPT.Config.new()
	config.explode_action_id = ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	config.windup = 0.4
	config.base_damage = 12.0
	config.element_id = ELEMENTS.ELEMENT_NEUTRAL
	config.radius = 60.0
	return config


func _arm_request(
	action_available: bool,
	from_chain: bool
) -> HANDLER_SCRIPT.ArmRequest:
	var request: HANDLER_SCRIPT.ArmRequest = HANDLER_SCRIPT.ArmRequest.new()
	request.action_available = action_available
	request.from_chain = from_chain
	return request


func _ports() -> HANDLER_SCRIPT.Ports:
	return HANDLER_SCRIPT.Ports.new(
		Callable(self, "_clear_focus"),
		Callable(self, "_stop_movement"),
		Callable(self, "_set_collision_enabled"),
		Callable(self, "_emit_windup"),
		Callable(self, "_refresh_visuals"),
		Callable(self, "_get_source_position"),
		Callable(self, "_emit_committed"),
		Callable(self, "_provide_direct_targets"),
		Callable(self, "_provide_enemy_targets"),
		Callable(self, "_has_line_of_sight"),
		Callable(self, "_finish_explosion")
	)


func _direct_target(
	target_id: String,
	position: Vector2,
	valid: bool = true
) -> HANDLER_SCRIPT.DirectTargetPort:
	_target_valid[target_id] = valid
	_target_positions[target_id] = position
	return HANDLER_SCRIPT.DirectTargetPort.new(
		Callable(self, "_target_is_valid").bind(target_id),
		Callable(self, "_target_position").bind(target_id),
		Callable(self, "_apply_damage").bind(target_id)
	)


func _enemy_target(
	target_id: String,
	position: Vector2,
	serial: int,
	is_source: bool = false,
	armed: bool = false,
	alive: bool = true,
	valid: bool = true
) -> HANDLER_SCRIPT.EnemyTargetPort:
	_target_valid[target_id] = valid
	_target_positions[target_id] = position
	_enemy_source[target_id] = is_source
	_enemy_armed[target_id] = armed
	_enemy_alive[target_id] = alive
	_enemy_serial[target_id] = serial
	return HANDLER_SCRIPT.EnemyTargetPort.new(
		Callable(self, "_target_is_valid").bind(target_id),
		Callable(self, "_target_is_source").bind(target_id),
		Callable(self, "_target_is_armed").bind(target_id),
		Callable(self, "_target_is_alive").bind(target_id),
		Callable(self, "_target_position").bind(target_id),
		Callable(self, "_target_spawn_serial").bind(target_id),
		Callable(self, "_apply_damage").bind(target_id)
	)


func _clear_focus() -> void:
	_events.append("clear_focus")


func _stop_movement() -> void:
	_events.append("stop_movement")


func _set_collision_enabled(enabled: bool) -> void:
	_events.append("collision:" + str(enabled).to_lower())


func _emit_windup(_duration: float) -> void:
	_events.append("windup")
	_windup_snapshot = _runtime_snapshot()


func _refresh_visuals() -> void:
	_events.append("refresh")


func _get_source_position() -> Vector2:
	return _source_position


func _emit_committed() -> void:
	_events.append("committed")
	_commit_snapshot = _runtime_snapshot()
	if _move_source_on_commit:
		_source_position = Vector2(100.0, 0.0)
	if _append_enemy_on_commit != null:
		_enemy_targets.append(_append_enemy_on_commit)


func _provide_direct_targets() -> Array[HANDLER_SCRIPT.DirectTargetPort]:
	_events.append("direct_targets")
	return _direct_targets


func _provide_enemy_targets() -> Array[HANDLER_SCRIPT.EnemyTargetPort]:
	_events.append("enemy_targets")
	return _enemy_targets


func _has_line_of_sight(
	from_position: Vector2,
	to_position: Vector2
) -> bool:
	_events.append(
		"los:%d:%d" % [int(from_position.x), int(to_position.x)]
	)
	return not bool(_blocked_position_x.get(int(to_position.x), false))


func _finish_explosion() -> void:
	_events.append("finished")
	_finish_snapshot = _runtime_snapshot()


func _target_is_valid(target_id: String) -> bool:
	return bool(_target_valid.get(target_id, false))


func _target_is_source(target_id: String) -> bool:
	return bool(_enemy_source.get(target_id, false))


func _target_is_armed(target_id: String) -> bool:
	return bool(_enemy_armed.get(target_id, false))


func _target_is_alive(target_id: String) -> bool:
	return bool(_enemy_alive.get(target_id, false))


func _target_position(target_id: String) -> Vector2:
	return _target_positions.get(target_id, Vector2.ZERO) as Vector2


func _target_spawn_serial(target_id: String) -> int:
	return int(_enemy_serial.get(target_id, 0))


func _apply_damage(
	base_damage: float,
	element_id: String,
	target_id: String
) -> HANDLER_SCRIPT.DamageResult:
	_events.append(target_id + ":damage")
	_damage_order.append(target_id)
	_damage_snapshots.append({
		"action_state": _runtime.action_state(),
		"armed": _runtime.is_armed(),
		"attack_hit": _runtime.attack_hit_committed(),
		"base_damage": base_damage,
		"element_id": element_id,
		"exploded": _runtime.has_exploded(),
		"target": target_id,
	})
	var result: HANDLER_SCRIPT.DamageResult = HANDLER_SCRIPT.DamageResult.new()
	result.applied = true
	result.amount = base_damage
	result.reason = "applied"
	return result


func _runtime_snapshot() -> Dictionary:
	return {
		"action_state": _runtime.action_state(),
		"action_timer": _runtime.action_timer(),
		"armed": _runtime.is_armed(),
		"armed_from_chain": _runtime.armed_from_chain(),
		"attack_hit": _runtime.attack_hit_committed(),
		"collateral_hit": _runtime.collateral_player_hit_committed(),
		"current_action": _runtime.current_action(),
		"exploded": _runtime.has_exploded(),
		"locked_direction": _runtime.locked_direction(),
	}
