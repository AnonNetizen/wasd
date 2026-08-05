class_name TestLabPlayerSlimeFusion
extends Node2D

const DUAL_VORTEX_SHADER: Shader = preload(
	"res://shaders/player_slime_dual_vortex.gdshader"
)
const CONTROL_POINT_COUNT: int = 20
const RENDER_SAMPLES_PER_CONTROL: int = 5
const EXPECTED_BOUNDARY_POINT_COUNT: int = (
	CONTROL_POINT_COUNT * RENDER_SAMPLES_PER_CONTROL
)
const DEFAULT_RADIUS: float = 25.0
const MUZZLE_DISTANCE: float = 38.0
const OUTLINE_WIDTH: float = 2.0
const WET_RIM_WIDTH: float = 0.75
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
const HIT_IMPULSE: float = 112.0
const DEFAULT_MAIN_PRIMARY := Color("7e63d8")
const DEFAULT_SUB_PRIMARY := Color("f2a23a")
const DEFAULT_MAIN_SECONDARY := Color("3d315e")
const DEFAULT_SUB_ACCENT := Color("ffd07a")

var _radius: float = DEFAULT_RADIUS
var _rest_points: Array[Vector2] = []
var _points: Array[Vector2] = []
var _velocities: Array[Vector2] = []
var _rest_area: float = 1.0
var _time: float = 0.0
var _aim_direction := Vector2.RIGHT
var _fixed_step_mode: bool = false
var _simulation_paused: bool = false
var _body: Polygon2D
var _outline: Line2D
var _wet_rim: Line2D
var _direction: Node2D
var _facing_beam: Line2D
var _body_material: ShaderMaterial
var _beam_gradient: Gradient
var _main_primary: Color = DEFAULT_MAIN_PRIMARY
var _sub_primary: Color = DEFAULT_SUB_PRIMARY
var _main_secondary: Color = DEFAULT_MAIN_SECONDARY
var _sub_accent: Color = DEFAULT_SUB_ACCENT
var _last_impulse_indices := PackedInt32Array()


func _ready() -> void:
	_build_visual_nodes()
	_rebuild_membrane()
	configure_palette(
		_main_primary,
		_sub_primary,
		_main_secondary,
		_sub_accent
	)
	_sync_visuals()


func _physics_process(delta: float) -> void:
	if _fixed_step_mode or _simulation_paused:
		return
	advance_visual(delta, Vector2.ZERO, _aim_direction)


func configure_palette(
	main_primary: Color,
	sub_primary: Color,
	main_secondary: Color,
	sub_accent: Color
) -> void:
	_main_primary = main_primary
	_sub_primary = sub_primary
	_main_secondary = main_secondary
	_sub_accent = sub_accent
	if _body_material != null:
		_body_material.set_shader_parameter("main_primary", _main_primary)
		_body_material.set_shader_parameter("sub_primary", _sub_primary)
		_body_material.set_shader_parameter("rim_secondary", _main_secondary)
	if _outline != null:
		_outline.default_color = _main_secondary
	if _wet_rim != null:
		_wet_rim.default_color = _main_primary.lerp(_sub_primary, 0.5).lightened(0.28)
	_sync_beam_gradient()


func configure_radius(radius: float) -> void:
	_radius = maxf(radius, 4.0)
	if _body_material != null:
		_body_material.set_shader_parameter("body_radius", _radius)
	_rebuild_membrane()
	_sync_visuals()


func advance_visual(
	delta: float,
	motion_velocity: Vector2 = Vector2.ZERO,
	aim_direction: Vector2 = Vector2.RIGHT
) -> void:
	if _simulation_paused or _points.is_empty():
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
	_apply_distributed_impulse(impulse_direction, impulse_direction * FIRE_IMPULSE)


func apply_hit_impulse(local_hit: Vector2) -> void:
	if _points.is_empty():
		return
	var hit_direction: Vector2 = local_hit.normalized()
	if hit_direction.length_squared() <= 0.0001:
		hit_direction = Vector2.LEFT
	_apply_distributed_impulse(hit_direction, -hit_direction * HIT_IMPULSE)


