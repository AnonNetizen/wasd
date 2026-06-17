# Doc: MinimumViableProduct/docs/代码/mvp_client.md
class_name MvpAimInput
extends Node

signal aim_changed(direction: Vector2, direction_name: String)

const ACTION_UP := &"ui_up"
const ACTION_DOWN := &"ui_down"
const ACTION_LEFT := &"ui_left"
const ACTION_RIGHT := &"ui_right"
const ACTION_ACCEPT := &"ui_accept"

@export var gamepad_deadzone: float = 0.35

var current_direction: Vector2 = Vector2.UP
var direction_names: Dictionary = {
	Vector2.UP: "up",
	Vector2.DOWN: "down",
	Vector2.LEFT: "left",
	Vector2.RIGHT: "right",
}
var current_direction_name: String = ""


func _ready() -> void:
	current_direction_name = _get_direction_name(current_direction)
	_ensure_default_input_map()


func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN, gamepad_deadzone)
	if input_vector == Vector2.ZERO:
		return

	var direction := _snap_to_cardinal(input_vector)
	_set_aim(direction, _get_direction_name(direction))


func get_current_direction() -> Vector2:
	return current_direction


func get_current_direction_name() -> String:
	return current_direction_name


func apply_config(config: Dictionary) -> void:
	gamepad_deadzone = clampf(_get_number(config, "gamepad_deadzone", gamepad_deadzone), 0.0, 1.0)
	var configured_names: Dictionary = _get_dictionary(config, "direction_names", direction_names)
	direction_names[Vector2.UP] = String(configured_names.get("up", direction_names[Vector2.UP]))
	direction_names[Vector2.DOWN] = String(configured_names.get("down", direction_names[Vector2.DOWN]))
	direction_names[Vector2.LEFT] = String(configured_names.get("left", direction_names[Vector2.LEFT]))
	direction_names[Vector2.RIGHT] = String(configured_names.get("right", direction_names[Vector2.RIGHT]))
	current_direction_name = _get_direction_name(current_direction)
	for action in [ACTION_UP, ACTION_DOWN, ACTION_LEFT, ACTION_RIGHT, ACTION_ACCEPT]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, gamepad_deadzone)


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
	return String(direction_names.get(direction, direction_names[Vector2.UP]))


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
		InputMap.add_action(action, gamepad_deadzone)


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


func _get_number(section: Dictionary, key: String, default_value: float) -> float:
	var value: Variant = section.get(key, default_value)
	if value is int or value is float:
		return float(value)

	push_warning("[MvpAimInput] config.%s must be a number, using %.2f" % [key, default_value])
	return default_value


func _get_dictionary(section: Dictionary, key: String, default_value: Dictionary) -> Dictionary:
	var value: Variant = section.get(key, default_value)
	if value is Dictionary:
		return value as Dictionary

	push_warning("[MvpAimInput] config.%s must be an object, using defaults" % key)
	return default_value
