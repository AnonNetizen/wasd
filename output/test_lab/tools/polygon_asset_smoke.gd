extends SceneTree

const ASSET_PATH: String = "res://data/polygon_assets/open_book.polygon.json"
const COMPILER := preload("res://scripts/polygon_asset_compiler_core.gd")
const MANIFEST_PATH: String = "res://data/polygon_imports/open_book.json"
const RUNTIME_SCRIPT := preload("res://scripts/polygon_asset_2d.gd")
const SCENE_PATH: String = "res://scenes/polygon_book_test.tscn"
const SHADER_PATH: String = "res://shaders/polygon_asset.gdshader"
const SOURCE_PATH: String = "res://assets/polygon_art/open_book_source.png"
const STYLE_PATH: String = "res://data/polygon_art_style.json"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var compiler := COMPILER.new()
	var first_result: Dictionary = compiler.compile_manifest(MANIFEST_PATH)
	var second_result: Dictionary = compiler.compile_manifest(MANIFEST_PATH)
	_check(bool(first_result.get("ok", false)), "First manifest compilation succeeds.")
	_check(bool(second_result.get("ok", false)), "Second manifest compilation succeeds.")
	if not bool(first_result.get("ok", false)) or not bool(second_result.get("ok", false)):
		_finish()
		return
	var first_data: Dictionary = first_result["data"]
	var second_data: Dictionary = second_result["data"]
	_check(
		_canonical_json(first_data) == _canonical_json(second_data),
		"Manifest compilation is deterministic."
	)

	var checked_result := _load_json_dictionary(ASSET_PATH)
	_check(bool(checked_result.get("ok", false)), "Checked-in Polygon JSON loads.")
	if not bool(checked_result.get("ok", false)):
		_finish()
		return
	var asset_data: Dictionary = checked_result["data"]
	_check(
		_variants_equivalent(asset_data, first_data),
		"Checked-in Polygon JSON matches a fresh deterministic compile."
	)

	var style_result := _load_json_dictionary(STYLE_PATH)
	_check(bool(style_result.get("ok", false)), "Style Profile loads.")
	if not bool(style_result.get("ok", false)):
		_finish()
		return
	var style: Dictionary = style_result["data"]
	_validate_source(asset_data)
	_validate_asset_schema(asset_data, style)
	_validate_scene_file_shape()
	_validate_shader_shape()
	await _validate_runtime(asset_data)
	await _validate_demo_scene()
	_finish()


func _validate_source(asset_data: Dictionary) -> void:
	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(SOURCE_PATH))
	_check(load_error == OK, "Source PNG decodes without import cache.")
	if load_error != OK:
		return
	var key := Color("#ff00ff")
	var border_is_exact := true
	for x in range(image.get_width()):
		border_is_exact = border_is_exact and _colors_equal(image.get_pixel(x, 0), key)
		border_is_exact = border_is_exact and _colors_equal(
			image.get_pixel(x, image.get_height() - 1),
			key
		)
	for y in range(image.get_height()):
		border_is_exact = border_is_exact and _colors_equal(image.get_pixel(0, y), key)
		border_is_exact = border_is_exact and _colors_equal(
			image.get_pixel(image.get_width() - 1, y),
			key
		)
	_check(border_is_exact, "Source PNG border is exact #ff00ff.")
	var source: Dictionary = asset_data.get("source", {})
	_check(
		String(source.get("sha256", "")) == _sha256_file(SOURCE_PATH),
		"Polygon JSON source hash matches the normalized source PNG."
	)


