class_name TestLabSlimeMembrane3D
extends Node3D

const CONTROL_POINT_HEIGHT: float = 0.18
const CURVE_CENTRIPETAL_ALPHA: float = 0.5
const CURVE_MIN_KNOT_SPACING: float = 0.0001
const CURVE_SAMPLES_PER_SEGMENT: int = 4
const MAX_DELTA: float = 0.033
const RING_HEIGHTS = [0.07, 0.20, 0.42, 0.66, 0.86, 1.01]
const RING_RADIUS_FACTORS = [0.84, 1.0, 0.96, 0.79, 0.54, 0.25]
const TOP_HEIGHT: float = 1.09

@export var base_radius: float = 0.76
@export var min_radius: float = 0.56
@export var max_radius: float = 1.02
@export var edge_stiffness: float = 56.0
@export var edge_damping: float = 8.0
@export var neighbor_smoothing: float = 30.0
@export var membrane_follow_stiffness: float = 40.0
@export var membrane_follow_damping: float = 7.0
@export var membrane_neighbor_smoothing: float = 19.0
@export var membrane_inertia: float = 0.28
@export var area_pressure: float = 38.0
@export var movement_push_amount: float = 0.15
@export var movement_squash_amount: float = 0.14
@export var breath_amount: float = 0.026
@export var breath_speed: float = 1.7
@export var surface_noise_amount: float = 0.018
@export var fire_push_amount: float = 0.16
@export var fire_impulse: float = 0.95
@export var fire_max_edge_speed: float = 2.4
@export var fire_rear_compression: float = 0.035
@export var fire_rear_wave_impulse: float = 0.38
@export var fire_shoulder_compression: float = 0.045
@export var fire_snap_amount: float = 0.72
@export var maximum_drive_speed: float = 4.8

var _control_points: Array[Marker3D] = []
var _directions: Array[Vector2] = []
var _drive_velocity: Vector2 = Vector2.ZERO
var _dynamic_mesh := ArrayMesh.new()
var _edge_offsets: Array[Vector2] = []
var _edge_velocities: Array[Vector2] = []
var _fire_sequence: int = 0
var _radial_velocities := PackedFloat32Array()
var _radii := PackedFloat32Array()
var _time: float = 0.0

@onready var _edge_rig: Node3D = get_node_or_null("EdgeRig") as Node3D
@onready var _outline_shell: MeshInstance3D = get_node_or_null("OutlineShell") as MeshInstance3D
@onready var _surface: MeshInstance3D = get_node_or_null("Surface") as MeshInstance3D


func _ready() -> void:
	_initialize_control_points()
	_rebuild_mesh()


func _physics_process(delta: float) -> void:
	if _control_points.size() < 4:
		return

	var safe_delta: float = minf(delta, MAX_DELTA)
	_time += safe_delta
	_update_control_points(safe_delta)
	_rebuild_mesh()


func control_point_count() -> int:
	return _control_points.size()


func deformation_amount() -> float:
	var largest_deformation: float = 0.0
	for index in range(_edge_offsets.size()):
		var rest_offset: Vector2 = _directions[index] * base_radius
		largest_deformation = maxf(largest_deformation, _edge_offsets[index].distance_to(rest_offset))
	return largest_deformation


func maximum_edge_speed() -> float:
	var maximum_speed: float = 0.0
	for edge_velocity in _edge_velocities:
		maximum_speed = maxf(maximum_speed, edge_velocity.length())
	return maximum_speed


func directional_extent(world_direction: Vector3) -> float:
	var local_direction: Vector2 = _world_direction_to_local_plane(world_direction)
	var extent: float = 0.0
	for edge_offset in _edge_offsets:
		extent = maxf(extent, edge_offset.dot(local_direction))
	return extent


