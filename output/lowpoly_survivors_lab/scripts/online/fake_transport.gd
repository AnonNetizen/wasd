class_name LowpolyFakeTransport
extends LowpolyTransport
## Deterministic in-process transport used by multiplayer smoke coverage.

static var _rooms: Dictionary = {}
static var _instances: Dictionary = {}
static var _next_user_serial: int = 1

var latency_seconds: float = 0.0
var drop_every_nth: int = 0
var duplicate_every_nth: int = 0
var reorder_next_pair: bool = false
var forced_user_id: String = ""
var defer_peer_connection: bool = false
var drop_peer_connections_before_success: int = 0
var connect_attempt_count: int = 0
var peer_reset_count: int = 0
var diagnostic_history: Array[StringName] = []

var _local_user_id: String = ""
var _display_name: String = ""
var _platform_name: String = "test"
var _room_code: String = ""
var _packet_serial: int = 0
var _fake_time: float = 0.0
var _pending_packets: Array[Dictionary] = []
var _held_reorder_packet: Dictionary = {}
var _pending_host_user_id: String = ""
var _logical_host_user_id: String = ""
var _logical_role: String = "none"


static func reset_bus_for_tests() -> void:
	_rooms.clear()
	_instances.clear()
	_next_user_serial = 1


func initialize_transport(config: Dictionary, display_name: String) -> void:
	_display_name = display_name.strip_edges()
	_platform_name = String(config.get("platform", "test"))
	_local_user_id = String(config.get("forced_user_id", forced_user_id))
	if _local_user_id.is_empty():
		_local_user_id = "fake-user-%d" % _next_user_serial
		_next_user_serial += 1
	if _instances.has(_local_user_id):
		transport_error.emit("Fake user id is already connected: %s" % _local_user_id)
		return
	_instances[_local_user_id] = self
	transport_ready.emit()
	authenticated.emit(_local_user_id)


func create_room(room_code: String, max_members: int, metadata: Dictionary) -> void:
	if _local_user_id.is_empty():
		transport_error.emit("Fake transport is not authenticated.")
		return
	var normalized_code := room_code.strip_edges().to_upper()
	if _rooms.has(normalized_code):
		transport_error.emit("Room code already exists.")
		return
	_room_code = normalized_code
	_rooms[_room_code] = {
		"room_code": _room_code,
		"host_user_id": _local_user_id,
		"max_members": clampi(max_members, 1, 4),
		"locked": false,
		"metadata": metadata.duplicate(true),
		"members": {_local_user_id: _make_member()},
		"join_order": [_local_user_id],
	}
	var snapshot := get_room_snapshot()
	room_created.emit(snapshot)
	room_changed.emit(snapshot)


func join_room(room_code: String) -> void:
	var normalized_code := room_code.strip_edges().to_upper()
	if not _rooms.has(normalized_code):
		transport_error.emit("Room code does not exist.")
		return
	var room: Dictionary = _rooms[normalized_code]
	if bool(room.get("locked", false)) and not _locked_room_contains_user(room, _local_user_id):
		transport_error.emit("Room has already started.")
		return
	var members: Dictionary = room.get("members", {})
	if members.size() >= int(room.get("max_members", 4)):
		transport_error.emit("Room is full.")
		return
	_room_code = normalized_code
	members[_local_user_id] = _make_member()
	var join_order: Array = room.get("join_order", [])
	join_order.append(_local_user_id)
	room["members"] = members
	room["join_order"] = join_order
	_rooms[_room_code] = room
	room_joined.emit(get_room_snapshot())
	_notify_room_members(_room_code)


func update_local_member(member_data: Dictionary) -> bool:
	if not _rooms.has(_room_code):
		return false
	var room: Dictionary = _rooms[_room_code]
	var members: Dictionary = room.get("members", {})
	if not members.has(_local_user_id):
		return false
	var member: Dictionary = members[_local_user_id]
	for key: Variant in member_data.keys():
		member[String(key)] = member_data[key]
	members[_local_user_id] = member
	room["members"] = members
	_rooms[_room_code] = room
	_notify_room_members(_room_code)
	return true


