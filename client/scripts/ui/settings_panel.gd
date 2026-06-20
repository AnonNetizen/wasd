# Doc: docs/代码/settings.md
# Authority: docs/AI协作/工作包/F7-SettingsLocalizationUI.md
class_name SettingsPanel
extends CanvasLayer


signal closed_requested()

const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")

const LOCALE_OPTIONS: Array[String] = ["zh_CN", "en"]
const AIM_MODE_OPTIONS: Array[String] = ["mouse", "4dir", "auto"]
const INPUT_BINDING_ROWS: Array[Dictionary] = [
	{
		"key": SETTINGS_KEYS.INPUT_MOVE_UP,
		"label_key": "ui_settings_input_move_up",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/MoveUpBindingBox/MoveUpBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/MoveUpBindingBox/MoveUpBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_MOVE_DOWN,
		"label_key": "ui_settings_input_move_down",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/MoveDownBindingBox/MoveDownBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/MoveDownBindingBox/MoveDownBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_MOVE_LEFT,
		"label_key": "ui_settings_input_move_left",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/MoveLeftBindingBox/MoveLeftBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/MoveLeftBindingBox/MoveLeftBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_MOVE_RIGHT,
		"label_key": "ui_settings_input_move_right",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/MoveRightBindingBox/MoveRightBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/MoveRightBindingBox/MoveRightBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_AIM_UP,
		"label_key": "ui_settings_input_aim_up",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/AimUpBindingBox/AimUpBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/AimUpBindingBox/AimUpBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_AIM_DOWN,
		"label_key": "ui_settings_input_aim_down",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/AimDownBindingBox/AimDownBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/AimDownBindingBox/AimDownBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_AIM_LEFT,
		"label_key": "ui_settings_input_aim_left",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/AimLeftBindingBox/AimLeftBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/AimLeftBindingBox/AimLeftBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_AIM_RIGHT,
		"label_key": "ui_settings_input_aim_right",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/AimRightBindingBox/AimRightBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/AimRightBindingBox/AimRightBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_USE_ACTIVE_ITEM,
		"label_key": "ui_settings_input_use_active_item",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/UseActiveItemBindingBox/UseActiveItemBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/UseActiveItemBindingBox/UseActiveItemBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_PAUSE,
		"label_key": "ui_settings_input_pause",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/PauseBindingBox/PauseBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/PauseBindingBox/PauseBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_UI_CONFIRM,
		"label_key": "ui_settings_input_ui_confirm",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/UiConfirmBindingBox/UiConfirmBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/UiConfirmBindingBox/UiConfirmBindingOption",
	},
	{
		"key": SETTINGS_KEYS.INPUT_UI_BACK,
		"label_key": "ui_settings_input_ui_back",
		"label_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/UiBackBindingBox/UiBackBindingLabel",
		"option_path": "Root/Center/Panel/Margin/Layout/InputBindingsGrid/UiBackBindingBox/UiBackBindingOption",
	},
]

var _aim_mode_option: OptionButton = null
var _analytics_check: CheckButton = null
var _close_button: Button = null
var _closing: bool = false
var _fire_on_release_check: CheckButton = null
var _fullscreen_check: CheckButton = null
var _input_feedback_label: Label = null
var _input_binding_options: Dictionary = {}
var _locale_option: OptionButton = null
var _master_slider: HSlider = null
var _master_value_label: Label = null
var _music_slider: HSlider = null
var _music_value_label: Label = null
var _pause_on_focus_loss_check: CheckButton = null
var _pressed_close: bool = false
var _record_replays_check: CheckButton = null
var _refreshing: bool = false
var _reset_input_bindings_button: Button = null
var _screen_shake_check: CheckButton = null
var _sfx_slider: HSlider = null
var _sfx_value_label: Label = null
var _vsync_check: CheckButton = null


func _input(event: InputEvent) -> void:
	if UIManager.top() != self:
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var close_hit: bool = _button_contains_position(_close_button, mouse_button.position)
	if mouse_button.pressed:
		_pressed_close = close_hit
		if close_hit:
			get_viewport().set_input_as_handled()
		return

	var was_pressed_close: bool = _pressed_close
	_pressed_close = false
	if was_pressed_close and close_hit:
		get_viewport().set_input_as_handled()
		_on_close_pressed()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_nodes()
	if _missing_required_nodes():
		push_error("[SettingsPanel] missing required scene nodes")
		return
	_connect_controls()
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh()
	call_deferred("_grab_initial_focus")


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func refresh() -> void:
	_refreshing = true
	_refresh_texts()
	_refresh_values()
	_refreshing = false


func request_close() -> void:
	_on_close_pressed()


