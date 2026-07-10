extends Node2D

# 云雾团实验 harness：亮色渐变天空底（运行时生成 GradientTexture2D）+ 升腾烟羽。
# 非交互，仅 Esc 返回索引。

const CLOUD_SCRIPT := preload("res://scripts/cloud_mist.gd")
const SCREEN := Vector2(1280.0, 760.0)
const ACTION_BACK := "lab_back"

var _background: TextureRect
var _cloud: Node2D
var _title_label: Label


func _ready() -> void:
	_ensure_input_actions()
	_create_background()
	_create_cloud()
	_create_labels()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION_BACK):
		get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")


func _create_background() -> void:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(0.83, 0.88, 0.95)) # 顶：浅冷天蓝
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.97, 0.95, 0.91)) # 底：暖亮
	gradient.add_point(0.62, Color(0.92, 0.92, 0.92))

	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill = GradientTexture2D.FILL_LINEAR
	gradient_texture.fill_from = Vector2(0.0, 0.0)
	gradient_texture.fill_to = Vector2(0.0, 1.0)
	gradient_texture.width = 8
	gradient_texture.height = 256

	_background = TextureRect.new()
	_background.name = "SkyBackdrop"
	_background.texture = gradient_texture
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.size = SCREEN
	_background.position = Vector2.ZERO
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)


func _create_cloud() -> void:
	_cloud = CLOUD_SCRIPT.new() as Node2D
	_cloud.name = "CloudMist"
	add_child(_cloud)


func _create_labels() -> void:
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = "Cloud Mist · 升腾烟羽"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(0.22, 0.27, 0.34, 0.82))
	_title_label.position = Vector2(40.0, 30.0)
	add_child(_title_label)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "CPUParticles2D 粒子团 · 自动升腾循环 · Esc 返回"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.30, 0.34, 0.40, 0.60))
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
