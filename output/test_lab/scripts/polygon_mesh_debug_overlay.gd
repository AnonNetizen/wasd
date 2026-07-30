class_name PolygonMeshDebugOverlay
extends Node2D

var _vertices := PackedVector2Array()
var _edges: Array[Vector2i] = []
var _asset_half_size := Vector2(128.0, 96.0)
var _animation_time: float = 0.0
var _page_turn_progress: float = 0.0
var _line_color := Color("#69d5d0")


func configure(
	vertices: PackedVector2Array,
	faces: Array,
	asset_half_size: Vector2,
	line_color: Color
) -> void:
	_vertices = vertices.duplicate()
	_asset_half_size = asset_half_size
	_line_color = line_color
	var unique_edges: Dictionary = {}
	_edges.clear()
	for face_value: Variant in faces:
		if not face_value is Dictionary:
			continue
		var indices_value: Variant = (face_value as Dictionary).get("indices", [])
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
			if unique_edges.has(key):
				continue
			unique_edges[key] = true
			_edges.append(normalized)
	queue_redraw()


func set_animation_state(animation_time: float, page_turn_progress: float) -> void:
	_animation_time = animation_time
	_page_turn_progress = clampf(page_turn_progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	for edge: Vector2i in _edges:
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
	var result := point
	var half_width := maxf(_asset_half_size.x, 1.0)
	var half_height := maxf(_asset_half_size.y, 1.0)
	var outer_weight := clampf(absf(result.x) / half_width, 0.0, 1.0)
	var spine_guard := smoothstep(0.04, 0.22, outer_weight)
	var idle_wave := sin(
		_animation_time * 1.35
		+ result.y * 0.028
		+ signf(result.x) * 0.75
	)
	result.y += idle_wave * 2.4 * outer_weight * outer_weight * spine_guard
	if result.x <= 0.001:
		return result
	var fold := sin(_page_turn_progress * PI)
	var vertical_center_weight := 1.0 - clampf(absf(result.y) / half_height, 0.0, 1.0)
	result.x -= fold * (result.x * 0.98 + 7.0 * outer_weight)
	result.y -= fold * 11.0 * outer_weight * vertical_center_weight
	return result