func set_presentation_state(
	tint: Color = Color.WHITE,
	alpha: float = 1.0,
	scale_multiplier: float = 1.0
) -> void:
	if _body_material != null:
		_body_material.set_shader_parameter("presentation_tint", tint)
		_body_material.set_shader_parameter("presentation_alpha", clampf(alpha, 0.0, 1.0))
	modulate.a = clampf(alpha, 0.0, 1.0)
	scale = Vector2.ONE * maxf(scale_multiplier, 0.0)


func set_fixed_step_mode(enabled: bool) -> void:
	_fixed_step_mode = enabled


func set_simulation_paused(paused: bool) -> void:
	_simulation_paused = paused


func advance_fixed_step(
	delta: float,
	motion_velocity: Vector2 = Vector2.ZERO,
	aim_direction: Vector2 = Vector2.RIGHT
) -> void:
	if not _fixed_step_mode:
		return
	advance_visual(delta, motion_velocity, aim_direction)


func reset_immediately() -> void:
	_points = _rest_points.duplicate()
	_velocities.clear()
	for _index in range(_rest_points.size()):
		_velocities.append(Vector2.ZERO)
	_time = 0.0
	_aim_direction = Vector2.RIGHT
	_last_impulse_indices.clear()
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
	for point in _smoothed_boundary_points():
		maximum_centerline_radius = maxf(maximum_centerline_radius, point.length())
	return maximum_centerline_radius + OUTLINE_WIDTH * 0.5


func maximum_render_turn_degrees() -> float:
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	var maximum_turn: float = 0.0
	for index in range(boundary.size()):
		var previous_index: int = posmod(index - 1, boundary.size())
		var next_index: int = (index + 1) % boundary.size()
		var incoming: Vector2 = boundary[index] - boundary[previous_index]
		var outgoing: Vector2 = boundary[next_index] - boundary[index]
		if incoming.length_squared() <= 0.000001 or outgoing.length_squared() <= 0.000001:
			continue
		maximum_turn = maxf(
			maximum_turn,
			absf(rad_to_deg(incoming.angle_to(outgoing)))
		)
	return maximum_turn


func maximum_neighbor_displacement_delta() -> float:
	var maximum_delta: float = 0.0
	for index in range(_points.size()):
		var next_index: int = (index + 1) % _points.size()
		var displacement: Vector2 = _points[index] - _rest_points[index]
		var next_displacement: Vector2 = _points[next_index] - _rest_points[next_index]
		maximum_delta = maxf(maximum_delta, displacement.distance_to(next_displacement))
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
		"main_secondary": _main_secondary,
		"sub_accent": _sub_accent,
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
	return _beam_gradient.colors if _beam_gradient != null else PackedColorArray()


func last_impulse_control_count() -> int:
	return _last_impulse_indices.size()


func last_impulse_controls_are_contiguous() -> bool:
	if _last_impulse_indices.size() != 5:
		return false
	for offset in range(1, _last_impulse_indices.size()):
		if _last_impulse_indices[offset] != posmod(
			_last_impulse_indices[0] + offset,
			_points.size()
		):
			return false
	return true


func geometry_signature() -> String:
	var parts := PackedStringArray()
	for point in _smoothed_boundary_points():
		parts.append("%.4f,%.4f" % [point.x, point.y])
	return ";".join(parts)


func _build_visual_nodes() -> void:
	if _body != null:
		return
	_body_material = ShaderMaterial.new()
	_body_material.shader = DUAL_VORTEX_SHADER
	_body_material.set_shader_parameter("animation_time", 0.0)
	_body_material.set_shader_parameter("body_radius", _radius)

	_body = Polygon2D.new()
	_body.name = "Body"
	_body.color = Color.WHITE
	_body.material = _body_material
	_body.z_index = 0
	add_child(_body)

	_outline = Line2D.new()
	_outline.name = "Outline"
	_outline.width = OUTLINE_WIDTH
	_outline.closed = true
	_outline.joint_mode = Line2D.LINE_JOINT_ROUND
	_outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	_outline.antialiased = true
	_outline.z_index = 1
	add_child(_outline)

	_wet_rim = Line2D.new()
	_wet_rim.name = "WetRim"
	_wet_rim.width = WET_RIM_WIDTH
	_wet_rim.closed = true
	_wet_rim.joint_mode = Line2D.LINE_JOINT_ROUND
	_wet_rim.antialiased = true
	_wet_rim.z_index = 2
	add_child(_wet_rim)

	_direction = Node2D.new()
	_direction.name = "Direction"
	_direction.z_index = 3
	add_child(_direction)

	_facing_beam = Line2D.new()
	_facing_beam.name = "FacingBeam"
	_facing_beam.width = 2.0
	_facing_beam.points = PackedVector2Array([Vector2.ZERO, Vector2(MUZZLE_DISTANCE, 0.0)])
	_facing_beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_facing_beam.end_cap_mode = Line2D.LINE_CAP_ROUND
	_facing_beam.antialiased = true
	_beam_gradient = Gradient.new()
	_facing_beam.gradient = _beam_gradient
	_direction.add_child(_facing_beam)


