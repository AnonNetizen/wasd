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
const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const GEAR_MOD_PLACEMENT_OUTCOMES := preload(
	"res://scripts/contracts/gear_mod_placement_outcomes.gd"
)
const TELEPORT_CHOICE_OUTCOMES := preload(
	"res://scripts/contracts/teleport_choice_outcomes.gd"
)
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const REPLAY_SCHEMA_VERSION: int = 10
const REPLAY_FILE_SCHEMA_VERSION: int = 10
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
	_trim_input_events_to_capacity()

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
	if _may_be_gear_mod_semantic_trigger(input_event):
		_trim_input_events_to_capacity(MAX_INPUT_EVENTS + 1)
	else:
		_trim_input_events_to_capacity()

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
	if not _is_valid_decision_event(decision_event):
		push_error("[Replay] invalid decision payload for event: %s" % event_name)
		return false
	if event_name == ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT:
		_discard_same_tick_gear_mod_trigger_input(payload)
	elif event_name == ANALYTICS_EVENTS.TELEPORT_CHOICE:
		_discard_same_tick_teleport_trigger_input(payload)
	_trim_input_events_to_capacity()

	_decision_events.append(decision_event)
	while _decision_events.size() > MAX_DECISION_EVENTS:
		_decision_events.pop_front()
		_dropped_decision_count += 1

	decision_recorded.emit(decision_event.duplicate(true))
	return true


func _discard_same_tick_gear_mod_trigger_input(payload: Dictionary) -> void:
	var trigger_action: String = ""
	match String(payload.get("outcome", "")):
		GEAR_MOD_PLACEMENT_OUTCOMES.PLACED:
			trigger_action = ACTIONS.UI_CONFIRM
		GEAR_MOD_PLACEMENT_OUTCOMES.CANCELLED:
			trigger_action = ACTIONS.UI_BACK
	if trigger_action.is_empty():
		return
	var decision_tick: int = GameClock.tick()
	for index: int in range(_input_events.size() - 1, -1, -1):
		var input_event: Dictionary = _input_events[index]
		if int(input_event.get("tick", -1)) != decision_tick:
			continue
		if (
			String(input_event.get("action", "")) == trigger_action
			and String(input_event.get("value_type", "")) == "bool"
			and bool(input_event.get("value", false))
		):
			_input_events.remove_at(index)
			return


func _discard_same_tick_teleport_trigger_input(payload: Dictionary) -> void:
	var trigger_action: String = ""
	match String(payload.get("outcome", "")):
		TELEPORT_CHOICE_OUTCOMES.TELEPORTED:
			trigger_action = ACTIONS.UI_CONFIRM
		TELEPORT_CHOICE_OUTCOMES.CANCELLED:
			trigger_action = ACTIONS.UI_BACK
	if trigger_action.is_empty():
		return
	var decision_tick: int = GameClock.tick()
	for index: int in range(_input_events.size() - 1, -1, -1):
		var input_event: Dictionary = _input_events[index]
		if int(input_event.get("tick", -1)) != decision_tick:
			continue
		if (
			String(input_event.get("action", "")) == trigger_action
			and String(input_event.get("value_type", "")) == "bool"
			and bool(input_event.get("value", false))
		):
			_input_events.remove_at(index)
			return


func _may_be_gear_mod_semantic_trigger(input_event: Dictionary) -> bool:
	return (
		String(input_event.get("value_type", "")) == "bool"
		and bool(input_event.get("value", false))
		and String(input_event.get("action", ""))
		in [ACTIONS.UI_CONFIRM, ACTIONS.UI_BACK]
	)


func _trim_input_events_to_capacity(
	capacity: int = MAX_INPUT_EVENTS
	) -> void:
	while _input_events.size() > capacity:
		_input_events.pop_front()
		_dropped_input_count += 1


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
	var dropped_event_error: String = _dropped_event_validation_error(recording_payload)
	if not dropped_event_error.is_empty():
		_set_error(dropped_event_error)
		return ""
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
	_normalize_wire_integer_fields(envelope)
	var validation_error: String = _validate_file_envelope(envelope)
	if not validation_error.is_empty():
		_set_error(validation_error)
		replay_load_failed.emit(path, _last_error)
		return {}

	replay_loaded.emit(path, envelope.duplicate(true))
	return envelope.duplicate(true)


func _normalize_wire_integer_fields(envelope: Dictionary) -> void:
	var recording_raw: Variant = envelope.get("recording", null)
	if not recording_raw is Dictionary:
		return
	var recording: Dictionary = recording_raw as Dictionary
	var decisions_raw: Variant = recording.get("decision_events", null)
	if not decisions_raw is Array:
		return
	for raw_event: Variant in decisions_raw as Array:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event as Dictionary
		_normalize_integral_field(event, "tick")
		if String(event.get("event", "")) != ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT:
			continue
		var payload_raw: Variant = event.get("payload", null)
		if not payload_raw is Dictionary:
			continue
		var payload: Dictionary = payload_raw as Dictionary
		_normalize_integral_field(payload, "instance_id")
		_normalize_integral_field(payload, "x")
		_normalize_integral_field(payload, "y")


