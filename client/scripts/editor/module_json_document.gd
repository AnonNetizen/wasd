# Doc: docs/代码/module_authoring_pipeline.md
@tool
class_name ModuleJsonDocument
extends RefCounted
## Editor-only document model for deterministic, conflict-safe module JSON editing.

signal document_changed
signal document_loaded(module_id: String)
signal document_saved(module_id: String)

const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_REVIEW_STATUSES := preload("res://scripts/contracts/module_review_statuses.gd")

const MODULE_SIZE: int = 11
const MODULE_SCHEMA_VERSION: int = 2
const DEFAULT_REGISTRY_PATH: String = "res://data/module_templates.json"
const DEFAULT_MODULE_DIRECTORY: String = "res://data/modules"
const DEFAULT_TILE_CATALOG_PATH: String = "res://data/module_tile_catalog.json"
const GROUND_LAYER: String = "ground"
const OBSTACLE_LAYER: String = "obstacles"
const DECORATION_LAYER: String = "decoration"
const DEFAULT_GROUND_TILE_ID: String = "module_tile_ground_default"
const DEFAULT_OBSTACLE_TILE_ID: String = "module_tile_obstacle_default"
const DEFAULT_DECORATION_TILE_ID: String = "module_tile_decoration_default"

var module_id: String = ""
var module_path: String = ""
var module_data: Dictionary = {}
var registry_entry: Dictionary = {}
var dirty: bool = false
var is_new_document: bool = false
var registry_path: String = DEFAULT_REGISTRY_PATH
var module_directory: String = DEFAULT_MODULE_DIRECTORY
var tile_catalog_path: String = DEFAULT_TILE_CATALOG_PATH

var _registry: Dictionary = {}
var _loaded_module_hash: String = ""
var _loaded_registry_hash: String = ""
var _original_module_signature: String = ""
var _original_entry_signature: String = ""
var _original_gameplay_signature: String = ""
var _undo_redo := UndoRedo.new()


func initialize() -> Dictionary:
	var registry_result: Dictionary = _load_json_dictionary(registry_path)
	if not bool(registry_result.get("ok", false)):
		return registry_result
	_registry = registry_result.get("data", {}) as Dictionary
	_loaded_registry_hash = _disk_hash(registry_path)
	return _success_result()


func configure_paths(
	custom_registry_path: String,
	custom_module_directory: String,
	custom_tile_catalog_path: String = ""
) -> void:
	registry_path = custom_registry_path
	module_directory = custom_module_directory
	tile_catalog_path = (
		custom_tile_catalog_path
		if not custom_tile_catalog_path.is_empty()
		else DEFAULT_TILE_CATALOG_PATH
	)


func dispose() -> void:
	if is_instance_valid(_undo_redo):
		_undo_redo.clear_history()
		_undo_redo.free()
	module_data.clear()
	registry_entry.clear()
	_registry.clear()


func module_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry_value: Variant in _registry.get("templates", []) as Array:
		if entry_value is Dictionary:
			var candidate_id: String = String((entry_value as Dictionary).get("id", ""))
			if not candidate_id.is_empty():
				ids.append(candidate_id)
	ids.sort()
	return ids


func open_module(requested_module_id: String) -> Dictionary:
	var entry: Dictionary = _registry_entry_for_id(requested_module_id)
	if entry.is_empty():
		return _error_result("Unknown module id: %s" % requested_module_id)
	var path: String = String(entry.get("path", _module_path_for_id(requested_module_id)))
	var load_result: Dictionary = _load_json_dictionary(path)
	if not bool(load_result.get("ok", false)):
		return load_result
	module_id = requested_module_id
	module_path = path
	module_data = _normalize_module(load_result.get("data", {}) as Dictionary, requested_module_id)
	registry_entry = entry.duplicate(true)
	is_new_document = false
	_loaded_module_hash = _disk_hash(module_path)
	_loaded_registry_hash = _disk_hash(registry_path)
	_reset_history_and_baseline()
	document_loaded.emit(module_id)
	return _success_result()


func reload_current() -> Dictionary:
	if module_id.is_empty():
		return _error_result("No module is open.")
	var requested_id: String = module_id
	var registry_result: Dictionary = initialize()
	if not bool(registry_result.get("ok", false)):
		return registry_result
	return open_module(requested_id)