func emit_surface_bud(world_direction: Vector3) -> Vector3:
	var local_direction: Vector2 = _world_direction_to_local_plane(world_direction)
	_push_membrane_for_fire(local_direction)
	_rebuild_mesh()
	var surface_distance: float = _surface_distance_for_direction(local_direction)
	return to_global(Vector3(local_direction.x * surface_distance, 0.60, local_direction.y * surface_distance))


func set_drive_velocity(world_velocity: Vector3) -> void:
	var local_velocity: Vector3 = global_basis.orthonormalized().inverse() * world_velocity
	_drive_velocity = Vector2(local_velocity.x, local_velocity.z)


func _append_triangle(indices: PackedInt32Array, first: int, second: int, third: int) -> void:
	indices.append(first)
	indices.append(second)
	indices.append(third)


func _average_radius() -> float:
	var total: float = 0.0
	for radius in _radii:
		total += radius
	return total / float(maxi(1, _radii.size()))


func _clamped_membrane_offset(candidate_offset: Vector2, fallback_direction: Vector2) -> Vector2:
	var distance: float = candidate_offset.length()
	var direction: Vector2 = fallback_direction
	if distance > 0.001:
		direction = candidate_offset / distance
	return direction * clampf(distance, min_radius * 0.82, max_radius + movement_push_amount)


func _curve_knot(previous_time: float, from_point: Vector2, to_point: Vector2) -> float:
	var point_distance: float = maxf(from_point.distance_to(to_point), CURVE_MIN_KNOT_SPACING)
	return previous_time + pow(point_distance, CURVE_CENTRIPETAL_ALPHA)


func _initialize_control_points() -> void:
	_control_points.clear()
	_directions.clear()
	_edge_offsets.clear()
	_edge_velocities.clear()
	if _edge_rig == null:
		push_error("[TestLabSlimeMembrane3D] EdgeRig is missing.")
		return

	for child in _edge_rig.get_children():
		if child is Marker3D:
			_control_points.append(child as Marker3D)

	if _control_points.size() < 4:
		push_error("[TestLabSlimeMembrane3D] At least four edge control points are required.")
		return

	_radii.resize(_control_points.size())
	_radial_velocities.resize(_control_points.size())
	for index in range(_control_points.size()):
		var ratio: float = float(index) / float(_control_points.size())
		var angle: float = ratio * TAU
		var direction := Vector2(cos(angle), sin(angle))
		var radius: float = base_radius + sin(angle * 3.0 + 0.35) * 0.028
		_directions.append(direction)
		_radii[index] = radius
		_radial_velocities[index] = 0.0
		_edge_offsets.append(direction * radius)
		_edge_velocities.append(Vector2.ZERO)
		_control_points[index].position = Vector3(direction.x * radius, CONTROL_POINT_HEIGHT, direction.y * radius)


func _interpolate_curve_point(
	from_point: Vector2,
	to_point: Vector2,
	from_time: float,
	to_time: float,
	sample_time: float
) -> Vector2:
	var time_span: float = to_time - from_time
	if time_span <= CURVE_MIN_KNOT_SPACING:
		return to_point
	var from_weight: float = (to_time - sample_time) / time_span
	var to_weight: float = (sample_time - from_time) / time_span
	return from_point * from_weight + to_point * to_weight


