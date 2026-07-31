class_name TestLabSlimeTombstone
extends Node3D

const CURVE_ALPHA: float = 0.5
const CURVE_MIN_KNOT_SPACING: float = 0.0001
const CURVE_SAMPLES_PER_SEGMENT: int = 3
const EXPECTED_CONTROL_POINT_COUNT: int = 18
const MAX_DELTA: float = 0.033
const SURFACE_SHADER_PATH: String = "res://shaders/slime_tombstone_surface.gdshader"
const WET_COAT_SHADER_PATH: String = "res://shaders/slime_tombstone_wet_coat.gdshader"
const OUTLINE_SHADER_PATH: String = "res://shaders/slime_tombstone_outline.gdshader"
const VISUAL_LAYER_COUNT: int = 3

@export var membrane_stiffness: float = 42.0
@export var membrane_damping: float = 7.2
@export var neighbor_stiffness: float = 20.0
@export var area_pressure: float = 28.0
@export var depth_stiffness: float = 48.0
@export var depth_damping: float = 7.8
@export var breath_amount: float = 0.018
@export var breath_speed: float = 1.45
@export var maximum_planar_offset: float = 0.52
@export var maximum_depth_offset: float = 0.24
@export var body_thickness: float = 0.48

var _anchor_weights: PackedFloat32Array = PackedFloat32Array()
var _center_depth: float = 0.0
var _center_depth_velocity: float = 0.0
var _control_points: Array[Marker3D] = []
var _depth_offsets: PackedFloat32Array = PackedFloat32Array()
var _depth_velocities: PackedFloat32Array = PackedFloat32Array()
var _dynamic_mesh: ArrayMesh = ArrayMesh.new()
var _points: Array[Vector2] = []
var _rest_area: float = 0.0
var _rest_center: Vector2 = Vector2.ZERO
var _rest_points: Array[Vector2] = []
var _time: float = 0.0
var _velocities: Array[Vector2] = []

@onready var _edge_rig: Node3D = get_node_or_null("EdgeRig") as Node3D
@onready var _face_mark: Label3D = get_node_or_null("FaceMark") as Label3D
@onready var _outline_shell: MeshInstance3D = get_node_or_null("OutlineShell") as MeshInstance3D
@onready var _surface: MeshInstance3D = get_node_or_null("Surface") as MeshInstance3D
@onready var _wet_coat: MeshInstance3D = get_node_or_null("WetCoat") as MeshInstance3D


func _ready() -> void:
	_initialize_control_points()
	_assign_materials()
	_rebuild_mesh()
	_update_face_mark()


func _physics_process(delta: float) -> void:
	if _points.size() < 4:
		return

	var safe_delta: float = minf(delta, MAX_DELTA)
	_time += safe_delta
	_update_membrane(safe_delta)
	_rebuild_mesh()
	_update_face_mark()
	_update_material_state()


func apply_poke(local_hit: Vector2, strength: float = 1.0) -> void:
	if _points.is_empty():
		return

	var safe_strength: float = clampf(strength, 0.0, 2.0)
	var inward_direction: Vector2 = (_rest_center - local_hit).normalized()
	if inward_direction.length_squared() <= 0.0001:
		inward_direction = Vector2(0.0, -1.0)
	for index in range(_points.size()):
		var distance: float = _rest_points[index].distance_to(local_hit)
		var weight: float = 1.0 - smoothstep(0.25, 2.25, distance)
		weight *= _anchor_weights[index]
		if weight <= 0.0:
			continue
		var outward_normal: Vector2 = _rest_outward_normal(index)
		_velocities[index] += (
			inward_direction * 2.35
			+ outward_normal * 0.34
		) * weight * safe_strength
		_depth_velocities[index] -= 1.55 * weight * safe_strength
	_center_depth_velocity -= 0.72 * safe_strength
	_rebuild_mesh()


func apply_squash(strength: float = 1.0) -> void:
	var safe_strength: float = clampf(strength, 0.0, 2.0)
	var bottom: float = _minimum_rest_y()
	var height: float = maxf(0.001, _maximum_rest_y() - bottom)
	for index in range(_points.size()):
		var vertical_ratio: float = clampf((_rest_points[index].y - bottom) / height, 0.0, 1.0)
		var side_sign: float = signf(_rest_points[index].x)
		_velocities[index].x += side_sign * (0.38 + vertical_ratio * 0.62) * safe_strength
		_velocities[index].y -= (0.62 + vertical_ratio * 1.35) * _anchor_weights[index] * safe_strength
		_depth_velocities[index] += sin(float(index) * 1.77) * 0.22 * safe_strength
	_center_depth_velocity += 0.42 * safe_strength
	_rebuild_mesh()


