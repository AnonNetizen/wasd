# Doc: docs/代码/replay.md
# Authority: docs/游戏设计文档.md §9.9, docs/游戏设计文档.md §9.18
class_name ReplayAutoload
extends Node


signal recording_enabled_changed(enabled: bool)
signal recording_started(recording: Dictionary)
signal recording_stopped(recording: Dictionary)
signal input_recorded(input_event: Dictionary)
signal decision_recorded(decision_event: Dictionary)
signal recording_cleared()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const MAX_INPUT_EVENTS: int = 4096
const MAX_DECISION_EVENTS: int = 512

var _enabled: bool = true
var _is_recording: bool = false
var _recording: Dictionary = {}
var _input_events: Array[Dictionary] = []
var _decision_events: Array[Dictionary] = []
var _dropped_input_count: int = 0
var _dropped_decision_count: int = 0


func _ready() -> void:
	set_enabled(bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS, true)))
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)
	if not GameState.state_changed.is_connected(_on_game_state_changed):
		GameState.state_changed.connect(_on_game_state_changed)


func start_recording(context: Dictionary = {}) -> bool:
	if not _enabled:
		return false
	if _is_recording:
		return false

	_is_recording = true
	_input_events.clear()
	_decision_events.clear()
	_dropped_input_count = 0
	_dropped_decision_count = 0
	_recording = {
		"schema_version": 1,
		"run_seed": RNG.run_seed(),
		"started_tick": GameClock.tick(),
		"started_time": GameClock.now(),
		"context": context.duplicate(true),
	}
	recording_started.emit(snapshot())
	return true


func stop_recording(reason: String = "") -> Dictionary:
	if not _is_recording:
		return {}

	_is_recording = false
	_recording["ended_tick"] = GameClock.tick()
	_recording["ended_time"] = GameClock.now()
	_recording["reason"] = reason
	_recording["dropped_input_events"] = _dropped_input_count
	_recording["dropped_decision_events"] = _dropped_decision_count

	var completed_recording: Dictionary = snapshot()
	Analytics.track_event(ANALYTICS_EVENTS.REPLAY_RECORDED, {
		"input_events": _input_events.size(),
		"decision_events": _decision_events.size(),
		"dropped_input_events": _dropped_input_count,
		"dropped_decision_events": _dropped_decision_count,
	})
	recording_stopped.emit(completed_recording)
	return completed_recording


func record_input_action(action_name: String, pressed: bool, strength: float = 1.0, participant_id: String = "") -> bool:
	if not _is_recording:
		return false
	if not _is_registered_action(action_name):
		push_error("[Replay] unknown input action: %s" % action_name)
		return false

	var input_event: Dictionary = {
		"action": action_name,
		"pressed": pressed,
		"strength": clampf(strength, 0.0, 1.0),
		"tick": GameClock.tick(),
		"time": GameClock.now(),
	}
	if not participant_id.is_empty():
		input_event["participant_id"] = participant_id

	_input_events.append(input_event)
	while _input_events.size() > MAX_INPUT_EVENTS:
		_input_events.pop_front()
		_dropped_input_count += 1

	input_recorded.emit(input_event.duplicate(true))
	return true


func record_decision(event_name: String, payload: Dictionary = {}) -> bool:
	if not _is_recording:
		return false
	if not _is_registered_analytics_event(event_name):
		push_error("[Replay] unknown decision event: %s" % event_name)
		return false

	var decision_event: Dictionary = {
		"event": event_name,
		"payload": payload.duplicate(true),
		"tick": GameClock.tick(),
		"time": GameClock.now(),
	}

	_decision_events.append(decision_event)
	while _decision_events.size() > MAX_DECISION_EVENTS:
		_decision_events.pop_front()
		_dropped_decision_count += 1

	decision_recorded.emit(decision_event.duplicate(true))
	return true


func clear_recording() -> void:
	_is_recording = false
	_recording.clear()
	_input_events.clear()
	_decision_events.clear()
	_dropped_input_count = 0
	_dropped_decision_count = 0
	recording_cleared.emit()


func snapshot() -> Dictionary:
	var recording_snapshot: Dictionary = _recording.duplicate(true)
	recording_snapshot["is_recording"] = _is_recording
	recording_snapshot["input_events"] = _copy_events(_input_events)
	recording_snapshot["decision_events"] = _copy_events(_decision_events)
	recording_snapshot["dropped_input_events"] = _dropped_input_count
	recording_snapshot["dropped_decision_events"] = _dropped_decision_count
	return recording_snapshot


func is_enabled() -> bool:
	return _enabled


func is_recording() -> bool:
	return _is_recording


func input_event_count() -> int:
	return _input_events.size()


func decision_event_count() -> int:
	return _decision_events.size()


func dropped_input_count() -> int:
	return _dropped_input_count


func dropped_decision_count() -> int:
	return _dropped_decision_count


func registered_actions() -> Array[String]:
	return ACTIONS.VALUES.duplicate()


func set_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return

	_enabled = enabled
	if not _enabled:
		clear_recording()
	recording_enabled_changed.emit(_enabled)


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS:
		set_enabled(bool(value))


func _on_game_state_changed(_old_state: StringName, new_state: StringName, context: Dictionary) -> void:
	if new_state == GameState.PLAYING and not _is_recording:
		start_recording(context)
		return

	if _is_recording and (new_state == GameState.GAME_OVER or new_state == GameState.RESULT or new_state == GameState.MAIN_MENU):
		stop_recording(String(new_state))


func _copy_events(source_events: Array[Dictionary]) -> Array[Dictionary]:
	var copied_events: Array[Dictionary] = []
	for source_event: Dictionary in source_events:
		copied_events.append(source_event.duplicate(true))
	return copied_events


func _is_registered_action(action_name: String) -> bool:
	if DataLoader != null and DataLoader.has_contract_value("actions", action_name):
		return true
	return ACTIONS.VALUES.has(action_name)


func _is_registered_analytics_event(event_name: String) -> bool:
	if DataLoader != null and DataLoader.has_contract_value("analytics_events", event_name):
		return true
	return ANALYTICS_EVENTS.VALUES.has(event_name)
