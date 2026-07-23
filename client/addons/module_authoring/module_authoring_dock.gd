# Doc: docs/代码/module_authoring_pipeline.md
@tool
extends VBoxContainer
## JSON-first module editor. It never reads or mutates the edited scene tree.

const MODULE_SCENE_BAKER := preload("res://scripts/editor/module_scene_baker.gd")
const MODULE_JSON_DOCUMENT := preload("res://scripts/editor/module_json_document.gd")
const MODULE_JSON_CANVAS := preload("res://scripts/editor/module_json_canvas.gd")
const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_PLACEMENT_TYPES := preload("res://scripts/contracts/module_placement_types.gd")

const LAYER_OPTIONS: Array[String] = ["ground", "obstacles", "decoration", "placements"]
const TOOL_OPTIONS: Array[String] = ["select", "terrain", "tile", "placement", "erase"]
const ROTATION_OPTIONS: Array[int] = [0, 90, 180, 270]

var editor_interface: EditorInterface

var _document: ModuleJsonDocument
var _canvas: ModuleJsonCanvas
var _module_combo: OptionButton
var _layer_combo: OptionButton
var _tool_combo: OptionButton
var _terrain_combo: OptionButton
var _tile_combo: OptionButton
var _placement_combo: OptionButton
var _preview_rotation_combo: OptionButton
var _tile_id_edit: LineEdit
var _tile_rotation_combo: OptionButton
var _flip_h_check: CheckBox
var _flip_v_check: CheckBox
var _payload_edit: TextEdit
var _role_edit: LineEdit
var _tags_edit: LineEdit
var _source_edit: LineEdit
var _rotation_checks: Dictionary = {}
var _selected_cell_label: Label
var _socket_label: Label
var _status_label: Label
var _error_text: RichTextLabel
var _save_button: Button
var _reload_button: Button
var _undo_button: Button
var _redo_button: Button
var _validate_button: Button
var _bake_button: Button
var _approve_button: Button
var _new_button: Button
var _copy_button: Button
var _id_dialog: ConfirmationDialog
var _id_edit: LineEdit
var _discard_dialog: ConfirmationDialog
var _pending_operation: String = ""
var _pending_module_id: String = ""
var _last_persisted_module_id: String = ""
var _combo_change_guard: bool = false


