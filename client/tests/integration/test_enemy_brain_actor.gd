extends SmokeHarness


const ENEMY_BASE_SCENE := preload(
	"res://scenes/gameplay/actors/enemy_base.tscn"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
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


func test_enemy_configures_brain_without_changing_run_v19_snapshot_wire() -> void:
	var target := Node2D.new()
	target.name = "PrimaryTarget"
	add_child_autofree(target)
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(enemy)
	enemy.configure({
		"id": "enemy_test",
		"ai_profile_id": "profile_actor_bridge",
		"ai_profile": {
			"perception": {
				"sight_radius": 400.0,
				"path_awareness_radius": 200.0,
				"memory_duration": 1.0,
			},
			"decision_interval": 0.12,
			"targeting": {"player_weight": 1.0},
			"movement": {"orbit_radius": 120.0},
			"actions": [{
				"id": ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
				"base_score": 1.0,
				"speed_scale": 1.0,
			}],
		},
		"max_hp": 100.0,
		"move_speed": 80.0,
		"hit_radius": 12.0,
		"separation_radius": 18.0,
	}, target)

	var summary: Dictionary = enemy.ai_debug_summary()
	assert_eq(summary.get("profile_id"), "profile_actor_bridge")
	assert_eq(summary.get("primary_target"), "PrimaryTarget")
	assert_eq(
		summary.get("perception_state"),
		EnemyBrain.PERCEPTION_UNAWARE
	)
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)


func test_enemy_snapshot_restore_keeps_brain_state_transient() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(enemy)
	var enemy_data: Dictionary = {
		"id": "enemy_test",
		"ai_profile_id": "profile_restore_bridge",
		"ai_profile": {
			"perception": {
				"sight_radius": 400.0,
				"path_awareness_radius": 200.0,
				"memory_duration": 1.0,
			},
			"decision_interval": 0.12,
			"targeting": {"player_weight": 1.0},
			"movement": {"orbit_radius": 120.0},
			"actions": [{
				"id": ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
				"base_score": 1.0,
				"speed_scale": 1.0,
			}],
		},
		"max_hp": 100.0,
		"move_speed": 80.0,
		"hit_radius": 12.0,
		"separation_radius": 18.0,
	}
	enemy.configure(enemy_data, target)
	var snapshot_data: Dictionary = enemy.snapshot()
	snapshot_data["position"] = {"x": 32.0, "y": 48.0}
	snapshot_data["life_points"] = 75.0
	enemy.restore_snapshot(snapshot_data)

	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)
	assert_eq(enemy.global_position, Vector2(32.0, 48.0))
	assert_almost_eq(enemy.current_life(), 75.0, 0.0)
	assert_eq(
		enemy.ai_debug_summary().get("perception_state"),
		EnemyBrain.PERCEPTION_UNAWARE
	)
