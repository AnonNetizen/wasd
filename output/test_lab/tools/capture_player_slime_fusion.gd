extends SceneTree

const SCENE_PATH: String = "res://scenes/player_slime_fusion_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/player_slime_fusion_test.png"
const PREVIEW_MAIN_BODY_PROBE := Vector2i(720, 420)
const PREVIEW_SWAP_BODY_PROBE := Vector2i(1040, 420)


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
	await physics_frame
	scene.call("debug_set_fixed_step_mode", true)
	scene.call("debug_set_auto_demo", false)
	scene.call("debug_set_paused", false)
	scene.call("debug_reset")

	for frame in range(180):
		var phase: float = float(frame) / 60.0
		var motion := Vector2(cos(phase * 1.2) * 175.0, sin(phase * 1.7) * 125.0)
		var aim := Vector2(0.88, -0.48).normalized()
		if frame in [24, 68, 126, 164]:
			scene.call("debug_fire", aim)
		if frame == 102:
			scene.call("debug_hit", Vector2(-25.0, -8.0))
		scene.call("debug_advance_fixed_step", 1.0 / 60.0, motion, aim)

	RenderingServer.force_draw(true)
	RenderingServer.force_sync()
	await process_frame
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Dual-vortex player slime capture returned an empty image.")
		quit(1)
		return
	var main_pixel: Color = image.get_pixelv(PREVIEW_MAIN_BODY_PROBE)
	var swap_pixel: Color = image.get_pixelv(PREVIEW_SWAP_BODY_PROBE)
	if _is_background_like(main_pixel) or _is_background_like(swap_pixel):
		push_error(
			"Dual-vortex preview center probe failed: main=%s swap=%s."
			% [main_pixel, swap_pixel]
		)
		quit(1)
		return

	var absolute_path: String = ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var save_error: Error = image.save_png(absolute_path)
	if save_error != OK:
		push_error("Failed to save screenshot: %s" % save_error)
		quit(save_error)
		return
	print(
		"Saved deterministic dual-vortex preview: %s (main=%s swap=%s)"
		% [absolute_path, main_pixel, swap_pixel]
	)
	quit(0)


func _is_background_like(color: Color) -> bool:
	return color.a < 0.9 or maxf(color.r, maxf(color.g, color.b)) < 0.16
