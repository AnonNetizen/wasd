class_name PolygonMeshDebugOverlay
extends Node2D

var _vertices := PackedVector2Array()
var _segments: Array[Vector2i] = []
var _line_color := Color("#69d5d0")


func configure(
	vertices: PackedVector2Array,
	faces: Array,
	line_color: Color
) -> void:
	_vertices = vertices.duplicate()
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


func _draw() -> void:
	for edge: Vector2i in _segments:
		if edge.x < 0 or edge.y < 0:
			continue
		if edge.x >= _vertices.size() or edge.y >= _vertices.size():
			continue
		draw_line(
			_vertices[edge.x],
			_vertices[edge.y],
			_line_color,
			0.85,
			true
		)
