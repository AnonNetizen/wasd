class_name SteamLabSlimeBody
extends Node2D

@export_range(16, 128, 1) var point_count: int = 64
@export var base_radius: float = 56.0
@export var min_radius: float = 34.0
@export var max_radius: float = 78.0
@export var core_collision_radius: float = 38.0
@export var follow_strength: float = 4.2
@export var follow_response: float = 9.5
@export var max_speed: float = 260.0
@export var edge_stiffness: float = 58.0
@export var edge_damping: float = 8.5
@export var neighbor_smoothing: float = 34.0
@export var membrane_follow_stiffness: float = 42.0
@export var membrane_follow_damping: float = 7.2
@export var membrane_neighbor_smoothing: float = 18.0
@export var membrane_inertia: float = 0.82
@export var movement_push_amount: float = 18.0
@export var movement_squash_amount: float = 0.14
@export var area_pressure: float = 42.0
@export var obstacle_edge_force: float = 1280.0
@export var edge_contact_distance: float = 24.0
@export var membrane_obstacle_clearance: float = 2.0
@export var breath_amount: float = 3.0
@export var breath_speed: float = 1.6
@export var surface_noise_amount: float = 2.4

var obstacle_rect: Rect2 = Rect2()
var obstacle_enabled: bool = false
var target_position: Vector2 = Vector2.ZERO

var _directions: Array[Vector2] = []
var _edge_offsets: Array[Vector2] = []
var _edge_velocities: Array[Vector2] = []
var _radii: PackedFloat32Array = PackedFloat32Array()
var _radial_velocities: PackedFloat32Array = PackedFloat32Array()
var _velocity: Vector2 = Vector2.ZERO
var _last_global_position: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _impact_strength: float = 0.0
var _position_drive_enabled: bool = true
var _fill_color: Color = Color(0.42, 0.86, 0.70, 0.48)
var _edge_color: Color = Color(0.75, 1.0, 0.86, 0.92)
var _core_color: Color = Color(0.21, 0.44, 0.54, 0.45)


func _ready() -> void:
	_initialize_edge_points()
	target_position = global_position
	_last_global_position = global_position


func _physics_process(delta: float) -> void:
	var safe_delta: float = minf(delta, 0.033)
	_time += safe_delta
	var core_delta := global_position - _last_global_position
	if _position_drive_enabled:
		core_delta += _update_body_motion(safe_delta)
	_update_edge_points(safe_delta, core_delta)
	_last_global_position = global_position
	_impact_strength = maxf(0.0, _impact_strength - safe_delta * 2.2)
	queue_redraw()


func set_follow_target(new_target_position: Vector2) -> void:
	target_position = new_target_position


func set_obstacle_rect(new_obstacle_rect: Rect2) -> void:
	obstacle_rect = new_obstacle_rect
	obstacle_enabled = obstacle_rect.size.x > 0.0 and obstacle_rect.size.y > 0.0


func set_position_drive_enabled(enabled: bool) -> void:
	_position_drive_enabled = enabled
	if not enabled:
		_velocity = Vector2.ZERO


func set_palette(fill_color: Color, edge_color: Color, core_color: Color) -> void:
	_fill_color = fill_color
	_edge_color = edge_color
	_core_color = core_color


func warp_to(new_global_position: Vector2) -> void:
	global_position = new_global_position
	target_position = new_global_position
	_velocity = Vector2.ZERO
	_last_global_position = new_global_position
	_reset_edge_offsets()


func body_velocity() -> Vector2:
	return _velocity


func _draw() -> void:
	if _directions.is_empty():
		return

	var membrane_points := PackedVector2Array()
	for index in range(point_count):
		membrane_points.append(_edge_offsets[index])

	var closed_points := PackedVector2Array(membrane_points)
	closed_points.append(membrane_points[0])

	var fill_color := Color(_fill_color, _fill_color.a + _impact_strength * 0.22)
	var contact_color := Color(1.0, 0.82, 0.42, 0.58)

	draw_colored_polygon(membrane_points, fill_color)
	draw_polyline(closed_points, _edge_color, 4.0, true)
	draw_polyline(closed_points, contact_color, 1.2 + _impact_strength * 2.6, true)
	draw_circle(Vector2.ZERO, base_radius * 0.38, _core_color)
	draw_arc(Vector2.ZERO, base_radius * 0.38, 0.0, TAU, 48, Color(_edge_color, 0.36), 1.6, true)

	for index in range(0, point_count, 8):
		draw_circle(_directions[index] * _radii[index], 2.0, Color(1.0, 0.94, 0.64, 0.56))


func _initialize_edge_points() -> void:
	_directions.clear()
	_edge_offsets.clear()
	_edge_velocities.clear()
	_radii.resize(point_count)
	_radial_velocities.resize(point_count)

	for index in range(point_count):
		var ratio := float(index) / float(point_count)
		var angle := ratio * TAU
		var direction := Vector2(cos(angle), sin(angle))
		_directions.append(direction)
		_radii[index] = base_radius + sin(angle * 3.0) * 2.0
		_radial_velocities[index] = 0.0
		_edge_offsets.append(direction * _radii[index])
		_edge_velocities.append(Vector2.ZERO)


