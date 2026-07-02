class_name SteamLabBuffPanel
extends Control

signal option_chosen(option_index: int)

var _dimmer: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _countdown_label: Label
var _waiting_label: Label
var _option_buttons: Array[Button] = []
var _countdown_remaining: float = 0.0
var _countdown_enabled: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_create_widgets()


func _process(delta: float) -> void:
	if not visible or not _countdown_enabled:
		return
	_countdown_remaining = maxf(0.0, _countdown_remaining - delta)
	_countdown_label.text = "%d 秒后自动选择" % ceili(_countdown_remaining)


func open_with_options(options: Array[Dictionary], timeout: float) -> void:
	visible = true
	_dimmer.visible = true
	_panel.visible = true
	_waiting_label.visible = false
	_title_label.text = "选择一项强化"
	_countdown_enabled = timeout > 0.0
	_countdown_label.visible = _countdown_enabled
	_countdown_remaining = timeout
	for index in range(_option_buttons.size()):
		var button := _option_buttons[index]
		if index < options.size():
			var option: Dictionary = options[index]
			button.text = "%s\n%s" % [String(option.get("name", "?")), String(option.get("desc", ""))]
			button.visible = true
			button.disabled = false
		else:
			button.visible = false


func show_waiting(text: String) -> void:
	visible = true
	_dimmer.visible = true
	_panel.visible = true
	_title_label.text = "强化选择"
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
	visible = false
	_countdown_enabled = false


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
	center.add_child(_panel)

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
	_title_label.text = "选择一项强化"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.98, 0.80, 0.98))
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
		button.pressed.connect(_on_option_pressed.bind(index))
		rows.add_child(button)
		_option_buttons.append(button)

	_waiting_label = Label.new()
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_waiting_label.add_theme_font_size_override("font_size", 17)
	_waiting_label.visible = false
	rows.add_child(_waiting_label)


func _on_option_pressed(option_index: int) -> void:
	for button in _option_buttons:
		button.disabled = true
	option_chosen.emit(option_index)
