# Doc: docs/代码/gameplay_runtime.md
class_name GearModPlacementCoordinator
extends Node


const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const GEAR_MOD_PLACEMENT_OUTCOMES := preload(
	"res://scripts/contracts/gear_mod_placement_outcomes.gd"
)
const MODULE_ROLES := preload(
	"res://scripts/contracts/module_roles.gd"
)
const VFX_CUES := preload("res://scripts/contracts/vfx_cues.gd")
const GEAR_MOD_BOARD_PANEL_SCENE := preload(
	"res://scenes/ui/gear_mod_board_panel.tscn"
)
const PRESENTATION_PICKUP_DEFAULT: String = "presentation_pickup_default"


class Bindings extends RefCounted:
	var player_port: Callable = Callable()
	var module_world_port: Callable = Callable()
	var spawn_port: Callable = Callable()
	var reward_port: Callable = Callable()
	var ui_port: Callable = Callable()
	var record_port: Callable = Callable()
	var requested_port: Callable = Callable()
	var resolved_port: Callable = Callable()
	var failed_port: Callable = Callable()
	var hero_composition_port: Callable = Callable()
	var hud_port: Callable = Callable()
	var interaction_refresh_port: Callable = Callable()
	var interaction_label_port: Callable = Callable()
	var feedback_port: Callable = Callable()
	var active_entity_port: Callable = Callable()
	var run_snapshot_port: Callable = Callable()
	var sync_ids_port: Callable = Callable()
	var apply_modifiers_port: Callable = Callable()
	var dictionary_port: Callable = Callable()
	var array_port: Callable = Callable()
	var coord_dictionary_port: Callable = Callable()
	var load_array_port: Callable = Callable()
	var find_item_port: Callable = Callable()
	var stats_snapshot_port: Callable = Callable()
	var format_stat_port: Callable = Callable()
	var content_available_port: Callable = Callable()
	var debug_result_port: Callable = Callable()


var bindings: Bindings = null
var board: RefCounted = null
var panel: Node = null
var pending: Dictionary = {}


func configure(value: Bindings) -> void:
	bindings = value


func clear_pending() -> void:
	panel = null
	pending.clear()


var _hero_composition: Dictionary:
	get:
		return bindings.hero_composition_port.call() as Dictionary
var _hud: CanvasLayer:
	get:
		return bindings.hud_port.call() as CanvasLayer
var _module_world_manager: Node2D:
	get:
		return bindings.module_world_port.call() as Node2D
var _player: CharacterBody2D:
	get:
		return bindings.player_port.call() as CharacterBody2D


func _update_combined_interaction_prompt() -> void:
	bindings.interaction_refresh_port.call()


func _interaction_binding_label() -> String:
	return String(bindings.interaction_label_port.call())


func _play_feedback(
	profile_id: String,
	cue: String,
	context: Dictionary = {}
) -> void:
	bindings.feedback_port.call(profile_id, cue, context)


func _is_active_world_entity(node: Node) -> bool:
	return bool(bindings.active_entity_port.call(node))


func _run_gear_mod_snapshot() -> Dictionary:
	return bindings.run_snapshot_port.call() as Dictionary


func _sync_run_gear_mod_ids_from_board() -> void:
	bindings.sync_ids_port.call()


func _apply_run_gear_modifiers() -> void:
	bindings.apply_modifiers_port.call()


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	return bindings.dictionary_port.call(raw_value) as Dictionary


func _array_or_empty(raw_value: Variant) -> Array:
	return bindings.array_port.call(raw_value) as Array


func _coord_to_dict(value: Vector2i) -> Dictionary:
	return bindings.coord_dictionary_port.call(value) as Dictionary


func _load_array(path: String, key: String) -> Array:
	return bindings.load_array_port.call(path, key) as Array


func _find_item(items: Array, requested_id: String) -> Dictionary:
	return bindings.find_item_port.call(items, requested_id) as Dictionary


func _stats_panel_snapshot() -> Dictionary:
	return bindings.stats_snapshot_port.call() as Dictionary


func _format_stat_value(value: float) -> String:
	return String(bindings.format_stat_port.call(value))


func _is_content_available(content_type: String, content_id: String) -> bool:
	return bool(bindings.content_available_port.call(content_type, content_id))


func _debug_result(ok: bool, reason: String) -> Dictionary:
	return bindings.debug_result_port.call(ok, reason) as Dictionary


func debug_gear_mod_board_snapshot() -> Dictionary:
	return _run_gear_mod_snapshot()

