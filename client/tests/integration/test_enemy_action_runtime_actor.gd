extends SmokeHarness


const ENEMY_BASE_SCENE := preload(
	"res://scenes/gameplay/actors/enemy_base.tscn"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")

const ENEMY_SNAPSHOT_KEYS: Array[String] = [
	"enemy_id",
	"position",
	"life_points",
	"spawn_health_multiplier",
	"spawn_damage_multiplier",
	"reward_snapshot",
	"home_position",
	"current_action",
	"action_state",
	"action_timer",
	"attack_cooldown_remaining",
	"attack_hit_committed",
	"collateral_player_hit_committed",
	"burst_shots_remaining",
	"locked_direction",
	"armed",
	"armed_from_chain",
	"has_exploded",
	"runtime_spawn_serial",
	"event_instance_id",
	"target_mode",
	"owned_tag_counts",
	"status_effects",
]

var _windup_events: Array[Dictionary] = []


func test_enemy_snapshot_wire_and_pool_lifecycle_reset_action_state() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var enemy: Enemy = _configured_enemy(target)
	var initial_snapshot: Dictionary = enemy.snapshot()
	assert_eq(initial_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_almost_eq(
		float(initial_snapshot.get("attack_cooldown_remaining", 0.0)),
		0.65,
		0.0
	)
	assert_false(enemy.debug_force_action_for_test("corrupt_action"))
	assert_eq(String(enemy.snapshot().get("current_action", "")), "")
	assert_true(
		enemy.debug_force_action_for_test(
			ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
		)
	)

	var active_snapshot: Dictionary = enemy.snapshot()
	active_snapshot["action_state"] = "ranged_windup"
	active_snapshot["action_timer"] = 0.17
	active_snapshot["attack_cooldown_remaining"] = 0.2
	active_snapshot["attack_hit_committed"] = true
	active_snapshot["collateral_player_hit_committed"] = true
	active_snapshot["burst_shots_remaining"] = 4
	active_snapshot["locked_direction"] = {"x": -1.0, "y": 0.0}
	active_snapshot["armed"] = false
	active_snapshot["armed_from_chain"] = false
	active_snapshot["has_exploded"] = false
	enemy.restore_snapshot(active_snapshot)
	assert_eq(
		String(enemy.snapshot().get("current_action", "")),
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	)

	enemy.call("_pool_release")
	_assert_default_action_snapshot(enemy.snapshot())
	enemy.call("_pool_reset")
	enemy.configure(_enemy_data(), target)
	var reused_snapshot: Dictionary = enemy.snapshot()
	_assert_default_action_snapshot(
		reused_snapshot,
		0.65
	)
	assert_eq(reused_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)


func test_ranged_and_armed_restore_emit_once_after_state_commit() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var enemy: Enemy = _configured_enemy(target)
	enemy.attack_windup_started.connect(_on_attack_windup_started)

	enemy.velocity = Vector2(90.0, 15.0)
	var ranged_snapshot: Dictionary = enemy.snapshot()
	ranged_snapshot["current_action"] = (
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	)
	ranged_snapshot["action_state"] = "ranged_windup"
	ranged_snapshot["action_timer"] = 0.17
	ranged_snapshot["attack_cooldown_remaining"] = 0.0
	ranged_snapshot["burst_shots_remaining"] = 4
	ranged_snapshot["locked_direction"] = {"x": -2.0, "y": 0.0}
	ranged_snapshot["armed"] = false
	ranged_snapshot["armed_from_chain"] = false
	ranged_snapshot["has_exploded"] = false
	enemy.restore_snapshot(ranged_snapshot)

	assert_eq(_windup_events.size(), 1)
	var ranged_event: Dictionary = _windup_events[0]
	assert_eq(
		String(ranged_event.get("action_id", "")),
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	)
	assert_eq(String(ranged_event.get("snapshot_action", "")), (
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	))
	assert_eq(
		String(ranged_event.get("snapshot_state", "")),
		"ranged_windup"
	)
	assert_almost_eq(
		float(ranged_event.get("snapshot_timer", 0.0)),
		0.17,
		0.0
	)
	assert_eq(ranged_event.get("velocity"), Vector2.ZERO)
	assert_false(bool(ranged_event.get("collision_disabled", true)))
	assert_almost_eq(
		float(
			(ranged_event.get("context", {}) as Dictionary).get(
				"duration",
				0.0
			)
		),
		0.17,
		0.0
	)
	assert_eq(
		enemy.snapshot().get("locked_direction"),
		{"x": -1.0, "y": 0.0}
	)

	target.global_position = enemy.global_position + Vector2.RIGHT * 120.0
	enemy.configure(_enemy_data(), target)
	var visual: Node2D = enemy.get_node_or_null("Visual") as Node2D
	assert_not_null(visual)
	if visual != null:
		assert_gt(visual.scale.x, 0.0)

	_windup_events.clear()
	enemy.velocity = Vector2(45.0, -20.0)
	var burst_snapshot: Dictionary = enemy.snapshot()
	burst_snapshot["current_action"] = (
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	)
	burst_snapshot["action_state"] = "ranged_burst"
	burst_snapshot["action_timer"] = 0.07
	burst_snapshot["burst_shots_remaining"] = 2
	burst_snapshot["locked_direction"] = {"x": -3.0, "y": 0.0}
	enemy.restore_snapshot(burst_snapshot)
	assert_eq(_windup_events.size(), 0)
	assert_eq(enemy.velocity, Vector2.ZERO)
	assert_eq(
		enemy.snapshot().get("locked_direction"),
		{"x": -1.0, "y": 0.0}
	)
	if visual != null:
		assert_lt(visual.scale.x, 0.0)

	_windup_events.clear()
	var armed_snapshot: Dictionary = enemy.snapshot()
	armed_snapshot["current_action"] = (
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)
	armed_snapshot["action_state"] = "armed_windup"
	armed_snapshot["action_timer"] = 0.22
	armed_snapshot["burst_shots_remaining"] = 0
	armed_snapshot["locked_direction"] = {"x": 0.0, "y": 0.0}
	armed_snapshot["armed"] = true
	armed_snapshot["armed_from_chain"] = true
	armed_snapshot["has_exploded"] = false
	enemy.restore_snapshot(armed_snapshot)

	assert_eq(_windup_events.size(), 1)
	var armed_event: Dictionary = _windup_events[0]
	assert_eq(
		String(armed_event.get("action_id", "")),
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)
	assert_eq(String(armed_event.get("snapshot_action", "")), (
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	))
	assert_eq(
		String(armed_event.get("snapshot_state", "")),
		"armed_windup"
	)
	assert_almost_eq(
		float(armed_event.get("snapshot_timer", 0.0)),
		0.22,
		0.0
	)
	assert_true(bool(armed_event.get("collision_disabled", false)))
	assert_almost_eq(
		float(
			(armed_event.get("context", {}) as Dictionary).get(
				"duration",
				0.0
			)
		),
		0.22,
		0.0
	)


func _configured_enemy(target: Node2D) -> Enemy:
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(enemy)
	enemy.configure(_enemy_data(), target)
	return enemy


func _enemy_data() -> Dictionary:
	return {
		"id": "enemy_action_runtime_actor",
		"ai_profile_id": "profile_action_runtime_actor",
		"ai_profile": {
			"perception": {
				"sight_radius": 600.0,
				"path_awareness_radius": 300.0,
				"memory_duration": 1.0,
			},
			"decision_interval": 0.12,
			"targeting": {"player_weight": 1.0},
			"movement": {"orbit_radius": 120.0},
			"actions": [
				{
					"id": ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK,
					"base_score": 1.0,
					"speed_scale": 1.0,
					"attack": {
						"attack_range": 600.0,
						"keep_distance": 280.0,
						"windup": 0.32,
						"burst_count": 4,
						"shot_interval": 0.12,
						"cooldown": 0.95,
						"initial_cooldown": 0.65,
						"damage": 18.0,
						"element_id": ELEMENTS.ELEMENT_NEUTRAL,
						"projectile": {
							"pool_id": POOL_IDS.BULLET_BASIC,
							"speed": 350.0,
							"range": 720.0,
							"hit_radius": 12.0,
							"lifetime": 2.1,
							"muzzle_distance": 24.0,
						},
					},
				},
				{
					"id": ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
					"base_score": 0.5,
					"speed_scale": 1.0,
					"attack": {
						"trigger_range": 72.0,
						"windup": 0.4,
						"damage": 36.0,
						"element_id": ELEMENTS.ELEMENT_NEUTRAL,
						"radius": 96.0,
					},
				},
			],
		},
		"max_hp": 100.0,
		"move_speed": 80.0,
		"hit_radius": 12.0,
		"separation_radius": 18.0,
	}


func _on_attack_windup_started(
	enemy: Node,
	action_id: String,
	context: Dictionary
) -> void:
	var snapshot_data: Dictionary = enemy.call("snapshot") as Dictionary
	var body: CharacterBody2D = enemy as CharacterBody2D
	var collision_shape: CollisionShape2D = enemy.get_node_or_null(
		"CollisionShape2D"
	) as CollisionShape2D
	_windup_events.append({
		"action_id": action_id,
		"snapshot_action": snapshot_data.get("current_action", ""),
		"snapshot_state": snapshot_data.get("action_state", ""),
		"snapshot_timer": snapshot_data.get("action_timer", 0.0),
		"velocity": body.velocity if body != null else Vector2.INF,
		"collision_disabled": (
			collision_shape.disabled if collision_shape != null else false
		),
		"context": context.duplicate(true),
	})


func _assert_default_action_snapshot(
	snapshot_data: Dictionary,
	expected_cooldown: float = 0.0
) -> void:
	assert_eq(String(snapshot_data.get("current_action", "")), "")
	assert_eq(String(snapshot_data.get("action_state", "")), "")
	assert_almost_eq(
		float(snapshot_data.get("action_timer", -1.0)),
		0.0,
		0.0
	)
	assert_almost_eq(
		float(snapshot_data.get("attack_cooldown_remaining", -1.0)),
		expected_cooldown,
		0.0
	)
	assert_false(bool(snapshot_data.get("attack_hit_committed", true)))
	assert_false(bool(
		snapshot_data.get("collateral_player_hit_committed", true)
	))
	assert_eq(int(snapshot_data.get("burst_shots_remaining", -1)), 0)
	assert_eq(
		snapshot_data.get("locked_direction"),
		{"x": 0.0, "y": 0.0}
	)
	assert_false(bool(snapshot_data.get("armed", true)))
	assert_false(bool(snapshot_data.get("armed_from_chain", true)))
	assert_false(bool(snapshot_data.get("has_exploded", true)))
