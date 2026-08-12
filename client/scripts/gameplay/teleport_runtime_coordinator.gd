# Doc: docs/代码/gameplay_runtime.md
class_name TeleportRuntimeCoordinator
extends Node


const MODULE_PLACEMENT_TYPES := preload(
	"res://scripts/contracts/module_placement_types.gd"
)
const TELEPORT_CHOICE_OUTCOMES := preload(
	"res://scripts/contracts/teleport_choice_outcomes.gd"
)
const TELEPORT_CHOICE_PANEL_SCENE := preload(
	"res://scenes/ui/teleport_choice_panel.tscn"
)
const TELEPORT_FADE_OVERLAY_SCENE := preload(
	"res://scenes/ui/teleport_fade_overlay.tscn"
)
const TELEPORTER_INTERACTABLE_SCENE := preload(
	"res://scenes/gameplay/teleporter_interactable.tscn"
)
const MODULE_ENCOUNTER_STATE_TELEGRAPHING: String = "telegraphing"


class Bindings extends RefCounted:
	var player_port: Callable = Callable()
	var module_world_port: Callable = Callable()
	var ui_port: Callable = Callable()
	var record_port: Callable = Callable()
	var active_world_port: Callable = Callable()
	var camera_port: Callable = Callable()
	var hud_port: Callable = Callable()
	var module_definition_port: Callable = Callable()
	var technical_slice_port: Callable = Callable()
	var pause_menu_port: Callable = Callable()
	var stream_change_port: Callable = Callable()
	var encounter_vfx_port: Callable = Callable()
	var refresh_hud_port: Callable = Callable()
	var module_slot_key_port: Callable = Callable()
	var interaction_refresh_port: Callable = Callable()
	var pause_port: Callable = Callable()
	var active_entity_port: Callable = Callable()
	var dictionary_port: Callable = Callable()
	var array_port: Callable = Callable()
	var vector_port: Callable = Callable()
	var vector2i_port: Callable = Callable()
	var coord_dictionary_port: Callable = Callable()
	var vector_dictionary_port: Callable = Callable()


var bindings: Bindings = null
var choice_panel: CanvasLayer = null
var fade_overlay: CanvasLayer = null
var source_station_id: String = ""
var transaction_active: bool = false
var module_station_ids: Dictionary = {}
var nodes: Dictionary = {}
var stations: Dictionary = {}


func configure(value: Bindings) -> void:
	bindings = value


func clear_state() -> void:
	choice_panel = null
	fade_overlay = null
	source_station_id = ""
	transaction_active = false
	module_station_ids.clear()
	nodes.clear()
	stations.clear()


var _active_world: Node2D:
	get:
		return bindings.active_world_port.call() as Node2D
var _camera_controller: Node2D:
	get:
		return bindings.camera_port.call() as Node2D
var _hud: CanvasLayer:
	get:
		return bindings.hud_port.call() as CanvasLayer
var _module_world_definition: Dictionary:
	get:
		return bindings.module_definition_port.call() as Dictionary
var _module_world_manager: Node2D:
	get:
		return bindings.module_world_port.call() as Node2D
var _module_world_technical_slice: bool:
	get:
		return bool(bindings.technical_slice_port.call())
var _pause_menu: CanvasLayer:
	get:
		return bindings.pause_menu_port.call() as CanvasLayer
var _player: CharacterBody2D:
	get:
		return bindings.player_port.call() as CharacterBody2D


func _handle_module_stream_change(stream_change: Dictionary) -> void:
	bindings.stream_change_port.call(stream_change)


func _restore_module_encounter_vfx(module_coord: Vector2i) -> void:
	bindings.encounter_vfx_port.call(module_coord)


func _refresh_module_world_hud() -> void:
	bindings.refresh_hud_port.call()


func _module_slot_key(module_coord: Vector2i) -> String:
	return String(bindings.module_slot_key_port.call(module_coord))


func _update_combined_interaction_prompt() -> void:
	bindings.interaction_refresh_port.call()


func _show_pause_menu() -> void:
	bindings.pause_port.call()


func _is_active_world_entity(node: Node) -> bool:
	return bool(bindings.active_entity_port.call(node))


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	return bindings.dictionary_port.call(raw_value) as Dictionary


func _array_or_empty(raw_value: Variant) -> Array:
	return bindings.array_port.call(raw_value) as Array


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	return bindings.vector_port.call(raw_value, fallback) as Vector2


