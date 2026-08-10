# Doc: docs/代码/module_world_manager.md
class_name ModuleWorldState
extends RefCounted
## Pure dynamic-state owner for the module world.
## Layout, assignment, hashing, navigation and streaming stay with ModuleWorldManager.

enum PinMutationResult {
	REJECTED,
	ACCEPTED_NO_REFRESH,
	ACCEPTED_REFRESH,
}

const ModuleSlotStateCodecRuntime := preload(
	"res://scripts/gameplay/module_slot_state_codec.gd"
)


class VisitChange extends RefCounted:
	var _entered: bool = false
	var _revealed_now: bool = false
	var _visited_now: bool = false


	func entered() -> bool:
		return _entered


	func revealed_now() -> bool:
		return _revealed_now


	func visited_now() -> bool:
		return _visited_now


	func _succeed(
		entered_value: bool,
		revealed_now_value: bool,
		visited_now_value: bool
	) -> void:
		_entered = entered_value
		_revealed_now = revealed_now_value
		_visited_now = visited_now_value


class RestoreCandidate extends RefCounted:
	var _is_valid: bool = false
	var _columns: int = 0
	var _rows: int = 0
	var _max_pinned_slots: int = 0
	var _current_module_coord: Vector2i = Vector2i(-1, -1)
	var _revealed: Dictionary = {}
	var _visited: Dictionary = {}
	var _pinned_slots: Dictionary = {}
	var _slot_states: Dictionary = {}


	func is_valid() -> bool:
		return _is_valid


	func _succeed(
		columns: int,
		rows: int,
		max_pinned_slots: int,
		current_module_coord: Vector2i,
		revealed: Dictionary,
		visited: Dictionary,
		pinned_slots: Dictionary,
		slot_states: Dictionary
	) -> void:
		_is_valid = true
		_columns = columns
		_rows = rows
		_max_pinned_slots = max_pinned_slots
		_current_module_coord = current_module_coord
		_revealed = revealed.duplicate()
		_visited = visited.duplicate()
		_pinned_slots = pinned_slots.duplicate()
		_slot_states = slot_states.duplicate(true)


	func _matches_configuration(
		columns: int,
		rows: int,
		max_pinned_slots: int
	) -> bool:
		return (
			_is_valid
			and _columns == columns
			and _rows == rows
			and _max_pinned_slots == max_pinned_slots
		)


	func _revealed_copy() -> Dictionary:
		return _revealed.duplicate()


	func _visited_copy() -> Dictionary:
		return _visited.duplicate()


	func _pinned_slots_copy() -> Dictionary:
		return _pinned_slots.duplicate()


	func _slot_states_copy() -> Dictionary:
		return _slot_states.duplicate(true)


var _columns: int = 0
var _rows: int = 0
var _max_pinned_slots: int = 0
var _invalid_coord: Vector2i = Vector2i(-1, -1)
var _current_module_coord: Vector2i = Vector2i(-1, -1)
var _revealed: Dictionary = {}
var _visited: Dictionary = {}
var _pinned_slots: Dictionary = {}
var _slot_state_codec: ModuleSlotStateCodecRuntime = ModuleSlotStateCodecRuntime.new()


func _init(
	columns: int = 0,
	rows: int = 0,
	max_pinned_slots: int = 0,
	invalid_coord: Vector2i = Vector2i(-1, -1)
) -> void:
	_columns = maxi(columns, 0)
	_rows = maxi(rows, 0)
	_max_pinned_slots = maxi(max_pinned_slots, 0)
	_invalid_coord = invalid_coord
	_current_module_coord = _invalid_coord
	_slot_state_codec.configure(_columns, _rows)


func reset() -> void:
	_current_module_coord = _invalid_coord
	_revealed.clear()
	_visited.clear()
	_pinned_slots.clear()
	_slot_state_codec.clear_states()


func enter_module(module_coord: Vector2i) -> VisitChange:
	var change := VisitChange.new()
	if not is_coord_valid(module_coord):
		return change
	var entered: bool = module_coord != _current_module_coord
	var key: String = slot_key(module_coord)
	var revealed_now: bool = not _revealed.has(key)
	var visited_now: bool = not _visited.has(key)
	_current_module_coord = module_coord
	_revealed[key] = true
	_visited[key] = true
	change._succeed(entered, revealed_now, visited_now)
	return change


func leave_world() -> void:
	_current_module_coord = _invalid_coord


