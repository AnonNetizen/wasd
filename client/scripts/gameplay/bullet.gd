# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §4
class_name Bullet
extends Node2D


const STATS := preload("res://scripts/contracts/stats.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")

const ACTIVE_DEPLOYABLE_GROUP: String = "active_deployables"
const DAMAGE_TARGET_GROUPS: Array[String] = ["active_enemies", "active_interest_point_targets"]
const MIN_TERRAIN_QUERY_RADIUS: float = 0.001
const TERRAIN_COLLISION_LAYER: int = 1 << 0
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

var _damage: float = 0.0
var _element_id: String = ""
var _damage_target_groups: Array[String] = []
var _hit_targets: Dictionary = {}
var _hit_radius: float = 0.0
var _initial_deployable_sweep_pending: bool = false
var _initial_deployable_sweep_start: Vector2 = Vector2.ZERO
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
var _visual: BulletSlimeVisual = null


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	var step: Vector2 = _velocity * scaled_delta
	var step_start: Vector2 = global_position
	var safe_fraction: float = _terrain_safe_fraction(step)
	var safe_step: Vector2 = step * safe_fraction
	position += safe_step
	_travelled += safe_step.length()
	_remaining_life -= scaled_delta
	var deployable_step_start: Vector2 = step_start
	if _initial_deployable_sweep_pending:
		deployable_step_start = _initial_deployable_sweep_start
		_initial_deployable_sweep_pending = false
	if _check_enemy_projectile_deployable_hit(
		deployable_step_start,
		global_position
	):
		return
	if safe_fraction < 1.0:
		PoolManager.release(self)
		return

	if _remaining_life <= 0.0 or _travelled >= _max_range:
		PoolManager.release(self)
		return

	_check_damage_target_hits(step_start, global_position)


func configure(stats: Dictionary, projectile: Dictionary, direction: Vector2, source: Node) -> void:
	_damage = float(stats.get(STATS.DAMAGE, 0.0))
	_element_id = String(projectile.get("element_id", ""))
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
	_initial_deployable_sweep_start = (
		(source as Node2D).global_position
		if source is Node2D
		else global_position
	)
	_initial_deployable_sweep_pending = _source_team == TEAM_ENEMY
	_wall_pierce_enabled = float(stats.get(STATS.WALL_PIERCE, 0.0)) > 0.0
	_prepare_terrain_query()
	_travelled = 0.0
	_velocity = direction.normalized() * float(stats.get(STATS.BULLET_SPEED, 0.0))
	add_to_group("active_bullets")
	_refresh_visual()


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"damage": _damage,
		"element_id": _element_id,
		"damage_target_groups": _damage_target_groups.duplicate(),
		"hit_radius": _hit_radius,
		"initial_deployable_sweep_pending": (
			_initial_deployable_sweep_pending
		),
		"initial_deployable_sweep_start": _vector_to_dict(
			_initial_deployable_sweep_start
		),
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
	_element_id = String(snapshot_data.get("element_id", ""))
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
	_initial_deployable_sweep_pending = bool(
		snapshot_data.get(
			"initial_deployable_sweep_pending",
			false
		)
	)
	_initial_deployable_sweep_start = _dict_to_vector(
		snapshot_data.get("initial_deployable_sweep_start", {}),
		global_position
	)
	_wall_pierce_enabled = bool(snapshot_data.get("wall_pierce_enabled", false))
	_prepare_terrain_query()
	_travelled = float(snapshot_data.get("travelled", 0.0))
	_velocity = _dict_to_vector(snapshot_data.get("velocity", {}), Vector2.ZERO)
	add_to_group("active_bullets")
	_refresh_visual()


func _pool_reset() -> void:
	_damage = 0.0
	_element_id = ""
	_damage_target_groups.clear()
	_hit_targets.clear()
	_hit_radius = 0.0
	_initial_deployable_sweep_pending = false
	_initial_deployable_sweep_start = Vector2.ZERO
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
	_refresh_visual()


func _pool_release() -> void:
	remove_from_group("active_bullets")
	_source = null
	_source_team = TEAM_PLAYER
	_initial_deployable_sweep_pending = false
	_terrain_initial_overlap_pending = false
	_refresh_visual()


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


func _refresh_visual() -> void:
	if _visual == null:
		_visual = get_node_or_null("Visual") as BulletSlimeVisual
	var radius: float = maxf(_hit_radius, 3.0)
	if _visual == null:
		return
	_visual.visible = true
	_visual.scale = Vector2(radius, radius)
	_visual.set_enemy_palette(_source_team == TEAM_ENEMY)


