@tool
extends SceneTree
## Headless smoke for the editor-only JSON document model. Writes only to user://.

const MODULE_JSON_DOCUMENT := preload("res://scripts/editor/module_json_document.gd")

var _failures := PackedStringArray()
var _root_path: String
var _module_directory: String
var _registry_path: String


func _init() -> void:
	_root_path = "user://module_json_editor_smoke_%d" % OS.get_process_id()
	_module_directory = "%s/modules" % _root_path
	_registry_path = "%s/module_templates.json" % _root_path
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_module_directory)
	)
	_expect(mkdir_error == OK, "temporary user:// directory should be created")
	if mkdir_error == OK:
		_run_document_smoke()
	_cleanup()
	if _failures.is_empty():
		print("[module-json-editor-smoke] PASS")
		quit(0)
		return
	for failure: String in _failures:
		printerr("[module-json-editor-smoke] %s" % failure)
	quit(1)


func _run_document_smoke() -> void:
	var base_path: String = "%s/module_base.json" % _module_directory
	_write_json(base_path, _module_data("module_base"))
	_write_json(
		_registry_path,
		{
			"schema_version": 2,
			"templates": [_registry_entry("module_base", base_path)],
		}
	)

	var document := MODULE_JSON_DOCUMENT.new() as ModuleJsonDocument
	document.configure_paths(_registry_path, _module_directory)
	_expect(bool(document.initialize().get("ok", false)), "initialize should load injected registry")
	_expect(bool(document.open_module("module_base").get("ok", false)), "open_module should load base JSON")
	document.set_terrain_cell(Vector2i(5, 5), "module_cell_blocked")
	_expect(document.dirty and document.has_undo(), "terrain edit should be dirty and undoable")
	document.undo()
	_expect(not document.dirty and document.has_redo(), "undo should restore the clean baseline")
	document.redo()
	_expect(document.dirty, "redo should restore the edit")
	document.undo()
	document.set_visual_cell(
		"decoration",
		Vector2i(2, 3),
		"module_tile_decoration_default",
		90,
		true,
		false
	)
	var first_save: Dictionary = document.save_current()
	_expect(bool(first_save.get("ok", false)), "save_current should persist a legal candidate")
	var saved_registry: Dictionary = _read_json(_registry_path)
	var saved_entry: Dictionary = _registry_entry_from_data(saved_registry, "module_base")
	_expect(
		String(saved_entry.get("review_status", "")) == "module_review_approved",
		"pure visual edits should preserve approved review status"
	)
	var saved_data: Dictionary = _read_json(base_path)
	_expect(not saved_data.has("edge_sockets"), "saved schema v2 JSON must omit edge_sockets")
	var decoration: Dictionary = (
		(saved_data.get("visual_layers", {}) as Dictionary).get("decoration", {})
		as Dictionary
	)
	_expect(
		not decoration.has("default_tile_id"),
		"decoration layer must contain only sparse cells"
	)
	document.set_terrain_cell(Vector2i(5, 5), "module_cell_blocked")
	_expect(bool(document.save_current().get("ok", false)), "gameplay edit should save")
	saved_registry = _read_json(_registry_path)
	saved_entry = _registry_entry_from_data(saved_registry, "module_base")
	_expect(
		String(saved_entry.get("review_status", "")) == "module_review_candidate",
		"approved gameplay edits should downgrade review status to candidate"
	)
	var first_hash: String = FileAccess.get_sha256(base_path)
	_expect(bool(document.save_current().get("ok", false)), "second deterministic save should succeed")
	_expect(
		FileAccess.get_sha256(base_path) == first_hash,
		"repeated saves should produce byte-identical JSON"
	)

	document.set_terrain_cell(Vector2i(1, 1), "module_cell_blocked")
	saved_data["_external_marker"] = true
	_write_json(base_path, saved_data)
	_expect(
		not bool(document.save_current().get("ok", true)),
		"save should reject a module changed externally after open"
	)

	var new_document := MODULE_JSON_DOCUMENT.new() as ModuleJsonDocument
	new_document.configure_paths(_registry_path, _module_directory)
	_expect(bool(new_document.initialize().get("ok", false)), "new document should initialize")
	_expect(bool(new_document.create_new("module_new").get("ok", false)), "create_new should succeed")
	new_document.set_registry_property("role", "module_role_semantically_incomplete")
	_expect(
		bool(new_document.save_current().get("ok", false)),
		"structure-valid semantic candidate should be savable"
	)
	_expect(
		FileAccess.file_exists("%s/module_new.json" % _module_directory),
		"new module JSON should be created"
	)

	var copy_document := MODULE_JSON_DOCUMENT.new() as ModuleJsonDocument
	copy_document.configure_paths(_registry_path, _module_directory)
	_expect(bool(copy_document.initialize().get("ok", false)), "copy document should initialize")
	_expect(bool(copy_document.open_module("module_base").get("ok", false)), "copy source should open")
	_expect(bool(copy_document.create_copy("module_copy").get("ok", false)), "create_copy should succeed")
	_expect(bool(copy_document.save_current().get("ok", false)), "copied module should save")
	var copied_data: Dictionary = _read_json("%s/module_copy.json" % _module_directory)
	_expect(
		String(copied_data.get("id", "")) == "module_copy",
		"copied JSON should receive the new module id"
	)

	var registry_conflict_document := MODULE_JSON_DOCUMENT.new() as ModuleJsonDocument
	registry_conflict_document.configure_paths(_registry_path, _module_directory)
	_expect(
		bool(registry_conflict_document.initialize().get("ok", false)),
		"registry conflict document should initialize"
	)
	_expect(
		bool(registry_conflict_document.open_module("module_base").get("ok", false)),
		"registry conflict source should open"
	)
	registry_conflict_document.set_registry_property("tags", ["externally_checked"])
	var externally_changed_registry: Dictionary = _read_json(_registry_path)
	externally_changed_registry["external_marker"] = true
	_write_json(_registry_path, externally_changed_registry)
	_expect(
		not bool(registry_conflict_document.save_current().get("ok", true)),
		"save should reject an externally changed registry when metadata is dirty"
	)
	document.dispose()
	new_document.dispose()
	copy_document.dispose()
	registry_conflict_document.dispose()


