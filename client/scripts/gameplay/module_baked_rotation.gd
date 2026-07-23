# Doc: docs/代码/module_authoring_pipeline.md
class_name ModuleBakedRotation
extends Resource
## One precomputed visual/collision variant of an authored 11 x 11 module.

@export_range(0, 270, 90) var rotation_degrees: int = 0
@export var ground_pattern: TileMapPattern
@export var obstacle_pattern: TileMapPattern
@export var decoration_pattern: TileMapPattern
@export var terrain_collision: ConcavePolygonShape2D
