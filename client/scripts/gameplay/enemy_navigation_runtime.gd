# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #145, ADR #146, ADR #197
class_name EnemyNavigationRuntime
extends RefCounted


const NAVIGATION_MODE_DIRECT: String = "direct"
const NAVIGATION_MODE_FLOW_FIELD: String = "flow_field"
const NAVIGATION_MODE_LOCAL_ASTAR: String = "local_astar"
const NAVIGATION_MODE_NONE: String = "none"
const NAVIGATION_NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i(1, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]
const PATH_TANGENT_SCORE_WEIGHT: float = 0.2
const SCORE_EPSILON: float = 0.001


var _cached_navigation_waypoint: Vector2 = Vector2.ZERO
var _has_cached_navigation_waypoint: bool = false
var _navigation_mode: String = NAVIGATION_MODE_NONE
var _navigation_provider: Node = null


func configure(navigation_provider: Node) -> void:
	reset()
	_navigation_provider = navigation_provider


func reset() -> void:
	_navigation_provider = null
	_navigation_mode = NAVIGATION_MODE_NONE
	_clear_cached_waypoint()


func mode() -> String:
	return _navigation_mode


func has_cached_waypoint() -> bool:
	return _has_cached_navigation_waypoint


func cached_waypoint() -> Vector2:
	return _cached_navigation_waypoint


func orbit_direction(
	from_position: Vector2,
	target_position: Vector2,
	orbit_radius: float,
	orbit_sign: float
) -> Vector2:
	var from_target: Vector2 = from_position - target_position
	if from_target.length_squared() <= 0.0:
		from_target = Vector2.RIGHT
	var radial: Vector2 = from_target.normalized()
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * orbit_sign
	var safe_orbit_radius: float = maxf(orbit_radius, 1.0)
	var distance: float = from_position.distance_to(target_position)
	if distance > safe_orbit_radius:
		return (
			(target_position - from_position).normalized()
			+ tangent * 0.7
		)
	return radial + tangent * 0.85


func movement_direction_to(
	from_position: Vector2,
	target_position: Vector2,
	clearance: float,
	use_active_field: bool,
	target_is_active_target: bool
) -> Vector2:
	var direct_direction: Vector2 = target_position - from_position
	if not _has_valid_provider():
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if has_clear_corridor(from_position, target_position, clearance):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	var use_active_target_query: bool = (
		use_active_field and target_is_active_target
	)
	var query: Dictionary = (
		active_navigation_query(
			from_position,
			target_position,
			true
		)
		if use_active_target_query
		else navigation_query(from_position, target_position)
	)
	if not bool(query.get("reachable", false)):
		_navigation_mode = NAVIGATION_MODE_NONE
		return Vector2.ZERO
	_navigation_mode = (
		NAVIGATION_MODE_FLOW_FIELD
		if use_active_target_query
		else NAVIGATION_MODE_LOCAL_ASTAR
	)
	return (
		(query.get("next_position", from_position) as Vector2)
		- from_position
	)


func direction_to_cached_target(
	from_position: Vector2,
	target_position: Vector2,
	clearance: float
) -> Vector2:
	var direct_direction: Vector2 = target_position - from_position
	if not _has_valid_provider():
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if has_clear_corridor(from_position, target_position, clearance):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if not _has_cached_navigation_waypoint:
		_navigation_mode = NAVIGATION_MODE_NONE
		return Vector2.ZERO
	_navigation_mode = NAVIGATION_MODE_LOCAL_ASTAR
	return _cached_navigation_waypoint - from_position


