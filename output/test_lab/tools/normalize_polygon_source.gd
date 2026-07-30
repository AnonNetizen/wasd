extends SceneTree

const DEFAULT_KEY := Color("#ff00ff")
const DEFAULT_THRESHOLD: float = 0.42


func _initialize() -> void:
	var source_path := ""
	var threshold := DEFAULT_THRESHOLD
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			source_path = argument.trim_prefix("--source=")
		elif argument.begins_with("--threshold="):
			var value := argument.trim_prefix("--threshold=")
			if value.is_valid_float():
				threshold = value.to_float()
	if source_path.is_empty():
		push_error("Missing --source=<res://path>.")
		quit(ERR_INVALID_PARAMETER)
		return

	var image := Image.new()
	var absolute_path := ProjectSettings.globalize_path(source_path)
	var load_error := image.load(absolute_path)
	if load_error != OK:
		push_error("Failed to load source image: %s" % error_string(load_error))
		quit(load_error)
		return

	var normalized_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if _rgb_distance(color, DEFAULT_KEY) <= threshold:
				image.set_pixel(x, y, DEFAULT_KEY)
				normalized_pixels += 1

	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		push_error("Failed to save normalized source image: %s" % error_string(save_error))
		quit(save_error)
		return

	print(
		"Normalized %d background pixels to #ff00ff in %s."
		% [normalized_pixels, source_path]
	)
	quit(0)


func _rgb_distance(first: Color, second: Color) -> float:
	var delta := Vector3(first.r - second.r, first.g - second.g, first.b - second.b)
	return delta.length()
