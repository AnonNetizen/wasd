extends Control

const ACTION_BACK: String = "lab_back"
const ACTION_REGENERATE: String = "lab_regenerate"
const CONFIG_PATH: String = "res://data/ai_universal_tile_test.json"
const GRID_SCRIPT := preload("res://scripts/universal_tile_grid.gd")
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"

@onready var _back_button: Button = get_node_or_null("Sidebar/Margin/Rows/BackButton") as Button
@onready var _cell_tiles_toggle: CheckButton = get_node_or_null("Sidebar/Margin/Rows/LayerToggles/CellTilesToggle") as CheckButton
@onready var _collision_toggle: CheckButton = get_node_or_null("Sidebar/Margin/Rows/LayerToggles/CollisionToggle") as CheckButton
@onready var _detail_toggle: CheckButton = get_node_or_null("Sidebar/Margin/Rows/LayerToggles/DetailToggle") as CheckButton
@onready var _error_label: Label = get_node_or_null("Sidebar/Margin/Rows/ErrorLabel") as Label
@onready var _grid: GRID_SCRIPT = get_node_or_null("UniversalTileGrid") as GRID_SCRIPT
@onready var _hover_label: Label = get_node_or_null("Sidebar/Margin/Rows/HoverPanel/Margin/HoverLabel") as Label
@onready var _metadata_toggle: CheckButton = get_node_or_null("Sidebar/Margin/Rows/LayerToggles/MetadataToggle") as CheckButton
@onready var _regenerate_button: Button = get_node_or_null("Sidebar/Margin/Rows/RegenerateButton") as Button
@onready var _seed_label: Label = get_node_or_null("Sidebar/Margin/Rows/SeedLabel") as Label
@onready var _summary_label: Label = get_node_or_null("Sidebar/Margin/Rows/SummaryLabel") as Label

var _current_seed: int = 0
var _hovered_cell: Vector2i = Vector2i(-1, -1)
var _ready_for_input: bool = false
var _seed_step: int = 1


func _ready() -> void:
	_ensure_input_actions()
	_connect_ui()
	var scene_config := _load_json_dictionary(CONFIG_PATH)
	if scene_config.is_empty():
		_show_error("Could not load scene config: %s" % CONFIG_PATH)
		return
	var style_pack_path := String(scene_config.get("style_pack_path", ""))
	var style_pack := _load_json_dictionary(style_pack_path)
	if style_pack.is_empty():
		_show_error("Could not load Style Pack: %s" % style_pack_path)
		return
	if _grid == null:
		_show_error("UniversalTileGrid node is missing.")
		return

	var configure_error: Error = _grid.configure(style_pack, scene_config)
	if configure_error != OK:
		_show_error("Grid configure failed: %s" % error_string(configure_error))
		return

	_current_seed = int(scene_config.get("base_seed", 0))
	_seed_step = maxi(int(scene_config.get("seed_step", 1)), 1)
	_grid.regenerate(_current_seed)
	_update_generation_labels()
	_update_hover_label(Vector2i(-1, -1))
	_ready_for_input = true


func _process(_delta: float) -> void:
	if not _ready_for_input or _grid == null:
		return
	var mouse_position := get_viewport().get_mouse_position()
	var cell: Vector2i = _grid.world_to_cell(mouse_position)
	if cell == _hovered_cell:
		return
	_hovered_cell = cell
	_grid.set_metadata_hovered_cell(cell)
	_update_hover_label(cell)


func debug_set_hovered_cell(cell: Vector2i) -> void:
	if _grid == null:
		return
	_hovered_cell = cell
	_grid.set_metadata_hovered_cell(cell)
	_update_hover_label(cell)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_BACK):
		_return_to_index()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_REGENERATE):
		_regenerate_next_seed()
		get_viewport().set_input_as_handled()


func _connect_ui() -> void:
	if _back_button != null:
		_back_button.pressed.connect(_return_to_index)
	if _regenerate_button != null:
		_regenerate_button.pressed.connect(_regenerate_next_seed)
	_connect_layer_toggle(_cell_tiles_toggle, GRID_SCRIPT.LAYER_CELL_TILES)
	_connect_layer_toggle(_collision_toggle, GRID_SCRIPT.LAYER_COLLISION)
	_connect_layer_toggle(_detail_toggle, GRID_SCRIPT.LAYER_DETAIL)
	_connect_layer_toggle(_metadata_toggle, GRID_SCRIPT.LAYER_METADATA)


