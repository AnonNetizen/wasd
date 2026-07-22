# Doc: docs/代码/settings.md
# Authority: docs/游戏设计文档.md §9.5, docs/词表与契约.md §5
class_name SettingsAutoload
extends Node


signal setting_changed(key: String, value: Variant)
signal settings_loaded(recovered: bool)
signal settings_saved(path: String)

const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const SETTINGS_PATH: String = "user://settings.cfg"
const META_SECTION: String = "meta"
const SETTINGS_SECTION: String = "settings"
const CONFIG_VERSION: int = 2
const KEYBOARD_BINDING_OPTIONS: Array[String] = [
	"W",
	"A",
	"S",
	"D",
	"Up",
	"Down",
	"Left",
	"Right",
	"Space",
	"Tab",
	"Escape",
	"Enter",
	"Q",
	"E",
	"R",
	"F",
	"P",
	"J",
	"K",
	"L",
	"I",
]
const LEGACY_INPUT_DEFAULTS: Dictionary = {
	SETTINGS_KEYS.INPUT_MOVE_UP: "W",
	SETTINGS_KEYS.INPUT_MOVE_DOWN: "S",
	SETTINGS_KEYS.INPUT_MOVE_LEFT: "A",
	SETTINGS_KEYS.INPUT_MOVE_RIGHT: "D",
	SETTINGS_KEYS.INPUT_AIM_UP: "Up",
	SETTINGS_KEYS.INPUT_AIM_DOWN: "Down",
	SETTINGS_KEYS.INPUT_AIM_LEFT: "Left",
	SETTINGS_KEYS.INPUT_AIM_RIGHT: "Right",
	SETTINGS_KEYS.INPUT_USE_ACTIVE_ITEM: "Space",
	SETTINGS_KEYS.INPUT_INTERACT: "E",
	SETTINGS_KEYS.INPUT_SHOW_STATS_PANEL: "Tab",
	SETTINGS_KEYS.INPUT_PAUSE: "Escape",
	SETTINGS_KEYS.INPUT_UI_CONFIRM: "Enter",
	SETTINGS_KEYS.INPUT_UI_BACK: "Escape",
}

var _values: Dictionary = {}
var _last_load_recovered: bool = false
var _legacy_input_bindings: Dictionary = {}


func _ready() -> void:
	reset_to_defaults(false)
	load_from_disk()


func get_value(key: String, fallback: Variant = null) -> Variant:
	if not _is_registered_key(key):
		return fallback
	return _values.get(key, fallback)


func set_value(key: String, value: Variant) -> bool:
	if not _is_registered_key(key):
		return false
	if LEGACY_INPUT_DEFAULTS.has(key):
		push_warning("[Settings] deprecated input binding key is read-only: %s" % key)
		return false

	var normalized: Variant = _normalize_value(key, value)
	if normalized == null:
		push_warning("[Settings] invalid value for %s: %s" % [key, str(value)])
		return false

	if _values.get(key) == normalized:
		return false

	_values[key] = normalized
	setting_changed.emit(key, normalized)
	save_to_disk()
	return true


func has_key(key: String) -> bool:
	return _is_registered_key(key)


func values() -> Dictionary:
	return _values.duplicate(true)


func take_legacy_input_bindings() -> Dictionary:
	var result: Dictionary = _legacy_input_bindings.duplicate(true)
	_legacy_input_bindings.clear()
	return result


func reset_to_defaults(persist: bool = false) -> void:
	_values = _default_values()
	if persist:
		save_to_disk()


func load_from_disk() -> bool:
	_values = _default_values()
	_last_load_recovered = false
	_legacy_input_bindings.clear()

	var config := ConfigFile.new()
	var error: Error = config.load(SETTINGS_PATH)
	if error == ERR_FILE_NOT_FOUND:
		settings_loaded.emit(false)
		return true
	if error != OK:
		_last_load_recovered = true
		push_warning("[Settings] failed to load settings.cfg; using defaults. error=%d" % int(error))
		save_to_disk()
		settings_loaded.emit(true)
		return false

	var version: Variant = config.get_value(META_SECTION, "version", 1)
	if not version is int or int(version) < 1 or int(version) > CONFIG_VERSION:
		_last_load_recovered = true
		push_warning("[Settings] unsupported settings config version; using defaults.")
		save_to_disk()
		settings_loaded.emit(true)
		return false

	for key: String in _default_values().keys():
		if not config.has_section_key(SETTINGS_SECTION, key):
			continue
		var raw_value: Variant = config.get_value(SETTINGS_SECTION, key)
		var normalized: Variant = _normalize_value(key, raw_value)
		if normalized == null:
			_last_load_recovered = true
			push_warning("[Settings] invalid saved value for %s; using default." % key)
			continue
		_values[key] = normalized

	if int(version) == 1:
		_capture_legacy_input_bindings(config)
	if _last_load_recovered or int(version) < CONFIG_VERSION:
		save_to_disk()
	settings_loaded.emit(_last_load_recovered)
	return not _last_load_recovered


