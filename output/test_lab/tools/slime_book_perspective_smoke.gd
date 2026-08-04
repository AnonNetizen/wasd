extends SceneTree

const SCENE_PATH: String = "res://scenes/slime_book_perspective_test.tscn"
const SHADER_PATH: String = "res://shaders/anchored_star_window.gdshader"


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var shader_source := FileAccess.get_file_as_string(SHADER_PATH)
	if not shader_source.contains("vec2 screen_point = (SCREEN_UV - 0.5)"):
		_fail("Book content is not anchored to the reused SCREEN_UV shader.")
		return

	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load slime book perspective scene.")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	if int(scene.call("debug_control_point_count")) != 20:
		_fail("Expected one 20-point closed soft-body book outline.")
		return
	if int(scene.call("debug_spine_point_count")) != 5:
		_fail("Expected five stable book-spine feature points.")
		return
	if int(scene.call("debug_page_guide_count")) != 2:
		_fail("Expected one lower page-edge guide per page.")
		return
	if float(scene.call("debug_top_spine_notch_depth")) < 18.0:
		_fail("The top spine notch is too shallow to read as an open book.")
		return
	if float(scene.call("debug_bottom_spine_projection")) < 24.0:
		_fail("The bottom spine projection is too shallow to preserve book identity.")
		return
	if float(scene.call("debug_page_symmetry_error")) > 0.1:
		_fail("The resting left/right pages are not mirror-symmetric.")
		return
	var book_size := scene.call("debug_book_size") as Vector2
	var aspect_ratio: float = book_size.x / maxf(book_size.y, 0.001)
	if aspect_ratio < 1.20 or aspect_ratio > 1.55:
		_fail("Book silhouette aspect ratio escaped the readable range: %.3f." % aspect_ratio)
		return
	if int(scene.call("debug_fill_point_count")) != 100:
		_fail("Expected the 20 book corners to produce a 100-point rounded Shader mask.")
		return
	if not bool(scene.call("debug_fill_matches_boundary")):
		_fail("Perspective fill is not synchronized with the live book boundary.")
		return

	var material := scene.call("debug_perspective_material") as ShaderMaterial
	var expected_shader := load(SHADER_PATH) as Shader
	if material == null or material.shader != expected_shader:
		_fail("The book does not directly reuse anchored_star_window.gdshader.")
		return

	scene.call("debug_set_auto_pulse", false)
	scene.call("debug_set_preview_time", 0.0)
	var start_position := scene.call("debug_cross_position") as Vector2
	scene.call("debug_set_preview_time", 2.4)
	var moved_position := scene.call("debug_cross_position") as Vector2
	if moved_position.distance_to(start_position) < 18.0:
		_fail("The book did not move far enough to demonstrate fixed-space sampling.")
		return

	var baseline_deformation := float(scene.call("debug_deformation_amount"))
	scene.call("debug_poke", Vector2(-184.0, -34.0), 1.08)
	for _frame_index in range(10):
		await physics_frame
		await process_frame
	if float(scene.call("debug_deformation_amount")) <= baseline_deformation + 0.5:
		_fail("The reused soft-body solver did not deform the left page.")
		return
	if not bool(scene.call("debug_fill_matches_boundary")):
		_fail("Perspective fill stopped following the deformed book boundary.")
		return
	var area_ratio := float(scene.call("debug_area_ratio"))
	if area_ratio < 0.72 or area_ratio > 1.28:
		_fail("Book area preservation escaped the source solver bounds: %.3f." % area_ratio)
		return

	print("SLIME BOOK PERSPECTIVE SMOKE PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
