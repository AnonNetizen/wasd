class_name LowpolyOnlineSession
extends Node
## Provider-neutral EOS session and authority lifecycle for the standalone lab.

signal state_changed(previous: int, current: int)
signal role_changed(previous: int, current: int)
signal availability_changed(available: bool, diagnostic: String)
signal room_changed(snapshot: Dictionary)
signal match_ready(match_data: Dictionary)
signal network_message(sender_user_id: String, kind: StringName, payload: Dictionary)
signal participant_connection_changed(user_id: String, connected: bool, seconds_remaining: float)
signal participant_grace_expired(user_id: String)
signal host_migration_started(new_host_user_id: String, authority_epoch: int)
signal host_takeover_requested(checkpoint: Dictionary, authority_epoch: int)
signal host_migration_finished(authority_epoch: int)
signal session_error(message: String)

enum State {
	OFFLINE,
	INITIALIZING,
	AUTHENTICATING,
	IDLE,
	CREATING_ROOM,
	JOINING_ROOM,
	LOBBY,
	CONNECTING,
	IN_MATCH,
	RECONNECTING,
	HOST_MIGRATING,
	ERROR,
}

enum NetworkRole {
	OFFLINE,
	HOST,
	CLIENT,
}

const PROTOCOL_VERSION := "lps-1"
const BUILD_VERSION := "0.2.0"
const MAX_PLAYERS: int = 4
const RECONNECT_GRACE_SECONDS: float = 60.0
const RECONNECT_ATTEMPT_SECONDS: float = 2.0
const HOST_MIGRATION_TIMEOUT_SECONDS: float = 15.0
const CONFIG_PATHS := [
	"res://config/eos_config.local.json",
	"res://config/eos_config.export.json",
	"user://eos_config.local.json",
]
const EOS_TRANSPORT_SCRIPT_PATH := "res://scripts/online/eos_transport.gd"

var _state: State = State.OFFLINE
var _role: NetworkRole = NetworkRole.OFFLINE
var _transport: LowpolyTransport
var _room_snapshot: Dictionary = {}
var _match_data: Dictionary = {}
var _display_name: String = ""
var _local_user_id: String = ""
var _authority_epoch: int = 0
var _reliable_send_sequence: int = 0
var _last_reliable_sequence: Dictionary = {}
var _disconnect_deadlines: Dictionary = {}
var _reconnect_accumulator: float = 0.0
var _migration_deadline: float = 0.0
var _cached_checkpoint: Dictionary = {}
var _last_error: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	availability_changed.emit(false, "EOS 尚未初始化；单人模式可用。")


func _process(delta: float) -> void:
	if _transport is LowpolyFakeTransport:
		(_transport as LowpolyFakeTransport).advance_fake_time(delta)
	if _role == NetworkRole.HOST and not _disconnect_deadlines.is_empty():
		var now := Time.get_ticks_msec() * 0.001
		for user_id: Variant in _disconnect_deadlines.keys():
			var remaining := float(_disconnect_deadlines[user_id]) - now
			participant_connection_changed.emit(String(user_id), false, maxf(remaining, 0.0))
			if remaining <= 0.0:
				_disconnect_deadlines.erase(user_id)
				if _transport != null:
					_transport.remove_member(String(user_id))
				participant_grace_expired.emit(String(user_id))
	if _state == State.RECONNECTING and _role == NetworkRole.CLIENT:
		_reconnect_accumulator += delta
		if _reconnect_accumulator >= RECONNECT_ATTEMPT_SECONDS:
			_reconnect_accumulator = 0.0
			_attempt_client_reconnect()
	if _state == State.HOST_MIGRATING and _migration_deadline > 0.0:
		if Time.get_ticks_msec() * 0.001 >= _migration_deadline:
			_migration_deadline = 0.0
			_fail("联机中断：房主迁移超过 15 秒。")


