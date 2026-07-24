# Doc: docs/代码/ui_effects.md
class_name UIFocusIndicator
extends Panel


const PADDING: float = 4.0

var _root: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_delta: float) -> void:
	if _root == null or not is_instance_valid(_root) or not UIManager.navigation_focus_visible():
		visible = false
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not (focused == _root or _root.is_ancestor_of(focused)):
		visible = false
		return
	global_position = focused.global_position - Vector2(PADDING, PADDING)
	size = focused.size + Vector2(PADDING * 2.0, PADDING * 2.0)
	visible = true


func bind(root: Node) -> void:
	_root = root
