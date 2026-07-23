# Doc: docs/代码/module_authoring_pipeline.md
@tool
class_name ModuleSceneBaker
extends RefCounted
## Shared implementation for the editor menu and the headless module bake commands.

const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const MODULE_EDGE_DIRECTIONS := preload("res://scripts/contracts/module_edge_directions.gd")
const MODULE_PLACEMENT_TYPES := preload("res://scripts/contracts/module_placement_types.gd")
const MODULE_REVIEW_STATUSES := preload("res://scripts/contracts/module_review_statuses.gd")
const MODULE_BAKED_DATA_SCRIPT := preload("res://scripts/gameplay/module_baked_data.gd")
const MODULE_BAKED_ROTATION_SCRIPT := preload("res://scripts/gameplay/module_baked_rotation.gd")

const MODULE_SIZE: int = 11
const CELL_SIZE: int = 160
const REGISTRY_PATH: String = "res://data/module_templates.json"
const AUTHORING_DIRECTORY: String = "res://scenes/modules"
const BAKED_DIRECTORY: String = "res://resources/modules"
const TILE_SET_PATH: String = "res://resources/modules/module_placeholder_tileset.tres"
const TILE_ATLAS_PATH: String = "res://assets/placeholders/module_tiles.svg"
const AUTHOR_ROOT_SCRIPT_PATH: String = "res://scripts/editor/module_authoring_root.gd"
const PLACEMENT_MARKER_SCRIPT_PATH: String = "res://scripts/editor/module_placement_marker.gd"
const GROUND_ATLAS_COORDS: Vector2i = Vector2i(0, 0)
const OBSTACLE_ATLAS_COORDS: Vector2i = Vector2i(1, 0)
const DECORATION_ATLAS_COORDS: Vector2i = Vector2i(2, 0)


static func bake_all(write_files: bool, initial_migration: bool = false) -> Dictionary:
	var registry_result: Dictionary = _load_json_dictionary(REGISTRY_PATH)
	if not bool(registry_result.get("ok", false)):
		return registry_result
	var registry: Dictionary = registry_result.get("data", {}) as Dictionary
	var entries: Array = registry.get("templates", []) as Array
	var result := _new_result()
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			_add_error(result, "%s contains a non-Dictionary template entry." % REGISTRY_PATH)
			continue
		var entry_result: Dictionary = _bake_entry(entry_value as Dictionary, write_files, initial_migration)
		_merge_result(result, entry_result)
	if write_files and bool(result.get("registry_changed", false)):
		var registry_error: String = _write_json(REGISTRY_PATH, registry)
		if not registry_error.is_empty():
			_add_error(result, registry_error)
	return result


static func bake_scene(scene_path: String, approve_after_bake: bool = false) -> Dictionary:
	var registry_result: Dictionary = _load_json_dictionary(REGISTRY_PATH)
	if not bool(registry_result.get("ok", false)):
		return registry_result
	var registry: Dictionary = registry_result.get("data", {}) as Dictionary
	var entry: Dictionary = _registry_entry_for_scene(registry, scene_path)
	if entry.is_empty():
		return _error_result("No module registry entry matches %s." % scene_path)
	var result: Dictionary = _bake_entry(entry, true, false)
	if not bool(result.get("ok", false)):
		return result
	if approve_after_bake:
		entry["review_status"] = MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED
		result["registry_changed"] = true
	if bool(result.get("registry_changed", false)):
		var registry_error: String = _write_json(REGISTRY_PATH, registry)
		if not registry_error.is_empty():
			_add_error(result, registry_error)
	return result


