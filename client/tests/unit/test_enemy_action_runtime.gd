extends SmokeHarness


const ENEMY_ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)

const ACTION_EXPLODE: String = "ai_action_explode_target"
const ACTION_MELEE: String = "ai_action_melee_attack"
const ACTION_RANGED: String = "ai_action_ranged_attack"


func test_defaults_reset_and_initial_ranged_cooldown() -> void:
	var runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
		ENEMY_ACTION_RUNTIME_SCRIPT.new()
	)
	_assert_default_values(runtime.snapshot_values())

	runtime.configure(0.65)
	assert_almost_eq(runtime.attack_cooldown_remaining(), 0.65, 0.0)
	runtime.set_current_action(ACTION_MELEE)
	runtime.set_action_state(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	)
	runtime.set_action_timer(0.4)
	runtime.set_attack_hit_committed(true)
	runtime.set_collateral_player_hit_committed(true)
	runtime.set_burst_shots_remaining(3)
	runtime.set_locked_direction(Vector2(3.0, 4.0))
	runtime.set_armed(true)
	runtime.set_armed_from_chain(true)
	runtime.set_has_exploded(true)
	runtime.reset()

	_assert_default_values(runtime.snapshot_values())


func test_timer_and_cooldown_advance_clamp_at_zero() -> void:
	var runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
		ENEMY_ACTION_RUNTIME_SCRIPT.new()
	)
	runtime.configure(0.6)
	runtime.set_action_timer(0.5)

	runtime.advance_action_timer(0.2)
	runtime.advance_attack_cooldown(0.2)
	assert_almost_eq(runtime.action_timer(), 0.3, 0.000_001)
	assert_almost_eq(
		runtime.attack_cooldown_remaining(),
		0.4,
		0.000_001
	)

	runtime.advance_action_timer(-1.0)
	runtime.advance_attack_cooldown(-1.0)
	assert_almost_eq(runtime.action_timer(), 0.3, 0.000_001)
	assert_almost_eq(
		runtime.attack_cooldown_remaining(),
		0.4,
		0.000_001
	)

	runtime.advance_action_timer(1.0)
	runtime.advance_attack_cooldown(1.0)
	assert_almost_eq(runtime.action_timer(), 0.0, 0.0)
	assert_almost_eq(runtime.attack_cooldown_remaining(), 0.0, 0.0)


func test_snapshot_restore_roundtrip_has_no_input_or_output_alias() -> void:
	var runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
		ENEMY_ACTION_RUNTIME_SCRIPT.new()
	)
	var input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = (
		ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput.new()
	)
	input.current_action = ACTION_MELEE
	input.action_state = (
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	)
	input.action_timer = 0.25
	input.attack_cooldown_remaining = 0.75
	input.attack_hit_committed = true
	input.collateral_player_hit_committed = true
	input.burst_shots_remaining = 0
	input.locked_direction = Vector2(2.0, -3.0)
	input.armed = false
	input.armed_from_chain = true
	input.has_exploded = true
	input.has_saved_burst_state = true
	var rules: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreRules = (
		_rules([ACTION_MELEE])
	)

	runtime.restore(input, rules)
	var values: ENEMY_ACTION_RUNTIME_SCRIPT.SnapshotValues = (
		runtime.snapshot_values()
	)
	assert_eq(values.current_action, ACTION_MELEE)
	assert_eq(
		values.action_state,
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	)
	assert_almost_eq(values.action_timer, 0.25, 0.0)
	assert_almost_eq(values.attack_cooldown_remaining, 0.75, 0.0)
	assert_true(values.attack_hit_committed)
	assert_true(values.collateral_player_hit_committed)
	assert_eq(values.burst_shots_remaining, 0)
	assert_eq(values.locked_direction, Vector2(2.0, -3.0))
	assert_false(values.armed)
	assert_true(values.armed_from_chain)
	assert_true(values.has_exploded)

	input.current_action = "mutated_input"
	input.locked_direction = Vector2.ZERO
	values.current_action = "mutated_output"
	values.locked_direction = Vector2.ONE
	assert_eq(runtime.current_action(), ACTION_MELEE)
	assert_eq(runtime.locked_direction(), Vector2(2.0, -3.0))


func test_invalid_action_clears_phase_and_timer() -> void:
	var runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
		ENEMY_ACTION_RUNTIME_SCRIPT.new()
	)
	var input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = (
		ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput.new()
	)
	input.current_action = "corrupt_action"
	input.action_state = (
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	)
	input.action_timer = 0.4
	input.attack_cooldown_remaining = 0.2
	input.attack_hit_committed = true
	input.has_saved_burst_state = true

	runtime.restore(input, _rules([ACTION_MELEE]))
	var values: ENEMY_ACTION_RUNTIME_SCRIPT.SnapshotValues = (
		runtime.snapshot_values()
	)
	assert_eq(values.current_action, "")
	assert_eq(values.action_state, "")
	assert_almost_eq(values.action_timer, 0.0, 0.0)
	assert_almost_eq(values.attack_cooldown_remaining, 0.2, 0.0)
	assert_true(values.attack_hit_committed)


