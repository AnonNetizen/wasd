# Doc: docs/代码/map_manager.md
# Authority: docs/游戏设计文档.md §5, docs/决策记录.md ADR #93 / ADR #105
class_name MapManager
extends Node2D


const BOUNDS_COLOR: Color = Color(0.48, 0.62, 0.70, 0.62)
const BOUNDS_FILL_COLOR: Color = Color(0.08, 0.10, 0.11, 0.12)
const BOUNDS_WIDTH: float = 4.0
const DEFAULT_BOUNDS_SIZE: Vector2 = Vector2(3200.0, 2200.0)
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 80.0)
const INVALID_POSITION: Vector2 = Vector2(1.0e20, 1.0e20)
const MANUAL_SOURCE: String = "manual"
const PCG_SOURCE: String = "pcg"
const PLACEMENT_ATTEMPTS_PER_HAZARD: int = 32
const SAFE_RADIUS_COLOR: Color = Color(0.40, 0.78, 0.66, 0.18)
const SPAWN_EDGE_PADDING: float = 16.0

var _bounds: Rect2 = Rect2(-DEFAULT_BOUNDS_SIZE * 0.5, DEFAULT_BOUNDS_SIZE)
var _enemy_spawn_margin: float = 128.0
var _hazard_rows: Dictionary = {}
var _hazard_placements: Array[Dictionary] = []
var _grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE
var _layout_id: String = ""
var _player_start: Vector2 = Vector2.ZERO
var _safe_radius: float = 0.0


func configure(layout_data: Dictionary, hazard_rows: Dictionary) -> void:
	_hazard_rows = hazard_rows.duplicate(true)
	_layout_id = String(layout_data.get("id", ""))
	_grid_cell_size = _parse_grid(layout_data.get("grid", {}))
	_safe_radius = maxf(float(layout_data.get("safe_radius", 0.0)), 0.0)
	_enemy_spawn_margin = maxf(float(layout_data.get("enemy_spawn_margin", 0.0)), 0.0)
	_bounds = _parse_bounds(layout_data.get("bounds", {}))
	_player_start = clamp_position(snap_to_grid(_dict_to_vector(layout_data.get("player_start", {}), Vector2.ZERO)))
	_hazard_placements.clear()
	queue_redraw()


func generate_hazard_placements(layout_data: Dictionary) -> Array[Dictionary]:
	_hazard_placements.clear()
	_add_manual_hazards(layout_data.get("manual_hazards", []))
	var pcg: Dictionary = _dictionary_or_empty(layout_data.get("pcg", {}))
	_add_pcg_hazards(pcg.get("hazards", []))
	queue_redraw()
	return hazard_placements()


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_layout_id = String(snapshot_data.get("layout_id", _layout_id))
	_bounds = _dict_to_rect(snapshot_data.get("bounds", {}), _bounds)
	_grid_cell_size = _dict_to_vector(snapshot_data.get("grid_cell_size", {}), _grid_cell_size)
	_player_start = clamp_position(snap_to_grid(_dict_to_vector(snapshot_data.get("player_start", {}), _player_start)))
	_safe_radius = maxf(float(snapshot_data.get("safe_radius", _safe_radius)), 0.0)
	_enemy_spawn_margin = maxf(float(snapshot_data.get("enemy_spawn_margin", _enemy_spawn_margin)), 0.0)
	_hazard_placements = _typed_placements(snapshot_data.get("hazard_placements", []))
	queue_redraw()


func snapshot() -> Dictionary:
	return {
		"layout_id": _layout_id,
		"bounds": _rect_to_dict(_bounds),
		"grid_cell_size": _vector_to_dict(_grid_cell_size),
		"player_start": _vector_to_dict(_player_start),
		"safe_radius": _safe_radius,
		"enemy_spawn_margin": _enemy_spawn_margin,
		"hazard_placements": _hazard_placements.duplicate(true),
	}


func layout_id() -> String:
	return _layout_id


func bounds() -> Rect2:
	return _bounds


func grid_cell_size() -> Vector2:
	return _grid_cell_size


func player_start() -> Vector2:
	return clamp_position(_player_start)


func hazard_placements() -> Array[Dictionary]:
	return _hazard_placements.duplicate(true)


func boundary_points() -> PackedVector2Array:
	return _boundary_points()


