extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")

const EXPECTED_ACTIONS: Array[String] = [
	ACTIONS.MOVE,
	ACTIONS.AIM,
	ACTIONS.FIRE,
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

	await _inject_key(KEY_D, true)
	await _inject_key(KEY_D, false)
	await _inject_key(KEY_UP, true)
	await _inject_key(KEY_UP, false)
	await _inject_mouse_motion(Vector2(720.0, 420.0), Vector2(8.0, -3.0))
	await _inject_mouse_button(MOUSE_BUTTON_LEFT, true)
	await _inject_mouse_button(MOUSE_BUTTON_LEFT, false)

	await _inject_key(KEY_ESCAPE, true)
	await _inject_key(KEY_ESCAPE, false)
	_expect(GameState.is_state(GameState.PAUSED), "ReplayInputSmoke should open PauseMenu after pause action")
	await _inject_key(KEY_ESCAPE, true)
	await _inject_key(KEY_ESCAPE, false)
	await _wait_for_game_state(GameState.PLAYING)
	_expect(GameState.is_state(GameState.PLAYING), "ReplayInputSmoke should return to PLAYING after ui_back")

	var events_before_playback: int = (Replay.snapshot().get("input_events", []) as Array).size()
	InputService.set_playback_active(true)
	await _inject_key(KEY_W, true)
	_expect(InputService.vector(ACTIONS.MOVE).is_zero_approx(), "physical input should not contaminate replay playback")
	_expect(InputService.inject_playback_value(ACTIONS.MOVE, Vector2(-2.0, 0.0)), "playback should accept movement Vector2")
	_expect(InputService.vector(ACTIONS.MOVE).is_equal_approx(Vector2.LEFT), "playback should normalize movement Vector2")
	await get_tree().physics_frame
	await get_tree().process_frame
	var events_after_playback: int = (Replay.snapshot().get("input_events", []) as Array).size()
	_expect(events_after_playback == events_before_playback, "playback and physical device state should not be re-recorded")
	await _inject_key(KEY_W, false)
	InputService.clear_playback_values()
	InputService.set_playback_active(false)

	GameState.change_state(GameState.GAME_OVER, {"source": "replay_input_smoke"})
	var completed: Dictionary = Replay.snapshot()
	var input_events: Array = completed.get("input_events", []) as Array
	_expect(input_events.size() >= 6, "ReplayInputSmoke should record multiple gameplay input events")
	for action_name: String in EXPECTED_ACTIONS:
		_expect(_has_input_action(input_events, action_name), "ReplayInputSmoke should record %s" % action_name)
	_expect(_all_events_are_v2(input_events), "ReplayInputSmoke should record only typed v2 input events")
	_expect(_has_vector_value(input_events, ACTIONS.MOVE, Vector2.RIGHT), "ReplayInputSmoke should record normalized movement intent")
	_expect(_has_vector_value(input_events, ACTIONS.AIM, Vector2.UP), "ReplayInputSmoke should record normalized final aim intent")

	GameState.change_state(GameState.MAIN_MENU, {"source": "replay_input_smoke"})
	InputService.set_playback_active(false)
	_finish(Replay.recording_summary(completed))


func _inject_key(keycode: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	InputService.debug_inject_input(event)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _inject_mouse_button(button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	InputService.debug_inject_input(event)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _inject_mouse_motion(position: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _has_input_action(input_events: Array, action_name: String) -> bool:
	for input_event: Variant in input_events:
		if input_event is Dictionary and String((input_event as Dictionary).get("action", "")) == action_name:
			return true
	return false


func _all_events_are_v2(input_events: Array) -> bool:
	for raw_event: Variant in input_events:
		if not raw_event is Dictionary:
			return false
		var input_event: Dictionary = raw_event as Dictionary
		if not input_event.has("value_type") or not input_event.has("value"):
			return false
		if input_event.has("pressed") or input_event.has("strength"):
			return false
	return true


func _has_vector_value(input_events: Array, action_name: String, expected: Vector2) -> bool:
	for raw_event: Variant in input_events:
		if not raw_event is Dictionary:
			continue
		var input_event: Dictionary = raw_event as Dictionary
		if String(input_event.get("action", "")) != action_name or String(input_event.get("value_type", "")) != "vector2":
			continue
		var components: Array = input_event.get("value", []) as Array
		if components.size() == 2 and Vector2(float(components[0]), float(components[1])).is_equal_approx(expected):
			return true
	return false


func _wait_for_node(node_name: String) -> Node:
	for _index: int in range(60):
		await get_tree().process_frame
		var node: Node = _find_node_by_name(get_tree().root, node_name)
		if node != null:
			return node
	return null


func _wait_for_game_state(expected_state: StringName) -> void:
	for _index: int in range(120):
		if GameState.is_state(expected_state):
			return
		await get_tree().process_frame


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
	InputService.clear_playback_values()
	InputService.set_playback_active(false)

	if _failures.is_empty():
		print("[ReplayInputSmoke] passed; summary=%s" % JSON.stringify(summary))
		get_tree().quit(0)
		return

	print("[ReplayInputSmoke] failed; failures=%d first=%s" % [_failures.size(), _failures[0]])
	get_tree().quit(1)