func debug_pending_gear_mod_placement() -> Dictionary:
	return _pending_gear_mod_placement_snapshot()

func request_gear_mod_relocation(
	instance_id: int,
	target: Vector2i,
	cost_authorizer: Callable = Callable()
) -> Dictionary:
	if board == null:
		return _debug_result(false, "board_unavailable")
	var result: Dictionary = board.call(
		"request_relocation",
		instance_id,
		target,
		cost_authorizer
	) as Dictionary
	if bool(result.get("ok", false)):
		_sync_run_gear_mod_ids_from_board()
		_apply_run_gear_modifiers()
	return result

func _try_interact_gear_mod_pickup(
	pickup: GearModPickup
) -> bool:
	if (
		pickup == null
		or not is_instance_valid(pickup)
		or not pickup.can_player_interact(_player)
		or not pending.is_empty()
	):
		return false
	if board == null:
		_emit_gear_mod_placement_failure(
			pickup.gear_mod_instance_id(),
			pickup.mod_id(),
			"board_unavailable"
		)
		return false
	var mod_id: String = pickup.mod_id()
	var instance_id: int = pickup.gear_mod_instance_id()
	var legal_cells: Array[Vector2i] = []
	var raw_legal_cells: Variant = board.call(
		"legal_cells",
		mod_id
	)
	if raw_legal_cells is Array:
		for raw_cell: Variant in raw_legal_cells as Array:
			if raw_cell is Vector2i:
				legal_cells.append(raw_cell as Vector2i)
	if legal_cells.is_empty():
		_emit_gear_mod_placement_failure(
			instance_id,
			mod_id,
			"no_legal_cell"
		)
		return false
	pending = {
		"instance_id": instance_id,
		"mod_id": mod_id,
		"legal_cells": legal_cells,
		"pickup": pickup,
	}
	var pending_snapshot: Dictionary = (
		_pending_gear_mod_placement_snapshot()
	)
	bindings.requested_port.call(pending_snapshot)
	_show_gear_mod_placement_panel(pending_snapshot)
	return true

func confirm_gear_mod_placement(
	instance_id: int,
	mod_id: String,
	coord: Vector2i
) -> Dictionary:
	return _confirm_pending_gear_mod_placement(
		instance_id,
		mod_id,
		coord,
		true
	)

func cancel_gear_mod_placement(
	instance_id: int,
	mod_id: String
) -> Dictionary:
	if not _pending_gear_mod_matches(instance_id, mod_id):
		return _debug_result(false, "pending_mismatch")
	return _cancel_pending_gear_mod_placement("player_cancelled", true)

func apply_replay_gear_mod_placement(
	payload: Dictionary
) -> Dictionary:
	var outcome: String = String(payload.get("outcome", ""))
	var expected_size: int = (
		5
		if outcome == GEAR_MOD_PLACEMENT_OUTCOMES.PLACED
		else 3
	)
	if (
		payload.size() != expected_size
		or not payload.get("instance_id") is int
		or not payload.get("mod_id") is String
		or not payload.get("outcome") is String
	):
		return _debug_result(false, "replay_divergence")
	var instance_id: int = int(payload.get("instance_id", 0))
	var mod_id: String = String(payload.get("mod_id", ""))
	if not _pending_gear_mod_matches(instance_id, mod_id):
		return _debug_result(false, "replay_divergence")
	if outcome == GEAR_MOD_PLACEMENT_OUTCOMES.CANCELLED:
		var cancel_result: Dictionary = _cancel_pending_gear_mod_placement(
			"replay_cancelled",
			false
		)
		if not bool(cancel_result.get("ok", false)):
			return _debug_result(false, "replay_divergence")
		return cancel_result
	if (
		outcome != GEAR_MOD_PLACEMENT_OUTCOMES.PLACED
		or not payload.get("x") is int
		or not payload.get("y") is int
	):
		return _debug_result(false, "replay_divergence")
	var placement_result: Dictionary = _confirm_pending_gear_mod_placement(
		instance_id,
		mod_id,
		Vector2i(
			int(payload.get("x", -1)),
			int(payload.get("y", -1))
		),
		false
	)
	if not bool(placement_result.get("ok", false)):
		return _debug_result(false, "replay_divergence")
	return placement_result

