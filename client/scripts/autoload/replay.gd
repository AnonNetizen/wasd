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
signal replay_saved(path: String, envelope: Dictionary)
signal replay_loaded(path: String, envelope: Dictionary)
signal replay_load_failed(path: String, error: String)

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const REPLAY_SCHEMA_VERSION: int = 2
const REPLAY_FILE_SCHEMA_VERSION: int = 2
const LEGACY_REPLAY_SCHEMA_VERSION: int = 1
const DEFAULT_PARTICIPANT_ID: String = "player_0"
const REPLAY_ROOT: String = "user://replays"
const REPLAY_EXTENSION: String = ".replay"
const MAX_INPUT_EVENTS: int = 4096
const MAX_DECISION_EVENTS: int = 512

var _enabled: bool = true
var _is_recording: bool = false
var _recording: Dictionary = {}
var _input_events: Array[Dictionary] = []
var _decision_events: Array[Dictionary] = []
var _dropped_input_count: int = 0
var _dropped_decision_count: int = 0
var _last_error: String = ""


func _ready() -> void:
	set_enabled(bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_RECORD_REPLAYS, true)))
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)
	if not GameState.state_changed.is_connected(_on_game_state_changed):
		GameState.state_changed.connect(_on_game_state_changed)
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)
	if not InputService.action_released.is_connected(_on_input_action_released):
		InputService.action_released.connect(_on_input_action_released)
	if not InputService.vector_changed.is_connected(_on_input_vector_changed):
		InputService.vector_changed.connect(_on_input_vector_changed)


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
		"schema_version": REPLAY_SCHEMA_VERSION,
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


func record_input_action(action_name: String, pressed: bool, _strength: float = 1.0, participant_id: String = DEFAULT_PARTICIPANT_ID) -> bool:
	return record_input_value(action_name, pressed, participant_id)


func record_input_value(action_name: String, value: Variant, participant_id: String = DEFAULT_PARTICIPANT_ID) -> bool:
	if not _is_recording:
		return false
	if not _is_registered_action(action_name):
		push_error("[Replay] unknown input action: %s" % action_name)
		return false
	var value_type: String = ""
	var stored_value: Variant = null
	if value is bool:
		if action_name in [ACTIONS.MOVE, ACTIONS.AIM, ACTIONS.POINTER_POSITION]:
			return false
		value_type = "bool"
		stored_value = bool(value)
	elif value is Vector2:
		if action_name not in [ACTIONS.MOVE, ACTIONS.AIM]:
			return false
		value_type = "vector2"
		var vector_value: Vector2 = value as Vector2
		if vector_value.length_squared() > 1.0:
			vector_value = vector_value.normalized()
		stored_value = [vector_value.x, vector_value.y]
	else:
		push_error("[Replay] unsupported input value type for %s" % action_name)
		return false

	var input_event: Dictionary = {
		"action": action_name,
		"value_type": value_type,
		"value": stored_value,
		"tick": GameClock.tick(),
		"time": GameClock.now(),
		"participant_id": participant_id if not participant_id.is_empty() else DEFAULT_PARTICIPANT_ID,
	}

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


func save_recording(recording: Dictionary = {}, file_name: String = "") -> String:
	_last_error = ""
	var recording_payload: Dictionary = recording.duplicate(true)
	if recording_payload.is_empty():
		recording_payload = snapshot()
	if not _is_valid_recording(recording_payload):
		_set_error("[Replay] cannot save invalid recording")
		return ""
	if not _ensure_replay_root():
		return ""

	var path: String = REPLAY_ROOT.path_join(_normalized_file_name(file_name))
	var envelope: Dictionary = _build_file_envelope(recording_payload)
	if not _write_json_file(path, envelope):
		return ""

	replay_saved.emit(path, envelope.duplicate(true))
	return path


func load_recording(path: String) -> Dictionary:
	var envelope: Dictionary = load_replay_file(path)
	if envelope.is_empty():
		return {}
	return (envelope.get("recording", {}) as Dictionary).duplicate(true)


