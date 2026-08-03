class_name TestLabBulletVfxSample
extends Node2D

## Shared procedural bullet body used by the Test Lab selection wall.

enum VariantId {
	TEAR_CORE,
	CROSS_SEED,
	GAP_RING,
	ROUND_CAPSULE,
	TRI_LOBE_CROWN,
	FACET_DART,
}

enum TeamPalette {
	PLAYER_WHITE,
	ENEMY_RED,
}

const VARIANT_COUNT: int = 6
const TEAM_COUNT: int = 2
const MAX_TRAIL_SAMPLES: int = 6
const TRAIL_SPACING: float = 7.0
const IMPACT_DURATION: float = 0.32
const POST_IMPACT_HOLD: float = 0.24

const PLAYER_OUTLINE: Color = Color("111722")
const PLAYER_SHELL: Color = Color("dceaf2")
const PLAYER_INNER: Color = Color("9cb7c5")
const PLAYER_HIGHLIGHT: Color = Color("ffffff")
const ENEMY_OUTLINE: Color = Color("2b080b")
const ENEMY_SHELL: Color = Color("e62935")
const ENEMY_INNER: Color = Color("ff5a55")
const ENEMY_HIGHLIGHT: Color = Color("ffd6cf")
const HITBOX_COLOR: Color = Color(0.26, 0.96, 0.78, 0.72)

var _variant_id: VariantId = VariantId.TEAR_CORE
var _team_palette: TeamPalette = TeamPalette.PLAYER_WHITE
var _hit_radius: float = 8.0
var _preview_scale: float = 1.0
var _speed: float = 0.0
var _lane_length: float = 0.0
var _phase_offset: float = 0.0
var _is_moving: bool = false
var _show_hitbox: bool = false
var _show_trail: bool = true
var _preview_time: float = 0.0
var _projectile_position: Vector2 = Vector2.ZERO
var _impact_progress: float = -1.0
var _geometry: PackedVector2Array = PackedVector2Array()
var _trail_positions: Array[Vector2] = []


func configure(
	variant_id: VariantId,
	team_palette: TeamPalette,
	hit_radius: float,
	preview_scale: float,
	speed: float = 0.0,
	lane_length: float = 0.0,
	phase_offset: float = 0.0
) -> void:
	_variant_id = variant_id
	_team_palette = team_palette
	_hit_radius = maxf(hit_radius, 1.0)
	_preview_scale = maxf(preview_scale, 0.1)
	_speed = maxf(speed, 0.0)
	_lane_length = maxf(lane_length, 0.0)
	_phase_offset = phase_offset
	_is_moving = _speed > 0.0 and _lane_length > 0.0
	_geometry = _build_geometry(_variant_id)
	reset_preview()


func set_preview_time(value: float) -> void:
	_preview_time = maxf(value, 0.0)
	if not _is_moving:
		_projectile_position = Vector2.ZERO
		_impact_progress = -1.0
		_trail_positions.clear()
		queue_redraw()
		return

	var travel_duration: float = _lane_length / _speed
	var cycle_duration: float = travel_duration + IMPACT_DURATION + POST_IMPACT_HOLD
	var cycle_time: float = fposmod(_preview_time + _phase_offset, cycle_duration)
	if cycle_time < travel_duration:
		_projectile_position = Vector2(_speed * cycle_time, 0.0)
		_impact_progress = -1.0
		_rebuild_trail(cycle_time)
	elif cycle_time < travel_duration + IMPACT_DURATION:
		_projectile_position = Vector2(_lane_length, 0.0)
		_impact_progress = (cycle_time - travel_duration) / IMPACT_DURATION
		_trail_positions.clear()
	else:
		_projectile_position = Vector2(_lane_length, 0.0)
		_impact_progress = 2.0
		_trail_positions.clear()
	queue_redraw()


func reset_preview() -> void:
	_preview_time = 0.0
	_projectile_position = Vector2.ZERO
	_impact_progress = -1.0
	_trail_positions.clear()
	queue_redraw()


func set_hitbox_visible(visible: bool) -> void:
	_show_hitbox = visible
	queue_redraw()


func set_trail_visible(visible: bool) -> void:
	_show_trail = visible
	queue_redraw()


func debug_force_impact(progress: float) -> void:
	_projectile_position = Vector2(_lane_length, 0.0)
	_impact_progress = clampf(progress, 0.0, 1.0)
	_trail_positions.clear()
	queue_redraw()


func variant_id() -> int:
	return int(_variant_id)


