extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const META_CURRENCIES := preload("res://scripts/contracts/meta_currencies.gd")
const GAME_OVER_PANEL_SCENE := preload("res://scenes/ui/game_over_panel.tscn")
const GAMEPLAY_HUD_SCENE := preload("res://scenes/gameplay/gameplay_hud.tscn")
const LEVEL_UP_PANEL_SCENE := preload("res://scenes/ui/level_up_panel.tscn")
const META_PROGRESSION_PANEL_SCENE := preload("res://scenes/ui/meta_progression_panel.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const TITLE_MENU_SCENE := preload("res://scenes/ui/title_menu.tscn")

const BOOT_FRAMES: int = 3

var _failures: Array[String] = []
var _original_exists: bool = false
var _original_text: String = ""
var _settings_panel_closed_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_capture_original_config()

	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame

	_expect_missing_file_uses_defaults()
	_expect_roundtrip_and_signal_flow()
	_expect_invalid_values_are_rejected()
	_expect_input_bindings_update_input_map()
	_expect_invalid_saved_values_recover_to_defaults()
	_expect_broken_config_recovers_to_defaults()
	await _expect_settings_panel_controls()
	await _expect_menu_settings_entries()
	await _expect_runtime_locale_refresh()

	_restore_original_config()
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
	var original_pause_binding: String = String(Settings.get_value(SETTINGS_KEYS.INPUT_PAUSE))
	_expect(not Settings.set_value(SETTINGS_KEYS.AUDIO_MASTER, 2.0), "master volume should reject values above 1.0")
	_expect(not Settings.set_value(SETTINGS_KEYS.GENERAL_LOCALE, "pirate"), "locale should reject unsupported values")
	_expect(not Settings.set_value(SETTINGS_KEYS.INPUT_PAUSE, "NoSuchKey"), "input pause should reject unsupported key names")
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), original_master), "invalid master volume should not mutate state")
	_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == original_locale, "invalid locale should not mutate state")
	_expect(String(Settings.get_value(SETTINGS_KEYS.INPUT_PAUSE)) == original_pause_binding, "invalid input binding should not mutate state")


