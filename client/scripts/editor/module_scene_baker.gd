# Doc: docs/代码/module_authoring_pipeline.md
@tool
class_name ModuleSceneBaker
extends RefCounted
## Deterministic one-way baker: module JSON -> generated runtime PackedScene.

const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_EDGE_DIRECTIONS := preload("res://scripts/contracts/module_edge_directions.gd")
const MODULE_REVIEW_STATUSES := preload("res://scripts/contracts/module_review_statuses.gd")
const GENERATED_MODULE_SCENE := preload("res://scripts/gameplay/generated_module_scene.gd")

const MODULE_SIZE: int = 11
const CELL_SIZE: int = 160
const REGISTRY_PATH: String = "res://data/module_templates.json"
const TILE_CATALOG_PATH: String = "res://data/module_tile_catalog.json"
const GENERATED_DIRECTORY: String = "res://scenes/generated/modules"
const BAKER_SCHEMA_VERSION: int = 1
const TRANSFORM_FLIP_H: int = TileSetAtlasSource.TRANSFORM_FLIP_H
const TRANSFORM_FLIP_V: int = TileSetAtlasSource.TRANSFORM_FLIP_V
const TRANSFORM_TRANSPOSE: int = TileSetAtlasSource.TRANSFORM_TRANSPOSE
const TRANSFORM_MASK: int = TRANSFORM_FLIP_H | TRANSFORM_FLIP_V | TRANSFORM_TRANSPOSE


static func validate_module(module_id: String) -> Dictionary:
	var registry_result: Dictionary = _load_registry()
	if not bool(registry_result.get("ok", false)):
		return registry_result
	if not _validate_project_data():
		return _error_result("Project data validation failed; see DataLoader errors above.")
	var registry: Dictionary = registry_result.get("data", {}) as Dictionary
	var entry: Dictionary = _registry_entry_for_id(registry, module_id)
	if entry.is_empty():
		return _error_result("Unknown module id: %s" % module_id)
	var context: Dictionary = _build_context(entry)
	if not bool(context.get("ok", false)):
		return context
	var result := _new_result()
	result["module_id"] = module_id
	result["gameplay_hash"] = context.get("gameplay_hash", "")
	result["visual_hash"] = context.get("visual_hash", "")
	result["bake_hash"] = context.get("bake_hash", "")
	result["approval_gameplay_hash"] = context.get("approval_gameplay_hash", "")
	return result


static func bake_all(write_files: bool = true) -> Dictionary:
	var registry_result: Dictionary = _load_registry()
	if not bool(registry_result.get("ok", false)):
		return registry_result
	if not _validate_project_data():
		return _error_result("Project data validation failed; see DataLoader errors above.")
	var registry: Dictionary = registry_result.get("data", {}) as Dictionary
	var result := _new_result()
	for entry_value: Variant in registry.get("templates", []) as Array:
		if not entry_value is Dictionary:
			_add_error(result, "%s contains a non-Dictionary template entry." % REGISTRY_PATH)
			continue
		_merge_result(result, _bake_entry(entry_value as Dictionary, write_files))
	if write_files and bool(result.get("registry_changed", false)):
		var write_error: String = _write_json(REGISTRY_PATH, registry)
		if not write_error.is_empty():
			_add_error(result, write_error)
	return result


static func check_all() -> Dictionary:
	return bake_all(false)


static func bake_module(module_id: String, write_files: bool = true) -> Dictionary:
	var registry_result: Dictionary = _load_registry()
	if not bool(registry_result.get("ok", false)):
		return registry_result
	if not _validate_project_data():
		return _error_result("Project data validation failed; see DataLoader errors above.")
	var registry: Dictionary = registry_result.get("data", {}) as Dictionary
	var entry: Dictionary = _registry_entry_for_id(registry, module_id)
	if entry.is_empty():
		return _error_result("Unknown module id: %s" % module_id)
	var result: Dictionary = _bake_entry(entry, write_files)
	if write_files and bool(result.get("registry_changed", false)):
		var write_error: String = _write_json(REGISTRY_PATH, registry)
		if not write_error.is_empty():
			_add_error(result, write_error)
	return result


static func approve_module(module_id: String) -> Dictionary:
	var registry_result: Dictionary = _load_registry()
	if not bool(registry_result.get("ok", false)):
		return registry_result
	if not _validate_project_data():
		return _error_result("Project data validation failed; see DataLoader errors above.")
	var registry: Dictionary = registry_result.get("data", {}) as Dictionary
	var entry: Dictionary = _registry_entry_for_id(registry, module_id)
	if entry.is_empty():
		return _error_result("Unknown module id: %s" % module_id)
	var check_result: Dictionary = _bake_entry(entry, false, true)
	if not bool(check_result.get("ok", false)):
		return check_result
	var context: Dictionary = _build_context(entry)
	if not bool(context.get("ok", false)):
		return context
	entry["review_status"] = MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED
	entry["approved_gameplay_hash"] = String(
		context.get("approval_gameplay_hash", "")
	)
	entry.erase("approved_source_hash")
	var write_error: String = _write_json(REGISTRY_PATH, registry)
	if not write_error.is_empty():
		return _error_result(write_error)
	var result := _new_result()
	result["module_id"] = module_id
	result["registry_changed"] = true
	result["approved_gameplay_hash"] = entry["approved_gameplay_hash"]
	return result


static func generated_scene_path(module_id: String, rotation_degrees: int) -> String:
	return "%s/%s/rotation_%d.tscn" % [
		GENERATED_DIRECTORY,
		module_id,
		posmod(rotation_degrees, 360),
	]


static func gameplay_projection(module_data: Dictionary) -> Dictionary:
	var terrain_rows: Array = _array_or_empty(module_data.get("terrain_rows", []))
	return {
		"schema_version": 1,
		"id": String(module_data.get("id", "")),
		"columns": MODULE_SIZE,
		"rows": MODULE_SIZE,
		"terrain_rows": _normalized_json_value(terrain_rows),
		"edge_sockets": _derive_edge_sockets(terrain_rows),
		"placements": _sorted_cell_entries(
			_array_or_empty(module_data.get("placements", []))
		),
	}


static func approval_gameplay_hash(
	module_data: Dictionary,
	registry_entry: Dictionary
) -> String:
	return _stable_hash(
		{
			"module": gameplay_projection(module_data),
			"role": String(registry_entry.get("role", "")),
			"tags": _sorted_strings(
				_array_or_empty(registry_entry.get("tags", []))
			),
			"allowed_rotations": _sorted_ints(
				_array_or_empty(registry_entry.get("allowed_rotations", []))
			),
		}
	)


