# Doc: docs/代码/module_world_manager.md
class_name ModuleWorldManager
extends Node2D
## Deterministic 7 x 7 module-world assignment, coordinate conversion, fog state and 3 x 3 streaming.
## Gameplay entity spawning remains owned by GameplayRunLoop; this manager only streams reusable ModuleChunk nodes.

const RNG_STREAMS := preload("res://scripts/contracts/rng_streams.gd")
const ModuleChunkStreamingControllerRuntime := preload(
	"res://scripts/gameplay/module_chunk_streaming_controller.gd"
)
const ModuleWorldLayoutRuntime := preload(
	"res://scripts/gameplay/module_world_layout.gd"
)
const ModuleNavigationFieldRuntime := preload("res://scripts/gameplay/module_navigation_field.gd")
const ModuleWorldStateRuntime := preload("res://scripts/gameplay/module_world_state.gd")

const WORLD_COLUMNS: int = ModuleWorldLayoutRuntime.WORLD_COLUMNS
const WORLD_ROWS: int = ModuleWorldLayoutRuntime.WORLD_ROWS
const MODULE_COLUMNS: int = ModuleWorldLayoutRuntime.MODULE_COLUMNS
const MODULE_ROWS: int = ModuleWorldLayoutRuntime.MODULE_ROWS
const WORLD_CELL_COLUMNS: int = ModuleWorldLayoutRuntime.WORLD_CELL_COLUMNS
const WORLD_CELL_ROWS: int = ModuleWorldLayoutRuntime.WORLD_CELL_ROWS
const WORLD_CENTER_GLOBAL_CELL: Vector2i = (
	ModuleWorldLayoutRuntime.WORLD_CENTER_GLOBAL_CELL
)
const MAX_STREAMING_CHUNKS: int = 9
const MAX_PINNED_CHUNKS: int = 3
const MAX_ACTIVE_CHUNKS: int = MAX_STREAMING_CHUNKS + MAX_PINNED_CHUNKS
const ROTATION_STEP: int = ModuleWorldLayoutRuntime.ROTATION_STEP
const ROTATION_FULL: int = ModuleWorldLayoutRuntime.ROTATION_FULL
const ASSIGNMENT_SEED_MODULUS: int = (
	ModuleWorldLayoutRuntime.ASSIGNMENT_SEED_MODULUS
)
const INVALID_COORD: Vector2i = ModuleWorldLayoutRuntime.INVALID_COORD
const MODULE_TERRAIN_Z_INDEX: int = -90

var _world_def: Dictionary = {}
var _active_radius: int = 1
var _navigation_flow_radius_cells: int = 1
var _module_layout: ModuleWorldLayoutRuntime = ModuleWorldLayoutRuntime.new()
var _navigation_field: ModuleNavigationFieldRuntime = ModuleNavigationFieldRuntime.new()
var _world_state: ModuleWorldStateRuntime = ModuleWorldStateRuntime.new(
	WORLD_COLUMNS,
	WORLD_ROWS,
	MAX_PINNED_CHUNKS,
	INVALID_COORD
)
var _chunk_streaming_controller: ModuleChunkStreamingControllerRuntime = (
	ModuleChunkStreamingControllerRuntime.new()
)
var _configured: bool = false


func _init() -> void:
	z_index = MODULE_TERRAIN_Z_INDEX


func configure(
	world_def: Dictionary,
	registry_by_id: Dictionary,
	templates_by_id: Dictionary,
	generated_scene_paths_by_id: Dictionary,
	run_seed: int,
	navigation_flow_radius_cells: int
) -> bool:
	var streaming_configuration := (
		ModuleChunkStreamingControllerRuntime.Configure.new()
	)
	streaming_configuration.generated_scene_paths_by_id = (
		generated_scene_paths_by_id
	)
	streaming_configuration.chunk_pool = _module_chunk_children()
	streaming_configuration.expected_chunk_count = MAX_ACTIVE_CHUNKS
	var chunk_pool_valid: bool = _chunk_streaming_controller.configure(
		streaming_configuration
	)
	_world_def = world_def.duplicate(true)
	var layout_valid: bool = _module_layout.configure(
		world_def,
		registry_by_id,
		templates_by_id,
		run_seed
	)
	_active_radius = clampi(int(_world_def.get("active_radius", 1)), 0, 1)
	_navigation_flow_radius_cells = navigation_flow_radius_cells
	_configured = (
		layout_valid
		and _navigation_flow_radius_cells > 0
		and _has_valid_generated_scene_paths()
	)
	if not _configured:
		push_error("[ModuleWorldManager] world geometry, generated scenes, cell size, or navigation flow radius are invalid")
		return false
	if not chunk_pool_valid:
		_configured = false
		push_error(
			"[ModuleWorldManager] scene must contain exactly %d ModuleChunk children, got %d"
			% [
				MAX_ACTIVE_CHUNKS,
				_chunk_streaming_controller.chunk_pool_size(),
			]
		)
		return false
	return build_assignment()


