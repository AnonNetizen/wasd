# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §8.2-A, docs/决策记录.md ADR #183
class_name PlayerSlimeVisual
extends Node2D


const CONTROL_POINT_COUNT: int = 20
const RENDER_SAMPLES_PER_CONTROL: int = 5
const EXPECTED_BOUNDARY_POINT_COUNT: int = (
	CONTROL_POINT_COUNT * RENDER_SAMPLES_PER_CONTROL
)
const DEFAULT_RADIUS: float = 25.0
const MUZZLE_DISTANCE: float = 38.0
const OUTLINE_WIDTH: float = 3.0
const WET_RIM_WIDTH: float = 1.0
const REST_RADIUS_INSET: float = 2.2
const MAXIMUM_RADIAL_INSET: float = 3.1
const MAXIMUM_TANGENTIAL_OFFSET: float = 1.55
const MAXIMUM_POINT_SPEED: float = 145.0
const MEMBRANE_STIFFNESS: float = 76.0
const MEMBRANE_DAMPING: float = 9.4
const NEIGHBOR_STIFFNESS: float = 48.0
const AREA_PRESSURE: float = 620.0
const VELOCITY_SPREAD: float = 0.31
const DISPLACEMENT_SMOOTHING: float = 0.28
const CORNER_ROUNDING: float = 0.32
const FIRE_IMPULSE: float = 88.0
const MOVEMENT_REFERENCE_SPEED: float = 260.0
const DEFAULT_MAIN_PRIMARY := Color("68bcdd")
const DEFAULT_SUB_PRIMARY := Color("ed2f72")

var _radius: float = DEFAULT_RADIUS
var _rest_points: Array[Vector2] = []
var _points: Array[Vector2] = []
var _velocities: Array[Vector2] = []
var _rest_area: float = 1.0
var _time: float = 0.0
var _aim_direction := Vector2.RIGHT
var _body: Polygon2D = null
var _outline: Line2D = null
var _wet_rim: Line2D = null
var _direction: Node2D = null
var _facing_beam: Line2D = null
var _body_material: ShaderMaterial = null
var _beam_gradient: Gradient = null
var _main_primary: Color = DEFAULT_MAIN_PRIMARY
var _sub_primary: Color = DEFAULT_SUB_PRIMARY
var _last_impulse_indices := PackedInt32Array()


func _ready() -> void:
	_bind_scene_nodes()
	_rebuild_membrane()
	_apply_palette()
	_sync_visuals()


func configure_palette(palette: Dictionary) -> void:
	_main_primary = _color_from_variant(
		palette.get("main_primary", _main_primary),
		_main_primary
	)
	_sub_primary = _color_from_variant(
		palette.get("sub_primary", _sub_primary),
		_sub_primary
	)
	_apply_palette()


func configure_radius(radius: float) -> void:
	_radius = maxf(radius, 4.0)
	if _body_material != null:
		_body_material.set_shader_parameter("body_radius", _radius)
	_rebuild_membrane()
	_sync_visuals()


func advance_visual(
	delta: float,
	motion_velocity: Vector2,
	aim_direction: Vector2
) -> void:
	if _points.is_empty():
		return
	var safe_delta: float = clampf(delta, 0.0001, 0.033)
	_time += safe_delta
	if aim_direction.length_squared() > 0.0001:
		_aim_direction = aim_direction.normalized()
	_update_membrane(safe_delta, motion_velocity)
	_sync_visuals()


func apply_fire_impulse(direction: Vector2) -> void:
	if _points.is_empty():
		return
	var impulse_direction: Vector2 = direction.normalized()
	if impulse_direction.length_squared() <= 0.0001:
		impulse_direction = _aim_direction
	_apply_distributed_impulse(
		impulse_direction,
		impulse_direction * FIRE_IMPULSE
	)


func set_presentation_state(
	tint: Color,
	alpha: float,
	visual_scale: Vector2
) -> void:
	var safe_alpha: float = clampf(alpha, 0.0, 1.0)
	var opaque_tint := Color(tint.r, tint.g, tint.b, 1.0)
	if _body_material != null:
		_body_material.set_shader_parameter("presentation_tint", opaque_tint)
		_body_material.set_shader_parameter("presentation_alpha", safe_alpha)
	var line_modulate := Color(opaque_tint, safe_alpha)
	if _outline != null:
		_outline.modulate = line_modulate
	if _wet_rim != null:
		_wet_rim.modulate = line_modulate
	if _direction != null:
		_direction.modulate = line_modulate
	scale = visual_scale


