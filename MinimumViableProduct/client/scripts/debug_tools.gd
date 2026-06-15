extends CanvasLayer

const ACTION_TOGGLE_CONSOLE: StringName = &"debug_toggle_console"
const ACTION_SUBMIT_COMMAND: StringName = &"debug_submit_command"
const ACTION_CLOSE_CONSOLE: StringName = &"debug_close_console"
const PANEL_WIDTH := 500.0
const PANEL_HEIGHT := 214.0

var session: Node
var panel: ColorRect
var output_label: Label
var input_line: LineEdit


func setup(main_session: Node) -> void:
	session = main_session
	_ensure_debug_input_map()
	_build_ui()
	_log("Debug tools enabled. Type help.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE_CONSOLE):
		_toggle_console()
		get_viewport().set_input_as_handled()
	elif panel != null and panel.visible and event.is_action_pressed(ACTION_CLOSE_CONSOLE):
		panel.visible = false
		get_viewport().set_input_as_handled()
	elif panel != null and panel.visible and event.is_action_pressed(ACTION_SUBMIT_COMMAND):
		_submit_command()
		get_viewport().set_input_as_handled()


func _ensure_debug_input_map() -> void:
	_ensure_key_action(ACTION_TOGGLE_CONSOLE, [KEY_F1, KEY_QUOTELEFT])
	_ensure_key_action(ACTION_SUBMIT_COMMAND, [KEY_ENTER])
	_ensure_key_action(ACTION_CLOSE_CONSOLE, [KEY_ESCAPE])


func _ensure_key_action(action_name: StringName, keycodes: Array[int]) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for keycode in keycodes:
		var already_bound := false
		for event in InputMap.action_get_events(action_name):
			if event is InputEventKey and event.keycode == keycode:
				already_bound = true
				break
		if already_bound:
			continue

		var key_event := InputEventKey.new()
		key_event.keycode = keycode
		InputMap.action_add_event(action_name, key_event)


func _build_ui() -> void:
	panel = ColorRect.new()
	panel.name = "DebugConsolePanel"
	panel.visible = false
	panel.offset_left = 18.0
	panel.offset_top = 150.0
	panel.offset_right = panel.offset_left + PANEL_WIDTH
	panel.offset_bottom = panel.offset_top + PANEL_HEIGHT
	panel.color = Color(0.02, 0.025, 0.035, 0.92)
	add_child(panel)

	output_label = Label.new()
	output_label.name = "Output"
	output_label.offset_left = 12.0
	output_label.offset_top = 10.0
	output_label.offset_right = PANEL_WIDTH - 12.0
	output_label.offset_bottom = 158.0
	output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	output_label.add_theme_font_size_override("font_size", 14)
	output_label.add_theme_color_override("font_color", Color(0.78, 0.95, 0.86))
	panel.add_child(output_label)

	input_line = LineEdit.new()
	input_line.name = "CommandInput"
	input_line.placeholder_text = "help / stats / heal 1 / hp 3 / damage 1 / spawn 4 / clear / kill / spawner on|off / reset"
	input_line.offset_left = 12.0
	input_line.offset_top = 166.0
	input_line.offset_right = PANEL_WIDTH - 12.0
	input_line.offset_bottom = PANEL_HEIGHT - 12.0
	input_line.add_theme_font_size_override("font_size", 14)
	input_line.text_submitted.connect(_on_text_submitted)
	panel.add_child(input_line)


func _toggle_console() -> void:
	if panel == null:
		return

	panel.visible = not panel.visible
	if panel.visible:
		input_line.grab_focus()
	else:
		input_line.release_focus()


func _on_text_submitted(_text: String) -> void:
	_submit_command()


func _submit_command() -> void:
	var command := input_line.text.strip_edges()
	input_line.clear()
	if command.is_empty():
		return

	_log("> %s" % command)
	_execute_command(command)


func _execute_command(command: String) -> void:
	var parts := command.split(" ", false)
	var name := parts[0].to_lower()
	match name:
		"help":
			_log("Commands: stats, heal [n], hp <n>, damage [n], spawn [n], clear, kill, spawner on|off, reset")
		"stats":
			_log(_format_stats())
		"heal":
			var amount := _get_int_arg(parts, 1, 1)
			session.call("debug_heal_player", amount)
			_log("Healed %d. %s" % [amount, _format_stats()])
		"hp":
			var hp := _get_int_arg(parts, 1, 1)
			session.call("debug_set_hp", hp)
			_log("HP set to %d. %s" % [hp, _format_stats()])
		"damage":
			var amount := _get_int_arg(parts, 1, 1)
			session.call("debug_damage_player", amount)
			_log("Damaged %d. %s" % [amount, _format_stats()])
		"spawn":
			var count := _get_int_arg(parts, 1, 1)
			var spawned := int(session.call("debug_spawn_enemies", count))
			_log("Spawned %d enemy/enemies. %s" % [spawned, _format_stats()])
		"clear":
			var cleared := int(session.call("debug_clear_enemies", false))
			_log("Cleared %d enemy/enemies. %s" % [cleared, _format_stats()])
		"kill":
			var killed := int(session.call("debug_clear_enemies", true))
			_log("Killed %d enemy/enemies. %s" % [killed, _format_stats()])
		"spawner":
			_set_spawner(parts)
		"reset":
			get_tree().reload_current_scene()
		_:
			_log("Unknown command: %s" % name)


func _set_spawner(parts: PackedStringArray) -> void:
	if parts.size() < 2:
		_log("Usage: spawner on|off")
		return

	var enabled := parts[1].to_lower() == "on"
	if parts[1].to_lower() != "on" and parts[1].to_lower() != "off":
		_log("Usage: spawner on|off")
		return

	session.call("debug_set_spawning_enabled", enabled)
	_log("Spawner %s. %s" % ["on" if enabled else "off", _format_stats()])


func _format_stats() -> String:
	if not session.has_method("get_debug_stats"):
		return "Stats unavailable."

	var stats: Dictionary = session.call("get_debug_stats")
	return "HP %d/%d | Time %.1fs | Kills %d | Enemies %d | Spawner %s" % [
		int(stats.get("hp", 0)),
		int(stats.get("max_hp", 0)),
		float(stats.get("time", 0.0)),
		int(stats.get("kills", 0)),
		int(stats.get("enemy_count", 0)),
		"on" if bool(stats.get("spawning", false)) else "off",
	]


func _get_int_arg(parts: PackedStringArray, index: int, default_value: int) -> int:
	if parts.size() <= index or not parts[index].is_valid_int():
		return default_value

	return parts[index].to_int()


func _log(message: String) -> void:
	if output_label == null:
		return

	var lines := output_label.text.split("\n", false)
	lines.append(message)
	while lines.size() > 9:
		lines.remove_at(0)
	output_label.text = "\n".join(lines)
