extends Node
class_name MvpAimInput

signal aim_changed(direction: Vector2, direction_name: String)

const ACTION_UP := &"ui_up"
const ACTION_DOWN := &"ui_down"
const ACTION_LEFT := &"ui_left"
const ACTION_RIGHT := &"ui_right"
const ACTION_ACCEPT := &"ui_accept"
const GAMEPAD_DEADZONE := 0.35

var current_direction: Vector2 = Vector2.UP
var current_direction_name: String = "上"


func _ready() -> void:
	_ensure_default_input_map()


func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN, GAMEPAD_DEADZONE)
	if input_vector == Vector2.ZERO:
		return

	var direction := _snap_to_cardinal(input_vector)
	_set_aim(direction, _get_direction_name(direction))


func get_current_direction() -> Vector2:
	return current_direction


func get_current_direction_name() -> String:
	return current_direction_name


func _set_aim(direction: Vector2, direction_name: String) -> void:
	if direction == current_direction:
		return

	current_direction = direction
	current_direction_name = direction_name
	aim_changed.emit(current_direction, current_direction_name)


func _snap_to_cardinal(input_vector: Vector2) -> Vector2:
	if absf(input_vector.x) > absf(input_vector.y):
		return Vector2.RIGHT if input_vector.x > 0.0 else Vector2.LEFT

	return Vector2.DOWN if input_vector.y > 0.0 else Vector2.UP


func _get_direction_name(direction: Vector2) -> String:
	if direction == Vector2.DOWN:
		return "下"
	if direction == Vector2.LEFT:
		return "左"
	if direction == Vector2.RIGHT:
		return "右"
	return "上"


func _ensure_default_input_map() -> void:
	# MVP runtime bindings keep keyboard, D-pad, and both sticks on the same InputMap actions.
	_ensure_key_event(ACTION_UP, KEY_UP)
	_ensure_key_event(ACTION_DOWN, KEY_DOWN)
	_ensure_key_event(ACTION_LEFT, KEY_LEFT)
	_ensure_key_event(ACTION_RIGHT, KEY_RIGHT)
	_ensure_key_event(ACTION_ACCEPT, KEY_ENTER)
	_ensure_key_event(ACTION_ACCEPT, KEY_SPACE)

	_ensure_button_event(ACTION_UP, JOY_BUTTON_DPAD_UP)
	_ensure_button_event(ACTION_DOWN, JOY_BUTTON_DPAD_DOWN)
	_ensure_button_event(ACTION_LEFT, JOY_BUTTON_DPAD_LEFT)
	_ensure_button_event(ACTION_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_ensure_button_event(ACTION_ACCEPT, JOY_BUTTON_A)

	_ensure_motion_event(ACTION_UP, JOY_AXIS_LEFT_Y, -1.0)
	_ensure_motion_event(ACTION_DOWN, JOY_AXIS_LEFT_Y, 1.0)
	_ensure_motion_event(ACTION_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_ensure_motion_event(ACTION_RIGHT, JOY_AXIS_LEFT_X, 1.0)
	_ensure_motion_event(ACTION_UP, JOY_AXIS_RIGHT_Y, -1.0)
	_ensure_motion_event(ACTION_DOWN, JOY_AXIS_RIGHT_Y, 1.0)
	_ensure_motion_event(ACTION_LEFT, JOY_AXIS_RIGHT_X, -1.0)
	_ensure_motion_event(ACTION_RIGHT, JOY_AXIS_RIGHT_X, 1.0)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, GAMEPAD_DEADZONE)


func _ensure_key_event(action: StringName, keycode: int) -> void:
	_ensure_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event.keycode == keycode or event.physical_keycode == keycode):
			return

	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action, key_event)


func _ensure_button_event(action: StringName, button_index: int) -> void:
	_ensure_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button_index:
			return

	var button_event := InputEventJoypadButton.new()
	button_event.button_index = button_index
	InputMap.action_add_event(action, button_event)


func _ensure_motion_event(action: StringName, axis: int, axis_value: float) -> void:
	_ensure_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and signf(event.axis_value) == signf(axis_value):
			return

	var motion_event := InputEventJoypadMotion.new()
	motion_event.axis = axis
	motion_event.axis_value = axis_value
	InputMap.action_add_event(action, motion_event)
