class_name TestLabSvgCurveCompoundShape
extends Node2D

const CURVE_IMPORTER_SCRIPT := preload("res://scripts/svg_curve_importer.gd")
const PERSPECTIVE_SHADER: Shader = preload("res://shaders/anchored_star_window.gdshader")
const SVG_SOURCE_PATH: String = "res://assets/svg_curve/pear_source.svg"
const TESSELLATION_LENGTH: float = 3.0

var _curves: Array[Curve2D] = []
var _contours: Array[PackedVector2Array] = []
var _curve_lines: Array[Line2D] = []
var _edge_mesh_instance: MeshInstance2D
var _material: ShaderMaterial
var _mesh_instance: MeshInstance2D
var _source_bounds := Rect2()
var _curve_segment_count: int = 0
var _curve_point_count: int = 0
var _tessellated_point_count: int = 0
var _hole_count: int = 0
var _edge_triangle_count: int = 0
var _triangle_count: int = 0
var _expected_edge_area: float = 0.0
var _edge_mesh_area: float = 0.0
var _expected_fill_area: float = 0.0
var _mesh_fill_area: float = 0.0
var _fill_sample_points := PackedVector2Array()
var _fill_sample_groups: Array[PackedVector2Array] = []
var _interior_contour_indices: Array[int] = []


func _ready() -> void:
	_load_svg_curves()


func set_animation_time(time_seconds: float) -> void:
	if _material != null:
		_material.set_shader_parameter("animation_time", maxf(time_seconds, 0.0))


func set_viewport_aspect(viewport_aspect: float) -> void:
	if _material != null:
		_material.set_shader_parameter("viewport_aspect", maxf(viewport_aspect, 0.01))


func set_curve_overlay_visible(visible: bool) -> void:
	for curve_line in _curve_lines:
		curve_line.visible = visible


func curve_overlay_visible() -> bool:
	return not _curve_lines.is_empty() and _curve_lines[0].visible


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


func hole_count() -> int:
	return _hole_count


func triangle_count() -> int:
	return _triangle_count


func edge_triangle_count() -> int:
	return _edge_triangle_count


func source_bounds() -> Rect2:
	return _source_bounds


func fill_area_ratio() -> float:
	return _mesh_fill_area / maxf(_expected_fill_area, 0.001)


func edge_area_ratio() -> float:
	return _edge_mesh_area / maxf(_expected_edge_area, 0.001)


func edge_uses_shader() -> bool:
	return _edge_mesh_instance != null and _edge_mesh_instance.material is ShaderMaterial


func perspective_material() -> ShaderMaterial:
	return _material


func fill_sample_points() -> PackedVector2Array:
	return _fill_sample_points


func fill_sample_groups() -> Array[PackedVector2Array]:
	return _fill_sample_groups


func all_curves_closed() -> bool:
	if _curves.is_empty():
		return false
	for curve in _curves:
		if curve.point_count < 3:
			return false
		if curve.get_point_position(0).distance_to(
			curve.get_point_position(curve.point_count - 1)
		) > 0.01:
			return false
	return true


func _load_svg_curves() -> void:
	var svg_source := FileAccess.get_file_as_string(SVG_SOURCE_PATH)
	if svg_source.is_empty():
		push_error("Failed to read SVG curve source: %s" % SVG_SOURCE_PATH)
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
	if _curves.is_empty():
		push_error("SVG importer produced no Curve2D resources.")
		return

	_normalize_curves()
	_create_path_nodes_and_contours()
	_build_compound_mesh()


func _normalize_curves() -> void:
	var has_point: bool = false
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for curve in _curves:
		for point_index in range(curve.point_count):
			var point_position := curve.get_point_position(point_index)
			minimum.x = minf(minimum.x, point_position.x)
			minimum.y = minf(minimum.y, point_position.y)
			maximum.x = maxf(maximum.x, point_position.x)
			maximum.y = maxf(maximum.y, point_position.y)
			has_point = true
	if not has_point:
		return
	var center: Vector2 = (minimum + maximum) * 0.5
	for curve in _curves:
		for point_index in range(curve.point_count):
			curve.set_point_position(
				point_index,
				curve.get_point_position(point_index) - center
			)


