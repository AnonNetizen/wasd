# Doc: docs/代码/module_authoring_pipeline.md
@tool
class_name ModulePlacementMarker
extends Marker2D
## Editor marker whose snapped position supplies `cell`; payload stores type-specific fields.

const MODULE_PLACEMENT_TYPES := preload("res://scripts/contracts/module_placement_types.gd")

@export_enum(
	"module_place_player_start",
	"module_place_enemy_spawn",
	"module_place_hazard",
	"module_place_reward_cache",
	"module_place_objective",
	"module_place_extraction"
) var placement_type: String = "module_place_player_start"
@export var payload: Dictionary = {}


func placement_at(cell: Vector2i) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	result["type"] = placement_type
	result["cell"] = {"x": cell.x, "y": cell.y}
	return result


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not MODULE_PLACEMENT_TYPES.VALUES.has(placement_type):
		warnings.append("placement_type is not registered in the module placement contract.")
	return warnings