func _check_damage_target_hits(
	step_start: Vector2,
	step_end: Vector2
) -> void:
	var candidates: Array[Dictionary] = []
	var seen_targets: Dictionary = {}
	for group_name: String in _damage_target_groups:
		if group_name == ACTIVE_DEPLOYABLE_GROUP:
			continue
		for raw_target: Node in get_tree().get_nodes_in_group(group_name):
			var instance_id: int = raw_target.get_instance_id()
			if seen_targets.has(instance_id):
				continue
			seen_targets[instance_id] = true
			var hit_fraction: float = _damage_target_hit_fraction(
				raw_target,
				step_start,
				step_end
			)
			if hit_fraction < 0.0:
				continue
			candidates.append({
				"target": raw_target,
				"fraction": hit_fraction,
				"instance_id": instance_id,
			})
	candidates.sort_custom(
		Callable(self, "_damage_target_candidate_less")
	)
	for candidate: Dictionary in candidates:
		var raw_target: Node = candidate.get("target") as Node
		if (
			raw_target != null
			and _try_hit_damage_target(
				raw_target,
				step_start,
				step_end
			)
		):
			return


func _damage_target_candidate_less(
	left: Dictionary,
	right: Dictionary
) -> bool:
	var left_fraction: float = float(left.get("fraction", INF))
	var right_fraction: float = float(right.get("fraction", INF))
	if not is_equal_approx(left_fraction, right_fraction):
		return left_fraction < right_fraction
	return int(left.get("instance_id", 0)) < int(
		right.get("instance_id", 0)
	)


func _damage_target_hit_fraction(
	raw_target: Node,
	step_start: Vector2,
	step_end: Vector2
) -> float:
	if (
		raw_target.is_in_group(ACTIVE_DEPLOYABLE_GROUP)
		or not raw_target is Node2D
		or not raw_target.has_method("is_alive")
		or not raw_target.has_method("hit_radius")
		or not bool(raw_target.call("is_alive"))
		or _hit_targets.has(raw_target.get_instance_id())
	):
		return -1.0
	var target: Node2D = raw_target as Node2D
	var combined_radius: float = (
		_hit_radius + float(raw_target.call("hit_radius"))
	)
	var segment: Vector2 = step_end - step_start
	var offset: Vector2 = step_start - target.global_position
	if offset.length_squared() <= combined_radius * combined_radius:
		return 0.0
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared <= 0.0:
		return -1.0
	var projection: float = -offset.dot(segment)
	var discriminant: float = (
		projection * projection
		- segment_length_squared
		* (
			offset.length_squared()
			- combined_radius * combined_radius
		)
	)
	if discriminant < 0.0:
		return -1.0
	var fraction: float = (
		projection - sqrt(discriminant)
	) / segment_length_squared
	if fraction < 0.0 or fraction > 1.0:
		return -1.0
	return fraction


func _check_enemy_projectile_deployable_hit(
	step_start: Vector2,
	step_end: Vector2
) -> bool:
	if _source_team != TEAM_ENEMY:
		return false
	var closest_target: Node2D = null
	var closest_fraction: float = INF
	for raw_target: Node in get_tree().get_nodes_in_group(
		ACTIVE_DEPLOYABLE_GROUP
	):
		if (
			not raw_target is Node2D
			or not raw_target.has_method("receive_projectile_damage")
			or not raw_target.has_method("is_alive")
			or not raw_target.has_method(
				"projectile_boundary_hit_fraction"
			)
			or not bool(raw_target.call("is_alive"))
		):
			continue
		var target: Node2D = raw_target as Node2D
		var fraction: float = float(
			raw_target.call(
				"projectile_boundary_hit_fraction",
				step_start,
				step_end,
				_hit_radius
			)
		)
		if fraction < 0.0 or fraction >= closest_fraction:
			continue
		closest_target = target
		closest_fraction = fraction
	if closest_target == null:
		return false

	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		_damage,
		_element_id,
		_source,
		closest_target,
		_source_team,
		_target_team
	)
	closest_target.call("receive_projectile_damage", info)
	PoolManager.release(self)
	return true


func _try_hit_damage_target(
	raw_target: Node,
	step_start: Vector2,
	step_end: Vector2
) -> bool:
	if raw_target.is_in_group(ACTIVE_DEPLOYABLE_GROUP):
		return false
	if not raw_target is Node2D or not raw_target.has_method("is_alive") or not raw_target.has_method("hit_radius"):
		return false
	if not bool(raw_target.call("is_alive")):
		return false
	var instance_id: int = raw_target.get_instance_id()
	if _hit_targets.has(instance_id):
		return false
	var target: Node2D = raw_target as Node2D
	var target_radius: float = _hit_radius + float(
		raw_target.call("hit_radius")
	)
	if (
		_closest_point_on_segment(
			target.global_position,
			step_start,
			step_end
		).distance_to(target.global_position)
		> target_radius
	):
		return false

	_hit_targets[instance_id] = true
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		_damage,
		_element_id,
		_source,
		target,
		_source_team,
		_target_team
	)
	Combat.apply_damage(target, info)
	if _pierce_remaining <= 0:
		PoolManager.release(self)
		return true
	_pierce_remaining -= 1
	return false


func _closest_point_on_segment(
	point: Vector2,
	start: Vector2,
	end: Vector2
) -> Vector2:
	var segment: Vector2 = end - start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.0:
		return start
	var fraction: float = clampf(
		(point - start).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return start + segment * fraction


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