func _validate_asset_schema(asset_data: Dictionary, style: Dictionary) -> void:
	_check(int(asset_data.get("schema_version", 0)) == 1, "Polygon asset schema_version is 1.")
	_check(String(asset_data.get("asset_id", "")) == "open_book", "Asset id is open_book.")
	_check(
		String(asset_data.get("style_id", "")) == String(style.get("style_id", "")),
		"Polygon asset references the configured Style Profile id."
	)
	var vertices := _vector2_array_from_json(asset_data.get("vertices", []))
	var faces_value: Variant = asset_data.get("faces", [])
	_check(not vertices.is_empty(), "Polygon asset has shared logical vertices.")
	_check(faces_value is Array, "Polygon asset faces are an array.")
	if not faces_value is Array:
		return
	var faces: Array = faces_value
	var target: Dictionary = style.get("target_face_count", {})
	_check(
		faces.size() >= int(target.get("min", 70))
		and faces.size() <= int(target.get("max", 140)),
		"Face count is inside the 70–140 Style Profile target."
	)
	_check(
		faces.size() <= int(target.get("hard_max", 160)),
		"Face count does not exceed the 160 hard limit."
	)
	var palette: Dictionary = style.get("palette", {})
	var region_counts: Dictionary = {
		"left_page": 0,
		"right_page": 0,
		"spine": 0,
	}
	var indices_are_valid := true
	var triangles_are_valid := true
	var palette_roles_are_valid := true
	var clear_order_is_valid := true
	for face_value: Variant in faces:
		if not face_value is Dictionary:
			indices_are_valid = false
			continue
		var face: Dictionary = face_value
		var indices_value: Variant = face.get("indices", [])
		if not indices_value is Array or (indices_value as Array).size() != 3:
			indices_are_valid = false
			continue
		var indices: Array = indices_value
		for index_value: Variant in indices:
			var vertex_index := int(index_value)
			indices_are_valid = (
				indices_are_valid
				and vertex_index >= 0
				and vertex_index < vertices.size()
			)
		if not indices_are_valid:
			continue
		var a := vertices[int(indices[0])]
		var b := vertices[int(indices[1])]
		var c := vertices[int(indices[2])]
		triangles_are_valid = triangles_are_valid and absf((b - a).cross(c - a)) > 0.001
		var palette_role := String(face.get("palette_role", ""))
		palette_roles_are_valid = palette_roles_are_valid and palette.has(palette_role)
		var region := String(face.get("region", ""))
		if region_counts.has(region):
			region_counts[region] = int(region_counts[region]) + 1
		clear_order_is_valid = clear_order_is_valid and (
			float(face.get("clear_order", 0.0)) > 0.0
			and float(face.get("clear_order", 0.0)) <= 1.0
		)
	_check(indices_are_valid, "Every face has three valid shared-vertex indices.")
	_check(triangles_are_valid, "Polygon asset contains no degenerate triangle.")
	_check(palette_roles_are_valid, "Every face color comes from the Style Profile palette.")
	_check(clear_order_is_valid, "Every face has a normalized clear order.")
	_check(_connected_component_count(faces) == 1, "Face topology has one connected component.")
	for region_name: String in region_counts:
		_check(
			int(region_counts[region_name]) > 0,
			"Semantic region is non-empty: %s." % region_name
		)

	var bounds := _rect_from_json(asset_data.get("bounds", {}))
	var anchors_value: Variant = asset_data.get("anchors", {})
	_check(anchors_value is Dictionary, "Polygon asset declares anchors.")
	if anchors_value is Dictionary:
		var anchors: Dictionary = anchors_value
		for required_anchor in ["center", "spine_top", "spine_bottom", "interaction"]:
			_check(anchors.has(required_anchor), "Required anchor exists: %s." % required_anchor)
			if anchors.has(required_anchor):
				_check(
					bounds.grow(0.01).has_point(_array_to_vector2(anchors[required_anchor])),
					"Anchor is inside bounds: %s." % required_anchor
				)
	var collision: Dictionary = asset_data.get("collision", {})
	var convex_hull := _vector2_array_from_json(collision.get("convex_hull", []))
	_check(convex_hull.size() >= 3, "Collision convex hull has at least three points.")
	for point: Vector2 in convex_hull:
		_check(bounds.grow(0.01).has_point(point), "Collision point is inside asset bounds.")
	var stats: Dictionary = asset_data.get("stats", {})
	_check(int(stats.get("connected_components", 0)) == 1, "Stats record one component.")
	_check(int(stats.get("draw_surfaces", 0)) == 1, "Stats record one draw surface.")


func _validate_scene_file_shape() -> void:
	_check(FileAccess.file_exists(SCENE_PATH), "Generated Polygon book scene exists.")
	var file := FileAccess.open(SCENE_PATH, FileAccess.READ)
	_check(file != null, "Generated scene is readable.")
	if file == null:
		return
	var text := file.get_as_text()
	_check(text.find("sub_resource type=\"Image\"") < 0, "Scene embeds no Image sub-resource.")
	_check(text.find("PackedByteArray") < 0, "Scene embeds no PackedByteArray.")
	_check(text.find(SOURCE_PATH) < 0, "Scene file has no source PNG resource dependency.")


func _validate_shader_shape() -> void:
	var shader := load(SHADER_PATH) as Shader
	_check(shader != null, "Polygon runtime shader loads.")
	if shader == null:
		return
	_check(
		shader.code.find("step(0.75, UV.y)") >= 0,
		"Shader gates page-turn deformation by per-face UV motion masks."
	)
	_check(
		shader.code.find("page_fold_light") >= 0
		and shader.code.find("page_fold_shadow") >= 0,
		"Shader exposes fold color-shift endpoints."
	)


