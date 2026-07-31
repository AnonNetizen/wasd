class_name PolygonMeshDebugOverlay
extends Node2D

var _vertices := PackedVector2Array()
var _vertex_motion_masks := PackedFloat32Array()
var _segments: Array[Vector2i] = []
var _deformation_axis := Vector2.RIGHT
var _deformation_origin: float = 0.0
var _deformation_span: float = 1.0
var _deformation_tangent_center: float = 0.0
var _deformation_tangent_span: float = 1.0
var _animation_time: float = 0.0
var _deformation_progress: float = 0.0
var _line_color := Color("#69d5d0")


func configure(
	vertices: PackedVector2Array,
	faces: Array,
	vertex_motion_masks: PackedFloat32Array,
	deformation_config: Dictionary,
	line_color: Color
) -> void:
	_vertices = vertices.duplicate()
	_vertex_motion_masks = vertex_motion_masks.duplicate()
	var axis_value: Variant = deformation_config.get(
		"axis",
		Vector2.RIGHT
	)
	if axis_value is Vector2:
		_deformation_axis = axis_value
	else:
		_deformation_axis = Vector2.RIGHT
	_deformation_axis = _deformation_axis.normalized()
	_deformation_origin = float(
		deformation_config.get("origin", 0.0)
	)
	_deformation_span = maxf(
		float(deformation_config.get("span", 1.0)),
		1.0
	)
	_deformation_tangent_center = float(
		deformation_config.get("tangent_center", 0.0)
	)
	_deformation_tangent_span = maxf(
		float(deformation_config.get("tangent_span", 1.0)),
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
	deformation_progress: float
) -> void:
	_animation_time = animation_time
	_deformation_progress = clampf(deformation_progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	for edge: Vector2i in _segments:
		if edge.x < 0 or edge.y < 0:
			continue
		if edge.x >= _vertices.size() or edge.y >= _vertices.size():
			continue
		draw_line(
			_deform_point(_vertices[edge.x], edge.x),
			_deform_point(_vertices[edge.y], edge.y),
			_line_color,
			0.85,
			true
		)


func _deform_point(point: Vector2, vertex_index: int) -> Vector2:
	if (
		vertex_index < 0
		or vertex_index >= _vertex_motion_masks.size()
		or _vertex_motion_masks[vertex_index] < 0.75
	):
		return point
	var axis := _deformation_axis
	var tangent := Vector2(-axis.y, axis.x)
	var primary_position := clampf(
		(point.dot(axis) - _deformation_origin) / _deformation_span,
		0.0,
		1.0
	)
	var tangent_position := clampf(
		(
			point.dot(tangent) - _deformation_tangent_center
		) / maxf(_deformation_tangent_span * 0.5, 1.0),
		-1.0,
		1.0
	)
	var tangent_weight := absf(tangent_position)
	var deformation_envelope := sin(_deformation_progress * PI)
	var crease_center := lerpf(0.18, 0.82, _deformation_progress)
	var crease_offset := primary_position - crease_center
	var crease_band := exp(-crease_offset * crease_offset * 34.0)
	var boundary_guard := (
		smoothstep(0.04, 0.20, primary_position)
		* (1.0 - smoothstep(0.76, 0.98, primary_position))
		* (1.0 - smoothstep(0.72, 0.97, tangent_weight))
	)
	var crease := deformation_envelope * crease_band * boundary_guard
	var result := point
	result -= axis * crease * (
		10.0 + 7.0 * (1.0 - primary_position)
	)
	result += (
		tangent
		* crease
		* 9.0
		* sin(tangent_position * PI * 0.5)
	)
	return result