func _expect_input_bindings_update_input_map() -> void:
	Settings.reset_to_defaults(false)
	_expect(_action_has_key(ACTIONS.PAUSE, KEY_ESCAPE), "default pause binding should apply Escape to InputMap")
	_expect(Settings.set_value(SETTINGS_KEYS.INPUT_PAUSE, "P"), "pause binding should accept P")
	_expect(String(Settings.get_value(SETTINGS_KEYS.INPUT_PAUSE)) == "P", "pause binding should store P")
	_expect(_action_has_key(ACTIONS.PAUSE, KEY_P), "pause binding should apply P to InputMap")
	_expect(not _action_has_key(ACTIONS.PAUSE, KEY_ESCAPE), "pause rebinding should replace the previous keyboard event")
	_expect(Settings.set_value(SETTINGS_KEYS.INPUT_PAUSE, "Escape"), "pause binding should restore Escape")


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
	var fullscreen_check: CheckButton = _find_node_by_name(panel, "FullscreenCheck") as CheckButton
	var aim_mode_option: OptionButton = _find_node_by_name(panel, "AimModeOption") as OptionButton
	var input_feedback_label: Label = _find_node_by_name(panel, "InputFeedbackLabel") as Label
	var pause_binding_option: OptionButton = _find_node_by_name(panel, "PauseBindingOption") as OptionButton
	var ui_back_binding_option: OptionButton = _find_node_by_name(panel, "UiBackBindingOption") as OptionButton
	var reset_input_button: Button = _find_node_by_name(panel, "ResetInputBindingsButton") as Button
	var close_button: Button = _find_node_by_name(panel, "CloseButton") as Button

	_expect(title_label != null and String(title_label.text) == tr("ui_settings_title"), "settings panel should show localized title")
	_expect(locale_option != null and locale_option.item_count == 2, "settings panel should expose two locale options")
	_expect(aim_mode_option != null and aim_mode_option.item_count == 2, "settings panel should expose aim mode options")
	_expect(pause_binding_option != null and pause_binding_option.item_count == Settings.input_binding_options().size(), "settings panel should expose input binding options")
	_expect(input_feedback_label != null and String(input_feedback_label.text) == tr("ui_settings_input_feedback_ready"), "settings panel should expose localized input feedback")
	_expect(reset_input_button != null and String(reset_input_button.text) == tr("ui_settings_input_restore_defaults"), "settings panel should expose reset input defaults button")
	_expect(master_slider != null and is_equal_approx(float(master_slider.value), 1.0), "settings panel should read master volume default")
	_expect(master_value_label != null and String(master_value_label.text) == "100%", "settings panel should show master volume percent")
	_expect(fullscreen_check != null and not fullscreen_check.button_pressed, "settings panel should read fullscreen default")

	if master_slider != null:
		master_slider.value = 0.35
		await get_tree().process_frame
		_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), 0.35), "master volume slider should write Settings")
		_expect(master_value_label != null and String(master_value_label.text) == "35%", "master volume slider should refresh percent")
	if locale_option != null:
		locale_option.select(1)
		locale_option.item_selected.emit(1)
		await get_tree().process_frame
		_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == "en", "locale option should write Settings.general.locale")
		_expect(Localization.current_locale() == "en", "settings panel locale option should switch Localization")
		_expect(title_label != null and String(title_label.text) == "Settings", "settings panel should refresh existing labels after locale switch")
	if aim_mode_option != null:
		aim_mode_option.select(1)
		aim_mode_option.item_selected.emit(1)
		await get_tree().process_frame
		_expect(String(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_AIM_MODE)) == "auto", "aim mode option should write Settings")
	if fullscreen_check != null:
		fullscreen_check.button_pressed = true
		fullscreen_check.toggled.emit(true)
		await get_tree().process_frame
		_expect(bool(Settings.get_value(SETTINGS_KEYS.VIDEO_FULLSCREEN)), "fullscreen check should write Settings")
	if pause_binding_option != null:
		var p_index: int = _option_index(pause_binding_option, "P")
		_expect(p_index >= 0, "pause binding option should include P")
		if p_index >= 0:
			pause_binding_option.select(p_index)
			pause_binding_option.item_selected.emit(p_index)
			await get_tree().process_frame
			_expect(String(Settings.get_value(SETTINGS_KEYS.INPUT_PAUSE)) == "P", "pause binding option should write Settings")
			_expect(_action_has_key(ACTIONS.PAUSE, KEY_P), "pause binding option should update InputMap")
			_expect(input_feedback_label != null and String(input_feedback_label.text).contains("Pause bound to P"), "pause binding should show saved feedback")
	if ui_back_binding_option != null:
		var p_index: int = _option_index(ui_back_binding_option, "P")
		_expect(p_index >= 0, "ui back binding option should include P")
		if p_index >= 0:
			ui_back_binding_option.select(p_index)
			ui_back_binding_option.item_selected.emit(p_index)
			await get_tree().process_frame
			_expect(String(Settings.get_value(SETTINGS_KEYS.INPUT_UI_BACK)) == "P", "ui back binding option should accept a shared binding")
			_expect(input_feedback_label != null and String(input_feedback_label.text).contains("shared with Pause"), "shared input binding should show conflict feedback")
	if reset_input_button != null:
		reset_input_button.pressed.emit()
		await get_tree().process_frame
		_expect(String(Settings.get_value(SETTINGS_KEYS.INPUT_PAUSE)) == "Escape", "reset input defaults should restore pause binding")
		_expect(String(Settings.get_value(SETTINGS_KEYS.INPUT_UI_BACK)) == "Escape", "reset input defaults should restore ui_back binding")
		_expect(_action_has_key(ACTIONS.PAUSE, KEY_ESCAPE), "reset input defaults should restore pause InputMap event")
		_expect(_action_has_key(ACTIONS.UI_BACK, KEY_ESCAPE), "reset input defaults should restore ui_back InputMap event")
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
	remove_child(pause_menu)
	pause_menu.queue_free()


func _expect_runtime_locale_refresh() -> void:
	Localization.set_locale("zh_CN")
	await _expect_hud_locale_refresh()
	await _expect_level_up_locale_refresh()
	await _expect_game_over_locale_refresh()
	await _expect_meta_progression_locale_refresh()
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

	remove_child(panel)
	panel.queue_free()


