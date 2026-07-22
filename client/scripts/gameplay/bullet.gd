# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §4
class_name Bullet
extends Node2D


const STATS := preload("res://scripts/contracts/stats.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")

const PLACEHOLDER_FILL_COLOR: Color = Color(1.0, 0.92, 0.35)
const PLACEHOLDER_OUTLINE_COLOR: Color = Color(0.07, 0.06, 0.05, 0.88)
const PLACEHOLDER_OUTLINE_SCALE: float = 1.45
const DAMAGE_TARGET_GROUPS: Array[String] = ["active_enemies", "active_interest_point_targets"]
const MIN_TERRAIN_QUERY_RADIUS: float = 0.001
const TERRAIN_COLLISION_LAYER: int = 1 << 0
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

var _damage: float = 0.0
var _damage_type: String = ""
var _damage_target_groups: Array[String] = []
var _hit_targets: Dictionary = {}
var _hit_radius: float = 0.0
var _remaining_life: float = 0.0
var _max_range: float = 0.0
var _pierce_remaining: int = 0
var _source: Node = null
var _source_team: String = TEAM_PLAYER
var _target_team: String = TEAM_ENEMY
var _terrain_query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
var _terrain_query_shape: CircleShape2D = CircleShape2D.new()
var _terrain_initial_overlap_pending: bool = false
var _travelled: float = 0.0
var _velocity: Vector2 = Vector2.ZERO
var _wall_pierce_enabled: bool = false


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	var step: Vector2 = _velocity * scaled_delta
	var safe_fraction: float = _terrain_safe_fraction(step)
	var safe_step: Vector2 = step * safe_fraction
	position += safe_step
	_travelled += safe_step.length()
	_remaining_life -= scaled_delta
	if safe_fraction < 1.0:
		PoolManager.release(self)
		return

	if _remaining_life <= 0.0 or _travelled >= _max_range:
		PoolManager.release(self)
		return

	_check_damage_target_hits()


func configure(stats: Dictionary, projectile: Dictionary, direction: Vector2, source: Node) -> void:
	_damage = float(stats.get(STATS.DAMAGE, 0.0))
	_damage_type = String(projectile.get("damage_type", ""))
	_damage_target_groups = _string_array(projectile.get("damage_target_groups", DAMAGE_TARGET_GROUPS))
	if _damage_target_groups.is_empty():
		_damage_target_groups = DAMAGE_TARGET_GROUPS.duplicate()
	_hit_targets.clear()
	_hit_radius = float(projectile.get("hit_radius", 0.0))
	_remaining_life = float(projectile.get("lifetime", 0.0))
	_max_range = float(stats.get(STATS.BULLET_RANGE, 0.0))
	_pierce_remaining = int(stats.get(STATS.PIERCE_COUNT, 0))
	_source = source
	_source_team = String(projectile.get("source_team", TEAM_PLAYER))
	_target_team = String(projectile.get("target_team", TEAM_ENEMY))
	_wall_pierce_enabled = float(stats.get(STATS.WALL_PIERCE, 0.0)) > 0.0
	_prepare_terrain_query()
	_travelled = 0.0
	_velocity = direction.normalized() * float(stats.get(STATS.BULLET_SPEED, 0.0))
	add_to_group("active_bullets")
	queue_redraw()


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"damage": _damage,
		"damage_type": _damage_type,
		"damage_target_groups": _damage_target_groups.duplicate(),
		"hit_radius": _hit_radius,
		"remaining_life": _remaining_life,
		"max_range": _max_range,
		"pierce_remaining": _pierce_remaining,
		"source_team": _source_team,
		"target_team": _target_team,
		"wall_pierce_enabled": _wall_pierce_enabled,
		"travelled": _travelled,
		"velocity": _vector_to_dict(_velocity),
	}


