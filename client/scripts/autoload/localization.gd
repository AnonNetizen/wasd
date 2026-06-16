# Doc: docs/代码/localization.md
# Authority: docs/游戏设计文档.md §9.4, client/locale/README.md
extends Node
class_name LocalizationAutoload


signal locale_changed(locale: String)

const DEFAULT_LOCALE: String = "zh_CN"
const SUPPORTED_LOCALES: Array[String] = ["zh_CN", "en"]
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")

var _current_locale: String = DEFAULT_LOCALE


func _ready() -> void:
	if Settings != null:
		Settings.setting_changed.connect(_on_setting_changed)
		set_locale(String(Settings.get_value(SETTINGS_KEYS.GENERAL_LOCALE, DEFAULT_LOCALE)))
	else:
		set_locale(DEFAULT_LOCALE)


func current_locale() -> String:
	return _current_locale


func supported_locales() -> Array[String]:
	return SUPPORTED_LOCALES.duplicate()


func set_locale(locale: String) -> bool:
	if not SUPPORTED_LOCALES.has(locale):
		push_error("[Localization] unsupported locale: %s" % locale)
		return false

	if locale == _current_locale:
		TranslationServer.set_locale(locale)
		return false

	_current_locale = locale
	TranslationServer.set_locale(locale)
	locale_changed.emit(_current_locale)
	return true


func tr_key(key: String) -> String:
	var translated: String = tr(key)
	if translated.is_empty():
		return key
	return translated


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == SETTINGS_KEYS.GENERAL_LOCALE:
		set_locale(String(value))
