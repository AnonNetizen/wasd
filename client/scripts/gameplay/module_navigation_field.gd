# Doc: docs/代码/module_world_manager.md
class_name ModuleNavigationField
extends RefCounted
## Full-world static navigation derived from a module assignment. No scene nodes are created per cell.

const DISTANCE_EPSILON: float = 0.001
const INVALID_CELL: Vector2i = Vector2i(-1, -1)
const INVALID_INDEX: int = -1
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i(1, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]

var _active_target_cell: Vector2i = INVALID_CELL
var _active_target_position: Vector2 = Vector2.ZERO
var _astar: AStarGrid2D = AStarGrid2D.new()
var _cell_size: float = 1.0
var _columns: int = 0
var _distances: PackedFloat64Array = PackedFloat64Array()
var _flow_rebuild_count: int = 0
var _next_indices: PackedInt32Array = PackedInt32Array()
var _origin: Vector2 = Vector2.ZERO
var _reachable_count: int = 0
var _rows: int = 0
var _world_center_cell: Vector2i = Vector2i.ZERO
var _walkable: PackedByteArray = PackedByteArray()


func configure(
	walkable: PackedByteArray,
	columns: int,
	rows: int,
	cell_size: float,
	origin: Vector2,
	world_center_cell: Vector2i
) -> bool:
	clear()
	if columns <= 0 or rows <= 0 or cell_size <= 0.0 or walkable.size() != columns * rows:
		return false
	_columns = columns
	_rows = rows
	_cell_size = cell_size
	_origin = origin
	_world_center_cell = world_center_cell
	_walkable = walkable.duplicate()
	_distances.resize(_walkable.size())
	_next_indices.resize(_walkable.size())
	_configure_astar()
	_reset_flow_arrays()
	return true


func clear() -> void:
	_active_target_cell = INVALID_CELL
	_active_target_position = Vector2.ZERO
	_astar = AStarGrid2D.new()
	_cell_size = 1.0
	_columns = 0
	_distances = PackedFloat64Array()
	_flow_rebuild_count = 0
	_next_indices = PackedInt32Array()
	_origin = Vector2.ZERO
	_reachable_count = 0
	_rows = 0
	_world_center_cell = Vector2i.ZERO
	_walkable = PackedByteArray()


func set_active_target(target_position: Vector2) -> bool:
	_active_target_position = target_position
	var target_cell: Vector2i = world_to_cell(target_position)
	if not is_cell_walkable(target_cell):
		_active_target_cell = INVALID_CELL
		_reset_flow_arrays()
		return false
	if target_cell != _active_target_cell:
		_active_target_cell = target_cell
		_rebuild_flow_field()
	return true


func query_to_active_target(from_position: Vector2) -> Dictionary:
	if not is_cell_walkable(_active_target_cell):
		return _unreachable_query(_active_target_position)
	var from_cell: Vector2i = world_to_cell(from_position)
	if not is_cell_walkable(from_cell):
		return _unreachable_query(_active_target_position)
	if from_cell == _active_target_cell:
		return {
			"reachable": true,
			"distance": from_position.distance_to(_active_target_position),
			"next_position": _active_target_position,
			"target_position": _active_target_position,
		}
	var from_index: int = _cell_index(from_cell)
	var route_distance: float = _distances[from_index]
	var next_index: int = _next_indices[from_index]
	if is_inf(route_distance) or next_index == INVALID_INDEX:
		return _unreachable_query(_active_target_position)
	var distance: float = route_distance
	distance += from_position.distance_to(cell_to_world(from_cell))
	distance += _active_target_position.distance_to(cell_to_world(_active_target_cell))
	return {
		"reachable": true,
		"distance": distance,
		"next_position": cell_to_world(_index_to_cell(next_index)),
		"target_position": _active_target_position,
	}


func query(from_position: Vector2, target_position: Vector2) -> Dictionary:
	var from_cell: Vector2i = world_to_cell(from_position)
	var target_cell: Vector2i = world_to_cell(target_position)
	if not is_cell_walkable(from_cell) or not is_cell_walkable(target_cell):
		return _unreachable_query(target_position)
	if from_cell == target_cell:
		return {
			"reachable": true,
			"distance": from_position.distance_to(target_position),
			"next_position": target_position,
			"target_position": target_position,
		}
	var id_path: Array[Vector2i] = _astar.get_id_path(from_cell, target_cell, false)
	if id_path.size() < 2:
		return _unreachable_query(target_position)
	var distance: float = from_position.distance_to(cell_to_world(from_cell))
	for path_index: int in range(1, id_path.size()):
		distance += cell_to_world(id_path[path_index - 1]).distance_to(cell_to_world(id_path[path_index]))
	distance += cell_to_world(target_cell).distance_to(target_position)
	return {
		"reachable": true,
		"distance": distance,
		"next_position": cell_to_world(id_path[1]),
		"target_position": target_position,
	}


