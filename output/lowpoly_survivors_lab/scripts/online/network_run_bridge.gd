class_name LowpolyNetworkRunBridge
extends Node
## Connects OnlineSession packets to the host-authoritative RunDirector simulation.

signal match_started(local_slot: int, role: int)
signal upgrade_offer_received(options: Array[Dictionary])
signal latency_changed(milliseconds: int)
signal migration_notice(active: bool, message: String)
signal online_match_interrupted(message: String)

const INPUT_RATE_HZ: float = 20.0
const SNAPSHOT_RATE_HZ: float = 10.0
const CHECKPOINT_RATE_HZ: float = 1.0
const MAX_INPUT_PACKETS_PER_SECOND: int = 32
const MAX_INPUT_PAYLOAD_BYTES: int = 256
const INTEREST_RADIUS: float = 56.0
const MOBILE_SNAPSHOT_DIVISOR: int = 2
const ENTITY_BATCH_SIZE: int = 6
const INITIAL_SYNC_RETRY_SECONDS: float = 2.0
const SNAPSHOT_STALL_SECONDS: float = 3.0

var _session: LowpolyOnlineSession
var _director: LowpolyRunDirector
var _running: bool = false
var _local_slot: int = 0
var _input_sequence: int = 0
var _input_accumulator: float = 0.0
var _snapshot_accumulator: float = 0.0
var _checkpoint_accumulator: float = 0.0
var _ping_accumulator: float = 0.0
var _latest_inputs: Dictionary = {}
var _pending_local_inputs: Array[Dictionary] = []
var _last_input_sequences: Dictionary = {}
var _input_rate_windows: Dictionary = {}
var _known_entities_by_user: Dictionary = {}
var _last_checkpoint: Dictionary = {}
var _touch_input: Vector2 = Vector2.ZERO
var _snapshot_frame_index: int = 0
var _authority_snapshot_received: bool = false
var _sync_retry_accumulator: float = 0.0
var _last_snapshot_received_msec: int = 0
var _snapshots_received: int = 0
var _entity_batches_received: int = 0
var _input_rate_hz: float = INPUT_RATE_HZ
var _snapshot_rate_hz: float = SNAPSHOT_RATE_HZ
var _checkpoint_rate_hz: float = CHECKPOINT_RATE_HZ
var _interest_radius: float = INTEREST_RADIUS


func setup(session: LowpolyOnlineSession, director: LowpolyRunDirector) -> void:
	_session = session
	_director = director
	var tuning := _director.get_network_tuning()
	_input_rate_hz = float(tuning.get("input_rate_hz", INPUT_RATE_HZ))
	_snapshot_rate_hz = float(tuning.get("snapshot_rate_hz", SNAPSHOT_RATE_HZ))
	_checkpoint_rate_hz = float(tuning.get("checkpoint_rate_hz", CHECKPOINT_RATE_HZ))
	_interest_radius = float(tuning.get("interest_radius", INTEREST_RADIUS))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session.match_ready.connect(_on_match_ready)
	_session.network_message.connect(_on_network_message)
	_session.participant_connection_changed.connect(_on_participant_connection_changed)
	_session.participant_grace_expired.connect(_on_participant_grace_expired)
	_session.host_migration_started.connect(_on_host_migration_started)
	_session.host_takeover_requested.connect(_on_host_takeover_requested)
	_session.host_migration_finished.connect(_on_host_migration_finished)
	_session.session_error.connect(_on_session_error)
	_director.network_upgrade_requested.connect(_on_network_upgrade_requested)
	_director.run_finished.connect(_on_run_finished)


func _physics_process(delta: float) -> void:
	if not _running or _session == null or _director == null:
		return
	if _session.get_state() != LowpolyOnlineSession.State.IN_MATCH:
		return
	var local_input := get_local_input()
	if _session.get_role() == LowpolyOnlineSession.NetworkRole.HOST:
		_latest_inputs[_local_slot] = local_input
		_director.simulate_network_step(delta, _latest_inputs)
		_update_host_replication(delta)
	else:
		_director.predict_local_player(delta, local_input)
		_input_accumulator += delta
		if _input_accumulator >= 1.0 / _input_rate_hz:
			_input_accumulator = fmod(_input_accumulator, 1.0 / _input_rate_hz)
			_send_local_input(local_input)
		var snapshot_stalled := (
			not _authority_snapshot_received
			or Time.get_ticks_msec() - _last_snapshot_received_msec
			> int(SNAPSHOT_STALL_SECONDS * 1000.0)
		)
		if snapshot_stalled:
			_sync_retry_accumulator += delta
			if _sync_retry_accumulator >= INITIAL_SYNC_RETRY_SECONDS:
				_sync_retry_accumulator = 0.0
				_session.send_to_host(&"sync_hello", {"slot": _local_slot})
	_update_ping(delta)