func reset_immediately() -> void:
	if _rest_points.is_empty():
		return

	_points = _rest_points.duplicate()
	_velocities.clear()
	_depth_offsets.resize(_rest_points.size())
	_depth_velocities.resize(_rest_points.size())
	for index in range(_rest_points.size()):
		_velocities.append(Vector2.ZERO)
		_depth_offsets[index] = 0.0
		_depth_velocities[index] = 0.0
		_control_points[index].position = Vector3(
			_rest_points[index].x,
			_rest_points[index].y,
			0.0
		)
	_center_depth = 0.0
	_center_depth_velocity = 0.0
	_rebuild_mesh()
	_update_face_mark()
	_update_material_state()


func control_point_count() -> int:
	return _control_points.size()


func deformation_amount() -> float:
	var largest_deformation: float = 0.0
	for index in range(_points.size()):
		largest_deformation = maxf(
			largest_deformation,
			_points[index].distance_to(_rest_points[index])
		)
		largest_deformation = maxf(largest_deformation, absf(_depth_offsets[index]))
	return largest_deformation


func anchored_deformation_amount() -> float:
	var largest_deformation: float = 0.0
	for index in range(_points.size()):
		if _anchor_weights[index] > 0.20:
			continue
		largest_deformation = maxf(
			largest_deformation,
			_points[index].distance_to(_rest_points[index])
		)
	return largest_deformation


func current_area_ratio() -> float:
	if _rest_area <= 0.0001:
		return 0.0
	return absf(_signed_area(_points)) / _rest_area


func silhouette_size() -> Vector2:
	if _points.is_empty():
		return Vector2.ZERO

	var minimum := _points[0]
	var maximum := _points[0]
	for point in _points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return maximum - minimum


func visual_layer_count() -> int:
	return VISUAL_LAYER_COUNT


func visual_layers_share_mesh() -> bool:
	if _surface == null or _wet_coat == null or _outline_shell == null:
		return false
	return (
		_surface.mesh == _dynamic_mesh
		and _wet_coat.mesh == _dynamic_mesh
		and _outline_shell.mesh == _dynamic_mesh
	)


func _append_triangle(
	indices: PackedInt32Array,
	first: int,
	second: int,
	third: int
) -> void:
	indices.append(first)
	indices.append(second)
	indices.append(third)


func _append_vertex(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	vertex: Vector3,
	normal: Vector3,
	uv: Vector2
) -> int:
	var index: int = vertices.size()
	vertices.append(vertex)
	normals.append(normal)
	uvs.append(uv)
	return index


func _assign_materials() -> void:
	if _surface != null:
		_surface.material_override = _shader_material(SURFACE_SHADER_PATH)
	if _wet_coat != null:
		_wet_coat.material_override = _shader_material(WET_COAT_SHADER_PATH)
	if _outline_shell != null:
		_outline_shell.material_override = _shader_material(OUTLINE_SHADER_PATH)


func _average_depth_offset() -> float:
	if _depth_offsets.is_empty():
		return 0.0
	var total: float = 0.0
	for depth_offset in _depth_offsets:
		total += depth_offset
	return total / float(_depth_offsets.size())


func _average_point(points: Array[Vector2]) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var average := Vector2.ZERO
	for point in points:
		average += point
	return average / float(points.size())


func _curve_knot(previous_time: float, from_point: Vector2, to_point: Vector2) -> float:
	var point_distance: float = maxf(from_point.distance_to(to_point), CURVE_MIN_KNOT_SPACING)
	return previous_time + pow(point_distance, CURVE_ALPHA)


