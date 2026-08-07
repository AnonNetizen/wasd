extends SceneTree

const SCENE_PATH: String = "res://scenes/svg_cpu_mod_icon_test.tscn"
const SHADER_PATH: String = "res://shaders/anchored_star_window.gdshader"
const SHAPE_SCRIPT_PATH: String = "res://scripts/svg_curve_outline_shape.gd"
const TEST_SCRIPT_PATH: String = "res://scripts/svg_cpu_mod_icon_test.gd"
const SVG_SOURCE_PATH: String = "res://assets/svg_curve/cpu_mod_source.svg"
const LARGE_ID: String = "large"
const DETAIL_ID: String = "detail"
const LIST_ID: String = "list"
const EXPECTED_SIZES := {
	LARGE_ID: 360.0,
	DETAIL_ID: 112.0,
	LIST_ID: 40.0,
}
const EXPECTED_BORDER_WIDTHS := {
	LARGE_ID: 10.0,
	DETAIL_ID: 4.0,
	LIST_ID: 2.0,
}
const EXPECTED_STAR_SCALES := {
	LARGE_ID: 0.90,
	DETAIL_ID: 1.25,
	LIST_ID: 1.80,
}


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var source_svg := FileAccess.get_file_as_string(SVG_SOURCE_PATH)
	if source_svg.contains("<metadata") or source_svg.contains("rdf:"):
		_fail("Sanitized CPU SVG still contains RDF metadata.")
		return
	if not source_svg.contains(
		"translate(0.000000,800.000000) scale(0.100000,-0.100000)"
	):
		_fail("CPU SVG lost its authored coordinate transform.")
		return
	if source_svg.count("<path") != 1 or not source_svg.contains("M3060 6142"):
		_fail("CPU SVG must contain exactly one authored closed silhouette path.")
		return

	var shape_source := FileAccess.get_file_as_string(SHAPE_SCRIPT_PATH)
	if not shape_source.contains(
		"func configure(source_path: String, border_color: Color, star_scale: float)"
	):
		_fail("Shared SVG outline shape is missing its pre-tree configuration API.")
		return
	if not shape_source.contains("DEFAULT_SVG_SOURCE_PATH"):
		_fail("Shared SVG outline shape no longer preserves the pear default source.")
		return
	var test_source := FileAccess.get_file_as_string(TEST_SCRIPT_PATH)
	for forbidden_term in ["_physics_process", "spring", "area_pressure", "SoftBody"]:
		if test_source.contains(forbidden_term):
			_fail("CPU Mod icon experiment contains an unwanted dependency: %s." % forbidden_term)
			return

	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load SVG CPU Mod icon scene.")
		return
	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var sample_ids: PackedStringArray = scene.call("debug_sample_ids")
	if sample_ids != PackedStringArray([LARGE_ID, DETAIL_ID, LIST_ID]):
		_fail("CPU Mod icon scene must expose large/detail/list samples in order.")
		return
	var expected_shader := load(SHADER_PATH) as Shader
	var common_segment_count: int = -1
	var common_point_count: int = -1
	for sample_id: String in sample_ids:
		if int(scene.call("debug_sample_subpath_count", sample_id)) != 1:
			_fail("CPU sample must produce exactly one Curve2D: %s." % sample_id)
			return
		if int(scene.call("debug_sample_path_node_count", sample_id)) != 1:
			_fail("CPU sample must contain one Path2D: %s." % sample_id)
			return
		if int(scene.call("debug_sample_border_line_count", sample_id)) != 1:
			_fail("CPU sample must contain one Line2D border: %s." % sample_id)
			return
		if int(scene.call("debug_sample_controls_overlay_count", sample_id)) != 1:
			_fail("CPU sample must retain one optional controls overlay: %s." % sample_id)
			return
		if bool(scene.call("debug_sample_controls_visible", sample_id)):
			_fail("CPU sample controls must default hidden: %s." % sample_id)
			return
		if not bool(scene.call("debug_sample_all_curves_closed", sample_id)):
			_fail("CPU sample curve must remain closed: %s." % sample_id)
			return

		var segment_count := int(scene.call("debug_sample_curve_segment_count", sample_id))
		var point_count := int(scene.call("debug_sample_curve_point_count", sample_id))
		if segment_count < 40 or point_count < 40:
			_fail("Too few CPU silhouette segments survived parsing: %s." % sample_id)
			return
		if common_segment_count < 0:
			common_segment_count = segment_count
			common_point_count = point_count
		elif segment_count != common_segment_count or point_count != common_point_count:
			_fail("CPU sample topology differs across display sizes.")
			return
		if int(scene.call("debug_sample_triangle_count", sample_id)) < 60:
			_fail("CPU silhouette triangulation produced too few triangles: %s." % sample_id)
			return
		var area_ratio := float(scene.call("debug_sample_fill_area_ratio", sample_id))
		if area_ratio < 0.985 or area_ratio > 1.015:
			_fail("CPU perspective fill area mismatch for %s: %.5f." % [sample_id, area_ratio])
			return

		var screen_size := scene.call("debug_sample_screen_size", sample_id) as Vector2
		var max_dimension: float = maxf(screen_size.x, screen_size.y)
		if absf(max_dimension - float(EXPECTED_SIZES[sample_id])) > 0.75:
			_fail("CPU sample has the wrong screen size: %s = %s." % [sample_id, screen_size])
			return
		var border_width := float(scene.call("debug_sample_border_width", sample_id))
		if not is_equal_approx(border_width, float(EXPECTED_BORDER_WIDTHS[sample_id])):
			_fail("CPU sample has the wrong screen border width: %s = %.3f." % [sample_id, border_width])
			return
		var star_scale := float(scene.call("debug_sample_star_scale", sample_id))
		if not is_equal_approx(star_scale, float(EXPECTED_STAR_SCALES[sample_id])):
			_fail("CPU sample has the wrong star scale: %s = %.3f." % [sample_id, star_scale])
			return

		var material := scene.call("debug_sample_perspective_material", sample_id) as ShaderMaterial
		if material == null or material.shader != expected_shader:
			_fail("CPU sample does not reuse anchored_star_window.gdshader: %s." % sample_id)
			return
		if bool(scene.call("debug_sample_border_uses_shader", sample_id)):
			_fail("CPU sample Line2D border must remain shader-free: %s." % sample_id)
			return
		var border_color := scene.call("debug_sample_border_color", sample_id) as Color
		if border_color.to_html(false) != "68bcdd":
			_fail("CPU sample does not use the project cyan border: %s." % sample_id)
			return

		var fill_samples := scene.call(
			"debug_sample_fill_screen_samples", sample_id
		) as PackedVector2Array
		var border_samples := scene.call(
			"debug_sample_border_screen_samples", sample_id
		) as PackedVector2Array
		if fill_samples.is_empty() or border_samples.size() < 16:
			_fail("CPU sample produced too few render probes: %s." % sample_id)
			return

	var descendant_count := int(scene.call("debug_descendant_count"))
	scene.call("debug_set_large_controls_visible", true)
	if not bool(scene.call("debug_sample_controls_visible", LARGE_ID)):
		_fail("Large CPU sample controls did not become visible.")
		return
	if (
		bool(scene.call("debug_sample_controls_visible", DETAIL_ID))
		or bool(scene.call("debug_sample_controls_visible", LIST_ID))
	):
		_fail("Large-sample controls toggle leaked into actual-size samples.")
		return
	scene.call("debug_set_large_controls_visible", false)
	if int(scene.call("debug_descendant_count")) != descendant_count:
		_fail("CPU controls toggle changed the scene node count.")
		return

	scene.call("debug_set_preview_time", 0.0)
	var large_start := scene.call("debug_sample_position", LARGE_ID) as Vector2
	var detail_start := scene.call("debug_sample_position", DETAIL_ID) as Vector2
	var list_start := scene.call("debug_sample_position", LIST_ID) as Vector2
	scene.call("debug_set_preview_time", 2.4)
	var large_moved := scene.call("debug_sample_position", LARGE_ID) as Vector2
	var detail_moved := scene.call("debug_sample_position", DETAIL_ID) as Vector2
	var list_moved := scene.call("debug_sample_position", LIST_ID) as Vector2
	if large_moved.distance_to(large_start) < 12.0:
		_fail("Large CPU sample did not move far enough to expose SCREEN_UV anchoring.")
		return
	if not detail_moved.is_equal_approx(detail_start) or not list_moved.is_equal_approx(list_start):
		_fail("Actual-size CPU samples must remain stationary.")
		return

	scene.call("debug_reset")
	if bool(scene.call("debug_motion_paused")):
		_fail("CPU experiment reset did not restore animation playback.")
		return
	if bool(scene.call("debug_sample_controls_visible", LARGE_ID)):
		_fail("CPU experiment reset did not hide the diagnostic controls.")
		return
	if int(scene.call("debug_descendant_count")) != descendant_count:
		_fail("CPU experiment reset changed the scene node count.")
		return

	print(
		"SVG CPU Mod icon diagnostics: samples=3 segments=%d points=%d triangles=%d sizes=360/112/40 borders=10/4/2"
		% [
			common_segment_count,
			common_point_count,
			int(scene.call("debug_sample_triangle_count", LARGE_ID)),
		]
	)
	print("SVG CPU MOD ICON ALL PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
