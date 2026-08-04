class_name TestLabSlimeBookPerspective
extends TestLabSlimeCrossPerspective

const BOOK_REST_OUTLINE: Array[Vector2] = [
	Vector2(0.0, -116.0),
	Vector2(28.0, -143.0),
	Vector2(86.0, -154.0),
	Vector2(146.0, -148.0),
	Vector2(184.0, -126.0),
	Vector2(192.0, -88.0),
	Vector2(194.0, 74.0),
	Vector2(183.0, 112.0),
	Vector2(128.0, 119.0),
	Vector2(58.0, 104.0),
	Vector2(0.0, 142.0),
	Vector2(-58.0, 104.0),
	Vector2(-128.0, 119.0),
	Vector2(-183.0, 112.0),
	Vector2(-194.0, 74.0),
	Vector2(-192.0, -88.0),
	Vector2(-184.0, -126.0),
	Vector2(-146.0, -148.0),
	Vector2(-86.0, -154.0),
	Vector2(-28.0, -143.0),
]
const SPINE_REST_POINTS: Array[Vector2] = [
	Vector2(0.0, -116.0),
	Vector2(0.0, -62.0),
	Vector2(0.0, -4.0),
	Vector2(0.0, 62.0),
	Vector2(0.0, 142.0),
]
const LEFT_PAGE_EDGE_REST_POINTS: Array[Vector2] = [
	Vector2(-12.0, 114.0),
	Vector2(-58.0, 91.0),
	Vector2(-112.0, 101.0),
	Vector2(-160.0, 94.0),
]
const RIGHT_PAGE_EDGE_REST_POINTS: Array[Vector2] = [
	Vector2(12.0, 114.0),
	Vector2(58.0, 91.0),
	Vector2(112.0, 101.0),
	Vector2(160.0, 94.0),
]


func _draw() -> void:
	if _points.is_empty():
		return
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	var closed_boundary := PackedVector2Array(boundary)
	closed_boundary.append(boundary[0])

	draw_polyline(closed_boundary, Color(0.008, 0.010, 0.030, 0.96), 30.0, true)
	draw_polyline(closed_boundary, Color(0.32, 0.22, 0.70, 0.42), 20.0, true)
	draw_polyline(closed_boundary, Color(0.55, 0.78, 1.0, 0.98), 8.0, true)
	draw_polyline(closed_boundary, Color(0.96, 0.91, 0.66, 0.84), 2.4, true)
	_draw_book_structure()
	_draw_impact_ripple()
	_draw_debug_rig()


func book_size() -> Vector2:
	return _point_bounds(_points).size


func top_spine_notch_depth() -> float:
	if _points.size() != BOOK_REST_OUTLINE.size():
		return 0.0
	return _points[0].y - minf(_points[1].y, _points[19].y)


func bottom_spine_projection() -> float:
	if _points.size() != BOOK_REST_OUTLINE.size():
		return 0.0
	return _points[10].y - maxf(_points[9].y, _points[11].y)


func page_symmetry_error() -> float:
	if _points.size() != BOOK_REST_OUTLINE.size():
		return INF
	var total_error: float = absf(_points[0].x) + absf(_points[10].x)
	for right_index in range(1, 10):
		var left_index: int = 20 - right_index
		total_error += absf(_points[right_index].x + _points[left_index].x)
		total_error += absf(_points[right_index].y - _points[left_index].y)
	return total_error / 20.0


func spine_point_count() -> int:
	return SPINE_REST_POINTS.size()


func page_guide_count() -> int:
	return 2


func _rest_outline_source() -> Array[Vector2]:
	return BOOK_REST_OUTLINE


func _draw_book_structure() -> void:
	var spine: PackedVector2Array = _deformed_feature_points(SPINE_REST_POINTS)
	draw_polyline(spine, Color(0.010, 0.018, 0.050, 0.92), 12.0, true)
	draw_polyline(spine, Color(0.90, 0.82, 0.50, 0.92), 4.0, true)
	draw_polyline(spine, Color(0.80, 0.92, 1.0, 0.74), 1.4, true)

	var left_page_edge: PackedVector2Array = _deformed_feature_points(
		LEFT_PAGE_EDGE_REST_POINTS
	)
	var right_page_edge: PackedVector2Array = _deformed_feature_points(
		RIGHT_PAGE_EDGE_REST_POINTS
	)
	for page_edge in [left_page_edge, right_page_edge]:
		draw_polyline(page_edge, Color(0.015, 0.030, 0.075, 0.78), 7.0, true)
		draw_polyline(page_edge, Color(0.67, 0.84, 1.0, 0.64), 2.0, true)

	var left_inner_mark := PackedVector2Array(
		[
			_deform_inner_point(Vector2(-42.0, -104.0)),
			_deform_inner_point(Vector2(-92.0, -116.0)),
			_deform_inner_point(Vector2(-142.0, -108.0)),
		]
	)
	var right_inner_mark := PackedVector2Array(
		[
			_deform_inner_point(Vector2(42.0, -104.0)),
			_deform_inner_point(Vector2(92.0, -116.0)),
			_deform_inner_point(Vector2(142.0, -108.0)),
		]
	)
	draw_polyline(left_inner_mark, Color(0.76, 0.88, 1.0, 0.28), 1.5, true)
	draw_polyline(right_inner_mark, Color(0.76, 0.88, 1.0, 0.28), 1.5, true)


func _deformed_feature_points(rest_positions: Array[Vector2]) -> PackedVector2Array:
	var deformed := PackedVector2Array()
	for rest_position in rest_positions:
		deformed.append(_deform_inner_point(rest_position))
	return deformed
