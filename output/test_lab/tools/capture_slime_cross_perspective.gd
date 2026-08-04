extends SceneTree

const SCENE_PATH: String = "res://scenes/slime_cross_perspective_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/slime_cross_perspective_test.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.call("debug_set_auto_pulse", false)
	scene.call("debug_set_fixed_step_mode", true)
	scene.call("debug_reset")
	scene.call("debug_set_preview_time", 2.4)
	for _frame_index in range(8):
		scene.call("debug_advance_fixed_step", 1.0 / 60.0)
	scene.call("debug_poke", Vector2(-120.0, -103.0), 1.12)
	for _frame_index in range(8):
		scene.call("debug_advance_fixed_step", 1.0 / 60.0)
	RenderingServer.force_draw(true)
	RenderingServer.force_sync()
	await process_frame

	var viewport_texture: ViewportTexture = root.get_texture()
	var image: Image = viewport_texture.get_image()
	var cross_position := scene.call("debug_cross_position") as Vector2
	var brightest_interior: float = _brightest_cross_interior(image, cross_position)
	if brightest_interior < 0.25:
		push_error(
			"Perspective cross interior did not render visible star content: %.4f"
			% brightest_interior
		)
		quit(1)
		return
	var absolute_path: String = ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var error: Error = image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		quit(error)
		return

	print("Brightest perspective-cross interior RGB sum: %.4f" % brightest_interior)
	print("Saved screenshot: %s" % absolute_path)
	quit(0)


func _brightest_cross_interior(image: Image, cross_position: Vector2) -> float:
	var brightest: float = 0.0
	for local_x in range(-96, 97, 3):
		for local_y in range(-124, -75, 3):
			var pixel_position := Vector2i(
				roundi(cross_position.x + float(local_x)),
				roundi(cross_position.y + float(local_y))
			)
			if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel_position):
				continue
			var sample: Color = image.get_pixelv(pixel_position)
			brightest = maxf(brightest, sample.r + sample.g + sample.b)
	return brightest