static func _bake_entry(
	entry: Dictionary,
	write_files: bool,
	ignore_approval_mismatch: bool = false
) -> Dictionary:
	var context: Dictionary = _build_context(entry)
	if not bool(context.get("ok", false)):
		return context
	var result := _new_result()
	var module_id: String = String(entry.get("id", ""))
	var approved: bool = (
		String(entry.get("review_status", ""))
		== MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED
	)
	var current_approval_hash: String = String(
		context.get("approval_gameplay_hash", "")
	)
	var stored_approval_hash: String = String(
		entry.get("approved_gameplay_hash", "")
	)
	if (
		approved
		and stored_approval_hash != current_approval_hash
		and not ignore_approval_mismatch
	):
		if write_files:
			entry["review_status"] = MODULE_REVIEW_STATUSES.MODULE_REVIEW_CANDIDATE
			entry.erase("approved_gameplay_hash")
			entry.erase("approved_source_hash")
			result["registry_changed"] = true
		else:
			_add_error(
				result,
				"%s gameplay approval hash is stale; save or bake it to demote the module."
				% module_id
			)

	var rotations: Array[int] = context.get("rotations", []) as Array[int]
	for rotation: int in rotations:
		var expected_root: GeneratedModuleScene = _build_generated_scene(
			context,
			rotation
		)
		if expected_root == null:
			_add_error(
				result,
				"Failed to build %s rotation %d in memory." % [module_id, rotation]
			)
			continue
		var path: String = generated_scene_path(module_id, rotation)
		var matches: bool = _generated_artifact_matches(path, expected_root)
		if write_files and not matches:
			var save_error: String = _save_generated_scene(path, expected_root)
			if not save_error.is_empty():
				_add_error(result, save_error)
			else:
				result["changed"] = int(result.get("changed", 0)) + 1
				if not _generated_artifact_matches(path, expected_root):
					_add_error(
						result,
						"%s did not match its in-memory fingerprint after saving." % path
					)
		elif write_files:
			var canonicalize_error: String = _strip_unstable_unique_ids(path)
			if not canonicalize_error.is_empty():
				_add_error(result, canonicalize_error)
		elif not write_files and not matches:
			_add_error(
				result,
				"%s is missing, stale, or was modified outside the baker." % path
			)
		expected_root.free()
		result["checked"] = int(result.get("checked", 0)) + 1
	if write_files and bool(result.get("ok", false)):
		result["baked"] = 1
	result["module_id"] = module_id
	result["gameplay_hash"] = context.get("gameplay_hash", "")
	result["visual_hash"] = context.get("visual_hash", "")
	result["bake_hash"] = context.get("bake_hash", "")
	return result


static func _build_context(entry: Dictionary) -> Dictionary:
	var result := _new_result()
	var module_id: String = String(entry.get("id", ""))
	var module_path: String = String(entry.get("path", ""))
	if module_id.is_empty() or module_path.is_empty():
		return _error_result("Module registry entry is missing id or path.")
	var module_result: Dictionary = _load_json_dictionary(module_path)
	if not bool(module_result.get("ok", false)):
		return module_result
	var module_data: Dictionary = module_result.get("data", {}) as Dictionary
	_validate_module_for_bake(
		result,
		module_data,
		module_id,
		module_path,
		String(entry.get("role", ""))
	)

	var catalog_result: Dictionary = _load_catalog()
	_merge_result(result, catalog_result)
	if not bool(result.get("ok", false)):
		return result
	var tile_set_path: String = String(catalog_result.get("tile_set_path", ""))
	var tile_set: TileSet = load(tile_set_path) as TileSet
	if tile_set == null:
		return _error_result("Failed to load module TileSet: %s" % tile_set_path)
	var catalog: Dictionary = catalog_result.get("catalog", {}) as Dictionary
	_validate_referenced_tiles(result, module_data, catalog)
	if not bool(result.get("ok", false)):
		return result

	var rotations: Array[int] = []
	for rotation_value: Variant in _array_or_empty(
		entry.get("allowed_rotations", [])
	):
		var rotation: int = int(rotation_value)
		if not [0, 90, 180, 270].has(rotation) or rotations.has(rotation):
			_add_error(
				result,
				"%s allowed_rotations must contain unique orthogonal rotations."
				% module_id
			)
		else:
			rotations.append(rotation)
	rotations.sort()
	if rotations.is_empty():
		_add_error(result, "%s has no allowed rotations." % module_id)
	if not bool(result.get("ok", false)):
		return result

	var gameplay_hash: String = _stable_hash(gameplay_projection(module_data))
	var visual_hash: String = _stable_hash(
		module_data.get("visual_layers", {})
	)
	var referenced_catalog: Dictionary = _referenced_catalog_projection(
		module_data,
		catalog_result.get("raw_catalog", {}) as Dictionary
	)
	var bake_hash: String = _stable_hash(
		{
			"baker_schema_version": BAKER_SCHEMA_VERSION,
			"module": module_data,
			"allowed_rotations": rotations,
			"tile_catalog": referenced_catalog,
		}
	)
	result["module_id"] = module_id
	result["module_path"] = module_path
	result["module_data"] = module_data
	result["entry"] = entry
	result["catalog"] = catalog
	result["tile_set"] = tile_set
	result["tile_set_path"] = tile_set_path
	result["rotations"] = rotations
	result["gameplay_hash"] = gameplay_hash
	result["visual_hash"] = visual_hash
	result["bake_hash"] = bake_hash
	result["approval_gameplay_hash"] = approval_gameplay_hash(
		module_data,
		entry
	)
	return result


