class_name TestLabSlimeCross2D
extends Node2D

const RENDER_SAMPLES_PER_CORNER: int = 5
const REST_OUTLINE: Array[Vector2] = [
	Vector2(-30.0, -230.0),
	Vector2(30.0, -230.0),
	Vector2(40.0, -220.0),
	Vector2(40.0, -145.0),
	Vector2(118.0, -145.0),
	Vector2(132.0, -132.0),
	Vector2(132.0, -72.0),
	Vector2(118.0, -58.0),
	Vector2(42.0, -58.0),
	Vector2(42.0, 205.0),
	Vector2(30.0, 220.0),
	Vector2(-30.0, 220.0),
	Vector2(-42.0, 205.0),
	Vector2(-42.0, -58.0),
	Vector2(-118.0, -58.0),
	Vector2(-132.0, -72.0),
	Vector2(-132.0, -132.0),
	Vector2(-118.0, -145.0),
	Vector2(-40.0, -145.0),
	Vector2(-40.0, -220.0),
]
const BUBBLE_REST_POSITIONS: Array[Vector2] = [
	Vector2(-9.0, -190.0),
	Vector2(11.0, -112.0),
	Vector2(-78.0, -103.0),
	Vector2(76.0, -94.0),
	Vector2(-8.0, -8.0),
	Vector2(13.0, 76.0),
	Vector2(-12.0, 158.0),
]

@export var membrane_stiffness: float = 54.0
@export var membrane_damping: float = 8.2
@export var neighbor_stiffness: float = 32.0
@export var area_pressure: float = 2500.0
@export var breath_amount: float = 1.8
@export var breath_speed: float = 1.45
@export var maximum_offset: float = 52.0
@export var maximum_point_speed: float = 620.0
@export var poke_impulse: float = 590.0
@export_range(0.0, 0.5, 0.01) var velocity_spread: float = 0.34
@export_range(0.0, 0.5, 0.01) var displacement_smoothing: float = 0.20
@export_range(0.05, 0.45, 0.01) var corner_rounding: float = 0.28

var _points: Array[Vector2] = []
var _rest_points: Array[Vector2] = []
var _velocities: Array[Vector2] = []
var _rest_normals: Array[Vector2] = []
var _rest_area: float = 1.0
var _time: float = 0.0
var _impact_strength: float = 0.0
var _impact_index: int = -1
var _debug_rig_enabled: bool = true


func _ready() -> void:
	_initialize_membrane()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _points.is_empty():
		return
	var safe_delta: float = minf(delta, 0.033)
	_time += safe_delta
	_update_membrane(safe_delta)
	_impact_strength = move_toward(_impact_strength, 0.0, safe_delta * 1.7)
	queue_redraw()


