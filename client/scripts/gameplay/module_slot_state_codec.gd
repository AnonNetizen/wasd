# Doc: docs/代码/module_world_manager.md
class_name ModuleSlotStateCodec
extends RefCounted
## Pure wire codec and deep-copy store for module-slot coordinates and payloads.


class SlotState extends RefCounted:
	var _payload: Dictionary = {}


	func _init(payload: Dictionary = {}) -> void:
		_payload = payload.duplicate(true)


	func payload() -> Dictionary:
		return _payload.duplicate(true)


	func initialized() -> bool:
		return bool(_payload.get("initialized", false))


	func encounter() -> Dictionary:
		return _dictionary_or_empty(_payload.get("enemy_encounter", {}))


	func snapshots(field_name: String) -> Array:
		var raw_value: Variant = _payload.get(field_name, [])
		if raw_value is Array:
			return (raw_value as Array).duplicate(true)
		return []


	func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
		if raw_value is Dictionary:
			return (raw_value as Dictionary).duplicate(true)
		return {}


var _columns: int = 0
var _rows: int = 0
var _states_by_slot: Dictionary = {}


func _init(columns: int = 0, rows: int = 0) -> void:
	configure(columns, rows)


func configure(columns: int, rows: int) -> void:
	_columns = maxi(columns, 0)
	_rows = maxi(rows, 0)
	_states_by_slot.clear()


func is_coord_valid(module_coord: Vector2i) -> bool:
	return (
		module_coord.x >= 0
		and module_coord.y >= 0
		and module_coord.x < _columns
		and module_coord.y < _rows
	)


func slot_key(module_coord: Vector2i) -> String:
	return "%d,%d" % [module_coord.x, module_coord.y]


func coord_to_wire(module_coord: Vector2i) -> Dictionary:
	return {
		"x": module_coord.x,
		"y": module_coord.y,
	}


func coord_from_wire(raw_value: Variant, fallback: Vector2i) -> Vector2i:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2i(
		int(value.get("x", fallback.x)),
		int(value.get("y", fallback.y))
	)


func coords_from_set(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for row_index: int in range(_rows):
		for column_index: int in range(_columns):
			var module_coord := Vector2i(column_index, row_index)
			if source.has(slot_key(module_coord)):
				result.append(module_coord)
	return result


func coords_to_wire(coords: Array[Vector2i]) -> Array[Dictionary]:
	var membership: Dictionary = {}
	for module_coord: Vector2i in coords:
		if is_coord_valid(module_coord):
			membership[slot_key(module_coord)] = true
	var result: Array[Dictionary] = []
	for module_coord: Vector2i in coords_from_set(membership):
		result.append(coord_to_wire(module_coord))
	return result


func set_from_wire(raw_value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not raw_value is Array:
		return result
	for raw_coord: Variant in raw_value as Array:
		var module_coord: Vector2i = coord_from_wire(raw_coord, Vector2i(-1, -1))
		if is_coord_valid(module_coord):
			result[slot_key(module_coord)] = true
	return result


func validate_pinned_slots(raw_value: Variant, max_pinned_slots: int) -> Dictionary:
	var result: Dictionary = {
		"is_valid": false,
		"pinned_slots": {},
	}
	if not raw_value is Array or max_pinned_slots < 0:
		return result
	var pinned_slots: Dictionary = {}
	for raw_coord: Variant in raw_value as Array:
		var module_coord: Vector2i = coord_from_wire(
			raw_coord,
			Vector2i(-1, -1)
		)
		if not is_coord_valid(module_coord):
			return result
		var key: String = slot_key(module_coord)
		if pinned_slots.has(key):
			return result
		pinned_slots[key] = true
	if pinned_slots.size() > max_pinned_slots:
		return result
	result["is_valid"] = true
	result["pinned_slots"] = pinned_slots
	return result


func set_state(module_coord: Vector2i, payload: Dictionary) -> void:
	if not is_coord_valid(module_coord):
		return
	_states_by_slot[slot_key(module_coord)] = SlotState.new(payload)


func state(module_coord: Vector2i) -> Dictionary:
	var typed_state: SlotState = typed_state_at(module_coord)
	if typed_state == null:
		return {}
	return typed_state.payload()


func typed_state_at(module_coord: Vector2i) -> SlotState:
	if not is_coord_valid(module_coord):
		return null
	var raw_state: Variant = _states_by_slot.get(slot_key(module_coord))
	if raw_state is SlotState:
		return raw_state as SlotState
	return null


func restore_states(raw_value: Variant) -> void:
	_states_by_slot.clear()
	if not raw_value is Dictionary:
		return
	var source: Dictionary = raw_value as Dictionary
	for row_index: int in range(_rows):
		for column_index: int in range(_columns):
			var module_coord := Vector2i(column_index, row_index)
			var key: String = slot_key(module_coord)
			var raw_payload: Variant = source.get(key)
			if raw_payload is Dictionary:
				_states_by_slot[key] = SlotState.new(raw_payload as Dictionary)


func ordered_states() -> Dictionary:
	var result: Dictionary = {}
	for module_coord: Vector2i in coords_from_set(_states_by_slot):
		var typed_state: SlotState = typed_state_at(module_coord)
		if typed_state != null:
			result[slot_key(module_coord)] = typed_state.payload()
	return result


func clear_states() -> void:
	_states_by_slot.clear()
