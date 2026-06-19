# Doc: docs/代码/ui_manager.md
# Authority: docs/游戏设计文档.md §9.14, docs/决策记录.md ADR #23
class_name UIManagerAutoload
extends Node


signal ui_pushed(node: Node, context: Dictionary)
signal ui_popped(node: Node)
signal ui_cleared()
signal ui_replaced(node: Node, context: Dictionary)

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ROOT_NAME: StringName = &"UIRoot"
const REPLAY_PARTICIPANT_ID: String = "player_0"

var _root: CanvasLayer
var _stack: Array[Node] = []
var _state_before_ui_pause: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = CanvasLayer.new()
	_root.name = ROOT_NAME
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)


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


func _unhandled_input(event: InputEvent) -> void:
	Replay.record_input_event(event, [ACTIONS.UI_BACK], REPLAY_PARTICIPANT_ID)

	if not event.is_action_pressed(ACTIONS.UI_BACK):
		return
	if _request_top_close():
		get_viewport().set_input_as_handled()


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
	var top_node: Node = top()
	if top_node == null or not is_instance_valid(top_node):
		return false
	if not top_node.has_method("request_close"):
		return false
	top_node.call("request_close")
	return true


func _apply_initial_focus(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
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
		if control.visible and control.focus_mode != Control.FOCUS_NONE:
			var button: BaseButton = control as BaseButton
			if button == null or not button.disabled:
				return control
	for child: Node in node.get_children():
		var found: Control = _first_focusable_control(child)
		if found != null:
			return found
	return null
