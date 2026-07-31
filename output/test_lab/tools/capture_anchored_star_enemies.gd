extends SceneTree

const SCENE_PATH: String = "res://scenes/anchored_star_enemies_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/anchored_star_enemies_test.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.call("set_preview_time", 2.4)
	for _frame_index in range(10):
		await process_frame

	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("Failed to read root viewport texture.")
		quit(1)
		return
	var image := viewport_texture.get_image()
	if image == null:
		push_error("Failed to read root viewport image.")
		quit(1)
		return

	var screenshot_path := ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var error := image.save_png(screenshot_path)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		quit(error)
		return

	print("Saved screenshot: %s" % screenshot_path)
	quit(0)