func set_touch_input(value: Vector2) -> void:
	_touch_input = value.limit_length(1.0)


func get_local_input() -> Vector2:
	var hardware := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return (hardware if hardware.length_squared() >= _touch_input.length_squared() else _touch_input).limit_length(1.0)


func submit_upgrade_choice(upgrade_id: StringName) -> bool:
	if not _running or _director.get_state() != LowpolyRunDirector.RunState.LEVEL_UP:
		return false
	if _session.get_role() == LowpolyOnlineSession.NetworkRole.HOST:
		return _director.choose_network_upgrade(_local_slot, upgrade_id)
	return _session.send_to_host(&"upgrade_choice", {
		"slot": _local_slot,
		"upgrade_id": String(upgrade_id),
	})


func stop_match() -> void:
	_running = false
	_latest_inputs.clear()
	_pending_local_inputs.clear()
	_known_entities_by_user.clear()
	_last_input_sequences.clear()
	_input_rate_windows.clear()
	_authority_snapshot_received = false
	_sync_retry_accumulator = 0.0


func get_debug_snapshot() -> Dictionary:
	return {
		"running": _running,
		"local_slot": _local_slot,
		"input_sequence": _input_sequence,
		"latest_inputs": _latest_inputs.duplicate(true),
		"pending_local_inputs": _pending_local_inputs.duplicate(true),
		"last_input_sequences": _last_input_sequences.duplicate(true),
		"checkpoint_tick": int(_last_checkpoint.get("tick", -1)),
		"authority_snapshot_received": _authority_snapshot_received,
		"last_snapshot_received_msec": _last_snapshot_received_msec,
		"snapshots_received": _snapshots_received,
		"entity_batches_received": _entity_batches_received,
	}


func queue_predicted_input_for_test(sequence: int, input_vector: Vector2, delta: float) -> void:
	_pending_local_inputs.append({
		"sequence": sequence,
		"vector": input_vector.limit_length(1.0),
		"delta": maxf(delta, 0.0),
	})


func _on_match_ready(match_data: Dictionary) -> void:
	_local_slot = _slot_for_user(match_data, _session.get_local_user_id())
	if _local_slot < 0:
		online_match_interrupted.emit("本地玩家不在锁定的开局名单中。")
		return
	var authority := _session.get_role() == LowpolyOnlineSession.NetworkRole.HOST
	if not _director.start_network_run(match_data, _session.get_local_user_id(), authority):
		online_match_interrupted.emit("无法创建联机玩法状态。")
		return
	_running = true
	_input_sequence = 0
	_input_accumulator = 0.0
	_snapshot_accumulator = 0.0
	_checkpoint_accumulator = 0.0
	_snapshot_frame_index = 0
	_authority_snapshot_received = authority
	_sync_retry_accumulator = 0.0
	_last_snapshot_received_msec = 0
	_snapshots_received = 0
	_entity_batches_received = 0
	_latest_inputs.clear()
	_pending_local_inputs.clear()
	for value: Variant in match_data.get("roster", []):
		if value is Dictionary:
			_latest_inputs[int((value as Dictionary).get("slot", -1))] = Vector2.ZERO
	match_started.emit(_local_slot, int(_session.get_role()))


func _send_local_input(input_vector: Vector2) -> void:
	_input_sequence += 1
	var payload := {
		"slot": _local_slot,
		"sequence": _input_sequence,
		"vector": [snappedf(input_vector.x, 0.001), snappedf(input_vector.y, 0.001)],
	}
	if _session.send_to_host(&"input", payload, false):
		queue_predicted_input_for_test(_input_sequence, input_vector, 1.0 / _input_rate_hz)
		if _pending_local_inputs.size() > 128:
			_pending_local_inputs.pop_front()


