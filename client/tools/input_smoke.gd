extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")

const WAIT_FRAMES: int = 3
const DETECTION_COUNTDOWN_SECONDS: float = 0.6

var _action_presses: Array[StringName] = []
var _action_releases: Array[StringName] = []
var _binding_backup: Dictionary = {}
var _bridged_actions: Array[StringName] = []
var _device_changes: Array[StringName] = []
var _failures: Array[String] = []
var _guide_mouse_motion_count: int = 0
var _remap_conflicts: Array[Dictionary] = []
var _remap_results: Array[Dictionary] = []
var _virtual_device_id: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _input(event: InputEvent) -> void:
	var action_event: InputEventAction = event as InputEventAction
	if action_event != null and action_event.pressed:
		_bridged_actions.append(action_event.action)


func _run() -> void:
	_capture_binding_files()
	_connect_observers()
	_virtual_device_id = GUIDE._input_state.connect_virtual_stick(0)
	await _wait_process_frames(WAIT_FRAMES)
	InputService.reset_bindings_to_defaults()

	await _expect_context_isolation_and_vector_input()
	await _expect_mouse_events_reach_guide_before_gui()
	await _expect_bool_edges_are_latched()
	await _expect_focus_and_disconnect_clear_state()
	await _expect_device_and_prompt_refresh()
	await _expect_capture_cancel_and_negative_axis()
	await _expect_detector_cancel_during_post_clear()
	await _expect_conflict_cancel_and_replace()
	_expect_safety_fallbacks_are_fixed()
	await _cleanup_runtime_state()
	_restore_binding_files()
	_finish()


func _expect_context_isolation_and_vector_input() -> void:
	GameState.change_state(GameState.MAIN_MENU, {"source": "input_smoke"})
	UIManager.clear()
	await _wait_process_frames(WAIT_FRAMES)
	_bridged_actions.clear()
	await _inject_key(KEY_ENTER, true)
	await _inject_key(KEY_ENTER, false)
	_expect(_bridged_actions.has(&"ui_accept"), "physical UI confirm should bridge to Godot ui_accept")
	_bridged_actions.clear()
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.UI_CONFIRM, true)
	InputService.inject_playback_value(ACTIONS.UI_CONFIRM, false)
	await get_tree().process_frame
	_expect(_bridged_actions.has(&"ui_accept"), "playback UI confirm should bridge to Godot ui_accept")
	InputService.set_playback_active(false)
	await _inject_key(KEY_W, true)
	_expect(InputService.vector(ACTIONS.MOVE).is_zero_approx(), "gameplay movement should be isolated while UI context is active")
	await _inject_key(KEY_W, false)

	GameState.change_state(GameState.PLAYING, {"source": "input_smoke"})
	UIManager.clear()
	await _wait_process_frames(WAIT_FRAMES)
	await _inject_key(KEY_W, true)
	_expect(InputService.vector(ACTIONS.MOVE).is_equal_approx(Vector2.UP), "W should produce native Vector2.UP movement intent")
	await _inject_key(KEY_W, false)
	_expect(InputService.vector(ACTIONS.MOVE).is_zero_approx(), "releasing W should clear movement intent")
	await _inject_key(KEY_W, true)
	GameState.change_state(GameState.MAIN_MENU, {"source": "input_smoke_context_clear"})
	await _wait_process_frames(WAIT_FRAMES)
	_expect(InputService.vector(ACTIONS.MOVE).is_zero_approx(), "switching away from gameplay should clear held movement")
	GameState.change_state(GameState.PLAYING, {"source": "input_smoke_context_restore"})
	await _wait_process_frames(WAIT_FRAMES)
	_expect(InputService.vector(ACTIONS.MOVE).is_zero_approx(), "restoring gameplay should not revive a pre-switch held input")
	await _inject_key(KEY_W, false)

	await _inject_key(KEY_UP, true)
	_expect(not InputService.should_use_pointer_aim(), "direction input should become the active aim source")
	var pointer_event: InputEventMouseMotion = InputEventMouseMotion.new()
	pointer_event.position = Vector2(640.0, 360.0)
	pointer_event.global_position = pointer_event.position
	pointer_event.relative = Vector2(4.0, -2.0)
	InputService.debug_inject_input(pointer_event)
	await _wait_process_frames(WAIT_FRAMES)
	_expect(InputService.should_use_pointer_aim(), "newer pointer activity should override a still-held direction aim")
	await _inject_key(KEY_UP, false)

	await _inject_joy_axis(JOY_AXIS_LEFT_X, -1.0)
	_expect(InputService.vector(ACTIONS.MOVE).x < -0.9, "left stick negative X should produce negative movement intent")
	await _inject_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await _inject_joy_axis(JOY_AXIS_RIGHT_Y, -1.0)
	_expect(InputService.vector(ACTIONS.AIM).y < -0.9, "right stick negative Y should produce negative aim intent")
	await _inject_joy_axis(JOY_AXIS_RIGHT_Y, 0.0)


