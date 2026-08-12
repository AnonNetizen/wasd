extends RefCounted
## Deterministic replay-only setup that discovers two stations and returns to source.


static func prepare(run_loop: Node) -> Dictionary:
	var manager: Node = _find_node_by_name(run_loop, "ModuleWorldManager")
	var player: Node2D = _find_node_by_name(run_loop, "Player") as Node2D
	if manager == null or player == null:
		return {}
	var stations: Array[Dictionary] = []
	var raw_stations: Dictionary = run_loop.get("_teleporter_stations") as Dictionary
	for raw_station: Variant in raw_stations.values():
		if raw_station is Dictionary:
			stations.append((raw_station as Dictionary).duplicate(true))
	stations.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("station_number", 0)) < int(right.get("station_number", 0))
	)
	if stations.size() != 3:
		return {}
	for station_index: int in [0, 1, 0]:
		var station: Dictionary = stations[station_index]
		var position: Vector2 = _vector(station.get("world_position", {}))
		if not bool(player.call("teleport_to", position)):
			return {}
		var stream_change: Dictionary = manager.call("tick", position)
		run_loop.call("_handle_module_stream_change", stream_change)
		var module_coord: Vector2i = _coord(station.get("module_coord", {}))
		var state: Dictionary = manager.call("slot_state", module_coord)
		state["enemy_snapshots"] = []
		state["enemy_encounter"] = {"state": "cleared"}
		manager.call("set_slot_state", module_coord, state)
	return {
		"source_station_id": String(stations[0].get("station_id", "")),
		"destination_station_id": String(stations[1].get("station_id", "")),
	}


static func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, node_name)
		if found != null:
			return found
	return null


static func _coord(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i(-1, -1)
	var data: Dictionary = value as Dictionary
	return Vector2i(int(data.get("x", -1)), int(data.get("y", -1)))


static func _vector(value: Variant) -> Vector2:
	if not value is Dictionary:
		return Vector2(INF, INF)
	var data: Dictionary = value as Dictionary
	return Vector2(float(data.get("x", INF)), float(data.get("y", INF)))
