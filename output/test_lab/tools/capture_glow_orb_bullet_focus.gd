extends SceneTree

const SCENE_PATH: String = "res://scenes/glow_orb_bullet_focus_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/glow_orb_bullet_focus.png"
const CAPTURE_TIME: float = 2.16
const PLAYER_BODY_PROBE: Vector2i = Vector2i(330, 320)
const ENEMY_BODY_PROBE: Vector2i = Vector2i(950, 320)
const PROBE_RADIUS: int = 2


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
	var player_probe: Color = _average_probe(image, PLAYER_BODY_PROBE)
	if minf(player_probe.r, minf(player_probe.g, player_probe.b)) <= 0.45:
		push_error("Player shader body did not render at its center: %s" % player_probe)
		quit(1)
		return
	var enemy_probe: Color = _average_probe(image, ENEMY_BODY_PROBE)
	if enemy_probe.r <= 0.55 or enemy_probe.r <= enemy_probe.g + 0.10:
		push_error("Enemy shader body did not render red at its center: %s" % enemy_probe)
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


func _average_probe(image: Image, center: Vector2i) -> Color:
	var red_total: float = 0.0
	var green_total: float = 0.0
	var blue_total: float = 0.0
	var alpha_total: float = 0.0
	var sample_count: int = 0
	for y in range(center.y - PROBE_RADIUS, center.y + PROBE_RADIUS + 1):
		for x in range(center.x - PROBE_RADIUS, center.x + PROBE_RADIUS + 1):
			var pixel: Color = image.get_pixel(x, y)
			red_total += pixel.r
			green_total += pixel.g
			blue_total += pixel.b
			alpha_total += pixel.a
			sample_count += 1
	var divisor: float = float(sample_count)
	return Color(
		red_total / divisor,
		green_total / divisor,
		blue_total / divisor,
		alpha_total / divisor
	)
