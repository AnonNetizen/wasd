# Doc: docs/代码/module_authoring_pipeline.md
@tool
class_name ModuleAuthoringRoot
extends Node2D
## Editor-only root metadata for a module layout source scene.

@export var module_id: String = ""


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if module_id.is_empty():
		warnings.append("module_id must match an entry in module_templates.json.")
	for required_child: String in ["Ground", "Obstacles", "Decoration", "Placements"]:
		if not has_node(NodePath(required_child)):
			warnings.append("Missing required child: %s" % required_child)
	return warnings