func path_band_direction(
	from_position: Vector2,
	target_position: Vector2,
	focus_is_active_target: bool,
	clearance: float,
	desired_distance: float,
	orbit_radius: float,
	orbit_sign: float
) -> Vector2:
	if not focus_is_active_target:
		if has_clear_corridor(
			from_position,
			target_position,
			clearance
		):
			_navigation_mode = NAVIGATION_MODE_DIRECT
			return orbit_direction(
				from_position,
				target_position,
				orbit_radius,
				orbit_sign
			)
		return movement_direction_to(
			from_position,
			target_position,
			clearance,
			false,
			false
		)
	if not _has_valid_provider():
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return orbit_direction(
			from_position,
			target_position,
			orbit_radius,
			orbit_sign
		)
	if not (
		_navigation_provider.has_method("world_to_global_cell")
		and _navigation_provider.has_method("global_cell_to_world")
	):
		return movement_direction_to(
			from_position,
			target_position,
			clearance,
			true,
			true
		)

	var current_cell: Vector2i = _navigation_provider.call(
		"world_to_global_cell",
		from_position
	) as Vector2i
	var from_target: Vector2 = from_position - target_position
	if from_target.length_squared() <= 0.0:
		from_target = Vector2.RIGHT
	var tangent: Vector2 = (
		Vector2(-from_target.y, from_target.x).normalized()
		* orbit_sign
	)
	var best_direction: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var safe_desired_distance: float = maxf(desired_distance, 1.0)
	for offset: Vector2i in NAVIGATION_NEIGHBOR_OFFSETS:
		var candidate_cell: Vector2i = current_cell + offset
		var candidate_position: Vector2 = _navigation_provider.call(
			"global_cell_to_world",
			candidate_cell
		) as Vector2
		if not has_clear_corridor(
			from_position,
			candidate_position,
			clearance
		):
			continue
		var query: Dictionary = _navigation_provider.call(
			"navigation_query_to_active_target",
			candidate_position
		) as Dictionary
		if not bool(query.get("reachable", false)):
			continue
		var route_distance: float = float(query.get("distance", INF))
		var direction: Vector2 = (
			candidate_position - from_position
		).normalized()
		var distance_score: float = (
			-absf(route_distance - safe_desired_distance)
			/ safe_desired_distance
		)
		var tangent_score: float = (
			direction.dot(tangent) * PATH_TANGENT_SCORE_WEIGHT
		)
		var score: float = distance_score + tangent_score
		if score > best_score + SCORE_EPSILON:
			best_score = score
			best_direction = candidate_position - from_position
	if best_direction.length_squared() <= 0.0:
		return movement_direction_to(
			from_position,
			target_position,
			clearance,
			true,
			true
		)
	_navigation_mode = NAVIGATION_MODE_FLOW_FIELD
	return best_direction


func refresh_cached_waypoint(
	from_position: Vector2,
	has_target: bool,
	target_position: Vector2
) -> void:
	_clear_cached_waypoint()
	if not _has_valid_provider() or not has_target:
		return
	var query: Dictionary = navigation_query(
		from_position,
		target_position
	)
	if not bool(query.get("reachable", false)):
		return
	_cached_navigation_waypoint = query.get(
		"next_position",
		Vector2.ZERO
	) as Vector2
	_has_cached_navigation_waypoint = true


func active_navigation_query(
	from_position: Vector2,
	target_position: Vector2,
	use_active_target: bool
) -> Dictionary:
	if not use_active_target:
		return navigation_query(from_position, target_position)
	if (
		_has_valid_provider()
		and _navigation_provider.has_method(
			"navigation_query_to_active_target"
		)
	):
		return _navigation_provider.call(
			"navigation_query_to_active_target",
			from_position
		) as Dictionary
	return _direct_query(from_position, target_position)


func navigation_query(
	from_position: Vector2,
	target_position: Vector2
) -> Dictionary:
	if (
		_has_valid_provider()
		and _navigation_provider.has_method("navigation_query")
	):
		return _navigation_provider.call(
			"navigation_query",
			from_position,
			target_position
		) as Dictionary
	return _direct_query(from_position, target_position)


func has_terrain_line_of_sight(
	from_position: Vector2,
	target_position: Vector2
) -> bool:
	if (
		_has_valid_provider()
		and _navigation_provider.has_method(
			"has_terrain_line_of_sight"
		)
	):
		return bool(_navigation_provider.call(
			"has_terrain_line_of_sight",
			from_position,
			target_position
		))
	return true


func has_clear_corridor(
	from_position: Vector2,
	target_position: Vector2,
	clearance: float
) -> bool:
	if (
		_has_valid_provider()
		and _navigation_provider.has_method("has_clear_corridor")
	):
		return bool(_navigation_provider.call(
			"has_clear_corridor",
			from_position,
			target_position,
			clearance
		))
	return true


func _clear_cached_waypoint() -> void:
	_cached_navigation_waypoint = Vector2.ZERO
	_has_cached_navigation_waypoint = false


func _direct_query(
	from_position: Vector2,
	target_position: Vector2
) -> Dictionary:
	return {
		"reachable": true,
		"distance": from_position.distance_to(target_position),
		"next_position": target_position,
		"target_position": target_position,
	}


func _has_valid_provider() -> bool:
	return (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
	)
