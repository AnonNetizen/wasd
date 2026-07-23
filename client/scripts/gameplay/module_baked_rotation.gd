# Doc: docs/代码/module_authoring_pipeline.md
class_name ModuleBakedRotation
extends Resource
## One precomputed visual/collision variant of an authored 11 x 11 module.

@export_range(0, 270, 90) var rotation_degrees: int = 0
@export var ground_pattern: TileMapPattern
@export var obstacle_pattern: TileMapPattern
@export var decoration_pattern: TileMapPattern
@export var terrain_collision: ConcavePolygonShape2D
@export var obstacle_patterns_by_edge_mask: Dictionary = {}
@export var terrain_collisions_by_edge_mask: Dictionary = {}


func obstacle_pattern_for_mask(edge_mask: int) -> TileMapPattern:
	return obstacle_patterns_by_edge_mask.get(edge_mask, obstacle_pattern) as TileMapPattern


func terrain_collision_for_mask(edge_mask: int) -> ConcavePolygonShape2D:
	return terrain_collisions_by_edge_mask.get(edge_mask, terrain_collision) as ConcavePolygonShape2D