func _confirm_pending_gear_mod_placement(
	instance_id: int,
	mod_id: String,
	coord: Vector2i,
	record_event: bool
) -> Dictionary:
	if (
		not GameState.is_state(GameState.PLAYING)
		or board == null
		or not _pending_gear_mod_matches(instance_id, mod_id)
	):
		return _debug_result(false, "pending_mismatch")
	var pickup: GearModPickup = pending.get(
		"pickup"
	) as GearModPickup
	if (
		pickup == null
		or not is_instance_valid(pickup)
		or not _is_active_world_entity(pickup)
		or pickup.gear_mod_instance_id() != instance_id
		or pickup.mod_id() != mod_id
	):
		return _emit_gear_mod_placement_failure(
			instance_id,
			mod_id,
			"pickup_unavailable"
		)
	if not _is_content_available(CONTENT_UNLOCK_TYPES.GEAR_MOD, mod_id):
		return _emit_gear_mod_placement_failure(
			instance_id,
			mod_id,
			"content_unavailable"
		)
	var result: Dictionary = board.call(
		"request_placement",
		instance_id,
		mod_id,
		coord
	) as Dictionary
	if not bool(result.get("ok", false)):
		return _emit_gear_mod_placement_failure(
			instance_id,
			mod_id,
			String(result.get("reason", "placement_rejected"))
		)
	var pickup_position: Vector2 = pickup.global_position
	_play_feedback(
		PRESENTATION_PICKUP_DEFAULT,
		VFX_CUES.PICKUP_COLLECT,
		{
			"owner": pickup,
			"world_position": pickup_position,
		}
	)
	PoolManager.release(pickup)
	pending.clear()
	_sync_run_gear_mod_ids_from_board()
	_apply_run_gear_modifiers()
	_play_gear_mod_placement_sfx(mod_id)
	_show_placed_gear_mod_feedback(mod_id)
	_close_gear_mod_board_panel(true)
	var resolved: Dictionary = {
		"ok": true,
		"instance_id": instance_id,
		"mod_id": mod_id,
		"outcome": GEAR_MOD_PLACEMENT_OUTCOMES.PLACED,
		"x": coord.x,
		"y": coord.y,
		"placement": _dictionary_or_empty(
			result.get("placement", {})
		),
	}
	if record_event:
		_record_gear_mod_placement(resolved)
	bindings.resolved_port.call(resolved.duplicate(true))
	_update_combined_interaction_prompt()
	return resolved

func _cancel_pending_gear_mod_placement(
	reason: String,
	record_event: bool
) -> Dictionary:
	if pending.is_empty():
		return _debug_result(false, "no_pending_placement")
	var instance_id: int = int(
		pending.get("instance_id", 0)
	)
	var mod_id: String = String(
		pending.get("mod_id", "")
	)
	pending.clear()
	_close_gear_mod_board_panel(false)
	var result: Dictionary = {
		"ok": true,
		"instance_id": instance_id,
		"mod_id": mod_id,
		"outcome": GEAR_MOD_PLACEMENT_OUTCOMES.CANCELLED,
		"reason": reason,
	}
	if record_event:
		_record_gear_mod_placement(result)
	bindings.resolved_port.call(result.duplicate(true))
	_update_combined_interaction_prompt()
	return result

func _pending_gear_mod_matches(instance_id: int, mod_id: String) -> bool:
	return (
		instance_id > 0
		and not mod_id.is_empty()
		and int(pending.get("instance_id", 0))
		== instance_id
		and String(pending.get("mod_id", ""))
		== mod_id
	)

func _pending_gear_mod_placement_snapshot() -> Dictionary:
	if pending.is_empty():
		return {}
	var legal_cells: Array[Dictionary] = []
	for raw_cell: Variant in _array_or_empty(
		pending.get("legal_cells", [])
	):
		if raw_cell is Vector2i:
			legal_cells.append(_coord_to_dict(raw_cell as Vector2i))
	return {
		"instance_id": int(
			pending.get("instance_id", 0)
		),
		"mod_id": String(
			pending.get("mod_id", "")
		),
		"legal_targets": legal_cells,
		"default_target": _current_module_coord_dict(),
	}

func _emit_gear_mod_placement_failure(
	instance_id: int,
	mod_id: String,
	reason: String
) -> Dictionary:
	if (
		reason == "no_legal_cell"
		and _hud != null
		and _hud.has_method("show_gear_mod_no_space_feedback")
	):
		_hud.call("show_gear_mod_no_space_feedback")
	var result: Dictionary = {
		"ok": false,
		"instance_id": instance_id,
		"mod_id": mod_id,
		"reason": reason,
	}
	bindings.failed_port.call(result.duplicate(true))
	return result

