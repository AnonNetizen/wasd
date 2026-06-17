# Doc: docs/代码/analytics.md
# Authority: docs/游戏设计文档.md §9.6, docs/词表与契约.md §4
class_name AnalyticsAutoload
extends Node


signal event_tracked(event_data: Dictionary)
signal analytics_enabled_changed(enabled: bool)
signal events_cleared()

const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const MAX_BUFFERED_EVENTS: int = 256

var _events: Array[Dictionary] = []
var _enabled: bool = true
var _dropped_count: int = 0


func _ready() -> void:
	set_enabled(bool(Settings.get_value(SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED, true)))
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)


func track_event(event_name: String, params: Dictionary = {}) -> bool:
	if not _is_registered_event(event_name):
		push_error("[Analytics] unknown event: %s" % event_name)
		return false

	if not _enabled:
		return false

	var event_data: Dictionary = {
		"name": event_name,
		"params": params.duplicate(true),
		"tick": GameClock.tick(),
		"time": GameClock.now(),
		"state": String(GameState.current()),
	}

	_events.append(event_data)
	while _events.size() > MAX_BUFFERED_EVENTS:
		_events.pop_front()
		_dropped_count += 1

	event_tracked.emit(event_data.duplicate(true))
	return true


func events() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for event_data: Dictionary in _events:
		snapshot.append(event_data.duplicate(true))
	return snapshot


func clear_events() -> void:
	_events.clear()
	events_cleared.emit()


func event_count() -> int:
	return _events.size()


func dropped_count() -> int:
	return _dropped_count


func is_enabled() -> bool:
	return _enabled


func set_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return

	_enabled = enabled
	if not _enabled:
		clear_events()
	analytics_enabled_changed.emit(_enabled)


func registered_events() -> Array[String]:
	return ANALYTICS_EVENTS.VALUES.duplicate()


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == SETTINGS_KEYS.PRIVACY_ANALYTICS_ENABLED:
		set_enabled(bool(value))


func _is_registered_event(event_name: String) -> bool:
	if DataLoader != null and DataLoader.has_contract_value("analytics_events", event_name):
		return true
	return ANALYTICS_EVENTS.VALUES.has(event_name)