func set_room_locked(locked: bool, match_data: Dictionary = {}) -> bool:
	if not _rooms.has(_room_code):
		return false
	var room: Dictionary = _rooms[_room_code]
	if String(room.get("host_user_id", "")) != _local_user_id:
		return false
	room["locked"] = locked
	if not match_data.is_empty():
		var metadata: Dictionary = room.get("metadata", {})
		metadata["match_data"] = match_data.duplicate(true)
		room["metadata"] = metadata
	_rooms[_room_code] = room
	_notify_room_members(_room_code)
	return true


func start_host(_socket_name: String) -> bool:
	if not _rooms.has(_room_code):
		return false
	var room: Dictionary = _rooms[_room_code]
	_logical_host_user_id = _local_user_id
	_logical_role = "host"
	var allowed := String(room.get("host_user_id", "")) == _local_user_id
	if allowed:
		_emit_connection_diagnostic(&"MESH_CREATED")
	return allowed


func connect_to_host(_socket_name: String, host_user_id: String) -> bool:
	connect_attempt_count += 1
	_logical_host_user_id = host_user_id
	_logical_role = "client"
	_emit_connection_diagnostic(&"MESH_CREATED", host_user_id)
	_emit_connection_diagnostic(&"REQUEST_SENT", host_user_id)
	if not _instances.has(host_user_id):
		return false
	if connect_attempt_count <= drop_peer_connections_before_success:
		return true
	if defer_peer_connection:
		_pending_host_user_id = host_user_id
		return true
	_emit_peer_connection(host_user_id)
	return true


func prepare_connection_retry() -> void:
	peer_reset_count += 1
	_pending_host_user_id = ""
	_emit_connection_diagnostic(&"CLOSED", _logical_host_user_id, {"close_reason": "retry_reset"})


func complete_deferred_connection_for_test() -> bool:
	if _pending_host_user_id.is_empty():
		return false
	var host_user_id := _pending_host_user_id
	_pending_host_user_id = ""
	_emit_peer_connection(host_user_id)
	return true


func _emit_peer_connection(host_user_id: String) -> void:
	_emit_connection_diagnostic(&"EOS_LINK_UP", host_user_id, {"network_type": 1})
	_emit_connection_diagnostic(&"PEER_READY", host_user_id)
	peer_connected.emit(host_user_id)
	var host := _instances[host_user_id] as LowpolyFakeTransport
	if is_instance_valid(host):
		host._emit_connection_diagnostic(&"REQUEST_ACCEPTED", _local_user_id)
		host._emit_connection_diagnostic(&"EOS_LINK_UP", _local_user_id, {"network_type": 1})
		host._emit_connection_diagnostic(&"PEER_READY", _local_user_id)
		host.peer_connected.emit(_local_user_id)


func send_packet(
	target_user_id: String,
	channel: Channel,
	payload: Dictionary
) -> bool:
	_packet_serial += 1
	if drop_every_nth > 0 and _packet_serial % drop_every_nth == 0:
		return true
	var targets: Array[String] = []
	if target_user_id.is_empty():
		if not _rooms.has(_room_code):
			return false
		var members: Dictionary = (_rooms[_room_code] as Dictionary).get("members", {})
		for user_id: Variant in members.keys():
			var normalized_id := String(user_id)
			if normalized_id != _local_user_id:
				targets.append(normalized_id)
	else:
		targets.append(target_user_id)
	for user_id: String in targets:
		if not _instances.has(user_id):
			continue
		_queue_packet(user_id, channel, payload)
		if duplicate_every_nth > 0 and _packet_serial % duplicate_every_nth == 0:
			_queue_packet(user_id, channel, payload)
	return true


func remove_member(user_id: String) -> bool:
	if not _rooms.has(_room_code):
		return false
	var room: Dictionary = _rooms[_room_code]
	if String(room.get("host_user_id", "")) != _local_user_id:
		return false
	_remove_member_from_room(_room_code, user_id, false)
	return true


