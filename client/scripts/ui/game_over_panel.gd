# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name GameOverPanel
extends CanvasLayer


signal quit_to_title_requested()
signal restart_requested()

const BUTTON_ACTION_QUIT_TO_TITLE: String = "quit_to_title"
const BUTTON_ACTION_RESTART: String = "restart"
const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)

var _button_actions: Array[String] = []
var _buttons: Array[Button] = []
var _pressed_button_index: int = -1
var _quit_button: Button = null
var _restart_button: Button = null
var _selection_locked: bool = false
var _summary_label: Label = null
var _new_unlocks_label: Label = null
var _title_label: Label = null
var _kills: int = 0
var _build_summary: Dictionary = {}
var _newly_unlocked: Variant = []
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
	_new_unlocks_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/NewUnlocksLabel"
	) as Label
	if _title_label == null or _restart_button == null or _quit_button == null:
		push_error("[GameOverPanel] missing required scene nodes")
		return
	if _summary_label == null or _new_unlocks_label == null:
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


func configure(
	kills: int,
	run_time: float,
	completed: bool = false,
	build_summary: Dictionary = {},
	newly_unlocked: Variant = []
) -> void:
	_kills = kills
	_run_time = run_time
	_completed = completed
	_build_summary = build_summary.duplicate(true)
	_newly_unlocked = _duplicate_unlock_payload(newly_unlocked)
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
	var build_text: String = _build_summary_text()
	if not build_text.is_empty():
		summary_text = "%s\n%s" % [summary_text, build_text]
	_summary_label.text = summary_text
	_refresh_new_unlocks()


func _refresh_new_unlocks() -> void:
	if _new_unlocks_label == null:
		return
	var unlock_count: int = _new_unlock_count(_newly_unlocked)
	_new_unlocks_label.visible = unlock_count > 0
	if unlock_count <= 0:
		_new_unlocks_label.text = ""
		return
	var display_names: PackedStringArray = _new_unlock_display_names(
		_newly_unlocked
	)
	if display_names.is_empty():
		_new_unlocks_label.text = tr(
			"ui_result_new_unlocks_summary"
		).format({"count": unlock_count})
		return
	var lines: PackedStringArray = [tr("ui_result_new_unlocks_header")]
	for display_name: String in display_names:
		lines.append(tr("ui_result_new_unlock_line").format({
			"name": display_name,
		}))
	_new_unlocks_label.text = _join_text(lines, "\n")


func _duplicate_unlock_payload(payload: Variant) -> Variant:
	if payload is Dictionary:
		return (payload as Dictionary).duplicate(true)
	if payload is Array:
		return (payload as Array).duplicate(true)
	return []


func _new_unlock_count(payload: Variant) -> int:
	if payload is Array:
		return (payload as Array).size()
	if not payload is Dictionary:
		return 0
	var count: int = 0
	for raw_entries: Variant in (payload as Dictionary).values():
		if raw_entries is Array:
			count += (raw_entries as Array).size()
	return count


func _new_unlock_display_names(payload: Variant) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	if payload is Array:
		for raw_entry: Variant in payload as Array:
			var display_name: String = _unlock_display_name("", raw_entry)
			if not display_name.is_empty():
				names.append(display_name)
		return names
	if not payload is Dictionary:
		return names
	for raw_type: Variant in (payload as Dictionary).keys():
		var entry_type: String = String(raw_type)
		var raw_entries: Variant = (payload as Dictionary).get(raw_type, [])
		if not raw_entries is Array:
			continue
		for raw_entry: Variant in raw_entries as Array:
			var display_name: String = _unlock_display_name(
				entry_type,
				raw_entry
			)
			if not display_name.is_empty():
				names.append(display_name)
	return names


func _unlock_display_name(entry_type: String, raw_entry: Variant) -> String:
	if raw_entry is Dictionary:
		var name_key: String = String(
			(raw_entry as Dictionary).get("name_key", "")
		)
		if not name_key.is_empty():
			return tr(name_key)
		if entry_type.is_empty():
			entry_type = String(
				(raw_entry as Dictionary).get("content_type", "")
			)
		raw_entry = String((raw_entry as Dictionary).get("id", ""))
	var entry_id: String = String(raw_entry)
	if entry_id.is_empty():
		return ""
	var content_source: Node = get_node_or_null("/root/ContentUnlockSystem")
	if content_source == null or not content_source.has_method("codex_entries"):
		return ""
	var candidate_types: Array[String] = [entry_type]
	if entry_type.is_empty():
		candidate_types = [
			CONTENT_UNLOCK_TYPES.CHARACTER,
			CONTENT_UNLOCK_TYPES.GEAR_MOD,
			CONTENT_UNLOCK_TYPES.ENEMY,
		]
	for candidate_type: String in candidate_types:
		var entries_value: Variant = content_source.call(
			"codex_entries",
			candidate_type
		)
		if not entries_value is Array:
			continue
		for candidate: Variant in entries_value as Array:
			if (
				candidate is Dictionary
				and String((candidate as Dictionary).get("id", ""))
				== entry_id
			):
				var name_key: String = String(
					(candidate as Dictionary).get("name_key", "")
				)
				return tr(name_key) if not name_key.is_empty() else ""
	return ""


func _build_summary_text() -> String:
	var lines: PackedStringArray = PackedStringArray()
	var gear_mods: Array = (
		_build_summary.get("gear_mods", [])
		if _build_summary.get("gear_mods", []) is Array
		else []
	)
	for raw_entry: Variant in gear_mods:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var mod_name_key: String = String(entry.get("name_key", ""))
		if mod_name_key.is_empty():
			continue
		var display_rank: int = maxi(
			int(entry.get("display_rank", int(entry.get("rank", 0)) + 1)),
			1
		)
		lines.append(tr("ui_result_gear_mod_line").format({
			"name": tr(mod_name_key),
			"count": display_rank,
		}))
	if lines.is_empty():
		return tr("ui_result_no_build")
	return "%s\n%s" % [tr("ui_result_build_header"), _join_text(lines, "\n")]


func _join_text(parts: PackedStringArray, separator: String) -> String:
	var result: String = ""
	for index: int in range(parts.size()):
		if index > 0:
			result += separator
		result += parts[index]
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