func _record_gear_mod_placement(result: Dictionary) -> void:
	var outcome: String = String(result.get("outcome", ""))
	var event_data: Dictionary = {
		"instance_id": int(result.get("instance_id", 0)),
		"mod_id": String(result.get("mod_id", "")),
		"outcome": outcome,
	}
	if outcome == GEAR_MOD_PLACEMENT_OUTCOMES.PLACED:
		event_data["x"] = int(result.get("x", -1))
		event_data["y"] = int(result.get("y", -1))
	bindings.record_port.call(event_data)

func _show_placed_gear_mod_feedback(mod_id: String) -> void:
	var definition: Dictionary = GearModSystem.mod_definition(mod_id)
	if (
		definition.is_empty()
		or _hud == null
		or not _hud.has_method("show_gear_mod_drop_feedback")
	):
		return
	_hud.call(
		"show_gear_mod_drop_feedback",
		String(definition.get("name_key", ""))
	)

func _play_gear_mod_placement_sfx(mod_id: String) -> void:
	var definition: Dictionary = GearModSystem.mod_definition(mod_id)
	var sfx_id: String = String(
		definition.get("placement_sfx_id", "")
	).strip_edges()
	if sfx_id.is_empty() or not AudioManager.has_stream(sfx_id):
		return
	AudioManager.play_sfx(sfx_id)

func open_gear_mod_board_inspect() -> bool:
	if (
		board == null
		or panel != null
		or not GameState.is_state(GameState.PLAYING)
	):
		return false
	var new_panel: GearModBoardPanel = UIManager.push(
		GEAR_MOD_BOARD_PANEL_SCENE,
		{"source": "gear_mod_board_inspect"}
	) as GearModBoardPanel
	if new_panel == null:
		return false
	panel = new_panel
	_connect_gear_mod_board_panel(new_panel)
	new_panel.configure_inspect(
		_run_gear_mod_snapshot(),
		_gear_mod_panel_map_snapshot(),
		_stats_panel_snapshot(),
		_gear_mod_panel_passive()
	)
	return true

func _show_gear_mod_placement_panel(pending: Dictionary) -> bool:
	if board == null:
		return false
	if (
		panel != null
		and is_instance_valid(panel)
	):
		return false
	var new_panel: GearModBoardPanel = UIManager.push(
		GEAR_MOD_BOARD_PANEL_SCENE,
		{"source": "gear_mod_placement"}
	) as GearModBoardPanel
	if new_panel == null:
		return false
	panel = new_panel
	_connect_gear_mod_board_panel(new_panel)
	new_panel.configure_placement(
		_run_gear_mod_snapshot(),
		_gear_mod_panel_map_snapshot(),
		_stats_panel_snapshot(),
		_gear_mod_panel_passive(),
		pending
	)
	return true

func _connect_gear_mod_board_panel(panel: GearModBoardPanel) -> void:
	panel.placement_confirmed.connect(
		_on_gear_mod_panel_placement_confirmed
	)
	panel.placement_cancelled.connect(
		_on_gear_mod_panel_placement_cancelled
	)
	panel.inspect_closed.connect(_on_gear_mod_panel_inspect_closed)
	panel.tree_exited.connect(_on_gear_mod_panel_tree_exited)

func _close_gear_mod_board_panel(committed: bool) -> void:
	if (
		panel == null
		or not is_instance_valid(panel)
	):
		panel = null
		return
	var closing_panel: Node = panel
	panel = null
	if committed and closing_panel.has_method("close_after_commit"):
		closing_panel.call("close_after_commit")
	elif closing_panel.has_method("request_close"):
		closing_panel.call("request_close")
	else:
		UIManager.pop_expected(closing_panel)

func _on_gear_mod_panel_placement_confirmed(
	instance_id: int,
	mod_id: String,
	coord: Vector2i
) -> void:
	confirm_gear_mod_placement(instance_id, mod_id, coord)

func _on_gear_mod_panel_placement_cancelled(
	instance_id: int,
	mod_id: String
) -> void:
	cancel_gear_mod_placement(instance_id, mod_id)

func _on_gear_mod_panel_inspect_closed() -> void:
	panel = null

func _on_gear_mod_panel_tree_exited() -> void:
	panel = null
	if not pending.is_empty():
		_cancel_pending_gear_mod_placement(
			"panel_closed",
			true
		)

