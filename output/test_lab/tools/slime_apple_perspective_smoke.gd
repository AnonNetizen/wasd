extends SceneTree

const APPLE_SCRIPT_PATH: String = "res://scripts/slime_apple_perspective.gd"
const SCENE_PATH: String = "res://scenes/slime_apple_perspective_test.tscn"
const SHADER_PATH: String = "res://shaders/anchored_star_window.gdshader"


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var shader_source := FileAccess.get_file_as_string(SHADER_PATH)
	if not shader_source.contains("vec2 screen_point = (SCREEN_UV - 0.5)"):
		_fail("Apple content is not anchored to the reused SCREEN_UV shader.")
		return
	var apple_source := FileAccess.get_file_as_string(APPLE_SCRIPT_PATH)
	if (
		apple_source.contains("_draw_debug_rig")
		or apple_source.contains("_draw_impact_ripple")
		or apple_source.contains("draw_line(")
	):
		_fail("The apple renderer added internal, impact-ripple or debug line drawing.")
		return
	if apple_source.count("draw_polyline(") != 4:
		_fail("The apple renderer must contain only the four inherited-style outer rim layers.")
		return

	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load slime apple perspective scene.")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	if int(scene.call("debug_control_point_count")) != 20:
		_fail("Expected one 20-point closed soft-body apple outline.")
		return
	if int(scene.call("debug_internal_feature_line_count")) != 0:
		_fail("The apple must not report internal feature lines.")
		return
	if bool(scene.call("debug_draws_debug_rig")):
		_fail("The apple appearance must not draw the inherited debug rig.")
		return
	var apple_size := scene.call("debug_apple_size") as Vector2
	var total_aspect: float = apple_size.x / maxf(apple_size.y, 0.001)
	if total_aspect < 0.78 or total_aspect > 0.98:
		_fail("Apple silhouette aspect escaped the readable range: %.3f." % total_aspect)
		return
	var body_size := scene.call("debug_apple_body_size") as Vector2
	var body_aspect: float = body_size.x / maxf(body_size.y, 0.001)
	if body_aspect < 0.88 or body_aspect > 1.08:
		_fail("Apple body is no longer broadly round: %.3f." % body_aspect)
		return
	if float(scene.call("debug_stem_height")) < 48.0:
		_fail("The integrated stem is too short to identify the apple.")
		return
	if float(scene.call("debug_leaf_reach")) < 90.0:
		_fail("The integrated leaf does not project far enough from the stem.")
		return
	if float(scene.call("debug_top_notch_depth")) < 5.0:
		_fail("The top shoulder notch is too shallow to separate the stem from the fruit.")
		return
	if float(scene.call("debug_bottom_rounding_depth")) < 12.0:
		_fail("The apple bottom lost its rounded central low point.")
		return
	if int(scene.call("debug_fill_point_count")) != 100:
		_fail("Expected the 20 apple corners to produce a 100-point rounded Shader mask.")
		return
	if not bool(scene.call("debug_fill_matches_boundary")):
		_fail("Perspective fill is not synchronized with the live apple boundary.")
		return

	var material := scene.call("debug_perspective_material") as ShaderMaterial
	var expected_shader := load(SHADER_PATH) as Shader
	if material == null or material.shader != expected_shader:
		_fail("The apple does not directly reuse anchored_star_window.gdshader.")
		return

	scene.call("debug_set_auto_pulse", false)
	scene.call("debug_set_preview_time", 0.0)
	var start_position := scene.call("debug_cross_position") as Vector2
	scene.call("debug_set_preview_time", 2.4)
	var moved_position := scene.call("debug_cross_position") as Vector2
	if moved_position.distance_to(start_position) < 18.0:
		_fail("The apple did not move far enough to demonstrate fixed-space sampling.")
		return

	var baseline_deformation := float(scene.call("debug_deformation_amount"))
	scene.call("debug_poke", Vector2(138.0, -6.0), 1.06)
	for _frame_index in range(10):
		await physics_frame
		await process_frame
	if float(scene.call("debug_deformation_amount")) <= baseline_deformation + 0.5:
		_fail("The reused soft-body solver did not deform the apple cheek.")
		return
	if not bool(scene.call("debug_fill_matches_boundary")):
		_fail("Perspective fill stopped following the deformed apple boundary.")
		return
	var area_ratio := float(scene.call("debug_area_ratio"))
	if area_ratio < 0.72 or area_ratio > 1.28:
		_fail("Apple area preservation escaped the source solver bounds: %.3f." % area_ratio)
		return

	print("SLIME APPLE PERSPECTIVE SMOKE PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
