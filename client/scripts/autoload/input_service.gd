# Doc: docs/代码/input_service.md
# Authority: docs/决策记录.md ADR #151, docs/词表与契约.md §7
class_name InputServiceAutoload
extends Node


signal action_pressed(action_id: StringName, participant_id: String)
signal action_released(action_id: StringName, participant_id: String)
signal vector_changed(action_id: StringName, value: Vector2, participant_id: String)
signal device_family_changed(device_family: StringName)
signal pointer_activity()
signal bindings_changed()
signal remap_started(binding_id: StringName, device_group: StringName)
signal remap_conflict(binding_id: StringName, conflicts: Array[StringName])
signal remap_finished(binding_id: StringName, applied: bool)

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const INPUT_BINDING_IDS := preload("res://scripts/contracts/input_binding_ids.gd")

const DEFAULT_PARTICIPANT_ID: String = "player_0"
const DEVICE_KEYBOARD_MOUSE: StringName = &"keyboard_mouse"
const DEVICE_GAMEPAD: StringName = &"gamepad"
const AIM_SOURCE_DIRECTION: StringName = &"direction"
const AIM_SOURCE_POINTER: StringName = &"pointer"
const INPUT_BINDINGS_PATH: String = "user://input_bindings.tres"
const INPUT_BINDINGS_TEMP_PATH: String = "user://input_bindings.tmp.tres"
const INPUT_BINDINGS_BACKUP_PATH: String = "user://input_bindings.bak.tres"
const INPUT_BINDINGS_INVALID_PATH: String = "user://input_bindings.invalid.tres"
const INPUT_BINDINGS_SCHEMA_VERSION: int = 1
const FORCE_RELEASE_DEBUG_TOOLS_OFF_FLAG: String = "--force-release-debug-tools-off"
const CONTEXT_GAMEPLAY_PATH: String = "res://resources/input/contexts/gameplay.tres"
const CONTEXT_UI_PATH: String = "res://resources/input/contexts/ui.tres"
const CONTEXT_DEBUG_PATH: String = "res://resources/input/contexts/debug.tres"
const ACTION_ROOT: String = "res://resources/input/actions"
const VECTOR_EPSILON_SQUARED: float = 0.000001

const BINDING_MOVE_UP: StringName = INPUT_BINDING_IDS.INPUT_MOVE_UP
const BINDING_MOVE_DOWN: StringName = INPUT_BINDING_IDS.INPUT_MOVE_DOWN
const BINDING_MOVE_LEFT: StringName = INPUT_BINDING_IDS.INPUT_MOVE_LEFT
const BINDING_MOVE_RIGHT: StringName = INPUT_BINDING_IDS.INPUT_MOVE_RIGHT
const BINDING_MOVE_STICK: StringName = INPUT_BINDING_IDS.INPUT_MOVE_STICK
const BINDING_AIM_UP: StringName = INPUT_BINDING_IDS.INPUT_AIM_UP
const BINDING_AIM_DOWN: StringName = INPUT_BINDING_IDS.INPUT_AIM_DOWN
const BINDING_AIM_LEFT: StringName = INPUT_BINDING_IDS.INPUT_AIM_LEFT
const BINDING_AIM_RIGHT: StringName = INPUT_BINDING_IDS.INPUT_AIM_RIGHT
const BINDING_AIM_STICK: StringName = INPUT_BINDING_IDS.INPUT_AIM_STICK
const BINDING_FIRE: StringName = INPUT_BINDING_IDS.INPUT_FIRE
const BINDING_USE_ACTIVE_ITEM: StringName = INPUT_BINDING_IDS.INPUT_USE_ACTIVE_ITEM
const BINDING_INTERACT: StringName = INPUT_BINDING_IDS.INPUT_INTERACT
const BINDING_SHOW_STATS_PANEL: StringName = INPUT_BINDING_IDS.INPUT_SHOW_STATS_PANEL
const BINDING_PAUSE: StringName = INPUT_BINDING_IDS.INPUT_PAUSE
const BINDING_UI_CONFIRM: StringName = INPUT_BINDING_IDS.INPUT_UI_CONFIRM
const BINDING_UI_BACK: StringName = INPUT_BINDING_IDS.INPUT_UI_BACK
const BINDING_ORDER: Array[StringName] = [
	BINDING_MOVE_UP,
	BINDING_MOVE_DOWN,
	BINDING_MOVE_LEFT,
	BINDING_MOVE_RIGHT,
	BINDING_MOVE_STICK,
	BINDING_AIM_UP,
	BINDING_AIM_DOWN,
	BINDING_AIM_LEFT,
	BINDING_AIM_RIGHT,
	BINDING_AIM_STICK,
	BINDING_FIRE,
	BINDING_USE_ACTIVE_ITEM,
	BINDING_INTERACT,
	BINDING_SHOW_STATS_PANEL,
	BINDING_PAUSE,
	BINDING_UI_CONFIRM,
	BINDING_UI_BACK,
]

const ACTION_RESOURCE_NAMES: PackedStringArray = [
	"move",
	"aim",
	"pointer_position",
	"fire",
	"use_active_item",
	"interact",
	"show_stats_panel",
	"pause",
	"ui_confirm",
	"ui_back",
	"ui_up",
	"ui_down",
	"ui_left",
	"ui_right",
	"debug_toggle_console",
	"debug_close_console",
]
const VECTOR_ACTION_IDS: Array[StringName] = [
	&"move",
	&"aim",
	&"pointer_position",
]
const UI_BRIDGE_ACTIONS: Dictionary = {
	&"ui_up": &"ui_up",
	&"ui_down": &"ui_down",
	&"ui_left": &"ui_left",
	&"ui_right": &"ui_right",
	&"ui_confirm": &"ui_accept",
	&"ui_back": &"ui_cancel",
}