func _push_membrane_for_fire(local_direction: Vector2) -> void:
	var side_sign: float = 1.0 if _fire_sequence % 2 == 0 else -1.0
	_fire_sequence += 1
	var tangent := Vector2(-local_direction.y, local_direction.x)
	for index in range(_edge_offsets.size()):
		var rest_direction: Vector2 = _directions[index]
		var alignment: float = clampf(rest_direction.dot(local_direction), -1.0, 1.0)
		var front_weight: float = pow(maxf(alignment, 0.0), 4.0)
		var shoulder_weight: float = pow(maxf(1.0 - absf(alignment), 0.0), 4.0)
		var rear_weight: float = pow(maxf(-alignment, 0.0), 4.0)
		var sidedness: float = rest_direction.dot(tangent)
		var asymmetry: float = 1.0 + side_sign * sidedness * 0.08
		var rest_offset: Vector2 = rest_direction * _radii[index]
		var shot_target := (
			rest_offset
			+ local_direction * fire_push_amount * front_weight * asymmetry
			- rest_direction * fire_shoulder_compression * shoulder_weight
			- rest_direction * fire_rear_compression * rear_weight
		)
		var clamped_target: Vector2 = _clamped_membrane_offset(shot_target, rest_direction)
		_edge_offsets[index] = _edge_offsets[index].lerp(
			clamped_target,
			clampf(fire_snap_amount, 0.0, 1.0)
		)
		_edge_velocities[index] += (
			local_direction * fire_impulse * front_weight * asymmetry
			- rest_direction * fire_impulse * 0.32 * shoulder_weight
			+ rest_direction * fire_rear_wave_impulse * rear_weight
		)
		_edge_velocities[index] = _edge_velocities[index].limit_length(fire_max_edge_speed)


func _rebuild_mesh() -> void:
	if _surface == null or _outline_shell == null or _edge_offsets.size() < 4:
		return

	var boundary_points: PackedVector2Array = _smoothed_boundary_points()
	var boundary_count: int = boundary_points.size()
	var ring_count: int = RING_HEIGHTS.size()
	if boundary_count < 4 or ring_count < 2:
		return

	var ring_vertex_count: int = boundary_count * ring_count
	var top_vertex_index: int = ring_vertex_count
	var bottom_vertex_index: int = ring_vertex_count + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(ring_vertex_count + 2)
	normals.resize(ring_vertex_count + 2)
	uvs.resize(ring_vertex_count + 2)

	for ring_index in range(ring_count):
		var radius_factor: float = RING_RADIUS_FACTORS[ring_index]
		for point_index in range(boundary_count):
			var vertex_index: int = ring_index * boundary_count + point_index
			var boundary_point: Vector2 = boundary_points[point_index]
			var radial_variation: float = boundary_point.length() - base_radius
			vertices[vertex_index] = Vector3(
				boundary_point.x * radius_factor,
				RING_HEIGHTS[ring_index] + radial_variation * 0.08 * (1.0 - radius_factor),
				boundary_point.y * radius_factor
			)
			uvs[vertex_index] = Vector2(
				float(point_index) / float(boundary_count),
				float(ring_index + 1) / float(ring_count + 1)
			)

	vertices[top_vertex_index] = Vector3(0.0, TOP_HEIGHT + (_average_radius() - base_radius) * 0.16, 0.0)
	vertices[bottom_vertex_index] = Vector3(0.0, RING_HEIGHTS[0], 0.0)
	normals[top_vertex_index] = Vector3.UP
	normals[bottom_vertex_index] = Vector3.DOWN
	uvs[top_vertex_index] = Vector2(0.5, 0.0)
	uvs[bottom_vertex_index] = Vector2(0.5, 1.0)

	for ring_index in range(ring_count):
		var lower_ring: int = maxi(0, ring_index - 1)
		var upper_ring: int = mini(ring_count - 1, ring_index + 1)
		for point_index in range(boundary_count):
			var previous_point: int = posmod(point_index - 1, boundary_count)
			var next_point: int = (point_index + 1) % boundary_count
			var vertex_index: int = ring_index * boundary_count + point_index
			var around_tangent: Vector3 = (
				vertices[ring_index * boundary_count + next_point]
				- vertices[ring_index * boundary_count + previous_point]
			)
			var vertical_tangent: Vector3 = (
				vertices[upper_ring * boundary_count + point_index]
				- vertices[lower_ring * boundary_count + point_index]
			)
			var normal: Vector3 = vertical_tangent.cross(around_tangent).normalized()
			var radial_direction := Vector3(vertices[vertex_index].x, 0.0, vertices[vertex_index].z)
			if normal.dot(radial_direction) < 0.0:
				normal = -normal
			normals[vertex_index] = normal

	var indices := PackedInt32Array()
	for ring_index in range(ring_count - 1):
		for point_index in range(boundary_count):
			var next_point: int = (point_index + 1) % boundary_count
			var lower_current: int = ring_index * boundary_count + point_index
			var lower_next: int = ring_index * boundary_count + next_point
			var upper_current: int = (ring_index + 1) * boundary_count + point_index
			var upper_next: int = (ring_index + 1) * boundary_count + next_point
			_append_triangle(indices, lower_current, lower_next, upper_next)
			_append_triangle(indices, lower_current, upper_next, upper_current)

	var top_ring_offset: int = (ring_count - 1) * boundary_count
	for point_index in range(boundary_count):
		var next_point: int = (point_index + 1) % boundary_count
		_append_triangle(indices, top_ring_offset + point_index, top_ring_offset + next_point, top_vertex_index)
		_append_triangle(indices, point_index, bottom_vertex_index, next_point)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_dynamic_mesh.clear_surfaces()
	_dynamic_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_surface.mesh = _dynamic_mesh
	_outline_shell.mesh = _dynamic_mesh