func create_new(requested_module_id: String) -> Dictionary:
	var id_error: String = _module_id_error(requested_module_id)
	if not id_error.is_empty():
		return _error_result(id_error)
	if not _registry_entry_for_id(requested_module_id).is_empty():
		return _error_result("Module id already exists: %s" % requested_module_id)
	module_id = requested_module_id
	module_path = _module_path_for_id(requested_module_id)
	module_data = _new_module_data(requested_module_id)
	registry_entry = _new_registry_entry(requested_module_id)
	is_new_document = true
	_loaded_module_hash = ""
	_loaded_registry_hash = _disk_hash(registry_path)
	_original_module_signature = ""
	_original_entry_signature = ""
	_original_gameplay_signature = ""
	_undo_redo.clear_history()
	dirty = true
	document_loaded.emit(module_id)
	document_changed.emit()
	return _success_result()


func create_copy(requested_module_id: String) -> Dictionary:
	if module_data.is_empty():
		return _error_result("Open a module before copying it.")
	var id_error: String = _module_id_error(requested_module_id)
	if not id_error.is_empty():
		return _error_result(id_error)
	if not _registry_entry_for_id(requested_module_id).is_empty():
		return _error_result("Module id already exists: %s" % requested_module_id)
	module_id = requested_module_id
	module_path = _module_path_for_id(requested_module_id)
	module_data = module_data.duplicate(true)
	module_data["id"] = requested_module_id
	registry_entry = registry_entry.duplicate(true)
	registry_entry["id"] = requested_module_id
	registry_entry["path"] = module_path
	registry_entry["review_status"] = MODULE_REVIEW_STATUSES.MODULE_REVIEW_CANDIDATE
	registry_entry.erase("approved_source_hash")
	registry_entry.erase("approved_gameplay_hash")
	is_new_document = true
	_loaded_module_hash = ""
	_loaded_registry_hash = _disk_hash(registry_path)
	_original_module_signature = ""
	_original_entry_signature = ""
	_original_gameplay_signature = ""
	_undo_redo.clear_history()
	dirty = true
	document_loaded.emit(module_id)
	document_changed.emit()
	return _success_result()


func save_current() -> Dictionary:
	if module_data.is_empty() or module_id.is_empty():
		return _error_result("No module is open.")
	var structure_result: Dictionary = validate_structure()
	if not bool(structure_result.get("ok", false)):
		return structure_result
	if not is_new_document and _disk_hash(module_path) != _loaded_module_hash:
		return _error_result(
			"%s changed on disk. Reload it before saving or explicitly discard the external change." % module_path
		)

	var prepared_module: Dictionary = _canonical_module(module_data)
	var prepared_entry: Dictionary = _canonical_registry_entry(registry_entry)
	var gameplay_changed: bool = (
		is_new_document
		or _gameplay_signature(prepared_module, prepared_entry) != _original_gameplay_signature
	)
	if (
		gameplay_changed
		and String(prepared_entry.get("review_status", ""))
		== MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED
	):
		prepared_entry["review_status"] = MODULE_REVIEW_STATUSES.MODULE_REVIEW_CANDIDATE
		prepared_entry.erase("approved_source_hash")
		prepared_entry.erase("approved_gameplay_hash")

	var prepared_registry: Dictionary = _registry_with_entry(prepared_entry)
	var registry_changed: bool = (
		_json_signature(prepared_registry) != _json_signature(_registry)
	)
	if registry_changed and _disk_hash(registry_path) != _loaded_registry_hash:
		return _error_result(
			"%s changed on disk. Reload before saving so registry edits are not overwritten." % registry_path
		)

	var write_error: String
	if registry_changed:
		write_error = _atomic_write_json_batch(
			{
				module_path: prepared_module,
				registry_path: prepared_registry,
			}
		)
	else:
		write_error = _atomic_write_json(module_path, prepared_module)
	if not write_error.is_empty():
		return _error_result(write_error)

	_registry = prepared_registry
	module_data = prepared_module
	registry_entry = prepared_entry
	is_new_document = false
	_loaded_module_hash = _disk_hash(module_path)
	_loaded_registry_hash = _disk_hash(registry_path)
	_reset_history_and_baseline()
	document_saved.emit(module_id)
	return _success_result()


