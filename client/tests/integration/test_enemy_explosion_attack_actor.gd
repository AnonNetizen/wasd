extends SmokeHarness


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

var _event_order: Array[String] = []
var _source_windup_snapshot: Dictionary = {}
var _source_windup_context: Dictionary = {}
var _source_commit_snapshot: Dictionary = {}
var _source_commit_context: Dictionary = {}
var _source_defeat_event: Dictionary = {}
var _chain_windup_snapshot: Dictionary = {}
var _chain_defeat_event: Dictionary = {}
var _move_source_on_commit: bool = false
var _observed_target: Enemy = null
var _target_life_at_source_commit: float = -1.0


class DamageTarget:
	extends Node2D

	const TARGET_TEAM: String = "team_player"

	var life: float = 100.0
	var received_amounts: Array[float] = []


	func is_alive() -> bool:
		return life > 0.0


	func combat_team_id() -> String:
		return TARGET_TEAM


	func receive_damage(info: RefCounted) -> Dictionary:
		var amount: float = float(info.get("amount"))
		received_amounts.append(amount)
		life = maxf(life - amount, 0.0)
		return {
			"applied": true,
			"amount": amount,
			"defeated": life <= 0.0,
			"reason": "applied",
		}


class NavigationProbe:
	extends Node

	var line_of_sight_queries: Array[String] = []


	func has_terrain_line_of_sight(
		from_position: Vector2,
		target_position: Vector2
	) -> bool:
		line_of_sight_queries.append("%d:%d" % [
			roundi(from_position.x),
			roundi(target_position.x),
		])
		return true


func before_each() -> void:
	_event_order.clear()
	_source_windup_snapshot.clear()
	_source_windup_context.clear()
	_source_commit_snapshot.clear()
	_source_commit_context.clear()
	_source_defeat_event.clear()
	_chain_windup_snapshot.clear()
	_chain_defeat_event.clear()
	_move_source_on_commit = false
	_observed_target = null
	_target_life_at_source_commit = -1.0