func leave_room() -> void:
	if not _room_code.is_empty() and _rooms.has(_room_code):
		_remove_member_from_room(_room_code, _local_user_id, true)
	_room_code = ""
	room_left.emit()


func shutdown() -> void:
	leave_room()
	if _instances.get(_local_user_id) == self:
		_instances.erase(_local_user_id)


func get_local_user_id() -> String:
	return _local_user_id


func get_room_snapshot() -> Dictionary:
	if not _rooms.has(_room_code):
		return {}
	return _public_room_snapshot(_rooms[_room_code])


func is_available() -> bool:
	return not _local_user_id.is_empty()


func get_debug_snapshot() -> Dictionary:
	return {
		"connect_attempt_count": connect_attempt_count,
		"peer_reset_count": peer_reset_count,
		"deferred_host_user_id": _pending_host_user_id,
		"logical_role": _logical_role,
		"diagnostic_history": diagnostic_history.duplicate(),
	}


func simulate_incoming_connection_request_for_test(remote_user_id: String) -> bool:
	var allowed := _star_peer_allowed(remote_user_id)
	_emit_connection_diagnostic(
		&"REQUEST_ACCEPTED" if allowed else &"CLOSED",
		remote_user_id,
		{} if allowed else {"close_reason": "unauthorized_request"}
	)
	return allowed


func _star_peer_allowed(remote_user_id: String) -> bool:
	if not _rooms.has(_room_code):
		return false
	return LowpolyTransport.is_star_connection_allowed(
		_logical_role,
		_local_user_id,
		_logical_host_user_id,
		remote_user_id,
		get_room_snapshot()
	)


func _emit_connection_diagnostic(
	stage: StringName,
	remote_user_id: String = "",
	extra: Dictionary = {}
) -> void:
	diagnostic_history.append(stage)
	var data := {
		"logical_role": _logical_role,
		"connected_peers": 1 if stage == &"PEER_READY" else 0,
		"expected_peers": _expected_peer_count(),
	}
	if not remote_user_id.is_empty():
		data["peer_hash"] = remote_user_id.sha256_text().left(8)
	for key: Variant in extra.keys():
		data[key] = extra[key]
	connection_diagnostic.emit(stage, data)


func _expected_peer_count() -> int:
	if not _rooms.has(_room_code):
		return 0
	var members: Dictionary = (_rooms[_room_code] as Dictionary).get("members", {})
	var other_members := maxi(members.size() - 1, 0)
	return mini(other_members, 1) if _logical_role == "client" else other_members


func advance_fake_time(delta: float) -> void:
	_fake_time += maxf(delta, 0.0)
	for index: int in range(_pending_packets.size() - 1, -1, -1):
		var queued: Dictionary = _pending_packets[index]
		if float(queued.get("deliver_at", 0.0)) > _fake_time:
			continue
		_pending_packets.remove_at(index)
		packet_received.emit(
			String(queued.get("sender", "")),
			int(queued.get("channel", Channel.RELIABLE)),
			(queued.get("payload", {}) as Dictionary).duplicate(true)
		)


func simulate_connection_loss() -> void:
	if _room_code.is_empty() or not _rooms.has(_room_code):
		return
	var room: Dictionary = _rooms[_room_code]
	var members: Dictionary = room.get("members", {})
	if members.has(_local_user_id):
		var member: Dictionary = members[_local_user_id]
		member["connected"] = false
		members[_local_user_id] = member
		room["members"] = members
		_rooms[_room_code] = room
	for user_id: Variant in members.keys():
		if String(user_id) == _local_user_id or not _instances.has(user_id):
			continue
		var other := _instances[user_id] as LowpolyFakeTransport
		if is_instance_valid(other):
			other.peer_disconnected.emit(_local_user_id)
	peer_disconnected.emit(String(room.get("host_user_id", "")))
	_notify_room_members(_room_code)


func simulate_reconnect() -> void:
	if _room_code.is_empty() or not _rooms.has(_room_code):
		return
	var room: Dictionary = _rooms[_room_code]
	var members: Dictionary = room.get("members", {})
	if not members.has(_local_user_id):
		return
	var member: Dictionary = members[_local_user_id]
	member["connected"] = true
	members[_local_user_id] = member
	room["members"] = members
	_rooms[_room_code] = room
	var host_id := String(room.get("host_user_id", ""))
	if host_id != _local_user_id:
		connect_to_host("", host_id)
	_notify_room_members(_room_code)


