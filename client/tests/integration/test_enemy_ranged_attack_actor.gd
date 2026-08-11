extends SmokeHarness


const BULLET_SCENE := preload("res://scenes/gameplay/bullet.tscn")
const ENEMY_BASE_SCENE := preload(
	"res://scenes/gameplay/actors/enemy_base.tscn"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")

const TEST_POOL_ID: String = POOL_IDS.BULLET_BASIC
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

var _commit_events: Array[Dictionary] = []
var _windup_events: Array[Dictionary] = []


func before_each() -> void:
	_commit_events.clear()
	_windup_events.clear()
	PoolManager.clear_all()
	assert_true(PoolManager.register_pool(
		TEST_POOL_ID,
		Callable(self, "_create_bullet"),
		8
	))


func after_each() -> void:
	PoolManager.clear_all()


func test_actor_burst_keeps_signal_and_runtime_commit_order() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var target := Node2D.new()
	target.name = "RangedTarget"
	target.global_position = Vector2(300.0, 40.0)
	world.add_child(target)
	var enemy: Enemy = _configured_enemy(world, target, 1.5)
	enemy.global_position = Vector2(100.0, 40.0)
	enemy.velocity = Vector2(80.0, -15.0)
	enemy.attack_windup_started.connect(_on_windup_started)
	enemy.attack_committed.connect(_on_attack_committed)
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)
	assert_true(enemy.debug_force_action_for_test(
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	))

	assert_true(enemy.debug_start_ranged_burst_for_test(Vector2(2.0, 0.0)))
	var windup_snapshot: Dictionary = enemy.snapshot()
	assert_eq(_windup_events.size(), 1)
	assert_eq(enemy.velocity, Vector2.ZERO)
	assert_eq(
		String(windup_snapshot.get("action_state", "")),
		"ranged_windup"
	)
	assert_eq(int(windup_snapshot.get("burst_shots_remaining", 0)), 2)
	assert_eq(
		windup_snapshot.get("locked_direction"),
		{"x": 1.0, "y": 0.0}
	)
	assert_eq(
		_windup_events[0],
		{
			"action_state": "ranged_windup",
			"burst_shots_remaining": 2,
			"duration": 0.32,
			"velocity": Vector2.ZERO,
		}
	)

	assert_true(enemy.debug_advance_ranged_attack_for_test(0.32))
	var first_shot_snapshot: Dictionary = enemy.snapshot()
	assert_eq(_commit_events.size(), 1)
	assert_eq(
		_commit_events[0],
		{
			"current_action": (
				ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
			),
			"action_state": "ranged_burst",
			"burst_shots_remaining": 2,
			"active_bullets": 1,
		}
	)
	assert_eq(
		String(first_shot_snapshot.get("action_state", "")),
		"ranged_burst"
	)
	assert_eq(
		int(first_shot_snapshot.get("burst_shots_remaining", 0)),
		1
	)
	assert_almost_eq(
		float(first_shot_snapshot.get("action_timer", 0.0)),
		0.12,
		0.0
	)

	assert_true(enemy.debug_advance_ranged_attack_for_test(0.12))
	assert_eq(_commit_events.size(), 2)
	assert_eq(
		_commit_events[1],
		{
			"current_action": (
				ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
			),
			"action_state": "ranged_burst",
			"burst_shots_remaining": 1,
			"active_bullets": 2,
		}
	)
	var finished_snapshot: Dictionary = enemy.snapshot()
	assert_eq(finished_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_eq(String(finished_snapshot.get("current_action", "")), "")
	assert_eq(String(finished_snapshot.get("action_state", "")), "")
	assert_eq(int(finished_snapshot.get("burst_shots_remaining", -1)), 0)
	assert_almost_eq(
		float(finished_snapshot.get("attack_cooldown_remaining", 0.0)),
		0.95,
		0.0
	)
	_assert_materialized_bullets(enemy, world, 2, 27.0)


func test_materialize_debug_seam_uses_current_actor_context_without_commit() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var target := Node2D.new()
	world.add_child(target)
	var enemy: Enemy = _configured_enemy(world, target, 1.25)
	enemy.global_position = Vector2(40.0, 18.0)
	enemy.attack_windup_started.connect(_on_windup_started)
	enemy.attack_committed.connect(_on_attack_committed)
	assert_false(enemy.debug_materialize_ranged_projectile_for_test(
		Vector2.RIGHT
	))
	assert_true(enemy.debug_force_action_for_test(
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	))
	assert_false(enemy.debug_materialize_ranged_projectile_for_test(
		Vector2.ZERO
	))
	assert_true(enemy.debug_materialize_ranged_projectile_for_test(
		Vector2(3.0, 0.0)
	))
	assert_true(_windup_events.is_empty())
	assert_true(_commit_events.is_empty())
	_assert_materialized_bullets(enemy, world, 1, 22.5)


func _configured_enemy(
	world: Node2D,
	target: Node2D,
	damage_multiplier: float
) -> Enemy:
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(enemy)
	enemy.configure(
		_enemy_data(),
		target,
		null,
		{
			"health_multiplier": 1.0,
			"damage_multiplier": damage_multiplier,
		}
	)
	return enemy


func _enemy_data() -> Dictionary:
	return {
		"id": "enemy_ranged_attack_actor",
		"ai_profile_id": "profile_ranged_attack_actor",
		"ai_profile": {
			"perception": {
				"memory_duration": 1.0,
				"path_awareness_radius": 300.0,
				"sight_radius": 600.0,
			},
			"decision_interval": 0.12,
			"targeting": {"player_weight": 1.0},
			"movement": {"orbit_radius": 120.0},
			"actions": [{
				"id": ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK,
				"base_score": 1.0,
				"speed_scale": 1.0,
				"attack": {
					"attack_range": 600.0,
					"keep_distance": 280.0,
					"windup": 0.32,
					"burst_count": 2,
					"shot_interval": 0.12,
					"cooldown": 0.95,
					"initial_cooldown": 0.0,
					"damage": 18.0,
					"element_id": ELEMENTS.ELEMENT_NEUTRAL,
					"projectile": {
						"pool_id": TEST_POOL_ID,
						"speed": 350.0,
						"range": 720.0,
						"hit_radius": 12.0,
						"lifetime": 2.1,
						"muzzle_distance": 24.0,
					},
				},
			}],
		},
		"max_hp": 100.0,
		"move_speed": 80.0,
		"hit_radius": 12.0,
		"separation_radius": 18.0,
	}


func _create_bullet() -> Node:
	return BULLET_SCENE.instantiate()


func _on_windup_started(
	enemy: Node,
	_action_id: String,
	context: Dictionary
) -> void:
	var snapshot_data: Dictionary = enemy.call("snapshot") as Dictionary
	var body: CharacterBody2D = enemy as CharacterBody2D
	_windup_events.append({
		"action_state": snapshot_data.get("action_state", ""),
		"burst_shots_remaining": snapshot_data.get(
			"burst_shots_remaining",
			0
		),
		"duration": context.get("duration", 0.0),
		"velocity": body.velocity if body != null else Vector2.INF,
	})


func _on_attack_committed(
	enemy: Node,
	_action_id: String,
	_context: Dictionary
) -> void:
	var snapshot_data: Dictionary = enemy.call("snapshot") as Dictionary
	_commit_events.append({
		"current_action": snapshot_data.get("current_action", ""),
		"action_state": snapshot_data.get("action_state", ""),
		"burst_shots_remaining": snapshot_data.get(
			"burst_shots_remaining",
			0
		),
		"active_bullets": PoolManager.active_count(TEST_POOL_ID),
	})


func _assert_materialized_bullets(
	enemy: Enemy,
	world: Node2D,
	expected_count: int,
	expected_damage: float
) -> void:
	assert_eq(PoolManager.active_count(TEST_POOL_ID), expected_count)
	var bullets: Array[Node] = get_tree().get_nodes_in_group(
		"active_bullets"
	)
	var matched: int = 0
	for bullet: Node in bullets:
		if bullet.get_parent() != world or not bullet.has_method("snapshot"):
			continue
		var snapshot_data: Dictionary = bullet.call("snapshot") as Dictionary
		if String(snapshot_data.get("source_team", "")) != "team_enemy":
			continue
		matched += 1
		assert_almost_eq(
			float(snapshot_data.get("damage", 0.0)),
			expected_damage,
			0.000_001
		)
		assert_eq(
			snapshot_data.get("damage_target_groups"),
			["active_projectile_blockers", "active_player"]
		)
		assert_almost_eq(
			(_dict_to_vector(snapshot_data.get("velocity", {}))).length(),
			350.0,
			0.000_001
		)
		assert_almost_eq(
			float(snapshot_data.get("max_range", 0.0)),
			720.0,
			0.0
		)
		assert_almost_eq(
			float(snapshot_data.get("hit_radius", 0.0)),
			12.0,
			0.0
		)
		assert_almost_eq(
			float(snapshot_data.get("remaining_life", 0.0)),
			2.1,
			0.0
		)
		assert_eq(
			_dict_to_vector(snapshot_data.get("position", {})),
			enemy.global_position + Vector2.RIGHT * 24.0
		)
	assert_eq(matched, expected_count)


func _dict_to_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if not value is Dictionary:
		return Vector2.ZERO
	var data: Dictionary = value as Dictionary
	return Vector2(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0))
	)
