# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name F4GameOverPanel
extends CanvasLayer


signal quit_to_title_requested()
signal restart_requested()

const BUTTON_HEIGHT: float = 52.0
const BUTTON_WIDTH: float = 260.0
const PANEL_WIDTH: float = 520.0

var _summary_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.42)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var title: Label = Label.new()
	title.text = tr("ui_game_over")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	_summary_label = Label.new()
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.add_theme_font_size_override("font_size", 20)
	layout.add_child(_summary_label)

	var restart_button: Button = _make_button(tr("ui_restart"))
	restart_button.pressed.connect(_on_restart_pressed)
	layout.add_child(restart_button)

	var quit_button: Button = _make_button(tr("ui_quit_to_title"))
	quit_button.pressed.connect(_on_quit_to_title_pressed)
	layout.add_child(quit_button)
	restart_button.call_deferred("grab_focus")


func configure(kills: int, run_time: float) -> void:
	if _summary_label == null:
		return
	_summary_label.text = tr("ui_run_summary").format({
		"kills": kills,
		"time": int(run_time),
	})


func _make_button(text_value: String) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_quit_to_title_pressed() -> void:
	quit_to_title_requested.emit()
