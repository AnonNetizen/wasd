extends SceneTree

const SCENE_PATH: String = "res://scenes/svg_curve_pear_test.tscn"
const SHADER_PATH: String = "res://shaders/anchored_star_window.gdshader"
const SHAPE_SCRIPT_PATH: String = "res://scripts/svg_curve_outline_shape.gd"
const TEST_SCRIPT_PATH: String = "res://scripts/svg_curve_pear_test.gd"
const SVG_SOURCE_PATH: String = "res://assets/svg_curve/pear_source.svg"
const DEFAULT_BORDER_WIDTH: float = 12.0


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var source_svg := FileAccess.get_file_as_string(SVG_SOURCE_PATH)
	if not source_svg.contains(
		"translate(189.226660,627.553395) scale(0.054699,-0.054699)"
	):
		_fail("Copied pear SVG lost its authored coordinate transform.")
		return
	if source_svg.count("<path") != 1 or not source_svg.contains("M4910 7993"):
		_fail("Pear SVG must contain exactly one authored closed outline path.")
		return
	if source_svg.contains("z m"):
		_fail("Pear SVG unexpectedly contains the previous compound-path subpaths.")
		return

	var shape_source := FileAccess.get_file_as_string(SHAPE_SCRIPT_PATH)
	for forbidden_term in [
		"_physics_process",
		"spring",
		"area_pressure",
		"slime_cross",
		"NavigationServer2D",
		"add_obstruction_outline",
	]:
		if shape_source.contains(forbidden_term):
			_fail("Single-outline conversion contains an unwanted dependency: %s." % forbidden_term)
			return
	if shape_source.count("Line2D.new()") != 1:
		_fail("Single SVG outline must create exactly one adjustable Line2D border.")
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

	if int(scene.call("debug_subpath_count")) != 1:
		_fail("New pear SVG must produce exactly one Curve2D outline.")
		return
	if int(scene.call("debug_path_node_count")) != 1:
		_fail("Expected one Path2D node for the authoritative SVG outline.")
		return
	if int(scene.call("debug_border_line_count")) != 1:
		_fail("Expected one Line2D generated from the SVG outline.")
		return
	if not bool(scene.call("debug_all_curves_closed")):
		_fail("Imported SVG outline must remain closed.")
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
		_fail("Curve tessellation did not produce a denser render cache.")
		return
	if int(scene.call("debug_triangle_count")) < 40:
		_fail("Single-outline interior triangulation produced too few triangles.")
		return
	var area_ratio := float(scene.call("debug_fill_area_ratio"))
	if area_ratio < 0.985 or area_ratio > 1.015:
		_fail("Perspective fill did not preserve the SVG interior area: %.5f." % area_ratio)
		return
	var display_size := scene.call("debug_curve_display_size") as Vector2
	if display_size.x < 300.0 or display_size.y < 430.0:
		_fail("Converted pear is too small for the dedicated preview: %s." % display_size)
		return

	var material := scene.call("debug_perspective_material") as ShaderMaterial
	var expected_shader := load(SHADER_PATH) as Shader
	if material == null or material.shader != expected_shader:
		_fail("Pear interior does not directly reuse anchored_star_window.gdshader.")
		return
	if bool(scene.call("debug_border_uses_shader")):
		_fail("Adjustable Line2D border must remain shader-free.")
		return
	if not is_equal_approx(float(scene.call("debug_border_width")), DEFAULT_BORDER_WIDTH):
		_fail("Pear border did not start at the documented adjustable width.")
		return
	var original_triangle_count := int(scene.call("debug_triangle_count"))
	scene.call("debug_set_border_width", 22.0)
	if not is_equal_approx(float(scene.call("debug_border_width")), 22.0):
		_fail("Runtime border-width control did not update Line2D.width.")
		return
	if int(scene.call("debug_triangle_count")) != original_triangle_count:
		_fail("Changing border width unexpectedly rebuilt or altered the interior fill.")
		return
	scene.call("debug_set_border_width", 200.0)
	if float(scene.call("debug_border_width")) > 30.001:
		_fail("Border-width control did not enforce its safe upper bound.")
		return
	scene.call("debug_set_border_width", DEFAULT_BORDER_WIDTH)

	var fill_samples := scene.call("debug_fill_screen_samples") as PackedVector2Array
	var border_samples := scene.call("debug_border_screen_samples") as PackedVector2Array
	if fill_samples.is_empty() or border_samples.size() < 16:
		_fail("Fill or border rendering diagnostics produced too few sample points.")
		return

	scene.call("debug_set_preview_time", 0.0)
	var start_position := scene.call("debug_curve_shape_position") as Vector2
	scene.call("debug_set_preview_time", 2.4)
	var moved_position := scene.call("debug_curve_shape_position") as Vector2
	if moved_position.distance_to(start_position) < 18.0:
		_fail("Curve pear did not move far enough to expose SCREEN_UV anchoring.")
		return

	print(
		"SVG outline pear diagnostics: subpaths=1 segments=%d anchors=%d tessellated=%d triangles=%d fill_area=%.5f border_width=%.1f"
		% [
			int(scene.call("debug_curve_segment_count")),
			int(scene.call("debug_curve_point_count")),
			int(scene.call("debug_tessellated_point_count")),
			int(scene.call("debug_triangle_count")),
			area_ratio,
			float(scene.call("debug_border_width")),
		]
	)
	print("SVG CURVE PEAR SMOKE PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