static func _validate_module_for_bake(
	result: Dictionary,
	module_data: Dictionary,
	expected_id: String,
	module_path: String,
	module_role: String
) -> void:
	if int(module_data.get("schema_version", 0)) != 2:
		_add_error(result, "%s schema_version must be 2." % module_path)
	if String(module_data.get("id", "")) != expected_id:
		_add_error(result, "%s id must be %s." % [module_path, expected_id])
	if (
		int(module_data.get("columns", 0)) != MODULE_SIZE
		or int(module_data.get("rows", 0)) != MODULE_SIZE
	):
		_add_error(result, "%s must be 11 x 11." % module_path)
	if module_data.has("edge_sockets"):
		_add_error(
			result,
			"%s must omit derived edge_sockets in schema v2." % module_path
		)
	var terrain_rows: Array = _array_or_empty(
		module_data.get("terrain_rows", [])
	)
	if terrain_rows.size() != MODULE_SIZE:
		_add_error(result, "%s terrain_rows must contain 11 rows." % module_path)
		return
	var floor_cells: Dictionary = {}
	for y: int in range(MODULE_SIZE):
		if not terrain_rows[y] is Array:
			_add_error(result, "%s terrain_rows[%d] must be an Array." % [module_path, y])
			continue
		var row: Array = terrain_rows[y] as Array
		if row.size() != MODULE_SIZE:
			_add_error(
				result,
				"%s terrain_rows[%d] must contain 11 cells." % [module_path, y]
			)
			continue
		for x: int in range(MODULE_SIZE):
			var token: String = String(row[x])
			if token == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
				floor_cells[Vector2i(x, y)] = true
			elif token != MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED:
				_add_cell_error(
					result,
					"%s terrain cell (%d, %d) has unknown token %s."
					% [module_path, x, y, token],
					Vector2i(x, y)
				)
	_validate_floor_connectivity(
		result,
		floor_cells,
		module_path,
		module_role == "module_role_sealed"
	)
	for placement_value: Variant in _array_or_empty(
		module_data.get("placements", [])
	):
		if not placement_value is Dictionary:
			continue
		var placement: Dictionary = placement_value as Dictionary
		var cell: Vector2i = _cell_from_value(placement.get("cell", {}))
		if not _is_cell_inside(cell):
			_add_cell_error(
				result,
				"%s placement is outside the module." % module_path,
				cell
			)
		elif not floor_cells.has(cell):
			_add_cell_error(
				result,
				"%s placement at %s lands on blocked terrain." % [module_path, cell],
				cell
			)


static func _validate_floor_connectivity(
	result: Dictionary,
	floor_cells: Dictionary,
	module_path: String,
	allow_empty: bool
) -> void:
	if floor_cells.is_empty():
		if not allow_empty:
			_add_error(result, "%s has no walkable terrain." % module_path)
		return
	var first_cell: Vector2i = floor_cells.keys()[0] as Vector2i
	var pending: Array[Vector2i] = [first_cell]
	var visited: Dictionary = {first_cell: true}
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for offset: Vector2i in [
			Vector2i.UP,
			Vector2i.RIGHT,
			Vector2i.DOWN,
			Vector2i.LEFT,
		]:
			var neighbor: Vector2i = cell + offset
			if floor_cells.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	if visited.size() != floor_cells.size():
		_add_error(
			result,
			"%s has disconnected walkable cells." % module_path
		)
		for cell_value: Variant in floor_cells.keys():
			var cell: Vector2i = cell_value as Vector2i
			if not visited.has(cell):
				_add_error_cell_only(result, cell)


static func _load_catalog() -> Dictionary:
	var load_result: Dictionary = _load_json_dictionary(TILE_CATALOG_PATH)
	if not bool(load_result.get("ok", false)):
		return load_result
	var raw_catalog: Dictionary = load_result.get("data", {}) as Dictionary
	var result := _new_result()
	if int(raw_catalog.get("schema_version", 0)) != 1:
		_add_error(result, "%s schema_version must be 1." % TILE_CATALOG_PATH)
	var tile_set_path: String = String(raw_catalog.get("tile_set_path", ""))
	if not ResourceLoader.exists(tile_set_path, "TileSet"):
		_add_error(result, "%s references a missing TileSet." % TILE_CATALOG_PATH)
		return result
	var tile_set: TileSet = load(tile_set_path) as TileSet
	if tile_set == null:
		_add_error(result, "Failed to load %s." % tile_set_path)
		return result
	var catalog: Dictionary = {}
	for tile_value: Variant in _array_or_empty(raw_catalog.get("tiles", [])):
		if not tile_value is Dictionary:
			_add_error(result, "%s tiles must contain Dictionaries." % TILE_CATALOG_PATH)
			continue
		var tile: Dictionary = tile_value as Dictionary
		var tile_id: String = String(tile.get("id", ""))
		var source_id: int = int(tile.get("source_id", -1))
		var atlas_coords: Vector2i = _cell_from_value(tile.get("atlas_coords", {}))
		var alternative_id: int = int(tile.get("alternative_id", -1))
		if tile_id.is_empty() or catalog.has(tile_id):
			_add_error(result, "%s contains an empty or duplicate tile id." % TILE_CATALOG_PATH)
			continue
		if source_id < 0 or not tile_set.has_source(source_id):
			_add_error(result, "%s references missing source %d." % [tile_id, source_id])
			continue
		var atlas_source: TileSetAtlasSource = tile_set.get_source(
			source_id
		) as TileSetAtlasSource
		if atlas_source == null or not atlas_source.has_tile(atlas_coords):
			_add_error(
				result,
				"%s references missing atlas cell %s." % [tile_id, atlas_coords]
			)
			continue
		if (
			alternative_id < 0
			or alternative_id >= TRANSFORM_FLIP_H
			or not atlas_source.has_alternative_tile(atlas_coords, alternative_id)
		):
			_add_error(
				result,
				"%s references missing or transform-reserved alternative %d."
				% [tile_id, alternative_id]
			)
			continue
		catalog[tile_id] = {
			"layer": String(tile.get("layer", "")),
			"source_id": source_id,
			"atlas_coords": atlas_coords,
			"alternative_id": alternative_id,
		}
	result["catalog"] = catalog
	result["tile_set_path"] = tile_set_path
	result["raw_catalog"] = raw_catalog
	return result