static func migrate_registered_json_to_scenes() -> Dictionary:
	var result := _new_result()
	var tile_set_result: Dictionary = _create_placeholder_tile_set()
	_merge_result(result, tile_set_result)
	if not bool(result.get("ok", false)):
		return result
	var tile_set: TileSet = load(TILE_SET_PATH) as TileSet
	if tile_set == null:
		return _error_result("Failed to reload generated TileSet: %s" % TILE_SET_PATH)
	var registry_result: Dictionary = _load_json_dictionary(REGISTRY_PATH)
	if not bool(registry_result.get("ok", false)):
		return registry_result
	var registry: Dictionary = registry_result.get("data", {}) as Dictionary
	for entry_value: Variant in registry.get("templates", []) as Array:
		if not entry_value is Dictionary:
			_add_error(result, "%s contains a non-Dictionary template entry." % REGISTRY_PATH)
			continue
		var entry: Dictionary = entry_value as Dictionary
		var json_result: Dictionary = _load_json_dictionary(String(entry.get("path", "")))
		if not bool(json_result.get("ok", false)):
			_merge_result(result, json_result)
			continue
		var scene_error: String = _create_authoring_scene(json_result.get("data", {}) as Dictionary, tile_set)
		if not scene_error.is_empty():
			_add_error(result, scene_error)
		else:
			result["migrated"] = int(result.get("migrated", 0)) + 1
	if not bool(result.get("ok", false)):
		return result
	var bake_result: Dictionary = bake_all(true, true)
	_merge_result(result, bake_result)
	return result


static func inspect_scene_root(root: Node, expected_id: String, scene_path: String = "") -> Dictionary:
	var result := _new_result()
	if root == null:
		return _error_result("Module scene could not be instantiated.")
	var actual_id: String = String(root.get("module_id"))
	if actual_id != expected_id:
		_add_error(result, "%s module_id must be %s, got %s." % [scene_path, expected_id, actual_id])
	var ground: TileMapLayer = root.get_node_or_null("Ground") as TileMapLayer
	var obstacles: TileMapLayer = root.get_node_or_null("Obstacles") as TileMapLayer
	var decoration: TileMapLayer = root.get_node_or_null("Decoration") as TileMapLayer
	var placements_root: Node = root.get_node_or_null("Placements")
	if ground == null:
		_add_error(result, "%s is missing Ground TileMapLayer." % scene_path)
	if obstacles == null:
		_add_error(result, "%s is missing Obstacles TileMapLayer." % scene_path)
	if decoration == null:
		_add_error(result, "%s is missing Decoration TileMapLayer." % scene_path)
	if placements_root == null:
		_add_error(result, "%s is missing Placements container." % scene_path)
	if not bool(result.get("ok", false)):
		return result

	var ground_cells: Dictionary = _validate_layer_cells(result, ground, "Ground", GROUND_ATLAS_COORDS, true)
	var obstacle_cells: Dictionary = _validate_layer_cells(result, obstacles, "Obstacles", OBSTACLE_ATLAS_COORDS, false)
	_validate_layer_cells(result, decoration, "Decoration", DECORATION_ATLAS_COORDS, false)
	for y: int in range(MODULE_SIZE):
		for x: int in range(MODULE_SIZE):
			var required_cell := Vector2i(x, y)
			if not ground_cells.has(required_cell):
				_add_error(result, "%s Ground is missing cell %s." % [scene_path, required_cell])
	if ground_cells.size() != MODULE_SIZE * MODULE_SIZE:
		_add_error(result, "%s Ground must contain exactly %d cells." % [scene_path, MODULE_SIZE * MODULE_SIZE])

	var terrain_rows: Array = []
	var floor_cells: Dictionary = {}
	for y: int in range(MODULE_SIZE):
		var row: Array[String] = []
		for x: int in range(MODULE_SIZE):
			var cell := Vector2i(x, y)
			if obstacle_cells.has(cell):
				row.append(MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED)
			else:
				row.append(MODULE_CELL_TOKENS.MODULE_CELL_FLOOR)
				floor_cells[cell] = true
		terrain_rows.append(row)
	_validate_floor_connectivity(result, floor_cells, scene_path)

	var placements: Array[Dictionary] = []
	var enemy_ids: Dictionary = _csv_ids("res://data/enemies.csv")
	var hazard_ids: Dictionary = _csv_ids("res://data/hazards.csv")
	for marker: Node in placements_root.get_children():
		if not marker is Marker2D:
			_add_error(result, "%s Placements/%s must be a Marker2D." % [scene_path, marker.name])
			continue
		var marker_position: Vector2 = (marker as Marker2D).position
		var cell := Vector2i(roundi(marker_position.x / float(CELL_SIZE)), roundi(marker_position.y / float(CELL_SIZE)))
		var snapped_position := Vector2(float(cell.x * CELL_SIZE), float(cell.y * CELL_SIZE))
		if not marker_position.is_equal_approx(snapped_position):
			_add_error(result, "%s Placements/%s is not snapped to the %d px cell grid." % [scene_path, marker.name, CELL_SIZE])
		if not _is_cell_inside(cell):
			_add_error(result, "%s Placements/%s is outside the 11 x 11 module." % [scene_path, marker.name])
			continue
		if obstacle_cells.has(cell):
			_add_error(result, "%s Placements/%s lands on a blocked cell." % [scene_path, marker.name])
		var placement_type: String = String(marker.get("placement_type"))
		if not MODULE_PLACEMENT_TYPES.VALUES.has(placement_type):
			_add_error(result, "%s Placements/%s has unknown placement type %s." % [scene_path, marker.name, placement_type])
			continue
		var payload_value: Variant = marker.get("payload")
		if not payload_value is Dictionary:
			_add_error(result, "%s Placements/%s payload must be a Dictionary." % [scene_path, marker.name])
			continue
		var payload: Dictionary = payload_value as Dictionary
		if placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_ENEMY_SPAWN and not enemy_ids.has(String(payload.get("enemy_id", ""))):
			_add_error(result, "%s Placements/%s has unknown enemy_id %s." % [scene_path, marker.name, String(payload.get("enemy_id", ""))])
		if placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_HAZARD and not hazard_ids.has(String(payload.get("hazard_id", ""))):
			_add_error(result, "%s Placements/%s has unknown hazard_id %s." % [scene_path, marker.name, String(payload.get("hazard_id", ""))])
		placements.append(_canonical_placement(placement_type, payload, cell))

	var module_json: Dictionary = {
		"schema_version": 1,
		"id": expected_id,
		"columns": MODULE_SIZE,
		"rows": MODULE_SIZE,
		"terrain_rows": terrain_rows,
		"edge_sockets": _derive_edge_sockets(floor_cells),
		"placements": placements,
	}
	result["module_json"] = module_json
	result["ground"] = ground
	result["obstacles"] = obstacles
	result["decoration"] = decoration
	result["obstacle_cells"] = obstacle_cells
	return result