func _expect_game_over_locale_refresh() -> void:
	Localization.set_locale("zh_CN")
	var panel: CanvasLayer = GAME_OVER_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "GameOverPanel"
	add_child(panel)
	await get_tree().process_frame
	var settlement: Dictionary = {
		"account_level": 2,
		"account_xp": 12,
		"currency_amount": 8,
		"currency_id": META_CURRENCIES.META_ESSENCE,
		"currency_name_key": "meta_currency_essence_name",
		"previous_account_level": 1,
		"profile": {
			"account_level": 2,
			"currencies": {
				META_CURRENCIES.META_ESSENCE: 8,
			},
		},
	}
	panel.call("configure", 5, 42.0, settlement)
	await get_tree().process_frame

	var title_label: Label = _find_node_by_name(panel, "TitleLabel") as Label
	var summary_label: Label = _find_node_by_name(panel, "SummaryLabel") as Label
	var settlement_label: Label = _find_node_by_name(panel, "SettlementLabel") as Label
	var profile_label: Label = _find_node_by_name(panel, "MetaProfileLabel") as Label
	var restart_button: Button = _find_node_by_name(panel, "RestartButton") as Button
	var quit_button: Button = _find_node_by_name(panel, "QuitToTitleButton") as Button
	_expect(title_label != null and String(title_label.text) == tr("ui_game_over"), "game-over title should start in zh_CN")
	_expect(summary_label != null and String(summary_label.text).contains(tr("ui_hud_kills")), "game-over summary should start in zh_CN")
	_expect(settlement_label != null and String(settlement_label.text).contains(tr("meta_currency_essence_name")), "game-over settlement should start in zh_CN")
	_expect(profile_label != null and String(profile_label.text).contains(tr("ui_meta_account_level_up").format({
		"from": 1,
		"to": 2,
	})), "game-over profile should start in zh_CN")

	Localization.set_locale("en")
	await get_tree().process_frame
	_expect(title_label != null and String(title_label.text) == "Run Over", "game-over title should refresh to en")
	_expect(summary_label != null and String(summary_label.text).contains("Kills"), "game-over summary should refresh to en")
	_expect(settlement_label != null and String(settlement_label.text).contains("Earned"), "game-over settlement should refresh to en")
	_expect(profile_label != null and String(profile_label.text).contains("Account Level Up"), "game-over profile should refresh to en")
	_expect(restart_button != null and String(restart_button.text) == "Restart", "game-over restart button should refresh to en")
	_expect(quit_button != null and String(quit_button.text) == "Back to Title", "game-over quit button should refresh to en")

	remove_child(panel)
	panel.queue_free()


func _expect_meta_progression_locale_refresh() -> void:
	Localization.set_locale("zh_CN")
	var panel: CanvasLayer = META_PROGRESSION_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "MetaProgressionPanel"
	add_child(panel)
	await get_tree().process_frame

	var title_label: Label = _find_node_by_name(panel, "TitleLabel") as Label
	var close_button: Button = _find_node_by_name(panel, "CloseButton") as Button
	_expect(title_label != null and String(title_label.text) == tr("ui_meta_progression_title"), "meta progression title should start in zh_CN")
	_expect(close_button != null and String(close_button.text) == tr("ui_cancel"), "meta progression close button should start in zh_CN")

	Localization.set_locale("en")
	await get_tree().process_frame
	_expect(title_label != null and String(title_label.text) == "Meta Upgrades", "meta progression title should refresh to en")
	_expect(close_button != null and String(close_button.text) == "Cancel", "meta progression close button should refresh to en")

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


func _option_index(option: OptionButton, text: String) -> int:
	for index: int in range(option.item_count):
		if String(option.get_item_text(index)) == text:
			return index
	return -1


func _action_has_key(action_id: String, keycode: Key) -> bool:
	if not InputMap.has_action(action_id):
		return false
	for event: InputEvent in InputMap.action_get_events(action_id):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return true
	return false


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


func _restore_original_config() -> void:
	if _original_exists:
		_write_text(Settings.settings_path(), _original_text)
		return
	_remove_settings_file()


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
