extends SmokeHarness


const ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)
const HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_ranged_attack_handler.gd"
)
const MATERIALIZER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_projectile_materializer.gd"
)

const ACTION_RANGED: String = "ai_action_ranged_attack"

var _commit_snapshots: Array[Dictionary] = []
var _events: Array[String] = []
var _materialize_ok: bool = true
var _materialize_reason: String = ""
var _runtime: ACTION_RUNTIME_SCRIPT = ACTION_RUNTIME_SCRIPT.new()


func before_each() -> void:
	_commit_snapshots.clear()
	_events.clear()
	_materialize_ok = true
	_materialize_reason = ""
	_runtime.reset()


func test_start_and_timer_boundary_commit_one_scheduled_shot() -> void:
	_runtime.set_current_action(ACTION_RANGED)
	var config: HANDLER_SCRIPT.Config = _config()
	var started: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start_burst(
		_runtime,
		config,
		Vector2(2.0, 0.0),
		_ports()
	)
	assert_true(started.handled)
	assert_true(started.started)
	assert_true(started.windup_started)
	assert_false(started.burst_started)
	assert_eq(_runtime.locked_direction(), Vector2.RIGHT)
	assert_eq(_runtime.burst_shots_remaining(), 4)
	assert_eq(
		_runtime.action_state(),
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP
	)
	assert_almost_eq(_runtime.action_timer(), 0.32, 0.0)
	assert_eq(_events, ["stop_and_face", "windup"])

	var before_due: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		0.319,
		_ports()
	)
	assert_true(before_due.handled)
	assert_false(before_due.scheduled_shot_committed)
	assert_almost_eq(_runtime.action_timer(), 0.001, 0.000_001)
	assert_eq(_events, ["stop_and_face", "windup"])

	var due: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		0.0011,
		_ports()
	)
	assert_true(due.handled)
	assert_true(due.burst_started)
	assert_true(due.scheduled_shot_committed)
	assert_true(due.projectile_materialized)
	assert_eq(due.projectile_reason, "")
	assert_eq(
		_runtime.action_state(),
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST
	)
	assert_eq(_runtime.burst_shots_remaining(), 3)
	assert_almost_eq(_runtime.action_timer(), 0.12, 0.0)
	assert_eq(_events, [
		"stop_and_face",
		"windup",
		"materialize",
		"committed",
	])
	assert_eq(_commit_snapshots.size(), 1)
	if _commit_snapshots.size() == 1:
		assert_eq(
			_commit_snapshots[0],
			{
				"current_action": ACTION_RANGED,
				"action_state": (
					ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST
				),
				"burst_shots_remaining": 4,
			}
		)


func test_pool_and_configure_failure_still_commit_and_advance_schedule() -> void:
	_runtime.set_current_action(ACTION_RANGED)
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST
	)
	_runtime.set_action_timer(0.0)
	_runtime.set_burst_shots_remaining(2)
	_runtime.set_locked_direction(Vector2.RIGHT)
	var config: HANDLER_SCRIPT.Config = _config()

	_materialize_ok = false
	_materialize_reason = MATERIALIZER_SCRIPT.REASON_POOL_UNAVAILABLE
	var pool_failure: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		0.0,
		_ports()
	)
	assert_true(pool_failure.scheduled_shot_committed)
	assert_false(pool_failure.projectile_materialized)
	assert_eq(
		pool_failure.projectile_reason,
		MATERIALIZER_SCRIPT.REASON_POOL_UNAVAILABLE
	)
	assert_eq(_runtime.burst_shots_remaining(), 1)
	assert_almost_eq(_runtime.action_timer(), 0.12, 0.0)
	assert_eq(_runtime.current_action(), ACTION_RANGED)
	assert_eq(_events, ["materialize", "committed"])
	assert_eq(
		_commit_snapshots[0].get("burst_shots_remaining"),
		2
	)

	_materialize_reason = MATERIALIZER_SCRIPT.REASON_CONFIGURE_FAILED
	var configure_failure: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.advance(
		_runtime,
		config,
		0.12,
		_ports()
	)
	assert_true(configure_failure.scheduled_shot_committed)
	assert_false(configure_failure.projectile_materialized)
	assert_eq(
		configure_failure.projectile_reason,
		MATERIALIZER_SCRIPT.REASON_CONFIGURE_FAILED
	)
	assert_true(configure_failure.finished)
	assert_eq(_events, [
		"materialize",
		"committed",
		"materialize",
		"committed",
		"finished",
	])
	assert_eq(_commit_snapshots.size(), 2)
	assert_eq(
		_commit_snapshots[1],
		{
			"current_action": ACTION_RANGED,
			"action_state": (
				ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST
			),
			"burst_shots_remaining": 1,
		}
	)
	assert_eq(_runtime.current_action(), "")
	assert_eq(_runtime.action_state(), "")
	assert_eq(_runtime.burst_shots_remaining(), 0)
	assert_almost_eq(_runtime.action_timer(), 0.0, 0.0)
	assert_almost_eq(_runtime.attack_cooldown_remaining(), 0.95, 0.0)