func _make_member() -> Dictionary:
	return {
		"user_id": _local_user_id,
		"display_name": _display_name,
		"platform": _platform_name,
		"ready": false,
		"connected": true,
	}


static func _locked_room_contains_user(room: Dictionary, user_id: String) -> bool:
	var metadata: Dictionary = room.get("metadata", {})
	var match_data: Dictionary = metadata.get("match_data", {})
	for value: Variant in match_data.get("roster", []):
		if value is Dictionary and String((value as Dictionary).get("user_id", "")) == user_id:
			return true
	return false


func _queue_packet(user_id: String, channel: Channel, payload: Dictionary) -> void:
	var target := _instances[user_id] as LowpolyFakeTransport
	if not is_instance_valid(target):
		return
	var queued := {
		"deliver_at": target._fake_time + latency_seconds,
		"sender": _local_user_id,
		"channel": int(channel),
		"payload": payload.duplicate(true),
	}
	if reorder_next_pair:
		if _held_reorder_packet.is_empty():
			_held_reorder_packet = {"target": user_id, "packet": queued}
			return
		var held_target_id := String(_held_reorder_packet.get("target", ""))
		if _instances.has(held_target_id):
			var held_target := _instances[held_target_id] as LowpolyFakeTransport
			held_target._pending_packets.append(_held_reorder_packet.get("packet", {}) as Dictionary)
		target._pending_packets.append(queued)
		_held_reorder_packet.clear()
		reorder_next_pair = false
		return
	target._pending_packets.append(queued)
	if latency_seconds <= 0.0:
		target.advance_fake_time(0.0)


static func _public_room_snapshot(room: Dictionary) -> Dictionary:
	var result: Dictionary = room.duplicate(true)
	var members_dictionary: Dictionary = result.get("members", {})
	var ordered_members: Array[Dictionary] = []
	for user_id: Variant in result.get("join_order", []):
		if members_dictionary.has(user_id):
			ordered_members.append((members_dictionary[user_id] as Dictionary).duplicate(true))
	result["members"] = ordered_members
	result.erase("join_order")
	return result


static func _notify_room_members(room_code: String) -> void:
	if not _rooms.has(room_code):
		return
	var snapshot := _public_room_snapshot(_rooms[room_code])
	var room: Dictionary = _rooms[room_code]
	var members: Dictionary = room.get("members", {})
	for user_id: Variant in members.keys():
		if not _instances.has(user_id):
			continue
		var transport := _instances[user_id] as LowpolyFakeTransport
		if is_instance_valid(transport):
			transport.room_changed.emit(snapshot.duplicate(true))


static func _remove_member_from_room(
	room_code: String,
	user_id: String,
	emit_disconnect: bool
) -> void:
	if not _rooms.has(room_code):
		return
	var room: Dictionary = _rooms[room_code]
	var members: Dictionary = room.get("members", {})
	if not members.has(user_id):
		return
	members.erase(user_id)
	var join_order: Array = room.get("join_order", [])
	join_order.erase(user_id)
	var old_host := String(room.get("host_user_id", ""))
	room["members"] = members
	room["join_order"] = join_order
	if members.is_empty():
		_rooms.erase(room_code)
		return
	if old_host == user_id:
		var new_host := String(join_order.front())
		room["host_user_id"] = new_host
		_rooms[room_code] = room
		for member_id: Variant in members.keys():
			if _instances.has(member_id):
				var peer := _instances[member_id] as LowpolyFakeTransport
				peer.host_changed.emit(new_host)
	else:
		_rooms[room_code] = room
	if emit_disconnect:
		for member_id: Variant in members.keys():
			if _instances.has(member_id):
				var peer := _instances[member_id] as LowpolyFakeTransport
				peer.peer_disconnected.emit(user_id)
	_notify_room_members(room_code)
