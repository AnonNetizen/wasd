extends Node
## Headless three-station teleporter network transaction smoke.


const MODULE_PLACEMENT_TYPES := preload(
	"res://scripts/contracts/module_placement_types.gd"
)
const TELEPORT_CHOICE_OUTCOMES := preload(
	"res://scripts/contracts/teleport_choice_outcomes.gd"
)

const BOOT_FRAMES: int = 60

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var run_loop: Node = await _wait_for_run_loop()
	_expect(run_loop != null, "teleporter smoke should find the gameplay run loop")
	if run_loop == null:
		_finish()
		return
	var manager: Node = _find_node_by_name(run_loop, "ModuleWorldManager")
	var player: Node2D = _find_node_by_name(run_loop, "Player") as Node2D
	_expect(manager != null, "teleporter smoke should find ModuleWorldManager")
	_expect(player != null, "teleporter smoke should find Player")
	if manager == null or player == null:
		_finish()
		return

	var stations: Array[Dictionary] = _sorted_stations(run_loop)
	_expect(stations.size() == 3, "formal world should index exactly three teleporters")
	_expect(_stations_have_stable_ids_and_numbers(stations), "stations should use row-major numbers and stable ids")
	_expect(_stations_respect_distance(stations, 4), "stations should remain at least four Manhattan modules apart")
	_expect(_placements_are_protected_teleporters(manager, stations), "every station should resolve to the strict teleporter placement")
	if stations.size() != 3:
		_finish()
		return

	var minimap: Node = run_loop.get_node_or_null("GameplayHud/Root/ModuleMinimap")
	_expect(minimap != null, "teleporter smoke should find the HUD minimap")
	if minimap != null:
		_expect(
			(minimap.call("interactable_markers") as Array).size()
			== _expected_minimap_marker_count(manager),
			"HUD minimap should expose every supported assignment marker before exploration"
		)
		for station: Dictionary in stations:
			var station_coord: Vector2i = _coord(station.get("module_coord", {}))
			_expect(
				(minimap.call("marker_kinds_at", station_coord) as Array)
				== [ModuleMinimap.MarkerKind.TELEPORTER],
				"every teleporter module should be marked before exploration"
			)
	await _visit_station(run_loop, manager, player, stations[0])
	_expect(
		not bool(run_loop.call("_show_teleport_choice_panel", String(stations[0].get("station_id", "")))),
		"one discovered station should not open the destination panel"
	)
	for station_index: int in range(1, stations.size()):
		await _visit_station(run_loop, manager, player, stations[station_index])
	await _visit_station(run_loop, manager, player, stations[0])
	if minimap != null:
		for station: Dictionary in stations:
			var station_coord: Vector2i = _coord(station.get("module_coord", {}))
			_expect(
				(minimap.call("marker_kinds_at", station_coord) as Array)
				== [ModuleMinimap.MarkerKind.TELEPORTER],
				"each explored teleporter module should keep its minimap marker"
			)

	var source: Dictionary = stations[0]
	var destination: Dictionary = stations[1]
	var source_coord: Vector2i = _coord(source.get("module_coord", {}))
	var destination_coord: Vector2i = _coord(destination.get("module_coord", {}))
	var source_state: Dictionary = manager.call("slot_state", source_coord)
	source_state["enemy_encounter"] = {
		"state": "telegraphing",
		"remaining_telegraph": 1.0,
	}
	manager.call("set_slot_state", source_coord, source_state)
	_expect(bool(run_loop.call("_module_slot_has_hostile_pressure", source_coord)), "source telegraph should block teleport use")
	_clear_slot_pressure(manager, source_coord)

	source_state = manager.call("slot_state", source_coord)
	source_state["enemy_snapshots"] = [{"enemy_id": "fixture"}]
	manager.call("set_slot_state", source_coord, source_state)
	_expect(bool(run_loop.call("_module_slot_has_hostile_pressure", source_coord)), "source enemy snapshots should block teleport use")
	_clear_slot_pressure(manager, source_coord)

	var active_world: Node = player.get_parent()
	var live_enemy := Node2D.new()
	live_enemy.name = "TeleporterSmokeLiveEnemy"
	live_enemy.add_to_group("active_enemies")
	live_enemy.set_meta("module_slot", "%d,%d" % [source_coord.x, source_coord.y])
	active_world.add_child(live_enemy)
	_expect(bool(run_loop.call("_module_slot_has_hostile_pressure", source_coord)), "source live enemy should block teleport use")
	live_enemy.queue_free()
	await get_tree().process_frame

	var target_state: Dictionary = manager.call("slot_state", destination_coord)
	target_state["enemy_snapshots"] = [{"enemy_id": "fixture"}]
	manager.call("set_slot_state", destination_coord, target_state)
	var choice_tick_before: int = GameClock.tick()
	_expect(
		bool(run_loop.call("_show_teleport_choice_panel", String(source.get("station_id", "")))),
		"visited destinations should open the non-pausing destination panel"
	)
	var panel: Node = run_loop.get("_teleport_choice_panel") as Node
	for _frame: int in range(3):
		await get_tree().physics_frame
	_expect(GameState.is_state(GameState.PLAYING), "destination choice should remain in PLAYING")
	_expect(
		InputService.non_pausing_ui_capture_active(),
		"destination choice should capture gameplay input without changing GameState"
	)
	_expect(
		GameClock.tick() > choice_tick_before,
		"destination choice should keep gameplay time running"
	)
	_expect(
		panel != null
		and (panel.call("destination_ids") as Array).size() == 2
		and not (panel.call("destination_ids") as Array).has(String(source.get("station_id", ""))),
		"panel should list only the other two discovered stations"
	)
	_expect(
		not (run_loop.call(
			"_prepare_teleport_transaction",
			String(source.get("station_id", "")),
			String(destination.get("station_id", ""))
		) as Dictionary).is_empty(),
		"dangerous target snapshots should not block arrival"
	)
	_clear_slot_pressure(manager, destination_coord)

	var position_before_failure: Vector2 = player.global_position
	source_state = manager.call("slot_state", source_coord)
	source_state["enemy_snapshots"] = [{"enemy_id": "fixture"}]
	manager.call("set_slot_state", source_coord, source_state)
	_expect(
		not bool(run_loop.call("apply_replay_teleport_choice", {
			"outcome": TELEPORT_CHOICE_OUTCOMES.TELEPORTED,
			"source_station_id": String(source.get("station_id", "")),
			"destination_station_id": String(destination.get("station_id", "")),
		})),
		"commit-time source pressure should reject the semantic choice"
	)
	_expect(player.global_position == position_before_failure, "failed teleport should not move the player")
	_expect(GameState.is_state(GameState.PLAYING), "failed teleport should remain selectable in PLAYING")
	_clear_slot_pressure(manager, source_coord)

	var replay_payload: Dictionary = {
		"outcome": TELEPORT_CHOICE_OUTCOMES.TELEPORTED,
		"source_station_id": String(source.get("station_id", "")),
		"destination_station_id": String(destination.get("station_id", "")),
	}
	_expect(
		bool(run_loop.call("apply_replay_teleport_choice", replay_payload)),
		"valid semantic destination should start the teleport transaction"
	)
	for _frame: int in range(180):
		if not bool(run_loop.call("replay_teleport_choice_pending")):
			break
		await get_tree().process_frame
	_expect(
		bool(run_loop.call("replay_teleport_choice_completed", replay_payload)),
		"non-zero replay fade should complete before replay summary state is accepted"
	)
	var destination_position: Vector2 = _vector(destination.get("world_position", {}))
	_expect(player.global_position == destination_position, "successful teleport should use the target platform cell")
	_expect(manager.call("current_module_coord") as Vector2i == destination_coord, "successful teleport should switch the current module")
	_expect(GameState.is_state(GameState.PLAYING), "fade-in completion should restore PLAYING")
	var summary: Dictionary = manager.call("debug_summary")
	_expect(int(summary.get("active_count", 0)) <= 12, "teleport streaming should respect the 3x3 plus pinned chunk cap")
	var snapshot: Dictionary = run_loop.call("create_run_snapshot")
	_expect(int(snapshot.get("schema_version", 0)) == 20, "teleporter run snapshot should use Run v20")

	await _visit_station(run_loop, manager, player, source)
	_expect(
		bool(run_loop.call("_show_teleport_choice_panel", String(source.get("station_id", "")))),
		"resume fixture should reopen the visited source station"
	)
	var choice_restore: Dictionary = run_loop.call("_ui_restore_snapshot")
	_expect(
		String(choice_restore.get("state", "")) == "teleport_choice"
		and String(choice_restore.get("source_station_id", ""))
		== String(source.get("station_id", "")),
		"Run v20 should persist the teleport choice source"
	)
	run_loop.call("_show_pause_menu")
	await get_tree().process_frame
	var paused_restore: Dictionary = run_loop.call("_ui_restore_snapshot")
	_expect(
		String(paused_restore.get("state", "")) == "paused"
		and String(paused_restore.get("underlying_state", ""))
		== "teleport_choice"
		and String(paused_restore.get("source_station_id", ""))
		== String(source.get("station_id", "")),
		"paused Run v20 should persist the underlying teleport choice"
	)
	run_loop.call("_on_pause_resume_requested")
	for _frame: int in range(30):
		await get_tree().process_frame
		if (
			GameState.is_state(GameState.PLAYING)
			and run_loop.get("_teleport_choice_panel") != null
		):
			break
	_expect(
		GameState.is_state(GameState.PLAYING)
		and run_loop.get("_teleport_choice_panel") != null,
		"closing pause should reveal the PLAYING teleport choice overlay"
	)
	_expect(
		bool(run_loop.call("apply_replay_teleport_choice", {
			"outcome": TELEPORT_CHOICE_OUTCOMES.CANCELLED,
			"source_station_id": String(source.get("station_id", "")),
		})),
		"semantic teleport cancellation should restore play"
	)
	_expect(
		bool(run_loop.call(
			"_show_teleport_choice_panel",
			String(source.get("station_id", ""))
		)),
		"death-during-fade fixture should reopen the source station"
	)
	_expect(
		bool(run_loop.call("_begin_teleport_choice", String(
			destination.get("station_id", "")
		), false)),
		"death-during-fade fixture should start a valid transaction"
	)
	for _frame: int in range(120):
		if player.global_position == destination_position:
			break
		await get_tree().process_frame
	_expect(
		player.global_position == destination_position
		and bool(run_loop.call("replay_teleport_choice_pending")),
		"teleport should commit before fade-in completes"
	)
	_expect(
		InputService.non_pausing_ui_capture_active(),
		"fade-in should keep gameplay input captured after the choice panel closes"
	)
	player.call("debug_set_life", 0.0)
	for _frame: int in range(120):
		if not bool(run_loop.call("replay_teleport_choice_pending")):
			break
		await get_tree().process_frame
	_expect(
		GameState.is_state(GameState.GAME_OVER),
		"death during fade-in should not be overwritten by PLAYING"
	)

	_finish()


