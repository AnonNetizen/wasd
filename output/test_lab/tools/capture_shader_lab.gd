extends SceneTree

const SCENE_PATH := "res://scenes/shader_lab.tscn"
const CAPTURES: Array[Dictionary] = [
	{
		"shader_id": "rotating_starfield",
		"preset_id": "showcase",
		"time": 8.0,
		"path": "res://screenshots/shader_lab_starfield_showcase.png",
	},
	{
		"shader_id": "rotating_starfield",
		"preset_id": "gameplay",
		"time": 8.0,
		"path": "res://screenshots/shader_lab_starfield_gameplay.png",
	},
	{
		"shader_id": "water_fire_flow",
		"preset_id": "showcase",
		"time": 6.5,
		"path": "res://screenshots/shader_lab_water_fire_showcase.png",
	},
	{
		"shader_id": "water_fire_flow",
		"preset_id": "gameplay",
		"time": 6.5,
		"path": "res://screenshots/shader_lab_water_fire_gameplay.png",
	},
]


func _initialize() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load Shader Lab scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _index in range(5):
		await process_frame

	scene.call("debug_set_paused", true)
	scene.call("debug_set_ui_visible", false)
	for capture in CAPTURES:
		if not bool(scene.call("debug_select_shader", String(capture["shader_id"]))):
			push_error("Unknown capture Shader: %s" % capture["shader_id"])
			quit(1)
			return
		if not bool(scene.call("debug_set_preset", String(capture["preset_id"]))):
			push_error("Unknown capture preset: %s" % capture["preset_id"])
			quit(1)
			return
		scene.call("debug_reset_current")
		scene.call("debug_set_animation_time", float(capture["time"]))
		for _index in range(8):
			await process_frame
		var error := _save_viewport(String(capture["path"]))
		if error != OK:
			quit(error)
			return

	quit(0)


func _save_viewport(screenshot_path: String) -> Error:
	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		push_error("Failed to read root viewport texture.")
		return ERR_CANT_ACQUIRE_RESOURCE
	var image := viewport_texture.get_image()
	if image == null:
		push_error("Failed to read root viewport image.")
		return ERR_CANT_ACQUIRE_RESOURCE
	var absolute_path := ProjectSettings.globalize_path(screenshot_path)
	var error := image.save_png(absolute_path)
	if error != OK:
		push_error("Failed to save screenshot: %s (%s)" % [absolute_path, error])
		return error
	print("Saved Shader Lab screenshot: %s" % absolute_path)
	return OK