func clamp_position(world_position: Vector2) -> Vector2:
	return Vector2(
		clampf(world_position.x, _bounds.position.x, _bounds.end.x),
		clampf(world_position.y, _bounds.position.y, _bounds.end.y)
	)


func snap_to_grid(world_position: Vector2) -> Vector2:
	var grid_index: Vector2i = _grid_index(world_position)
	return _grid_position(grid_index)


func normalize_hazard_position(world_position: Vector2, hazard_id: String) -> Vector2:
	return _normalize_hazard_position(world_position, hazard_id)


func spawn_position(player_position: Vector2, viewport_size: Vector2) -> Vector2:
	var radius: float = maxf(viewport_size.x, viewport_size.y) * 0.55
	var spawn_bounds: Rect2 = _bounds.grow(-maxf(_enemy_spawn_margin, SPAWN_EDGE_PADDING))
	if spawn_bounds.size.x <= 0.0 or spawn_bounds.size.y <= 0.0:
		spawn_bounds = _bounds.grow(-SPAWN_EDGE_PADDING)
	var angle: float = RNG.spawn.randf_range(0.0, TAU)
	var candidate: Vector2 = player_position + Vector2.RIGHT.rotated(angle) * radius
	return Vector2(
		clampf(candidate.x, spawn_bounds.position.x, spawn_bounds.end.x),
		clampf(candidate.y, spawn_bounds.position.y, spawn_bounds.end.y)
	)


func debug_summary() -> Dictionary:
	return {
		"layout_id": _layout_id,
		"bounds": _rect_to_dict(_bounds),
		"grid_cell_size": _vector_to_dict(_grid_cell_size),
		"boundary_shape": "diamond",
		"boundary_points": _points_to_array(_boundary_points()),
		"hazard_count": _hazard_placements.size(),
		"safe_radius": _safe_radius,
	}


func _draw() -> void:
	var points: PackedVector2Array = _boundary_points()
	draw_colored_polygon(points, BOUNDS_FILL_COLOR)
	_draw_polygon_outline(points, BOUNDS_COLOR, BOUNDS_WIDTH)
	if _safe_radius > 0.0:
		draw_arc(_player_start, _safe_radius, 0.0, TAU, 96, SAFE_RADIUS_COLOR, 2.0)


func _parse_bounds(raw_value: Variant) -> Rect2:
	var data: Dictionary = _dictionary_or_empty(raw_value)
	var size: Vector2 = Vector2(
		maxf(float(data.get("width", DEFAULT_BOUNDS_SIZE.x)), 1.0),
		maxf(float(data.get("height", DEFAULT_BOUNDS_SIZE.y)), 1.0)
	)
	return Rect2(-size * 0.5, size)


func _parse_grid(raw_value: Variant) -> Vector2:
	var data: Dictionary = _dictionary_or_empty(raw_value)
	return Vector2(
		maxf(float(data.get("cell_width", DEFAULT_GRID_CELL_SIZE.x)), 1.0),
		maxf(float(data.get("cell_height", DEFAULT_GRID_CELL_SIZE.y)), 1.0)
	)


func _boundary_points() -> PackedVector2Array:
	var center: Vector2 = _bounds.get_center()
	return PackedVector2Array([
		Vector2(center.x, _bounds.position.y),
		Vector2(_bounds.end.x, center.y),
		Vector2(center.x, _bounds.end.y),
		Vector2(_bounds.position.x, center.y),
	])


func _draw_polygon_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index: int in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width)


func _add_manual_hazards(raw_value: Variant) -> void:
	for raw_hazard: Variant in _array_or_empty(raw_value):
		if not raw_hazard is Dictionary:
			continue
		var hazard_data: Dictionary = raw_hazard as Dictionary
		var hazard_id: String = String(hazard_data.get("id", ""))
		if not _hazard_rows.has(hazard_id):
			continue
		var position: Vector2 = Vector2(float(hazard_data.get("x", 0.0)), float(hazard_data.get("y", 0.0)))
		_hazard_placements.append(_placement(hazard_id, _normalize_hazard_position(position, hazard_id), MANUAL_SOURCE))


