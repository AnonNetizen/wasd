extends SceneTree

const COMPARISON_SCREENSHOT: String = "res://screenshots/polygon_book_comparison.png"
const GENERIC_EFFECTS_SCREENSHOT: String = (
	"res://screenshots/polygon_book_generic_effects_strip.png"
)
const MID_TURN_SCREENSHOT: String = "res://screenshots/polygon_book_page_turn_mid.png"
const MOTION_STRIP_SCREENSHOT: String = "res://screenshots/polygon_book_page_turn_strip.png"
const RUNTIME_PANEL_RECT := Rect2i(554, 120, 698, 492)
const SCENE_PATH: String = "res://scenes/polygon_book_test.tscn"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load scene: %s" % SCENE_PATH)
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame_index in range(8):
		await process_frame

	if not scene.has_method("prepare_capture"):
		_fail("Polygon book scene does not expose prepare_capture().")
		return
	scene.call("prepare_capture", 0.0, 0.0)
	for _frame_index in range(3):
		await process_frame
	if not _save_viewport(COMPARISON_SCREENSHOT):
		return

	scene.call("prepare_capture", 0.5, 0.0)
	for _frame_index in range(3):
		await process_frame
	if not _save_viewport(MID_TURN_SCREENSHOT):
		return
	if not await _save_generic_effects_strip(scene):
		return
	if not await _save_motion_strip(scene):
		return
	print(
		"Saved Polygon book screenshots: %s, %s, %s, and %s"
		% [
			ProjectSettings.globalize_path(COMPARISON_SCREENSHOT),
			ProjectSettings.globalize_path(MID_TURN_SCREENSHOT),
			ProjectSettings.globalize_path(GENERIC_EFFECTS_SCREENSHOT),
			ProjectSettings.globalize_path(MOTION_STRIP_SCREENSHOT),
		]
	)
	quit(0)


func _save_generic_effects_strip(scene: Node) -> bool:
	if not scene.has_method("prepare_generic_capture"):
		_fail("Polygon book scene does not expose prepare_generic_capture().")
		return false
	var states: Array[Array] = [
		[0.25, 0.0],
		[0.60, 0.0],
		[1.0, 0.0],
		[1.0, 0.45],
		[1.0, 0.85],
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
			"prepare_generic_capture",
			float(state[0]),
			float(state[1])
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
	var absolute_path := ProjectSettings.globalize_path(
		GENERIC_EFFECTS_SCREENSHOT
	)
	var save_error := strip.save_png(absolute_path)
	if save_error != OK:
		_fail(
			"Failed to save generic effects strip: %s"
			% error_string(save_error)
		)
		return false
	return true


func _save_motion_strip(scene: Node) -> bool:
	var progress_values: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
	var frame_size := Vector2i(300, 212)
	var strip := Image.create(
		frame_size.x * progress_values.size(),
		frame_size.y,
		false,
		Image.FORMAT_RGBA8
	)
	strip.fill(Color("#10101a"))
	for frame_index in range(progress_values.size()):
		scene.call("prepare_capture", progress_values[frame_index], 0.0)
		for _frame_index in range(2):
			await process_frame
		var viewport_image := _get_viewport_image()
		if viewport_image == null:
			return false
		var frame := viewport_image.get_region(RUNTIME_PANEL_RECT)
		frame.resize(frame_size.x, frame_size.y, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(
			frame,
			Rect2i(Vector2i.ZERO, frame_size),
			Vector2i(frame_index * frame_size.x, 0)
		)
	var absolute_path := ProjectSettings.globalize_path(MOTION_STRIP_SCREENSHOT)
	var save_error := strip.save_png(absolute_path)
	if save_error != OK:
		_fail("Failed to save motion strip: %s" % error_string(save_error))
		return false
	return true


func _save_viewport(path: String) -> bool:
	var image := _get_viewport_image()
	if image == null:
		return false
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		_fail("Failed to create screenshot directory: %s" % error_string(directory_error))
		return false
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		_fail("Failed to save screenshot: %s" % error_string(save_error))
		return false
	return true


func _get_viewport_image() -> Image:
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		_fail("Failed to read root viewport texture.")
		return null
	var image := viewport_texture.get_image()
	if image == null:
		_fail("Failed to read root viewport image.")
	return image


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