func reset_immediately() -> void:
	_points = _rest_points.duplicate()
	_velocities.clear()
	for _index: int in range(_rest_points.size()):
		_velocities.append(Vector2.ZERO)
	_time = 0.0
	_aim_direction = Vector2.RIGHT
	_last_impulse_indices.clear()
	set_presentation_state(Color.WHITE, 1.0, Vector2.ONE)
	_sync_visuals()


func control_point_count() -> int:
	return _points.size()


func boundary_point_count() -> int:
	return _smoothed_boundary_points().size()


func current_area_ratio() -> float:
	if _rest_area <= 0.0001:
		return 1.0
	return absf(_signed_area(_points)) / _rest_area


func maximum_render_extent() -> float:
	var maximum_centerline_radius: float = 0.0
	for point: Vector2 in _smoothed_boundary_points():
		maximum_centerline_radius = maxf(
			maximum_centerline_radius,
			point.length()
		)
	return maximum_centerline_radius + OUTLINE_WIDTH * 0.5


func maximum_render_turn_degrees() -> float:
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	var maximum_turn: float = 0.0
	for index: int in range(boundary.size()):
		var previous_index: int = posmod(index - 1, boundary.size())
		var next_index: int = (index + 1) % boundary.size()
		var incoming: Vector2 = boundary[index] - boundary[previous_index]
		var outgoing: Vector2 = boundary[next_index] - boundary[index]
		if (
			incoming.length_squared() <= 0.000001
			or outgoing.length_squared() <= 0.000001
		):
			continue
		maximum_turn = maxf(
			maximum_turn,
			absf(rad_to_deg(incoming.angle_to(outgoing)))
		)
	return maximum_turn


func maximum_neighbor_displacement_delta() -> float:
	var maximum_delta: float = 0.0
	for index: int in range(_points.size()):
		var next_index: int = (index + 1) % _points.size()
		var displacement: Vector2 = _points[index] - _rest_points[index]
		var next_displacement: Vector2 = (
			_points[next_index] - _rest_points[next_index]
		)
		maximum_delta = maxf(
			maximum_delta,
			displacement.distance_to(next_displacement)
		)
	return maximum_delta


func beam_end() -> Vector2:
	if _facing_beam == null or _facing_beam.points.size() < 2:
		return Vector2.ZERO
	return _facing_beam.points[1]


func animation_time() -> float:
	return _time


func body_material() -> ShaderMaterial:
	return _body_material


func body_polygon() -> PackedVector2Array:
	return _body.polygon if _body != null else PackedVector2Array()


func palette_state() -> Dictionary:
	return {
		"main_primary": _main_primary,
		"sub_primary": _sub_primary,
	}


func visual_node_count() -> int:
	return _count_nodes(self)


func material_instance_ids() -> PackedInt64Array:
	var identifiers := PackedInt64Array()
	if _body_material != null:
		identifiers.append(_body_material.get_instance_id())
	if _beam_gradient != null:
		identifiers.append(_beam_gradient.get_instance_id())
	return identifiers


func beam_gradient_colors() -> PackedColorArray:
	return (
		_beam_gradient.colors
		if _beam_gradient != null
		else PackedColorArray()
	)


func last_impulse_control_count() -> int:
	return _last_impulse_indices.size()


func last_impulse_controls_are_contiguous() -> bool:
	if _last_impulse_indices.size() != 5:
		return false
	for offset: int in range(1, _last_impulse_indices.size()):
		if _last_impulse_indices[offset] != posmod(
			_last_impulse_indices[0] + offset,
			_points.size()
		):
			return false
	return true


func geometry_signature() -> String:
	var parts := PackedStringArray()
	for point: Vector2 in _smoothed_boundary_points():
		parts.append("%.4f,%.4f" % [point.x, point.y])
	return ";".join(parts)


func _bind_scene_nodes() -> void:
	_body = get_node_or_null("Body") as Polygon2D
	_outline = get_node_or_null("Outline") as Line2D
	_wet_rim = get_node_or_null("WetRim") as Line2D
	_direction = get_node_or_null("Direction") as Node2D
	_facing_beam = get_node_or_null("Direction/FacingBeam") as Line2D
	if (
		_body == null
		or _outline == null
		or _wet_rim == null
		or _direction == null
		or _facing_beam == null
	):
		push_error("[PlayerSlimeVisual] missing scene-authored visual nodes")
		return
	_body_material = _body.material as ShaderMaterial
	_beam_gradient = _facing_beam.gradient
	if _body_material == null or _beam_gradient == null:
		push_error("[PlayerSlimeVisual] missing scene-authored material resources")


