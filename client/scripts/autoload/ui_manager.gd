# Doc: docs/代码/ui_manager.md
# Authority: docs/游戏设计文档.md §9.14, docs/决策记录.md ADR #23
class_name UIManagerAutoload
extends Node


signal ui_pushed(node: Node, context: Dictionary)
signal ui_popped(node: Node)
signal ui_cleared()
signal ui_replaced(node: Node, context: Dictionary)
signal navigation_focus_visibility_changed(visible: bool)

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ROOT_NAME: StringName = &"UIRoot"
const INPUT_PARTICIPANT_ID: String = "player_0"
const UI_NAVIGATION_ACTIONS: Array[String] = [
	ACTIONS.UI_UP,
	ACTIONS.UI_DOWN,
	ACTIONS.UI_LEFT,
	ACTIONS.UI_RIGHT,
	ACTIONS.UI_CONFIRM,
]

var _root: CanvasLayer
var _confirmation_cancelled: Callable = Callable()
var _confirmation_confirmed: Callable = Callable()
var _confirmation_dialog: ConfirmationDialog = null
var _navigation_focus_visible: bool = false
var _stack: Array[Node] = []
var _state_before_ui_pause: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = CanvasLayer.new()
	_root.name = ROOT_NAME
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)
	_confirmation_dialog = ConfirmationDialog.new()
	_confirmation_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirmation_dialog.confirmed.connect(_on_confirmation_confirmed)
	_confirmation_dialog.canceled.connect(_on_confirmation_cancelled)
	_root.add_child(_confirmation_dialog)
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)
	if not InputService.device_family_changed.is_connected(_on_input_device_family_changed):
		InputService.device_family_changed.connect(_on_input_device_family_changed)
	if not InputService.pointer_activity.is_connected(_on_pointer_activity):
		InputService.pointer_activity.connect(_on_pointer_activity)
	_set_navigation_focus_visible(InputService.current_device_family() == InputService.DEVICE_GAMEPAD)


func _exit_tree() -> void:
	if InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.disconnect(_on_input_action_pressed)
	if InputService.device_family_changed.is_connected(_on_input_device_family_changed):
		InputService.device_family_changed.disconnect(_on_input_device_family_changed)
	if InputService.pointer_activity.is_connected(_on_pointer_activity):
		InputService.pointer_activity.disconnect(_on_pointer_activity)


func push(scene: PackedScene, context: Dictionary = {}) -> Node:
	if scene == null:
		push_error("[UIManager] cannot push a null scene")
		return null

	var node: Node = scene.instantiate()
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(node)
	_stack.append(node)
	_apply_pause_request(node)
	ui_pushed.emit(node, context.duplicate(true))
	call_deferred("_apply_initial_focus", node)
	return node


func pop() -> Node:
	return _pop_top(true)


func replace(scene: PackedScene, context: Dictionary = {}) -> Node:
	if scene == null:
		push_error("[UIManager] cannot replace with a null scene")
		return null

	var had_previous_node: bool = not _stack.is_empty()
	_pop_top(false)
	var node: Node = push(scene, context)
	if had_previous_node:
		_restore_pause_if_needed()
	if node != null:
		ui_replaced.emit(node, context.duplicate(true))
	return node


func _pop_top(restore_pause: bool) -> Node:
	if _stack.is_empty():
		return null

	var node: Node = _stack.pop_back() as Node
	if is_instance_valid(node):
		_root.remove_child(node)
		ui_popped.emit(node)
		node.queue_free()
	if restore_pause:
		_restore_pause_if_needed()
	return node


func clear() -> void:
	while not _stack.is_empty():
		var node: Node = _stack.pop_back() as Node
		if is_instance_valid(node):
			_root.remove_child(node)
			ui_popped.emit(node)
			node.queue_free()
	_restore_pause_if_needed()
	ui_cleared.emit()


func stack_size() -> int:
	return _stack.size()


func top() -> Node:
	if _stack.is_empty():
		return null
	return _stack[_stack.size() - 1] as Node


func stack_snapshot() -> Array[Node]:
	var snapshot: Array[Node] = []
	for node: Node in _stack:
		snapshot.append(node)
	return snapshot


func show_confirmation(
		title: String,
		body: String,
		confirm_text: String,
		cancel_text: String,
		confirmed: Callable,
		cancelled: Callable
	) -> bool:
	if _confirmation_dialog == null or _confirmation_dialog.visible:
		return false
	_confirmation_confirmed = confirmed
	_confirmation_cancelled = cancelled
	_confirmation_dialog.title = title
	_confirmation_dialog.dialog_text = body
	_confirmation_dialog.ok_button_text = confirm_text
	_confirmation_dialog.cancel_button_text = cancel_text
	_confirmation_dialog.popup_centered()
	return true