var _actions: Dictionary = {}
var _binding_items: Dictionary = {}
var _binding_specs: Dictionary = {}
var _context_signature: String = ""
var _contexts: Dictionary = {}
var _current_device_family: StringName = DEVICE_KEYBOARD_MOUSE
var _debug_capture_active: bool = false
var _formatter: GUIDEInputFormatter = null
var _input_detector: GUIDEInputDetector = null
var _last_aim_source: StringName = AIM_SOURCE_DIRECTION
var _last_emitted_vector_values: Dictionary = {}
var _pending_bool_edges: Array[Dictionary] = []
var _pending_ui_bridge_actions: Array[StringName] = []
var _physical_bool_values: Dictionary = {}
var _physical_vector_values: Dictionary = {}
var _playback_active: bool = false
var _playback_values: Dictionary = {}
var _remapper: GUIDERemapper = null
var _remapping_config: GUIDERemappingConfig = null
var _pending_remap: Dictionary = {}
var _resolved_aim: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_resources()
	if _actions.is_empty() or _contexts.is_empty():
		push_error("[InputService] GUIDE input resources are unavailable")
		set_process(false)
		return
	_binding_specs = _build_binding_specs()
	_remapper = GUIDERemapper.new()
	_input_detector = GUIDEInputDetector.new()
	_input_detector.name = "GUIDEInputDetector"
	_input_detector.process_mode = Node.PROCESS_MODE_ALWAYS
	_input_detector.abort_detection_on = _build_abort_inputs()
	_input_detector.input_detected.connect(_on_input_detected)
	add_child(_input_detector)
	_load_remapping_config()
	_rebuild_remapper()
	_apply_legacy_settings_migration()
	_apply_remapping_config()
	_formatter = GUIDEInputFormatter.new(32, _prompt_mapping_for_action)
	_configure_formatter_filter()
	_connect_ui_bridge_actions()
	if not GameState.state_changed.is_connected(_on_game_state_changed):
		GameState.state_changed.connect(_on_game_state_changed)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	call_deferred("_connect_ui_manager")
	call_deferred("_apply_contexts")


func _process(_delta: float) -> void:
	if _playback_active:
		return
	_sample_physical_actions()


func _physics_process(_delta: float) -> void:
	_flush_physical_edges()


func _input(event: InputEvent) -> void:
	if not _pending_remap.is_empty() and _is_remap_abort_event(event):
		get_viewport().set_input_as_handled()
		call_deferred("cancel_remap")
		return
	if event is InputEventKey or event is InputEventMouse:
		_set_device_family(DEVICE_KEYBOARD_MOUSE)
		if event is InputEventMouseMotion:
			_last_aim_source = AIM_SOURCE_POINTER
			if (event as InputEventMouseMotion).relative.length_squared() > 0.0:
				pointer_activity.emit()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			pointer_activity.emit()
		return
	if event is InputEventJoypadButton:
		_set_device_family(DEVICE_GAMEPAD)
		return
	var joy_motion: InputEventJoypadMotion = event as InputEventJoypadMotion
	if joy_motion != null and absf(joy_motion.axis_value) >= 0.2:
		_set_device_family(DEVICE_GAMEPAD)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_runtime_values(true)
		cancel_remap()


func vector(action_id: StringName, participant_id: String = DEFAULT_PARTICIPANT_ID) -> Vector2:
	if participant_id != DEFAULT_PARTICIPANT_ID:
		return Vector2.ZERO
	if _playback_active:
		return _variant_to_vector(_playback_values.get(action_id, Vector2.ZERO))
	return _variant_to_vector(_physical_vector_values.get(action_id, Vector2.ZERO))


func is_pressed(action_id: StringName, participant_id: String = DEFAULT_PARTICIPANT_ID) -> bool:
	if participant_id != DEFAULT_PARTICIPANT_ID:
		return false
	if _playback_active:
		return bool(_playback_values.get(action_id, false))
	return bool(_physical_bool_values.get(action_id, false))


func pointer_viewport_position() -> Vector2:
	return vector(&"pointer_position")


func pointer_world_position(viewport: Viewport = null) -> Vector2:
	var target_viewport: Viewport = viewport if viewport != null else get_viewport()
	if target_viewport == null:
		return pointer_viewport_position()
	return target_viewport.get_canvas_transform().affine_inverse() * pointer_viewport_position()


func publish_resolved_aim(value: Vector2) -> void:
	if _playback_active:
		return
	var normalized: Vector2 = value
	if normalized.length_squared() > 1.0:
		normalized = normalized.normalized()
	if _resolved_aim.distance_squared_to(normalized) <= VECTOR_EPSILON_SQUARED:
		return
	_resolved_aim = normalized
	vector_changed.emit(&"aim", normalized, DEFAULT_PARTICIPANT_ID)


func resolved_aim() -> Vector2:
	if _playback_active:
		return vector(&"aim")
	return _resolved_aim


func should_use_pointer_aim() -> bool:
	return not _playback_active and _last_aim_source == AIM_SOURCE_POINTER


func current_device_family() -> StringName:
	return _current_device_family


func set_debug_capture_active(enabled: bool) -> void:
	if _debug_capture_active == enabled:
		return
	_debug_capture_active = enabled and _debug_inputs_enabled()
	_context_signature = ""
	_apply_contexts()


func action_resource(action_id: StringName) -> GUIDEAction:
	return _actions.get(action_id) as GUIDEAction


func prompt_text(action_id: StringName) -> String:
	var action: GUIDEAction = action_resource(action_id)
	if action == null or _formatter == null:
		return String(action_id)
	_configure_formatter_filter()
	return _formatter.action_as_text(action)


func prompt_richtext_async(action_id: StringName) -> String:
	var action: GUIDEAction = action_resource(action_id)
	if action == null or _formatter == null:
		return String(action_id)
	if DisplayServer.get_name() == "headless":
		return prompt_text(action_id)
	_configure_formatter_filter()
	return await _formatter.action_as_richtext_async(action)


