# Doc: docs/代码/room_manager.md
class_name RoomManager
extends Node2D
## F13 手工房间制流程协调点：加载房间序列与房间场景、读取 marker、锁 / 开门、清房检测、切房与快照恢复。
## 由 GameplayRunLoop 在房间 carrier 模式下创建并驱动；对象池生成与战斗结算仍由 GameplayRunLoop 负责，
## RoomManager 只持有房间几何 / 门状态 / 清房计数，不直接 acquire 池节点、不直接走 Combat。

signal room_entered(room_id: String, room_index: int)
signal room_cleared(room_id: String)
signal exit_reached(target_entry_id: String, is_final: bool)

const ROOM_SPAWN_KEY: String = "room"

const DOOR_UNLOCK_RULES := preload("res://scripts/contracts/door_unlock_rules.gd")
const ROOM_CLEAR_CONDITIONS := preload("res://scripts/contracts/room_clear_conditions.gd")

var _sequence: Dictionary = {}
var _rooms_by_id: Dictionary = {}
var _room_index: int = -1
var _current_room_id: String = ""
var _current_clear_condition: String = ROOM_CLEAR_CONDITIONS.ROOM_CLEAR_ALL_ENEMIES
var _room_scene_root: Node2D = null
var _doors: Dictionary = {}
var _enemy_alive: int = 0
var _enemy_spawned_total: int = 0
var _room_cleared: bool = false
var _exit_emitted: bool = false


func configure(sequence: Dictionary, rooms_by_id: Dictionary) -> void:
	_sequence = sequence.duplicate(true)
	_rooms_by_id = rooms_by_id.duplicate(true)
	_room_index = -1
	_current_room_id = ""


func room_count() -> int:
	return _sequence_room_ids().size()


func current_room_id() -> String:
	return _current_room_id


func current_room_index() -> int:
	return _room_index


func is_final_room() -> bool:
	var ids: Array = _sequence_room_ids()
	if _room_index < 0 or _room_index >= ids.size():
		return false
	var final_id: String = String(_sequence.get("final_room_id", ""))
	if not final_id.is_empty():
		return _current_room_id == final_id
	return _room_index == ids.size() - 1


func is_current_room_cleared() -> bool:
	return _room_cleared


## Loads the room scene at the sequence index, mounts it, reads markers and returns
## enter info for GameplayRunLoop to act on. entry_id selects which RoomPlayerStartMarker
## to spawn the player at ("" -> first marker). Marker enemy / hazard data is returned but
## NOT spawned here; the run loop owns pooled spawning.
func enter_room_index(index: int, entry_id: String = "") -> Dictionary:
	_teardown_room_scene()
	var ids: Array = _sequence_room_ids()
	if index < 0 or index >= ids.size():
		push_error("[RoomManager] room index out of range: %d" % index)
		return {}
	var room_id: String = String(ids[index])
	if not _rooms_by_id.has(room_id):
		push_error("[RoomManager] unknown room id: %s" % room_id)
		return {}
	var room_data: Dictionary = _rooms_by_id[room_id]
	var scene_path: String = String(room_data.get("scene_path", ""))
	var packed: Resource = load(scene_path)
	if not packed is PackedScene:
		push_error("[RoomManager] failed to load room scene: %s" % scene_path)
		return {}
	var scene_instance: Node = (packed as PackedScene).instantiate()
	if not scene_instance is Node2D:
		push_error("[RoomManager] room scene root is not Node2D: %s" % scene_path)
		scene_instance.free()
		return {}

	_room_scene_root = scene_instance as Node2D
	add_child(_room_scene_root)

	_room_index = index
	_current_room_id = room_id
	_current_clear_condition = String(room_data.get("clear_condition", ROOM_CLEAR_CONDITIONS.ROOM_CLEAR_ALL_ENEMIES))
	_enemy_alive = 0
	_enemy_spawned_total = 0
	_room_cleared = false
	_exit_emitted = false
	_doors.clear()

	var markers: Dictionary = _collect_markers(_room_scene_root)
	var bounds_layout: Dictionary = _build_bounds_layout(markers, entry_id)
	for door_data: Dictionary in markers["doors"]:
		var door_id: String = String(door_data.get("door_id", ""))
		if door_id.is_empty():
			continue
		var entry: Dictionary = door_data.duplicate(true)
		entry["unlocked"] = String(door_data.get("unlock_rule", "")) == DOOR_UNLOCK_RULES.UNLOCK_OPEN
		_doors[door_id] = entry

	room_entered.emit(_current_room_id, _room_index)
	return {
		"room_id": room_id,
		"clear_condition": _current_clear_condition,
		"bounds_layout": bounds_layout,
		"player_start": bounds_layout.get("player_start", {}),
		"enemy_spawns": markers["enemy_spawns"],
		"hazard_spawns": markers["hazard_spawns"],
	}


func notify_room_enemies_spawned(count: int) -> void:
	if count <= 0:
		return
	_enemy_spawned_total += count
	_enemy_alive += count


func notify_enemy_defeated() -> void:
	_enemy_alive = maxi(_enemy_alive - 1, 0)


## Per-frame room update driven by GameplayRunLoop while PLAYING. Opens exit doors when the
## room is cleared and reports a switch intent when the player reaches an unlocked exit.
func tick(player_position: Vector2) -> Dictionary:
	if _room_scene_root == null or not is_instance_valid(_room_scene_root):
		return {}
	if not _room_cleared and _is_clear_condition_met():
		_room_cleared = true
		_unlock_clear_doors()
		room_cleared.emit(_current_room_id)
	if _room_cleared and not _exit_emitted:
		for door_id: String in _doors.keys():
			var door: Dictionary = _doors[door_id]
			if not bool(door.get("unlocked", false)):
				continue
			var radius: float = maxf(float(door.get("trigger_radius", 96.0)), 1.0)
			if player_position.distance_to(_door_position(door)) <= radius:
				_exit_emitted = true
				var final_room: bool = is_final_room()
				var target_entry_id: String = String(door.get("target_entry_id", ""))
				exit_reached.emit(target_entry_id, final_room)
				return {
					"action": "switch",
					"target_entry_id": target_entry_id,
					"is_final": final_room,
				}
	return {}