func validate_structure() -> Dictionary:
	var result := _success_result()
	if String(module_data.get("id", "")) != module_id:
		_add_error(result, "Module JSON id must match %s." % module_id)
	if int(module_data.get("schema_version", -1)) != MODULE_SCHEMA_VERSION:
		_add_error(result, "schema_version must be %d." % MODULE_SCHEMA_VERSION)
	if int(module_data.get("columns", -1)) != MODULE_SIZE or int(module_data.get("rows", -1)) != MODULE_SIZE:
		_add_error(result, "Module dimensions must be %d x %d." % [MODULE_SIZE, MODULE_SIZE])
	var terrain_rows: Array = module_data.get("terrain_rows", []) as Array
	if terrain_rows.size() != MODULE_SIZE:
		_add_error(result, "terrain_rows must contain %d rows." % MODULE_SIZE)
	else:
		for y: int in range(MODULE_SIZE):
			if not terrain_rows[y] is Array or (terrain_rows[y] as Array).size() != MODULE_SIZE:
				_add_error(result, "terrain_rows[%d] must contain %d cells." % [y, MODULE_SIZE])
	var placements_value: Variant = module_data.get("placements", [])
	if not placements_value is Array:
		_add_error(result, "placements must be an Array.")
	var visual_layers_value: Variant = module_data.get("visual_layers", {})
	if not visual_layers_value is Dictionary:
		_add_error(result, "visual_layers must be a Dictionary.")
	else:
		var visual_layers: Dictionary = visual_layers_value as Dictionary
		for layer_name: String in [GROUND_LAYER, OBSTACLE_LAYER, DECORATION_LAYER]:
			if not visual_layers.get(layer_name, {}) is Dictionary:
				_add_error(result, "visual_layers.%s must be a Dictionary." % layer_name)
	return result


func set_terrain_cell(cell: Vector2i, token: String) -> void:
	if not _is_cell_inside(cell):
		return
	var next_module: Dictionary = module_data.duplicate(true)
	var terrain_rows: Array = next_module.get("terrain_rows", []) as Array
	if terrain_rows.size() != MODULE_SIZE or not terrain_rows[cell.y] is Array:
		return
	var row: Array = terrain_rows[cell.y] as Array
	if row.size() != MODULE_SIZE or String(row[cell.x]) == token:
		return
	row[cell.x] = token
	_commit_edit("Paint terrain", next_module, registry_entry)


func set_visual_cell(
	layer_name: String,
	cell: Vector2i,
	tile_id: String,
	rotation: int,
	flip_h: bool,
	flip_v: bool
) -> void:
	if not _is_cell_inside(cell) or tile_id.is_empty():
		return
	var next_module: Dictionary = module_data.duplicate(true)
	var layers: Dictionary = next_module.get("visual_layers", {}) as Dictionary
	var layer_data: Dictionary = layers.get(layer_name, {}) as Dictionary
	var list_key: String = "cells" if layer_name == DECORATION_LAYER else "overrides"
	var cells: Array = layer_data.get(list_key, []) as Array
	var visual_cell: Dictionary = {
		"cell": {"x": cell.x, "y": cell.y},
		"tile_id": tile_id,
		"rotation": posmod(rotation, 360),
		"flip_h": flip_h,
		"flip_v": flip_v,
	}
	var existing_index: int = _cell_entry_index(cells, cell)
	if existing_index >= 0:
		cells[existing_index] = visual_cell
	else:
		cells.append(visual_cell)
	layer_data[list_key] = cells
	layers[layer_name] = layer_data
	next_module["visual_layers"] = layers
	_commit_edit("Paint %s visual" % layer_name, next_module, registry_entry)


func erase_visual_cell(layer_name: String, cell: Vector2i) -> void:
	var next_module: Dictionary = module_data.duplicate(true)
	var layers: Dictionary = next_module.get("visual_layers", {}) as Dictionary
	var layer_data: Dictionary = layers.get(layer_name, {}) as Dictionary
	var list_key: String = "cells" if layer_name == DECORATION_LAYER else "overrides"
	var cells: Array = layer_data.get(list_key, []) as Array
	var existing_index: int = _cell_entry_index(cells, cell)
	if existing_index < 0:
		return
	cells.remove_at(existing_index)
	layer_data[list_key] = cells
	layers[layer_name] = layer_data
	next_module["visual_layers"] = layers
	_commit_edit("Erase %s visual" % layer_name, next_module, registry_entry)


