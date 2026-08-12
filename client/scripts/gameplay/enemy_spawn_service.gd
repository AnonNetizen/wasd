# Doc: docs/代码/enemy_spawn_service.md
# Authority: docs/决策记录.md ADR #197
class_name EnemySpawnService
extends Node


const DEFAULT_SPAWN_DIFFICULTY: Dictionary = {
	"health_multiplier": 1.0,
	"damage_multiplier": 1.0,
}

var _active_world: Node2D = null
var _player: Node2D = null
var _navigation_provider: Callable = Callable()
var _difficulty_provider: Callable = Callable()
var _reward_resolver: Callable = Callable()
var _bounds_handler: Callable = Callable()
var _lifecycle_handler: Callable = Callable()
var _acquire_handler: Callable = Callable()
var _release_handler: Callable = Callable()
var _next_spawn_serial: int = 1
var _configured: bool = false


func configure(
	active_world: Node2D,
	player: Node2D,
	navigation_provider: Callable,
	difficulty_provider: Callable,
	reward_resolver: Callable,
	bounds_handler: Callable,
	lifecycle_handler: Callable,
	acquire_handler: Callable = Callable(),
	release_handler: Callable = Callable()
) -> bool:
	_configured = false
	if (
		active_world == null
		or player == null
		or not navigation_provider.is_valid()
		or not difficulty_provider.is_valid()
		or not reward_resolver.is_valid()
		or not bounds_handler.is_valid()
		or not lifecycle_handler.is_valid()
	):
		return false
	_active_world = active_world
	_player = player
	_navigation_provider = navigation_provider
	_difficulty_provider = difficulty_provider
	_reward_resolver = reward_resolver
	_bounds_handler = bounds_handler
	_lifecycle_handler = lifecycle_handler
	_acquire_handler = (
		acquire_handler
		if acquire_handler.is_valid()
		else Callable(PoolManager, "acquire")
	)
	_release_handler = (
		release_handler
		if release_handler.is_valid()
		else Callable(PoolManager, "release")
	)
	if not _acquire_handler.is_valid() or not _release_handler.is_valid():
		return false
	_configured = true
	return true


func reset_spawn_serial(next_serial: int = 1) -> void:
	_next_spawn_serial = maxi(next_serial, 1)


func next_spawn_serial() -> int:
	return _next_spawn_serial


## Acquires and materializes one fresh enemy. The caller remains responsible for
## content availability, walkability, pool registration, and spawn planning.
func spawn_fresh(spec: Dictionary) -> Dictionary:
	if not _configured:
		return _result(false, "not_configured")
	var enemy_data: Dictionary = _dictionary_or_empty(
		spec.get("enemy_data", {})
	)
	var enemy: Node2D = _acquire_enemy(enemy_data)
	if enemy == null:
		return _result(false, "pool_unavailable")

	var spawn_context: Dictionary = _dictionary_or_empty(
		spec.get("spawn_context", {})
	)
	if bool(spec.get("normal_rewards", true)):
		var raw_reward: Variant = _reward_resolver.call(
			enemy_data,
			spawn_context
		)
		var reward_snapshot: Dictionary = _dictionary_or_empty(raw_reward)
		if reward_snapshot.is_empty():
			_release_handler.call(enemy)
			return _result(false, "reward_unavailable")
		spawn_context["reward_snapshot"] = reward_snapshot

	var spawn_position: Vector2 = spec.get(
		"world_position",
		Vector2.ZERO
	) as Vector2
	var raw_position_provider: Variant = spec.get(
		"position_provider",
		Callable()
	)
	if raw_position_provider is Callable:
		var position_provider: Callable = raw_position_provider as Callable
		if position_provider.is_valid():
			var raw_position: Variant = position_provider.call()
			if not raw_position is Vector2:
				_release_handler.call(enemy)
				return _result(false, "invalid_spawn_position")
			spawn_position = raw_position as Vector2

	# Fresh spawning intentionally resolves its position before reparenting.
	enemy.global_position = spawn_position
	_reparent_to_active_world(enemy)
	_apply_spawn_metadata(
		enemy,
		String(spec.get("wave_key", "")),
		String(spec.get("module_slot", ""))
	)
	_configure_enemy(enemy, enemy_data, spawn_context, spec)
	_assign_spawn_serial(enemy)
	_call_pre_lifecycle_hook(enemy, spec)
	_bounds_handler.call(enemy)
	_lifecycle_handler.call(enemy, String(spec.get("wave_key", "")))
	return _result(true, "", enemy)