func _add_pcg_hazards(raw_value: Variant) -> void:
	for raw_rule: Variant in _array_or_empty(raw_value):
		if not raw_rule is Dictionary:
			continue
		var rule: Dictionary = raw_rule as Dictionary
		var hazard_id: String = String(rule.get("id", ""))
		if not _hazard_rows.has(hazard_id):
			continue
		var count: int = maxi(int(rule.get("count", 0)), 0)
		var min_distance: float = maxf(float(rule.get("min_distance_from_player", _safe_radius)), 0.0)
		var min_spacing: float = maxf(float(rule.get("min_spacing", 0.0)), 0.0)
		for _index: int in range(count):
			var position: Vector2 = _roll_hazard_position(hazard_id, min_distance, min_spacing)
			if position != INVALID_POSITION:
				_hazard_placements.append(_placement(hazard_id, position, PCG_SOURCE))


func _roll_hazard_position(hazard_id: String, min_distance: float, min_spacing: float) -> Vector2:
	var half_extents: Vector2 = _hazard_half_extents(hazard_id)
	var placement_padding: float = maxf(maxf(half_extents.x, half_extents.y), SPAWN_EDGE_PADDING)
	var placement_bounds: Rect2 = _bounds.grow(-placement_padding)
	if placement_bounds.size.x <= 0.0 or placement_bounds.size.y <= 0.0:
		return INVALID_POSITION
	var attempts: int = maxi(PLACEMENT_ATTEMPTS_PER_HAZARD, 1)
	for _attempt: int in range(attempts):
		var candidate: Vector2 = Vector2(
			RNG.world.randf_range(placement_bounds.position.x, placement_bounds.end.x),
			RNG.world.randf_range(placement_bounds.position.y, placement_bounds.end.y)
		)
		candidate = _normalize_hazard_position(candidate, hazard_id)
		if _is_valid_hazard_position(candidate, hazard_id, min_distance, min_spacing):
			return candidate
	return INVALID_POSITION


func _is_valid_hazard_position(candidate: Vector2, hazard_id: String, min_distance: float, min_spacing: float) -> bool:
	if not _is_hazard_inside_bounds(candidate, hazard_id):
		return false
	var minimum_player_distance: float = maxf(min_distance, _safe_radius)
	if candidate.distance_to(_player_start) < minimum_player_distance:
		return false
	var candidate_radius: float = _hazard_spacing_radius(hazard_id)
	for placement: Dictionary in _hazard_placements:
		var other_position: Vector2 = _dict_to_vector(placement.get("position", {}), Vector2.ZERO)
		var other_radius: float = _hazard_spacing_radius(String(placement.get("hazard_id", "")))
		var required_spacing: float = maxf(min_spacing, candidate_radius + other_radius)
		if candidate.distance_to(other_position) < required_spacing:
			return false
	return true


func _placement(hazard_id: String, position: Vector2, source: String) -> Dictionary:
	return {
		"hazard_id": hazard_id,
		"position": _vector_to_dict(position),
		"source": source,
	}


func _normalize_hazard_position(world_position: Vector2, hazard_id: String) -> Vector2:
	var half_extents: Vector2 = _hazard_half_extents(hazard_id)
	var min_x: float = _bounds.position.x + half_extents.x
	var max_x: float = _bounds.end.x - half_extents.x
	var min_y: float = _bounds.position.y + half_extents.y
	var max_y: float = _bounds.end.y - half_extents.y
	if min_x > max_x or min_y > max_y:
		return _nearest_hazard_anchor_position(clamp_position(world_position), hazard_id)
	var clamped_target: Vector2 = Vector2(
		clampf(world_position.x, min_x, max_x),
		clampf(world_position.y, min_y, max_y)
	)
	return _nearest_hazard_anchor_position(clamped_target, hazard_id)


func _nearest_hazard_anchor_position(target_position: Vector2, hazard_id: String) -> Vector2:
	var base_index: Vector2i = _grid_index(target_position)
	var best_position: Vector2 = INVALID_POSITION
	var best_distance: float = INF
	var search_radius: int = _hazard_grid_search_radius(hazard_id)
	for radius: int in range(search_radius + 1):
		for column_offset: int in range(-radius, radius + 1):
			for row_offset: int in range(-radius, radius + 1):
				if maxi(absi(column_offset), absi(row_offset)) != radius:
					continue
				var candidate_index: Vector2i = Vector2i(
					base_index.x + column_offset,
					base_index.y + row_offset
				)
				for candidate: Vector2 in _hazard_anchor_candidates(candidate_index, hazard_id):
					if not _is_hazard_inside_bounds(candidate, hazard_id):
						continue
					var distance: float = target_position.distance_squared_to(candidate)
					if best_position == INVALID_POSITION or distance < best_distance:
						best_position = candidate
						best_distance = distance
	if best_position != INVALID_POSITION:
		return best_position
	return _hazard_anchor_candidates(_grid_index(clamp_position(target_position)), hazard_id)[0]