func set_placement(cell: Vector2i, placement_type: String, payload: Dictionary) -> void:
	if not _is_cell_inside(cell):
		return
	var next_module: Dictionary = module_data.duplicate(true)
	var placements: Array = next_module.get("placements", []) as Array
	var placement: Dictionary = _sorted_dictionary(payload)
	placement["type"] = placement_type
	placement["cell"] = {"x": cell.x, "y": cell.y}
	var existing_index: int = _cell_entry_index(placements, cell)
	if existing_index >= 0:
		placements[existing_index] = placement
	else:
		placements.append(placement)
	next_module["placements"] = placements
	_commit_edit("Set placement", next_module, registry_entry)


func erase_placement(cell: Vector2i) -> void:
	var next_module: Dictionary = module_data.duplicate(true)
	var placements: Array = next_module.get("placements", []) as Array
	var existing_index: int = _cell_entry_index(placements, cell)
	if existing_index < 0:
		return
	placements.remove_at(existing_index)
	next_module["placements"] = placements
	_commit_edit("Erase placement", next_module, registry_entry)


func set_registry_property(property_name: String, value: Variant) -> void:
	if registry_entry.get(property_name) == value:
		return
	var next_entry: Dictionary = registry_entry.duplicate(true)
	next_entry[property_name] = value
	_commit_edit("Change module metadata", module_data, next_entry)


func set_registry_properties(values: Dictionary) -> void:
	var next_entry: Dictionary = registry_entry.duplicate(true)
	var changed: bool = false
	for property_name_value: Variant in values.keys():
		var property_name: String = String(property_name_value)
		var value: Variant = values[property_name_value]
		if next_entry.get(property_name) != value:
			next_entry[property_name] = value
			changed = true
	if changed:
		_commit_edit("Change module metadata", module_data, next_entry)


func undo() -> void:
	if _undo_redo.has_undo():
		_undo_redo.undo()


func redo() -> void:
	if _undo_redo.has_redo():
		_undo_redo.redo()


func has_undo() -> bool:
	return _undo_redo.has_undo()


func has_redo() -> bool:
	return _undo_redo.has_redo()


func placement_at(cell: Vector2i) -> Dictionary:
	for placement_value: Variant in module_data.get("placements", []) as Array:
		if placement_value is Dictionary and _entry_cell(placement_value as Dictionary) == cell:
			return (placement_value as Dictionary).duplicate(true)
	return {}


func visual_at(layer_name: String, cell: Vector2i) -> Dictionary:
	var layers: Dictionary = module_data.get("visual_layers", {}) as Dictionary
	var layer_data: Dictionary = layers.get(layer_name, {}) as Dictionary
	var list_key: String = "cells" if layer_name == DECORATION_LAYER else "overrides"
	for cell_value: Variant in layer_data.get(list_key, []) as Array:
		if cell_value is Dictionary and _entry_cell(cell_value as Dictionary) == cell:
			return (cell_value as Dictionary).duplicate(true)
	return {}


func tile_catalog_ids() -> PackedStringArray:
	var result := PackedStringArray([
		DEFAULT_GROUND_TILE_ID,
		DEFAULT_OBSTACLE_TILE_ID,
		DEFAULT_DECORATION_TILE_ID,
	])
	if not FileAccess.file_exists(tile_catalog_path):
		return result
	var catalog_result: Dictionary = _load_json_dictionary(tile_catalog_path)
	if not bool(catalog_result.get("ok", false)):
		return result
	var catalog: Dictionary = catalog_result.get("data", {}) as Dictionary
	var tiles_value: Variant = catalog.get("tiles", [])
	if tiles_value is Array:
		for tile_value: Variant in tiles_value as Array:
			if tile_value is Dictionary:
				var tile_id: String = String((tile_value as Dictionary).get("id", ""))
				if not tile_id.is_empty() and not result.has(tile_id):
					result.append(tile_id)
	elif tiles_value is Dictionary:
		for tile_key: Variant in (tiles_value as Dictionary).keys():
			var tile_id: String = String(tile_key)
			if not tile_id.is_empty() and not result.has(tile_id):
				result.append(tile_id)
	result.sort()
	return result


