extends SceneTree

# 鼠标开火链路探针（需要带窗口跑，headless 下 UI 尺寸为 0 测不出拦截）：
#   godot --path output/steamworks_lab --script res://tests/input_fire_probe.gd

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[input-fire-probe] PASS %s" % label)
	else:
		_failures += 1
		print("[input-fire-probe] FAIL %s" % label)


func _run() -> void:
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	root.add_child(main_scene)
	await process_frame
	main_scene.call("_begin_single_player")
	await create_timer(0.8).timeout

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(270.0, 300.0)
	press.global_position = press.position
	Input.parse_input_event(press)
	await create_timer(0.8).timeout

	_check(bool(main_scene.get("_fire_held")), "mouse press reaches fire input")
	var bullets: Array = main_scene.get("_bullets")
	_check(not bullets.is_empty(), "held fire spawns bullets (%d)" % bullets.size())

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = press.position
	release.global_position = press.position
	Input.parse_input_event(release)
	await create_timer(0.2).timeout
	_check(not bool(main_scene.get("_fire_held")), "mouse release stops fire")

	print("[input-fire-probe] %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(1 if _failures > 0 else 0)