func load_replay_file(path: String) -> Dictionary:
	_last_error = ""
	if path.strip_edges().is_empty():
		_set_error("[Replay] replay path is empty")
		replay_load_failed.emit(path, _last_error)
		return {}
	if not FileAccess.file_exists(path):
		_set_error("[Replay] replay file not found: %s" % path)
		replay_load_failed.emit(path, _last_error)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_error("[Replay] replay file is not readable: %s" % path)
		replay_load_failed.emit(path, _last_error)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_set_error("[Replay] replay file is not a JSON object: %s" % path)
		replay_load_failed.emit(path, _last_error)
		return {}

	var envelope: Dictionary = parsed as Dictionary
	var validation_error: String = _validate_file_envelope(envelope)
	if not validation_error.is_empty():
		_set_error(validation_error)
		replay_load_failed.emit(path, _last_error)
		return {}

	var migrated_envelope: Dictionary = _migrate_envelope_to_current(envelope)
	replay_loaded.emit(path, migrated_envelope.duplicate(true))
	return migrated_envelope.duplicate(true)


func replay_root() -> String:
	return REPLAY_ROOT


func last_error() -> String:
	return _last_error


func current_data_fingerprint() -> String:
	return _data_fingerprint()


func recording_summary(recording: Dictionary) -> Dictionary:
	var input_events: Array = recording.get("input_events", []) as Array
	var decision_events: Array = recording.get("decision_events", []) as Array
	var summary: Dictionary = {
		"schema_version": int(recording.get("schema_version", 0)),
		"run_seed": int(recording.get("run_seed", 0)),
		"started_tick": int(recording.get("started_tick", 0)),
		"ended_tick": int(recording.get("ended_tick", 0)),
		"started_time": float(recording.get("started_time", 0.0)),
		"ended_time": float(recording.get("ended_time", 0.0)),
		"reason": String(recording.get("reason", "")),
		"input_events": input_events.size(),
		"decision_events": decision_events.size(),
		"dropped_input_events": int(recording.get("dropped_input_events", 0)),
		"dropped_decision_events": int(recording.get("dropped_decision_events", 0)),
	}
	var run_summary: Variant = recording.get("run_summary", {})
	if run_summary is Dictionary and not (run_summary as Dictionary).is_empty():
		summary["run_summary"] = (run_summary as Dictionary).duplicate(true)
	return summary


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
		if InputService.playback_active():
			return
		start_recording(context)
		return

	if _is_recording and (new_state == GameState.GAME_OVER or new_state == GameState.RESULT or new_state == GameState.MAIN_MENU):
		stop_recording(String(new_state))


func _on_input_action_pressed(action_id: StringName, participant_id: String) -> void:
	if InputService.playback_active():
		return
	record_input_value(String(action_id), true, participant_id)


func _on_input_action_released(action_id: StringName, participant_id: String) -> void:
	if InputService.playback_active():
		return
	record_input_value(String(action_id), false, participant_id)


func _on_input_vector_changed(action_id: StringName, value: Vector2, participant_id: String) -> void:
	if InputService.playback_active():
		return
	if action_id != StringName(ACTIONS.MOVE) and action_id != StringName(ACTIONS.AIM):
		return
	record_input_value(String(action_id), value, participant_id)


func _copy_events(source_events: Array[Dictionary]) -> Array[Dictionary]:
	var copied_events: Array[Dictionary] = []
	for source_event: Dictionary in source_events:
		copied_events.append(source_event.duplicate(true))
	return copied_events


func _build_file_envelope(recording: Dictionary) -> Dictionary:
	var recording_payload: Dictionary = recording.duplicate(true)
	return {
		"file_schema_version": REPLAY_FILE_SCHEMA_VERSION,
		"created_at": Time.get_datetime_string_from_system(false, false),
		"game_version": SaveManager.GAME_VERSION,
		"data_fingerprint": _data_fingerprint(),
		"recording_hash": _payload_hash(recording_payload),
		"recording": recording_payload,
		"summary": recording_summary(recording_payload),
	}


func _validate_file_envelope(envelope: Dictionary) -> String:
	for field_name: String in ["file_schema_version", "created_at", "game_version", "data_fingerprint", "recording_hash", "recording", "summary"]:
		if not envelope.has(field_name):
			return "[Replay] replay missing field: %s" % field_name
	if not envelope["recording"] is Dictionary:
		return "[Replay] replay recording must be a Dictionary"

	var file_schema_version: int = int(envelope.get("file_schema_version", 0))
	if file_schema_version < LEGACY_REPLAY_SCHEMA_VERSION or file_schema_version > REPLAY_FILE_SCHEMA_VERSION:
		return "[Replay] replay file schema is newer than supported: %d > %d" % [file_schema_version, REPLAY_FILE_SCHEMA_VERSION]

	var recording: Dictionary = envelope["recording"] as Dictionary
	if not _is_valid_recording_for_version(recording, file_schema_version):
		return "[Replay] replay recording payload is invalid"
	var expected_hash: String = _payload_hash(recording)
	if String(envelope.get("recording_hash", "")) != expected_hash:
		return "[Replay] replay recording_hash mismatch"
	return ""


