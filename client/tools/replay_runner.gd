extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")

const ARG_ALLOW_DATA_FINGERPRINT_MISMATCH: String = "--allow-data-fingerprint-mismatch"
const ARG_EXPECTATION_FILE: String = "--expectation-file"
const ARG_REPLAY_FILE: String = "--replay-file"
const ARG_RERUN_RUNTIME_SUMMARY: String = "--rerun-runtime-summary"
const FLOAT_TOLERANCE: float = 0.0001
const SMOKE_REPLAY_FILE_NAME: String = "runner_smoke_basic_run.replay"
const SMOKE_REPLAY_SEED: int = 20260619
const SMOKE_RECORD_FRAMES: int = 3

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var replay_path: String = _argument_value(ARG_REPLAY_FILE)
	var expected_summary: Dictionary = {}
	var cleanup_replay_after_run: bool = false
	if replay_path.is_empty():
		var smoke_payload: Dictionary = await _create_smoke_replay()
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

	Replay.set_enabled(false)
	Replay.clear_recording()
	RNG.set_run_seed(int(recording.get("run_seed", 0)))
	GameClock.reset()

	var boot_node: Node = get_parent()
	if boot_node == null or not boot_node.has_method("_start_gameplay_run"):
		_expect(false, "ReplayRunner runtime rerun should be hosted by FormalClientBoot")
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
		return {}

	for _index: int in range(capture_frames):
		await get_tree().physics_frame
		await get_tree().process_frame

	var summary: Dictionary = _runtime_summary(run_loop, capture_frames)
	GameState.change_state(GameState.MAIN_MENU, {"source": "replay_runner_rerun"})
	return summary


func _runtime_summary(run_loop: Node, capture_frames: int) -> Dictionary:
	var snapshot: Dictionary = {}
	if run_loop.has_method("create_run_snapshot"):
		snapshot = run_loop.call("create_run_snapshot") as Dictionary
	return {
		"schema_version": 1,
		"scenario": String(_dictionary_or_empty(snapshot.get("context", {})).get("scenario", "golden_basic_run")),
		"capture_frames": capture_frames,
		"state": String(GameState.current()),
		"level": int(snapshot.get("level", 1)),
		"xp": int(snapshot.get("xp", 0)),
		"kills": int(snapshot.get("kills", 0)),
		"active_enemies": _array_size(snapshot.get("enemies", [])),
		"active_bullets": _array_size(snapshot.get("bullets", [])),
		"active_pickups": _array_size(snapshot.get("pickups", [])),
		"pool_stats": {
			POOL_IDS.BULLET_BASIC: PoolManager.stats(POOL_IDS.BULLET_BASIC),
			POOL_IDS.ENEMY_CHASER: PoolManager.stats(POOL_IDS.ENEMY_CHASER),
			POOL_IDS.ENEMY_SWARM: PoolManager.stats(POOL_IDS.ENEMY_SWARM),
			POOL_IDS.PICKUP_ORB: PoolManager.stats(POOL_IDS.PICKUP_ORB),
		},
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
	var path: String = Replay.replay_root().path_join(SMOKE_REPLAY_FILE_NAME)
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
