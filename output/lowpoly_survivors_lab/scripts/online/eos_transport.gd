class_name LowpolyEosTransport
extends LowpolyTransport
## EOSG 2.3.0 adapter. No gameplay script is allowed to call EOSG directly.

const BUCKET_ID := "LOWPOLY_SURVIVORS_V1"
const MAX_RPC_CHUNK_BYTES: int = 700
const MAX_RPC_CHUNKS: int = 1024
const MAX_UNCOMPRESSED_MESSAGE_BYTES: int = 4 * 1024 * 1024
const MAX_ASSEMBLIES_PER_SENDER: int = 8
const CHUNK_EXPIRY_SECONDS: float = 8.0

var _local_user_id: String = ""
var _display_name: String = ""
var _platform_name: String = "unknown"
var _room_code: String = ""
var _lobby: HLobby
var _peer: EOSGMultiplayerPeer
var _socket_name: String = ""
var _host_user_id: String = ""
var _next_message_id: int = 1
var _assemblies: Dictionary = {}
var _platform_service: Node
var _auth_service: Node
var _lobbies_service: Node
var _p2p_service: Node


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	for key: Variant in _assemblies.keys():
		var assembly: Dictionary = _assemblies[key]
		if now - float(assembly.get("updated_at", now)) > CHUNK_EXPIRY_SECONDS:
			_assemblies.erase(key)


func initialize_transport(config: Dictionary, display_name: String) -> void:
	_display_name = display_name.strip_edges().left(32)
	_platform_name = _detect_platform()
	if _display_name.is_empty():
		transport_error.emit("昵称不能为空。")
		return
	if not _validate_config(config):
		transport_error.emit("EOS 本地配置不完整，仍可使用单人游戏。")
		return
	_platform_service = get_node_or_null("/root/HPlatform")
	_auth_service = get_node_or_null("/root/HAuth")
	_lobbies_service = get_node_or_null("/root/HLobbies")
	_p2p_service = get_node_or_null("/root/HP2P")
	if _platform_service == null or _auth_service == null or _lobbies_service == null or _p2p_service == null:
		transport_error.emit("EOSG autoload 未安装完整；单人模式仍可用。")
		return

	var credentials := HCredentials.new()
	credentials.product_name = String(config.get("product_name", "Lowpoly Survivors Lab"))
	credentials.product_version = String(config.get("product_version", "0.2.0"))
	credentials.product_id = String(config.get("product_id", ""))
	credentials.sandbox_id = String(config.get("sandbox_id", ""))
	credentials.deployment_id = String(config.get("deployment_id", ""))
	credentials.client_id = String(config.get("client_id", ""))
	credentials.client_secret = String(config.get("client_secret", ""))
	credentials.encryption_key = String(config.get("encryption_key", ""))
	_platform_service.set("task_network_timeout_seconds", 12.0)
	if not await _platform_service.call("setup_eos_async", credentials):
		transport_error.emit("EOS SDK 初始化失败，仍可使用单人游戏。")
		return
	transport_ready.emit()

	var device_options := EOS.Connect.CreateDeviceIdOptions.new()
	device_options.device_model = "%s %s" % [OS.get_name(), OS.get_model_name()]
	EOS.Connect.ConnectInterface.create_device_id(device_options)
	var create_result: Dictionary = await IEOS.connect_interface_create_device_id_callback
	var create_code := int(create_result.get("result_code", EOS.Result.UnexpectedError))
	if not EOS.is_success(create_result) and create_code != EOS.Result.DuplicateNotAllowed and create_code != EOS.Result.AlreadyConfigured:
		transport_error.emit("无法创建 EOS Device ID：%s" % EOS.result_str(create_code))
		return

	var login_options := EOS.Connect.LoginOptions.new()
	login_options.credentials = EOS.Connect.Credentials.new()
	login_options.credentials.type = EOS.ExternalCredentialType.DeviceidAccessToken
	login_options.credentials.token = null
	login_options.user_login_info = EOS.Connect.UserLoginInfo.new()
	login_options.user_login_info.display_name = _display_name
	_auth_service.set("display_name", _display_name)
	if not await _auth_service.call("login_game_services_async", login_options):
		transport_error.emit("EOS Device ID 登录失败。")
		return
	_local_user_id = String(_auth_service.get("product_user_id"))
	if _local_user_id.is_empty():
		transport_error.emit("EOS 登录未返回 Product User ID。")
		return
	_p2p_service.call("set_relay_control", EOS.P2P.RelayControl.AllowRelays)
	authenticated.emit(_local_user_id)


