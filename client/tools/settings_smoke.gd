extends Node


const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const GAME_OVER_PANEL_SCENE := preload("res://scenes/ui/game_over_panel.tscn")
const GAMEPLAY_HUD_SCENE := preload("res://scenes/gameplay/gameplay_hud.tscn")
const LEVEL_UP_PANEL_SCENE := preload("res://scenes/ui/level_up_panel.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const TITLE_MENU_SCENE := preload("res://scenes/ui/title_menu.tscn")

const BOOT_FRAMES: int = 3
const BUTTON_TEXT_EXTRA_PADDING: float = 6.0
const ENGLISH_UI_FIT_TOLERANCE: float = 2.0

var _failures: Array[String] = []
var _original_exists: bool = false
var _original_text: String = ""
var _original_binding_files: Dictionary = {}
var _settings_panel_closed_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_capture_original_config()
	_capture_original_binding_files()

	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame

	_expect_missing_file_uses_defaults()
	_expect_roundtrip_and_signal_flow()
	_expect_invalid_values_are_rejected()
	_expect_legacy_input_bindings_migrate_to_v2()
	_expect_input_bindings_use_independent_resource()
	_expect_invalid_saved_values_recover_to_defaults()
	_expect_broken_config_recovers_to_defaults()
	await _expect_settings_panel_controls()
	await _expect_menu_settings_entries()
	await _expect_runtime_locale_refresh()

	_restore_original_config()
	_restore_original_binding_files()
	_finish()


func _expect_missing_file_uses_defaults() -> void:
	_remove_settings_file()
	Settings.reset_to_defaults(false)
	var loaded_cleanly: bool = Settings.load_from_disk()
	_expect(loaded_cleanly, "missing settings file should load as defaults without recovery")
	_expect(not Settings.last_load_recovered(), "missing settings file should not be marked as recovered")
	_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == "zh_CN", "default locale should be zh_CN")
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), 1.0), "default master volume should be 1.0")


func _expect_roundtrip_and_signal_flow() -> void:
	var changed_keys: Array[String] = []
	var change_handler := _on_setting_changed.bind(changed_keys)
	if not Settings.setting_changed.is_connected(change_handler):
		Settings.setting_changed.connect(change_handler)

	_expect(Settings.set_value(SETTINGS_KEYS.AUDIO_MASTER, 0.42), "master volume should accept a valid float")
	_expect(Settings.set_value(SETTINGS_KEYS.GENERAL_LOCALE, "en"), "locale should accept en")
	_expect(FileAccess.file_exists(Settings.settings_path()), "settings.cfg should be created after valid changes")
	_expect(changed_keys.has(SETTINGS_KEYS.AUDIO_MASTER), "master volume change should emit setting_changed")
	_expect(changed_keys.has(SETTINGS_KEYS.GENERAL_LOCALE), "locale change should emit setting_changed")
	_expect(Localization.current_locale() == "en", "Localization should follow Settings.general.locale")

	Settings.reset_to_defaults(false)
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), 1.0), "reset should restore in-memory default")
	var loaded_cleanly: bool = Settings.load_from_disk()
	_expect(loaded_cleanly, "saved valid settings should load cleanly")
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), 0.42), "master volume should roundtrip from disk")
	_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == "en", "locale should roundtrip from disk")


func _expect_invalid_values_are_rejected() -> void:
	var original_master: float = float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER))
	var original_locale: String = String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE))
	_expect(not Settings.set_value(SETTINGS_KEYS.AUDIO_MASTER, 2.0), "master volume should reject values above 1.0")
	_expect(not Settings.set_value(SETTINGS_KEYS.GENERAL_LOCALE, "pirate"), "locale should reject unsupported values")
	_expect(not Settings.set_value(SETTINGS_KEYS.INPUT_PAUSE, "P"), "legacy input keys should be read-only after settings v2")
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), original_master), "invalid master volume should not mutate state")
	_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == original_locale, "invalid locale should not mutate state")
	_expect(Settings.get_value(SETTINGS_KEYS.INPUT_PAUSE, null) == null, "settings v2 should not retain deprecated input values")