func derived_edge_sockets() -> Dictionary:
	return _derive_edge_sockets(module_data.get("terrain_rows", []) as Array)


func _commit_edit(action_name: String, next_module: Dictionary, next_entry: Dictionary) -> void:
	var do_state: Callable = Callable(self, "_apply_state").bind(
		next_module.duplicate(true),
		next_entry.duplicate(true)
	)
	var undo_state: Callable = Callable(self, "_apply_state").bind(
		module_data.duplicate(true),
		registry_entry.duplicate(true)
	)
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_method(do_state)
	_undo_redo.add_undo_method(undo_state)
	_undo_redo.commit_action()


func _apply_state(next_module: Dictionary, next_entry: Dictionary) -> void:
	module_data = next_module.duplicate(true)
	registry_entry = next_entry.duplicate(true)
	dirty = (
		is_new_document
		or _json_signature(_canonical_module(module_data)) != _original_module_signature
		or _json_signature(_canonical_registry_entry(registry_entry)) != _original_entry_signature
	)
	document_changed.emit()


func _reset_history_and_baseline() -> void:
	module_data = _canonical_module(module_data)
	registry_entry = _canonical_registry_entry(registry_entry)
	_original_module_signature = _json_signature(module_data)
	_original_entry_signature = _json_signature(registry_entry)
	_original_gameplay_signature = _gameplay_signature(module_data, registry_entry)
	_undo_redo.clear_history()
	dirty = false
	document_changed.emit()


func _normalize_module(source: Dictionary, expected_id: String) -> Dictionary:
	var normalized: Dictionary = source.duplicate(true)
	normalized["schema_version"] = MODULE_SCHEMA_VERSION
	normalized["id"] = expected_id
	normalized["columns"] = int(normalized.get("columns", MODULE_SIZE))
	normalized["rows"] = int(normalized.get("rows", MODULE_SIZE))
	if not normalized.get("terrain_rows", []) is Array:
		normalized["terrain_rows"] = _empty_terrain_rows()
	normalized.erase("edge_sockets")
	if not normalized.get("placements", []) is Array:
		normalized["placements"] = []
	if not normalized.get("visual_layers", {}) is Dictionary:
		normalized["visual_layers"] = _default_visual_layers()
	else:
		normalized["visual_layers"] = _normalize_visual_layers(
			normalized.get("visual_layers", {}) as Dictionary
		)
	return normalized


func _new_module_data(requested_module_id: String) -> Dictionary:
	var terrain_rows: Array = _empty_terrain_rows()
	return {
		"schema_version": MODULE_SCHEMA_VERSION,
		"id": requested_module_id,
		"columns": MODULE_SIZE,
		"rows": MODULE_SIZE,
		"terrain_rows": terrain_rows,
		"placements": [],
		"visual_layers": _default_visual_layers(),
	}


func _new_registry_entry(requested_module_id: String) -> Dictionary:
	return {
		"id": requested_module_id,
		"path": _module_path_for_id(requested_module_id),
		"role": "module_role_connector",
		"tags": [],
		"source": "ai",
		"review_status": MODULE_REVIEW_STATUSES.MODULE_REVIEW_CANDIDATE,
		"allowed_rotations": [0, 90, 180, 270],
	}


func _empty_terrain_rows() -> Array:
	var rows: Array = []
	for _y: int in range(MODULE_SIZE):
		var row: Array[String] = []
		for _x: int in range(MODULE_SIZE):
			row.append(MODULE_CELL_TOKENS.MODULE_CELL_FLOOR)
		rows.append(row)
	return rows


func _default_visual_layers() -> Dictionary:
	return {
		GROUND_LAYER: {
			"default_tile_id": DEFAULT_GROUND_TILE_ID,
			"overrides": [],
		},
		OBSTACLE_LAYER: {
			"default_tile_id": DEFAULT_OBSTACLE_TILE_ID,
			"overrides": [],
		},
		DECORATION_LAYER: {
			"cells": [],
		},
	}


