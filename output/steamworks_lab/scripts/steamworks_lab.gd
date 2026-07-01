extends Node2D

const SESSION_SCRIPT := preload("res://scripts/network_session.gd")
const PLAYER_SCRIPT := preload("res://scripts/slime_player.gd")

const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const WORLD_RECT := Rect2(Vector2(260.0, 74.0), Vector2(960.0, 620.0))
const DEFAULT_PORT: int = 24567

const ACTION_MOVE_UP := "move_up"
const ACTION_MOVE_DOWN := "move_down"
const ACTION_MOVE_LEFT := "move_left"
const ACTION_MOVE_RIGHT := "move_right"

var _session: Node
var _players: Dictionary = {}
var _peer_inputs: Dictionary = {}
var _log_lines: Array[String] = []

var _ui_root: Control
var _status_label: Label
var _log_label: Label
var _address_input: LineEdit
var _port_input: SpinBox
var _lobby_input: LineEdit
var _steam_status_label: Label
var _host_steam_button: Button
var _join_steam_button: Button


func _ready() -> void:
	_ensure_input_actions()
	_create_session()
	_create_ui()
	_start_offline()


func _physics_process(_delta: float) -> void:
	var input_vector := _local_input_vector()
	if bool(_session.call("is_host")):
		_peer_inputs[1] = input_vector
		_apply_host_inputs()
		_session.call("broadcast_snapshot", _build_snapshot())
	elif String(_session.call("active_transport")) != "offline":
		_session.call("send_input_to_host", input_vector)
	else:
		var offline_player: Node = _ensure_player(1, "Offline Slime")
		offline_player.call("set_input_vector", input_vector)

	_update_status()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.034, 0.044, 0.047, 1.0), true)
	draw_rect(WORLD_RECT.grow(18.0), Color(0.0, 0.0, 0.0, 0.20), true)
	draw_rect(WORLD_RECT, Color(0.054, 0.074, 0.070, 1.0), true)
	draw_rect(WORLD_RECT, Color(0.40, 0.62, 0.54, 0.42), false, 2.0)
	_draw_grid()


func _create_session() -> void:
	_session = SESSION_SCRIPT.new() as Node
	_session.name = "NetworkSession"
	add_child(_session)
	_session.connect("status_changed", Callable(self, "_append_log"))
	_session.connect("session_started", Callable(self, "_on_session_started"))
	_session.connect("session_ended", Callable(self, "_on_session_ended"))
	_session.connect("peer_joined", Callable(self, "_on_peer_joined"))
	_session.connect("peer_left", Callable(self, "_on_peer_left"))
	_session.connect("input_received", Callable(self, "_on_input_received"))
	_session.connect("snapshot_received", Callable(self, "_on_snapshot_received"))


func _create_ui() -> void:
	_ui_root = Control.new()
	_ui_root.name = "UiRoot"
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ui_root)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(24.0, 24.0)
	panel.custom_minimum_size = Vector2(216.0, 710.0)
	_ui_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "Steamworks Slime Lab"
	title.add_theme_font_size_override("font_size", 20)
	rows.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "Offline"
	rows.add_child(_status_label)

	var offline_button := _make_button("Offline")
	offline_button.pressed.connect(_start_offline)
	rows.add_child(offline_button)

	var host_local_button := _make_button("Host Local")
	host_local_button.pressed.connect(_on_host_local_pressed)
	rows.add_child(host_local_button)

	_address_input = LineEdit.new()
	_address_input.text = "127.0.0.1"
	_address_input.placeholder_text = "Address"
	rows.add_child(_address_input)

	_port_input = SpinBox.new()
	_port_input.min_value = 1
	_port_input.max_value = 65535
	_port_input.value = DEFAULT_PORT
	_port_input.step = 1
	rows.add_child(_port_input)

	var join_local_button := _make_button("Join Local")
	join_local_button.pressed.connect(_on_join_local_pressed)
	rows.add_child(join_local_button)

	var separator_a := HSeparator.new()
	rows.add_child(separator_a)

	_steam_status_label = Label.new()
	_steam_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_steam_status_label.text = String(_session.call("steam_status_text"))
	rows.add_child(_steam_status_label)

	_host_steam_button = _make_button("Host Steam")
	_host_steam_button.pressed.connect(_on_host_steam_pressed)
	rows.add_child(_host_steam_button)

	_lobby_input = LineEdit.new()
	_lobby_input.placeholder_text = "Steam lobby id"
	rows.add_child(_lobby_input)

	_join_steam_button = _make_button("Join Steam by ID")
	_join_steam_button.pressed.connect(_on_join_steam_pressed)
	rows.add_child(_join_steam_button)

	var leave_button := _make_button("Leave")
	leave_button.pressed.connect(_start_offline)
	rows.add_child(leave_button)

	var separator_b := HSeparator.new()
	rows.add_child(separator_b)

	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.text = ""
	_log_label.custom_minimum_size = Vector2(188.0, 220.0)
	rows.add_child(_log_label)


