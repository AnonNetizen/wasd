extends SceneTree

const COMPARISON_SCREENSHOT: String = "res://screenshots/polygon_book_comparison.png"
const MID_TURN_SCREENSHOT: String = "res://screenshots/polygon_book_page_turn_mid.png"
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
	print(
		"Saved Polygon book screenshots: %s and %s"
		% [
			ProjectSettings.globalize_path(COMPARISON_SCREENSHOT),
			ProjectSettings.globalize_path(MID_TURN_SCREENSHOT),
		]
	)
	quit(0)


func _save_viewport(path: String) -> bool:
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		_fail("Failed to read root viewport texture.")
		return false
	var image := viewport_texture.get_image()
	if image == null:
		_fail("Failed to read root viewport image.")
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


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