func _ready() -> void:
	name = "Module JSON"
	custom_minimum_size = Vector2(420.0, 600.0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_document = MODULE_JSON_DOCUMENT.new() as ModuleJsonDocument
	_document.document_changed.connect(_on_document_changed)
	_document.document_loaded.connect(_on_document_loaded)
	_document.document_saved.connect(_on_document_saved)
	var initialize_result: Dictionary = _document.initialize()
	if not bool(initialize_result.get("ok", false)):
		_report_result("Initialize", initialize_result)
		_set_controls_enabled(false)
		return
	_refresh_module_list()
	var ids: PackedStringArray = _document.module_ids()
	if not ids.is_empty():
		_open_module(ids[0])


func _exit_tree() -> void:
	if _document != null:
		_document.dispose()


func _build_ui() -> void:
	var title := Label.new()
	title.text = "Module JSON Editor"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	var module_row := HBoxContainer.new()
	add_child(module_row)
	_module_combo = OptionButton.new()
	_module_combo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_module_combo.item_selected.connect(_on_module_selected)
	module_row.add_child(_module_combo)
	_new_button = _make_button("New", _on_new_pressed)
	module_row.add_child(_new_button)
	_copy_button = _make_button("Copy", _on_copy_pressed)
	module_row.add_child(_copy_button)

	var file_row := HBoxContainer.new()
	add_child(file_row)
	_save_button = _make_button("Save", _on_save_pressed)
	file_row.add_child(_save_button)
	_reload_button = _make_button("Reload", _on_reload_pressed)
	file_row.add_child(_reload_button)
	_undo_button = _make_button("Undo", _on_undo_pressed)
	file_row.add_child(_undo_button)
	_redo_button = _make_button("Redo", _on_redo_pressed)
	file_row.add_child(_redo_button)

	var action_row := HBoxContainer.new()
	add_child(action_row)
	_validate_button = _make_button("Validate", _on_validate_pressed)
	action_row.add_child(_validate_button)
	_bake_button = _make_button("Bake", _on_bake_pressed)
	action_row.add_child(_bake_button)
	_approve_button = _make_button("Approve", _on_approve_pressed)
	action_row.add_child(_approve_button)

	add_child(HSeparator.new())
	var editing_grid := GridContainer.new()
	editing_grid.columns = 2
	add_child(editing_grid)
	_add_labeled_option(editing_grid, "Layer", LAYER_OPTIONS, "_layer_combo")
	_add_labeled_option(editing_grid, "Tool", TOOL_OPTIONS, "_tool_combo")
	_add_labeled_option(
		editing_grid,
		"Terrain",
		[
			MODULE_CELL_TOKENS.MODULE_CELL_FLOOR,
			MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED,
		],
		"_terrain_combo"
	)
	_add_labeled_option(editing_grid, "Tile", [], "_tile_combo")
	_add_labeled_option(
		editing_grid,
		"Placement",
		_array_to_strings(MODULE_PLACEMENT_TYPES.VALUES),
		"_placement_combo"
	)
	_add_labeled_option(
		editing_grid,
		"Preview",
		["0°", "90°", "180°", "270°"],
		"_preview_rotation_combo",
		ROTATION_OPTIONS
	)
	_layer_combo.item_selected.connect(_on_layer_changed)
	_preview_rotation_combo.item_selected.connect(_on_preview_rotation_changed)

	_canvas = MODULE_JSON_CANVAS.new() as ModuleJsonCanvas
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.cell_primary_requested.connect(_on_canvas_primary)
	_canvas.cell_secondary_requested.connect(_on_canvas_secondary)
	_canvas.selected_cell_changed.connect(_on_selected_cell_changed)
	add_child(_canvas)

	var details := TabContainer.new()
	details.custom_minimum_size = Vector2(0.0, 250.0)
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(details)
	details.add_child(_build_cell_properties())
	details.add_child(_build_module_properties())
	details.add_child(_build_validation_panel())

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_id_dialog = ConfirmationDialog.new()
	_id_dialog.title = "Module id"
	_id_dialog.confirmed.connect(_on_id_dialog_confirmed)
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "module_example"
	_id_edit.custom_minimum_size = Vector2(360.0, 0.0)
	_id_dialog.add_child(_id_edit)
	add_child(_id_dialog)

	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = "Discard unsaved changes?"
	_discard_dialog.dialog_text = "The current module has unsaved changes."
	_discard_dialog.confirmed.connect(_on_discard_confirmed)
	add_child(_discard_dialog)


func _build_cell_properties() -> Control:
	var root := VBoxContainer.new()
	root.name = "Cell"
	_selected_cell_label = Label.new()
	_selected_cell_label.text = "Selected: none"
	root.add_child(_selected_cell_label)
	var tile_grid := GridContainer.new()
	tile_grid.columns = 2
	root.add_child(tile_grid)
	tile_grid.add_child(_make_label("Tile id"))
	_tile_id_edit = LineEdit.new()
	_tile_id_edit.placeholder_text = "module_tile_..."
	tile_grid.add_child(_tile_id_edit)
	tile_grid.add_child(_make_label("Tile rotation"))
	_tile_rotation_combo = _make_option(
		["0°", "90°", "180°", "270°"],
		ROTATION_OPTIONS
	)
	tile_grid.add_child(_tile_rotation_combo)
	tile_grid.add_child(_make_label("Transform"))
	var transform_row := HBoxContainer.new()
	_flip_h_check = CheckBox.new()
	_flip_h_check.text = "Flip H"
	transform_row.add_child(_flip_h_check)
	_flip_v_check = CheckBox.new()
	_flip_v_check.text = "Flip V"
	transform_row.add_child(_flip_v_check)
	tile_grid.add_child(transform_row)
	var apply_visual := _make_button("Apply visual to selected cell", _on_apply_visual_pressed)
	root.add_child(apply_visual)
	root.add_child(_make_label("Placement payload (JSON object)"))
	_payload_edit = TextEdit.new()
	_payload_edit.custom_minimum_size = Vector2(0.0, 82.0)
	_payload_edit.placeholder_text = "{}"
	root.add_child(_payload_edit)
	var apply_placement := _make_button(
		"Apply placement to selected cell",
		_on_apply_placement_pressed
	)
	root.add_child(apply_placement)
	return root


func _build_module_properties() -> Control:
	var root := VBoxContainer.new()
	root.name = "Module"
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	grid.add_child(_make_label("Role"))
	_role_edit = LineEdit.new()
	grid.add_child(_role_edit)
	grid.add_child(_make_label("Tags"))
	_tags_edit = LineEdit.new()
	_tags_edit.placeholder_text = "comma,separated"
	grid.add_child(_tags_edit)
	grid.add_child(_make_label("Source"))
	_source_edit = LineEdit.new()
	grid.add_child(_source_edit)
	grid.add_child(_make_label("Rotations"))
	var rotation_row := HBoxContainer.new()
	for rotation: int in ROTATION_OPTIONS:
		var check := CheckBox.new()
		check.text = str(rotation)
		rotation_row.add_child(check)
		_rotation_checks[rotation] = check
	grid.add_child(rotation_row)
	root.add_child(_make_button("Apply metadata", _on_apply_metadata_pressed))
	_socket_label = Label.new()
	_socket_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_socket_label)
	return root