func build_assignment() -> bool:
	if not _configured:
		return false
	_reset_world_state()
	if (
		_module_layout.build_seeded_assignment(
			_world_random_port(),
			RNG_STREAMS.WORLD
		)
		and _finalize_assignment()
	):
		return true
	push_warning("[ModuleWorldManager] generated assignment invalid; using checked-in fallback assignment")
	return build_fallback_assignment()


func build_fallback_assignment() -> bool:
	if not _configured:
		return false
	_reset_world_state()
	if not _module_layout.load_fallback_assignment():
		_report_fallback_error(
			"[ModuleWorldManager] fallback assignment could not be loaded"
		)
		return false
	if not _module_layout.assign_fallback_objective(
		_world_random_port(),
		RNG_STREAMS.WORLD
	):
		_report_fallback_error(
			"[ModuleWorldManager] fallback objective spawn could not be selected"
		)
		return false
	return _finalize_assignment()


## Narrow diagnostic seam keeps legacy fallback text testable without printing
## expected engine errors through the canonical fail-closed GUT runner.
func _report_fallback_error(message: String) -> void:
	push_error(message)


func build_technical_slice_assignment() -> bool:
	if not _configured:
		return false
	_reset_world_state()
	if not _module_layout.build_technical_slice_assignment():
		push_error("[ModuleWorldManager] technical-slice assignment could not be loaded")
		return false
	return _finalize_assignment()


func tick(player_position: Vector2) -> Dictionary:
	_navigation_field.set_active_target(player_position)
	var global_cell: Vector2i = world_to_global_cell(player_position)
	var module_and_local: Dictionary = global_cell_to_module_and_local(global_cell)
	var next_coord: Vector2i = module_and_local.get("module_coord", INVALID_COORD) as Vector2i
	if not _is_module_coord_valid(next_coord):
		var outside_streaming_change: Dictionary = _refresh_active_modules(INVALID_COORD)
		_world_state.leave_world()
		return {
			"current_module": {},
			"entered": false,
			"revealed_now": false,
			"visited_now": false,
			"activated": outside_streaming_change.get("activated", []),
			"deactivated": outside_streaming_change.get("deactivated", []),
			"outside_world": true,
		}

	var visit_change: ModuleWorldStateRuntime.VisitChange = (
		_world_state.enter_module(next_coord)
	)
	var streaming_change: Dictionary = _refresh_active_modules(next_coord)
	return {
		"current_module": _coord_to_dict(next_coord),
		"local_cell": _coord_to_dict(module_and_local.get("local_cell", INVALID_COORD) as Vector2i),
		"entered": visit_change.entered(),
		"revealed_now": visit_change.revealed_now(),
		"visited_now": visit_change.visited_now(),
		"activated": streaming_change.get("activated", []),
		"deactivated": streaming_change.get("deactivated", []),
		"outside_world": false,
	}


func world_to_global_cell(world_position: Vector2) -> Vector2i:
	return _module_layout.world_to_global_cell(world_position)


func global_cell_to_world(global_cell: Vector2i) -> Vector2:
	return _module_layout.global_cell_to_world(global_cell)


func is_world_position_walkable(world_position: Vector2) -> bool:
	return _module_layout.is_world_position_walkable(world_position)


func navigation_query_to_active_target(from_world_position: Vector2) -> Dictionary:
	return _navigation_field.query_to_active_target(from_world_position)