func current_module_coord() -> Vector2i:
	return _current_module_coord


func revealed_module_coords() -> Array[Vector2i]:
	return _slot_state_codec.coords_from_set(_revealed)


func visited_module_coords() -> Array[Vector2i]:
	return _slot_state_codec.coords_from_set(_visited)


func is_module_revealed(module_coord: Vector2i) -> bool:
	return _revealed.has(slot_key(module_coord))


func is_module_visited(module_coord: Vector2i) -> bool:
	return _visited.has(slot_key(module_coord))


func mutate_pin(module_coord: Vector2i, pinned: bool) -> int:
	if not is_coord_valid(module_coord):
		return PinMutationResult.REJECTED
	var key: String = slot_key(module_coord)
	if pinned:
		if _pinned_slots.has(key):
			return PinMutationResult.ACCEPTED_NO_REFRESH
		if _pinned_slots.size() >= _max_pinned_slots:
			return PinMutationResult.REJECTED
		_pinned_slots[key] = true
		return PinMutationResult.ACCEPTED_REFRESH
	_pinned_slots.erase(key)
	return PinMutationResult.ACCEPTED_REFRESH


func pinned_module_coords() -> Array[Vector2i]:
	return _slot_state_codec.coords_from_set(_pinned_slots)


func set_slot_state(module_coord: Vector2i, state: Dictionary) -> void:
	_slot_state_codec.set_state(module_coord, state)


func slot_state(module_coord: Vector2i) -> Dictionary:
	return _slot_state_codec.state(module_coord)


func snapshot_fields() -> Dictionary:
	return {
		"current_module": (
			coord_to_wire(_current_module_coord)
			if is_coord_valid(_current_module_coord)
			else {}
		),
		"revealed": coords_to_wire(revealed_module_coords()),
		"visited": coords_to_wire(visited_module_coords()),
		"pinned_slots": coords_to_wire(pinned_module_coords()),
		"slot_states": _slot_state_codec.ordered_states(),
	}


func prepare_restore(state: Dictionary) -> RestoreCandidate:
	var candidate := RestoreCandidate.new()
	var pinned_result: Dictionary = _slot_state_codec.validate_pinned_slots(
		state.get("pinned_slots", []),
		_max_pinned_slots
	)
	if not bool(pinned_result.get("is_valid", false)):
		return candidate
	var candidate_codec: ModuleSlotStateCodecRuntime = (
		ModuleSlotStateCodecRuntime.new(_columns, _rows)
	)
	candidate_codec.restore_states(state.get("slot_states", {}))
	candidate._succeed(
		_columns,
		_rows,
		_max_pinned_slots,
		coord_from_wire(state.get("current_module", {}), _invalid_coord),
		_slot_state_codec.set_from_wire(state.get("revealed", [])),
		_slot_state_codec.set_from_wire(state.get("visited", [])),
		(pinned_result.get("pinned_slots", {}) as Dictionary),
		candidate_codec.ordered_states()
	)
	return candidate


## Commits a fully prepared dynamic-state snapshot without validation or I/O.
## Callers validate the candidate before committing external assignment/cache state.
func commit_restore(candidate: RestoreCandidate) -> void:
	if (
		candidate == null
		or not candidate._matches_configuration(
			_columns,
			_rows,
			_max_pinned_slots
		)
	):
		return
	var next_codec: ModuleSlotStateCodecRuntime = (
		ModuleSlotStateCodecRuntime.new(_columns, _rows)
	)
	next_codec.restore_states(candidate._slot_states_copy())
	_current_module_coord = candidate._current_module_coord
	_revealed = candidate._revealed_copy()
	_visited = candidate._visited_copy()
	_pinned_slots = candidate._pinned_slots_copy()
	_slot_state_codec = next_codec


func is_coord_valid(module_coord: Vector2i) -> bool:
	return _slot_state_codec.is_coord_valid(module_coord)


func slot_key(module_coord: Vector2i) -> String:
	return _slot_state_codec.slot_key(module_coord)


func coord_to_wire(module_coord: Vector2i) -> Dictionary:
	return _slot_state_codec.coord_to_wire(module_coord)


func coords_to_wire(coords: Array[Vector2i]) -> Array[Dictionary]:
	return _slot_state_codec.coords_to_wire(coords)


func coord_from_wire(raw_value: Variant, fallback: Vector2i) -> Vector2i:
	return _slot_state_codec.coord_from_wire(raw_value, fallback)
