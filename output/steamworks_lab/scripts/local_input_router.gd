class_name SteamLabLocalInputRouter
extends Node

signal roster_changed(roster: Array[Dictionary])
signal controller_missing(slot_id: int)
signal controllers_restored()
signal controller_overflow(ignored_count: int)

const KEYBOARD_SLOT_ID: int = 1
const FIRST_CONTROLLER_SLOT_ID: int = 2
const LAST_CONTROLLER_SLOT_ID: int = 4
const CONTROLLER_DEADZONE: float = 0.25
const KEYBOARD_DEVICE_NAME: String = "Keyboard & Mouse"
const KEYBOARD_ACTIONS: Dictionary = {
	"move_left": "move_left",
	"move_right": "move_right",
	"move_up": "move_up",
	"move_down": "move_down",
	"fire": "fire",
	"active_item": "active_item",
	"merge": "merge",
	"expression": "expression_wheel",
	"pause": "pause_menu",
}
const ACTION_PREFIX_FORMAT: String = "couch_p%d_"
const ACTION_SUFFIXES: Array[String] = [
	"move_left",
	"move_right",
	"move_up",
	"move_down",
	"aim_left",
	"aim_right",
	"aim_up",
	"aim_down",
	"fire",
	"active_item",
	"merge",
	"expression",
	"pause",
]

var _enabled: bool = false
var _roster_locked: bool = false
var _had_missing_controllers: bool = false
var _slots_by_id: Dictionary = {
	KEYBOARD_SLOT_ID: {
		"slot_id": KEYBOARD_SLOT_ID,
		"device_id": -1,
		"device_name": KEYBOARD_DEVICE_NAME,
		"missing": false,
	},
}
var _device_to_slot: Dictionary = {}
var _last_aim_by_slot: Dictionary = {KEYBOARD_SLOT_ID: Vector2.UP}
var _debug_device_override_enabled: bool = false
var _debug_connected_devices: Array[Dictionary] = []
var _debug_input_frames: Dictionary = {}
var _ignored_controller_count: int = 0


func _ready() -> void:
	set_process(_enabled)


func _process(_delta: float) -> void:
	if _enabled:
		_reconcile_devices()


func enable_lobby() -> void:
	_enabled = true
	_roster_locked = false
	_had_missing_controllers = false
	set_process(true)
	_reconcile_devices()


func disable() -> void:
	var changed := _slots_by_id.size() > 1
	for slot_id in range(FIRST_CONTROLLER_SLOT_ID, LAST_CONTROLLER_SLOT_ID + 1):
		_clear_slot_actions(slot_id)
	_device_to_slot.clear()
	_slots_by_id.clear()
	_slots_by_id[KEYBOARD_SLOT_ID] = _keyboard_slot()
	_last_aim_by_slot.clear()
	_last_aim_by_slot[KEYBOARD_SLOT_ID] = Vector2.UP
	_debug_input_frames.clear()
	_ignored_controller_count = 0
	_enabled = false
	_roster_locked = false
	_had_missing_controllers = false
	set_process(false)
	if changed:
		roster_changed.emit(slots())


func lock_roster() -> void:
	if _enabled and not _roster_locked:
		_reconcile_devices()
	_roster_locked = true
	_had_missing_controllers = not missing_slot_ids().is_empty()


func unlock_roster() -> void:
	_roster_locked = false
	_had_missing_controllers = false
	if _enabled:
		_reconcile_devices()


func is_locked() -> bool:
	return _roster_locked


func slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var slot_ids: Array[int] = []
	for slot_id_value in _slots_by_id.keys():
		slot_ids.append(int(slot_id_value))
	slot_ids.sort()
	for slot_id in slot_ids:
		var slot: Dictionary = _slots_by_id[slot_id]
		result.append(slot.duplicate(true))
	return result


func active_slot_ids() -> Array[int]:
	var result: Array[int] = []
	for slot in slots():
		if not bool(slot.get("missing", false)):
			result.append(int(slot.get("slot_id", 0)))
	return result