func initialize_online(display_name: String, transport_override: LowpolyTransport = null) -> bool:
	if _state != State.OFFLINE and _state != State.ERROR:
		return false
	_display_name = display_name.strip_edges().left(32)
	if _display_name.is_empty():
		_fail("昵称不能为空。")
		return false
	_reset_transport()
	_set_role(NetworkRole.OFFLINE)
	_set_state(State.INITIALIZING)
	var config: Dictionary = {}
	if transport_override != null:
		_transport = transport_override
		config = {"platform": _platform_name()}
	else:
		config = _load_local_config()
		if config.is_empty():
			_set_state(State.OFFLINE)
			availability_changed.emit(false, "未找到 EOS 本地配置；单人模式可用。")
			return false
		var transport_script := load(EOS_TRANSPORT_SCRIPT_PATH) as Script
		if transport_script == null:
			_set_state(State.OFFLINE)
			availability_changed.emit(false, "EOS 传输脚本无法加载；单人模式可用。")
			return false
		_transport = transport_script.new() as LowpolyTransport
		if _transport == null:
			_set_state(State.OFFLINE)
			availability_changed.emit(false, "EOS 传输实例无法创建；单人模式可用。")
			return false
	_transport.name = "Transport"
	add_child(_transport)
	_bind_transport()
	_transport.initialize_transport(config, _display_name)
	return true


func create_room() -> bool:
	if _state != State.IDLE or _transport == null:
		return false
	_set_state(State.CREATING_ROOM)
	var room_code := _generate_room_code()
	_transport.create_room(room_code, MAX_PLAYERS, {
		"protocol": PROTOCOL_VERSION,
		"build": BUILD_VERSION,
	})
	return true


func join_room(room_code: String) -> bool:
	if _state != State.IDLE or _transport == null:
		return false
	var normalized := room_code.strip_edges()
	if normalized.length() != 6 or not normalized.is_valid_int():
		_fail("房间码必须是六位数字。", false)
		return false
	_set_state(State.JOINING_ROOM)
	_transport.join_room(normalized)
	return true


func set_ready(ready: bool) -> bool:
	if _state != State.LOBBY or _transport == null:
		return false
	return _transport.update_local_member({
		"display_name": _display_name,
		"ready": ready,
		"platform": _platform_name(),
	})


func can_start_match() -> bool:
	if _state != State.LOBBY or _role != NetworkRole.HOST:
		return false
	var members: Array = _room_snapshot.get("members", [])
	if members.is_empty() or members.size() > MAX_PLAYERS:
		return false
	for value: Variant in members:
		if not value is Dictionary:
			return false
		var member: Dictionary = value
		if not bool(member.get("connected", true)) or not bool(member.get("ready", false)):
			return false
	return true


func start_match(seed: int = -1) -> bool:
	if not can_start_match() or _transport == null:
		return false
	var roster := _build_roster()
	if roster.is_empty():
		return false
	_authority_epoch = 1
	_match_data = {
		"protocol": PROTOCOL_VERSION,
		"build": BUILD_VERSION,
		"room_code": String(_room_snapshot.get("room_code", "")),
		"host_user_id": _local_user_id,
		"socket": "LPS_%s" % String(_room_snapshot.get("room_code", "000000")),
		"seed": seed if seed >= 0 else randi_range(100000, 2147483000),
		"authority_epoch": _authority_epoch,
		"difficulty_players": roster.size(),
		"roster": roster,
		"locked": true,
	}
	_set_state(State.CONNECTING)
	if not _transport.start_host(String(_match_data["socket"])):
		_fail("无法启动 EOS P2P 房主。")
		return false
	if not _transport.set_room_locked(true, _match_data):
		_fail("无法锁定 EOS Lobby。")
		return false
	_set_state(State.IN_MATCH)
	match_ready.emit(_match_data.duplicate(true))
	return true


