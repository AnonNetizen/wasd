extends SceneTree
## Headless entry point for deterministic module authoring migration and bake checks.

const MODULE_SCENE_BAKER := preload("res://scripts/editor/module_scene_baker.gd")


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary
	if arguments.has("--migrate-json"):
		result = MODULE_SCENE_BAKER.migrate_registered_json_to_scenes()
	elif arguments.has("--module-bake-check"):
		result = MODULE_SCENE_BAKER.bake_all(false)
	elif arguments.has("--module-bake"):
		var scene_path: String = _value_after(arguments, "--scene")
		if scene_path.is_empty():
			result = MODULE_SCENE_BAKER.bake_all(true)
		else:
			result = MODULE_SCENE_BAKER.bake_scene(scene_path)
	else:
		result = {"ok": false, "errors": PackedStringArray(["Expected --module-bake, --module-bake-check, or --migrate-json."])}
	_report(result)
	quit(0 if bool(result.get("ok", false)) else 1)


func _report(result: Dictionary) -> void:
	for message: String in result.get("errors", PackedStringArray()) as PackedStringArray:
		printerr("[module-bake] %s" % message)
	print(
		"[module-bake] ok=%s migrated=%d baked=%d checked=%d changed=%d registry_changed=%s" % [
			str(bool(result.get("ok", false))).to_lower(),
			int(result.get("migrated", 0)),
			int(result.get("baked", 0)),
			int(result.get("checked", 0)),
			int(result.get("changed", 0)),
			str(bool(result.get("registry_changed", false))).to_lower(),
		]
	)


func _value_after(arguments: PackedStringArray, flag: String) -> String:
	var index: int = arguments.find(flag)
	if index >= 0 and index + 1 < arguments.size():
		return arguments[index + 1]
	return ""
