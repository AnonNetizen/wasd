extends SmokeHarness


const ABILITY_TAGS := preload(
	"res://scripts/contracts/ability_tags.gd"
)
const DAMAGE_INFO_SCRIPT := preload(
	"res://scripts/combat/damage_info.gd"
)
const ENEMY_BASE_SCENE := preload(
	"res://scenes/gameplay/actors/enemy_base.tscn"
)
const ENEMY_AI_ACTIONS := preload(
	"res://scripts/contracts/enemy_ai_actions.gd"
)
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const STATUS_EFFECT_SCRIPT := preload(
	"res://scripts/combat/status_effect.gd"
)
const STATUS_EFFECTS := preload(
	"res://scripts/contracts/status_effects.gd"
)
const STATUS_STACK_RULES := preload(
	"res://scripts/contracts/status_stack_rules.gd"
)

const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"
const TEST_POOL_ID: String = POOL_IDS.ENEMY_CHASER
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


func before_each() -> void:
	PoolManager.clear_all()
	assert_true(PoolManager.register_pool(
		TEST_POOL_ID,
		Callable(self, "_create_enemy"),
		2
	))


func after_each() -> void:
	PoolManager.clear_all()


func test_actor_status_facade_roundtrips_through_public_pool_lifecycle() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var enemy: Enemy = _configured_enemy(target)
	assert_eq(enemy.snapshot().keys(), ENEMY_SNAPSHOT_KEYS)
	assert_true(enemy.add_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_PRIMARY
	))
	var apply_result: Dictionary = enemy.apply_status_effect(
		_silence_status(target)
	)
	assert_true(bool(apply_result.get("applied", false)))
	assert_eq(enemy.owned_tags(), [
		ABILITY_TAGS.ABILITY_TAG_PRIMARY,
		ABILITY_TAGS.ABILITY_TAG_SILENCED,
	])
	assert_eq(enemy.active_statuses(), [STATUS_EFFECTS.SILENCE])
	assert_eq(enemy.status_stack_count(STATUS_EFFECTS.SILENCE), 1)
	assert_eq(enemy.status_summary(), [{
		"id": STATUS_EFFECTS.SILENCE,
		"name_key": "status_silence_name",
		"stacks": 1,
		"remaining": 5.0,
	}])

	var escaped_snapshot: Dictionary = enemy.snapshot()
	assert_eq(escaped_snapshot.keys(), ENEMY_SNAPSHOT_KEYS)
	var escaped_counts: Dictionary = escaped_snapshot.get(
		"owned_tag_counts",
		{}
	) as Dictionary
	escaped_counts[ABILITY_TAGS.ABILITY_TAG_SILENCED] = 99
	var escaped_effects: Array = (
		escaped_snapshot.get("status_effects", {}) as Dictionary
	).get("effects", []) as Array
	assert_false(escaped_effects.is_empty())
	if not escaped_effects.is_empty():
		(escaped_effects[0] as Dictionary)["remaining"] = 0.0
	var saved_snapshot: Dictionary = enemy.snapshot()
	assert_eq(
		int((saved_snapshot.get(
			"owned_tag_counts",
			{}
		) as Dictionary).get(
			ABILITY_TAGS.ABILITY_TAG_SILENCED,
			0
		)),
		1
	)
	var saved_status_effects: Dictionary = saved_snapshot.get(
		"status_effects",
		{}
	) as Dictionary
	var saved_effects: Array = saved_status_effects.get(
		"effects",
		[]
	) as Array
	assert_false(saved_effects.is_empty())
	var saved_first_effect: Dictionary = {}
	if not saved_effects.is_empty():
		saved_first_effect = saved_effects[0] as Dictionary
	assert_almost_eq(
		float(saved_first_effect.get("remaining", 0.0)),
		5.0,
		0.0
	)

	assert_true(PoolManager.release(enemy))
	var reused: Enemy = PoolManager.acquire(TEST_POOL_ID) as Enemy
	assert_not_null(reused)
	assert_same(reused, enemy)
	reused.configure(_enemy_data(), target)
	reused.set_physics_process(false)
	assert_eq(reused.owned_tags(), [])
	assert_eq(reused.active_statuses(), [])
	reused.restore_snapshot(saved_snapshot)
	var roundtrip: Dictionary = reused.snapshot()
	assert_eq(roundtrip.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_eq(
		roundtrip.get("owned_tag_counts"),
		saved_snapshot.get("owned_tag_counts")
	)
	assert_eq(
		roundtrip.get("status_effects"),
		saved_snapshot.get("status_effects")
	)
	assert_true(reused.remove_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_false(reused.has_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_true(PoolManager.release(reused))


func test_actor_legacy_owned_tags_restore_to_counted_23_key_wire() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var enemy: Enemy = _configured_enemy(target)
	var legacy_snapshot: Dictionary = enemy.snapshot()
	legacy_snapshot.erase("owned_tag_counts")
	legacy_snapshot["owned_tags"] = [
		ABILITY_TAGS.ABILITY_TAG_SILENCED,
		ABILITY_TAGS.ABILITY_TAG_SILENCED,
		"ability_tag_unknown",
	]
	enemy.restore_snapshot(legacy_snapshot)

	var restored: Dictionary = enemy.snapshot()
	assert_eq(restored.keys(), ENEMY_SNAPSHOT_KEYS)
	assert_eq(restored.get("owned_tag_counts"), {
		ABILITY_TAGS.ABILITY_TAG_SILENCED: 2,
	})
	assert_true(enemy.remove_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_true(enemy.has_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_true(enemy.remove_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_false(enemy.has_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_true(PoolManager.release(enemy))


func test_actor_extracts_damage_source_team_before_status_forward() -> void:
	var target := Node2D.new()
	add_child_autofree(target)
	var enemy: Enemy = _configured_enemy(target)
	var result: Dictionary = enemy.apply_status_effect(
		_vulnerability_status(target)
	)
	assert_true(bool(result.get("applied", false)))

	var player_info: RefCounted = DAMAGE_INFO_SCRIPT.new()
	player_info.set("source_team", TEAM_PLAYER)
	var enemy_info: RefCounted = DAMAGE_INFO_SCRIPT.new()
	enemy_info.set("source_team", TEAM_ENEMY)
	assert_almost_eq(
		enemy.incoming_damage_multiplier(player_info),
		1.1,
		0.000_001
	)
	assert_almost_eq(
		enemy.incoming_damage_multiplier(enemy_info),
		1.0,
		0.0
	)
	assert_true(PoolManager.release(enemy))


func _create_enemy() -> Node:
	return ENEMY_BASE_SCENE.instantiate()


func _configured_enemy(target: Node2D) -> Enemy:
	var enemy: Enemy = PoolManager.acquire(TEST_POOL_ID) as Enemy
	assert_not_null(enemy)
	enemy.configure(_enemy_data(), target)
	enemy.set_physics_process(false)
	return enemy


func _enemy_data() -> Dictionary:
	return {
		"id": "enemy_status_host_actor",
		"ai_profile_id": "enemy_status_host_actor_profile",
		"ai_profile": {
			"perception": {
				"memory_duration": 1.0,
				"path_awareness_radius": 100.0,
				"sight_radius": 300.0,
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
		"move_speed": 0.0,
		"hit_radius": 12.0,
		"separation_radius": 18.0,
	}


func _silence_status(source: Node) -> Resource:
	return STATUS_EFFECT_SCRIPT.new().setup(
		STATUS_EFFECTS.SILENCE,
		{
			"duration": 5.0,
			"stack_rule": STATUS_STACK_RULES.REFRESH,
			"granted_ability_tags": [
				ABILITY_TAGS.ABILITY_TAG_SILENCED,
			],
		},
		source
	)


func _vulnerability_status(source: Node) -> Resource:
	return STATUS_EFFECT_SCRIPT.new().setup(
		STATUS_EFFECTS.VULNERABLE,
		{
			"duration": 5.0,
			"stack_rule": STATUS_STACK_RULES.ADD_STACK_REFRESH,
			"max_stacks": 5,
			"incoming_damage_per_stack": 0.1,
			"incoming_damage_source_team": TEAM_PLAYER,
		},
		source
	)
