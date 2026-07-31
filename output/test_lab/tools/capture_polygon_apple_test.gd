extends SceneTree

const COMPARISON_SCREENSHOT: String = (
	"res://screenshots/polygon_apple_comparison.png"
)
const EFFECTS_SCREENSHOT: String = (
	"res://screenshots/polygon_apple_generic_effects_strip.png"
)
const RUNTIME_PANEL_RECT := Rect2i(554, 120, 698, 492)
const SCENE_PATH: String = "res://scenes/polygon_apple_test.tscn"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load Polygon apple scene.")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	for _frame_index in range(4):
		await process_frame
	scene.call("prepare_capture", 1.0, 0.0, 0.0, 0.0)
	for _frame_index in range(2):
		await process_frame
	if not _save_viewport(COMPARISON_SCREENSHOT):
		return
	if not await _save_effects_strip(scene):
		return
	print(
		"Saved Polygon apple screenshots: %s and %s"
		% [
			ProjectSettings.globalize_path(COMPARISON_SCREENSHOT),
			ProjectSettings.globalize_path(EFFECTS_SCREENSHOT),
		]
	)
	quit(0)


func _save_effects_strip(scene: Node) -> bool:
	var states: Array[Array] = [
		[0.20, 0.0, 0.0, 0.0],
		[1.0, 0.0, 0.15, 0.65],
		[1.0, 0.0, 0.65, 0.65],
		[1.0, 0.45, 0.0, 0.0],
		[1.0, 1.0, 0.0, 0.0],
	]
	var frame_size := Vector2i(300, 212)
	var strip := Image.create(
		frame_size.x * states.size(),
		frame_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	strip.fill(Color("#10101a"))
	for frame_index in range(states.size()):
		var state: Array = states[frame_index]
		scene.call(
			"prepare_capture",
			float(state[0]),
			float(state[1]),
			float(state[2]),
			float(state[3])
		)
		for _frame_index in range(2):
			await process_frame
		var viewport_image := _get_viewport_image()
		if viewport_image == null:
			return false
		var frame := viewport_image.get_region(RUNTIME_PANEL_RECT)
		frame.resize(
			frame_size.x,
			frame_size.y,
			Image.INTERPOLATE_LANCZOS
		)
		strip.blit_rect(
			frame,
			Rect2i(Vector2i.ZERO, frame_size),
			Vector2i(frame_index * frame_size.x, 0)
		)
	var save_error := strip.save_png(
		ProjectSettings.globalize_path(EFFECTS_SCREENSHOT)
	)
	if save_error != OK:
		_fail(
			"Failed to save apple effects strip: %s"
			% error_string(save_error)
		)
		return false
	return true


func _save_viewport(path: String) -> bool:
	var image := _get_viewport_image()
	if image == null:
		return false
	var save_error := image.save_png(ProjectSettings.globalize_path(path))
	if save_error != OK:
		_fail(
			"Failed to save Polygon apple screenshot: %s"
			% error_string(save_error)
		)
		return false
	return true


func _get_viewport_image() -> Image:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("Viewport capture returned an empty image.")
		return null
	return image


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