func missing_slot_ids() -> Array[int]:
	var result: Array[int] = []
	for slot_id in range(FIRST_CONTROLLER_SLOT_ID, LAST_CONTROLLER_SLOT_ID + 1):
		if not _slots_by_id.has(slot_id):
			continue
		var slot: Dictionary = _slots_by_id[slot_id]
		if bool(slot.get("missing", false)):
			result.append(slot_id)
	return result


func device_name_for_slot(slot_id: int) -> String:
	if not _slots_by_id.has(slot_id):
		return ""
	var slot: Dictionary = _slots_by_id[slot_id]
	return String(slot.get("device_name", ""))


func ignored_controller_count() -> int:
	return _ignored_controller_count


func set_keyboard_aim_direction(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		_last_aim_by_slot[KEYBOARD_SLOT_ID] = direction.normalized()


func input_frame(slot_id: int) -> Dictionary:
	if not _slots_by_id.has(slot_id):
		return _default_input_frame(slot_id)
	var slot: Dictionary = _slots_by_id[slot_id]
	if bool(slot.get("missing", false)):
		return _default_input_frame(slot_id)
	if _debug_input_frames.has(slot_id):
		var debug_frame: Dictionary = _debug_input_frames[slot_id]
		return _normalized_input_frame(slot_id, debug_frame)
	if slot_id == KEYBOARD_SLOT_ID:
		return _keyboard_input_frame()
	if not _enabled:
		return _default_input_frame(slot_id)

	var move := Input.get_vector(
		_action_name(slot_id, "move_left"),
		_action_name(slot_id, "move_right"),
		_action_name(slot_id, "move_up"),
		_action_name(slot_id, "move_down"),
		CONTROLLER_DEADZONE
	)
	var aim := Input.get_vector(
		_action_name(slot_id, "aim_left"),
		_action_name(slot_id, "aim_right"),
		_action_name(slot_id, "aim_up"),
		_action_name(slot_id, "aim_down"),
		CONTROLLER_DEADZONE
	)
	if aim.length_squared() > 0.0:
		_last_aim_by_slot[slot_id] = aim.normalized()
	var last_aim: Vector2 = _last_aim_by_slot.get(slot_id, Vector2.UP)
	return {
		"move": move.limit_length(1.0),
		"aim": last_aim,
		"fire_held": Input.is_action_pressed(_action_name(slot_id, "fire")),
		"active_item_pressed": Input.is_action_just_pressed(_action_name(slot_id, "active_item")),
		"merge_held": Input.is_action_pressed(_action_name(slot_id, "merge")),
		"expression_held": Input.is_action_pressed(_action_name(slot_id, "expression")),
		"pause_pressed": Input.is_action_just_pressed(_action_name(slot_id, "pause")),
	}


func _keyboard_input_frame() -> Dictionary:
	var move := Vector2(
		_action_strength_if_exists(String(KEYBOARD_ACTIONS["move_right"]))
		- _action_strength_if_exists(String(KEYBOARD_ACTIONS["move_left"])),
		_action_strength_if_exists(String(KEYBOARD_ACTIONS["move_down"]))
		- _action_strength_if_exists(String(KEYBOARD_ACTIONS["move_up"]))
	).limit_length(1.0)
	return {
		"move": move,
		"aim": _last_aim_by_slot.get(KEYBOARD_SLOT_ID, Vector2.UP),
		"fire_held": _action_pressed_if_exists(String(KEYBOARD_ACTIONS["fire"])),
		"active_item_pressed": _action_just_pressed_if_exists(String(KEYBOARD_ACTIONS["active_item"])),
		"merge_held": _action_pressed_if_exists(String(KEYBOARD_ACTIONS["merge"])),
		"expression_held": _action_pressed_if_exists(String(KEYBOARD_ACTIONS["expression"])),
		"pause_pressed": _action_just_pressed_if_exists(String(KEYBOARD_ACTIONS["pause"])),
	}


func _action_strength_if_exists(action_name: String) -> float:
	return Input.get_action_strength(action_name) if InputMap.has_action(action_name) else 0.0


func _action_pressed_if_exists(action_name: String) -> bool:
	return Input.is_action_pressed(action_name) if InputMap.has_action(action_name) else false


func _action_just_pressed_if_exists(action_name: String) -> bool:
	return Input.is_action_just_pressed(action_name) if InputMap.has_action(action_name) else false


func debug_set_connected_devices(devices: Array[Dictionary]) -> void:
	_debug_device_override_enabled = true
	_debug_connected_devices.clear()
	var known_device_ids: Dictionary = {}
	for device_data in devices:
		var device_id := int(device_data.get("device_id", device_data.get("id", -1)))
		if device_id < 0 or known_device_ids.has(device_id):
			continue
		known_device_ids[device_id] = true
		var device_name := String(device_data.get("device_name", device_data.get("name", ""))).strip_edges()
		if device_name == "":
			device_name = _fallback_device_name(device_id)
		_debug_connected_devices.append({
			"device_id": device_id,
			"device_name": device_name,
		})
	if _enabled:
		_reconcile_devices()


func debug_set_input_frame(slot_id: int, frame: Dictionary) -> void:
	if slot_id < KEYBOARD_SLOT_ID or slot_id > LAST_CONTROLLER_SLOT_ID:
		return
	_debug_input_frames[slot_id] = frame.duplicate(true)


func _reconcile_devices() -> void:
	if not _enabled:
		return
	var connected_devices := _connected_devices()
	var connected_by_id: Dictionary = {}
	for device_data in connected_devices:
		connected_by_id[int(device_data["device_id"])] = device_data

	var changed := false
	var newly_missing_slot_ids: Array[int] = []
	if _roster_locked:
		for slot_id in range(FIRST_CONTROLLER_SLOT_ID, LAST_CONTROLLER_SLOT_ID + 1):
			if not _slots_by_id.has(slot_id):
				continue
			var slot: Dictionary = _slots_by_id[slot_id]
			if bool(slot.get("missing", false)):
				continue
			var device_id := int(slot.get("device_id", -1))
			if connected_by_id.has(device_id):
				changed = _refresh_slot_name(slot_id, connected_by_id[device_id]) or changed
				continue
			_device_to_slot.erase(device_id)
			slot["missing"] = true
			_slots_by_id[slot_id] = slot
			_clear_slot_actions(slot_id)
			_debug_input_frames.erase(slot_id)
			changed = true
			newly_missing_slot_ids.append(slot_id)
	else:
		for slot_id in range(FIRST_CONTROLLER_SLOT_ID, LAST_CONTROLLER_SLOT_ID + 1):
			if not _slots_by_id.has(slot_id):
				continue
			var slot: Dictionary = _slots_by_id[slot_id]
			if bool(slot.get("missing", false)):
				_remove_slot(slot_id)
				changed = true
				continue
			var device_id := int(slot.get("device_id", -1))
			if connected_by_id.has(device_id):
				changed = _refresh_slot_name(slot_id, connected_by_id[device_id]) or changed
				continue
			_remove_slot(slot_id)
			changed = true

	for device_data in connected_devices:
		var device_id := int(device_data["device_id"])
		if _device_to_slot.has(device_id):
			continue
		var target_slot_id := _lowest_missing_slot_id() if _roster_locked else _lowest_open_slot_id()
		if target_slot_id < FIRST_CONTROLLER_SLOT_ID:
			continue
		_assign_device_to_slot(target_slot_id, device_data)
		changed = true

	var ignored_count := 0
	for device_data in connected_devices:
		if not _device_to_slot.has(int(device_data["device_id"])):
			ignored_count += 1
	if ignored_count != _ignored_controller_count:
		_ignored_controller_count = ignored_count
		controller_overflow.emit(_ignored_controller_count)

	var has_missing_controllers := _roster_locked and not missing_slot_ids().is_empty()
	var restored := (
		(_had_missing_controllers or not newly_missing_slot_ids.is_empty())
		and not has_missing_controllers
	)
	_had_missing_controllers = has_missing_controllers
	if changed:
		roster_changed.emit(slots())
	for slot_id in newly_missing_slot_ids:
		controller_missing.emit(slot_id)
	if restored:
		controllers_restored.emit()


func _connected_devices() -> Array[Dictionary]:
	if _debug_device_override_enabled:
		var debug_result: Array[Dictionary] = []
		for device_data in _debug_connected_devices:
			debug_result.append(device_data.duplicate(true))
		return debug_result

	var result: Array[Dictionary] = []
	for device_id in Input.get_connected_joypads():
		var device_name := Input.get_joy_name(device_id).strip_edges()
		if device_name == "":
			device_name = _fallback_device_name(device_id)
		result.append({
			"device_id": device_id,
			"device_name": device_name,
		})
	return result


func _assign_device_to_slot(slot_id: int, device_data: Dictionary) -> void:
	var previous_device_id := -1
	if _slots_by_id.has(slot_id):
		var previous_slot: Dictionary = _slots_by_id[slot_id]
		previous_device_id = int(previous_slot.get("device_id", -1))
	if previous_device_id >= 0:
		_device_to_slot.erase(previous_device_id)

	var device_id := int(device_data.get("device_id", -1))
	var device_name := String(device_data.get("device_name", _fallback_device_name(device_id)))
	_slots_by_id[slot_id] = {
		"slot_id": slot_id,
		"device_id": device_id,
		"device_name": device_name,
		"missing": false,
	}
	_device_to_slot[device_id] = slot_id
	if not _last_aim_by_slot.has(slot_id):
		_last_aim_by_slot[slot_id] = Vector2.UP
	_configure_slot_actions(slot_id, device_id)


func _remove_slot(slot_id: int) -> void:
	if not _slots_by_id.has(slot_id):
		return
	var slot: Dictionary = _slots_by_id[slot_id]
	_device_to_slot.erase(int(slot.get("device_id", -1)))
	_slots_by_id.erase(slot_id)
	_last_aim_by_slot.erase(slot_id)
	_debug_input_frames.erase(slot_id)
	_clear_slot_actions(slot_id)


func _refresh_slot_name(slot_id: int, device_data: Dictionary) -> bool:
	var slot: Dictionary = _slots_by_id[slot_id]
	var next_name := String(device_data.get("device_name", ""))
	if String(slot.get("device_name", "")) == next_name:
		return false
	slot["device_name"] = next_name
	_slots_by_id[slot_id] = slot
	return true


func _lowest_open_slot_id() -> int:
	for slot_id in range(FIRST_CONTROLLER_SLOT_ID, LAST_CONTROLLER_SLOT_ID + 1):
		if not _slots_by_id.has(slot_id):
			return slot_id
	return -1


func _lowest_missing_slot_id() -> int:
	for slot_id in range(FIRST_CONTROLLER_SLOT_ID, LAST_CONTROLLER_SLOT_ID + 1):
		if not _slots_by_id.has(slot_id):
			continue
		var slot: Dictionary = _slots_by_id[slot_id]
		if bool(slot.get("missing", false)):
			return slot_id
	return -1


func _configure_slot_actions(slot_id: int, device_id: int) -> void:
	_clear_slot_actions(slot_id)
	for suffix in ACTION_SUFFIXES:
		var action_name := _action_name(slot_id, suffix)
		InputMap.add_action(action_name, CONTROLLER_DEADZONE)

	_add_axis_event(_action_name(slot_id, "move_left"), device_id, JOY_AXIS_LEFT_X, -1.0)
	_add_button_event(_action_name(slot_id, "move_left"), device_id, JOY_BUTTON_DPAD_LEFT)
	_add_axis_event(_action_name(slot_id, "move_right"), device_id, JOY_AXIS_LEFT_X, 1.0)
	_add_button_event(_action_name(slot_id, "move_right"), device_id, JOY_BUTTON_DPAD_RIGHT)
	_add_axis_event(_action_name(slot_id, "move_up"), device_id, JOY_AXIS_LEFT_Y, -1.0)
	_add_button_event(_action_name(slot_id, "move_up"), device_id, JOY_BUTTON_DPAD_UP)
	_add_axis_event(_action_name(slot_id, "move_down"), device_id, JOY_AXIS_LEFT_Y, 1.0)
	_add_button_event(_action_name(slot_id, "move_down"), device_id, JOY_BUTTON_DPAD_DOWN)

	_add_axis_event(_action_name(slot_id, "aim_left"), device_id, JOY_AXIS_RIGHT_X, -1.0)
	_add_axis_event(_action_name(slot_id, "aim_right"), device_id, JOY_AXIS_RIGHT_X, 1.0)
	_add_axis_event(_action_name(slot_id, "aim_up"), device_id, JOY_AXIS_RIGHT_Y, -1.0)
	_add_axis_event(_action_name(slot_id, "aim_down"), device_id, JOY_AXIS_RIGHT_Y, 1.0)

	_add_axis_event(_action_name(slot_id, "fire"), device_id, JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_button_event(_action_name(slot_id, "active_item"), device_id, JOY_BUTTON_X)
	_add_button_event(_action_name(slot_id, "merge"), device_id, JOY_BUTTON_A)
	_add_button_event(_action_name(slot_id, "expression"), device_id, JOY_BUTTON_Y)
	_add_button_event(_action_name(slot_id, "pause"), device_id, JOY_BUTTON_START)


func _clear_slot_actions(slot_id: int) -> void:
	for suffix in ACTION_SUFFIXES:
		var action_name := _action_name(slot_id, suffix)
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)


func _add_axis_event(action_name: StringName, device_id: int, axis: int, axis_value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = axis
	event.axis_value = axis_value
	InputMap.action_add_event(action_name, event)


func _add_button_event(action_name: StringName, device_id: int, button_index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device_id
	event.button_index = button_index
	InputMap.action_add_event(action_name, event)


func _normalized_input_frame(slot_id: int, frame: Dictionary) -> Dictionary:
	var move := Vector2.ZERO
	var move_value: Variant = frame.get("move", Vector2.ZERO)
	if move_value is Vector2:
		move = move_value
	if move.length() <= CONTROLLER_DEADZONE:
		move = Vector2.ZERO
	else:
		move = move.limit_length(1.0)

	var aim := Vector2.ZERO
	var aim_value: Variant = frame.get("aim", Vector2.ZERO)
	if aim_value is Vector2:
		aim = aim_value
	if aim.length() > CONTROLLER_DEADZONE:
		_last_aim_by_slot[slot_id] = aim.normalized()
	var last_aim: Vector2 = _last_aim_by_slot.get(slot_id, Vector2.UP)
	return {
		"move": move,
		"aim": last_aim,
		"fire_held": bool(frame.get("fire_held", false)),
		"active_item_pressed": bool(frame.get("active_item_pressed", false)),
		"merge_held": bool(frame.get("merge_held", false)),
		"expression_held": bool(frame.get("expression_held", false)),
		"pause_pressed": bool(frame.get("pause_pressed", false)),
	}


func _default_input_frame(slot_id: int) -> Dictionary:
	var last_aim: Vector2 = _last_aim_by_slot.get(slot_id, Vector2.UP)
	return {
		"move": Vector2.ZERO,
		"aim": last_aim,
		"fire_held": false,
		"active_item_pressed": false,
		"merge_held": false,
		"expression_held": false,
		"pause_pressed": false,
	}


func _keyboard_slot() -> Dictionary:
	return {
		"slot_id": KEYBOARD_SLOT_ID,
		"device_id": -1,
		"device_name": KEYBOARD_DEVICE_NAME,
		"missing": false,
	}


func _action_name(slot_id: int, suffix: String) -> StringName:
	return StringName((ACTION_PREFIX_FORMAT % slot_id) + suffix)


func _fallback_device_name(device_id: int) -> String:
	return "Controller %d" % (device_id + 1)