func team_palette() -> int:
	return int(_team_palette)


func geometry_signature() -> String:
	if _variant_id == VariantId.GAP_RING:
		return "gap_ring:r0.68:w0.32:g0.72"
	var parts: PackedStringArray = PackedStringArray()
	for point: Vector2 in _geometry:
		parts.append("%.4f,%.4f" % [point.x, point.y])
	return ";".join(parts)


func primary_color() -> Color:
	return ENEMY_SHELL if _team_palette == TeamPalette.ENEMY_RED else PLAYER_SHELL


func visual_body_extent() -> float:
	var radius: float = _hit_radius * _preview_scale
	if _variant_id == VariantId.GAP_RING:
		return radius * 0.92 * 1.018
	var maximum_ratio: float = 0.0
	for pulse: float in [-1.0, 1.0]:
		var body_scale: Vector2 = _body_scale_for_pulse(pulse)
		for point: Vector2 in _geometry:
			maximum_ratio = maxf(maximum_ratio, (point * body_scale).length())
	return radius * maximum_ratio


func collision_radius() -> float:
	return _hit_radius * _preview_scale


func configured_hit_radius() -> float:
	return _hit_radius


func preview_speed() -> float:
	return _speed


func trail_sample_count() -> int:
	return _trail_positions.size()


func effect_child_count() -> int:
	return get_child_count()


func is_impact_active() -> bool:
	return _impact_progress >= 0.0 and _impact_progress <= 1.0


func _draw() -> void:
	var radius: float = _hit_radius * _preview_scale
	if _show_trail and _impact_progress < 0.0:
		_draw_trail(radius)
	if _show_hitbox and _impact_progress <= 1.0:
		draw_arc(
			_projectile_position,
			radius,
			0.0,
			TAU,
			32,
			HITBOX_COLOR,
			1.0,
			true
		)
	if _impact_progress >= 0.0:
		if _impact_progress <= 1.0:
			_draw_hit_effect(radius, _impact_progress)
		return
	_draw_body(_projectile_position, radius, 1.0)


func _draw_body(center: Vector2, radius: float, alpha: float) -> void:
	var pulse: float = sin(_preview_time * 5.2 + float(_variant_id) * 0.83)
	if _variant_id == VariantId.GAP_RING:
		_draw_gap_ring(center, radius * (1.0 + pulse * 0.018), alpha)
		return
	var body_scale: Vector2 = _body_scale_for_pulse(pulse)

	var outline: Color = _palette_color("outline", alpha)
	var shell: Color = _palette_color("shell", alpha)
	var inner: Color = _palette_color("inner", alpha * 0.82)
	var highlight: Color = _palette_color("highlight", alpha)
	var outer_points: PackedVector2Array = _transform_points(
		_geometry,
		center,
		Vector2(radius * body_scale.x, radius * body_scale.y)
	)
	var shell_points: PackedVector2Array = _transform_points(
		_geometry,
		center,
		Vector2(radius * 0.84 * body_scale.x, radius * 0.84 * body_scale.y)
	)
	var inner_center: Vector2 = center + Vector2(-radius * 0.08, radius * 0.10)
	var inner_points: PackedVector2Array = _transform_points(
		_geometry,
		inner_center,
		Vector2(radius * 0.55 * body_scale.x, radius * 0.55 * body_scale.y)
	)
	_fill_polygon(outer_points, outline)
	_fill_polygon(shell_points, shell)
	_fill_polygon(inner_points, inner)
	if _variant_id == VariantId.FACET_DART:
		_draw_dart_facets(center, radius, body_scale, pulse, alpha)

	var core_position: Vector2 = center + Vector2(radius * 0.16, radius * 0.04)
	draw_circle(core_position, radius * 0.19, _palette_color("highlight", alpha * 0.82))
	draw_circle(
		center + Vector2(-radius * 0.26, -radius * 0.29),
		maxf(radius * 0.11, 1.0),
		highlight
	)
	draw_arc(
		center + Vector2(-radius * 0.06, -radius * 0.03),
		radius * 0.58,
		PI * 1.05,
		PI * 1.48,
		10,
		_palette_color("highlight", alpha * 0.72),
		maxf(radius * 0.075, 1.0),
		true
	)


