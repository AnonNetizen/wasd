extends Node
## Focused async lifecycle coverage for UIManager transitions.


const PANEL_SCENE: PackedScene = preload("res://scenes/ui/settings_panel.tscn")
const MAX_WAIT_FRAMES: int = 240

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	UIManager.clear(true)

	var first: Node = UIManager.push(PANEL_SCENE, {"source": "ui_manager_smoke"})
	_expect(first != null, "push should instantiate a panel")
	_expect(await _wait_for_state(first, UIManager.UIState.ACTIVE), "push should reach ACTIVE")
	_expect(UIManager.top() == first, "active panel should be the stack top")

	var popped: Node = UIManager.pop_expected(first)
	_expect(popped == first, "pop_expected should accept the active top")
	_expect(UIManager.pop_expected(first) == null, "duplicate pop should be ignored")
	_expect(
		await _wait_for_state(first, UIManager.UIState.REMOVED),
		"popped panel should reach REMOVED"
	)
	_expect(UIManager.stack_size() == 0, "pop should empty the stack")

	var previous: Node = UIManager.push(
		PANEL_SCENE,
		{"source": "ui_manager_smoke_replace_old"}
	)
	_expect(
		await _wait_for_state(previous, UIManager.UIState.ACTIVE),
		"replace source should reach ACTIVE"
	)
	var replacement: Node = UIManager.replace(
		PANEL_SCENE,
		{"source": "ui_manager_smoke_replace_new"}
	)
	_expect(replacement != null, "replace should instantiate the replacement")
	_expect(
		await _wait_for_state(replacement, UIManager.UIState.ACTIVE),
		"replacement should enter after the previous panel exits"
	)
	_expect(UIManager.top() == replacement, "replacement should become the stack top")
	_expect(
		not is_instance_valid(previous)
		or UIManager.ui_state(previous) == UIManager.UIState.REMOVED,
		"replace should remove the previous panel"
	)

	UIManager.clear(true)
	_expect(UIManager.stack_size() == 0, "immediate clear should empty the stack")
	await get_tree().process_frame
	await get_tree().process_frame
	var ui_root: Node = UIManager.get_node_or_null("UIRoot")
	_expect(
		ui_root != null and ui_root.get_child_count() == 1,
		"clear should leave no orphan panels or effect bundles"
	)

	if _failures.is_empty():
		print("[ui-manager-smoke] PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[ui-manager-smoke] %s" % failure)
	get_tree().quit(1)


func _wait_for_state(node: Node, target_state: int) -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		if not is_instance_valid(node):
			return target_state == UIManager.UIState.REMOVED
		if UIManager.ui_state(node) == target_state:
			return true
		await get_tree().process_frame
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
