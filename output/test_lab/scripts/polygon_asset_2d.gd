class_name PolygonAsset2D
extends Node2D

const DEBUG_OVERLAY_SCRIPT := preload("res://scripts/polygon_mesh_debug_overlay.gd")
const PAGE_PALETTE_ROLES: Array[String] = [
	"page_light",
	"page_mid",
	"page_shadow",
	"accent_warm",
]
const PAGE_UNDERLAY_ROLE_MAP: Dictionary = {
	"page_light": "page_mid",
	"page_mid": "page_shadow",
	"page_shadow": "page_light",
	"accent_warm": "page_mid",
}
const POLYGON_SHADER := preload("res://shaders/polygon_asset.gdshader")

var _asset_data: Dictionary = {}
var _mesh_instance: MeshInstance2D
var _outline: Line2D
var _debug_overlay: Node2D
var _interaction_area: Area2D
var _collision_polygon: CollisionPolygon2D
var _mesh_material: ShaderMaterial
var _outline_material: ShaderMaterial
var _animation_time: float = 0.0
var _page_turn_progress: float = 0.0
var _clear_progress: float = 0.0
var _debug_mesh_visible: bool = false
var _page_surface_face_count: int = 0
var _turnable_face_count: int = 0
var _page_underlay_face_count: int = 0
var _render_face_count: int = 0


func _ready() -> void:
	_ensure_runtime_nodes()


func load_asset(path: String) -> Error:
	_ensure_runtime_nodes()
	var parsed := _load_json_dictionary(path)
	if not bool(parsed.get("ok", false)):
		push_error(String(parsed.get("error", "Failed to load Polygon asset.")))
		return ERR_FILE_CORRUPT
	var data: Dictionary = parsed["data"]
	var validation_error := _validate_asset_data(data)
	if validation_error != OK:
		return validation_error
	_asset_data = data.duplicate(true)
	var mesh_error := _build_mesh()
	if mesh_error != OK:
		return mesh_error
	_build_outline()
	_build_collision()
	_build_anchors()
	_build_debug_overlay()
	reset_visual()
	return OK


func set_animation_time(seconds: float) -> void:
	_animation_time = maxf(seconds, 0.0)
	_set_material_parameter("animation_time", _animation_time)
	if _debug_overlay != null:
		_debug_overlay.set_animation_state(_animation_time, _page_turn_progress)


func set_page_turn_progress(progress: float) -> void:
	_page_turn_progress = clampf(progress, 0.0, 1.0)
	_set_material_parameter("page_turn_progress", _page_turn_progress)
	if _debug_overlay != null:
		_debug_overlay.set_animation_state(_animation_time, _page_turn_progress)


func set_clear_progress(progress: float) -> void:
	_clear_progress = clampf(progress, 0.0, 1.0)
	_set_material_parameter("clear_progress", _clear_progress)


func reset_visual() -> void:
	set_animation_time(0.0)
	set_page_turn_progress(0.0)
	set_clear_progress(0.0)


func set_debug_mesh_visible(visible: bool) -> void:
	_debug_mesh_visible = visible
	if _debug_overlay != null:
		_debug_overlay.visible = visible


func get_asset_data() -> Dictionary:
	return _asset_data.duplicate(true)


func get_runtime_stats() -> Dictionary:
	var mesh := _mesh_instance.mesh as ArrayMesh if _mesh_instance != null else null
	var mesh_vertex_count := 0
	if mesh != null and mesh.get_surface_count() == 1:
		mesh_vertex_count = mesh.surface_get_array_len(0)
	return {
		"mesh_instance_count": 1 if _mesh_instance != null else 0,
		"surface_count": mesh.get_surface_count() if mesh != null else 0,
		"mesh_vertex_count": mesh_vertex_count,
		"has_texture": _mesh_instance.texture != null if _mesh_instance != null else false,
		"outline_node_count": 1 if _outline != null else 0,
		"collision_static": true,
		"source_face_count": int(_asset_data.get("stats", {}).get("face_count", 0)),
		"page_surface_face_count": _page_surface_face_count,
		"turnable_face_count": _turnable_face_count,
		"page_underlay_face_count": _page_underlay_face_count,
		"render_face_count": _render_face_count,
		"animation_time": _animation_time,
		"page_turn_progress": _page_turn_progress,
		"clear_progress": _clear_progress,
		"debug_mesh_visible": _debug_mesh_visible,
	}


