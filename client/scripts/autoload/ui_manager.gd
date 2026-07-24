# Doc: docs/代码/ui_manager.md
# Authority: docs/游戏设计文档.md §9.14, docs/决策记录.md ADR #23
class_name UIManagerAutoload
extends Node


signal ui_pushed(node: Node, context: Dictionary)
signal ui_popped(node: Node)
signal ui_cleared()
signal ui_replaced(node: Node, context: Dictionary)
signal ui_entered(node: Node, context: Dictionary)
signal ui_exit_started(node: Node)
signal ui_removed(node: Node)
signal navigation_focus_visibility_changed(visible: bool)

enum UIState {
	ENTERING,
	ACTIVE,
	EXITING,
	REMOVED,
}

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const CONFIRMATION_MODAL_SCENE: PackedScene = preload("res://scenes/ui/confirmation_modal.tscn")
const UI_EFFECT_BUNDLE_SCENE: PackedScene = preload("res://scenes/ui/effects/ui_effect_bundle.tscn")
const UI_TRANSITION_BLOCKER_SCENE: PackedScene = preload("res://scenes/ui/effects/ui_transition_blocker.tscn")
const ROOT_NAME: StringName = &"UIRoot"
const INPUT_PARTICIPANT_ID: String = "player_0"
const UI_NAVIGATION_ACTIONS: Array[String] = [
	ACTIONS.UI_UP,
	ACTIONS.UI_DOWN,
	ACTIONS.UI_LEFT,
	ACTIONS.UI_RIGHT,
	ACTIONS.UI_CONFIRM,
]

var _clear_pending: Dictionary = {}
var _confirmation_cancelled: Callable = Callable()
var _confirmation_confirmed: Callable = Callable()
var _confirmation_modal: ConfirmationModal = null
var _contexts: Dictionary = {}
var _delayed_enters: Dictionary = {}
var _focus_restore: Dictionary = {}
var _navigation_focus_visible: bool = false
var _root: CanvasLayer
var _stack: Array[Node] = []
var _state_before_ui_pause: StringName = &""
var _states: Dictionary = {}
var _transition_blocker: Control = null
var _transitions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = CanvasLayer.new()
	_root.name = ROOT_NAME
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)
	_transition_blocker = UI_TRANSITION_BLOCKER_SCENE.instantiate() as Control
	if _transition_blocker == null:
		push_error("[UIManager] failed to instantiate transition blocker")
	else:
		_transition_blocker.visible = false
		_root.add_child(_transition_blocker)
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)
	if not InputService.device_family_changed.is_connected(_on_input_device_family_changed):
		InputService.device_family_changed.connect(_on_input_device_family_changed)
	if not InputService.pointer_activity.is_connected(_on_pointer_activity):
		InputService.pointer_activity.connect(_on_pointer_activity)
	_set_navigation_focus_visible(
		InputService.current_device_family() == InputService.DEVICE_GAMEPAD
	)


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

	var focused: Control = get_viewport().gui_get_focus_owner()
	var node: Node = scene.instantiate()
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(node)
	_stack.append(node)
	var instance_id: int = node.get_instance_id()
	_contexts[instance_id] = context.duplicate(true)
	if focused != null and is_instance_valid(focused):
		_focus_restore[instance_id] = weakref(focused)
	_install_effect_bundle(node)
	_set_state(node, UIState.ENTERING)
	_apply_pause_request(node)
	ui_pushed.emit(node, context.duplicate(true))
	_refresh_transition_blocker()
	call_deferred("_play_enter", node)
	return node


func pop(immediate: bool = false) -> Node:
	return pop_expected(top(), immediate)


func pop_expected(expected: Node, immediate: bool = false) -> Node:
	if expected == null or not is_instance_valid(expected):
		return null
	if top() != expected:
		return null
	var state: int = ui_state(expected)
	if state == UIState.EXITING or state == UIState.REMOVED:
		return null
	_start_exit(expected, true, immediate)
	return expected


func replace(scene: PackedScene, context: Dictionary = {}) -> Node:
	if scene == null:
		push_error("[UIManager] cannot replace with a null scene")
		return null

	var previous: Node = top()
	if previous == null:
		var only_node: Node = push(scene, context)
		if only_node != null:
			ui_replaced.emit(only_node, context.duplicate(true))
		return only_node

	var node: Node = push(scene, context)
	if node == null:
		return null
	_delayed_enters[node.get_instance_id()] = true
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_set_canvas_items_visible(node, false)
	_set_state(node, UIState.ENTERING)
	_start_exit(
		previous,
		false,
		false,
		Callable(self, "_start_replacement_enter").bind(node, context.duplicate(true))
	)
	return node


func clear(immediate: bool = false) -> void:
	if _stack.is_empty():
		_restore_pause_if_needed()
		ui_cleared.emit()
		return
	_clear_pending.clear()
	var snapshot: Array[Node] = stack_snapshot()
	for node: Node in snapshot:
		if not is_instance_valid(node):
			continue
		_clear_pending[node.get_instance_id()] = true
		_start_exit(node, false, immediate)
	if _clear_pending.is_empty():
		_finish_clear()