func binding_rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for binding_id: StringName in BINDING_ORDER:
		var spec: Dictionary = _binding_specs[binding_id] as Dictionary
		result.append({
			"id": binding_id,
			"label_key": String(spec.get("label_key", "")),
			"keyboard_available": not _targets_for_group(spec, DEVICE_KEYBOARD_MOUSE).is_empty(),
			"gamepad_available": not _targets_for_group(spec, DEVICE_GAMEPAD).is_empty(),
		})
	return result


func binding_text(binding_id: StringName, device_group: StringName) -> String:
	var item: GUIDERemapper.ConfigItem = _primary_item(binding_id, device_group)
	if item == null or _remapper == null:
		return "—"
	var input: GUIDEInput = _remapper.get_bound_input_or_null(item)
	if input == null:
		return tr("ui_settings_input_unbound")
	if _formatter == null:
		return str(input)
	return _formatter.input_as_text(input)


func begin_remap(binding_id: StringName, device_group: StringName) -> bool:
	if _input_detector == null or _input_detector.is_detecting or not _pending_remap.is_empty():
		return false
	var item: GUIDERemapper.ConfigItem = _primary_item(binding_id, device_group)
	if item == null:
		return false
	_pending_remap = {
		"binding_id": binding_id,
		"device_group": device_group,
		"item": item,
	}
	_context_signature = ""
	_disable_all_contexts()
	_clear_runtime_values(true)
	remap_started.emit(binding_id, device_group)
	var device_types: Array[GUIDEInput.DeviceType] = []
	if device_group == DEVICE_GAMEPAD:
		device_types.append(GUIDEInput.DeviceType.JOY)
	else:
		device_types.append(GUIDEInput.DeviceType.KEYBOARD)
		device_types.append(GUIDEInput.DeviceType.MOUSE)
	if item.value_type == GUIDEAction.GUIDEActionValueType.AXIS_2D:
		_input_detector.detect_axis_2d(device_types)
	else:
		_input_detector.detect_bool(device_types)
	return true


func cancel_remap() -> void:
	if _input_detector != null and _input_detector.is_detecting:
		_input_detector.abort_detection()
	if _pending_remap.is_empty():
		return
	var binding_id: StringName = StringName(_pending_remap.get("binding_id", &""))
	_pending_remap.clear()
	remap_finished.emit(binding_id, false)
	call_deferred("_apply_contexts")


func resolve_pending_remap(replace_conflicts: bool) -> bool:
	if _pending_remap.is_empty() or not _pending_remap.has("input"):
		return false
	var binding_id: StringName = StringName(_pending_remap.get("binding_id", &""))
	if not replace_conflicts:
		_pending_remap.clear()
		remap_finished.emit(binding_id, false)
		call_deferred("_apply_contexts")
		return false
	if bool(_pending_remap.get("reserved_conflict", false)):
		_pending_remap.clear()
		remap_finished.emit(binding_id, false)
		call_deferred("_apply_contexts")
		return false
	_apply_pending_remap()
	return true


func reset_bindings_to_defaults() -> bool:
	_pending_remap.clear()
	_remapping_config = GUIDERemappingConfig.new()
	_remapping_config.custom_data = {"schema_version": INPUT_BINDINGS_SCHEMA_VERSION}
	_rebuild_remapper()
	_apply_remapping_config()
	var saved: bool = _save_remapping_config()
	bindings_changed.emit()
	return saved


func set_playback_active(enabled: bool) -> void:
	if _playback_active == enabled:
		return
	_playback_active = enabled
	_playback_values.clear()
	_clear_runtime_values(false)
	if enabled:
		_last_aim_source = AIM_SOURCE_DIRECTION


func playback_active() -> bool:
	return _playback_active


func inject_playback_value(
		action_id: StringName,
		value: Variant,
		participant_id: String = DEFAULT_PARTICIPANT_ID
	) -> bool:
	if not _playback_active or participant_id != DEFAULT_PARTICIPANT_ID:
		return false
	if VECTOR_ACTION_IDS.has(action_id):
		var vector_value: Vector2 = _variant_to_vector(value)
		if action_id != &"pointer_position" and vector_value.length_squared() > 1.0:
			vector_value = vector_value.normalized()
		var previous_vector: Vector2 = _variant_to_vector(_playback_values.get(action_id, Vector2.ZERO))
		_playback_values[action_id] = vector_value
		if not previous_vector.is_equal_approx(vector_value):
			vector_changed.emit(action_id, vector_value, participant_id)
		return true
	if not value is bool:
		return false
	var previous_pressed: bool = bool(_playback_values.get(action_id, false))
	var pressed: bool = bool(value)
	_playback_values[action_id] = pressed
	if pressed == previous_pressed:
		return true
	if pressed:
		action_pressed.emit(action_id, participant_id)
		if UI_BRIDGE_ACTIONS.has(action_id):
			_emit_ui_action(StringName(UI_BRIDGE_ACTIONS[action_id]))
	else:
		action_released.emit(action_id, participant_id)
	return true


func clear_playback_values() -> void:
	_playback_values.clear()


func debug_inject_input(event: InputEvent) -> void:
	if event == null:
		return
	var aborts_remap: bool = not _pending_remap.is_empty() and _is_remap_abort_event(event)
	_input(event)
	if aborts_remap:
		return
	if _input_detector != null and _input_detector.is_detecting:
		_input_detector.debug_inject_input(event)
		return
	GUIDE.inject_input(event)


func bindings_path() -> String:
	return INPUT_BINDINGS_PATH


