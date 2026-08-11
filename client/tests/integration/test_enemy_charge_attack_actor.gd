extends SmokeHarness


const ENEMY_BASE_SCENE := preload(
	"res://scenes/gameplay/actors/enemy_base.tscn"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
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
var _windup_snapshot: Dictionary = {}
var _windup_context: Dictionary = {}
var _commit_snapshot: Dictionary = {}
var _commit_context: Dictionary = {}


class DamageTarget:
	extends Node2D

	const TARGET_TEAM: String = "team_player"

	var target_id: String = ""
	var life: float = 100.0
	var radius: float = 6.0
	var event_order: Array[String] = []
	var received_amounts: Array[float] = []
	var received_elements: Array[String] = []
	var knockbacks: Array[Dictionary] = []


	func configure(
		configured_id: String,
		shared_event_order: Array[String]
	) -> void:
		target_id = configured_id
		event_order = shared_event_order


	func is_alive() -> bool:
		return life > 0.0


	func hit_radius() -> float:
		return radius


	func combat_team_id() -> String:
		return TARGET_TEAM


	func receive_damage(info: RefCounted) -> Dictionary:
		var amount: float = float(info.get("amount"))
		event_order.append(target_id + ":damage")
		received_amounts.append(amount)
		received_elements.append(String(info.get("element_id")))
		life = maxf(life - amount, 0.0)
		return {
			"applied": true,
			"amount": amount,
			"defeated": life <= 0.0,
			"reason": "applied",
		}


	func apply_external_knockback(
		direction: Vector2,
		distance: float,
		duration: float
	) -> void:
		event_order.append(target_id + ":knockback")
		knockbacks.append({
			"direction": direction,
			"distance": distance,
			"duration": duration,
		})


func before_each() -> void:
	_event_order.clear()
	_windup_snapshot.clear()
	_windup_context.clear()
	_commit_snapshot.clear()
	_commit_context.clear()


func test_actor_charge_keeps_commit_before_movement_and_damage() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var player: DamageTarget = _damage_target(
		world,
		"player",
		Vector2(50.0, 0.0)
	)
	var enemy: Enemy = _configured_enemy(world, player, player, 1.5, false)
	enemy.attack_windup_started.connect(_on_windup_started)
	enemy.attack_committed.connect(_on_attack_committed)
	await get_tree().physics_frame
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)
	assert_true(enemy.debug_force_action_for_test(
		ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
	))

	assert_true(enemy.debug_start_charge_for_test())
	assert_eq(_event_order, ["windup"])
	assert_eq(_windup_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_eq(
		String(_windup_snapshot.get("action_state", "")),
		"charge_windup"
	)
	assert_almost_eq(
		float(_windup_snapshot.get("action_timer", 0.0)),
		0.2,
		0.0
	)
	assert_eq(_windup_context.get("scale"), Vector2(120.0, 18.0))
	assert_true(enemy.debug_advance_charge_for_test(0.21))
	assert_eq(_event_order, ["windup", "committed"])
	assert_eq(enemy.global_position, Vector2.ZERO)
	assert_eq(player.received_amounts, [])
	assert_eq(
		String(_commit_snapshot.get("action_state", "")),
		"charge_release"
	)
	assert_almost_eq(
		float(_commit_snapshot.get("action_timer", 0.0)),
		0.8,
		0.0
	)
	assert_false(bool(_commit_snapshot.get("attack_hit_committed", true)))

	assert_true(enemy.debug_advance_charge_for_test(0.5))
	assert_eq(_event_order, [
		"windup",
		"committed",
		"player:damage",
		"player:knockback",
	])
	assert_eq(player.received_amounts, [15.0])
	assert_eq(player.received_elements, [ELEMENTS.ELEMENT_NEUTRAL])
	assert_eq(player.knockbacks, [{
		"direction": Vector2.RIGHT,
		"distance": 24.0,
		"duration": 0.18,
	}])
	assert_eq(enemy.global_position, Vector2(50.0, 0.0))
	var release_snapshot: Dictionary = enemy.snapshot()
	assert_eq(release_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_true(bool(release_snapshot.get("attack_hit_committed", false)))
	assert_false(bool(release_snapshot.get(
		"collateral_player_hit_committed",
		true
	)))
	assert_eq(
		String(release_snapshot.get("action_state", "")),
		"charge_release"
	)
	assert_almost_eq(
		float(release_snapshot.get("action_timer", 0.0)),
		0.3,
		0.000_001
	)

	assert_true(enemy.debug_advance_charge_for_test(0.31))
	var finished_snapshot: Dictionary = enemy.snapshot()
	assert_eq(String(finished_snapshot.get("current_action", "")), "")
	assert_eq(String(finished_snapshot.get("action_state", "")), "")
	assert_almost_eq(
		float(finished_snapshot.get("attack_cooldown_remaining", 0.0)),
		0.9,
		0.0
	)
	assert_eq(player.received_amounts, [15.0])


func test_actor_charge_scans_primary_then_player_and_knocks_back_only_player() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var player: DamageTarget = _damage_target(
		world,
		"player",
		Vector2(44.0, 0.0)
	)
	var primary: DamageTarget = _damage_target(
		world,
		"primary",
		Vector2(60.0, 0.0)
	)
	var enemy: Enemy = _configured_enemy(world, player, primary, 1.0, true)
	enemy.attack_windup_started.connect(_on_windup_started)
	enemy.attack_committed.connect(_on_attack_committed)
	await get_tree().physics_frame
	assert_true(enemy.debug_force_action_for_test(
		ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
	))
	assert_true(enemy.debug_start_charge_for_test())
	assert_true(enemy.debug_advance_charge_for_test(0.21))
	assert_true(enemy.debug_advance_charge_for_test(0.7))
	assert_eq(_event_order, [
		"windup",
		"committed",
		"primary:damage",
		"player:damage",
		"player:knockback",
	])
	assert_eq(primary.received_amounts, [10.0])
	assert_eq(player.received_amounts, [10.0])
	assert_true(primary.knockbacks.is_empty())
	assert_eq(player.knockbacks, [{
		"direction": Vector2.RIGHT,
		"distance": 24.0,
		"duration": 0.18,
	}])
	var snapshot_data: Dictionary = enemy.snapshot()
	assert_eq(snapshot_data.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_true(bool(snapshot_data.get("attack_hit_committed", false)))
	assert_true(bool(snapshot_data.get(
		"collateral_player_hit_committed",
		false
	)))
	assert_eq(String(snapshot_data.get("current_action", "")), "")
	assert_eq(String(snapshot_data.get("action_state", "")), "")
	assert_almost_eq(
		float(snapshot_data.get("attack_cooldown_remaining", 0.0)),
		0.9,
		0.0
	)


func _damage_target(
	world: Node2D,
	target_id: String,
	position: Vector2
) -> DamageTarget:
	var target: DamageTarget = DamageTarget.new()
	target.configure(target_id, _event_order)
	target.global_position = position
	world.add_child(target)
	return target


func _configured_enemy(
	world: Node2D,
	player: Node2D,
	primary: Node2D,
	damage_multiplier: float,
	stop_on_hit: bool
) -> Enemy:
	var enemy: Enemy = ENEMY_BASE_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.configure(
		_enemy_data(stop_on_hit),
		player,
		null,
		{
			"health_multiplier": 1.0,
			"damage_multiplier": damage_multiplier,
		},
		{"primary_target": primary}
	)
	return enemy


func _enemy_data(stop_on_hit: bool) -> Dictionary:
	return {
		"id": "enemy_charge_attack_actor",
		"ai_profile_id": "profile_charge_attack_actor",
		"ai_profile": {
			"perception": {
				"memory_duration": 1.0,
				"path_awareness_radius": 100.0,
				"sight_radius": 300.0,
			},
			"decision_interval": 0.12,
			"targeting": {"player_weight": 1.0},
			"movement": {"orbit_radius": 0.0},
			"actions": [{
				"id": ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET,
				"base_score": 1.0,
				"speed_scale": 1.0,
				"attack": {
					"trigger_range": 120.0,
					"windup": 0.2,
					"release_duration": 0.8,
					"speed_multiplier": 1.0,
					"cooldown": 0.9,
					"damage": 10.0,
					"element_id": ELEMENTS.ELEMENT_NEUTRAL,
					"stop_on_hit": stop_on_hit,
					"knockback_distance": 24.0,
					"knockback_duration": 0.18,
				},
			}],
		},
		"max_hp": 100.0,
		"move_speed": 100.0,
		"hit_radius": 12.0,
		"separation_radius": 18.0,
	}


func _on_windup_started(
	enemy: Node,
	_action_id: String,
	context: Dictionary
) -> void:
	_event_order.append("windup")
	_windup_snapshot = enemy.call("snapshot") as Dictionary
	_windup_context = context.duplicate(true)


func _on_attack_committed(
	enemy: Node,
	_action_id: String,
	context: Dictionary
) -> void:
	_event_order.append("committed")
	_commit_snapshot = enemy.call("snapshot") as Dictionary
	_commit_context = context.duplicate(true)
