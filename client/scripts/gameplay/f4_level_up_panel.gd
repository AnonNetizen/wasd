# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §7.1
class_name F4LevelUpPanel
extends CanvasLayer


signal choice_selected(choice: Dictionary)

const BUTTON_HEIGHT: float = 56.0
const PANEL_WIDTH: float = 420.0

var _choices: Array[Dictionary] = []
var _root: Control = null
var _button_box: VBoxContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_WIDTH * 0.5
	panel.offset_right = PANEL_WIDTH * 0.5
	panel.offset_top = -150.0
	panel.offset_bottom = 150.0
	_root.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var title: Label = Label.new()
	title.text = tr("ui_level_up_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)

	_button_box = VBoxContainer.new()
	_button_box.add_theme_constant_override("separation", 8)
	layout.add_child(_button_box)
	_refresh_buttons()


func configure(choices: Array[Dictionary]) -> void:
	_choices = choices.duplicate(true)
	if _button_box != null:
		_refresh_buttons()


func choose_index(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	choice_selected.emit(_choices[index].duplicate(true))


func choice_id(index: int) -> String:
	if index < 0 or index >= _choices.size():
		return ""
	return String(_choices[index].get("id", ""))


func _refresh_buttons() -> void:
	for child: Node in _button_box.get_children():
		child.queue_free()

	for index: int in range(_choices.size()):
		var choice: Dictionary = _choices[index]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(PANEL_WIDTH - 40.0, BUTTON_HEIGHT)
		button.text = "%s\n%s" % [tr(String(choice.get("name_key", ""))), tr(String(choice.get("desc_key", "")))]
		button.pressed.connect(Callable(self, "_on_choice_pressed").bind(index))
		_button_box.add_child(button)


func _on_choice_pressed(index: int) -> void:
	choose_index(index)
