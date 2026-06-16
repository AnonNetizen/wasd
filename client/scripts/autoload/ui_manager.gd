# Doc: docs/代码/ui_manager.md
# Authority: docs/游戏设计文档.md §9.14, docs/决策记录.md ADR #23
extends Node
class_name UIManagerAutoload


signal ui_pushed(node: Node, context: Dictionary)
signal ui_popped(node: Node)
signal ui_cleared()
signal ui_replaced(node: Node, context: Dictionary)

const ROOT_NAME: StringName = &"UIRoot"

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
	return node


func pop() -> Node:
	if _stack.is_empty():
		return null

	var node: Node = _stack.pop_back() as Node
	if is_instance_valid(node):
		_root.remove_child(node)
		ui_popped.emit(node)
		node.queue_free()
	_restore_pause_if_needed()
	return node


func replace(scene: PackedScene, context: Dictionary = {}) -> Node:
	pop()
	var node: Node = push(scene, context)
	if node != null:
		ui_replaced.emit(node, context.duplicate(true))
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


func _apply_pause_request(node: Node) -> void:
	if not _node_requests_pause(node):
		return

	if GameState.current() != GameState.PAUSED and GameState.current() != GameState.LEVEL_UP:
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
