class_name SteamLabSettings
extends RefCounted

const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")

const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
const DEFAULT_WINDOW_SIZE := Vector2i(540, 960)
const DEFAULT_WINDOW_MARGIN := Vector2i(48, 48)
const MAX_PLAYER_NAME_LENGTH: int = 18

var locale: String = LAB_LOCALE_SCRIPT.LOCALE_EN
var fullscreen: bool = false
var player_name: String = ""
var slime_palette_id: int = 0
var bullet_palette_id: int = 0


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
	player_name = ""
	slime_palette_id = 0
	bullet_palette_id = 0
	if not FileAccess.file_exists(CONFIG_PATH):
		return false

	var config := ConfigFile.new()
	var error := config.load(CONFIG_PATH)
	if error != OK:
		return false

	var saved_locale := String(config.get_value(SECTION, "locale", detected_locale))
	locale = LAB_LOCALE_SCRIPT.normalize_locale(saved_locale)
	fullscreen = bool(config.get_value(SECTION, "fullscreen", false))
	player_name = clean_player_name(String(config.get_value(SECTION, "player_name", "")))
	slime_palette_id = maxi(0, int(config.get_value(SECTION, "slime_palette_id", 0)))
	bullet_palette_id = maxi(0, int(config.get_value(SECTION, "bullet_palette_id", 0)))
	return true


func save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION, "locale", locale)
	config.set_value(SECTION, "fullscreen", fullscreen)
	config.set_value(SECTION, "player_name", player_name)
	config.set_value(SECTION, "slime_palette_id", slime_palette_id)
	config.set_value(SECTION, "bullet_palette_id", bullet_palette_id)
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


func set_player_name(new_name: String) -> bool:
	var cleaned := clean_player_name(new_name)
	if player_name == cleaned:
		return false
	player_name = cleaned
	return true


func set_slime_palette_id(palette_id: int) -> bool:
	var normalized := maxi(0, palette_id)
	if slime_palette_id == normalized:
		return false
	slime_palette_id = normalized
	return true


func set_bullet_palette_id(palette_id: int) -> bool:
	var normalized := maxi(0, palette_id)
	if bullet_palette_id == normalized:
		return false
	bullet_palette_id = normalized
	return true


func appearance_settings() -> Dictionary:
	return {
		"name": player_name,
		"slime_palette_id": slime_palette_id,
		"bullet_palette_id": bullet_palette_id,
	}


func apply_fullscreen() -> void:
	var display_name := DisplayServer.get_name().to_lower()
	if display_name == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_apply_fullscreen_fallback_if_needed()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	DisplayServer.window_set_size(DEFAULT_WINDOW_SIZE)
	_center_window()


func _apply_fullscreen_fallback_if_needed() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return
	var screen_id := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_id)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(usable_rect.position)
	DisplayServer.window_set_size(usable_rect.size)


func _center_window() -> void:
	var screen_id := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_id)
	var target_position := usable_rect.position + (usable_rect.size - DEFAULT_WINDOW_SIZE) / 2
	var minimum_position := usable_rect.position + DEFAULT_WINDOW_MARGIN
	DisplayServer.window_set_position(Vector2i(
		maxi(target_position.x, minimum_position.x),
		maxi(target_position.y, minimum_position.y)
	))


func clean_player_name(raw_name: String) -> String:
	var clean := raw_name.strip_edges()
	if clean.length() > MAX_PLAYER_NAME_LENGTH:
		clean = clean.substr(0, MAX_PLAYER_NAME_LENGTH)
	return clean
