extends SceneTree

const ASSET_PATH: String = "res://data/polygon_assets/open_book.polygon.json"
const BOOK_ANIMATOR_SOURCE_PATH: String = (
	"res://scripts/polygon_book_animator.gd"
)
const BOOK_SHADER_PATH: String = (
	"res://shaders/polygon_book_page_turn.gdshader"
)
const COMPILER := preload("res://scripts/polygon_asset_compiler_core.gd")
const COMPILER_SOURCE_PATH: String = "res://scripts/polygon_asset_compiler_core.gd"
const DEBUG_OVERLAY_SOURCE_PATH: String = (
	"res://scripts/polygon_mesh_debug_overlay.gd"
)
const MANIFEST_PATH: String = "res://data/polygon_imports/open_book.json"
const RUNTIME_SCRIPT := preload("res://scripts/polygon_asset_2d.gd")
const RUNTIME_SOURCE_PATH: String = "res://scripts/polygon_asset_2d.gd"
const PROMPT_BUILDER := preload("res://scripts/polygon_prompt_builder.gd")
const PROMPT_TEMPLATE_PATH: String = (
	"res://data/polygon_prompt_templates/source_image_v1.json"
)
const IMPORT_TEMPLATE_PATH: String = (
	"res://data/polygon_imports/_linear_band_asset.template.json"
)
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
	_validate_prompt_template()
	_validate_generic_compiler_source()
	await _validate_arbitrary_axis_compile(compiler)
	_validate_source(asset_data)
	_validate_asset_schema(asset_data, style)
	_validate_scene_file_shape()
	_validate_shader_shape()
	_validate_book_adapter_shape()
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
	_check(int(asset_data.get("schema_version", 0)) == 3, "Polygon asset schema_version is 3.")
	_check(String(asset_data.get("asset_id", "")) == "open_book", "Asset id is open_book.")
	_check(
		String(asset_data.get("style_id", "")) == String(style.get("style_id", "")),
		"Polygon asset references the configured Style Profile id."
	)
	var construction: Dictionary = asset_data.get("construction", {})
	_check(
		String(construction.get("mode", "")) == "shape_guided"
		and bool(construction.get("generated_geometry", false))
		and not bool(construction.get("runtime_source_texture", true)),
		"Asset records tool-built geometry with no runtime source texture."
	)
	var custom_animation: Dictionary = asset_data.get(
		"custom_animation",
		{}
	)
	_check(
		String(custom_animation.get("adapter", ""))
		== "book_page_turn",
		"Book asset declares semantic animation outside the generic runtime."
	)
	var source_usage: Array = construction.get("source_usage", [])
	_check(
		source_usage == [
			"outer_shape",
			"landmark_features",
			"color_reference",
		],
		"Asset limits source-image usage to shape and color reference."
	)
	var vertices := _vector2_array_from_json(asset_data.get("vertices", []))
	var faces_value: Variant = asset_data.get("faces", [])
	_check(not vertices.is_empty(), "Polygon asset has shared logical vertices.")
	_check(faces_value is Array, "Polygon asset faces are an array.")
	if not faces_value is Array:
		return
	var faces: Array = faces_value
	var target: Dictionary = style.get("target_face_count", {})
	var target_min := int(target.get("min", 48))
	var target_max := int(target.get("max", 80))
	_check(
		faces.size() >= target_min
		and faces.size() <= target_max,
		"Face count is inside the %d–%d Style Profile target."
		% [target_min, target_max]
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
	var minimum_visible_area := float(
		style.get("minimum_visible_face_area_px2", 0.0)
	)
	var minimum_outline_edge_length := float(
		style.get("minimum_outline_edge_length_px", 0.0)
	)
	_check(minimum_visible_altitude > 0.0, "Style Profile declares visible-face altitude.")
	_check(
		minimum_visible_area > 0.0,
		"Style Profile declares a minimum visible face area."
	)
	_check(
		minimum_outline_edge_length > 0.0,
		"Style Profile declares a minimum outline edge length."
	)
	var actual_minimum_area := INF
	var actual_minimum_altitude := INF
	for face_value: Variant in faces:
		var face: Dictionary = face_value
		actual_minimum_area = minf(
			actual_minimum_area,
			_face_area(face, vertices)
		)
		actual_minimum_altitude = minf(
			actual_minimum_altitude,
			_face_minimum_altitude(face, vertices)
		)
	_check(
		actual_minimum_area >= minimum_visible_area,
		"Compiled topology contains no face below the visible-area threshold."
	)
	_check(
		actual_minimum_altitude >= minimum_visible_altitude,
		"Compiled topology contains no thin face below the altitude threshold."
	)
	var actual_minimum_outline_edge := INF
	for outline_index in range(outline.size()):
		actual_minimum_outline_edge = minf(
			actual_minimum_outline_edge,
			outline[outline_index].distance_to(
				outline[(outline_index + 1) % outline.size()]
			)
		)
	_check(
		actual_minimum_outline_edge >= minimum_outline_edge_length,
		"Compiled outline contains no short edge that can form a sliver face."
	)
	var emphasized_left_lower_face := false
	for face_value: Variant in faces:
		var face: Dictionary = face_value
		if String(face.get("region", "")) != "left_page":
			continue
		if String(face.get("palette_role", "")) != "surface_shadow":
			continue
		var centroid := _face_centroid(face, vertices)
		if (
			centroid.x < -60.0
			and centroid.y > 30.0
			and _face_area(face, vertices) >= 800.0
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
	_validate_features(
		asset_data,
		style,
		vertices,
		faces
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
		String(stats.get("construction_mode", "")) == "shape_guided",
		"Stats record source-guided tool construction."
	)
	_check(
		int(stats.get("feature_count", 0)) == 1,
		"Stats record the extracted primary feature."
	)
	_check(
		int(stats.get("protected_feature_edge_count", 0)) >= 2,
		"Stats record protected edges on both sides of the feature."
	)
	_check(
		is_equal_approx(
			float(stats.get("minimum_triangle_area_px2", 0.0)),
			actual_minimum_area
		),
		"Stats record the verified minimum face area."
	)
	_check(
		absf(
			float(stats.get("minimum_face_altitude_px", 0.0))
			- actual_minimum_altitude
		) <= 0.001,
		"Stats record the verified minimum face altitude."
	)
	_check(
		absf(
			float(stats.get("minimum_outline_edge_length_px", 0.0))
			- actual_minimum_outline_edge
		) <= 0.001,
		"Stats record the verified minimum outline edge length."
	)
	_check(
		int(stats.get("removed_outline_vertex_count", 0)) > 0,
		"Compiler records removed outline nodes instead of masking their faces."
	)
	_check(
		int(stats.get("constructed_outline_removed_vertex_count", 0)) > 0,
		"Compiler removes new sliver-prone nodes after inserting shape boundaries."
	)
	_check(int(stats.get("emphasized_face_count", 0)) == 1, "Stats record one emphasized face.")


func _validate_features(
	asset_data: Dictionary,
	style: Dictionary,
	vertices: PackedVector2Array,
	faces: Array
) -> void:
	var features_value: Variant = asset_data.get("features", [])
	_check(features_value is Array, "Polygon asset features is an array.")
	if not features_value is Array:
		return
	var features: Array = features_value
	_check(features.size() == 1, "Open book has one extracted landmark feature.")
	if features.size() != 1 or not features[0] is Dictionary:
		return
	var feature: Dictionary = features[0]
	_check(
		String(feature.get("id", "")) == "spine"
		and String(feature.get("kind", "")) == "linear_band"
		and String(feature.get("negative_region", "")) == "left_page"
		and String(feature.get("region", "")) == "spine"
		and String(feature.get("positive_region", "")) == "right_page",
		"Book manifest maps one generic linear band to its three regions."
	)
	var axis := _array_to_vector2(feature.get("axis", []))
	var cross_axis := _array_to_vector2(
		feature.get("cross_axis", [])
	)
	var minimum_coordinate := float(
		feature.get("minimum_coordinate", 0.0)
	)
	var center_coordinate := float(
		feature.get("center_coordinate", 0.0)
	)
	var maximum_coordinate := float(
		feature.get("maximum_coordinate", 0.0)
	)
	var source_width := float(feature.get("source_width_px", 0.0))
	var constructed_width := float(
		feature.get("constructed_width_px", 0.0)
	)
	var extraction: Dictionary = style.get("feature_extraction", {})
	var minimum_width := float(
		extraction.get("minimum_constructed_band_width_px", 0.0)
	)
	var maximum_width := float(
		extraction.get("maximum_constructed_band_width_px", INF)
	)
	_check(
		source_width > 0.0,
		"Spine extraction records a non-zero source width."
	)
	_check(
		constructed_width >= minimum_width
		and constructed_width <= maximum_width
		and constructed_width >= source_width,
		"Tool rebuilds the spine inside the configured readable width range."
	)
	_check(
		absf(axis.length() - 1.0) <= 0.001
		and absf(cross_axis.length() - 1.0) <= 0.001
		and absf(axis.dot(cross_axis)) <= 0.001,
		"Feature stores an orthonormal local basis."
	)
	_check(
		absf(
			center_coordinate
			- (minimum_coordinate + maximum_coordinate) * 0.5
		) <= 0.001
		and absf(
			constructed_width
			- (maximum_coordinate - minimum_coordinate)
		) <= 0.001,
		"Constructed feature bounds agree with its center and width."
	)
	var source_color_hex := String(feature.get("source_color", ""))
	var source_color := Color("#" + source_color_hex)
	var palette: Dictionary = style.get("palette", {})
	var palette_role := String(feature.get("palette_role", ""))
	_check(
		source_color_hex.length() == 6
		and palette.has(palette_role),
		"Spine records its sampled source color and a valid palette role."
	)
	_check(
		palette_role == _nearest_palette_role(source_color, palette),
		"Spine palette role is the nearest Style Profile color to the source sample."
	)

	var region_geometry_is_constrained := true
	var feature_faces_use_extracted_color := true
	for face_value: Variant in faces:
		var face: Dictionary = face_value
		var region := String(face.get("region", ""))
		var indices: Array = face.get("indices", [])
		for index_value: Variant in indices:
			var coordinate := vertices[int(index_value)].dot(
				cross_axis
			)
			if region == "left_page":
				region_geometry_is_constrained = (
					region_geometry_is_constrained
					and coordinate <= minimum_coordinate + 0.001
				)
			elif region == "right_page":
				region_geometry_is_constrained = (
					region_geometry_is_constrained
					and coordinate >= maximum_coordinate - 0.001
				)
			elif region == "spine":
				region_geometry_is_constrained = (
					region_geometry_is_constrained
					and coordinate >= minimum_coordinate - 0.001
					and coordinate <= maximum_coordinate + 0.001
				)
		if region == "spine":
			feature_faces_use_extracted_color = (
				feature_faces_use_extracted_color
				and String(face.get("palette_role", "")) == palette_role
			)
	_check(
		region_geometry_is_constrained,
		"No generated face crosses a protected spine boundary."
	)
	_check(
		feature_faces_use_extracted_color,
		"Every feature face uses the source-derived palette role."
	)
	_check(
		_count_feature_boundary_edges(
			faces,
			vertices,
			cross_axis,
			minimum_coordinate,
			maximum_coordinate,
			"left_page",
			"spine",
			"right_page"
		) >= 2,
		"Both feature boundaries are shared protected edges, not visual overlays."
	)


func _count_feature_boundary_edges(
	faces: Array,
	vertices: PackedVector2Array,
	cross_axis: Vector2,
	minimum_coordinate: float,
	maximum_coordinate: float,
	negative_region: String,
	feature_region: String,
	positive_region: String
) -> int:
	var edge_owners: Dictionary = {}
	for face_value: Variant in faces:
		var face: Dictionary = face_value
		var indices: Array = face.get("indices", [])
		for edge_index in range(3):
			var first := int(indices[edge_index])
			var second := int(indices[(edge_index + 1) % 3])
			var edge_key := _edge_key(first, second)
			var owners: Array = edge_owners.get(edge_key, [])
			owners.append(String(face.get("region", "")))
			edge_owners[edge_key] = owners
	var protected_count := 0
	for edge_value: Variant in edge_owners:
		var edge_key := String(edge_value)
		var owners: Array = edge_owners[edge_key]
		if owners.size() != 2 or not owners.has(feature_region):
			continue
		var index_parts := edge_key.split(":")
		var first_point := vertices[int(index_parts[0])]
		var second_point := vertices[int(index_parts[1])]
		var on_negative := (
			is_equal_approx(
				first_point.dot(cross_axis),
				minimum_coordinate
			)
			and is_equal_approx(
				second_point.dot(cross_axis),
				minimum_coordinate
			)
			and owners.has(negative_region)
		)
		var on_positive := (
			is_equal_approx(
				first_point.dot(cross_axis),
				maximum_coordinate
			)
			and is_equal_approx(
				second_point.dot(cross_axis),
				maximum_coordinate
			)
			and owners.has(positive_region)
		)
		if on_negative or on_positive:
			protected_count += 1
	return protected_count


func _nearest_palette_role(source_color: Color, palette: Dictionary) -> String:
	var nearest_role := ""
	var nearest_distance := INF
	var roles: Array = palette.keys()
	roles.sort()
	for role_value: Variant in roles:
		var role := String(role_value)
		var palette_color := Color(String(palette[role]))
		var delta := Vector3(
			source_color.r - palette_color.r,
			source_color.g - palette_color.g,
			source_color.b - palette_color.b
		)
		if delta.length_squared() < nearest_distance:
			nearest_distance = delta.length_squared()
			nearest_role = role
	return nearest_role


func _validate_prompt_template() -> void:
	_check(
		FileAccess.file_exists(PROMPT_TEMPLATE_PATH),
		"Reusable Polygon source-image prompt template exists."
	)
	var builder := PROMPT_BUILDER.new()
	var first_result: Dictionary = builder.build_from_manifest(
		MANIFEST_PATH
	)
	var second_result: Dictionary = builder.build_from_manifest(
		MANIFEST_PATH
	)
	_check(
		bool(first_result.get("ok", false))
		and bool(second_result.get("ok", false)),
		"Book manifest renders through the reusable prompt template."
	)
	if (
		not bool(first_result.get("ok", false))
		or not bool(second_result.get("ok", false))
	):
		return
	var first_prompt := String(first_result.get("prompt", ""))
	var second_prompt := String(second_result.get("prompt", ""))
	_check(
		first_prompt == second_prompt,
		"Prompt template rendering is deterministic."
	)
	_check(
		not first_prompt.contains("{{")
		and first_prompt.contains("outer contour alone")
		and first_prompt.contains("Landmark 1")
		and first_prompt.contains("one continuous unbroken band")
		and first_prompt.contains("constructs all final Polygon points and faces itself"),
		"Rendered prompt enforces recognizable silhouette and structural landmarks."
	)
	var rejection_checks: Array = first_result.get(
		"rejection_checks",
		[]
	)
	_check(
		rejection_checks.size() >= 8,
		"Prompt template declares machine-authoring rejection checks."
	)
	var import_template_result := _load_json_dictionary(
		IMPORT_TEMPLATE_PATH
	)
	_check(
		bool(import_template_result.get("ok", false)),
		"Reusable linear-band import manifest template loads."
	)
	if bool(import_template_result.get("ok", false)):
		var import_template: Dictionary = import_template_result["data"]
		_check(
			int(import_template.get("schema_version", 0)) == 3
			and String(import_template.get("prompt_template", ""))
			== PROMPT_TEMPLATE_PATH
			and import_template.get("palette", {}) is Dictionary
			and (import_template.get("feature_guides", []) as Array).size()
			== 1,
			"Import template binds schema v3, palette, prompt, and one primary feature."
		)


func _validate_generic_compiler_source() -> void:
	var file := FileAccess.open(COMPILER_SOURCE_PATH, FileAccess.READ)
	_check(file != null, "Generic Polygon compiler source is readable.")
	if file == null:
		return
	var source := file.get_as_text().to_lower()
	var object_specific_tokens: Array[String] = [
		"spine",
		"left_page",
		"right_page",
		"vertical_band",
	]
	var is_generic := true
	for token: String in object_specific_tokens:
		is_generic = is_generic and not source.contains(token)
	_check(
		is_generic,
		"Compiler core contains no book-specific feature or region ids."
	)
	_check(
		source.contains("linear_band")
		and source.contains("cross_axis")
		and source.contains("_clip_polygon_half_plane"),
		"Compiler core constructs arbitrary-axis linear feature partitions."
	)
	var generic_runtime_sources := [
		RUNTIME_SOURCE_PATH,
		DEBUG_OVERLAY_SOURCE_PATH,
		SHADER_PATH,
	]
	var runtime_sources_are_generic := true
	for source_path: String in generic_runtime_sources:
		var source_file := FileAccess.open(source_path, FileAccess.READ)
		if source_file == null:
			runtime_sources_are_generic = false
			continue
		var runtime_source := source_file.get_as_text().to_lower()
		for token: String in object_specific_tokens:
			runtime_sources_are_generic = (
				runtime_sources_are_generic
				and not runtime_source.contains(token)
			)
		for motion_token in [
			"page_turn",
			"turnable_page",
			"right_page_position",
		]:
			runtime_sources_are_generic = (
				runtime_sources_are_generic
				and not runtime_source.contains(motion_token)
			)
	_check(
		runtime_sources_are_generic,
		"Runtime, shader, and debug overlay contain no book-specific motion ids."
	)


func _validate_arbitrary_axis_compile(compiler: RefCounted) -> void:
	var fixture_directory := ProjectSettings.globalize_path(
		"user://polygon_asset_generic_smoke"
	)
	var source_path := fixture_directory.path_join(
		"rotated_source.png"
	)
	var manifest_path := fixture_directory.path_join(
		"rotated_manifest.json"
	)
	var output_path := fixture_directory.path_join(
		"rotated_output.polygon.json"
	)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		fixture_directory
	)
	_check(
		directory_error == OK,
		"Generic compiler fixture directory can be created."
	)
	if directory_error != OK:
		return
	var source := Image.new()
	var load_error := source.load(
		ProjectSettings.globalize_path(SOURCE_PATH)
	)
	if load_error != OK:
		_check(false, "Generic compiler fixture source loads.")
		return
	source.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var rotated := Image.create(
		source.get_height(),
		source.get_width(),
		false,
		Image.FORMAT_RGBA8
	)
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			rotated.set_pixel(
				source.get_height() - 1 - y,
				x,
				source.get_pixel(x, y)
			)
	var save_error := rotated.save_png(source_path)
	_check(
		save_error == OK,
		"Generic compiler rotated fixture can be written."
	)
	if save_error != OK:
		return
	var manifest := {
		"schema_version": 3,
		"asset_id": "rotated_generic_fixture",
		"source_image": source_path,
		"style_profile": STYLE_PATH,
		"output_asset": output_path,
		"background_key": "#ff00ff",
		"pivot": {"mode": "foreground_bounds_center"},
		"default_region": "surface",
		"motion_profile": {
			"motion_axis": [0.0, 1.0],
			"primary_motion_regions": ["positive_side"],
			"secondary_motion_regions": ["negative_side"],
			"motion_surface_kinds": ["surface"],
			"generation_tint_palette_role": "accent_warm",
			"dissolve_tint_palette_role": "secondary_shadow",
		},
		"custom_animation": {},
		"feature_guides": [{
			"id": "primary_landmark",
			"kind": "linear_band",
			"axis": [1.0, 0.0],
			"cross_axis": [0.0, 1.0],
			"anchor_normalized": [0.5, 0.5],
			"sample_offsets": [-0.25, 0.0, 0.25],
			"negative_region": "negative_side",
			"region": "landmark",
			"positive_region": "positive_side",
			"search_half_width_ratio": 0.1,
			"minimum_constructed_width_px": 20.0,
			"maximum_constructed_width_px": 28.0,
		}],
		"facet_emphasis": [],
		"anchors": {},
		"collision": {
			"strategy": "convex_hull",
			"static_during_visual_animation": true,
		},
	}
	var manifest_file := FileAccess.open(
		manifest_path,
		FileAccess.WRITE
	)
	_check(
		manifest_file != null,
		"Generic compiler rotated manifest can be written."
	)
	if manifest_file == null:
		return
	manifest_file.store_string(
		JSON.stringify(manifest, "\t", true, true) + "\n"
	)
	manifest_file = null
	var result: Dictionary = compiler.compile_manifest(manifest_path)
	_check(
		bool(result.get("ok", false)),
		"Generic compiler handles the same landmark on a horizontal axis."
	)
	if bool(result.get("ok", false)):
		var data: Dictionary = result["data"]
		var features: Array = data.get("features", [])
		var regions: Dictionary = data.get("regions", {})
		var feature: Dictionary = (
			features[0] as Dictionary
			if not features.is_empty()
			else {}
		)
		_check(
			_array_to_vector2(feature.get("axis", [])).is_equal_approx(
				Vector2.RIGHT
			)
			and _array_to_vector2(
				feature.get("cross_axis", [])
			).is_equal_approx(Vector2.DOWN),
			"Compiled feature preserves the manifest coordinate basis."
		)
		_check(
			regions.has("negative_side")
			and regions.has("landmark")
			and regions.has("positive_side")
			and not regions.has("left_page")
			and not regions.has("right_page"),
			"Compiler emits manifest-defined region ids without book defaults."
		)
		var write_error: Error = compiler.write_compiled_result(result)
		_check(
			write_error == OK,
			"Generic compiler fixture can be written for runtime loading."
		)
		if write_error == OK:
			var runtime := RUNTIME_SCRIPT.new()
			runtime.name = "RotatedGenericRuntime"
			root.add_child(runtime)
			await process_frame
			var runtime_error: Error = runtime.load_asset(output_path)
			var runtime_stats: Dictionary = runtime.get_runtime_stats()
			_check(
				runtime_error == OK,
				"Generic runtime loads the arbitrary-axis compiled asset."
			)
			_check(
				_array_to_vector2(
					runtime_stats.get("motion_axis", [])
				).is_equal_approx(Vector2.DOWN)
				and int(runtime_stats.get(
					"primary_motion_face_count",
					0
				)) > 0,
				"Generic runtime uses manifest-defined motion direction and regions."
			)
			runtime.set_motion_progress(0.5)
			runtime.set_motion_strength(0.6)
			runtime.set_generation_progress(0.4)
			runtime.set_dissolve_progress(0.3)
			var effect_stats: Dictionary = runtime.get_runtime_stats()
			_check(
				is_equal_approx(
					float(effect_stats.get("motion_progress", 0.0)),
					0.5
				),
				"Arbitrary-axis generic motion is directly controllable."
			)
			_check(
				is_equal_approx(
					float(effect_stats.get("generation_progress", 0.0)),
					0.4
				)
				and is_equal_approx(
					float(effect_stats.get("dissolve_progress", 0.0)),
					0.3
				),
				"Generic generation and dissolve progress are directly controllable."
			)
			runtime.queue_free()
			await process_frame
	DirAccess.remove_absolute(manifest_path)
	DirAccess.remove_absolute(source_path)
	DirAccess.remove_absolute(output_path)
	DirAccess.remove_absolute(fixture_directory)


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
		shader.code.find("vertex_motion_weight") >= 0
		and shader.code.find("step(0.75, COLOR.a)") >= 0,
		"Generic shader separates shared-vertex motion from per-face color animation."
	)
	_check(
		shader.code.find("motion_progress") >= 0
		and shader.code.find("motion_strength") >= 0
		and shader.code.find("boundary_guard") >= 0,
		"Generic shader exposes bounded point motion."
	)
	_check(
		shader.code.find("generation_progress") >= 0
		and shader.code.find("dissolve_progress") >= 0
		and shader.code.find("generation_tint") >= 0
		and shader.code.find("dissolve_tint") >= 0,
		"Generic shader exposes generation and dissolve lifecycle effects."
	)
	_check(
		shader.code.find("generation_progress <= 0.0001") >= 0
		and shader.code.find("generation_progress >= 0.9999") >= 0
		and shader.code.find("dissolve_progress <= 0.0001") >= 0
		and shader.code.find("dissolve_progress >= 0.9999") >= 0,
		"Generic lifecycle shader removes endpoint residue faces."
	)
	_check(
		shader.code.find("page_turn_progress") < 0
		and shader.code.find("page_fold") < 0
		and shader.code.find("crease_center") < 0,
		"Generic shader contains no book-specific page-turn algorithm."
	)


