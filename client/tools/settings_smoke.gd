extends Node


const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")

const BOOT_FRAMES: int = 3

var _failures: Array[String] = []
var _original_exists: bool = false
var _original_text: String = ""


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


func _on_setting_changed(key: String, _value: Variant, changed_keys: Array[String]) -> void:
	changed_keys.append(key)


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
