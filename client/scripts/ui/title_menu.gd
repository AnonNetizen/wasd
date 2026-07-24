# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name TitleMenu
extends CanvasLayer


signal quit_requested()
signal continue_requested()
signal gear_mod_requested()
signal settings_requested()
signal start_requested()

var _continue_button: Button = null
var _gear_mod_button: Button = null
var _notice_key: String = ""
var _notice_label: Label = null
var _quit_button: Button = null
var _settings_button: Button = null
var _start_button: Button = null
var _subtitle_label: Label = null
var _title_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_title_label = get_node_or_null("Root/Center/Panel/Margin/Layout/TitleLabel") as Label
	_subtitle_label = get_node_or_null("Root/Center/Panel/Margin/Layout/SubtitleLabel") as Label
	_start_button = get_node_or_null("Root/Center/Panel/Margin/Layout/StartButton") as Button
	_settings_button = get_node_or_null("Root/Center/Panel/Margin/Layout/SettingsButton") as Button
	_quit_button = get_node_or_null("Root/Center/Panel/Margin/Layout/QuitButton") as Button
	_notice_label = get_node_or_null("Root/Center/Panel/Margin/Layout/RunSaveNoticeLabel") as Label
	_continue_button = get_node_or_null("Root/Center/Panel/Margin/Layout/ContinueRunButton") as Button
	_gear_mod_button = get_node_or_null("Root/Center/Panel/Margin/Layout/GearModButton") as Button

	if _title_label == null or _subtitle_label == null or _start_button == null or _quit_button == null:
		push_error("[TitleMenu] missing required scene nodes")
		return
	if _notice_label == null or _continue_button == null:
		push_error("[TitleMenu] missing required scene nodes")
		return
	if _gear_mod_button == null or _settings_button == null:
		push_error("[TitleMenu] missing required scene nodes")
		return

	_notice_label.visible = false

	_continue_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_continue_button.pressed.connect(_on_continue_pressed)

	_start_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_start_button.pressed.connect(_on_start_pressed)

	_gear_mod_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_gear_mod_button.pressed.connect(_on_gear_mod_pressed)

	_settings_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_button.pressed.connect(_on_settings_pressed)

	_quit_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_quit_button.pressed.connect(_on_quit_pressed)
	if not UIManager.navigation_focus_visibility_changed.is_connected(_on_navigation_focus_visibility_changed):
		UIManager.navigation_focus_visibility_changed.connect(_on_navigation_focus_visibility_changed)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh_texts()
	call_deferred("_grab_button_focus", _start_button)


func _exit_tree() -> void:
	if UIManager.navigation_focus_visibility_changed.is_connected(_on_navigation_focus_visibility_changed):
		UIManager.navigation_focus_visibility_changed.disconnect(_on_navigation_focus_visibility_changed)
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure(can_continue: bool, notice_key: String = "") -> void:
	_notice_key = notice_key
	if _continue_button == null:
		return
	_continue_button.visible = can_continue
	_continue_button.disabled = not can_continue
	if _notice_label == null:
		return
	_notice_label.visible = not _notice_key.is_empty()
	if _notice_label.visible:
		_notice_label.text = tr(_notice_key)
	else:
		_notice_label.text = ""


func refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_title_name")
	if _subtitle_label != null:
		_subtitle_label.text = tr("ui_title_subtitle")
	if _continue_button != null:
		_continue_button.text = tr("ui_continue_run")
	if _start_button != null:
		_start_button.text = tr("ui_start")
	if _settings_button != null:
		_settings_button.text = tr("ui_settings")
	if _gear_mod_button != null:
		_gear_mod_button.text = tr("ui_gear_mod_title_entry")
	if _quit_button != null:
		_quit_button.text = tr("ui_quit")
	if _notice_label != null and _notice_label.visible and not _notice_key.is_empty():
		_notice_label.text = tr(_notice_key)


func _grab_button_focus(button: Button) -> void:
	if is_instance_valid(button) and button.is_inside_tree():
		UIManager.grab_focus_for_navigation(button)


func _on_start_pressed() -> void:
	start_requested.emit()


func _on_continue_pressed() -> void:
	continue_requested.emit()


func _on_gear_mod_pressed() -> void:
	gear_mod_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _on_navigation_focus_visibility_changed(visible: bool) -> void:
	if visible and UIManager.stack_size() == 0:
		UIManager.grab_focus_for_navigation(_start_button)


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()