func has_terrain_line_of_sight(from_position: Vector2, target_position: Vector2) -> bool:
	return has_clear_corridor(from_position, target_position, 0.0)


func has_clear_corridor(from_position: Vector2, target_position: Vector2, clearance: float) -> bool:
	if not is_cell_walkable(world_to_cell(from_position)) or not is_cell_walkable(world_to_cell(target_position)):
		return false
	var safe_clearance: float = maxf(clearance, 0.0)
	var minimum: Vector2 = Vector2(
		minf(from_position.x, target_position.x) - safe_clearance,
		minf(from_position.y, target_position.y) - safe_clearance
	)
	var maximum: Vector2 = Vector2(
		maxf(from_position.x, target_position.x) + safe_clearance,
		maxf(from_position.y, target_position.y) + safe_clearance
	)
	var minimum_cell: Vector2i = world_to_cell(minimum)
	var maximum_cell: Vector2i = world_to_cell(maximum)
	minimum_cell.x = clampi(minimum_cell.x, 0, _columns - 1)
	minimum_cell.y = clampi(minimum_cell.y, 0, _rows - 1)
	maximum_cell.x = clampi(maximum_cell.x, 0, _columns - 1)
	maximum_cell.y = clampi(maximum_cell.y, 0, _rows - 1)
	for row: int in range(minimum_cell.y, maximum_cell.y + 1):
		for column: int in range(minimum_cell.x, maximum_cell.x + 1):
			var cell := Vector2i(column, row)
			if is_cell_walkable(cell):
				continue
			var center: Vector2 = cell_to_world(cell)
			var blocked_rect := Rect2(
				center - Vector2.ONE * (_cell_size * 0.5 + safe_clearance),
				Vector2.ONE * (_cell_size + safe_clearance * 2.0)
			)
			if _segment_intersects_rect(from_position, target_position, blocked_rect):
				return false
	return true


func world_to_cell(world_position: Vector2) -> Vector2i:
	var relative_position: Vector2 = world_position - _origin
	return Vector2i(
		int(floorf(relative_position.x / _cell_size + float(_world_center_cell.x) + 0.5)),
		int(floorf(relative_position.y / _cell_size + float(_world_center_cell.y) + 0.5))
	)


func cell_to_world(cell: Vector2i) -> Vector2:
	return _origin + Vector2(
		float(cell.x - _world_center_cell.x) * _cell_size,
		float(cell.y - _world_center_cell.y) * _cell_size
	)


func is_cell_walkable(cell: Vector2i) -> bool:
	return _is_cell_valid(cell) and _walkable[_cell_index(cell)] != 0


func debug_summary() -> Dictionary:
	return {
		"active_target_cell": _coord_to_dict(_active_target_cell) if _is_cell_valid(_active_target_cell) else {},
		"flow_rebuild_count": _flow_rebuild_count,
		"reachable_count": _reachable_count,
		"walkable_count": _walkable_count(),
	}


func _configure_astar() -> void:
	_astar.region = Rect2i(0, 0, _columns, _rows)
	_astar.cell_size = Vector2.ONE * _cell_size
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for row: int in range(_rows):
		for column: int in range(_columns):
			var cell := Vector2i(column, row)
			if not is_cell_walkable(cell):
				_astar.set_point_solid(cell, true)


func _rebuild_flow_field() -> void:
	_reset_flow_arrays()
	if not is_cell_walkable(_active_target_cell):
		return
	_flow_rebuild_count += 1
	var target_index: int = _cell_index(_active_target_cell)
	_distances[target_index] = 0.0
	_next_indices[target_index] = target_index
	var heap: Array[Dictionary] = []
	_heap_push(heap, 0.0, target_index)
	while not heap.is_empty():
		var current: Dictionary = _heap_pop(heap)
		var current_distance: float = float(current.get("distance", INF))
		var current_index: int = int(current.get("index", INVALID_INDEX))
		if current_index == INVALID_INDEX or current_distance > _distances[current_index] + DISTANCE_EPSILON:
			continue
		var current_cell: Vector2i = _index_to_cell(current_index)
		for offset: Vector2i in NEIGHBOR_OFFSETS:
			var neighbor_cell: Vector2i = current_cell + offset
			if not _can_traverse(neighbor_cell, current_cell):
				continue
			var neighbor_index: int = _cell_index(neighbor_cell)
			var step_distance: float = _cell_size * (sqrt(2.0) if offset.x != 0 and offset.y != 0 else 1.0)
			var candidate_distance: float = current_distance + step_distance
			var distance_improved: bool = candidate_distance < _distances[neighbor_index] - DISTANCE_EPSILON
			var tie_improved: bool = (
				is_equal_approx(candidate_distance, _distances[neighbor_index])
				and (_next_indices[neighbor_index] == INVALID_INDEX or current_index < _next_indices[neighbor_index])
			)
			if not distance_improved and not tie_improved:
				continue
			_distances[neighbor_index] = candidate_distance
			_next_indices[neighbor_index] = current_index
			_heap_push(heap, candidate_distance, neighbor_index)
	_reachable_count = 0
	for distance: float in _distances:
		if not is_inf(distance):
			_reachable_count += 1