func _expect_legacy_input_bindings_migrate_to_v2() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("settings", SETTINGS_KEYS.GENERAL_LOCALE, "en")
	config.set_value("settings", SETTINGS_KEYS.INPUT_PAUSE, "P")
	config.set_value("settings", SETTINGS_KEYS.INPUT_INTERACT, "F")
	_expect(config.save(Settings.settings_path()) == OK, "smoke should write legacy settings v1 fixture")
	_expect(Settings.load_from_disk(), "valid settings v1 should migrate cleanly")
	var legacy_bindings: Dictionary = Settings.take_legacy_input_bindings()
	_expect(String(legacy_bindings.get(SETTINGS_KEYS.INPUT_PAUSE, "")) == "P", "settings v1 should expose legacy pause binding once")
	_expect(String(legacy_bindings.get(SETTINGS_KEYS.INPUT_INTERACT, "")) == "F", "settings v1 should expose legacy interact binding once")
	_expect(Settings.take_legacy_input_bindings().is_empty(), "legacy binding migration payload should be one-shot")
	var migrated := ConfigFile.new()
	_expect(migrated.load(Settings.settings_path()) == OK, "migrated settings v2 should be readable")
	_expect(int(migrated.get_value("meta", "version", 0)) == 2, "settings migration should rewrite config as v2")
	_expect(not migrated.has_section_key("settings", SETTINGS_KEYS.INPUT_PAUSE), "settings v2 should not persist GUIDE bindings")
	_expect(not migrated.has_section_key("settings", SETTINGS_KEYS.INPUT_INTERACT), "settings v2 should remove legacy input keys")


func _expect_input_bindings_use_independent_resource() -> void:
	_expect(InputService.reset_bindings_to_defaults(), "resetting GUIDE bindings should save the independent resource")
	_expect(FileAccess.file_exists(InputService.bindings_path()), "input bindings should persist outside settings.cfg")
	var loaded: Resource = ResourceLoader.load(InputService.bindings_path(), "GUIDERemappingConfig", ResourceLoader.CACHE_MODE_IGNORE)
	var remapping_config: GUIDERemappingConfig = loaded as GUIDERemappingConfig
	_expect(remapping_config != null, "input binding resource should load as GUIDERemappingConfig")
	if remapping_config != null:
		_expect(int(remapping_config.custom_data.get("schema_version", 0)) == 1, "input binding resource should declare project schema v1")
	var settings_config := ConfigFile.new()
	_expect(settings_config.load(Settings.settings_path()) == OK, "settings.cfg should remain readable after GUIDE binding save")
	_expect(not settings_config.has_section_key("settings", SETTINGS_KEYS.INPUT_PAUSE), "GUIDE binding save should not write legacy input keys into settings.cfg")


func _expect_invalid_saved_values_recover_to_defaults() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("settings", SETTINGS_KEYS.GENERAL_LOCALE, "pirate")
	config.set_value("settings", SETTINGS_KEYS.AUDIO_MASTER, 2.0)
	config.set_value("settings", SETTINGS_KEYS.AUDIO_SFX, 0.25)
	config.set_value("settings", SETTINGS_KEYS.VIDEO_FULLSCREEN, "yes")
	_expect(config.save(Settings.settings_path()) == OK, "smoke should write invalid settings fixture")

	Settings.reset_to_defaults(false)
	var loaded_cleanly: bool = Settings.load_from_disk()
	_expect(not loaded_cleanly, "invalid saved values should report recovery")
	_expect(Settings.last_load_recovered(), "invalid saved values should mark load as recovered")
	_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == "zh_CN", "invalid saved locale should fall back to default")
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), 1.0), "invalid saved master volume should fall back to default")
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_SFX)), 0.25), "valid saved sfx volume should survive partial recovery")
	_expect(not bool(Settings.get_value(SETTINGS_KEYS.VIDEO_FULLSCREEN)), "invalid saved fullscreen should fall back to default")