static func _bake_entry(entry: Dictionary, write_files: bool, initial_migration: bool) -> Dictionary:
	var result := _new_result()
	var module_id: String = String(entry.get("id", ""))
	var scene_path: String = _scene_path_for_id(module_id)
	var generated_json_path: String = String(entry.get("path", ""))
	var baked_path: String = _baked_path_for_id(module_id)
	if module_id.is_empty() or generated_json_path.is_empty():
		return _error_result("Module registry entry is missing id or path.")
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		return _error_result("Missing authoring scene: %s" % scene_path)
	var packed_scene: PackedScene = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed_scene == null:
		return _error_result("Failed to load authoring scene: %s" % scene_path)
	var root: Node = packed_scene.instantiate()
	var inspect_result: Dictionary = inspect_scene_root(root, module_id, scene_path)
	if not bool(inspect_result.get("ok", false)):
		root.free()
		return inspect_result
	var allowed_rotations: Array = entry.get("allowed_rotations", []) as Array
	if allowed_rotations.is_empty():
		root.free()
		return _error_result("%s has no allowed rotations." % module_id)
	var source_hash: String = _source_content_hash(scene_path)
	var baked_data := MODULE_BAKED_DATA_SCRIPT.new() as ModuleBakedData
	baked_data.module_id = module_id
	baked_data.source_scene_path = scene_path
	baked_data.generated_json_path = generated_json_path
	baked_data.source_content_hash = source_hash
	var ground: TileMapLayer = inspect_result.get("ground") as TileMapLayer
	var obstacles: TileMapLayer = inspect_result.get("obstacles") as TileMapLayer
	var decoration: TileMapLayer = inspect_result.get("decoration") as TileMapLayer
	var obstacle_cells: Dictionary = inspect_result.get("obstacle_cells", {}) as Dictionary
	for rotation_value: Variant in allowed_rotations:
		var rotation: int = int(rotation_value)
		if not [0, 90, 180, 270].has(rotation):
			_add_error(result, "%s declares unsupported rotation %d." % [module_id, rotation])
			continue
		var baked_rotation := MODULE_BAKED_ROTATION_SCRIPT.new() as ModuleBakedRotation
		baked_rotation.rotation_degrees = rotation
		baked_rotation.ground_pattern = _pattern_for_layer(ground, rotation)
		baked_rotation.obstacle_pattern = _pattern_for_layer(obstacles, rotation)
		baked_rotation.decoration_pattern = _pattern_for_layer(decoration, rotation)
		baked_rotation.terrain_collision = _collision_for_cells(obstacle_cells, rotation)
		baked_data.rotations.append(baked_rotation)
	if not bool(result.get("ok", false)):
		root.free()
		return result

	var generated_json: Dictionary = inspect_result.get("module_json", {}) as Dictionary
	var existing_json_result: Dictionary = _load_json_dictionary(generated_json_path)
	var json_matches: bool = bool(existing_json_result.get("ok", false)) and _semantic_equal(existing_json_result.get("data"), generated_json)
	var baked_matches: bool = _baked_artifact_matches(baked_path, baked_data)
	var artifact_changed: bool = not json_matches or not baked_matches
	if not write_files:
		if not json_matches:
			_add_error(result, "%s is stale; run module-bake." % generated_json_path)
		if not baked_matches:
			_add_error(result, "%s is stale or missing; run module-bake." % baked_path)
		if not is_approval_current(String(entry.get("review_status", "")), not artifact_changed):
			_add_error(result, "%s changed after approval and must be baked and explicitly approved again." % module_id)
		root.free()
		result["checked"] = int(result.get("checked", 0)) + 1
		return result

	if initial_migration and not json_matches:
		root.free()
		return _error_result(
			"Initial migration semantic mismatch for %s at %s; existing JSON was not overwritten." % [
				module_id,
				_first_difference(existing_json_result.get("data"), generated_json),
			]
		)
	if artifact_changed:
		var json_error: String = _write_json(generated_json_path, generated_json) if not json_matches or initial_migration else ""
		if not json_error.is_empty():
			_add_error(result, json_error)
		var save_error: Error = ResourceSaver.save(baked_data, baked_path)
		if save_error != OK:
			_add_error(result, "Failed to save %s (error %d)." % [baked_path, save_error])
		if String(entry.get("review_status", "")) == MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED and not initial_migration:
			entry["review_status"] = MODULE_REVIEW_STATUSES.MODULE_REVIEW_CANDIDATE
			result["registry_changed"] = true
		result["changed"] = int(result.get("changed", 0)) + 1
	result["baked"] = int(result.get("baked", 0)) + 1
	root.free()
	return result


