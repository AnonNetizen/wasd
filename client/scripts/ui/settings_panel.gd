# Doc: docs/代码/settings.md
# Doc: docs/代码/input_service.md
# Authority: docs/决策记录.md ADR #151
class_name SettingsPanel
extends CanvasLayer


signal closed_requested()

const INPUT_BINDING_ROW_SCENE: PackedScene = preload("res://scenes/ui/input_binding_row.tscn")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")

const LOCALE_OPTIONS: Array[String] = ["zh_CN", "en"]
const AIM_MODE_OPTIONS: Array[String] = ["mouse", "4dir", "auto"]

var _aim_mode_option: OptionButton = null
var _active_remap_device_group: StringName = &""
var _analytics_check: CheckButton = null
var _close_button: Button = null
var _closing: bool = false
var _conflict_dialog_open: bool = false
var _fire_on_release_check: CheckButton = null
var _fullscreen_check: CheckButton = null
var _input_binding_buttons: Dictionary = {}
var _input_binding_labels: Dictionary = {}
var _input_bindings_grid: GridContainer = null
var _input_feedback_label: Label = null
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
	_rebuild_input_binding_grid()
	_connect_controls()
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	if not InputService.bindings_changed.is_connected(_on_bindings_changed):
		InputService.bindings_changed.connect(_on_bindings_changed)
	if not InputService.device_family_changed.is_connected(_on_device_family_changed):
		InputService.device_family_changed.connect(_on_device_family_changed)
	if not InputService.remap_started.is_connected(_on_remap_started):
		InputService.remap_started.connect(_on_remap_started)
	if not InputService.remap_conflict.is_connected(_on_remap_conflict):
		InputService.remap_conflict.connect(_on_remap_conflict)
	if not InputService.remap_finished.is_connected(_on_remap_finished):
		InputService.remap_finished.connect(_on_remap_finished)
	refresh()
	call_deferred("_grab_initial_focus")


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)
	if InputService.bindings_changed.is_connected(_on_bindings_changed):
		InputService.bindings_changed.disconnect(_on_bindings_changed)
	if InputService.device_family_changed.is_connected(_on_device_family_changed):
		InputService.device_family_changed.disconnect(_on_device_family_changed)
	if InputService.remap_started.is_connected(_on_remap_started):
		InputService.remap_started.disconnect(_on_remap_started)
	if InputService.remap_conflict.is_connected(_on_remap_conflict):
		InputService.remap_conflict.disconnect(_on_remap_conflict)
	if InputService.remap_finished.is_connected(_on_remap_finished):
		InputService.remap_finished.disconnect(_on_remap_finished)
	InputService.cancel_remap()


func refresh() -> void:
	_refreshing = true
	_refresh_texts()
	_refresh_values()
	_refreshing = false


func request_close() -> void:
	_on_close_pressed()


func grab_default_focus() -> void:
	_grab_initial_focus()


func _bind_nodes() -> void:
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
	_input_bindings_grid = get_node_or_null("Root/Center/Panel/Margin/Layout/InputBindingsGrid") as GridContainer
	_reset_input_bindings_button = get_node_or_null("Root/Center/Panel/Margin/Layout/ResetInputBindingsButton") as Button
	_analytics_check = get_node_or_null("Root/Center/Panel/Margin/Layout/AnalyticsCheck") as CheckButton
	_close_button = get_node_or_null("Root/Center/Panel/Margin/Layout/CloseButton") as Button


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
		or _input_bindings_grid == null
		or _reset_input_bindings_button == null
		or _analytics_check == null
		or _close_button == null
	)


func _rebuild_input_binding_grid() -> void:
	for child: Node in _input_bindings_grid.get_children():
		child.free()
	_input_binding_buttons.clear()
	_input_binding_labels.clear()
	_input_bindings_grid.columns = 4
	for row: Dictionary in InputService.binding_rows():
		var binding_id: StringName = StringName(row.get("id", &""))
		var box: VBoxContainer = INPUT_BINDING_ROW_SCENE.instantiate() as VBoxContainer
		if box == null:
			push_error("[SettingsPanel] failed to instantiate input binding row template")
			continue
		box.name = "%sBindingRow" % String(binding_id).to_pascal_case()
		var label: Label = box.get_node_or_null("BindingLabel") as Label
		var keyboard_button: Button = box.get_node_or_null("Buttons/KeyboardMouseButton") as Button
		var gamepad_button: Button = box.get_node_or_null("Buttons/GamepadButton") as Button
		if label == null or keyboard_button == null or gamepad_button == null:
			box.queue_free()
			push_error("[SettingsPanel] input binding row template is incomplete")
			continue
		_input_binding_labels[binding_id] = label
		_configure_binding_button(keyboard_button, binding_id, InputService.DEVICE_KEYBOARD_MOUSE, bool(row.get("keyboard_available", false)))
		_configure_binding_button(gamepad_button, binding_id, InputService.DEVICE_GAMEPAD, bool(row.get("gamepad_available", false)))
		_input_bindings_grid.add_child(box)