func _expect_mouse_events_reach_guide_before_gui() -> void:
	GameState.change_state(GameState.PLAYING, {"source": "input_smoke_mouse_gui_overlap"})
	UIManager.clear()
	await _wait_process_frames(WAIT_FRAMES)

	var mouse_blocker: MouseInputBlocker = MouseInputBlocker.new()
	mouse_blocker.name = "MouseInputBlocker"
	mouse_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_blocker.position = Vector2.ZERO
	mouse_blocker.size = get_viewport().get_visible_rect().size
	add_child(mouse_blocker)
	await get_tree().process_frame

	var pointer_position: Vector2 = Vector2(704.0, 416.0)
	var pointer_event: InputEventMouseMotion = InputEventMouseMotion.new()
	pointer_event.position = pointer_position
	pointer_event.global_position = pointer_position
	pointer_event.relative = Vector2(7.0, -4.0)
	var mouse_motion_count_before: int = _guide_mouse_motion_count
	Input.parse_input_event(pointer_event)
	await _wait_process_frames(WAIT_FRAMES)
	_expect(
		_guide_mouse_motion_count > mouse_motion_count_before,
		"viewport mouse motion should reach GUIDE before a full-screen Control consumes it"
	)
	_expect(InputService.should_use_pointer_aim(), "viewport mouse motion should select pointer aim")

	var press_event: InputEventMouseButton = InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.position = pointer_position
	press_event.global_position = pointer_position
	press_event.pressed = true
	Input.parse_input_event(press_event)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(
		InputService.is_pressed(ACTIONS.FIRE),
		"left mouse press should reach GUIDE before a full-screen Control consumes it"
	)

	var release_event := press_event.duplicate() as InputEventMouseButton
	release_event.pressed = false
	Input.parse_input_event(release_event)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(not InputService.is_pressed(ACTIONS.FIRE), "left mouse release should clear fire intent")
	mouse_blocker.queue_free()
	await get_tree().process_frame


func _expect_bool_edges_are_latched() -> void:
	_action_presses.clear()
	_action_releases.clear()
	await _inject_mouse_button(MOUSE_BUTTON_LEFT, true, false)
	await _inject_mouse_button(MOUSE_BUTTON_LEFT, false, false)
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(_action_presses.has(StringName(ACTIONS.FIRE)), "short fire press should be latched to a physics tick")
	_expect(_action_releases.has(StringName(ACTIONS.FIRE)), "short fire release should be latched to a physics tick")
	_expect(not InputService.is_pressed(ACTIONS.FIRE), "short fire input should not remain held")


