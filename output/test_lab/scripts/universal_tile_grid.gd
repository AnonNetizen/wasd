class_name UniversalTileGrid
extends Node2D

## Data-driven 2D grid used by the AI universal Tile workflow experiment.

const LAYER_BASE: String = "base"
const LAYER_COLLISION: String = "collision"
const LAYER_DETAIL: String = "detail"
const LAYER_METADATA: String = "metadata"
const LAYER_OBJECT: String = "object"
const LAYER_SHADOW: String = "shadow"
const SUPPORTED_SCHEMA_VERSION: int = 1

var _assets_by_id: Dictionary = {}
var _asset_textures: Dictionary = {}
var _base_asset_id: String = ""
var _base_layer: TileMapLayer
var _cell_metadata: Dictionary = {}
var _collision_layer: Node2D
var _configured: bool = false
var _detail_layer: Node2D
var _grid_size: Vector2i = Vector2i.ZERO
var _hover_highlight: Polygon2D
var _last_seed: int = 0
var _layer_visibility: Dictionary = {
	LAYER_BASE: true,
	LAYER_SHADOW: true,
	LAYER_OBJECT: true,
	LAYER_DETAIL: true,
	LAYER_COLLISION: true,
	LAYER_METADATA: true,
}
var _layout_signature: String = ""
var _metadata_overlay: Node2D
var _object_layer: Node2D
var _placement_rules: Array[Dictionary] = []
var _placements: Array[Dictionary] = []
var _shadow_layer: Node2D
var _tile_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_ensure_layers()


func configure(style_pack: Dictionary, scene_config: Dictionary) -> Error:
	_ensure_layers()
	_configured = false
	_assets_by_id.clear()
	_asset_textures.clear()
	_placement_rules.clear()

	if int(style_pack.get("schema_version", 0)) != SUPPORTED_SCHEMA_VERSION:
		return ERR_INVALID_DATA
	if int(scene_config.get("schema_version", 0)) != SUPPORTED_SCHEMA_VERSION:
		return ERR_INVALID_DATA
	if String(style_pack.get("projection", "")) != "orthographic_top_down":
		return ERR_INVALID_DATA

	_grid_size = _array_to_vector2i(scene_config.get("grid_size", []))
	_tile_size = _array_to_vector2i(style_pack.get("tile_size_px", []))
	var scene_tile_size := _array_to_vector2i(scene_config.get("tile_size_px", []))
	if _grid_size.x <= 0 or _grid_size.y <= 0:
		return ERR_INVALID_DATA
	if _tile_size.x <= 0 or _tile_size.y <= 0:
		return ERR_INVALID_DATA
	if scene_tile_size != _tile_size:
		return ERR_INVALID_DATA

	var assets_value: Variant = style_pack.get("assets", [])
	if not assets_value is Array:
		return ERR_INVALID_DATA
	for asset_value: Variant in assets_value:
		if not asset_value is Dictionary:
			return ERR_INVALID_DATA
		var asset: Dictionary = (asset_value as Dictionary).duplicate(true)
		var asset_id := String(asset.get("id", ""))
		if asset_id.is_empty() or _assets_by_id.has(asset_id):
			return ERR_INVALID_DATA
		if _array_to_vector2i(asset.get("size_px", [])) != _tile_size:
			return ERR_INVALID_DATA
		if _array_to_vector2i(asset.get("footprint_cells", [])) != Vector2i.ONE:
			return ERR_INVALID_DATA
		if String(asset.get("footprint_shape", "")) != "square":
			return ERR_INVALID_DATA
		if not ["ground_range", "obstacle"].has(String(asset.get("asset_type", ""))):
			return ERR_INVALID_DATA
		var texture_path := String(asset.get("texture_path", ""))
		var texture := _load_runtime_texture(texture_path)
		if texture == null:
			return ERR_FILE_NOT_FOUND
		_assets_by_id[asset_id] = asset
		_asset_textures[asset_id] = texture

	_base_asset_id = String(scene_config.get("base_fill_asset_id", ""))
	if not _assets_by_id.has(_base_asset_id):
		return ERR_INVALID_DATA
	var base_asset: Dictionary = _assets_by_id[_base_asset_id]
	if String(base_asset.get("role", "")) != LAYER_BASE or String(base_asset.get("asset_type", "")) != "ground_range":
		return ERR_INVALID_DATA

	var generation_rules_value: Variant = scene_config.get("generation_rules", {})
	if not generation_rules_value is Dictionary:
		return ERR_INVALID_DATA
	var generation_rules: Dictionary = generation_rules_value
	if String(generation_rules.get("placement_zone", "")) != "perimeter":
		return ERR_INVALID_DATA
	if bool(generation_rules.get("allow_overlap", true)):
		return ERR_INVALID_DATA
	var placements_value: Variant = generation_rules.get("placements", [])
	if not placements_value is Array:
		return ERR_INVALID_DATA
	var requested_object_count: int = 0
	for rule_value: Variant in placements_value:
		if not rule_value is Dictionary:
			return ERR_INVALID_DATA
		var rule: Dictionary = (rule_value as Dictionary).duplicate(true)
		var asset_id := String(rule.get("asset_id", ""))
		var count := int(rule.get("count", 0))
		if not _assets_by_id.has(asset_id) or count <= 0:
			return ERR_INVALID_DATA
		var object_asset: Dictionary = _assets_by_id[asset_id]
		if String(object_asset.get("role", "")) != LAYER_OBJECT or String(object_asset.get("asset_type", "")) != "obstacle":
			return ERR_INVALID_DATA
		if not _has_valid_collision(object_asset):
			return ERR_INVALID_DATA
		_placement_rules.append(rule)
		requested_object_count += count
	if requested_object_count > _perimeter_cells().size():
		return ERR_INVALID_DATA

	var tile_set_error := _configure_base_tile_set()
	if tile_set_error != OK:
		return tile_set_error
	_configured = true
	return OK


