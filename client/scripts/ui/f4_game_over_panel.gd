# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name F4GameOverPanel
extends CanvasLayer


signal quit_to_title_requested()
signal restart_requested()

const BUTTON_HEIGHT: float = 52.0
const BUTTON_WIDTH: float = 260.0
const PANEL_WIDTH: float = 520.0

var _buttons: Array[Button] = []
var _pressed_button_index: int = -1
var _selection_locked: bool = false
var _summary_label: Label = null


func _input(event: InputEvent) -> void:
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
	backdrop.color = Color(0.0, 0.0, 0.0, 0.42)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
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
	title.text = tr("ui_game_over")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	_summary_label = Label.new()
	_summary_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.add_theme_font_size_override("font_size", 20)
	layout.add_child(_summary_label)

	var restart_button: Button = _make_button("RestartButton", tr("ui_restart"))
	restart_button.pressed.connect(_on_restart_pressed)
	_buttons.append(restart_button)
	layout.add_child(restart_button)

	var quit_button: Button = _make_button("QuitToTitleButton", tr("ui_quit_to_title"))
	quit_button.pressed.connect(_on_quit_to_title_pressed)
	_buttons.append(quit_button)
	layout.add_child(quit_button)
	restart_button.call_deferred("grab_focus")


func configure(kills: int, run_time: float) -> void:
	if _summary_label == null:
		return
	_summary_label.text = tr("ui_run_summary").format({
		"kills": kills,
		"time": int(run_time),
	})


func _make_button(button_name: String, text_value: String) -> Button:
	var button: Button = Button.new()
	button.name = button_name
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.text = text_value
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _on_restart_pressed() -> void:
	_activate_button(0)


func _on_quit_to_title_pressed() -> void:
	_activate_button(1)


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
		restart_requested.emit()
	elif index == 1:
		quit_to_title_requested.emit()