func _apply_palette() -> void:
	if _body_material != null:
		_body_material.set_shader_parameter("main_primary", _main_primary)
		_body_material.set_shader_parameter("sub_primary", _sub_primary)
		_body_material.set_shader_parameter("body_radius", _radius)
	if _outline != null:
		_outline.default_color = _main_primary
	if _wet_rim != null:
		_wet_rim.default_color = _main_primary.lightened(0.28)
	_sync_beam_gradient()


func _rebuild_membrane() -> void:
	_rest_points.clear()
	_points.clear()
	_velocities.clear()
	var rest_radius: float = maxf(_radius - REST_RADIUS_INSET, 1.0)
	for index: int in range(CONTROL_POINT_COUNT):
		var angle: float = TAU * float(index) / float(CONTROL_POINT_COUNT)
		var point := Vector2.RIGHT.rotated(angle) * rest_radius
		_rest_points.append(point)
		_points.append(point)
		_velocities.append(Vector2.ZERO)
	_rest_area = absf(_signed_area(_rest_points))


func _update_membrane(delta: float, motion_velocity: Vector2) -> void:
	var speed_ratio: float = clampf(
		motion_velocity.length() / MOVEMENT_REFERENCE_SPEED,
		0.0,
		1.0
	)
	var motion_direction: Vector2 = motion_velocity.normalized()
	if motion_direction.length_squared() <= 0.0001:
		motion_direction = _aim_direction
	var pressure: float = (1.0 - current_area_ratio()) * AREA_PRESSURE

	for index: int in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var rest_normal: Vector2 = _rest_points[index].normalized()
		var axis_alignment: float = rest_normal.dot(motion_direction)
		var broad_compression: float = -absf(axis_alignment) * speed_ratio * 0.78
		var side_expansion: float = (
			(1.0 - absf(axis_alignment)) * speed_ratio * 0.42
		)
		var breath: float = sin(_time * 2.1 + float(index) * 0.31) * 0.10
		var target: Vector2 = _rest_points[index]
		target += rest_normal * (broad_compression + side_expansion + breath)

		var previous_shape_target: Vector2 = (
			_points[previous_index]
			+ (_rest_points[index] - _rest_points[previous_index])
		)
		var next_shape_target: Vector2 = (
			_points[next_index]
			+ (_rest_points[index] - _rest_points[next_index])
		)
		var shape_target: Vector2 = (
			(previous_shape_target + next_shape_target) * 0.5
		)
		var spring_force: Vector2 = (
			(target - _points[index]) * MEMBRANE_STIFFNESS
		)
		var shape_force: Vector2 = (
			(shape_target - _points[index]) * NEIGHBOR_STIFFNESS
		)
		var pressure_force: Vector2 = rest_normal * pressure
		_velocities[index] += (
			(spring_force + shape_force + pressure_force) * delta
		)
		_velocities[index] *= maxf(0.0, 1.0 - MEMBRANE_DAMPING * delta)

	var velocity_source: Array[Vector2] = _velocities.duplicate()
	for index: int in range(_velocities.size()):
		var previous_index: int = posmod(index - 1, _velocities.size())
		var next_index: int = (index + 1) % _velocities.size()
		var neighbor_velocity: Vector2 = (
			velocity_source[previous_index] + velocity_source[next_index]
		) * 0.5
		_velocities[index] = velocity_source[index].lerp(
			neighbor_velocity,
			VELOCITY_SPREAD
		).limit_length(MAXIMUM_POINT_SPEED)

	var integrated_points: Array[Vector2] = []
	integrated_points.resize(_points.size())
	for index: int in range(_points.size()):
		integrated_points[index] = _bounded_point(
			index,
			_points[index] + _velocities[index] * delta
		)

	var next_points: Array[Vector2] = []
	next_points.resize(_points.size())
	for index: int in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var displacement: Vector2 = (
			integrated_points[index] - _rest_points[index]
		)
		var neighbor_displacement: Vector2 = (
			integrated_points[previous_index] - _rest_points[previous_index]
			+ integrated_points[next_index] - _rest_points[next_index]
		) * 0.5
		var corrected_displacement: Vector2 = displacement.lerp(
			neighbor_displacement,
			DISPLACEMENT_SMOOTHING
		)
		next_points[index] = _bounded_point(
			index,
			_rest_points[index] + corrected_displacement
		)
		_velocities[index] = (
			(next_points[index] - _points[index]) / maxf(delta, 0.0001)
		).limit_length(MAXIMUM_POINT_SPEED)
	_points = next_points