func _reset_flow_arrays() -> void:
	_reachable_count = 0
	for index: int in range(_distances.size()):
		_distances[index] = INF
		_next_indices[index] = INVALID_INDEX


func _can_traverse(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not is_cell_walkable(from_cell) or not is_cell_walkable(to_cell):
		return false
	var offset: Vector2i = to_cell - from_cell
	if offset.x == 0 or offset.y == 0:
		return true
	return (
		is_cell_walkable(from_cell + Vector2i(offset.x, 0))
		and is_cell_walkable(from_cell + Vector2i(0, offset.y))
	)


func _heap_push(heap: Array[Dictionary], distance: float, index: int) -> void:
	heap.append({"distance": distance, "index": index})
	var child_index: int = heap.size() - 1
	while child_index > 0:
		var parent_index: int = (child_index - 1) / 2
		if not _heap_entry_less(heap[child_index], heap[parent_index]):
			break
		var swap_entry: Dictionary = heap[parent_index]
		heap[parent_index] = heap[child_index]
		heap[child_index] = swap_entry
		child_index = parent_index


func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = last
	var parent_index: int = 0
	while true:
		var left_index: int = parent_index * 2 + 1
		if left_index >= heap.size():
			break
		var right_index: int = left_index + 1
		var smallest_index: int = left_index
		if right_index < heap.size() and _heap_entry_less(heap[right_index], heap[left_index]):
			smallest_index = right_index
		if not _heap_entry_less(heap[smallest_index], heap[parent_index]):
			break
		var swap_entry: Dictionary = heap[parent_index]
		heap[parent_index] = heap[smallest_index]
		heap[smallest_index] = swap_entry
		parent_index = smallest_index
	return result


func _heap_entry_less(left: Dictionary, right: Dictionary) -> bool:
	var left_distance: float = float(left.get("distance", INF))
	var right_distance: float = float(right.get("distance", INF))
	if left_distance < right_distance - DISTANCE_EPSILON:
		return true
	if left_distance > right_distance + DISTANCE_EPSILON:
		return false
	return int(left.get("index", INVALID_INDEX)) < int(right.get("index", INVALID_INDEX))


func _segment_intersects_rect(from_position: Vector2, target_position: Vector2, rect: Rect2) -> bool:
	var direction: Vector2 = target_position - from_position
	var minimum: Vector2 = rect.position
	var maximum: Vector2 = rect.end
	var interval := Vector2(0.0, 1.0)
	var x_clip: Vector3 = _clip_segment_axis(from_position.x, direction.x, minimum.x, maximum.x, interval)
	if x_clip.z < 0.5:
		return false
	interval = Vector2(x_clip.x, x_clip.y)
	var y_clip: Vector3 = _clip_segment_axis(from_position.y, direction.y, minimum.y, maximum.y, interval)
	if y_clip.z < 0.5:
		return false
	return y_clip.x <= y_clip.y + DISTANCE_EPSILON


func _clip_segment_axis(origin: float, delta: float, minimum: float, maximum: float, interval: Vector2) -> Vector3:
	if is_zero_approx(delta):
		return Vector3(interval.x, interval.y, 1.0 if origin >= minimum and origin <= maximum else 0.0)
	var first: float = (minimum - origin) / delta
	var second: float = (maximum - origin) / delta
	if first > second:
		var swap_value: float = first
		first = second
		second = swap_value
	interval.x = maxf(interval.x, first)
	interval.y = minf(interval.y, second)
	return Vector3(interval.x, interval.y, 1.0 if interval.x <= interval.y + DISTANCE_EPSILON else 0.0)


func _walkable_count() -> int:
	var result: int = 0
	for value: int in _walkable:
		if value != 0:
			result += 1
	return result


func _cell_index(cell: Vector2i) -> int:
	return cell.y * _columns + cell.x


func _index_to_cell(index: int) -> Vector2i:
	return Vector2i(index % _columns, index / _columns)


func _is_cell_valid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _columns and cell.y < _rows


func _unreachable_query(target_position: Vector2) -> Dictionary:
	return {
		"reachable": false,
		"distance": INF,
		"next_position": Vector2.ZERO,
		"target_position": target_position,
	}


func _coord_to_dict(coord: Vector2i) -> Dictionary:
	return {"x": coord.x, "y": coord.y}
