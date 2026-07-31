class_name PolygonAsset2D
extends Node2D

const DEBUG_OVERLAY_SCRIPT := preload("res://scripts/polygon_mesh_debug_overlay.gd")
const MOVEMENT_DAMPING: float = 8.5
const MOVEMENT_MAX_DELTA: float = 1.0 / 30.0
const MOVEMENT_MAX_DEFORMATION: float = 1.15
const MOVEMENT_SETTLE_DISTANCE: float = 0.0005
const MOVEMENT_SETTLE_SPEED: float = 0.005
const MOVEMENT_SPRING_STIFFNESS: float = 52.0
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
var _movement_current := Vector2.ZERO
var _movement_spring_velocity := Vector2.ZERO
var _movement_target := Vector2.ZERO
var _generation_progress: float = 1.0
var _dissolve_progress: float = 0.0
var _debug_mesh_visible: bool = false
var _motion_surface_face_count: int = 0
var _primary_motion_face_count: int = 0
var _render_face_count: int = 0
var _motion_logical_vertex_count: int = 0
var _pinned_motion_boundary_vertex_count: int = 0
var _pinned_outline_vertex_count: int = 0
var _vertex_motion_masks := PackedFloat32Array()
var _motion_config: Dictionary = {}


func _ready() -> void:
	_ensure_runtime_nodes()


func _process(delta: float) -> void:
	advance_movement_deformation(delta)


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
	_motion_config.clear()
	set_effect_shader(POLYGON_SHADER)
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


func set_movement_velocity(
	velocity: Vector2,
	full_deformation_speed: float
) -> void:
	if full_deformation_speed <= 0.0 or velocity.length() <= 0.0001:
		_movement_target = Vector2.ZERO
		return
	_movement_target = (
		velocity.normalized()
		* clampf(
			velocity.length() / full_deformation_speed,
			0.0,
			1.0
		)
	)


func set_movement_state(direction: Vector2, amount: float) -> void:
	var clamped_amount := clampf(amount, 0.0, 1.0)
	_movement_current = (
		direction.normalized()
		* clamped_amount
		if direction.length() > 0.0001 and clamped_amount > 0.0001
		else Vector2.ZERO
	)
	_movement_target = _movement_current
	_movement_spring_velocity = Vector2.ZERO
	_apply_current_movement_deformation()


func advance_movement_deformation(delta: float) -> void:
	var remaining := clampf(delta, 0.0, 0.1)
	while remaining > 0.0001:
		var step_delta := minf(remaining, MOVEMENT_MAX_DELTA)
		var acceleration := (
			(_movement_target - _movement_current)
			* MOVEMENT_SPRING_STIFFNESS
		)
		_movement_spring_velocity += acceleration * step_delta
		_movement_spring_velocity *= maxf(
			0.0,
			1.0 - MOVEMENT_DAMPING * step_delta
		)
		_movement_current += _movement_spring_velocity * step_delta
		_movement_current = _movement_current.limit_length(
			MOVEMENT_MAX_DEFORMATION
		)
		remaining -= step_delta
	if (
		_movement_target.is_zero_approx()
		and _movement_current.length() < MOVEMENT_SETTLE_DISTANCE
		and _movement_spring_velocity.length() < MOVEMENT_SETTLE_SPEED
	):
		_movement_current = Vector2.ZERO
		_movement_spring_velocity = Vector2.ZERO
	_apply_current_movement_deformation()


func set_generation_progress(progress: float) -> void:
	_generation_progress = clampf(progress, 0.0, 1.0)
	_set_material_parameter(
		"generation_progress",
		_generation_progress
	)


func set_dissolve_progress(progress: float) -> void:
	_dissolve_progress = clampf(progress, 0.0, 1.0)
	_set_material_parameter(
		"dissolve_progress",
		_dissolve_progress
	)


func set_effect_shader(shader: Shader) -> void:
	_ensure_runtime_nodes()
	_mesh_material.shader = shader if shader != null else POLYGON_SHADER
	_outline_material.shader = shader if shader != null else POLYGON_SHADER
	_apply_material_state()


func set_effect_parameter(
	parameter_name: StringName,
	value: Variant
) -> void:
	_set_material_parameter(parameter_name, value)


