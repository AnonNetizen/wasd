# Doc: docs/代码/data_table_editor.md
# Doc: docs/代码/module_authoring_pipeline.md
@tool
class_name ProjectDataValidationBridge
extends RefCounted
## Shared editor-only bridge to the runtime DataLoader validation contract.

const VALIDATION_SCRIPT: String = (
	"res://scripts/editor/project_data_validation_cli.gd"
)


static func validate_project_data(prefer_headless: bool = false) -> Dictionary:
	if not prefer_headless:
		var in_process_result: Dictionary = _validate_in_process()
		if bool(in_process_result.get("available", false)):
			return in_process_result
	return _validate_with_headless_process()


static func _validate_in_process() -> Dictionary:
	var result: Dictionary = _new_result()
	result["available"] = false
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return result
	var loader: Node = tree.root.get_node_or_null("DataLoader")
	if loader == null:
		return result
	result["available"] = true
	if not loader.has_method("validate_project_data"):
		return _error_result(
			"DataLoader does not expose validate_project_data().",
			true
		)
	if bool(loader.call("validate_project_data")):
		return result
	return _error_result(
		"Project data validation failed; inspect DataLoader diagnostics.",
		true
	)


static func _validate_with_headless_process() -> Dictionary:
	if not FileAccess.file_exists(VALIDATION_SCRIPT):
		return _error_result("missing validation script: %s" % VALIDATION_SCRIPT)
	var executable_path: String = OS.get_executable_path()
	if executable_path.is_empty():
		return _error_result("unable to resolve the current Godot executable")
	var output: Array = []
	var exit_code: int = OS.execute(
		executable_path,
		PackedStringArray(
			[
				"--headless",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"--script",
				VALIDATION_SCRIPT,
			]
		),
		output,
		true,
		false
	)
	var output_text: String = "\n".join(PackedStringArray(output)).strip_edges()
	if exit_code == 0:
		var result: Dictionary = _new_result()
		result["output"] = output_text
		return result
	var failure: Dictionary = _error_result(
		"headless DataLoader validation exited with code %d" % exit_code
	)
	if not output_text.is_empty():
		var errors: PackedStringArray = failure.get("errors", PackedStringArray())
		errors.append(output_text)
		failure["errors"] = errors
	failure["output"] = output_text
	return failure


static func _new_result() -> Dictionary:
	return {
		"ok": true,
		"available": true,
		"errors": PackedStringArray(),
		"output": "",
	}


static func _error_result(message: String, available: bool = true) -> Dictionary:
	return {
		"ok": false,
		"available": available,
		"errors": PackedStringArray([message]),
		"output": "",
	}
