extends SceneTree

const SCENE_PATH: String = "res://scenes/slime_room_shooter_3d.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/slime_room_shooter_3d.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for _frame in range(10):
		await process_frame

	scene.call("debug_set_player_position", Vector3(-1.2, 0.0, -1.4))
	var aim_target := Vector3(3.0, 0.0, 4.4)
	for _shot in range(5):
		scene.call("debug_fire_at_world", aim_target)
		for _frame in range(3):
			await physics_frame
			await process_frame

	for _frame in range(3):
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