func _hazard_anchor_candidates(grid_index: Vector2i, hazard_id: String) -> Array[Vector2]:
	if _hazard_radius_tiles(hazard_id) % 2 == 1:
		return [_grid_position(grid_index)]
	var half_width: float = maxf(_grid_cell_size.x * 0.5, 1.0)
	var half_height: float = maxf(_grid_cell_size.y * 0.5, 1.0)
	var base_position: Vector2 = _grid_position(grid_index)
	return [
		base_position + Vector2(0.0, half_height),
		base_position + Vector2(half_width, 0.0),
	]


func _grid_index(world_position: Vector2) -> Vector2i:
	var half_width: float = maxf(_grid_cell_size.x * 0.5, 1.0)
	var half_height: float = maxf(_grid_cell_size.y * 0.5, 1.0)
	var u: float = world_position.x / half_width
	var v: float = world_position.y / half_height
	return Vector2i(roundi((u + v) * 0.5), roundi((v - u) * 0.5))


func _grid_position(grid_index: Vector2i) -> Vector2:
	var half_width: float = maxf(_grid_cell_size.x * 0.5, 1.0)
	var half_height: float = maxf(_grid_cell_size.y * 0.5, 1.0)
	return Vector2(
		float(grid_index.x - grid_index.y) * half_width,
		float(grid_index.x + grid_index.y) * half_height
	)


func _hazard_grid_search_radius(hazard_id: String) -> int:
	var half_width: float = maxf(_grid_cell_size.x * 0.5, 1.0)
	var half_height: float = maxf(_grid_cell_size.y * 0.5, 1.0)
	var hazard_steps: float = maxf(_hazard_half_extents(hazard_id).x / half_width, _hazard_half_extents(hazard_id).y / half_height)
	return maxi(int(ceilf(hazard_steps)) + 4, 8)


func _is_hazard_inside_bounds(candidate: Vector2, hazard_id: String) -> bool:
	var half_extents: Vector2 = _hazard_half_extents(hazard_id)
	return (
		candidate.x - half_extents.x >= _bounds.position.x
		and candidate.x + half_extents.x <= _bounds.end.x
		and candidate.y - half_extents.y >= _bounds.position.y
		and candidate.y + half_extents.y <= _bounds.end.y
	)


func _hazard_spacing_radius(hazard_id: String) -> float:
	var half_extents: Vector2 = _hazard_half_extents(hazard_id)
	return maxf(half_extents.x, half_extents.y)


func _hazard_half_extents(hazard_id: String) -> Vector2:
	return _grid_cell_size * 0.5 * float(_hazard_radius_tiles(hazard_id))


func _hazard_radius_tiles(hazard_id: String) -> int:
	var hazard_data: Dictionary = _dictionary_or_empty(_hazard_rows.get(hazard_id, {}))
	return maxi(int(hazard_data.get("radius_tiles", 1)), 1)


func _typed_placements(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_item: Variant in _array_or_empty(raw_value):
		if raw_item is Dictionary:
			var item: Dictionary = (raw_item as Dictionary).duplicate(true)
			var hazard_id: String = String(item.get("hazard_id", ""))
			item["position"] = _vector_to_dict(_normalize_hazard_position(_dict_to_vector(item.get("position", {}), Vector2.ZERO), hazard_id))
			result.append(item)
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _rect_to_dict(value: Rect2) -> Dictionary:
	return {
		"x": value.position.x,
		"y": value.position.y,
		"width": value.size.x,
		"height": value.size.y,
	}


func _dict_to_rect(raw_value: Variant, fallback: Rect2) -> Rect2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Rect2(
		Vector2(float(value.get("x", fallback.position.x)), float(value.get("y", fallback.position.y))),
		Vector2(float(value.get("width", fallback.size.x)), float(value.get("height", fallback.size.y)))
	)


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _points_to_array(points: PackedVector2Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point: Vector2 in points:
		result.append(_vector_to_dict(point))
	return result


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
