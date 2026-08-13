class_name LowpolyTransport
extends Node
## Provider-neutral lobby and packet transport used by the standalone lab.

signal transport_ready
signal authenticated(user_id: String)
signal room_created(snapshot: Dictionary)
signal room_joined(snapshot: Dictionary)
signal room_changed(snapshot: Dictionary)
signal room_left
signal host_changed(new_host_user_id: String)
signal peer_connected(user_id: String)
signal peer_disconnected(user_id: String)
signal packet_received(sender_user_id: String, channel: int, payload: Dictionary)
signal transport_error(message: String)

enum Channel {
	RELIABLE,
	SNAPSHOT,
}


func initialize_transport(_config: Dictionary, _display_name: String) -> void:
	transport_error.emit("Transport does not implement initialization.")


func create_room(_room_code: String, _max_members: int, _metadata: Dictionary) -> void:
	transport_error.emit("Transport does not implement room creation.")


func join_room(_room_code: String) -> void:
	transport_error.emit("Transport does not implement room joining.")


func update_local_member(_member_data: Dictionary) -> bool:
	return false


func set_room_locked(_locked: bool, _match_data: Dictionary = {}) -> bool:
	return false


func start_host(_socket_name: String) -> bool:
	return false


func connect_to_host(_socket_name: String, _host_user_id: String) -> bool:
	return false


func send_packet(
	_target_user_id: String,
	_channel: Channel,
	_payload: Dictionary
) -> bool:
	return false


func remove_member(_user_id: String) -> bool:
	return false


func leave_room() -> void:
	room_left.emit()


func shutdown() -> void:
	pass


func get_local_user_id() -> String:
	return ""


func get_room_snapshot() -> Dictionary:
	return {}


func is_available() -> bool:
	return false