func _update_body_motion(delta: float) -> Vector2:
	var previous_position := global_position
	var to_target := target_position - global_position
	var desired_velocity := to_target * follow_strength
	if desired_velocity.length() > max_speed:
		desired_velocity = desired_velocity.normalized() * max_speed

	var response := 1.0 - exp(-follow_response * delta)
	_velocity = _velocity.lerp(desired_velocity, response)
	global_position += _velocity * delta
	_resolve_core_obstacle()
	return global_position - previous_position


func _resolve_core_obstacle() -> void:
	if not obstacle_enabled:
		return

	var normal := Vector2.ZERO
	var distance := 0.0
	if obstacle_rect.has_point(global_position):
		normal = _normal_from_rect_inside(global_position, obstacle_rect)
	else:
		var closest_point := _closest_point_to_rect(global_position, obstacle_rect)
		var offset := global_position - closest_point
		distance = offset.length()
		if distance <= 0.001:
			normal = Vector2.LEFT
		else:
			normal = offset / distance

	if distance >= core_collision_radius:
		return

	var penetration := core_collision_radius - distance
	global_position += normal * penetration

	var velocity_into_obstacle := _velocity.dot(-normal)
	if velocity_into_obstacle > 0.0:
		_velocity += normal * velocity_into_obstacle * 0.85

	_impact_strength = maxf(_impact_strength, clampf(penetration / 42.0, 0.0, 1.0))


func _update_edge_points(delta: float, core_delta: Vector2) -> void:
	var average_radius := _average_radius()
	var pressure_force := (base_radius - average_radius) * area_pressure
	var next_radii := PackedFloat32Array(_radii)

	for index in range(point_count):
		var previous_index := posmod(index - 1, point_count)
		var next_index := (index + 1) % point_count
		var neighbor_average := (_radii[previous_index] + _radii[next_index]) * 0.5
		var ratio := float(index) / float(point_count)
		var breath := sin(_time * breath_speed + ratio * TAU * 2.0) * breath_amount
		var ripple := sin(_time * 2.1 + ratio * TAU * 7.0) * surface_noise_amount
		var target_radius := base_radius + breath + ripple
		var spring_force := (target_radius - _radii[index]) * edge_stiffness
		var smoothing_force := (neighbor_average - _radii[index]) * neighbor_smoothing
		var obstacle_force := _obstacle_radial_force(index)
		var acceleration := spring_force + smoothing_force + pressure_force + obstacle_force

		_radial_velocities[index] += acceleration * delta
		_radial_velocities[index] *= maxf(0.0, 1.0 - edge_damping * delta)
		var candidate_radius: float = clampf(_radii[index] + _radial_velocities[index] * delta, min_radius, max_radius)
		var limited_radius: float = _limit_radius_against_obstacle(index, candidate_radius)
		if limited_radius < candidate_radius:
			_radial_velocities[index] = minf(_radial_velocities[index], 0.0)
			_impact_strength = maxf(_impact_strength, clampf((candidate_radius - limited_radius) / 32.0, 0.0, 1.0))
		next_radii[index] = limited_radius

	_radii = next_radii
	_update_membrane_offsets(delta, core_delta)


func _update_membrane_offsets(delta: float, core_delta: Vector2) -> void:
	if _edge_offsets.size() != point_count or _edge_velocities.size() != point_count:
		_reset_edge_offsets()

	var drive_velocity := Vector2.ZERO
	if delta > 0.0001:
		drive_velocity = core_delta / delta
	var drive_speed := drive_velocity.length()
	var drive_direction := Vector2.ZERO
	if drive_speed > 0.001:
		drive_direction = drive_velocity / drive_speed
	var drive_ratio := clampf(drive_speed / maxf(max_speed, 1.0), 0.0, 1.0)
	var core_shift := core_delta * membrane_inertia
	var next_offsets: Array[Vector2] = []
	next_offsets.resize(point_count)

	for index in range(point_count):
		_edge_offsets[index] -= core_shift
		var previous_index := posmod(index - 1, point_count)
		var next_index := (index + 1) % point_count
		var direction := _directions[index]
		var alignment := 0.0
		if drive_direction != Vector2.ZERO:
			alignment = direction.dot(drive_direction)
		var side_alignment := 1.0 - absf(alignment)
		var squash := 1.0 + maxf(alignment, 0.0) * movement_squash_amount * drive_ratio
		squash -= side_alignment * movement_squash_amount * 0.45 * drive_ratio
		var target_offset := direction * _radii[index] * squash
		target_offset += drive_direction * maxf(alignment, 0.0) * movement_push_amount * drive_ratio

		var neighbor_average := (_edge_offsets[previous_index] + _edge_offsets[next_index]) * 0.5
		var spring_force := (target_offset - _edge_offsets[index]) * membrane_follow_stiffness
		var smoothing_force := (neighbor_average - _edge_offsets[index]) * membrane_neighbor_smoothing
		_edge_velocities[index] += (spring_force + smoothing_force) * delta
		_edge_velocities[index] *= maxf(0.0, 1.0 - membrane_follow_damping * delta)
		var candidate_offset := _edge_offsets[index] + _edge_velocities[index] * delta
		next_offsets[index] = _clamped_membrane_offset(candidate_offset, direction)

	_edge_offsets = next_offsets