func _connect_layer_toggle(toggle: CheckButton, layer_id: String) -> void:
	if toggle == null:
		return
	toggle.toggled.connect(_set_grid_layer_visible.bind(layer_id))


func _set_grid_layer_visible(visible: bool, layer_id: String) -> void:
	if _grid != null:
		_grid.set_layer_visible(layer_id, visible)


func _regenerate_next_seed() -> void:
	if not _ready_for_input or _grid == null:
		return
	_current_seed += _seed_step
	_grid.regenerate(_current_seed)
	_hovered_cell = Vector2i(-1, -1)
	_update_generation_labels()
	_update_hover_label(_hovered_cell)


func _return_to_index() -> void:
	var change_error := get_tree().change_scene_to_file(INDEX_SCENE_PATH)
	if change_error != OK:
		_show_error("Could not return to Test Lab index: %s" % error_string(change_error))


func _update_generation_labels() -> void:
	if _grid == null:
		return
	var summary: Dictionary = _grid.get_generation_summary()
	var tile_counts: Dictionary = summary.get("tile_counts", {})
	if _seed_label != null:
		_seed_label.text = "Seed  %d" % int(summary.get("seed", 0))
	if _summary_label != null:
		_summary_label.text = (
			"%d marble  ·  %d trees  ·  %d cabinets\n"
			+ "%d balanced-overlap cells  ·  symmetric fused seams  ·  continuous floor breath"
		) % [
			int(tile_counts.get("marble_floor_01", 0)),
			int(tile_counts.get("tree_01", 0)),
			int(tile_counts.get("wood_cabinet_01", 0)),
			int(summary.get("cell_count", 0)),
		]


func _update_hover_label(cell: Vector2i) -> void:
	if _hover_label == null:
		return
	if _grid == null or cell.x < 0 or cell.y < 0:
		_hover_label.text = "Hover a cell to inspect its metadata."
		return
	var metadata: Dictionary = _grid.get_cell_metadata(cell)
	var tile_metadata: Dictionary = metadata.get("tile", {})
	var collision: Dictionary = metadata.get("collision", {})
	var interaction: Dictionary = metadata.get("interaction", {})
	var tile_id := String(tile_metadata.get("id", "none"))
	_hover_label.text = (
		"Cell (%d, %d)\n"
		+ "Layers: %s\n"
		+ "Tile: %s\n"
		+ "Tags: %s\n"
		+ "Footprint: %s\n"
		+ "Collision: %s\n"
		+ "Interactable: %s  ·  Lootable: %s"
	) % [
		cell.x,
		cell.y,
		", ".join(PackedStringArray(metadata.get("layers", []))),
		tile_id,
		", ".join(PackedStringArray(metadata.get("tags", []))),
		str(metadata.get("footprint_cells", [1, 1])),
		_collision_text(collision),
		str(bool(interaction.get("interactable", false))),
		str(bool(interaction.get("lootable", false))),
	]


func _collision_text(collision: Dictionary) -> String:
	match String(collision.get("shape", "none")):
		"circle":
			return "circle r=%s offset=%s" % [
				str(collision.get("radius_px", 0)),
				str(collision.get("offset_px", [0, 0])),
			]
		"rectangle":
			return "rect %s offset=%s" % [
				str(collision.get("size_px", [])),
				str(collision.get("offset_px", [0, 0])),
			]
		_:
			return "none"


func _show_error(message: String) -> void:
	push_error(message)
	if _error_label != null:
		_error_label.text = message
		_error_label.visible = true


func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		push_error("JSON parse failed for %s at line %d: %s" % [
			path,
			parser.get_error_line(),
			parser.get_error_message(),
		])
		return {}
	if not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_REGENERATE, KEY_R)
	_register_key_action(ACTION_BACK, KEY_ESCAPE)


func _register_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event: InputEvent in InputMap.action_get_events(action_name):
		var existing_key := existing_event as InputEventKey
		if existing_key != null and existing_key.keycode == keycode:
			return
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action_name, key_event)