func _dict_to_vector2i(
	raw_value: Variant,
	fallback: Vector2i = Vector2i(-1, -1)
) -> Vector2i:
	return bindings.vector2i_port.call(raw_value, fallback) as Vector2i


func _coord_to_dict(value: Vector2i) -> Dictionary:
	return bindings.coord_dictionary_port.call(value) as Dictionary


func _vector_to_dict(value: Vector2) -> Dictionary:
	return bindings.vector_dictionary_port.call(value) as Dictionary


func _register_all_module_teleporters() -> void:
	if _module_world_manager == null or not stations.is_empty():
		return
	var station_entries: Array[Dictionary] = []
	for row_index: int in range(7):
		for column_index: int in range(7):
			var module_coord := Vector2i(column_index, row_index)
			var placements: Array[Dictionary] = _module_world_manager.call(
				"placements_at",
				module_coord
			)
			for placement: Dictionary in placements:
				if (
					String(placement.get("type", ""))
					!= MODULE_PLACEMENT_TYPES.MODULE_PLACE_TELEPORTER
				):
					continue
				var local_cell: Vector2i = _dict_to_vector2i(
					placement.get("cell", {})
				)
				var station_id: String = _teleporter_station_id(
					module_coord,
					local_cell
				)
				station_entries.append({
					"station_id": station_id,
					"network_id": String(
						placement.get("network_id", "")
					),
					"module_coord": _coord_to_dict(module_coord),
					"cell": _coord_to_dict(local_cell),
					"world_position": _dictionary_or_empty(
						placement.get("world_position", {})
					),
					"interaction_radius": float(
						placement.get("interaction_radius", 0.0)
					),
				})
	station_entries.sort_custom(_teleporter_station_less)
	for station_index: int in range(station_entries.size()):
		var station: Dictionary = station_entries[station_index]
		station["station_number"] = station_index + 1
		var station_id: String = String(station.get("station_id", ""))
		var module_coord: Vector2i = _dict_to_vector2i(
			station.get("module_coord", {})
		)
		var slot_key: String = _module_slot_key(module_coord)
		var station_ids_for_module: Array = _array_or_empty(
			module_station_ids.get(slot_key, [])
		).duplicate()
		station_ids_for_module.append(station_id)
		module_station_ids[slot_key] = station_ids_for_module
		stations[station_id] = station
	if stations.size() != 3:
		# The checked-in technical slice is a compact combat/streaming fixture and
		# intentionally does not model the formal world's three-station network.
		if _module_world_technical_slice:
			stations.clear()
			module_station_ids.clear()
			return
		push_error(
			"[GameplayRunLoop] teleporter network must contain exactly 3 stations"
		)

func _activate_module_teleporter_visuals(module_coord: Vector2i) -> void:
	if _active_world == null:
		return
	var station_ids: Array = _array_or_empty(
		module_station_ids.get(
			_module_slot_key(module_coord),
			[]
		)
	)
	for raw_station_id: Variant in station_ids:
		var station_id: String = String(raw_station_id)
		if nodes.has(station_id):
			continue
		var station: Dictionary = _dictionary_or_empty(
			stations.get(station_id, {})
		)
		var raw_node: Node = TELEPORTER_INTERACTABLE_SCENE.instantiate()
		if not raw_node is Node2D:
			raw_node.queue_free()
			push_error(
				"[GameplayRunLoop] teleporter interactable scene root is invalid"
			)
			continue
		var interactable: Node2D = raw_node as Node2D
		_active_world.add_child(interactable)
		interactable.global_position = _dict_to_vector(
			station.get("world_position", {}),
			Vector2.ZERO
		)
		if interactable.has_method("configure"):
			interactable.call(
				"configure",
				station_id,
				float(station.get("interaction_radius", 0.0))
			)
		if interactable.has_method("set_station_number"):
			interactable.call(
				"set_station_number",
				int(station.get("station_number", 0))
			)
		nodes[station_id] = interactable

func _deactivate_module_teleporter_visuals(
	module_coord: Vector2i
) -> void:
	for raw_station_id: Variant in _array_or_empty(
		module_station_ids.get(
			_module_slot_key(module_coord),
			[]
		)
	):
		var station_id: String = String(raw_station_id)
		var node: Node = nodes.get(station_id) as Node
		nodes.erase(station_id)
		if node != null and is_instance_valid(node):
			node.queue_free()