func _expect_broken_config_recovers_to_defaults() -> void:
	_write_text(Settings.settings_path(), "[settings\nbroken")
	Settings.reset_to_defaults(false)
	var loaded_cleanly: bool = Settings.load_from_disk()
	_expect(not loaded_cleanly, "broken settings.cfg should report recovery")
	_expect(Settings.last_load_recovered(), "broken settings.cfg should mark load as recovered")
	_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == "zh_CN", "broken settings.cfg should restore default locale")
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), 1.0), "broken settings.cfg should restore default master volume")


func _expect_settings_panel_controls() -> void:
	Settings.reset_to_defaults(true)
	Localization.set_locale("zh_CN")
	var panel: CanvasLayer = SETTINGS_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "SettingsPanel"
	add_child(panel)
	await get_tree().process_frame

	_expect(tr("ui_settings_title") != "ui_settings_title", "settings panel title key should resolve through translations")
	var title_label: Label = _find_node_by_name(panel, "TitleLabel") as Label
	var locale_option: OptionButton = _find_node_by_name(panel, "LocaleOption") as OptionButton
	var master_slider: HSlider = _find_node_by_name(panel, "MasterVolumeSlider") as HSlider
	var master_value_label: Label = _find_node_by_name(panel, "MasterVolumeValueLabel") as Label
	var video_section_label: Label = _find_node_by_name(panel, "VideoSectionLabel") as Label
	var fullscreen_check: CheckButton = _find_node_by_name(panel, "FullscreenCheck") as CheckButton
	var vsync_check: CheckButton = _find_node_by_name(panel, "VsyncCheck") as CheckButton
	var fire_on_release_check: CheckButton = _find_node_by_name(panel, "FireOnReleaseCheck") as CheckButton
	var aim_mode_row: HBoxContainer = _find_node_by_name(panel, "AimModeRow") as HBoxContainer
	var screen_shake_check: CheckButton = _find_node_by_name(panel, "ScreenShakeCheck") as CheckButton
	var pause_on_focus_loss_check: CheckButton = _find_node_by_name(panel, "PauseOnFocusLossCheck") as CheckButton
	var record_replays_check: CheckButton = _find_node_by_name(panel, "RecordReplaysCheck") as CheckButton
	var input_feedback_label: Label = _find_node_by_name(panel, "InputFeedbackLabel") as Label
	var input_bindings_grid: GridContainer = _find_node_by_name(panel, "InputBindingsGrid") as GridContainer
	var reset_input_button: Button = _find_node_by_name(panel, "ResetInputBindingsButton") as Button
	var close_button: Button = _find_node_by_name(panel, "CloseButton") as Button

	_expect(title_label != null and String(title_label.text) == tr("ui_settings_title"), "settings panel should show localized title")
	_expect(locale_option != null and locale_option.item_count == 2, "settings panel should expose two locale options")
	_expect(video_section_label != null and not video_section_label.visible, "settings panel should hide unsupported video settings")
	_expect(fullscreen_check != null and not fullscreen_check.visible, "settings panel should hide unsupported fullscreen setting")
	_expect(vsync_check != null and not vsync_check.visible, "settings panel should hide unsupported vsync setting")
	_expect(fire_on_release_check != null and not fire_on_release_check.visible, "settings panel should hide unsupported fire-on-release setting")
	_expect(aim_mode_row != null and not aim_mode_row.visible, "settings panel should hide unsupported aim mode setting")
	_expect(screen_shake_check != null and screen_shake_check.visible, "settings panel should expose wired screen shake setting")
	_expect(pause_on_focus_loss_check != null and not pause_on_focus_loss_check.visible, "settings panel should hide unsupported focus-loss pause setting")
	_expect(record_replays_check != null and record_replays_check.visible, "settings panel should still expose wired replay recording setting")
	_expect(input_bindings_grid != null and input_bindings_grid.get_child_count() == InputService.binding_rows().size(), "settings panel should expose one capture row per project binding")
	_expect(input_bindings_grid != null and _count_binding_buttons(input_bindings_grid) >= InputService.binding_rows().size(), "settings panel should expose keyboard and gamepad capture buttons")
	_expect(input_feedback_label != null and String(input_feedback_label.text) == tr("ui_settings_input_feedback_ready"), "settings panel should expose localized input feedback")
	_expect(reset_input_button != null and String(reset_input_button.text) == tr("ui_settings_input_restore_defaults"), "settings panel should expose reset input defaults button")
	_expect(master_slider != null and is_equal_approx(float(master_slider.value), 1.0), "settings panel should read master volume default")
	_expect(master_value_label != null and String(master_value_label.text) == "100%", "settings panel should show master volume percent")


	if master_slider != null:
		master_slider.value = 0.35
		await get_tree().process_frame
		_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), 0.35), "master volume slider should write Settings")
		_expect(master_value_label != null and String(master_value_label.text) == "35%", "master volume slider should refresh percent")
	if screen_shake_check != null:
		screen_shake_check.button_pressed = false
		screen_shake_check.toggled.emit(false)
		await get_tree().process_frame
		_expect(not bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE)), "screen shake control should write Settings")
		screen_shake_check.button_pressed = true
		screen_shake_check.toggled.emit(true)
		await get_tree().process_frame
		_expect(bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE)), "screen shake control should restore the enabled setting")
	if locale_option != null:
		locale_option.select(1)
		locale_option.item_selected.emit(1)
		await get_tree().process_frame
		_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == "en", "locale option should write Settings.general.locale")
		_expect(Localization.current_locale() == "en", "settings panel locale option should switch Localization")
		_expect(title_label != null and String(title_label.text) == "Settings", "settings panel should refresh existing labels after locale switch")
		_expect_english_buttons_fit(panel, "settings panel")

	if reset_input_button != null:
		reset_input_button.pressed.emit()
		await get_tree().process_frame
		_expect(FileAccess.file_exists(InputService.bindings_path()), "reset input defaults should persist GUIDE remapping config")
		_expect(InputService.binding_text(InputService.BINDING_PAUSE, InputService.DEVICE_KEYBOARD_MOUSE).contains("Escape"), "reset input defaults should restore pause fallback")
		_expect(InputService.binding_text(InputService.BINDING_INTERACT, InputService.DEVICE_KEYBOARD_MOUSE).contains("E"), "reset input defaults should restore interact binding")
		_expect(input_feedback_label != null and String(input_feedback_label.text) == "Input bindings restored to defaults.", "reset input defaults should show feedback")

	if close_button != null:
		_settings_panel_closed_count = 0
		panel.closed_requested.connect(_on_settings_panel_closed)
		close_button.pressed.emit()
		_expect(_settings_panel_closed_count == 1, "settings panel close button should emit closed_requested")

	remove_child(panel)
	panel.queue_free()
	Localization.set_locale("zh_CN")


