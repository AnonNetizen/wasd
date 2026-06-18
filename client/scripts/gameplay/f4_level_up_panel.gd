# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §7.1
class_name F4LevelUpPanel
extends CanvasLayer


signal choice_selected(choice: Dictionary)

const BUTTON_HEIGHT: float = 56.0
const BUTTON_HORIZONTAL_PADDING: float = 48.0
const PANEL_MAX_WIDTH: float = 720.0
const PANEL_MIN_WIDTH: float = 520.0
const PANEL_WIDTH_RATIO: float = 0.42

var _choices: Array[Dictionary] = []
var _button_box: VBoxContainer = null
var _panel: PanelContainer = null
var _root: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.resized.connect(_update_panel_width)
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "LevelUpPanelFrame"
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_panel.add_child(margin)

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
	_update_panel_width()
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
		button.custom_minimum_size = Vector2(_button_width(), BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s\n%s" % [tr(String(choice.get("name_key", ""))), tr(String(choice.get("desc_key", "")))]
		button.pressed.connect(Callable(self, "_on_choice_pressed").bind(index))
		_button_box.add_child(button)


func _on_choice_pressed(index: int) -> void:
	choose_index(index)


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
