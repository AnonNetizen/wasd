extends SmokeHarness


const DAMAGE_INFO_SCRIPT := preload(
	"res://scripts/combat/damage_info.gd"
)
const ENEMY_BASE_SCENE := preload(
	"res://scenes/gameplay/actors/enemy_base.tscn"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
const ENEMY_DEFEAT_CAUSES := preload(
	"res://scripts/contracts/enemy_defeat_causes.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")

const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"
const TEST_POOL_ID: String = POOL_IDS.ENEMY_CHASER
const PUBLIC_RESULT_KEYS: Array[String] = [
	"applied",
	"amount",
	"defeated",
	"reason",
]
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

var _events: Array[String] = []
var _observed_enemy: Enemy = null
var _defeat_event: Dictionary = {}
var _defeat_life: float = -1.0
var _defeat_feedback_active: bool = false
var _defeat_in_active_group: bool = true
var _combat_result: Dictionary = {}
var _combat_life: float = -1.0
var _combat_feedback_active: bool = false
var _windup_snapshot: Dictionary = {}
var _commit_snapshot: Dictionary = {}
var _combat_callback: Callable = Callable()


class CommittedExploder:
	extends Node


	func is_committed_exploder() -> bool:
		return true


func before_each() -> void:
	_events.clear()
	_observed_enemy = null
	_defeat_event.clear()
	_defeat_life = -1.0
	_defeat_feedback_active = false
	_defeat_in_active_group = true
	_combat_result.clear()
	_combat_life = -1.0
	_combat_feedback_active = false
	_windup_snapshot.clear()
	_commit_snapshot.clear()
	PoolManager.clear_all()
	assert_true(PoolManager.register_pool(
		TEST_POOL_ID,
		Callable(self, "_create_enemy"),
		4
	))
	_combat_callback = Callable(self, "_on_damage_applied")
	Combat.damage_applied.connect(_combat_callback)


func after_each() -> void:
	if Combat.damage_applied.is_connected(_combat_callback):
		Combat.damage_applied.disconnect(_combat_callback)
	PoolManager.clear_all()


func test_player_lethal_damage_orders_life_signal_presentation_and_pool() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var player := Node2D.new()
	world.add_child(player)
	var enemy: Enemy = _configured_enemy(
		player,
		_approach_actions(),
		40.0,
		17
	)
	_observe_enemy(enemy)
	assert_public_api(enemy, &"receive_damage")
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)

	var result: Dictionary = Combat.apply_damage(
		enemy,
		_damage_info(75.0, player, enemy, TEAM_PLAYER)
	)
	assert_eq(result.keys(), PUBLIC_RESULT_KEYS)
	assert_eq(result, {
		"applied": true,
		"amount": 40.0,
		"defeated": true,
		"reason": "applied",
	})
	assert_eq(_events, ["defeated", "combat"])
	assert_almost_eq(_defeat_life, 0.0, 0.0)
	assert_false(_defeat_feedback_active)
	assert_false(_defeat_in_active_group)
	assert_almost_eq(_combat_life, 0.0, 0.0)
	assert_true(_combat_feedback_active)
	assert_eq(_combat_result, result)
	assert_eq(_defeat_event, {
		"gold_reward": 17,
		"counts_as_kill": true,
		"drops_rewards": true,
		"cause_id": ENEMY_DEFEAT_CAUSES.PLAYER_DAMAGE,
	})
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)
	assert_almost_eq(enemy.current_life(), 0.0, 0.0)
	assert_true(enemy.is_defeat_feedback_active())
	assert_eq(PoolManager.active_count(TEST_POOL_ID), 1)
	assert_eq(PoolManager.available_count(TEST_POOL_ID), 0)

	var animation_player: AnimationPlayer = enemy.get_node(
		"Presentation/AnimationPlayer"
	) as AnimationPlayer
	assert_eq(animation_player.current_animation, &"defeat")
	animation_player.advance(1.0)
	assert_eq(PoolManager.active_count(TEST_POOL_ID), 0)
	assert_eq(PoolManager.available_count(TEST_POOL_ID), 1)
	assert_false(enemy.visible)
	assert_false(enemy.is_defeat_feedback_active())