func _make_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0.0, 36.0)
	return button


func _start_offline() -> void:
	if _session != null:
		_session.call("leave_session")
	_clear_players()
	_peer_inputs.clear()
	var player: Node = _ensure_player(1, "Offline Slime")
	player.call("warp_to", WORLD_RECT.get_center())
	player.call("set_local_or_host_simulated", true)
	_append_log("Offline mode. Use WASD to move the slime.")


func _on_host_local_pressed() -> void:
	_clear_players()
	_peer_inputs.clear()
	_session.call("host_local", int(_port_input.value))


func _on_join_local_pressed() -> void:
	_clear_players()
	_peer_inputs.clear()
	_session.call("join_local", _address_input.text, int(_port_input.value))


func _on_host_steam_pressed() -> void:
	_clear_players()
	_peer_inputs.clear()
	_session.call("host_steam")


func _on_join_steam_pressed() -> void:
	_clear_players()
	_peer_inputs.clear()
	_session.call("join_steam_lobby", _lobby_input.text)


func _on_session_started(host: bool, transport: String, lobby_id: String) -> void:
	if host:
		var host_player: Node = _ensure_player(1, "Host")
		host_player.call("warp_to", _spawn_position_for_slot(0))
		host_player.call("set_local_or_host_simulated", true)
	else:
		_append_log("Waiting for host snapshot...")
	if lobby_id != "":
		_lobby_input.text = lobby_id
	_append_log("Session started: %s %s" % [transport, "host" if host else "client"])


func _on_session_ended() -> void:
	_update_status()


func _on_peer_joined(peer_id: int) -> void:
	if not bool(_session.call("is_host")):
		return
	var player: Node = _ensure_player(peer_id, "Peer %d" % peer_id)
	player.call("set_local_or_host_simulated", true)
	_peer_inputs[peer_id] = Vector2.ZERO


func _on_peer_left(peer_id: int) -> void:
	_remove_player(peer_id)
	_peer_inputs.erase(peer_id)


func _on_input_received(peer_id: int, input_vector: Vector2) -> void:
	if not bool(_session.call("is_host")):
		return
	_peer_inputs[peer_id] = input_vector


func _on_snapshot_received(snapshot: Dictionary) -> void:
	if bool(_session.call("is_host")):
		return
	var players: Variant = snapshot.get("players", [])
	if not players is Array:
		return
	var seen: Dictionary = {}
	for raw_player in players:
		if not raw_player is Dictionary:
			continue
		var player_data: Dictionary = raw_player
		var peer_id := int(player_data.get("peer_id", 0))
		if peer_id <= 0:
			continue
		seen[peer_id] = true
		var player: Node = _ensure_player(peer_id, String(player_data.get("name", "Peer %d" % peer_id)))
		player.call("set_local_or_host_simulated", false)
		player.call("set_authoritative_state", _dict_to_vector(player_data.get("position", {})), _dict_to_vector(player_data.get("velocity", {})))

	for peer_id in _players.keys():
		if not seen.has(peer_id):
			_remove_player(peer_id)


