extends SceneTree

const SCENE_PATH: String = "res://scenes/underground_spawn_beacon_test.tscn"
const CAPTURES: Array[Dictionary] = [
	{"name": "overview", "time": 0.72},
	{"name": "charge", "time": 0.30},
	{"name": "eruption", "time": 0.90},
	{"name": "breakout", "time": 1.43},
]


func _initialize() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return
	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	for definition: Dictionary in CAPTURES:
		scene.call("debug_set_preview_time", float(definition["time"]))
		await process_frame
		await process_frame
		RenderingServer.force_draw(true)
		RenderingServer.force_sync()
		await process_frame
		var image: Image = root.get_texture().get_image()
		if image.get_size() != Vector2i(1280, 760):
			push_error("Unexpected capture size for %s: %s" % [definition["name"], image.get_size()])
			quit(1)
			return
		var path: String = "res://screenshots/underground_spawn_beacon_%s.png" % definition["name"]
		var error: Error = image.save_png(ProjectSettings.globalize_path(path))
		if error != OK:
			push_error("Failed to save %s: %s" % [path, error])
			quit(error)
			return
		print("Saved screenshot: %s" % ProjectSettings.globalize_path(path))
	quit(0)