func _normalize_integral_field(target: Dictionary, field_name: String) -> void:
	var raw_value: Variant = target.get(field_name, null)
	if not raw_value is float:
		return
	var value: float = float(raw_value)
	if not is_finite(value) or value != floor(value) or absf(value) > 9007199254740992.0:
		return
	target[field_name] = int(value)


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
		"mod_environment": _current_mod_environment(),
		"data_fingerprint": _data_fingerprint(),
		"recording_hash": _payload_hash(recording_payload),
		"recording": recording_payload,
		"summary": recording_summary(recording_payload),
	}


func _validate_file_envelope(envelope: Dictionary) -> String:
	for field_name: String in ["file_schema_version", "created_at", "game_version", "mod_environment", "data_fingerprint", "recording_hash", "recording", "summary"]:
		if not envelope.has(field_name):
			return "[Replay] replay missing field: %s" % field_name
	if not envelope["recording"] is Dictionary:
		return "[Replay] replay recording must be a Dictionary"

	var file_schema_version: int = int(envelope.get("file_schema_version", 0))
	if file_schema_version != REPLAY_FILE_SCHEMA_VERSION:
		return "[Replay] unsupported replay file schema: %d; expected %d" % [file_schema_version, REPLAY_FILE_SCHEMA_VERSION]
	var environment_error: String = _validate_mod_environment(
		envelope.get("mod_environment", null)
	)
	if not environment_error.is_empty():
		return environment_error
	var stored_fingerprint: String = String(envelope.get("data_fingerprint", ""))
	var current_fingerprint: String = _data_fingerprint()
	if stored_fingerprint != current_fingerprint:
		return "[Replay] data_fingerprint mismatch"

	var recording: Dictionary = envelope["recording"] as Dictionary
	var recording_schema_version: int = int(recording.get("schema_version", 0))
	if recording_schema_version != REPLAY_SCHEMA_VERSION:
		return "[Replay] unsupported replay recording schema: %d; expected %d" % [recording_schema_version, REPLAY_SCHEMA_VERSION]
	var dropped_event_error: String = _dropped_event_validation_error(recording)
	if not dropped_event_error.is_empty():
		return dropped_event_error
	if not _is_valid_recording(recording):
		return "[Replay] replay recording payload is invalid"
	var expected_hash: String = _payload_hash(recording)
	if String(envelope.get("recording_hash", "")) != expected_hash:
		return "[Replay] replay recording_hash mismatch"
	return ""


func _is_valid_recording(recording: Dictionary) -> bool:
	if int(recording.get("schema_version", 0)) != REPLAY_SCHEMA_VERSION:
		return false
	if not _dropped_event_validation_error(recording).is_empty():
		return false
	if not recording.has("run_seed") or not recording.has("started_tick") or not recording.has("started_time"):
		return false
	if not recording.get("context", {}) is Dictionary:
		return false
	var context: Dictionary = recording.get("context", {}) as Dictionary
	if not _is_valid_content_availability(
		context.get("content_availability", {})
	):
		return false
	if not recording.get("input_events", []) is Array:
		return false
	if not recording.get("decision_events", []) is Array:
		return false
	for raw_event: Variant in recording.get("input_events", []) as Array:
		if not raw_event is Dictionary or not _is_valid_input_event(raw_event as Dictionary):
			return false
	for raw_event: Variant in recording.get("decision_events", []) as Array:
		if not raw_event is Dictionary or not _is_valid_decision_event(raw_event as Dictionary):
			return false
	return true


func _dropped_event_validation_error(recording: Dictionary) -> String:
	var dropped_counts: Array[int] = []
	for field_name: String in [
		"dropped_input_events",
		"dropped_decision_events",
	]:
		var raw_count: Variant = recording.get(field_name, 0)
		if not raw_count is int and not raw_count is float:
			return "[Replay] %s must be a non-negative integer" % field_name
		var numeric_count: float = float(raw_count)
		if (
			not is_finite(numeric_count)
			or numeric_count < 0.0
			or numeric_count != floor(numeric_count)
		):
			return "[Replay] %s must be a non-negative integer" % field_name
		dropped_counts.append(int(numeric_count))
	if dropped_counts[0] > 0 or dropped_counts[1] > 0:
		return (
			"[Replay] incomplete recording dropped events: input=%d decision=%d"
			% dropped_counts
		)
	return ""


func _is_valid_content_availability(raw_value: Variant) -> bool:
	if not raw_value is Dictionary:
		return false
	var snapshot: Dictionary = raw_value as Dictionary
	for content_type: String in CONTENT_UNLOCK_TYPES.VALUES:
		var raw_ids: Variant = snapshot.get(content_type, [])
		if not raw_ids is Array:
			return false
		var ids: Array[String] = []
		for raw_id: Variant in raw_ids as Array:
			if not raw_id is String:
				return false
			var content_id: String = String(raw_id).strip_edges()
			if content_id.is_empty() or ids.has(content_id):
				return false
			ids.append(content_id)
		var sorted_ids: Array[String] = ids.duplicate()
		sorted_ids.sort()
		if ids != sorted_ids:
			return false
		if (
			content_type == CONTENT_UNLOCK_TYPES.CHARACTER
			and ids.size() < 2
		):
			return false
		if (
			content_type != CONTENT_UNLOCK_TYPES.CHARACTER
			and ids.is_empty()
		):
			return false
	return true


