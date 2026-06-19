extends Node


const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
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
	_expect_invalid_saved_values_recover_to_defaults()
	_expect_broken_config_recovers_to_defaults()
	await _expect_settings_panel_controls()
	await _expect_menu_settings_entries()

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
	_expect(not Settings.set_value(SETTINGS_KEYS.AUDIO_MASTER, 2.0), "master volume should reject values above 1.0")
	_expect(not Settings.set_value(SETTINGS_KEYS.GENERAL_LOCALE, "pirate"), "locale should reject unsupported values")
	_expect(is_equal_approx(float(Settings.get_value(SETTINGS_KEYS.AUDIO_MASTER)), original_master), "invalid master volume should not mutate state")
	_expect(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE)) == original_locale, "invalid locale should not mutate state")


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
	var close_button: Button = _find_node_by_name(panel, "CloseButton") as Button

	_expect(title_label != null and String(title_label.text) == tr("ui_settings_title"), "settings panel should show localized title")
	_expect(locale_option != null and locale_option.item_count == 2, "settings panel should expose two locale options")
	_expect(aim_mode_option != null and aim_mode_option.item_count == 2, "settings panel should expose aim mode options")
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
