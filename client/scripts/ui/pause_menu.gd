# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/正式项目工作规划.md F5, docs/游戏设计文档.md §9.12 / §9.16
class_name PauseMenu
extends CanvasLayer


signal quit_to_title_requested()
signal restart_requested()
signal resume_requested()
signal save_and_quit_requested()
signal settings_requested()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const REPLAY_PARTICIPANT_ID: String = "player_0"

var pauses_game: bool = true

var _buttons: Array[Button] = []
var _pressed_button_index: int = -1
var _selection_locked: bool = false
var _title_label: Label = null


func _input(event: InputEvent) -> void:
	if UIManager.top() != self:
		return

	Replay.record_input_event(event, [ACTIONS.PAUSE], REPLAY_PARTICIPANT_ID)

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

	_title_label = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/TitleLabel") as Label
	var resume_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/ResumeButton") as Button
	var settings_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/SettingsButton") as Button
	var save_and_quit_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/SaveAndQuitButton") as Button
	var restart_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/RestartButton") as Button
	var quit_to_title_button: Button = get_node_or_null("Root/Center/PauseMenuPanel/Margin/Layout/QuitToTitleButton") as Button
	if _title_label == null or resume_button == null or settings_button == null or save_and_quit_button == null or restart_button == null or quit_to_title_button == null:
		push_error("[PauseMenu] missing required scene nodes")
		return

	_register_button(resume_button)
	_register_button(settings_button)
	_register_button(save_and_quit_button)
	_register_button(restart_button)
	_register_button(quit_to_title_button)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh_texts()
	if not _buttons.is_empty():
		_buttons[0].call_deferred("grab_focus")


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_pause_title")
	_set_button_text(0, "ui_resume")
	_set_button_text(1, "ui_settings")
	_set_button_text(2, "ui_save_and_quit")
	_set_button_text(3, "ui_restart")
	_set_button_text(4, "ui_quit_to_title")


func request_close() -> void:
	_activate_button(0)


func _register_button(button: Button) -> void:
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
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
	if index == 1:
		settings_requested.emit()
		return
	_selection_locked = true
	if index == 0:
		resume_requested.emit()
	elif index == 2:
		save_and_quit_requested.emit()
	elif index == 3:
		restart_requested.emit()
	elif index == 4:
		quit_to_title_requested.emit()


func _set_button_text(index: int, text_key: String) -> void:
	if index >= 0 and index < _buttons.size():
		_buttons[index].text = tr(text_key)


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()
