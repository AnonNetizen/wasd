# Doc: docs/代码/map_manager.md
# Authority: docs/游戏设计文档.md §5, docs/决策记录.md ADR #93 / ADR #105
class_name MapManager
extends Node2D


const BOUNDS_COLOR: Color = Color(0.48, 0.62, 0.70, 0.62)
const BOUNDS_FILL_COLOR: Color = Color(0.08, 0.10, 0.11, 0.12)
const BOUNDS_WIDTH: float = 4.0
const DEFAULT_BOUNDS_SIZE: Vector2 = Vector2(3200.0, 1600.0)
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 80.0)
const INVALID_POSITION: Vector2 = Vector2(1.0e20, 1.0e20)
const MANUAL_SOURCE: String = "manual"
const PCG_SOURCE: String = "pcg"
const PLACEMENT_ATTEMPTS_PER_HAZARD: int = 32
const SAFE_ZONE_FILL_COLOR: Color = Color(0.24, 0.72, 0.56, 0.10)
const SAFE_ZONE_RING_COLOR: Color = Color(0.40, 0.78, 0.66, 0.38)
const SAFE_ZONE_WIDTH: float = 2.0
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


func boundary_center() -> Vector2:
	return _bounds.get_center()


func boundary_half_extents() -> Vector2:
	return _diamond_half_extents()


func safe_zone_points() -> PackedVector2Array:
	return _safe_zone_points()


func safe_zone_half_extents() -> Vector2:
	return _safe_zone_half_extents()


func clamp_position(world_position: Vector2) -> Vector2:
	return _clamp_to_diamond(world_position)


func snap_to_grid(world_position: Vector2) -> Vector2:
	var grid_index: Vector2i = _grid_index(world_position)
	return _grid_position(grid_index)


func normalize_hazard_position(world_position: Vector2, hazard_id: String) -> Vector2:
	return _normalize_hazard_position(world_position, hazard_id)


func spawn_position(player_position: Vector2, viewport_size: Vector2) -> Vector2:
	var radius: float = maxf(viewport_size.x, viewport_size.y) * 0.55
	var spawn_padding: Vector2 = _diamond_padding_extents(maxf(_enemy_spawn_margin, SPAWN_EDGE_PADDING))
	if not _has_diamond_room(spawn_padding):
		spawn_padding = _diamond_padding_extents(SPAWN_EDGE_PADDING)
	var angle: float = RNG.spawn.randf_range(0.0, TAU)
	var candidate: Vector2 = player_position + Vector2.RIGHT.rotated(angle) * radius
	return _clamp_to_diamond(candidate, spawn_padding)


func debug_summary() -> Dictionary:
	return {
		"layout_id": _layout_id,
		"bounds": _rect_to_dict(_bounds),
		"grid_cell_size": _vector_to_dict(_grid_cell_size),
		"boundary_shape": "diamond",
		"boundary_center": _vector_to_dict(boundary_center()),
		"boundary_half_extents": _vector_to_dict(_diamond_half_extents()),
		"boundary_points": _points_to_array(_boundary_points()),
		"safe_zone_shape": "diamond" if _safe_radius > 0.0 else "none",
		"safe_zone_half_extents": _vector_to_dict(_safe_zone_half_extents()),
		"safe_zone_points": _points_to_array(_safe_zone_points()),
		"player_start": _vector_to_dict(_player_start),
		"hazard_count": _hazard_placements.size(),
		"safe_radius": _safe_radius,
	}


func _draw() -> void:
	var points: PackedVector2Array = _boundary_points()
	draw_colored_polygon(points, BOUNDS_FILL_COLOR)
	_draw_polygon_outline(points, BOUNDS_COLOR, BOUNDS_WIDTH)
	if _safe_radius > 0.0:
		var safe_points: PackedVector2Array = _safe_zone_points()
		draw_colored_polygon(safe_points, SAFE_ZONE_FILL_COLOR)
		_draw_polygon_outline(safe_points, SAFE_ZONE_RING_COLOR, SAFE_ZONE_WIDTH)


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
	var center: Vector2 = boundary_center()
	var half_extents: Vector2 = _diamond_half_extents()
	return PackedVector2Array([
		center + Vector2(0.0, -half_extents.y),
		center + Vector2(half_extents.x, 0.0),
		center + Vector2(0.0, half_extents.y),
		center + Vector2(-half_extents.x, 0.0),
	])


func _diamond_half_extents() -> Vector2:
	var ratio: float = _diamond_slope_ratio()
	var horizontal_limit: float = maxf(_bounds.size.x * 0.5, 1.0)
	var vertical_limit: float = maxf(_bounds.size.y * 0.5, 1.0)
	var vertical_from_width: float = horizontal_limit * ratio
	if vertical_from_width <= vertical_limit:
		return Vector2(horizontal_limit, vertical_from_width)
	return Vector2(vertical_limit / ratio, vertical_limit)


