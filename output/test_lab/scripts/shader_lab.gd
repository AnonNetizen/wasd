extends Control

## 全屏 Shader 实验场。注册项共享一组基础 uniform，控制器负责选择、会话内参数和确定性时间。

const INDEX_SCENE_PATH := "res://scenes/test_lab_index.tscn"
const STARFIELD_SHADER: Shader = preload("res://shaders/rotating_starfield.gdshader")
const WATER_FIRE_SHADER: Shader = preload("res://shaders/water_fire_flow.gdshader")

const PRESET_SHOWCASE := "showcase"
const PRESET_GAMEPLAY := "gameplay"

const ACTION_BACK := "lab_back"
const ACTION_NEXT_SHADER := "shader_lab_next"
const ACTION_TOGGLE_PRESET := "shader_lab_toggle_preset"
const ACTION_TOGGLE_PAUSE := "shader_lab_toggle_pause"
const ACTION_RESET := "shader_lab_reset"
const ACTION_TOGGLE_UI := "shader_lab_toggle_ui"
const ACTION_SELECT_ONE := "shader_lab_select_1"
const ACTION_SELECT_TWO := "shader_lab_select_2"

const SHADER_DEFINITIONS: Array[Dictionary] = [
	{
		"id": "rotating_starfield",
		"name": "旋转星云穿行 / Rotating Starfield",
		"description": "五层星点旋转并向镜头推进，叠加低频星云和稀疏亮星。",
		"shader": STARFIELD_SHADER,
		"showcase": {"speed": 1.0, "intensity": 1.0, "scale": 1.0},
		"gameplay": {"speed": 0.65, "intensity": 0.55, "scale": 1.05},
	},
	{
		"id": "water_fire_flow",
		"name": "水火双流体涡旋 / Water & Fire",
		"description": "冷水与热火反向卷入，交界处形成流动的蒸汽亮边。",
		"shader": WATER_FIRE_SHADER,
		"showcase": {"speed": 0.85, "intensity": 1.0, "scale": 1.0},
		"gameplay": {"speed": 0.55, "intensity": 0.5, "scale": 1.15},
	},
]

var _preview: ColorRect
var _material: ShaderMaterial
var _control_panel: PanelContainer
var _shader_selector: OptionButton
var _description_label: Label
var _showcase_button: Button
var _gameplay_button: Button
var _speed_slider: HSlider
var _intensity_slider: HSlider
var _scale_slider: HSlider
var _speed_value_label: Label
var _intensity_value_label: Label
var _scale_value_label: Label
var _pause_button: Button
var _fps_label: Label

var _current_shader_index: int = 0
var _current_preset_id: String = PRESET_SHOWCASE
var _animation_time: float = 0.0
var _paused: bool = false
var _ui_visible: bool = true
var _applying_state: bool = false
var _fps_update_elapsed: float = 0.0
var _session_values: Dictionary = {}


func _ready() -> void:
	_create_preview()
	_create_control_panel()
	_ensure_input_actions()
	_populate_shader_selector()
	get_viewport().size_changed.connect(_update_viewport_aspect)
	_select_shader_index(0)
	_update_pause_button()
	_update_viewport_aspect()


func _process(delta: float) -> void:
	_process_shortcuts()
	if not _paused:
		_animation_time += delta
		_material.set_shader_parameter("animation_time", _animation_time)

	_fps_update_elapsed += delta
	if _fps_update_elapsed >= 0.25:
		_fps_update_elapsed = 0.0
		_fps_label.text = "FPS  %d" % Engine.get_frames_per_second()


func debug_select_shader(shader_id: String) -> bool:
	for index in range(SHADER_DEFINITIONS.size()):
		if String(SHADER_DEFINITIONS[index]["id"]) == shader_id:
			_select_shader_index(index)
			return true
	return false


func debug_set_preset(preset_id: String) -> bool:
	if preset_id != PRESET_SHOWCASE and preset_id != PRESET_GAMEPLAY:
		return false
	_set_preset(preset_id)
	return true


