class_name TestLabGlowOrbBulletSample
extends Node2D

## Four-control-point slime-rim projectile used only by the Test Lab.

enum TeamPalette {
	PLAYER_WHITE,
	ENEMY_RED,
}

const TEAM_COUNT: int = 2
const EDGE_CONTROL_NODE_COUNT: int = 4
const CURVE_SAMPLES_PER_SEGMENT: int = 16
const MAX_TRAIL_SAMPLES: int = 6
const TRAIL_SPACING: float = 7.0
const IMPACT_DURATION: float = 0.24
const POST_IMPACT_HOLD: float = 0.20
const RIM_WIDTH_RATIO: float = 0.12
const MIN_RIM_WIDTH: float = 1.0
const CURVE_CENTRIPETAL_ALPHA: float = 0.5
const CURVE_MIN_KNOT_SPACING: float = 0.0001

const EDGE_NODE_NAMES := [
	"EdgeEast",
	"EdgeSouth",
	"EdgeWest",
	"EdgeNorth",
]
const EDGE_NODE_DIRECTIONS := [
	Vector2(1.0, 0.0),
	Vector2(0.0, 1.0),
	Vector2(-1.0, 0.0),
	Vector2(0.0, -1.0),
]

const PLAYER_BODY: Color = Color("dceaf2")
const PLAYER_EDGE: Color = Color("f6fbff")
const ENEMY_BODY: Color = Color("e62935")
const ENEMY_EDGE: Color = Color("ff5963")
const HITBOX_COLOR: Color = Color(0.26, 0.96, 0.78, 0.72)

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
var _trail_positions: Array[Vector2] = []
var _edge_control_nodes: Array[Node2D] = []


func _ready() -> void:
	_build_edge_control_nodes()
	_sync_edge_control_nodes()


func configure(
	team_palette: TeamPalette,
	hit_radius: float,
	preview_scale: float,
	speed: float = 0.0,
	lane_length: float = 0.0,
	phase_offset: float = 0.0
) -> void:
	_team_palette = team_palette
	_hit_radius = maxf(hit_radius, 1.0)
	_preview_scale = maxf(preview_scale, 0.1)
	_speed = maxf(speed, 0.0)
	_lane_length = maxf(lane_length, 0.0)
	_phase_offset = phase_offset
	_is_moving = _speed > 0.0 and _lane_length > 0.0
	reset_preview()


func set_preview_time(value: float) -> void:
	_preview_time = maxf(value, 0.0)
	if not _is_moving:
		_projectile_position = Vector2.ZERO
		_impact_progress = -1.0
		_trail_positions.clear()
		_sync_edge_control_nodes()
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
	_sync_edge_control_nodes()
	queue_redraw()


func reset_preview() -> void:
	_preview_time = 0.0
	_projectile_position = Vector2.ZERO
	_impact_progress = -1.0
	_trail_positions.clear()
	_sync_edge_control_nodes()
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
	_sync_edge_control_nodes()
	queue_redraw()


func team_palette() -> int:
	return int(_team_palette)


func geometry_signature() -> String:
	return "circle:r1.0:four_edge_nodes:catmull_rom:no_highlight:no_shader:no_glow"


func body_render_mode() -> String:
	return "four_node_slime_rim"


func primary_color() -> Color:
	return ENEMY_BODY if _team_palette == TeamPalette.ENEMY_RED else PLAYER_BODY


func rim_color() -> Color:
	return ENEMY_EDGE if _team_palette == TeamPalette.ENEMY_RED else PLAYER_EDGE


func rim_width_pixels() -> float:
	return _rim_width(_hit_radius * _preview_scale)


func core_visual_extent() -> float:
	var maximum_extent: float = 0.0
	for body_point: Vector2 in _smoothed_body_points():
		maximum_extent = maxf(
			maximum_extent,
			body_point.distance_to(_projectile_position)
		)
	return maximum_extent


func visual_body_extent() -> float:
	var radius: float = _hit_radius * _preview_scale
	return core_visual_extent() + _rim_width(radius) * 0.5


func external_glow_extent() -> float:
	return 0.0


func collision_radius() -> float:
	return _hit_radius * _preview_scale


func configured_hit_radius() -> float:
	return _hit_radius


func preview_speed() -> float:
	return _speed


func trail_sample_count() -> int:
	return _trail_positions.size()


func effect_child_count() -> int:
	return maxi(get_child_count() - _edge_control_nodes.size(), 0)


func edge_control_node_count() -> int:
	return _edge_control_nodes.size()


func smoothed_boundary_point_count() -> int:
	return _smoothed_body_points().size()


func edge_controls_form_cardinal_ring() -> bool:
	if _edge_control_nodes.size() != EDGE_CONTROL_NODE_COUNT:
		return false
	var radius: float = _hit_radius * _preview_scale
	var expected_radius: float = _edge_control_radius(radius)
	for index in range(EDGE_CONTROL_NODE_COUNT):
		var offset: Vector2 = _edge_control_nodes[index].position - _projectile_position
		if not is_equal_approx(offset.length(), expected_radius):
			return false
		if offset.normalized().dot(EDGE_NODE_DIRECTIONS[index]) < 0.999:
			return false
	return true