func _update_host_replication(delta: float) -> void:
	_snapshot_accumulator += delta
	_checkpoint_accumulator += delta
	if _snapshot_accumulator >= 1.0 / _snapshot_rate_hz:
		_snapshot_accumulator = fmod(_snapshot_accumulator, 1.0 / _snapshot_rate_hz)
		_send_tailored_snapshots()
	if _checkpoint_accumulator >= 1.0 / _checkpoint_rate_hz:
		_checkpoint_accumulator = fmod(_checkpoint_accumulator, 1.0 / _checkpoint_rate_hz)
		_last_checkpoint = _director.make_authority_checkpoint()
		_last_checkpoint["network"] = {
			"authority_epoch": _session.get_authority_epoch(),
			"reliable_event_sequence": _session.get_reliable_send_sequence(),
			"last_input_sequences": _last_input_sequences.duplicate(true),
		}
		_session.set_cached_checkpoint(_last_checkpoint)
		_session.broadcast(&"checkpoint", {"checkpoint": _last_checkpoint})


func _send_tailored_snapshots() -> void:
	_snapshot_frame_index += 1
	var match_data := _session.get_match_data()
	for value: Variant in match_data.get("roster", []):
		if not value is Dictionary:
			continue
		var member: Dictionary = value
		var user_id := String(member.get("user_id", ""))
		var slot := int(member.get("slot", -1))
		if user_id.is_empty() or user_id == _session.get_local_user_id():
			continue
		if (
			String(member.get("platform", "")) == "android"
			and _snapshot_frame_index % MOBILE_SNAPSHOT_DIVISOR != 0
		):
			continue
		var target_player := _director.get_player_for_slot(slot)
		if target_player == null or target_player.network_removed:
			continue
		var snapshot := _director.make_network_snapshot(target_player.global_position, _interest_radius)
		snapshot["ack_input_sequence"] = int(_last_input_sequences.get(user_id, 0))
		_send_entity_delta(user_id, snapshot)
		var core_snapshot := snapshot.duplicate(false)
		for category: String in ["enemies", "player_projectiles", "enemy_projectiles", "pickups"]:
			core_snapshot.erase(category)
		_session.send_message(user_id, &"state_snapshot", core_snapshot, false)
		_send_entity_batches(user_id, snapshot)


func _send_entity_batches(user_id: String, snapshot: Dictionary) -> void:
	var tick := int(snapshot.get("tick", 0))
	for category: String in ["enemies", "player_projectiles", "enemy_projectiles", "pickups"]:
		var states: Array = snapshot.get(category, [])
		for begin: int in range(0, states.size(), ENTITY_BATCH_SIZE):
			var batch: Array = states.slice(begin, mini(begin + ENTITY_BATCH_SIZE, states.size()))
			_session.send_message(user_id, &"entity_snapshot", {
				"tick": tick,
				"category": category,
				"states": batch,
			}, false)


func _send_entity_delta(user_id: String, snapshot: Dictionary) -> void:
	var current: Dictionary = {}
	var state_by_id: Dictionary = {}
	for category: String in ["enemies", "player_projectiles", "enemy_projectiles", "pickups"]:
		for value: Variant in snapshot.get(category, []):
			if not value is Dictionary:
				continue
			var entity_id := int((value as Dictionary).get("entity_id", 0))
			if entity_id <= 0:
				continue
			current[entity_id] = category
			state_by_id[entity_id] = (value as Dictionary).duplicate(true)
	var previous: Dictionary = _known_entities_by_user.get(user_id, {})
	var spawned: Array[Dictionary] = []
	var removed: Array[int] = []
	for entity_value: Variant in current.keys():
		if not previous.has(entity_value):
			spawned.append({
				"category": String(current[entity_value]),
				"state": state_by_id[entity_value],
			})
	for entity_value: Variant in previous.keys():
		if not current.has(entity_value):
			removed.append(int(entity_value))
	if not spawned.is_empty() or not removed.is_empty():
		if not _session.send_message(user_id, &"entity_delta", {
			"tick": int(snapshot.get("tick", 0)),
			"spawned": spawned,
			"removed": removed,
		}):
			return
	_known_entities_by_user[user_id] = current


func _on_network_message(sender_user_id: String, kind: StringName, payload: Dictionary) -> void:
	if _session.get_role() == LowpolyOnlineSession.NetworkRole.HOST:
		_handle_host_message(sender_user_id, kind, payload)
	else:
		_handle_client_message(sender_user_id, kind, payload)


func _handle_host_message(sender_user_id: String, kind: StringName, payload: Dictionary) -> void:
	if _director.get_slot_for_user(sender_user_id) < 0:
		return
	match kind:
		&"input":
			_accept_input(sender_user_id, payload)
		&"upgrade_choice":
			_accept_upgrade_choice(sender_user_id, payload)
		&"ping":
			_session.send_message(sender_user_id, &"pong", {
				"client_time": int(payload.get("client_time", 0)),
			})
		&"sync_hello", &"reconnect_hello":
			_session.mark_peer_reconnected(sender_user_id)
			_director.set_network_player_connected(sender_user_id, true)
			_send_initial_sync(sender_user_id)
		_:
			# Clients cannot submit damage, spawns, health, checkpoints or results.
			return


