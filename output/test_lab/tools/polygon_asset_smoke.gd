extends SceneTree

const ASSET_PATH: String = "res://data/polygon_assets/open_book.polygon.json"
const COMPILER := preload("res://scripts/polygon_asset_compiler_core.gd")
const MANIFEST_PATH: String = "res://data/polygon_imports/open_book.json"
const PAGE_PALETTE_ROLES: Array[String] = [
	"page_light",
	"page_mid",
	"page_shadow",
	"accent_warm",
]
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
	await _validate_runtime()
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
	var surface_kinds_are_valid := true
	var recolored_cover_face_count := 0
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
		surface_kinds_are_valid = (
			surface_kinds_are_valid
			and ["page", "cover"].has(String(face.get("surface_kind", "")))
		)
		if (
			String(face.get("surface_kind", "")) == "cover"
			and PAGE_PALETTE_ROLES.has(palette_role)
		):
			recolored_cover_face_count += 1
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
	_check(
		surface_kinds_are_valid,
		"Every face keeps an independent page or cover surface kind."
	)
	_check(
		recolored_cover_face_count > 0,
		"Small cover-color islands can merge visually without changing surface kind."
	)
	_check(clear_order_is_valid, "Every face has a normalized clear order.")
	var outline := _vector2_array_from_json(asset_data.get("outline", []))
	var topology := _analyze_edge_topology(faces, outline.size())
	_check(
		bool(topology.get("watertight", false)),
		"Every internal edge has two owners and every outline edge has one."
	)
	_check(
		int(topology.get("connected_components", 0)) == 1,
		"Face topology has one edge-connected component."
	)
	var minimum_visible_altitude := float(
		style.get("minimum_visible_face_altitude_px", 0.0)
	)
	var skinny_face_count := 0
	var visually_merged_skinny_face_count := 0
	for face_index in range(faces.size()):
		var face: Dictionary = faces[face_index]
		if _face_minimum_altitude(face, vertices) >= minimum_visible_altitude:
			continue
		skinny_face_count += 1
		if _skinny_face_reaches_major_same_color(
			face_index,
			faces,
			vertices,
			minimum_visible_altitude
		):
			visually_merged_skinny_face_count += 1
	_check(minimum_visible_altitude > 0.0, "Style Profile declares visible-face altitude.")
	_check(skinny_face_count > 0, "Compiled topology contains skinny fill triangles to merge.")
	_check(
		visually_merged_skinny_face_count == skinny_face_count,
		"Every skinny fill triangle visually merges into an adjacent major face."
	)
	var minimum_visible_color_region_area := float(
		style.get("minimum_visible_color_region_area_px2", 0.0)
	)
	_check(
		minimum_visible_color_region_area > 0.0,
		"Style Profile declares a minimum visible color-region area."
	)
	_check(
		_count_small_color_components(
			faces,
			vertices,
			minimum_visible_color_region_area
		) == 0,
		"Every connected color region meets the minimum visible area."
	)
	var emphasized_left_lower_face := false
	for face_value: Variant in faces:
		var face: Dictionary = face_value
		if String(face.get("region", "")) != "left_page":
			continue
		if String(face.get("palette_role", "")) != "page_shadow":
			continue
		var centroid := _face_centroid(face, vertices)
		if (
			centroid.x < -40.0
			and centroid.y > 30.0
			and _face_area(face, vertices) > 2_000.0
		):
			emphasized_left_lower_face = true
			break
	_check(
		emphasized_left_lower_face,
		"Left-lower major page face uses the explicit shadow emphasis."
	)
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
	_check(bool(stats.get("watertight", false)), "Stats record watertight topology.")
	_check(
		int(stats.get("boundary_edge_count", -1))
		== int(topology.get("boundary_edge_count", -2)),
		"Stats record the verified boundary edge count."
	)
	_check(
		int(stats.get("interior_edge_count", -1))
		== int(topology.get("interior_edge_count", -2)),
		"Stats record the verified interior edge count."
	)
	_check(int(stats.get("draw_surfaces", 0)) == 1, "Stats record one draw surface.")
	_check(
		int(stats.get("visually_merged_skinny_face_count", 0)) == skinny_face_count,
		"Stats record every visually merged skinny face."
	)
	_check(
		is_equal_approx(
			float(stats.get("minimum_visible_color_region_area_px2", 0.0)),
			minimum_visible_color_region_area
		),
		"Stats record the minimum visible color-region area."
	)
	_check(
		int(stats.get("visually_merged_small_region_face_count", 0)) > 0,
		"Stats record merged faces from undersized color regions."
	)
	_check(int(stats.get("emphasized_face_count", 0)) == 1, "Stats record one emphasized face.")


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
		shader.code.find("vertex_turn_weight") >= 0
		and shader.code.find("step(0.75, COLOR.a)") >= 0,
		"Shader separates shared-vertex deformation from per-face color animation."
	)
	_check(
		shader.code.find("crease_center") >= 0
		and shader.code.find("turn_boundary_guard") >= 0,
		"Shader animates a bounded crease through page vertices."
	)
	_check(
		shader.code.find("page_fold_light") >= 0
		and shader.code.find("page_fold_shadow") >= 0,
		"Shader exposes fold color-shift endpoints."
	)