static func _create_placeholder_tile_set() -> Dictionary:
	var texture: Texture2D = load(TILE_ATLAS_PATH) as Texture2D
	if texture == null:
		return _error_result("Tile atlas is not imported: %s" % TILE_ATLAS_PATH)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)
	for atlas_coords: Vector2i in [GROUND_ATLAS_COORDS, OBSTACLE_ATLAS_COORDS, DECORATION_ATLAS_COORDS]:
		atlas.create_tile(atlas_coords)
	tile_set.add_source(atlas, 0)
	var save_error: Error = ResourceSaver.save(tile_set, TILE_SET_PATH)
	if save_error != OK:
		return _error_result("Failed to save %s (error %d)." % [TILE_SET_PATH, save_error])
	var result := _new_result()
	result["changed"] = 1
	return result


static func _create_authoring_scene(module_json: Dictionary, tile_set: TileSet) -> String:
	var module_id: String = String(module_json.get("id", ""))
	if module_id.is_empty():
		return "Cannot migrate module JSON without an id."
	var root := Node2D.new()
	root.name = "ModuleAuthoring"
	root.set_script(load(AUTHOR_ROOT_SCRIPT_PATH))
	root.set("module_id", module_id)
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tile_set
	ground.position = Vector2(-CELL_SIZE / 2.0, -CELL_SIZE / 2.0)
	root.add_child(ground)
	ground.owner = root
	var obstacles := TileMapLayer.new()
	obstacles.name = "Obstacles"
	obstacles.tile_set = tile_set
	obstacles.position = ground.position
	root.add_child(obstacles)
	obstacles.owner = root
	var decoration := TileMapLayer.new()
	decoration.name = "Decoration"
	decoration.tile_set = tile_set
	decoration.position = ground.position
	root.add_child(decoration)
	decoration.owner = root
	var placements_root := Node2D.new()
	placements_root.name = "Placements"
	root.add_child(placements_root)
	placements_root.owner = root

	var terrain_rows: Array = module_json.get("terrain_rows", []) as Array
	for y: int in range(MODULE_SIZE):
		var row: Array = terrain_rows[y] as Array
		for x: int in range(MODULE_SIZE):
			var cell := Vector2i(x, y)
			ground.set_cell(cell, 0, GROUND_ATLAS_COORDS)
			if String(row[x]) == MODULE_CELL_TOKENS.MODULE_CELL_BLOCKED:
				obstacles.set_cell(cell, 0, OBSTACLE_ATLAS_COORDS)
	var placement_index: int = 0
	for placement_value: Variant in module_json.get("placements", []) as Array:
		if not placement_value is Dictionary:
			continue
		var placement: Dictionary = (placement_value as Dictionary).duplicate(true)
		var cell_value: Dictionary = placement.get("cell", {}) as Dictionary
		var cell := Vector2i(int(cell_value.get("x", -1)), int(cell_value.get("y", -1)))
		var marker := Marker2D.new()
		marker.name = "Placement_%02d" % placement_index
		marker.set_script(load(PLACEMENT_MARKER_SCRIPT_PATH))
		marker.position = Vector2(float(cell.x * CELL_SIZE), float(cell.y * CELL_SIZE))
		marker.set("placement_type", String(placement.get("type", "")))
		placement.erase("type")
		placement.erase("cell")
		marker.set("payload", placement)
		placements_root.add_child(marker)
		marker.owner = root
		placement_index += 1
	var packed_scene := PackedScene.new()
	var pack_error: Error = packed_scene.pack(root)
	if pack_error != OK:
		root.free()
		return "Failed to pack %s (error %d)." % [module_id, pack_error]
	var scene_path: String = _scene_path_for_id(module_id)
	var save_error: Error = ResourceSaver.save(packed_scene, scene_path)
	root.free()
	if save_error != OK:
		return "Failed to save %s (error %d)." % [scene_path, save_error]
	return ""


