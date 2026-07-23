extends SceneTree
## Headless entry point for deterministic JSON -> TSCN module baking and checks.

const MODULE_SCENE_BAKER := preload("res://scripts/editor/module_scene_baker.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var result: Dictionary
	var module_id: String = _value_after(arguments, "--module")
	if arguments.has("--module-bake-check"):
		result = (
			MODULE_SCENE_BAKER.check_all()
			if module_id.is_empty()
			else MODULE_SCENE_BAKER.bake_module(module_id, false)
		)
	elif arguments.has("--module-bake"):
		result = (
			MODULE_SCENE_BAKER.bake_all(true)
			if module_id.is_empty()
			else MODULE_SCENE_BAKER.bake_module(module_id, true)
		)
	else:
		result = {
			"ok": false,
			"errors": PackedStringArray(
				["Expected --module-bake or --module-bake-check."]
			),
		}
	_report(result)
	quit(0 if bool(result.get("ok", false)) else 1)


func _report(result: Dictionary) -> void:
	for message: String in result.get("errors", PackedStringArray()) as PackedStringArray:
		printerr("[module-bake] %s" % message)
	print(
		"[module-bake] ok=%s baked=%d checked=%d changed=%d registry_changed=%s" % [
			str(bool(result.get("ok", false))).to_lower(),
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
