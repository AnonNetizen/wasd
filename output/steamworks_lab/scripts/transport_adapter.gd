class_name SteamLabTransportAdapter
extends Node

signal steam_peer_ready(peer: MultiplayerPeer, lobby_id: String, host: bool)
signal steam_failed(message: String)
signal steam_status(message: String)

const LOBBY_TYPE_PUBLIC: int = 2
const RESULT_OK: int = 1
const CHAT_ROOM_ENTER_RESPONSE_SUCCESS: int = 1
const LAB_MARKER_KEY: String = "wasd_lab"
const LAB_MARKER_VALUE: String = "steamworks_slime_v1"
const LAB_VERSION_KEY: String = "lab_version"
const LAB_VERSION_VALUE: String = "1"

var _steam: Object
var _pending_host: bool = false
var _pending_join: bool = false
var _active_lobby_id: String = ""
var _steam_initialized: bool = false


func _ready() -> void:
	_refresh_steam()


func _process(_delta: float) -> void:
	if _steam != null and _steam.has_method("run_callbacks"):
		_steam.call("run_callbacks")


func create_local_server(port: int, max_players: int) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_players)
	if error != OK:
		return {"ok": false, "message": "Failed to host local ENet server on port %d: %s" % [port, error]}
	return {"ok": true, "peer": peer, "message": "Hosting local ENet server on 127.0.0.1:%d" % port}


func create_local_client(address: String, port: int) -> Dictionary:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return {"ok": false, "message": "Failed to join %s:%d: %s" % [address, port, error]}
	return {"ok": true, "peer": peer, "message": "Joining local ENet server at %s:%d" % [address, port]}


func steam_available() -> bool:
	_refresh_steam()
	if _steam == null or not ClassDB.class_exists("SteamMultiplayerPeer"):
		return false
	if _steam.has_method("loggedOn") and not bool(_steam.call("loggedOn")):
		return false
	return true


func steam_diagnostics() -> String:
	_refresh_steam()
	if _steam == null:
		return "GodotSteam singleton is not installed. Local ENet is still available."
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return "Steam singleton exists, but SteamMultiplayerPeer is missing."
	if _steam.has_method("loggedOn") and not bool(_steam.call("loggedOn")):
		return "Steam is available, but the user is not logged on."
	return "Steam transport is available."


func host_steam_lobby(max_players: int) -> bool:
	if not steam_available():
		steam_failed.emit(steam_diagnostics())
		return false
	_connect_steam_signals()
	_pending_host = true
	_pending_join = false
	steam_status.emit("Creating Steam lobby with Spacewar app id 480...")
	_steam.call("createLobby", LOBBY_TYPE_PUBLIC, max_players)
	return true


func join_steam_lobby(lobby_id_text: String) -> bool:
	if not steam_available():
		steam_failed.emit(steam_diagnostics())
		return false
	if not lobby_id_text.is_valid_int():
		steam_failed.emit("Steam lobby id must be a numeric id.")
		return false
	_connect_steam_signals()
	_pending_join = true
	_pending_host = false
	_active_lobby_id = lobby_id_text
	steam_status.emit("Joining Steam lobby %s..." % lobby_id_text)
	_steam.call("joinLobby", int(lobby_id_text))
	return true


func leave_steam_lobby() -> void:
	if _steam != null and _active_lobby_id.is_valid_int() and _steam.has_method("leaveLobby"):
		_steam.call("leaveLobby", int(_active_lobby_id))
	_active_lobby_id = ""
	_pending_host = false
	_pending_join = false


func _refresh_steam() -> void:
	if Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
		_initialize_steam_if_needed()
	else:
		_steam = null


func _connect_steam_signals() -> void:
	if _steam == null:
		return
	_connect_signal_if_present("lobby_created", Callable(self, "_on_lobby_created"))
	_connect_signal_if_present("lobby_joined", Callable(self, "_on_lobby_joined"))


func _connect_signal_if_present(signal_name: StringName, callable: Callable) -> void:
	if _steam == null or not _steam.has_signal(signal_name):
		return
	if not _steam.is_connected(signal_name, callable):
		_steam.connect(signal_name, callable)


