class_name PolygonMeshDebugOverlay
extends Node2D

var _vertices := PackedVector2Array()
var _vertex_motion_masks := PackedFloat32Array()
var _segments: Array[Vector2i] = []
var _motion_axis := Vector2.RIGHT
var _motion_origin: float = 0.0
var _motion_span: float = 1.0
var _motion_tangent_center: float = 0.0
var _motion_tangent_span: float = 1.0
var _animation_time: float = 0.0
var _motion_progress: float = 0.0
var _motion_strength: float = 0.0
var _line_color := Color("#69d5d0")


func configure(
	vertices: PackedVector2Array,
	faces: Array,
	vertex_motion_masks: PackedFloat32Array,
	motion_config: Dictionary,
	line_color: Color
) -> void:
	_vertices = vertices.duplicate()
	_vertex_motion_masks = vertex_motion_masks.duplicate()
	var axis_value: Variant = motion_config.get(
		"axis",
		Vector2.RIGHT
	)
	if axis_value is Vector2:
		_motion_axis = axis_value
	else:
		_motion_axis = Vector2.RIGHT
	_motion_axis = _motion_axis.normalized()
	_motion_origin = float(
		motion_config.get("origin", 0.0)
	)
	_motion_span = maxf(
		float(motion_config.get("span", 1.0)),
		1.0
	)
	_motion_tangent_center = float(
		motion_config.get("tangent_center", 0.0)
	)
	_motion_tangent_span = maxf(
		float(motion_config.get("tangent_span", 1.0)),
		1.0
	)
	_line_color = line_color
	var unique_segments: Dictionary = {}
	_segments.clear()
	for face_value: Variant in faces:
		if not face_value is Dictionary:
			continue
		var face: Dictionary = face_value
		var indices_value: Variant = face.get("indices", [])
		if not indices_value is Array or (indices_value as Array).size() != 3:
			continue
		var indices: Array = indices_value
		for edge in [
			Vector2i(int(indices[0]), int(indices[1])),
			Vector2i(int(indices[1]), int(indices[2])),
			Vector2i(int(indices[2]), int(indices[0])),
		]:
			var normalized := Vector2i(
				mini(edge.x, edge.y),
				maxi(edge.x, edge.y)
			)
			var key := "%d:%d" % [normalized.x, normalized.y]
			if unique_segments.has(key):
				continue
			unique_segments[key] = true
			_segments.append(normalized)
	queue_redraw()


func set_animation_state(
	animation_time: float,
	motion_progress: float,
	motion_strength: float
) -> void:
	_animation_time = animation_time
	_motion_progress = clampf(motion_progress, 0.0, 1.0)
	_motion_strength = clampf(motion_strength, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	for edge: Vector2i in _segments:
		if edge.x < 0 or edge.y < 0:
			continue
		if edge.x >= _vertices.size() or edge.y >= _vertices.size():
			continue
		draw_line(
			_animate_point(_vertices[edge.x], edge.x),
			_animate_point(_vertices[edge.y], edge.y),
			_line_color,
			0.85,
			true
		)


func _animate_point(point: Vector2, vertex_index: int) -> Vector2:
	if (
		vertex_index < 0
		or vertex_index >= _vertex_motion_masks.size()
		or _vertex_motion_masks[vertex_index] <= 0.0
	):
		return point
	var motion_weight := _vertex_motion_masks[vertex_index]
	if motion_weight <= 0.0 or _motion_strength <= 0.0:
		return point
	var axis := _motion_axis
	var tangent := Vector2(-axis.y, axis.x)
	var primary_position := clampf(
		(point.dot(axis) - _motion_origin) / _motion_span,
		0.0,
		1.0
	)
	var tangent_position := clampf(
		(
			point.dot(tangent) - _motion_tangent_center
		) / maxf(_motion_tangent_span * 0.5, 1.0),
		-1.0,
		1.0
	)
	var boundary_guard := (
		smoothstep(0.02, 0.16, primary_position)
		* (1.0 - smoothstep(0.84, 0.98, primary_position))
		* (1.0 - smoothstep(0.82, 1.0, absf(tangent_position)))
	)
	var phase := (
		_animation_time * 1.35
		+ _motion_progress * TAU
		+ primary_position * 3.4
		+ tangent_position * 1.8
	)
	var sway := (
		sin(phase)
		* _motion_strength
		* motion_weight
		* boundary_guard
	)
	var result := point
	result += tangent * sway * 4.0
	result += axis * cos(phase * 0.73) * sway * 1.4
	return result