func reset_visual() -> void:
	set_animation_time(0.0)
	_movement_current = Vector2.ZERO
	_movement_target = Vector2.ZERO
	_movement_spring_velocity = Vector2.ZERO
	_apply_current_movement_deformation()
	set_generation_progress(1.0)
	set_dissolve_progress(0.0)


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
		"motion_surface_face_count": _motion_surface_face_count,
		"primary_motion_face_count": _primary_motion_face_count,
		"render_face_count": _render_face_count,
		"motion_logical_vertex_count": _motion_logical_vertex_count,
		"pinned_motion_boundary_vertex_count":
			_pinned_motion_boundary_vertex_count,
		"pinned_outline_vertex_count": _pinned_outline_vertex_count,
		"animation_time": _animation_time,
		"movement_direction": _vector2_to_array(
			_movement_current.normalized()
			if not _movement_current.is_zero_approx()
			else Vector2.ZERO
		),
		"movement_amount": _movement_current.length(),
		"movement_target_direction": _vector2_to_array(
			_movement_target.normalized()
			if not _movement_target.is_zero_approx()
			else Vector2.ZERO
		),
		"movement_target_amount": _movement_target.length(),
		"movement_spring_speed": _movement_spring_velocity.length(),
		"motion_axis": _vector2_to_array(
			_motion_config.get("axis", Vector2.RIGHT)
		),
		"generation_progress": _generation_progress,
		"dissolve_progress": _dissolve_progress,
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
	_motion_surface_face_count = 0
	_primary_motion_face_count = 0
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
			_motion_surface_face_count += 1
		if motion_mask >= 0.75:
			_primary_motion_face_count += 1
		validated_faces.append(face)
	_render_face_count = validated_faces.size()
	_vertex_motion_masks = _build_vertex_motion_masks(
		validated_faces,
		vertices,
		_vector2_array_from_json(_asset_data.get("outline", []))
	)
	var motion_error := _configure_motion(
		vertices,
		validated_faces
	)
	if motion_error != OK:
		return motion_error

	var expanded_vertices := PackedVector3Array()
	var expanded_colors := PackedColorArray()
	var expanded_uvs := PackedVector2Array()
	for face: Dictionary in validated_faces:
		var indices: Array = face["indices"]
		var role := String(face.get("palette_role", ""))
		var color := Color(String(palette[role]))
		color.a = 1.0 if _motion_mask_for_face(face) >= 0.75 else 0.5
		var clear_order := clampf(
			float(face.get("clear_order", 1.0)),
			0.0,
			1.0
		)
		for vertex_index_value: Variant in indices:
			var vertex_index := int(vertex_index_value)
			var vertex := vertices[vertex_index]
			expanded_vertices.append(Vector3(vertex.x, vertex.y, 0.0))
			expanded_colors.append(color)
			expanded_uvs.append(Vector2(
				clear_order,
				_vertex_motion_masks[vertex_index]
			))

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
	var palette: Dictionary = _asset_data.get("palette", {})
	var debug_color := Color("#69d5d0")
	if palette.has("debug_mesh"):
		debug_color = Color(String(palette["debug_mesh"]))
	_debug_overlay.configure(
		_vector2_array_from_json(_asset_data.get("vertices", [])),
		_asset_data.get("faces", []),
		_vertex_motion_masks,
		_motion_config,
		debug_color
	)
	_debug_overlay.visible = _debug_mesh_visible


func _apply_asset_half_size() -> void:
	var bounds: Dictionary = _asset_data.get("bounds", {})
	var half_size := _array_to_vector2(bounds.get("size", [])) * 0.5
	_set_material_parameter("asset_half_size", half_size)


