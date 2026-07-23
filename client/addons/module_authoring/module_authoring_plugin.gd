@tool
extends EditorPlugin
## Editor-only menu bridge to the deterministic module scene baker.

const MODULE_SCENE_BAKER := preload("res://scripts/editor/module_scene_baker.gd")


func _enter_tree() -> void:
	add_tool_menu_item("Modules/Bake Current", _bake_current)
	add_tool_menu_item("Modules/Bake All", _bake_all)
	add_tool_menu_item("Modules/Approve Current", _approve_current)


func _exit_tree() -> void:
	remove_tool_menu_item("Modules/Bake Current")
	remove_tool_menu_item("Modules/Bake All")
	remove_tool_menu_item("Modules/Approve Current")


func _bake_current() -> void:
	var scene_path: String = _save_and_get_current_scene_path()
	if scene_path.is_empty():
		printerr("[module-authoring] Save a module scene before baking it.")
		return
	_report(MODULE_SCENE_BAKER.bake_scene(scene_path))


func _bake_all() -> void:
	get_editor_interface().save_all_scenes()
	_report(MODULE_SCENE_BAKER.bake_all(true))


func _approve_current() -> void:
	var scene_path: String = _save_and_get_current_scene_path()
	if scene_path.is_empty():
		printerr("[module-authoring] Save a module scene before approving it.")
		return
	_report(MODULE_SCENE_BAKER.bake_scene(scene_path, true))


func _save_and_get_current_scene_path() -> String:
	var edited_root: Node = get_editor_interface().get_edited_scene_root()
	if edited_root == null or edited_root.scene_file_path.is_empty():
		return ""
	var save_error: Error = get_editor_interface().save_scene()
	if save_error != OK:
		printerr("[module-authoring] Failed to save current scene (error %d)." % save_error)
		return ""
	return edited_root.scene_file_path


func _report(result: Dictionary) -> void:
	for message: String in result.get("errors", PackedStringArray()) as PackedStringArray:
		printerr("[module-authoring] %s" % message)
	if bool(result.get("ok", false)):
		print("[module-authoring] Bake complete: %s" % result)
		get_editor_interface().get_resource_filesystem().scan()
