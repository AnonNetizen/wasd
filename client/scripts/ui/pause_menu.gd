# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/正式项目工作规划.md F5, docs/游戏设计文档.md §9.12 / §9.16
class_name PauseMenu
extends CanvasLayer


signal quit_to_title_requested()
signal restart_requested()
signal resume_requested()
signal save_and_quit_requested()

const ACTIONS := preload("res://scripts/contracts/actions.gd")

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

	var title: Label = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/TitleLabel") as Label
	var resume_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/ResumeButton") as Button
	var save_and_quit_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/SaveAndQuitButton") as Button
	var restart_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/RestartButton") as Button
	var quit_to_title_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/QuitToTitleButton") as Button
	if title == null or resume_button == null or save_and_quit_button == null or restart_button == null or quit_to_title_button == null:
		push_error("[PauseMenu] missing required scene nodes")
		return

	title.text = tr("ui_pause_title")
	_register_button(resume_button, tr("ui_resume"))
	_register_button(save_and_quit_button, tr("ui_save_and_quit"))
	_register_button(restart_button, tr("ui_restart"))
	_register_button(quit_to_title_button, tr("ui_quit_to_title"))
	if not _buttons.is_empty():
		_buttons[0].call_deferred("grab_focus")


func _register_button(button: Button, text_value: String) -> void:
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.text = text_value
	var button_index: int = _buttons.size()
	button.pressed.connect(func() -> void:
		_activate_button(button_index)
	)
	_buttons.append(button)


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
