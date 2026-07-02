extends SceneTree

# 战斗画面截图（不要加 --headless，gl_compatibility 下会输出黑图）：
#   godot --path output/steamworks_lab --script res://tests/capture_battle.gd -- --out=<输出目录>

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
	print("[capture-battle] saved %s (%s)" % [path, error_string(error)])


func _run() -> void:
	var out_dir := _out_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	root.add_child(main_scene)
	await process_frame
	await create_timer(0.4).timeout
	_save_screenshot(out_dir.path_join("start_menu.png"))
	main_scene.call("_begin_single_player")
	await create_timer(4.5).timeout
	_save_screenshot(out_dir.path_join("battle.png"))

	var director: Node = main_scene.get("_director")
	if director != null:
		director.call("_enter_buff_choice")
		await create_timer(0.4).timeout
		_save_screenshot(out_dir.path_join("buff_choice.png"))
	quit(0)
