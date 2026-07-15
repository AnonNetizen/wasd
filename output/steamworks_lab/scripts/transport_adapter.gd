class_name SteamLabTransportAdapter
extends Node

signal steam_peer_ready(peer: MultiplayerPeer, lobby_id: String, host: bool)
signal steam_failed(message: String)
signal steam_status(message: String)
signal steam_lobby_join_requested(lobby_id: String, friend_id: String)

const STEAM_APP_ID_SETTING: StringName = &"steam/initialization/app_data/app_id"
const STEAM_RESTART_THROUGH_CLIENT_SETTING: StringName = &"steam/restart_through_client"
const DEVELOPMENT_APP_ID_PATH: String = "res://steam_appid.txt"
const DISABLE_STEAM_ARG: String = "--disable-steam"
const LOBBY_TYPE_PUBLIC: int = 2
const RESULT_OK: int = 1
const CHAT_ROOM_ENTER_RESPONSE_SUCCESS: int = 1
const CHAT_MEMBER_STATE_CHANGE_ENTERED: int = 0x0001
const CHAT_MEMBER_STATE_CHANGE_LEFT: int = 0x0002
const CHAT_MEMBER_STATE_CHANGE_DISCONNECTED: int = 0x0004
const CHAT_MEMBER_STATE_CHANGE_KICKED: int = 0x0008
const CHAT_MEMBER_STATE_CHANGE_BANNED: int = 0x0010
const LAB_MARKER_KEY: String = "wasd_lab"
const LAB_MARKER_VALUE: String = "steamworks_slime_v1"
const LAB_VERSION_KEY: String = "lab_version"
const LAB_VERSION_VALUE: String = "2"

var _steam: Object
var _active_steam_peer: MultiplayerPeer
var _known_steam_ids: Dictionary = {}
var _pending_host: bool = false
var _pending_join: bool = false
var _active_lobby_id: String = ""
var _is_steam_host: bool = false
var _steam_disabled: bool = false
var _steam_init_attempted: bool = false
var _steam_init_ok: bool = false
var _steam_init_detail: String = "not attempted"
var _runtime_app_id: int = 0
var _restart_requested: bool = false


static func configured_app_id() -> int:
	return int(ProjectSettings.get_setting(STEAM_APP_ID_SETTING, 0))


static func development_app_id() -> int:
	var file := FileAccess.open(DEVELOPMENT_APP_ID_PATH, FileAccess.READ)
	if file == null:
		return 0
	var value := file.get_as_text().strip_edges()
	if not value.is_valid_int():
		return 0
	return int(value)


static func app_id_configuration_is_valid() -> bool:
	var app_id := configured_app_id()
	return app_id > 0 and development_app_id() == app_id


static func steam_init_result_succeeded(result: Variant) -> bool:
	match typeof(result):
		TYPE_BOOL:
			return bool(result)
		TYPE_DICTIONARY:
			var response := result as Dictionary
			return int(response.get("status", -1)) == 0
		TYPE_INT:
			return int(result) == 1
		_:
			return false


static func steam_disabled_from_args(args: PackedStringArray) -> bool:
	for arg in args:
		if String(arg).strip_edges() == DISABLE_STEAM_ARG:
			return true
	return false


static func should_restart_through_client(
		is_export_template: bool,
		restart_enabled: bool,
		restart_method_available: bool
) -> bool:
	return is_export_template and restart_enabled and restart_method_available


static func connect_lobby_from_args(args: PackedStringArray) -> String:
	for index in range(args.size()):
		var arg := String(args[index]).strip_edges()
		if arg == "+connect_lobby" and index + 1 < args.size():
			var lobby_id := String(args[index + 1]).strip_edges()
			if lobby_id.is_valid_int():
				return lobby_id
		if arg.begins_with("+connect_lobby="):
			var lobby_id := arg.trim_prefix("+connect_lobby=").strip_edges()
			if lobby_id.is_valid_int():
				return lobby_id
	return ""


static func lobby_metadata_is_compatible(marker: String, version: String) -> bool:
	return marker == LAB_MARKER_VALUE and version == LAB_VERSION_VALUE


func _ready() -> void:
	var command_line_args := OS.get_cmdline_args()
	command_line_args.append_array(OS.get_cmdline_user_args())
	_steam_disabled = steam_disabled_from_args(command_line_args)
	_refresh_steam()
	if _restart_requested:
		return
	_connect_steam_signals()
	call_deferred("_emit_launch_lobby_request")