func _wait_for_run_loop() -> Node:
	for _frame: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if run_loop != null and GameState.is_state(GameState.PLAYING):
			return run_loop
	return null


func _sorted_stations(run_loop: Node) -> Array[Dictionary]:
	var stations: Array[Dictionary] = []
	var raw_stations: Dictionary = run_loop.get("_teleporter_stations") as Dictionary
	for raw_station: Variant in raw_stations.values():
		if raw_station is Dictionary:
			stations.append((raw_station as Dictionary).duplicate(true))
	stations.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("station_number", 0)) < int(right.get("station_number", 0))
	)
	return stations


func _stations_have_stable_ids_and_numbers(stations: Array[Dictionary]) -> bool:
	var previous_coord := Vector2i(-1, -1)
	for index: int in range(stations.size()):
		var station: Dictionary = stations[index]
		var module_coord: Vector2i = _coord(station.get("module_coord", {}))
		var local_cell: Vector2i = _coord(station.get("cell", {}))
		var expected_id: String = "teleporter_%d_%d_%d_%d" % [
			module_coord.x,
			module_coord.y,
			local_cell.x,
			local_cell.y,
		]
		if int(station.get("station_number", 0)) != index + 1:
			return false
		if String(station.get("station_id", "")) != expected_id:
			return false
		if index > 0 and (
			module_coord.y < previous_coord.y
			or (
				module_coord.y == previous_coord.y
				and module_coord.x < previous_coord.x
			)
		):
			return false
		previous_coord = module_coord
	return true


