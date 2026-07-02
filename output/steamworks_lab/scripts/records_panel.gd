class_name SteamLabRecordsPanel
extends Control

const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")
const LAB_SAVE_SCRIPT := preload("res://scripts/lab_save.gd")
const UI_STYLE_SCRIPT := preload("res://scripts/ui_style.gd")

var _best_seconds: float = 0.0
var _dimmer: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _best_label: Label
var _time_label: Label
var _close_button: Button
var _panel_tween: Tween
var _locale: String = LAB_LOCALE_SCRIPT.LOCALE_ZH_CN


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_create_widgets()


func set_locale(locale: String) -> void:
	_locale = LAB_LOCALE_SCRIPT.normalize_locale(locale)
	_refresh_text()


func set_best_survival(seconds: float) -> void:
	_best_seconds = maxf(0.0, seconds)
	_refresh_text()


func open(seconds: float) -> void:
	set_best_survival(seconds)
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	visible = true
	_dimmer.visible = true
	_panel.visible = true
	_dimmer.color = Color(0.01, 0.02, 0.02, 0.0)
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size * 0.5
	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(_dimmer, "color:a", 0.58, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_panel, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(_panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	if DisplayServer.get_name().to_lower() == "headless":
		_finish_close()
		return
	_panel_tween = create_tween()
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(_dimmer, "color:a", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(_panel, "modulate:a", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(_panel, "scale", Vector2(0.96, 0.96), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_panel_tween.chain().tween_callback(_finish_close)


func is_open() -> bool:
	return visible


func _finish_close() -> void:
	visible = false


func _create_widgets() -> void:
	_dimmer = ColorRect.new()
	_dimmer.name = "Dimmer"
	_dimmer.color = Color(0.01, 0.02, 0.02, 0.58)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dimmer)
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.name = "RecordsPanel"
	_panel.custom_minimum_size = Vector2(358.0, 260.0)
	UI_STYLE_SCRIPT.apply_panel(_panel, "hero")
	center.add_child(_panel)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 14)
	margin.add_child(rows)

	_title_label = Label.new()
	_title_label.name = "RecordsTitle"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 27)
	_title_label.add_theme_color_override("font_color", Color(0.96, 1.0, 0.74, 0.98))
	_title_label.add_theme_constant_override("outline_size", 3)
	_title_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.52))
	rows.add_child(_title_label)

	_best_label = Label.new()
	_best_label.name = "BestSurvivalLabel"
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_best_label.add_theme_font_size_override("font_size", 14)
	_best_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.MUTED_TEXT_COLOR)
	rows.add_child(_best_label)

	_time_label = Label.new()
	_time_label.name = "BestSurvivalTime"
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 34)
	_time_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.SLIME_COLOR)
	_time_label.add_theme_constant_override("outline_size", 4)
	_time_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.55))
	rows.add_child(_time_label)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.custom_minimum_size = Vector2(260.0, 46.0)
	UI_STYLE_SCRIPT.apply_button(_close_button, true)
	_close_button.pressed.connect(close)
	rows.add_child(_close_button)

	_refresh_text()


func _refresh_text() -> void:
	if _title_label == null:
		return
	_title_label.text = _t("records_title")
	_best_label.text = _t("records_best_survival")
	_time_label.text = _t("records_no_record") if _best_seconds <= 0.0 else LAB_SAVE_SCRIPT.format_survival_time(_best_seconds)
	_close_button.text = _t("records_close")


func _t(key: String, args: Dictionary = {}) -> String:
	return LAB_LOCALE_SCRIPT.text(_locale, key, args)
