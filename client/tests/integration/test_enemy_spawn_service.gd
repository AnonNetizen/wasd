extends SmokeHarness


const ENEMY_SPAWN_SERVICE_SCRIPT := preload(
	"res://scripts/gameplay/enemy_spawn_service.gd"
)

var _acquire_node: Node = null
var _acquire_calls: int = 0
var _release_calls: int = 0
var _reward_calls: int = 0
var _position_calls: int = 0
var _armed_restore_events: int = 0
var _reward_result: Dictionary = {
	"valid": true,
	"gold_reward": 4,
}
var _pool_host: Node = null


func before_each() -> void:
	super()
	_acquire_node = null
	_acquire_calls = 0
	_release_calls = 0
	_reward_calls = 0
	_position_calls = 0
	_armed_restore_events = 0
	_reward_result = {
		"valid": true,
		"gold_reward": 4,
	}
	_pool_host = Node.new()
	add_child_autofree(_pool_host)


func test_pool_failure_does_not_consume_reward_position_or_serial() -> void:
	var fixture: Dictionary = _new_service_fixture()
	var service: ENEMY_SPAWN_SERVICE_SCRIPT = (
		fixture["service"] as ENEMY_SPAWN_SERVICE_SCRIPT
	)

	var result: Dictionary = service.spawn_fresh({
		"enemy_data": _enemy_data(),
		"wave_key": "wave_pool_failure",
		"position_provider": Callable(self, "_provide_position"),
		"normal_rewards": true,
	})

	assert_false(bool(result.get("ok", true)))
	assert_eq(String(result.get("reason", "")), "pool_unavailable")
	assert_eq(_acquire_calls, 1)
	assert_eq(_reward_calls, 0)
	assert_eq(_position_calls, 0)
	assert_eq(service.next_spawn_serial(), 1)


func test_reward_failure_releases_before_random_position_and_serial() -> void:
	var fixture: Dictionary = _new_service_fixture()
	var service: ENEMY_SPAWN_SERVICE_SCRIPT = (
		fixture["service"] as ENEMY_SPAWN_SERVICE_SCRIPT
	)
	var enemy: FakeEnemy = _new_enemy()
	_acquire_node = enemy
	_reward_result.clear()

	var result: Dictionary = service.spawn_fresh({
		"enemy_data": _enemy_data(),
		"wave_key": "wave_reward_failure",
		"position_provider": Callable(self, "_provide_position"),
		"normal_rewards": true,
	})

	assert_false(bool(result.get("ok", true)))
	assert_eq(String(result.get("reason", "")), "reward_unavailable")
	assert_eq(_reward_calls, 1)
	assert_eq(_release_calls, 1)
	assert_eq(_position_calls, 0)
	assert_eq(service.next_spawn_serial(), 1)


func test_reused_enemy_clears_stale_module_metadata() -> void:
	var fixture: Dictionary = _new_service_fixture()
	var service: ENEMY_SPAWN_SERVICE_SCRIPT = (
		fixture["service"] as ENEMY_SPAWN_SERVICE_SCRIPT
	)
	var active_world: Node2D = fixture["active_world"] as Node2D
	var enemy: FakeEnemy = _new_enemy()
	_acquire_node = enemy

	var first_result: Dictionary = service.spawn_fresh({
		"enemy_data": _enemy_data(),
		"wave_key": "module_wave_a",
		"module_slot": "3,4",
		"world_position": Vector2(120.0, 80.0),
		"normal_rewards": false,
	})
	assert_true(bool(first_result.get("ok", false)))
	assert_eq(enemy.get_parent(), active_world)
	assert_eq(String(enemy.get_meta("module_slot", "")), "3,4")
	assert_eq(enemy.runtime_spawn_serial, 1)

	enemy.reparent(_pool_host, true)
	var second_result: Dictionary = service.spawn_fresh({
		"enemy_data": _enemy_data(),
		"wave_key": "open_wave_b",
		"world_position": Vector2(200.0, 40.0),
		"normal_rewards": false,
	})

	assert_true(bool(second_result.get("ok", false)))
	assert_eq(String(enemy.get_meta("wave_key", "")), "open_wave_b")
	assert_false(enemy.has_meta("module_slot"))
	assert_eq(enemy.runtime_spawn_serial, 2)
	assert_eq(enemy.global_position, Vector2(200.0, 40.0))
	assert_eq(service.next_spawn_serial(), 3)