func _expect_menu_settings_entries() -> void:
	Localization.set_locale("en")
	var title_menu: CanvasLayer = TITLE_MENU_SCENE.instantiate() as CanvasLayer
	title_menu.name = "TitleMenu"
	add_child(title_menu)
	await get_tree().process_frame
	title_menu.call("configure", false, "")
	var title_settings_button: Button = _find_node_by_name(title_menu, "SettingsButton") as Button
	_expect(title_settings_button != null and String(title_settings_button.text) == tr("ui_settings"), "title menu should expose localized settings entry")
	var title_requested: Array[bool] = [false]
	title_menu.connect("settings_requested", func() -> void:
		title_requested[0] = true
	)
	if title_settings_button != null:
		title_settings_button.pressed.emit()
	_expect(title_requested[0], "title settings button should emit settings_requested")
	_expect_english_buttons_fit(title_menu, "title menu")
	remove_child(title_menu)
	title_menu.queue_free()

	var pause_menu: CanvasLayer = PAUSE_MENU_SCENE.instantiate() as CanvasLayer
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	await get_tree().process_frame
	var pause_settings_button: Button = _find_node_by_name(pause_menu, "SettingsButton") as Button
	_expect(pause_settings_button != null and String(pause_settings_button.text) == tr("ui_settings"), "pause menu should expose localized settings entry")
	var pause_requested: Array[bool] = [false]
	pause_menu.connect("settings_requested", func() -> void:
		pause_requested[0] = true
	)
	if pause_settings_button != null:
		pause_settings_button.pressed.emit()
	_expect(pause_requested[0], "pause settings button should emit settings_requested without locking pause menu")
	_expect_english_buttons_fit(pause_menu, "pause menu")
	remove_child(pause_menu)
	pause_menu.queue_free()
	Localization.set_locale("zh_CN")