static func _validate_layer_cells(result: Dictionary, layer: TileMapLayer, layer_name: String, expected_atlas: Vector2i, require_cells: bool) -> Dictionary:
	var cells: Dictionary = {}
	for cell: Vector2i in layer.get_used_cells():
		if not _is_cell_inside(cell):
			_add_error(result, "%s contains out-of-bounds cell %s." % [layer_name, cell])
			continue
		if layer.get_cell_source_id(cell) != 0 or layer.get_cell_atlas_coords(cell) != expected_atlas or layer.get_cell_alternative_tile(cell) != 0:
			_add_error(result, "%s cell %s uses an unknown tile id." % [layer_name, cell])
		cells[cell] = true
	if require_cells and cells.is_empty():
		_add_error(result, "%s must not be empty." % layer_name)
	return cells


static func _validate_floor_connectivity(result: Dictionary, floor_cells: Dictionary, scene_path: String) -> void:
	if floor_cells.is_empty():
		return
	var open: Array[Vector2i] = [floor_cells.keys()[0] as Vector2i]
	var visited: Dictionary = {}
	while not open.is_empty():
		var cell: Vector2i = open.pop_back()
		if visited.has(cell) or not floor_cells.has(cell):
			continue
		visited[cell] = true
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			open.append(cell + direction)
	if visited.size() != floor_cells.size():
		_add_error(result, "%s has disconnected walkable cells or edge sockets." % scene_path)