func _load_resources() -> void:
	for action_name: String in ACTION_RESOURCE_NAMES:
		var action_path: String = "%s/%s.tres" % [ACTION_ROOT, action_name]
		var action: GUIDEAction = load(action_path) as GUIDEAction
		if action == null:
			push_error("[InputService] missing GUIDE action resource: %s" % action_path)
			continue
		_actions[StringName(action_name)] = action
	for context_entry: Dictionary in [
		{"id": &"gameplay", "path": CONTEXT_GAMEPLAY_PATH},
		{"id": &"ui", "path": CONTEXT_UI_PATH},
		{"id": &"debug", "path": CONTEXT_DEBUG_PATH},
	]:
		var context_path: String = String(context_entry["path"])
		var context: GUIDEMappingContext = load(context_path) as GUIDEMappingContext
		if context == null:
			push_error("[InputService] missing GUIDE mapping context: %s" % context_path)
			continue
		_contexts[context_entry["id"]] = context


func _sample_physical_actions() -> void:
	for action_id: StringName in _actions:
		var action: GUIDEAction = _actions[action_id] as GUIDEAction
		if action == null:
			continue
		if VECTOR_ACTION_IDS.has(action_id):
			var value: Vector2 = action.value_axis_2d
			if action_id != &"pointer_position" and value.length_squared() > 1.0:
				value = value.normalized()
			var previous_value: Vector2 = _variant_to_vector(
				_physical_vector_values.get(action_id, Vector2.ZERO)
			)
			_physical_vector_values[action_id] = value
			if (
				action_id == &"aim"
				and value.length_squared() > VECTOR_EPSILON_SQUARED
				and previous_value.distance_squared_to(value) > VECTOR_EPSILON_SQUARED
			):
				_last_aim_source = AIM_SOURCE_DIRECTION
			continue
		var pressed: bool = action.value_bool
		var previous_pressed: bool = bool(_physical_bool_values.get(action_id, false))
		_physical_bool_values[action_id] = pressed
		if pressed == previous_pressed:
			continue
		_pending_bool_edges.append({"action": action_id, "pressed": pressed})


func _flush_physical_edges() -> void:
	if _playback_active:
		_pending_bool_edges.clear()
		return
	var queued_edges: Array[Dictionary] = _pending_bool_edges.duplicate()
	_pending_bool_edges.clear()
	for edge: Dictionary in queued_edges:
		var action_id: StringName = StringName(edge.get("action", &""))
		if bool(edge.get("pressed", false)):
			action_pressed.emit(action_id, DEFAULT_PARTICIPANT_ID)
		else:
			action_released.emit(action_id, DEFAULT_PARTICIPANT_ID)
	for action_id: StringName in VECTOR_ACTION_IDS:
		if action_id == &"aim":
			continue
		var value: Vector2 = _variant_to_vector(_physical_vector_values.get(action_id, Vector2.ZERO))
		var previous: Vector2 = _variant_to_vector(_last_emitted_vector_values.get(action_id, Vector2.ZERO))
		if previous.distance_squared_to(value) <= VECTOR_EPSILON_SQUARED:
			continue
		_last_emitted_vector_values[action_id] = value
		vector_changed.emit(action_id, value, DEFAULT_PARTICIPANT_ID)
	_flush_ui_bridge_actions()


func _clear_runtime_values(emit_releases: bool) -> void:
	if emit_releases:
		for action_id: StringName in _physical_bool_values:
			if bool(_physical_bool_values[action_id]):
				action_released.emit(action_id, DEFAULT_PARTICIPANT_ID)
	_pending_bool_edges.clear()
	_pending_ui_bridge_actions.clear()
	_physical_bool_values.clear()
	_physical_vector_values.clear()
	for action_id: StringName in _last_emitted_vector_values:
		var previous: Vector2 = _variant_to_vector(_last_emitted_vector_values[action_id])
		if emit_releases and previous.length_squared() > VECTOR_EPSILON_SQUARED:
			vector_changed.emit(action_id, Vector2.ZERO, DEFAULT_PARTICIPANT_ID)
	_last_emitted_vector_values.clear()
	if emit_releases and _resolved_aim.length_squared() > VECTOR_EPSILON_SQUARED:
		vector_changed.emit(&"aim", Vector2.ZERO, DEFAULT_PARTICIPANT_ID)
	_resolved_aim = Vector2.ZERO


func _set_device_family(device_family: StringName) -> void:
	if _current_device_family == device_family:
		return
	_current_device_family = device_family
	_configure_formatter_filter()
	device_family_changed.emit(device_family)


func _configure_formatter_filter() -> void:
	if _formatter == null:
		return
	var device_mask: int = GUIDEInput.DeviceType.JOY
	if _current_device_family == DEVICE_KEYBOARD_MOUSE:
		device_mask = GUIDEInput.DeviceType.KEYBOARD | GUIDEInput.DeviceType.MOUSE
	_formatter.formatting_options.input_filter = func(context: GUIDEInputFormatter.FormattingContext) -> bool:
		return context.input != null and (int(context.input.device_type) & device_mask) != 0


func _connect_ui_bridge_actions() -> void:
	for action_id: StringName in UI_BRIDGE_ACTIONS:
		var action: GUIDEAction = action_resource(action_id)
		if action == null:
			continue
		var builtin_action: StringName = StringName(UI_BRIDGE_ACTIONS[action_id])
		var bridge_callable: Callable = _queue_ui_action.bind(builtin_action)
		if not action.just_triggered.is_connected(bridge_callable):
			action.just_triggered.connect(bridge_callable)


func _queue_ui_action(action_id: StringName) -> void:
	if _playback_active:
		return
	_pending_ui_bridge_actions.append(action_id)


func _flush_ui_bridge_actions() -> void:
	var queued_actions: Array[StringName] = _pending_ui_bridge_actions.duplicate()
	_pending_ui_bridge_actions.clear()
	for action_id: StringName in queued_actions:
		_emit_ui_action(action_id)


