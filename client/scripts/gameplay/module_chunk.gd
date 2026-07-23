# Doc: docs/代码/module_world_manager.md
class_name ModuleChunk
extends Node2D
## Reusable scene-authored carrier for one baked 11 x 11 module assignment.

const MODULE_EDGE_DIRECTIONS := preload("res://scripts/contracts/module_edge_directions.gd")

const MODULE_SIZE: int = 11
const AUTHORING_CELL_SIZE: float = 160.0
const WORLD_CENTER_GLOBAL_CELL: Vector2i = Vector2i(49, 49)
const EDGE_MASK_NORTH: int = 1 << 0
const EDGE_MASK_EAST: int = 1 << 1
const EDGE_MASK_SOUTH: int = 1 << 2
const EDGE_MASK_WEST: int = 1 << 3

var _baked_data: ModuleBakedData = null
var _module_coord: Vector2i = Vector2i(-1, -1)
var _rotation: int = 0
var _cell_size: float = AUTHORING_CELL_SIZE
var _ground: TileMapLayer = null
var _obstacles: TileMapLayer = null
var _decoration: TileMapLayer = null
var _collision_shape: CollisionShape2D = null


func _ready() -> void:
	_bind_scene_nodes()


func configure(
	baked_data: ModuleBakedData,
	module_coord: Vector2i,
	rotation: int,
	masked_edges: Array,
	cell_size: float,
	world_origin: Vector2
) -> bool:
	clear()
	_bind_scene_nodes()
	if baked_data == null or _ground == null or _obstacles == null or _decoration == null or _collision_shape == null:
		push_error("[ModuleChunk] baked data or required scene nodes are missing")
		return false
	var normalized_rotation: int = _normalize_rotation(rotation)
	var baked_rotation: ModuleBakedRotation = baked_data.rotation_data(normalized_rotation)
	if baked_rotation == null:
		push_error("[ModuleChunk] %s is missing rotation %d" % [baked_data.module_id, normalized_rotation])
		return false
	var edge_mask: int = _edge_mask(masked_edges)
	var obstacle_pattern: TileMapPattern = baked_rotation.obstacle_pattern_for_mask(edge_mask)
	var terrain_collision: ConcavePolygonShape2D = baked_rotation.terrain_collision_for_mask(edge_mask)
	if baked_rotation.ground_pattern == null or obstacle_pattern == null or baked_rotation.decoration_pattern == null or terrain_collision == null:
		push_error("[ModuleChunk] %s rotation %d mask %d is incomplete" % [baked_data.module_id, normalized_rotation, edge_mask])
		return false

	_baked_data = baked_data
	_module_coord = module_coord
	_rotation = normalized_rotation
	_cell_size = maxf(cell_size, 1.0)
	_ground.set_pattern(Vector2i.ZERO, baked_rotation.ground_pattern)
	_obstacles.set_pattern(Vector2i.ZERO, obstacle_pattern)
	_decoration.set_pattern(Vector2i.ZERO, baked_rotation.decoration_pattern)
	_collision_shape.shape = terrain_collision
	_collision_shape.disabled = terrain_collision.get_segments().is_empty()
	scale = Vector2.ONE * (_cell_size / AUTHORING_CELL_SIZE)
	position = world_origin + Vector2(
		float(_module_coord.x * MODULE_SIZE - WORLD_CENTER_GLOBAL_CELL.x) * _cell_size,
		float(_module_coord.y * MODULE_SIZE - WORLD_CENTER_GLOBAL_CELL.y) * _cell_size
	)
	visible = true
	return true


func clear() -> void:
	_bind_scene_nodes()
	_baked_data = null
	_module_coord = Vector2i(-1, -1)
	_rotation = 0
	position = Vector2.ZERO
	scale = Vector2.ONE
	visible = false
	if _ground != null:
		_ground.clear()
	if _obstacles != null:
		_obstacles.clear()
	if _decoration != null:
		_decoration.clear()
	if _collision_shape != null:
		_collision_shape.shape = null
		_collision_shape.disabled = true


func reset() -> void:
	clear()


func module_coord() -> Vector2i:
	return _module_coord


func rotation_degrees() -> int:
	return _rotation


func template_id() -> String:
	return _baked_data.module_id if _baked_data != null else ""


func debug_summary() -> Dictionary:
	return {
		"template_id": template_id(),
		"module_coord": {"x": _module_coord.x, "y": _module_coord.y},
		"rotation": _rotation,
		"cell_size": _cell_size,
		"collision_shape_count": 1 if _collision_shape != null and _collision_shape.shape != null else 0,
	}


func _bind_scene_nodes() -> void:
	if _ground == null:
		_ground = get_node_or_null("Ground") as TileMapLayer
	if _obstacles == null:
		_obstacles = get_node_or_null("Obstacles") as TileMapLayer
	if _decoration == null:
		_decoration = get_node_or_null("Decoration") as TileMapLayer
	if _collision_shape == null:
		_collision_shape = get_node_or_null("TerrainCollision/MergedBlockedCells") as CollisionShape2D


func _edge_mask(masked_edges: Array) -> int:
	var result: int = 0
	for raw_edge: Variant in masked_edges:
		match String(raw_edge):
			MODULE_EDGE_DIRECTIONS.EDGE_NORTH:
				result |= EDGE_MASK_NORTH
			MODULE_EDGE_DIRECTIONS.EDGE_EAST:
				result |= EDGE_MASK_EAST
			MODULE_EDGE_DIRECTIONS.EDGE_SOUTH:
				result |= EDGE_MASK_SOUTH
			MODULE_EDGE_DIRECTIONS.EDGE_WEST:
				result |= EDGE_MASK_WEST
	return result


func _normalize_rotation(rotation_degrees: int) -> int:
	var normalized: int = posmod(rotation_degrees, 360)
	return normalized if normalized % 90 == 0 else 0