func _normalize_visual_layers(source: Dictionary) -> Dictionary:
	var defaults: Dictionary = _default_visual_layers()
	var result: Dictionary = {}
	for layer_name: String in [GROUND_LAYER, OBSTACLE_LAYER, DECORATION_LAYER]:
		var layer_data: Dictionary = (
			(source.get(layer_name, {}) as Dictionary).duplicate(true)
			if source.get(layer_name, {}) is Dictionary
			else {}
		)
		var default_layer: Dictionary = defaults.get(layer_name, {}) as Dictionary
		if (
			layer_name != DECORATION_LAYER
			and String(layer_data.get("default_tile_id", "")).is_empty()
		):
			layer_data["default_tile_id"] = default_layer.get("default_tile_id", "")
		if layer_name == DECORATION_LAYER:
			layer_data.erase("default_tile_id")
		var list_key: String = "cells" if layer_name == DECORATION_LAYER else "overrides"
		if not layer_data.get(list_key, []) is Array:
			layer_data[list_key] = []
		result[layer_name] = layer_data
	return result


func _canonical_module(source: Dictionary) -> Dictionary:
	var normalized: Dictionary = _normalize_module(source, module_id)
	var result: Dictionary = {
		"schema_version": MODULE_SCHEMA_VERSION,
		"id": module_id,
		"columns": MODULE_SIZE,
		"rows": MODULE_SIZE,
		"terrain_rows": _normalized_json_value(normalized.get("terrain_rows", [])),
		"placements": _sorted_cell_entries(normalized.get("placements", []) as Array),
		"visual_layers": _canonical_visual_layers(
			normalized.get("visual_layers", {}) as Dictionary
		),
	}
	var known_keys: Array[String] = [
		"schema_version",
		"id",
		"columns",
		"rows",
		"terrain_rows",
		"placements",
		"visual_layers",
	]
	var extra_keys: Array[String] = []
	for key_value: Variant in normalized.keys():
		var key: String = String(key_value)
		if not known_keys.has(key):
			extra_keys.append(key)
	extra_keys.sort()
	for key: String in extra_keys:
		result[key] = _normalized_json_value(normalized[key])
	return result


func _canonical_visual_layers(source: Dictionary) -> Dictionary:
	var normalized: Dictionary = _normalize_visual_layers(source)
	var result: Dictionary = {}
	for layer_name: String in [GROUND_LAYER, OBSTACLE_LAYER, DECORATION_LAYER]:
		var layer_data: Dictionary = normalized.get(layer_name, {}) as Dictionary
		var list_key: String = "cells" if layer_name == DECORATION_LAYER else "overrides"
		if layer_name == DECORATION_LAYER:
			result[layer_name] = {
				"cells": _sorted_cell_entries(layer_data.get("cells", []) as Array),
			}
		else:
			result[layer_name] = {
				"default_tile_id": String(layer_data.get("default_tile_id", "")),
				"overrides": _sorted_cell_entries(
					layer_data.get("overrides", []) as Array
				),
			}
	return result


func _canonical_registry_entry(source: Dictionary) -> Dictionary:
	var key_order: Array[String] = [
		"id",
		"path",
		"role",
		"tags",
		"source",
		"review_status",
		"allowed_rotations",
		"approved_gameplay_hash",
		"approved_source_hash",
	]
	var result: Dictionary = {}
	for key: String in key_order:
		if source.has(key):
			result[key] = _normalized_json_value(source[key])
	var extra_keys: Array[String] = []
	for key_value: Variant in source.keys():
		var key: String = String(key_value)
		if not key_order.has(key):
			extra_keys.append(key)
	extra_keys.sort()
	for key: String in extra_keys:
		result[key] = _normalized_json_value(source[key])
	return result


func _registry_with_entry(entry: Dictionary) -> Dictionary:
	var next_registry: Dictionary = _registry.duplicate(true)
	var entries: Array = next_registry.get("templates", []) as Array
	var found: bool = false
	for index: int in range(entries.size()):
		if entries[index] is Dictionary and String((entries[index] as Dictionary).get("id", "")) == module_id:
			entries[index] = entry
			found = true
			break
	if not found:
		entries.append(entry)
	next_registry["templates"] = entries
	return next_registry


