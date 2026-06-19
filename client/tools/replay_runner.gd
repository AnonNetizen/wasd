extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const META_CURRENCIES := preload("res://scripts/contracts/meta_currencies.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const ARG_ALLOW_DATA_FINGERPRINT_MISMATCH: String = "--allow-data-fingerprint-mismatch"
const ARG_EXPECTATION_FILE: String = "--expectation-file"
const ARG_REPLAY_FILE: String = "--replay-file"
const ARG_RERUN_RUNTIME_SUMMARY: String = "--rerun-runtime-summary"
const FLOAT_TOLERANCE: float = 0.0001
const FRAME_SAMPLE_INTERVAL: int = 30
const INPUT_PLAYBACK_CAPTURE_FRAMES: int = 80
const INPUT_PLAYBACK_REPLAY_FILE_NAME: String = "runner_input_playback.replay"
const INPUT_PLAYBACK_REPLAY_SEED: int = 20260619
const INPUT_PLAYBACK_SCENARIO: String = "runner_input_playback"
const SMOKE_REPLAY_FILE_NAME: String = "runner_smoke_basic_run.replay"
const SMOKE_REPLAY_SEED: int = 20260619
const SMOKE_RECORD_FRAMES: int = 3

var _failures: Array[String] = []
var _runtime_save_backups: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var replay_path: String = _argument_value(ARG_REPLAY_FILE)
	var expected_summary: Dictionary = {}
	var cleanup_replay_after_run: bool = false
	if replay_path.is_empty():
		var smoke_payload: Dictionary = await _create_runtime_input_replay() if _has_argument(ARG_RERUN_RUNTIME_SUMMARY) else await _create_smoke_replay()
		replay_path = String(smoke_payload.get("path", ""))
		expected_summary = smoke_payload.get("summary", {}) as Dictionary
		cleanup_replay_after_run = true

	var expectation_file: String = _argument_value(ARG_EXPECTATION_FILE)
	if not expectation_file.is_empty():
		expected_summary = _read_expected_summary(expectation_file)

	_expect(not replay_path.is_empty(), "ReplayRunner should receive or create a replay file")
	if replay_path.is_empty():
		_finish(replay_path, {}, cleanup_replay_after_run)
		return

	var envelope: Dictionary = Replay.load_replay_file(replay_path)
	if envelope.is_empty():
		_expect(false, "ReplayRunner should load replay file: %s" % Replay.last_error())
		_finish(replay_path, {}, cleanup_replay_after_run)
		return

	var recording: Dictionary = envelope.get("recording", {}) as Dictionary
	var actual_summary: Dictionary = Replay.recording_summary(recording)
	if expected_summary.is_empty():
		expected_summary = envelope.get("summary", {}) as Dictionary

	_compare_data_fingerprint(envelope)
	if _has_argument(ARG_RERUN_RUNTIME_SUMMARY):
		var actual_run_summary: Dictionary = await _rerun_runtime_summary(recording)
		if not actual_run_summary.is_empty():
			actual_summary["run_summary"] = actual_run_summary
	_compare_summaries(expected_summary, actual_summary)
	_finish(replay_path, actual_summary, cleanup_replay_after_run)


func _create_smoke_replay() -> Dictionary:
	_cleanup_smoke_file()
	Replay.set_enabled(true)
	Replay.clear_recording()
	RNG.set_run_seed(SMOKE_REPLAY_SEED)
	GameClock.reset()

	GameState.change_state(GameState.PLAYING, {
		"source": "replay_runner",
		"scenario": "runner_smoke_basic_run",
	})
	for _index: int in range(SMOKE_RECORD_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame

	_expect(Replay.is_recording(), "ReplayRunner smoke replay should start recording")
	_expect(Replay.record_input_action(ACTIONS.MOVE_RIGHT, true, 1.0, "player_0"), "ReplayRunner smoke should record action press")
	_expect(Replay.record_input_action(ACTIONS.MOVE_RIGHT, false, 0.0, "player_0"), "ReplayRunner smoke should record action release")
	_expect(Replay.record_decision(ANALYTICS_EVENTS.LEVEL_UP, {
		"level": 2,
		"choices": ["growth_damage_small", "growth_fire_rate_small", "growth_pickup_range_small"],
		"selected": "growth_damage_small",
	}), "ReplayRunner smoke should record a decision event")

	GameState.change_state(GameState.GAME_OVER, {"source": "replay_runner"})
	var completed: Dictionary = Replay.snapshot()
	var path: String = Replay.save_recording(completed, SMOKE_REPLAY_FILE_NAME)
	_expect(not path.is_empty(), "ReplayRunner smoke replay should save a .replay file")
	GameState.change_state(GameState.MAIN_MENU, {"source": "replay_runner"})
	return {
		"path": path,
		"summary": Replay.recording_summary(completed),
	}


func _create_runtime_input_replay() -> Dictionary:
	_cleanup_replay_file(INPUT_PLAYBACK_REPLAY_FILE_NAME)
	var input_events: Array[Dictionary] = _input_playback_events()
	var recording: Dictionary = {
		"schema_version": 1,
		"run_seed": INPUT_PLAYBACK_REPLAY_SEED,
		"started_tick": 0,
		"started_time": 0.0,
		"ended_tick": INPUT_PLAYBACK_CAPTURE_FRAMES,
		"ended_time": 0.0,
		"reason": String(GameState.GAME_OVER),
		"context": {
			"source": "replay_runner",
			"scenario": INPUT_PLAYBACK_SCENARIO,
			"capture_frames": INPUT_PLAYBACK_CAPTURE_FRAMES,
		},
		"input_events": input_events,
		"decision_events": [],
		"dropped_input_events": 0,
		"dropped_decision_events": 0,
	}
	var run_summary: Dictionary = await _run_runtime_summary(recording, INPUT_PLAYBACK_CAPTURE_FRAMES)
	_expect(not run_summary.is_empty(), "ReplayRunner input playback smoke should produce a run_summary")
	if not run_summary.is_empty():
		recording["run_summary"] = run_summary

	var path: String = Replay.save_recording(recording, INPUT_PLAYBACK_REPLAY_FILE_NAME)
	_expect(not path.is_empty(), "ReplayRunner input playback smoke should save a .replay file")
	return {
		"path": path,
		"summary": Replay.recording_summary(recording),
	}


func _input_playback_events() -> Array[Dictionary]:
	return [
		_input_event(ACTIONS.MOVE_RIGHT, true, 1.0, 1),
		_input_event(ACTIONS.MOVE_RIGHT, false, 0.0, 30),
		_input_event(ACTIONS.AIM_UP, true, 1.0, 35),
		_input_event(ACTIONS.AIM_UP, false, 0.0, 40),
		_input_event(ACTIONS.PAUSE, true, 1.0, 45),
		_input_event(ACTIONS.PAUSE, false, 0.0, 45),
		_input_event(ACTIONS.UI_BACK, true, 1.0, 45),
		_input_event(ACTIONS.UI_BACK, false, 0.0, 45),
	]


func _input_event(action_name: String, pressed: bool, strength: float, tick: int) -> Dictionary:
	return {
		"action": action_name,
		"frame": tick,
		"pressed": pressed,
		"strength": strength,
		"tick": tick,
		"time": float(tick) / 60.0,
		"participant_id": "player_0",
	}


func _read_expected_summary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_expect(false, "ReplayRunner expectation file should exist: %s" % path)
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_expect(false, "ReplayRunner expectation file should be readable: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return (parsed as Dictionary).duplicate(true)

	_expect(false, "ReplayRunner expectation file should be a JSON object: %s" % path)
	return {}


func _compare_data_fingerprint(envelope: Dictionary) -> void:
	if _has_argument(ARG_ALLOW_DATA_FINGERPRINT_MISMATCH):
		return

	var actual_fingerprint: String = Replay.current_data_fingerprint()
	var expected_fingerprint: String = String(envelope.get("data_fingerprint", ""))
	_expect(expected_fingerprint == actual_fingerprint, "ReplayRunner data_fingerprint mismatch expected=%s actual=%s" % [
		expected_fingerprint,
		actual_fingerprint,
	])


func _compare_summaries(expected_summary: Dictionary, actual_summary: Dictionary) -> void:
	var diffs: Array[String] = []
	_collect_summary_diffs(expected_summary, actual_summary, "summary", diffs)
	if diffs.is_empty():
		return

	_expect(false, "ReplayRunner summary diff: %s" % diffs[0])


func _rerun_runtime_summary(recording: Dictionary) -> Dictionary:
	var expected_run_summary: Dictionary = _dictionary_or_empty(recording.get("run_summary", {}))
	_expect(not expected_run_summary.is_empty(), "ReplayRunner runtime rerun requires recording.run_summary")
	if expected_run_summary.is_empty():
		return {}

	var capture_frames: int = int(expected_run_summary.get("capture_frames", 0))
	_expect(capture_frames > 0, "ReplayRunner runtime rerun requires run_summary.capture_frames")
	if capture_frames <= 0:
		return {}

	return await _run_runtime_summary(recording, capture_frames)


func _run_runtime_summary(recording: Dictionary, capture_frames: int) -> Dictionary:
	var scenario: String = String(_dictionary_or_empty(recording.get("context", {})).get("scenario", "golden_basic_run"))
	_prepare_runtime_scenario(scenario)
	Replay.set_enabled(false)
	Replay.clear_recording()
	RNG.set_run_seed(int(recording.get("run_seed", 0)))
	GameClock.reset()

	var boot_node: Node = get_parent()
	if boot_node == null or not boot_node.has_method("_start_gameplay_run"):
		_expect(false, "ReplayRunner runtime rerun should be hosted by FormalClientBoot")
		_restore_runtime_scenario(scenario)
		return {}
	boot_node.call("_start_gameplay_run")

	var run_loop: Node = null
	for _index: int in range(30):
		await get_tree().process_frame
		run_loop = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if run_loop != null:
			break
	_expect(run_loop != null, "ReplayRunner runtime rerun should mount GameplayRunLoop")
	if run_loop == null:
		_restore_runtime_scenario(scenario)
		return {}

	var input_events: Array[Dictionary] = _sorted_input_events(recording.get("input_events", []))
	var runtime_events: Array[Dictionary] = _sorted_runtime_events(recording.get("runtime_events", []))
	var next_input_index: int = 0
	var next_runtime_index: int = 0
	var frame_samples: Array[Dictionary] = []
	for frame_number: int in range(1, capture_frames + 1):
		next_input_index = await _apply_due_input_events(input_events, next_input_index, frame_number)
		next_runtime_index = await _apply_due_runtime_events(runtime_events, next_runtime_index, frame_number, run_loop)
		await get_tree().physics_frame
		await get_tree().process_frame
		if _should_capture_frame_sample(frame_number, capture_frames):
			frame_samples.append(_frame_sample(run_loop, frame_number, scenario))

	next_input_index = await _apply_due_input_events(input_events, next_input_index, capture_frames + 1)
	next_runtime_index = await _apply_due_runtime_events(runtime_events, next_runtime_index, capture_frames + 1, run_loop)
	var summary: Dictionary = _runtime_summary(run_loop, capture_frames, scenario, frame_samples)
	_release_input_actions(input_events)
	GameState.change_state(GameState.MAIN_MENU, {"source": "replay_runner_rerun"})
	_restore_runtime_scenario(scenario)
	return summary


func _runtime_summary(run_loop: Node, capture_frames: int, scenario: String, frame_samples: Array[Dictionary]) -> Dictionary:
	var snapshot: Dictionary = _run_snapshot(run_loop)
	var summary: Dictionary = {
		"schema_version": 1,
		"scenario": scenario,
		"capture_frames": capture_frames,
		"frame_sample_interval": FRAME_SAMPLE_INTERVAL,
		"frame_samples": frame_samples,
		"state": String(GameState.current()),
		"ui_stack": UIManager.stack_size(),
		"level": int(snapshot.get("level", 1)),
		"xp": int(snapshot.get("xp", 0)),
		"kills": int(snapshot.get("kills", 0)),
		"player_moved_right": _player_position_x(snapshot) > 0.0,
		"player_aim_direction": _dictionary_or_empty(_dictionary_or_empty(snapshot.get("player", {})).get("aim_direction", {})),
		"active_pickups": _array_size(snapshot.get("pickups", [])),
	}
	if _uses_exact_runtime_counts(scenario):
		summary["active_enemies"] = _array_size(snapshot.get("enemies", []))
		summary["active_bullets"] = _array_size(snapshot.get("bullets", []))
		summary["pool_stats"] = {
			POOL_IDS.BULLET_BASIC: PoolManager.stats(POOL_IDS.BULLET_BASIC),
			POOL_IDS.ENEMY_CHASER: PoolManager.stats(POOL_IDS.ENEMY_CHASER),
			POOL_IDS.ENEMY_SWARM: PoolManager.stats(POOL_IDS.ENEMY_SWARM),
			POOL_IDS.PICKUP_ORB: PoolManager.stats(POOL_IDS.PICKUP_ORB),
		}
	else:
		summary["enemies_present"] = _array_size(snapshot.get("enemies", [])) > 0
		summary["bullets_present"] = _array_size(snapshot.get("bullets", [])) > 0
	if scenario == "golden_full_death":
		summary["player_defeated"] = GameState.is_state(GameState.GAME_OVER)
		summary["game_over_panel_visible"] = _find_node_by_name(get_tree().root, "GameOverPanel") != null
		summary["meta_save_exists"] = SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
		summary["run_save_exists"] = SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
		summary["meta_currency_amount"] = _meta_currency_amount()
	return summary


func _uses_exact_runtime_counts(scenario: String) -> bool:
	return not ["golden_pause_resume", "golden_full_death"].has(scenario)


func _frame_sample(run_loop: Node, frame_number: int, scenario: String) -> Dictionary:
	var snapshot: Dictionary = _run_snapshot(run_loop)
	var sample: Dictionary = {
		"frame": frame_number,
		"state": String(GameState.current()),
		"ui_stack": UIManager.stack_size(),
		"level": int(snapshot.get("level", 1)),
		"xp": int(snapshot.get("xp", 0)),
		"kills": int(snapshot.get("kills", 0)),
		"player_moved_right": _player_position_x(snapshot) > 0.0,
		"player_aim_direction": _dictionary_or_empty(_dictionary_or_empty(snapshot.get("player", {})).get("aim_direction", {})),
		"active_pickups": _array_size(snapshot.get("pickups", [])),
	}
	if _uses_exact_runtime_counts(scenario):
		sample["active_enemies"] = _array_size(snapshot.get("enemies", []))
	else:
		sample["enemies_present"] = _array_size(snapshot.get("enemies", [])) > 0
	sample["bullets_present"] = _array_size(snapshot.get("bullets", [])) > 0
	if scenario == "golden_full_death":
		sample["player_life"] = _player_life(snapshot)
		sample["game_over_panel_visible"] = _find_node_by_name(get_tree().root, "GameOverPanel") != null
	return sample


func _should_capture_frame_sample(frame_number: int, capture_frames: int) -> bool:
	return frame_number == capture_frames or frame_number % FRAME_SAMPLE_INTERVAL == 0


func _run_snapshot(run_loop: Node) -> Dictionary:
	if run_loop.has_method("create_run_snapshot"):
		return run_loop.call("create_run_snapshot") as Dictionary
	return {}


func _player_position_x(snapshot: Dictionary) -> float:
	var player_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("player", {}))
	var position: Dictionary = _dictionary_or_empty(player_snapshot.get("position", {}))
	return float(position.get("x", 0.0))


func _player_life(snapshot: Dictionary) -> float:
	var player_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("player", {}))
	return float(player_snapshot.get("life_points", 0.0))


func _meta_currency_amount() -> int:
	if not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META):
		return 0
	var profile: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	var currencies: Dictionary = _dictionary_or_empty(profile.get("currencies", {}))
	return int(currencies.get(META_CURRENCIES.META_ESSENCE, 0))