func _clear_teleporters() -> void:
	if (
		choice_panel != null
		and is_instance_valid(choice_panel)
	):
		UIManager.remove_expected(choice_panel, true)
	choice_panel = null
	if (
		fade_overlay != null
		and is_instance_valid(fade_overlay)
	):
		UIManager.remove_expected(fade_overlay, true)
	fade_overlay = null
	source_station_id = ""
	transaction_active = false
	for raw_node: Variant in nodes.values():
		var interactable: Node = raw_node as Node
		if interactable != null and is_instance_valid(interactable):
			interactable.queue_free()
	nodes.clear()
	stations.clear()
	module_station_ids.clear()

func _teleporter_station_id(
	module_coord: Vector2i,
	local_cell: Vector2i
) -> String:
	return "teleporter_%d_%d_%d_%d" % [
		module_coord.x,
		module_coord.y,
		local_cell.x,
		local_cell.y,
	]

func _teleporter_station_less(
	left: Dictionary,
	right: Dictionary
) -> bool:
	var left_module: Vector2i = _dict_to_vector2i(
		left.get("module_coord", {})
	)
	var right_module: Vector2i = _dict_to_vector2i(
		right.get("module_coord", {})
	)
	if left_module.y != right_module.y:
		return left_module.y < right_module.y
	if left_module.x != right_module.x:
		return left_module.x < right_module.x
	var left_cell: Vector2i = _dict_to_vector2i(left.get("cell", {}))
	var right_cell: Vector2i = _dict_to_vector2i(right.get("cell", {}))
	if left_cell.y != right_cell.y:
		return left_cell.y < right_cell.y
	return left_cell.x < right_cell.x

func _try_interact_teleporter(station_id: String) -> bool:
	if (
		station_id.is_empty()
		or transaction_active
		or (
			choice_panel != null
			and is_instance_valid(choice_panel)
		)
	):
		return false
	var station: Dictionary = _dictionary_or_empty(
		stations.get(station_id, {})
	)
	if station.is_empty() or not _is_station_current(station):
		return false
	var source_coord: Vector2i = _dict_to_vector2i(
		station.get("module_coord", {})
	)
	if _module_slot_has_hostile_pressure(source_coord):
		_show_teleporter_feedback("show_teleporter_unsafe_feedback")
		return false
	var visited_stations: Array[Dictionary] = (
		_visited_teleporter_stations(station_id)
	)
	if visited_stations.size() <= 1:
		_show_teleporter_feedback(
			"show_teleporter_no_destination_feedback"
		)
		return false
	return _show_teleport_choice_panel(station_id)

func _show_teleport_choice_panel(station_id: String) -> bool:
	if (
		choice_panel != null
		and is_instance_valid(choice_panel)
	):
		return source_station_id == station_id
	var source: Dictionary = _dictionary_or_empty(
		stations.get(station_id, {})
	)
	if source.is_empty() or not _is_station_current(source):
		return false
	if _module_slot_has_hostile_pressure(
		_dict_to_vector2i(source.get("module_coord", {}))
	):
		return false
	var stations: Array[Dictionary] = _visited_teleporter_stations(
		station_id
	)
	if stations.size() <= 1:
		return false
	choice_panel = UIManager.push(
		TELEPORT_CHOICE_PANEL_SCENE,
		{
			"source": "teleport_choice",
			"source_station_id": station_id,
		}
	) as CanvasLayer
	if choice_panel == null:
		return false
	source_station_id = station_id
	if not bool(
		choice_panel.call(
			"configure",
			station_id,
			stations
		)
	):
		UIManager.remove_expected(choice_panel, true)
		choice_panel = null
		source_station_id = ""
		return false
	choice_panel.connect(
		"destination_selected",
		Callable(self, "_on_teleport_destination_selected")
	)
	choice_panel.connect(
		"cancelled",
		Callable(self, "_on_teleport_choice_cancelled"),
		CONNECT_ONE_SHOT
	)
	choice_panel.connect(
		"pause_requested",
		Callable(self, "_on_teleport_choice_pause_requested")
	)
	choice_panel.tree_exited.connect(
		Callable(self, "_on_teleport_choice_panel_tree_exited"),
		CONNECT_ONE_SHOT
	)
	return true

func _on_teleport_destination_selected(
	destination_station_id: String
) -> void:
	_begin_teleport_choice(destination_station_id, true)