func debug_set_controls(speed: float, intensity: float, scale: float) -> void:
	_applying_state = true
	_speed_slider.value = clampf(speed, _speed_slider.min_value, _speed_slider.max_value)
	_intensity_slider.value = clampf(intensity, _intensity_slider.min_value, _intensity_slider.max_value)
	_scale_slider.value = clampf(scale, _scale_slider.min_value, _scale_slider.max_value)
	_applying_state = false
	_store_current_controls()
	_apply_control_uniforms()


func debug_set_paused(paused: bool) -> void:
	_paused = paused
	_update_pause_button()


func debug_set_ui_visible(visible: bool) -> void:
	_ui_visible = visible
	_control_panel.visible = visible


func debug_set_animation_time(value: float) -> void:
	_animation_time = maxf(value, 0.0)
	_material.set_shader_parameter("animation_time", _animation_time)


func debug_reset_current() -> void:
	_reset_current_state()


func debug_state() -> Dictionary:
	var shader_path := ""
	if _material != null and _material.shader != null:
		shader_path = _material.shader.resource_path
	return {
		"shader_id": String(_current_definition()["id"]),
		"preset_id": _current_preset_id,
		"shader_path": shader_path,
		"selector_count": _shader_selector.item_count,
		"speed": float(_speed_slider.value),
		"intensity": float(_intensity_slider.value),
		"scale": float(_scale_slider.value),
		"animation_time": _animation_time,
		"paused": _paused,
		"ui_visible": _ui_visible,
		"viewport_aspect": float(_material.get_shader_parameter("viewport_aspect")),
		"gameplay_mix": float(_material.get_shader_parameter("gameplay_mix")),
		"panel_exists": is_instance_valid(_control_panel),
		"fps_label_exists": is_instance_valid(_fps_label),
		"pause_button_text": _pause_button.text,
		"index_scene_path": INDEX_SCENE_PATH,
	}


func _create_preview() -> void:
	_preview = ColorRect.new()
	_preview.name = "ShaderPreview"
	_preview.color = Color.WHITE
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_preview)

	_material = ShaderMaterial.new()
	_preview.material = _material


func _create_control_panel() -> void:
	_control_panel = PanelContainer.new()
	_control_panel.name = "ControlPanel"
	_control_panel.position = Vector2(24.0, 24.0)
	_control_panel.size = Vector2(372.0, 664.0)
	_control_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_control_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_control_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	_control_panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	var eyebrow := Label.new()
	eyebrow.text = "WASD TEST LAB  /  SHADER"
	eyebrow.add_theme_font_size_override("font_size", 14)
	eyebrow.add_theme_color_override("font_color", Color(0.46, 0.85, 1.0, 0.86))
	rows.add_child(eyebrow)

	var title := Label.new()
	title.text = "Shader 实验场"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	rows.add_child(title)

	_shader_selector = OptionButton.new()
	_shader_selector.name = "ShaderSelector"
	_shader_selector.custom_minimum_size.y = 44.0
	_shader_selector.item_selected.connect(_on_shader_selected)
	rows.add_child(_shader_selector)

	_description_label = Label.new()
	_description_label.name = "Description"
	_description_label.custom_minimum_size.y = 48.0
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.add_theme_font_size_override("font_size", 15)
	_description_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	rows.add_child(_description_label)

	var preset_label := _section_label("预览预设")
	rows.add_child(preset_label)

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	rows.add_child(preset_row)

	_showcase_button = Button.new()
	_showcase_button.name = "ShowcasePreset"
	_showcase_button.text = "展示"
	_showcase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_showcase_button.custom_minimum_size.y = 40.0
	_showcase_button.pressed.connect(_set_preset.bind(PRESET_SHOWCASE))
	preset_row.add_child(_showcase_button)

	_gameplay_button = Button.new()
	_gameplay_button.name = "GameplayPreset"
	_gameplay_button.text = "游戏"
	_gameplay_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gameplay_button.custom_minimum_size.y = 40.0
	_gameplay_button.pressed.connect(_set_preset.bind(PRESET_GAMEPLAY))
	preset_row.add_child(_gameplay_button)

	var parameters_label := _section_label("基础参数")
	rows.add_child(parameters_label)

	var speed_section := _create_slider_section("速度", "SpeedSlider", 0.0, 2.0, 0.01)
	_speed_slider = speed_section["slider"] as HSlider
	_speed_value_label = speed_section["value_label"] as Label
	_speed_slider.value_changed.connect(_on_controls_changed)
	rows.add_child(speed_section["root"] as Control)

	var intensity_section := _create_slider_section("强度", "IntensitySlider", 0.0, 1.5, 0.01)
	_intensity_slider = intensity_section["slider"] as HSlider
	_intensity_value_label = intensity_section["value_label"] as Label
	_intensity_slider.value_changed.connect(_on_controls_changed)
	rows.add_child(intensity_section["root"] as Control)

	var scale_section := _create_slider_section("纹理尺度", "ScaleSlider", 0.5, 2.0, 0.01)
	_scale_slider = scale_section["slider"] as HSlider
	_scale_value_label = scale_section["value_label"] as Label
	_scale_slider.value_changed.connect(_on_controls_changed)
	rows.add_child(scale_section["root"] as Control)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	rows.add_child(action_row)

	_pause_button = Button.new()
	_pause_button.name = "PauseButton"
	_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_button.custom_minimum_size.y = 40.0
	_pause_button.pressed.connect(_toggle_pause)
	action_row.add_child(_pause_button)

	var reset_button := Button.new()
	reset_button.name = "ResetButton"
	reset_button.text = "重置"
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.custom_minimum_size.y = 40.0
	reset_button.pressed.connect(_reset_current_state)
	action_row.add_child(reset_button)

	var divider := HSeparator.new()
	rows.add_child(divider)

	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.text = "FPS  --"
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.add_theme_color_override("font_color", Color(0.57, 0.95, 0.72))
	rows.add_child(_fps_label)

	var hints := Label.new()
	hints.name = "Hints"
	hints.text = "1/2 直选 · Tab 切换 · M 预设\nSpace 暂停 · R 重置 · H 隐藏 · Esc 返回"
	hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hints.add_theme_font_size_override("font_size", 13)
	hints.add_theme_color_override("font_color", Color(0.59, 0.64, 0.72))
	rows.add_child(hints)


