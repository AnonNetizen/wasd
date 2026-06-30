extends SceneTree

const SCENE_PATH := "res://scenes/advanced_cell_test.tscn"
const SCREENSHOT_PATH := "res://screenshots/advanced_cell_test.png"


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

	# 等初始化后触发"分裂"，停在收腰峰值做封面（更能体现可控复杂动画）
	for _warmup in range(4):
		await process_frame
	var cell := scene.get_node_or_null("AdvancedCell")
	if cell != null:
		cell.call("trigger_divide")
	for _index in range(96):
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
