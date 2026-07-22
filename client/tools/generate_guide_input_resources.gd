# Doc: docs/代码/input_service.md
# Authority: docs/决策记录.md ADR #151
extends SceneTree


const ACTION_ROOT: String = "res://resources/input/actions"
const CONTEXT_ROOT: String = "res://resources/input/contexts"

var _actions: Dictionary = {}


func _init() -> void:
	_create_directories()
	_create_actions()
	_create_contexts()
	quit()


func _create_directories() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ACTION_ROOT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTEXT_ROOT))


func _create_actions() -> void:
	_save_action(&"move", GUIDEAction.GUIDEActionValueType.AXIS_2D, true)
	_save_action(&"aim", GUIDEAction.GUIDEActionValueType.AXIS_2D, true)
	_save_action(&"pointer_position", GUIDEAction.GUIDEActionValueType.AXIS_2D, false)
	for action_id: StringName in [
		&"fire",
		&"use_active_item",
		&"interact",
		&"show_stats_panel",
		&"pause",
		&"ui_confirm",
		&"ui_back",
	]:
		_save_action(action_id, GUIDEAction.GUIDEActionValueType.BOOL, true)
	for action_id: StringName in [
		&"ui_up",
		&"ui_down",
		&"ui_left",
		&"ui_right",
		&"debug_toggle_console",
		&"debug_close_console",
	]:
		_save_action(action_id, GUIDEAction.GUIDEActionValueType.BOOL, false)


func _save_action(action_id: StringName, value_type: GUIDEAction.GUIDEActionValueType, remappable: bool) -> void:
	var action: GUIDEAction = GUIDEAction.new()
	action.name = action_id
	action.action_value_type = value_type
	action.is_remappable = remappable
	action.display_name = String(action_id)
	action.display_category = "input"
	var path: String = "%s/%s.tres" % [ACTION_ROOT, String(action_id)]
	var error: Error = ResourceSaver.save(action, path)
	if error != OK:
		push_error("Failed to save GUIDE action %s: %d" % [action_id, int(error)])
	var saved_action: GUIDEAction = ResourceLoader.load(path, "GUIDEAction", ResourceLoader.CACHE_MODE_IGNORE) as GUIDEAction
	_actions[action_id] = saved_action if saved_action != null else action


func _create_contexts() -> void:
	_save_context("gameplay", _gameplay_mappings())
	_save_context("ui", _ui_mappings())
	_save_context("debug", _debug_mappings())


func _gameplay_mappings() -> Array[GUIDEActionMapping]:
	var mappings: Array[GUIDEActionMapping] = []
	mappings.append(_mapping(&"move", [
		_vector_key(KEY_W, &"up"),
		_vector_key(KEY_S, &"down"),
		_vector_key(KEY_A, &"left"),
		_vector_key(KEY_D, &"right"),
		_vector_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, true),
	]))
	mappings.append(_mapping(&"aim", [
		_vector_key(KEY_UP, &"up"),
		_vector_key(KEY_DOWN, &"down"),
		_vector_key(KEY_LEFT, &"left"),
		_vector_key(KEY_RIGHT, &"right"),
		_vector_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, true),
		_vector_button(JOY_BUTTON_DPAD_UP, &"up"),
		_vector_button(JOY_BUTTON_DPAD_DOWN, &"down"),
		_vector_button(JOY_BUTTON_DPAD_LEFT, &"left"),
		_vector_button(JOY_BUTTON_DPAD_RIGHT, &"right"),
	]))
	mappings.append(_mapping(&"pointer_position", [_fixed_input(GUIDEInputMousePosition.new())]))
	mappings.append(_mapping(&"fire", [
		_remappable_input(_mouse_button(MOUSE_BUTTON_LEFT)),
		_remappable_input(_joy_axis(JOY_AXIS_TRIGGER_RIGHT)),
	]))
	mappings.append(_mapping(&"use_active_item", [
		_remappable_input(_key(KEY_SPACE)),
		_remappable_input(_joy_button(JOY_BUTTON_A)),
	]))
	mappings.append(_mapping(&"interact", [
		_remappable_input(_key(KEY_E)),
		_remappable_input(_joy_button(JOY_BUTTON_X)),
	]))
	mappings.append(_mapping(&"show_stats_panel", [
		_remappable_input(_key(KEY_TAB)),
		_remappable_input(_joy_button(JOY_BUTTON_BACK)),
	]))
	mappings.append(_mapping(&"pause", [
		_remappable_input(_key(KEY_ESCAPE)),
		_remappable_input(_joy_button(JOY_BUTTON_START)),
		_fixed_input(_key(KEY_ESCAPE)),
		_fixed_input(_joy_button(JOY_BUTTON_START)),
	]))
	return mappings