func _sorted_input_events(raw_input_events: Variant) -> Array[Dictionary]:
	var input_events: Array[Dictionary] = []
	if not raw_input_events is Array:
		return input_events
	for raw_input_event: Variant in raw_input_events as Array:
		if raw_input_event is Dictionary:
			input_events.append((raw_input_event as Dictionary).duplicate(true))
	input_events.sort_custom(_sort_input_events_by_tick)
	return input_events


func _sorted_runtime_events(raw_runtime_events: Variant) -> Array[Dictionary]:
	var runtime_events: Array[Dictionary] = []
	if not raw_runtime_events is Array:
		return runtime_events
	for raw_runtime_event: Variant in raw_runtime_events as Array:
		if raw_runtime_event is Dictionary:
			runtime_events.append((raw_runtime_event as Dictionary).duplicate(true))
	runtime_events.sort_custom(_sort_runtime_events_by_frame)
	return runtime_events


func _sort_input_events_by_tick(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("tick", 0)) < int(right.get("tick", 0))


func _sort_runtime_events_by_frame(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("frame", left.get("tick", 0))) < int(right.get("frame", right.get("tick", 0)))


func _apply_due_input_events(input_events: Array[Dictionary], next_input_index: int, frame_number: int) -> int:
	while next_input_index < input_events.size():
		var input_event: Dictionary = input_events[next_input_index]
		if not _is_input_event_due(input_event, frame_number):
			return next_input_index
		await _apply_input_event(input_event)
		next_input_index += 1
	return next_input_index