func _create_slider_section(
	label_text: String,
	slider_name: String,
	minimum: float,
	maximum: float,
	step: float
) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	root.add_child(header)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	header.add_child(label)

	var value_label := Label.new()
	value_label.text = "1.00×"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size.x = 64.0
	value_label.add_theme_color_override("font_color", Color(0.55, 0.87, 1.0))
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size.y = 24.0
	root.add_child(slider)

	return {"root": root, "slider": slider, "value_label": value_label}


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.92, 0.72, 0.38))
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.027, 0.055, 0.93)
	style.border_color = Color(0.21, 0.63, 0.82, 0.72)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 12
	return style


func _populate_shader_selector() -> void:
	_shader_selector.clear()
	for definition in SHADER_DEFINITIONS:
		_shader_selector.add_item(String(definition["name"]))


func _select_shader_index(index: int) -> void:
	if index < 0 or index >= SHADER_DEFINITIONS.size():
		return
	_store_current_controls()
	_current_shader_index = index
	_shader_selector.select(index)
	var definition := _current_definition()
	_material.shader = definition["shader"] as Shader
	_description_label.text = String(definition["description"])
	_apply_saved_or_default_state()


func _set_preset(preset_id: String) -> void:
	if preset_id != PRESET_SHOWCASE and preset_id != PRESET_GAMEPLAY:
		return
	_store_current_controls()
	_current_preset_id = preset_id
	_apply_saved_or_default_state()


func _apply_saved_or_default_state() -> void:
	var key := _state_key()
	if not _session_values.has(key):
		_session_values[key] = _preset_defaults()
	var values: Dictionary = _session_values[key]
	_applying_state = true
	_speed_slider.value = float(values["speed"])
	_intensity_slider.value = float(values["intensity"])
	_scale_slider.value = float(values["scale"])
	_applying_state = false
	_apply_control_uniforms()
	_update_preset_buttons()


func _preset_defaults() -> Dictionary:
	var definition := _current_definition()
	var values: Dictionary = definition[_current_preset_id]
	return values.duplicate(true)


