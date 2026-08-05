extends SceneTree

const SCENE_PATH: String = "res://scenes/organic_vfx_pipeline_selection_test.tscn"
const SCRIPT_PATH: String = "res://scripts/organic_vfx_pipeline_selection_test.gd"


func _initialize() -> void:
	var script: Script = load(SCRIPT_PATH) as Script
	if script == null:
		push_error("Failed to load organic VFX selection script: %s" % SCRIPT_PATH)
		quit(1)
		return
	var root_node := Node2D.new()
	root_node.name = "OrganicVfxPipelineSelectionTest"
	root_node.set_script(script)
	var packed_scene := PackedScene.new()
	var pack_error: Error = packed_scene.pack(root_node)
	if pack_error != OK:
		push_error("Failed to pack organic VFX selection scene: %s" % pack_error)
		root_node.free()
		quit(pack_error)
		return
	var save_error: Error = ResourceSaver.save(packed_scene, SCENE_PATH, ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES)
	if save_error != OK:
		push_error("Failed to save organic VFX selection scene: %s" % save_error)
		root_node.free()
		quit(save_error)
		return
	var normalize_error: Error = _strip_generated_unique_ids()
	if normalize_error != OK:
		push_error("Failed to normalize organic VFX selection scene: %s" % normalize_error)
		root_node.free()
		quit(normalize_error)
		return
	print("Saved organic VFX selection scene: %s" % SCENE_PATH)
	root_node.free()
	quit(0)


func _strip_generated_unique_ids() -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(SCENE_PATH)
	var source: String = FileAccess.get_file_as_string(absolute_path)
	if source.is_empty():
		return FileAccess.get_open_error()
	var unique_id_pattern := RegEx.new()
	var compile_error: Error = unique_id_pattern.compile(" unique_id=\\d+")
	if compile_error != OK:
		return compile_error
	var normalized: String = unique_id_pattern.sub(source, "", true)
	var output_file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if output_file == null:
		return FileAccess.get_open_error()
	output_file.store_string(normalized)
	output_file.close()
	return OK