func _process(_delta: float) -> void:
	if _steam_init_ok and _steam != null and _steam.has_method("run_callbacks"):
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
	if _steam_disabled or _steam == null or not _steam_init_ok:
		return false
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return false
	var app_id := configured_app_id()
	if _runtime_app_id > 0 and _runtime_app_id != app_id:
		return false
	if _steam.has_method("loggedOn") and not bool(_steam.call("loggedOn")):
		return false
	return true


func steam_diagnostics() -> String:
	_refresh_steam()
	if _steam_disabled:
		return "Steam integration is disabled for this process. Local ENet is still available."
	if _steam == null:
		return "GodotSteam singleton is not installed. Local ENet is still available."
	var app_id := configured_app_id()
	if app_id <= 0:
		return "Steam App ID is missing or invalid in ProjectSettings."
	if not _steam_init_ok:
		return "Steam initialization failed for app id %d: %s" % [app_id, _steam_init_detail]
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return "Steam singleton exists, but SteamMultiplayerPeer is missing."
	if _runtime_app_id > 0 and _runtime_app_id != app_id:
		return "Steam App ID mismatch: expected %d, runtime reports %d." % [app_id, _runtime_app_id]
	if _steam.has_method("loggedOn") and not bool(_steam.call("loggedOn")):
		return "Steam is available, but the user is not logged on."
	return "Steam transport is available for app id %d." % app_id


func steam_game_language() -> String:
	_refresh_steam()
	if _steam == null or not _steam_init_ok:
		return ""
	for method_name in [
		"getCurrentGameLanguage",
		"get_current_game_language",
		"getSteamUILanguage",
		"get_steam_ui_language",
	]:
		if not _steam.has_method(method_name):
			continue
		var value := String(_steam.call(method_name)).strip_edges()
		if value != "":
			return value
	return ""


func open_steam_invite_overlay() -> bool:
	_refresh_steam()
	if not steam_available():
		steam_failed.emit(steam_diagnostics())
		return false
	if not _active_lobby_id.is_valid_int():
		steam_failed.emit("Steam invite requires an active lobby.")
		return false
	for method_name in [
		"activateGameOverlayInviteDialog",
		"activate_game_overlay_invite_dialog",
	]:
		if not _steam.has_method(method_name):
			continue
		_steam.call(method_name, int(_active_lobby_id))
		steam_status.emit("Steam invite overlay opened for lobby %s." % _active_lobby_id)
		return true
	steam_failed.emit("Steam overlay invite dialog method is missing.")
	return false


func host_steam_lobby(max_players: int) -> bool:
	if not steam_available():
		steam_failed.emit(steam_diagnostics())
		return false
	_connect_steam_signals()
	_pending_host = true
	_pending_join = false
	steam_status.emit("Creating Steam lobby for app id %d..." % configured_app_id())
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
	_active_steam_peer = null
	_known_steam_ids.clear()
	_active_lobby_id = ""
	_is_steam_host = false
	_pending_host = false
	_pending_join = false


func _refresh_steam() -> void:
	if _steam_disabled:
		_steam = null
		return
	if Engine.has_singleton("Steam"):
		var steam_singleton := Engine.get_singleton("Steam")
		if steam_singleton != _steam:
			_steam = steam_singleton
			_steam_init_attempted = false
			_steam_init_ok = false
			_steam_init_detail = "not attempted"
			_runtime_app_id = 0
		_initialize_steam_if_needed()
	else:
		_steam = null


func _connect_steam_signals() -> void:
	if _steam == null:
		return
	_connect_signal_if_present("lobby_created", Callable(self, "_on_lobby_created"))
	_connect_signal_if_present("lobby_joined", Callable(self, "_on_lobby_joined"))
	_connect_signal_if_present("lobby_chat_update", Callable(self, "_on_lobby_chat_update"))
	for signal_name in [
		"join_requested",
		"game_lobby_join_requested",
		"lobby_join_requested",
	]:
		_connect_signal_if_present(signal_name, Callable(self, "_on_lobby_join_requested"))


func _connect_signal_if_present(signal_name: StringName, callable: Callable) -> void:
	if _steam == null or not _steam.has_signal(signal_name):
		return
	if not _steam.is_connected(signal_name, callable):
		_steam.connect(signal_name, callable)