func _apply_material_state() -> void:
	_apply_asset_half_size()
	_set_material_parameter("animation_time", _animation_time)
	_set_material_parameter("movement_deformation", _movement_current)
	_set_material_parameter(
		"generation_progress",
		_generation_progress
	)
	_set_material_parameter(
		"dissolve_progress",
		_dissolve_progress
	)
	if not _motion_config.is_empty():
		_set_material_parameter(
			"motion_axis",
			_motion_config.get("axis", Vector2.RIGHT)
		)
		_set_material_parameter(
			"motion_origin",
			_motion_config.get("origin", 0.0)
		)
		_set_material_parameter(
			"motion_span",
			_motion_config.get("span", 1.0)
		)
		_set_material_parameter(
			"motion_tangent_center",
			_motion_config.get("tangent_center", 0.0)
		)
		_set_material_parameter(
			"motion_tangent_span",
			_motion_config.get("tangent_span", 1.0)
		)
	var motion_profile: Dictionary = _asset_data.get(
		"motion_profile",
		{}
	)
	var palette: Dictionary = _asset_data.get("palette", {})
	for tint_binding in [
		{
			"field": "movement_tint_palette_role",
			"parameter": "movement_tint",
		},
		{
			"field": "generation_tint_palette_role",
			"parameter": "generation_tint",
		},
		{
			"field": "dissolve_tint_palette_role",
			"parameter": "dissolve_tint",
		},
	]:
		var role := String(motion_profile.get(
			String(tint_binding["field"]),
			""
		))
		if not role.is_empty() and palette.has(role):
			_set_material_parameter(
				StringName(tint_binding["parameter"]),
				Color(String(palette[role]))
			)
	_mesh_material.set_shader_parameter("outline_mode", false)
	_outline_material.set_shader_parameter("outline_mode", true)


func _apply_current_movement_deformation() -> void:
	_set_material_parameter(
		"movement_deformation",
		_movement_current
	)
	if _debug_overlay != null:
		_debug_overlay.set_movement_deformation(_movement_current)


func _set_material_parameter(parameter_name: StringName, value: Variant) -> void:
	if _mesh_material != null:
		_mesh_material.set_shader_parameter(parameter_name, value)
	if _outline_material != null:
		_outline_material.set_shader_parameter(parameter_name, value)


func _validate_asset_data(data: Dictionary) -> Error:
	if int(data.get("schema_version", 0)) != 3:
		return ERR_UNAVAILABLE
	if String(data.get("asset_id", "")).is_empty():
		return ERR_INVALID_DATA
	if not data.get("vertices", null) is Array:
		return ERR_INVALID_DATA
	if not data.get("faces", null) is Array:
		return ERR_INVALID_DATA
	if not data.get("outline", null) is Array:
		return ERR_INVALID_DATA
	var motion_profile_value: Variant = data.get("motion_profile", {})
	if not motion_profile_value is Dictionary:
		return ERR_INVALID_DATA
	var motion_profile: Dictionary = motion_profile_value
	for field_name in [
		"primary_motion_regions",
		"secondary_motion_regions",
		"motion_surface_kinds",
	]:
		if not motion_profile.get(field_name, []) is Array:
			return ERR_INVALID_DATA
	var primary_regions: Array = motion_profile.get(
		"primary_motion_regions",
		[]
	)
	if (
		not primary_regions.is_empty()
		and _array_to_vector2(
			motion_profile.get("motion_axis", [])
		).length() <= 0.0001
	):
		return ERR_INVALID_DATA
	var palette: Dictionary = data.get("palette", {})
	for color_role_field in [
		"movement_tint_palette_role",
		"generation_tint_palette_role",
		"dissolve_tint_palette_role",
	]:
		var role := String(motion_profile.get(color_role_field, ""))
		if not role.is_empty() and not palette.has(role):
			return ERR_INVALID_DATA
	if not data.get("custom_animation", {}) is Dictionary:
		return ERR_INVALID_DATA
	return OK


func _motion_mask_for_face(face: Dictionary) -> float:
	var motion_profile: Dictionary = _asset_data.get(
		"motion_profile",
		{}
	)
	var surface_kind := String(face.get("surface_kind", ""))
	var motion_surface_kinds: Array = motion_profile.get(
		"motion_surface_kinds",
		[]
	)
	if not motion_surface_kinds.has(surface_kind):
		return 0.0
	var region := String(face.get("region", ""))
	var primary_regions: Array = motion_profile.get(
		"primary_motion_regions",
		[]
	)
	var secondary_regions: Array = motion_profile.get(
		"secondary_motion_regions",
		[]
	)
	if primary_regions.has(region):
		return 1.0
	if secondary_regions.has(region):
		return 0.5
	return 0.0