func _stations_respect_distance(stations: Array[Dictionary], minimum: int) -> bool:
	for left_index: int in range(stations.size()):
		var left: Vector2i = _coord(stations[left_index].get("module_coord", {}))
		for right_index: int in range(left_index + 1, stations.size()):
			var right: Vector2i = _coord(stations[right_index].get("module_coord", {}))
			if absi(left.x - right.x) + absi(left.y - right.y) < minimum:
				return false
	return true


func _placements_are_protected_teleporters(manager: Node, stations: Array[Dictionary]) -> bool:
	for station: Dictionary in stations:
		var module_coord: Vector2i = _coord(station.get("module_coord", {}))
		var placements: Array[Dictionary] = manager.call("placements_at", module_coord)
		var found: bool = false
		for placement: Dictionary in placements:
			if String(placement.get("type", "")) != MODULE_PLACEMENT_TYPES.MODULE_PLACE_TELEPORTER:
				continue
			found = (
				_coord(placement.get("cell", {})) == Vector2i(5, 5)
				and float(placement.get("interaction_radius", 0.0)) == 180.0
			)
		if not found:
			return false
		var empty_positions: Array[Vector2] = manager.call("empty_floor_positions_at", module_coord)
		if empty_positions.has(_vector(station.get("world_position", {}))):
			return false
	return true