func _build_validation_panel() -> Control:
	var root := VBoxContainer.new()
	root.name = "Validation"
	_error_text = RichTextLabel.new()
	_error_text.fit_content = false
	_error_text.scroll_active = true
	_error_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_error_text.custom_minimum_size = Vector2(0.0, 180.0)
	root.add_child(_error_text)
	return root


func _add_labeled_option(
	parent: GridContainer,
	label_text: String,
	values: Array[String],
	field_name: String,
	metadata_values: Array[int] = []
) -> void:
	parent.add_child(_make_label(label_text))
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index: int in range(values.size()):
		option.add_item(values[index])
		var metadata: Variant = metadata_values[index] if index < metadata_values.size() else values[index]
		option.set_item_metadata(index, metadata)
	parent.add_child(option)
	set(field_name, option)


func _make_option(labels: Array[String], metadata_values: Array[int]) -> OptionButton:
	var option := OptionButton.new()
	for index: int in range(labels.size()):
		option.add_item(labels[index])
		option.set_item_metadata(index, metadata_values[index])
	return option


func _make_button(label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.pressed.connect(callback)
	return button


func _make_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	return label


func _array_to_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _refresh_module_list() -> void:
	var selected_id: String = _document.module_id if _document != null else ""
	_combo_change_guard = true
	_module_combo.clear()
	var ids: PackedStringArray = _document.module_ids()
	if not selected_id.is_empty() and not ids.has(selected_id):
		ids.append(selected_id)
		ids.sort()
	for id_value: String in ids:
		_module_combo.add_item(id_value)
		_module_combo.set_item_metadata(_module_combo.item_count - 1, id_value)
	_select_module_in_combo(selected_id)
	_combo_change_guard = false


func _refresh_from_document() -> void:
	if _document == null:
		return
	_canvas.set_module_data(_document.module_data)
	_refresh_tile_catalog()
	_refresh_metadata_fields()
	_refresh_socket_text()
	_refresh_selected_cell()
	_refresh_buttons()
	var dirty_suffix: String = " *" if _document.dirty else ""
	_status_label.text = "%s%s — %s" % [
		_document.module_id,
		dirty_suffix,
		String(_document.registry_entry.get("review_status", "unknown")),
	]


func _refresh_tile_catalog() -> void:
	var previous: String = _selected_option_string(_tile_combo)
	_tile_combo.clear()
	for tile_id: String in _document.tile_catalog_ids():
		_tile_combo.add_item(tile_id)
		_tile_combo.set_item_metadata(_tile_combo.item_count - 1, tile_id)
	_select_option_by_metadata(_tile_combo, previous)


func _refresh_metadata_fields() -> void:
	_role_edit.text = String(_document.registry_entry.get("role", ""))
	var tags: PackedStringArray = []
	for tag_value: Variant in _document.registry_entry.get("tags", []) as Array:
		tags.append(String(tag_value))
	_tags_edit.text = ",".join(tags)
	_source_edit.text = String(_document.registry_entry.get("source", ""))
	var rotations: Array = _document.registry_entry.get("allowed_rotations", []) as Array
	for rotation: int in ROTATION_OPTIONS:
		var check: CheckBox = _rotation_checks.get(rotation) as CheckBox
		check.button_pressed = rotations.has(rotation)


func _refresh_socket_text() -> void:
	var sockets: Dictionary = _document.derived_edge_sockets()
	_socket_label.text = "Derived sockets: N %s  E %s  S %s  W %s" % [
		str(sockets.get("edge_north", [])),
		str(sockets.get("edge_east", [])),
		str(sockets.get("edge_south", [])),
		str(sockets.get("edge_west", [])),
	]


func _refresh_selected_cell() -> void:
	var cell: Vector2i = _canvas.selected_cell
	if cell.x < 0:
		_selected_cell_label.text = "Selected: none"
		return
	_selected_cell_label.text = "Selected: (%d, %d)" % [cell.x, cell.y]
	var layer_name: String = _selected_option_string(_layer_combo)
	if layer_name == "placements":
		var placement: Dictionary = _document.placement_at(cell)
		_payload_edit.text = _placement_payload_text(placement)
		if placement.has("type"):
			_select_option_by_metadata(_placement_combo, String(placement.get("type", "")))
		return
	var visual: Dictionary = _document.visual_at(layer_name, cell)
	if visual.is_empty():
		_tile_id_edit.text = _selected_option_string(_tile_combo)
		_tile_rotation_combo.select(0)
		_flip_h_check.button_pressed = false
		_flip_v_check.button_pressed = false
		return
	_tile_id_edit.text = String(visual.get("tile_id", ""))
	_select_option_by_metadata(_tile_rotation_combo, int(visual.get("rotation", 0)))
	_flip_h_check.button_pressed = bool(visual.get("flip_h", false))
	_flip_v_check.button_pressed = bool(visual.get("flip_v", false))


func _refresh_buttons() -> void:
	var has_document: bool = not _document.module_id.is_empty()
	_save_button.disabled = not has_document or not _document.dirty
	_reload_button.disabled = not has_document
	_undo_button.disabled = not _document.has_undo()
	_redo_button.disabled = not _document.has_redo()
	_validate_button.disabled = not has_document
	_bake_button.disabled = not has_document or _document.dirty or _document.is_new_document
	_approve_button.disabled = not has_document or _document.dirty or _document.is_new_document
	_copy_button.disabled = not has_document


func _set_controls_enabled(enabled: bool) -> void:
	for control_value: Variant in [
		_module_combo,
		_new_button,
		_copy_button,
		_save_button,
		_reload_button,
		_undo_button,
		_redo_button,
		_validate_button,
		_bake_button,
		_approve_button,
	]:
		var control: BaseButton = control_value as BaseButton
		control.disabled = not enabled


func _open_module(requested_id: String) -> void:
	var result: Dictionary = _document.open_module(requested_id)
	if not bool(result.get("ok", false)):
		_report_result("Open", result)
		return
	_last_persisted_module_id = requested_id
	_refresh_module_list()
	_clear_errors()
	_refresh_from_document()


func _on_document_changed() -> void:
	_refresh_from_document()


func _on_document_loaded(_loaded_id: String) -> void:
	_refresh_module_list()
	_clear_errors()
	_refresh_from_document()


func _on_document_saved(_saved_id: String) -> void:
	_last_persisted_module_id = _document.module_id
	_refresh_module_list()
	_refresh_from_document()
	if editor_interface != null:
		editor_interface.get_resource_filesystem().scan()


func _on_module_selected(index: int) -> void:
	if _combo_change_guard:
		return
	var requested_id: String = String(_module_combo.get_item_metadata(index))
	if requested_id == _document.module_id:
		return
	if _document.dirty:
		_pending_operation = "open"
		_pending_module_id = requested_id
		_combo_change_guard = true
		_select_module_in_combo(_document.module_id)
		_combo_change_guard = false
		_discard_dialog.popup_centered()
		return
	_open_module(requested_id)


func _on_new_pressed() -> void:
	_request_id_operation("new")


func _on_copy_pressed() -> void:
	_request_id_operation("copy")


func _request_id_operation(operation: String) -> void:
	if _document.dirty:
		_pending_operation = "%s_after_discard" % operation
		_discard_dialog.popup_centered()
		return
	_pending_operation = operation
	_id_edit.text = ""
	_id_dialog.title = "New module id" if operation == "new" else "Copy module as"
	_id_dialog.popup_centered()
	_id_edit.grab_focus()


func _on_id_dialog_confirmed() -> void:
	var requested_id: String = _id_edit.text.strip_edges()
	var result: Dictionary
	if _pending_operation == "new":
		result = _document.create_new(requested_id)
	else:
		result = _document.create_copy(requested_id)
	if not bool(result.get("ok", false)):
		_report_result("Create", result)
		return
	_refresh_module_list()
	_refresh_from_document()


func _on_discard_confirmed() -> void:
	var operation: String = _pending_operation
	if operation == "open":
		_open_module(_pending_module_id)
		return
	if operation == "reload":
		_discard_local_changes()
		return
	if not _discard_local_changes():
		return
	if operation == "new_after_discard":
		_request_id_operation("new")
	elif operation == "copy_after_discard":
		_request_id_operation("copy")


func _discard_local_changes() -> bool:
	if _document.is_new_document and not _last_persisted_module_id.is_empty():
		_open_module(_last_persisted_module_id)
		return _document.module_id == _last_persisted_module_id
	var reload_result: Dictionary = _document.reload_current()
	if not bool(reload_result.get("ok", false)):
		_report_result("Reload", reload_result)
		return false
	return true


func _on_save_pressed() -> void:
	var result: Dictionary = _document.save_current()
	_report_result("Save", result)


func _on_reload_pressed() -> void:
	if _document.dirty:
		_pending_operation = "reload"
		_discard_dialog.popup_centered()
		return
	_reload_document()


func _reload_document() -> void:
	var result: Dictionary = _document.reload_current()
	_report_result("Reload", result)


func _on_undo_pressed() -> void:
	_document.undo()


func _on_redo_pressed() -> void:
	_document.redo()


func _on_validate_pressed() -> void:
	var structure_result: Dictionary = _document.validate_structure()
	if not bool(structure_result.get("ok", false)):
		_report_result("Validate", structure_result)
		return
	if _document.dirty or _document.is_new_document:
		_report_result(
			"Validate",
			_error_result("Save the JSON before running full semantic validation.")
		)
		return
	_report_result(
		"Validate",
		_call_baker("validate_module", [_document.module_id])
	)


func _on_bake_pressed() -> void:
	if not _ensure_saved_for_action("Bake"):
		return
	var result: Dictionary = _call_baker("bake_module", [_document.module_id, true])
	_report_result("Bake", result)
	if bool(result.get("ok", false)) and editor_interface != null:
		editor_interface.get_resource_filesystem().scan()


func _on_approve_pressed() -> void:
	if not _ensure_saved_for_action("Approve"):
		return
	var result: Dictionary = _call_baker("approve_module", [_document.module_id])
	_report_result("Approve", result)
	if bool(result.get("ok", false)):
		_reload_document()
		if editor_interface != null:
			editor_interface.get_resource_filesystem().scan()


func _ensure_saved_for_action(action_name: String) -> bool:
	if _document.dirty or _document.is_new_document:
		_report_result(
			action_name,
			_error_result("Save the JSON before %s." % action_name.to_lower())
		)
		return false
	return true


func _on_layer_changed(_index: int) -> void:
	var layer_name: String = _selected_option_string(_layer_combo)
	_canvas.set_active_layer(layer_name)
	if layer_name == "placements":
		_select_option_by_metadata(_tool_combo, "placement")
	elif layer_name == "decoration" and _selected_option_string(_tool_combo) == "terrain":
		_select_option_by_metadata(_tool_combo, "tile")
	_refresh_selected_cell()


func _on_preview_rotation_changed(index: int) -> void:
	_canvas.set_preview_rotation(int(_preview_rotation_combo.get_item_metadata(index)))


func _on_canvas_primary(cell: Vector2i) -> void:
	var tool_name: String = _selected_option_string(_tool_combo)
	var layer_name: String = _selected_option_string(_layer_combo)
	match tool_name:
		"terrain":
			_document.set_terrain_cell(cell, _selected_option_string(_terrain_combo))
		"tile":
			if layer_name != "placements":
				_apply_visual(cell, layer_name)
		"placement":
			_apply_placement(cell)
		"erase":
			_erase_cell(cell, layer_name)
		_:
			_refresh_selected_cell()


func _on_canvas_secondary(cell: Vector2i) -> void:
	_erase_cell(cell, _selected_option_string(_layer_combo))


func _erase_cell(cell: Vector2i, layer_name: String) -> void:
	if layer_name == "placements":
		_document.erase_placement(cell)
	else:
		_document.erase_visual_cell(layer_name, cell)


func _on_selected_cell_changed(_cell: Vector2i) -> void:
	_refresh_selected_cell()


func _on_apply_visual_pressed() -> void:
	var layer_name: String = _selected_option_string(_layer_combo)
	if layer_name == "placements" or _canvas.selected_cell.x < 0:
		return
	_apply_visual(_canvas.selected_cell, layer_name)


func _apply_visual(cell: Vector2i, layer_name: String) -> void:
	var tile_id: String = _tile_id_edit.text.strip_edges()
	if tile_id.is_empty():
		tile_id = _selected_option_string(_tile_combo)
	var rotation: int = int(
		_tile_rotation_combo.get_item_metadata(_tile_rotation_combo.selected)
	)
	_document.set_visual_cell(
		layer_name,
		cell,
		tile_id,
		rotation,
		_flip_h_check.button_pressed,
		_flip_v_check.button_pressed
	)


func _on_apply_placement_pressed() -> void:
	if _canvas.selected_cell.x < 0:
		return
	_apply_placement(_canvas.selected_cell)


func _apply_placement(cell: Vector2i) -> void:
	var payload_result: Dictionary = _parse_payload()
	if not bool(payload_result.get("ok", false)):
		_report_result("Placement", payload_result)
		return
	_document.set_placement(
		cell,
		_selected_option_string(_placement_combo),
		payload_result.get("data", {}) as Dictionary
	)


func _parse_payload() -> Dictionary:
	var text_value: String = _payload_edit.text.strip_edges()
	if text_value.is_empty():
		text_value = "{}"
	var parsed: Variant = JSON.parse_string(text_value)
	if not parsed is Dictionary:
		return _error_result("Placement payload must be a JSON object.")
	var result := _success_result()
	result["data"] = parsed as Dictionary
	return result


func _on_apply_metadata_pressed() -> void:
	var role: String = _role_edit.text.strip_edges()
	var source: String = _source_edit.text.strip_edges()
	var tags: Array[String] = []
	for raw_tag: String in _tags_edit.text.split(",", false):
		var tag: String = raw_tag.strip_edges()
		if not tag.is_empty() and not tags.has(tag):
			tags.append(tag)
	tags.sort()
	var rotations: Array[int] = []
	for rotation: int in ROTATION_OPTIONS:
		var check: CheckBox = _rotation_checks.get(rotation) as CheckBox
		if check.button_pressed:
			rotations.append(rotation)
	_document.set_registry_properties(
		{
			"role": role,
			"tags": tags,
			"source": source,
			"allowed_rotations": rotations,
		}
	)


func _call_baker(method_name: String, arguments: Array) -> Dictionary:
	var callable := Callable(MODULE_SCENE_BAKER, method_name)
	if not callable.is_valid():
		return _error_result(
			"ModuleSceneBaker.%s is unavailable. Update the JSON-first baker interface." % method_name
		)
	var value: Variant = callable.callv(arguments)
	if not value is Dictionary:
		return _error_result("ModuleSceneBaker.%s returned an invalid result." % method_name)
	return value as Dictionary


func _report_result(action_name: String, result: Dictionary) -> void:
	var ok: bool = bool(result.get("ok", false))
	var errors: PackedStringArray = _result_errors(result)
	_error_text.clear()
	if ok:
		_error_text.append_text("[color=7ee39a]%s succeeded.[/color]\n" % action_name)
		_canvas.set_error_cells({})
	else:
		_error_text.append_text("[color=ff6b74]%s failed.[/color]\n" % action_name)
		for message: String in errors:
			_error_text.append_text("• %s\n" % message)
	_canvas.set_error_cells(_result_error_cells(result))
	_status_label.text = "%s %s" % [action_name, "complete" if ok else "failed"]
	if not ok:
		for message: String in errors:
			printerr("[module-authoring] %s" % message)
	else:
		print("[module-authoring] %s: %s" % [action_name, result])
	_refresh_buttons()


func _clear_errors() -> void:
	_error_text.clear()
	_canvas.set_error_cells({})


func _result_errors(result: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var value: Variant = result.get("errors", PackedStringArray())
	if value is PackedStringArray:
		return value as PackedStringArray
	if value is Array:
		for item: Variant in value as Array:
			errors.append(String(item))
	return errors


func _result_error_cells(result: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	var value: Variant = result.get("error_cells", [])
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if key is Vector2i:
				cells[key] = true
		return cells
	if value is Array:
		for item: Variant in value as Array:
			if item is Vector2i:
				cells[item] = true
			elif item is Dictionary:
				var cell: Dictionary = item as Dictionary
				cells[Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))] = true
	return cells


func _placement_payload_text(placement: Dictionary) -> String:
	if placement.is_empty():
		return "{}"
	var payload: Dictionary = placement.duplicate(true)
	payload.erase("type")
	payload.erase("cell")
	return JSON.stringify(payload, "  ", false, true)


func _select_module_in_combo(requested_id: String) -> void:
	for index: int in range(_module_combo.item_count):
		if String(_module_combo.get_item_metadata(index)) == requested_id:
			_module_combo.select(index)
			return


func _select_option_by_metadata(option: OptionButton, value: Variant) -> void:
	for index: int in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return


func _selected_option_string(option: OptionButton) -> String:
	if option == null or option.item_count == 0 or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func _success_result() -> Dictionary:
	return {"ok": true, "errors": PackedStringArray()}


func _error_result(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