func _expect_focus_and_disconnect_clear_state() -> void:
	await _inject_mouse_button(MOUSE_BUTTON_LEFT, true)
	_expect(InputService.is_pressed(ACTIONS.FIRE), "fire should be held before focus loss")
	GUIDE.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	InputService.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait_process_frames(WAIT_FRAMES)
	_expect(not InputService.is_pressed(ACTIONS.FIRE), "focus loss should clear held bool state")
	await _inject_mouse_button(MOUSE_BUTTON_LEFT, false)

	await _inject_joy_button(JOY_BUTTON_A, true)
	_expect(InputService.is_pressed(ACTIONS.USE_ACTIVE_ITEM), "gamepad active-item input should become held")
	GUIDE.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	InputService.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _wait_process_frames(WAIT_FRAMES)
	_expect(not InputService.is_pressed(ACTIONS.USE_ACTIVE_ITEM), "focus loss should clear held gamepad state")
	await _inject_joy_button(JOY_BUTTON_A, false)

	await _inject_joy_button(JOY_BUTTON_A, true)
	_expect(InputService.is_pressed(ACTIONS.USE_ACTIVE_ITEM), "gamepad active-item input should become held before disconnect")
	GUIDE._input_state.disconnect_virtual_stick(_virtual_device_id)
	Input.joy_connection_changed.emit(_virtual_device_id, false)
	await _wait_process_frames(WAIT_FRAMES)
	_expect(not InputService.is_pressed(ACTIONS.USE_ACTIVE_ITEM), "gamepad disconnect should clear held state")
	_virtual_device_id = GUIDE._input_state.connect_virtual_stick(0)
	await _inject_joy_button(JOY_BUTTON_A, false)


func _expect_device_and_prompt_refresh() -> void:
	_device_changes.clear()
	await _inject_key(KEY_E, true)
	await _inject_key(KEY_E, false)
	_expect(InputService.current_device_family() == InputService.DEVICE_KEYBOARD_MOUSE, "keyboard input should select keyboard/mouse prompt family")
	var keyboard_prompt: String = InputService.prompt_text(ACTIONS.INTERACT)
	_expect(not keyboard_prompt.is_empty(), "keyboard prompt should render text")
	var keyboard_richtext: String = await InputService.prompt_richtext_async(ACTIONS.INTERACT)
	_expect(not keyboard_richtext.is_empty(), "keyboard prompt should render asynchronous rich text")
	await _inject_joy_axis(JOY_AXIS_LEFT_X, 0.8)
	_expect(InputService.current_device_family() == InputService.DEVICE_GAMEPAD, "joy input should select gamepad prompt family")
	var gamepad_prompt: String = InputService.prompt_text(ACTIONS.INTERACT)
	_expect(not gamepad_prompt.is_empty(), "gamepad prompt should render text")
	var gamepad_richtext: String = await InputService.prompt_richtext_async(ACTIONS.INTERACT)
	_expect(not gamepad_richtext.is_empty(), "gamepad prompt should render asynchronous rich text")
	_expect(_device_changes.has(InputService.DEVICE_GAMEPAD), "device family change should emit refresh signal")
	await _inject_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await _inject_key(KEY_E, true)
	await _inject_key(KEY_E, false)
	_expect(InputService.current_device_family() == InputService.DEVICE_KEYBOARD_MOUSE, "keyboard input should switch prompts back after gamepad activity")
	_expect(_device_changes.has(InputService.DEVICE_KEYBOARD_MOUSE), "keyboard return should emit device refresh signal")


func _expect_capture_cancel_and_negative_axis() -> void:
	_remap_results.clear()
	_expect(InputService.begin_remap(InputService.BINDING_INTERACT, InputService.DEVICE_KEYBOARD_MOUSE), "keyboard remap capture should start")
	InputService.cancel_remap()
	await _wait_process_frames(WAIT_FRAMES)
	_expect(_has_remap_result(InputService.BINDING_INTERACT, false), "capture cancellation during countdown should return to idle")
	_expect(InputService.begin_remap(InputService.BINDING_INTERACT, InputService.DEVICE_KEYBOARD_MOUSE), "capture should start again after countdown cancellation")
	InputService.cancel_remap()
	await _wait_process_frames(WAIT_FRAMES)
	var detector: GUIDEInputDetector = InputService.get_node_or_null("GUIDEInputDetector") as GUIDEInputDetector
	_expect(detector != null, "InputService should own a GUIDE input detector")
	if detector != null:
		detector.detection_countdown_seconds = 0.0

	_remap_results.clear()
	_expect(InputService.begin_remap(InputService.BINDING_MOVE_STICK, InputService.DEVICE_GAMEPAD), "2D stick capture should start")
	await _wait_for_detection_ready()
	await _push_joy_axis(JOY_AXIS_LEFT_X, -0.85)
	await _push_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await _wait_process_frames(WAIT_FRAMES)
	_expect(_has_remap_result(InputService.BINDING_MOVE_STICK, true), "negative stick axis should be accepted by 2D capture")
	_expect(FileAccess.file_exists(InputService.bindings_path()), "successful capture should persist input_bindings.tres")