static func _derive_edge_sockets(floor_cells: Dictionary) -> Dictionary:
	var north: Array[int] = []
	var south: Array[int] = []
	var east: Array[int] = []
	var west: Array[int] = []
	for index: int in range(MODULE_SIZE):
		if floor_cells.has(Vector2i(index, 0)):
			north.append(index)
		if floor_cells.has(Vector2i(index, MODULE_SIZE - 1)):
			south.append(index)
		if floor_cells.has(Vector2i(MODULE_SIZE - 1, index)):
			east.append(index)
		if floor_cells.has(Vector2i(0, index)):
			west.append(index)
	return {
		MODULE_EDGE_DIRECTIONS.EDGE_NORTH: north,
		MODULE_EDGE_DIRECTIONS.EDGE_SOUTH: south,
		MODULE_EDGE_DIRECTIONS.EDGE_EAST: east,
		MODULE_EDGE_DIRECTIONS.EDGE_WEST: west,
	}


static func _canonical_placement(placement_type: String, payload: Dictionary, cell: Vector2i) -> Dictionary:
	var result: Dictionary = {
		"type": placement_type,
		"cell": {"x": cell.x, "y": cell.y},
	}
	if payload.has("footprint"):
		result["footprint"] = _normalized_json_value(payload.get("footprint"))
	var field_order: Array[String] = []
	match placement_type:
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_ENEMY_SPAWN:
			field_order = ["enemy_id", "count"]
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_HAZARD:
			field_order = ["hazard_id"]
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE:
			field_order = ["resource_rewards", "claim_radius"]
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_OBJECTIVE:
			field_order = ["target_hp", "target_hit_radius"]
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_EXTRACTION:
			field_order = ["radius", "hold_time"]
	for field: String in field_order:
		if payload.has(field):
			result[field] = _canonical_resource_rewards(payload[field]) if field == "resource_rewards" else _normalized_json_value(payload[field])
	var extra_fields: Array[String] = []
	for field_value: Variant in payload.keys():
		var field: String = String(field_value)
		if field != "footprint" and not field_order.has(field):
			extra_fields.append(field)
	extra_fields.sort()
	for field: String in extra_fields:
		result[field] = _normalized_json_value(payload[field])
	return result


static func _canonical_resource_rewards(value: Variant) -> Array:
	var rewards: Array = []
	if not value is Array:
		return rewards
	for reward_value: Variant in value as Array:
		if not reward_value is Dictionary:
			continue
		var reward: Dictionary = reward_value as Dictionary
		rewards.append({
			"id": String(reward.get("id", "")),
			"amount": _normalized_json_value(reward.get("amount", 0)),
		})
	return rewards


static func _normalized_json_value(value: Variant) -> Variant:
	if value is float and is_equal_approx(value, roundf(value)):
		return int(roundf(value))
	if value is Array:
		var normalized_array: Array = []
		for item: Variant in value as Array:
			normalized_array.append(_normalized_json_value(item))
		return normalized_array
	if value is Dictionary:
		var normalized_dictionary: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			normalized_dictionary[key] = _normalized_json_value((value as Dictionary)[key])
		return normalized_dictionary
	return value


static func _pattern_for_layer(layer: TileMapLayer, rotation: int) -> TileMapPattern:
	var pattern := TileMapPattern.new()
	for source_cell: Vector2i in layer.get_used_cells():
		var target_cell: Vector2i = _rotate_cell(source_cell, rotation)
		pattern.set_cell(
			target_cell,
			layer.get_cell_source_id(source_cell),
			layer.get_cell_atlas_coords(source_cell),
			layer.get_cell_alternative_tile(source_cell)
		)
	return pattern