func rim_color_differs_from_body() -> bool:
	var body: Color = primary_color()
	var edge: Color = rim_color()
	return Vector3(body.r, body.g, body.b).distance_to(Vector3(edge.r, edge.g, edge.b)) > 0.08


func has_localized_highlight() -> bool:
	return false


func is_impact_active() -> bool:
	return _impact_progress >= 0.0 and _impact_progress <= 1.0


func _draw() -> void:
	var radius: float = _hit_radius * _preview_scale
	if _show_trail and _impact_progress < 0.0:
		_draw_trail(radius)
	if _impact_progress < 0.0:
		_draw_body(radius)
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
	if _impact_progress >= 0.0 and _impact_progress <= 1.0:
		_draw_hit_effect(radius, _impact_progress)


func _draw_body(radius: float) -> void:
	var body_points: PackedVector2Array = _smoothed_body_points()
	if body_points.size() < 3:
		return
	var closed_points := PackedVector2Array(body_points)
	closed_points.append(body_points[0])
	draw_colored_polygon(body_points, _color("body", 1.0))
	draw_polyline(closed_points, _color("edge", 1.0), _rim_width(radius), true)


func _draw_trail(radius: float) -> void:
	for index in range(_trail_positions.size()):
		var ratio: float = float(index + 1) / float(_trail_positions.size() + 1)
		var marker_radius: float = radius * lerpf(0.12, 0.34, ratio)
		var marker_position: Vector2 = _trail_positions[index]
		draw_circle(marker_position, marker_radius, _color("edge", ratio * 0.26))
		draw_circle(marker_position, marker_radius * 0.68, _color("body", ratio * 0.34))


func _draw_hit_effect(radius: float, progress: float) -> void:
	var fade: float = 1.0 - progress
	var center: Vector2 = _projectile_position
	draw_arc(
		center,
		radius * lerpf(0.58, 2.05, progress),
		0.0,
		TAU,
		32,
		_color("edge", fade * 0.92),
		maxf(radius * lerpf(0.16, 0.04, progress), 1.0),
		true
	)
	for index in range(6):
		var angle: float = float(index) * TAU / 6.0
		var spark_center: Vector2 = center + Vector2.from_angle(angle) * radius * lerpf(0.34, 1.65, progress)
		var spark_radius: float = radius * lerpf(0.11, 0.025, progress)
		draw_circle(spark_center, spark_radius, _color("edge", fade * 0.80))
		draw_circle(spark_center, spark_radius * 0.62, _color("body", fade * 0.85))


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


func _build_edge_control_nodes() -> void:
	if not _edge_control_nodes.is_empty():
		return
	for index in range(EDGE_CONTROL_NODE_COUNT):
		var edge_node := Node2D.new()
		edge_node.name = EDGE_NODE_NAMES[index]
		add_child(edge_node)
		_edge_control_nodes.append(edge_node)


func _sync_edge_control_nodes() -> void:
	if _edge_control_nodes.size() != EDGE_CONTROL_NODE_COUNT:
		return
	var radius: float = _hit_radius * _preview_scale
	var control_radius: float = _edge_control_radius(radius)
	for index in range(EDGE_CONTROL_NODE_COUNT):
		_edge_control_nodes[index].position = (
			_projectile_position + EDGE_NODE_DIRECTIONS[index] * control_radius
		)


func _edge_control_radius(radius: float) -> float:
	return maxf(radius - _rim_width(radius) * 0.5, 0.5)


func _rim_width(radius: float) -> float:
	return maxf(radius * RIM_WIDTH_RATIO, MIN_RIM_WIDTH)


func _smoothed_body_points() -> PackedVector2Array:
	var smoothed_points := PackedVector2Array()
	if _edge_control_nodes.size() < EDGE_CONTROL_NODE_COUNT:
		return smoothed_points
	var control_points: Array[Vector2] = []
	for edge_node: Node2D in _edge_control_nodes:
		control_points.append(edge_node.position)

	for index in range(control_points.size()):
		var previous_point: Vector2 = control_points[posmod(index - 1, control_points.size())]
		var current_point: Vector2 = control_points[index]
		var next_point: Vector2 = control_points[(index + 1) % control_points.size()]
		var next_next_point: Vector2 = control_points[(index + 2) % control_points.size()]
		for sample_index in range(CURVE_SAMPLES_PER_SEGMENT):
			var segment_ratio: float = float(sample_index) / float(CURVE_SAMPLES_PER_SEGMENT)
			smoothed_points.append(
				_sample_centripetal_catmull_rom(
					previous_point,
					current_point,
					next_point,
					next_next_point,
					segment_ratio
				)
			)
	return smoothed_points


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


func _curve_knot(previous_time: float, from_point: Vector2, to_point: Vector2) -> float:
	var point_distance: float = maxf(from_point.distance_to(to_point), CURVE_MIN_KNOT_SPACING)
	return previous_time + pow(point_distance, CURVE_CENTRIPETAL_ALPHA)


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


func _color(role: String, alpha: float) -> Color:
	var color: Color
	if _team_palette == TeamPalette.ENEMY_RED:
		color = ENEMY_EDGE if role == "edge" else ENEMY_BODY
	else:
		color = PLAYER_EDGE if role == "edge" else PLAYER_BODY
	color.a *= clampf(alpha, 0.0, 1.0)
	return color