func _expect_runtime_locale_refresh() -> void:
	Localization.set_locale("zh_CN")
	await _expect_hud_locale_refresh()
	await _expect_level_up_locale_refresh()
	await _expect_game_over_locale_refresh()
	Localization.set_locale("zh_CN")


func _expect_hud_locale_refresh() -> void:
	var hud: CanvasLayer = GAMEPLAY_HUD_SCENE.instantiate() as CanvasLayer
	hud.name = "GameplayHud"
	add_child(hud)
	await get_tree().process_frame

	hud.call("set_life", 3.0, 5.0)
	hud.call("set_kills", 2)
	hud.call("set_level", 4)
	hud.call("set_xp", 1, 10)
	hud.call("show_upgrade_feedback", "ui_growth_damage_small_name")
	await get_tree().process_frame

	var life_label: Label = _find_node_by_name(hud, "LifeLabel") as Label
	var kills_label: Label = _find_node_by_name(hud, "KillsLabel") as Label
	var level_label: Label = _find_node_by_name(hud, "LevelLabel") as Label
	var xp_label: Label = _find_node_by_name(hud, "XpLabel") as Label
	var feedback_label: Label = _find_node_by_name(hud, "UpgradeFeedbackLabel") as Label
	_expect(life_label != null and String(life_label.text).begins_with(tr("ui_hud_life")), "HUD life should start in zh_CN")
	_expect(kills_label != null and String(kills_label.text).begins_with(tr("ui_hud_kills")), "HUD kills should start in zh_CN")
	_expect(level_label != null and String(level_label.text).begins_with(tr("ui_hud_level")), "HUD level should start in zh_CN")
	_expect(xp_label != null and String(xp_label.text).begins_with(tr("ui_hud_xp")), "HUD XP should start in zh_CN")
	_expect(feedback_label != null and String(feedback_label.text).contains(tr("ui_growth_damage_small_name")), "HUD upgrade feedback should start in zh_CN")

	Localization.set_locale("en")
	await get_tree().process_frame
	_expect(life_label != null and String(life_label.text).begins_with("Life"), "HUD life should refresh to en")
	_expect(kills_label != null and String(kills_label.text).begins_with("Kills"), "HUD kills should refresh to en")
	_expect(level_label != null and String(level_label.text).begins_with("Level"), "HUD level should refresh to en")
	_expect(xp_label != null and String(xp_label.text).begins_with("XP"), "HUD XP should refresh to en")
	_expect(feedback_label != null and String(feedback_label.text).contains("Upgrade"), "HUD upgrade feedback should refresh to en")

	remove_child(hud)
	hud.queue_free()