func _initialize_steam_if_needed() -> void:
	if _steam == null or _steam_init_attempted:
		return
	_steam_init_attempted = true
	var app_id := configured_app_id()
	if app_id <= 0:
		_steam_init_detail = "invalid configured App ID"
		steam_failed.emit("Steam App ID is missing or invalid in ProjectSettings.")
		return

	if should_restart_through_client(
		OS.has_feature("template"),
		bool(ProjectSettings.get_setting(STEAM_RESTART_THROUGH_CLIENT_SETTING, true)),
		_steam.has_method("restartAppIfNecessary")
	):
		var should_restart := bool(_steam.call("restartAppIfNecessary", app_id))
		if should_restart:
			_restart_requested = true
			_steam_init_detail = "relaunch requested through Steam client"
			steam_status.emit("Relaunching through Steam for app id %d." % app_id)
			get_tree().quit()
			return

	if not _steam.has_method("steamInitEx") and not _steam.has_method("steamInit"):
		_steam_init_detail = "steamInitEx/steamInit methods are missing"
		steam_failed.emit("GodotSteam is installed, but steamInitEx and steamInit are missing.")
		return

	var result: Variant = _call_steam_init(app_id)
	_steam_init_ok = steam_init_result_succeeded(result)
	_steam_init_detail = str(result)
	_runtime_app_id = _read_runtime_app_id()
	if not _steam_init_ok:
		steam_failed.emit("Steam initialization failed for app id %d: %s" % [app_id, _steam_init_detail])
		return
	if _runtime_app_id > 0 and _runtime_app_id != app_id:
		_steam_init_ok = false
		_steam_init_detail = "runtime app id %d does not match" % _runtime_app_id
		steam_failed.emit("Steam App ID mismatch: expected %d, runtime reports %d." % [app_id, _runtime_app_id])
		return
	steam_status.emit("Steam initialized for app id %d: %s" % [app_id, _steam_init_detail])


func _call_steam_init(app_id: int) -> Variant:
	if _steam == null:
		return null
	if _steam.has_method("steamInitEx"):
		return _steam.call("steamInitEx", app_id, false)
	if _steam.has_method("steamInit"):
		return _steam.call("steamInit", app_id, false)
	return null


func _read_runtime_app_id() -> int:
	if _steam == null:
		return 0
	for method_name in ["getAppID", "get_app_id"]:
		if _steam.has_method(method_name):
			return int(_steam.call(method_name))
	return 0


func _emit_launch_lobby_request() -> void:
	if _steam_disabled or _restart_requested:
		return
	var lobby_id := connect_lobby_from_args(OS.get_cmdline_args())
	if lobby_id == "":
		return
	steam_status.emit("Steam launch requested lobby %s." % lobby_id)
	steam_lobby_join_requested.emit(lobby_id, "")


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
		var failure_message := String(peer_result.get("message", "Steam host peer creation failed."))
		leave_steam_lobby()
		steam_failed.emit(failure_message)
		return

	_pending_host = false
	_active_steam_peer = peer_result["peer"] as MultiplayerPeer
	_is_steam_host = true
	_track_current_lobby_members(lobby_id)
	steam_peer_ready.emit(peer_result["peer"], _active_lobby_id, true)


func _on_lobby_join_requested(lobby_id_data: Variant, friend_id_data: Variant = 0) -> void:
	var lobby_id := String(lobby_id_data).strip_edges()
	if not lobby_id.is_valid_int() or int(lobby_id) <= 0:
		steam_failed.emit("Steam invite did not include a valid lobby id.")
		return
	var friend_id := String(friend_id_data).strip_edges()
	steam_status.emit("Steam invite requested lobby %s." % lobby_id)
	steam_lobby_join_requested.emit(lobby_id, friend_id if friend_id.is_valid_int() else "")


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if not _pending_join:
		return
	if response != CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		_pending_join = false
		_active_lobby_id = ""
		_known_steam_ids.clear()
		steam_failed.emit("Steam lobby join failed with response %d." % response)
		return

	_active_lobby_id = str(lobby_id)
	var marker := ""
	var version := ""
	if _steam != null and _steam.has_method("getLobbyData"):
		marker = String(_steam.call("getLobbyData", lobby_id, LAB_MARKER_KEY))
		version = String(_steam.call("getLobbyData", lobby_id, LAB_VERSION_KEY))
	if not lobby_metadata_is_compatible(marker, version):
		var failure_message := "Steam lobby protocol mismatch: expected %s/%s, got %s/%s." % [
			LAB_MARKER_VALUE,
			LAB_VERSION_VALUE,
			marker if marker != "" else "<missing>",
			version if version != "" else "<missing>",
		]
		leave_steam_lobby()
		steam_failed.emit(failure_message)
		return
	steam_status.emit("Joined Steam slime lobby %s." % _active_lobby_id)

	var peer_result := _create_steam_client_peer(lobby_id)
	if not bool(peer_result.get("ok", false)):
		var failure_message := String(peer_result.get("message", "Steam client peer creation failed."))
		leave_steam_lobby()
		steam_failed.emit(failure_message)
		return

	_pending_join = false
	_active_steam_peer = peer_result["peer"] as MultiplayerPeer
	_is_steam_host = false
	var member_count := _track_current_lobby_members(lobby_id)
	if member_count <= 1:
		steam_status.emit("Steam lobby reports one account after join; same-account double launch cannot create a second P2P peer.")
	steam_peer_ready.emit(peer_result["peer"], _active_lobby_id, false)