func test_valid_ranged_windup_and_burst_restore_exact_values() -> void:
	var runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
		ENEMY_ACTION_RUNTIME_SCRIPT.new()
	)
	var input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = _ranged_input(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP,
		0.17,
		4,
		Vector2(-2.0, 0.0)
	)
	var result: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreResult = runtime.restore(
		input,
		_rules([ACTION_RANGED])
	)
	assert_true(result.restored_ranged_state)
	assert_true(result.resume_ranged_windup)
	assert_eq(runtime.current_action(), ACTION_RANGED)
	assert_eq(
		runtime.action_state(),
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP
	)
	assert_almost_eq(runtime.action_timer(), 0.17, 0.0)
	assert_eq(runtime.burst_shots_remaining(), 4)
	assert_eq(runtime.locked_direction(), Vector2.LEFT)

	input = _ranged_input(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST,
		0.07,
		2,
		Vector2(0.0, 3.0)
	)
	result = runtime.restore(input, _rules([ACTION_RANGED]))
	assert_true(result.restored_ranged_state)
	assert_false(result.resume_ranged_windup)
	assert_eq(
		runtime.action_state(),
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST
	)
	assert_almost_eq(runtime.action_timer(), 0.07, 0.0)
	assert_eq(runtime.burst_shots_remaining(), 2)
	assert_eq(runtime.locked_direction(), Vector2.DOWN)


func test_legacy_ranged_snapshot_clears_without_cooldown() -> void:
	var runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
		ENEMY_ACTION_RUNTIME_SCRIPT.new()
	)
	var input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = _ranged_input(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP,
		0.17,
		0,
		Vector2.LEFT
	)
	input.has_saved_burst_state = false
	runtime.restore(input, _rules([ACTION_RANGED]))

	_assert_cleared_ranged(runtime, 0.0)


func test_invalid_ranged_action_phase_count_direction_and_timer_cooldown() -> void:
	var cases: Array[ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput] = []
	var invalid_action: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = (
		_ranged_input(
			ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST,
		0.08,
		5,
		Vector2.LEFT
		)
	)
	invalid_action.current_action = "corrupt_ranged_action"
	cases.append(invalid_action)
	cases.append(_ranged_input("corrupt_phase", 0.08, 4, Vector2.LEFT))
	cases.append(_ranged_input(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST,
		0.08,
		4,
		Vector2.LEFT
	))
	cases.append(_ranged_input(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP,
		0.08,
		4,
		Vector2.ZERO
	))
	var invalid_timer: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = (
		_ranged_input(
			ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP,
		0.0,
		4,
		Vector2.LEFT
		)
	)
	invalid_timer.has_valid_saved_action_timer = false
	cases.append(invalid_timer)

	for input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput in cases:
		var runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
			ENEMY_ACTION_RUNTIME_SCRIPT.new()
		)
		runtime.restore(input, _rules([ACTION_RANGED]))
		_assert_cleared_ranged(runtime, 0.95)


func test_armed_restore_is_pure_state_and_does_not_emit() -> void:
	var runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
		ENEMY_ACTION_RUNTIME_SCRIPT.new()
	)
	var input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = (
		ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput.new()
	)
	input.current_action = ACTION_EXPLODE
	input.action_state = (
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_ARMED_WINDUP
	)
	input.action_timer = 0.22
	input.armed = true
	input.armed_from_chain = true
	input.has_saved_burst_state = true
	var result: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreResult = runtime.restore(
		input,
		_rules([ACTION_EXPLODE])
	)

	assert_false(result.resume_ranged_windup)
	assert_false(result.restored_ranged_state)
	assert_true(runtime.is_armed())
	assert_true(runtime.armed_from_chain())
	assert_false(runtime.has_signal("attack_windup_started"))
	runtime.force_armed_restore(ACTION_EXPLODE)
	assert_eq(runtime.current_action(), ACTION_EXPLODE)
	assert_eq(
		runtime.action_state(),
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_ARMED_WINDUP
	)
	assert_almost_eq(runtime.action_timer(), 0.22, 0.0)


func _rules(
	valid_action_ids: Array[String]
) -> ENEMY_ACTION_RUNTIME_SCRIPT.RestoreRules:
	var rules: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreRules = (
		ENEMY_ACTION_RUNTIME_SCRIPT.RestoreRules.new()
	)
	rules.valid_action_ids = valid_action_ids.duplicate()
	rules.explode_action_id = ACTION_EXPLODE
	rules.ranged_action_id = ACTION_RANGED
	rules.ranged_burst_count = 4
	rules.ranged_windup = 0.32
	rules.ranged_shot_interval = 0.12
	rules.ranged_cooldown = 0.95
	return rules


func _ranged_input(
	state: String,
	timer: float,
	remaining: int,
	direction: Vector2
) -> ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput:
	var input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = (
		ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput.new()
	)
	input.current_action = ACTION_RANGED
	input.action_state = state
	input.action_timer = timer
	input.attack_cooldown_remaining = 0.0
	input.burst_shots_remaining = remaining
	input.locked_direction = direction
	input.has_saved_burst_state = true
	input.has_valid_saved_action_timer = true
	return input


func _assert_default_values(
	values: ENEMY_ACTION_RUNTIME_SCRIPT.SnapshotValues
) -> void:
	assert_eq(values.current_action, "")
	assert_eq(values.action_state, "")
	assert_almost_eq(values.action_timer, 0.0, 0.0)
	assert_almost_eq(values.attack_cooldown_remaining, 0.0, 0.0)
	assert_false(values.attack_hit_committed)
	assert_false(values.collateral_player_hit_committed)
	assert_eq(values.burst_shots_remaining, 0)
	assert_eq(values.locked_direction, Vector2.ZERO)
	assert_false(values.armed)
	assert_false(values.armed_from_chain)
	assert_false(values.has_exploded)


func _assert_cleared_ranged(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	expected_cooldown: float
) -> void:
	assert_eq(runtime.current_action(), "")
	assert_eq(runtime.action_state(), "")
	assert_almost_eq(runtime.action_timer(), 0.0, 0.0)
	assert_eq(runtime.burst_shots_remaining(), 0)
	assert_eq(runtime.locked_direction(), Vector2.ZERO)
	assert_almost_eq(
		runtime.attack_cooldown_remaining(),
		expected_cooldown,
		0.000_001
	)