func _begin_teleport_choice(
	destination_station_id: String,
	record_event: bool
) -> bool:
	if transaction_active:
		return false
	var transaction: Dictionary = _prepare_teleport_transaction(
		source_station_id,
		destination_station_id
	)
	if transaction.is_empty():
		_show_teleport_choice_failure()
		return false
	if not InputService.begin_non_pausing_ui_capture(self):
		_show_teleport_choice_failure()
		return false
	transaction_active = true
	if (
		choice_panel != null
		and is_instance_valid(choice_panel)
		and choice_panel.has_method("set_input_locked")
	):
		choice_panel.call("set_input_locked", true)
	_execute_teleport_transition(transaction, record_event)
	return true

func _prepare_teleport_transaction(
	source_station_id: String,
	destination_station_id: String
) -> Dictionary:
	if (
		not GameState.is_state(GameState.PLAYING)
		or choice_panel == null
		or not is_instance_valid(choice_panel)
		or source_station_id.is_empty()
		or destination_station_id.is_empty()
		or source_station_id == destination_station_id
		or _player == null
		or not _player.has_method("teleport_to")
		or (
			_player.has_method("is_alive")
			and not bool(_player.call("is_alive"))
		)
		or _camera_controller == null
		or not _camera_controller.has_method("snap_to_target")
	):
		return {}
	var source: Dictionary = _dictionary_or_empty(
		stations.get(source_station_id, {})
	)
	var destination: Dictionary = _dictionary_or_empty(
		stations.get(destination_station_id, {})
	)
	if (
		source.is_empty()
		or destination.is_empty()
		or String(source.get("network_id", ""))
		!= String(destination.get("network_id", ""))
		or not _is_station_current(source)
	):
		return {}
	var source_coord: Vector2i = _dict_to_vector2i(
		source.get("module_coord", {})
	)
	var destination_coord: Vector2i = _dict_to_vector2i(
		destination.get("module_coord", {})
	)
	if (
		_module_slot_has_hostile_pressure(source_coord)
		or not bool(
			_module_world_manager.call(
				"is_module_visited",
				destination_coord
			)
		)
		or not _station_placement_still_exists(source)
		or not _station_placement_still_exists(destination)
	):
		return {}
	var destination_position: Vector2 = _dict_to_vector(
		destination.get("world_position", {}),
		Vector2(INF, INF)
	)
	if (
		not destination_position.is_finite()
		or not bool(
			_module_world_manager.call(
				"is_world_position_walkable",
				destination_position
			)
		)
	):
		return {}
	return {
		"source_station_id": source_station_id,
		"destination_station_id": destination_station_id,
		"destination_coord": _coord_to_dict(destination_coord),
		"destination_position": _vector_to_dict(destination_position),
	}

func _execute_teleport_transition(
	transaction: Dictionary,
	record_event: bool
) -> void:
	fade_overlay = UIManager.push(
		TELEPORT_FADE_OVERLAY_SCENE,
		{"source": "teleport_transition", "immediate": true}
	) as CanvasLayer
	if fade_overlay == null:
		_finish_teleport_transition(false, transaction)
		return
	var transition_config: Dictionary = _dictionary_or_empty(
		_module_world_definition.get("teleporter_transition", {})
	)
	var fade_out_duration: float = maxf(
		float(transition_config.get("fade_out_duration", 0.2)),
		0.0
	)
	var fade_in_duration: float = maxf(
		float(transition_config.get("fade_in_duration", 0.2)),
		0.0
	)
	var succeeded: bool = await fade_overlay.call(
		"transition",
		Callable(self, "_commit_teleport_transaction").bind(
			transaction,
			record_event
		),
		fade_out_duration,
		fade_in_duration
	)
	_finish_teleport_transition(succeeded, transaction)