func _expect_level_up_locale_refresh() -> void:
	Localization.set_locale("zh_CN")
	var panel: CanvasLayer = LEVEL_UP_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "LevelUpPanel"
	add_child(panel)
	await get_tree().process_frame
	var choices: Array[Dictionary] = [{
		"id": "smoke_choice",
		"name_key": "ui_growth_damage_small_name",
		"desc_key": "ui_growth_damage_small_desc",
	}]
	panel.call("configure", choices)
	await get_tree().process_frame

	var title_label: Label = _find_node_by_name(panel, "TitleLabel") as Label
	var button_box: VBoxContainer = _find_node_by_name(panel, "ButtonBox") as VBoxContainer
	var choice_button: Button = null
	if button_box != null and button_box.get_child_count() > 0:
		choice_button = button_box.get_child(0) as Button
	_expect(title_label != null and String(title_label.text) == tr("ui_level_up_title"), "level-up panel title should start in zh_CN")
	_expect(choice_button != null and String(choice_button.text).contains(tr("ui_growth_damage_small_name")), "level-up choice should start in zh_CN")

	Localization.set_locale("en")
	await get_tree().process_frame
	button_box = _find_node_by_name(panel, "ButtonBox") as VBoxContainer
	choice_button = null
	if button_box != null and button_box.get_child_count() > 0:
		choice_button = button_box.get_child(0) as Button
	_expect(title_label != null and String(title_label.text) == "Choose Upgrade", "level-up panel title should refresh to en")
	_expect(choice_button != null and String(choice_button.text).contains("Hardened Core"), "level-up choice should refresh to en")
	_expect_english_buttons_fit(panel, "level-up panel")

	remove_child(panel)
	panel.queue_free()


func _expect_game_over_locale_refresh() -> void:
	Localization.set_locale("zh_CN")
	var panel: CanvasLayer = GAME_OVER_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "GameOverPanel"
	add_child(panel)
	await get_tree().process_frame
	panel.call("configure", 5, 42.0)
	await get_tree().process_frame

	var title_label: Label = _find_node_by_name(panel, "TitleLabel") as Label
	var summary_label: Label = _find_node_by_name(panel, "SummaryLabel") as Label
	var restart_button: Button = _find_node_by_name(panel, "RestartButton") as Button
	var quit_button: Button = _find_node_by_name(panel, "QuitToTitleButton") as Button
	_expect(title_label != null and String(title_label.text) == tr("ui_game_over"), "game-over title should start in zh_CN")
	_expect(summary_label != null and String(summary_label.text).contains(tr("ui_hud_kills")), "game-over summary should start in zh_CN")

	Localization.set_locale("en")
	await get_tree().process_frame
	_expect(title_label != null and String(title_label.text) == "Run Over", "game-over title should refresh to en")
	_expect(summary_label != null and String(summary_label.text).contains("Kills"), "game-over summary should refresh to en")
	_expect(restart_button != null and String(restart_button.text) == "Restart", "game-over restart button should refresh to en")
	_expect(quit_button != null and String(quit_button.text) == "Back to Title", "game-over quit button should refresh to en")
	_expect_english_buttons_fit(panel, "game-over panel")

	remove_child(panel)
	panel.queue_free()


func _on_setting_changed(key: String, _value: Variant, changed_keys: Array[String]) -> void:
	changed_keys.append(key)


func _on_settings_panel_closed() -> void:
	_settings_panel_closed_count += 1


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root == null:
		return null
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _count_binding_buttons(root: Node) -> int:
	var count: int = 1 if root is Button else 0
	for child: Node in root.get_children():
		count += _count_binding_buttons(child)
	return count


func _expect_english_buttons_fit(root: Node, context: String) -> void:
	if Localization.current_locale() != "en":
		_expect(false, "%s english button fit check should run under en locale" % context)
		return

	var buttons: Array[Button] = []
	_collect_visible_buttons(root, buttons)
	for button: Button in buttons:
		var text: String = _button_display_text(button)
		if text.is_empty():
			continue
		var fit: Dictionary = _button_text_fit(button, text)
		if bool(fit.get("skipped", false)):
			continue
		_expect(
			bool(fit["fits"]),
			"%s button '%s' english text should fit: '%s' width=%.1f available=%.1f measured=%.1f" % [
				context,
				String(button.name),
				text,
				float(fit["width"]),
				float(fit["available"]),
				float(fit["measured"]),
			]
		)