func _bind_nodes() -> void:
	_input_binding_options.clear()
	_locale_option = get_node_or_null("Root/Center/Panel/Margin/Layout/LanguageRow/LocaleOption") as OptionButton
	_master_slider = get_node_or_null("Root/Center/Panel/Margin/Layout/MasterVolumeRow/MasterVolumeSlider") as HSlider
	_master_value_label = get_node_or_null("Root/Center/Panel/Margin/Layout/MasterVolumeRow/MasterVolumeValueLabel") as Label
	_music_slider = get_node_or_null("Root/Center/Panel/Margin/Layout/MusicVolumeRow/MusicVolumeSlider") as HSlider
	_music_value_label = get_node_or_null("Root/Center/Panel/Margin/Layout/MusicVolumeRow/MusicVolumeValueLabel") as Label
	_sfx_slider = get_node_or_null("Root/Center/Panel/Margin/Layout/SfxVolumeRow/SfxVolumeSlider") as HSlider
	_sfx_value_label = get_node_or_null("Root/Center/Panel/Margin/Layout/SfxVolumeRow/SfxVolumeValueLabel") as Label
	_fullscreen_check = get_node_or_null("Root/Center/Panel/Margin/Layout/FullscreenCheck") as CheckButton
	_vsync_check = get_node_or_null("Root/Center/Panel/Margin/Layout/VsyncCheck") as CheckButton
	_fire_on_release_check = get_node_or_null("Root/Center/Panel/Margin/Layout/FireOnReleaseCheck") as CheckButton
	_aim_mode_option = get_node_or_null("Root/Center/Panel/Margin/Layout/AimModeRow/AimModeOption") as OptionButton
	_screen_shake_check = get_node_or_null("Root/Center/Panel/Margin/Layout/ScreenShakeCheck") as CheckButton
	_pause_on_focus_loss_check = get_node_or_null("Root/Center/Panel/Margin/Layout/PauseOnFocusLossCheck") as CheckButton
	_record_replays_check = get_node_or_null("Root/Center/Panel/Margin/Layout/RecordReplaysCheck") as CheckButton
	_input_feedback_label = get_node_or_null("Root/Center/Panel/Margin/Layout/InputFeedbackLabel") as Label
	_reset_input_bindings_button = get_node_or_null("Root/Center/Panel/Margin/Layout/ResetInputBindingsButton") as Button
	_analytics_check = get_node_or_null("Root/Center/Panel/Margin/Layout/AnalyticsCheck") as CheckButton
	_close_button = get_node_or_null("Root/Center/Panel/Margin/Layout/CloseButton") as Button
	for row: Dictionary in INPUT_BINDING_ROWS:
		var key: String = String(row["key"])
		_input_binding_options[key] = get_node_or_null(String(row["option_path"])) as OptionButton


func _missing_required_nodes() -> bool:
	return (
		_locale_option == null
		or _master_slider == null
		or _master_value_label == null
		or _music_slider == null
		or _music_value_label == null
		or _sfx_slider == null
		or _sfx_value_label == null
		or _fullscreen_check == null
		or _vsync_check == null
		or _fire_on_release_check == null
		or _aim_mode_option == null
		or _screen_shake_check == null
		or _pause_on_focus_loss_check == null
		or _record_replays_check == null
		or _input_feedback_label == null
		or _reset_input_bindings_button == null
		or _has_missing_input_binding_options()
		or _analytics_check == null
		or _close_button == null
	)


func _has_missing_input_binding_options() -> bool:
	for row: Dictionary in INPUT_BINDING_ROWS:
		if _input_binding_options.get(String(row["key"])) == null:
			return true
	return false