func _initialize_control_points() -> void:
	_control_points.clear()
	_rest_points.clear()
	_points.clear()
	_velocities.clear()
	if _edge_rig == null:
		push_error("[TestLabSlimeTombstone] EdgeRig is missing.")
		return

	for child in _edge_rig.get_children():
		if child is Marker3D:
			var marker := child as Marker3D
			_control_points.append(marker)
			_rest_points.append(Vector2(marker.position.x, marker.position.y))

	if _control_points.size() != EXPECTED_CONTROL_POINT_COUNT:
		push_error(
			"[TestLabSlimeTombstone] Expected %d control points, got %d."
			% [EXPECTED_CONTROL_POINT_COUNT, _control_points.size()]
		)
		return

	_points = _rest_points.duplicate()
	_rest_center = _average_point(_rest_points)
	_rest_area = absf(_signed_area(_rest_points))
	_anchor_weights.resize(_rest_points.size())
	_depth_offsets.resize(_rest_points.size())
	_depth_velocities.resize(_rest_points.size())
	var minimum_y: float = _minimum_rest_y()
	for index in range(_rest_points.size()):
		var height_from_base: float = _rest_points[index].y - minimum_y
		_anchor_weights[index] = smoothstep(0.04, 1.15, height_from_base)
		_depth_offsets[index] = 0.0
		_depth_velocities[index] = 0.0
		_velocities.append(Vector2.ZERO)


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


func _maximum_rest_y() -> float:
	var maximum: float = -INF
	for point in _rest_points:
		maximum = maxf(maximum, point.y)
	return maximum


func _minimum_rest_y() -> float:
	var minimum: float = INF
	for point in _rest_points:
		minimum = minf(minimum, point.y)
	return minimum


func _point_bounds(points: Array[Vector2]) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _rebuild_mesh() -> void:
	if _surface == null or _wet_coat == null or _outline_shell == null:
		return

	var boundary_points: PackedVector2Array = _smoothed_boundary_points()
	var boundary_depths: PackedFloat32Array = _smoothed_boundary_depths()
	var boundary_count: int = boundary_points.size()
	if boundary_count < 4:
		return

	var center: Vector2 = _average_point(_points)
	var half_thickness: float = body_thickness * 0.5
	var average_depth: float = _average_depth_offset()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var bounds: Rect2 = _point_bounds(_points)
	var safe_width: float = maxf(bounds.size.x, 0.001)
	var safe_height: float = maxf(bounds.size.y, 0.001)

	var front_center_index: int = _append_vertex(
		vertices,
		normals,
		uvs,
		Vector3(center.x, center.y, half_thickness + 0.12 + _center_depth + average_depth * 0.35),
		Vector3.FORWARD,
		Vector2(
			(center.x - bounds.position.x) / safe_width,
			1.0 - (center.y - bounds.position.y) / safe_height
		)
	)
	var front_inner_start: int = vertices.size()
	for index in range(boundary_count):
		var boundary_point: Vector2 = boundary_points[index]
		var inner_point: Vector2 = center.lerp(boundary_point, 0.58)
		var inner_depth: float = lerpf(_center_depth, boundary_depths[index], 0.62)
		_append_vertex(
			vertices,
			normals,
			uvs,
			Vector3(inner_point.x, inner_point.y, half_thickness + 0.08 + inner_depth),
			Vector3.FORWARD,
			Vector2(
				(inner_point.x - bounds.position.x) / safe_width,
				1.0 - (inner_point.y - bounds.position.y) / safe_height
			)
		)
	var front_outer_start: int = vertices.size()
	for index in range(boundary_count):
		var boundary_point: Vector2 = boundary_points[index]
		var outward_normal: Vector2 = _boundary_outward_normal(boundary_points, index)
		_append_vertex(
			vertices,
			normals,
			uvs,
			Vector3(boundary_point.x, boundary_point.y, half_thickness + boundary_depths[index]),
			Vector3(outward_normal.x * 0.18, outward_normal.y * 0.18, 0.968).normalized(),
			Vector2(
				(boundary_point.x - bounds.position.x) / safe_width,
				1.0 - (boundary_point.y - bounds.position.y) / safe_height
			)
		)

	for index in range(boundary_count):
		var next_index: int = (index + 1) % boundary_count
		_append_triangle(
			indices,
			front_center_index,
			front_inner_start + next_index,
			front_inner_start + index
		)
		_append_triangle(
			indices,
			front_inner_start + index,
			front_inner_start + next_index,
			front_outer_start + next_index
		)
		_append_triangle(
			indices,
			front_inner_start + index,
			front_outer_start + next_index,
			front_outer_start + index
		)

	var back_center_index: int = _append_vertex(
		vertices,
		normals,
		uvs,
		Vector3(center.x, center.y, -half_thickness - average_depth * 0.10),
		Vector3.BACK,
		Vector2(0.5, 0.5)
	)
	var back_outer_start: int = vertices.size()
	for index in range(boundary_count):
		var boundary_point: Vector2 = boundary_points[index]
		_append_vertex(
			vertices,
			normals,
			uvs,
			Vector3(boundary_point.x, boundary_point.y, -half_thickness - boundary_depths[index] * 0.10),
			Vector3.BACK,
			Vector2(
				(boundary_point.x - bounds.position.x) / safe_width,
				1.0 - (boundary_point.y - bounds.position.y) / safe_height
			)
		)
	for index in range(boundary_count):
		var next_index: int = (index + 1) % boundary_count
		_append_triangle(
			indices,
			back_center_index,
			back_outer_start + index,
			back_outer_start + next_index
		)

	for index in range(boundary_count):
		var next_index: int = (index + 1) % boundary_count
		var current_point: Vector2 = boundary_points[index]
		var next_point: Vector2 = boundary_points[next_index]
		var outward_normal: Vector2 = _boundary_outward_normal(boundary_points, index)
		var side_normal := Vector3(outward_normal.x, outward_normal.y, 0.0)
		var side_start: int = vertices.size()
		_append_vertex(
			vertices,
			normals,
			uvs,
			Vector3(current_point.x, current_point.y, half_thickness + boundary_depths[index]),
			side_normal,
			Vector2(float(index) / float(boundary_count), 0.0)
		)
		_append_vertex(
			vertices,
			normals,
			uvs,
			Vector3(next_point.x, next_point.y, half_thickness + boundary_depths[next_index]),
			side_normal,
			Vector2(float(next_index) / float(boundary_count), 0.0)
		)
		_append_vertex(
			vertices,
			normals,
			uvs,
			Vector3(next_point.x, next_point.y, -half_thickness - boundary_depths[next_index] * 0.10),
			side_normal,
			Vector2(float(next_index) / float(boundary_count), 1.0)
		)
		_append_vertex(
			vertices,
			normals,
			uvs,
			Vector3(current_point.x, current_point.y, -half_thickness - boundary_depths[index] * 0.10),
			side_normal,
			Vector2(float(index) / float(boundary_count), 1.0)
		)
		_append_triangle(indices, side_start, side_start + 1, side_start + 3)
		_append_triangle(indices, side_start + 1, side_start + 2, side_start + 3)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_dynamic_mesh.clear_surfaces()
	_dynamic_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_surface.mesh = _dynamic_mesh
	_wet_coat.mesh = _dynamic_mesh
	_outline_shell.mesh = _dynamic_mesh


