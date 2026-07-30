class_name PolygonMeshDebugOverlay
extends Node2D

const PAGE_PALETTE_ROLES: Array[String] = [
	"page_light",
	"page_mid",
	"page_shadow",
	"accent_warm",
]

var _vertices := PackedVector2Array()
var _segments: Array[Dictionary] = []
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
		var motion_mask := _motion_mask_for_face(face)
		for edge in [
			Vector2i(int(indices[0]), int(indices[1])),
			Vector2i(int(indices[1]), int(indices[2])),
			Vector2i(int(indices[2]), int(indices[0])),
		]:
			var normalized := Vector2i(
				mini(edge.x, edge.y),
				maxi(edge.x, edge.y)
			)
			var key := "%d:%d:%.1f" % [normalized.x, normalized.y, motion_mask]
			if unique_segments.has(key):
				continue
			unique_segments[key] = true
			_segments.append({
				"edge": normalized,
				"motion_mask": motion_mask,
			})
	queue_redraw()


func set_animation_state(animation_time: float, page_turn_progress: float) -> void:
	_animation_time = animation_time
	_page_turn_progress = clampf(page_turn_progress, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	for segment: Dictionary in _segments:
		var edge: Vector2i = segment["edge"]
		if edge.x < 0 or edge.y < 0:
			continue
		if edge.x >= _vertices.size() or edge.y >= _vertices.size():
			continue
		draw_line(
			_deform_point(_vertices[edge.x], float(segment["motion_mask"])),
			_deform_point(_vertices[edge.y], float(segment["motion_mask"])),
			_line_color,
			0.85,
			true
		)


func _deform_point(point: Vector2, motion_mask: float) -> Vector2:
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
	var page_surface := 1.0 if motion_mask >= 0.25 else 0.0
	result.y += (
		idle_wave
		* 3.6
		* outer_weight
		* outer_weight
		* spine_guard
		* page_surface
	)
	if motion_mask < 0.75:
		return result
	var fold := sin(_page_turn_progress * PI)
	var vertical_center_weight := 1.0 - clampf(absf(result.y) / half_height, 0.0, 1.0)
	result.x -= fold * (result.x * 1.04 + 9.0 * outer_weight)
	result.y -= fold * 14.0 * outer_weight * vertical_center_weight
	return result


func _motion_mask_for_face(face: Dictionary) -> float:
	var role := String(face.get("palette_role", ""))
	if not PAGE_PALETTE_ROLES.has(role):
		return 0.0
	var region := String(face.get("region", ""))
	if region == "right_page":
		return 1.0
	if region == "left_page":
		return 0.5
	return 0.0