func restore_snapshot(snapshot_data: Dictionary, source: Node) -> void:
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_damage = float(snapshot_data.get("damage", 0.0))
	_damage_type = String(snapshot_data.get("damage_type", ""))
	_damage_target_groups = _string_array(snapshot_data.get("damage_target_groups", DAMAGE_TARGET_GROUPS))
	if _damage_target_groups.is_empty():
		_damage_target_groups = DAMAGE_TARGET_GROUPS.duplicate()
	_hit_targets.clear()
	_hit_radius = float(snapshot_data.get("hit_radius", 0.0))
	_remaining_life = float(snapshot_data.get("remaining_life", 0.0))
	_max_range = float(snapshot_data.get("max_range", 0.0))
	_pierce_remaining = int(snapshot_data.get("pierce_remaining", 0))
	_source = source
	_source_team = String(snapshot_data.get("source_team", TEAM_PLAYER))
	_target_team = String(snapshot_data.get("target_team", TEAM_ENEMY))
	_wall_pierce_enabled = bool(snapshot_data.get("wall_pierce_enabled", false))
	_prepare_terrain_query()
	_travelled = float(snapshot_data.get("travelled", 0.0))
	_velocity = _dict_to_vector(snapshot_data.get("velocity", {}), Vector2.ZERO)
	add_to_group("active_bullets")
	queue_redraw()


func _pool_reset() -> void:
	_damage = 0.0
	_damage_type = ""
	_damage_target_groups.clear()
	_hit_targets.clear()
	_hit_radius = 0.0
	_remaining_life = 0.0
	_max_range = 0.0
	_pierce_remaining = 0
	_source = null
	_source_team = TEAM_PLAYER
	_target_team = TEAM_ENEMY
	_terrain_initial_overlap_pending = false
	_travelled = 0.0
	_velocity = Vector2.ZERO
	_wall_pierce_enabled = false
	visible = true


func _pool_release() -> void:
	remove_from_group("active_bullets")
	_source = null
	_terrain_initial_overlap_pending = false


func _draw() -> void:
	var radius: float = maxf(_hit_radius, 3.0)
	draw_circle(Vector2.ZERO, radius * PLACEHOLDER_OUTLINE_SCALE, PLACEHOLDER_OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, radius, PLACEHOLDER_FILL_COLOR)


func _prepare_terrain_query() -> void:
	_terrain_query_shape.radius = maxf(_hit_radius, MIN_TERRAIN_QUERY_RADIUS)
	_terrain_query.shape = _terrain_query_shape
	_terrain_query.collision_mask = TERRAIN_COLLISION_LAYER
	_terrain_query.collide_with_areas = false
	_terrain_query.collide_with_bodies = true
	_terrain_initial_overlap_pending = not _wall_pierce_enabled


func _terrain_safe_fraction(step: Vector2) -> float:
	if _wall_pierce_enabled:
		return 1.0

	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	_terrain_query.transform = Transform2D(0.0, global_position)
	_terrain_query.motion = Vector2.ZERO
	if _terrain_initial_overlap_pending:
		_terrain_initial_overlap_pending = false
		if not space_state.intersect_shape(_terrain_query, 1).is_empty():
			return 0.0
	if step.is_zero_approx():
		return 1.0

	_terrain_query.motion = step
	var motion_result: PackedFloat32Array = space_state.cast_motion(_terrain_query)
	if motion_result.size() < 2:
		return 1.0
	return clampf(motion_result[0], 0.0, 1.0)


func _check_damage_target_hits() -> void:
	for group_name: String in _damage_target_groups:
		for raw_target: Node in get_tree().get_nodes_in_group(group_name):
			if _try_hit_damage_target(raw_target):
				return


func _try_hit_damage_target(raw_target: Node) -> bool:
	if not raw_target is Node2D or not raw_target.has_method("is_alive") or not raw_target.has_method("hit_radius"):
		return false
	if not bool(raw_target.call("is_alive")):
		return false
	var instance_id: int = raw_target.get_instance_id()
	if _hit_targets.has(instance_id):
		return false
	var target: Node2D = raw_target as Node2D
	if global_position.distance_to(target.global_position) > _hit_radius + float(raw_target.call("hit_radius")):
		return false

	_hit_targets[instance_id] = true
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(_damage, _damage_type, _source, target, _source_team, _target_team)
	Combat.apply_damage(target, info)
	if _pierce_remaining <= 0:
		PoolManager.release(self)
		return true
	_pierce_remaining -= 1
	return false


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if raw_value is Array:
		for item: Variant in raw_value as Array:
			var text: String = String(item)
			if not text.is_empty():
				result.append(text)
		return result
	if raw_value is String:
		for raw_item: String in String(raw_value).split("|", false):
			var text: String = raw_item.strip_edges()
			if not text.is_empty():
				result.append(text)
	return result


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
