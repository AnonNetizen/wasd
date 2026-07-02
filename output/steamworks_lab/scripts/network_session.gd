class_name SteamLabNetworkSession
extends Node

signal status_changed(message: String)
signal session_started(host: bool, transport: String, lobby_id: String)
signal session_ended()
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal input_received(peer_id: int, input_vector: Vector2)
signal snapshot_received(snapshot: Dictionary)
signal expression_received(peer_id: int, expression_id: String)
signal shot_requested(peer_id: int, direction: Vector2)
signal shot_received(peer_id: int, origin: Vector2, direction: Vector2, speed: float)
signal phase_received(phase: int, payload: Dictionary)
signal buff_options_received(options: PackedInt32Array)
signal buff_choice_received(peer_id: int, option_index: int)
signal enemy_volley_received(origin: Vector2, directions: PackedVector2Array, speed: float)
signal battle_reset_received()
signal battle_launch_received()
signal active_item_requested(peer_id: int)
signal active_item_used_received(peer_id: int, item_id: int, origin: Vector2)

const TRANSPORT_SCRIPT := preload("res://scripts/transport_adapter.gd")
const DEFAULT_PORT: int = 24567
const MAX_PLAYERS: int = 8

var _transport: Node
var _is_host: bool = false
var _active_transport: String = "offline"
var _lobby_id: String = ""


func _ready() -> void:
	_ensure_transport()
	_connect_multiplayer_signals()


func _ensure_transport() -> void:
	if _transport != null:
		return
	_transport = TRANSPORT_SCRIPT.new() as Node
	_transport.name = "TransportAdapter"
	add_child(_transport)
	_transport.connect("steam_peer_ready", Callable(self, "_on_steam_peer_ready"))
	_transport.connect("steam_failed", Callable(self, "_emit_status"))
	_transport.connect("steam_status", Callable(self, "_emit_status"))


func host_local(port: int = DEFAULT_PORT) -> void:
	_ensure_transport()
	leave_session()
	var result: Dictionary = _transport.call("create_local_server", port, MAX_PLAYERS)
	if not bool(result.get("ok", false)):
		_emit_status(String(result.get("message", "Local host failed.")))
		return
	_apply_peer(result["peer"], true, "local", "")
	_emit_status(String(result.get("message", "Local host ready.")))