func _sample_centripetal_catmull_rom(
	point_0: Vector2,
	point_1: Vector2,
	point_2: Vector2,
	point_3: Vector2,
	segment_ratio: float
) -> Vector2:
	var time_0: float = 0.0
	var time_1: float = _curve_knot(time_0, point_0, point_1)
	var time_2: float = _curve_knot(time_1, point_1, point_2)
	var time_3: float = _curve_knot(time_2, point_2, point_3)
	var sample_time: float = lerpf(time_1, time_2, segment_ratio)

	var point_a_1: Vector2 = _interpolate_curve_point(point_0, point_1, time_0, time_1, sample_time)
	var point_a_2: Vector2 = _interpolate_curve_point(point_1, point_2, time_1, time_2, sample_time)
	var point_a_3: Vector2 = _interpolate_curve_point(point_2, point_3, time_2, time_3, sample_time)
	var point_b_1: Vector2 = _interpolate_curve_point(point_a_1, point_a_2, time_0, time_2, sample_time)
	var point_b_2: Vector2 = _interpolate_curve_point(point_a_2, point_a_3, time_1, time_3, sample_time)
	return _interpolate_curve_point(point_b_1, point_b_2, time_1, time_2, sample_time)


func _smoothed_boundary_points() -> PackedVector2Array:
	var smoothed_points := PackedVector2Array()
	for index in range(_edge_offsets.size()):
		var previous_index: int = posmod(index - 1, _edge_offsets.size())
		var next_index: int = (index + 1) % _edge_offsets.size()
		var next_next_index: int = (index + 2) % _edge_offsets.size()
		for sample_index in range(CURVE_SAMPLES_PER_SEGMENT):
			smoothed_points.append(
				_sample_centripetal_catmull_rom(
					_edge_offsets[previous_index],
					_edge_offsets[index],
					_edge_offsets[next_index],
					_edge_offsets[next_next_index],
					float(sample_index) / float(CURVE_SAMPLES_PER_SEGMENT)
				)
			)
	return smoothed_points


func _surface_distance_for_direction(local_direction: Vector2) -> float:
	var best_projection: float = base_radius
	for edge_offset in _edge_offsets:
		best_projection = maxf(best_projection, edge_offset.dot(local_direction))
	return best_projection