func _expect_detector_cancel_during_post_clear() -> void:
	var detector: GUIDEInputDetector = GUIDEInputDetector.new()
	detector.detection_countdown_seconds = 0.0
	detector.abort_detection_on = []
	var detected_inputs: Array[GUIDEInput] = []
	detector.input_detected.connect(func(input: GUIDEInput) -> void:
		detected_inputs.append(input)
	)
	add_child(detector)
	await get_tree().process_frame
	var device_types: Array[GUIDEInput.DeviceType] = [GUIDEInput.DeviceType.KEYBOARD]
	detector.detect_bool(device_types)
	await _wait_process_frames(WAIT_FRAMES)
	detector.debug_inject_input(_key_event(KEY_R, false))
	_expect(detector.is_detecting, "detector should enter post-clear after capturing an input")
	detector.abort_detection()
	await _wait_process_frames(WAIT_FRAMES)
	_expect(not detector.is_detecting, "cancelling during post-clear should return detector to idle")
	_expect(detected_inputs.size() == 1 and detected_inputs[0] == null, "post-clear cancellation should report an aborted capture")
	remove_child(detector)
	detector.queue_free()


func _expect_conflict_cancel_and_replace() -> void:
	InputService.reset_bindings_to_defaults()
	await _wait_process_frames(WAIT_FRAMES)
	await _push_key(KEY_SHIFT, true)
	await _push_key(KEY_SHIFT, false)
	var default_pause_prompt: String = InputService.prompt_text(ACTIONS.PAUSE)
	_remap_conflicts.clear()
	_remap_results.clear()
	_expect(InputService.begin_remap(InputService.BINDING_PAUSE, InputService.DEVICE_KEYBOARD_MOUSE), "pause conflict capture should start")
	await _wait_for_detection_ready()
	await _push_key(KEY_E, true)
	await _push_key(KEY_E, false)
	await _wait_process_frames(WAIT_FRAMES)
	_expect(_has_conflict(InputService.BINDING_PAUSE, InputService.BINDING_INTERACT), "same-context keyboard conflict should be reported")
	_expect(not InputService.resolve_pending_remap(false), "conflict cancel should reject the pending replacement")
	await _wait_process_frames(WAIT_FRAMES)
	var canceled_override: Dictionary = _saved_binding_override(
		"res://resources/input/contexts/gameplay.tres",
		"res://resources/input/actions/pause.tres",
		0
	)
	_expect(not bool(canceled_override.get("found", false)), "conflict cancel should preserve the default pause binding")

	_remap_conflicts.clear()
	_remap_results.clear()
	_expect(InputService.begin_remap(InputService.BINDING_PAUSE, InputService.DEVICE_KEYBOARD_MOUSE), "pause conflict capture should restart")
	await _wait_for_detection_ready()
	await _push_key(KEY_E, true)
	await _push_key(KEY_E, false)
	await _wait_process_frames(WAIT_FRAMES)
	_expect(InputService.resolve_pending_remap(true), "conflict replace should apply the pending binding")
	await _wait_process_frames(WAIT_FRAMES)
	var pause_override: Dictionary = _saved_binding_override(
		"res://resources/input/contexts/gameplay.tres",
		"res://resources/input/actions/pause.tres",
		0
	)
	var pause_key: GUIDEInputKey = pause_override.get("input") as GUIDEInputKey
	_expect(bool(pause_override.get("found", false)) and pause_key != null and pause_key.key == KEY_E, "conflict replace should persist the new pause binding")
	var remapped_pause_prompt: String = InputService.prompt_text(ACTIONS.PAUSE)
	_expect(remapped_pause_prompt != default_pause_prompt, "prompt formatting should reflect the current remapped binding")
	var interact_override: Dictionary = _saved_binding_override(
		"res://resources/input/contexts/gameplay.tres",
		"res://resources/input/actions/interact.tres",
		0
	)
	_expect(bool(interact_override.get("found", false)) and interact_override.get("input") == null, "conflict replace should unbind the previous same-context owner")
	InputService.reset_bindings_to_defaults()
	var restored_pause_prompt: String = InputService.prompt_text(ACTIONS.PAUSE)
	_expect(
		restored_pause_prompt == default_pause_prompt,
		"restoring defaults should refresh prompt formatting default=%s restored=%s" % [default_pause_prompt, restored_pause_prompt]
	)