func _emit_ui_action(action_id: StringName) -> void:
	var pressed_event: InputEventAction = InputEventAction.new()
	pressed_event.action = action_id
	pressed_event.pressed = true
	pressed_event.strength = 1.0
	Input.parse_input_event(pressed_event)
	var released_event: InputEventAction = InputEventAction.new()
	released_event.action = action_id
	released_event.pressed = false
	released_event.strength = 0.0
	Input.parse_input_event(released_event)


func _connect_ui_manager() -> void:
	if UIManager == null:
		return
	if not UIManager.ui_pushed.is_connected(_on_ui_stack_changed):
		UIManager.ui_pushed.connect(_on_ui_stack_changed)
	if not UIManager.ui_popped.is_connected(_on_ui_stack_changed):
		UIManager.ui_popped.connect(_on_ui_stack_changed)
	if not UIManager.ui_cleared.is_connected(_on_ui_stack_cleared):
		UIManager.ui_cleared.connect(_on_ui_stack_cleared)
	if not UIManager.ui_replaced.is_connected(_on_ui_stack_changed):
		UIManager.ui_replaced.connect(_on_ui_stack_changed)
	_apply_contexts()


func _on_game_state_changed(_old_state: StringName, _new_state: StringName, _context: Dictionary) -> void:
	call_deferred("_apply_contexts")


func _on_ui_stack_changed(_node: Node, _context: Dictionary = {}) -> void:
	call_deferred("_apply_contexts")


func _on_ui_stack_cleared() -> void:
	call_deferred("_apply_contexts")


func _apply_contexts() -> void:
	if _input_detector != null and _input_detector.is_detecting:
		return
	var gameplay_context: GUIDEMappingContext = _contexts.get(&"gameplay") as GUIDEMappingContext
	var ui_context: GUIDEMappingContext = _contexts.get(&"ui") as GUIDEMappingContext
	var debug_context: GUIDEMappingContext = _contexts.get(&"debug") as GUIDEMappingContext
	var ui_active: bool = not GameState.is_state(GameState.PLAYING) or _debug_capture_active
	if UIManager != null:
		ui_active = ui_active or UIManager.stack_size() > 0
	var debug_inputs_enabled: bool = _debug_inputs_enabled()
	var signature: String = "%s|%s|%s" % [str(ui_active), str(debug_inputs_enabled), str(_debug_capture_active)]
	if signature == _context_signature:
		return
	_context_signature = signature
	GUIDE.release_pressed_inputs()
	_set_context_enabled(gameplay_context, not ui_active, 10)
	_set_context_enabled(ui_context, ui_active, 0)
	_set_context_enabled(debug_context, debug_inputs_enabled, 20)
	_clear_runtime_values(true)


func _debug_inputs_enabled() -> bool:
	if OS.get_cmdline_user_args().has(FORCE_RELEASE_DEBUG_TOOLS_OFF_FLAG):
		return false
	return OS.is_debug_build() or OS.has_feature("dev_tools")


func _set_context_enabled(context: GUIDEMappingContext, enabled: bool, priority: int) -> void:
	if context == null:
		return
	if enabled and not GUIDE.is_mapping_context_enabled(context):
		GUIDE.enable_mapping_context(context, false, priority)
	elif GUIDE.is_mapping_context_enabled(context):
		if not enabled:
			GUIDE.disable_mapping_context(context)


func _disable_all_contexts() -> void:
	for context: GUIDEMappingContext in GUIDE.get_enabled_mapping_contexts():
		GUIDE.disable_mapping_context(context)


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected:
		return
	_clear_runtime_values(true)
	cancel_remap()
	if Input.get_connected_joypads().is_empty():
		_set_device_family(DEVICE_KEYBOARD_MOUSE)


func _all_runtime_contexts() -> Array[GUIDEMappingContext]:
	var result: Array[GUIDEMappingContext] = []
	for context_id: StringName in [&"gameplay", &"ui", &"debug"]:
		var context: GUIDEMappingContext = _contexts.get(context_id) as GUIDEMappingContext
		if context != null:
			result.append(context)
	return result


func _build_binding_specs() -> Dictionary:
	return {
		BINDING_MOVE_UP: _binding_spec("ui_settings_input_move_up", [[&"gameplay", &"move", 0]], []),
		BINDING_MOVE_DOWN: _binding_spec("ui_settings_input_move_down", [[&"gameplay", &"move", 1]], []),
		BINDING_MOVE_LEFT: _binding_spec("ui_settings_input_move_left", [[&"gameplay", &"move", 2]], []),
		BINDING_MOVE_RIGHT: _binding_spec("ui_settings_input_move_right", [[&"gameplay", &"move", 3]], []),
		BINDING_MOVE_STICK: _binding_spec("ui_settings_input_move_stick", [], [[&"gameplay", &"move", 4]]),
		BINDING_AIM_UP: _binding_spec("ui_settings_input_aim_up", [[&"gameplay", &"aim", 0]], []),
		BINDING_AIM_DOWN: _binding_spec("ui_settings_input_aim_down", [[&"gameplay", &"aim", 1]], []),
		BINDING_AIM_LEFT: _binding_spec("ui_settings_input_aim_left", [[&"gameplay", &"aim", 2]], []),
		BINDING_AIM_RIGHT: _binding_spec("ui_settings_input_aim_right", [[&"gameplay", &"aim", 3]], []),
		BINDING_AIM_STICK: _binding_spec("ui_settings_input_aim_stick", [], [[&"gameplay", &"aim", 4]]),
		BINDING_FIRE: _binding_spec("ui_settings_input_fire", [[&"gameplay", &"fire", 0]], [[&"gameplay", &"fire", 1]]),
		BINDING_USE_ACTIVE_ITEM: _binding_spec("ui_settings_input_use_active_item", [[&"gameplay", &"use_active_item", 0]], [[&"gameplay", &"use_active_item", 1]]),
		BINDING_INTERACT: _binding_spec("ui_settings_input_interact", [[&"gameplay", &"interact", 0]], [[&"gameplay", &"interact", 1]]),
		BINDING_SHOW_STATS_PANEL: _binding_spec("ui_settings_input_show_stats_panel", [[&"gameplay", &"show_stats_panel", 0]], [[&"gameplay", &"show_stats_panel", 1]]),
		BINDING_PAUSE: _binding_spec("ui_settings_input_pause", [[&"gameplay", &"pause", 0], [&"ui", &"pause", 0]], [[&"gameplay", &"pause", 1], [&"ui", &"pause", 1]]),
		BINDING_UI_CONFIRM: _binding_spec("ui_settings_input_ui_confirm", [[&"ui", &"ui_confirm", 0]], [[&"ui", &"ui_confirm", 1]]),
		BINDING_UI_BACK: _binding_spec("ui_settings_input_ui_back", [[&"ui", &"ui_back", 0]], [[&"ui", &"ui_back", 1]]),
	}