func navigation_query(from_world_position: Vector2, target_world_position: Vector2) -> Dictionary:
	return _navigation_field.query(from_world_position, target_world_position)


func has_terrain_line_of_sight(from_world_position: Vector2, target_world_position: Vector2) -> bool:
	return _navigation_field.has_terrain_line_of_sight(from_world_position, target_world_position)


func has_clear_corridor(from_world_position: Vector2, target_world_position: Vector2, clearance: float) -> bool:
	return _navigation_field.has_clear_corridor(from_world_position, target_world_position, clearance)


func global_cell_to_module_and_local(global_cell: Vector2i) -> Dictionary:
	return _module_layout.global_cell_to_module_and_local(global_cell)


func module_local_to_global_cell(module_coord: Vector2i, local_cell: Vector2i) -> Vector2i:
	return _module_layout.module_local_to_global_cell(module_coord, local_cell)


func assignment() -> Dictionary:
	return _module_layout.assignment()


func assignment_at(module_coord: Vector2i) -> Dictionary:
	return _module_layout.assignment_at(module_coord)


func role_module_coord(role: String) -> Vector2i:
	return _module_layout.role_module_coord(role)


func placements_at(module_coord: Vector2i) -> Array[Dictionary]:
	return _module_layout.placements_at(module_coord)


## Returns effective, unoccupied floor-cell centers in stable row-major order.
## Static gameplay placement footprints are excluded after module rotation.
func empty_floor_positions_at(module_coord: Vector2i) -> Array[Vector2]:
	return _module_layout.empty_floor_positions_at(module_coord)


func map_hash() -> String:
	return _module_layout.map_hash()


func current_module_coord() -> Vector2i:
	return _world_state.current_module_coord()


func revealed_module_coords() -> Array[Vector2i]:
	return _world_state.revealed_module_coords()


func visited_module_coords() -> Array[Vector2i]:
	return _world_state.visited_module_coords()


func active_module_coords() -> Array[Vector2i]:
	return _chunk_streaming_controller.active_module_coords()


func is_module_revealed(module_coord: Vector2i) -> bool:
	return _world_state.is_module_revealed(module_coord)


func is_module_visited(module_coord: Vector2i) -> bool:
	return _world_state.is_module_visited(module_coord)


func is_module_active(module_coord: Vector2i) -> bool:
	return _chunk_streaming_controller.is_module_active(module_coord)


func set_slot_pinned(module_coord: Vector2i, pinned: bool) -> bool:
	if not _configured or not _is_module_coord_valid(module_coord):
		return false
	if not _module_layout.has_assignment_at(module_coord):
		return false
	var mutation_result: int = _world_state.mutate_pin(module_coord, pinned)
	match mutation_result:
		ModuleWorldStateRuntime.PinMutationResult.REJECTED:
			return false
		ModuleWorldStateRuntime.PinMutationResult.ACCEPTED_NO_REFRESH:
			return true
		ModuleWorldStateRuntime.PinMutationResult.ACCEPTED_REFRESH:
			_refresh_active_modules(current_module_coord())
		_:
			return false
	return true


func pinned_module_coords() -> Array[Vector2i]:
	return _world_state.pinned_module_coords()


func set_slot_state(module_coord: Vector2i, state: Dictionary) -> void:
	_world_state.set_slot_state(module_coord, state)


func slot_state(module_coord: Vector2i) -> Dictionary:
	return _world_state.slot_state(module_coord)


func snapshot() -> Dictionary:
	var state_fields: Dictionary = _world_state.snapshot_fields()
	return {
		"world_id": String(_world_def.get("id", "")),
		"run_seed": _module_layout.run_seed(),
		"assignment": _module_layout.assignment_entries(),
		"map_hash": _module_layout.map_hash(),
		"current_module": state_fields.get("current_module", {}),
		"revealed": state_fields.get("revealed", []),
		"visited": state_fields.get("visited", []),
		"pinned_slots": state_fields.get("pinned_slots", []),
		"slot_states": state_fields.get("slot_states", {}),
	}


