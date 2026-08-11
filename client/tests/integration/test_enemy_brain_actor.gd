extends SmokeHarness


const ENEMY_BASE_SCENE := preload(
	"res://scenes/gameplay/actors/enemy_base.tscn"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
const ENEMY_NAVIGATION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_navigation_runtime.gd"
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

var _previous_game_state: StringName = &""
var _previous_game_context: Dictionary = {}


class FakeNavigationProvider:
	extends Node

	var actor: Enemy = null
	var calls: Array[String] = []
	var action_at_local_query: String = ""
	var focus_at_local_query: String = ""
	var corridor_open: bool = true

	func navigation_query_to_active_target(
		from_position: Vector2
	) -> Dictionary:
		calls.append("route")
		return {
			"reachable": true,
			"distance": 80.0,
			"next_position": from_position + Vector2.RIGHT,
		}

	func navigation_query(
		_from_position: Vector2,
		target_position: Vector2
	) -> Dictionary:
		calls.append("local")
		if actor != null and is_instance_valid(actor):
			var summary: Dictionary = actor.ai_debug_summary()
			action_at_local_query = String(summary.get("action", ""))
			focus_at_local_query = String(
				summary.get("focus_target", "")
			)
		return {
			"reachable": true,
			"distance": 20.0,
			"next_position": target_position,
		}

	func has_terrain_line_of_sight(
		_from_position: Vector2,
		_target_position: Vector2
	) -> bool:
		calls.append("los")
		return true

	func has_clear_corridor(
		_from_position: Vector2,
		_target_position: Vector2,
		_clearance: float
	) -> bool:
		calls.append("corridor")
		return corridor_open


func before_each() -> void:
	super()
	_previous_game_state = GameState.current()
	_previous_game_context = GameState.context()
	GameState.change_state(GameState.PLAYING)


func after_each() -> void:
	GameState.change_state(_previous_game_state, _previous_game_context)
	super()


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


func test_enemy_sense_keeps_route_los_corridor_order() -> void:
	var target := Node2D.new()
	target.name = "PrimaryTarget"
	target.global_position = Vector2(80.0, 0.0)
	add_child_autofree(target)
	var provider := FakeNavigationProvider.new()
	add_child_autofree(provider)
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	add_child_autofree(enemy)
	provider.actor = enemy
	enemy.configure(
		_enemy_data(
			"profile_sense_order",
			1.0,
			ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
		),
		target,
		provider
	)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_true(provider.calls.size() >= 3)
	assert_eq(provider.calls.slice(0, 3), ["route", "los", "corridor"])
	var summary: Dictionary = enemy.ai_debug_summary()
	assert_eq(
		summary.get("action"),
		ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
	)
	assert_eq(summary.get("focus_target"), "PrimaryTarget")
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)


func test_enemy_zero_player_weight_avoids_all_provider_calls() -> void:
	var target := Node2D.new()
	target.global_position = Vector2(80.0, 0.0)
	add_child_autofree(target)
	var provider := FakeNavigationProvider.new()
	add_child_autofree(provider)
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	add_child_autofree(enemy)
	enemy.configure(
		_enemy_data(
			"profile_zero_weight",
			0.0,
			ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
		),
		target,
		provider
	)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_true(provider.calls.is_empty())
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)


func test_event_primary_at_player_position_uses_local_route() -> void:
	var player := Node2D.new()
	player.name = "PlayerTarget"
	player.global_position = Vector2(80.0, 0.0)
	add_child_autofree(player)
	var event_primary := Node2D.new()
	event_primary.name = "DefenseTarget"
	event_primary.global_position = player.global_position
	add_child_autofree(event_primary)
	var provider := FakeNavigationProvider.new()
	provider.corridor_open = false
	add_child_autofree(provider)
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	add_child_autofree(enemy)
	enemy.configure(
		_enemy_data(
			"profile_event_identity",
			1.0,
			ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET
		),
		player,
		provider,
		{},
		{
			"event_instance_id": "event_identity",
			"primary_target": event_primary,
		}
	)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_true(provider.calls.size() >= 5)
	assert_eq(provider.calls.slice(0, 3), ["local", "los", "corridor"])
	assert_false(provider.calls.has("route"))
	assert_true(provider.calls.count("local") >= 2)
	var summary: Dictionary = enemy.ai_debug_summary()
	assert_eq(summary.get("primary_target"), "DefenseTarget")
	assert_eq(summary.get("focus_target"), "DefenseTarget")
	assert_eq(
		summary.get("navigation_mode"),
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_MODE_LOCAL_ASTAR
	)
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)


func test_enemy_commits_action_and_focus_before_waypoint_refresh() -> void:
	var target := Node2D.new()
	target.global_position = Vector2(80.0, 0.0)
	add_child_autofree(target)
	var provider := FakeNavigationProvider.new()
	provider.corridor_open = false
	add_child_autofree(provider)
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	add_child_autofree(enemy)
	provider.actor = enemy
	enemy.configure(
		_enemy_data(
			"profile_waypoint_order",
			0.0,
			ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME
		),
		target,
		provider
	)
	enemy.global_position = Vector2(20.0, 0.0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_false(provider.calls.is_empty())
	assert_eq(provider.calls.front(), "local")
	assert_eq(
		provider.action_at_local_query,
		ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME
	)
	assert_eq(provider.focus_at_local_query, "")
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)


func _enemy_data(
	profile_id: String,
	player_weight: float,
	action_id: String
) -> Dictionary:
	return {
		"id": "enemy_test",
		"ai_profile_id": profile_id,
		"ai_profile": {
			"perception": {
				"memory_duration": 1.0,
				"path_awareness_radius": 200.0,
				"sight_radius": 400.0,
			},
			"decision_interval": 0.12,
			"targeting": {"player_weight": player_weight},
			"movement": {"orbit_radius": 120.0},
			"actions": [{
				"id": action_id,
				"base_score": 1.0,
				"speed_scale": 1.0,
			}],
		},
		"max_hp": 100.0,
		"move_speed": 0.0,
		"hit_radius": 12.0,
		"separation_radius": 18.0,
	}