func _build_vertex_motion_masks(
	faces: Array[Dictionary],
	vertices: PackedVector2Array,
	outline: PackedVector2Array
) -> PackedFloat32Array:
	var vertex_count := vertices.size()
	var has_primary_face := PackedByteArray()
	var has_secondary_face := PackedByteArray()
	var has_fixed_face := PackedByteArray()
	has_primary_face.resize(vertex_count)
	has_secondary_face.resize(vertex_count)
	has_fixed_face.resize(vertex_count)
	for face: Dictionary in faces:
		var face_motion_mask := _motion_mask_for_face(face)
		var indices: Array = face.get("indices", [])
		for vertex_index_value: Variant in indices:
			var vertex_index := int(vertex_index_value)
			if face_motion_mask >= 0.75:
				has_primary_face[vertex_index] = 1
			elif face_motion_mask >= 0.25:
				has_secondary_face[vertex_index] = 1
			else:
				has_fixed_face[vertex_index] = 1

	var result := PackedFloat32Array()
	result.resize(vertex_count)
	_motion_logical_vertex_count = 0
	_pinned_motion_boundary_vertex_count = 0
	_pinned_outline_vertex_count = 0
	var outline_points: Dictionary = {}
	for point: Vector2 in outline:
		outline_points[point] = true
	for vertex_index in range(vertex_count):
		var touches_primary := has_primary_face[vertex_index] == 1
		var touches_other_geometry := (
			has_secondary_face[vertex_index] == 1
			or has_fixed_face[vertex_index] == 1
		)
		if outline_points.has(vertices[vertex_index]):
			result[vertex_index] = 0.0
			if touches_primary or has_secondary_face[vertex_index] == 1:
				_pinned_outline_vertex_count += 1
		elif touches_primary and not touches_other_geometry:
			result[vertex_index] = 1.0
			_motion_logical_vertex_count += 1
		elif touches_primary:
			result[vertex_index] = 0.0
			_pinned_motion_boundary_vertex_count += 1
		elif has_secondary_face[vertex_index] == 1 and has_fixed_face[vertex_index] == 0:
			result[vertex_index] = 0.5
	return result


func _configure_motion(
	vertices: PackedVector2Array,
	faces: Array[Dictionary]
) -> Error:
	var motion_profile: Dictionary = _asset_data.get(
		"motion_profile",
		{}
	)
	var axis := _array_to_vector2(
		motion_profile.get("motion_axis", [1.0, 0.0])
	)
	if axis.length() <= 0.0001:
		axis = Vector2.RIGHT
	axis = axis.normalized()
	var tangent := Vector2(-axis.y, axis.x)
	var minimum_projection := INF
	var maximum_projection := -INF
	var minimum_tangent := INF
	var maximum_tangent := -INF
	for face: Dictionary in faces:
		if _motion_mask_for_face(face) < 0.75:
			continue
		var indices: Array = face.get("indices", [])
		for vertex_index_value: Variant in indices:
			var point := vertices[int(vertex_index_value)]
			var projection := point.dot(axis)
			var tangent_projection := point.dot(tangent)
			minimum_projection = minf(minimum_projection, projection)
			maximum_projection = maxf(maximum_projection, projection)
			minimum_tangent = minf(minimum_tangent, tangent_projection)
			maximum_tangent = maxf(maximum_tangent, tangent_projection)
	if minimum_projection == INF:
		minimum_projection = 0.0
		maximum_projection = 1.0
		minimum_tangent = -0.5
		maximum_tangent = 0.5
	var span := maxf(maximum_projection - minimum_projection, 1.0)
	var tangent_span := maxf(maximum_tangent - minimum_tangent, 1.0)
	_motion_config = {
		"axis": axis,
		"origin": minimum_projection,
		"span": span,
		"tangent_center": (minimum_tangent + maximum_tangent) * 0.5,
		"tangent_span": tangent_span,
	}
	_apply_material_state()
	return OK


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


func _vector2_to_array(value: Vector2) -> Array:
	return [value.x, value.y]