func _connect_controls() -> void:
	_configure_slider(_master_slider)
	_configure_slider(_music_slider)
	_configure_slider(_sfx_slider)

	_locale_option.item_selected.connect(_on_locale_selected)
	_master_slider.value_changed.connect(_on_master_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_vsync_check.toggled.connect(_on_vsync_toggled)
	_fire_on_release_check.toggled.connect(_on_fire_on_release_toggled)
	_aim_mode_option.item_selected.connect(_on_aim_mode_selected)
	_screen_shake_check.toggled.connect(_on_screen_shake_toggled)
	_pause_on_focus_loss_check.toggled.connect(_on_pause_on_focus_loss_toggled)
	_record_replays_check.toggled.connect(_on_record_replays_toggled)
	for row: Dictionary in INPUT_BINDING_ROWS:
		var key: String = String(row["key"])
		var option: OptionButton = _input_binding_options[key] as OptionButton
		option.item_selected.connect(_on_input_binding_selected.bind(key))
	_reset_input_bindings_button.pressed.connect(_on_reset_input_bindings_pressed)
	_analytics_check.toggled.connect(_on_analytics_toggled)
	_close_button.pressed.connect(_on_close_pressed)


func _configure_slider(slider: HSlider) -> void:
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05


func _refresh_texts() -> void:
	_set_label_text("Root/Center/Panel/Margin/Layout/TitleLabel", "ui_settings_title")
	_set_label_text("Root/Center/Panel/Margin/Layout/AudioSectionLabel", "ui_settings_audio")
	_set_label_text("Root/Center/Panel/Margin/Layout/VideoSectionLabel", "ui_settings_video")
	_set_label_text("Root/Center/Panel/Margin/Layout/GameplaySectionLabel", "ui_settings_gameplay")
	_set_label_text("Root/Center/Panel/Margin/Layout/InputSectionLabel", "ui_settings_input")
	_set_label_text("Root/Center/Panel/Margin/Layout/PrivacySectionLabel", "ui_settings_privacy")
	_set_label_text("Root/Center/Panel/Margin/Layout/LanguageRow/LocaleLabel", "ui_settings_language")
	_set_label_text("Root/Center/Panel/Margin/Layout/MasterVolumeRow/MasterVolumeLabel", "ui_settings_master_volume")
	_set_label_text("Root/Center/Panel/Margin/Layout/MusicVolumeRow/MusicVolumeLabel", "ui_settings_music_volume")
	_set_label_text("Root/Center/Panel/Margin/Layout/SfxVolumeRow/SfxVolumeLabel", "ui_settings_sfx_volume")
	_set_label_text("Root/Center/Panel/Margin/Layout/AimModeRow/AimModeLabel", "ui_settings_aim_mode")

	_fullscreen_check.text = tr("ui_settings_fullscreen")
	_vsync_check.text = tr("ui_settings_vsync")
	_fire_on_release_check.text = tr("ui_settings_fire_on_release")
	_screen_shake_check.text = tr("ui_settings_screen_shake")
	_pause_on_focus_loss_check.text = tr("ui_settings_pause_on_focus_loss")
	_record_replays_check.text = tr("ui_settings_record_replays")
	_reset_input_bindings_button.text = tr("ui_settings_input_restore_defaults")
	_analytics_check.text = tr("ui_settings_analytics_enabled")
	_close_button.text = tr("ui_cancel")
	_input_feedback_label.text = tr("ui_settings_input_feedback_ready")

	_replace_options(_locale_option, [
		tr("ui_settings_language_zh_cn"),
		tr("ui_settings_language_en"),
	])
	_replace_options(_aim_mode_option, [
		tr("ui_settings_aim_mode_mouse"),
		tr("ui_settings_aim_mode_4dir"),
		tr("ui_settings_aim_mode_auto"),
	])
	var input_options: Array[String] = Settings.input_binding_options()
	for row: Dictionary in INPUT_BINDING_ROWS:
		_set_label_text(String(row["label_path"]), String(row["label_key"]))
		var option: OptionButton = _input_binding_options[String(row["key"])] as OptionButton
		_replace_options(option, input_options)


func _set_label_text(path: String, key: String) -> void:
	var label: Label = get_node_or_null(path) as Label
	if label != null:
		label.text = tr(key)


func _replace_options(option: OptionButton, labels: Array[String]) -> void:
	var selected_id: int = option.selected
	option.clear()
	for label: String in labels:
		option.add_item(label)
	if selected_id >= 0 and selected_id < labels.size():
		option.select(selected_id)


func _refresh_values() -> void:
	_select_option_value(_locale_option, LOCALE_OPTIONS, String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE, "zh_CN")))
	_set_slider_value(_master_slider, _master_value_label, float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER, 1.0)))
	_set_slider_value(_music_slider, _music_value_label, float(Settings.get_value(SETTINGS_KEYS.AUDIO_MUSIC, 0.8)))
	_set_slider_value(_sfx_slider, _sfx_value_label, float(Settings.get_value(SETTINGS_KEYS.AUDIO_SFX, 0.9)))
	_fullscreen_check.button_pressed = bool(Settings.get_value(SETTINGS_KEYS.VIDEO_FULLSCREEN, false))
	_vsync_check.button_pressed = bool(Settings.get_value(SETTINGS_KEYS.VIDEO_VSYNC, true))
	_fire_on_release_check.button_pressed = bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_FIRE_ON_RELEASE, false))
	_select_option_value(_aim_mode_option, AIM_MODE_OPTIONS, String(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_AIM_MODE, "mouse")))
	_screen_shake_check.button_pressed = bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true))
	_pause_on_focus_loss_check.button_pressed = bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_PAUSE_ON_FOCUS_LOSS, true))
	_record_replays_check.button_pressed = bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS, true))
	var input_options: Array[String] = Settings.input_binding_options()
	for row: Dictionary in INPUT_BINDING_ROWS:
		var key: String = String(row["key"])
		var option: OptionButton = _input_binding_options[key] as OptionButton
		_select_option_value(option, input_options, String(Settings.get_value(key, "")))
	_analytics_check.button_pressed = bool(Settings.get_value(SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED, true))