func _configure_binding_button(button: Button, binding_id: StringName, device_group: StringName, available: bool) -> void:
	button.visible = available
	if not available:
		return
	button.pressed.connect(_on_binding_button_pressed.bind(binding_id, device_group))
	_input_binding_buttons[_binding_button_key(binding_id, device_group)] = button


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
	_replace_options(_locale_option, [tr("ui_settings_language_zh_cn"), tr("ui_settings_language_en")])
	_replace_options(_aim_mode_option, [
		tr("ui_settings_aim_mode_mouse"),
		tr("ui_settings_aim_mode_4dir"),
		tr("ui_settings_aim_mode_auto"),
	])
	for row: Dictionary in InputService.binding_rows():
		var binding_id: StringName = StringName(row.get("id", &""))
		var label: Label = _input_binding_labels.get(binding_id) as Label
		if label != null:
			label.text = tr(String(row.get("label_key", "")))


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
	_analytics_check.button_pressed = bool(Settings.get_value(SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED, true))
	for row: Dictionary in InputService.binding_rows():
		var binding_id: StringName = StringName(row.get("id", &""))
		_refresh_binding_button(binding_id, InputService.DEVICE_KEYBOARD_MOUSE)
		_refresh_binding_button(binding_id, InputService.DEVICE_GAMEPAD)


func _refresh_binding_button(binding_id: StringName, device_group: StringName) -> void:
	var button: Button = _input_binding_buttons.get(_binding_button_key(binding_id, device_group)) as Button
	if button == null:
		return
	var prefix: String = tr("ui_settings_input_keyboard") if device_group == InputService.DEVICE_KEYBOARD_MOUSE else tr("ui_settings_input_gamepad")
	var binding: String = InputService.binding_text(binding_id, device_group)
	button.text = binding
	button.tooltip_text = "%s: %s" % [prefix, binding]


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


func _select_option_value(option: OptionButton, options: Array[String], value: String) -> void:
	option.select(maxi(0, options.find(value)))


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
	if index >= 0 and index < LOCALE_OPTIONS.size():
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
	if index >= 0 and index < AIM_MODE_OPTIONS.size():
		_set_setting(SETTINGS_KEYS.GAMEPLAY_AIM_MODE, AIM_MODE_OPTIONS[index])


func _on_screen_shake_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, enabled)


func _on_pause_on_focus_loss_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.GAMEPLAY_PAUSE_ON_FOCUS_LOSS, enabled)


func _on_record_replays_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS, enabled)


func _on_analytics_toggled(enabled: bool) -> void:
	_set_setting(SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED, enabled)


func _on_binding_button_pressed(binding_id: StringName, device_group: StringName) -> void:
	if InputService.begin_remap(binding_id, device_group):
		_input_feedback_label.text = tr("ui_settings_input_feedback_capturing")


func _on_reset_input_bindings_pressed() -> void:
	InputService.reset_bindings_to_defaults()
	refresh()
	_input_feedback_label.text = tr("ui_settings_input_feedback_restored")


func _on_bindings_changed() -> void:
	refresh()


func _on_device_family_changed(_device_family: StringName) -> void:
	_refresh_values()


func _on_remap_started(_binding_id: StringName, device_group: StringName) -> void:
	_active_remap_device_group = device_group
	_set_binding_buttons_disabled(true)


func _on_remap_conflict(binding_id: StringName, conflicts: Array[StringName]) -> void:
	var other_names: PackedStringArray = []
	for conflict_id: StringName in conflicts:
		other_names.append(_binding_label(conflict_id))
	var body: String = tr("ui_settings_input_conflict_body").format({
		"action": _binding_label(binding_id),
		"other": ", ".join(other_names),
	})
	_conflict_dialog_open = UIManager.show_confirmation(
		tr("ui_settings_input_conflict_title"),
		body,
		tr("ui_settings_input_conflict_replace"),
		tr("ui_cancel"),
		_on_conflict_replace,
		_on_conflict_cancel
	)
	if not _conflict_dialog_open:
		InputService.resolve_pending_remap(false)


func _on_remap_finished(binding_id: StringName, applied: bool) -> void:
	_set_binding_buttons_disabled(false)
	refresh()
	if applied:
		_input_feedback_label.text = tr("ui_settings_input_feedback_saved").format({
			"action": _binding_label(binding_id),
			"binding": InputService.binding_text(binding_id, _active_remap_device_group),
		})
	else:
		_input_feedback_label.text = tr("ui_settings_input_feedback_cancelled")
	_active_remap_device_group = &""


func _on_conflict_replace() -> void:
	_conflict_dialog_open = false
	InputService.resolve_pending_remap(true)


func _on_conflict_cancel() -> void:
	_conflict_dialog_open = false
	InputService.resolve_pending_remap(false)


func _set_binding_buttons_disabled(disabled: bool) -> void:
	for raw_button: Variant in _input_binding_buttons.values():
		var button: Button = raw_button as Button
		if button != null:
			button.disabled = disabled


func _binding_label(binding_id: StringName) -> String:
	for row: Dictionary in InputService.binding_rows():
		if StringName(row.get("id", &"")) == binding_id:
			return tr(String(row.get("label_key", "")))
	return String(binding_id)


func _binding_button_key(binding_id: StringName, device_group: StringName) -> String:
	return "%s|%s" % [String(binding_id), String(device_group)]


func _on_locale_changed(_locale: String) -> void:
	refresh()


func _on_close_pressed() -> void:
	if _closing:
		return
	if _conflict_dialog_open:
		UIManager.cancel_confirmation()
		return
	InputService.cancel_remap()
	_closing = true
	closed_requested.emit()
	if UIManager.top() == self:
		UIManager.pop()


func _button_contains_position(button: Button, position: Vector2) -> bool:
	return (
		is_instance_valid(button)
		and button.visible
		and not button.disabled
		and button.get_global_rect().has_point(position)
	)


func _grab_initial_focus() -> void:
	if is_instance_valid(_locale_option) and _locale_option.is_inside_tree():
		UIManager.grab_focus_for_navigation(_locale_option)
