class_name SteamLabBuffPanel
extends Control

signal option_chosen(option_index: int)

const UI_STYLE_SCRIPT := preload("res://scripts/ui_style.gd")
const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")

var _dimmer: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _countdown_label: Label
var _waiting_label: Label
var _option_buttons: Array[Button] = []
var _countdown_remaining: float = 0.0
var _countdown_enabled: bool = false
var _panel_tween: Tween
var _locale: String = LAB_LOCALE_SCRIPT.LOCALE_ZH_CN
var _current_options: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_create_widgets()


func _process(delta: float) -> void:
	if not visible or not _countdown_enabled:
		return
	_countdown_remaining = maxf(0.0, _countdown_remaining - delta)
	_refresh_countdown_label()


func set_locale(locale: String) -> void:
	_locale = LAB_LOCALE_SCRIPT.normalize_locale(locale)
	if _title_label == null:
		return
	if _waiting_label != null and _waiting_label.visible:
		_title_label.text = _t("buff_title_waiting")
	elif visible:
		_title_label.text = _t("buff_title_choose")
	_refresh_countdown_label()
	_refresh_option_buttons()


func open_with_options(options: Array[Dictionary], timeout: float) -> void:
	_current_options = options.duplicate(true)
	_animate_open()
	_waiting_label.visible = false
	_title_label.text = _t("buff_title_choose")
	_countdown_enabled = timeout > 0.0
	_countdown_label.visible = _countdown_enabled
	_countdown_remaining = timeout
	_refresh_countdown_label()
	_refresh_option_buttons()


func _refresh_option_buttons() -> void:
	for index in range(_option_buttons.size()):
		var button := _option_buttons[index]
		if index < _current_options.size():
			var option: Dictionary = _current_options[index]
			button.text = "%s\n%s" % [String(option.get("name", "?")), String(option.get("desc", ""))]
			button.visible = true
			button.disabled = false
		else:
			button.visible = false


func show_waiting(text: String) -> void:
	_current_options.clear()
	_animate_open()
	_title_label.text = _t("buff_title_waiting")
	for button in _option_buttons:
		button.visible = false
	_waiting_label.text = text
	_waiting_label.visible = true


func update_waiting(text: String) -> void:
	if _waiting_label.visible:
		_waiting_label.text = text


func is_waiting() -> bool:
	return visible and _waiting_label.visible


func close() -> void:
	_countdown_enabled = false
	_current_options.clear()
	if not visible:
		return
	_animate_close()


func _animate_open() -> void:
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	visible = true
	_dimmer.visible = true
	_panel.visible = true
	_dimmer.color = Color(0.02, 0.03, 0.04, 0.0)
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size * 0.5
	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(_dimmer, "color:a", 0.68, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_panel, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_close() -> void:
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(_dimmer, "color:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(_panel, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_panel_tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _create_widgets() -> void:
	_dimmer = ColorRect.new()
	_dimmer.name = "Dimmer"
	_dimmer.color = Color(0.02, 0.03, 0.04, 0.62)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dimmer)
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.name = "BuffPanel"
	_panel.custom_minimum_size = Vector2(380.0, 420.0)
	UI_STYLE_SCRIPT.apply_panel(_panel, "hero")
	center.add_child(_panel)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)

	_title_label = Label.new()
	_title_label.text = _t("buff_title_choose")
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.74, 0.98))
	_title_label.add_theme_constant_override("outline_size", 3)
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.52))
	rows.add_child(_title_label)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 14)
	_countdown_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.56, 0.92))
	_countdown_label.visible = false
	rows.add_child(_countdown_label)

	for index in range(3):
		var button := Button.new()
		button.custom_minimum_size = Vector2(0.0, 84.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI_STYLE_SCRIPT.apply_button(button)
		button.pressed.connect(_on_option_pressed.bind(index))
		rows.add_child(button)
		_option_buttons.append(button)

	_waiting_label = Label.new()
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_waiting_label.add_theme_font_size_override("font_size", 17)
	_waiting_label.visible = false
	rows.add_child(_waiting_label)


func _refresh_countdown_label() -> void:
	if _countdown_label == null:
		return
	_countdown_label.text = _t("buff_countdown", {"seconds": ceili(_countdown_remaining)})


func _t(key: String, args: Dictionary = {}) -> String:
	return LAB_LOCALE_SCRIPT.text(_locale, key, args)


func _on_option_pressed(option_index: int) -> void:
	for button in _option_buttons:
		button.disabled = true
	option_chosen.emit(option_index)
