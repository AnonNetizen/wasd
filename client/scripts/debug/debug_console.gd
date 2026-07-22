# Doc: docs/代码/debug_tools.md
# Authority: docs/游戏设计文档.md §9.20, docs/词表与契约.md §9
class_name DebugConsole
extends CanvasLayer


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const GM_COMMAND_REGISTRY_SCRIPT := preload("res://scripts/debug/gm_command_registry.gd")
const PANEL_HEIGHT_RATIO: float = 0.32
const MAX_LOG_LINES: int = 80

var _boot: Node = null
var _enabled: bool = false
var _input_line: LineEdit = null
var _log_lines: PackedStringArray = []
var _log_view: RichTextLabel = null
var _registry: Node = null
var _root: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_ui()
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)


func _exit_tree() -> void:
	InputService.set_debug_capture_active(false)
	if InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.disconnect(_on_input_action_pressed)


func setup(boot: Node, enabled_override: bool = true) -> void:
	_boot = boot
	_enabled = enabled_override and _debug_tools_allowed()
	if not _enabled:
		queue_free()
		return
	_registry = GM_COMMAND_REGISTRY_SCRIPT.new()
	_registry.name = "GMCommandRegistry"
	add_child(_registry)
	_registry.call("setup", _boot)
	_append_log("DebugConsole ready. Type help.")


func _on_input_action_pressed(action_id: StringName, _participant_id: String) -> void:
	if not _enabled:
		return
	if action_id == StringName(ACTIONS.DEBUG_TOGGLE_CONSOLE):
		_set_console_visible(not is_console_visible())
		return
	if is_console_visible() and action_id in [StringName(ACTIONS.DEBUG_CLOSE_CONSOLE), StringName(ACTIONS.UI_BACK)]:
		_set_console_visible(false)


func execute_command(command: String) -> Dictionary:
	if not _enabled:
		return {
			"ok": false,
			"message": "debug console disabled",
		}
	if _registry == null or not is_instance_valid(_registry):
		return {
			"ok": false,
			"message": "gm registry unavailable",
		}
	var trimmed: String = command.strip_edges()
	if trimmed.is_empty():
		return {
			"ok": false,
			"message": "empty command",
		}
	_append_log("> %s" % trimmed)
	var result: Dictionary = _registry.call("execute", trimmed)
	var prefix: String = "ok" if bool(result.get("ok", false)) else "error"
	_append_log("[%s] %s" % [prefix, String(result.get("message", ""))])
	return result


func is_console_visible() -> bool:
	return _root != null and _root.visible


func execute_command_for_test(command: String) -> Dictionary:
	return execute_command(command)


func is_console_visible_for_test() -> bool:
	return is_console_visible()


func set_console_visible_for_test(is_visible: bool) -> void:
	_set_console_visible(is_visible)


func has_registry_for_test() -> bool:
	return _registry != null and is_instance_valid(_registry)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "DebugConsoleRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "DebugConsolePanel"
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0 - PANEL_HEIGHT_RATIO
	panel.anchor_bottom = 1.0
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)

	var style_box: StyleBoxFlat = StyleBoxFlat.new()
	style_box.bg_color = Color(0.03, 0.035, 0.04, 0.92)
	style_box.border_color = Color(0.22, 0.28, 0.34, 1.0)
	style_box.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style_box)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_log_view = RichTextLabel.new()
	_log_view.name = "DebugConsoleLog"
	_log_view.fit_content = false
	_log_view.scroll_following = true
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.bbcode_enabled = false
	box.add_child(_log_view)

	_input_line = LineEdit.new()
	_input_line.name = "DebugConsoleInput"
	_input_line.placeholder_text = "GM command"
	_input_line.text_submitted.connect(_on_command_submitted)
	box.add_child(_input_line)


func _on_command_submitted(command: String) -> void:
	var result: Dictionary = execute_command(command)
	if bool(result.get("ok", false)) and _input_line != null:
		_input_line.clear()


func _set_console_visible(is_visible: bool) -> void:
	if _root == null:
		return
	_root.visible = is_visible
	InputService.set_debug_capture_active(is_visible)
	if is_visible and _input_line != null:
		_input_line.grab_focus()
	elif _input_line != null:
		_input_line.release_focus()


func _append_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	if _log_view != null:
		_log_view.text = "\n".join(_log_lines)


func _debug_tools_allowed() -> bool:
	return OS.is_debug_build() or OS.has_feature("dev_tools")