func _bounded_point(index: int, candidate: Vector2) -> Vector2:
	var rest_normal: Vector2 = _rest_points[index].normalized()
	var rest_tangent := Vector2(-rest_normal.y, rest_normal.x)
	var displacement: Vector2 = candidate - _rest_points[index]
	var maximum_outset: float = maxf(
		_radius - OUTLINE_WIDTH * 0.5 - _rest_points[index].length(),
		0.0
	)
	var radial_offset: float = clampf(
		displacement.dot(rest_normal),
		-MAXIMUM_RADIAL_INSET,
		maximum_outset
	)
	var tangential_offset: float = clampf(
		displacement.dot(rest_tangent),
		-MAXIMUM_TANGENTIAL_OFFSET,
		MAXIMUM_TANGENTIAL_OFFSET
	)
	var bounded: Vector2 = (
		_rest_points[index]
		+ rest_normal * radial_offset
		+ rest_tangent * tangential_offset
	)
	var centerline_limit: float = _radius - OUTLINE_WIDTH * 0.5
	return bounded.limit_length(centerline_limit)


func _apply_distributed_impulse(
	impact_direction: Vector2,
	impulse: Vector2
) -> void:
	var center_index: int = _nearest_direction_index(impact_direction)
	_last_impulse_indices.clear()
	for offset: int in range(-2, 3):
		var index: int = posmod(center_index + offset, _points.size())
		_last_impulse_indices.append(index)
		var normalized_offset: float = float(abs(offset)) / 3.0
		var weight: float = cos(normalized_offset * PI * 0.5)
		_velocities[index] = (
			_velocities[index] + impulse * weight
		).limit_length(MAXIMUM_POINT_SPEED)


func _nearest_direction_index(direction: Vector2) -> int:
	var normalized_direction: Vector2 = direction.normalized()
	var nearest_index: int = 0
	var best_dot: float = -INF
	for index: int in range(_rest_points.size()):
		var direction_dot: float = (
			_rest_points[index].normalized().dot(normalized_direction)
		)
		if direction_dot > best_dot:
			best_dot = direction_dot
			nearest_index = index
	return nearest_index


func _sync_visuals() -> void:
	if (
		_body == null
		or _outline == null
		or _wet_rim == null
		or _direction == null
		or _body_material == null
		or _points.is_empty()
	):
		return
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	_body.polygon = boundary
	_outline.points = boundary
	_wet_rim.points = boundary
	_direction.rotation = _aim_direction.angle()
	_body_material.set_shader_parameter("animation_time", _time)


func _sync_beam_gradient() -> void:
	if _beam_gradient == null:
		return
	_beam_gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	_beam_gradient.colors = PackedColorArray([
		Color(_main_primary, 0.16),
		Color(_main_primary, 0.78),
		Color(_main_primary, 0.06),
	])


func _smoothed_boundary_points() -> PackedVector2Array:
	var smoothed_points := PackedVector2Array()
	for index: int in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var corner: Vector2 = _points[index]
		var entry: Vector2 = corner.lerp(
			_points[previous_index],
			CORNER_ROUNDING
		)
		var exit: Vector2 = corner.lerp(
			_points[next_index],
			CORNER_ROUNDING
		)
		for sample_index: int in range(RENDER_SAMPLES_PER_CONTROL):
			var ratio: float = (
				float(sample_index) / float(RENDER_SAMPLES_PER_CONTROL - 1)
			)
			var inverse_ratio: float = 1.0 - ratio
			smoothed_points.append(
				entry * inverse_ratio * inverse_ratio
				+ corner * 2.0 * inverse_ratio * ratio
				+ exit * ratio * ratio
			)
	return smoothed_points


func _signed_area(points: Array[Vector2]) -> float:
	if points.size() < 3:
		return 0.0
	var area: float = 0.0
	for index: int in range(points.size()):
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5


func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count


func _color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	if value is String and Color.html_is_valid(String(value)):
		return Color.from_string(String(value), fallback)
	return fallback
