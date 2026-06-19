# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name TitleMenu
extends CanvasLayer


signal quit_requested()
signal continue_requested()
signal meta_progression_requested()
signal start_requested()

var _continue_button: Button = null
var _meta_progression_button: Button = null
var _meta_summary_label: Label = null
var _notice_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var title: Label = get_node_or_null("Root/Center/Panel/Margin/Layout/TitleLabel") as Label
	var subtitle: Label = get_node_or_null("Root/Center/Panel/Margin/Layout/SubtitleLabel") as Label
	var start_button: Button = get_node_or_null("Root/Center/Panel/Margin/Layout/StartButton") as Button
	var quit_button: Button = get_node_or_null("Root/Center/Panel/Margin/Layout/QuitButton") as Button
	_notice_label = get_node_or_null("Root/Center/Panel/Margin/Layout/RunSaveNoticeLabel") as Label
	_meta_summary_label = get_node_or_null("Root/Center/Panel/Margin/Layout/MetaProfileSummaryLabel") as Label
	_continue_button = get_node_or_null("Root/Center/Panel/Margin/Layout/ContinueRunButton") as Button
	_meta_progression_button = get_node_or_null("Root/Center/Panel/Margin/Layout/MetaProgressionButton") as Button

	if title == null or subtitle == null or start_button == null or quit_button == null:
		push_error("[TitleMenu] missing required scene nodes")
		return
	if _notice_label == null or _meta_summary_label == null or _continue_button == null or _meta_progression_button == null:
		push_error("[TitleMenu] missing required scene nodes")
		return

	title.text = tr("ui_title_name")
	subtitle.text = tr("ui_title_subtitle")
	_notice_label.visible = false

	_continue_button.text = tr("ui_continue_run")
	_continue_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_continue_button.pressed.connect(_on_continue_pressed)

	start_button.text = tr("ui_start")
	start_button.process_mode = Node.PROCESS_MODE_ALWAYS
	start_button.pressed.connect(_on_start_pressed)

	_meta_progression_button.text = tr("ui_meta_progression")
	_meta_progression_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_meta_progression_button.pressed.connect(_on_meta_progression_pressed)

	quit_button.text = tr("ui_quit")
	quit_button.process_mode = Node.PROCESS_MODE_ALWAYS
	quit_button.pressed.connect(_on_quit_pressed)
	call_deferred("_grab_button_focus", start_button)
	refresh_meta_summary()


func configure(can_continue: bool, notice_key: String = "") -> void:
	if _continue_button == null:
		return
	_continue_button.visible = can_continue
	_continue_button.disabled = not can_continue
	if _notice_label == null:
		return
	_notice_label.visible = not notice_key.is_empty()
	if _notice_label.visible:
		_notice_label.text = tr(notice_key)
	else:
		_notice_label.text = ""


func refresh_meta_summary() -> void:
	var profile: Dictionary = MetaProgressionSystem.profile_summary()
	var currency_name: String = tr(String(profile.get("currency_name_key", "")))
	if _meta_summary_label != null:
		_meta_summary_label.text = tr("ui_meta_title_summary").format({
			"level": int(profile.get("account_level", 1)),
			"currency": currency_name,
			"amount": int(profile.get("currency_amount", 0)),
		})

	var has_available_purchase: bool = not MetaProgressionSystem.first_available_purchase().is_empty()
	if _meta_progression_button != null:
		_meta_progression_button.text = (
			tr("ui_meta_progression_available") if has_available_purchase else tr("ui_meta_progression")
		)
		_meta_progression_button.tooltip_text = _meta_summary_label.text if _meta_summary_label != null else ""


func _grab_button_focus(button: Button) -> void:
	if is_instance_valid(button) and button.is_inside_tree():
		button.grab_focus()


func _on_start_pressed() -> void:
	start_requested.emit()


func _on_continue_pressed() -> void:
	continue_requested.emit()


func _on_meta_progression_pressed() -> void:
	meta_progression_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()
