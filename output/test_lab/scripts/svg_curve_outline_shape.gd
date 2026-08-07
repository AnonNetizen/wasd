class_name TestLabSvgCurveOutlineShape
extends Node2D

const CURVE_IMPORTER_SCRIPT := preload("res://scripts/svg_curve_importer.gd")
const CONTROLS_OVERLAY_SCRIPT := preload("res://scripts/svg_curve_controls_overlay.gd")
const PERSPECTIVE_SHADER: Shader = preload("res://shaders/anchored_star_window.gdshader")
const DEFAULT_SVG_SOURCE_PATH: String = "res://assets/svg_curve/pear_source.svg"
const TESSELLATION_LENGTH: float = 3.0
const DEFAULT_BORDER_WIDTH: float = 12.0
const MIN_BORDER_WIDTH: float = 0.5
const MAX_BORDER_WIDTH: float = 30.0
const DEFAULT_BORDER_COLOR := Color(0.48, 0.82, 0.58, 1.0)
const DEFAULT_STAR_SCALE: float = 0.82

var _curves: Array[Curve2D] = []
var _contour := PackedVector2Array()
var _material: ShaderMaterial
var _fill_mesh_instance: MeshInstance2D
var _border_line: Line2D
var _controls_overlay: TestLabSvgCurveControlsOverlay
var _source_bounds := Rect2()
var _curve_segment_count: int = 0
var _curve_point_count: int = 0
var _tessellated_point_count: int = 0
var _triangle_count: int = 0
var _expected_fill_area: float = 0.0
var _mesh_fill_area: float = 0.0
var _fill_sample_points := PackedVector2Array()
var _border_sample_points := PackedVector2Array()
var _svg_source_path: String = DEFAULT_SVG_SOURCE_PATH
var _border_color: Color = DEFAULT_BORDER_COLOR
var _star_scale: float = DEFAULT_STAR_SCALE


func _ready() -> void:
	_load_svg_curve()


func configure(source_path: String, border_color: Color, star_scale: float) -> void:
	if is_inside_tree():
		push_error("SVG curve outline must be configured before entering the scene tree.")
		return
	if source_path.is_empty():
		push_error("SVG curve outline source path must not be empty.")
		return
	_svg_source_path = source_path
	_border_color = border_color
	_star_scale = clampf(star_scale, 0.05, 2.0)


func set_animation_time(time_seconds: float) -> void:
	if _material != null:
		_material.set_shader_parameter("animation_time", maxf(time_seconds, 0.0))


func set_viewport_aspect(viewport_aspect: float) -> void:
	if _material != null:
		_material.set_shader_parameter("viewport_aspect", maxf(viewport_aspect, 0.01))


func set_border_width(width: float) -> void:
	if _border_line != null:
		_border_line.width = clampf(width, MIN_BORDER_WIDTH, MAX_BORDER_WIDTH)


func border_width() -> float:
	return _border_line.width if _border_line != null else 0.0


func border_color() -> Color:
	return _border_color


func border_line_count() -> int:
	return 1 if _border_line != null else 0


func border_uses_shader() -> bool:
	return _border_line != null and _border_line.material is ShaderMaterial


func set_controls_visible(controls_visible: bool) -> void:
	if _controls_overlay != null:
		_controls_overlay.visible = controls_visible


func controls_visible() -> bool:
	return _controls_overlay != null and _controls_overlay.visible


func controls_overlay_count() -> int:
	return 1 if _controls_overlay != null else 0


func control_anchor_count() -> int:
	return _controls_overlay.anchor_count() if _controls_overlay != null else 0


func control_handle_count() -> int:
	return _controls_overlay.handle_count() if _controls_overlay != null else 0


func control_anchor_points() -> PackedVector2Array:
	return _controls_overlay.anchor_points() if _controls_overlay != null else PackedVector2Array()


func control_in_handle_points() -> PackedVector2Array:
	return _controls_overlay.in_handle_points() if _controls_overlay != null else PackedVector2Array()


func control_out_handle_points() -> PackedVector2Array:
	return _controls_overlay.out_handle_points() if _controls_overlay != null else PackedVector2Array()


func control_anchor_color() -> Color:
	return _controls_overlay.anchor_color() if _controls_overlay != null else Color.TRANSPARENT


func control_in_handle_color() -> Color:
	return _controls_overlay.in_handle_color() if _controls_overlay != null else Color.TRANSPARENT


func control_out_handle_color() -> Color:
	return _controls_overlay.out_handle_color() if _controls_overlay != null else Color.TRANSPARENT


func subpath_count() -> int:
	return _curves.size()


func path_node_count() -> int:
	var count: int = 0
	for child in get_children():
		if child is Path2D:
			count += 1
	return count


func curve_segment_count() -> int:
	return _curve_segment_count


func curve_point_count() -> int:
	return _curve_point_count


func tessellated_point_count() -> int:
	return _tessellated_point_count


func triangle_count() -> int:
	return _triangle_count


func source_bounds() -> Rect2:
	return _source_bounds


func fill_area_ratio() -> float:
	return _mesh_fill_area / maxf(_expected_fill_area, 0.001)


func perspective_material() -> ShaderMaterial:
	return _material


func fill_sample_points() -> PackedVector2Array:
	return _fill_sample_points


func border_sample_points() -> PackedVector2Array:
	return _border_sample_points


func all_curves_closed() -> bool:
	if _curves.size() != 1:
		return false
	var curve: Curve2D = _curves[0]
	if curve.point_count < 3:
		return false
	return curve.get_point_position(0).distance_to(
		curve.get_point_position(curve.point_count - 1)
	) <= 0.01


