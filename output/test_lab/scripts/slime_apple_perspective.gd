class_name TestLabSlimeApplePerspective
extends TestLabSlimeCrossPerspective

const APPLE_REST_OUTLINE: Array[Vector2] = [
	Vector2(-24.0, -112.0),
	Vector2(-18.0, -156.0),
	Vector2(2.0, -176.0),
	Vector2(14.0, -142.0),
	Vector2(40.0, -152.0),
	Vector2(122.0, -166.0),
	Vector2(92.0, -120.0),
	Vector2(44.0, -112.0),
	Vector2(104.0, -88.0),
	Vector2(140.0, -34.0),
	Vector2(144.0, 40.0),
	Vector2(112.0, 108.0),
	Vector2(54.0, 150.0),
	Vector2(0.0, 164.0),
	Vector2(-62.0, 148.0),
	Vector2(-116.0, 104.0),
	Vector2(-142.0, 40.0),
	Vector2(-138.0, -34.0),
	Vector2(-102.0, -88.0),
	Vector2(-58.0, -120.0),
]


func _draw() -> void:
	if _points.is_empty():
		return
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	var closed_boundary := PackedVector2Array(boundary)
	closed_boundary.append(boundary[0])

	draw_polyline(closed_boundary, Color(0.008, 0.010, 0.026, 0.96), 30.0, true)
	draw_polyline(closed_boundary, Color(0.30, 0.18, 0.62, 0.40), 20.0, true)
	draw_polyline(closed_boundary, Color(0.55, 0.92, 0.66, 0.98), 8.0, true)
	draw_polyline(closed_boundary, Color(0.96, 0.88, 0.60, 0.82), 2.4, true)


func apple_size() -> Vector2:
	return _point_bounds(_points).size


func apple_body_size() -> Vector2:
	if _points.size() != APPLE_REST_OUTLINE.size():
		return Vector2.ZERO
	var body_points: Array[Vector2] = []
	for point_index in range(7, _points.size()):
		body_points.append(_points[point_index])
	body_points.append(_points[0])
	return _point_bounds(body_points).size


func stem_height() -> float:
	if _points.size() != APPLE_REST_OUTLINE.size():
		return 0.0
	var shoulder_height: float = minf(_points[0].y, _points[7].y)
	return shoulder_height - _points[2].y


func leaf_reach() -> float:
	if _points.size() != APPLE_REST_OUTLINE.size():
		return 0.0
	return maxf(maxf(_points[4].x, _points[5].x), _points[6].x) - _points[3].x


func top_notch_depth() -> float:
	if _points.size() != APPLE_REST_OUTLINE.size():
		return 0.0
	return _points[0].y - minf(_points[19].y, _points[7].y)


func bottom_rounding_depth() -> float:
	if _points.size() != APPLE_REST_OUTLINE.size():
		return 0.0
	return _points[13].y - maxf(_points[12].y, _points[14].y)


func internal_feature_line_count() -> int:
	return 0


func draws_debug_rig() -> bool:
	return false


func _rest_outline_source() -> Array[Vector2]:
	return APPLE_REST_OUTLINE
