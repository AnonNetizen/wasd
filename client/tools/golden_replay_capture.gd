extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const META_CURRENCIES := preload("res://scripts/contracts/meta_currencies.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const CAPTURE_FRAMES: int = 180
const CAPTURE_SECONDS: float = 3.0
const DEFAULT_SCENARIO: String = "golden_basic_run"
const FRAME_SAMPLE_INTERVAL: int = 30
const FULL_DEATH_FRAME: int = 75
const GOLDEN_REPLAY_SEED: int = 20260619
const SCENARIO_ARGUMENT: String = "--golden-scenario"

var _failures: Array[String] = []
var _scenario: String = DEFAULT_SCENARIO
var _scenario_save_backups: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_scenario = _capture_scenario()
	_prepare_scenario()
	Replay.set_enabled(true)
	Replay.clear_recording()
	RNG.set_run_seed(GOLDEN_REPLAY_SEED)
	GameClock.reset()

	var boot_node: Node = get_parent()
	if boot_node == null or not boot_node.has_method("_start_gameplay_run"):
		_expect(false, "GoldenReplayCapture should be hosted by FormalClientBoot")
		_restore_scenario_saves()
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
		_restore_scenario_saves()
		_finish("")
		return

	var frame_samples: Array[Dictionary] = []
	for frame_number: int in range(1, CAPTURE_FRAMES + 1):
		await _apply_scenario_inputs(frame_number)
		await _apply_scenario_runtime_events(run_loop, frame_number)
		await get_tree().physics_frame
		await get_tree().process_frame
		if _should_capture_frame_sample(frame_number, CAPTURE_FRAMES):
			frame_samples.append(_frame_sample(run_loop, frame_number))

	if _scenario == "golden_full_death":
		_expect(not Replay.is_recording(), "GoldenReplayCapture full death should stop recording on GAME_OVER")
		_expect(GameState.is_state(GameState.GAME_OVER), "GoldenReplayCapture full death should enter GAME_OVER")
	else:
		_expect(Replay.is_recording(), "GoldenReplayCapture should record through Replay autoload")
	var run_summary: Dictionary = _runtime_summary(run_loop, frame_samples)
	_release_scenario_actions()
	GameState.change_state(GameState.GAME_OVER, {"source": "golden_replay_capture", "scenario": _scenario})

	var completed: Dictionary = Replay.snapshot()
	if _scenario == "golden_pause_resume":
		completed["input_events"] = _pause_resume_input_events()
	elif _scenario == "golden_full_death":
		completed["runtime_events"] = _full_death_runtime_events()
	completed["ended_tick"] = CAPTURE_FRAMES
	completed["ended_time"] = CAPTURE_SECONDS
	completed["run_summary"] = run_summary
	var context: Dictionary = _dictionary_or_empty(completed.get("context", {}))
	context["scenario"] = _scenario
	context["capture_frames"] = CAPTURE_FRAMES
	completed["context"] = context

	var user_path: String = Replay.save_recording(completed, _replay_file_name())
	_expect(not user_path.is_empty(), "GoldenReplayCapture should save a .replay file")
	if user_path.is_empty():
		_restore_scenario_saves()
		_finish("")
		return

	var output_path: String = _copy_normalized_replay_to_project(user_path, _output_path())
	_expect(not output_path.is_empty(), "GoldenReplayCapture should copy replay to %s" % _output_path())
	if not output_path.is_empty():
		var envelope: Dictionary = Replay.load_replay_file(_output_path())
		_expect(not envelope.is_empty(), "GoldenReplayCapture output should load as a replay file")

	GameState.change_state(GameState.MAIN_MENU, {"source": "golden_replay_capture"})
	_restore_scenario_saves()
	_finish(output_path)


func _runtime_summary(run_loop: Node, frame_samples: Array[Dictionary]) -> Dictionary:
	var snapshot: Dictionary = _run_snapshot(run_loop)
	var summary: Dictionary = {
		"schema_version": 1,
		"scenario": _scenario,
		"capture_frames": CAPTURE_FRAMES,
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
	if _uses_exact_runtime_counts(_scenario):
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
	if _scenario == "golden_full_death":
		summary["player_defeated"] = GameState.is_state(GameState.GAME_OVER)
		summary["game_over_panel_visible"] = _find_node_by_name(get_tree().root, "GameOverPanel") != null
		summary["meta_save_exists"] = SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
		summary["run_save_exists"] = SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
		summary["meta_currency_amount"] = _meta_currency_amount()
	return summary


func _uses_exact_runtime_counts(scenario: String) -> bool:
	return scenario == DEFAULT_SCENARIO


func _frame_sample(run_loop: Node, frame_number: int) -> Dictionary:
	var snapshot: Dictionary = _run_snapshot(run_loop)
	var sample: Dictionary = {
		"frame": frame_number,
		"state": String(GameState.current()),
		"ui_stack": UIManager.stack_size(),
		"level": int(snapshot.get("level", 1)),
		"xp": int(snapshot.get("xp", 0)),
		"kills": int(snapshot.get("kills", 0)),
		"player_life": _player_life(snapshot),
		"player_moved_right": _player_position_x(snapshot) > 0.0,
		"player_aim_direction": _dictionary_or_empty(_dictionary_or_empty(snapshot.get("player", {})).get("aim_direction", {})),
		"weapon_cooldown_ready": _weapon_cooldown_remaining(snapshot) <= 0.0,
		"active_pickups": _array_size(snapshot.get("pickups", [])),
		"pickups_present": _array_size(snapshot.get("pickups", [])) > 0,
		"enemy_types": _enemy_types(snapshot),
	}
	if _uses_exact_runtime_counts(_scenario):
		sample["active_enemies"] = _array_size(snapshot.get("enemies", []))
	else:
		sample["enemies_present"] = _array_size(snapshot.get("enemies", [])) > 0
	sample["bullets_present"] = _array_size(snapshot.get("bullets", [])) > 0
	if _scenario == "golden_full_death":
		sample["game_over_panel_visible"] = _find_node_by_name(get_tree().root, "GameOverPanel") != null
	return sample


func _should_capture_frame_sample(frame_number: int, capture_frames: int) -> bool:
	return frame_number == capture_frames or frame_number % FRAME_SAMPLE_INTERVAL == 0


func _run_snapshot(run_loop: Node) -> Dictionary:
	if run_loop.has_method("create_run_snapshot"):
		return run_loop.call("create_run_snapshot") as Dictionary
	return {}


func _apply_scenario_inputs(frame_number: int) -> void:
	if _scenario != "golden_pause_resume":
		return
	if frame_number == 30:
		await _apply_input_event(ACTIONS.PAUSE, true, 1.0)
		await _apply_input_event(ACTIONS.PAUSE, false, 0.0)
	elif frame_number == 45:
		await _apply_input_event(ACTIONS.UI_BACK, true, 1.0)
		await _apply_input_event(ACTIONS.UI_BACK, false, 0.0)


func _apply_input_event(action_name: String, pressed: bool, strength: float) -> void:
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


func _apply_scenario_runtime_events(run_loop: Node, frame_number: int) -> void:
	if _scenario != "golden_full_death" or frame_number != FULL_DEATH_FRAME:
		return
	await _defeat_player(run_loop)


func _defeat_player(run_loop: Node) -> void:
	var player: Node = _find_node_by_name(run_loop, "Player")
	if player == null:
		_expect(false, "GoldenReplayCapture full death should find Player")
		return
	var damage_source: Node = Node.new()
	damage_source.name = "GoldenFullDeathDamageSource"
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
	_expect(bool(result.get("applied", false)), "GoldenReplayCapture full death damage should apply")
	_expect(bool(result.get("defeated", false)), "GoldenReplayCapture full death should defeat player")
	damage_source.queue_free()
	await get_tree().process_frame


func _release_scenario_actions() -> void:
	Input.action_release(ACTIONS.PAUSE)
	Input.action_release(ACTIONS.UI_BACK)


func _prepare_scenario() -> void:
	if _scenario != "golden_full_death":
		return
	_scenario_save_backups.clear()
	_scenario_save_backups[SAVE_KINDS.RUN] = _save_backup(SAVE_KINDS.RUN)
	_scenario_save_backups[SAVE_KINDS.META] = _save_backup(SAVE_KINDS.META)
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)


func _restore_scenario_saves() -> void:
	if _scenario != "golden_full_death":
		return
	for kind: String in [SAVE_KINDS.RUN, SAVE_KINDS.META]:
		var backup: Dictionary = _dictionary_or_empty(_scenario_save_backups.get(kind, {}))
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


func _capture_scenario() -> String:
	var requested_scenario: String = _argument_value(SCENARIO_ARGUMENT)
	if ["golden_pause_resume", "golden_full_death"].has(requested_scenario):
		return requested_scenario
	return DEFAULT_SCENARIO


func _pause_resume_input_events() -> Array[Dictionary]:
	return [
		_input_event(ACTIONS.PAUSE, true, 1.0, 25),
		_input_event(ACTIONS.PAUSE, false, 0.0, 25),
		_input_event(ACTIONS.UI_BACK, true, 1.0, 40),
		_input_event(ACTIONS.UI_BACK, false, 0.0, 40),
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


func _full_death_runtime_events() -> Array[Dictionary]:
	return [
		{
			"event": "defeat_player",
			"frame": FULL_DEATH_FRAME,
			"tick": FULL_DEATH_FRAME,
			"time": float(FULL_DEATH_FRAME) / 60.0,
		},
	]


func _argument_value(flag: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == flag and index + 1 < args.size():
			return args[index + 1]
	return ""


func _replay_file_name() -> String:
	return "%s.replay" % _scenario


func _output_path() -> String:
	return "res://tests/replays/%s" % _replay_file_name()


func _player_position_x(snapshot: Dictionary) -> float:
	var player_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("player", {}))
	var position: Dictionary = _dictionary_or_empty(player_snapshot.get("position", {}))
	return float(position.get("x", 0.0))


func _player_life(snapshot: Dictionary) -> float:
	var player_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("player", {}))
	return float(player_snapshot.get("life_points", 0.0))


func _weapon_cooldown_remaining(snapshot: Dictionary) -> float:
	var weapon_snapshot: Dictionary = _dictionary_or_empty(snapshot.get("weapon", {}))
	return float(weapon_snapshot.get("cooldown_remaining", 0.0))


func _enemy_types(snapshot: Dictionary) -> Array[String]:
	var types: Array[String] = []
	for raw_enemy: Variant in _array_or_empty(snapshot.get("enemies", [])):
		if not raw_enemy is Dictionary:
			continue
		var enemy_id: String = String((raw_enemy as Dictionary).get("enemy_id", ""))
		if not enemy_id.is_empty() and not types.has(enemy_id):
			types.append(enemy_id)
	types.sort()
	return types


func _meta_currency_amount() -> int:
	if not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META):
		return 0
	var profile: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	var currencies: Dictionary = _dictionary_or_empty(profile.get("currencies", {}))
	return int(currencies.get(META_CURRENCIES.META_ESSENCE, 0))


func _copy_normalized_replay_to_project(source_path: String, destination_path: String) -> String:
	if not FileAccess.file_exists(source_path):
		return ""

	var source_file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return ""
	var source_text: String = source_file.get_as_text()
	var created_at_pattern: RegEx = RegEx.new()
	created_at_pattern.compile("\"created_at\":\\s*\"[^\"]*\"")
	source_text = created_at_pattern.sub(source_text, "\"created_at\": \"golden:%s\"" % _scenario, true)

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


func _array_or_empty(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


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