static func _validate_referenced_tiles(
	result: Dictionary,
	module_data: Dictionary,
	catalog: Dictionary
) -> void:
	var layers: Dictionary = _dictionary_or_empty(
		module_data.get("visual_layers", {})
	)
	for layer_name: String in ["ground", "obstacles"]:
		var layer: Dictionary = _dictionary_or_empty(layers.get(layer_name, {}))
		_validate_tile_reference(
			result,
			String(layer.get("default_tile_id", "")),
			layer_name,
			catalog,
			Vector2i(-1, -1)
		)
		for cell_value: Variant in _array_or_empty(layer.get("overrides", [])):
			if not cell_value is Dictionary:
				continue
			var cell_entry: Dictionary = cell_value as Dictionary
			var cell: Vector2i = _cell_from_value(cell_entry.get("cell", {}))
			_validate_tile_reference(
				result,
				String(cell_entry.get("tile_id", "")),
				layer_name,
				catalog,
				cell
			)
			_validate_visual_transform(result, cell_entry, cell)
			if (
				layer_name == "obstacles"
				and _terrain_token(module_data, cell)
				!= MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED
			):
				_add_cell_error(
					result,
					"Obstacle visual override at %s requires blocked terrain." % cell,
					cell
				)
	var decoration: Dictionary = _dictionary_or_empty(
		layers.get("decoration", {})
	)
	for cell_value: Variant in _array_or_empty(decoration.get("cells", [])):
		if not cell_value is Dictionary:
			continue
		var cell_entry: Dictionary = cell_value as Dictionary
		var cell: Vector2i = _cell_from_value(cell_entry.get("cell", {}))
		_validate_tile_reference(
			result,
			String(cell_entry.get("tile_id", "")),
			"decoration",
			catalog,
			cell
		)
		_validate_visual_transform(result, cell_entry, cell)


static func _validate_tile_reference(
	result: Dictionary,
	tile_id: String,
	expected_layer: String,
	catalog: Dictionary,
	cell: Vector2i
) -> void:
	if not catalog.has(tile_id):
		_add_cell_error(
			result,
			"Unknown module tile id %s." % tile_id,
			cell
		)
		return
	var tile: Dictionary = catalog[tile_id] as Dictionary
	if String(tile.get("layer", "")) != expected_layer:
		_add_cell_error(
			result,
			"Tile %s cannot be used in the %s layer." % [tile_id, expected_layer],
			cell
		)


static func _validate_visual_transform(
	result: Dictionary,
	entry: Dictionary,
	cell: Vector2i
) -> void:
	var rotation: int = int(entry.get("rotation", -1))
	if not [0, 90, 180, 270].has(rotation):
		_add_cell_error(
			result,
			"Visual cell %s has non-orthogonal rotation %d." % [cell, rotation],
			cell
		)
	if not entry.get("flip_h") is bool or not entry.get("flip_v") is bool:
		_add_cell_error(
			result,
			"Visual cell %s flip values must be bool." % cell,
			cell
		)


static func _build_generated_scene(
	context: Dictionary,
	rotation: int
) -> GeneratedModuleScene:
	var module_data: Dictionary = context.get("module_data", {}) as Dictionary
	var catalog: Dictionary = context.get("catalog", {}) as Dictionary
	var tile_set: TileSet = context.get("tile_set") as TileSet
	if module_data.is_empty() or catalog.is_empty() or tile_set == null:
		return null
	var root := GENERATED_MODULE_SCENE.new() as GeneratedModuleScene
	root.name = "GeneratedModule"
	root.baker_schema_version = BAKER_SCHEMA_VERSION
	root.module_id = String(context.get("module_id", ""))
	root.module_rotation_degrees = rotation
	root.gameplay_hash = String(context.get("gameplay_hash", ""))
	root.visual_hash = String(context.get("visual_hash", ""))
	root.bake_hash = String(context.get("bake_hash", ""))
	root.placement_snapshot = _rotated_placements(
		_array_or_empty(module_data.get("placements", [])),
		rotation
	)

	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.position = Vector2(-CELL_SIZE * 0.5, -CELL_SIZE * 0.5)
	ground.tile_set = tile_set
	_add_owned_child(root, ground, root)
	var obstacles := TileMapLayer.new()
	obstacles.name = "Obstacles"
	obstacles.position = Vector2(-CELL_SIZE * 0.5, -CELL_SIZE * 0.5)
	obstacles.tile_set = tile_set
	_add_owned_child(root, obstacles, root)
	var decoration := TileMapLayer.new()
	decoration.name = "Decoration"
	decoration.position = Vector2(-CELL_SIZE * 0.5, -CELL_SIZE * 0.5)
	decoration.tile_set = tile_set
	_add_owned_child(root, decoration, root)

	var blocked_cells: Dictionary = _terrain_cells(
		module_data,
		MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED,
		rotation
	)
	var floor_cells: Dictionary = _terrain_cells(
		module_data,
		MODULE_CELL_TOKENS.MODULE_CELL_FLOOR,
		rotation
	)
	_populate_visual_layers(
		ground,
		obstacles,
		decoration,
		module_data,
		catalog,
		rotation
	)
	_add_collision_subtree(root, "TerrainCollision", blocked_cells, root, false)

	var edge_seals := Node2D.new()
	edge_seals.name = "EdgeSeals"
	_add_owned_child(root, edge_seals, root)
	var obstacle_default_id: String = String(
		(
			_dictionary_or_empty(
				_dictionary_or_empty(
					module_data.get("visual_layers", {})
				).get("obstacles", {})
			)
		).get("default_tile_id", "")
	)
	for edge: String in MODULE_EDGE_DIRECTIONS.VALUES:
		_add_edge_seal(
			edge_seals,
			edge,
			_edge_floor_cells(floor_cells, edge),
			obstacle_default_id,
			catalog,
			tile_set,
			rotation,
			root
		)
	return root


static func _populate_visual_layers(
	ground: TileMapLayer,
	obstacles: TileMapLayer,
	decoration: TileMapLayer,
	module_data: Dictionary,
	catalog: Dictionary,
	module_rotation: int
) -> void:
	var layers: Dictionary = _dictionary_or_empty(
		module_data.get("visual_layers", {})
	)
	var ground_data: Dictionary = _dictionary_or_empty(layers.get("ground", {}))
	var ground_overrides: Dictionary = _entries_by_cell(
		_array_or_empty(ground_data.get("overrides", []))
	)
	var obstacle_data: Dictionary = _dictionary_or_empty(
		layers.get("obstacles", {})
	)
	var obstacle_overrides: Dictionary = _entries_by_cell(
		_array_or_empty(obstacle_data.get("overrides", []))
	)
	for y: int in range(MODULE_SIZE):
		for x: int in range(MODULE_SIZE):
			var source_cell := Vector2i(x, y)
			var ground_entry: Dictionary = _dictionary_or_empty(
				ground_overrides.get(source_cell, {})
			)
			_set_catalog_cell(
				ground,
				_rotate_cell(source_cell, module_rotation),
				String(
					ground_entry.get(
						"tile_id",
						ground_data.get("default_tile_id", "")
					)
				),
				ground_entry,
				module_rotation,
				catalog
			)
			if (
				_terrain_token(module_data, source_cell)
				== MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED
			):
				var obstacle_entry: Dictionary = _dictionary_or_empty(
					obstacle_overrides.get(source_cell, {})
				)
				_set_catalog_cell(
					obstacles,
					_rotate_cell(source_cell, module_rotation),
					String(
						obstacle_entry.get(
							"tile_id",
							obstacle_data.get("default_tile_id", "")
						)
					),
					obstacle_entry,
					module_rotation,
					catalog
				)
	var decoration_data: Dictionary = _dictionary_or_empty(
		layers.get("decoration", {})
	)
	for entry_value: Variant in _array_or_empty(decoration_data.get("cells", [])):
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value as Dictionary
		var source_cell: Vector2i = _cell_from_value(entry.get("cell", {}))
		_set_catalog_cell(
			decoration,
			_rotate_cell(source_cell, module_rotation),
			String(entry.get("tile_id", "")),
			entry,
			module_rotation,
			catalog
		)


