extends SceneTree

const SCENE_PATH := "res://scenes/neon_geometry_combat_test.tscn"
const SCREENSHOT_PATH := "res://screenshots/neon_geometry_combat_test.png"
const CAPTURE_OUTPUTS: Array[Dictionary] = [
	{"phase": 0, "path": "res://screenshots/neon_geometry_combat_test_round4_charge.png"},
	{"phase": 1, "path": "res://screenshots/neon_geometry_combat_test_round4_contact.png"},
	{"phase": 2, "path": "res://screenshots/neon_geometry_combat_test_round4_aftermath.png"},
]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	for capture: Dictionary in CAPTURE_OUTPUTS:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 760)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		root.add_child(viewport)
		var scene := packed_scene.instantiate()
		viewport.add_child(scene)
		for _index in range(6):
			await process_frame
		if not scene.has_method("debug_prepare_capture_phase"):
			push_error("Neon geometry scene is missing debug_prepare_capture_phase().")
			quit(1)
			return
		scene.call("debug_prepare_capture_phase", int(capture["phase"]))
		for _index in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := _viewport_image(viewport)
		if image == null:
			quit(1)
			return
		var output_path := String(capture["path"])
		if not _save_image(image, output_path):
			quit(1)
			return
		if int(capture["phase"]) == 1 and not _save_image(image, SCREENSHOT_PATH):
			quit(1)
			return
		viewport.queue_free()
		await process_frame
	quit(0)


func _viewport_image(viewport: SubViewport) -> Image:
	var viewport_texture := viewport.get_texture()
	if viewport_texture == null:
		push_error("Failed to read root viewport texture.")
		return null
	var image := viewport_texture.get_image()
	if image == null:
		push_error("Failed to read root viewport image.")
	return image


func _save_image(image: Image, resource_path: String) -> bool:
	var screenshot_path := ProjectSettings.globalize_path(resource_path)
	var error := image.save_png(screenshot_path)
	if error != OK:
		push_error("Failed to save screenshot: %s" % error)
		return false
	print("Saved screenshot: %s" % screenshot_path)
	return true