func cancel_confirmation() -> bool:
	if _confirmation_dialog == null or not _confirmation_dialog.visible:
		return false
	_confirmation_dialog.hide()
	_on_confirmation_cancelled()
	return true


func navigation_focus_visible() -> bool:
	return _navigation_focus_visible


func event_requests_navigation_focus(_event: InputEvent) -> bool:
	return InputService.current_device_family() == InputService.DEVICE_GAMEPAD


func grab_focus_for_navigation(control: Control) -> bool:
	if not _navigation_focus_visible:
		return false
	if not _can_focus_control(control):
		return false
	control.grab_focus()
	return true


func _on_input_action_pressed(action_id: StringName, participant_id: String) -> void:
	if participant_id != INPUT_PARTICIPANT_ID:
		return
	if UI_NAVIGATION_ACTIONS.has(String(action_id)):
		_set_navigation_focus_visible(true, false)
		_ensure_top_navigation_focus()
		return
	if action_id == StringName(ACTIONS.UI_BACK):
		_request_top_close()


func _apply_pause_request(node: Node) -> void:
	if not _node_requests_pause(node):
		return

	if GameState.current() != GameState.PAUSED:
		_state_before_ui_pause = GameState.current()
	GameState.change_state(GameState.PAUSED, {"source": "ui_manager"})


func _restore_pause_if_needed() -> void:
	if _stack_has_pause_request():
		return
	if GameState.current() != GameState.PAUSED:
		_state_before_ui_pause = &""
		return

	var target_state: StringName = _state_before_ui_pause
	_state_before_ui_pause = &""
	if target_state == &"":
		target_state = GameState.PLAYING
	GameState.change_state(target_state, {"source": "ui_manager"})


func _stack_has_pause_request() -> bool:
	for node: Node in _stack:
		if is_instance_valid(node) and _node_requests_pause(node):
			return true
	return false


func _node_requests_pause(node: Node) -> bool:
	if node.has_meta("pauses_game") and bool(node.get_meta("pauses_game")):
		return true

	var property_value: Variant = node.get("pauses_game")
	return property_value is bool and bool(property_value)


func _request_top_close() -> bool:
	if cancel_confirmation():
		return true
	var top_node: Node = top()
	if top_node == null or not is_instance_valid(top_node):
		return false
	if not top_node.has_method("request_close"):
		return false
	top_node.call("request_close")
	return true


func _on_confirmation_confirmed() -> void:
	var callback: Callable = _confirmation_confirmed
	_clear_confirmation_callbacks()
	if callback.is_valid():
		callback.call()


func _on_confirmation_cancelled() -> void:
	var callback: Callable = _confirmation_cancelled
	_clear_confirmation_callbacks()
	if callback.is_valid():
		callback.call()


func _clear_confirmation_callbacks() -> void:
	_confirmation_confirmed = Callable()
	_confirmation_cancelled = Callable()


func _on_input_device_family_changed(device_family: StringName) -> void:
	var gamepad_active: bool = device_family == InputService.DEVICE_GAMEPAD
	_set_navigation_focus_visible(gamepad_active, false)
	if gamepad_active:
		call_deferred("_ensure_top_navigation_focus")
	else:
		call_deferred("_release_current_navigation_focus")


func _on_pointer_activity() -> void:
	_set_navigation_focus_visible(false)


func _set_navigation_focus_visible(visible: bool, release_now: bool = true) -> void:
	if _navigation_focus_visible == visible:
		return
	_navigation_focus_visible = visible
	if not _navigation_focus_visible and release_now:
		_release_current_navigation_focus()
	navigation_focus_visibility_changed.emit(_navigation_focus_visible)


func _release_current_navigation_focus() -> void:
	if _navigation_focus_visible:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null:
		return
	if focused is LineEdit or focused is TextEdit:
		return
	focused.release_focus()


func _ensure_top_navigation_focus() -> void:
	if not _navigation_focus_visible:
		return
	var top_node: Node = top()
	if top_node != null:
		_apply_initial_focus(top_node)


func _apply_initial_focus(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if not _navigation_focus_visible:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and (focused == node or node.is_ancestor_of(focused)):
		return
	if node.has_method("grab_default_focus"):
		node.call("grab_default_focus")
		return
	var control: Control = _first_focusable_control(node)
	if control != null:
		control.grab_focus()


func _first_focusable_control(node: Node) -> Control:
	if node is Control:
		var control: Control = node as Control
		if _can_focus_control(control):
			return control
	for child: Node in node.get_children():
		var found: Control = _first_focusable_control(child)
		if found != null:
			return found
	return null


func _can_focus_control(control: Control) -> bool:
	if control == null or not is_instance_valid(control):
		return false
	if not control.visible or control.focus_mode == Control.FOCUS_NONE:
		return false
	var button: BaseButton = control as BaseButton
	return button == null or not button.disabled
