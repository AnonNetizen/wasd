class_name PolygonMeshDebugOverlay
extends Node2D

var _vertices := PackedVector2Array()
var _segments: Array[Vector2i] = []
var _asset_half_size := Vector2.ONE
var _movement_deformation := Vector2.ZERO
var _line_color := Color("#69d5d0")


func configure(
	vertices: PackedVector2Array,
	faces: Array,
	_vertex_motion_masks: PackedFloat32Array,
	_motion_config: Dictionary,
	line_color: Color
) -> void:
	_vertices = vertices.duplicate()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point: Vector2 in _vertices:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	_asset_half_size = (maximum - minimum) * 0.5
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


func set_movement_deformation(deformation: Vector2) -> void:
	_movement_deformation = deformation
	queue_redraw()


func _draw() -> void:
	for edge: Vector2i in _segments:
		if edge.x < 0 or edge.y < 0:
			continue
		if edge.x >= _vertices.size() or edge.y >= _vertices.size():
			continue
		draw_line(
			_deform_point(_vertices[edge.x]),
			_deform_point(_vertices[edge.y]),
			_line_color,
			0.85,
			true
		)


func _deform_point(point: Vector2) -> Vector2:
	var deformation_amount := _movement_deformation.length()
	if deformation_amount <= 0.0001:
		return point
	var direction := _movement_deformation / deformation_amount
	var tangent := Vector2(-direction.y, direction.x)
	var longitudinal_extent := maxf(
		absf(direction.x) * _asset_half_size.x
		+ absf(direction.y) * _asset_half_size.y,
		1.0
	)
	var longitudinal := point.dot(direction)
	var lateral := point.dot(tangent)
	var normalized_longitudinal := clampf(
		longitudinal / longitudinal_extent,
		-1.0,
		1.0
	)
	var front_weight := smoothstep(
		-0.10,
		0.92,
		normalized_longitudinal
	)
	var center_weight := (
		1.0
		- normalized_longitudinal * normalized_longitudinal
	)
	longitudinal *= 1.0 + deformation_amount * 0.085
	longitudinal += deformation_amount * front_weight * 4.5
	longitudinal -= deformation_amount * center_weight * 2.2
	lateral *= (
		1.0
		- deformation_amount
		* 0.048
		* (1.0 - absf(normalized_longitudinal) * 0.35)
	)
	return direction * longitudinal + tangent * lateral