func test_world_event_fresh_spawn_keeps_frozen_context_and_difficulty() -> void:
	var fixture: Dictionary = _new_service_fixture()
	var service: ENEMY_SPAWN_SERVICE_SCRIPT = (
		fixture["service"] as ENEMY_SPAWN_SERVICE_SCRIPT
	)
	var enemy: FakeEnemy = _new_enemy()
	_acquire_node = enemy
	var fixed_difficulty: Dictionary = {
		"health_multiplier": 1.75,
		"damage_multiplier": 1.25,
	}

	var result: Dictionary = service.spawn_fresh({
		"enemy_data": _enemy_data(),
		"wave_key": "world_event_evt_01_0",
		"module_slot": "5,2",
		"world_position": Vector2(480.0, 320.0),
		"spawn_context": {
			"event_instance_id": "evt_01",
			"reward_specialization_multiplier": 1.5,
		},
		"fixed_spawn_difficulty": fixed_difficulty,
		"normal_rewards": true,
	})

	assert_true(bool(result.get("ok", false)))
	assert_eq(_reward_calls, 1)
	assert_eq(
		String(enemy.configured_context.get("event_instance_id", "")),
		"evt_01"
	)
	assert_eq(
		enemy.configured_context.get("reward_snapshot", {}),
		_reward_result
	)
	assert_eq(enemy.configured_difficulty, fixed_difficulty)
	assert_eq(String(enemy.get_meta("module_slot", "")), "5,2")


func test_debug_pre_lifecycle_hook_stays_between_serial_and_bounds() -> void:
	var fixture: Dictionary = _new_service_fixture()
	var service: ENEMY_SPAWN_SERVICE_SCRIPT = (
		fixture["service"] as ENEMY_SPAWN_SERVICE_SCRIPT
	)
	var enemy: FakeEnemy = _new_enemy()
	_acquire_node = enemy

	var result: Dictionary = service.spawn_fresh({
		"enemy_data": _enemy_data(),
		"wave_key": "debug_test_arena_stationary",
		"world_position": Vector2(120.0, 40.0),
		"normal_rewards": false,
		"use_default_navigation": false,
		"fixed_spawn_difficulty": {
			"health_multiplier": 1.0,
			"damage_multiplier": 1.0,
		},
		"pre_lifecycle_hook": Callable(
			self,
			"_configure_pre_lifecycle"
		),
	})

	assert_true(bool(result.get("ok", false)))
	assert_true(bool(enemy.get_meta("pre_lifecycle_configured", false)))
	assert_eq(enemy.call_order, [
		"configure",
		"serial",
		"pre_lifecycle",
		"bounds",
		"lifecycle",
	])


func test_restore_connects_feedback_after_bounds_and_before_armed_state() -> void:
	var fixture: Dictionary = _new_service_fixture()
	var service: ENEMY_SPAWN_SERVICE_SCRIPT = (
		fixture["service"] as ENEMY_SPAWN_SERVICE_SCRIPT
	)
	var enemy: FakeEnemy = _new_enemy()
	_acquire_node = enemy
	service.reset_spawn_serial(5)

	var result: Dictionary = service.restore_enemy({
		"enemy_data": _enemy_data(),
		"wave_key": "world_event_evt_02_1",
		"module_slot": "6,3",
		"world_position": Vector2(640.0, 160.0),
		"spawn_context": {
			"event_instance_id": "evt_02",
			"reward_snapshot": {
				"valid": true,
				"gold_reward": 9,
			},
		},
		"fixed_spawn_difficulty": {
			"health_multiplier": 2.0,
			"damage_multiplier": 1.4,
		},
		"runtime_spawn_serial": 12,
		"snapshot": {
			"armed": true,
			"runtime_spawn_serial": 12,
		},
	})

	assert_true(bool(result.get("ok", false)))
	assert_eq(_armed_restore_events, 1)
	assert_eq(service.next_spawn_serial(), 13)
	assert_eq(enemy.runtime_spawn_serial, 12)
	assert_eq(enemy.call_order, [
		"configure",
		"serial",
		"bounds",
		"lifecycle",
		"restore",
	])


