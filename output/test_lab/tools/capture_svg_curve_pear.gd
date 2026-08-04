extends SceneTree

const SCENE_PATH: String = "res://scenes/svg_curve_pear_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/svg_curve_pear_test.png"
const DEFAULT_BORDER_WIDTH: float = 12.0


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
	scene.call("debug_set_border_width", DEFAULT_BORDER_WIDTH)
	scene.call("debug_set_preview_time", 2.4)
	RenderingServer.force_draw(true)
	RenderingServer.force_sync()
	await process_frame

	var viewport_texture: ViewportTexture = root.get_texture()
	var image: Image = viewport_texture.get_image()
	var fill_samples := scene.call("debug_fill_screen_samples") as PackedVector2Array
	var brightest_fill: float = _brightest_sample(image, fill_samples)
	if brightest_fill < 0.35:
		push_error("SVG outline interior did not render visible perspective content: %.4f" % brightest_fill)
		quit(1)
		return
	var border_samples := scene.call("debug_border_screen_samples") as PackedVector2Array
	var expected_border := scene.call("debug_border_color") as Color
	var border_color_error: float = _closest_color_error(
		image,
		border_samples,
		expected_border
	)
	if border_color_error > 0.18:
		push_error("Adjustable Line2D border did not render its configured color: %.4f" % border_color_error)
		quit(1)
		return

	var absolute_path: String = ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var error: Error = image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		quit(error)
		return
	print("Brightest outline-interior RGB sum: %.4f" % brightest_fill)
	print("Closest adjustable-border RGB error: %.4f" % border_color_error)
	print("Saved screenshot: %s" % absolute_path)
	quit(0)


func _brightest_sample(image: Image, sample_points: PackedVector2Array) -> float:
	var brightest: float = 0.0
	var image_bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for sample_position in sample_points:
		var center := Vector2i(roundi(sample_position.x), roundi(sample_position.y))
		for offset_x in range(-2, 3):
			for offset_y in range(-2, 3):
				var pixel_position := center + Vector2i(offset_x, offset_y)
				if not image_bounds.has_point(pixel_position):
					continue
				var sample: Color = image.get_pixelv(pixel_position)
				brightest = maxf(brightest, sample.r + sample.g + sample.b)
	return brightest


func _closest_color_error(
	image: Image,
	sample_points: PackedVector2Array,
	expected_color: Color
) -> float:
	var closest_error: float = INF
	var image_bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for sample_position in sample_points:
		var center := Vector2i(roundi(sample_position.x), roundi(sample_position.y))
		for offset_x in range(-2, 3):
			for offset_y in range(-2, 3):
				var pixel_position := center + Vector2i(offset_x, offset_y)
				if not image_bounds.has_point(pixel_position):
					continue
				var sample: Color = image.get_pixelv(pixel_position)
				var color_error: float = (
					absf(sample.r - expected_color.r)
					+ absf(sample.g - expected_color.g)
					+ absf(sample.b - expected_color.b)
				)
				closest_error = minf(closest_error, color_error)
	return closest_error
