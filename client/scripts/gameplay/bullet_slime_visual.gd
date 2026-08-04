# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §4, docs/决策记录.md ADR #181
class_name BulletSlimeVisual
extends Node2D
## Shared four-control-point slime-rim visual for pooled projectiles.


const CURVE_SAMPLES_PER_SEGMENT: int = 16
const EDGE_CONTROL_NODE_COUNT: int = 4
const CURVE_CENTRIPETAL_ALPHA: float = 0.5
const CURVE_MIN_KNOT_SPACING: float = 0.0001

const PLAYER_BODY_COLOR: Color = Color("dceaf2")
const PLAYER_RIM_COLOR: Color = Color("f6fbff")
const ENEMY_BODY_COLOR: Color = Color("e62935")
const ENEMY_RIM_COLOR: Color = Color("ff5963")

var _enemy_palette_enabled: bool = false
var _smoothed_boundary := PackedVector2Array()

@onready var _body: Polygon2D = $Body
@onready var _rim: Line2D = $Rim
@onready var _edge_control_nodes: Array[Node2D] = [
	$EdgeEast,
	$EdgeSouth,
	$EdgeWest,
	$EdgeNorth,
]


func _ready() -> void:
	_rebuild_geometry()
	_apply_palette()


func set_enemy_palette(enabled: bool) -> void:
	_enemy_palette_enabled = enabled
	_apply_palette()


func body_render_mode() -> String:
	return "four_node_slime_rim"


func geometry_signature() -> String:
	return "circle:r1.0:four_edge_nodes:catmull_rom:no_highlight:no_shader:no_glow:no_trail"


func edge_control_node_count() -> int:
	return _edge_control_nodes.size()


func smoothed_boundary_point_count() -> int:
	return _smoothed_boundary.size()


func edge_controls_form_cardinal_ring() -> bool:
	if _edge_control_nodes.size() != EDGE_CONTROL_NODE_COUNT:
		return false
	var expected_directions: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.UP,
	]
	var expected_radius: float = _edge_control_nodes[0].position.length()
	for index: int in range(EDGE_CONTROL_NODE_COUNT):
		var offset: Vector2 = _edge_control_nodes[index].position
		if not is_equal_approx(offset.length(), expected_radius):
			return false
		if offset.normalized().dot(expected_directions[index]) < 0.999:
			return false
	return true


func normalized_visual_extent() -> float:
	var maximum_extent: float = 0.0
	for point: Vector2 in _smoothed_boundary:
		maximum_extent = maxf(maximum_extent, point.length())
	return maximum_extent + _rim.width * 0.5


func body_color() -> Color:
	return _body.color if _body != null else Color.TRANSPARENT


func rim_color() -> Color:
	return _rim.default_color if _rim != null else Color.TRANSPARENT


func uses_enemy_palette() -> bool:
	return _enemy_palette_enabled


func has_shader_material() -> bool:
	return (
		(_body != null and _body.material is ShaderMaterial)
		or (_rim != null and _rim.material is ShaderMaterial)
	)


func _apply_palette() -> void:
	if _body == null or _rim == null:
		return
	_body.color = ENEMY_BODY_COLOR if _enemy_palette_enabled else PLAYER_BODY_COLOR
	_rim.default_color = ENEMY_RIM_COLOR if _enemy_palette_enabled else PLAYER_RIM_COLOR


func _rebuild_geometry() -> void:
	_smoothed_boundary = _smoothed_body_points()
	if _body != null:
		_body.polygon = _smoothed_boundary
	if _rim != null:
		_rim.points = _smoothed_boundary


func _smoothed_body_points() -> PackedVector2Array:
	var smoothed_points := PackedVector2Array()
	if _edge_control_nodes.size() != EDGE_CONTROL_NODE_COUNT:
		return smoothed_points
	var control_points: Array[Vector2] = []
	for edge_node: Node2D in _edge_control_nodes:
		control_points.append(edge_node.position)

	for index: int in range(control_points.size()):
		var previous_point: Vector2 = control_points[posmod(index - 1, control_points.size())]
		var current_point: Vector2 = control_points[index]
		var next_point: Vector2 = control_points[(index + 1) % control_points.size()]
		var next_next_point: Vector2 = control_points[(index + 2) % control_points.size()]
		for sample_index: int in range(CURVE_SAMPLES_PER_SEGMENT):
			var segment_ratio: float = (
				float(sample_index) / float(CURVE_SAMPLES_PER_SEGMENT)
			)
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
	var point_a_1: Vector2 = _interpolate_curve_point(
		point_0,
		point_1,
		time_0,
		time_1,
		sample_time
	)
	var point_a_2: Vector2 = _interpolate_curve_point(
		point_1,
		point_2,
		time_1,
		time_2,
		sample_time
	)
	var point_a_3: Vector2 = _interpolate_curve_point(
		point_2,
		point_3,
		time_2,
		time_3,
		sample_time
	)
	var point_b_1: Vector2 = _interpolate_curve_point(
		point_a_1,
		point_a_2,
		time_0,
		time_2,
		sample_time
	)
	var point_b_2: Vector2 = _interpolate_curve_point(
		point_a_2,
		point_a_3,
		time_1,
		time_3,
		sample_time
	)
	return _interpolate_curve_point(
		point_b_1,
		point_b_2,
		time_1,
		time_2,
		sample_time
	)


func _curve_knot(
	previous_time: float,
	from_point: Vector2,
	to_point: Vector2
) -> float:
	var point_distance: float = maxf(
		from_point.distance_to(to_point),
		CURVE_MIN_KNOT_SPACING
	)
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
