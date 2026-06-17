# Doc: docs/代码/settings.md
# Authority: docs/游戏设计文档.md §9.5, docs/词表与契约.md §5
class_name SettingsAutoload
extends Node


signal setting_changed(key: String, value: Variant)

const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")

var _values: Dictionary = {}


func _ready() -> void:
	reset_to_defaults()


func get_value(key: String, fallback: Variant = null) -> Variant:
	if not _is_registered_key(key):
		return fallback
	return _values.get(key, fallback)


func set_value(key: String, value: Variant) -> bool:
	if not _is_registered_key(key):
		return false

	if _values.get(key) == value:
		return false

	_values[key] = value
	setting_changed.emit(key, value)
	return true


func has_key(key: String) -> bool:
	return _is_registered_key(key)


func values() -> Dictionary:
	return _values.duplicate(true)


func reset_to_defaults() -> void:
	_values = _default_values()


func _is_registered_key(key: String) -> bool:
	if DataLoader == null or not DataLoader.has_contract_value("settings_keys", key):
		push_error("[Settings] unknown settings key: %s" % key)
		return false
	return true


func _default_values() -> Dictionary:
	return {
		SETTINGS_KEYS.GENERAL_LOCALE: "zh_CN",
		SETTINGS_KEYS.VIDEO_FULLSCREEN: false,
		SETTINGS_KEYS.VIDEO_VSYNC: true,
		SETTINGS_KEYS.AUDIO_MASTER: 1.0,
		SETTINGS_KEYS.AUDIO_MUSIC: 0.8,
		SETTINGS_KEYS.AUDIO_SFX: 0.9,
		SETTINGS_KEYS.GAMEPLAY_FIRE_ON_RELEASE: false,
		SETTINGS_KEYS.GAMEPLAY_AIM_MODE: "4dir",
		SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE: true,
		SETTINGS_KEYS.GAMEPLAY_PAUSE_ON_FOCUS_LOSS: true,
		SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS: true,
		SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED: true,
	}