func _commit_teleport_transaction(
	transaction: Dictionary,
	record_event: bool
) -> bool:
	var refreshed: Dictionary = _prepare_teleport_transaction(
		String(transaction.get("source_station_id", "")),
		String(transaction.get("destination_station_id", ""))
	)
	if refreshed.is_empty():
		return false
	var destination_position: Vector2 = _dict_to_vector(
		refreshed.get("destination_position", {}),
		Vector2(INF, INF)
	)
	if not bool(_player.call("teleport_to", destination_position)):
		return false
	var stream_change: Dictionary = _module_world_manager.call(
		"tick",
		destination_position
	)
	_handle_module_stream_change(stream_change)
	_camera_controller.call("snap_to_target", true)
	_refresh_module_world_hud()
	_update_combined_interaction_prompt()
	var destination_coord: Vector2i = _dict_to_vector2i(
		refreshed.get("destination_coord", {})
	)
	_restore_module_encounter_vfx(destination_coord)
	if (
		choice_panel != null
		and is_instance_valid(choice_panel)
	):
		UIManager.remove_expected(choice_panel, true)
	choice_panel = null
	if record_event:
		_record_teleport_choice({
			"outcome": TELEPORT_CHOICE_OUTCOMES.TELEPORTED,
			"source_station_id": String(
				transaction.get("source_station_id", "")
			),
			"destination_station_id": String(
				transaction.get("destination_station_id", "")
			),
		})
	return true

func _finish_teleport_transition(
	succeeded: bool,
	transaction: Dictionary
) -> void:
	if (
		fade_overlay != null
		and is_instance_valid(fade_overlay)
	):
		UIManager.remove_expected(fade_overlay, true)
	fade_overlay = null
	InputService.end_non_pausing_ui_capture(self)
	transaction_active = false
	if succeeded:
		source_station_id = ""
		return
	if (
		choice_panel != null
		and is_instance_valid(choice_panel)
		and choice_panel.has_method("set_input_locked")
	):
		choice_panel.call("set_input_locked", false)
	if not GameState.is_state(GameState.PLAYING):
		return
	_show_teleport_choice_failure()

func _on_teleport_choice_cancelled() -> void:
	if transaction_active:
		return
	_cancel_teleport_choice(true)

func _cancel_teleport_choice(record_event: bool) -> bool:
	if (
		source_station_id.is_empty()
		or not GameState.is_state(GameState.PLAYING)
		or choice_panel == null
		or not is_instance_valid(choice_panel)
	):
		return false
	var cancelled_source_station_id: String = source_station_id
	if record_event:
		_record_teleport_choice({
			"outcome": TELEPORT_CHOICE_OUTCOMES.CANCELLED,
			"source_station_id": cancelled_source_station_id,
		})
	if (
		choice_panel != null
		and is_instance_valid(choice_panel)
	):
		UIManager.remove_expected(choice_panel, true)
	choice_panel = null
	source_station_id = ""
	return true

func _on_teleport_choice_pause_requested() -> void:
	if _pause_menu == null and not transaction_active:
		_show_pause_menu()

func _on_teleport_choice_panel_tree_exited() -> void:
	choice_panel = null
	if transaction_active:
		return
	source_station_id = ""

func _record_teleport_choice(payload: Dictionary) -> void:
	bindings.record_port.call(payload)

func apply_replay_teleport_choice(payload: Dictionary) -> bool:
	var outcome: String = String(payload.get("outcome", ""))
	var expected_size: int = (
		3
		if outcome == TELEPORT_CHOICE_OUTCOMES.TELEPORTED
		else 2
	)
	if (
		payload.size() != expected_size
		or not payload.get("outcome") is String
		or not payload.get("source_station_id") is String
		or String(payload.get("source_station_id", ""))
		!= source_station_id
	):
		return false
	if outcome == TELEPORT_CHOICE_OUTCOMES.CANCELLED:
		return _cancel_teleport_choice(false)
	if (
		outcome != TELEPORT_CHOICE_OUTCOMES.TELEPORTED
		or not payload.get("destination_station_id") is String
	):
		return false
	return _begin_teleport_choice(
		String(payload.get("destination_station_id", "")),
		false
	)

func replay_teleport_choice_pending() -> bool:
	return transaction_active

func replay_teleport_choice_completed(payload: Dictionary) -> bool:
	if (
		transaction_active
		or not GameState.is_state(GameState.PLAYING)
		or String(payload.get("outcome", ""))
		!= TELEPORT_CHOICE_OUTCOMES.TELEPORTED
	):
		return false
	var destination: Dictionary = _dictionary_or_empty(
		stations.get(
			String(payload.get("destination_station_id", "")),
			{}
		)
	)
	if destination.is_empty() or _player == null or _module_world_manager == null:
		return false
	var destination_coord: Vector2i = _dict_to_vector2i(
		destination.get("module_coord", {})
	)
	var destination_position: Vector2 = _dict_to_vector(
		destination.get("world_position", {}),
		Vector2(INF, INF)
	)
	var current_coord: Vector2i = _module_world_manager.call(
		"current_module_coord"
	) as Vector2i
	return (
		destination_position.is_finite()
		and _player.global_position.is_equal_approx(destination_position)
		and current_coord == destination_coord
	)