func _create_path_nodes_and_contours() -> void:
	var bounds_initialized: bool = false
	var largest_area_magnitude: float = 0.0
	var largest_area_sign: float = 0.0
	var signed_areas: Array[float] = []
	for curve_index in range(_curves.size()):
		var curve := _curves[curve_index]
		_curve_point_count += curve.point_count
		var path := Path2D.new()
		path.name = "SvgCurvePath%d" % curve_index
		path.curve = curve
		add_child(path)

		var contour: PackedVector2Array = _sanitize_closed_contour(
			curve.tessellate_even_length(8, TESSELLATION_LENGTH)
		)
		_contours.append(contour)
		_tessellated_point_count += contour.size()
		var signed_area: float = _signed_area(contour)
		signed_areas.append(signed_area)
		if absf(signed_area) > largest_area_magnitude:
			largest_area_magnitude = absf(signed_area)
			largest_area_sign = signf(signed_area)
		for point in contour:
			if not bounds_initialized:
				_source_bounds = Rect2(point, Vector2.ZERO)
				bounds_initialized = true
			else:
				_source_bounds = _source_bounds.expand(point)

		var curve_line := Line2D.new()
		curve_line.name = "CurveOverlay%d" % curve_index
		var overlay_points := PackedVector2Array(contour)
		if not overlay_points.is_empty():
			overlay_points.append(overlay_points[0])
		curve_line.points = overlay_points
		curve_line.width = 1.2
		curve_line.default_color = Color(0.92, 0.62, 1.0, 0.86)
		curve_line.antialiased = true
		curve_line.visible = false
		add_child(curve_line)
		_curve_lines.append(curve_line)
	_expected_edge_area = absf(_sum_values(signed_areas))
	for contour_index in range(signed_areas.size()):
		var signed_area: float = signed_areas[contour_index]
		if signf(signed_area) != largest_area_sign:
			_hole_count += 1
			_interior_contour_indices.append(contour_index)
			_expected_fill_area += absf(signed_area)