func _collect_visible_buttons(root: Node, buttons: Array[Button]) -> void:
	if root == null:
		return
	if root is Button:
		var button: Button = root as Button
		if button.is_visible_in_tree():
			buttons.append(button)
	for child: Node in root.get_children():
		_collect_visible_buttons(child, buttons)


func _button_display_text(button: Button) -> String:
	var option_button: OptionButton = button as OptionButton
	if option_button != null and option_button.selected >= 0:
		return String(option_button.get_item_text(option_button.selected))
	return String(button.text)


func _button_text_fit(button: Button, text: String) -> Dictionary:
	var font: Font = button.get_theme_font("font")
	var font_size: int = button.get_theme_font_size("font_size")
	if font == null or font_size <= 0 or button.size.x <= 0.0:
		return {"skipped": true}

	var style_minimum: Vector2 = Vector2.ZERO
	var stylebox: StyleBox = button.get_theme_stylebox("normal")
	if stylebox != null:
		style_minimum = stylebox.get_minimum_size()

	var icon_width: float = 0.0
	if button.icon != null:
		icon_width = float(button.icon.get_width() + button.get_theme_constant("h_separation"))

	var available_width: float = button.size.x - style_minimum.x - icon_width - BUTTON_TEXT_EXTRA_PADDING
	var measured_width: float = _max_line_width(font, font_size, text)
	return {
		"available": available_width,
		"fits": measured_width <= available_width + ENGLISH_UI_FIT_TOLERANCE,
		"measured": measured_width,
		"width": button.size.x,
	}


func _max_line_width(font: Font, font_size: int, text: String) -> float:
	var max_width: float = 0.0
	for line: String in text.split("\n"):
		var line_width: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		max_width = max(max_width, line_width)
	return max_width


func _capture_original_config() -> void:
	_original_exists = FileAccess.file_exists(Settings.settings_path())
	if not _original_exists:
		_original_text = ""
		return

	var file: FileAccess = FileAccess.open(Settings.settings_path(), FileAccess.READ)
	if file == null:
		_expect(false, "smoke should read original settings.cfg")
		return
	_original_text = file.get_as_text()


func _capture_original_binding_files() -> void:
	_original_binding_files.clear()
	for path: String in _binding_fixture_paths():
		var entry: Dictionary = {"exists": FileAccess.file_exists(path), "text": ""}
		if bool(entry["exists"]):
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				entry["text"] = file.get_as_text()
		_original_binding_files[path] = entry


func _restore_original_config() -> void:
	if _original_exists:
		_write_text(Settings.settings_path(), _original_text)
		return
	_remove_settings_file()


func _restore_original_binding_files() -> void:
	for path: String in _binding_fixture_paths():
		var entry: Dictionary = _original_binding_files.get(path, {}) as Dictionary
		if bool(entry.get("exists", false)):
			_write_text(path, String(entry.get("text", "")))
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _binding_fixture_paths() -> Array[String]:
	return [
		InputService.bindings_path(),
		"user://input_bindings.tmp.tres",
		"user://input_bindings.bak.tres",
		"user://input_bindings.invalid.tres",
	]


func _remove_settings_file() -> void:
	if FileAccess.file_exists(Settings.settings_path()):
		DirAccess.remove_absolute(Settings.settings_path())


func _write_text(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_expect(false, "smoke should open settings path for writing: %s" % path)
		return
	file.store_string(content)
	file.flush()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[SettingsSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[SettingsSmoke] passed")
		get_tree().quit(0)
		return

	print("[SettingsSmoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