func join_local(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> void:
	_ensure_transport()
	leave_session()
	var result: Dictionary = _transport.call("create_local_client", address, port)
	if not bool(result.get("ok", false)):
		_emit_status(String(result.get("message", "Local join failed.")))
		return
	_apply_peer(result["peer"], false, "local", "")
	_emit_status(String(result.get("message", "Joining local host...")))


func host_steam() -> void:
	_ensure_transport()
	leave_session()
	if not bool(_transport.call("host_steam_lobby", MAX_PLAYERS)):
		return
	_active_transport = "steam"


func join_steam_lobby(lobby_id: String) -> void:
	_ensure_transport()
	leave_session()
	if not bool(_transport.call("join_steam_lobby", lobby_id)):
		return
	_active_transport = "steam"


func leave_session() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	if _transport != null:
		_transport.call("leave_steam_lobby")
	_is_host = false
	_active_transport = "offline"
	_lobby_id = ""
	session_ended.emit()


func is_host() -> bool:
	return _is_host


func active_transport() -> String:
	return _active_transport


func lobby_id() -> String:
	return _lobby_id


func local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


func steam_status_text() -> String:
	_ensure_transport()
	if _transport == null:
		return "Steam transport adapter is not ready."
	return String(_transport.call("steam_diagnostics"))


func steam_available() -> bool:
	_ensure_transport()
	if _transport == null:
		return false
	return bool(_transport.call("steam_available"))


func steam_game_language() -> String:
	_ensure_transport()
	if _transport == null:
		return ""
	return String(_transport.call("steam_game_language"))


func send_input_to_host(input_vector: Vector2) -> void:
	var limited := input_vector.limit_length(1.0)
	if _is_host:
		input_received.emit(1, limited)
		return
	if not _client_connection_ready():
		return
	_submit_input.rpc_id(1, limited.x, limited.y)


func _client_connection_ready() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func broadcast_snapshot(snapshot: Dictionary) -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	_receive_snapshot.rpc(snapshot)


func send_expression_to_host(expression_id: String) -> void:
	var clean_expression_id := expression_id.strip_edges()
	if clean_expression_id == "":
		return
	if _is_host:
		expression_received.emit(1, clean_expression_id)
		broadcast_expression(1, clean_expression_id)
		return
	if not _client_connection_ready():
		return
	_submit_expression.rpc_id(1, clean_expression_id)


func broadcast_expression(peer_id: int, expression_id: String) -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	_receive_expression.rpc(peer_id, expression_id)


func send_shot_to_host(direction: Vector2) -> void:
	var limited_direction := direction.normalized()
	if limited_direction.length_squared() <= 0.0001:
		return
	if _is_host:
		shot_requested.emit(1, limited_direction)
		return
	if not _client_connection_ready():
		return
	_submit_shot.rpc_id(1, limited_direction.x, limited_direction.y)


func send_active_item_to_host() -> void:
	if _is_host:
		active_item_requested.emit(1)
		return
	if not _client_connection_ready():
		return
	_submit_active_item_use.rpc_id(1)


func broadcast_shot(peer_id: int, origin: Vector2, direction: Vector2, speed: float) -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	var limited_direction := direction.normalized()
	if limited_direction.length_squared() <= 0.0001:
		return
	_receive_shot.rpc(peer_id, origin.x, origin.y, limited_direction.x, limited_direction.y, speed)


func broadcast_phase(phase: int, payload: Dictionary) -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	_receive_phase.rpc(phase, payload)


func send_buff_options(peer_id: int, options: PackedInt32Array) -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	if peer_id == 1:
		buff_options_received.emit(options)
		return
	_receive_buff_options.rpc_id(peer_id, options)


func send_buff_choice_to_host(option_index: int) -> void:
	if _is_host:
		buff_choice_received.emit(1, option_index)
		return
	if not _client_connection_ready():
		return
	_submit_buff_choice.rpc_id(1, option_index)


func broadcast_enemy_volley(origin: Vector2, directions: PackedVector2Array, speed: float) -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	if directions.is_empty():
		return
	_receive_enemy_volley.rpc(origin.x, origin.y, directions, speed)


func broadcast_active_item_used(peer_id: int, item_id: int, origin: Vector2) -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	_receive_active_item_used.rpc(peer_id, item_id, origin.x, origin.y)


func broadcast_battle_reset() -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	_receive_battle_reset.rpc()


func broadcast_battle_launch() -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	_receive_battle_launch.rpc()


func send_battle_launch(peer_id: int) -> void:
	if not _is_host or multiplayer.multiplayer_peer == null:
		return
	_receive_battle_launch.rpc_id(peer_id)


@rpc("any_peer", "unreliable")
func _submit_input(input_x: float, input_y: float) -> void:
	if not _is_host:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	input_received.emit(sender_id, Vector2(input_x, input_y).limit_length(1.0))


@rpc("any_peer", "reliable")
func _submit_expression(expression_id: String) -> void:
	if not _is_host:
		return
	var clean_expression_id := expression_id.strip_edges()
	if clean_expression_id == "":
		return
	var sender_id := multiplayer.get_remote_sender_id()
	expression_received.emit(sender_id, clean_expression_id)
	broadcast_expression(sender_id, clean_expression_id)


@rpc("any_peer", "reliable")
func _submit_shot(direction_x: float, direction_y: float) -> void:
	if not _is_host:
		return
	var direction := Vector2(direction_x, direction_y).normalized()
	if direction.length_squared() <= 0.0001:
		return
	shot_requested.emit(multiplayer.get_remote_sender_id(), direction)


@rpc("any_peer", "reliable")
func _submit_active_item_use() -> void:
	if not _is_host:
		return
	active_item_requested.emit(multiplayer.get_remote_sender_id())


@rpc("authority", "unreliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	snapshot_received.emit(snapshot)


@rpc("authority", "reliable")
func _receive_expression(peer_id: int, expression_id: String) -> void:
	expression_received.emit(peer_id, expression_id)


@rpc("authority", "reliable")
func _receive_shot(peer_id: int, origin_x: float, origin_y: float, direction_x: float, direction_y: float, speed: float) -> void:
	shot_received.emit(peer_id, Vector2(origin_x, origin_y), Vector2(direction_x, direction_y).normalized(), speed)


@rpc("authority", "reliable")
func _receive_phase(phase: int, payload: Dictionary) -> void:
	phase_received.emit(phase, payload)


@rpc("authority", "reliable")
func _receive_buff_options(options: PackedInt32Array) -> void:
	buff_options_received.emit(options)


@rpc("any_peer", "reliable")
func _submit_buff_choice(option_index: int) -> void:
	if not _is_host:
		return
	if option_index < 0 or option_index > 2:
		return
	buff_choice_received.emit(multiplayer.get_remote_sender_id(), option_index)


@rpc("authority", "reliable")
func _receive_enemy_volley(origin_x: float, origin_y: float, directions: PackedVector2Array, speed: float) -> void:
	enemy_volley_received.emit(Vector2(origin_x, origin_y), directions, speed)


@rpc("authority", "reliable")
func _receive_active_item_used(peer_id: int, item_id: int, origin_x: float, origin_y: float) -> void:
	active_item_used_received.emit(peer_id, item_id, Vector2(origin_x, origin_y))


@rpc("authority", "reliable")
func _receive_battle_reset() -> void:
	battle_reset_received.emit()


@rpc("authority", "reliable")
func _receive_battle_launch() -> void:
	battle_launch_received.emit()


func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _apply_peer(peer: MultiplayerPeer, host: bool, transport: String, lobby: String) -> void:
	multiplayer.multiplayer_peer = peer
	_is_host = host
	_active_transport = transport
	_lobby_id = lobby
	session_started.emit(host, transport, lobby)
	if host:
		peer_joined.emit(1)


func _on_steam_peer_ready(peer: MultiplayerPeer, lobby: String, host: bool) -> void:
	_apply_peer(peer, host, "steam", lobby)
	if host:
		_emit_status("Hosting Steam lobby %s." % lobby)
	else:
		_emit_status("Connected to Steam lobby %s." % lobby)


func _on_peer_connected(peer_id: int) -> void:
	_emit_status("Peer connected: %d" % peer_id)
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_emit_status("Peer disconnected: %d" % peer_id)
	peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	_emit_status("Connected to host as peer %d." % multiplayer.get_unique_id())
	session_started.emit(false, _active_transport, _lobby_id)


func _on_connection_failed() -> void:
	_emit_status("Connection failed.")
	leave_session()


func _on_server_disconnected() -> void:
	_emit_status("Host disconnected.")
	leave_session()


func _emit_status(message: String) -> void:
	status_changed.emit(message)