func _apply_host_inputs() -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player == null:
			continue
		var input_vector: Vector2 = _peer_inputs.get(peer_id, Vector2.ZERO)
		player.call("set_input_vector", input_vector)


func _build_snapshot() -> Dictionary:
	var player_states: Array[Dictionary] = []
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player == null:
			continue
		player_states.append(player.call("snapshot_state"))
	return {
		"players": player_states,
		"transport": String(_session.call("active_transport")),
		"lobby_id": String(_session.call("lobby_id")),
	}


func _ensure_player(peer_id: int, display_name: String) -> Node:
	if _players.has(peer_id):
		return _players[peer_id]
	var player := PLAYER_SCRIPT.new() as Node
	player.name = "SlimePlayer%d" % peer_id
	player.call("set_player_info", peer_id, display_name, peer_id)
	add_child(player)
	player.call("warp_to", _spawn_position_for_slot(_players.size()))
	_players[peer_id] = player
	return player


func _remove_player(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	var player := _players[peer_id] as Node
	_players.erase(peer_id)
	if is_instance_valid(player):
		player.queue_free()


func _clear_players() -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if is_instance_valid(player):
			player.queue_free()
	_players.clear()


func _local_input_vector() -> Vector2:
	var input_vector := Input.get_vector(ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_MOVE_UP, ACTION_MOVE_DOWN)
	return input_vector.limit_length(1.0)


func _spawn_position_for_slot(slot_index: int) -> Vector2:
	var columns := 4
	var spacing := Vector2(150.0, 130.0)
	var index: int = maxi(0, slot_index)
	var column: int = index % columns
	var row: int = floori(float(index) / float(columns))
	return WORLD_RECT.position + Vector2(160.0 + float(column) * spacing.x, 140.0 + float(row) * spacing.y)


func _dict_to_vector(data: Variant) -> Vector2:
	if not data is Dictionary:
		return Vector2.ZERO
	var dictionary: Dictionary = data
	return Vector2(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)))


func _draw_grid() -> void:
	var grid_color := Color(0.33, 0.55, 0.49, 0.12)
	var step := 40.0
	for x_index in range(int(WORLD_RECT.size.x / step) + 1):
		var x := WORLD_RECT.position.x + float(x_index) * step
		draw_line(Vector2(x, WORLD_RECT.position.y), Vector2(x, WORLD_RECT.position.y + WORLD_RECT.size.y), grid_color, 1.0)
	for y_index in range(int(WORLD_RECT.size.y / step) + 1):
		var y := WORLD_RECT.position.y + float(y_index) * step
		draw_line(Vector2(WORLD_RECT.position.x, y), Vector2(WORLD_RECT.position.x + WORLD_RECT.size.x, y), grid_color, 1.0)


func _update_status() -> void:
	if _status_label == null:
		return
	_status_label.text = "Mode: %s\nPeer: %d\nLobby: %s\nPlayers: %d" % [
		String(_session.call("active_transport")),
		int(_session.call("local_peer_id")),
		String(_session.call("lobby_id")) if String(_session.call("lobby_id")) != "" else "-",
		_players.size(),
	]
	if _steam_status_label != null:
		var steam_available := bool(_session.call("steam_available"))
		_steam_status_label.text = String(_session.call("steam_status_text"))
		if _host_steam_button != null:
			_host_steam_button.disabled = not steam_available
		if _join_steam_button != null:
			_join_steam_button.disabled = not steam_available


func _append_log(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > 10:
		_log_lines.pop_front()
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)
	print("[SteamworksLab] %s" % message)


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_MOVE_UP, KEY_W)
	_register_key_action(ACTION_MOVE_UP, KEY_UP)
	_register_key_action(ACTION_MOVE_DOWN, KEY_S)
	_register_key_action(ACTION_MOVE_DOWN, KEY_DOWN)
	_register_key_action(ACTION_MOVE_LEFT, KEY_A)
	_register_key_action(ACTION_MOVE_LEFT, KEY_LEFT)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_D)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_RIGHT)


func _register_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action_name, event)
