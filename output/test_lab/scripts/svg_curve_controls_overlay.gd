class_name TestLabSvgCurveControlsOverlay
extends Node2D

const ANCHOR_COLOR := Color(1.0, 0.86, 0.28, 1.0)
const ANCHOR_OUTLINE_COLOR := Color(0.12, 0.09, 0.03, 0.96)
const IN_HANDLE_COLOR := Color(0.25, 0.88, 1.0, 1.0)
const OUT_HANDLE_COLOR := Color(1.0, 0.38, 0.68, 1.0)
const IN_GUIDE_COLOR := Color(0.25, 0.88, 1.0, 0.72)
const OUT_GUIDE_COLOR := Color(1.0, 0.38, 0.68, 0.72)
const HANDLE_EPSILON: float = 0.01

var _curve: Curve2D
var _anchor_points := PackedVector2Array()
var _in_handle_points := PackedVector2Array()
var _out_handle_points := PackedVector2Array()


func configure(curve: Curve2D) -> void:
	_curve = curve
	_rebuild_point_cache()
	queue_redraw()


func anchor_count() -> int:
	return _anchor_points.size()


func handle_count() -> int:
	return _in_handle_points.size() + _out_handle_points.size()


func anchor_points() -> PackedVector2Array:
	return _anchor_points


func in_handle_points() -> PackedVector2Array:
	return _in_handle_points


func out_handle_points() -> PackedVector2Array:
	return _out_handle_points


func anchor_color() -> Color:
	return ANCHOR_COLOR


func in_handle_color() -> Color:
	return IN_HANDLE_COLOR


func out_handle_color() -> Color:
	return OUT_HANDLE_COLOR


func _draw() -> void:
	if _curve == null:
		return
	var unique_point_count: int = _unique_point_count()
	for point_index in range(unique_point_count):
		var anchor: Vector2 = _curve.get_point_position(point_index)
		var in_offset: Vector2 = _curve.get_point_in(point_index)
		var out_offset: Vector2 = _curve.get_point_out(point_index)
		if in_offset.length() > HANDLE_EPSILON:
			draw_line(anchor, anchor + in_offset, IN_GUIDE_COLOR, 1.15, true)
		if out_offset.length() > HANDLE_EPSILON:
			draw_line(anchor, anchor + out_offset, OUT_GUIDE_COLOR, 1.15, true)

	for handle_point in _in_handle_points:
		draw_circle(handle_point, 3.2, IN_HANDLE_COLOR)
	for handle_point in _out_handle_points:
		draw_circle(handle_point, 3.2, OUT_HANDLE_COLOR)
	for anchor in _anchor_points:
		draw_circle(anchor, 5.4, ANCHOR_OUTLINE_COLOR)
		draw_circle(anchor, 3.5, ANCHOR_COLOR)


func _rebuild_point_cache() -> void:
	_anchor_points.clear()
	_in_handle_points.clear()
	_out_handle_points.clear()
	if _curve == null:
		return
	for point_index in range(_unique_point_count()):
		var anchor: Vector2 = _curve.get_point_position(point_index)
		_anchor_points.append(anchor)
		var in_offset: Vector2 = _curve.get_point_in(point_index)
		if in_offset.length() > HANDLE_EPSILON:
			_in_handle_points.append(anchor + in_offset)
		var out_offset: Vector2 = _curve.get_point_out(point_index)
		if out_offset.length() > HANDLE_EPSILON:
			_out_handle_points.append(anchor + out_offset)


func _unique_point_count() -> int:
	if _curve == null or _curve.point_count == 0:
		return 0
	if _curve.point_count > 1 and _curve.get_point_position(0).distance_to(
		_curve.get_point_position(_curve.point_count - 1)
	) <= HANDLE_EPSILON:
		return _curve.point_count - 1
	return _curve.point_count