static func _set_catalog_cell(
	layer: TileMapLayer,
	cell: Vector2i,
	tile_id: String,
	transform_entry: Dictionary,
	module_rotation: int,
	catalog: Dictionary
) -> void:
	if not catalog.has(tile_id):
		return
	var tile: Dictionary = catalog[tile_id] as Dictionary
	var local_flags: int = _visual_transform_flags(
		int(transform_entry.get("rotation", 0)),
		bool(transform_entry.get("flip_h", false)),
		bool(transform_entry.get("flip_v", false))
	)
	var flags: int = _compose_transform_flags(
		_rotation_transform_flags(module_rotation),
		local_flags
	)
	layer.set_cell(
		cell,
		int(tile.get("source_id", -1)),
		tile.get("atlas_coords", Vector2i(-1, -1)) as Vector2i,
		int(tile.get("alternative_id", 0)) | flags
	)


static func _add_collision_subtree(
	parent: Node,
	node_name: String,
	cells: Dictionary,
	scene_root: Node,
	disabled: bool
) -> CollisionShape2D:
	var body := StaticBody2D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	_add_owned_child(parent, body, scene_root)
	var shape_node := CollisionShape2D.new()
	shape_node.name = "Shape" if node_name == "SealCollision" else "MergedBlockedCells"
	shape_node.shape = _collision_for_cells(cells)
	shape_node.disabled = disabled or (
		shape_node.shape as ConcavePolygonShape2D
	).get_segments().is_empty()
	_add_owned_child(body, shape_node, scene_root)
	return shape_node


static func _add_edge_seal(
	parent: Node2D,
	edge: String,
	cells: Dictionary,
	tile_id: String,
	catalog: Dictionary,
	tile_set: TileSet,
	module_rotation: int,
	scene_root: Node
) -> void:
	var names: Dictionary = {
		MODULE_EDGE_DIRECTIONS.EDGE_NORTH: "North",
		MODULE_EDGE_DIRECTIONS.EDGE_EAST: "East",
		MODULE_EDGE_DIRECTIONS.EDGE_SOUTH: "South",
		MODULE_EDGE_DIRECTIONS.EDGE_WEST: "West",
	}
	var edge_root := Node2D.new()
	edge_root.name = String(names.get(edge, edge))
	edge_root.visible = false
	_add_owned_child(parent, edge_root, scene_root)
	var visual := TileMapLayer.new()
	visual.name = "SealVisual"
	visual.position = Vector2(-CELL_SIZE * 0.5, -CELL_SIZE * 0.5)
	visual.tile_set = tile_set
	_add_owned_child(edge_root, visual, scene_root)
	for cell_value: Variant in cells.keys():
		_set_catalog_cell(
			visual,
			cell_value as Vector2i,
			tile_id,
			{},
			module_rotation,
			catalog
		)
	_add_collision_subtree(edge_root, "SealCollision", cells, scene_root, true)


static func _save_generated_scene(
	path: String,
	root: GeneratedModuleScene
) -> String:
	var absolute_directory: String = ProjectSettings.globalize_path(
		path.get_base_dir()
	)
	var make_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_directory
	)
	if make_error != OK:
		return "Failed to create generated module directory %s (error %d)." % [
			path.get_base_dir(),
			make_error,
		]
	var packed := PackedScene.new()
	var pack_error: Error = packed.pack(root)
	if pack_error != OK:
		return "Failed to pack %s (error %d)." % [path, pack_error]
	var save_error: Error = ResourceSaver.save(packed, path)
	if save_error != OK:
		return "Failed to save %s (error %d)." % [path, save_error]
	var canonicalize_error: String = _strip_unstable_unique_ids(path)
	if not canonicalize_error.is_empty():
		return canonicalize_error
	return ""