func _ui_mappings() -> Array[GUIDEActionMapping]:
	var mappings: Array[GUIDEActionMapping] = []
	mappings.append(_mapping(&"ui_up", _ui_direction_inputs(KEY_UP, KEY_W, JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, GUIDEInputJoyDirection.Direction.NEGATIVE)))
	mappings.append(_mapping(&"ui_down", _ui_direction_inputs(KEY_DOWN, KEY_S, JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, GUIDEInputJoyDirection.Direction.POSITIVE)))
	mappings.append(_mapping(&"ui_left", _ui_direction_inputs(KEY_LEFT, KEY_A, JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, GUIDEInputJoyDirection.Direction.NEGATIVE)))
	mappings.append(_mapping(&"ui_right", _ui_direction_inputs(KEY_RIGHT, KEY_D, JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, GUIDEInputJoyDirection.Direction.POSITIVE)))
	mappings.append(_mapping(&"ui_confirm", [
		_remappable_input(_key(KEY_ENTER)),
		_remappable_input(_joy_button(JOY_BUTTON_A)),
	]))
	mappings.append(_mapping(&"ui_back", [
		_remappable_input(_key(KEY_ESCAPE)),
		_remappable_input(_joy_button(JOY_BUTTON_B)),
		_fixed_input(_key(KEY_ESCAPE)),
		_fixed_input(_joy_button(JOY_BUTTON_B)),
	]))
	mappings.append(_mapping(&"pause", [
		_remappable_input(_key(KEY_ESCAPE)),
		_remappable_input(_joy_button(JOY_BUTTON_START)),
		_fixed_input(_key(KEY_ESCAPE)),
		_fixed_input(_joy_button(JOY_BUTTON_START)),
	]))
	return mappings


func _debug_mappings() -> Array[GUIDEActionMapping]:
	return [
		_mapping(&"debug_toggle_console", [
			_fixed_input(_key(KEY_F1)),
			_fixed_input(_key(KEY_QUOTELEFT)),
		]),
		_mapping(&"debug_close_console", [_fixed_input(_key(KEY_ESCAPE))]),
	]


func _ui_direction_inputs(
		keycode: Key,
		alternate_keycode: Key,
		button: JoyButton,
		axis: JoyAxis,
		direction: GUIDEInputJoyDirection.Direction
	) -> Array[GUIDEInputMapping]:
	var key_mapping: GUIDEInputMapping = _fixed_input(_key(keycode))
	key_mapping.triggers = [_pulse_trigger()]
	var alternate_key_mapping: GUIDEInputMapping = _fixed_input(_key(alternate_keycode))
	alternate_key_mapping.triggers = [_pulse_trigger()]
	var button_mapping: GUIDEInputMapping = _fixed_input(_joy_button(button))
	button_mapping.triggers = [_pulse_trigger()]
	var direction_mapping: GUIDEInputMapping = _fixed_input(_joy_direction(axis, direction))
	direction_mapping.triggers = [_pulse_trigger()]
	return [key_mapping, alternate_key_mapping, button_mapping, direction_mapping]


func _mapping(action_id: StringName, inputs: Array[GUIDEInputMapping]) -> GUIDEActionMapping:
	var mapping: GUIDEActionMapping = GUIDEActionMapping.new()
	mapping.action = _actions[action_id] as GUIDEAction
	mapping.input_mappings = inputs
	return mapping