static func _collision_for_cells(source_cells: Dictionary, rotation: int) -> ConcavePolygonShape2D:
	var rotated_cells: Dictionary = {}
	for source_cell_value: Variant in source_cells.keys():
		var source_cell: Vector2i = source_cell_value as Vector2i
		rotated_cells[_rotate_cell(source_cell, rotation)] = true
	var segments := PackedVector2Array()
	var half_cell: float = CELL_SIZE * 0.5
	for cell_value: Variant in rotated_cells.keys():
		var cell: Vector2i = cell_value as Vector2i
		var left: float = float(cell.x * CELL_SIZE) - half_cell
		var right: float = left + CELL_SIZE
		var top: float = float(cell.y * CELL_SIZE) - half_cell
		var bottom: float = top + CELL_SIZE
		if not rotated_cells.has(cell + Vector2i.UP):
			segments.append_array(PackedVector2Array([Vector2(left, top), Vector2(right, top)]))
		if not rotated_cells.has(cell + Vector2i.RIGHT):
			segments.append_array(PackedVector2Array([Vector2(right, top), Vector2(right, bottom)]))
		if not rotated_cells.has(cell + Vector2i.DOWN):
			segments.append_array(PackedVector2Array([Vector2(right, bottom), Vector2(left, bottom)]))
		if not rotated_cells.has(cell + Vector2i.LEFT):
			segments.append_array(PackedVector2Array([Vector2(left, bottom), Vector2(left, top)]))
	var shape := ConcavePolygonShape2D.new()
	shape.set_segments(segments)
	return shape


static func _baked_artifact_matches(path: String, expected: ModuleBakedData) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var actual: ModuleBakedData = ResourceLoader.load(path, "ModuleBakedData", ResourceLoader.CACHE_MODE_IGNORE) as ModuleBakedData
	if actual == null or actual.module_id != expected.module_id or actual.source_content_hash != expected.source_content_hash:
		return false
	if actual.rotations.size() != expected.rotations.size():
		return false
	for expected_rotation: ModuleBakedRotation in expected.rotations:
		var actual_rotation: ModuleBakedRotation = actual.rotation_data(expected_rotation.rotation_degrees)
		if actual_rotation == null:
			return false
		if _pattern_signature(actual_rotation.ground_pattern) != _pattern_signature(expected_rotation.ground_pattern):
			return false
		if _pattern_signature(actual_rotation.obstacle_pattern) != _pattern_signature(expected_rotation.obstacle_pattern):
			return false
		if _pattern_signature(actual_rotation.decoration_pattern) != _pattern_signature(expected_rotation.decoration_pattern):
			return false
		if actual_rotation.terrain_collision == null or expected_rotation.terrain_collision == null:
			return false
		if actual_rotation.terrain_collision.get_segments() != expected_rotation.terrain_collision.get_segments():
			return false
	return true


static func is_approval_current(review_status: String, artifacts_match: bool) -> bool:
	return review_status != MODULE_REVIEW_STATUSES.MODULE_REVIEW_APPROVED or artifacts_match


static func _pattern_signature(pattern: TileMapPattern) -> String:
	if pattern == null:
		return "<null>"
	var parts: PackedStringArray = []
	var cells: Array[Vector2i] = pattern.get_used_cells()
	cells.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.y < right.y or (left.y == right.y and left.x < right.x))
	for cell: Vector2i in cells:
		parts.append("%d,%d:%d:%d,%d:%d" % [cell.x, cell.y, pattern.get_cell_source_id(cell), pattern.get_cell_atlas_coords(cell).x, pattern.get_cell_atlas_coords(cell).y, pattern.get_cell_alternative_tile(cell)])
	return "|".join(parts)


static func _source_content_hash(scene_path: String) -> String:
	return "%s:%s" % [FileAccess.get_sha256(scene_path), FileAccess.get_sha256(TILE_SET_PATH)]


static func _registry_entry_for_scene(registry: Dictionary, scene_path: String) -> Dictionary:
	for entry_value: Variant in registry.get("templates", []) as Array:
		if entry_value is Dictionary:
			var entry: Dictionary = entry_value as Dictionary
			if _scene_path_for_id(String(entry.get("id", ""))) == scene_path:
				return entry
	return {}


static func _scene_path_for_id(module_id: String) -> String:
	return "%s/%s.tscn" % [AUTHORING_DIRECTORY, module_id]


