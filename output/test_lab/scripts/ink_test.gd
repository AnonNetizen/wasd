extends Node2D

# 水墨角色实验 harness：实例化全屏水墨场 + 标题标签。非交互，仅 Esc 返回索引。

const FIELD_SCRIPT := preload("res://scripts/ink_field.gd")
const ACTION_BACK := "lab_back"

var _field: Node2D
var _title_label: Label


func _ready() -> void:
	_ensure_input_actions()
	_create_field()
	_create_labels()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION_BACK):
		get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")


func _create_field() -> void:
	_field = FIELD_SCRIPT.new() as Node2D
	_field.name = "InkField"
	add_child(_field)


func _create_labels() -> void:
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "Ink Wash · 水墨角色"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(0.16, 0.14, 0.13, 0.78))
	_title_label.position = Vector2(40.0, 30.0)
	add_child(_title_label)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "抽象墨团：大者居中为玩家，小者环绕为敌人 · Esc 返回"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.20, 0.18, 0.16, 0.55))
	hint.position = Vector2(40.0, 64.0)
	add_child(hint)


func _ensure_input_actions() -> void:
	if not InputMap.has_action(ACTION_BACK):
		InputMap.add_action(ACTION_BACK)
	for event in InputMap.action_get_events(ACTION_BACK):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == KEY_ESCAPE:
			return
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	InputMap.action_add_event(ACTION_BACK, event)