func _is_valid_input_event(event: Dictionary) -> bool:
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


func _is_valid_decision_event(event: Dictionary) -> bool:
	for field_name: String in ["event", "payload", "tick", "time"]:
		if not event.has(field_name):
			return false
	if not event["event"] is String or not event["payload"] is Dictionary:
		return false
	if not event["tick"] is int or not (event["time"] is int or event["time"] is float):
		return false
	var event_name: String = String(event["event"])
	if not _is_registered_analytics_event(event_name):
		return false
	if event_name != ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT:
		if event_name == ANALYTICS_EVENTS.TELEPORT_CHOICE:
			return _is_valid_teleport_choice_payload(
				event["payload"] as Dictionary
			)
		return true
	return _is_valid_gear_mod_placement_payload(
		event["payload"] as Dictionary
	)


func _is_valid_gear_mod_placement_payload(payload: Dictionary) -> bool:
	for field_name: String in ["instance_id", "mod_id", "outcome"]:
		if not payload.has(field_name):
			return false
	if not payload["instance_id"] is int or int(payload["instance_id"]) <= 0:
		return false
	if not payload["mod_id"] is String or String(payload["mod_id"]).is_empty():
		return false
	var outcome: String = String(payload["outcome"])
	if not GEAR_MOD_PLACEMENT_OUTCOMES.VALUES.has(outcome):
		return false
	var expected_keys: Array[String] = ["instance_id", "mod_id", "outcome"]
	if outcome == GEAR_MOD_PLACEMENT_OUTCOMES.PLACED:
		expected_keys.append_array(["x", "y"])
		if not payload.get("x") is int or not payload.get("y") is int:
			return false
		var coord := Vector2i(int(payload["x"]), int(payload["y"]))
		if coord.x < 0 or coord.x >= 7 or coord.y < 0 or coord.y >= 7:
			return false
	var actual_keys: Array[String] = []
	for raw_key: Variant in payload.keys():
		actual_keys.append(String(raw_key))
	actual_keys.sort()
	expected_keys.sort()
	return actual_keys == expected_keys


func _is_valid_teleport_choice_payload(payload: Dictionary) -> bool:
	if (
		not payload.get("outcome") is String
		or not payload.get("source_station_id") is String
		or String(payload.get("source_station_id", "")).is_empty()
	):
		return false
	var outcome: String = String(payload.get("outcome", ""))
	var expected_keys: Array[String] = [
		"outcome",
		"source_station_id",
	]
	if outcome == TELEPORT_CHOICE_OUTCOMES.TELEPORTED:
		expected_keys.append("destination_station_id")
		if (
			not payload.get("destination_station_id") is String
			or String(
				payload.get("destination_station_id", "")
			).is_empty()
			or String(payload.get("destination_station_id", ""))
			== String(payload.get("source_station_id", ""))
		):
			return false
	elif outcome != TELEPORT_CHOICE_OUTCOMES.CANCELLED:
		return false
	var actual_keys: Array[String] = []
	for raw_key: Variant in payload.keys():
		actual_keys.append(String(raw_key))
	actual_keys.sort()
	expected_keys.sort()
	return actual_keys == expected_keys


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
		"effect_gameplay": (
			DataLoader.effect_gameplay_fingerprint_payload()
			if DataLoader.has_method("effect_gameplay_fingerprint_payload")
			else {}
		),
		"gear_mod_gameplay": (
			DataLoader.gear_mod_gameplay_fingerprint_payload()
		),
		"mod_environment": _current_mod_environment(),
	}
	return _payload_hash(payload)


func _current_mod_environment() -> Array[Dictionary]:
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("mod_environment"):
		return []
	var raw_environment: Variant = loader.call("mod_environment")
	if not raw_environment is Array:
		return []
	var environment: Array[Dictionary] = []
	for raw_entry: Variant in raw_environment as Array:
		if raw_entry is Dictionary:
			environment.append((raw_entry as Dictionary).duplicate(true))
	return environment


func _validate_mod_environment(raw_environment: Variant) -> String:
	if not raw_environment is Array:
		return "[Replay] mod_environment must be an Array"
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("validate_environment"):
		return "" if (raw_environment as Array).is_empty() else "[Replay] ModLoader unavailable for recorded mod environment"
	var result: Variant = loader.call("validate_environment", raw_environment)
	if not result is Dictionary:
		return "[Replay] ModLoader returned an invalid environment validation result"
	if bool((result as Dictionary).get("ok", false)):
		return ""
	return "[Replay] mod environment mismatch: %s" % String(
		(result as Dictionary).get("reason", "unknown mismatch")
	)


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