## Materializes an enemy from a Run v20 entity snapshot. Reward and event
## context are supplied by the caller and are never re-resolved here.
func restore_enemy(spec: Dictionary) -> Dictionary:
	if not _configured:
		return _result(false, "not_configured")
	var enemy_data: Dictionary = _dictionary_or_empty(
		spec.get("enemy_data", {})
	)
	var enemy: Node2D = _acquire_enemy(enemy_data)
	if enemy == null:
		return _result(false, "pool_unavailable")

	# Restore intentionally reparents before applying the saved world position.
	_reparent_to_active_world(enemy)
	enemy.global_position = spec.get(
		"world_position",
		Vector2.ZERO
	) as Vector2
	var wave_key: String = String(spec.get("wave_key", ""))
	_apply_spawn_metadata(
		enemy,
		wave_key,
		String(spec.get("module_slot", ""))
	)
	_configure_enemy(
		enemy,
		enemy_data,
		_dictionary_or_empty(spec.get("spawn_context", {})),
		spec
	)
	_restore_spawn_serial(
		enemy,
		maxi(int(spec.get("runtime_spawn_serial", 0)), 0)
	)
	_call_pre_lifecycle_hook(enemy, spec)
	_bounds_handler.call(enemy)
	_lifecycle_handler.call(enemy, wave_key)
	var snapshot_data: Dictionary = _dictionary_or_empty(
		spec.get("snapshot", {})
	)
	if enemy.has_method("restore_snapshot"):
		enemy.call("restore_snapshot", snapshot_data)
	return _result(true, "", enemy)


func _acquire_enemy(enemy_data: Dictionary) -> Node2D:
	var pool_id: String = String(enemy_data.get("pool_id", ""))
	var raw_node: Variant = _acquire_handler.call(pool_id)
	if not raw_node is Node2D:
		return null
	var enemy: Node2D = raw_node as Node2D
	if not enemy.has_method("configure"):
		return null
	return enemy


func _configure_enemy(
	enemy: Node2D,
	enemy_data: Dictionary,
	spawn_context: Dictionary,
	spec: Dictionary
) -> void:
	var navigation_provider: Node = null
	if bool(spec.get("use_default_navigation", true)):
		var raw_navigation: Variant = _navigation_provider.call()
		if raw_navigation is Node:
			navigation_provider = raw_navigation as Node
	var spawn_difficulty: Dictionary = _dictionary_or_empty(
		spec.get("fixed_spawn_difficulty", {})
	)
	if (
		spawn_difficulty.is_empty()
		and bool(spec.get("use_default_difficulty", true))
	):
		spawn_difficulty = _dictionary_or_empty(
			_difficulty_provider.call()
		)
	if spawn_difficulty.is_empty():
		spawn_difficulty = DEFAULT_SPAWN_DIFFICULTY.duplicate(true)
	enemy.call(
		"configure",
		enemy_data,
		_player,
		navigation_provider,
		spawn_difficulty,
		spawn_context
	)


func _apply_spawn_metadata(
	enemy: Node,
	wave_key: String,
	module_slot: String
) -> void:
	enemy.set_meta("wave_key", wave_key)
	if module_slot.is_empty():
		if enemy.has_meta("module_slot"):
			enemy.remove_meta("module_slot")
	else:
		enemy.set_meta("module_slot", module_slot)


func _assign_spawn_serial(enemy: Node) -> void:
	if not enemy.has_method("set_runtime_spawn_serial"):
		return
	enemy.call("set_runtime_spawn_serial", _next_spawn_serial)
	_next_spawn_serial += 1


func _restore_spawn_serial(enemy: Node, restored_serial: int) -> void:
	if not enemy.has_method("set_runtime_spawn_serial"):
		return
	enemy.call("set_runtime_spawn_serial", restored_serial)
	_next_spawn_serial = maxi(_next_spawn_serial, restored_serial + 1)


func _call_pre_lifecycle_hook(enemy: Node2D, spec: Dictionary) -> void:
	var raw_hook: Variant = spec.get("pre_lifecycle_hook", Callable())
	if not raw_hook is Callable:
		return
	var hook: Callable = raw_hook as Callable
	if hook.is_valid():
		hook.call(enemy)


func _reparent_to_active_world(enemy: Node) -> void:
	var old_parent: Node = enemy.get_parent()
	if old_parent == _active_world:
		return
	if old_parent == null:
		push_error(
			"[EnemySpawnService] acquired enemy has no PoolManager parent"
		)
		return
	enemy.reparent(_active_world, true)


func _result(
	ok: bool,
	reason: String,
	enemy: Node2D = null
) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"enemy": enemy,
	}


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}
