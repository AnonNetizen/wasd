# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/正式项目工作规划.md F5, docs/游戏设计文档.md §9.12 / §9.16
class_name F4PauseMenu
extends CanvasLayer


signal quit_to_title_requested()
signal restart_requested()
signal resume_requested()
signal save_and_quit_requested()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const BUTTON_HEIGHT: float = 52.0
const BUTTON_WIDTH: float = 280.0
const PANEL_WIDTH: float = 540.0

var pauses_game: bool = true

var _buttons: Array[Button] = []
var _pressed_button_index: int = -1
var _selection_locked: bool = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTIONS.PAUSE):
		get_viewport().set_input_as_handled()
		_activate_button(0)
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var button_index: int = _button_index_at_position(mouse_button.position)
	if mouse_button.pressed:
		_pressed_button_index = button_index
		if button_index >= 0:
			get_viewport().set_input_as_handled()
		return

	var pressed_button_index: int = _pressed_button_index
	_pressed_button_index = -1
	if button_index < 0 or button_index != pressed_button_index:
		return
	get_viewport().set_input_as_handled()
	_activate_button(button_index)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root: Control = Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = Color(0.0, 0.0, 0.0, 0.38)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "PauseMenuPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.process_mode = Node.PROCESS_MODE_ALWAYS
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.process_mode = Node.PROCESS_MODE_ALWAYS
	layout.mouse_filter = Control.MOUSE_FILTER_PASS
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var title: Label = Label.new()
	title.process_mode = Node.PROCESS_MODE_ALWAYS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = tr("ui_pause_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	_add_button(layout, "ResumeButton", tr("ui_resume"))
	_add_button(layout, "SaveAndQuitButton", tr("ui_save_and_quit"))
	_add_button(layout, "RestartButton", tr("ui_restart"))
	_add_button(layout, "QuitToTitleButton", tr("ui_quit_to_title"))
	if not _buttons.is_empty():
		_buttons[0].call_deferred("grab_focus")


func _add_button(parent: Node, button_name: String, text_value: String) -> void:
	var button: Button = Button.new()
	button.name = button_name
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.text = text_value
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var button_index: int = _buttons.size()
	button.pressed.connect(func() -> void:
		_activate_button(button_index)
	)
	_buttons.append(button)
	parent.add_child(button)


func _button_index_at_position(position: Vector2) -> int:
	for index: int in range(_buttons.size()):
		var button: Button = _buttons[index]
		if not is_instance_valid(button) or not button.visible or button.disabled:
			continue
		if button.get_global_rect().has_point(position):
			return index
	return -1


func _activate_button(index: int) -> void:
	if _selection_locked:
		return
	if index < 0 or index >= _buttons.size():
		return
	_selection_locked = true
	if index == 0:
		resume_requested.emit()
	elif index == 1:
		save_and_quit_requested.emit()
	elif index == 2:
		restart_requested.emit()
	elif index == 3:
		quit_to_title_requested.emit()