func _load_svg_curve() -> void:
	var svg_source := FileAccess.get_file_as_string(_svg_source_path)
	if svg_source.is_empty():
		push_error("Failed to read SVG curve source: %s" % _svg_source_path)
		return
	var importer := CURVE_IMPORTER_SCRIPT.new() as TestLabSvgCurveImporter
	var import_result: Dictionary = importer.parse(svg_source)
	if not bool(import_result.get("ok", false)):
		push_error("SVG curve import failed: %s" % String(import_result.get("error", "")))
		return
	var segment_counts: Array = import_result.get("segment_counts", [])
	for segment_count: Variant in segment_counts:
		_curve_segment_count += int(segment_count)
	var curve_values: Array = import_result.get("curves", [])
	for curve_value: Variant in curve_values:
		var curve := curve_value as Curve2D
		if curve != null:
			_curves.append(curve)
	if _curves.size() != 1:
		push_error("Single-outline SVG source must produce exactly one Curve2D.")
		return

	_normalize_curve()
	_create_path_and_contour()
	_build_fill_mesh()
	_build_border_line()
	_build_controls_overlay()


func _normalize_curve() -> void:
	var curve: Curve2D = _curves[0]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point_index in range(curve.point_count):
		var point_position := curve.get_point_position(point_index)
		minimum.x = minf(minimum.x, point_position.x)
		minimum.y = minf(minimum.y, point_position.y)
		maximum.x = maxf(maximum.x, point_position.x)
		maximum.y = maxf(maximum.y, point_position.y)
	var center: Vector2 = (minimum + maximum) * 0.5
	for point_index in range(curve.point_count):
		curve.set_point_position(
			point_index,
			curve.get_point_position(point_index) - center
		)


func _create_path_and_contour() -> void:
	var curve: Curve2D = _curves[0]
	_curve_point_count = curve.point_count
	var path := Path2D.new()
	path.name = "SvgOutlinePath"
	path.curve = curve
	add_child(path)

	_contour = _sanitize_closed_contour(
		curve.tessellate_even_length(8, TESSELLATION_LENGTH)
	)
	_tessellated_point_count = _contour.size()
	if _contour.size() < 3:
		push_error("SVG outline tessellation produced fewer than three points.")
		return
	_source_bounds = Rect2(_contour[0], Vector2.ZERO)
	for point in _contour:
		_source_bounds = _source_bounds.expand(point)
	_expected_fill_area = absf(_signed_area(_contour))


func _build_fill_mesh() -> void:
	var triangle_indices: PackedInt32Array = Geometry2D.triangulate_polygon(_contour)
	var expanded_vertices := PackedVector3Array()
	for triangle_offset in range(0, triangle_indices.size(), 3):
		if triangle_offset + 2 >= triangle_indices.size():
			break
		var point_a: Vector2 = _contour[triangle_indices[triangle_offset]]
		var point_b: Vector2 = _contour[triangle_indices[triangle_offset + 1]]
		var point_c: Vector2 = _contour[triangle_indices[triangle_offset + 2]]
		expanded_vertices.append(Vector3(point_a.x, point_a.y, 0.0))
		expanded_vertices.append(Vector3(point_b.x, point_b.y, 0.0))
		expanded_vertices.append(Vector3(point_c.x, point_c.y, 0.0))
		_mesh_fill_area += absf((point_b - point_a).cross(point_c - point_a)) * 0.5
		_fill_sample_points.append((point_a + point_b + point_c) / 3.0)
	_triangle_count = expanded_vertices.size() / 3
	if expanded_vertices.is_empty():
		push_error("SVG outline fill triangulation produced no triangles.")
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = expanded_vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_material = ShaderMaterial.new()
	_material.shader = PERSPECTIVE_SHADER
	_material.set_shader_parameter("animation_time", 0.0)
	_material.set_shader_parameter("star_scale", _star_scale)
	_fill_mesh_instance = MeshInstance2D.new()
	_fill_mesh_instance.name = "CurveInteriorMesh"
	_fill_mesh_instance.mesh = mesh
	_fill_mesh_instance.material = _material
	add_child(_fill_mesh_instance)
	move_child(_fill_mesh_instance, 0)


func _build_border_line() -> void:
	var closed_points := PackedVector2Array(_contour)
	closed_points.append(closed_points[0])
	_border_line = Line2D.new()
	_border_line.name = "AdjustableCurveBorder"
	_border_line.points = closed_points
	_border_line.width = DEFAULT_BORDER_WIDTH
	_border_line.default_color = _border_color
	_border_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_border_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_border_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_border_line.antialiased = true
	add_child(_border_line)
	move_child(_border_line, 1)

	var sample_step: int = maxi(_contour.size() / 64, 1)
	for point_index in range(0, _contour.size(), sample_step):
		_border_sample_points.append(_contour[point_index])


func _build_controls_overlay() -> void:
	_controls_overlay = CONTROLS_OVERLAY_SCRIPT.new() as TestLabSvgCurveControlsOverlay
	_controls_overlay.name = "SvgBezierControls"
	_controls_overlay.z_index = 20
	_controls_overlay.configure(_curves[0])
	_controls_overlay.visible = true
	add_child(_controls_overlay)


func _signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for point_index in range(points.size()):
		area += points[point_index].cross(points[(point_index + 1) % points.size()])
	return area * 0.5


func _sanitize_closed_contour(points: PackedVector2Array) -> PackedVector2Array:
	var sanitized := PackedVector2Array()
	for point in points:
		if sanitized.is_empty() or sanitized[-1].distance_to(point) > 0.01:
			sanitized.append(point)
	while sanitized.size() > 1 and sanitized[0].distance_to(sanitized[-1]) <= 0.01:
		sanitized.resize(sanitized.size() - 1)
	return sanitized