func _new_service_fixture() -> Dictionary:
	var active_world := Node2D.new()
	add_child_autofree(active_world)
	var player := Node2D.new()
	add_child_autofree(player)
	var service: ENEMY_SPAWN_SERVICE_SCRIPT = (
		ENEMY_SPAWN_SERVICE_SCRIPT.new()
	)
	add_child_autofree(service)
	assert_true(service.configure(
		active_world,
		player,
		Callable(self, "_navigation_provider"),
		Callable(self, "_difficulty_provider"),
		Callable(self, "_resolve_reward"),
		Callable(self, "_apply_bounds"),
		Callable(self, "_connect_lifecycle"),
		Callable(self, "_acquire_enemy"),
		Callable(self, "_release_enemy")
	))
	return {
		"active_world": active_world,
		"service": service,
	}


func _new_enemy() -> FakeEnemy:
	var enemy := FakeEnemy.new()
	_pool_host.add_child(enemy)
	return enemy


func _enemy_data() -> Dictionary:
	return {
		"id": "enemy_fixture",
		"pool_id": "enemy_fixture_pool",
	}


func _acquire_enemy(_pool_id: String) -> Node:
	_acquire_calls += 1
	return _acquire_node


func _release_enemy(_enemy: Node) -> bool:
	_release_calls += 1
	return true


func _navigation_provider() -> Node:
	return null


func _difficulty_provider() -> Dictionary:
	return {
		"health_multiplier": 1.1,
		"damage_multiplier": 1.2,
	}


func _resolve_reward(
	_enemy_data: Dictionary,
	_spawn_context: Dictionary
) -> Dictionary:
	_reward_calls += 1
	return _reward_result.duplicate(true)


func _provide_position() -> Vector2:
	_position_calls += 1
	return Vector2(320.0, 240.0)


func _apply_bounds(enemy: Node2D) -> void:
	(enemy as FakeEnemy).call_order.append("bounds")


func _configure_pre_lifecycle(enemy: Node2D) -> void:
	var fake_enemy: FakeEnemy = enemy as FakeEnemy
	fake_enemy.call_order.append("pre_lifecycle")
	fake_enemy.set_meta("pre_lifecycle_configured", true)


func _connect_lifecycle(enemy: Node2D, _wave_key: String) -> void:
	var fake_enemy: FakeEnemy = enemy as FakeEnemy
	fake_enemy.call_order.append("lifecycle")
	var callback := Callable(self, "_on_armed_restored")
	if not fake_enemy.armed_restored.is_connected(callback):
		fake_enemy.armed_restored.connect(callback)


func _on_armed_restored() -> void:
	_armed_restore_events += 1


class FakeEnemy:
	extends Node2D

	signal armed_restored()

	var configured_context: Dictionary = {}
	var configured_difficulty: Dictionary = {}
	var runtime_spawn_serial: int = 0
	var call_order: Array[String] = []


	func configure(
		_enemy_data: Dictionary,
		_player: Node2D,
		_navigation_provider: Node = null,
		spawn_difficulty: Dictionary = {},
		spawn_context: Dictionary = {}
	) -> void:
		call_order.append("configure")
		configured_difficulty = spawn_difficulty.duplicate(true)
		configured_context = spawn_context.duplicate(true)


	func set_runtime_spawn_serial(spawn_serial: int) -> void:
		call_order.append("serial")
		runtime_spawn_serial = spawn_serial


	func restore_snapshot(snapshot_data: Dictionary) -> void:
		call_order.append("restore")
		if bool(snapshot_data.get("armed", false)):
			armed_restored.emit()