func create_room(room_code: String, max_members: int, metadata: Dictionary) -> void:
	if _local_user_id.is_empty():
		transport_error.emit("EOS 尚未完成登录。")
		return
	_room_code = room_code.strip_edges().to_upper()
	var collisions: Array[HLobby] = await _lobbies_service.call("search_by_attribute_async", [
		{"key": "ROOM_CODE", "value": _room_code},
		{"key": "PROTOCOL", "value": String(metadata.get("protocol", ""))},
	])
	if collisions != null and not collisions.is_empty():
		transport_error.emit("房间码发生碰撞，请重新创建。")
		return
	_lobbies_service.set("presence_enabled", false)
	_lobbies_service.set("local_rtc_options", {})
	var options := EOS.Lobby.CreateLobbyOptions.new()
	options.bucket_id = BUCKET_ID
	options.disable_host_migration = false
	options.max_lobby_members = clampi(max_members, 1, 4)
	options.enable_rtc_room = false
	options.allow_invites = false
	options.enable_join_by_id = false
	options.presence_enabled = false
	options.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	_lobby = await _lobbies_service.call("create_lobby_async", options)
	if _lobby == null:
		transport_error.emit("EOS 创建房间失败。")
		return
	_bind_lobby()
	_lobby.add_attribute("ROOM_CODE", _room_code)
	_lobby.add_attribute("PROTOCOL", String(metadata.get("protocol", "")))
	_lobby.add_attribute("BUILD", String(metadata.get("build", "")))
	_lobby.add_attribute("LOCKED", false)
	_lobby.add_attribute("MATCH_DATA", "")
	_add_local_member_attributes(false)
	if not await _lobby.update_async():
		transport_error.emit("EOS 房间属性写入失败。")
		return
	var snapshot := get_room_snapshot()
	room_created.emit(snapshot)
	room_changed.emit(snapshot)


func join_room(room_code: String) -> void:
	if _local_user_id.is_empty():
		transport_error.emit("EOS 尚未完成登录。")
		return
	_room_code = room_code.strip_edges().to_upper()
	var results: Array[HLobby] = await _lobbies_service.call("search_by_attribute_async", [
		{"key": "ROOM_CODE", "value": _room_code},
		{"key": "PROTOCOL", "value": LowpolyOnlineSession.PROTOCOL_VERSION},
	])
	if results == null or results.is_empty():
		transport_error.emit("未找到房间。")
		return
	var candidate := results.front() as HLobby
	if candidate == null:
		transport_error.emit("房间信息不可用。")
		return
	var locked_attribute: Dictionary = candidate.get_attribute("LOCKED")
	var locked := bool(locked_attribute.get("value", false))
	if locked:
		var match_attribute: Dictionary = candidate.get_attribute("MATCH_DATA")
		var advertised_match := _parse_match_data(String(match_attribute.get("value", "")))
		if not _match_roster_contains_user(advertised_match, _local_user_id):
			transport_error.emit("房间已经开局，禁止中途加入。")
			return
	_lobby = await _lobbies_service.call("join_async", candidate)
	if _lobby == null:
		transport_error.emit("EOS 加入房间失败。")
		return
	_bind_lobby()
	_add_local_member_attributes(false)
	if not await _lobby.update_async():
		transport_error.emit("EOS 玩家属性写入失败。")
		return
	var snapshot := get_room_snapshot()
	room_joined.emit(snapshot)
	room_changed.emit(snapshot)