func regenerate(seed: int) -> void:
	if not _configured:
		push_error("UniversalTileGrid must be configured before regenerate().")
		return
	_last_seed = seed
	_clear_dynamic_layers()
	_fill_base_layer()
	_build_base_metadata()

	var available_cells := _perimeter_cells()
	_deterministic_shuffle(available_cells, seed)
	var cell_cursor: int = 0
	var object_index: int = 0
	for rule: Dictionary in _placement_rules:
		var asset_id := String(rule.get("asset_id", ""))
		var count := int(rule.get("count", 0))
		for _count_index in range(count):
			var cell: Vector2i = available_cells[cell_cursor]
			cell_cursor += 1
			_add_object(asset_id, cell, object_index)
			object_index += 1

	_build_metadata_grid()
	_layout_signature = _compose_layout_signature()
	_apply_layer_visibility()


func get_layout_signature() -> String:
	return _layout_signature


func get_generation_summary() -> Dictionary:
	var counts: Dictionary = {}
	var perimeter_only: bool = true
	var occupied_cells: Dictionary = {}
	for placement: Dictionary in _placements:
		var asset_id := String(placement.get("asset_id", ""))
		counts[asset_id] = int(counts.get(asset_id, 0)) + 1
		var cell: Vector2i = placement.get("cell", Vector2i(-1, -1))
		perimeter_only = perimeter_only and _is_perimeter_cell(cell)
		occupied_cells[cell] = true
	return {
		"seed": _last_seed,
		"grid_size": [_grid_size.x, _grid_size.y],
		"tile_size_px": [_tile_size.x, _tile_size.y],
		"base_asset_id": _base_asset_id,
		"base_cell_count": _grid_size.x * _grid_size.y,
		"object_count": _placements.size(),
		"object_counts": counts,
		"collision_count": _placements.size(),
		"perimeter_only": perimeter_only,
		"overlap_free": occupied_cells.size() == _placements.size(),
		"detail_count": 0,
		"layer_visibility": _layer_visibility.duplicate(true),
		"layout_signature": _layout_signature,
	}