func _module_data(requested_id: String) -> Dictionary:
	var terrain_rows: Array = []
	for _y: int in range(11):
		var row: Array[String] = []
		for _x: int in range(11):
			row.append("module_cell_floor")
		terrain_rows.append(row)
	return {
		"schema_version": 2,
		"id": requested_id,
		"columns": 11,
		"rows": 11,
		"terrain_rows": terrain_rows,
		"placements": [],
		"visual_layers": {
			"ground": {
				"default_tile_id": "module_tile_ground_default",
				"overrides": [],
			},
			"obstacles": {
				"default_tile_id": "module_tile_obstacle_default",
				"overrides": [],
			},
			"decoration": {"cells": []},
		},
	}


func _registry_entry(requested_id: String, path: String) -> Dictionary:
	return {
		"id": requested_id,
		"path": path,
		"role": "module_role_connector",
		"tags": [],
		"source": "ai",
		"review_status": "module_review_approved",
		"allowed_rotations": [0, 90, 180, 270],
		"approved_gameplay_hash": "fixture".sha256_text(),
	}


func _registry_entry_from_data(registry: Dictionary, requested_id: String) -> Dictionary:
	for entry_value: Variant in registry.get("templates", []) as Array:
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value as Dictionary
			if String(entry.get("id", "")) == requested_id:
				return entry
	return {}


func _write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	_expect(file != null, "test fixture should open %s" % path)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "  ", false, true) + "\n")
	file.close()


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "test fixture should read %s" % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_expect(parsed is Dictionary, "%s should contain a JSON object" % path)
	return parsed as Dictionary if parsed is Dictionary else {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _cleanup() -> void:
	var paths: Array[String] = [
		"%s/module_base.json" % _module_directory,
		"%s/module_new.json" % _module_directory,
		"%s/module_copy.json" % _module_directory,
		_registry_path,
	]
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var absolute_module_directory: String = ProjectSettings.globalize_path(_module_directory)
	var absolute_root_path: String = ProjectSettings.globalize_path(_root_path)
	if DirAccess.dir_exists_absolute(absolute_module_directory):
		DirAccess.remove_absolute(absolute_module_directory)
	if DirAccess.dir_exists_absolute(absolute_root_path):
		DirAccess.remove_absolute(absolute_root_path)