func _validate_runtime(asset_data: Dictionary) -> void:
	var runtime := RUNTIME_SCRIPT.new()
	runtime.name = "RuntimeUnderTest"
	root.add_child(runtime)
	await process_frame
	var load_error: Error = runtime.load_asset(ASSET_PATH)
	_check(load_error == OK, "PolygonAsset2D loads the compiled JSON.")
	if load_error != OK:
		runtime.queue_free()
		return
	var mesh_instances := runtime.find_children("*", "MeshInstance2D", true, false)
	_check(mesh_instances.size() == 1, "PolygonAsset2D owns exactly one MeshInstance2D.")
	var mesh_instance := runtime.get_mesh_instance() as MeshInstance2D
	_check(mesh_instance != null, "Runtime exposes the Polygon mesh instance.")
	var runtime_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		int(runtime_stats.get("turnable_face_count", 0)) > 0,
		"Runtime identifies turnable right-page faces."
	)
	_check(
		int(runtime_stats.get("page_underlay_face_count", 0))
		== int(runtime_stats.get("turnable_face_count", -1)),
		"Every turnable page face has one fixed underlay face."
	)
	_check(
		int(runtime_stats.get("render_face_count", 0))
		== int(runtime_stats.get("source_face_count", 0))
		+ int(runtime_stats.get("page_underlay_face_count", 0)),
		"Runtime render-face count includes only the fixed page underlay duplicates."
	)
	if mesh_instance != null:
		var mesh := mesh_instance.mesh as ArrayMesh
		_check(mesh != null, "Runtime mesh is an ArrayMesh.")
		if mesh != null:
			_check(mesh.get_surface_count() == 1, "Runtime ArrayMesh has one surface.")
			_check(
				mesh.surface_get_array_len(0)
				== int(runtime_stats.get("render_face_count", 0)) * 3,
				"Runtime expands source and underlay faces into one surface."
			)
			var arrays := mesh.surface_get_arrays(0)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var turnable_vertex_count := 0
			var idle_page_vertex_count := 0
			for uv: Vector2 in uvs:
				if uv.y >= 0.75:
					turnable_vertex_count += 1
				elif uv.y >= 0.25:
					idle_page_vertex_count += 1
			_check(
				turnable_vertex_count
				== int(runtime_stats.get("turnable_face_count", 0)) * 3,
				"Only turnable page faces carry the page-turn UV mask."
			)
			_check(
				idle_page_vertex_count > 0,
				"Left-page surface faces retain idle-only motion masks."
			)
			var palette: Dictionary = asset_data.get("palette", {})
			var palette_colors: Dictionary = {}
			for palette_color_value: Variant in palette.values():
				palette_colors[Color(String(palette_color_value)).to_html(false)] = true
			var underlay_color_keys: Dictionary = {}
			var underlay_vertex_count := (
				int(runtime_stats.get("page_underlay_face_count", 0)) * 3
			)
			var underlay_colors_are_profiled := true
			for color_index in range(mini(underlay_vertex_count, colors.size())):
				var color_key := colors[color_index].to_html(false)
				underlay_color_keys[color_key] = true
				if not palette_colors.has(color_key):
					underlay_colors_are_profiled = false
			_check(
				underlay_colors_are_profiled,
				"Fixed page underlay colors come from the Style Profile."
			)
			_check(
				underlay_color_keys.size() >= 2,
				"Fixed page underlay preserves multiple Polygon color blocks."
			)
		_check(mesh_instance.texture == null, "Runtime MeshInstance2D has no texture.")
	var outline_nodes := runtime.find_children("*", "Line2D", true, false)
	_check(outline_nodes.size() == 1, "Runtime owns one synchronized Line2D outline.")
	var area := runtime.get_node_or_null("InteractionArea") as Area2D
	_check(area != null, "Runtime creates an Area2D interaction boundary.")
	var collision := runtime.get_node_or_null("InteractionArea/CollisionPolygon") as CollisionPolygon2D
	_check(collision != null, "Runtime creates convex-hull collision.")
	var collision_before := collision.polygon.duplicate() if collision != null else PackedVector2Array()

	runtime.set_animation_time(2.5)
	runtime.set_page_turn_progress(0.5)
	runtime.set_clear_progress(0.65)
	var progress_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		is_equal_approx(float(progress_stats.get("animation_time", 0.0)), 2.5),
		"Animation time can be set directly."
	)
	_check(
		is_equal_approx(float(progress_stats.get("page_turn_progress", 0.0)), 0.5),
		"Page-turn progress can be set directly."
	)
	_check(
		is_equal_approx(float(progress_stats.get("clear_progress", 0.0)), 0.65),
		"Clear progress can be set directly."
	)
	if collision != null:
		_check(
			collision.polygon == collision_before,
			"Convex-hull collision remains static during visual animation."
		)
	runtime.reset_visual()
	var reset_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		is_zero_approx(float(reset_stats.get("animation_time", -1.0)))
		and is_zero_approx(float(reset_stats.get("page_turn_progress", -1.0)))
		and is_zero_approx(float(reset_stats.get("clear_progress", -1.0))),
		"reset_visual restores all animation progress."
	)
	runtime.set_debug_mesh_visible(true)
	_check(
		bool(runtime.get_runtime_stats().get("debug_mesh_visible", false)),
		"Debug triangle mesh can be enabled without another MeshInstance2D."
	)
	runtime.queue_free()
	await process_frame