func get_mesh_instance() -> MeshInstance2D:
	return _mesh_instance


func _ensure_runtime_nodes() -> void:
	if _mesh_instance != null:
		return
	_mesh_instance = MeshInstance2D.new()
	_mesh_instance.name = "PolygonMesh"
	add_child(_mesh_instance)

	_outline = Line2D.new()
	_outline.name = "OuterOutline"
	_outline.closed = true
	_outline.antialiased = true
	_outline.joint_mode = Line2D.LINE_JOINT_ROUND
	_outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_outline)

	_debug_overlay = DEBUG_OVERLAY_SCRIPT.new()
	_debug_overlay.name = "MeshDebug"
	_debug_overlay.visible = false
	add_child(_debug_overlay)

	_interaction_area = Area2D.new()
	_interaction_area.name = "InteractionArea"
	add_child(_interaction_area)
	_collision_polygon = CollisionPolygon2D.new()
	_collision_polygon.name = "CollisionPolygon"
	_interaction_area.add_child(_collision_polygon)

	_mesh_material = ShaderMaterial.new()
	_mesh_material.shader = POLYGON_SHADER
	_mesh_material.set_shader_parameter("outline_mode", false)
	_mesh_instance.material = _mesh_material

	_outline_material = ShaderMaterial.new()
	_outline_material.shader = POLYGON_SHADER
	_outline_material.set_shader_parameter("outline_mode", true)
	_outline.material = _outline_material


func _build_mesh() -> Error:
	var vertices := _vector2_array_from_json(_asset_data.get("vertices", []))
	var faces_value: Variant = _asset_data.get("faces", [])
	var palette_value: Variant = _asset_data.get("palette", {})
	if not faces_value is Array or not palette_value is Dictionary:
		return ERR_INVALID_DATA
	var faces: Array = faces_value
	var palette: Dictionary = palette_value
	var validated_faces: Array[Dictionary] = []
	_page_surface_face_count = 0
	_turnable_face_count = 0
	_page_underlay_face_count = 0
	_render_face_count = 0
	for face_value: Variant in faces:
		if not face_value is Dictionary:
			return ERR_INVALID_DATA
		var face: Dictionary = face_value
		var indices_value: Variant = face.get("indices", [])
		if not indices_value is Array or (indices_value as Array).size() != 3:
			return ERR_INVALID_DATA
		var role := String(face.get("palette_role", ""))
		if not palette.has(role):
			return ERR_INVALID_DATA
		for vertex_index_value: Variant in indices_value:
			var vertex_index := int(vertex_index_value)
			if vertex_index < 0 or vertex_index >= vertices.size():
				return ERR_INVALID_DATA
		var motion_mask := _motion_mask_for_face(face)
		if motion_mask >= 0.25:
			_page_surface_face_count += 1
		if motion_mask >= 0.75:
			_turnable_face_count += 1
		validated_faces.append(face)

	var render_faces: Array[Dictionary] = []
	for face: Dictionary in validated_faces:
		if _motion_mask_for_face(face) < 0.75:
			continue
		var source_role := String(face.get("palette_role", "page_mid"))
		var underlay_role := String(PAGE_UNDERLAY_ROLE_MAP.get(source_role, "page_mid"))
		render_faces.append({
			"indices": (face["indices"] as Array).duplicate(),
			"color": Color(String(palette[underlay_role])),
			"clear_order": float(face.get("clear_order", 1.0)),
			"motion_mask": 0.0,
		})
		_page_underlay_face_count += 1
	for face: Dictionary in validated_faces:
		var role := String(face.get("palette_role", ""))
		render_faces.append({
			"indices": (face["indices"] as Array).duplicate(),
			"color": Color(String(palette[role])),
			"clear_order": float(face.get("clear_order", 1.0)),
			"motion_mask": _motion_mask_for_face(face),
		})
	_render_face_count = render_faces.size()

	var expanded_vertices := PackedVector3Array()
	var expanded_colors := PackedColorArray()
	var expanded_uvs := PackedVector2Array()
	for render_face: Dictionary in render_faces:
		var indices: Array = render_face["indices"]
		var color: Color = render_face["color"]
		color.a = 1.0
		var clear_order := clampf(
			float(render_face.get("clear_order", 1.0)),
			0.0,
			1.0
		)
		var motion_mask := clampf(float(render_face.get("motion_mask", 0.0)), 0.0, 1.0)
		for vertex_index_value: Variant in indices:
			var vertex_index := int(vertex_index_value)
			var vertex := vertices[vertex_index]
			expanded_vertices.append(Vector3(vertex.x, vertex.y, 0.0))
			expanded_colors.append(color)
			expanded_uvs.append(Vector2(clear_order, motion_mask))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = expanded_vertices
	arrays[Mesh.ARRAY_COLOR] = expanded_colors
	arrays[Mesh.ARRAY_TEX_UV] = expanded_uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance.mesh = mesh
	_apply_asset_half_size()
	return OK


