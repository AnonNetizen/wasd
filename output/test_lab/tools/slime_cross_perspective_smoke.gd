extends SceneTree

const SCENE_PATH: String = "res://scenes/slime_cross_perspective_test.tscn"
const SHADER_PATH: String = "res://shaders/anchored_star_window.gdshader"


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var shader_source := FileAccess.get_file_as_string(SHADER_PATH)
	if shader_source.is_empty():
		_fail("Failed to read the reused perspective shader.")
		return
	if not shader_source.contains("vec2 screen_point = (SCREEN_UV - 0.5)"):
		_fail("Perspective content is not anchored to SCREEN_UV.")
		return
	if shader_source.contains("MODEL_MATRIX") or shader_source.contains("CANVAS_MATRIX"):
		_fail("Perspective shader unexpectedly depends on CanvasItem transforms.")
		return

	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load slime cross perspective scene.")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	if int(scene.call("debug_control_point_count")) != 20:
		_fail("The original 20-point slime cross outline was not preserved.")
		return
	if int(scene.call("debug_concave_corner_count")) != 4:
		_fail("The original four concave cross corners were not preserved.")
		return
	var arm_span := float(scene.call("debug_arm_span"))
	var stem_width := float(scene.call("debug_stem_width"))
	if arm_span / maxf(stem_width, 0.001) < 3.0:
		_fail("The cross arm/stem proportion no longer matches the source construction.")
		return
	if int(scene.call("debug_fill_point_count")) != 100:
		_fail("Expected the 20 corners to produce 100 rounded perspective-fill points.")
		return
	if not bool(scene.call("debug_fill_matches_boundary")):
		_fail("Perspective fill is not synchronized with the live rounded boundary.")
		return

	var material := scene.call("debug_perspective_material") as ShaderMaterial
	if material == null or material.shader == null:
		_fail("Perspective ShaderMaterial is missing.")
		return
	var expected_shader := load(SHADER_PATH) as Shader
	if material.shader != expected_shader:
		_fail("The new experiment does not reuse the anchored-star shader resource.")
		return
	if float(material.get_shader_parameter("viewport_aspect")) <= 0.01:
		_fail("Viewport aspect was not propagated to the perspective shader.")
		return

	scene.call("debug_set_auto_pulse", false)
	scene.call("debug_set_preview_time", 0.0)
	var start_position := scene.call("debug_cross_position") as Vector2
	scene.call("debug_set_preview_time", 2.4)
	var moved_position := scene.call("debug_cross_position") as Vector2
	if moved_position.distance_to(start_position) < 20.0:
		_fail("The cross did not move far enough to demonstrate screen-space sampling.")
		return

	var baseline_deformation := float(scene.call("debug_deformation_amount"))
	scene.call("debug_poke", Vector2(-120.0, -103.0), 1.1)
	for _frame_index in range(10):
		await physics_frame
		await process_frame
	var deformed_amount := float(scene.call("debug_deformation_amount"))
	if deformed_amount <= baseline_deformation + 0.5:
		_fail("The reused slime cross solver did not react to a local poke.")
		return
	if not bool(scene.call("debug_fill_matches_boundary")):
		_fail("Perspective fill stopped following the deformed cross boundary.")
		return
	var area_ratio := float(scene.call("debug_area_ratio"))
	if area_ratio < 0.72 or area_ratio > 1.28:
		_fail("Area preservation escaped the source cross bounds: %.3f." % area_ratio)
		return

	print("SLIME CROSS PERSPECTIVE SMOKE PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