func _validate_demo_scene() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_check(packed_scene != null, "Polygon book demo scene loads as PackedScene.")
	if packed_scene == null:
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	_check(scene.has_method("get_auto_demo_state"), "Demo exposes auto-demo state.")
	_check(scene.has_method("debug_set_auto_demo_time"), "Demo exposes deterministic auto timing.")
	if (
		not scene.has_method("get_auto_demo_state")
		or not scene.has_method("debug_set_auto_demo_time")
	):
		scene.queue_free()
		return
	var initial_state: Dictionary = scene.call("get_auto_demo_state")
	_check(bool(initial_state.get("enabled", false)), "Auto demo is enabled on scene entry.")
	scene.call("debug_set_auto_demo_time", 1.6)
	var polygon_asset: Node = scene.call("get_polygon_asset")
	var turn_stats: Dictionary = polygon_asset.call("get_runtime_stats")
	_check(
		float(turn_stats.get("page_turn_progress", 0.0)) > 0.4,
		"Auto demo reaches a visible page-turn phase."
	)
	scene.call("debug_set_auto_demo_time", 3.5)
	var clear_stats: Dictionary = polygon_asset.call("get_runtime_stats")
	_check(
		float(clear_stats.get("clear_progress", 0.0)) > 0.4,
		"Auto demo reaches a visible clear phase."
	)
	scene.queue_free()
	await process_frame


func _connected_component_count(faces: Array) -> int:
	if faces.is_empty():
		return 0
	var vertex_to_faces: Dictionary = {}
	for face_index in range(faces.size()):
		var face: Dictionary = faces[face_index]
		var indices: Array = face.get("indices", [])
		if indices.size() != 3:
			continue
		for vertex_index_value: Variant in indices:
			var vertex_index := int(vertex_index_value)
			var owners: Array = vertex_to_faces.get(vertex_index, [])
			owners.append(face_index)
			vertex_to_faces[vertex_index] = owners
	var adjacency: Array = []
	adjacency.resize(faces.size())
	for index in range(faces.size()):
		adjacency[index] = []
	for owners_value: Variant in vertex_to_faces.values():
		var owners: Array = owners_value
		for first_index in range(owners.size()):
			for second_index in range(first_index + 1, owners.size()):
				(adjacency[int(owners[first_index])] as Array).append(int(owners[second_index]))
				(adjacency[int(owners[second_index])] as Array).append(int(owners[first_index]))
	var visited: Dictionary = {}
	var component_count := 0
	for start in range(faces.size()):
		if visited.has(start):
			continue
		component_count += 1
		var queue: Array[int] = [start]
		visited[start] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			for neighbor_value: Variant in adjacency[current]:
				var neighbor := int(neighbor_value)
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				queue.append(neighbor)
	return component_count


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"ok": false}
	return {"ok": true, "data": (parser.data as Dictionary).duplicate(true)}


func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(65_536))
	return context.finish().hex_encode()


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _variants_equivalent(first: Variant, second: Variant) -> bool:
	if first is Dictionary and second is Dictionary:
		var first_dictionary: Dictionary = first
		var second_dictionary: Dictionary = second
		if first_dictionary.size() != second_dictionary.size():
			return false
		for key: Variant in first_dictionary:
			if not second_dictionary.has(key):
				return false
			if not _variants_equivalent(first_dictionary[key], second_dictionary[key]):
				return false
		return true
	if first is Array and second is Array:
		var first_array: Array = first
		var second_array: Array = second
		if first_array.size() != second_array.size():
			return false
		for index in range(first_array.size()):
			if not _variants_equivalent(first_array[index], second_array[index]):
				return false
		return true
	if (first is int or first is float) and (second is int or second is float):
		return is_equal_approx(float(first), float(second))
	return first == second


func _rect_from_json(value: Variant) -> Rect2:
	if not value is Dictionary:
		return Rect2()
	var data: Dictionary = value
	return Rect2(
		_array_to_vector2(data.get("min", [])),
		_array_to_vector2(data.get("size", []))
	)


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


func _colors_equal(first: Color, second: Color) -> bool:
	return (
		is_equal_approx(first.r, second.r)
		and is_equal_approx(first.g, second.g)
		and is_equal_approx(first.b, second.b)
		and is_equal_approx(first.a, second.a)
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures.append(message)
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("POLYGON_ASSET_SMOKE_OK")
		quit(0)
		return
	push_error("Polygon asset smoke failed with %d issue(s)." % _failures.size())
	quit(1)
