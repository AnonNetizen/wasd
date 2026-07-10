extends Node2D

# 情绪团实验 harness：暗背景（随当前情绪微染色）+ 居中情绪团 + 情绪名 / 操作提示标签。
# Space / 左键 / → 切下一情绪，1~4 直选，Esc 返回索引，鼠标移动作为局部焦点。

const BLOB_SCRIPT := preload("res://scripts/emotion_blob.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const ACTION_BACK := "lab_back"
const ACTION_NEXT := "lab_next_emotion"

var _blob: Node2D
var _name_label: Label
var _hint_label: Label
var _time: float = 0.0
var _last_emotion: int = -1
var _mouse_was_pressed: bool = false


func _ready() -> void:
	_ensure_input_actions()
	_create_blob()
	_create_labels()


func _process(delta: float) -> void:
	_time += delta

	if Input.is_action_just_pressed(ACTION_BACK):
		get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")
		return

	if Input.is_action_just_pressed(ACTION_NEXT):
		_blob.call("next_emotion")

	var mouse_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if mouse_pressed and not _mouse_was_pressed:
		_blob.call("next_emotion")
	_mouse_was_pressed = mouse_pressed

	for index in range(4):
		if Input.is_physical_key_pressed(KEY_1 + index) and int(_blob.get("emotion_index")) != index:
			_blob.call("set_emotion", index)

	var mouse_position := get_global_mouse_position()
	_blob.call("set_focus", mouse_position - _blob.global_position)

	var emotion_index := int(_blob.get("emotion_index"))
	if emotion_index != _last_emotion:
		_last_emotion = emotion_index
		_name_label.text = String(_blob.call("current_emotion_name"))

	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.045, 0.047, 0.055, 1.0), true)

	# 团后柔和径向辉光，按当前情绪染色
	var tint: Color = _blob.call("current_glow_color")
	var center := VIEWPORT_SIZE * 0.5
	for ring in range(6):
		var ratio := float(ring) / 5.0
		var radius := lerpf(520.0, 90.0, ratio)
		var alpha := lerpf(0.015, 0.075, ratio)
		draw_circle(center, radius, Color(tint.r, tint.g, tint.b, alpha))


func _create_blob() -> void:
	_blob = BLOB_SCRIPT.new() as Node2D
	_blob.name = "EmotionBlob"
	_blob.set("emotion_index", 0)
	_blob.global_position = VIEWPORT_SIZE * 0.5
	add_child(_blob)


func _create_labels() -> void:
	_name_label = Label.new()
	_name_label.name = "EmotionName"
	_name_label.text = ""
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 38)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97, 0.92))
	_name_label.size = Vector2(420.0, 52.0)
	_name_label.position = Vector2(VIEWPORT_SIZE.x * 0.5 - 210.0, 648.0)
	add_child(_name_label)

	_hint_label = Label.new()
	_hint_label.name = "Hints"
	_hint_label.text = "Space / 左键 / → 切换情绪    1-4 直选    Esc 返回"
	_hint_label.add_theme_font_size_override("font_size", 18)
	_hint_label.add_theme_color_override("font_color", Color(0.70, 0.72, 0.78, 0.70))
	_hint_label.position = Vector2(40.0, 32.0)
	add_child(_hint_label)


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_BACK, [KEY_ESCAPE])
	_register_key_action(ACTION_NEXT, [KEY_SPACE, KEY_RIGHT])


func _register_key_action(action_name: String, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for keycode in keycodes:
		var already_bound := false
		for event in InputMap.action_get_events(action_name):
			var key_event := event as InputEventKey
			if key_event != null and key_event.keycode == keycode:
				already_bound = true
				break
		if already_bound:
			continue
		var event := InputEventKey.new()
		event.keycode = keycode
		InputMap.action_add_event(action_name, event)