func get_cell_metadata(cell: Vector2i) -> Dictionary:
	var metadata_value: Variant = _cell_metadata.get(cell, {})
	if not metadata_value is Dictionary:
		return {}
	return (metadata_value as Dictionary).duplicate(true)


func set_layer_visible(layer_id: String, visible: bool) -> void:
	if not _layer_visibility.has(layer_id):
		push_warning("Unknown universal Tile layer: %s" % layer_id)
		return
	_layer_visibility[layer_id] = visible
	_apply_layer_visibility()


func world_to_cell(world_position: Vector2) -> Vector2i:
	if _tile_size.x <= 0 or _tile_size.y <= 0:
		return Vector2i(-1, -1)
	var local_position := to_local(world_position)
	var cell := Vector2i(
		floori(local_position.x / float(_tile_size.x)),
		floori(local_position.y / float(_tile_size.y))
	)
	if not _is_in_bounds(cell):
		return Vector2i(-1, -1)
	return cell


func set_metadata_hovered_cell(cell: Vector2i) -> void:
	if _hover_highlight == null:
		return
	_hover_highlight.visible = _is_in_bounds(cell)
	if _hover_highlight.visible:
		_hover_highlight.position = Vector2(cell * _tile_size)


func _ensure_layers() -> void:
	_base_layer = get_node_or_null("BaseLayer") as TileMapLayer
	if _base_layer == null:
		_base_layer = TileMapLayer.new()
		_base_layer.name = "BaseLayer"
		add_child(_base_layer)
	_base_layer.z_index = 0

	_shadow_layer = _ensure_node2d("ShadowLayer", 1)
	_object_layer = _ensure_node2d("ObjectLayer", 2)
	_object_layer.y_sort_enabled = true
	_detail_layer = _ensure_node2d("DetailLayer", 3)
	_collision_layer = _ensure_node2d("CollisionLayer", 4)
	_metadata_overlay = _ensure_node2d("MetadataOverlay", 10)


func _ensure_node2d(node_name: String, target_z_index: int) -> Node2D:
	var layer := get_node_or_null(node_name) as Node2D
	if layer == null:
		layer = Node2D.new()
		layer.name = node_name
		add_child(layer)
	layer.z_index = target_z_index
	return layer


func _configure_base_tile_set() -> Error:
	var texture_value: Variant = _asset_textures.get(_base_asset_id)
	if not texture_value is Texture2D:
		return ERR_INVALID_DATA
	var texture: Texture2D = texture_value
	if Vector2i(texture.get_size()) != _tile_size:
		return ERR_INVALID_DATA

	var tile_set := TileSet.new()
	tile_set.tile_size = _tile_size
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = texture
	atlas_source.texture_region_size = _tile_size
	atlas_source.create_tile(Vector2i.ZERO)
	var source_id := tile_set.add_source(atlas_source)
	if source_id < 0:
		return ERR_CANT_CREATE
	_base_layer.tile_set = tile_set
	_base_layer.set_meta("atlas_source_id", source_id)
	return OK


func _fill_base_layer() -> void:
	_base_layer.clear()
	var source_id := int(_base_layer.get_meta("atlas_source_id", -1))
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			_base_layer.set_cell(Vector2i(x, y), source_id, Vector2i.ZERO)


func _build_base_metadata() -> void:
	_cell_metadata.clear()
	var base_asset: Dictionary = _assets_by_id[_base_asset_id]
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			var cell := Vector2i(x, y)
			_cell_metadata[cell] = {
				"cell": [x, y],
				"layers": [LAYER_BASE],
				"base": _metadata_for_asset(base_asset),
				"object": {},
				"tags": _string_array(base_asset.get("tags", [])),
				"footprint_cells": [1, 1],
				"collision": {"shape": "none"},
				"interaction": {"interactable": false, "lootable": false},
			}


