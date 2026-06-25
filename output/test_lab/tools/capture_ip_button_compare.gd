extends SceneTree

const SCENE_PATH := "res://scenes/ip_button_compare.tscn"
const SCREENSHOT_PATH := "E:/GameProjects/wasd/wasd/output/test_lab/screenshots/ip_button_compare.png"


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

	for _index in range(12):
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

	var error := image.save_png(SCREENSHOT_PATH)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		quit(error)
		return

	print("Saved screenshot: %s" % SCREENSHOT_PATH)
	quit(0)