func _on_lobby_chat_update(lobby_id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if _active_lobby_id != str(lobby_id):
		return
	if _has_member_state(chat_state, CHAT_MEMBER_STATE_CHANGE_ENTERED):
		steam_status.emit("Steam lobby member entered: %s." % str(changed_id))
		if _is_steam_host:
			_add_lobby_member_peer(changed_id)
		else:
			_remember_steam_id(changed_id)
		return

	if _has_member_state(chat_state, CHAT_MEMBER_STATE_CHANGE_LEFT):
		_forget_steam_id(changed_id)
		steam_status.emit("Steam lobby member left: %s." % str(changed_id))
		return
	if _has_member_state(chat_state, CHAT_MEMBER_STATE_CHANGE_DISCONNECTED):
		_forget_steam_id(changed_id)
		steam_status.emit("Steam lobby member disconnected: %s." % str(changed_id))
		return
	if _has_member_state(chat_state, CHAT_MEMBER_STATE_CHANGE_KICKED):
		_forget_steam_id(changed_id)
		steam_status.emit("Steam lobby member kicked: %s." % str(changed_id))
		return
	if _has_member_state(chat_state, CHAT_MEMBER_STATE_CHANGE_BANNED):
		_forget_steam_id(changed_id)
		steam_status.emit("Steam lobby member banned: %s." % str(changed_id))


func _set_lobby_metadata(lobby_id: int) -> void:
	if _steam == null:
		return
	if _steam.has_method("setLobbyData"):
		_steam.call("setLobbyData", lobby_id, LAB_MARKER_KEY, LAB_MARKER_VALUE)
		_steam.call("setLobbyData", lobby_id, LAB_VERSION_KEY, LAB_VERSION_VALUE)
		_steam.call("setLobbyData", lobby_id, "name", "Steamworks Slime Lab")
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


func _track_current_lobby_members(lobby_id: int) -> int:
	_known_steam_ids.clear()
	if _steam == null:
		return 0
	if not _steam.has_method("getNumLobbyMembers") or not _steam.has_method("getLobbyMemberByIndex"):
		return 0

	var member_count := int(_steam.call("getNumLobbyMembers", lobby_id))
	for index in range(member_count):
		var member_id := int(_steam.call("getLobbyMemberByIndex", lobby_id, index))
		if member_id > 0:
			_remember_steam_id(member_id)
	steam_status.emit("Steam lobby currently has %d member(s)." % member_count)
	return member_count


func _add_lobby_member_peer(steam_id: int) -> void:
	if _active_steam_peer == null:
		steam_status.emit("Steam peer is not ready; cannot add lobby member %s." % str(steam_id))
		return
	if steam_id <= 0:
		return

	var local_steam_id := _local_steam_id()
	if local_steam_id != 0 and steam_id == local_steam_id:
		_remember_steam_id(steam_id)
		steam_status.emit("Steam reported this same account in the lobby; use a second Steam account/device for true Steam P2P.")
		return

	var key := str(steam_id)
	if _known_steam_ids.has(key):
		return
	if not _active_steam_peer.has_method("add_peer"):
		steam_failed.emit("SteamMultiplayerPeer has no add_peer method for lobby member %s." % key)
		return

	var error := int(_active_steam_peer.call("add_peer", steam_id, 0))
	if error != OK:
		steam_failed.emit("Steam add_peer failed for lobby member %s: %s" % [key, error])
		return
	_remember_steam_id(steam_id)
	steam_status.emit("Steam P2P peer added for lobby member %s." % key)


func _local_steam_id() -> int:
	if _steam != null and _steam.has_method("getSteamID"):
		return int(_steam.call("getSteamID"))
	return 0


func _remember_steam_id(steam_id: int) -> void:
	if steam_id > 0:
		_known_steam_ids[str(steam_id)] = true


func _forget_steam_id(steam_id: int) -> void:
	_known_steam_ids.erase(str(steam_id))


func _has_member_state(chat_state: int, state: int) -> bool:
	return (chat_state & state) != 0