func _binding_spec(label_key: String, keyboard_targets: Array, gamepad_targets: Array) -> Dictionary:
	return {
		"label_key": label_key,
		"keyboard_targets": keyboard_targets,
		"gamepad_targets": gamepad_targets,
	}


func _targets_for_group(spec: Dictionary, device_group: StringName) -> Array:
	if device_group == DEVICE_GAMEPAD:
		return spec.get("gamepad_targets", []) as Array
	return spec.get("keyboard_targets", []) as Array


func _rebuild_remapper() -> void:
	if _remapper == null:
		return
	_remapper.initialize(_all_runtime_contexts(), _remapping_config)
	_binding_items.clear()
	for item: GUIDERemapper.ConfigItem in _remapper.get_remappable_items():
		_binding_items[_item_key(item.context, item.action, item.index)] = item


func _primary_item(binding_id: StringName, device_group: StringName) -> GUIDERemapper.ConfigItem:
	var spec: Dictionary = _binding_specs.get(binding_id, {}) as Dictionary
	var targets: Array = _targets_for_group(spec, device_group)
	if targets.is_empty():
		return null
	return _item_for_target(targets[0] as Array)


func _items_for_binding(binding_id: StringName, device_group: StringName) -> Array[GUIDERemapper.ConfigItem]:
	var result: Array[GUIDERemapper.ConfigItem] = []
	var spec: Dictionary = _binding_specs.get(binding_id, {}) as Dictionary
	for raw_target: Variant in _targets_for_group(spec, device_group):
		var target: Array = raw_target as Array
		var item: GUIDERemapper.ConfigItem = _item_for_target(target)
		if item != null:
			result.append(item)
	return result


func _item_for_target(target: Array) -> GUIDERemapper.ConfigItem:
	if target.size() != 3:
		return null
	var context: GUIDEMappingContext = _contexts.get(target[0]) as GUIDEMappingContext
	var action: GUIDEAction = _actions.get(target[1]) as GUIDEAction
	return _binding_items.get(_item_key(context, action, int(target[2]))) as GUIDERemapper.ConfigItem


func _item_key(context: GUIDEMappingContext, action: GUIDEAction, index: int) -> String:
	if context == null or action == null:
		return ""
	return "%s|%s|%d" % [context.resource_path, action.resource_path, index]


func _on_input_detected(input: GUIDEInput) -> void:
	if _pending_remap.is_empty():
		call_deferred("_apply_contexts")
		return
	var binding_id: StringName = StringName(_pending_remap.get("binding_id", &""))
	if input == null:
		_pending_remap.clear()
		remap_finished.emit(binding_id, false)
		call_deferred("_apply_contexts")
		return
	_pending_remap["input"] = input
	var device_group: StringName = StringName(_pending_remap.get("device_group", DEVICE_KEYBOARD_MOUSE))
	var conflicts: Array[GUIDERemapper.ConfigItem] = []
	var reserved_conflict: bool = false
	for item: GUIDERemapper.ConfigItem in _items_for_binding(binding_id, device_group):
		for conflict: GUIDERemapper.ConfigItem in _remapper.get_input_collisions(item, input):
			if not _contexts_can_overlap(item.context, conflict.context):
				continue
			if conflict.action == item.action:
				continue
			if not conflicts.any(func(existing: GUIDERemapper.ConfigItem) -> bool: return existing.is_same_as(conflict)):
				conflicts.append(conflict)
				reserved_conflict = reserved_conflict or not conflict.is_remappable
	_pending_remap["conflicts"] = conflicts
	_pending_remap["reserved_conflict"] = reserved_conflict
	if conflicts.is_empty():
		_apply_pending_remap()
		return
	var conflict_ids: Array[StringName] = []
	for conflict: GUIDERemapper.ConfigItem in conflicts:
		var conflict_id: StringName = _binding_id_for_item(conflict)
		if conflict_id == &"" and conflict.action != null:
			conflict_id = conflict.action.name
		if conflict_id != &"" and not conflict_ids.has(conflict_id):
			conflict_ids.append(conflict_id)
	remap_conflict.emit(binding_id, conflict_ids)
	call_deferred("_apply_contexts")


func _apply_pending_remap() -> void:
	var binding_id: StringName = StringName(_pending_remap.get("binding_id", &""))
	var device_group: StringName = StringName(_pending_remap.get("device_group", DEVICE_KEYBOARD_MOUSE))
	var input: GUIDEInput = _pending_remap.get("input") as GUIDEInput
	for conflict: GUIDERemapper.ConfigItem in _pending_remap.get("conflicts", []) as Array:
		if conflict.is_remappable:
			_remapper.set_bound_input(conflict, null)
	var items: Array[GUIDERemapper.ConfigItem] = _items_for_binding(binding_id, device_group)
	for index: int in items.size():
		var item_input: GUIDEInput = input if index == 0 else input.duplicate(true) as GUIDEInput
		_remapper.set_bound_input(items[index], item_input)
	_remapping_config = _remapper.get_mapping_config()
	_remapping_config.custom_data["schema_version"] = INPUT_BINDINGS_SCHEMA_VERSION
	_pending_remap.clear()
	_rebuild_remapper()
	_apply_remapping_config()
	var saved: bool = _save_remapping_config()
	bindings_changed.emit()
	remap_finished.emit(binding_id, saved)
	call_deferred("_apply_contexts")


