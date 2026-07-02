extends SceneTree

# 史莱姆形变压力截图（移动 + 连射中，需带窗口跑）：
#   godot --path output/steamworks_lab --script res://tests/capture_slime_stress.gd -- --out=<输出目录>

const DEFAULT_OUT_DIR: String = "user://captures"


func _init() -> void:
	call_deferred("_run")


func _out_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--out="):
			return String(arg).trim_prefix("--out=")
	return DEFAULT_OUT_DIR


func _save_screenshot(path: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	print("[slime-stress] saved %s (%s)" % [path, error_string(error)])


func _press_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _press_mouse(pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)


func _run() -> void:
	var out_dir := _out_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	root.add_child(main_scene)
	await process_frame
	main_scene.call("_begin_single_player")
	await create_timer(0.6).timeout

	_save_screenshot(out_dir.path_join("slime_idle.png"))

	_press_mouse(true, Vector2(270.0, 200.0))
	await create_timer(1.4).timeout
	_save_screenshot(out_dir.path_join("slime_firing.png"))

	_press_key(KEY_A, true)
	await create_timer(1.2).timeout
	_save_screenshot(out_dir.path_join("slime_move_fire.png"))

	_press_key(KEY_A, false)
	_press_key(KEY_D, true)
	await create_timer(0.35).timeout
	_save_screenshot(out_dir.path_join("slime_turn.png"))

	quit(0)
