# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name F4TitleMenu
extends CanvasLayer


signal quit_requested()
signal start_requested()

const BUTTON_HEIGHT: float = 54.0
const BUTTON_WIDTH: float = 260.0
const PANEL_WIDTH: float = 520.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.07, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var title: Label = Label.new()
	title.text = tr("ui_title_name")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	layout.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = tr("ui_title_subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	layout.add_child(subtitle)

	var start_button: Button = _make_button(tr("ui_start"))
	start_button.pressed.connect(_on_start_pressed)
	layout.add_child(start_button)

	var quit_button: Button = _make_button(tr("ui_quit"))
	quit_button.pressed.connect(_on_quit_pressed)
	layout.add_child(quit_button)
	start_button.call_deferred("grab_focus")


func _make_button(text_value: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _on_start_pressed() -> void:
	start_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()