func _contexts_can_overlap(first: GUIDEMappingContext, second: GUIDEMappingContext) -> bool:
	if first == second:
		return true
	var gameplay_context: GUIDEMappingContext = _contexts.get(&"gameplay") as GUIDEMappingContext
	var ui_context: GUIDEMappingContext = _contexts.get(&"ui") as GUIDEMappingContext
	return not ((first == gameplay_context and second == ui_context) or (first == ui_context and second == gameplay_context))


func _binding_id_for_item(item: GUIDERemapper.ConfigItem) -> StringName:
	for binding_id: StringName in _binding_specs:
		var spec: Dictionary = _binding_specs[binding_id] as Dictionary
		for device_group: StringName in [DEVICE_KEYBOARD_MOUSE, DEVICE_GAMEPAD]:
			for candidate: GUIDERemapper.ConfigItem in _items_for_binding(binding_id, device_group):
				if candidate.is_same_as(item):
					return binding_id
			for raw_target: Variant in _targets_for_group(spec, device_group):
				var target: Array = raw_target as Array
				if target.size() == 3 and _contexts.get(target[0]) == item.context and _actions.get(target[1]) == item.action:
					return binding_id
	return &""


func _prompt_mapping_for_action(action: GUIDEAction) -> GUIDEActionMapping:
	if action == null:
		return null
	for context: GUIDEMappingContext in _all_runtime_contexts():
		for source_mapping: GUIDEActionMapping in context.mappings:
			if source_mapping.action != action:
				continue
			var prompt_mapping: GUIDEActionMapping = GUIDEActionMapping.new()
			prompt_mapping.action = action
			var prompt_inputs: Array[GUIDEInputMapping] = []
			var included_inputs: Array[GUIDEInput] = []
			for index: int in source_mapping.input_mappings.size():
				var source_input_mapping: GUIDEInputMapping = source_mapping.input_mappings[index]
				var prompt_input_mapping: GUIDEInputMapping = source_input_mapping.duplicate(true) as GUIDEInputMapping
				var item: GUIDERemapper.ConfigItem = _binding_items.get(
					_item_key(context, action, index)
				) as GUIDERemapper.ConfigItem
				if item != null and _remapper != null:
					prompt_input_mapping.input = _remapper.get_bound_input_or_null(item)
				var prompt_input: GUIDEInput = prompt_input_mapping.input
				if prompt_input == null or _input_list_has_equivalent(included_inputs, prompt_input):
					continue
				included_inputs.append(prompt_input)
				prompt_inputs.append(prompt_input_mapping)
			prompt_mapping.input_mappings = prompt_inputs
			return prompt_mapping
	return null


func _input_list_has_equivalent(inputs: Array[GUIDEInput], candidate: GUIDEInput) -> bool:
	for input: GUIDEInput in inputs:
		if input.is_same_as(candidate):
			return true
	return false


func _load_remapping_config() -> void:
	_remapping_config = GUIDERemappingConfig.new()
	_remapping_config.custom_data = {"schema_version": INPUT_BINDINGS_SCHEMA_VERSION}
	if not ResourceLoader.exists(INPUT_BINDINGS_PATH):
		var missing_target_backup: GUIDERemappingConfig = _load_config_resource(INPUT_BINDINGS_BACKUP_PATH)
		if missing_target_backup != null and _is_supported_remapping_config(missing_target_backup):
			_remapping_config = missing_target_backup
			_save_remapping_config()
		return
	var config: GUIDERemappingConfig = _load_config_resource(INPUT_BINDINGS_PATH)
	if config != null and _is_supported_remapping_config(config):
		_remapping_config = config
		return
	_quarantine_invalid_bindings()
	var backup_config: GUIDERemappingConfig = _load_config_resource(INPUT_BINDINGS_BACKUP_PATH)
	if backup_config != null and _is_supported_remapping_config(backup_config):
		_remapping_config = backup_config
		_save_remapping_config()


func _load_config_resource(path: String) -> GUIDERemappingConfig:
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = ResourceLoader.load(path, "GUIDERemappingConfig", ResourceLoader.CACHE_MODE_IGNORE)
	return loaded as GUIDERemappingConfig


func _is_supported_remapping_config(config: GUIDERemappingConfig) -> bool:
	var schema_version: int = int(config.custom_data.get("schema_version", 0))
	if schema_version < 1 or schema_version > INPUT_BINDINGS_SCHEMA_VERSION:
		return false
	var allowed_contexts: Array[GUIDEMappingContext] = _all_runtime_contexts()
	for raw_context: Variant in config.remapped_inputs:
		if not raw_context is GUIDEMappingContext or not allowed_contexts.has(raw_context as GUIDEMappingContext):
			return false
		var action_map: Variant = config.remapped_inputs[raw_context]
		if not action_map is Dictionary:
			return false
		for raw_action: Variant in action_map:
			if not raw_action is GUIDEAction or not _actions.values().has(raw_action):
				return false
			var index_map: Variant = action_map[raw_action]
			if not index_map is Dictionary:
				return false
			for raw_index: Variant in index_map:
				if not raw_index is int:
					return false
				if not _context_has_mapping_index(raw_context as GUIDEMappingContext, raw_action as GUIDEAction, int(raw_index)):
					return false
				var input: Variant = index_map[raw_index]
				if input != null and not _is_supported_binding_input(input):
					return false
	return true