func _handle_client_message(sender_user_id: String, kind: StringName, payload: Dictionary) -> void:
	if sender_user_id != String(_session.get_match_data().get("host_user_id", "")):
		return
	match kind:
		&"snapshot":
			_apply_client_snapshot(payload)
		&"initial_snapshot":
			_apply_client_snapshot(payload)
		&"state_snapshot":
			if _director.apply_network_core_snapshot(payload, true):
				_mark_authority_snapshot_received()
		&"entity_snapshot":
			if _director.apply_network_entity_batch(
				StringName(payload.get("category", "")),
				payload.get("states", []),
				int(payload.get("tick", 0))
			):
				_entity_batches_received += 1
		&"entity_delta":
			_director.apply_network_entity_delta(payload)
		&"upgrade_offer":
			if int(payload.get("slot", -1)) == _local_slot:
				var options: Array[Dictionary] = []
				for value: Variant in payload.get("options", []):
					if value is Dictionary:
						options.append((value as Dictionary).duplicate(true))
				upgrade_offer_received.emit(options)
		&"checkpoint":
			_last_checkpoint = (payload.get("checkpoint", {}) as Dictionary).duplicate(true)
			_session.set_cached_checkpoint(_last_checkpoint)
		&"player_removed":
			_director.remove_network_player(String(payload.get("user_id", "")))
		&"run_finished":
			_director.apply_network_result(bool(payload.get("victory", false)), payload.get("summary", {}))
		&"pong":
			var now := Time.get_ticks_msec()
			var started := int(payload.get("client_time", now))
			latency_changed.emit(maxi(0, now - started))
		_:
			return


func _apply_client_snapshot(snapshot: Dictionary) -> void:
	var acknowledged := int(snapshot.get("ack_input_sequence", 0))
	while (
		not _pending_local_inputs.is_empty()
		and int(_pending_local_inputs.front().get("sequence", 0)) <= acknowledged
	):
		_pending_local_inputs.pop_front()
	var replay_inputs := _pending_local_inputs.duplicate(true)
	# Reset the owned character to the host result, then replay only unacknowledged
	# inputs. This is the rollback/correction half of client-side prediction.
	if not _director.apply_network_snapshot(snapshot, true):
		return
	_mark_authority_snapshot_received()
	_pending_local_inputs = replay_inputs.duplicate(true)
	for pending: Dictionary in replay_inputs:
		var pending_vector: Vector2 = pending.get("vector", Vector2.ZERO)
		_director.predict_local_player(
			float(pending.get("delta", 0.0)),
			pending_vector
		)


func _accept_input(sender_user_id: String, payload: Dictionary) -> void:
	if var_to_bytes(payload).size() > MAX_INPUT_PAYLOAD_BYTES:
		return
	var slot := _director.get_slot_for_user(sender_user_id)
	if slot < 0 or int(payload.get("slot", -1)) != slot:
		return
	var sequence := int(payload.get("sequence", 0))
	if sequence <= int(_last_input_sequences.get(sender_user_id, 0)):
		return
	if not _consume_input_rate(sender_user_id):
		return
	var values: Array = payload.get("vector", [])
	if values.size() != 2:
		return
	var input_vector := Vector2(float(values[0]), float(values[1]))
	if not is_finite(input_vector.x) or not is_finite(input_vector.y) or input_vector.length() > 1.001:
		return
	_last_input_sequences[sender_user_id] = sequence
	_latest_inputs[slot] = input_vector.limit_length(1.0)


func _accept_upgrade_choice(sender_user_id: String, payload: Dictionary) -> void:
	var slot := _director.get_slot_for_user(sender_user_id)
	if slot < 0 or int(payload.get("slot", -1)) != slot:
		return
	var upgrade_id := StringName(payload.get("upgrade_id", ""))
	_director.choose_network_upgrade(slot, upgrade_id)


func _consume_input_rate(user_id: String) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	var window: Dictionary = _input_rate_windows.get(user_id, {"start": now, "count": 0})
	if now - float(window.get("start", now)) >= 1.0:
		window = {"start": now, "count": 0}
	window["count"] = int(window.get("count", 0)) + 1
	_input_rate_windows[user_id] = window
	return int(window["count"]) <= MAX_INPUT_PACKETS_PER_SECOND