func _rest_outward_normal(index: int) -> Vector2:
	var previous_index: int = posmod(index - 1, _rest_points.size())
	var next_index: int = (index + 1) % _rest_points.size()
	var tangent: Vector2 = _rest_points[next_index] - _rest_points[previous_index]
	var normal := Vector2(-tangent.y, tangent.x)
	if normal.length_squared() <= 0.0001:
		return Vector2.LEFT
	return normal.normalized()


func _sample_curve(
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


func _shader_material(shader_path: String) -> ShaderMaterial:
	var shader := load(shader_path) as Shader
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _signed_area(points: Array[Vector2]) -> float:
	if points.size() < 3:
		return 0.0
	var area: float = 0.0
	for index in range(points.size()):
		var next_index: int = (index + 1) % points.size()
		area += points[index].cross(points[next_index])
	return area * 0.5


func _smoothed_boundary_depths() -> PackedFloat32Array:
	var depths := PackedFloat32Array()
	for index in range(_depth_offsets.size()):
		var next_index: int = (index + 1) % _depth_offsets.size()
		for sample_index in range(CURVE_SAMPLES_PER_SEGMENT):
			var ratio: float = float(sample_index) / float(CURVE_SAMPLES_PER_SEGMENT)
			depths.append(lerpf(_depth_offsets[index], _depth_offsets[next_index], ratio))
	return depths


func _smoothed_boundary_points() -> PackedVector2Array:
	var smoothed_points := PackedVector2Array()
	for index in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var next_next_index: int = (index + 2) % _points.size()
		for sample_index in range(CURVE_SAMPLES_PER_SEGMENT):
			smoothed_points.append(
				_sample_curve(
					_points[previous_index],
					_points[index],
					_points[next_index],
					_points[next_next_index],
					float(sample_index) / float(CURVE_SAMPLES_PER_SEGMENT)
				)
			)
	return smoothed_points


func _update_face_mark() -> void:
	if _face_mark == null or _points.is_empty():
		return
	var bounds: Rect2 = _point_bounds(_points)
	var center: Vector2 = bounds.get_center()
	var width_ratio: float = clampf(bounds.size.x / 2.60, 0.82, 1.18)
	var height_ratio: float = clampf(bounds.size.y / 4.38, 0.82, 1.14)
	_face_mark.position = Vector3(
		center.x * 0.22,
		bounds.position.y + bounds.size.y * 0.55,
		body_thickness * 0.5 + 0.105 + _center_depth * 0.56
	)
	_face_mark.scale = Vector3(width_ratio, height_ratio, 1.0)


func _update_material_state() -> void:
	var pulse: float = clampf(
		deformation_amount() * 1.4 + absf(_center_depth) * 2.2,
		0.0,
		1.0
	)
	for mesh_instance in [_surface, _wet_coat]:
		if mesh_instance == null or not mesh_instance.material_override is ShaderMaterial:
			continue
		var material := mesh_instance.material_override as ShaderMaterial
		material.set_shader_parameter(&"pulse", pulse)


func _update_membrane(delta: float) -> void:
	var area_ratio: float = current_area_ratio()
	var pressure: float = (1.0 - area_ratio) * area_pressure
	var next_points: Array[Vector2] = []
	next_points.resize(_points.size())
	var next_depths := PackedFloat32Array(_depth_offsets)

	for index in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var mobility: float = _anchor_weights[index]
		var outward_normal: Vector2 = _rest_outward_normal(index)
		var phase: float = _time * breath_speed + float(index) * 0.61
		var target: Vector2 = _rest_points[index]
		target += outward_normal * sin(phase) * breath_amount * mobility
		var previous_shape_target: Vector2 = (
			_points[previous_index]
			+ (_rest_points[index] - _rest_points[previous_index])
		)
		var next_shape_target: Vector2 = (
			_points[next_index]
			+ (_rest_points[index] - _rest_points[next_index])
		)
		var shape_target: Vector2 = (previous_shape_target + next_shape_target) * 0.5
		var spring_force: Vector2 = (target - _points[index]) * membrane_stiffness
		var shape_force: Vector2 = (shape_target - _points[index]) * neighbor_stiffness
		var pressure_force: Vector2 = outward_normal * pressure * mobility
		_velocities[index] += (spring_force + shape_force + pressure_force) * delta
		_velocities[index] *= maxf(0.0, 1.0 - membrane_damping * delta)
		var candidate: Vector2 = _points[index] + _velocities[index] * delta
		var maximum_offset: float = maximum_planar_offset * lerpf(0.12, 1.0, mobility)
		var offset: Vector2 = (candidate - _rest_points[index]).limit_length(maximum_offset)
		next_points[index] = _rest_points[index] + offset

		var neighbor_depth: float = (
			_depth_offsets[previous_index]
			+ _depth_offsets[next_index]
		) * 0.5
		var target_depth: float = sin(phase * 0.84) * breath_amount * 0.35 * mobility
		var depth_force: float = (
			(target_depth - _depth_offsets[index]) * depth_stiffness
			+ (neighbor_depth - _depth_offsets[index]) * neighbor_stiffness
		)
		_depth_velocities[index] += depth_force * delta
		_depth_velocities[index] *= maxf(0.0, 1.0 - depth_damping * delta)
		next_depths[index] = clampf(
			_depth_offsets[index] + _depth_velocities[index] * delta,
			-maximum_depth_offset,
			maximum_depth_offset
		)

	_points = next_points
	_depth_offsets = next_depths
	_center_depth_velocity += -_center_depth * depth_stiffness * 0.72 * delta
	_center_depth_velocity *= maxf(0.0, 1.0 - depth_damping * delta)
	_center_depth = clampf(
		_center_depth + _center_depth_velocity * delta,
		-maximum_depth_offset,
		maximum_depth_offset
	)

	for index in range(_control_points.size()):
		_control_points[index].position = Vector3(
			_points[index].x,
			_points[index].y,
			_depth_offsets[index]
		)


func _boundary_outward_normal(points: PackedVector2Array, index: int) -> Vector2:
	var previous_index: int = posmod(index - 1, points.size())
	var next_index: int = (index + 1) % points.size()
	var tangent: Vector2 = points[next_index] - points[previous_index]
	var normal := Vector2(-tangent.y, tangent.x)
	if normal.length_squared() <= 0.0001:
		return Vector2.LEFT
	return normal.normalized()
