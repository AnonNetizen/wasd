extends SceneTree

const SCENE_PATH: String = "res://scenes/svg_cpu_mod_icon_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/svg_cpu_mod_icon_test.png"
const SAMPLE_IDS := ["large", "detail", "list"]


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
	scene.call("debug_set_large_controls_visible", false)
	scene.call("debug_set_preview_time", 2.4)
	RenderingServer.force_draw(true)
	RenderingServer.force_sync()
	await process_frame

	var viewport_texture: ViewportTexture = root.get_texture()
	var image: Image = viewport_texture.get_image()
	for sample_id: String in SAMPLE_IDS:
		var fill_samples := scene.call(
			"debug_sample_fill_screen_samples", sample_id
		) as PackedVector2Array
		var brightest_fill: float = _brightest_sample(image, fill_samples)
		var minimum_fill: float = 0.24 if sample_id == "list" else 0.35
		if brightest_fill < minimum_fill:
			push_error(
				"CPU %s sample did not render visible perspective content: %.4f"
				% [sample_id, brightest_fill]
			)
			quit(1)
			return
		var border_samples := scene.call(
			"debug_sample_border_screen_samples", sample_id
		) as PackedVector2Array
		var expected_border := scene.call(
			"debug_sample_border_color", sample_id
		) as Color
		var border_color_error: float = _closest_color_error(
			image,
			border_samples,
			expected_border
		)
		if border_color_error > 0.24:
			push_error(
				"CPU %s border did not render its cyan color: %.4f"
				% [sample_id, border_color_error]
			)
			quit(1)
			return
		print(
			"CPU %s probes: brightest_fill=%.4f border_error=%.4f"
			% [sample_id, brightest_fill, border_color_error]
		)

	var absolute_path: String = ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var error: Error = image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		quit(error)
		return
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