func leave_room() -> void:
	if _transport != null:
		_transport.leave_room()
	_room_snapshot.clear()
	_match_data.clear()
	_authority_epoch = 0
	_disconnect_deadlines.clear()
	_last_reliable_sequence.clear()
	_set_role(NetworkRole.OFFLINE)
	_set_state(State.IDLE if _transport != null and _transport.is_available() else State.OFFLINE)


func shutdown_online() -> void:
	_reset_transport()
	_room_snapshot.clear()
	_match_data.clear()
	_set_role(NetworkRole.OFFLINE)
	_set_state(State.OFFLINE)
	availability_changed.emit(false, "EOS 已关闭；单人模式可用。")


func abort_online_match(message: String) -> void:
	if _state in [State.IN_MATCH, State.RECONNECTING, State.HOST_MIGRATING]:
		_fail(message)


func send_message(
	target_user_id: String,
	kind: StringName,
	payload: Dictionary,
	reliable: bool = true
) -> bool:
	if _state != State.IN_MATCH and _state != State.HOST_MIGRATING and _state != State.RECONNECTING:
		return false
	if _transport == null or _role == NetworkRole.OFFLINE:
		return false
	if reliable:
		_reliable_send_sequence += 1
	var envelope := {
		"protocol": PROTOCOL_VERSION,
		"epoch": _authority_epoch,
		"kind": String(kind),
		"sequence": _reliable_send_sequence if reliable else int(payload.get("sequence", 0)),
		"reliable": reliable,
		"payload": payload.duplicate(true),
	}
	return _transport.send_packet(
		target_user_id,
		LowpolyTransport.Channel.RELIABLE if reliable else LowpolyTransport.Channel.SNAPSHOT,
		envelope
	)


func send_to_host(kind: StringName, payload: Dictionary, reliable: bool = true) -> bool:
	var host_id := String(_match_data.get("host_user_id", _room_snapshot.get("host_user_id", "")))
	if host_id.is_empty():
		return false
	if _role == NetworkRole.HOST:
		network_message.emit(_local_user_id, kind, payload.duplicate(true))
		return true
	return send_message(host_id, kind, payload, reliable)


func broadcast(kind: StringName, payload: Dictionary, reliable: bool = true) -> bool:
	if _role != NetworkRole.HOST:
		return false
	return send_message("", kind, payload, reliable)


func set_cached_checkpoint(checkpoint: Dictionary) -> void:
	_cached_checkpoint = checkpoint.duplicate(true)


func get_cached_checkpoint() -> Dictionary:
	return _cached_checkpoint.duplicate(true)


func complete_host_migration(restored_checkpoint: Dictionary) -> bool:
	if _state != State.HOST_MIGRATING or _role != NetworkRole.HOST:
		return false
	if not restored_checkpoint.is_empty():
		_cached_checkpoint = restored_checkpoint.duplicate(true)
	_match_data["host_user_id"] = _local_user_id
	_match_data["authority_epoch"] = _authority_epoch
	# Lobby MATCH_DATA is a recovery advertisement. Refresh it before sending the
	# resume event so peers can never restore the departed owner's stale epoch.
	if not _transport.set_room_locked(true, _match_data):
		_fail("房主迁移后无法刷新 Lobby 对局元数据。")
		return false
	broadcast(&"authority_resumed", {
		"host_user_id": _local_user_id,
		"authority_epoch": _authority_epoch,
		"checkpoint": _cached_checkpoint,
	})
	_migration_deadline = 0.0
	_set_state(State.IN_MATCH)
	host_migration_finished.emit(_authority_epoch)
	return true


func mark_peer_reconnected(user_id: String) -> void:
	if _role == NetworkRole.HOST and _disconnect_deadlines.has(user_id):
		_disconnect_deadlines.erase(user_id)
		participant_connection_changed.emit(user_id, true, RECONNECT_GRACE_SECONDS)


func get_state() -> State:
	return _state


func get_role() -> NetworkRole:
	return _role


func get_local_user_id() -> String:
	return _local_user_id


func get_room_snapshot() -> Dictionary:
	return _room_snapshot.duplicate(true)