func _validate_runtime() -> void:
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
	var runtime_asset_data: Dictionary = runtime.get_asset_data()
	var runtime_faces: Array = runtime_asset_data.get("faces", [])
	var authored_turnable_face_count := 0
	for face_value: Variant in runtime_faces:
		if _motion_mask_for_face(face_value as Dictionary) >= 0.75:
			authored_turnable_face_count += 1
	_check(
		authored_turnable_face_count > 0
		and int(runtime_stats.get("turnable_face_count", 0))
		== authored_turnable_face_count,
		"Runtime keeps exactly the authored right-page faces turnable."
	)
	_check(
		int(runtime_stats.get("deformable_logical_vertex_count", 0)) > 0,
		"Runtime keeps interior right-page logical vertices deformable."
	)
	_check(
		int(runtime_stats.get("pinned_page_boundary_vertex_count", 0)) > 0,
		"Runtime pins logical vertices shared by the page and fixed book geometry."
	)
	_check(
		int(runtime_stats.get("render_face_count", 0))
		== int(runtime_stats.get("source_face_count", -1)),
		"Runtime renders exactly the source faces with no duplicated page layer."
	)
	if mesh_instance != null:
		var mesh := mesh_instance.mesh as ArrayMesh
		_check(mesh != null, "Runtime mesh is an ArrayMesh.")
		if mesh != null:
			_check(mesh.get_surface_count() == 1, "Runtime ArrayMesh has one surface.")
			_check(
				mesh.surface_get_array_len(0)
				== int(runtime_stats.get("source_face_count", 0)) * 3,
				"Runtime expands each source face once into the single surface."
			)
			var arrays := mesh.surface_get_arrays(0)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var expected_motion_masks := _build_expected_vertex_motion_masks(
				runtime_faces,
				_vector2_array_from_json(
					runtime_asset_data.get("vertices", [])
				).size()
			)
			var expanded_vertex_index := 0
			var shared_motion_masks_match := true
			var face_animation_flags_match := true
			var fixed_surface_motion_match := true
			var turnable_vertex_count := 0
			var idle_page_vertex_count := 0
			for face_value: Variant in runtime_faces:
				var face: Dictionary = face_value
				var indices: Array = face.get("indices", [])
				var expected_face_alpha := (
					1.0 if _motion_mask_for_face(face) >= 0.75 else 0.5
				)
				for vertex_index_value: Variant in indices:
					var logical_vertex_index := int(vertex_index_value)
					var uv := uvs[expanded_vertex_index]
					var color := colors[expanded_vertex_index]
					shared_motion_masks_match = (
						shared_motion_masks_match
						and is_equal_approx(
							uv.y,
							expected_motion_masks[logical_vertex_index]
						)
					)
					face_animation_flags_match = (
						face_animation_flags_match
						and absf(color.a - expected_face_alpha) <= 0.01
					)
					if String(face.get("surface_kind", "")) == "cover":
						fixed_surface_motion_match = (
							fixed_surface_motion_match
							and uv.y < 0.25
						)
					if uv.y >= 0.75:
						turnable_vertex_count += 1
					elif uv.y >= 0.25:
						idle_page_vertex_count += 1
					expanded_vertex_index += 1
			_check(
				shared_motion_masks_match,
				"Every duplicate of a shared logical vertex uses one motion weight."
			)
			_check(
				face_animation_flags_match,
				"Per-face color animation flags remain independent from vertex motion."
			)
			_check(
				fixed_surface_motion_match,
				"Visually recolored cover faces remain fixed during page turns."
			)
			_check(
				turnable_vertex_count > 0,
				"Turnable page faces retain deformable interior vertices."
			)
			_check(
				idle_page_vertex_count > 0,
				"Left-page faces remain masked separately from turnable right-page faces."
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


func _face_area(face: Dictionary, vertices: PackedVector2Array) -> float:
	var indices: Array = face.get("indices", [])
	if indices.size() != 3:
		return 0.0
	var a := vertices[int(indices[0])]
	var b := vertices[int(indices[1])]
	var c := vertices[int(indices[2])]
	return absf((b - a).cross(c - a)) * 0.5


func _face_centroid(face: Dictionary, vertices: PackedVector2Array) -> Vector2:
	var indices: Array = face.get("indices", [])
	if indices.size() != 3:
		return Vector2.ZERO
	return (
		vertices[int(indices[0])]
		+ vertices[int(indices[1])]
		+ vertices[int(indices[2])]
	) / 3.0


func _face_minimum_altitude(
	face: Dictionary,
	vertices: PackedVector2Array
) -> float:
	var indices: Array = face.get("indices", [])
	if indices.size() != 3:
		return 0.0
	var a := vertices[int(indices[0])]
	var b := vertices[int(indices[1])]
	var c := vertices[int(indices[2])]
	var maximum_edge := maxf(
		a.distance_to(b),
		maxf(b.distance_to(c), c.distance_to(a))
	)
	if maximum_edge <= 0.0:
		return 0.0
	return _face_area(face, vertices) * 2.0 / maximum_edge


func _faces_are_adjacent(first: Dictionary, second: Dictionary) -> bool:
	var first_indices: Array = first.get("indices", [])
	var second_indices: Array = second.get("indices", [])
	var shared_count := 0
	for first_index_value: Variant in first_indices:
		for second_index_value: Variant in second_indices:
			if int(first_index_value) == int(second_index_value):
				shared_count += 1
				break
	return shared_count >= 1


func _skinny_face_reaches_major_same_color(
	start_index: int,
	faces: Array,
	vertices: PackedVector2Array,
	minimum_visible_altitude: float
) -> bool:
	var target_role := String((faces[start_index] as Dictionary).get("palette_role", ""))
	var queue: Array[int] = [start_index]
	var visited: Dictionary = {start_index: true}
	while not queue.is_empty():
		var face_index: int = queue.pop_front()
		var face: Dictionary = faces[face_index]
		if _face_minimum_altitude(face, vertices) >= minimum_visible_altitude:
			return true
		for neighbor_index in range(faces.size()):
			if visited.has(neighbor_index):
				continue
			var neighbor: Dictionary = faces[neighbor_index]
			if String(neighbor.get("palette_role", "")) != target_role:
				continue
			if not _faces_are_adjacent(face, neighbor):
				continue
			visited[neighbor_index] = true
			queue.append(neighbor_index)
	return false


func _count_small_color_components(
	faces: Array,
	vertices: PackedVector2Array,
	minimum_area: float
) -> int:
	var visited: Dictionary = {}
	var small_component_count := 0
	for start_index in range(faces.size()):
		if visited.has(start_index):
			continue
		var role := String((faces[start_index] as Dictionary).get(
			"palette_role",
			""
		))
		var queue: Array[int] = [start_index]
		var component_area := 0.0
		visited[start_index] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			var current_face: Dictionary = faces[current]
			component_area += _face_area(current_face, vertices)
			for neighbor_index in range(faces.size()):
				if visited.has(neighbor_index):
					continue
				var neighbor: Dictionary = faces[neighbor_index]
				if String(neighbor.get("palette_role", "")) != role:
					continue
				if not _faces_share_edge(current_face, neighbor):
					continue
				visited[neighbor_index] = true
				queue.append(neighbor_index)
		if component_area < minimum_area:
			small_component_count += 1
	return small_component_count


func _faces_share_edge(first: Dictionary, second: Dictionary) -> bool:
	var first_indices: Array = first.get("indices", [])
	var second_indices: Array = second.get("indices", [])
	var shared_count := 0
	for first_index_value: Variant in first_indices:
		if second_indices.has(first_index_value):
			shared_count += 1
	return shared_count == 2


func _analyze_edge_topology(
	faces: Array,
	outline_vertex_count: int
) -> Dictionary:
	var edge_to_faces: Dictionary = {}
	for face_index in range(faces.size()):
		var face: Dictionary = faces[face_index]
		var indices: Array = face.get("indices", [])
		if indices.size() != 3:
			continue
		for edge_index in range(3):
			var edge := _edge_key(
				int(indices[edge_index]),
				int(indices[(edge_index + 1) % 3])
			)
			var owners: Array = edge_to_faces.get(edge, [])
			owners.append(face_index)
			edge_to_faces[edge] = owners

	var expected_boundary_edges: Dictionary = {}
	for outline_index in range(outline_vertex_count):
		expected_boundary_edges[_edge_key(
			outline_index,
			(outline_index + 1) % outline_vertex_count
		)] = true
	var adjacency: Array = []
	adjacency.resize(faces.size())
	for index in range(faces.size()):
		adjacency[index] = []
	var watertight := true
	var boundary_edge_count := 0
	var interior_edge_count := 0
	for edge_value: Variant in edge_to_faces:
		var edge := String(edge_value)
		var owners: Array = edge_to_faces[edge]
		if owners.size() == 1:
			boundary_edge_count += 1
			watertight = watertight and expected_boundary_edges.has(edge)
		elif owners.size() == 2:
			interior_edge_count += 1
			var first_owner := int(owners[0])
			var second_owner := int(owners[1])
			(adjacency[first_owner] as Array).append(second_owner)
			(adjacency[second_owner] as Array).append(first_owner)
		else:
			watertight = false
	for edge_value: Variant in expected_boundary_edges:
		var edge := String(edge_value)
		watertight = (
			watertight
			and edge_to_faces.has(edge)
			and (edge_to_faces[edge] as Array).size() == 1
		)
	watertight = (
		watertight
		and boundary_edge_count == outline_vertex_count
	)
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
	return {
		"watertight": watertight,
		"connected_components": component_count,
		"boundary_edge_count": boundary_edge_count,
		"interior_edge_count": interior_edge_count,
	}


func _build_expected_vertex_motion_masks(
	faces: Array,
	vertex_count: int
) -> PackedFloat32Array:
	var has_turnable_face := PackedByteArray()
	var has_left_page_face := PackedByteArray()
	var has_fixed_face := PackedByteArray()
	has_turnable_face.resize(vertex_count)
	has_left_page_face.resize(vertex_count)
	has_fixed_face.resize(vertex_count)
	for face_value: Variant in faces:
		var face: Dictionary = face_value
		var face_motion_mask := _motion_mask_for_face(face)
		var indices: Array = face.get("indices", [])
		for vertex_index_value: Variant in indices:
			var vertex_index := int(vertex_index_value)
			if face_motion_mask >= 0.75:
				has_turnable_face[vertex_index] = 1
			elif face_motion_mask >= 0.25:
				has_left_page_face[vertex_index] = 1
			else:
				has_fixed_face[vertex_index] = 1

	var result := PackedFloat32Array()
	result.resize(vertex_count)
	for vertex_index in range(vertex_count):
		var touches_turnable_page := has_turnable_face[vertex_index] == 1
		var touches_other_geometry := (
			has_left_page_face[vertex_index] == 1
			or has_fixed_face[vertex_index] == 1
		)
		if touches_turnable_page and not touches_other_geometry:
			result[vertex_index] = 1.0
		elif (
			not touches_turnable_page
			and has_left_page_face[vertex_index] == 1
			and has_fixed_face[vertex_index] == 0
		):
			result[vertex_index] = 0.5
	return result


func _motion_mask_for_face(face: Dictionary) -> float:
	var role := String(face.get("palette_role", ""))
	var surface_kind := String(face.get("surface_kind", ""))
	var is_page_surface := surface_kind == "page"
	if surface_kind.is_empty():
		is_page_surface = PAGE_PALETTE_ROLES.has(role)
	if not is_page_surface:
		return 0.0
	var region := String(face.get("region", ""))
	if region == "right_page":
		return 1.0
	if region == "left_page":
		return 0.5
	return 0.0


func _edge_key(first: int, second: int) -> String:
	return "%d:%d" % [mini(first, second), maxi(first, second)]


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
