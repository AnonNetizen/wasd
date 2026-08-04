extends SceneTree

const SCENE_PATH: String = "res://scenes/svg_curve_pear_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/svg_curve_pear_test.png"


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
	scene.call("debug_set_curve_overlay", false)
	scene.call("debug_set_preview_time", 2.4)
	RenderingServer.force_draw(true)
	RenderingServer.force_sync()
	await process_frame

	var viewport_texture: ViewportTexture = root.get_texture()
	var image: Image = viewport_texture.get_image()
	var fill_sample_groups: Array = scene.call("debug_fill_screen_sample_groups")
	if fill_sample_groups.size() != 2:
		push_error("Expected separate leaf and pear-body fill sample groups.")
		quit(1)
		return
	var brightest_regions: Array[float] = []
	for fill_group_value: Variant in fill_sample_groups:
		var fill_group := fill_group_value as PackedVector2Array
		var brightest_region: float = _brightest_fill_sample(image, fill_group)
		if brightest_region < 0.35:
			push_error(
				"SVG enclosed interior %d did not render visible perspective content: %.4f"
				% [brightest_regions.size(), brightest_region]
			)
			quit(1)
			return
		brightest_regions.append(brightest_region)

	var absolute_path: String = ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var error: Error = image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		quit(error)
		return
	print(
		"Brightest enclosed-interior RGB sums (leaf/body): %.4f / %.4f"
		% [brightest_regions[0], brightest_regions[1]]
	)
	print("Saved screenshot: %s" % absolute_path)
	quit(0)


func _brightest_fill_sample(image: Image, fill_samples: PackedVector2Array) -> float:
	var brightest: float = 0.0
	var image_bounds := Rect2i(Vector2i.ZERO, image.get_size())
	for sample_position in fill_samples:
		var center := Vector2i(roundi(sample_position.x), roundi(sample_position.y))
		for offset_x in range(-2, 3):
			for offset_y in range(-2, 3):
				var pixel_position := center + Vector2i(offset_x, offset_y)
				if not image_bounds.has_point(pixel_position):
					continue
				var sample: Color = image.get_pixelv(pixel_position)
				brightest = maxf(brightest, sample.r + sample.g + sample.b)
	return brightest