func save_to_disk() -> bool:
	var config := ConfigFile.new()
	config.set_value(META_SECTION, "version", CONFIG_VERSION)
	var defaults := _default_values()
	for key: String in defaults.keys():
		config.set_value(SETTINGS_SECTION, key, _values.get(key, defaults[key]))

	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_error("[Settings] failed to save settings.cfg. error=%d" % int(error))
		return false

	settings_saved.emit(SETTINGS_PATH)
	return true


func settings_path() -> String:
	return SETTINGS_PATH


func last_load_recovered() -> bool:
	return _last_load_recovered


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
		SETTINGS_KEYS.GAMEPLAY_AIM_MODE: "mouse",
		SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE: true,
		SETTINGS_KEYS.GAMEPLAY_PAUSE_ON_FOCUS_LOSS: true,
		SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS: true,
		SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED: true,
	}


func _normalize_value(key: String, value: Variant) -> Variant:
	if not _is_registered_key(key):
		return null

	var spec: Dictionary = _setting_specs().get(key, {}) as Dictionary
	var expected_type: String = String(spec.get("type", ""))
	match expected_type:
		"bool":
			if value is bool:
				return value
		"float":
			if value is int or value is float:
				var number: float = float(value)
				if spec.has("min") and number < float(spec["min"]):
					return null
				if spec.has("max") and number > float(spec["max"]):
					return null
				return number
		"string":
			if value is String:
				var text: String = String(value)
				var options: Array = spec.get("options", []) as Array
				if not options.is_empty() and not options.has(text):
					return null
				return text
		_:
			push_error("[Settings] missing validation spec for %s" % key)
	return null


func _setting_specs() -> Dictionary:
	return {
		SETTINGS_KEYS.GENERAL_LOCALE: {"type": "string", "options": ["zh_CN", "en"]},
		SETTINGS_KEYS.VIDEO_FULLSCREEN: {"type": "bool"},
		SETTINGS_KEYS.VIDEO_VSYNC: {"type": "bool"},
		SETTINGS_KEYS.AUDIO_MASTER: {"type": "float", "min": 0.0, "max": 1.0},
		SETTINGS_KEYS.AUDIO_MUSIC: {"type": "float", "min": 0.0, "max": 1.0},
		SETTINGS_KEYS.AUDIO_SFX: {"type": "float", "min": 0.0, "max": 1.0},
		SETTINGS_KEYS.GAMEPLAY_FIRE_ON_RELEASE: {"type": "bool"},
		SETTINGS_KEYS.GAMEPLAY_AIM_MODE: {"type": "string", "options": ["mouse", "4dir", "auto"]},
		SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE: {"type": "bool"},
		SETTINGS_KEYS.GAMEPLAY_PAUSE_ON_FOCUS_LOSS: {"type": "bool"},
		SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS: {"type": "bool"},
		SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED: {"type": "bool"},
	}


func _capture_legacy_input_bindings(config: ConfigFile) -> void:
	for key: String in LEGACY_INPUT_DEFAULTS:
		var binding: String = String(LEGACY_INPUT_DEFAULTS[key])
		if config.has_section_key(SETTINGS_SECTION, key):
			var raw_value: Variant = config.get_value(SETTINGS_SECTION, key)
			if raw_value is String and KEYBOARD_BINDING_OPTIONS.has(String(raw_value)):
				binding = String(raw_value)
			else:
				_last_load_recovered = true
				push_warning("[Settings] invalid legacy input binding for %s; using default." % key)
		_legacy_input_bindings[key] = binding