func _select_option_value(option: OptionButton, options: Array[String], value: String) -> void:
	var option_index: int = options.find(value)
	if option_index < 0:
		option_index = 0
	option.select(option_index)


func _set_slider_value(slider: HSlider, label: Label, value: float) -> void:
	slider.value = value
	_set_percent_label(label, value)


func _set_percent_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))


func _set_setting(key: String, value: Variant) -> void:
	if _refreshing:
		return
	if Settings.set_value(key, value):
		_refreshing = true
		_refresh_values()
		_refreshing = false


func _on_locale_selected(index: int) -> void:
	if index < 0 or index >= LOCALE_OPTIONS.size():
		return
	_set_setting(SETTINGS_KEYS.GENERAL_LOCALE, LOCALE_OPTIONS[index])


func _on_master_volume_changed(value: float) -> void:
	_set_percent_label(_master_value_label, value)
	_set_setting(SETTINGS_KEYS.AUDIO_MASTER, value)


func _on_music_volume_changed(value: float) -> void:
	_set_percent_label(_music_value_label, value)
	_set_setting(SETTINGS_KEYS.AUDIO_MUSIC, value)


func _on_sfx_volume_changed(value: float) -> void:
	_set_percent_label(_sfx_value_label, value)
	_set_setting(SETTINGS_KEYS.AUDIO_SFX, value)


func _on_fullscreen_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.VIDEO_FULLSCREEN, enabled)


func _on_vsync_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.VIDEO_VSYNC, enabled)


func _on_fire_on_release_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.GAMEPLAY_FIRE_ON_RELEASE, enabled)


func _on_aim_mode_selected(index: int) -> void:
	if index < 0 or index >= AIM_MODE_OPTIONS.size():
		return
	_set_setting(SETTINGS_KEYS.GAMEPLAY_AIM_MODE, AIM_MODE_OPTIONS[index])


func _on_screen_shake_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, enabled)


func _on_pause_on_focus_loss_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.GAMEPLAY_PAUSE_ON_FOCUS_LOSS, enabled)


func _on_record_replays_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS, enabled)


func _on_input_binding_selected(index: int, key: String) -> void:
	var input_options: Array[String] = Settings.input_binding_options()
	if index < 0 or index >= input_options.size():
		return
	var binding: String = input_options[index]
	var changed: bool = _set_setting_with_result(key, binding)
	if changed:
		_show_input_binding_feedback(key, binding)
		return
	_refreshing = true
	_refresh_values()
	_refreshing = false
	_show_input_binding_feedback(key, binding)


func _on_reset_input_bindings_pressed() -> void:
	Settings.reset_input_bindings_to_defaults(true)
	_refreshing = true
	_refresh_values()
	_refreshing = false
	_input_feedback_label.text = tr("ui_settings_input_feedback_restored")


func _on_analytics_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED, enabled)


func _on_locale_changed(_locale: String) -> void:
	refresh()


func _on_close_pressed() -> void:
	if _closing:
		return
	_closing = true
	closed_requested.emit()
	if UIManager.top() == self:
		UIManager.pop()


func _set_setting_with_result(key: String, value: Variant) -> bool:
	if _refreshing:
		return false
	if Settings.set_value(key, value):
		_refreshing = true
		_refresh_values()
		_refreshing = false
		return true
	return false


func _show_input_binding_feedback(key: String, binding: String) -> void:
	var conflict_key: String = _first_conflicting_input_key(key, binding)
	if conflict_key.is_empty():
		_input_feedback_label.text = tr("ui_settings_input_feedback_saved").format({
			"action": _input_label_for_key(key),
			"binding": binding,
		})
		return

	_input_feedback_label.text = tr("ui_settings_input_feedback_shared").format({
		"action": _input_label_for_key(key),
		"binding": binding,
		"other": _input_label_for_key(conflict_key),
	})


func _first_conflicting_input_key(key: String, binding: String) -> String:
	for row: Dictionary in INPUT_BINDING_ROWS:
		var other_key: String = String(row["key"])
		if other_key == key:
			continue
		if String(Settings.get_value(other_key, "")) == binding:
			return other_key
	return ""


func _input_label_for_key(key: String) -> String:
	for row: Dictionary in INPUT_BINDING_ROWS:
		if String(row["key"]) == key:
			return tr(String(row["label_key"]))
	return key


func _button_contains_position(button: Button, position: Vector2) -> bool:
	return (
		is_instance_valid(button)
		and button.visible
		and not button.disabled
		and button.get_global_rect().has_point(position)
	)


func _grab_initial_focus() -> void:
	if is_instance_valid(_locale_option) and _locale_option.is_inside_tree():
		_locale_option.grab_focus()
