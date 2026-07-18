extends SceneTree

const SCENE_PATH := "res://scenes/neon_geometry_combat_test.tscn"
const SCREENSHOT_PATH := "res://screenshots/neon_geometry_combat_test.png"


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

	if not scene.has_method("debug_prepare_capture"):
		push_error("Neon geometry scene is missing debug_prepare_capture().")
		quit(1)
		return
	scene.call("debug_prepare_capture")

	for _index in range(22):
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