func restore_state(state: Dictionary) -> bool:
	if not _configured:
		return false
	var saved_world_id: String = String(state.get("world_id", ""))
	var configured_world_id: String = String(_world_def.get("id", ""))
	if not saved_world_id.is_empty() and saved_world_id != configured_world_id:
		push_error("[ModuleWorldManager] snapshot world id does not match configured world")
		return false
	var restored_world_state: ModuleWorldStateRuntime.RestoreCandidate = (
		_world_state.prepare_restore(state)
	)
	if not restored_world_state.is_valid():
		return false
	var restored_layout: ModuleWorldLayoutRuntime.RestoreCandidate = (
		_module_layout.prepare_restore_assignment(
			state.get("assignment", []),
			int(state.get("run_seed", _module_layout.run_seed()))
		)
	)
	if not restored_layout.is_valid():
		return false
	var prepared_assignment: ModuleChunkStreamingControllerRuntime.PreparedAssignment = (
		_prepare_assignment_scenes(restored_layout.assignment_entries())
	)
	if not prepared_assignment.is_valid():
		return false
	var restored_hash: String = _module_layout.map_hash_for_candidate(
		restored_layout
	)
	var saved_hash: String = String(state.get("map_hash", ""))
	if not saved_hash.is_empty() and saved_hash != restored_hash:
		push_error("[ModuleWorldManager] snapshot map hash does not match assignment")
		return false
	if not _chunk_streaming_controller.commit_prepared(prepared_assignment):
		return false

	_chunk_streaming_controller.clear_active()
	_module_layout.commit_restore(restored_layout, restored_hash)
	_rebuild_navigation_field()
	_world_state.commit_restore(restored_world_state)
	if _is_module_coord_valid(current_module_coord()):
		_refresh_active_modules(current_module_coord())
	elif not pinned_module_coords().is_empty():
		_refresh_active_modules(INVALID_COORD)
	return true


func debug_summary() -> Dictionary:
	return {
		"world_id": String(_world_def.get("id", "")),
		"configured": _configured,
		"run_seed": _module_layout.run_seed(),
		"columns": WORLD_COLUMNS,
		"rows": WORLD_ROWS,
		"module_columns": MODULE_COLUMNS,
		"module_rows": MODULE_ROWS,
		"global_columns": WORLD_CELL_COLUMNS,
		"global_rows": WORLD_CELL_ROWS,
		"cell_size": _module_layout.cell_size(),
		"world_origin": _vector_to_dict(_module_layout.world_origin()),
		"assignment_count": _module_layout.assignment_count(),
		"map_hash": _module_layout.map_hash(),
		"current_module": _coord_to_dict(current_module_coord()) if _is_module_coord_valid(current_module_coord()) else {},
		"revealed_count": revealed_module_coords().size(),
		"visited_count": visited_module_coords().size(),
		"active_count": _chunk_streaming_controller.active_count(),
		"pinned_count": pinned_module_coords().size(),
		"pinned_slots": _coords_to_dict_array(pinned_module_coords()),
		"world_event_assignment_count": _module_layout.world_event_assignment_count(),
		"world_event_template_ids": _module_layout.world_event_template_ids(),
		"revealed_slots": _coords_to_dict_array(revealed_module_coords()),
		"visited_slots": _coords_to_dict_array(visited_module_coords()),
		"active_slots": _coords_to_dict_array(active_module_coords()),
		"chunk_pool_size": _chunk_streaming_controller.chunk_pool_size(),
		"preloaded_scene_count": _chunk_streaming_controller.preloaded_scene_count(),
		"navigation": _navigation_field.debug_summary(),
	}


func _world_random_port() -> ModuleWorldLayoutRuntime.RandomPort:
	return ModuleWorldLayoutRuntime.RandomPort.new(
		Callable(RNG.world, "snapshot"),
		Callable(RNG.world, "configure"),
		Callable(RNG.world, "restore_snapshot"),
		Callable(RNG.world, "randi"),
		Callable(RNG.world, "randf_range")
	)


func _finalize_assignment() -> bool:
	if not _module_layout.is_assignment_valid():
		return false
	var prepared_assignment: ModuleChunkStreamingControllerRuntime.PreparedAssignment = (
		_prepare_assignment_scenes(_module_layout.assignment_entries())
	)
	if not prepared_assignment.is_valid():
		return false
	var next_map_hash: String = _module_layout.compute_map_hash()
	if not _chunk_streaming_controller.commit_prepared(prepared_assignment):
		return false
	_module_layout.commit_map_hash(next_map_hash)
	_rebuild_navigation_field()
	return true