func _is_input_event_due(input_event: Dictionary, frame_number: int) -> bool:
	if input_event.has("frame"):
		return int(input_event.get("frame", 0)) <= frame_number
	return int(input_event.get("tick", 0)) <= GameClock.tick()


func _apply_due_runtime_events(runtime_events: Array[Dictionary], next_runtime_index: int, frame_number: int, run_loop: Node) -> int:
	while next_runtime_index < runtime_events.size():
		var runtime_event: Dictionary = runtime_events[next_runtime_index]
		if not _is_runtime_event_due(runtime_event, frame_number):
			return next_runtime_index
		await _apply_runtime_event(runtime_event, run_loop)
		next_runtime_index += 1
	return next_runtime_index


func _is_runtime_event_due(runtime_event: Dictionary, frame_number: int) -> bool:
	if runtime_event.has("frame"):
		return int(runtime_event.get("frame", 0)) <= frame_number
	return int(runtime_event.get("tick", 0)) <= GameClock.tick()


func _apply_runtime_event(runtime_event: Dictionary, run_loop: Node) -> void:
	var event_name: String = String(runtime_event.get("event", ""))
	if event_name == "defeat_player":
		await _defeat_player(run_loop)


func _defeat_player(run_loop: Node) -> void:
	var player: Node = _find_node_by_name(run_loop, "Player")
	if player == null:
		_expect(false, "ReplayRunner full death runtime event should find Player")
		return
	var damage_source: Node = Node.new()
	damage_source.name = "ReplayRunnerFullDeathDamageSource"
	run_loop.add_child(damage_source)
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		float(player.call("max_life")),
		DAMAGE_TYPES.PHYSICAL,
		damage_source,
		player,
		"team_enemy",
		"team_player"
	)
	var result: Dictionary = Combat.apply_damage(player, info)
	_expect(bool(result.get("applied", false)), "ReplayRunner full death damage should apply")
	_expect(bool(result.get("defeated", false)), "ReplayRunner full death should defeat player")
	damage_source.queue_free()
	await get_tree().process_frame