func _reset_edge_offsets() -> void:
	_edge_offsets.clear()
	_edge_velocities.clear()
	for index in range(_directions.size()):
		_edge_offsets.append(_directions[index] * _radii[index])
		_edge_velocities.append(Vector2.ZERO)


func _clamped_membrane_offset(candidate_offset: Vector2, fallback_direction: Vector2) -> Vector2:
	var distance := candidate_offset.length()
	var direction := fallback_direction
	if distance > 0.001:
		direction = candidate_offset / distance
	var minimum_distance := min_radius * 0.78
	var maximum_distance := max_radius + movement_push_amount
	return direction * clampf(distance, minimum_distance, maximum_distance)


func _obstacle_radial_force(index: int) -> float:
	if not obstacle_enabled:
		return 0.0

	var direction := _directions[index]
	var edge_position := global_position + _edge_offsets[index]
	var normal := Vector2.ZERO
	var distance := 0.0

	if obstacle_rect.has_point(edge_position):
		normal = _normal_from_rect_inside(edge_position, obstacle_rect)
	else:
		var closest_point := _closest_point_to_rect(edge_position, obstacle_rect)
		var offset := edge_position - closest_point
		distance = offset.length()
		if distance > edge_contact_distance:
			return 0.0
		if distance <= 0.001:
			normal = -direction
		else:
			normal = offset / distance

	var pressure := 1.0
	if distance > 0.0:
		pressure = 1.0 - clampf(distance / edge_contact_distance, 0.0, 1.0)

	var radial_alignment := normal.dot(direction)
	if radial_alignment >= 0.0:
		return 0.0

	_impact_strength = maxf(_impact_strength, pressure * 0.45)
	return radial_alignment * pressure * obstacle_edge_force


func _limit_radius_against_obstacle(index: int, candidate_radius: float) -> float:
	if not obstacle_enabled:
		return candidate_radius

	var direction := _directions[index]
	var hit_distance: float = _ray_rect_entry_distance(global_position, direction, obstacle_rect)
	if hit_distance < 0.0:
		return candidate_radius

	var allowed_radius: float = maxf(0.0, hit_distance - membrane_obstacle_clearance)
	if candidate_radius <= allowed_radius:
		return candidate_radius

	return allowed_radius


func _ray_rect_entry_distance(origin: Vector2, direction: Vector2, rect: Rect2) -> float:
	var t_min := -INF
	var t_max := INF
	var rect_end := rect.position + rect.size

	if absf(direction.x) <= 0.0001:
		if origin.x < rect.position.x or origin.x > rect_end.x:
			return -1.0
	else:
		var tx_1 := (rect.position.x - origin.x) / direction.x
		var tx_2 := (rect_end.x - origin.x) / direction.x
		t_min = maxf(t_min, minf(tx_1, tx_2))
		t_max = minf(t_max, maxf(tx_1, tx_2))

	if absf(direction.y) <= 0.0001:
		if origin.y < rect.position.y or origin.y > rect_end.y:
			return -1.0
	else:
		var ty_1 := (rect.position.y - origin.y) / direction.y
		var ty_2 := (rect_end.y - origin.y) / direction.y
		t_min = maxf(t_min, minf(ty_1, ty_2))
		t_max = minf(t_max, maxf(ty_1, ty_2))

	if t_max < 0.0 or t_min > t_max:
		return -1.0
	return maxf(0.0, t_min)


func _average_radius() -> float:
	var total := 0.0
	for radius in _radii:
		total += radius
	return total / float(maxi(1, _radii.size()))


func _closest_point_to_rect(point: Vector2, rect: Rect2) -> Vector2:
	return Vector2(
		clampf(point.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(point.y, rect.position.y, rect.position.y + rect.size.y)
	)


func _normal_from_rect_inside(point: Vector2, rect: Rect2) -> Vector2:
	var left_distance: float = absf(point.x - rect.position.x)
	var right_distance: float = absf(rect.position.x + rect.size.x - point.x)
	var top_distance: float = absf(point.y - rect.position.y)
	var bottom_distance: float = absf(rect.position.y + rect.size.y - point.y)
	var min_distance: float = minf(minf(left_distance, right_distance), minf(top_distance, bottom_distance))

	if min_distance == left_distance:
		return Vector2.LEFT
	if min_distance == right_distance:
		return Vector2.RIGHT
	if min_distance == top_distance:
		return Vector2.UP
	return Vector2.DOWN
