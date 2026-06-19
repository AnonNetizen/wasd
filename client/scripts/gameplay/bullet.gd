# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §4
class_name Bullet
extends Node2D


const STATS := preload("res://scripts/contracts/stats.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")

var _damage: float = 0.0
var _damage_type: String = ""
var _hit_targets: Dictionary = {}
var _hit_radius: float = 0.0
var _remaining_life: float = 0.0
var _max_range: float = 0.0
var _pierce_remaining: int = 0
var _source: Node = null
var _travelled: float = 0.0
var _velocity: Vector2 = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	var step: Vector2 = _velocity * scaled_delta
	position += step
	_travelled += step.length()
	_remaining_life -= scaled_delta

	if _remaining_life <= 0.0 or _travelled >= _max_range:
		PoolManager.release(self)
		return

	_check_enemy_hits()


func configure(stats: Dictionary, projectile: Dictionary, direction: Vector2, source: Node) -> void:
	_damage = float(stats.get(STATS.DAMAGE, 0.0))
	_damage_type = String(projectile.get("damage_type", ""))
	_hit_targets.clear()
	_hit_radius = float(projectile.get("hit_radius", 0.0))
	_remaining_life = float(projectile.get("lifetime", 0.0))
	_max_range = float(stats.get(STATS.BULLET_RANGE, 0.0))
	_pierce_remaining = int(stats.get(STATS.PIERCE_COUNT, 0))
	_source = source
	_travelled = 0.0
	_velocity = direction.normalized() * float(stats.get(STATS.BULLET_SPEED, 0.0))
	add_to_group("active_bullets")
	queue_redraw()


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"damage": _damage,
		"damage_type": _damage_type,
		"hit_radius": _hit_radius,
		"remaining_life": _remaining_life,
		"max_range": _max_range,
		"pierce_remaining": _pierce_remaining,
		"travelled": _travelled,
		"velocity": _vector_to_dict(_velocity),
	}


func restore_snapshot(snapshot_data: Dictionary, source: Node) -> void:
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_damage = float(snapshot_data.get("damage", 0.0))
	_damage_type = String(snapshot_data.get("damage_type", ""))
	_hit_targets.clear()
	_hit_radius = float(snapshot_data.get("hit_radius", 0.0))
	_remaining_life = float(snapshot_data.get("remaining_life", 0.0))
	_max_range = float(snapshot_data.get("max_range", 0.0))
	_pierce_remaining = int(snapshot_data.get("pierce_remaining", 0))
	_source = source
	_travelled = float(snapshot_data.get("travelled", 0.0))
	_velocity = _dict_to_vector(snapshot_data.get("velocity", {}), Vector2.ZERO)
	add_to_group("active_bullets")
	queue_redraw()


func _pool_reset() -> void:
	_damage = 0.0
	_damage_type = ""
	_hit_targets.clear()
	_hit_radius = 0.0
	_remaining_life = 0.0
	_max_range = 0.0
	_pierce_remaining = 0
	_source = null
	_travelled = 0.0
	_velocity = Vector2.ZERO
	visible = true


func _pool_release() -> void:
	remove_from_group("active_bullets")
	_source = null


func _draw() -> void:
	draw_circle(Vector2.ZERO, maxf(_hit_radius, 3.0), Color(1.0, 0.92, 0.35))


func _check_enemy_hits() -> void:
	for raw_enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if not raw_enemy is Node2D or not raw_enemy.has_method("is_alive") or not raw_enemy.has_method("hit_radius"):
			continue
		if not bool(raw_enemy.call("is_alive")):
			continue
		var instance_id: int = raw_enemy.get_instance_id()
		if _hit_targets.has(instance_id):
			continue
		var enemy: Node2D = raw_enemy as Node2D
		if global_position.distance_to(enemy.global_position) > _hit_radius + float(raw_enemy.call("hit_radius")):
			continue

		_hit_targets[instance_id] = true
		var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(_damage, _damage_type, _source, enemy, "team_player", "team_enemy")
		Combat.apply_damage(enemy, info)
		if _pierce_remaining <= 0:
			PoolManager.release(self)
			return
		_pierce_remaining -= 1


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