func _saved_binding_override(context_path: String, action_path: String, index: int) -> Dictionary:
	var config: GUIDERemappingConfig = ResourceLoader.load(
		InputService.bindings_path(),
		"GUIDERemappingConfig",
		ResourceLoader.CACHE_MODE_IGNORE
	) as GUIDERemappingConfig
	if config == null:
		return {"found": false, "input": null}
	for raw_context: Variant in config.remapped_inputs:
		var context: GUIDEMappingContext = raw_context as GUIDEMappingContext
		if context == null or context.resource_path != context_path:
			continue
		var action_map: Dictionary = config.remapped_inputs[raw_context] as Dictionary
		for raw_action: Variant in action_map:
			var action: GUIDEAction = raw_action as GUIDEAction
			if action == null or action.resource_path != action_path:
				continue
			var index_map: Dictionary = action_map[raw_action] as Dictionary
			if index_map.has(index):
				return {"found": true, "input": index_map[index]}
	return {"found": false, "input": null}


func _expect_safety_fallbacks_are_fixed() -> void:
	var gameplay: GUIDEMappingContext = load("res://resources/input/contexts/gameplay.tres") as GUIDEMappingContext
	var ui: GUIDEMappingContext = load("res://resources/input/contexts/ui.tres") as GUIDEMappingContext
	var pause_action: GUIDEAction = InputService.action_resource(ACTIONS.PAUSE)
	var back_action: GUIDEAction = InputService.action_resource(ACTIONS.UI_BACK)
	_expect(_has_fixed_key(gameplay, pause_action, KEY_ESCAPE), "gameplay pause should keep a fixed Escape fallback")
	_expect(_has_fixed_joy_button(gameplay, pause_action, JOY_BUTTON_START), "gameplay pause should keep a fixed Start fallback")
	_expect(_has_fixed_key(ui, back_action, KEY_ESCAPE), "UI back should keep a fixed Escape fallback")
	_expect(_has_fixed_joy_button(ui, back_action, JOY_BUTTON_B), "UI back should keep a fixed B fallback")


func _has_fixed_key(context: GUIDEMappingContext, action: GUIDEAction, keycode: Key) -> bool:
	for mapping: GUIDEInputMapping in _input_mappings_for_action(context, action):
		var key_input: GUIDEInputKey = mapping.input as GUIDEInputKey
		if key_input != null and key_input.key == keycode and mapping.override_action_settings and not mapping.is_remappable:
			return true
	return false


func _has_fixed_joy_button(context: GUIDEMappingContext, action: GUIDEAction, button: JoyButton) -> bool:
	for mapping: GUIDEInputMapping in _input_mappings_for_action(context, action):
		var joy_input: GUIDEInputJoyButton = mapping.input as GUIDEInputJoyButton
		if joy_input != null and joy_input.button == button and mapping.override_action_settings and not mapping.is_remappable:
			return true
	return false


func _input_mappings_for_action(context: GUIDEMappingContext, action: GUIDEAction) -> Array[GUIDEInputMapping]:
	var result: Array[GUIDEInputMapping] = []
	if context == null or action == null:
		return result
	for action_mapping: GUIDEActionMapping in context.mappings:
		if action_mapping.action == action:
			result.append_array(action_mapping.input_mappings)
	return result


func _inject_key(keycode: Key, pressed: bool) -> void:
	var event: InputEventKey = _key_event(keycode, pressed)
	InputService.debug_inject_input(event)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _push_key(keycode: Key, pressed: bool) -> void:
	InputService.debug_inject_input(_key_event(keycode, pressed))
	await get_tree().process_frame