func get_match_data() -> Dictionary:
	return _match_data.duplicate(true)


func get_authority_epoch() -> int:
	return _authority_epoch


func get_reliable_send_sequence() -> int:
	return _reliable_send_sequence


func adopt_checkpoint_network_metadata(checkpoint: Dictionary) -> void:
	var metadata: Dictionary = checkpoint.get("network", {})
	_reliable_send_sequence = maxi(
		_reliable_send_sequence,
		int(metadata.get("reliable_event_sequence", 0))
	)


func is_online_match() -> bool:
	return _role != NetworkRole.OFFLINE and _state in [State.IN_MATCH, State.RECONNECTING, State.HOST_MIGRATING]


func get_debug_snapshot() -> Dictionary:
	return {
		"state": int(_state),
		"role": int(_role),
		"local_user_id": _local_user_id,
		"room": _room_snapshot.duplicate(true),
		"match": _match_data.duplicate(true),
		"authority_epoch": _authority_epoch,
		"disconnecting": _disconnect_deadlines.duplicate(true),
		"last_error": _last_error,
	}


func get_transport_for_tests() -> LowpolyTransport:
	return _transport


func force_reconnect_timeout_for_test(user_id: String) -> bool:
	if not _disconnect_deadlines.has(user_id):
		return false
	_disconnect_deadlines[user_id] = Time.get_ticks_msec() * 0.001 - 0.01
	return true


func force_host_migration_timeout_for_test() -> bool:
	if _state != State.HOST_MIGRATING:
		return false
	_migration_deadline = Time.get_ticks_msec() * 0.001 - 0.01
	return true


func _bind_transport() -> void:
	_transport.transport_ready.connect(_on_transport_ready)
	_transport.authenticated.connect(_on_authenticated)
	_transport.room_created.connect(_on_room_entered)
	_transport.room_joined.connect(_on_room_entered)
	_transport.room_changed.connect(_on_room_changed)
	_transport.room_left.connect(_on_room_left)
	_transport.host_changed.connect(_on_host_changed)
	_transport.peer_connected.connect(_on_peer_connected)
	_transport.peer_disconnected.connect(_on_peer_disconnected)
	_transport.packet_received.connect(_on_packet_received)
	_transport.transport_error.connect(_on_transport_error)


func _on_transport_ready() -> void:
	_set_state(State.AUTHENTICATING)


func _on_authenticated(user_id: String) -> void:
	_local_user_id = user_id
	_set_state(State.IDLE)
	availability_changed.emit(true, "EOS Device ID 已连接。")


func _on_room_entered(snapshot: Dictionary) -> void:
	_room_snapshot = snapshot.duplicate(true)
	var metadata: Dictionary = _room_snapshot.get("metadata", {})
	if String(metadata.get("protocol", "")) != PROTOCOL_VERSION:
		_transport.leave_room()
		_fail("房间协议版本不兼容。")
		return
	if String(metadata.get("build", "")) != BUILD_VERSION:
		_transport.leave_room()
		_fail("房间构建版本不兼容。")
		return
	_update_role_from_room()
	_set_state(State.LOBBY)
	room_changed.emit(_room_snapshot.duplicate(true))