func _rebuild_navigation_field() -> void:
	var walkable := PackedByteArray()
	walkable.resize(WORLD_CELL_COLUMNS * WORLD_CELL_ROWS)
	for row_index: int in range(WORLD_CELL_ROWS):
		for column_index: int in range(WORLD_CELL_COLUMNS):
			var global_cell := Vector2i(column_index, row_index)
			var cell_index: int = row_index * WORLD_CELL_COLUMNS + column_index
			walkable[cell_index] = (
				1
				if _module_layout.is_global_cell_walkable(global_cell)
				else 0
			)
	if not _navigation_field.configure(
		walkable,
		WORLD_CELL_COLUMNS,
		WORLD_CELL_ROWS,
		_module_layout.cell_size(),
		_module_layout.world_origin(),
		WORLD_CENTER_GLOBAL_CELL,
		_navigation_flow_radius_cells
	):
		push_error("[ModuleWorldManager] navigation field could not be built from assignment")


func _refresh_active_modules(center_coord: Vector2i) -> Dictionary:
	var request := ModuleChunkStreamingControllerRuntime.StreamRequest.new()
	request.center_coord = center_coord
	request.pinned_coords = pinned_module_coords()
	request.columns = WORLD_COLUMNS
	request.rows = WORLD_ROWS
	request.active_radius = _active_radius
	request.cell_size = _module_layout.cell_size()
	request.world_origin = _module_layout.world_origin()
	request.assignment_provider = Callable(_module_layout, "assignment_at")
	request.masked_edges_provider = Callable(
		_module_layout,
		"masked_edges_for_coord"
	)
	var change: ModuleChunkStreamingControllerRuntime.StreamChange = (
		_chunk_streaming_controller.refresh(request)
	)
	for _failure_index: int in range(change.pool_exhausted_count()):
		push_error("[ModuleWorldManager] active chunk pool exhausted")
	return {
		"activated": _coords_to_dict_array(change.activated_coords()),
		"deactivated": _coords_to_dict_array(change.deactivated_coords()),
	}


func _module_chunk_children() -> Array[ModuleChunk]:
	var result: Array[ModuleChunk] = []
	for child: Node in get_children():
		if child is ModuleChunk:
			result.append(child as ModuleChunk)
	return result


func _reset_world_state() -> void:
	_chunk_streaming_controller.clear_active()
	_chunk_streaming_controller.clear_cache()
	_navigation_field.clear()
	_module_layout.reset()
	_world_state.reset()


func _has_valid_generated_scene_paths() -> bool:
	return _chunk_streaming_controller.has_valid_generated_scene_paths(
		_module_layout.template_ids()
	)


func _prepare_assignment_scenes(
	assignment_entries: Array[Dictionary]
) -> ModuleChunkStreamingControllerRuntime.PreparedAssignment:
	var prepared: ModuleChunkStreamingControllerRuntime.PreparedAssignment = (
		_chunk_streaming_controller.prepare_assignment(
			assignment_entries
		)
	)
	match prepared.error_code():
		ModuleChunkStreamingControllerRuntime.PrepareError.LOAD_FAILED:
			push_error(
				"[ModuleWorldManager] failed to preload generated scene %s"
				% prepared.template_id()
			)
		ModuleChunkStreamingControllerRuntime.PrepareError.ROOT_INVALID:
			push_error(
				"[ModuleWorldManager] %s root is not GeneratedModuleScene"
				% prepared.template_id()
			)
		ModuleChunkStreamingControllerRuntime.PrepareError.METADATA_STALE:
			push_error(
				"[ModuleWorldManager] %s metadata is stale"
				% prepared.template_id()
			)
		_:
			pass
	return prepared


func _is_module_coord_valid(module_coord: Vector2i) -> bool:
	return _module_layout.is_module_coord_valid(module_coord)


func _coord_to_dict(coord: Vector2i) -> Dictionary:
	return _world_state.coord_to_wire(coord)


func _coords_to_dict_array(coords: Array[Vector2i]) -> Array[Dictionary]:
	return _world_state.coords_to_wire(coords)


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}