func _apply_input_event(input_event: Dictionary) -> void:
	var action_name: String = String(input_event.get("action", ""))
	if action_name.is_empty():
		return
	var pressed: bool = bool(input_event.get("pressed", false))
	var strength: float = clampf(float(input_event.get("strength", 1.0 if pressed else 0.0)), 0.0, 1.0)
	if pressed:
		Input.action_press(action_name, strength)
	else:
		Input.action_release(action_name)

	var event: InputEventAction = InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = strength
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _release_input_actions(input_events: Array[Dictionary]) -> void:
	var released_actions: Dictionary = {}
	for input_event: Dictionary in input_events:
		var action_name: String = String(input_event.get("action", ""))
		if action_name.is_empty() or released_actions.has(action_name):
			continue
		Input.action_release(action_name)
		released_actions[action_name] = true


func _prepare_runtime_scenario(scenario: String) -> void:
	if scenario != "golden_full_death":
		return
	_runtime_save_backups.clear()
	_runtime_save_backups[SAVE_KINDS.RUN] = _save_backup(SAVE_KINDS.RUN)
	_runtime_save_backups[SAVE_KINDS.META] = _save_backup(SAVE_KINDS.META)
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)


func _restore_runtime_scenario(scenario: String) -> void:
	if scenario != "golden_full_death":
		return
	for kind: String in [SAVE_KINDS.RUN, SAVE_KINDS.META]:
		var backup: Dictionary = _dictionary_or_empty(_runtime_save_backups.get(kind, {}))
		if bool(backup.get("existed", false)):
			SaveManager.save(SaveManager.DEFAULT_SLOT, kind, _dictionary_or_empty(backup.get("payload", {})))
		else:
			SaveManager.delete(SaveManager.DEFAULT_SLOT, kind)