func _on_room_changed(snapshot: Dictionary) -> void:
	var previous_match_host := String(_match_data.get("host_user_id", ""))
	_room_snapshot = snapshot.duplicate(true)
	_update_role_from_room()
	room_changed.emit(_room_snapshot.duplicate(true))
	var metadata: Dictionary = _room_snapshot.get("metadata", {})
	var advertised_match: Dictionary = metadata.get("match_data", {})
	if bool(_room_snapshot.get("locked", false)) and not advertised_match.is_empty():
		if String(advertised_match.get("protocol", "")) != PROTOCOL_VERSION:
			_fail("房间协议版本不兼容。")
			return
		if String(advertised_match.get("build", "")) != BUILD_VERSION:
			_fail("房间构建版本不兼容。")
			return
		if _state == State.LOBBY:
			_match_data = advertised_match.duplicate(true)
			_authority_epoch = int(_match_data.get("authority_epoch", 1))
		if _role == NetworkRole.CLIENT and _state == State.LOBBY:
			_set_state(State.CONNECTING)
			if _transport.connect_to_host(
				String(_match_data.get("socket", "")),
				String(_match_data.get("host_user_id", ""))
			):
				_set_state(State.IN_MATCH)
				match_ready.emit(_match_data.duplicate(true))
			else:
				_set_state(State.RECONNECTING)
		elif _state in [State.IN_MATCH, State.RECONNECTING, State.HOST_MIGRATING]:
			# MATCH_DATA can lag one Lobby-owner notification behind during host
			# migration. The current Lobby owner is authoritative for host election;
			# do not let the stale advertisement roll epoch/host back.
			var lobby_host := String(_room_snapshot.get("host_user_id", ""))
			if not lobby_host.is_empty() and lobby_host != previous_match_host:
				_begin_host_migration(lobby_host)


func _on_room_left() -> void:
	var interrupted := _state in [State.IN_MATCH, State.RECONNECTING, State.HOST_MIGRATING]
	var departed_owner := _role == NetworkRole.HOST
	_room_snapshot.clear()
	_match_data.clear()
	_set_role(NetworkRole.OFFLINE)
	if interrupted and not departed_owner:
		_fail("联机中断：EOS Lobby 已关闭。")
	elif _state != State.OFFLINE:
		_set_state(State.IDLE if _transport != null and _transport.is_available() else State.OFFLINE)


func _on_peer_connected(user_id: String) -> void:
	if user_id.is_empty():
		return
	if _role == NetworkRole.HOST:
		mark_peer_reconnected(user_id)
	elif user_id == String(_match_data.get("host_user_id", "")) and _state == State.RECONNECTING:
		_set_state(State.IN_MATCH)
	participant_connection_changed.emit(user_id, true, RECONNECT_GRACE_SECONDS)


func _on_peer_disconnected(user_id: String) -> void:
	if user_id.is_empty():
		return
	participant_connection_changed.emit(user_id, false, RECONNECT_GRACE_SECONDS)
	if _role == NetworkRole.HOST:
		_disconnect_deadlines[user_id] = Time.get_ticks_msec() * 0.001 + RECONNECT_GRACE_SECONDS
	elif user_id == String(_match_data.get("host_user_id", "")):
		_reconnect_accumulator = RECONNECT_ATTEMPT_SECONDS
		_set_state(State.RECONNECTING)


func _on_host_changed(new_host_user_id: String) -> void:
	if _match_data.is_empty() or _state not in [State.IN_MATCH, State.RECONNECTING, State.HOST_MIGRATING]:
		_update_role_from_room()
		return
	_begin_host_migration(new_host_user_id)


func _begin_host_migration(new_host_user_id: String) -> void:
	if new_host_user_id.is_empty() or _match_data.is_empty():
		return
	if String(_match_data.get("host_user_id", "")) == new_host_user_id:
		_set_role(NetworkRole.HOST if new_host_user_id == _local_user_id else NetworkRole.CLIENT)
		return
	_authority_epoch += 1
	_last_reliable_sequence.clear()
	_match_data["host_user_id"] = new_host_user_id
	_match_data["authority_epoch"] = _authority_epoch
	_set_state(State.HOST_MIGRATING)
	_migration_deadline = Time.get_ticks_msec() * 0.001 + HOST_MIGRATION_TIMEOUT_SECONDS
	_set_role(NetworkRole.HOST if new_host_user_id == _local_user_id else NetworkRole.CLIENT)
	host_migration_started.emit(new_host_user_id, _authority_epoch)
	if _role == NetworkRole.HOST:
		if not _transport.start_host(String(_match_data.get("socket", ""))):
			_fail("房主迁移时无法重建 P2P 星型连接。")
			return
		host_takeover_requested.emit.call_deferred(
			_cached_checkpoint.duplicate(true),
			_authority_epoch
		)
	else:
		_transport.connect_to_host(String(_match_data.get("socket", "")), new_host_user_id)


