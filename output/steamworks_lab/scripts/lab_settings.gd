class_name SteamLabSettings
extends RefCounted

const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
const DEFAULT_WINDOW_SIZE := Vector2i(540, 960)

var locale: String = LAB_LOCALE_SCRIPT.LOCALE_EN
var fullscreen: bool = false


static func default_locale_for_language(raw_language: String) -> String:
	return LAB_LOCALE_SCRIPT.normalize_locale(raw_language)


static func default_locale_for_environment(steam_language: String = "") -> String:
	if steam_language.strip_edges() != "":
		return default_locale_for_language(steam_language)
	return default_locale_for_language(OS.get_locale())


func load_settings(steam_language: String = "") -> bool:
	var detected_locale := default_locale_for_environment(steam_language)
	locale = detected_locale
	fullscreen = false
	if not FileAccess.file_exists(CONFIG_PATH):
		return false

	var config := ConfigFile.new()
	var error := config.load(CONFIG_PATH)
	if error != OK:
		return false

	var saved_locale := String(config.get_value(SECTION, "locale", detected_locale))
	locale = LAB_LOCALE_SCRIPT.normalize_locale(saved_locale)
	fullscreen = bool(config.get_value(SECTION, "fullscreen", false))
	return true


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "locale", locale)
	config.set_value(SECTION, "fullscreen", fullscreen)
	return config.save(CONFIG_PATH) == OK


func set_locale(new_locale: String) -> bool:
	var normalized := LAB_LOCALE_SCRIPT.normalize_locale(new_locale)
	if locale == normalized:
		return false
	locale = normalized
	return true


func set_fullscreen(enabled: bool) -> bool:
	if fullscreen == enabled:
		return false
	fullscreen = enabled
	return true


func apply_fullscreen() -> void:
	var display_name := DisplayServer.get_name().to_lower()
	if display_name == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(DEFAULT_WINDOW_SIZE)