func _body_scale_for_pulse(pulse: float) -> Vector2:
	match _variant_id:
		VariantId.TEAR_CORE:
			return Vector2(0.970 + pulse * 0.014, 0.940 - pulse * 0.014)
		VariantId.CROSS_SEED:
			return Vector2.ONE * (0.900 + pulse * 0.012)
		VariantId.ROUND_CAPSULE:
			return Vector2(0.970 + pulse * 0.014, 0.940 - pulse * 0.012)
		VariantId.TRI_LOBE_CROWN:
			return Vector2.ONE * (0.970 + pulse * 0.012)
		VariantId.FACET_DART:
			return Vector2(0.980, 0.950 + pulse * 0.012)
	return Vector2.ONE


func _draw_dart_facets(
	center: Vector2,
	radius: float,
	body_scale: Vector2,
	pulse: float,
	alpha: float
) -> void:
	var upper_facet: PackedVector2Array = _transform_points(
		PackedVector2Array([
			Vector2(-0.54, -0.06),
			Vector2(0.26, -0.42),
			Vector2(0.78, 0.0),
			Vector2(0.04, 0.02),
		]),
		center,
		Vector2(radius * body_scale.x, radius * body_scale.y)
	)
	var lower_facet: PackedVector2Array = _transform_points(
		PackedVector2Array([
			Vector2(-0.54, 0.06),
			Vector2(0.04, -0.02),
			Vector2(0.78, 0.0),
			Vector2(0.26, 0.42),
		]),
		center,
		Vector2(radius * body_scale.x, radius * body_scale.y)
	)
	var upper_alpha: float = alpha * (0.12 + (pulse + 1.0) * 0.055)
	var lower_alpha: float = alpha * (0.23 - (pulse + 1.0) * 0.055)
	_fill_polygon(upper_facet, _palette_color("highlight", upper_alpha))
	_fill_polygon(lower_facet, _palette_color("highlight", lower_alpha))


func _draw_gap_ring(center: Vector2, radius: float, alpha: float) -> void:
	var gap_half: float = 0.36
	var start_angle: float = -PI + gap_half
	var end_angle: float = PI - gap_half
	draw_arc(
		center,
		radius * 0.68,
		start_angle,
		end_angle,
		40,
		_palette_color("outline", alpha),
		maxf(radius * 0.48, 1.0),
		true
	)
	draw_arc(
		center,
		radius * 0.68,
		start_angle,
		end_angle,
		40,
		_palette_color("shell", alpha),
		maxf(radius * 0.31, 1.0),
		true
	)
	draw_arc(
		center + Vector2(-radius * 0.04, radius * 0.05),
		radius * 0.66,
		PI * 1.04,
		PI * 1.54,
		14,
		_palette_color("inner", alpha * 0.72),
		maxf(radius * 0.12, 1.0),
		true
	)
	draw_arc(
		center + Vector2(-radius * 0.04, -radius * 0.03),
		radius * 0.70,
		PI * 1.12,
		PI * 1.42,
		10,
		_palette_color("highlight", alpha),
		maxf(radius * 0.075, 1.0),
		true
	)


func _draw_trail(radius: float) -> void:
	if _trail_positions.is_empty():
		return
	for index in range(_trail_positions.size()):
		var ratio: float = float(index + 1) / float(_trail_positions.size() + 1)
		var marker_alpha: float = ratio * 0.34
		var marker_radius: float = radius * lerpf(0.18, 0.48, ratio)
		var marker_position: Vector2 = _trail_positions[index]
		match _variant_id:
			VariantId.TEAR_CORE:
				draw_circle(
					marker_position,
					marker_radius,
					_palette_color("shell", marker_alpha)
				)
			VariantId.CROSS_SEED:
				var trail_shape: PackedVector2Array = _transform_points(
					_geometry,
					marker_position,
					Vector2.ONE * marker_radius
				)
				_fill_polygon(trail_shape, _palette_color("shell", marker_alpha))
			VariantId.GAP_RING:
				draw_arc(
					marker_position,
					marker_radius * 0.72,
					-PI + 0.36,
					PI - 0.36,
					16,
					_palette_color("shell", marker_alpha),
					maxf(marker_radius * 0.24, 0.8),
					true
				)
			VariantId.ROUND_CAPSULE:
				draw_line(
					marker_position - Vector2(marker_radius * 1.2, marker_radius * 0.32),
					marker_position + Vector2(marker_radius * 0.7, marker_radius * 0.32),
					_palette_color("shell", marker_alpha),
					maxf(marker_radius * 0.24, 1.0),
					true
				)
				draw_line(
					marker_position - Vector2(marker_radius * 1.2, -marker_radius * 0.32),
					marker_position + Vector2(marker_radius * 0.7, -marker_radius * 0.32),
					_palette_color("inner", marker_alpha),
					maxf(marker_radius * 0.18, 1.0),
					true
				)
			VariantId.TRI_LOBE_CROWN:
				for lobe_index in range(3):
					var angle: float = float(lobe_index) * TAU / 3.0
					draw_circle(
						marker_position + Vector2.from_angle(angle) * marker_radius * 0.32,
						marker_radius * 0.26,
						_palette_color("shell", marker_alpha)
					)
			VariantId.FACET_DART:
				draw_line(
					marker_position - Vector2(marker_radius * 1.35, 0.0),
					marker_position + Vector2(marker_radius * 0.35, 0.0),
					_palette_color("highlight", marker_alpha),
					maxf(marker_radius * 0.18, 1.0),
					true
				)


