extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")

const REPLAY_FILE_NAME: String = "smoke_basic_run.replay"
const REPLAY_SEED: int = 20260619
const RECORD_FRAMES: int = 3

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_cleanup_smoke_file()
	Replay.set_enabled(true)
	Replay.clear_recording()
	RNG.set_run_seed(REPLAY_SEED)
	GameClock.reset()

	GameState.change_state(GameState.PLAYING, {
		"source": "replay_smoke",
		"scenario": "golden_basic_run",
	})
	for _index: int in range(RECORD_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame

	_expect(Replay.is_recording(), "Replay should start recording from PLAYING state")
	_expect(Replay.record_input_action(ACTIONS.MOVE_RIGHT, true, 1.0, "player_0"), "Replay should record registered input actions")
	_expect(Replay.record_input_action(ACTIONS.MOVE_RIGHT, false, 0.0, "player_0"), "Replay should record action release")
	_expect(Replay.record_decision(ANALYTICS_EVENTS.LEVEL_UP, {
		"level": 2,
		"choices": ["growth_damage_small", "growth_fire_rate_small", "growth_pickup_range_small"],
		"selected": "growth_damage_small",
	}), "Replay should record registered decision events")

	GameState.change_state(GameState.GAME_OVER, {"source": "replay_smoke"})
	var completed: Dictionary = Replay.snapshot()
	_expect(not Replay.is_recording(), "Replay should stop recording on GAME_OVER")
	_expect(String(completed.get("reason", "")) == String(GameState.GAME_OVER), "Replay should store stop reason")

	var path: String = Replay.save_recording(completed, REPLAY_FILE_NAME)
	_expect(not path.is_empty(), "Replay should save a .replay file")
	_expect(FileAccess.file_exists(path), "Replay file should exist after save")

	var loaded: Dictionary = Replay.load_recording(path)
	_expect(not loaded.is_empty(), "Replay should load a saved .replay file")
	_expect(_summaries_match(Replay.recording_summary(completed), Replay.recording_summary(loaded)), "Replay summary should roundtrip through disk")

	var envelope: Dictionary = Replay.load_replay_file(path)
	_expect(String(envelope.get("data_fingerprint", "")) == Replay.current_data_fingerprint(), "Replay envelope should include the current data fingerprint")

	_cleanup_smoke_file()
	GameState.change_state(GameState.MAIN_MENU, {"source": "replay_smoke"})
	_finish()


func _summaries_match(left: Dictionary, right: Dictionary) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _cleanup_smoke_file() -> void:
	var path: String = Replay.replay_root().path_join(REPLAY_FILE_NAME)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[ReplaySmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[ReplaySmoke] passed")
		get_tree().quit(0)
		return

	print("[ReplaySmoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