func _vector_key(keycode: Key, direction: StringName) -> GUIDEInputMapping:
	var mapping: GUIDEInputMapping = _remappable_input(_key(keycode))
	mapping.modifiers = _direction_modifiers(direction)
	return mapping


func _vector_button(button: JoyButton, direction: StringName) -> GUIDEInputMapping:
	var mapping: GUIDEInputMapping = _fixed_input(_joy_button(button))
	mapping.modifiers = _direction_modifiers(direction)
	return mapping


func _vector_stick(x_axis: JoyAxis, y_axis: JoyAxis, remappable: bool) -> GUIDEInputMapping:
	var stick: GUIDEInputJoyAxis2D = GUIDEInputJoyAxis2D.new()
	stick.joy_index = -1
	stick.x = x_axis
	stick.y = y_axis
	var mapping: GUIDEInputMapping = _remappable_input(stick) if remappable else _fixed_input(stick)
	var deadzone: GUIDEModifierDeadzone = GUIDEModifierDeadzone.new()
	deadzone.lower_threshold = 0.2
	deadzone.upper_threshold = 1.0
	mapping.modifiers = [deadzone]
	return mapping


func _direction_modifiers(direction: StringName) -> Array[GUIDEModifier]:
	var result: Array[GUIDEModifier] = []
	if direction == &"up" or direction == &"down":
		result.append(GUIDEModifierInputSwizzle.new())
	if direction == &"up" or direction == &"left":
		result.append(GUIDEModifierNegate.new())
	return result


func _remappable_input(input: GUIDEInput) -> GUIDEInputMapping:
	var mapping: GUIDEInputMapping = GUIDEInputMapping.new()
	mapping.override_action_settings = true
	mapping.is_remappable = true
	mapping.input = input
	return mapping


func _fixed_input(input: GUIDEInput) -> GUIDEInputMapping:
	var mapping: GUIDEInputMapping = GUIDEInputMapping.new()
	mapping.override_action_settings = true
	mapping.is_remappable = false
	mapping.input = input
	return mapping


func _key(keycode: Key) -> GUIDEInputKey:
	var input: GUIDEInputKey = GUIDEInputKey.new()
	input.key = keycode
	return input


func _mouse_button(button: MouseButton) -> GUIDEInputMouseButton:
	var input: GUIDEInputMouseButton = GUIDEInputMouseButton.new()
	input.button = button
	return input


func _joy_button(button: JoyButton) -> GUIDEInputJoyButton:
	var input: GUIDEInputJoyButton = GUIDEInputJoyButton.new()
	input.joy_index = -1
	input.button = button
	return input


func _joy_axis(axis: JoyAxis) -> GUIDEInputJoyAxis1D:
	var input: GUIDEInputJoyAxis1D = GUIDEInputJoyAxis1D.new()
	input.joy_index = -1
	input.axis = axis
	return input


func _joy_direction(axis: JoyAxis, direction: GUIDEInputJoyDirection.Direction) -> GUIDEInputJoyDirection:
	var input: GUIDEInputJoyDirection = GUIDEInputJoyDirection.new()
	input.joy_index = -1
	input.axis = axis
	input.direction = direction
	return input


func _pulse_trigger() -> GUIDETriggerPulse:
	var trigger: GUIDETriggerPulse = GUIDETriggerPulse.new()
	trigger.trigger_on_start = true
	trigger.initial_delay = 0.35
	trigger.pulse_interval = 0.1
	return trigger


func _save_context(context_id: String, mappings: Array[GUIDEActionMapping]) -> void:
	var context: GUIDEMappingContext = GUIDEMappingContext.new()
	context.display_name = context_id
	context.mappings = mappings
	var path: String = "%s/%s.tres" % [CONTEXT_ROOT, context_id]
	var error: Error = ResourceSaver.save(context, path)
	if error != OK:
		push_error("Failed to save GUIDE context %s: %d" % [context_id, int(error)])