func _on_network_upgrade_requested(
	slot: int,
	user_id: String,
	options: Array[Dictionary]
) -> void:
	if not _running or _session.get_role() != LowpolyOnlineSession.NetworkRole.HOST:
		return
	if user_id == _session.get_local_user_id():
		upgrade_offer_received.emit(options)
	else:
		_session.send_message(user_id, &"upgrade_offer", {
			"slot": slot,
			"options": options,
		})


func _on_participant_connection_changed(user_id: String, connected: bool, _remaining: float) -> void:
	if not _running:
		return
	_director.set_network_player_connected(user_id, connected)
	if connected and _session.get_role() == LowpolyOnlineSession.NetworkRole.CLIENT:
		_session.send_to_host(&"sync_hello", {"slot": _local_slot})


func _send_initial_sync(user_id: String) -> void:
	var slot := _director.get_slot_for_user(user_id)
	var target_player := _director.get_player_for_slot(slot)
	if slot < 0 or target_player == null or target_player.network_removed:
		return
	# Do not mark the entity set as known until normal replication runs. The next
	# delta therefore repeats authoritative spawns after this reliable baseline.
	var snapshot := _director.make_network_snapshot(target_player.global_position, _interest_radius)
	snapshot["ack_input_sequence"] = int(_last_input_sequences.get(user_id, 0))
	_session.send_message(user_id, &"initial_snapshot", snapshot)
	if not _last_checkpoint.is_empty():
		_session.send_message(user_id, &"checkpoint", {"checkpoint": _last_checkpoint})


func _mark_authority_snapshot_received() -> void:
	_authority_snapshot_received = true
	_sync_retry_accumulator = 0.0
	_last_snapshot_received_msec = Time.get_ticks_msec()
	_snapshots_received += 1


func _on_participant_grace_expired(user_id: String) -> void:
	if not _running or _session.get_role() != LowpolyOnlineSession.NetworkRole.HOST:
		return
	_director.remove_network_player(user_id)
	_session.broadcast(&"player_removed", {"user_id": user_id})


func _on_host_migration_started(new_host_user_id: String, _epoch: int) -> void:
	migration_notice.emit(true, "正在迁移房主：%s" % new_host_user_id.left(8))
	_director.set_network_authority(false)


func _on_host_takeover_requested(checkpoint: Dictionary, _epoch: int) -> void:
	if checkpoint.is_empty() or not _director.restore_authority_checkpoint(checkpoint):
		_session.abort_online_match("联机中断：没有可用的房主迁移检查点。")
		return
	_last_checkpoint = checkpoint.duplicate(true)
	_session.adopt_checkpoint_network_metadata(checkpoint)
	var network_metadata: Dictionary = checkpoint.get("network", {})
	_last_input_sequences = (
		(network_metadata.get("last_input_sequences", {}) as Dictionary).duplicate(true)
	)
	for slot_value: Variant in _latest_inputs.keys():
		_latest_inputs[slot_value] = Vector2.ZERO
	_director.set_network_authority(true)
	_session.complete_host_migration(checkpoint)


func _on_host_migration_finished(_epoch: int) -> void:
	_director.set_network_authority(_session.get_role() == LowpolyOnlineSession.NetworkRole.HOST)
	migration_notice.emit(false, "房主迁移完成。")


func _on_run_finished(victory: bool, summary: Dictionary) -> void:
	if not _running or _session.get_role() != LowpolyOnlineSession.NetworkRole.HOST:
		return
	_session.broadcast(&"run_finished", {
		"victory": victory,
		"summary": summary,
	})


func _update_ping(delta: float) -> void:
	if _session.get_role() != LowpolyOnlineSession.NetworkRole.CLIENT:
		return
	_ping_accumulator += delta
	if _ping_accumulator >= 2.0:
		_ping_accumulator = fmod(_ping_accumulator, 2.0)
		_session.send_to_host(&"ping", {"client_time": Time.get_ticks_msec()})


func _on_session_error(message: String) -> void:
	if _running:
		online_match_interrupted.emit(message)


static func _slot_for_user(match_data: Dictionary, user_id: String) -> int:
	for value: Variant in match_data.get("roster", []):
		if value is Dictionary and String((value as Dictionary).get("user_id", "")) == user_id:
			return int((value as Dictionary).get("slot", -1))
	return -1
