extends Node
## F13 room-switch headless smoke: drives the room carrier through clear -> open door ->
## switch room -> save/restore. Mounted by FormalClientBoot for the --room-switch-smoke flag.

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const BOOT_FRAMES: int = 3

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var run_loop: Node = await _wait_for_playing_run_loop()
	_expect(run_loop != null, "room carrier run should reach PLAYING")
	if run_loop == null:
		_finish()
		return
	_expect(bool(run_loop.call("debug_room_carrier_enabled")), "fresh run should be in room carrier mode")

	# Room 1: entry room, locked exit, one enemy.
	var state_entry: Dictionary = run_loop.call("debug_room_state")
	_expect(String(state_entry.get("current_room_id", "")) == "room_demo_entry", "first room should be room_demo_entry")
	_expect(int(state_entry.get("room_index", -1)) == 0, "first room index should be 0")
	_expect(not bool(state_entry.get("cleared", true)), "first room should start uncleared")
	_expect(_active_count("active_enemies") == 1, "first room should spawn exactly one enemy")
	var doors_entry: Dictionary = run_loop.call("debug_room_doors")
	_expect(doors_entry.has("door_exit"), "first room should expose door_exit")
	_expect(not _door_unlocked(doors_entry, "door_exit"), "exit door should start locked")

	# Clear the room -> the exit unlocks.
	run_loop.call("debug_kill_enemies")
	for _frame_clear: int in range(BOOT_FRAMES * 3):
		await get_tree().process_frame
	var state_cleared: Dictionary = run_loop.call("debug_room_state")
	_expect(bool(state_cleared.get("cleared", false)), "first room should clear after enemies die")
	var doors_cleared: Dictionary = run_loop.call("debug_room_doors")
	_expect(_door_unlocked(doors_cleared, "door_exit"), "exit door should unlock after clear")

	# Walk into the open exit -> switch to the next room.
	var exit_position: Vector2 = _door_position(doors_cleared, "door_exit")
	run_loop.call("debug_set_player_position", exit_position)
	for _frame_switch: int in range(BOOT_FRAMES * 3):
		await get_tree().process_frame

	# Room 2: arena room with one enemy and one hazard.
	var state_arena: Dictionary = run_loop.call("debug_room_state")
	_expect(String(state_arena.get("current_room_id", "")) == "room_demo_arena", "touching the exit should switch to room_demo_arena")
	_expect(int(state_arena.get("room_index", -1)) == 1, "second room index should be 1")
	_expect(_active_count("active_enemies") == 1, "second room should spawn exactly one enemy")
	_expect(_active_count("active_hazards") == 1, "second room should spawn exactly one hazard")

	await _expect_save_restore(run_loop)
	_finish()


func _expect_save_restore(run_loop: Node) -> void:
	var saved_state: Dictionary = run_loop.call("debug_room_state")

	await _push_action_once(ACTIONS.PAUSE)
	var pause_menu: Node = null
	for _frame_pause: int in range(BOOT_FRAMES * 2):
		await get_tree().process_frame
		pause_menu = _find_node_by_name(get_tree().root, "PauseMenu")
		if pause_menu != null:
			break
	_expect(pause_menu != null, "pause should show the pause menu")
	if pause_menu == null:
		return
	var save_button: Button = _find_node_by_name(pause_menu, "SaveAndQuitButton") as Button
	_expect(save_button != null, "pause menu should expose save-and-quit")
	if save_button == null:
		return
	await _click_button(save_button)
	await _wait_for_title_menu()
	_expect(SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), "save-and-quit should write a run save")

	var title_menu: Node = _find_node_by_name(get_tree().root, "TitleMenu")
	var continue_button: Button = _find_node_by_name(title_menu, "ContinueRunButton") as Button
	_expect(continue_button != null, "title menu should expose continue when a run save exists")
	if continue_button == null:
		return
	await _click_button(continue_button)

	var restored: Node = await _wait_for_state_run_loop(GameState.PAUSED)
	_expect(restored != null, "continue should mount a restored run loop")
	if restored == null:
		return
	_expect(bool(restored.call("debug_room_carrier_enabled")), "restored run should re-enable the room carrier from save data")
	var restored_state: Dictionary = restored.call("debug_room_state")
	_expect(String(restored_state.get("current_room_id", "")) == String(saved_state.get("current_room_id", "")), "continue should restore the current room id")
	_expect(int(restored_state.get("room_index", -1)) == int(saved_state.get("room_index", -2)), "continue should restore the room index")
	_expect(_active_count("active_enemies") >= 1, "continue should restore the live room enemy")
	_expect(_active_count("active_hazards") >= 1, "continue should restore the live room hazard")
	var restored_doors: Dictionary = restored.call("debug_room_doors")
	_expect(restored_doors.has("door_complete"), "restored arena room should expose its exit door")


func _active_count(group_name: String) -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if node is Node2D and is_instance_valid(node):
			count += 1
	return count


func _door_unlocked(doors: Dictionary, door_id: String) -> bool:
	var door: Dictionary = doors.get(door_id, {}) if doors.get(door_id, {}) is Dictionary else {}
	return bool(door.get("unlocked", false))


func _door_position(doors: Dictionary, door_id: String) -> Vector2:
	var door: Dictionary = doors.get(door_id, {}) if doors.get(door_id, {}) is Dictionary else {}
	var pos: Dictionary = door.get("position", {}) if door.get("position", {}) is Dictionary else {}
	return Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))


func _wait_for_playing_run_loop() -> Node:
	for _frame: int in range(BOOT_FRAMES * 8):
		await get_tree().process_frame
		if GameState.is_state(GameState.PLAYING):
			var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
			if run_loop != null:
				return run_loop
	return _find_node_by_name(get_tree().root, "GameplayRunLoop")


func _wait_for_state_run_loop(state_value: StringName) -> Node:
	for _frame: int in range(BOOT_FRAMES * 12):
		await get_tree().process_frame
		if GameState.is_state(state_value):
			var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
			if run_loop != null:
				return run_loop
	return null


func _wait_for_title_menu() -> void:
	for _frame: int in range(BOOT_FRAMES * 12):
		await get_tree().process_frame
		if _find_node_by_name(get_tree().root, "TitleMenu") != null:
			return


func _push_action_once(action: StringName) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = action
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().process_frame
	var release: InputEventAction = InputEventAction.new()
	release.action = action
	release.pressed = false
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _click_button(button: Button) -> void:
	await get_tree().process_frame
	var center: Vector2 = button.get_global_rect().get_center()
	button.grab_focus()

	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	get_viewport().push_input(press, true)
	await get_tree().process_frame

	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	release.global_position = center
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _find_node_by_name(root_node: Node, target_name: String) -> Node:
	if root_node == null:
		return null
	if String(root_node.name) == target_name:
		return root_node
	for child: Node in root_node.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("[RoomSwitchSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[RoomSwitchSmoke] passed; rooms switched and restored")
		get_tree().quit(0)
	else:
		print("[RoomSwitchSmoke] failed; failures=%d" % _failures.size())
		get_tree().quit(1)
