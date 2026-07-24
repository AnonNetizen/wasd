# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §7.1
class_name LevelUpPanel
extends CanvasLayer


signal choice_selected(choice: Dictionary)
signal pause_requested()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const LEVEL_UP_CHOICE_BUTTON_SCENE: PackedScene = preload("res://scenes/ui/level_up_choice_button.tscn")
const BUTTON_HEIGHT: float = 56.0
const BUTTON_HORIZONTAL_PADDING: float = 48.0
const PANEL_MAX_WIDTH: float = 720.0
const PANEL_MIN_WIDTH: float = 520.0
const PANEL_WIDTH_RATIO: float = 0.42
const INPUT_PARTICIPANT_ID: String = "player_0"

var _choices: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _button_box: VBoxContainer = null
var _panel: PanelContainer = null
var _pressed_choice_index: int = -1
var _root: Control = null
var _selection_locked: bool = false
var _title_label: Label = null


func _input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var choice_index: int = _choice_index_at_position(mouse_button.position)
	if mouse_button.pressed:
		_pressed_choice_index = choice_index
		if choice_index >= 0:
			get_viewport().set_input_as_handled()
		return

	var pressed_choice_index: int = _pressed_choice_index
	_pressed_choice_index = -1
	if choice_index < 0 or choice_index != pressed_choice_index:
		return
	get_viewport().set_input_as_handled()
	choose_index(choice_index)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)

	_root = get_node_or_null("Root") as Control
	_panel = get_node_or_null("Root/Center/LevelUpPanelFrame") as PanelContainer
	_button_box = get_node_or_null("Root/Center/LevelUpPanelFrame/Margin/Layout/ButtonBox") as VBoxContainer
	_title_label = get_node_or_null("Root/Center/LevelUpPanelFrame/Margin/Layout/TitleLabel") as Label
	if _root == null or _panel == null or _button_box == null or _title_label == null:
		push_error("[LevelUpPanel] missing required scene nodes")
		return

	_root.resized.connect(_update_panel_width)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_update_panel_width()
	refresh_texts()


func _exit_tree() -> void:
	if InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.disconnect(_on_input_action_pressed)
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure(choices: Array[Dictionary]) -> void:
	_choices = choices.duplicate(true)
	_pressed_choice_index = -1
	_selection_locked = false
	if _button_box != null:
		_refresh_buttons()


func choose_index(index: int) -> void:
	if _selection_locked:
		return
	if index < 0 or index >= _choices.size():
		return
	_selection_locked = true
	choice_selected.emit(_choices[index].duplicate(true))


func choice_id(index: int) -> String:
	if index < 0 or index >= _choices.size():
		return ""
	return String(_choices[index].get("id", ""))


func refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_level_up_title")
	_refresh_buttons()


func _refresh_buttons() -> void:
	if _button_box == null:
		return
	_buttons.clear()
	for child: Node in _button_box.get_children():
		child.queue_free()

	for index: int in range(_choices.size()):
		var choice: Dictionary = _choices[index]
		var button: Button = LEVEL_UP_CHOICE_BUTTON_SCENE.instantiate() as Button
		if button == null:
			push_error("[LevelUpPanel] failed to instantiate choice button template")
			continue
		button.custom_minimum_size = Vector2(_button_width(), BUTTON_HEIGHT)
		button.text = "%s\n%s" % [tr(String(choice.get("name_key", ""))), tr(String(choice.get("desc_key", "")))]
		button.pressed.connect(Callable(self, "_on_choice_pressed").bind(index))
		_buttons.append(button)
		_button_box.add_child(button)
	var feedback: UIButtonFeedback = get_node_or_null(
		"UIEffects/ButtonFeedback"
	) as UIButtonFeedback
	if feedback != null:
		feedback.call_deferred("refresh_bindings")


func _on_choice_pressed(index: int) -> void:
	if index >= 0 and index < _buttons.size():
		var feedback: UISelectionFeedback = get_node_or_null(
			"UIEffects/SelectionFeedback"
		) as UISelectionFeedback
		if feedback != null:
			feedback.play_selection(_buttons[index])
	choose_index(index)


func _on_input_action_pressed(action_id: StringName, participant_id: String) -> void:
	if participant_id != INPUT_PARTICIPANT_ID or action_id != StringName(ACTIONS.PAUSE):
		return
	if UIManager.top() == self:
		pause_requested.emit()


func _choice_index_at_position(position: Vector2) -> int:
	for index: int in range(_buttons.size()):
		var button: Button = _buttons[index]
		if not is_instance_valid(button) or not button.visible or button.disabled:
			continue
		if button.get_global_rect().has_point(position):
			return index
	return -1


func _update_panel_width() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(_panel_width(), 0.0)
	if _button_box != null:
		for child: Node in _button_box.get_children():
			if child is Control:
				(child as Control).custom_minimum_size.x = _button_width()


func _panel_width() -> float:
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	if _root != null and _root.size.x > 0.0:
		viewport_width = _root.size.x
	return clampf(viewport_width * PANEL_WIDTH_RATIO, PANEL_MIN_WIDTH, PANEL_MAX_WIDTH)


func _button_width() -> float:
	return maxf(_panel_width() - BUTTON_HORIZONTAL_PADDING, 1.0)


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()
