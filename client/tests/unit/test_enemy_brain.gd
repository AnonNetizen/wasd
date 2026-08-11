extends SmokeHarness


const ENEMY_AI_ACTIONS := preload("res://scripts/contracts/enemy_ai_actions.gd")
const ENEMY_BRAIN_SCRIPT := preload("res://scripts/gameplay/enemy_brain.gd")


func test_perception_progresses_visible_path_memory_then_unaware() -> void:
	var brain: EnemyBrain = _configured_brain([
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 1.0),
	])
	var visible_input: EnemyBrain.SenseInput = _sense(
		Vector2(100.0, 0.0),
		true,
		true,
		100.0
	)
	var visible: EnemyBrain.Decision = brain.decide(visible_input, 0.0)

	assert_eq(brain.perception_state(), EnemyBrain.PERCEPTION_VISIBLE)
	assert_true(visible.focus_primary_target)
	assert_eq(visible.target_position, Vector2(100.0, 0.0))
	assert_almost_eq(brain.memory_remaining(), 2.0, 0.000_001)

	var path_input: EnemyBrain.SenseInput = _sense(
		Vector2(140.0, 0.0),
		false,
		true,
		180.0
	)
	var path_aware: EnemyBrain.Decision = brain.decide(path_input, 0.0)
	assert_eq(
		brain.perception_state(),
		EnemyBrain.PERCEPTION_PATH_AWARE
	)
	assert_true(path_aware.focus_primary_target)
	assert_eq(brain.last_known_position(), Vector2(140.0, 0.0))

	brain.advance_memory(0.5)
	var lost_input: EnemyBrain.SenseInput = _sense(
		Vector2(600.0, 0.0),
		false,
		false,
		INF
	)
	var remembered: EnemyBrain.Decision = brain.decide(lost_input, 0.0)
	assert_eq(brain.perception_state(), EnemyBrain.PERCEPTION_MEMORY)
	assert_false(remembered.focus_primary_target)
	assert_true(remembered.has_target_position)
	assert_eq(remembered.target_position, Vector2(140.0, 0.0))

	brain.advance_memory(2.0)
	var unaware: EnemyBrain.Decision = brain.decide(lost_input, 0.0)
	assert_eq(brain.perception_state(), EnemyBrain.PERCEPTION_UNAWARE)
	assert_false(brain.has_last_known_position())
	assert_false(unaware.focus_primary_target)
	assert_false(unaware.has_target_position)


func test_source_order_and_score_epsilon_preserve_first_action() -> void:
	var brain: EnemyBrain = _configured_brain([
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 1.0),
		_action(ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME, 1.0005),
	])
	var decision: EnemyBrain.Decision = brain.decide(
		_sense_without_target(),
		0.0
	)
	assert_eq(
		decision.action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
	)

	brain = _configured_brain([
		_action(ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME, 1.0),
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 1.0),
	])
	decision = brain.decide(_sense_without_target(), 0.0)
	assert_eq(decision.action_id, ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME)

	brain = _configured_brain([
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 1.0),
		_action(ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME, 1.002),
	])
	decision = brain.decide(_sense_without_target(), 0.0)
	assert_eq(decision.action_id, ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME)


func test_melee_explode_and_charge_respect_cooldown_but_ranged_does_not() -> void:
	var input: EnemyBrain.SenseInput = _sense(
		Vector2(20.0, 0.0),
		true,
		true,
		20.0,
		true
	)
	for action_id: String in [
		ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK,
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
		ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET,
	]:
		var brain: EnemyBrain = _configured_brain([
			_attack_action(action_id, 10.0, 100.0),
			_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 0.1),
		])
		assert_eq(
			brain.decide(input, 1.0).action_id,
			ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
			"%s must be gated while cooldown remains" % action_id
		)

	var ranged: EnemyBrain = _configured_brain([
		_attack_action(
			ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK,
			10.0,
			100.0
		),
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 0.1),
	])
	assert_eq(
		ranged.decide(input, 1.0).action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	)


func test_charge_requires_clear_corridor() -> void:
	var brain: EnemyBrain = _configured_brain([
		_attack_action(
			ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET,
			10.0,
			120.0
		),
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 0.1),
	])
	var blocked: EnemyBrain.SenseInput = _sense(
		Vector2(60.0, 0.0),
		true,
		true,
		60.0,
		false
	)
	assert_eq(
		brain.decide(blocked, 0.0).action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
	)

	blocked.has_clear_corridor = true
	assert_eq(
		brain.decide(blocked, 0.0).action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
	)


func test_ranged_requires_line_of_sight_and_attack_range() -> void:
	var brain: EnemyBrain = _configured_brain([
		_attack_action(
			ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK,
			10.0,
			100.0
		),
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 0.1),
	])
	var blocked: EnemyBrain.SenseInput = _sense(
		Vector2(60.0, 0.0),
		false,
		true,
		60.0
	)
	assert_eq(
		brain.decide(blocked, 0.0).action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
	)

	var out_of_range: EnemyBrain.SenseInput = _sense(
		Vector2(140.0, 0.0),
		true,
		true,
		140.0
	)
	assert_eq(
		brain.decide(out_of_range, 0.0).action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
	)

	var valid: EnemyBrain.SenseInput = _sense(
		Vector2(80.0, 0.0),
		true,
		true,
		80.0
	)
	assert_eq(
		brain.decide(valid, 0.0).action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	)


