extends SceneTree

const COMPILER := preload("res://scripts/polygon_asset_compiler_core.gd")


func _initialize() -> void:
	var manifest_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			manifest_path = argument.trim_prefix("--manifest=")
	if manifest_path.is_empty():
		push_error("Missing --manifest=<res://path>.")
		quit(ERR_INVALID_PARAMETER)
		return

	var compiler := COMPILER.new()
	var result: Dictionary = compiler.compile_manifest(manifest_path)
	if not bool(result.get("ok", false)):
		push_error(String(result.get("error", "Polygon asset compilation failed.")))
		quit(ERR_INVALID_DATA)
		return
	var write_error: Error = compiler.write_compiled_result(result)
	if write_error != OK:
		push_error("Failed to write Polygon asset: %s" % error_string(write_error))
		quit(write_error)
		return

	var data: Dictionary = result["data"]
	var stats: Dictionary = data["stats"]
	print(
		"Compiled %s: %d faces, %d logical vertices, %d outline vertices -> %s"
		% [
			String(data["asset_id"]),
			int(stats["face_count"]),
			int(stats["logical_vertex_count"]),
			int(stats["outline_vertex_count"]),
			String(result["output_path"]),
		]
	)
	quit(0)