func _rebuild_membrane() -> void:
	_rest_points.clear()
	_points.clear()
	_velocities.clear()
	var rest_radius: float = maxf(_radius - REST_RADIUS_INSET, 1.0)
	for index in range(CONTROL_POINT_COUNT):
		var angle: float = TAU * float(index) / float(CONTROL_POINT_COUNT)
		var point := Vector2.RIGHT.rotated(angle) * rest_radius
		_rest_points.append(point)
		_points.append(point)
		_velocities.append(Vector2.ZERO)
	_rest_area = absf(_signed_area(_rest_points))


func _update_membrane(delta: float, motion_velocity: Vector2) -> void:
	var speed_ratio: float = clampf(motion_velocity.length() / 260.0, 0.0, 1.0)
	var motion_direction: Vector2 = motion_velocity.normalized()
	if motion_direction.length_squared() <= 0.0001:
		motion_direction = _aim_direction
	var pressure: float = (1.0 - current_area_ratio()) * AREA_PRESSURE

	for index in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var rest_normal: Vector2 = _rest_points[index].normalized()
		var axis_alignment: float = rest_normal.dot(motion_direction)
		var broad_compression: float = -absf(axis_alignment) * speed_ratio * 0.78
		var side_expansion: float = (1.0 - absf(axis_alignment)) * speed_ratio * 0.42
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
		var shape_target: Vector2 = (previous_shape_target + next_shape_target) * 0.5
		var spring_force: Vector2 = (target - _points[index]) * MEMBRANE_STIFFNESS
		var shape_force: Vector2 = (shape_target - _points[index]) * NEIGHBOR_STIFFNESS
		var pressure_force: Vector2 = rest_normal * pressure
		_velocities[index] += (spring_force + shape_force + pressure_force) * delta
		_velocities[index] *= maxf(0.0, 1.0 - MEMBRANE_DAMPING * delta)

	var velocity_source: Array[Vector2] = _velocities.duplicate()
	for index in range(_velocities.size()):
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
	for index in range(_points.size()):
		integrated_points[index] = _bounded_point(
			index,
			_points[index] + _velocities[index] * delta
		)

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
	for offset in range(-2, 3):
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
	for index in range(_rest_points.size()):
		var direction_dot: float = _rest_points[index].normalized().dot(normalized_direction)
		if direction_dot > best_dot:
			best_dot = direction_dot
			nearest_index = index
	return nearest_index


func _sync_visuals() -> void:
	if _body == null or _points.is_empty():
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
	_beam_gradient.colors = PackedColorArray(
		[
			Color(_sub_accent, 0.16),
			Color(_sub_accent, 0.78),
			Color(_sub_accent, 0.06),
		]
	)


func _smoothed_boundary_points() -> PackedVector2Array:
	var smoothed_points := PackedVector2Array()
	for index in range(_points.size()):
		var previous_index: int = posmod(index - 1, _points.size())
		var next_index: int = (index + 1) % _points.size()
		var corner: Vector2 = _points[index]
		var entry: Vector2 = corner.lerp(_points[previous_index], CORNER_ROUNDING)
		var exit: Vector2 = corner.lerp(_points[next_index], CORNER_ROUNDING)
		for sample_index in range(RENDER_SAMPLES_PER_CONTROL):
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
	for index in range(points.size()):
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5


func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