func _gear_mod_panel_map_snapshot() -> Dictionary:
	if _module_world_manager == null:
		return {}
	return {
		"visited_slots": _module_world_manager.call(
			"visited_module_coords"
		),
		"current_slot": _current_module_coord_dict(),
		"objective_slot": _coord_to_dict(
			_module_world_manager.call(
				"role_module_coord",
				MODULE_ROLES.MODULE_ROLE_OBJECTIVE
			) as Vector2i
		),
	}

func _current_module_coord_dict() -> Dictionary:
	if _module_world_manager == null:
		return {}
	return _coord_to_dict(
		_module_world_manager.call("current_module_coord") as Vector2i
	)

func _gear_mod_panel_passive() -> Dictionary:
	return _find_item(
		_load_array(DataLoader.HERO_PASSIVES_PATH, "passives"),
		String(_hero_composition.get("passive_id", ""))
	)

func _update_gear_mod_pickup_prompt(
	pickup: GearModPickup
) -> void:
	if (
		_hud == null
		or pickup == null
		or not is_instance_valid(pickup)
		or not _hud.has_method("show_interaction_prompt")
	):
		return
	var mod_id: String = pickup.mod_id()
	var definition: Dictionary = GearModSystem.mod_definition(mod_id)
	if definition.is_empty():
		return
	var effect_text: String = tr(String(definition.get("desc_key", "")))
	if not GearModSystem.modifier_components(mod_id).is_empty():
		effect_text = _format_gear_mod_pickup_effect(
			mod_id,
			GearModSystem.modifiers(mod_id)
		)
	var values: Dictionary = {
		"name": tr(String(definition.get("name_key", ""))),
		"effect": effect_text,
	}
	_hud.call(
		"show_interaction_prompt",
		_interaction_binding_label(),
		"ui_interact_pickup_gear_mod",
		values
	)

func _format_gear_mod_pickup_effect(
	mod_id: String,
	modifiers: Array[Dictionary]
) -> String:
	var parts: Array[String] = []
	for modifier: Dictionary in modifiers:
		var stat: String = String(modifier.get("stat", ""))
		var stat_label: String = tr("ui_stats_%s" % stat)
		var modifier_type: String = String(
			modifier.get("type", "")
		)
		var value: float = float(modifier.get("value", 0.0))
		if modifier_type == "mult":
			parts.append(
				"%s %s%%" % [
					stat_label,
					_format_signed_number((value - 1.0) * 100.0),
				]
			)
		elif modifier_type == "add":
			parts.append(
				"%s %s" % [
					stat_label,
					_format_signed_number(value),
				]
			)
	if parts.is_empty():
		return tr(
			String(
				GearModSystem.mod_definition(mod_id).get(
					"desc_key",
					""
				)
			)
		)
	return " · ".join(parts)

func _format_signed_number(value: float) -> String:
	var magnitude: String = _format_stat_value(absf(value))
	return "%s%s" % ["+" if value >= 0.0 else "-", magnitude]


func _nearest_gear_mod_pickup_candidate() -> Dictionary:
	if _player == null:
		return {}
	var best: Dictionary = {}
	for raw_node: Node in get_tree().get_nodes_in_group(
		"active_gear_mod_pickups"
	):
		if not raw_node is GearModPickup:
			continue
		var pickup: GearModPickup = raw_node as GearModPickup
		if (
			not _is_active_world_entity(pickup)
			or not pickup.can_player_interact(_player)
		):
			continue
		var distance: float = _player.global_position.distance_to(
			pickup.global_position
		)
		if not best.is_empty():
			var best_distance: float = float(
				best.get("distance", INF)
			)
			var best_pickup: GearModPickup = best.get(
				"pickup"
			) as GearModPickup
			if distance > best_distance:
				continue
			if (
				is_equal_approx(distance, best_distance)
				and best_pickup != null
				and (
					pickup.global_position
					== best_pickup.global_position
					and pickup.gear_mod_instance_id()
					>= best_pickup.gear_mod_instance_id()
					or (
						pickup.global_position
						!= best_pickup.global_position
						and not _pickup_position_precedes(
							pickup.global_position,
							best_pickup.global_position
						)
					)
				)
			):
				continue
		best = {
			"kind": "gear_mod_pickup",
			"id": pickup.gear_mod_instance_id(),
			"distance": distance,
			"pickup": pickup,
		}
	return best

func _pickup_position_precedes(left: Vector2, right: Vector2) -> bool:
	if not is_equal_approx(left.x, right.x):
		return left.x < right.x
	return left.y < right.y