func test_zero_windup_commits_immediately_before_decrement() -> void:
	_runtime.set_current_action(ACTION_RANGED)
	var config: HANDLER_SCRIPT.Config = _config()
	config.windup = 0.0
	config.burst_count = 2
	var result: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start_burst(
		_runtime,
		config,
		Vector2.RIGHT,
		_ports()
	)
	assert_true(result.started)
	assert_true(result.windup_started)
	assert_true(result.burst_started)
	assert_true(result.scheduled_shot_committed)
	assert_eq(_events, [
		"stop_and_face",
		"windup",
		"materialize",
		"committed",
	])
	assert_eq(
		_commit_snapshots[0].get("burst_shots_remaining"),
		2
	)
	assert_eq(_runtime.burst_shots_remaining(), 1)
	assert_almost_eq(_runtime.action_timer(), 0.12, 0.0)


func test_invalid_direction_and_empty_burst_keep_legacy_finish_rules() -> void:
	_runtime.set_current_action(ACTION_RANGED)
	var config: HANDLER_SCRIPT.Config = _config()
	var invalid_direction: HANDLER_SCRIPT.Result = (
		HANDLER_SCRIPT.start_burst(
			_runtime,
			config,
			Vector2.ZERO,
			_ports()
		)
	)
	assert_true(invalid_direction.handled)
	assert_false(invalid_direction.started)
	assert_eq(
		invalid_direction.reason,
		HANDLER_SCRIPT.REASON_INVALID_DIRECTION
	)
	assert_eq(_runtime.current_action(), ACTION_RANGED)
	assert_eq(_runtime.locked_direction(), Vector2.ZERO)
	assert_true(_events.is_empty())

	config.burst_count = 0
	var empty_burst: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.start_burst(
		_runtime,
		config,
		Vector2(4.0, 0.0),
		_ports()
	)
	assert_true(empty_burst.handled)
	assert_false(empty_burst.started)
	assert_true(empty_burst.finished)
	assert_eq(_events, ["finished"])
	assert_eq(_runtime.current_action(), "")
	assert_eq(_runtime.action_state(), "")
	assert_eq(_runtime.burst_shots_remaining(), 0)
	assert_eq(_runtime.locked_direction(), Vector2.RIGHT)
	assert_almost_eq(_runtime.attack_cooldown_remaining(), 0.95, 0.0)


func test_non_ranged_state_is_not_handled_or_advanced() -> void:
	_runtime.set_current_action("ai_action_melee_attack")
	_runtime.set_action_state(
		ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
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


func _config() -> HANDLER_SCRIPT.Config:
	var config: HANDLER_SCRIPT.Config = HANDLER_SCRIPT.Config.new()
	config.windup = 0.32
	config.burst_count = 4
	config.shot_interval = 0.12
	config.cooldown = 0.95
	config.projectile.pool_id = "bullet_basic"
	config.projectile.damage = 18.0
	config.projectile.speed = 350.0
	config.projectile.max_range = 720.0
	config.projectile.damage_target_groups = ["active_player"]
	return config


func _ports() -> HANDLER_SCRIPT.Ports:
	return HANDLER_SCRIPT.Ports.new(
		Callable(self, "_stop_and_face"),
		Callable(self, "_emit_windup"),
		Callable(self, "_materialize"),
		Callable(self, "_emit_committed"),
		Callable(self, "_finish")
	)


func _stop_and_face(_direction: Vector2) -> void:
	_events.append("stop_and_face")


func _emit_windup(_duration: float) -> void:
	_events.append("windup")


func _materialize(
	_projectile: MATERIALIZER_SCRIPT.Spec,
	_direction: Vector2
) -> MATERIALIZER_SCRIPT.Result:
	_events.append("materialize")
	var result: MATERIALIZER_SCRIPT.Result = MATERIALIZER_SCRIPT.Result.new()
	result.ok = _materialize_ok
	result.reason = _materialize_reason
	return result


func _emit_committed() -> void:
	_events.append("committed")
	var values: ACTION_RUNTIME_SCRIPT.SnapshotValues = (
		_runtime.snapshot_values()
	)
	_commit_snapshots.append({
		"current_action": values.current_action,
		"action_state": values.action_state,
		"burst_shots_remaining": values.burst_shots_remaining,
	})


func _finish() -> void:
	_events.append("finished")
