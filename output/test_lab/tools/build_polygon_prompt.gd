extends SceneTree

const PROMPT_BUILDER := preload(
	"res://scripts/polygon_prompt_builder.gd"
)


func _initialize() -> void:
	var manifest_path := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			manifest_path = argument.trim_prefix("--manifest=")
	if manifest_path.is_empty():
		push_error("Missing --manifest=<res://path>.")
		quit(ERR_INVALID_PARAMETER)
		return
	var builder := PROMPT_BUILDER.new()
	var result: Dictionary = builder.build_from_manifest(manifest_path)
	if not bool(result.get("ok", false)):
		push_error(String(result.get(
			"error",
			"Polygon prompt generation failed."
		)))
		quit(ERR_INVALID_DATA)
		return
	print("POLYGON_PROMPT_BEGIN")
	print(String(result["prompt"]))
	print("POLYGON_PROMPT_END")
	quit(0)
