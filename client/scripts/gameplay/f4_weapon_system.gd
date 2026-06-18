# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §4
class_name F4WeaponSystem
extends Node


const STATS := preload("res://scripts/contracts/stats.gd")

var _player: Node2D = null
var _active_parent: Node = null
var _base_stats: Dictionary = {}
var _runtime_stats: Dictionary = {}
var _stat_additions: Dictionary = {}
var _stat_multipliers: Dictionary = {}
var _weapon_data: Dictionary = {}
var _cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	if _player == null or _weapon_data.is_empty():
		return
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	_cooldown_remaining -= scaled_delta
	if _cooldown_remaining > 0.0:
		return

	_fire_once()
	var fire_rate: float = float(_runtime_stats.get(STATS.FIRE_RATE, 1.0))
	_cooldown_remaining = 1.0 / maxf(fire_rate, 0.01)


func configure(player: Node2D, active_parent: Node, weapon_data: Dictionary) -> void:
	_player = player
	_active_parent = active_parent
	_weapon_data = weapon_data.duplicate(true)
	_base_stats = _weapon_data.get("base_stats", {}).duplicate(true)
	_stat_additions.clear()
	_stat_multipliers.clear()
	_rebuild_runtime_stats()
	_cooldown_remaining = 0.0


func apply_modifiers(modifiers: Array) -> void:
	for raw_modifier: Variant in modifiers:
		if not raw_modifier is Dictionary:
			continue
		var modifier: Dictionary = raw_modifier as Dictionary
		var stat: String = String(modifier.get("stat", ""))
		var modifier_type: String = String(modifier.get("type", ""))
		var value: float = float(modifier.get("value", 0.0))
		if modifier_type == "add":
			_stat_additions[stat] = float(_stat_additions.get(stat, 0.0)) + value
		elif modifier_type == "mult":
			_stat_multipliers[stat] = float(_stat_multipliers.get(stat, 1.0)) * value
	_rebuild_runtime_stats()


func stat_value(stat: String) -> float:
	return float(_runtime_stats.get(stat, 0.0))


func snapshot() -> Dictionary:
	return {
		"cooldown_remaining": _cooldown_remaining,
		"stat_additions": _stat_additions.duplicate(true),
		"stat_multipliers": _stat_multipliers.duplicate(true),
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_stat_additions = _dictionary_or_empty(snapshot_data.get("stat_additions", {}))
	_stat_multipliers = _dictionary_or_empty(snapshot_data.get("stat_multipliers", {}))
	_rebuild_runtime_stats()
	_cooldown_remaining = maxf(float(snapshot_data.get("cooldown_remaining", 0.0)), 0.0)


func _fire_once() -> void:
	var projectile: Dictionary = _weapon_data.get("projectile", {})
	var bullet_count: int = int(_runtime_stats.get(STATS.BULLET_COUNT, 1))
	for _index: int in range(maxi(bullet_count, 1)):
		_spawn_bullet(_runtime_stats, projectile)


func _spawn_bullet(stats: Dictionary, projectile: Dictionary) -> void:
	var pool_id: String = String(projectile.get("pool_id", ""))
	var raw_node: Node = PoolManager.acquire(pool_id)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return

	var bullet: Node2D = raw_node as Node2D
	var raw_direction: Variant = _player.get("aim_direction")
	var direction: Vector2 = raw_direction if raw_direction is Vector2 else Vector2.RIGHT
	direction = direction.normalized()
	var muzzle_distance: float = float(projectile.get("muzzle_distance", 0.0))
	bullet.global_position = _player.global_position + direction * muzzle_distance
	_reparent_to_active_world(bullet)
	bullet.call("configure", stats, projectile, direction, _player)


func _reparent_to_active_world(node: Node) -> void:
	if _active_parent == null:
		return
	var old_parent: Node = node.get_parent()
	if old_parent == _active_parent:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	_active_parent.add_child(node)


func _rebuild_runtime_stats() -> void:
	_runtime_stats = _base_stats.duplicate(true)
	for stat: String in _base_stats.keys():
		var base_value: float = float(_base_stats.get(stat, 0.0))
		var added_value: float = float(_stat_additions.get(stat, 0.0))
		var multiplier: float = float(_stat_multipliers.get(stat, 1.0))
		_runtime_stats[stat] = (base_value + added_value) * multiplier
	for stat: String in _stat_additions.keys():
		if _runtime_stats.has(stat):
			continue
		_runtime_stats[stat] = float(_stat_additions.get(stat, 0.0)) * float(_stat_multipliers.get(stat, 1.0))


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}