func _draw() -> void:
	if _points.is_empty():
		return
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	var closed_boundary := PackedVector2Array(boundary)
	closed_boundary.append(boundary[0])
	var fill_boundary := PackedVector2Array(_points)
	var center: Vector2 = _polygon_centroid(_points)

	draw_set_transform(Vector2(15.0, 19.0), 0.0, Vector2.ONE)
	_draw_triangulated_polygon(fill_boundary, Color(0.005, 0.015, 0.024, 0.72))
	draw_polyline(closed_boundary, Color(0.005, 0.015, 0.024, 0.58), 26.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_polyline(closed_boundary, Color(0.02, 0.16, 0.18, 0.34), 34.0, true)
	_draw_triangulated_polygon(fill_boundary, Color(0.018, 0.095, 0.105, 1.0))
	draw_polyline(closed_boundary, Color(0.015, 0.055, 0.065, 1.0), 16.0, true)

	var body_boundary: PackedVector2Array = _scaled_polygon(fill_boundary, center, 0.965)
	_draw_triangulated_polygon(body_boundary, Color(0.18, 0.82, 0.63, 0.96))
	draw_polyline(closed_boundary, Color(0.18, 0.82, 0.63, 0.96), 9.0, true)

	var inner_boundary: PackedVector2Array = _scaled_polygon(fill_boundary, center, 0.80)
	for index in range(inner_boundary.size()):
		inner_boundary[index] += Vector2(0.0, 8.0)
	_draw_triangulated_polygon(inner_boundary, Color(0.035, 0.34, 0.35, 0.70))

	var core_boundary: PackedVector2Array = _scaled_polygon(fill_boundary, center, 0.61)
	for index in range(core_boundary.size()):
		core_boundary[index] += Vector2(4.0, 17.0)
	_draw_triangulated_polygon(core_boundary, Color(0.025, 0.21, 0.29, 0.46))

	draw_polyline(closed_boundary, Color(0.58, 1.0, 0.84, 0.92), 5.0, true)
	_draw_wet_highlights()
	_draw_bubbles()
	_draw_impact_ripple()
	_draw_debug_rig()


func apply_poke(local_hit: Vector2, strength: float = 1.0) -> void:
	if _points.is_empty():
		return
	var nearest_index: int = _nearest_point_index(local_hit)
	var inward: Vector2 = (_polygon_centroid(_points) - local_hit).normalized()
	if inward.length_squared() <= 0.0001:
		inward = -_rest_normals[nearest_index]
	for offset in range(-2, 3):
		var index: int = posmod(nearest_index + offset, _points.size())
		var weight: float = 1.0 - absf(float(offset)) / 3.0
		_velocities[index] += inward * poke_impulse * strength * weight
	_impact_index = nearest_index
	_impact_strength = clampf(0.55 + strength * 0.45, 0.0, 1.4)


func apply_squash(strength: float = 1.0) -> void:
	if _points.is_empty():
		return
	var center: Vector2 = _polygon_centroid(_points)
	for index in range(_points.size()):
		var offset: Vector2 = _points[index] - center
		var horizontal_sign: float = signf(offset.x)
		var vertical_sign: float = signf(offset.y)
		_velocities[index].x += horizontal_sign * 165.0 * strength
		_velocities[index].y -= vertical_sign * 390.0 * strength
	_impact_index = 0
	_impact_strength = clampf(0.7 + strength * 0.35, 0.0, 1.4)


func reset_immediately() -> void:
	_points = _rest_points.duplicate()
	_velocities.clear()
	for _index in range(_rest_points.size()):
		_velocities.append(Vector2.ZERO)
	_impact_index = -1
	_impact_strength = 0.0
	queue_redraw()


func set_debug_rig_enabled(enabled: bool) -> void:
	_debug_rig_enabled = enabled
	queue_redraw()


func toggle_debug_rig() -> void:
	set_debug_rig_enabled(not _debug_rig_enabled)


func debug_rig_enabled() -> bool:
	return _debug_rig_enabled


func control_point_count() -> int:
	return _points.size()


func concave_corner_count() -> int:
	return _count_concave_corners(_rest_points)


func current_area_ratio() -> float:
	if _rest_area <= 0.001:
		return 1.0
	return absf(_signed_area(_points)) / _rest_area


func deformation_amount() -> float:
	if _points.is_empty():
		return 0.0
	var total: float = 0.0
	for index in range(_points.size()):
		total += _points[index].distance_to(_rest_points[index])
	return total / float(_points.size())


func silhouette_size() -> Vector2:
	return _point_bounds(_points).size


func arm_span() -> float:
	if _points.size() != REST_OUTLINE.size():
		return 0.0
	return _points[5].distance_to(_points[16])


func stem_width() -> float:
	if _points.size() != REST_OUTLINE.size():
		return 0.0
	return (
		absf(_points[9].x - _points[12].x)
		+ absf(_points[2].x - _points[19].x)
	) * 0.5


func notch_clearance() -> float:
	if _points.size() != REST_OUTLINE.size():
		return 0.0
	var right_top: float = _points[4].x - _points[3].x
	var right_bottom: float = _points[7].x - _points[8].x
	var left_bottom: float = _points[13].x - _points[14].x
	var left_top: float = _points[18].x - _points[17].x
	return minf(minf(right_top, right_bottom), minf(left_bottom, left_top))


func maximum_render_turn_degrees() -> float:
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	var maximum_turn: float = 0.0
	for index in range(boundary.size()):
		var previous_index: int = posmod(index - 1, boundary.size())
		var next_index: int = (index + 1) % boundary.size()
		var incoming: Vector2 = boundary[index] - boundary[previous_index]
		var outgoing: Vector2 = boundary[next_index] - boundary[index]
		if incoming.length_squared() <= 0.0001 or outgoing.length_squared() <= 0.0001:
			continue
		var turn: float = absf(rad_to_deg(incoming.angle_to(outgoing)))
		maximum_turn = maxf(maximum_turn, turn)
	return maximum_turn


func maximum_neighbor_displacement_delta() -> float:
	var maximum_delta: float = 0.0
	for index in range(_points.size()):
		var next_index: int = (index + 1) % _points.size()
		var displacement: Vector2 = _points[index] - _rest_points[index]
		var next_displacement: Vector2 = _points[next_index] - _rest_points[next_index]
		maximum_delta = maxf(maximum_delta, displacement.distance_to(next_displacement))
	return maximum_delta


func _rest_outline_source() -> Array[Vector2]:
	return REST_OUTLINE


func _initialize_membrane() -> void:
	_rest_points.clear()
	_points.clear()
	_velocities.clear()
	_rest_normals.clear()
	for point in _rest_outline_source():
		_rest_points.append(point)
		_points.append(point)
		_velocities.append(Vector2.ZERO)
	_rest_area = absf(_signed_area(_rest_points))
	for index in range(_rest_points.size()):
		_rest_normals.append(_boundary_outward_normal(_rest_points, index))


func _update_membrane(delta: float) -> void:
	var area_ratio: float = current_area_ratio()
	var pressure: float = (1.0 - area_ratio) * area_pressure

	for index in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var phase: float = _time * breath_speed + float(index) * 0.73
		var target: Vector2 = _rest_points[index]
		target += _rest_normals[index] * sin(phase) * breath_amount
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
		var pressure_force: Vector2 = _rest_normals[index] * pressure
		_velocities[index] += (spring_force + shape_force + pressure_force) * delta
		_velocities[index] *= maxf(0.0, 1.0 - membrane_damping * delta)

	var velocity_source: Array[Vector2] = _velocities.duplicate()
	for index in range(_velocities.size()):
		var previous_index: int = posmod(index - 1, _velocities.size())
		var next_index: int = (index + 1) % _velocities.size()
		var neighbor_velocity: Vector2 = (
			velocity_source[previous_index] + velocity_source[next_index]
		) * 0.5
		_velocities[index] = velocity_source[index].lerp(
			neighbor_velocity,
			velocity_spread
		).limit_length(maximum_point_speed)

	var integrated_points: Array[Vector2] = []
	integrated_points.resize(_points.size())
	for index in range(_points.size()):
		var candidate: Vector2 = _points[index] + _velocities[index] * delta
		var offset: Vector2 = (candidate - _rest_points[index]).limit_length(maximum_offset)
		integrated_points[index] = _rest_points[index] + offset

	var next_points: Array[Vector2] = []
	next_points.resize(_points.size())
	for index in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var displacement: Vector2 = integrated_points[index] - _rest_points[index]
		var neighbor_displacement: Vector2 = (
			integrated_points[previous_index] - _rest_points[previous_index]
			+ integrated_points[next_index] - _rest_points[next_index]
		) * 0.5
		var corrected_displacement: Vector2 = displacement.lerp(
			neighbor_displacement,
			displacement_smoothing
		).limit_length(maximum_offset)
		next_points[index] = _rest_points[index] + corrected_displacement
		_velocities[index] = (
			(next_points[index] - _points[index]) / maxf(delta, 0.0001)
		).limit_length(maximum_point_speed)

	_points = next_points


func _draw_wet_highlights() -> void:
	var cap_start: Vector2 = _deform_inner_point(Vector2(-13.0, -202.0))
	var cap_end: Vector2 = _deform_inner_point(Vector2(-13.0, -169.0))
	draw_line(cap_start, cap_end, Color(0.88, 1.0, 0.94, 0.86), 8.0, true)
	draw_circle(cap_start, 4.0, Color(0.94, 1.0, 0.97, 0.90))
	draw_circle(cap_end, 4.0, Color(0.75, 1.0, 0.89, 0.72))

	var arm_start: Vector2 = _deform_inner_point(Vector2(-101.0, -112.0))
	var arm_end: Vector2 = _deform_inner_point(Vector2(-68.0, -112.0))
	draw_line(arm_start, arm_end, Color(0.82, 1.0, 0.92, 0.72), 6.0, true)
	draw_circle(arm_start, 3.0, Color(0.92, 1.0, 0.97, 0.82))


func _draw_bubbles() -> void:
	for index in range(BUBBLE_REST_POSITIONS.size()):
		var bubble_position: Vector2 = _deform_inner_point(BUBBLE_REST_POSITIONS[index])
		var radius: float = 5.0 + float(index % 3) * 2.0
		draw_circle(bubble_position, radius, Color(0.015, 0.12, 0.17, 0.32))
		draw_arc(
			bubble_position,
			radius,
			PI,
			TAU * 0.86,
			10,
			Color(0.66, 1.0, 0.87, 0.62),
			1.7,
			true
		)


func _draw_impact_ripple() -> void:
	if _impact_index < 0 or _impact_strength <= 0.01:
		return
	var ripple_center: Vector2 = _points[_impact_index]
	var radius: float = lerpf(18.0, 42.0, 1.0 - minf(_impact_strength, 1.0))
	draw_arc(
		ripple_center,
		radius,
		0.0,
		TAU,
		28,
		Color(0.75, 1.0, 0.90, _impact_strength * 0.58),
		3.0,
		true
	)


func _draw_debug_rig() -> void:
	if not _debug_rig_enabled:
		return
	var rest_center: Vector2 = _polygon_centroid(_rest_points)
	var current_center: Vector2 = _polygon_centroid(_points)
	var rest_closed := PackedVector2Array(_rest_points)
	rest_closed.append(_rest_points[0])

	draw_polyline(rest_closed, Color(0.66, 0.42, 1.0, 0.68), 2.0, true)
	for index in range(_points.size()):
		var next_index: int = (index + 1) % _points.size()
		draw_line(
			current_center,
			_points[index],
			Color(0.28, 0.94, 0.78, 0.24),
			1.15,
			true
		)
		draw_line(
			_points[index],
			_points[next_index],
			Color(1.0, 0.72, 0.20, 0.94),
			2.5,
			true
		)

		var displacement: Vector2 = _points[index] - _rest_points[index]
		if displacement.length_squared() > 0.20:
			draw_line(
				_rest_points[index],
				_points[index],
				Color(0.28, 0.88, 1.0, 0.86),
				1.8,
				true
			)

		draw_circle(_rest_points[index], 5.2, Color(0.09, 0.035, 0.18, 0.90))
		draw_arc(
			_rest_points[index],
			5.2,
			0.0,
			TAU,
			16,
			Color(0.74, 0.48, 1.0, 0.92),
			1.6,
			true
		)
		var point_color := Color(1.0, 0.30, 0.66, 1.0)
		if not _is_concave_corner(_rest_points, index):
			point_color = Color(1.0, 0.82, 0.24, 1.0)
		draw_circle(_points[index], 7.2, Color(0.035, 0.025, 0.045, 0.94))
		draw_circle(_points[index], 4.6, point_color)
		draw_circle(_points[index] + Vector2(-1.3, -1.4), 1.4, Color.WHITE)

	draw_line(
		rest_center - Vector2(10.0, 0.0),
		rest_center + Vector2(10.0, 0.0),
		Color(0.72, 0.52, 1.0, 0.90),
		1.5,
		true
	)
	draw_line(
		rest_center - Vector2(0.0, 10.0),
		rest_center + Vector2(0.0, 10.0),
		Color(0.72, 0.52, 1.0, 0.90),
		1.5,
		true
	)
	draw_circle(current_center, 8.0, Color(0.02, 0.08, 0.09, 0.92))
	draw_circle(current_center, 4.5, Color(0.30, 1.0, 0.78, 1.0))


func _draw_triangulated_polygon(points: PackedVector2Array, color: Color) -> void:
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	for index in range(0, indices.size(), 3):
		var triangle := PackedVector2Array(
			[
				points[indices[index]],
				points[indices[index + 1]],
				points[indices[index + 2]],
			]
		)
		draw_colored_polygon(triangle, color)


func _deform_inner_point(rest_position: Vector2) -> Vector2:
	var weighted_displacement := Vector2.ZERO
	var total_weight: float = 0.0
	for index in range(_rest_points.size()):
		var distance_squared: float = maxf(
			rest_position.distance_squared_to(_rest_points[index]),
			256.0
		)
		var weight: float = 1.0 / distance_squared
		weighted_displacement += (_points[index] - _rest_points[index]) * weight
		total_weight += weight
	if total_weight <= 0.0:
		return rest_position
	return rest_position + weighted_displacement / total_weight


func _nearest_point_index(local_hit: Vector2) -> int:
	var nearest_index: int = 0
	var nearest_distance: float = INF
	for index in range(_points.size()):
		var distance: float = _points[index].distance_squared_to(local_hit)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	return nearest_index


func _smoothed_boundary_points() -> PackedVector2Array:
	var smoothed_points := PackedVector2Array()
	for index in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var corner: Vector2 = _points[index]
		var entry: Vector2 = corner.lerp(_points[previous_index], corner_rounding)
		var exit: Vector2 = corner.lerp(_points[next_index], corner_rounding)
		for sample_index in range(RENDER_SAMPLES_PER_CORNER):
			var ratio: float = (
				float(sample_index) / float(RENDER_SAMPLES_PER_CORNER - 1)
			)
			var inverse_ratio: float = 1.0 - ratio
			smoothed_points.append(
				entry * inverse_ratio * inverse_ratio
				+ corner * 2.0 * inverse_ratio * ratio
				+ exit * ratio * ratio
			)
	return smoothed_points


func _scaled_polygon(
	points: PackedVector2Array,
	center: Vector2,
	scale_factor: float
) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point in points:
		scaled.append(center + (point - center) * scale_factor)
	return scaled


func _boundary_outward_normal(points: Array[Vector2], index: int) -> Vector2:
	var previous_index: int = posmod(index - 1, points.size())
	var next_index: int = (index + 1) % points.size()
	var tangent: Vector2 = points[next_index] - points[previous_index]
	var normal := Vector2(tangent.y, -tangent.x)
	if _signed_area(points) < 0.0:
		normal = -normal
	if normal.length_squared() <= 0.0001:
		return Vector2.UP
	return normal.normalized()


func _count_concave_corners(points: Array[Vector2]) -> int:
	if points.size() < 3:
		return 0
	var polygon_sign: float = signf(_signed_area(points))
	var count: int = 0
	for index in range(points.size()):
		var previous_index: int = posmod(index - 1, points.size())
		var next_index: int = (index + 1) % points.size()
		var incoming: Vector2 = points[index] - points[previous_index]
		var outgoing: Vector2 = points[next_index] - points[index]
		if signf(incoming.cross(outgoing)) != polygon_sign:
			count += 1
	return count


func _is_concave_corner(points: Array[Vector2], index: int) -> bool:
	if points.size() < 3:
		return false
	var previous_index: int = posmod(index - 1, points.size())
	var next_index: int = (index + 1) % points.size()
	var incoming: Vector2 = points[index] - points[previous_index]
	var outgoing: Vector2 = points[next_index] - points[index]
	return signf(incoming.cross(outgoing)) != signf(_signed_area(points))


func _polygon_centroid(points: Array[Vector2]) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in points:
		total += point
	return total / float(points.size())


func _point_bounds(points: Array[Vector2]) -> Rect2:
	if points.is_empty():
		return Rect2()
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point in points:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _signed_area(points: Array[Vector2]) -> float:
	if points.size() < 3:
		return 0.0
	var area: float = 0.0
	for index in range(points.size()):
		var next_index: int = (index + 1) % points.size()
		area += points[index].cross(points[next_index])
	return area * 0.5
