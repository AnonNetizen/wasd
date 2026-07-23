# Doc: docs/代码/module_authoring_pipeline.md
class_name GeneratedModuleScene
extends Node2D
## Immutable runtime module scene produced by the JSON-only editor baker.

const MODULE_EDGE_DIRECTIONS := preload("res://scripts/contracts/module_edge_directions.gd")

const BAKER_SCHEMA_VERSION: int = 2

@export var baker_schema_version: int = BAKER_SCHEMA_VERSION
@export var module_id: String = ""
@export_range(0, 270, 90) var module_rotation_degrees: int = 0
@export var gameplay_hash: String = ""
@export var visual_hash: String = ""
@export var bake_hash: String = ""
@export var placement_snapshot: Array[Dictionary] = []


func set_masked_edges(masked_edges: Array) -> void:
	var masked: Dictionary = {}
	for edge_value: Variant in masked_edges:
		masked[String(edge_value)] = true
	_set_edge_enabled("EdgeSeals/North", masked.has(MODULE_EDGE_DIRECTIONS.EDGE_NORTH))
	_set_edge_enabled("EdgeSeals/East", masked.has(MODULE_EDGE_DIRECTIONS.EDGE_EAST))
	_set_edge_enabled("EdgeSeals/South", masked.has(MODULE_EDGE_DIRECTIONS.EDGE_SOUTH))
	_set_edge_enabled("EdgeSeals/West", masked.has(MODULE_EDGE_DIRECTIONS.EDGE_WEST))


func _set_edge_enabled(node_path: String, enabled: bool) -> void:
	var edge_root: Node2D = get_node_or_null(node_path) as Node2D
	if edge_root == null:
		return
	edge_root.visible = enabled
	var collision: CollisionShape2D = edge_root.get_node_or_null(
		"SealCollision/Shape"
	) as CollisionShape2D
	if collision != null:
		var has_segments: bool = (
			collision.shape is ConcavePolygonShape2D
			and not (collision.shape as ConcavePolygonShape2D).get_segments().is_empty()
		)
		collision.disabled = not enabled or not has_segments