func test_actor_explosion_uses_live_direct_and_frozen_enemy_origins() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var navigation := NavigationProbe.new()
	world.add_child(navigation)
	var player := DamageTarget.new()
	player.global_position = Vector2(300.0, 0.0)
	world.add_child(player)
	var victim: Enemy = _configured_enemy(
		world,
		"enemy_explosion_actor_victim",
		Vector2(100.0, 0.0),
		player,
		player,
		navigation,
		_approach_actions(),
		100.0
	)
	victim.set_runtime_spawn_serial(4)
	var source: Enemy = _configured_enemy(
		world,
		"enemy_explosion_actor_source",
		Vector2.ZERO,
		player,
		victim,
		navigation,
		_explosion_actions(0.2, 10.0, 120.0),
		100.0
	)
	source.set_runtime_spawn_serial(1)
	source.attack_windup_started.connect(_on_source_windup_started)
	source.attack_committed.connect(_on_source_attack_committed)
	source.defeated.connect(_on_source_defeated)
	_move_source_on_commit = true
	_observed_target = victim
	await get_tree().physics_frame

	assert_eq(source.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)
	source.velocity = Vector2(42.0, 0.0)
	assert_true(source.debug_arm_explosion_for_test(false))
	assert_eq(_event_order, ["source:windup"])
	assert_eq(_source_windup_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_eq(
		String(_source_windup_snapshot.get("current_action", "")),
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)
	assert_eq(
		String(_source_windup_snapshot.get("action_state", "")),
		"armed_windup"
	)
	assert_true(bool(_source_windup_snapshot.get("armed", false)))
	assert_false(bool(_source_windup_snapshot.get("has_exploded", true)))
	assert_almost_eq(
		float(_source_windup_snapshot.get("action_timer", 0.0)),
		0.2,
		0.0
	)
	assert_eq(source.velocity, Vector2.ZERO)
	assert_eq(_source_windup_context.get("owner"), source)
	assert_eq(_source_windup_context.get("world_position"), Vector2.ZERO)
	assert_false(bool(_source_windup_context.get("follow_owner", true)))
	assert_almost_eq(
		float(_source_windup_context.get("duration", 0.0)),
		0.2,
		0.0
	)
	assert_eq(
		_source_windup_context.get("scale"),
		Vector2.ONE * 120.0 / 36.0
	)
	await get_tree().physics_frame
	var collision_shape: CollisionShape2D = (
		source.get_node("CollisionShape2D") as CollisionShape2D
	)
	assert_true(collision_shape.disabled)

	assert_true(source.debug_advance_explosion_for_test(0.21))
	assert_eq(_event_order, [
		"source:windup",
		"source:committed",
		"source:defeated",
	])
	assert_eq(navigation.line_of_sight_queries, ["100:100", "0:100"])
	assert_almost_eq(_target_life_at_source_commit, 100.0, 0.0)
	assert_almost_eq(victim.current_life(), 80.0, 0.0)
	assert_true(player.received_amounts.is_empty())
	assert_eq(source.global_position, Vector2(100.0, 0.0))
	assert_true(bool(_source_commit_snapshot.get("armed", false)))
	assert_true(bool(_source_commit_snapshot.get("has_exploded", false)))
	assert_true(bool(_source_commit_snapshot.get(
		"attack_hit_committed",
		false
	)))
	assert_almost_eq(
		float(_source_commit_snapshot.get("life_points", 0.0)),
		100.0,
		0.0
	)
	assert_null(_source_commit_context.get("owner"))
	assert_eq(_source_commit_context.get("world_position"), Vector2.ZERO)
	assert_false(bool(_source_commit_context.get("follow_owner", true)))
	assert_almost_eq(
		float(_source_commit_context.get("duration", -1.0)),
		0.0,
		0.0
	)
	assert_eq(
		_source_commit_context.get("scale"),
		Vector2.ONE * 120.0 / 23.0
	)
	var finished_snapshot: Dictionary = source.snapshot()
	assert_eq(finished_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_almost_eq(
		float(finished_snapshot.get("life_points", -1.0)),
		0.0,
		0.0
	)
	assert_true(bool(finished_snapshot.get("armed", false)))
	assert_true(bool(finished_snapshot.get("has_exploded", false)))
	assert_eq(
		String(finished_snapshot.get("current_action", "")),
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)
	assert_eq(
		String(finished_snapshot.get("action_state", "")),
		"armed_windup"
	)
	_assert_exploder_defeat(_source_defeat_event)


func test_actor_lethal_enemy_explosion_arms_delayed_chain_generation() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var player := DamageTarget.new()
	player.global_position = Vector2(300.0, 0.0)
	world.add_child(player)
	var chain_target: Enemy = _configured_enemy(
		world,
		"enemy_explosion_actor_chain",
		Vector2(20.0, 0.0),
		player,
		player,
		null,
		_explosion_actions(0.35, 10.0, 60.0),
		100.0
	)
	chain_target.set_runtime_spawn_serial(2)
	var source: Enemy = _configured_enemy(
		world,
		"enemy_explosion_actor_chain_source",
		Vector2.ZERO,
		player,
		chain_target,
		null,
		_explosion_actions(0.1, 150.0, 60.0),
		100.0
	)
	source.set_runtime_spawn_serial(1)
	source.attack_windup_started.connect(_on_source_windup_started)
	source.attack_committed.connect(_on_source_attack_committed)
	source.defeated.connect(_on_source_defeated)
	chain_target.attack_windup_started.connect(_on_chain_windup_started)
	chain_target.attack_committed.connect(_on_chain_attack_committed)
	chain_target.defeated.connect(_on_chain_defeated)
	_observed_target = chain_target
	await get_tree().physics_frame

	assert_true(source.debug_arm_explosion_for_test(false))
	assert_true(source.debug_advance_explosion_for_test(0.11))
	assert_eq(_event_order, [
		"source:windup",
		"source:committed",
		"chain:windup",
		"source:defeated",
	])
	assert_almost_eq(_target_life_at_source_commit, 100.0, 0.0)
	var armed_snapshot: Dictionary = chain_target.snapshot()
	assert_eq(armed_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_almost_eq(
		float(armed_snapshot.get("life_points", -1.0)),
		0.0,
		0.0
	)
	assert_true(bool(armed_snapshot.get("armed", false)))
	assert_true(bool(armed_snapshot.get("armed_from_chain", false)))
	assert_false(bool(armed_snapshot.get("has_exploded", true)))
	assert_eq(
		String(armed_snapshot.get("current_action", "")),
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)
	assert_eq(
		String(armed_snapshot.get("action_state", "")),
		"armed_windup"
	)
	assert_almost_eq(
		float(armed_snapshot.get("action_timer", 0.0)),
		0.35,
		0.0
	)
	assert_eq(_chain_windup_snapshot, armed_snapshot)
	assert_true(chain_target.debug_advance_explosion_for_test(0.34))
	assert_eq(_event_order.size(), 4)
	assert_true(chain_target.debug_advance_explosion_for_test(0.011))
	assert_eq(_event_order, [
		"source:windup",
		"source:committed",
		"chain:windup",
		"source:defeated",
		"chain:committed",
		"chain:defeated",
	])
	var exploded_snapshot: Dictionary = chain_target.snapshot()
	assert_true(bool(exploded_snapshot.get("armed", false)))
	assert_true(bool(exploded_snapshot.get("armed_from_chain", false)))
	assert_true(bool(exploded_snapshot.get("has_exploded", false)))
	_assert_exploder_defeat(_chain_defeat_event)


func _configured_enemy(
	world: Node2D,
	enemy_id: String,
	position: Vector2,
	player: Node2D,
	primary: Node2D,
	navigation_provider: Node,
	actions: Array[Dictionary],
	max_life: float
) -> Enemy:
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	enemy.global_position = position
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.configure(
		_enemy_data(enemy_id, actions, max_life),
		player,
		navigation_provider,
		{
			"health_multiplier": 1.0,
			"damage_multiplier": 1.0,
		},
		{"primary_target": primary}
	)
	return enemy


func _enemy_data(
	enemy_id: String,
	actions: Array[Dictionary],
	max_life: float
) -> Dictionary:
	return {
		"id": enemy_id,
		"ai_profile_id": enemy_id + "_profile",
		"ai_profile": {
			"perception": {
				"memory_duration": 1.0,
				"path_awareness_radius": 100.0,
				"sight_radius": 300.0,
			},
			"decision_interval": 0.12,
			"targeting": {"player_weight": 1.0},
			"movement": {"orbit_radius": 0.0},
			"actions": actions,
		},
		"max_hp": max_life,
		"move_speed": 80.0,
		"hit_radius": 12.0,
		"separation_radius": 18.0,
	}


func _approach_actions() -> Array[Dictionary]:
	return [{
		"id": ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
		"base_score": 1.0,
		"speed_scale": 1.0,
	}]


func _explosion_actions(
	windup: float,
	damage: float,
	radius: float
) -> Array[Dictionary]:
	return [{
		"id": ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
		"base_score": 1.0,
		"speed_scale": 1.0,
		"attack": {
			"trigger_range": radius,
			"windup": windup,
			"damage": damage,
			"element_id": ELEMENTS.ELEMENT_NEUTRAL,
			"radius": radius,
		},
	}]


func _on_source_windup_started(
	enemy: Node,
	_action_id: String,
	context: Dictionary
) -> void:
	_event_order.append("source:windup")
	_source_windup_snapshot = enemy.call("snapshot") as Dictionary
	_source_windup_context = context.duplicate(true)


func _on_source_attack_committed(
	enemy: Node,
	_action_id: String,
	context: Dictionary
) -> void:
	_event_order.append("source:committed")
	if _observed_target != null and is_instance_valid(_observed_target):
		_target_life_at_source_commit = _observed_target.current_life()
	if _move_source_on_commit:
		(enemy as Node2D).global_position = Vector2(100.0, 0.0)
	_source_commit_snapshot = enemy.call("snapshot") as Dictionary
	_source_commit_context = context.duplicate(true)


func _on_source_defeated(
	_enemy: Node,
	_gold_reward: int,
	counts_as_kill: bool,
	drops_rewards: bool,
	cause_id: String
) -> void:
	_event_order.append("source:defeated")
	_source_defeat_event = {
		"counts_as_kill": counts_as_kill,
		"drops_rewards": drops_rewards,
		"cause_id": cause_id,
	}


func _on_chain_windup_started(
	enemy: Node,
	_action_id: String,
	_context: Dictionary
) -> void:
	_event_order.append("chain:windup")
	_chain_windup_snapshot = enemy.call("snapshot") as Dictionary


func _on_chain_attack_committed(
	_enemy: Node,
	_action_id: String,
	_context: Dictionary
) -> void:
	_event_order.append("chain:committed")


func _on_chain_defeated(
	_enemy: Node,
	_gold_reward: int,
	counts_as_kill: bool,
	drops_rewards: bool,
	cause_id: String
) -> void:
	_event_order.append("chain:defeated")
	_chain_defeat_event = {
		"counts_as_kill": counts_as_kill,
		"drops_rewards": drops_rewards,
		"cause_id": cause_id,
	}


func _assert_exploder_defeat(event: Dictionary) -> void:
	assert_false(bool(event.get("counts_as_kill", true)))
	assert_false(bool(event.get("drops_rewards", true)))
	assert_eq(
		String(event.get("cause_id", "")),
		ENEMY_DEFEAT_CAUSES.EXPLODER_DETONATION
	)