func update_local_member(member_data: Dictionary) -> bool:
	if _lobby == null or not _lobby.is_valid():
		return false
	if member_data.has("display_name"):
		_display_name = String(member_data["display_name"]).strip_edges().left(32)
	_add_local_member_attributes(bool(member_data.get("ready", false)))
	_lobby.update_async()
	return true


func set_room_locked(locked: bool, match_data: Dictionary = {}) -> bool:
	if _lobby == null or not _lobby.is_owner():
		return false
	# Keep the code-searchable lobby advertised so a roster member can rejoin
	# after owner migration. LOCKED + MATCH_DATA is enforced before joining and
	# again by the authoritative roster; unknown PUIDs remain rejected.
	_lobby.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	_lobby.add_attribute("LOCKED", locked)
	_lobby.add_attribute("MATCH_DATA", JSON.stringify(match_data) if locked else "")
	_lobby.update_async()
	return true


func start_host(socket_name: String) -> bool:
	_close_peer()
	_socket_name = socket_name.left(32)
	_host_user_id = _local_user_id
	_peer = EOSGMultiplayerPeer.new()
	var result := _peer.create_server(_socket_name)
	if result != OK:
		transport_error.emit("EOS P2P 房主监听失败：%s" % error_string(result))
		_peer = null
		return false
	_bind_peer()
	multiplayer.multiplayer_peer = _peer
	return true


func connect_to_host(socket_name: String, host_user_id: String) -> bool:
	_close_peer()
	_socket_name = socket_name.left(32)
	_host_user_id = host_user_id
	_peer = EOSGMultiplayerPeer.new()
	var result := _peer.create_client(_socket_name, _host_user_id)
	if result != OK:
		transport_error.emit("EOS P2P 连接房主失败：%s" % error_string(result))
		_peer = null
		return false
	_bind_peer()
	multiplayer.multiplayer_peer = _peer
	return true


func send_packet(target_user_id: String, channel: Channel, payload: Dictionary) -> bool:
	if _peer == null or multiplayer.multiplayer_peer != _peer:
		return false
	var raw_bytes := var_to_bytes(payload)
	if raw_bytes.size() <= 0 or raw_bytes.size() > MAX_UNCOMPRESSED_MESSAGE_BYTES:
		return false
	var bytes := raw_bytes.compress(FileAccess.COMPRESSION_ZSTD)
	var total := maxi(1, ceili(float(bytes.size()) / float(MAX_RPC_CHUNK_BYTES)))
	if total > MAX_RPC_CHUNKS:
		return false
	var message_id := _next_message_id
	_next_message_id += 1
	var peer_ids: Array[int] = []
	if target_user_id.is_empty():
		for value: Variant in _peer.get_all_peers():
			peer_ids.append(int(value))
	else:
		var target_peer_id := _peer.get_peer_id(target_user_id)
		if target_peer_id <= 0:
			return false
		peer_ids.append(target_peer_id)
	for peer_id: int in peer_ids:
		for index: int in range(total):
			var begin := index * MAX_RPC_CHUNK_BYTES
			var end := mini(begin + MAX_RPC_CHUNK_BYTES, bytes.size())
			var chunk := bytes.slice(begin, end)
			if channel == Channel.RELIABLE:
				rpc_id(peer_id, "_rpc_receive_reliable_chunk", message_id, index, total, raw_bytes.size(), chunk)
			else:
				rpc_id(peer_id, "_rpc_receive_snapshot_chunk", message_id, index, total, raw_bytes.size(), chunk)
	return true


func remove_member(user_id: String) -> bool:
	if _lobby == null or not _lobby.is_owner():
		return false
	var member := _lobby.get_member_by_product_user_id(user_id)
	if member == null:
		return false
	member.kick_member_async()
	return true


