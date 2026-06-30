extends Node2D

const PATCH_SCRIPT := preload("res://scripts/mycelium_patch.gd")
const ACTION_BACK := "lab_back"
const ACTION_TOGGLE_DECAY := "lab_toggle_decay"
const ACTION_RESEED := "lab_reseed"
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const GRID_STEP := 40.0
const ROOM_RECT := Rect2(Vector2(110.0, 76.0), Vector2(1060.0, 610.0))

var _patch: Node2D
var _time: float = 0.0
var _seed: int = 24017
var _decaying: bool = false


func _ready() -> void:
	_ensure_input_actions()
	_create_patch()


func _process(delta: float) -> void:
	_time += delta

	if Input.is_action_just_pressed(ACTION_BACK):
		get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")
		return
	if Input.is_action_just_pressed(ACTION_TOGGLE_DECAY):
		_decaying = not _decaying
	if Input.is_action_just_pressed(ACTION_RESEED):
		_seed += 7919
		_patch.call("regenerate", _seed)

	var mouse_position := get_global_mouse_position()
	_patch.call("set_focus_position", mouse_position - _patch.global_position)

	var target_growth := 0.38 if _decaying else 0.92
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		target_growth = 1.0

	var current_growth := float(_patch.get("growth_amount"))
	var growth_speed := 0.42 if target_growth > current_growth else 0.22
	_patch.call("set_growth_amount", move_toward(current_growth, target_growth, delta * growth_speed))
	queue_redraw()


func _draw() -> void:
	_draw_floor()
	_draw_status_marks()


func _create_patch() -> void:
	_patch = PATCH_SCRIPT.new() as Node2D
	_patch.name = "MyceliumPatch"
	_patch.set("seed", _seed)
	_patch.set("field_size", Vector2(1020.0, 560.0))
	_patch.set("source_count", 8)
	_patch.set("strand_density", 1.0)
	_patch.set("growth_amount", 0.74)
	_patch.global_position = ROOM_RECT.position + ROOM_RECT.size * 0.5
	add_child(_patch)


func _draw_floor() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.039, 0.035, 0.043, 1.0), true)
	draw_rect(ROOM_RECT.grow(18.0), Color(0.0, 0.0, 0.0, 0.22), true)
	draw_rect(ROOM_RECT, Color(0.086, 0.067, 0.072, 1.0), true)
	draw_rect(ROOM_RECT, Color(0.43, 0.30, 0.24, 0.78), false, 3.0)

	var grid_color := Color(0.52, 0.42, 0.33, 0.10)
	for x_index in range(int(ROOM_RECT.size.x / GRID_STEP) + 1):
		var x := ROOM_RECT.position.x + float(x_index) * GRID_STEP
		draw_line(Vector2(x, ROOM_RECT.position.y), Vector2(x, ROOM_RECT.end.y), grid_color, 1.0)

	for y_index in range(int(ROOM_RECT.size.y / GRID_STEP) + 1):
		var y := ROOM_RECT.position.y + float(y_index) * GRID_STEP
		draw_line(Vector2(ROOM_RECT.position.x, y), Vector2(ROOM_RECT.end.x, y), grid_color, 1.0)

	for band_index in range(9):
		var y := ROOM_RECT.position.y + 64.0 + float(band_index) * 58.0
		var color := Color(0.30, 0.20, 0.22, 0.10 + sin(_time * 0.6 + float(band_index)) * 0.025)
		draw_line(Vector2(ROOM_RECT.position.x + 20.0, y), Vector2(ROOM_RECT.end.x - 20.0, y + 22.0), color, 3.0)


func _draw_status_marks() -> void:
	var origin := Vector2(128.0, 40.0)
	var growth_width := 220.0 * float(_patch.get("growth_amount"))
	draw_rect(Rect2(origin, Vector2(236.0, 16.0)), Color(0.14, 0.10, 0.10, 0.82), true)
	draw_rect(Rect2(origin + Vector2(8.0, 5.0), Vector2(growth_width, 6.0)), Color(0.76, 0.66, 0.42, 0.88), true)

	var state_color := Color(0.48, 0.72, 0.62, 0.88)
	if _decaying:
		state_color = Color(0.58, 0.34, 0.34, 0.88)
	draw_circle(origin + Vector2(266.0, 8.0), 8.0, state_color)


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_BACK, KEY_ESCAPE)
	_register_key_action(ACTION_TOGGLE_DECAY, KEY_SPACE)
	_register_key_action(ACTION_RESEED, KEY_R)


func _register_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return

	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action_name, event)