func _visited_teleporter_stations(
	source_station_id: String
) -> Array[Dictionary]:
	var source: Dictionary = _dictionary_or_empty(
		stations.get(source_station_id, {})
	)
	var network_id: String = String(source.get("network_id", ""))
	var result: Array[Dictionary] = []
	for raw_station: Variant in stations.values():
		var station: Dictionary = raw_station as Dictionary
		var module_coord: Vector2i = _dict_to_vector2i(
			station.get("module_coord", {})
		)
		if (
			String(station.get("network_id", "")) != network_id
			or not bool(
				_module_world_manager.call(
					"is_module_visited",
					module_coord
				)
			)
		):
			continue
		var copy: Dictionary = station.duplicate(true)
		copy["is_current"] = (
			String(copy.get("station_id", "")) == source_station_id
		)
		result.append(copy)
	result.sort_custom(_teleporter_station_less)
	return result

func _is_station_current(station: Dictionary) -> bool:
	if _module_world_manager == null:
		return false
	var current_module: Vector2i = _module_world_manager.call(
		"current_module_coord"
	) as Vector2i
	return (
		_dict_to_vector2i(station.get("module_coord", {}))
		== current_module
	)

func _station_placement_still_exists(station: Dictionary) -> bool:
	var module_coord: Vector2i = _dict_to_vector2i(
		station.get("module_coord", {})
	)
	var expected_station_id: String = String(
		station.get("station_id", "")
	)
	var placements: Array[Dictionary] = _module_world_manager.call(
		"placements_at",
		module_coord
	)
	for placement: Dictionary in placements:
		if (
			String(placement.get("type", ""))
			!= MODULE_PLACEMENT_TYPES.MODULE_PLACE_TELEPORTER
		):
			continue
		var local_cell: Vector2i = _dict_to_vector2i(
			placement.get("cell", {})
		)
		if (
			_teleporter_station_id(module_coord, local_cell)
			== expected_station_id
		):
			return true
	return false

func _module_slot_has_hostile_pressure(
	module_coord: Vector2i
) -> bool:
	if _module_world_manager == null:
		return true
	var state: Dictionary = _module_world_manager.call(
		"slot_state",
		module_coord
	) as Dictionary
	var encounter: Dictionary = _dictionary_or_empty(
		state.get("enemy_encounter", {})
	)
	if (
		String(encounter.get("state", ""))
		== MODULE_ENCOUNTER_STATE_TELEGRAPHING
		and float(encounter.get("remaining_telegraph", 0.0)) > 0.0
	):
		return true
	if not _array_or_empty(state.get("enemy_snapshots", [])).is_empty():
		return true
	var slot_key: String = _module_slot_key(module_coord)
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			not _is_active_world_entity(enemy)
			or String(enemy.get_meta("module_slot", "")) != slot_key
		):
			continue
		if enemy.has_method("is_alive") and not bool(enemy.call("is_alive")):
			continue
		return true
	return false

func _show_teleporter_feedback(method_name: String) -> void:
	if _hud != null and _hud.has_method(method_name):
		_hud.call(method_name)

func _show_teleport_choice_failure() -> void:
	if (
		choice_panel != null
		and is_instance_valid(choice_panel)
		and choice_panel.has_method("show_feedback")
	):
		choice_panel.call(
			"show_feedback",
			"ui_teleport_failed"
		)
		return
	_show_teleporter_feedback("show_teleporter_failed_feedback")


func _nearest_teleporter_candidate() -> Dictionary:
	if _player == null:
		return {}
	var best: Dictionary = {}
	for raw_station_id: Variant in nodes.keys():
		var station_id: String = String(raw_station_id)
		var node: Node2D = nodes.get(station_id) as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if (
			node.has_method("can_player_interact")
			and not bool(node.call("can_player_interact", _player))
		):
			continue
		var distance: float = _player.global_position.distance_to(
			node.global_position
		)
		if (
			best.is_empty()
			or distance < float(best.get("distance", INF))
		):
			best = {
				"kind": "teleporter",
				"id": station_id,
				"distance": distance,
			}
	return best
