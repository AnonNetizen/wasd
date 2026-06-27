# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name GameOverPanel
extends CanvasLayer


signal quit_to_title_requested()
signal restart_requested()

const BUTTON_ACTION_QUIT_TO_TITLE: String = "quit_to_title"
const BUTTON_ACTION_RESTART: String = "restart"

var _button_actions: Array[String] = []
var _buttons: Array[Button] = []
var _pressed_button_index: int = -1
var _quit_button: Button = null
var _restart_button: Button = null
var _selection_locked: bool = false
var _summary_label: Label = null
var _title_label: Label = null
var _kills: int = 0
var _loot_summary: Dictionary = {}
var _run_time: float = 0.0
var _completed: bool = false


func _input(event: InputEvent) -> void:
	if UIManager.top() != self:
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var button_index: int = _button_index_at_position(mouse_button.position)
	if mouse_button.pressed:
		_pressed_button_index = button_index
		if button_index >= 0:
			get_viewport().set_input_as_handled()
		return

	var pressed_button_index: int = _pressed_button_index
	_pressed_button_index = -1
	if button_index < 0 or button_index != pressed_button_index:
		return
	get_viewport().set_input_as_handled()
	_activate_button(button_index)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_title_label = get_node_or_null("Root/Center/Panel/Margin/Layout/TitleLabel") as Label
	_restart_button = get_node_or_null("Root/Center/Panel/Margin/Layout/RestartButton") as Button
	_quit_button = get_node_or_null("Root/Center/Panel/Margin/Layout/QuitToTitleButton") as Button
	_summary_label = get_node_or_null("Root/Center/Panel/Margin/Layout/SummaryLabel") as Label
	if _title_label == null or _restart_button == null or _quit_button == null:
		push_error("[GameOverPanel] missing required scene nodes")
		return
	if _summary_label == null:
		push_error("[GameOverPanel] missing required scene nodes")
		return

	_restart_button.pressed.connect(_on_restart_pressed)
	_register_button(_restart_button, BUTTON_ACTION_RESTART)

	_quit_button.pressed.connect(_on_quit_to_title_pressed)
	_register_button(_quit_button, BUTTON_ACTION_QUIT_TO_TITLE)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh_texts()
	call_deferred("grab_default_focus")


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure(kills: int, run_time: float, completed: bool = false, loot_summary: Dictionary = {}) -> void:
	_kills = kills
	_run_time = run_time
	_completed = completed
	_loot_summary = loot_summary.duplicate(true)
	refresh_texts()


func refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_run_complete") if _completed else tr("ui_game_over")
	if _restart_button != null:
		_restart_button.text = tr("ui_restart")
	if _quit_button != null:
		_quit_button.text = tr("ui_quit_to_title")
	if _summary_label == null:
		return
	var summary_key: String = "ui_run_complete_summary" if _completed else "ui_run_summary"
	var summary_text: String = tr(summary_key).format({
		"kills": _kills,
		"time": int(_run_time),
	})
	var loot_text: String = _loot_summary_text()
	if not loot_text.is_empty():
		summary_text = "%s\n%s" % [summary_text, loot_text]
	_summary_label.text = summary_text


func _loot_summary_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var resources: Dictionary = _loot_summary.get("resources", {}) if _loot_summary.get("resources", {}) is Dictionary else {}
	var resource_ids: Array[String] = _sorted_keys(resources)
	for resource_id: String in resource_ids:
		var amount: int = int(resources.get(resource_id, 0))
		if amount <= 0:
			continue
		lines.append(tr("ui_result_resource_line").format({
			"name": tr("%s_name" % resource_id),
			"amount": amount,
		}))
	var gear_mods: Array = _loot_summary.get("gear_mods", []) if _loot_summary.get("gear_mods", []) is Array else []
	var gear_mod_counts: Dictionary = _gear_mod_counts(gear_mods)
	for mod_name_key: String in _sorted_keys(gear_mod_counts):
		var count: int = int(gear_mod_counts.get(mod_name_key, 0))
		if count <= 0:
			continue
		lines.append(tr("ui_result_gear_mod_line").format({
			"name": tr(mod_name_key),
			"count": count,
		}))
	if lines.is_empty():
		return tr("ui_result_no_loot") if _completed else tr("ui_result_no_lost_loot")
	var header_key: String = "ui_result_secured_header" if _completed else "ui_result_lost_header"
	return "%s\n%s" % [tr(header_key), _join_text(lines, "\n")]


func _join_text(parts: PackedStringArray, separator: String) -> String:
	var result: String = ""
	for index: int in range(parts.size()):
		if index > 0:
			result += separator
		result += parts[index]
	return result


func _gear_mod_counts(gear_mods: Array) -> Dictionary:
	var counts: Dictionary = {}
	for raw_entry: Variant in gear_mods:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var name_key: String = String(entry.get("name_key", ""))
		if name_key.is_empty():
			continue
		counts[name_key] = int(counts.get(name_key, 0)) + 1
	return counts


func _sorted_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in values.keys():
		var value: String = String(key)
		if not value.is_empty():
			result.append(value)
	result.sort()
	return result


func grab_default_focus() -> void:
	UIManager.grab_focus_for_navigation(_restart_button)


func _register_button(button: Button, action: String) -> void:
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	_buttons.append(button)
	_button_actions.append(action)


func _on_restart_pressed() -> void:
	_activate_button(_button_actions.find(BUTTON_ACTION_RESTART))


func _on_quit_to_title_pressed() -> void:
	_activate_button(_button_actions.find(BUTTON_ACTION_QUIT_TO_TITLE))


func _button_index_at_position(position: Vector2) -> int:
	for index: int in range(_buttons.size()):
		var button: Button = _buttons[index]
		if not is_instance_valid(button) or not button.visible or button.disabled:
			continue
		if button.get_global_rect().has_point(position):
			return index
	return -1


func _activate_button(index: int) -> void:
	if _selection_locked:
		return
	if index < 0 or index >= _buttons.size():
		return
	var action: String = _button_actions[index]
	_selection_locked = true
	if action == BUTTON_ACTION_RESTART:
		restart_requested.emit()
	elif action == BUTTON_ACTION_QUIT_TO_TITLE:
		quit_to_title_requested.emit()


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()
