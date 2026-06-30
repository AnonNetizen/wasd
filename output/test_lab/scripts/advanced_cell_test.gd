extends Node2D

# 骨骼蒙皮细胞实验 harness：暗底 + 居中细胞，按键触发各动画。
# 1 idle / 2 伪足 / 3 分裂 / 4 吞噬，Space 顺次切换，Esc 返回索引。

const CELL_SCRIPT := preload("res://scripts/advanced_cell.gd")
const SCREEN := Vector2(1280.0, 760.0)
const OBSTACLE_CENTER := Vector2(826.0, 392.0)
const OBSTACLE_RADIUS := 66.0
const OBSTACLE_FILL := Color(0.30, 0.28, 0.33, 1.0)
const OBSTACLE_RIM := Color(0.46, 0.44, 0.50, 1.0)

const ACTION_BACK := "lab_back"
const ACTION_IDLE := "cell_idle"
const ACTION_PSEUDOPOD := "cell_pseudopod"
const ACTION_DIVIDE := "cell_divide"
const ACTION_ENGULF := "cell_engulf"
const ACTION_CYCLE := "cell_cycle"

var _cell: Node2D
var _state_label: Label
var _cycle_index: int = 0
var _time: float = 0.0
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	_ensure_input_actions()
	_create_cell()
	_create_labels()


func _process(delta: float) -> void:
	_time += delta

	if Input.is_action_just_pressed(ACTION_BACK):
		get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")
		return

	if Input.is_action_just_pressed(ACTION_IDLE):
		_cell.call("play_idle")
	elif Input.is_action_just_pressed(ACTION_PSEUDOPOD):
		_cell.call("trigger_pseudopod")
	elif Input.is_action_just_pressed(ACTION_DIVIDE):
		_cell.call("trigger_divide")
	elif Input.is_action_just_pressed(ACTION_ENGULF):
		_cell.call("trigger_engulf")
	elif Input.is_action_just_pressed(ACTION_CYCLE):
		_cycle_next()

	_update_drag()

	_state_label.text = "State: %s" % String(_cell.call("current_state"))
	queue_redraw()


func _update_drag() -> void:
	var mouse := get_global_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not _dragging:
			_dragging = true
			_drag_offset = _cell.position - mouse
		_cell.position = Vector2(
			clampf(mouse.x + _drag_offset.x, 120.0, SCREEN.x - 120.0),
			clampf(mouse.y + _drag_offset.y, 140.0, SCREEN.y - 120.0)
		)
	else:
		_dragging = false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.066, 0.082, 0.090, 1.0), true)
	var center := SCREEN * 0.5
	for ring in range(5):
		var ratio := float(ring) / 4.0
		var radius := lerpf(560.0, 200.0, ratio)
		draw_circle(center, radius, Color(0.10, 0.16, 0.17, 0.04))
	# 障碍物（石块）—— 细胞撞上时膜会贴壁凹陷
	draw_circle(OBSTACLE_CENTER, OBSTACLE_RADIUS + 6.0, Color(0.0, 0.0, 0.0, 0.28))
	draw_circle(OBSTACLE_CENTER, OBSTACLE_RADIUS, OBSTACLE_FILL)
	draw_circle(OBSTACLE_CENTER + Vector2(-18.0, -20.0), OBSTACLE_RADIUS * 0.42, Color(OBSTACLE_RIM, 0.30))
	draw_arc(OBSTACLE_CENTER, OBSTACLE_RADIUS, 0.0, TAU, 40, OBSTACLE_RIM, 2.0, true)


func _create_cell() -> void:
	_cell = CELL_SCRIPT.new() as Node2D
	_cell.name = "AdvancedCell"
	_cell.position = SCREEN * 0.5
	add_child(_cell)
	_cell.call("set_obstacle_circle", OBSTACLE_CENTER, OBSTACLE_RADIUS)


func _create_labels() -> void:
	_state_label = Label.new()
	_state_label.name = "StateLabel"
	_state_label.text = "State: idle"
	_state_label.add_theme_font_size_override("font_size", 24)
	_state_label.add_theme_color_override("font_color", Color(0.80, 0.95, 0.92, 0.9))
	_state_label.position = Vector2(40.0, 30.0)
	add_child(_state_label)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "1 idle · 2 伪足 · 3 分裂 · 4 吞噬 · Space 顺次 · 左键拖动细胞撞障碍物 · Esc 返回"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.58, 0.72, 0.72, 0.7))
	hint.position = Vector2(40.0, 64.0)
	add_child(hint)


func _cycle_next() -> void:
	_cycle_index = (_cycle_index + 1) % 4
	match _cycle_index:
		0:
			_cell.call("play_idle")
		1:
			_cell.call("trigger_pseudopod")
		2:
			_cell.call("trigger_divide")
		3:
			_cell.call("trigger_engulf")


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_BACK, KEY_ESCAPE)
	_register_key_action(ACTION_IDLE, KEY_1)
	_register_key_action(ACTION_PSEUDOPOD, KEY_2)
	_register_key_action(ACTION_DIVIDE, KEY_3)
	_register_key_action(ACTION_ENGULF, KEY_4)
	_register_key_action(ACTION_CYCLE, KEY_SPACE)


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