static func _baked_path_for_id(module_id: String) -> String:
	return "%s/%s.tres" % [BAKED_DIRECTORY, module_id]


static func _rotate_cell(source_cell: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 360):
		90:
			return Vector2i(MODULE_SIZE - 1 - source_cell.y, source_cell.x)
		180:
			return Vector2i(MODULE_SIZE - 1 - source_cell.x, MODULE_SIZE - 1 - source_cell.y)
		270:
			return Vector2i(source_cell.y, MODULE_SIZE - 1 - source_cell.x)
		_:
			return source_cell


static func _is_cell_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MODULE_SIZE and cell.y < MODULE_SIZE


static func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return _error_result("Missing JSON file: %s" % path)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error_result("Failed to open JSON file: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _error_result("JSON root must be a Dictionary: %s" % path)
	var result: Dictionary = _new_result()
	result["data"] = parsed as Dictionary
	return result


static func _csv_ids(path: String) -> Dictionary:
	var ids: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ids
	var first_row: bool = true
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if first_row:
			first_row = false
			continue
		if not row.is_empty() and not row[0].is_empty():
			ids[row[0]] = true
	return ids


static func _write_json(path: String, data: Dictionary) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Failed to open generated JSON for writing: %s" % path
	file.store_string(JSON.stringify(data, "  ", false, true) + "\n")
	return ""


static func _first_difference(left: Variant, right: Variant, path: String = "root") -> String:
	if (left is int or left is float) and (right is int or right is float):
		return "" if is_equal_approx(float(left), float(right)) else "%s (%s != %s)" % [path, str(left), str(right)]
	if typeof(left) != typeof(right):
		return "%s (type %s != %s)" % [path, type_string(typeof(left)), type_string(typeof(right))]
	if left is Dictionary:
		var left_dict: Dictionary = left as Dictionary
		var right_dict: Dictionary = right as Dictionary
		if left_dict.size() != right_dict.size():
			return "%s (key count %d != %d)" % [path, left_dict.size(), right_dict.size()]
		for key: Variant in left_dict.keys():
			if not right_dict.has(key):
				return "%s.%s (missing key)" % [path, str(key)]
			var nested: String = _first_difference(left_dict[key], right_dict[key], "%s.%s" % [path, str(key)])
			if not nested.is_empty():
				return nested
		return ""
	if left is Array:
		var left_array: Array = left as Array
		var right_array: Array = right as Array
		if left_array.size() != right_array.size():
			return "%s (length %d != %d)" % [path, left_array.size(), right_array.size()]
		for index: int in range(left_array.size()):
			var nested: String = _first_difference(left_array[index], right_array[index], "%s[%d]" % [path, index])
			if not nested.is_empty():
				return nested
		return ""
	if left != right:
		return "%s (%s != %s)" % [path, str(left), str(right)]
	return ""


static func _semantic_equal(left: Variant, right: Variant) -> bool:
	return _first_difference(left, right).is_empty()


static func _new_result() -> Dictionary:
	return {"ok": true, "errors": PackedStringArray(), "changed": 0, "baked": 0, "checked": 0, "migrated": 0, "registry_changed": false}


static func _error_result(message: String) -> Dictionary:
	var result := _new_result()
	_add_error(result, message)
	return result


static func _add_error(result: Dictionary, message: String) -> void:
	result["ok"] = false
	var errors: PackedStringArray = result.get("errors", PackedStringArray()) as PackedStringArray
	errors.append(message)
	result["errors"] = errors


static func _merge_result(target: Dictionary, source: Dictionary) -> void:
	if not bool(source.get("ok", false)):
		target["ok"] = false
	var errors: PackedStringArray = target.get("errors", PackedStringArray()) as PackedStringArray
	errors.append_array(source.get("errors", PackedStringArray()) as PackedStringArray)
	target["errors"] = errors
	for counter: String in ["changed", "baked", "checked", "migrated"]:
		target[counter] = int(target.get(counter, 0)) + int(source.get(counter, 0))
	if bool(source.get("registry_changed", false)):
		target["registry_changed"] = true
