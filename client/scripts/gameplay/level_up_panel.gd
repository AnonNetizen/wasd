# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §7.1
class_name LevelUpPanel
extends CanvasLayer


signal choice_selected(choice: Dictionary)
signal pause_requested()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const BUTTON_HEIGHT: float = 56.0
const BUTTON_HORIZONTAL_PADDING: float = 48.0
const PANEL_MAX_WIDTH: float = 720.0
const PANEL_MIN_WIDTH: float = 520.0
const PANEL_WIDTH_RATIO: float = 0.42

var _choices: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _button_box: VBoxContainer = null
var _panel: PanelContainer = null
var _pressed_choice_index: int = -1
var _root: Control = null
var _selection_locked: bool = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTIONS.PAUSE) and UIManager.top() == self:
		get_viewport().set_input_as_handled()
		pause_requested.emit()
		return

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
	_root = Control.new()
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.resized.connect(_update_panel_width)
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "LevelUpPanelFrame"
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.process_mode = Node.PROCESS_MODE_ALWAYS
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.process_mode = Node.PROCESS_MODE_ALWAYS
	layout.mouse_filter = Control.MOUSE_FILTER_PASS
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var title: Label = Label.new()
	title.process_mode = Node.PROCESS_MODE_ALWAYS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = tr("ui_level_up_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)

	_button_box = VBoxContainer.new()
	_button_box.process_mode = Node.PROCESS_MODE_ALWAYS
	_button_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_button_box.add_theme_constant_override("separation", 8)
	layout.add_child(_button_box)
	_update_panel_width()
	_refresh_buttons()


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


func _refresh_buttons() -> void:
	_buttons.clear()
	for child: Node in _button_box.get_children():
		child.queue_free()

	for index: int in range(_choices.size()):
		var choice: Dictionary = _choices[index]
		var button: Button = Button.new()
		button.process_mode = Node.PROCESS_MODE_ALWAYS
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.custom_minimum_size = Vector2(_button_width(), BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s\n%s" % [tr(String(choice.get("name_key", ""))), tr(String(choice.get("desc_key", "")))]
		button.pressed.connect(Callable(self, "_on_choice_pressed").bind(index))
		_buttons.append(button)
		_button_box.add_child(button)


func _on_choice_pressed(index: int) -> void:
	choose_index(index)


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