func _update_control_points(delta: float) -> void:
	var average_radius: float = _average_radius()
	var pressure_force: float = (base_radius - average_radius) * area_pressure
	var next_radii := PackedFloat32Array(_radii)
	for index in range(_radii.size()):
		var previous_index: int = posmod(index - 1, _radii.size())
		var next_index: int = (index + 1) % _radii.size()
		var neighbor_average: float = (_radii[previous_index] + _radii[next_index]) * 0.5
		var ratio: float = float(index) / float(_radii.size())
		var breath: float = sin(_time * breath_speed + ratio * TAU * 2.0) * breath_amount
		var ripple: float = sin(_time * 2.1 + ratio * TAU * 7.0) * surface_noise_amount
		var target_radius: float = base_radius + breath + ripple
		var acceleration: float = (
			(target_radius - _radii[index]) * edge_stiffness
			+ (neighbor_average - _radii[index]) * neighbor_smoothing
			+ pressure_force
		)
		_radial_velocities[index] += acceleration * delta
		_radial_velocities[index] *= maxf(0.0, 1.0 - edge_damping * delta)
		next_radii[index] = clampf(
			_radii[index] + _radial_velocities[index] * delta,
			min_radius,
			max_radius
		)
	_radii = next_radii

	var drive_speed: float = _drive_velocity.length()
	var drive_direction: Vector2 = Vector2.ZERO
	if drive_speed > 0.001:
		drive_direction = _drive_velocity / drive_speed
	var drive_ratio: float = clampf(drive_speed / maxf(maximum_drive_speed, 0.001), 0.0, 1.0)
	var core_shift: Vector2 = _drive_velocity * delta * membrane_inertia
	var next_offsets: Array[Vector2] = []
	next_offsets.resize(_edge_offsets.size())

	for index in range(_edge_offsets.size()):
		_edge_offsets[index] -= core_shift
		var previous_index: int = posmod(index - 1, _edge_offsets.size())
		var next_index: int = (index + 1) % _edge_offsets.size()
		var direction: Vector2 = _directions[index]
		var alignment: float = direction.dot(drive_direction) if drive_direction != Vector2.ZERO else 0.0
		var side_alignment: float = 1.0 - absf(alignment)
		var squash: float = 1.0 + maxf(alignment, 0.0) * movement_squash_amount * drive_ratio
		squash -= side_alignment * movement_squash_amount * 0.45 * drive_ratio
		var target_offset: Vector2 = direction * _radii[index] * squash
		target_offset += drive_direction * maxf(alignment, 0.0) * movement_push_amount * drive_ratio

		var neighbor_average: Vector2 = (_edge_offsets[previous_index] + _edge_offsets[next_index]) * 0.5
		var spring_force: Vector2 = (target_offset - _edge_offsets[index]) * membrane_follow_stiffness
		var smoothing_force: Vector2 = (neighbor_average - _edge_offsets[index]) * membrane_neighbor_smoothing
		_edge_velocities[index] += (spring_force + smoothing_force) * delta
		_edge_velocities[index] *= maxf(0.0, 1.0 - membrane_follow_damping * delta)
		next_offsets[index] = _clamped_membrane_offset(
			_edge_offsets[index] + _edge_velocities[index] * delta,
			direction
		)
	_edge_offsets = next_offsets

	for index in range(_control_points.size()):
		var edge_offset: Vector2 = _edge_offsets[index]
		var height_wave: float = sin(_time * 2.4 + float(index) * 0.73) * 0.012
		_control_points[index].position = Vector3(edge_offset.x, CONTROL_POINT_HEIGHT + height_wave, edge_offset.y)


func _world_direction_to_local_plane(world_direction: Vector3) -> Vector2:
	var flat_world_direction := Vector3(world_direction.x, 0.0, world_direction.z).normalized()
	if flat_world_direction.length_squared() <= 0.0001:
		flat_world_direction = Vector3.FORWARD
	var local_direction_3d: Vector3 = global_basis.orthonormalized().inverse() * flat_world_direction
	var local_direction := Vector2(local_direction_3d.x, local_direction_3d.z)
	if local_direction.length_squared() <= 0.0001:
		return Vector2(0.0, -1.0)
	return local_direction.normalized()