func _initialize_steam_if_needed() -> void:
	if _steam == null or _steam_initialized:
		return
	_steam_initialized = true
	if _steam.has_method("steamInit"):
		var result: Variant = _steam.call("steamInit")
		steam_status.emit("Steam init result: %s" % str(result))


func _on_lobby_created(connect: int, lobby_id: int) -> void:
	if not _pending_host:
		return
	if connect != RESULT_OK or lobby_id == 0:
		_pending_host = false
		steam_failed.emit("Steam lobby creation failed with result %d." % connect)
		return

	_active_lobby_id = str(lobby_id)
	_set_lobby_metadata(lobby_id)
	steam_status.emit("Steam lobby created: %s" % _active_lobby_id)

	var peer_result := _create_steam_host_peer(lobby_id)
	if not bool(peer_result.get("ok", false)):
		_pending_host = false
		steam_failed.emit(String(peer_result.get("message", "Steam host peer creation failed.")))
		return

	_pending_host = false
	steam_peer_ready.emit(peer_result["peer"], _active_lobby_id, true)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if not _pending_join:
		return
	if response != CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_pending_join = false
		steam_failed.emit("Steam lobby join failed with response %d." % response)
		return

	_active_lobby_id = str(lobby_id)
	var marker := ""
	if _steam != null and _steam.has_method("getLobbyData"):
		marker = String(_steam.call("getLobbyData", lobby_id, LAB_MARKER_KEY))
	if marker != LAB_MARKER_VALUE:
		steam_status.emit("Joined lobby %s without lab marker; continuing because this is a Spacewar test." % _active_lobby_id)
	else:
		steam_status.emit("Joined Steam slime lobby %s." % _active_lobby_id)

	var peer_result := _create_steam_client_peer(lobby_id)
	if not bool(peer_result.get("ok", false)):
		_pending_join = false
		steam_failed.emit(String(peer_result.get("message", "Steam client peer creation failed.")))
		return

	_pending_join = false
	steam_peer_ready.emit(peer_result["peer"], _active_lobby_id, false)


func _set_lobby_metadata(lobby_id: int) -> void:
	if _steam == null:
		return
	if _steam.has_method("setLobbyData"):
		_steam.call("setLobbyData", lobby_id, LAB_MARKER_KEY, LAB_MARKER_VALUE)
		_steam.call("setLobbyData", lobby_id, LAB_VERSION_KEY, LAB_VERSION_VALUE)
		_steam.call("setLobbyData", lobby_id, "name", "WASD Slime Lab")
	if _steam.has_method("setLobbyJoinable"):
		_steam.call("setLobbyJoinable", lobby_id, true)


func _create_steam_host_peer(lobby_id: int) -> Dictionary:
	var peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null:
		return {"ok": false, "message": "Could not instantiate SteamMultiplayerPeer."}
	if peer.has_method("host_with_lobby"):
		var error := int(peer.call("host_with_lobby", lobby_id))
		if error != OK:
			return {"ok": false, "message": "host_with_lobby failed: %s" % error}
	elif peer.has_method("create_host"):
		var error := int(peer.call("create_host", 0))
		if error != OK:
			return {"ok": false, "message": "create_host failed: %s" % error}
	else:
		return {"ok": false, "message": "SteamMultiplayerPeer has no host_with_lobby/create_host method."}
	return {"ok": true, "peer": peer}


func _create_steam_client_peer(lobby_id: int) -> Dictionary:
	var peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null:
		return {"ok": false, "message": "Could not instantiate SteamMultiplayerPeer."}
	if peer.has_method("connect_to_lobby"):
		var error := int(peer.call("connect_to_lobby", lobby_id))
		if error != OK:
			return {"ok": false, "message": "connect_to_lobby failed: %s" % error}
	elif peer.has_method("create_client") and _steam != null and _steam.has_method("getLobbyOwner"):
		var owner_id := int(_steam.call("getLobbyOwner", lobby_id))
		var error := int(peer.call("create_client", owner_id, 0))
		if error != OK:
			return {"ok": false, "message": "create_client failed: %s" % error}
	else:
		return {"ok": false, "message": "SteamMultiplayerPeer has no connect_to_lobby/create_client method."}
	return {"ok": true, "peer": peer}
