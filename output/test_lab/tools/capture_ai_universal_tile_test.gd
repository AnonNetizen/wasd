extends SceneTree

const GRID_SCRIPT := preload("res://scripts/universal_tile_grid.gd")
const LAYER_CELL_TILES: String = "cell_tiles"
const LAYER_COLLISION: String = "collision"
const LAYER_DETAIL: String = "detail"
const LAYER_METADATA: String = "metadata"
const SCENE_PATH: String = "res://scenes/ai_universal_tile_test.tscn"
const SCREENSHOT_PATH: String = "res://screenshots/ai_universal_tile_test.png"

var _capture_time: float = -1.0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--capture-time="):
			continue
		var value := argument.trim_prefix("--capture-time=")
		if not value.is_valid_float():
			_fail("Invalid --capture-time value: %s" % value)
			return
		_capture_time = value.to_float()
	call_deferred("_capture")


func _capture() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load scene: %s" % SCENE_PATH)
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame_index in range(12):
		await process_frame

	var grid: GRID_SCRIPT = scene.get_node_or_null("UniversalTileGrid") as GRID_SCRIPT
	if grid == null:
		_fail("AI universal Tile scene is missing UniversalTileGrid.")
		return
	if not _prepare_layer_controls(scene, grid):
		return
	if _capture_time >= 0.0:
		grid.debug_prepare_capture(_capture_time)
	else:
		grid.debug_prepare_capture()

	var summary: Dictionary = grid.get_generation_summary()
	var grid_size := _array_to_vector2i(summary.get("grid_size", []))
	var tile_size := _array_to_vector2i(summary.get("tile_size_px", []))
	var target_cell := _find_tile_cell(grid, grid_size, "wood_cabinet_01")
	if target_cell.x < 0 or target_cell.y < 0:
		_fail("Could not find a cabinet tile for the metadata screenshot.")
		return
	if tile_size.x <= 0 or tile_size.y <= 0:
		_fail("Runtime summary does not expose a valid tile_size_px.")
		return

	if scene.has_method("debug_set_hovered_cell"):
		scene.call("debug_set_hovered_cell", target_cell)
	else:
		grid.set_metadata_hovered_cell(target_cell)
	var target_center := Vector2(
		(float(target_cell.x) + 0.5) * float(tile_size.x),
		(float(target_cell.y) + 0.5) * float(tile_size.y)
	)
	Input.warp_mouse(grid.to_global(target_center))
	for _frame_index in range(6):
		await process_frame

	var viewport_texture := root.get_texture()
	if viewport_texture == null:
		_fail("Failed to read root viewport texture.")
		return
	var image := viewport_texture.get_image()
	if image == null:
		_fail("Failed to read root viewport image.")
		return

	var screenshot_path := ProjectSettings.globalize_path(SCREENSHOT_PATH)
	var screenshot_directory := screenshot_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(screenshot_directory)
	if directory_error != OK:
		_fail("Failed to create screenshot directory: %s" % error_string(directory_error), directory_error)
		return
	var save_error := image.save_png(screenshot_path)
	if save_error != OK:
		_fail("Failed to save screenshot: %s" % error_string(save_error), save_error)
		return

	var capture_label := "default" if _capture_time < 0.0 else "%.3f" % _capture_time
	print("Saved screenshot: %s (capture_time=%s)" % [screenshot_path, capture_label])
	quit(0)


func _prepare_layer_controls(scene: Node, grid: GRID_SCRIPT) -> bool:
	var layer_states: Dictionary = {
		LAYER_CELL_TILES: {"toggle": "CellTilesToggle", "visible": true},
		LAYER_COLLISION: {"toggle": "CollisionToggle", "visible": false},
		LAYER_DETAIL: {"toggle": "DetailToggle", "visible": false},
		LAYER_METADATA: {"toggle": "MetadataToggle", "visible": false},
	}
	for layer_id: String in layer_states:
		var state: Dictionary = layer_states[layer_id]
		var toggle_path := "Sidebar/Margin/Rows/LayerToggles/%s" % String(state["toggle"])
		var toggle := scene.get_node_or_null(toggle_path) as CheckButton
		if toggle == null:
			_fail("Screenshot scene is missing layer toggle: %s" % toggle_path)
			return false
		var visible := bool(state["visible"])
		toggle.set_pressed_no_signal(visible)
		grid.set_layer_visible(layer_id, visible)
	return true


func _find_tile_cell(grid: GRID_SCRIPT, grid_size: Vector2i, asset_id: String) -> Vector2i:
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			var metadata: Dictionary = grid.get_cell_metadata(cell)
			var tile_value: Variant = metadata.get("tile", {})
			if tile_value is Dictionary and String((tile_value as Dictionary).get("id", "")) == asset_id:
				return cell
	return Vector2i(-1, -1)


func _array_to_vector2i(value: Variant) -> Vector2i:
	if not value is Array or (value as Array).size() != 2:
		return Vector2i.ZERO
	var values: Array = value
	return Vector2i(int(values[0]), int(values[1]))


func _fail(message: String, error_code: int = 1) -> void:
	push_error(message)
	quit(error_code)