static func _strip_unstable_unique_ids(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Failed to reopen generated scene %s for canonicalization." % path
	var contents: String = file.get_as_text()
	file.close()
	var unique_id_pattern: RegEx = RegEx.create_from_string(" unique_id=\\d+")
	if unique_id_pattern == null:
		return "Failed to compile generated-scene canonicalization pattern."
	var canonical_contents: String = unique_id_pattern.sub(contents, "", true)
	if canonical_contents == contents:
		return ""
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Failed to canonicalize generated scene %s." % path
	file.store_string(canonical_contents)
	file.close()
	return ""


static func _generated_artifact_matches(
	path: String,
	expected_root: GeneratedModuleScene
) -> bool:
	if not ResourceLoader.exists(path, "PackedScene"):
		return false
	var packed: PackedScene = ResourceLoader.load(
		path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if packed == null:
		return false
	var actual_root: Node = packed.instantiate()
	if actual_root == null:
		return false
	var matches: bool = _scene_fingerprint(actual_root) == _scene_fingerprint(
		expected_root
	)
	actual_root.free()
	return matches


static func _scene_fingerprint(root: Node) -> String:
	return _stable_hash(_node_projection(root))


static func _node_projection(node: Node) -> Dictionary:
	var result: Dictionary = {
		"name": String(node.name),
		"type": node.get_class(),
		"script": (
			String((node.get_script() as Script).resource_path)
			if node.get_script() is Script
			else ""
		),
	}
	if node is Node2D:
		var node_2d: Node2D = node as Node2D
		result["position"] = _vector2_projection(node_2d.position)
		result["rotation"] = node_2d.rotation
		result["scale"] = _vector2_projection(node_2d.scale)
	if node is CanvasItem:
		result["visible"] = (node as CanvasItem).visible
		result["z_index"] = (node as CanvasItem).z_index
	if node is GeneratedModuleScene:
		var generated: GeneratedModuleScene = node as GeneratedModuleScene
		result["generated"] = {
			"baker_schema_version": generated.baker_schema_version,
			"module_id": generated.module_id,
			"rotation_degrees": generated.module_rotation_degrees,
			"gameplay_hash": generated.gameplay_hash,
			"visual_hash": generated.visual_hash,
			"bake_hash": generated.bake_hash,
			"placement_snapshot": generated.placement_snapshot,
		}
	if node is TileMapLayer:
		var layer: TileMapLayer = node as TileMapLayer
		var cells: Array[Dictionary] = []
		var used_cells: Array[Vector2i] = layer.get_used_cells()
		used_cells.sort_custom(
			func(left: Vector2i, right: Vector2i) -> bool:
				return left.y < right.y or (
					left.y == right.y and left.x < right.x
				)
		)
		for cell: Vector2i in used_cells:
			cells.append(
				{
					"cell": _vector2i_projection(cell),
					"source_id": layer.get_cell_source_id(cell),
					"atlas_coords": _vector2i_projection(
						layer.get_cell_atlas_coords(cell)
					),
					"alternative_id": layer.get_cell_alternative_tile(cell),
				}
			)
		result["tile_map"] = {
			"tile_set": (
				layer.tile_set.resource_path
				if layer.tile_set != null
				else ""
			),
			"cells": cells,
		}
	if node is CollisionObject2D:
		var collision_object: CollisionObject2D = node as CollisionObject2D
		result["collision_object"] = {
			"layer": collision_object.collision_layer,
			"mask": collision_object.collision_mask,
		}
	if node is CollisionShape2D:
		var collision_shape: CollisionShape2D = node as CollisionShape2D
		var segments: Array = []
		if collision_shape.shape is ConcavePolygonShape2D:
			for point: Vector2 in (
				collision_shape.shape as ConcavePolygonShape2D
			).get_segments():
				segments.append(_vector2_projection(point))
		result["collision_shape"] = {
			"disabled": collision_shape.disabled,
			"shape_type": (
				collision_shape.shape.get_class()
				if collision_shape.shape != null
				else ""
			),
			"segments": segments,
		}
	var children: Array[Dictionary] = []
	for child: Node in node.get_children():
		children.append(_node_projection(child))
	result["children"] = children
	return result


static func _terrain_cells(
	module_data: Dictionary,
	token: String,
	rotation: int
) -> Dictionary:
	var result: Dictionary = {}
	var rows: Array = _array_or_empty(module_data.get("terrain_rows", []))
	for y: int in range(mini(rows.size(), MODULE_SIZE)):
		if not rows[y] is Array:
			continue
		var row: Array = rows[y] as Array
		for x: int in range(mini(row.size(), MODULE_SIZE)):
			if String(row[x]) == token:
				result[_rotate_cell(Vector2i(x, y), rotation)] = true
	return result


static func _edge_floor_cells(
	floor_cells: Dictionary,
	edge: String
) -> Dictionary:
	var result: Dictionary = {}
	for cell_value: Variant in floor_cells.keys():
		var cell: Vector2i = cell_value as Vector2i
		var matches: bool = (
			(edge == MODULE_EDGE_DIRECTIONS.EDGE_NORTH and cell.y == 0)
			or (
				edge == MODULE_EDGE_DIRECTIONS.EDGE_EAST
				and cell.x == MODULE_SIZE - 1
			)
			or (
				edge == MODULE_EDGE_DIRECTIONS.EDGE_SOUTH
				and cell.y == MODULE_SIZE - 1
			)
			or (edge == MODULE_EDGE_DIRECTIONS.EDGE_WEST and cell.x == 0)
		)
		if matches:
			result[cell] = true
	return result


static func _collision_for_cells(cells: Dictionary) -> ConcavePolygonShape2D:
	var segments := PackedVector2Array()
	var half_cell: float = CELL_SIZE * 0.5
	var sorted_cells: Array[Vector2i] = []
	for value: Variant in cells.keys():
		sorted_cells.append(value as Vector2i)
	sorted_cells.sort_custom(
		func(left: Vector2i, right: Vector2i) -> bool:
			return left.y < right.y or (
				left.y == right.y and left.x < right.x
			)
	)
	for cell: Vector2i in sorted_cells:
		var left: float = float(cell.x * CELL_SIZE) - half_cell
		var right: float = left + CELL_SIZE
		var top: float = float(cell.y * CELL_SIZE) - half_cell
		var bottom: float = top + CELL_SIZE
		if not cells.has(cell + Vector2i.UP):
			segments.append_array(
				PackedVector2Array([Vector2(left, top), Vector2(right, top)])
			)
		if not cells.has(cell + Vector2i.RIGHT):
			segments.append_array(
				PackedVector2Array([Vector2(right, top), Vector2(right, bottom)])
			)
		if not cells.has(cell + Vector2i.DOWN):
			segments.append_array(
				PackedVector2Array([Vector2(right, bottom), Vector2(left, bottom)])
			)
		if not cells.has(cell + Vector2i.LEFT):
			segments.append_array(
				PackedVector2Array([Vector2(left, bottom), Vector2(left, top)])
			)
	var shape := ConcavePolygonShape2D.new()
	shape.set_segments(segments)
	return shape


static func _rotated_placements(
	placements: Array,
	rotation: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for placement_value: Variant in placements:
		if not placement_value is Dictionary:
			continue
		var placement: Dictionary = _sorted_dictionary(
			(placement_value as Dictionary).duplicate(true)
		)
		var source_cell: Vector2i = _cell_from_value(placement.get("cell", {}))
		var width: int = 1
		var height: int = 1
		if placement.get("footprint") is Dictionary:
			var footprint: Dictionary = placement["footprint"] as Dictionary
			width = maxi(int(footprint.get("width", 1)), 1)
			height = maxi(int(footprint.get("height", 1)), 1)
		var rotated_cells: Array[Vector2i] = []
		for y: int in range(height):
			for x: int in range(width):
				rotated_cells.append(
					_rotate_cell(source_cell + Vector2i(x, y), rotation)
				)
		var minimum := Vector2i(MODULE_SIZE, MODULE_SIZE)
		var maximum := Vector2i(-1, -1)
		for cell: Vector2i in rotated_cells:
			minimum.x = mini(minimum.x, cell.x)
			minimum.y = mini(minimum.y, cell.y)
			maximum.x = maxi(maximum.x, cell.x)
			maximum.y = maxi(maximum.y, cell.y)
		placement["cell"] = _vector2i_projection(minimum)
		if placement.has("footprint"):
			placement["footprint"] = {
				"width": maximum.x - minimum.x + 1,
				"height": maximum.y - minimum.y + 1,
			}
		result.append(_sorted_dictionary(placement))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_cell: Vector2i = _cell_from_value(left.get("cell", {}))
			var right_cell: Vector2i = _cell_from_value(right.get("cell", {}))
			return (
				left_cell.y < right_cell.y
				or (
					left_cell.y == right_cell.y
					and (
						left_cell.x < right_cell.x
						or (
							left_cell.x == right_cell.x
							and String(left.get("type", ""))
							< String(right.get("type", ""))
						)
					)
				)
			)
	)
	return result


static func _derive_edge_sockets(terrain_rows: Array) -> Dictionary:
	var result: Dictionary = {
		MODULE_EDGE_DIRECTIONS.EDGE_NORTH: [],
		MODULE_EDGE_DIRECTIONS.EDGE_SOUTH: [],
		MODULE_EDGE_DIRECTIONS.EDGE_EAST: [],
		MODULE_EDGE_DIRECTIONS.EDGE_WEST: [],
	}
	if terrain_rows.size() != MODULE_SIZE:
		return result
	for row_value: Variant in terrain_rows:
		if not row_value is Array or (row_value as Array).size() != MODULE_SIZE:
			return result
	for index: int in range(MODULE_SIZE):
		if String((terrain_rows[0] as Array)[index]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result[MODULE_EDGE_DIRECTIONS.EDGE_NORTH] as Array).append(index)
		if String((terrain_rows[MODULE_SIZE - 1] as Array)[index]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result[MODULE_EDGE_DIRECTIONS.EDGE_SOUTH] as Array).append(index)
		if String((terrain_rows[index] as Array)[MODULE_SIZE - 1]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result[MODULE_EDGE_DIRECTIONS.EDGE_EAST] as Array).append(index)
		if String((terrain_rows[index] as Array)[0]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result[MODULE_EDGE_DIRECTIONS.EDGE_WEST] as Array).append(index)
	return result


static func _visual_transform_flags(
	rotation: int,
	flip_h: bool,
	flip_v: bool
) -> int:
	var flags: int = _rotation_transform_flags(rotation)
	if flip_h:
		flags ^= TRANSFORM_FLIP_H
	if flip_v:
		flags ^= TRANSFORM_FLIP_V
	return flags


static func _rotation_transform_flags(rotation: int) -> int:
	match posmod(rotation, 360):
		90:
			return TRANSFORM_FLIP_H | TRANSFORM_TRANSPOSE
		180:
			return TRANSFORM_FLIP_H | TRANSFORM_FLIP_V
		270:
			return TRANSFORM_FLIP_V | TRANSFORM_TRANSPOSE
		_:
			return 0


static func _compose_transform_flags(left_flags: int, right_flags: int) -> int:
	var expected_x: Vector2i = _apply_transform_flags(
		left_flags,
		_apply_transform_flags(right_flags, Vector2i.RIGHT)
	)
	var expected_y: Vector2i = _apply_transform_flags(
		left_flags,
		_apply_transform_flags(right_flags, Vector2i.DOWN)
	)
	for candidate_index: int in range(8):
		var candidate: int = (
			(TRANSFORM_FLIP_H if candidate_index & 1 else 0)
			| (TRANSFORM_FLIP_V if candidate_index & 2 else 0)
			| (TRANSFORM_TRANSPOSE if candidate_index & 4 else 0)
		)
		if (
			_apply_transform_flags(candidate, Vector2i.RIGHT) == expected_x
			and _apply_transform_flags(candidate, Vector2i.DOWN) == expected_y
		):
			return candidate
	return 0


static func _apply_transform_flags(flags: int, point: Vector2i) -> Vector2i:
	var result: Vector2i = point
	if flags & TRANSFORM_TRANSPOSE:
		result = Vector2i(result.y, result.x)
	if flags & TRANSFORM_FLIP_H:
		result.x = -result.x
	if flags & TRANSFORM_FLIP_V:
		result.y = -result.y
	return result


static func _rotate_cell(source_cell: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 360):
		90:
			return Vector2i(MODULE_SIZE - 1 - source_cell.y, source_cell.x)
		180:
			return Vector2i(
				MODULE_SIZE - 1 - source_cell.x,
				MODULE_SIZE - 1 - source_cell.y
			)
		270:
			return Vector2i(source_cell.y, MODULE_SIZE - 1 - source_cell.x)
		_:
			return source_cell


static func _entries_by_cell(entries: Array) -> Dictionary:
	var result: Dictionary = {}
	for entry_value: Variant in entries:
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value as Dictionary
			result[_cell_from_value(entry.get("cell", {}))] = entry
	return result


static func _terrain_token(
	module_data: Dictionary,
	cell: Vector2i
) -> String:
	if not _is_cell_inside(cell):
		return ""
	var rows: Array = _array_or_empty(module_data.get("terrain_rows", []))
	if cell.y >= rows.size() or not rows[cell.y] is Array:
		return ""
	var row: Array = rows[cell.y] as Array
	return String(row[cell.x]) if cell.x < row.size() else ""


static func _referenced_catalog_projection(
	module_data: Dictionary,
	raw_catalog: Dictionary
) -> Dictionary:
	var referenced_ids: Dictionary = {}
	var layers: Dictionary = _dictionary_or_empty(
		module_data.get("visual_layers", {})
	)
	for layer_name: String in ["ground", "obstacles"]:
		var layer: Dictionary = _dictionary_or_empty(layers.get(layer_name, {}))
		referenced_ids[String(layer.get("default_tile_id", ""))] = true
		for entry_value: Variant in _array_or_empty(layer.get("overrides", [])):
			if entry_value is Dictionary:
				referenced_ids[String((entry_value as Dictionary).get("tile_id", ""))] = true
	var decoration: Dictionary = _dictionary_or_empty(
		layers.get("decoration", {})
	)
	for entry_value: Variant in _array_or_empty(decoration.get("cells", [])):
		if entry_value is Dictionary:
			referenced_ids[String((entry_value as Dictionary).get("tile_id", ""))] = true
	var tiles: Array[Dictionary] = []
	for tile_value: Variant in _array_or_empty(raw_catalog.get("tiles", [])):
		if (
			tile_value is Dictionary
			and referenced_ids.has(String((tile_value as Dictionary).get("id", "")))
		):
			tiles.append(_sorted_dictionary(tile_value as Dictionary))
	tiles.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("id", "")) < String(right.get("id", ""))
	)
	return {
		"schema_version": int(raw_catalog.get("schema_version", 0)),
		"tile_set_path": String(raw_catalog.get("tile_set_path", "")),
		"tiles": tiles,
	}