func _save_backup(kind: String) -> Dictionary:
	if not SaveManager.has_save(SaveManager.DEFAULT_SLOT, kind):
		return {"existed": false, "payload": {}}
	return {
		"existed": true,
		"payload": SaveManager.load(SaveManager.DEFAULT_SLOT, kind),
	}


func _collect_summary_diffs(expected_value: Variant, actual_value: Variant, path: String, diffs: Array[String]) -> void:
	if not diffs.is_empty():
		return

	if expected_value is Dictionary and actual_value is Dictionary:
		var expected_dictionary: Dictionary = expected_value as Dictionary
		var actual_dictionary: Dictionary = actual_value as Dictionary
		var keys: Array = expected_dictionary.keys()
		keys.sort()
		for key: Variant in keys:
			var key_name: String = String(key)
			var child_path: String = "%s.%s" % [path, key_name]
			if not actual_dictionary.has(key):
				diffs.append("%s missing actual value expected=%s" % [child_path, _format_value(expected_dictionary[key])])
				return
			_collect_summary_diffs(expected_dictionary[key], actual_dictionary[key], child_path, diffs)
			if not diffs.is_empty():
				return
		var actual_keys: Array = actual_dictionary.keys()
		actual_keys.sort()
		for key: Variant in actual_keys:
			if not expected_dictionary.has(key):
				diffs.append("%s.%s unexpected actual value=%s" % [path, String(key), _format_value(actual_dictionary[key])])
				return
		return

	if expected_value is Array and actual_value is Array:
		var expected_array: Array = expected_value as Array
		var actual_array: Array = actual_value as Array
		if expected_array.size() != actual_array.size():
			diffs.append("%s expected size=%d actual size=%d" % [path, expected_array.size(), actual_array.size()])
			return
		for index: int in range(expected_array.size()):
			_collect_summary_diffs(expected_array[index], actual_array[index], "%s[%d]" % [path, index], diffs)
			if not diffs.is_empty():
				return
		return

	if expected_value is float or actual_value is float:
		var expected_float: float = float(expected_value)
		var actual_float: float = float(actual_value)
		if absf(expected_float - actual_float) > FLOAT_TOLERANCE:
			diffs.append("%s expected=%s actual=%s" % [path, _format_value(expected_value), _format_value(actual_value)])
		return

	if expected_value != actual_value:
		diffs.append("%s expected=%s actual=%s" % [path, _format_value(expected_value), _format_value(actual_value)])


