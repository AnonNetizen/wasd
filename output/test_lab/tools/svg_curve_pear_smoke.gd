extends SceneTree

const SCENE_PATH: String = "res://scenes/svg_curve_pear_test.tscn"
const SHADER_PATH: String = "res://shaders/anchored_star_window.gdshader"
const SHAPE_SCRIPT_PATH: String = "res://scripts/svg_curve_compound_shape.gd"
const TEST_SCRIPT_PATH: String = "res://scripts/svg_curve_pear_test.gd"
const SVG_SOURCE_PATH: String = "res://assets/svg_curve/pear_source.svg"


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var source_svg := FileAccess.get_file_as_string(SVG_SOURCE_PATH)
	if not source_svg.contains("translate(0,512) scale(0.1,-0.1)"):
		_fail("Copied pear SVG lost its authored coordinate transform.")
		return
	if not source_svg.contains(" c-") or not source_svg.contains("z m"):
		_fail("Copied pear SVG no longer contains the source cubic compound path.")
		return
	var shape_source := FileAccess.get_file_as_string(SHAPE_SCRIPT_PATH)
	for forbidden_term in ["_physics_process", "spring", "area_pressure", "slime_cross"]:
		if shape_source.contains(forbidden_term):
			_fail("Curve conversion unexpectedly depends on soft-body code: %s." % forbidden_term)
			return
	var test_source := FileAccess.get_file_as_string(TEST_SCRIPT_PATH)
	if test_source.contains("draw_line("):
		_fail("Clean SVG preview must not add decorative or background lines.")
		return

	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load SVG curve pear scene.")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	if int(scene.call("debug_subpath_count")) != 3:
		_fail("Expected the SVG compound path to produce three Curve2D subpaths.")
		return
	if int(scene.call("debug_path_node_count")) != 3:
		_fail("Expected one Path2D node per authoritative SVG subpath.")
		return
	if int(scene.call("debug_hole_count")) != 2:
		_fail("Expected the two reverse-wound SVG subpaths to become enclosed fill regions.")
		return
	var fill_sample_groups: Array = scene.call("debug_fill_screen_sample_groups")
	if fill_sample_groups.size() != 2:
		_fail("Expected independent fill diagnostics for the leaf and pear-body interiors.")
		return
	for fill_group_value: Variant in fill_sample_groups:
		var fill_group := fill_group_value as PackedVector2Array
		if fill_group.is_empty():
			_fail("An enclosed SVG interior produced no fill triangles or sample points.")
			return
	if not bool(scene.call("debug_all_curves_closed")):
		_fail("Every imported SVG subpath must remain a closed Curve2D.")
		return
	if int(scene.call("debug_curve_segment_count")) < 20:
		_fail("Too few authored SVG curve segments survived parsing.")
		return
	if int(scene.call("debug_curve_point_count")) < 20:
		_fail("Too few Curve2D anchors survived direct SVG conversion.")
		return
	if int(scene.call("debug_tessellated_point_count")) <= int(
		scene.call("debug_curve_point_count")
	):
		_fail("Curve tessellation did not produce a render cache denser than the authored curves.")
		return
	if int(scene.call("debug_edge_triangle_count")) < 20:
		_fail("Original black SVG region produced too few edge triangles.")
		return
	if int(scene.call("debug_triangle_count")) < 20:
		_fail("Enclosed pear-and-leaf interiors produced too few fill triangles.")
		return
	var edge_area_ratio := float(scene.call("debug_edge_area_ratio"))
	if edge_area_ratio < 0.985 or edge_area_ratio > 1.015:
		_fail("Black SVG edge mesh did not preserve compound area: %.5f." % edge_area_ratio)
		return
	var area_ratio := float(scene.call("debug_fill_area_ratio"))
	if area_ratio < 0.985 or area_ratio > 1.015:
		_fail("Perspective mesh did not preserve enclosed interior area: %.5f." % area_ratio)
		return
	var display_size := scene.call("debug_curve_display_size") as Vector2
	if display_size.x < 240.0 or display_size.y < 340.0:
		_fail("Converted pear is too small for the dedicated preview: %s." % display_size)
		return

	var material := scene.call("debug_perspective_material") as ShaderMaterial
	var expected_shader := load(SHADER_PATH) as Shader
	if material == null or material.shader != expected_shader:
		_fail("Enclosed interior mesh does not directly reuse anchored_star_window.gdshader.")
		return
	if bool(scene.call("debug_edge_uses_shader")):
		_fail("Original black SVG region must remain a shader-free solid edge.")
		return
	if bool(scene.call("debug_curve_overlay_visible")):
		_fail("Curve overlay must default to hidden for the clean preview.")
		return
	scene.call("debug_set_curve_overlay", true)
	if not bool(scene.call("debug_curve_overlay_visible")):
		_fail("Curve overlay diagnostics cannot expose the imported path boundaries.")
		return
	scene.call("debug_set_curve_overlay", false)

	scene.call("debug_set_preview_time", 0.0)
	var start_position := scene.call("debug_curve_shape_position") as Vector2
	scene.call("debug_set_preview_time", 2.4)
	var moved_position := scene.call("debug_curve_shape_position") as Vector2
	if moved_position.distance_to(start_position) < 18.0:
		_fail("Curve pear did not move far enough to expose SCREEN_UV anchoring.")
		return

	print(
		"SVG curve pear diagnostics: subpaths=%d interiors=%d edge_triangles=%d fill_triangles=%d edge_area=%.5f fill_area=%.5f"
		% [
			int(scene.call("debug_subpath_count")),
			int(scene.call("debug_hole_count")),
			int(scene.call("debug_edge_triangle_count")),
			int(scene.call("debug_triangle_count")),
			edge_area_ratio,
			area_ratio,
		]
	)
	print("SVG CURVE PEAR SMOKE PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
