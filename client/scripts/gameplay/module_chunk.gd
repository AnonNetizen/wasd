# Doc: docs/代码/module_world_manager.md
class_name ModuleChunk
extends Node2D
## Reusable scene-authored slot mounting one generated module PackedScene.

const MODULE_EDGE_DIRECTIONS := preload(
	"res://scripts/contracts/module_edge_directions.gd"
)

const MODULE_SIZE: int = 11
const AUTHORING_CELL_SIZE: float = 160.0
const AUTHORING_MODULE_SPAN: float = float(MODULE_SIZE - 1) * AUTHORING_CELL_SIZE
const WORLD_CENTER_GLOBAL_CELL: Vector2i = Vector2i(49, 49)

var _module_coord: Vector2i = Vector2i(-1, -1)
var _rotation: int = 0
var _cell_size: float = AUTHORING_CELL_SIZE
var _module_instance: GeneratedModuleScene = null


func configure(
	generated_scene: PackedScene,
	module_coord: Vector2i,
	rotation: int,
	masked_edges: Array,
	cell_size: float,
	world_origin: Vector2
) -> bool:
	clear()
	if generated_scene == null:
		push_error("[ModuleChunk] generated module PackedScene is missing")
		return false
	var instance: Node = generated_scene.instantiate()
	if not instance is GeneratedModuleScene:
		if instance != null:
			instance.free()
		push_error("[ModuleChunk] generated scene root must be GeneratedModuleScene")
		return false
	var generated: GeneratedModuleScene = instance as GeneratedModuleScene
	var normalized_rotation: int = _normalize_rotation(rotation)
	if (
		generated.baker_schema_version
		!= GeneratedModuleScene.BAKER_SCHEMA_VERSION
		or generated.module_rotation_degrees != 0
		or generated.module_id.is_empty()
	):
		generated.free()
		push_error("[ModuleChunk] generated scene metadata is invalid")
		return false

	_module_coord = module_coord
	_rotation = normalized_rotation
	_cell_size = maxf(cell_size, 1.0)
	_module_instance = generated
	add_child(_module_instance)
	_apply_runtime_rotation(_module_instance, normalized_rotation)
	_module_instance.set_masked_edges(
		_canonical_masked_edges(masked_edges, normalized_rotation)
	)
	scale = Vector2.ONE * (_cell_size / AUTHORING_CELL_SIZE)
	position = world_origin + Vector2(
		float(_module_coord.x * MODULE_SIZE - WORLD_CENTER_GLOBAL_CELL.x)
		* _cell_size,
		float(_module_coord.y * MODULE_SIZE - WORLD_CENTER_GLOBAL_CELL.y)
		* _cell_size
	)
	visible = true
	return true


func clear() -> void:
	if _module_instance != null:
		remove_child(_module_instance)
		_module_instance.free()
		_module_instance = null
	_module_coord = Vector2i(-1, -1)
	_rotation = 0
	position = Vector2.ZERO
	scale = Vector2.ONE
	visible = false


func reset() -> void:
	clear()


func module_coord() -> Vector2i:
	return _module_coord


func rotation_degrees_value() -> int:
	return _rotation


func rotation_degrees() -> int:
	return _rotation


func template_id() -> String:
	return _module_instance.module_id if _module_instance != null else ""


func generated_instance() -> GeneratedModuleScene:
	return _module_instance


func debug_summary() -> Dictionary:
	return {
		"template_id": template_id(),
		"module_coord": {"x": _module_coord.x, "y": _module_coord.y},
		"rotation": _rotation,
		"cell_size": _cell_size,
		"collision_shape_count": (
			_collision_shape_count(_module_instance)
			if _module_instance != null
			else 0
		),
		"mounted_scene_count": 1 if _module_instance != null else 0,
	}


func _collision_shape_count(root: Node) -> int:
	var count: int = 1 if root is CollisionShape2D else 0
	for child: Node in root.get_children():
		count += _collision_shape_count(child)
	return count


func _normalize_rotation(rotation_value: int) -> int:
	var normalized: int = posmod(rotation_value, 360)
	return normalized if normalized % 90 == 0 else 0


func _apply_runtime_rotation(
	generated: GeneratedModuleScene,
	rotation_value: int
) -> void:
	var normalized: int = _normalize_rotation(rotation_value)
	generated.rotation_degrees = float(normalized)
	match normalized:
		90:
			generated.position = Vector2(AUTHORING_MODULE_SPAN, 0.0)
		180:
			generated.position = Vector2(
				AUTHORING_MODULE_SPAN,
				AUTHORING_MODULE_SPAN
			)
		270:
			generated.position = Vector2(0.0, AUTHORING_MODULE_SPAN)
		_:
			generated.position = Vector2.ZERO


func _canonical_masked_edges(
	world_edges: Array,
	rotation_value: int
) -> Array[String]:
	var canonical_edges: Array[String] = []
	var directions: Array[String] = [
		MODULE_EDGE_DIRECTIONS.EDGE_NORTH,
		MODULE_EDGE_DIRECTIONS.EDGE_EAST,
		MODULE_EDGE_DIRECTIONS.EDGE_SOUTH,
		MODULE_EDGE_DIRECTIONS.EDGE_WEST,
	]
	var rotation_steps: int = int(_normalize_rotation(rotation_value) / 90)
	for edge_value: Variant in world_edges:
		var world_index: int = directions.find(String(edge_value))
		if world_index < 0:
			continue
		var canonical_index: int = posmod(world_index - rotation_steps, 4)
		canonical_edges.append(directions[canonical_index])
	return canonical_edges