func stack_size() -> int:
	return _stack.size()


func top() -> Node:
	for index: int in range(_stack.size() - 1, -1, -1):
		var node: Node = _stack[index]
		if node != null and is_instance_valid(node):
			return node
	return null


func stack_snapshot() -> Array[Node]:
	var snapshot: Array[Node] = []
	for node: Node in _stack:
		if node != null and is_instance_valid(node):
			snapshot.append(node)
	return snapshot


func ui_state(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return UIState.REMOVED
	return int(_states.get(node.get_instance_id(), UIState.REMOVED))


func show_confirmation(
		title: String,
		body: String,
		confirm_text: String,
		cancel_text: String,
		confirmed: Callable,
		cancelled: Callable
	) -> bool:
	if _confirmation_modal != null and is_instance_valid(_confirmation_modal):
		return false
	_confirmation_confirmed = confirmed
	_confirmation_cancelled = cancelled
	_confirmation_modal = push(
		CONFIRMATION_MODAL_SCENE,
		{"source": "ui_confirmation"}
	) as ConfirmationModal
	if _confirmation_modal == null:
		_clear_confirmation_callbacks()
		return false
	_confirmation_modal.configure(title, body, confirm_text, cancel_text)
	_confirmation_modal.confirmed.connect(_on_confirmation_confirmed, CONNECT_ONE_SHOT)
	_confirmation_modal.cancelled.connect(_on_confirmation_cancelled, CONNECT_ONE_SHOT)
	return true


func cancel_confirmation() -> bool:
	if _confirmation_modal == null or not is_instance_valid(_confirmation_modal):
		return false
	_confirmation_modal.request_cancel()
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


func _play_enter(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _delayed_enters.has(node.get_instance_id()):
		return
	if ui_state(node) != UIState.ENTERING or not node.is_inside_tree():
		return
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	_set_canvas_items_visible(node, true)
	var transition: UIPanelTransition = _transition_for(node)
	var immediate: bool = bool(
		(_contexts.get(node.get_instance_id(), {}) as Dictionary).get("immediate", false)
	)
	if transition == null or immediate:
		_finish_enter(node)
		return
	transition.play_enter(Callable(self, "_finish_enter").bind(node))


func _finish_enter(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if ui_state(node) != UIState.ENTERING:
		return
	_set_state(node, UIState.ACTIVE)
	_refresh_transition_blocker()
	var context: Dictionary = (
		_contexts.get(node.get_instance_id(), {}) as Dictionary
	).duplicate(true)
	ui_entered.emit(node, context)
	call_deferred("_apply_initial_focus", node)


func _start_exit(
		node: Node,
		restore_pause: bool,
		immediate: bool,
		completed: Callable = Callable()
	) -> void:
	if node == null or not is_instance_valid(node):
		if completed.is_valid():
			completed.call()
		return
	var state: int = ui_state(node)
	if state == UIState.EXITING or state == UIState.REMOVED:
		return
	_set_state(node, UIState.EXITING)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	ui_exit_started.emit(node)
	ui_popped.emit(node)
	_refresh_transition_blocker()
	var completion: Callable = Callable(
		self,
		"_finish_remove"
	).bind(node, restore_pause, completed)
	var transition: UIPanelTransition = _transition_for(node)
	if immediate or transition == null:
		completion.call()
		return
	transition.play_exit(completion)


func _finish_remove(
		node: Node,
		restore_pause: bool,
		completed: Callable = Callable()
	) -> void:
	if node == null or not is_instance_valid(node):
		if completed.is_valid():
			completed.call()
		return
	var instance_id: int = node.get_instance_id()
	if ui_state(node) == UIState.REMOVED:
		return
	_set_state(node, UIState.REMOVED)
	_stack.erase(node)
	if node.get_parent() == _root:
		_root.remove_child(node)
	if node == _confirmation_modal:
		_confirmation_modal = null
		_clear_confirmation_callbacks()
	ui_removed.emit(node)
	node.queue_free()
	_transitions.erase(instance_id)
	_contexts.erase(instance_id)
	_delayed_enters.erase(instance_id)
	_states.erase(instance_id)
	_refresh_transition_blocker()
	if _clear_pending.has(instance_id):
		_clear_pending.erase(instance_id)
		if _clear_pending.is_empty():
			_finish_clear()
	elif restore_pause:
		_restore_pause_if_needed()
	_restore_focus_after_removal(instance_id)
	_focus_restore.erase(instance_id)
	if completed.is_valid():
		completed.call()


func _finish_clear() -> void:
	_restore_pause_if_needed()
	_refresh_transition_blocker()
	ui_cleared.emit()


func _start_replacement_enter(
		node: Node,
		context: Dictionary
	) -> void:
	if node == null or not is_instance_valid(node):
		return
	_delayed_enters.erase(node.get_instance_id())
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	_set_canvas_items_visible(node, true)
	_restore_pause_if_needed()
	_play_enter(node)
	ui_replaced.emit(node, context.duplicate(true))


func _install_effect_bundle(node: Node) -> void:
	var target: CanvasItem = _find_transition_target(node)
	var backdrop: CanvasItem = _find_named_canvas_item(node, &"Backdrop")
	var bundle: Node = UI_EFFECT_BUNDLE_SCENE.instantiate()
	if bundle == null:
		push_error("[UIManager] failed to instantiate UI effect bundle")
		return
	bundle.name = &"UIEffects"
	node.add_child(bundle)
	var transition: UIPanelTransition = bundle.get_node_or_null(
		"PanelTransition"
	) as UIPanelTransition
	if transition != null:
		transition.configure(target, backdrop)
		_transitions[node.get_instance_id()] = transition
	var button_feedback: UIButtonFeedback = bundle.get_node_or_null(
		"ButtonFeedback"
	) as UIButtonFeedback
	if button_feedback != null:
		button_feedback.bind(node)
	var focus_indicator: UIFocusIndicator = bundle.get_node_or_null(
		"FocusIndicator"
	) as UIFocusIndicator
	if focus_indicator != null:
		focus_indicator.bind(node)
	if _transition_blocker != null:
		_root.move_child(_transition_blocker, _root.get_child_count() - 1)


func _transition_for(node: Node) -> UIPanelTransition:
	if node == null or not is_instance_valid(node):
		return null
	return _transitions.get(node.get_instance_id()) as UIPanelTransition


func _find_transition_target(node: Node) -> CanvasItem:
	var panel: PanelContainer = _find_first_panel(node)
	if panel != null:
		return panel
	var motion_root: CanvasItem = _find_named_canvas_item(node, &"MotionRoot")
	if motion_root != null:
		return motion_root
	var root_control: Control = node.get_node_or_null("Root") as Control
	if root_control != null:
		return root_control
	return node as CanvasItem


func _find_first_panel(node: Node) -> PanelContainer:
	if node is PanelContainer:
		return node as PanelContainer
	for child: Node in node.get_children():
		var found: PanelContainer = _find_first_panel(child)
		if found != null:
			return found
	return null


func _find_named_canvas_item(node: Node, target_name: StringName) -> CanvasItem:
	if node.name == target_name and node is CanvasItem:
		return node as CanvasItem
	for child: Node in node.get_children():
		var found: CanvasItem = _find_named_canvas_item(child, target_name)
		if found != null:
			return found
	return null


func _set_canvas_items_visible(node: Node, visible: bool) -> void:
	for child: Node in node.get_children():
		if child.name == &"UIEffects":
			continue
		if child is CanvasItem:
			(child as CanvasItem).visible = visible


func _set_state(node: Node, state: UIState) -> void:
	if node == null or not is_instance_valid(node):
		return
	_states[node.get_instance_id()] = state


func _refresh_transition_blocker() -> void:
	if _transition_blocker == null:
		return
	var should_block: bool = false
	for node: Node in _stack:
		var state: int = ui_state(node)
		if state == UIState.ENTERING or state == UIState.EXITING:
			should_block = true
			break
	_transition_blocker.visible = should_block
	if should_block and _transition_blocker.get_parent() == _root:
		_root.move_child(_transition_blocker, _root.get_child_count() - 1)


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
	if _confirmation_modal != null and is_instance_valid(_confirmation_modal):
		return cancel_confirmation()
	var top_node: Node = top()
	if top_node == null or not is_instance_valid(top_node):
		return false
	if ui_state(top_node) != UIState.ACTIVE:
		return false
	if not top_node.has_method("request_close"):
		return false
	top_node.call("request_close")
	return true


func _on_confirmation_confirmed() -> void:
	var modal: ConfirmationModal = _confirmation_modal
	var callback: Callable = _confirmation_confirmed
	_confirmation_modal = null
	_clear_confirmation_callbacks()
	pop_expected(modal)
	if callback.is_valid():
		callback.call()


func _on_confirmation_cancelled() -> void:
	var modal: ConfirmationModal = _confirmation_modal
	var callback: Callable = _confirmation_cancelled
	_confirmation_modal = null
	_clear_confirmation_callbacks()
	pop_expected(modal)
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
	if top_node != null and ui_state(top_node) == UIState.ACTIVE:
		_apply_initial_focus(top_node)


func _apply_initial_focus(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if ui_state(node) != UIState.ACTIVE or top() != node:
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


func _restore_focus_after_removal(instance_id: int) -> void:
	if not _navigation_focus_visible:
		return
	var top_node: Node = top()
	if top_node == null or ui_state(top_node) != UIState.ACTIVE:
		return
	var restore_ref: WeakRef = _focus_restore.get(instance_id) as WeakRef
	var restore_control: Control = null
	if restore_ref != null:
		restore_control = restore_ref.get_ref() as Control
	if (
		restore_control != null
		and is_instance_valid(restore_control)
		and (
			restore_control == top_node
			or top_node.is_ancestor_of(restore_control)
		)
		and _can_focus_control(restore_control)
	):
		restore_control.grab_focus()
		return
	call_deferred("_apply_initial_focus", top_node)


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
