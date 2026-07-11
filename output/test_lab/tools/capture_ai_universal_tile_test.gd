extends SceneTree

const SCENE_PATH: String = "res://scenes/ai_universal_tile_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/ai_universal_tile_test.png"


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
	for _frame_index in range(12):
		await process_frame

	var grid := scene.get_node_or_null("UniversalTileGrid") as Node2D
	if grid != null:
		var cabinet_cell_center := grid.to_global(Vector2(5.5 * 128.0, 2.5 * 128.0))
		Input.warp_mouse(cabinet_cell_center)
	for _frame_index in range(6):
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
	var screenshot_directory := screenshot_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(screenshot_directory)
	if directory_error != OK:
		push_error("Failed to create screenshot directory: %s" % error_string(directory_error))
		quit(directory_error)
		return
	var save_error := image.save_png(screenshot_path)
	if save_error != OK:
		push_error("Failed to save screenshot: %s" % error_string(save_error))
		quit(save_error)
		return

	print("Saved screenshot: %s" % screenshot_path)
	quit(0)