func _is_valid_recording(recording: Dictionary) -> bool:
	if int(recording.get("schema_version", 0)) != REPLAY_SCHEMA_VERSION:
		return false
	if not recording.has("run_seed") or not recording.has("started_tick") or not recording.has("started_time"):
		return false
	if not recording.get("input_events", []) is Array:
		return false
	if not recording.get("decision_events", []) is Array:
		return false
	for raw_event: Variant in recording.get("input_events", []) as Array:
		if not raw_event is Dictionary or not _is_valid_v2_input_event(raw_event as Dictionary):
			return false
	return true


func _is_valid_recording_for_version(recording: Dictionary, file_schema_version: int) -> bool:
	if file_schema_version == LEGACY_REPLAY_SCHEMA_VERSION:
		return _is_valid_v1_recording(recording)
	return _is_valid_recording(recording)


func _is_valid_v1_recording(recording: Dictionary) -> bool:
	if int(recording.get("schema_version", 0)) != LEGACY_REPLAY_SCHEMA_VERSION:
		return false
	if not recording.has("run_seed") or not recording.has("started_tick") or not recording.has("started_time"):
		return false
	if not recording.get("input_events", []) is Array or not recording.get("decision_events", []) is Array:
		return false
	for raw_event: Variant in recording.get("input_events", []) as Array:
		if not raw_event is Dictionary:
			return false
		var event: Dictionary = raw_event as Dictionary
		if not event.get("action", "") is String or not event.get("pressed", false) is bool:
			return false
		if not _is_registered_action(String(event.get("action", ""))):
			return false
		if not event.has("tick") or not event.has("time"):
			return false
	return true


func _is_valid_v2_input_event(event: Dictionary) -> bool:
	for field_name: String in ["action", "value_type", "value", "tick", "time", "participant_id"]:
		if not event.has(field_name):
			return false
	if not event["action"] is String or not event["participant_id"] is String:
		return false
	var action_name: String = String(event["action"])
	if not _is_registered_action(action_name) or String(event["participant_id"]).is_empty():
		return false
	var value_type: String = String(event["value_type"])
	if value_type == "bool":
		return event["value"] is bool and action_name not in [ACTIONS.MOVE, ACTIONS.AIM, ACTIONS.POINTER_POSITION]
	if value_type != "vector2" or not event["value"] is Array:
		return false
	if action_name not in [ACTIONS.MOVE, ACTIONS.AIM]:
		return false
	var components: Array = event["value"] as Array
	return components.size() == 2 and (components[0] is int or components[0] is float) and (components[1] is int or components[1] is float)


func _migrate_envelope_to_current(envelope: Dictionary) -> Dictionary:
	if int(envelope.get("file_schema_version", 0)) == REPLAY_FILE_SCHEMA_VERSION:
		return envelope.duplicate(true)
	var migrated: Dictionary = envelope.duplicate(true)
	var recording: Dictionary = (migrated.get("recording", {}) as Dictionary).duplicate(true)
	recording["schema_version"] = REPLAY_SCHEMA_VERSION
	recording["input_events"] = _migrate_v1_input_events(recording.get("input_events", []) as Array)
	migrated["file_schema_version"] = REPLAY_FILE_SCHEMA_VERSION
	migrated["recording"] = recording
	migrated["recording_hash"] = _payload_hash(recording)
	migrated["summary"] = recording_summary(recording)
	return migrated


func _migrate_v1_input_events(source_events: Array) -> Array[Dictionary]:
	var migrated: Array[Dictionary] = []
	var directional_state: Dictionary = {}
	var last_vectors: Dictionary = {
		ACTIONS.MOVE: Vector2.ZERO,
		ACTIONS.AIM: Vector2.ZERO,
	}
	for raw_event: Variant in source_events:
		var event: Dictionary = raw_event as Dictionary
		var action_name: String = String(event.get("action", ""))
		var vector_action: String = _legacy_vector_action(action_name)
		if vector_action.is_empty():
			migrated.append(_v2_event_from_v1(event, action_name, bool(event.get("pressed", false))))
			continue
		directional_state[action_name] = bool(event.get("pressed", false))
		var vector_value: Vector2 = _legacy_vector_value(vector_action, directional_state)
		var previous: Vector2 = last_vectors.get(vector_action, Vector2.ZERO) as Vector2
		if previous.is_equal_approx(vector_value):
			continue
		last_vectors[vector_action] = vector_value
		migrated.append(_v2_event_from_v1(event, vector_action, vector_value))
	return migrated


