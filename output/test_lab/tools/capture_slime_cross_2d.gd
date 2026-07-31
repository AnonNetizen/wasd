extends SceneTree

const SCENE_PATH: String = "res://scenes/slime_cross_2d_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/slime_cross_2d_test.png"


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
	scene.call("debug_set_auto_pulse", false)
	for _frame in range(42):
		await physics_frame
		await process_frame

	scene.call("debug_poke", Vector2(-120.0, -102.0), 1.18)
	for _frame in range(8):
		await physics_frame
		await process_frame
	RenderingServer.force_draw(true)
	RenderingServer.force_sync()
	await process_frame

	var viewport_texture: ViewportTexture = root.get_texture()
	var image: Image = viewport_texture.get_image()
	var absolute_path: String = ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var error: Error = image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		quit(error)
		return

	print("Saved screenshot: %s" % absolute_path)
	quit(0)