func _draw_hit_effect(radius: float, progress: float) -> void:
	var fade: float = 1.0 - progress
	var center: Vector2 = _projectile_position
	match _variant_id:
		VariantId.TEAR_CORE:
			var splash: PackedVector2Array = _ellipse_points(
				center,
				Vector2(radius * lerpf(1.18, 1.85, progress), radius * lerpf(0.38, 0.10, progress)),
				24
			)
			_fill_polygon(splash, _palette_color("shell", fade * 0.72))
			_draw_expanding_ring(center, radius, progress, fade)
		VariantId.CROSS_SEED:
			var cross_burst: PackedVector2Array = _transform_points(
				_geometry,
				center,
				Vector2.ONE * radius * lerpf(0.85, 2.05, progress)
			)
			_fill_polygon(cross_burst, _palette_color("shell", fade * 0.58))
		VariantId.GAP_RING:
			draw_arc(
				center,
				radius * lerpf(0.68, 2.2, progress),
				-PI + 0.36 * fade,
				PI - 0.36 * fade,
				40,
				_palette_color("shell", fade),
				maxf(radius * lerpf(0.30, 0.08, progress), 1.0),
				true
			)
		VariantId.ROUND_CAPSULE:
			for side in [-1.0, 1.0]:
				draw_circle(
					center + Vector2(0.0, side * radius * lerpf(0.25, 1.65, progress)),
					radius * lerpf(0.46, 0.12, progress),
					_palette_color("shell", fade)
				)
			_draw_expanding_ring(center, radius * 0.8, progress, fade * 0.72)
		VariantId.TRI_LOBE_CROWN:
			for lobe_index in range(3):
				var angle: float = float(lobe_index) * TAU / 3.0
				var lobe_center: Vector2 = center + Vector2.from_angle(angle) * radius * lerpf(0.25, 1.7, progress)
				draw_arc(
					lobe_center,
					radius * 0.48,
					angle - 0.75,
					angle + 0.75,
					12,
					_palette_color("shell", fade),
					maxf(radius * 0.13, 1.0),
					true
				)
		VariantId.FACET_DART:
			for fragment_index in range(4):
				var angle: float = float(fragment_index) * TAU / 4.0
				var fragment_center: Vector2 = center + Vector2.from_angle(angle) * radius * lerpf(0.3, 1.8, progress)
				var fragment := PackedVector2Array([
					fragment_center + Vector2.from_angle(angle) * radius * 0.28,
					fragment_center + Vector2.from_angle(angle + 2.25) * radius * 0.17,
					fragment_center + Vector2.from_angle(angle - 2.25) * radius * 0.17,
				])
				_fill_polygon(fragment, _palette_color("shell", fade))


func _draw_expanding_ring(center: Vector2, radius: float, progress: float, alpha: float) -> void:
	draw_arc(
		center,
		radius * lerpf(0.72, 2.1, progress),
		0.0,
		TAU,
		32,
		_palette_color("highlight", alpha),
		maxf(radius * lerpf(0.16, 0.05, progress), 1.0),
		true
	)


func _rebuild_trail(travel_time: float) -> void:
	_trail_positions.clear()
	var travelled: float = _speed * travel_time
	var sample_count: int = mini(
		MAX_TRAIL_SAMPLES,
		int(floor(travelled / TRAIL_SPACING))
	)
	for sample_index in range(sample_count, 0, -1):
		_trail_positions.append(
			_projectile_position - Vector2(TRAIL_SPACING * float(sample_index), 0.0)
		)


