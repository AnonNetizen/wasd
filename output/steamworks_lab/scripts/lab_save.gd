class_name SteamLabSave
extends RefCounted

const CONFIG_PATH: String = "user://save.cfg"
const SECTION_RECORDS: String = "records"
const KEY_BEST_SURVIVAL_SECONDS: String = "best_survival_seconds"

var best_survival_seconds: float = 0.0


static func format_survival_time(seconds: float) -> String:
	var total_seconds := maxi(0, int(seconds))
	var minutes := total_seconds / 60
	var remaining_seconds := total_seconds % 60
	return "%02d:%02d" % [minutes, remaining_seconds]


func load_save() -> bool:
	best_survival_seconds = 0.0
	if not FileAccess.file_exists(CONFIG_PATH):
		return false

	var config := ConfigFile.new()
	var load_error := config.load(CONFIG_PATH)
	if load_error != OK:
		return false

	var raw_value: Variant = config.get_value(SECTION_RECORDS, KEY_BEST_SURVIVAL_SECONDS, 0.0)
	best_survival_seconds = _sanitize_seconds(raw_value)
	return true


func save_records() -> bool:
	var config := ConfigFile.new()
	config.set_value(SECTION_RECORDS, KEY_BEST_SURVIVAL_SECONDS, best_survival_seconds)
	return config.save(CONFIG_PATH) == OK


func record_survival_time(seconds: float) -> bool:
	var sanitized_seconds := _sanitize_seconds(seconds)
	if sanitized_seconds <= best_survival_seconds:
		return false
	best_survival_seconds = sanitized_seconds
	save_records()
	return true


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