func leave_room() -> void:
	_close_peer()
	if _lobby != null and _lobby.is_valid():
		_lobby.leave_async()
	_lobby = null
	_room_code = ""
	room_left.emit()


func shutdown() -> void:
	leave_room()
	_assemblies.clear()


func get_local_user_id() -> String:
	return _local_user_id


func get_room_snapshot() -> Dictionary:
	if _lobby == null or not _lobby.is_valid():
		return {}
	var members: Array[Dictionary] = []
	for member: HLobbyMember in _lobby.members:
		members.append({
			"user_id": member.product_user_id,
			"display_name": _member_attribute(member, "NAME", "幸存者"),
			"platform": _member_attribute(member, "PLATFORM", "unknown"),
			"ready": bool(_member_attribute(member, "READY", false)),
			"connected": true,
		})
	return {
		"room_code": String(_lobby_attribute("ROOM_CODE", _room_code)),
		"host_user_id": _lobby.owner_product_user_id,
		"max_members": _lobby.max_members,
		"locked": bool(_lobby_attribute("LOCKED", false)),
		"metadata": {
			"protocol": String(_lobby_attribute("PROTOCOL", "")),
			"build": String(_lobby_attribute("BUILD", "")),
			"match_data": _parse_match_data(String(_lobby_attribute("MATCH_DATA", ""))),
		},
		"members": members,
	}


func is_available() -> bool:
	return not _local_user_id.is_empty()


@rpc("any_peer", "call_remote", "reliable", 0)
func _rpc_receive_reliable_chunk(message_id: int, index: int, total: int, raw_size: int, bytes: PackedByteArray) -> void:
	_receive_chunk(Channel.RELIABLE, message_id, index, total, raw_size, bytes)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rpc_receive_snapshot_chunk(message_id: int, index: int, total: int, raw_size: int, bytes: PackedByteArray) -> void:
	_receive_chunk(Channel.SNAPSHOT, message_id, index, total, raw_size, bytes)


func _receive_chunk(
	channel: Channel,
	message_id: int,
	index: int,
	total: int,
	raw_size: int,
	bytes: PackedByteArray
) -> void:
	if (
		_peer == null
		or total <= 0
		or total > MAX_RPC_CHUNKS
		or raw_size <= 0
		or raw_size > MAX_UNCOMPRESSED_MESSAGE_BYTES
		or index < 0
		or index >= total
		or bytes.size() > MAX_RPC_CHUNK_BYTES
	):
		return
	var sender_peer_id := multiplayer.get_remote_sender_id()
	var sender_user_id := _peer.get_peer_user_id(sender_peer_id)
	if sender_user_id.is_empty():
		return
	var key := "%s:%d:%d" % [sender_user_id, int(channel), message_id]
	if not _assemblies.has(key) and _assembly_count_for_sender(sender_user_id) >= MAX_ASSEMBLIES_PER_SENDER:
		return
	var assembly: Dictionary = _assemblies.get(key, {
		"total": total,
		"raw_size": raw_size,
		"parts": {},
		"updated_at": Time.get_ticks_msec() * 0.001,
	})
	if int(assembly.get("total", -1)) != total or int(assembly.get("raw_size", -1)) != raw_size:
		return
	var parts: Dictionary = assembly.get("parts", {})
	parts[index] = bytes
	assembly["parts"] = parts
	assembly["updated_at"] = Time.get_ticks_msec() * 0.001
	_assemblies[key] = assembly
	if parts.size() != total:
		return
	var merged := PackedByteArray()
	for part_index: int in range(total):
		if not parts.has(part_index):
			return
		merged.append_array(parts[part_index] as PackedByteArray)
	_assemblies.erase(key)
	var decoded_bytes := merged.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if decoded_bytes.size() != raw_size:
		return
	var decoded: Variant = bytes_to_var(decoded_bytes)
	if decoded is Dictionary:
		packet_received.emit(sender_user_id, int(channel), decoded)