func _state_key() -> String:
	return "%s:%s" % [String(_current_definition()["id"]), _current_preset_id]


func _current_definition() -> Dictionary:
	return SHADER_DEFINITIONS[_current_shader_index]


func _store_current_controls() -> void:
	if _speed_slider == null or _applying_state or _material == null or _material.shader == null:
		return
	_session_values[_state_key()] = {
		"speed": float(_speed_slider.value),
		"intensity": float(_intensity_slider.value),
		"scale": float(_scale_slider.value),
	}


func _apply_control_uniforms() -> void:
	_material.set_shader_parameter("motion_speed", float(_speed_slider.value))
	_material.set_shader_parameter("effect_intensity", float(_intensity_slider.value))
	_material.set_shader_parameter("pattern_scale", float(_scale_slider.value))
	_material.set_shader_parameter(
		"gameplay_mix",
		1.0 if _current_preset_id == PRESET_GAMEPLAY else 0.0
	)
	_material.set_shader_parameter("animation_time", _animation_time)
	_update_control_value_labels()


func _update_control_value_labels() -> void:
	_speed_value_label.text = "%.2f×" % _speed_slider.value
	_intensity_value_label.text = "%.2f×" % _intensity_slider.value
	_scale_value_label.text = "%.2f×" % _scale_slider.value


func _update_preset_buttons() -> void:
	var is_showcase := _current_preset_id == PRESET_SHOWCASE
	_showcase_button.disabled = is_showcase
	_gameplay_button.disabled = not is_showcase


func _update_pause_button() -> void:
	_pause_button.text = "继续" if _paused else "暂停"


func _toggle_pause() -> void:
	debug_set_paused(not _paused)


func _reset_current_state() -> void:
	_session_values[_state_key()] = _preset_defaults()
	_animation_time = 0.0
	_apply_saved_or_default_state()


func _toggle_ui() -> void:
	debug_set_ui_visible(not _ui_visible)


func _update_viewport_aspect() -> void:
	var viewport_size := get_viewport_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	_material.set_shader_parameter("viewport_aspect", aspect)


func _on_shader_selected(index: int) -> void:
	_select_shader_index(index)


func _on_controls_changed(_value: float) -> void:
	if _applying_state:
		return
	_store_current_controls()
	_apply_control_uniforms()


func _process_shortcuts() -> void:
	if Input.is_action_just_pressed(ACTION_BACK):
		get_tree().change_scene_to_file(INDEX_SCENE_PATH)
		return
	if Input.is_action_just_pressed(ACTION_NEXT_SHADER):
		_select_shader_index((_current_shader_index + 1) % SHADER_DEFINITIONS.size())
	if Input.is_action_just_pressed(ACTION_TOGGLE_PRESET):
		_set_preset(PRESET_GAMEPLAY if _current_preset_id == PRESET_SHOWCASE else PRESET_SHOWCASE)
	if Input.is_action_just_pressed(ACTION_TOGGLE_PAUSE):
		_toggle_pause()
	if Input.is_action_just_pressed(ACTION_RESET):
		_reset_current_state()
	if Input.is_action_just_pressed(ACTION_TOGGLE_UI):
		_toggle_ui()
	if Input.is_action_just_pressed(ACTION_SELECT_ONE):
		_select_shader_index(0)
	if Input.is_action_just_pressed(ACTION_SELECT_TWO) and SHADER_DEFINITIONS.size() > 1:
		_select_shader_index(1)


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_BACK, KEY_ESCAPE)
	_register_key_action(ACTION_NEXT_SHADER, KEY_TAB)
	_register_key_action(ACTION_TOGGLE_PRESET, KEY_M)
	_register_key_action(ACTION_TOGGLE_PAUSE, KEY_SPACE)
	_register_key_action(ACTION_RESET, KEY_R)
	_register_key_action(ACTION_TOGGLE_UI, KEY_H)
	_register_key_action(ACTION_SELECT_ONE, KEY_1)
	_register_key_action(ACTION_SELECT_TWO, KEY_2)


func _register_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and (existing_event as InputEventKey).keycode == keycode:
			return
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action_name, event)
