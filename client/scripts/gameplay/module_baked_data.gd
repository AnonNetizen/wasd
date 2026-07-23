# Doc: docs/代码/module_authoring_pipeline.md
class_name ModuleBakedData
extends Resource
## Runtime artifact baked from an editor-only module authoring scene.

@export var schema_version: int = 1
@export var module_id: String = ""
@export_file("*.tscn") var source_scene_path: String = ""
@export_file("*.json") var generated_json_path: String = ""
@export var source_content_hash: String = ""
@export var rotations: Array[ModuleBakedRotation] = []


func rotation_data(rotation_degrees: int) -> ModuleBakedRotation:
	var normalized: int = posmod(rotation_degrees, 360)
	for baked_rotation: ModuleBakedRotation in rotations:
		if baked_rotation != null and baked_rotation.rotation_degrees == normalized:
			return baked_rotation
	return null
