class_name TestLabSoftBodyCell
extends Node2D

@export_range(16, 128, 1) var point_count: int = 64
@export var base_radius: float = 92.0
@export var min_radius: float = 56.0
@export var max_radius: float = 126.0
@export var core_collision_radius: float = 58.0
@export var follow_strength: float = 3.2
@export var follow_response: float = 8.0
@export var max_speed: float = 340.0
@export var edge_stiffness: float = 58.0
@export var edge_damping: float = 8.5
@export var neighbor_smoothing: float = 34.0
@export var area_pressure: float = 42.0
@export var obstacle_edge_force: float = 1280.0
@export var edge_contact_distance: float = 34.0
@export var breath_amount: float = 4.0
@export var breath_speed: float = 1.4
@export var surface_noise_amount: float = 3.2

var obstacle_rect: Rect2 = Rect2()
var obstacle_enabled: bool = false
var target_position: Vector2 = Vector2.ZERO

var _directions: Array[Vector2] = []
var _radii: PackedFloat32Array = PackedFloat32Array()
var _radial_velocities: PackedFloat32Array = PackedFloat32Array()
var _velocity: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _impact_strength: float = 0.0


func _ready() -> void:
	_initialize_edge_points()
	target_position = global_position


func _physics_process(delta: float) -> void:
	var safe_delta: float = min(delta, 0.033)
	_time += safe_delta
	_update_body_motion(safe_delta)
	_update_edge_points(safe_delta)
	_impact_strength = max(0.0, _impact_strength - safe_delta * 2.2)
	queue_redraw()


func set_follow_target(new_target_position: Vector2) -> void:
	target_position = new_target_position


func set_obstacle_rect(new_obstacle_rect: Rect2) -> void:
	obstacle_rect = new_obstacle_rect
	obstacle_enabled = obstacle_rect.size.x > 0.0 and obstacle_rect.size.y > 0.0


func _draw() -> void:
	if _directions.is_empty():
		return

	var membrane_points := PackedVector2Array()
	for index in range(point_count):
		membrane_points.append(_directions[index] * _radii[index])

	var closed_points := PackedVector2Array(membrane_points)
	closed_points.append(membrane_points[0])

	var fill_color := Color(0.42, 0.86, 0.70, 0.42 + _impact_strength * 0.22)
	var membrane_color := Color(0.75, 1.0, 0.86, 0.92)
	var contact_color := Color(1.0, 0.82, 0.42, 0.58)

	draw_colored_polygon(membrane_points, fill_color)
	draw_polyline(closed_points, membrane_color, 5.0, true)
	draw_polyline(closed_points, contact_color, 1.5 + _impact_strength * 3.0, true)
	draw_circle(Vector2.ZERO, base_radius * 0.42, Color(0.21, 0.44, 0.54, 0.45))
	draw_arc(Vector2.ZERO, base_radius * 0.42, 0.0, TAU, 48, Color(0.72, 1.0, 0.94, 0.42), 2.0, true)

	for index in range(0, point_count, 8):
		draw_circle(_directions[index] * _radii[index], 3.0, Color(1.0, 0.94, 0.64, 0.72))


func _initialize_edge_points() -> void:
	_directions.clear()
	_radii.resize(point_count)
	_radial_velocities.resize(point_count)

	for index in range(point_count):
		var ratio := float(index) / float(point_count)
		var angle := ratio * TAU
		var direction := Vector2(cos(angle), sin(angle))
		_directions.append(direction)
		_radii[index] = base_radius + sin(angle * 3.0) * 2.0
		_radial_velocities[index] = 0.0


func _update_body_motion(delta: float) -> void:
	var to_target := target_position - global_position
	var desired_velocity := to_target * follow_strength
	if desired_velocity.length() > max_speed:
		desired_velocity = desired_velocity.normalized() * max_speed

	var response := 1.0 - exp(-follow_response * delta)
	_velocity = _velocity.lerp(desired_velocity, response)
	global_position += _velocity * delta
	_resolve_core_obstacle()


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

	_impact_strength = max(_impact_strength, clamp(penetration / 42.0, 0.0, 1.0))


func _update_edge_points(delta: float) -> void:
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
		_radial_velocities[index] *= max(0.0, 1.0 - edge_damping * delta)
		next_radii[index] = clamp(_radii[index] + _radial_velocities[index] * delta, min_radius, max_radius)

	_radii = next_radii


func _obstacle_radial_force(index: int) -> float:
	if not obstacle_enabled:
		return 0.0

	var direction := _directions[index]
	var edge_position := global_position + direction * _radii[index]
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
		pressure = 1.0 - clamp(distance / edge_contact_distance, 0.0, 1.0)

	var radial_alignment := normal.dot(direction)
	if radial_alignment >= 0.0:
		return 0.0

	_impact_strength = max(_impact_strength, pressure * 0.45)
	return radial_alignment * pressure * obstacle_edge_force


func _average_radius() -> float:
	var total := 0.0
	for radius in _radii:
		total += radius
	return total / float(max(1, _radii.size()))


func _closest_point_to_rect(point: Vector2, rect: Rect2) -> Vector2:
	return Vector2(
		clamp(point.x, rect.position.x, rect.position.x + rect.size.x),
		clamp(point.y, rect.position.y, rect.position.y + rect.size.y)
	)


func _normal_from_rect_inside(point: Vector2, rect: Rect2) -> Vector2:
	var left_distance: float = abs(point.x - rect.position.x)
	var right_distance: float = abs(rect.position.x + rect.size.x - point.x)
	var top_distance: float = abs(point.y - rect.position.y)
	var bottom_distance: float = abs(rect.position.y + rect.size.y - point.y)
	var min_distance: float = min(min(left_distance, right_distance), min(top_distance, bottom_distance))

	if min_distance == left_distance:
		return Vector2.LEFT
	if min_distance == right_distance:
		return Vector2.RIGHT
	if min_distance == top_distance:
		return Vector2.UP
	return Vector2.DOWN