func snapshot() -> Dictionary:
	var door_states: Dictionary = {}
	for door_id: String in _doors.keys():
		door_states[door_id] = bool((_doors[door_id] as Dictionary).get("unlocked", false))
	return {
		"sequence_id": String(_sequence.get("id", "")),
		"room_index": _room_index,
		"current_room_id": _current_room_id,
		"clear_condition": _current_clear_condition,
		"enemy_alive": _enemy_alive,
		"enemy_spawned_total": _enemy_spawned_total,
		"cleared": _room_cleared,
		"door_states": door_states,
	}


## Applies saved counters and door states after enter_room_index has rebuilt the room scene.
## Live enemies / hazards are restored separately by GameplayRunLoop from the run payload.
func restore_state(state: Dictionary) -> void:
	_enemy_alive = maxi(int(state.get("enemy_alive", 0)), 0)
	_enemy_spawned_total = maxi(int(state.get("enemy_spawned_total", 0)), 0)
	_room_cleared = bool(state.get("cleared", false))
	_exit_emitted = false
	var saved_doors: Variant = state.get("door_states", {})
	if not saved_doors is Dictionary:
		return
	for door_key: Variant in (saved_doors as Dictionary).keys():
		var door_id: String = String(door_key)
		if not _doors.has(door_id):
			continue
		var door: Dictionary = _doors[door_id]
		door["unlocked"] = bool((saved_doors as Dictionary)[door_key])
		_doors[door_id] = door


func debug_doors() -> Dictionary:
	var result: Dictionary = {}
	for door_id: String in _doors.keys():
		var door: Dictionary = _doors[door_id]
		result[door_id] = {
			"position": _dictionary_or_empty(door.get("position", {})),
			"unlocked": bool(door.get("unlocked", false)),
			"target_entry_id": String(door.get("target_entry_id", "")),
		}
	return result


func _sequence_room_ids() -> Array:
	var ids: Variant = _sequence.get("room_ids", [])
	if ids is Array:
		return ids as Array
	return []


func _is_clear_condition_met() -> bool:
	if _current_clear_condition == ROOM_CLEAR_CONDITIONS.ROOM_CLEAR_NONE:
		return true
	return _enemy_alive <= 0


func _unlock_clear_doors() -> void:
	for door_id: String in _doors.keys():
		var door: Dictionary = _doors[door_id]
		if String(door.get("unlock_rule", "")) == DOOR_UNLOCK_RULES.UNLOCK_ON_CLEAR:
			door["unlocked"] = true
			_doors[door_id] = door


func _door_position(door: Dictionary) -> Vector2:
	var raw: Variant = door.get("position", {})
	if not raw is Dictionary:
		return Vector2.ZERO
	var pos: Dictionary = raw as Dictionary
	return Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))


func _select_player_start(starts: Array, entry_id: String) -> Dictionary:
	for raw: Variant in starts:
		if not raw is Dictionary:
			continue
		var start: Dictionary = raw as Dictionary
		if not entry_id.is_empty() and String(start.get("entry_id", "")) == entry_id:
			return _dictionary_or_empty(start.get("position", {}))
	if not starts.is_empty() and starts[0] is Dictionary:
		return _dictionary_or_empty((starts[0] as Dictionary).get("position", {}))
	return {"x": 0.0, "y": 0.0}


func _build_bounds_layout(markers: Dictionary, entry_id: String) -> Dictionary:
	var bounds_data: Dictionary = {}
	var room_root: Variant = markers.get("room_root", null)
	if room_root != null and (room_root as Object).has_method("to_bounds_data"):
		bounds_data = (room_root as Object).call("to_bounds_data")
	return {
		"id": "room_%s" % _current_room_id,
		"bounds": bounds_data.get("bounds", {"width": 1280.0, "height": 1280.0}),
		"grid": bounds_data.get("grid", {"cell_width": 160.0, "cell_height": 160.0}),
		"player_start": _select_player_start(markers["player_starts"], entry_id),
		"safe_radius": 0.0,
		"enemy_spawn_margin": 128.0,
	}


func _collect_markers(root: Node) -> Dictionary:
	var result: Dictionary = {
		"room_root": null,
		"player_starts": [],
		"doors": [],
		"enemy_spawns": [],
		"hazard_spawns": [],
	}
	_collect_markers_recursive(root, result)
	return result


func _collect_markers_recursive(node: Node, result: Dictionary) -> void:
	if node is RoomRoot:
		result["room_root"] = node
	elif node is RoomPlayerStartMarker:
		(result["player_starts"] as Array).append((node as RoomPlayerStartMarker).to_data())
	elif node is RoomDoorMarker:
		(result["doors"] as Array).append((node as RoomDoorMarker).to_data())
	elif node is RoomEnemySpawnMarker:
		(result["enemy_spawns"] as Array).append((node as RoomEnemySpawnMarker).to_data())
	elif node is RoomHazardMarker:
		(result["hazard_spawns"] as Array).append((node as RoomHazardMarker).to_data())
	for child: Node in node.get_children():
		_collect_markers_recursive(child, result)


func _teardown_room_scene() -> void:
	if _room_scene_root != null and is_instance_valid(_room_scene_root):
		_room_scene_root.queue_free()
	_room_scene_root = null


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}