func _key_event(keycode: Key, pressed: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


func _inject_mouse_button(button: MouseButton, pressed: bool, wait_for_physics: bool = true) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	InputService.debug_inject_input(event)
	await get_tree().process_frame
	if wait_for_physics:
		await get_tree().physics_frame
		await get_tree().process_frame


func _inject_joy_button(button: JoyButton, pressed: bool) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = _virtual_device_id
	event.button_index = button
	event.pressed = pressed
	InputService.debug_inject_input(event)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _inject_joy_axis(axis: JoyAxis, value: float) -> void:
	await _push_joy_axis(axis, value)
	await get_tree().physics_frame
	await get_tree().process_frame


func _push_joy_axis(axis: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = _virtual_device_id
	event.axis = axis
	event.axis_value = value
	InputService.debug_inject_input(event)
	await get_tree().process_frame


func _wait_process_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _wait_for_detection_ready() -> void:
	await get_tree().create_timer(DETECTION_COUNTDOWN_SECONDS, true, false, true).timeout
	await _wait_process_frames(WAIT_FRAMES)


func _connect_observers() -> void:
	GUIDE._input_state.mouse_position_changed.connect(func() -> void:
		_guide_mouse_motion_count += 1
	)
	InputService.action_pressed.connect(func(action_id: StringName, _participant_id: String) -> void:
		_action_presses.append(action_id)
	)
	InputService.action_released.connect(func(action_id: StringName, _participant_id: String) -> void:
		_action_releases.append(action_id)
	)
	InputService.device_family_changed.connect(func(device_family: StringName) -> void:
		_device_changes.append(device_family)
	)
	InputService.remap_conflict.connect(func(binding_id: StringName, conflicts: Array[StringName]) -> void:
		_remap_conflicts.append({"binding_id": binding_id, "conflicts": conflicts.duplicate()})
	)
	InputService.remap_finished.connect(func(binding_id: StringName, applied: bool) -> void:
		_remap_results.append({"binding_id": binding_id, "applied": applied})
	)


func _has_remap_result(binding_id: StringName, applied: bool) -> bool:
	for result: Dictionary in _remap_results:
		if StringName(result.get("binding_id", &"")) == binding_id and bool(result.get("applied", false)) == applied:
			return true
	return false


func _has_conflict(binding_id: StringName, other_binding_id: StringName) -> bool:
	for result: Dictionary in _remap_conflicts:
		if StringName(result.get("binding_id", &"")) != binding_id:
			continue
		var conflicts: Array = result.get("conflicts", []) as Array
		if conflicts.has(other_binding_id):
			return true
	return false


func _capture_binding_files() -> void:
	_binding_backup.clear()
	for path: String in _binding_paths():
		var entry: Dictionary = {"exists": FileAccess.file_exists(path), "text": ""}
		if bool(entry["exists"]):
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				entry["text"] = file.get_as_text()
		_binding_backup[path] = entry


func _restore_binding_files() -> void:
	for path: String in _binding_paths():
		var entry: Dictionary = _binding_backup.get(path, {}) as Dictionary
		if bool(entry.get("exists", false)):
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(String(entry.get("text", "")))
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _binding_paths() -> Array[String]:
	return [
		InputService.bindings_path(),
		"user://input_bindings.tmp.tres",
		"user://input_bindings.bak.tres",
		"user://input_bindings.invalid.tres",
	]


func _cleanup_runtime_state() -> void:
	InputService.cancel_remap()
	InputService.clear_playback_values()
	InputService.set_playback_active(false)
	await _inject_key(KEY_W, false)
	await _inject_key(KEY_E, false)
	await _inject_mouse_button(MOUSE_BUTTON_LEFT, false)
	await _inject_joy_button(JOY_BUTTON_A, false)
	await _inject_joy_axis(JOY_AXIS_LEFT_X, 0.0)
	await _inject_joy_axis(JOY_AXIS_RIGHT_Y, 0.0)
	if _virtual_device_id != 0:
		GUIDE._input_state.disconnect_virtual_stick(_virtual_device_id)
		_virtual_device_id = 0
	GameState.change_state(GameState.MAIN_MENU, {"source": "input_smoke"})
	UIManager.clear()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[InputSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[InputSmoke] passed")
		get_tree().quit(0)
		return
	print("[InputSmoke] failed; failures=%d first=%s" % [_failures.size(), _failures[0]])
	get_tree().quit(1)


class MouseInputBlocker:
	extends Control

	func _gui_input(_event: InputEvent) -> void:
		accept_event()