func _format_value(value: Variant) -> String:
	return JSON.stringify(value)


func _argument_value(flag: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == flag and index + 1 < args.size():
			return args[index + 1]
	return ""


func _has_argument(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _array_size(value: Variant) -> int:
	if value is Array:
		return (value as Array).size()
	return 0


func _find_node_by_name(root_node: Node, target_name: String) -> Node:
	if root_node == null:
		return null
	if root_node.name == target_name:
		return root_node
	for child: Node in root_node.get_children():
		var match_node: Node = _find_node_by_name(child, target_name)
		if match_node != null:
			return match_node
	return null


func _cleanup_smoke_file() -> void:
	_cleanup_replay_file(SMOKE_REPLAY_FILE_NAME)


func _cleanup_replay_file(file_name: String) -> void:
	var path: String = Replay.replay_root().path_join(file_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[ReplayRunner] %s" % message)


func _finish(replay_path: String, summary: Dictionary, cleanup_replay_after_run: bool) -> void:
	if cleanup_replay_after_run:
		_cleanup_smoke_file()

	if _failures.is_empty():
		print("[ReplayRunner] passed; file=%s summary=%s" % [replay_path, JSON.stringify(summary)])
		get_tree().quit(0)
		return

	print("[ReplayRunner] failed; failures=%d first=%s" % [_failures.size(), _failures[0]])
	get_tree().quit(1)
