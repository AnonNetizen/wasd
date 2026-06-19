extends Node


const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")

const CAPTURE_FRAMES: int = 180
const CAPTURE_SECONDS: float = 3.0
const FRAME_SAMPLE_INTERVAL: int = 30
const GOLDEN_REPLAY_SEED: int = 20260619
const GOLDEN_REPLAY_FILE_NAME: String = "golden_basic_run.replay"
const NORMALIZED_CREATED_AT: String = "golden:golden_basic_run"
const OUTPUT_PATH: String = "res://tests/replays/golden_basic_run.replay"
const SCENARIO: String = "golden_basic_run"

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	Replay.set_enabled(true)
	Replay.clear_recording()
	RNG.set_run_seed(GOLDEN_REPLAY_SEED)
	GameClock.reset()

	var boot_node: Node = get_parent()
	if boot_node == null or not boot_node.has_method("_start_gameplay_run"):
		_expect(false, "GoldenReplayCapture should be hosted by FormalClientBoot")
		_finish("")
		return
	boot_node.call("_start_gameplay_run")

	var run_loop: Node = null
	for _index: int in range(30):
		await get_tree().process_frame
		run_loop = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if run_loop != null:
			break
	_expect(run_loop != null, "GoldenReplayCapture should run with GameplayRunLoop mounted")
	if run_loop == null:
		_finish("")
		return

	var frame_samples: Array[Dictionary] = []
	for frame_number: int in range(1, CAPTURE_FRAMES + 1):
		await get_tree().physics_frame
		await get_tree().process_frame
		if _should_capture_frame_sample(frame_number, CAPTURE_FRAMES):
			frame_samples.append(_frame_sample(run_loop, frame_number))

	_expect(Replay.is_recording(), "GoldenReplayCapture should record through Replay autoload")
	var run_summary: Dictionary = _runtime_summary(run_loop, frame_samples)
	GameState.change_state(GameState.GAME_OVER, {"source": "golden_replay_capture", "scenario": SCENARIO})

	var completed: Dictionary = Replay.snapshot()
	completed["ended_tick"] = CAPTURE_FRAMES
	completed["ended_time"] = CAPTURE_SECONDS
	completed["run_summary"] = run_summary
	var context: Dictionary = _dictionary_or_empty(completed.get("context", {}))
	context["scenario"] = SCENARIO
	context["capture_frames"] = CAPTURE_FRAMES
	completed["context"] = context

	var user_path: String = Replay.save_recording(completed, GOLDEN_REPLAY_FILE_NAME)
	_expect(not user_path.is_empty(), "GoldenReplayCapture should save a .replay file")
	if user_path.is_empty():
		_finish("")
		return

	var output_path: String = _copy_normalized_replay_to_project(user_path, OUTPUT_PATH)
	_expect(not output_path.is_empty(), "GoldenReplayCapture should copy replay to %s" % OUTPUT_PATH)
	if not output_path.is_empty():
		var envelope: Dictionary = Replay.load_replay_file(OUTPUT_PATH)
		_expect(not envelope.is_empty(), "GoldenReplayCapture output should load as a replay file")

	GameState.change_state(GameState.MAIN_MENU, {"source": "golden_replay_capture"})
	_finish(output_path)


func _runtime_summary(run_loop: Node, frame_samples: Array[Dictionary]) -> Dictionary:
	var snapshot: Dictionary = _run_snapshot(run_loop)
	return {
		"schema_version": 1,
		"scenario": SCENARIO,
		"capture_frames": CAPTURE_FRAMES,
		"frame_sample_interval": FRAME_SAMPLE_INTERVAL,
		"frame_samples": frame_samples,
		"state": String(GameState.current()),
		"level": int(snapshot.get("level", 1)),
		"xp": int(snapshot.get("xp", 0)),
		"kills": int(snapshot.get("kills", 0)),
		"player_moved_right": _player_position_x(snapshot) > 0.0,
		"player_aim_direction": _dictionary_or_empty(_dictionary_or_empty(snapshot.get("player", {})).get("aim_direction", {})),
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


func _frame_sample(run_loop: Node, frame_number: int) -> Dictionary:
	var snapshot: Dictionary = _run_snapshot(run_loop)
	return {
		"frame": frame_number,
		"state": String(GameState.current()),
		"level": int(snapshot.get("level", 1)),
		"xp": int(snapshot.get("xp", 0)),
		"kills": int(snapshot.get("kills", 0)),
		"player_moved_right": _player_position_x(snapshot) > 0.0,
		"player_aim_direction": _dictionary_or_empty(_dictionary_or_empty(snapshot.get("player", {})).get("aim_direction", {})),
		"active_enemies": _array_size(snapshot.get("enemies", [])),
		"bullets_present": _array_size(snapshot.get("bullets", [])) > 0,
		"active_pickups": _array_size(snapshot.get("pickups", [])),
	}


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


func _copy_normalized_replay_to_project(source_path: String, destination_path: String) -> String:
	if not FileAccess.file_exists(source_path):
		return ""

	var source_file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return ""
	var source_text: String = source_file.get_as_text()
	var created_at_pattern: RegEx = RegEx.new()
	created_at_pattern.compile("\"created_at\":\\s*\"[^\"]*\"")
	source_text = created_at_pattern.sub(source_text, "\"created_at\": \"%s\"" % NORMALIZED_CREATED_AT, true)

	var absolute_directory: String = ProjectSettings.globalize_path(destination_path.get_base_dir())
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if error != OK:
		return ""

	var destination_file: FileAccess = FileAccess.open(destination_path, FileAccess.WRITE)
	if destination_file == null:
		return ""
	destination_file.store_string(source_text)
	destination_file.flush()
	return destination_path


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


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[GoldenReplayCapture] %s" % message)


func _finish(output_path: String) -> void:
	if _failures.is_empty():
		print("[GoldenReplayCapture] passed; output=%s" % output_path)
		get_tree().quit(0)
		return

	print("[GoldenReplayCapture] failed; failures=%d first=%s" % [_failures.size(), _failures[0]])
	get_tree().quit(1)