func _diamond_slope_ratio() -> float:
	return maxf(_grid_cell_size.y, 1.0) / maxf(_grid_cell_size.x, 1.0)


func _safe_zone_half_extents() -> Vector2:
	if _safe_radius <= 0.0:
		return Vector2.ZERO
	var grid_width: float = maxf(_grid_cell_size.x, 1.0)
	var horizontal_grid_span: float = maxf(_safe_radius / grid_width, 0.0)
	var grid_line_span: float = maxf(ceilf(horizontal_grid_span - 0.5) + 0.5, 0.5)
	var half_width: float = grid_width * grid_line_span
	return Vector2(half_width, half_width * _diamond_slope_ratio())


func _safe_zone_points() -> PackedVector2Array:
	if _safe_radius <= 0.0:
		return PackedVector2Array()
	var half_extents: Vector2 = _safe_zone_half_extents()
	return PackedVector2Array([
		_player_start + Vector2(0.0, -half_extents.y),
		_player_start + Vector2(half_extents.x, 0.0),
		_player_start + Vector2(0.0, half_extents.y),
		_player_start + Vector2(-half_extents.x, 0.0),
	])


func _diamond_padding_extents(horizontal_padding: float) -> Vector2:
	var padding: float = maxf(horizontal_padding, 0.0)
	return Vector2(padding, padding * _diamond_slope_ratio())


func _diamond_inset_ratio(inset_extents: Vector2) -> float:
	var half_extents: Vector2 = _diamond_half_extents()
	return maxf(
		maxf(inset_extents.x, 0.0) / maxf(half_extents.x, 1.0),
		maxf(inset_extents.y, 0.0) / maxf(half_extents.y, 1.0)
	)


func _has_diamond_room(inset_extents: Vector2) -> bool:
	return _diamond_inset_ratio(inset_extents) < 1.0


func _is_position_inside_diamond(world_position: Vector2, inset_extents: Vector2 = Vector2.ZERO) -> bool:
	var center: Vector2 = boundary_center()
	var half_extents: Vector2 = _diamond_half_extents()
	var offset: Vector2 = world_position - center
	var limit: float = 1.0 - _diamond_inset_ratio(inset_extents)
	if limit < 0.0:
		return false
	var normalized_distance: float = absf(offset.x) / maxf(half_extents.x, 1.0) + absf(offset.y) / maxf(half_extents.y, 1.0)
	return normalized_distance <= limit + 0.01


func _clamp_to_diamond(world_position: Vector2, inset_extents: Vector2 = Vector2.ZERO) -> Vector2:
	var center: Vector2 = boundary_center()
	var half_extents: Vector2 = _diamond_half_extents()
	var offset: Vector2 = world_position - center
	var limit: float = maxf(1.0 - _diamond_inset_ratio(inset_extents), 0.0)
	var normalized_distance: float = absf(offset.x) / maxf(half_extents.x, 1.0) + absf(offset.y) / maxf(half_extents.y, 1.0)
	if normalized_distance <= limit or normalized_distance <= 0.0:
		return world_position
	return center + offset * (limit / normalized_distance)


func _diamond_rect(inset_extents: Vector2 = Vector2.ZERO) -> Rect2:
	var center: Vector2 = boundary_center()
	var half_extents: Vector2 = _diamond_half_extents() * maxf(1.0 - _diamond_inset_ratio(inset_extents), 0.0)
	return Rect2(center - half_extents, half_extents * 2.0)


func _random_diamond_position(inset_extents: Vector2 = Vector2.ZERO) -> Vector2:
	var rect: Rect2 = _diamond_rect(inset_extents)
	for _attempt: int in range(16):
		var candidate: Vector2 = Vector2(
			RNG.world.randf_range(rect.position.x, rect.end.x),
			RNG.world.randf_range(rect.position.y, rect.end.y)
		)
		if _is_position_inside_diamond(candidate, inset_extents):
			return candidate
	return _clamp_to_diamond(rect.get_center(), inset_extents)


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
	var placement_padding: Vector2 = Vector2(
		maxf(half_extents.x, SPAWN_EDGE_PADDING),
		maxf(half_extents.y, SPAWN_EDGE_PADDING * _diamond_slope_ratio())
	)
	if not _has_diamond_room(placement_padding):
		return INVALID_POSITION
	var attempts: int = maxi(PLACEMENT_ATTEMPTS_PER_HAZARD, 1)
	for _attempt: int in range(attempts):
		var candidate: Vector2 = _random_diamond_position(placement_padding)
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
	if not _has_diamond_room(half_extents):
		return _nearest_hazard_anchor_position(clamp_position(world_position), hazard_id)
	var clamped_target: Vector2 = _clamp_to_diamond(world_position, half_extents)
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
	return _is_position_inside_diamond(candidate, half_extents)


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