func _gameplay_signature(source_module: Dictionary, source_entry: Dictionary) -> String:
	var gameplay_projection: Dictionary = {
		"terrain_rows": source_module.get("terrain_rows", []),
		"edge_sockets": _derive_edge_sockets(source_module.get("terrain_rows", []) as Array),
		"placements": _sorted_cell_entries(source_module.get("placements", []) as Array),
		"role": source_entry.get("role", ""),
		"tags": source_entry.get("tags", []),
		"allowed_rotations": source_entry.get("allowed_rotations", []),
	}
	return _json_signature(gameplay_projection)


func _derive_edge_sockets(terrain_rows: Array) -> Dictionary:
	var north: Array[int] = []
	var south: Array[int] = []
	var east: Array[int] = []
	var west: Array[int] = []
	if terrain_rows.size() != MODULE_SIZE:
		return {
			"edge_north": north,
			"edge_south": south,
			"edge_east": east,
			"edge_west": west,
		}
	for index: int in range(MODULE_SIZE):
		var north_row: Array = terrain_rows[0] as Array
		var south_row: Array = terrain_rows[MODULE_SIZE - 1] as Array
		var row: Array = terrain_rows[index] as Array
		if north_row.size() == MODULE_SIZE and String(north_row[index]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			north.append(index)
		if south_row.size() == MODULE_SIZE and String(south_row[index]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			south.append(index)
		if row.size() == MODULE_SIZE and String(row[MODULE_SIZE - 1]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			east.append(index)
		if row.size() == MODULE_SIZE and String(row[0]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			west.append(index)
	return {
		"edge_north": north,
		"edge_south": south,
		"edge_east": east,
		"edge_west": west,
	}


func _sorted_cell_entries(source: Array) -> Array:
	var result: Array = []
	for value: Variant in source:
		if value is Dictionary:
			result.append(_sorted_dictionary(value as Dictionary))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_cell: Vector2i = _entry_cell(left)
			var right_cell: Vector2i = _entry_cell(right)
			if left_cell.y != right_cell.y:
				return left_cell.y < right_cell.y
			if left_cell.x != right_cell.x:
				return left_cell.x < right_cell.x
			return String(left.get("type", left.get("tile_id", ""))) < String(
				right.get("type", right.get("tile_id", ""))
			)
	)
	return result


func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key_value: Variant in source.keys():
		keys.append(String(key_value))
	keys.sort()
	var result: Dictionary = {}
	for key: String in keys:
		result[key] = _normalized_json_value(source[key])
	return result


func _normalized_json_value(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)):
		return int(roundf(value))
	if value is Array:
		var normalized_array: Array = []
		for item: Variant in value as Array:
			normalized_array.append(_normalized_json_value(item))
		return normalized_array
	if value is Dictionary:
		return _sorted_dictionary(value as Dictionary)
	return value


func _cell_entry_index(entries: Array, cell: Vector2i) -> int:
	for index: int in range(entries.size()):
		if entries[index] is Dictionary and _entry_cell(entries[index] as Dictionary) == cell:
			return index
	return -1


func _entry_cell(entry: Dictionary) -> Vector2i:
	var cell_value: Variant = entry.get("cell", {})
	if not cell_value is Dictionary:
		return Vector2i(-1, -1)
	var cell: Dictionary = cell_value as Dictionary
	return Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))


func _registry_entry_for_id(requested_module_id: String) -> Dictionary:
	for entry_value: Variant in _registry.get("templates", []) as Array:
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value as Dictionary
			if String(entry.get("id", "")) == requested_module_id:
				return entry.duplicate(true)
	return {}


func _module_id_error(requested_module_id: String) -> String:
	if requested_module_id.is_empty():
		return "Module id must not be empty."
	if requested_module_id != requested_module_id.to_lower():
		return "Module id must use lowercase snake_case."
	if not requested_module_id.begins_with("module_"):
		return "Module id must begin with module_."
	for character: String in requested_module_id:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789_":
			return "Module id may contain only lowercase letters, digits, and underscores."
	return ""


func _module_path_for_id(requested_module_id: String) -> String:
	return "%s/%s.json" % [module_directory, requested_module_id]


func _is_cell_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MODULE_SIZE and cell.y < MODULE_SIZE


