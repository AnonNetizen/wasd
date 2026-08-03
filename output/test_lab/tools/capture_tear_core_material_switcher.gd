extends SceneTree

const SCENE_PATH: String = "res://scenes/tear_core_material_switcher_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/tear_core_material_switcher.png"
const CAPTURE_TIME: float = 2.16


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
	scene.call("debug_apply_material_style", 1)
	scene.call("debug_set_preview_time", CAPTURE_TIME)
	await process_frame
	RenderingServer.force_draw(true)
	RenderingServer.force_sync()
	await process_frame

	var image: Image = root.get_texture().get_image()
	if image.get_size() != Vector2i(1280, 760):
		push_error("Unexpected capture size: %s" % image.get_size())
		quit(1)
		return
	var absolute_path: String = ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var error: Error = image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		quit(error)
		return

	print("Saved screenshot: %s" % absolute_path)
	quit(0)