func _v2_event_from_v1(source_event: Dictionary, action_name: String, value: Variant) -> Dictionary:
	var migrated: Dictionary = {
		"action": action_name,
		"value_type": "vector2" if value is Vector2 else "bool",
		"value": [value.x, value.y] if value is Vector2 else bool(value),
		"tick": int(source_event.get("tick", 0)),
		"time": float(source_event.get("time", 0.0)),
		"participant_id": String(source_event.get("participant_id", DEFAULT_PARTICIPANT_ID)),
	}
	return migrated


func _legacy_vector_action(action_name: String) -> String:
	if action_name in [ACTIONS.MOVE_UP, ACTIONS.MOVE_DOWN, ACTIONS.MOVE_LEFT, ACTIONS.MOVE_RIGHT]:
		return ACTIONS.MOVE
	if action_name in [ACTIONS.AIM_UP, ACTIONS.AIM_DOWN, ACTIONS.AIM_LEFT, ACTIONS.AIM_RIGHT]:
		return ACTIONS.AIM
	return ""


func _legacy_vector_value(vector_action: String, state: Dictionary) -> Vector2:
	var value: Vector2 = Vector2.ZERO
	if vector_action == ACTIONS.MOVE:
		value = Vector2(
			float(int(bool(state.get(ACTIONS.MOVE_RIGHT, false))) - int(bool(state.get(ACTIONS.MOVE_LEFT, false)))),
			float(int(bool(state.get(ACTIONS.MOVE_DOWN, false))) - int(bool(state.get(ACTIONS.MOVE_UP, false))))
		)
	else:
		value = Vector2(
			float(int(bool(state.get(ACTIONS.AIM_RIGHT, false))) - int(bool(state.get(ACTIONS.AIM_LEFT, false)))),
			float(int(bool(state.get(ACTIONS.AIM_DOWN, false))) - int(bool(state.get(ACTIONS.AIM_UP, false))))
		)
	return value.normalized() if value.length_squared() > 1.0 else value


func _ensure_replay_root() -> bool:
	var error: Error = DirAccess.make_dir_recursive_absolute(REPLAY_ROOT)
	if error != OK:
		_set_error("[Replay] failed to create replay directory: %s" % REPLAY_ROOT)
		return false
	return true


func _write_json_file(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_error("[Replay] failed to open replay file for writing: %s" % path)
		return false

	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	return true


func _normalized_file_name(file_name: String) -> String:
	var normalized: String = file_name.strip_edges()
	if normalized.is_empty():
		normalized = "replay_%s" % Time.get_datetime_string_from_system(false, false).replace(":", "-")
	normalized = normalized.get_file()
	if normalized.contains(".."):
		normalized = "replay_%s" % Time.get_datetime_string_from_system(false, false).replace(":", "-")
	if not normalized.ends_with(REPLAY_EXTENSION):
		normalized = "%s%s" % [normalized, REPLAY_EXTENSION]
	return normalized


func _data_fingerprint() -> String:
	var payload: Dictionary = {
		"contracts": DataLoader.contracts(),
		"schema_counts": DataLoader.schema_counts(),
	}
	return _payload_hash(payload)


func _payload_hash(payload: Dictionary) -> String:
	return _stable_serialize(payload).sha256_text()


func _stable_serialize(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array = dictionary.keys()
		keys.sort()
		var parts: Array[String] = []
		for key: Variant in keys:
			parts.append("%s:%s" % [JSON.stringify(String(key)), _stable_serialize(dictionary[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var array_value: Array = value as Array
		var parts: Array[String] = []
		for item: Variant in array_value:
			parts.append(_stable_serialize(item))
		return "[%s]" % ",".join(parts)
	if value is int:
		return String.num_int64(int(value))
	if value is float:
		var number: float = float(value)
		if is_equal_approx(number, roundf(number)):
			return String.num_int64(int(number))
		return String.num(number)
	return JSON.stringify(value)


func _set_error(message: String) -> void:
	_last_error = message
	push_error(message)


func _is_registered_action(action_name: String) -> bool:
	if DataLoader != null and DataLoader.has_contract_value("actions", action_name):
		return true
	return ACTIONS.VALUES.has(action_name)


func _is_registered_analytics_event(event_name: String) -> bool:
	if DataLoader != null and DataLoader.has_contract_value("analytics_events", event_name):
		return true
	return ANALYTICS_EVENTS.VALUES.has(event_name)