func test_enemy_explosion_lethal_damage_arms_delayed_chain_at_zero_life() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var player := Node2D.new()
	player.global_position = Vector2(500.0, 0.0)
	world.add_child(player)
	var source := CommittedExploder.new()
	world.add_child(source)
	var enemy: Enemy = _configured_enemy(
		player,
		_explosion_actions(0.25),
		40.0,
		11
	)
	_observe_enemy(enemy)

	var result: Dictionary = Combat.apply_damage(
		enemy,
		_damage_info(50.0, source, enemy, TEAM_ENEMY)
	)
	assert_eq(result.keys(), PUBLIC_RESULT_KEYS)
	assert_eq(result, {
		"applied": true,
		"amount": 40.0,
		"defeated": false,
		"reason": "chain_armed",
	})
	assert_eq(_events, ["windup", "combat"])
	assert_true(_defeat_event.is_empty())
	assert_eq(_windup_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_almost_eq(
		float(_windup_snapshot.get("life_points", -1.0)),
		0.0,
		0.0
	)
	assert_true(bool(_windup_snapshot.get("armed", false)))
	assert_true(bool(_windup_snapshot.get("armed_from_chain", false)))
	assert_false(bool(_windup_snapshot.get("has_exploded", true)))
	assert_almost_eq(
		float(_windup_snapshot.get("action_timer", -1.0)),
		0.25,
		0.0
	)
	assert_almost_eq(enemy.current_life(), 0.0, 0.0)
	assert_true(enemy.is_armed())
	assert_false(enemy.is_defeat_feedback_active())
	assert_eq(PoolManager.active_count(TEST_POOL_ID), 1)
	assert_eq(PoolManager.available_count(TEST_POOL_ID), 0)
	assert_eq(_combat_result, result)


func test_zero_windup_chain_reenters_and_finishes_before_combat_signal() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var player := Node2D.new()
	player.global_position = Vector2(500.0, 0.0)
	world.add_child(player)
	var source := CommittedExploder.new()
	world.add_child(source)
	var enemy: Enemy = _configured_enemy(
		player,
		_explosion_actions(0.0),
		40.0,
		13
	)
	_observe_enemy(enemy)

	var result: Dictionary = Combat.apply_damage(
		enemy,
		_damage_info(50.0, source, enemy, TEAM_ENEMY)
	)
	assert_eq(result.keys(), PUBLIC_RESULT_KEYS)
	assert_eq(result, {
		"applied": true,
		"amount": 40.0,
		"defeated": false,
		"reason": "chain_armed",
	})
	assert_eq(_events, [
		"windup",
		"committed",
		"defeated",
		"combat",
	])
	assert_almost_eq(
		float(_windup_snapshot.get("life_points", -1.0)),
		0.0,
		0.0
	)
	assert_almost_eq(
		float(_commit_snapshot.get("life_points", -1.0)),
		0.0,
		0.0
	)
	assert_true(bool(_commit_snapshot.get("armed", false)))
	assert_true(bool(_commit_snapshot.get("has_exploded", false)))
	assert_almost_eq(_defeat_life, 0.0, 0.0)
	assert_eq(_defeat_event, {
		"gold_reward": 13,
		"counts_as_kill": false,
		"drops_rewards": false,
		"cause_id": ENEMY_DEFEAT_CAUSES.EXPLODER_DETONATION,
	})
	assert_eq(_combat_result, result)
	assert_true(enemy.is_defeat_feedback_active())
	assert_eq(PoolManager.active_count(TEST_POOL_ID), 1)


func _create_enemy() -> Node:
	return ENEMY_BASE_SCENE.instantiate()


func _configured_enemy(
	player: Node2D,
	actions: Array[Dictionary],
	max_life: float,
	gold_reward: int
) -> Enemy:
	var enemy: Enemy = PoolManager.acquire(TEST_POOL_ID) as Enemy
	assert_not_null(enemy)
	enemy.configure(
		_enemy_data(actions, max_life),
		player,
		null,
		{
			"health_multiplier": 1.0,
			"damage_multiplier": 1.0,
		},
		{
			"reward_snapshot": {
				"valid": true,
				"gold_reward": gold_reward,
			},
		}
	)
	enemy.set_physics_process(false)
	return enemy


func _enemy_data(
	actions: Array[Dictionary],
	max_life: float
) -> Dictionary:
	return {
		"id": "enemy_damage_actor",
		"ai_profile_id": "enemy_damage_actor_profile",
		"ai_profile": {
			"perception": {
				"memory_duration": 1.0,
				"path_awareness_radius": 100.0,
				"sight_radius": 300.0,
			},
			"decision_interval": 0.12,
			"targeting": {
				"player_weight": 1.0,
				"territory_radius": 0.0,
				"territory_weight": 0.0,
			},
			"movement": {"orbit_radius": 0.0},
			"actions": actions,
		},
		"max_hp": max_life,
		"move_speed": 80.0,
		"hit_radius": 12.0,
		"separation_radius": 8.0,
	}


func _approach_actions() -> Array[Dictionary]:
	return [{
		"id": ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
		"base_score": 1.0,
		"speed_scale": 1.0,
	}]


func _explosion_actions(windup: float) -> Array[Dictionary]:
	return [{
		"id": ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
		"base_score": 1.0,
		"speed_scale": 1.0,
		"attack": {
			"trigger_range": 60.0,
			"windup": windup,
			"damage": 10.0,
			"element_id": ELEMENTS.ELEMENT_NEUTRAL,
			"radius": 60.0,
		},
	}]


func _damage_info(
	amount: float,
	source: Node,
	target: Enemy,
	source_team: String
) -> RefCounted:
	return DAMAGE_INFO_SCRIPT.new().setup(
		amount,
		ELEMENTS.ELEMENT_NEUTRAL,
		source,
		target,
		source_team,
		TEAM_ENEMY
	)


func _observe_enemy(enemy: Enemy) -> void:
	_observed_enemy = enemy
	enemy.defeated.connect(_on_enemy_defeated)
	enemy.attack_windup_started.connect(_on_attack_windup_started)
	enemy.attack_committed.connect(_on_attack_committed)


func _on_enemy_defeated(
	enemy: Node,
	gold_reward: int,
	counts_as_kill: bool,
	drops_rewards: bool,
	cause_id: String
) -> void:
	if enemy != _observed_enemy:
		return
	_events.append("defeated")
	_defeat_life = _observed_enemy.current_life()
	_defeat_feedback_active = (
		_observed_enemy.is_defeat_feedback_active()
	)
	_defeat_in_active_group = _observed_enemy.is_in_group(
		"active_enemies"
	)
	_defeat_event = {
		"gold_reward": gold_reward,
		"counts_as_kill": counts_as_kill,
		"drops_rewards": drops_rewards,
		"cause_id": cause_id,
	}


func _on_attack_windup_started(
	enemy: Node,
	_action_id: String,
	_context: Dictionary
) -> void:
	if enemy != _observed_enemy:
		return
	_events.append("windup")
	_windup_snapshot = _observed_enemy.snapshot()


func _on_attack_committed(
	enemy: Node,
	_action_id: String,
	_context: Dictionary
) -> void:
	if enemy != _observed_enemy:
		return
	_events.append("committed")
	_commit_snapshot = _observed_enemy.snapshot()


func _on_damage_applied(
	target: Node,
	_info: RefCounted,
	result: Dictionary
) -> void:
	if target != _observed_enemy:
		return
	_events.append("combat")
	_combat_result = result.duplicate(true)
	_combat_life = _observed_enemy.current_life()
	_combat_feedback_active = (
		_observed_enemy.is_defeat_feedback_active()
	)