func _build_compound_mesh() -> void:
	var navigation_polygon := NavigationPolygon.new()
	navigation_polygon.agent_radius = 0.0
	navigation_polygon.cell_size = 0.01
	var source_geometry := NavigationMeshSourceGeometryData2D.new()
	var outer_index: int = 0
	for contour_index in range(1, _contours.size()):
		if absf(_signed_area(_contours[contour_index])) > absf(
			_signed_area(_contours[outer_index])
		):
			outer_index = contour_index
	var outer_winding_sign: float = signf(_signed_area(_contours[outer_index]))
	for contour_index in range(_contours.size()):
		var contour: PackedVector2Array = _contours[contour_index]
		if contour_index == outer_index or signf(_signed_area(contour)) == outer_winding_sign:
			source_geometry.add_traversable_outline(contour)
		else:
			source_geometry.add_obstruction_outline(contour)
	NavigationServer2D.bake_from_source_geometry_data(
		navigation_polygon,
		source_geometry
	)
	var navigation_vertices: PackedVector2Array = navigation_polygon.get_vertices()
	var edge_vertices := PackedVector3Array()
	for polygon_index in range(navigation_polygon.get_polygon_count()):
		var vertex_indices: PackedInt32Array = navigation_polygon.get_polygon(polygon_index)
		var polygon_points := PackedVector2Array()
		for vertex_index in vertex_indices:
			polygon_points.append(navigation_vertices[vertex_index])
		var triangle_indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon_points)
		for triangle_offset in range(0, triangle_indices.size(), 3):
			if triangle_offset + 2 >= triangle_indices.size():
				break
			var point_a: Vector2 = polygon_points[triangle_indices[triangle_offset]]
			var point_b: Vector2 = polygon_points[triangle_indices[triangle_offset + 1]]
			var point_c: Vector2 = polygon_points[triangle_indices[triangle_offset + 2]]
			edge_vertices.append(Vector3(point_a.x, point_a.y, 0.0))
			edge_vertices.append(Vector3(point_b.x, point_b.y, 0.0))
			edge_vertices.append(Vector3(point_c.x, point_c.y, 0.0))
			_edge_mesh_area += absf((point_b - point_a).cross(point_c - point_a)) * 0.5
	_edge_triangle_count = edge_vertices.size() / 3
	if edge_vertices.is_empty():
		push_error("SVG black-edge triangulation produced no triangles.")
		return
	_edge_mesh_instance = _create_mesh_instance(edge_vertices, "SvgBlackEdge")
	_edge_mesh_instance.self_modulate = Color(0.045, 0.085, 0.068, 1.0)
	add_child(_edge_mesh_instance)
	move_child(_edge_mesh_instance, 0)

	var fill_vertices := PackedVector3Array()
	for contour_index in _interior_contour_indices:
		var interior_contour: PackedVector2Array = _contours[contour_index]
		var region_samples := PackedVector2Array()
		var fill_triangle_indices: PackedInt32Array = Geometry2D.triangulate_polygon(
			interior_contour
		)
		for triangle_offset in range(0, fill_triangle_indices.size(), 3):
			if triangle_offset + 2 >= fill_triangle_indices.size():
				break
			var point_a: Vector2 = interior_contour[
				fill_triangle_indices[triangle_offset]
			]
			var point_b: Vector2 = interior_contour[
				fill_triangle_indices[triangle_offset + 1]
			]
			var point_c: Vector2 = interior_contour[
				fill_triangle_indices[triangle_offset + 2]
			]
			fill_vertices.append(Vector3(point_a.x, point_a.y, 0.0))
			fill_vertices.append(Vector3(point_b.x, point_b.y, 0.0))
			fill_vertices.append(Vector3(point_c.x, point_c.y, 0.0))
			_mesh_fill_area += absf((point_b - point_a).cross(point_c - point_a)) * 0.5
			var sample_point: Vector2 = (point_a + point_b + point_c) / 3.0
			_fill_sample_points.append(sample_point)
			region_samples.append(sample_point)
		_fill_sample_groups.append(region_samples)
	_triangle_count = fill_vertices.size() / 3
	if fill_vertices.is_empty():
		push_error("SVG enclosed-interior triangulation produced no triangles.")
		return
	_material = ShaderMaterial.new()
	_material.shader = PERSPECTIVE_SHADER
	_material.set_shader_parameter("animation_time", 0.0)
	_material.set_shader_parameter("star_scale", 0.82)
	_mesh_instance = _create_mesh_instance(fill_vertices, "CurveInteriorMesh")
	_mesh_instance.material = _material
	add_child(_mesh_instance)
	move_child(_mesh_instance, 1)


func _create_mesh_instance(vertices: PackedVector3Array, instance_name: String) -> MeshInstance2D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_instance := MeshInstance2D.new()
	mesh_instance.name = instance_name
	mesh_instance.mesh = mesh
	return mesh_instance


func _signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for point_index in range(points.size()):
		area += points[point_index].cross(points[(point_index + 1) % points.size()])
	return area * 0.5


func _sum_values(values: Array[float]) -> float:
	var total: float = 0.0
	for value in values:
		total += value
	return total


func _sanitize_closed_contour(points: PackedVector2Array) -> PackedVector2Array:
	var sanitized := PackedVector2Array()
	for point in points:
		if sanitized.is_empty() or sanitized[-1].distance_to(point) > 0.01:
			sanitized.append(point)
	while sanitized.size() > 1 and sanitized[0].distance_to(sanitized[-1]) <= 0.01:
		sanitized.resize(sanitized.size() - 1)
	return sanitized