func _disk_hash(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


func _json_signature(value: Variant) -> String:
	return JSON.stringify(_normalized_json_value(value), "", false, true)


func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _error_result("Missing JSON file: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error_result("Failed to open JSON file: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _error_result("JSON root must be a Dictionary: %s" % path)
	var result := _success_result()
	result["data"] = parsed as Dictionary
	return result


func _atomic_write_json(path: String, data: Dictionary) -> String:
	return _atomic_write_json_batch({path: data})


func _atomic_write_json_batch(writes: Dictionary) -> String:
	var paths: Array[String] = []
	for path_value: Variant in writes.keys():
		paths.append(String(path_value))
	paths.sort()
	if paths.is_empty():
		return ""

	var originally_existed: Dictionary = {}
	for path: String in paths:
		var temporary_path: String = "%s.tmp" % path
		var backup_path: String = "%s.bak" % path
		var absolute_temporary_path: String = ProjectSettings.globalize_path(temporary_path)
		var absolute_backup_path: String = ProjectSettings.globalize_path(backup_path)
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(absolute_temporary_path)
		if FileAccess.file_exists(backup_path):
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(absolute_backup_path)
			else:
				var recover_error: Error = DirAccess.rename_absolute(
					absolute_backup_path,
					ProjectSettings.globalize_path(path)
				)
				if recover_error != OK:
					_remove_batch_temporary_files(paths)
					return "Failed to recover interrupted JSON transaction for %s (error %d)." % [
						path,
						recover_error,
					]
		originally_existed[path] = FileAccess.file_exists(path)
		var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
		if file == null:
			_remove_batch_temporary_files(paths)
			return "Failed to stage JSON transaction file: %s" % temporary_path
		file.store_string(
			JSON.stringify(
				_normalized_json_value(writes.get(path, {})),
				"  ",
				false,
				true
			)
			+ "\n"
		)
		file.close()

	var backed_up_paths: Array[String] = []
	for path: String in paths:
		if not bool(originally_existed.get(path, false)):
			continue
		var backup_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path),
			ProjectSettings.globalize_path("%s.bak" % path)
		)
		if backup_error != OK:
			_restore_json_batch(paths, backed_up_paths, [])
			return "Failed to back up JSON transaction target %s (error %d)." % [
				path,
				backup_error,
			]
		backed_up_paths.append(path)

	var promoted_paths: Array[String] = []
	for path: String in paths:
		var replace_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path("%s.tmp" % path),
			ProjectSettings.globalize_path(path)
		)
		if replace_error != OK:
			var rollback_errors: PackedStringArray = _restore_json_batch(
				paths,
				backed_up_paths,
				promoted_paths
			)
			var suffix: String = (
				" Rollback errors: %s" % "; ".join(rollback_errors)
				if not rollback_errors.is_empty()
				else ""
			)
			return "Failed to promote JSON transaction target %s (error %d).%s" % [
				path,
				replace_error,
				suffix,
			]
		promoted_paths.append(path)

	for path: String in backed_up_paths:
		var backup_path: String = "%s.bak" % path
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	return ""


func _restore_json_batch(
	all_paths: Array[String],
	backed_up_paths: Array[String],
	promoted_paths: Array[String]
) -> PackedStringArray:
	var errors := PackedStringArray()
	for path: String in promoted_paths:
		if FileAccess.file_exists(path):
			var remove_error: Error = DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path)
			)
			if remove_error != OK:
				errors.append("remove %s error %d" % [path, remove_error])
	for path: String in backed_up_paths:
		var backup_path: String = "%s.bak" % path
		if not FileAccess.file_exists(backup_path):
			errors.append("missing rollback backup %s" % backup_path)
			continue
		var restore_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(backup_path),
			ProjectSettings.globalize_path(path)
		)
		if restore_error != OK:
			errors.append("restore %s error %d" % [path, restore_error])
	_remove_batch_temporary_files(all_paths)
	return errors


func _remove_batch_temporary_files(paths: Array[String]) -> void:
	for path: String in paths:
		var temporary_path: String = "%s.tmp" % path
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))


func _success_result() -> Dictionary:
	return {"ok": true, "errors": PackedStringArray()}


func _error_result(message: String) -> Dictionary:
	var result := _success_result()
	_add_error(result, message)
	return result


func _add_error(result: Dictionary, message: String) -> void:
	result["ok"] = false
	var errors: PackedStringArray = result.get("errors", PackedStringArray()) as PackedStringArray
	errors.append(message)
	result["errors"] = errors