func _add_object(asset_id: String, cell: Vector2i, object_index: int) -> void:
	var asset: Dictionary = _assets_by_id[asset_id]
	var texture: Texture2D = _asset_textures[asset_id]
	var cell_center := Vector2(
		(float(cell.x) + 0.5) * float(_tile_size.x),
		(float(cell.y) + 0.5) * float(_tile_size.y)
	)

	var shadow := _create_shadow(asset, cell_center, object_index)
	_shadow_layer.add_child(shadow)

	var sprite := Sprite2D.new()
	sprite.name = "%s_%02d" % [asset_id.to_pascal_case(), object_index]
	sprite.texture = texture
	sprite.position = cell_center
	var anchor_point := _array_to_vector2(asset.get("anchor_point_px", [_tile_size.x * 0.5, _tile_size.y * 0.5]))
	sprite.offset = Vector2(float(_tile_size.x), float(_tile_size.y)) * 0.5 - anchor_point
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.set_meta("asset_id", asset_id)
	sprite.set_meta("cell", cell)
	sprite.set_meta("sort_layer", int(asset.get("sort_layer", 0)))
	_object_layer.add_child(sprite)

	var collision_body := _create_collision_body(asset, cell, cell_center, object_index)
	_collision_layer.add_child(collision_body)

	var placement: Dictionary = {
		"asset_id": asset_id,
		"cell": cell,
		"object_index": object_index,
	}
	_placements.append(placement)

	var cell_metadata: Dictionary = _cell_metadata[cell]
	cell_metadata["layers"] = [LAYER_BASE, LAYER_SHADOW, LAYER_OBJECT, LAYER_COLLISION]
	cell_metadata["object"] = _metadata_for_asset(asset)
	cell_metadata["tags"] = _merged_tags(cell_metadata.get("tags", []), asset.get("tags", []))
	cell_metadata["footprint_cells"] = [1, 1]
	cell_metadata["collision"] = (asset.get("collision", {}) as Dictionary).duplicate(true)
	cell_metadata["interaction"] = _interaction_for_asset(asset)
	_cell_metadata[cell] = cell_metadata


func _create_shadow(asset: Dictionary, cell_center: Vector2, object_index: int) -> Polygon2D:
	var shadow_data: Dictionary = asset.get("shadow", {})
	var ellipse_size := _array_to_vector2(shadow_data.get("size_px", [_tile_size.x * 0.6, _tile_size.y * 0.3]))
	var offset := _array_to_vector2(shadow_data.get("offset_px", [0, 0]))
	var opacity := clampf(float(shadow_data.get("opacity", 0.25)), 0.0, 1.0)
	var points := PackedVector2Array()
	for point_index in range(24):
		var angle := TAU * float(point_index) / 24.0
		points.append(Vector2(cos(angle) * ellipse_size.x * 0.5, sin(angle) * ellipse_size.y * 0.5))
	var shadow := Polygon2D.new()
	shadow.name = "Shadow_%02d" % object_index
	shadow.polygon = points
	shadow.color = Color(0.035, 0.045, 0.038, opacity)
	shadow.position = cell_center + offset
	return shadow


func _create_collision_body(
	asset: Dictionary,
	cell: Vector2i,
	cell_center: Vector2,
	object_index: int
) -> StaticBody2D:
	var collision: Dictionary = asset.get("collision", {})
	var body := StaticBody2D.new()
	body.name = "Collision_%02d" % object_index
	body.position = cell_center
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("asset_id", String(asset.get("id", "")))
	body.set_meta("cell", cell)

	var collision_shape := CollisionShape2D.new()
	collision_shape.name = "Shape"
	collision_shape.position = _array_to_vector2(collision.get("offset_px", [0, 0]))
	match String(collision.get("shape", "")):
		"circle":
			var circle_shape := CircleShape2D.new()
			circle_shape.radius = float(collision.get("radius_px", 0.0))
			collision_shape.shape = circle_shape
		"rectangle":
			var rectangle_shape := RectangleShape2D.new()
			rectangle_shape.size = _array_to_vector2(collision.get("size_px", []))
			collision_shape.shape = rectangle_shape
		_:
			push_error("Unsupported collision shape in universal Tile asset.")
	body.add_child(collision_shape)
	return body