func _on_packet_received(sender_user_id: String, _channel: int, envelope: Dictionary) -> void:
	if String(envelope.get("protocol", "")) != PROTOCOL_VERSION:
		return
	if int(envelope.get("epoch", -1)) != _authority_epoch:
		return
	var reliable := bool(envelope.get("reliable", false))
	var sequence := int(envelope.get("sequence", 0))
	if reliable:
		var last := int(_last_reliable_sequence.get(sender_user_id, 0))
		if sequence <= last:
			return
		_last_reliable_sequence[sender_user_id] = sequence
	var kind := StringName(envelope.get("kind", ""))
	var payload: Dictionary = envelope.get("payload", {})
	if kind == &"authority_resumed":
		if sender_user_id != String(_match_data.get("host_user_id", "")):
			return
		_cached_checkpoint = (payload.get("checkpoint", {}) as Dictionary).duplicate(true)
		_migration_deadline = 0.0
		_set_state(State.IN_MATCH)
		host_migration_finished.emit(_authority_epoch)
		return
	network_message.emit(sender_user_id, kind, payload.duplicate(true))


func _on_transport_error(message: String) -> void:
	_fail(message)


func _attempt_client_reconnect() -> void:
	if _transport == null or _match_data.is_empty():
		return
	_transport.connect_to_host(
		String(_match_data.get("socket", "")),
		String(_match_data.get("host_user_id", ""))
	)


func _build_roster() -> Array[Dictionary]:
	var members: Array = _room_snapshot.get("members", [])
	var host_id := String(_room_snapshot.get("host_user_id", ""))
	var ordered: Array[Dictionary] = []
	for value: Variant in members:
		if value is Dictionary and String((value as Dictionary).get("user_id", "")) == host_id:
			ordered.append((value as Dictionary).duplicate(true))
	for value: Variant in members:
		if value is Dictionary and String((value as Dictionary).get("user_id", "")) != host_id:
			ordered.append((value as Dictionary).duplicate(true))
	for index: int in range(ordered.size()):
		ordered[index]["slot"] = index
	return ordered


func _update_role_from_room() -> void:
	if _room_snapshot.is_empty():
		_set_role(NetworkRole.OFFLINE)
	else:
		_set_role(
			NetworkRole.HOST
			if String(_room_snapshot.get("host_user_id", "")) == _local_user_id
			else NetworkRole.CLIENT
		)


func _set_state(value: State) -> void:
	if _state == value:
		return
	var previous := _state
	_state = value
	state_changed.emit(int(previous), int(_state))


func _set_role(value: NetworkRole) -> void:
	if _role == value:
		return
	var previous := _role
	_role = value
	role_changed.emit(int(previous), int(_role))


func _fail(message: String, terminal: bool = true) -> void:
	_last_error = message
	if terminal:
		_set_state(State.ERROR)
	session_error.emit(message)


func _reset_transport() -> void:
	if _transport != null:
		_transport.shutdown()
		if _transport.get_parent() == self:
			remove_child(_transport)
		_transport.queue_free()
	_transport = null
	_local_user_id = ""


func _load_local_config() -> Dictionary:
	var environment_path := OS.get_environment("LOWPOLY_EOS_CONFIG_PATH").strip_edges()
	var candidates: Array[String] = []
	if not environment_path.is_empty():
		candidates.append(environment_path)
	for path: String in CONFIG_PATHS:
		candidates.append(path)
	for path: String in candidates:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			return parsed
	return {}


static func _generate_room_code() -> String:
	return "%06d" % randi_range(0, 999999)


static func _platform_name() -> String:
	return "android" if OS.get_name() == "Android" else "windows" if OS.get_name() == "Windows" else OS.get_name().to_lower()
