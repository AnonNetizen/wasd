# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §4
class_name F4WeaponSystem
extends Node


const STATS := preload("res://scripts/contracts/stats.gd")

var _player: Node2D = null
var _active_parent: Node = null
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
	var stats: Dictionary = _weapon_data.get("base_stats", {})
	var fire_rate: float = float(stats.get(STATS.FIRE_RATE, 1.0))
	_cooldown_remaining = 1.0 / maxf(fire_rate, 0.01)


func configure(player: Node2D, active_parent: Node, weapon_data: Dictionary) -> void:
	_player = player
	_active_parent = active_parent
	_weapon_data = weapon_data.duplicate(true)
	_cooldown_remaining = 0.0


func _fire_once() -> void:
	var stats: Dictionary = _weapon_data.get("base_stats", {})
	var projectile: Dictionary = _weapon_data.get("projectile", {})
	var bullet_count: int = int(stats.get(STATS.BULLET_COUNT, 1))
	for _index: int in range(maxi(bullet_count, 1)):
		_spawn_bullet(stats, projectile)


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