func _build_metadata_grid() -> void:
	_clear_children(_metadata_overlay)
	for x in range(_grid_size.x + 1):
		var x_position := float(x * _tile_size.x)
		_add_overlay_line(
			PackedVector2Array([Vector2(x_position, 0.0), Vector2(x_position, float(_grid_size.y * _tile_size.y))]),
			Color(0.78, 0.88, 0.78, 0.28),
			1.0
		)
	for y in range(_grid_size.y + 1):
		var y_position := float(y * _tile_size.y)
		_add_overlay_line(
			PackedVector2Array([Vector2(0.0, y_position), Vector2(float(_grid_size.x * _tile_size.x), y_position)]),
			Color(0.78, 0.88, 0.78, 0.28),
			1.0
		)

	for placement: Dictionary in _placements:
		var asset: Dictionary = _assets_by_id[String(placement.get("asset_id", ""))]
		var cell: Vector2i = placement.get("cell", Vector2i.ZERO)
		_add_collision_outline(asset, cell)

	_hover_highlight = Polygon2D.new()
	_hover_highlight.name = "HoverHighlight"
	_hover_highlight.polygon = PackedVector2Array([
		Vector2(3.0, 3.0),
		Vector2(float(_tile_size.x) - 3.0, 3.0),
		Vector2(float(_tile_size.x) - 3.0, float(_tile_size.y) - 3.0),
		Vector2(3.0, float(_tile_size.y) - 3.0),
	])
	_hover_highlight.color = Color(0.80, 0.94, 0.62, 0.14)
	_hover_highlight.visible = false
	_metadata_overlay.add_child(_hover_highlight)


func _add_collision_outline(asset: Dictionary, cell: Vector2i) -> void:
	var collision: Dictionary = asset.get("collision", {})
	var center := Vector2(
		(float(cell.x) + 0.5) * float(_tile_size.x),
		(float(cell.y) + 0.5) * float(_tile_size.y)
	) + _array_to_vector2(collision.get("offset_px", [0, 0]))
	var points := PackedVector2Array()
	match String(collision.get("shape", "")):
		"circle":
			var radius := float(collision.get("radius_px", 0.0))
			for point_index in range(25):
				var angle := TAU * float(point_index) / 24.0
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		"rectangle":
			var size := _array_to_vector2(collision.get("size_px", []))
			var half_size := size * 0.5
			points = PackedVector2Array([
				center - half_size,
				center + Vector2(half_size.x, -half_size.y),
				center + half_size,
				center + Vector2(-half_size.x, half_size.y),
				center - half_size,
			])
		_:
			return
	_add_overlay_line(points, Color(0.96, 0.55, 0.20, 0.88), 2.0)