static func _validate_project_data() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var loader: Node = tree.root.get_node_or_null("DataLoader")
	return loader != null and bool(loader.call("validate_project_data"))


static func _load_registry() -> Dictionary:
	return _load_json_dictionary(REGISTRY_PATH)


static func _registry_entry_for_id(
	registry: Dictionary,
	module_id: String
) -> Dictionary:
	for entry_value: Variant in _array_or_empty(registry.get("templates", [])):
		if (
			entry_value is Dictionary
			and String((entry_value as Dictionary).get("id", "")) == module_id
		):
			return entry_value as Dictionary
	return {}


static func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _error_result("Missing JSON file: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error_result("Failed to open JSON file: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _error_result("JSON root must be a Dictionary: %s" % path)
	var result := _new_result()
	result["data"] = parsed as Dictionary
	return result


static func _write_json(path: String, data: Dictionary) -> String:
	var temporary_path: String = "%s.tmp" % path
	var backup_path: String = "%s.bak" % path
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var absolute_temporary: String = ProjectSettings.globalize_path(temporary_path)
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(absolute_temporary)
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return "Failed to stage JSON file: %s" % temporary_path
	file.store_string(
		JSON.stringify(_normalized_json_value(data), "  ", false, true) + "\n"
	)
	file.close()
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	if FileAccess.file_exists(path):
		var backup_error: Error = DirAccess.rename_absolute(
			absolute_path,
			absolute_backup
		)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temporary)
			return "Failed to back up %s (error %d)." % [path, backup_error]
	var replace_error: Error = DirAccess.rename_absolute(
		absolute_temporary,
		absolute_path
	)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		return "Failed to replace %s (error %d)." % [path, replace_error]
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	return ""