func test_approach_orbit_and_guard_return_typed_movement_intent() -> void:
	var approach: EnemyBrain = _configured_brain([
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 1.0),
	])
	var primary_position := Vector2(120.0, 40.0)
	var approach_decision: EnemyBrain.Decision = approach.decide(
		_sense(primary_position, true, true, primary_position.length()),
		0.0
	)
	assert_eq(
		approach_decision.action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
	)
	assert_true(approach_decision.focus_primary_target)
	assert_eq(approach_decision.target_position, primary_position)

	var orbit: EnemyBrain = _configured_brain([
		_action(ENEMY_AI_ACTIONS.AI_ACTION_ORBIT_TARGET, 2.0),
		_action(ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, 0.1),
	])
	assert_eq(
		orbit.decide(_sense(Vector2(160.0, 0.0)), 0.0).action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_ORBIT_TARGET
	)

	var guard: EnemyBrain = _configured_brain([
		_action(ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME, 1.0),
	])
	var guard_input: EnemyBrain.SenseInput = _sense_without_target()
	guard_input.self_position = Vector2(120.0, 0.0)
	guard_input.home_position = Vector2(10.0, 0.0)
	var guard_decision: EnemyBrain.Decision = guard.decide(
		guard_input,
		0.0
	)
	assert_eq(
		guard_decision.action_id,
		ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME
	)
	assert_false(guard_decision.focus_primary_target)
	assert_true(guard_decision.has_target_position)
	assert_eq(guard_decision.target_position, Vector2(10.0, 0.0))


func test_configure_reset_timers_and_outputs_do_not_alias_inputs() -> void:
	var source_profile: Dictionary = _profile([
		{
			"id": ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK,
			"base_score": 2.0,
			"speed_scale": 0.75,
			"attack": {
				"attack_range": 100.0,
				"initial_cooldown": 0.65,
			},
		},
	])
	var brain: EnemyBrain = ENEMY_BRAIN_SCRIPT.new()
	brain.configure("profile_original", source_profile)
	(source_profile["movement"] as Dictionary)["orbit_radius"] = 999.0
	var source_actions: Array = source_profile["actions"] as Array
	(source_actions[0] as Dictionary)["base_score"] = 99.0

	var action_copy: Dictionary = brain.action(
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	)
	action_copy["base_score"] = -1.0
	assert_eq(brain.profile_id(), "profile_original")
	assert_almost_eq(brain.movement_value("orbit_radius"), 160.0, 0.0)
	assert_almost_eq(
		float(
			brain.action(
				ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
			).get("base_score", 0.0)
		),
		2.0,
		0.0
	)
	assert_almost_eq(brain.initial_attack_cooldown(), 0.65, 0.0)
	assert_true(brain.is_decision_due())

	brain.decide(_sense(Vector2(40.0, 0.0)), 0.0)
	assert_false(brain.is_decision_due())
	brain.advance_decision(0.2)
	assert_true(brain.is_decision_due())
	brain.request_decision_now()
	assert_true(brain.is_decision_due())

	var state_copy: Dictionary = brain.debug_state()
	(state_copy["scores"] as Dictionary).clear()
	assert_false(brain.last_scores().is_empty())

	brain.reset()
	assert_eq(brain.profile_id(), "")
	assert_false(
		brain.has_action(ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK)
	)
	assert_eq(brain.perception_state(), EnemyBrain.PERCEPTION_UNAWARE)
	assert_false(brain.has_movement_target())


func test_brain_is_pure_ref_counted_without_runtime_service_access() -> void:
	var brain: EnemyBrain = ENEMY_BRAIN_SCRIPT.new()
	assert_true(brain is RefCounted)
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/gameplay/enemy_brain.gd"
	)
	for forbidden: String in [
		"extends Node",
		"Node2D",
		"GameClock",
		"RNG.",
		"get_tree(",
		"get_node(",
		"has_method(",
		".call(",
	]:
		assert_false(
			source.contains(forbidden),
			"EnemyBrain must not access %s" % forbidden
		)


func _configured_brain(actions: Array) -> EnemyBrain:
	var brain: EnemyBrain = ENEMY_BRAIN_SCRIPT.new()
	brain.configure("profile_test", _profile(actions))
	return brain


func _profile(actions: Array) -> Dictionary:
	return {
		"perception": {
			"sight_radius": 800.0,
			"path_awareness_radius": 300.0,
			"memory_duration": 2.0,
		},
		"decision_interval": 0.12,
		"targeting": {
			"player_weight": 1.0,
			"territory_radius": 50.0,
			"territory_weight": 2.0,
		},
		"movement": {"orbit_radius": 160.0},
		"actions": actions.duplicate(true),
	}


func _action(action_id: String, base_score: float) -> Dictionary:
	return {
		"id": action_id,
		"base_score": base_score,
		"speed_scale": 1.0,
	}


func _attack_action(
	action_id: String,
	base_score: float,
	attack_range: float
) -> Dictionary:
	var attack: Dictionary = {"trigger_range": attack_range}
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK:
		attack = {"attack_range": attack_range}
	return {
		"id": action_id,
		"base_score": base_score,
		"speed_scale": 1.0,
		"attack": attack,
	}


func _sense(
	target_position: Vector2,
	has_line_of_sight: bool = true,
	route_reachable: bool = true,
	path_distance: float = -1.0,
	has_clear_corridor: bool = true
) -> EnemyBrain.SenseInput:
	var input: EnemyBrain.SenseInput = EnemyBrain.SenseInput.new()
	input.self_position = Vector2.ZERO
	input.home_position = Vector2.ZERO
	input.target_available = true
	input.target_position = target_position
	input.direct_distance = input.self_position.distance_to(target_position)
	input.route_reachable = route_reachable
	input.path_distance = (
		input.direct_distance if path_distance < 0.0 else path_distance
	)
	input.has_line_of_sight = has_line_of_sight
	input.has_clear_corridor = has_clear_corridor
	return input


func _sense_without_target() -> EnemyBrain.SenseInput:
	var input: EnemyBrain.SenseInput = EnemyBrain.SenseInput.new()
	input.home_position = Vector2.ZERO
	return input