func _add_overlay_line(points: PackedVector2Array, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = true
	_metadata_overlay.add_child(line)


func _clear_dynamic_layers() -> void:
	_placements.clear()
	_clear_children(_shadow_layer)
	_clear_children(_object_layer)
	_clear_children(_detail_layer)
	_clear_children(_collision_layer)
	_clear_children(_metadata_overlay)
	_hover_highlight = null


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.free()


func _perimeter_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			var cell := Vector2i(x, y)
			if _is_perimeter_cell(cell):
				cells.append(cell)
	return cells


func _deterministic_shuffle(cells: Array[Vector2i], seed: int) -> void:
	var state: int = absi(seed)
	if state == 0:
		state = 1
	for source_index in range(cells.size() - 1, 0, -1):
		state = int((state * 1_103_515_245 + 12_345) % 2_147_483_647)
		var target_index := state % (source_index + 1)
		var temporary := cells[source_index]
		cells[source_index] = cells[target_index]
		cells[target_index] = temporary


func _compose_layout_signature() -> String:
	var placement_parts := PackedStringArray()
	for placement: Dictionary in _placements:
		var cell: Vector2i = placement.get("cell", Vector2i.ZERO)
		placement_parts.append("%s@%d,%d" % [String(placement.get("asset_id", "")), cell.x, cell.y])
	return "grid=%dx%d|base=%s|objects=%s" % [
		_grid_size.x,
		_grid_size.y,
		_base_asset_id,
		";".join(placement_parts),
	]


func _metadata_for_asset(asset: Dictionary) -> Dictionary:
	return {
		"id": String(asset.get("id", "")),
		"role": String(asset.get("role", "")),
		"footprint_cells": [1, 1],
		"anchor_point_px": _int_array(asset.get("anchor_point_px", [])),
		"orientation_read": String(asset.get("orientation_read", "")),
		"sort_layer": int(asset.get("sort_layer", 0)),
		"tags": _string_array(asset.get("tags", [])),
	}


func _interaction_for_asset(asset: Dictionary) -> Dictionary:
	var interaction_value: Variant = asset.get("interaction", {})
	if not interaction_value is Dictionary:
		return {"interactable": false, "lootable": false}
	var interaction: Dictionary = interaction_value
	return {
		"interactable": bool(interaction.get("interactable", false)),
		"lootable": bool(interaction.get("lootable", false)),
	}


func _has_valid_collision(asset: Dictionary) -> bool:
	var collision_value: Variant = asset.get("collision", {})
	if not collision_value is Dictionary:
		return false
	var collision: Dictionary = collision_value
	match String(collision.get("shape", "")):
		"circle":
			return float(collision.get("radius_px", 0.0)) > 0.0
		"rectangle":
			var size := _array_to_vector2(collision.get("size_px", []))
			return size.x > 0.0 and size.y > 0.0
		_:
			return false


func _load_runtime_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty():
		return null
	var image := Image.new()
	var resolved_path := texture_path
	if texture_path.begins_with("res://") or texture_path.begins_with("user://"):
		resolved_path = ProjectSettings.globalize_path(texture_path)
	var load_error := image.load(resolved_path)
	if load_error != OK:
		push_error("Failed to load universal Tile image: %s (%s)" % [texture_path, load_error])
		return null
	return ImageTexture.create_from_image(image)


func _apply_layer_visibility() -> void:
	if _base_layer != null:
		_base_layer.visible = bool(_layer_visibility[LAYER_BASE])
	if _shadow_layer != null:
		_shadow_layer.visible = bool(_layer_visibility[LAYER_SHADOW])
	if _object_layer != null:
		_object_layer.visible = bool(_layer_visibility[LAYER_OBJECT])
	if _detail_layer != null:
		_detail_layer.visible = bool(_layer_visibility[LAYER_DETAIL])
	if _collision_layer != null:
		_collision_layer.visible = bool(_layer_visibility[LAYER_COLLISION])
	if _metadata_overlay != null:
		_metadata_overlay.visible = bool(_layer_visibility[LAYER_METADATA])


func _is_perimeter_cell(cell: Vector2i) -> bool:
	return _is_in_bounds(cell) and (
		cell.x == 0
		or cell.y == 0
		or cell.x == _grid_size.x - 1
		or cell.y == _grid_size.y - 1
	)


func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_size.x and cell.y < _grid_size.y


func _array_to_vector2i(value: Variant) -> Vector2i:
	if not value is Array or (value as Array).size() != 2:
		return Vector2i.ZERO
	var values: Array = value
	return Vector2i(int(values[0]), int(values[1]))


func _array_to_vector2(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.ZERO
	var values: Array = value
	return Vector2(float(values[0]), float(values[1]))


func _int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if not value is Array:
		return result
	for item: Variant in value:
		result.append(int(item))
	return result


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value:
		result.append(String(item))
	return result


func _merged_tags(first: Variant, second: Variant) -> Array[String]:
	var merged := _string_array(first)
	for tag: String in _string_array(second):
		if not merged.has(tag):
			merged.append(tag)
	return merged