static func _stable_hash(value: Variant) -> String:
	return JSON.stringify(_normalized_json_value(value), "", false, true).sha256_text()


static func _normalized_json_value(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)):
		return int(roundf(value))
	if value is Vector2i:
		return _vector2i_projection(value as Vector2i)
	if value is Vector2:
		return _vector2_projection(value as Vector2)
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_normalized_json_value(item))
		return result
	if value is Dictionary:
		return _sorted_dictionary(value as Dictionary)
	return value


static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key_value: Variant in source.keys():
		keys.append(String(key_value))
	keys.sort()
	var result: Dictionary = {}
	for key: String in keys:
		result[key] = _normalized_json_value(source[key])
	return result


static func _sorted_cell_entries(source: Array) -> Array:
	var result: Array = []
	for value: Variant in source:
		if value is Dictionary:
			result.append(_sorted_dictionary(value as Dictionary))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_cell: Vector2i = _cell_from_value(left.get("cell", {}))
			var right_cell: Vector2i = _cell_from_value(right.get("cell", {}))
			return (
				left_cell.y < right_cell.y
				or (
					left_cell.y == right_cell.y
					and (
						left_cell.x < right_cell.x
						or (
							left_cell.x == right_cell.x
							and String(left.get("type", left.get("tile_id", "")))
							< String(right.get("type", right.get("tile_id", "")))
						)
					)
				)
			)
	)
	return result


static func _sorted_strings(source: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in source:
		result.append(String(value))
	result.sort()
	return result


static func _sorted_ints(source: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in source:
		result.append(int(value))
	result.sort()
	return result


static func _cell_from_value(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if not value is Dictionary:
		return Vector2i(-1, -1)
	var cell: Dictionary = value as Dictionary
	return Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))


static func _vector2_projection(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _vector2i_projection(value: Vector2i) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _array_or_empty(value: Variant) -> Array:
	return value as Array if value is Array else []


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


static func _is_cell_inside(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < MODULE_SIZE
		and cell.y < MODULE_SIZE
	)


static func _add_owned_child(
	parent: Node,
	child: Node,
	scene_root: Node
) -> void:
	parent.add_child(child)
	child.owner = scene_root


static func _new_result() -> Dictionary:
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"error_cells": [],
		"baked": 0,
		"checked": 0,
		"changed": 0,
		"registry_changed": false,
	}


static func _error_result(message: String) -> Dictionary:
	var result := _new_result()
	_add_error(result, message)
	return result


static func _add_error(result: Dictionary, message: String) -> void:
	result["ok"] = false
	var errors: PackedStringArray = result.get(
		"errors",
		PackedStringArray()
	) as PackedStringArray
	errors.append(message)
	result["errors"] = errors


static func _add_cell_error(
	result: Dictionary,
	message: String,
	cell: Vector2i
) -> void:
	_add_error(result, message)
	_add_error_cell_only(result, cell)


static func _add_error_cell_only(
	result: Dictionary,
	cell: Vector2i
) -> void:
	if not _is_cell_inside(cell):
		return
	var cells: Array = result.get("error_cells", []) as Array
	var projection: Dictionary = _vector2i_projection(cell)
	if not cells.has(projection):
		cells.append(projection)
	result["error_cells"] = cells


static func _merge_result(target: Dictionary, source: Dictionary) -> void:
	if not bool(source.get("ok", false)):
		target["ok"] = false
	var target_errors: PackedStringArray = target.get(
		"errors",
		PackedStringArray()
	) as PackedStringArray
	for message: String in source.get("errors", PackedStringArray()) as PackedStringArray:
		target_errors.append(message)
	target["errors"] = target_errors
	var target_cells: Array = target.get("error_cells", []) as Array
	for cell_value: Variant in source.get("error_cells", []) as Array:
		if not target_cells.has(cell_value):
			target_cells.append(cell_value)
	target["error_cells"] = target_cells
	for count_key: String in ["baked", "checked", "changed"]:
		target[count_key] = int(target.get(count_key, 0)) + int(
			source.get(count_key, 0)
		)
	target["registry_changed"] = (
		bool(target.get("registry_changed", false))
		or bool(source.get("registry_changed", false))
	)
