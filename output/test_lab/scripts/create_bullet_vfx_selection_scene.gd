extends SceneTree

const OUTPUT_SCENE_PATH: String = "res://scenes/bullet_vfx_selection_test.tscn"
const SCENE_SCRIPT_PATH: String = "res://scripts/bullet_vfx_selection_test.gd"


func _initialize() -> void:
	var scene_script := load(SCENE_SCRIPT_PATH) as Script
	if scene_script == null or not scene_script.can_instantiate():
		push_error("Bullet VFX selection scene script is not instantiable.")
		quit(1)
		return

	var scene_root := Node2D.new()
	scene_root.name = "BulletVfxSelectionTest"
	scene_root.set_script(scene_script)

	var packed_scene := PackedScene.new()
	var pack_error: Error = packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack bullet VFX selection scene: %s" % pack_error)
		scene_root.free()
		quit(pack_error)
		return

	var save_error: Error = ResourceSaver.save(
		packed_scene,
		OUTPUT_SCENE_PATH,
		ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES
	)
	if save_error != OK:
		push_error("Failed to save bullet VFX selection scene: %s" % save_error)
		scene_root.free()
		quit(save_error)
		return
	var normalize_error: Error = _strip_generated_unique_ids()
	if normalize_error != OK:
		push_error("Failed to normalize bullet VFX selection scene: %s" % normalize_error)
		scene_root.free()
		quit(normalize_error)
		return

	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	scene_root.free()
	quit(0)


func _strip_generated_unique_ids() -> Error:
	var absolute_path: String = ProjectSettings.globalize_path(OUTPUT_SCENE_PATH)
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