func _expected_minimap_marker_count(manager: Node) -> int:
	var count: int = 0
	for y: int in range(ModuleMinimap.DEFAULT_ROWS):
		for x: int in range(ModuleMinimap.DEFAULT_COLUMNS):
			for placement: Dictionary in manager.call(
				"placements_at",
				Vector2i(x, y)
			):
				if String(placement.get("type", "")) in [
					MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE,
					MODULE_PLACEMENT_TYPES.MODULE_PLACE_WORLD_EVENT,
					MODULE_PLACEMENT_TYPES.MODULE_PLACE_TELEPORTER,
				]:
					count += 1
	return count


func _visit_station(run_loop: Node, manager: Node, player: Node2D, station: Dictionary) -> void:
	var position: Vector2 = _vector(station.get("world_position", {}))
	player.call("teleport_to", position)
	var stream_change: Dictionary = manager.call("tick", position)
	run_loop.call("_handle_module_stream_change", stream_change)
	_clear_slot_pressure(manager, _coord(station.get("module_coord", {})))
	await get_tree().process_frame


func _clear_slot_pressure(manager: Node, coord: Vector2i) -> void:
	var state: Dictionary = manager.call("slot_state", coord)
	state["enemy_snapshots"] = []
	state["enemy_encounter"] = {"state": "cleared"}
	manager.call("set_slot_state", coord, state)


func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, node_name)
		if found != null:
			return found
	return null


func _coord(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i(-1, -1)
	var data: Dictionary = value as Dictionary
	return Vector2i(int(data.get("x", -1)), int(data.get("y", -1)))


func _vector(value: Variant) -> Vector2:
	if not value is Dictionary:
		return Vector2.ZERO
	var data: Dictionary = value as Dictionary
	return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[TeleporterSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[TeleporterSmoke] PASS")
		get_tree().quit(0)
		return
	print("[TeleporterSmoke] FAIL count=%d first=%s" % [_failures.size(), _failures[0]])
	get_tree().quit(1)