func _validate_book_adapter_shape() -> void:
	var book_shader := load(BOOK_SHADER_PATH) as Shader
	_check(book_shader != null, "Book page-turn adapter shader loads.")
	if book_shader != null:
		_check(
			book_shader.code.find("page_turn_progress") >= 0
			and book_shader.code.find("page_fold_light") >= 0
			and book_shader.code.find("crease_center") >= 0,
			"Book-only shader owns page geometry and color animation."
		)
		_check(
			book_shader.code.find("generation_progress") >= 0
			and book_shader.code.find("dissolve_progress") >= 0
			and book_shader.code.find("motion_strength") >= 0,
			"Book-only shader preserves the generic lifecycle contract."
		)
		_check(
			book_shader.code.find("generation_progress <= 0.0001") >= 0
			and book_shader.code.find("dissolve_progress >= 0.9999") >= 0,
			"Book-only shader preserves residue-free lifecycle endpoints."
		)
	var adapter_file := FileAccess.open(
		BOOK_ANIMATOR_SOURCE_PATH,
		FileAccess.READ
	)
	_check(adapter_file != null, "Book page-turn animator source is readable.")
	if adapter_file != null:
		var adapter_source := adapter_file.get_as_text()
		_check(
			adapter_source.contains("ADAPTER_ID")
			and adapter_source.contains("set_page_turn_progress")
			and adapter_source.contains("set_effect_shader"),
			"Book page-turn API exists only in the semantic adapter."
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
	var motion_profile: Dictionary = runtime_asset_data.get(
		"motion_profile",
		{}
	)
	var authored_primary_face_count := 0
	for face_value: Variant in runtime_faces:
		if _motion_mask_for_face(
			face_value as Dictionary,
			motion_profile
		) >= 0.75:
			authored_primary_face_count += 1
	_check(
		authored_primary_face_count > 0
		and int(runtime_stats.get("primary_motion_face_count", 0))
		== authored_primary_face_count,
		"Runtime keeps exactly the manifest-authored primary motion faces."
	)
	_check(
		int(runtime_stats.get("motion_logical_vertex_count", 0)) > 0,
		"Runtime keeps interior primary-region logical vertices movable."
	)
	_check(
		int(runtime_stats.get("pinned_motion_boundary_vertex_count", 0)) > 0,
		"Runtime pins logical vertices shared by moving and fixed geometry."
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
				),
				_vector2_array_from_json(
					runtime_asset_data.get("outline", [])
				),
				motion_profile
			)
			var expanded_vertex_index := 0
			var shared_motion_masks_match := true
			var face_animation_flags_match := true
			var fixed_surface_motion_match := true
			var spine_motion_match := true
			var turnable_vertex_count := 0
			var idle_page_vertex_count := 0
			for face_value: Variant in runtime_faces:
				var face: Dictionary = face_value
				var indices: Array = face.get("indices", [])
				var expected_face_alpha := (
					1.0
					if _motion_mask_for_face(
						face,
						motion_profile
					) >= 0.75
					else 0.5
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
					if String(face.get("region", "")) == "spine":
						spine_motion_match = (
							spine_motion_match
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
				"Cover faces remain fixed during page turns."
			)
			_check(
				spine_motion_match,
				"Constructed spine faces remain fixed during page turns."
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
		runtime.set_effect_shader(load(BOOK_SHADER_PATH) as Shader)
		var reload_error: Error = runtime.load_asset(ASSET_PATH)
		var reloaded_material := (
			runtime.get_mesh_instance().material as ShaderMaterial
		)
		var generic_shader := load(
			"res://shaders/polygon_asset.gdshader"
		) as Shader
		_check(
			reload_error == OK
			and reloaded_material != null
			and reloaded_material.shader
			== generic_shader,
			"Reloading an asset restores the generic shader before adapter binding."
		)
	var outline_nodes := runtime.find_children("*", "Line2D", true, false)
	_check(outline_nodes.size() == 1, "Runtime owns one synchronized Line2D outline.")
	var area := runtime.get_node_or_null("InteractionArea") as Area2D
	_check(area != null, "Runtime creates an Area2D interaction boundary.")
	var collision := runtime.get_node_or_null("InteractionArea/CollisionPolygon") as CollisionPolygon2D
	_check(collision != null, "Runtime creates convex-hull collision.")
	var collision_before := collision.polygon.duplicate() if collision != null else PackedVector2Array()

	runtime.set_animation_time(2.5)
	runtime.set_motion_progress(0.5)
	runtime.set_motion_strength(0.6)
	runtime.set_generation_progress(0.4)
	runtime.set_dissolve_progress(0.65)
	var progress_stats: Dictionary = runtime.get_runtime_stats()
	_check(
		is_equal_approx(float(progress_stats.get("animation_time", 0.0)), 2.5),
		"Animation time can be set directly."
	)
	_check(
		is_equal_approx(
			float(progress_stats.get("motion_progress", 0.0)),
			0.5
		)
		and is_equal_approx(
			float(progress_stats.get("motion_strength", 0.0)),
			0.6
		),
		"Generic motion progress and strength can be set directly."
	)
	_check(
		is_equal_approx(
			float(progress_stats.get("generation_progress", 0.0)),
			0.4
		)
		and is_equal_approx(
			float(progress_stats.get("dissolve_progress", 0.0)),
			0.65
		),
		"Generic generation and dissolve progress can be set directly."
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
		and is_zero_approx(float(reset_stats.get("motion_progress", -1.0)))
		and is_zero_approx(float(reset_stats.get("motion_strength", -1.0)))
		and is_equal_approx(
			float(reset_stats.get("generation_progress", 0.0)),
			1.0
		)
		and is_zero_approx(float(reset_stats.get("dissolve_progress", -1.0))),
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
	_check(
		scene.has_method("get_book_animation_state"),
		"Demo exposes the isolated book-animation adapter state."
	)
	if (
		not scene.has_method("get_auto_demo_state")
		or not scene.has_method("debug_set_auto_demo_time")
		or not scene.has_method("get_book_animation_state")
	):
		scene.queue_free()
		return
	var initial_state: Dictionary = scene.call("get_auto_demo_state")
	_check(bool(initial_state.get("enabled", false)), "Auto demo is enabled on scene entry.")
	var polygon_asset: Node = scene.call("get_polygon_asset")
	scene.call("debug_set_auto_demo_time", 0.45)
	var generation_stats: Dictionary = polygon_asset.call("get_runtime_stats")
	_check(
		float(generation_stats.get("generation_progress", 1.0)) > 0.3
		and float(generation_stats.get("generation_progress", 1.0)) < 0.7,
		"Auto demo reaches a visible generic generation phase."
	)
	scene.call("debug_set_auto_demo_time", 2.2)
	var book_state: Dictionary = scene.call("get_book_animation_state")
	_check(
		float(book_state.get("page_turn_progress", 0.0)) > 0.4,
		"Auto demo reaches page turn through the book-only adapter."
	)
	scene.call("debug_set_auto_demo_time", 4.1)
	var clear_stats: Dictionary = polygon_asset.call("get_runtime_stats")
	_check(
		float(clear_stats.get("dissolve_progress", 0.0)) > 0.4,
		"Auto demo reaches a visible generic dissolve phase."
	)
	_check(
		float(clear_stats.get("motion_strength", 0.0)) > 0.0,
		"Auto demo keeps generic motion enabled independently of page turn."
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
	vertices: PackedVector2Array,
	outline: PackedVector2Array,
	motion_profile: Dictionary
) -> PackedFloat32Array:
	var vertex_count := vertices.size()
	var has_primary_face := PackedByteArray()
	var has_secondary_face := PackedByteArray()
	var has_fixed_face := PackedByteArray()
	has_primary_face.resize(vertex_count)
	has_secondary_face.resize(vertex_count)
	has_fixed_face.resize(vertex_count)
	for face_value: Variant in faces:
		var face: Dictionary = face_value
		var face_motion_mask := _motion_mask_for_face(
			face,
			motion_profile
		)
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
		elif touches_primary and not touches_other_geometry:
			result[vertex_index] = 1.0
		elif (
			not touches_primary
			and has_secondary_face[vertex_index] == 1
			and has_fixed_face[vertex_index] == 0
		):
			result[vertex_index] = 0.5
	return result


func _motion_mask_for_face(
	face: Dictionary,
	motion_profile: Dictionary
) -> float:
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
