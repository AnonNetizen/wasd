extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")

const EXPECTED_ACTIONS: Array[String] = [
	ACTIONS.MOVE_RIGHT,
	ACTIONS.AIM_UP,
	ACTIONS.PAUSE,
	ACTIONS.UI_BACK,
]
const SMOKE_REPLAY_SEED: int = 20260619

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	Replay.set_enabled(true)
	Replay.clear_recording()
	RNG.set_run_seed(SMOKE_REPLAY_SEED)
	GameClock.reset()

	var boot_node: Node = get_parent()
	if boot_node == null or not boot_node.has_method("_start_gameplay_run"):
		_expect(false, "ReplayInputSmoke should be hosted by FormalClientBoot")
		_finish({})
		return
	boot_node.call("_start_gameplay_run")

	var run_loop: Node = await _wait_for_node("GameplayRunLoop")
	_expect(run_loop != null, "ReplayInputSmoke should mount GameplayRunLoop")
	if run_loop == null:
		_finish({})
		return

	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(Replay.is_recording(), "ReplayInputSmoke should start recording on PLAYING")

	Input.action_press(ACTIONS.MOVE_RIGHT)
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_release(ACTIONS.MOVE_RIGHT)
	await get_tree().physics_frame
	await get_tree().process_frame

	Input.action_press(ACTIONS.AIM_UP)
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_release(ACTIONS.AIM_UP)
	await get_tree().physics_frame
	await get_tree().process_frame

	await _push_action_once(ACTIONS.PAUSE)
	_expect(GameState.is_state(GameState.PAUSED), "ReplayInputSmoke should open PauseMenu after pause action")
	await _push_action_once(ACTIONS.UI_BACK)
	_expect(GameState.is_state(GameState.PLAYING), "ReplayInputSmoke should return to PLAYING after ui_back")

	GameState.change_state(GameState.GAME_OVER, {"source": "replay_input_smoke"})
	var completed: Dictionary = Replay.snapshot()
	var input_events: Array = completed.get("input_events", []) as Array
	_expect(input_events.size() >= 6, "ReplayInputSmoke should record multiple gameplay input events")
	for action_name: String in EXPECTED_ACTIONS:
		_expect(_has_input_action(input_events, action_name), "ReplayInputSmoke should record %s" % action_name)

	GameState.change_state(GameState.MAIN_MENU, {"source": "replay_input_smoke"})
	_finish(Replay.recording_summary(completed))


func _push_action_once(action_id: String) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = action_id
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().process_frame

	var release: InputEventAction = InputEventAction.new()
	release.action = action_id
	release.pressed = false
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _has_input_action(input_events: Array, action_name: String) -> bool:
	for input_event: Variant in input_events:
		if input_event is Dictionary and String((input_event as Dictionary).get("action", "")) == action_name:
			return true
	return false


func _wait_for_node(node_name: String) -> Node:
	for _index: int in range(60):
		await get_tree().process_frame
		var node: Node = _find_node_by_name(get_tree().root, node_name)
		if node != null:
			return node
	return null


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
	push_error("[ReplayInputSmoke] %s" % message)


func _finish(summary: Dictionary) -> void:
	Input.action_release(ACTIONS.MOVE_RIGHT)
	Input.action_release(ACTIONS.AIM_UP)

	if _failures.is_empty():
		print("[ReplayInputSmoke] passed; summary=%s" % JSON.stringify(summary))
		get_tree().quit(0)
		return

	print("[ReplayInputSmoke] failed; failures=%d first=%s" % [_failures.size(), _failures[0]])
	get_tree().quit(1)