func _assembly_count_for_sender(sender_user_id: String) -> int:
	var prefix := "%s:" % sender_user_id
	var count := 0
	for key: Variant in _assemblies.keys():
		if String(key).begins_with(prefix):
			count += 1
	return count


func _bind_lobby() -> void:
	if not _lobby.lobby_updated.is_connected(_on_lobby_updated):
		_lobby.lobby_updated.connect(_on_lobby_updated)
	if not _lobby.kicked_from_lobby.is_connected(_on_kicked_from_lobby):
		_lobby.kicked_from_lobby.connect(_on_kicked_from_lobby)
	if not _lobby.lobby_owner_changed.is_connected(_on_lobby_owner_changed):
		_lobby.lobby_owner_changed.connect(_on_lobby_owner_changed)


func _bind_peer() -> void:
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)


func _close_peer() -> void:
	if _peer != null:
		if multiplayer.multiplayer_peer == _peer:
			multiplayer.multiplayer_peer = null
		_peer.close()
	_peer = null


func _add_local_member_attributes(ready: bool) -> void:
	_lobby.add_current_member_attribute("NAME", _display_name)
	_lobby.add_current_member_attribute("PLATFORM", _platform_name)
	_lobby.add_current_member_attribute("READY", ready)


func _lobby_attribute(key: String, fallback: Variant) -> Variant:
	var attribute: Dictionary = _lobby.get_attribute(key)
	return attribute.get("value", fallback) if not attribute.is_empty() else fallback


static func _member_attribute(member: HLobbyMember, key: String, fallback: Variant) -> Variant:
	var attribute: Dictionary = member.get_attribute(key)
	return attribute.get("value", fallback) if not attribute.is_empty() else fallback


static func _parse_match_data(raw: String) -> Dictionary:
	if raw.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _match_roster_contains_user(match_data: Dictionary, user_id: String) -> bool:
	for value: Variant in match_data.get("roster", []):
		if value is Dictionary and String((value as Dictionary).get("user_id", "")) == user_id:
			return true
	return false


func _on_lobby_updated() -> void:
	_enforce_locked_roster()
	var snapshot := get_room_snapshot()
	room_changed.emit(snapshot)


func _enforce_locked_roster() -> void:
	if _lobby == null or not _lobby.is_owner() or not bool(_lobby_attribute("LOCKED", false)):
		return
	var match_data := _parse_match_data(String(_lobby_attribute("MATCH_DATA", "")))
	for member: HLobbyMember in _lobby.members:
		if not _match_roster_contains_user(match_data, member.product_user_id):
			member.kick_member_async()


func _on_kicked_from_lobby() -> void:
	_close_peer()
	_lobby = null
	_room_code = ""
	room_left.emit()


func _on_lobby_owner_changed() -> void:
	if _lobby == null:
		return
	host_changed.emit(_lobby.owner_product_user_id)
	room_changed.emit(get_room_snapshot())


func _on_peer_connected(peer_id: int) -> void:
	if _peer != null:
		peer_connected.emit(_peer.get_peer_user_id(peer_id))


func _on_peer_disconnected(peer_id: int) -> void:
	if _peer != null:
		peer_disconnected.emit(_peer.get_peer_user_id(peer_id))


static func _validate_config(config: Dictionary) -> bool:
	for key: String in ["product_id", "sandbox_id", "deployment_id", "client_id", "client_secret"]:
		var value := String(config.get(key, "")).strip_edges()
		if value.is_empty() or value.begins_with("REPLACE_"):
			return false
	var encryption_key := String(config.get("encryption_key", ""))
	return encryption_key.length() == 64 and encryption_key.is_valid_hex_number(false)


static func _detect_platform() -> String:
	match OS.get_name():
		"Android":
			return "android"
		"Windows":
			return "windows"
		_:
			return OS.get_name().to_lower()