func _build_outline() -> void:
	var outline_points := _vector2_array_from_json(_asset_data.get("outline", []))
	_outline.points = outline_points
	var palette: Dictionary = _asset_data.get("palette", {})
	_outline.default_color = Color(String(palette.get("outline", "#191824")))
	var style_width := 4.0
	_outline.width = style_width


func _build_collision() -> void:
	var collision: Dictionary = _asset_data.get("collision", {})
	_collision_polygon.polygon = _vector2_array_from_json(collision.get("convex_hull", []))


func _build_anchors() -> void:
	for child: Node in get_children():
		if child is Marker2D and child.name.begins_with("Anchor"):
			child.queue_free()
	var anchors_value: Variant = _asset_data.get("anchors", {})
	if not anchors_value is Dictionary:
		return
	var anchors: Dictionary = anchors_value
	for anchor_name: String in anchors:
		var marker := Marker2D.new()
		marker.name = "Anchor%s" % anchor_name.to_pascal_case()
		marker.position = _array_to_vector2(anchors[anchor_name])
		marker.set_meta("anchor_id", anchor_name)
		add_child(marker)


func _build_debug_overlay() -> void:
	var bounds: Dictionary = _asset_data.get("bounds", {})
	var size := _array_to_vector2(bounds.get("size", []))
	var half_size := size * 0.5
	var palette: Dictionary = _asset_data.get("palette", {})
	var debug_color := Color("#69d5d0")
	if palette.has("debug_mesh"):
		debug_color = Color(String(palette["debug_mesh"]))
	_debug_overlay.configure(
		_vector2_array_from_json(_asset_data.get("vertices", [])),
		_asset_data.get("faces", []),
		half_size,
		debug_color
	)
	_debug_overlay.visible = _debug_mesh_visible


func _apply_asset_half_size() -> void:
	var bounds: Dictionary = _asset_data.get("bounds", {})
	var half_size := _array_to_vector2(bounds.get("size", [])) * 0.5
	_mesh_material.set_shader_parameter("asset_half_size", half_size)
	_outline_material.set_shader_parameter("asset_half_size", half_size)


func _set_material_parameter(parameter_name: StringName, value: Variant) -> void:
	if _mesh_material != null:
		_mesh_material.set_shader_parameter(parameter_name, value)
	if _outline_material != null:
		_outline_material.set_shader_parameter(parameter_name, value)


func _validate_asset_data(data: Dictionary) -> Error:
	if int(data.get("schema_version", 0)) != 1:
		return ERR_UNAVAILABLE
	if String(data.get("asset_id", "")).is_empty():
		return ERR_INVALID_DATA
	if not data.get("vertices", null) is Array:
		return ERR_INVALID_DATA
	if not data.get("faces", null) is Array:
		return ERR_INVALID_DATA
	if not data.get("outline", null) is Array:
		return ERR_INVALID_DATA
	return OK


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


func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "error": "Polygon asset does not exist: %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Failed to open Polygon asset: %s" % path}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK or not parser.data is Dictionary:
		return {
			"ok": false,
			"error": "Invalid Polygon JSON at line %d: %s"
				% [parser.get_error_line(), parser.get_error_message()],
		}
	return {"ok": true, "data": (parser.data as Dictionary).duplicate(true)}


func _vector2_array_from_json(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not value is Array:
		return result
	for point_value: Variant in value:
		result.append(_array_to_vector2(point_value))
	return result


func _array_to_vector2(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	var values: Array = value
	return Vector2(float(values[0]), float(values[1]))