func _is_supported_binding_input(input: Variant) -> bool:
	return (
		input is GUIDEInputKey
		or input is GUIDEInputMouseButton
		or input is GUIDEInputJoyButton
		or input is GUIDEInputJoyAxis1D
		or input is GUIDEInputJoyAxis2D
		or input is GUIDEInputJoyDirection
	)


func _context_has_mapping_index(context: GUIDEMappingContext, action: GUIDEAction, index: int) -> bool:
	if index < 0:
		return false
	for action_mapping: GUIDEActionMapping in context.mappings:
		if action_mapping.action != action:
			continue
		if index >= action_mapping.input_mappings.size():
			return false
		var input_mapping: GUIDEInputMapping = action_mapping.input_mappings[index]
		return action.is_remappable and (not input_mapping.override_action_settings or input_mapping.is_remappable)
	return false


func _apply_remapping_config() -> void:
	if _remapping_config != null:
		GUIDE.set_remapping_config(_remapping_config)


func _save_remapping_config() -> bool:
	if _remapping_config == null:
		return false
	_remapping_config.custom_data["schema_version"] = INPUT_BINDINGS_SCHEMA_VERSION
	var save_error: Error = ResourceSaver.save(_remapping_config, INPUT_BINDINGS_TEMP_PATH)
	if save_error != OK:
		push_error("[InputService] failed to save temporary input bindings: %d" % int(save_error))
		return false
	var target_path: String = ProjectSettings.globalize_path(INPUT_BINDINGS_PATH)
	var temp_path: String = ProjectSettings.globalize_path(INPUT_BINDINGS_TEMP_PATH)
	var backup_path: String = ProjectSettings.globalize_path(INPUT_BINDINGS_BACKUP_PATH)
	if FileAccess.file_exists(target_path):
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		var copy_error: Error = DirAccess.copy_absolute(target_path, backup_path)
		if copy_error != OK:
			push_error("[InputService] failed to back up input bindings: %d" % int(copy_error))
			return false
		var remove_error: Error = DirAccess.remove_absolute(target_path)
		if remove_error != OK:
			push_error("[InputService] failed to replace input bindings: %d" % int(remove_error))
			return false
	var rename_error: Error = DirAccess.rename_absolute(temp_path, target_path)
	if rename_error == OK:
		return true
	push_error("[InputService] failed to finalize input bindings: %d" % int(rename_error))
	if FileAccess.file_exists(backup_path):
		DirAccess.copy_absolute(backup_path, target_path)
	return false


func _quarantine_invalid_bindings() -> void:
	var source_path: String = ProjectSettings.globalize_path(INPUT_BINDINGS_PATH)
	var invalid_path: String = ProjectSettings.globalize_path(INPUT_BINDINGS_INVALID_PATH)
	if not FileAccess.file_exists(source_path):
		return
	if FileAccess.file_exists(invalid_path):
		DirAccess.remove_absolute(invalid_path)
	var error: Error = DirAccess.rename_absolute(source_path, invalid_path)
	if error != OK:
		push_warning("[InputService] failed to quarantine invalid input bindings: %d" % int(error))


func _apply_legacy_settings_migration() -> void:
	if not Settings.has_method("take_legacy_input_bindings"):
		return
	var legacy: Dictionary = Settings.call("take_legacy_input_bindings") as Dictionary
	if legacy.is_empty():
		return
	for raw_binding_id: Variant in legacy:
		var binding_id: StringName = StringName(String(raw_binding_id))
		var item: GUIDERemapper.ConfigItem = _primary_item(binding_id, DEVICE_KEYBOARD_MOUSE)
		if item == null:
			continue
		var keycode: Key = _legacy_keycode(String(legacy[raw_binding_id]))
		if keycode == KEY_NONE:
			continue
		var input: GUIDEInputKey = GUIDEInputKey.new()
		input.key = keycode
		_remapper.set_bound_input(item, input)
	_remapping_config = _remapper.get_mapping_config()
	_remapping_config.custom_data["schema_version"] = INPUT_BINDINGS_SCHEMA_VERSION
	_rebuild_remapper()
	_save_remapping_config()


func _legacy_keycode(key_name: String) -> Key:
	var keycodes: Dictionary = {
		"W": KEY_W,
		"A": KEY_A,
		"S": KEY_S,
		"D": KEY_D,
		"Up": KEY_UP,
		"Down": KEY_DOWN,
		"Left": KEY_LEFT,
		"Right": KEY_RIGHT,
		"Space": KEY_SPACE,
		"Tab": KEY_TAB,
		"Escape": KEY_ESCAPE,
		"Enter": KEY_ENTER,
		"Q": KEY_Q,
		"E": KEY_E,
		"R": KEY_R,
		"F": KEY_F,
		"P": KEY_P,
		"J": KEY_J,
		"K": KEY_K,
		"L": KEY_L,
		"I": KEY_I,
	}
	return int(keycodes.get(key_name, KEY_NONE))


func _build_abort_inputs() -> Array[GUIDEInput]:
	var result: Array[GUIDEInput] = []
	var escape: GUIDEInputKey = GUIDEInputKey.new()
	escape.key = KEY_ESCAPE
	result.append(escape)
	for button: JoyButton in [JOY_BUTTON_START, JOY_BUTTON_B]:
		var joy_button: GUIDEInputJoyButton = GUIDEInputJoyButton.new()
		joy_button.joy_index = -1
		joy_button.button = button
		result.append(joy_button)
	return result


func _is_remap_abort_event(event: InputEvent) -> bool:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null:
		return key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_ESCAPE
	var button_event: InputEventJoypadButton = event as InputEventJoypadButton
	return button_event != null and button_event.pressed and button_event.button_index in [JOY_BUTTON_START, JOY_BUTTON_B]


func _variant_to_vector(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array:
		var components: Array = value as Array
		if components.size() == 2 and (components[0] is int or components[0] is float) and (components[1] is int or components[1] is float):
			return Vector2(float(components[0]), float(components[1]))
	return Vector2.ZERO
