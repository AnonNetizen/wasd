class_name SteamLabSave
extends RefCounted

enum RecordCategory {
	SINGLE,
	MULTIPLAYER,
}

const CONFIG_PATH: String = "user://save.cfg"
const SECTION_RECORDS: String = "records"
const SCHEMA_VERSION: int = 2
const KEY_SCHEMA_VERSION: String = "schema_version"
const KEY_BEST_SINGLE_SURVIVAL_SECONDS: String = "best_single_survival_seconds"
const KEY_BEST_MULTIPLAYER_SURVIVAL_SECONDS: String = "best_multiplayer_survival_seconds"
const LEGACY_KEY_BEST_SURVIVAL_SECONDS: String = "best_survival_seconds"

var _best_single_survival_seconds: float = 0.0
var _best_multiplayer_survival_seconds: float = 0.0
var _config_path: String = CONFIG_PATH
var _writes_blocked: bool = false


func _init(config_path: String = CONFIG_PATH) -> void:
	_config_path = config_path


static func format_survival_time(seconds: float) -> String:
	var total_seconds := maxi(0, int(seconds))
	var minutes := total_seconds / 60
	var remaining_seconds := total_seconds % 60
	return "%02d:%02d" % [minutes, remaining_seconds]


func load_save() -> bool:
	_best_single_survival_seconds = 0.0
	_best_multiplayer_survival_seconds = 0.0
	_writes_blocked = false
	if not FileAccess.file_exists(_config_path):
		return false

	var config := ConfigFile.new()
	var load_error := config.load(_config_path)
	if load_error != OK:
		return false

	var schema_version := _schema_version(config.get_value(SECTION_RECORDS, KEY_SCHEMA_VERSION, 0))
	if schema_version > SCHEMA_VERSION:
		_writes_blocked = true
		return false
	if config.has_section_key(SECTION_RECORDS, LEGACY_KEY_BEST_SURVIVAL_SECONDS):
		return save_records()
	if schema_version != SCHEMA_VERSION:
		return false

	_best_single_survival_seconds = _sanitize_seconds(
		config.get_value(SECTION_RECORDS, KEY_BEST_SINGLE_SURVIVAL_SECONDS, 0.0)
	)
	_best_multiplayer_survival_seconds = _sanitize_seconds(
		config.get_value(SECTION_RECORDS, KEY_BEST_MULTIPLAYER_SURVIVAL_SECONDS, 0.0)
	)
	return true


func save_records() -> bool:
	if _writes_blocked:
		return false
	var config := ConfigFile.new()
	config.set_value(SECTION_RECORDS, KEY_SCHEMA_VERSION, SCHEMA_VERSION)
	config.set_value(SECTION_RECORDS, KEY_BEST_SINGLE_SURVIVAL_SECONDS, _best_single_survival_seconds)
	config.set_value(SECTION_RECORDS, KEY_BEST_MULTIPLAYER_SURVIVAL_SECONDS, _best_multiplayer_survival_seconds)
	var file := FileAccess.open(_config_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(config.encode_to_text())
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error == OK


func best_survival_seconds(category: RecordCategory) -> float:
	match category:
		RecordCategory.SINGLE:
			return _best_single_survival_seconds
		RecordCategory.MULTIPLAYER:
			return _best_multiplayer_survival_seconds
		_:
			return 0.0


func record_survival_time(category: RecordCategory, seconds: float) -> bool:
	var sanitized_seconds := _sanitize_seconds(seconds)
	var previous_best := best_survival_seconds(category)
	if sanitized_seconds <= previous_best:
		return false
	if not _set_best_survival_seconds(category, sanitized_seconds):
		return false
	if save_records():
		return true
	_set_best_survival_seconds(category, previous_best)
	return false


func _set_best_survival_seconds(category: RecordCategory, seconds: float) -> bool:
	match category:
		RecordCategory.SINGLE:
			_best_single_survival_seconds = seconds
		RecordCategory.MULTIPLAYER:
			_best_multiplayer_survival_seconds = seconds
		_:
			return false
	return true


func _schema_version(value: Variant) -> int:
	if value is int:
		return int(value)
	if value is float:
		var number := float(value)
		if not is_nan(number) and not is_inf(number) and is_equal_approx(number, floorf(number)):
			return int(number)
	return 0


func _sanitize_seconds(value: Variant) -> float:
	var seconds := 0.0
	if value is int or value is float:
		seconds = float(value)
	elif value is String:
		var text := String(value).strip_edges()
		if text.is_valid_float():
			seconds = text.to_float()
	if is_nan(seconds) or is_inf(seconds) or seconds < 0.0:
		return 0.0
	return seconds