func _palette_color(role: String, alpha: float) -> Color:
	var color: Color
	if _team_palette == TeamPalette.ENEMY_RED:
		match role:
			"outline":
				color = ENEMY_OUTLINE
			"inner":
				color = ENEMY_INNER
			"highlight":
				color = ENEMY_HIGHLIGHT
			_:
				color = ENEMY_SHELL
	else:
		match role:
			"outline":
				color = PLAYER_OUTLINE
			"inner":
				color = PLAYER_INNER
			"highlight":
				color = PLAYER_HIGHLIGHT
			_:
				color = PLAYER_SHELL
	color.a *= clampf(alpha, 0.0, 1.0)
	return color


func _build_geometry(variant_id: VariantId) -> PackedVector2Array:
	match variant_id:
		VariantId.TEAR_CORE:
			return _rounded_polygon(PackedVector2Array([
				Vector2(-0.88, 0.0),
				Vector2(-0.52, -0.62),
				Vector2(0.08, -0.86),
				Vector2(0.72, -0.64),
				Vector2(1.0, 0.0),
				Vector2(0.72, 0.64),
				Vector2(0.08, 0.86),
				Vector2(-0.52, 0.62),
			]), 0.24, 4)
		VariantId.CROSS_SEED:
			return _rounded_polygon(PackedVector2Array([
				Vector2(-0.35, -1.0),
				Vector2(0.35, -1.0),
				Vector2(0.42, -0.48),
				Vector2(1.0, -0.38),
				Vector2(1.0, 0.38),
				Vector2(0.42, 0.48),
				Vector2(0.35, 1.0),
				Vector2(-0.35, 1.0),
				Vector2(-0.42, 0.48),
				Vector2(-1.0, 0.38),
				Vector2(-1.0, -0.38),
				Vector2(-0.42, -0.48),
			]), 0.20, 4)
		VariantId.GAP_RING:
			return PackedVector2Array()
		VariantId.ROUND_CAPSULE:
			return _rounded_polygon(PackedVector2Array([
				Vector2(-0.88, -0.58),
				Vector2(0.48, -0.58),
				Vector2(0.92, -0.34),
				Vector2(1.0, 0.0),
				Vector2(0.92, 0.34),
				Vector2(0.48, 0.58),
				Vector2(-0.88, 0.58),
			]), 0.30, 4)
		VariantId.TRI_LOBE_CROWN:
			var points: PackedVector2Array = PackedVector2Array()
			for index in range(36):
				var angle: float = float(index) * TAU / 36.0
				var radial: float = 0.80 + cos(angle * 3.0) * 0.18
				points.append(Vector2.from_angle(angle) * radial)
			return points
		VariantId.FACET_DART:
			return _rounded_polygon(PackedVector2Array([
				Vector2(-0.82, 0.0),
				Vector2(-0.12, -0.72),
				Vector2(0.52, -0.48),
				Vector2(1.0, 0.0),
				Vector2(0.52, 0.48),
				Vector2(-0.12, 0.72),
			]), 0.22, 4)
	return PackedVector2Array()


func _rounded_polygon(
	base_points: PackedVector2Array,
	rounding: float,
	samples_per_corner: int
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for index in range(base_points.size()):
		var previous_index: int = posmod(index - 1, base_points.size())
		var next_index: int = (index + 1) % base_points.size()
		var corner: Vector2 = base_points[index]
		var entry: Vector2 = corner.lerp(base_points[previous_index], rounding)
		var exit_point: Vector2 = corner.lerp(base_points[next_index], rounding)
		for sample_index in range(samples_per_corner):
			var ratio: float = float(sample_index) / float(samples_per_corner - 1)
			var inverse_ratio: float = 1.0 - ratio
			result.append(
				entry * inverse_ratio * inverse_ratio
				+ corner * 2.0 * inverse_ratio * ratio
				+ exit_point * ratio * ratio
			)
	return result


func _transform_points(
	points: PackedVector2Array,
	center: Vector2,
	scale_factor: Vector2
) -> PackedVector2Array:
	var transformed: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		transformed.append(center + point * scale_factor)
	return transformed


func _ellipse_points(
	center: Vector2,
	extents: Vector2,
	point_count: int
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for index in range(point_count):
		var angle: float = float(index) * TAU / float(point_count)
		result.append(center + Vector2(cos(angle) * extents.x, sin(angle) * extents.y))
	return result


func _fill_polygon(points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(points)
	for index in range(0, indices.size(), 3):
		var triangle := PackedVector2Array([
			points[indices[index]],
			points[indices[index + 1]],
			points[indices[index + 2]],
		])
		draw_colored_polygon(triangle, color)
