class_name UniversalTileGrid
extends Node2D

## Mutually exclusive, data-driven cell Tile grid for the AI art workflow experiment.

const LAYER_CELL_TILES: String = "cell_tiles"
const LAYER_COLLISION: String = "collision"
const LAYER_DETAIL: String = "detail"
const LAYER_METADATA: String = "metadata"
const CELL_VISUAL_BLEED_PX: float = 2.0
const FLOOR_CORNER_RADIUS_PX: float = 8.0
const FLOOR_BREATH_SPEED: float = 1.14
const FLOOR_BREATH_WIDTH_AMPLITUDE: float = 0.08
const FLOOR_EDGE_WIDTH_PX: float = 5.0
const FLOOR_SOURCE_CROP_PX: float = 3.5
const OBSTACLE_BREATH_SPEED: float = 1.32
const OBSTACLE_BREATH_WIDTH_AMPLITUDE: float = 0.12
const OBSTACLE_BORDER_WIDTH_PX: float = 7.0
const OBSTACLE_CORNER_RADIUS_PX: float = 11.0
const SUPPORTED_SCENE_SCHEMA_VERSION: int = 2
const SUPPORTED_STYLE_PACK_SCHEMA_VERSION: int = 2
const VISUAL_CAPTURE_TIME: float = 1.75
const VISUAL_STACK_SEED: int = 41_923
const TILE_VISUAL_SHADER_CODE: String = """
shader_type canvas_item;
render_mode unshaded;

uniform vec2 tile_size_px = vec2(128.0, 128.0);
uniform float corner_radius_px = 10.0;
uniform float border_width_px = 0.0;
uniform float floor_edge_width_px = 0.0;
uniform float source_crop_px = 0.0;
uniform float wobble_strength_px = 0.0;
uniform float wobble_motion_px = 0.0;
uniform float border_motion_strength = 0.0;
uniform float border_breath_amplitude = 0.0;
uniform float border_breath_speed = 1.0;
uniform float floor_breath_amplitude = 0.0;
uniform float floor_breath_speed = 1.0;
uniform float phase = 0.0;
uniform vec4 border_color : source_color = vec4(0.08, 0.09, 0.07, 1.0);
uniform vec4 border_highlight_color : source_color = vec4(0.24, 0.30, 0.18, 1.0);
uniform vec4 floor_edge_color : source_color = vec4(0.82, 0.84, 0.72, 1.0);
uniform bool freeze_animation = false;
uniform float frozen_time = 0.0;

float signed_rounded_box(vec2 point, vec2 half_extent, float radius) {
	vec2 q = abs(point) - half_extent + vec2(radius);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

float organic_wobble(vec2 uv) {
	float broad = sin(uv.x * 18.0 + uv.y * 7.0 + phase);
	float cross = sin(uv.y * 25.0 - uv.x * 9.0 - phase * 0.73);
	float detail = sin((uv.x + uv.y) * 39.0 + phase * 1.91);
	return (broad * 0.52 + cross * 0.33 + detail * 0.15) * wobble_strength_px;
}

void fragment() {
	vec2 crop_uv = vec2(source_crop_px) / tile_size_px;
	vec2 source_uv = mix(crop_uv, vec2(1.0) - crop_uv, UV);
	vec4 source = texture(TEXTURE, source_uv);
	vec2 pixel_position = (UV - vec2(0.5)) * tile_size_px;
	float animation_time = freeze_animation ? frozen_time : TIME;
	float contour_motion = sin(
		(UV.x - UV.y) * 22.0 + animation_time * 0.72 + phase
	) * wobble_motion_px;
	float wobble = organic_wobble(UV) + contour_motion;
	float radius = max(corner_radius_px + wobble * 0.18, 1.0);
	vec2 half_extent = tile_size_px * 0.5 - vec2(0.25);
	float distance_to_edge = signed_rounded_box(pixel_position, half_extent, radius) + wobble;
	float antialias_width = max(fwidth(distance_to_edge), 0.75);
	float shape_alpha = 1.0 - smoothstep(-antialias_width, antialias_width, distance_to_edge);

	float floor_mode = step(0.01, floor_edge_width_px);
	vec3 rounded_floor_color = mix(floor_edge_color.rgb, source.rgb, shape_alpha);
	vec3 shaped_color = mix(source.rgb, rounded_floor_color, floor_mode);
	float border_breath = 0.5 + 0.5 * sin(
		animation_time * border_breath_speed + phase
	);
	float border_width_scale = 1.0 + (
		border_breath * 2.0 - 1.0
	) * border_breath_amplitude;
	float animated_border_width = border_width_px * border_width_scale;
	float border_inner = 1.0 - smoothstep(
		-antialias_width,
		antialias_width,
		distance_to_edge + animated_border_width
	);
	float border_mask = shape_alpha * (1.0 - border_inner) * step(0.01, border_width_px);
	float perimeter_angle = atan(pixel_position.y, pixel_position.x);
	float border_flow = 0.5 + 0.5 * sin(
		perimeter_angle * 3.0 - animation_time * 1.35 + phase
	);
	float border_light = border_motion_strength * (
		0.14 + border_breath * 0.48 + border_flow * 0.10
	);
	vec3 animated_border = mix(border_color.rgb, border_highlight_color.rgb, border_light);
	shaped_color = mix(shaped_color, animated_border, border_mask * 0.88);

	float floor_breath = 0.5 + 0.5 * sin(
		animation_time * floor_breath_speed + phase
	);
	float floor_width_scale = 1.0 + (
		floor_breath * 2.0 - 1.0
	) * floor_breath_amplitude;
	float animated_floor_width = floor_edge_width_px * floor_width_scale;
	float floor_inner = 1.0 - smoothstep(
		-antialias_width,
		antialias_width,
		distance_to_edge + animated_floor_width
	);
	float floor_band = shape_alpha * (1.0 - floor_inner) * step(0.01, floor_edge_width_px);
	float floor_edge_mix = floor_band * (0.10 + floor_breath * 0.30);
	shaped_color = mix(shaped_color, floor_edge_color.rgb, floor_edge_mix);

	float output_alpha = mix(shape_alpha, 1.0, floor_mode);
	COLOR = vec4(shaped_color, output_alpha);
}
"""

var _asset_order: Array[String] = []
var _asset_main_colors: Dictionary = {}
var _asset_textures: Dictionary = {}
var _assets_by_id: Dictionary = {}
var _cell_assignments: Dictionary = {}
var _cell_metadata: Dictionary = {}
var _cell_tile_layer: TileMapLayer
var _collision_bodies: Node2D
var _collision_overlay: Node2D
var _configured: bool = false
var _default_tile_asset_id: String = ""
var _detail: Node2D
var _grid_size: Vector2i = Vector2i.ZERO
var _hover_highlight: Polygon2D
var _last_seed: int = 0
var _layer_visibility: Dictionary = {
	LAYER_CELL_TILES: true,
	LAYER_COLLISION: true,
	LAYER_DETAIL: true,
	LAYER_METADATA: true,
}
var _layout_signature: String = ""
var _metadata: Node2D
var _obstacle_asset_ids: Dictionary = {}
var _obstacle_placements: Array[Dictionary] = []
var _placement_rules: Array[Dictionary] = []
var _seam_fill_layer: Node2D
var _source_ids_by_asset: Dictionary = {}
var _tile_visual_layer: Node2D
var _tile_visual_materials: Array[ShaderMaterial] = []
var _tile_visual_shader: Shader
var _tile_size: Vector2i = Vector2i.ZERO


func _ready() -> void:
	_ensure_layers()


func configure(style_pack: Dictionary, scene_config: Dictionary) -> Error:
	_ensure_layers()
	_reset_configuration()

	if int(style_pack.get("schema_version", 0)) != SUPPORTED_STYLE_PACK_SCHEMA_VERSION:
		return ERR_INVALID_DATA
	if int(scene_config.get("schema_version", 0)) != SUPPORTED_SCENE_SCHEMA_VERSION:
		return ERR_INVALID_DATA
	if String(style_pack.get("projection", "")) != "orthographic_top_down":
		return ERR_INVALID_DATA
	if String(style_pack.get("composition_mode", "")) != "exclusive_cell_tiles":
		return ERR_INVALID_DATA
	if String(scene_config.get("cell_composition", "")) != "exclusive":
		return ERR_INVALID_DATA

	_grid_size = _array_to_vector2i(scene_config.get("grid_size", []))
	_tile_size = _array_to_vector2i(style_pack.get("tile_size_px", []))
	var scene_tile_size := _array_to_vector2i(scene_config.get("tile_size_px", []))
	if _grid_size.x <= 0 or _grid_size.y <= 0:
		return ERR_INVALID_DATA
	if _tile_size.x <= 0 or _tile_size.y <= 0 or scene_tile_size != _tile_size:
		return ERR_INVALID_DATA

	var assets_error := _load_assets(style_pack)
	if assets_error != OK:
		return assets_error

	_default_tile_asset_id = String(scene_config.get("default_tile_asset_id", ""))
	if not _assets_by_id.has(_default_tile_asset_id):
		return ERR_INVALID_DATA
	var default_asset: Dictionary = _assets_by_id[_default_tile_asset_id]
	if default_asset.get("collision", null) != null:
		return ERR_INVALID_DATA
	if not _string_array(default_asset.get("tags", [])).has("walkable"):
		return ERR_INVALID_DATA

	var rules_error := _load_placement_rules(scene_config)
	if rules_error != OK:
		return rules_error
	var tile_set_error := _configure_cell_tile_set()
	if tile_set_error != OK:
		return tile_set_error

	_configured = true
	return OK


func regenerate(seed: int) -> void:
	if not _configured:
		push_error("UniversalTileGrid must be configured before regenerate().")
		return

	_last_seed = seed
	_clear_runtime_state()
	_assign_default_tiles()
	_assign_obstacle_tiles(seed)
	_render_cell_tiles()
	_build_collision_runtime()
	_build_metadata_grid()
	_layout_signature = _compose_layout_signature()
	_apply_layer_visibility()


func get_layout_signature() -> String:
	return _layout_signature


func get_generation_summary() -> Dictionary:
	var tile_counts: Dictionary = {}
	var blocked_count: int = 0
	var walkable_count: int = 0
	for asset_id_value: Variant in _cell_assignments.values():
		var asset_id := String(asset_id_value)
		tile_counts[asset_id] = int(tile_counts.get(asset_id, 0)) + 1
		if _obstacle_asset_ids.has(asset_id):
			blocked_count += 1
		else:
			walkable_count += 1

	var perimeter_only: bool = true
	var occupied_obstacle_cells: Dictionary = {}
	for placement: Dictionary in _obstacle_placements:
		var cell: Vector2i = placement.get("cell", Vector2i(-1, -1))
		perimeter_only = perimeter_only and _is_perimeter_cell(cell)
		occupied_obstacle_cells[cell] = true

	var expected_cell_count := _grid_size.x * _grid_size.y
	return {
		"seed": _last_seed,
		"grid_size": [_grid_size.x, _grid_size.y],
		"tile_size_px": [_tile_size.x, _tile_size.y],
		"cell_composition": "exclusive",
		"default_tile_asset_id": _default_tile_asset_id,
		"cell_count": _cell_assignments.size(),
		"tile_count": _cell_assignments.size(),
		"tile_counts": tile_counts,
		"default_tile_count": int(tile_counts.get(_default_tile_asset_id, 0)),
		"obstacle_count": _obstacle_placements.size(),
		"walkable_count": walkable_count,
		"blocked_count": blocked_count,
		"collision_count": _obstacle_placements.size(),
		"full_grid": _cell_assignments.size() == expected_cell_count,
		"mutually_exclusive": _cell_assignments.size() == expected_cell_count,
		"perimeter_only": perimeter_only,
		"overlap_free": occupied_obstacle_cells.size() == _obstacle_placements.size(),
		"detail_count": 0,
		"visual_style": {
			"rounded_cell_count": _tile_visual_layer.get_child_count() if _tile_visual_layer != null else 0,
			"obstacle_border_count": _obstacle_placements.size(),
			"seam_fill_count": _seam_fill_layer.get_child_count() if _seam_fill_layer != null else 0,
			"cell_visual_bleed_px": CELL_VISUAL_BLEED_PX,
			"floor_source_crop_px": FLOOR_SOURCE_CROP_PX,
			"continuous_seam_underlay": true,
			"floor_full_cell_seam_fill": true,
			"visual_stack_mode": "deterministic_balanced",
			"visual_stack_seed": VISUAL_STACK_SEED,
			"obstacle_border_motion": true,
			"obstacle_breath_width_amplitude": OBSTACLE_BREATH_WIDTH_AMPLITUDE,
			"obstacle_breath_speed": OBSTACLE_BREATH_SPEED,
			"floor_edge_breathing": true,
			"floor_breath_width_amplitude": FLOOR_BREATH_WIDTH_AMPLITUDE,
			"floor_breath_speed": FLOOR_BREATH_SPEED,
			"floor_corner_radius_px": FLOOR_CORNER_RADIUS_PX,
			"obstacle_corner_radius_px": OBSTACLE_CORNER_RADIUS_PX,
			"obstacle_border_width_px": OBSTACLE_BORDER_WIDTH_PX,
			"render_source": "runtime_shader",
		},
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


func debug_prepare_capture(animation_time: float = VISUAL_CAPTURE_TIME) -> void:
	for material: ShaderMaterial in _tile_visual_materials:
		material.set_shader_parameter("freeze_animation", true)
		material.set_shader_parameter("frozen_time", animation_time)


func _reset_configuration() -> void:
	_configured = false
	_asset_order.clear()
	_asset_main_colors.clear()
	_asset_textures.clear()
	_assets_by_id.clear()
	_obstacle_asset_ids.clear()
	_placement_rules.clear()
	_source_ids_by_asset.clear()


func _load_assets(style_pack: Dictionary) -> Error:
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
		if String(asset.get("role", "")) != "cell_tile":
			return ERR_INVALID_DATA
		if String(asset.get("visual_occupancy", "")) != "full_cell":
			return ERR_INVALID_DATA
		if String(asset.get("alpha_mode", "")) != "opaque":
			return ERR_INVALID_DATA

		var texture_path := String(asset.get("texture_path", ""))
		var texture := _load_runtime_texture(texture_path)
		if texture == null:
			return ERR_FILE_NOT_FOUND
		_assets_by_id[asset_id] = asset
		_asset_textures[asset_id] = texture
		_asset_main_colors[asset_id] = _sample_main_color(texture)
		_asset_order.append(asset_id)
	return OK


func _load_placement_rules(scene_config: Dictionary) -> Error:
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
	var requested_obstacle_count: int = 0
	var requested_assets: Dictionary = {}
	for rule_value: Variant in placements_value:
		if not rule_value is Dictionary:
			return ERR_INVALID_DATA
		var rule: Dictionary = (rule_value as Dictionary).duplicate(true)
		var asset_id := String(rule.get("asset_id", ""))
		var count := int(rule.get("count", 0))
		if not _assets_by_id.has(asset_id) or count <= 0 or requested_assets.has(asset_id):
			return ERR_INVALID_DATA
		var asset: Dictionary = _assets_by_id[asset_id]
		if not _has_full_cell_collision(asset):
			return ERR_INVALID_DATA
		var tags := _string_array(asset.get("tags", []))
		if not tags.has("obstacle") or not tags.has("non_walkable"):
			return ERR_INVALID_DATA
		requested_assets[asset_id] = true
		_obstacle_asset_ids[asset_id] = true
		_placement_rules.append(rule)
		requested_obstacle_count += count

	var cell_count := _grid_size.x * _grid_size.y
	if requested_obstacle_count >= cell_count:
		return ERR_INVALID_DATA
	if requested_obstacle_count > _perimeter_cells().size():
		return ERR_INVALID_DATA
	return OK


func _ensure_layers() -> void:
	_cell_tile_layer = get_node_or_null("CellTileLayer") as TileMapLayer
	if _cell_tile_layer == null:
		_cell_tile_layer = TileMapLayer.new()
		_cell_tile_layer.name = "CellTileLayer"
		add_child(_cell_tile_layer)
	_cell_tile_layer.z_index = 0
	_cell_tile_layer.self_modulate = Color(1.0, 1.0, 1.0, 0.0)

	_seam_fill_layer = _ensure_node2d("SeamFillLayer", -1)
	_tile_visual_layer = _ensure_node2d("TileVisualLayer", 0)
	_collision_bodies = _ensure_node2d("CollisionBodies", 1)
	_collision_overlay = _ensure_node2d("CollisionOverlay", 10)
	_detail = _ensure_node2d("DetailLayer", 2)
	_metadata = _ensure_node2d("MetadataOverlay", 11)


func _ensure_node2d(node_name: String, target_z_index: int) -> Node2D:
	var layer := get_node_or_null(node_name) as Node2D
	if layer == null:
		layer = Node2D.new()
		layer.name = node_name
		add_child(layer)
	layer.z_index = target_z_index
	return layer


func _configure_cell_tile_set() -> Error:
	var tile_set := TileSet.new()
	tile_set.tile_size = _tile_size
	_source_ids_by_asset.clear()
	for asset_id: String in _asset_order:
		var texture_value: Variant = _asset_textures.get(asset_id)
		if not texture_value is Texture2D:
			return ERR_INVALID_DATA
		var texture: Texture2D = texture_value
		if Vector2i(texture.get_size()) != _tile_size:
			return ERR_INVALID_DATA

		var atlas_source := TileSetAtlasSource.new()
		atlas_source.texture = texture
		atlas_source.texture_region_size = _tile_size
		atlas_source.create_tile(Vector2i.ZERO)
		var source_id := tile_set.add_source(atlas_source)
		if source_id < 0:
			return ERR_CANT_CREATE
		_source_ids_by_asset[asset_id] = source_id
	_cell_tile_layer.tile_set = tile_set
	return OK


func _clear_runtime_state() -> void:
	_cell_assignments.clear()
	_cell_metadata.clear()
	_obstacle_placements.clear()
	_cell_tile_layer.clear()
	_clear_children(_seam_fill_layer)
	_clear_children(_tile_visual_layer)
	_tile_visual_materials.clear()
	_clear_children(_collision_bodies)
	_clear_children(_collision_overlay)
	_clear_children(_detail)
	_clear_children(_metadata)
	_hover_highlight = null


func _assign_default_tiles() -> void:
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			_cell_assignments[Vector2i(x, y)] = _default_tile_asset_id


func _assign_obstacle_tiles(seed: int) -> void:
	var available_cells := _perimeter_cells()
	_deterministic_shuffle(available_cells, seed)
	var cell_cursor: int = 0
	var obstacle_index: int = 0
	for rule: Dictionary in _placement_rules:
		var asset_id := String(rule.get("asset_id", ""))
		var count := int(rule.get("count", 0))
		for _count_index in range(count):
			var cell: Vector2i = available_cells[cell_cursor]
			cell_cursor += 1
			_cell_assignments[cell] = asset_id
			_obstacle_placements.append({
				"asset_id": asset_id,
				"cell": cell,
				"obstacle_index": obstacle_index,
			})
			obstacle_index += 1


func _render_cell_tiles() -> void:
	_build_seam_fill()
	var floor_cells: Array[Vector2i] = []
	var obstacle_cells: Array[Vector2i] = []
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			var cell := Vector2i(x, y)
			var asset_id := String(_cell_assignments.get(cell, ""))
			var source_id := int(_source_ids_by_asset.get(asset_id, -1))
			_cell_tile_layer.set_cell(cell, source_id, Vector2i.ZERO)
			_cell_metadata[cell] = _build_cell_metadata(cell, asset_id)
			if _obstacle_asset_ids.has(asset_id):
				obstacle_cells.append(cell)
			else:
				floor_cells.append(cell)

	_deterministic_shuffle(floor_cells, VISUAL_STACK_SEED)
	_deterministic_shuffle(obstacle_cells, VISUAL_STACK_SEED + 1_009)
	var stack_rank: int = 0
	for cell: Vector2i in floor_cells:
		_add_tile_visual(cell, String(_cell_assignments.get(cell, "")), stack_rank)
		stack_rank += 1
	for cell: Vector2i in obstacle_cells:
		_add_tile_visual(cell, String(_cell_assignments.get(cell, "")), stack_rank)
		stack_rank += 1


func _add_tile_visual(cell: Vector2i, asset_id: String, stack_rank: int) -> void:
	var texture_value: Variant = _asset_textures.get(asset_id)
	if not texture_value is Texture2D:
		return
	var texture: Texture2D = texture_value
	var is_floor := asset_id == _default_tile_asset_id
	var content_color: Color = _asset_main_colors.get(asset_id, Color(0.5, 0.5, 0.5, 1.0))
	var floor_color: Color = _asset_main_colors.get(
		_default_tile_asset_id,
		Color(0.5, 0.5, 0.5, 1.0)
	)
	var border_color := _deep_content_color(content_color)
	var border_highlight_color := _content_edge_highlight(content_color)
	var material := ShaderMaterial.new()
	material.shader = _tile_visual_shader_instance()
	material.set_shader_parameter("tile_size_px", Vector2(_tile_size))
	material.set_shader_parameter(
		"corner_radius_px",
		FLOOR_CORNER_RADIUS_PX if is_floor else OBSTACLE_CORNER_RADIUS_PX
	)
	material.set_shader_parameter("border_width_px", 0.0 if is_floor else OBSTACLE_BORDER_WIDTH_PX)
	material.set_shader_parameter("floor_edge_width_px", FLOOR_EDGE_WIDTH_PX if is_floor else 0.0)
	material.set_shader_parameter("source_crop_px", FLOOR_SOURCE_CROP_PX if is_floor else 0.0)
	material.set_shader_parameter("wobble_strength_px", 0.55 if is_floor else 1.65)
	material.set_shader_parameter("wobble_motion_px", 0.0 if is_floor else 0.32)
	material.set_shader_parameter("border_motion_strength", 0.0 if is_floor else 1.0)
	material.set_shader_parameter(
		"border_breath_amplitude",
		0.0 if is_floor else OBSTACLE_BREATH_WIDTH_AMPLITUDE
	)
	material.set_shader_parameter("border_breath_speed", OBSTACLE_BREATH_SPEED)
	material.set_shader_parameter(
		"floor_breath_amplitude",
		FLOOR_BREATH_WIDTH_AMPLITUDE if is_floor else 0.0
	)
	material.set_shader_parameter("floor_breath_speed", FLOOR_BREATH_SPEED)
	material.set_shader_parameter("phase", _visual_phase(cell, asset_id))
	material.set_shader_parameter("border_color", border_color)
	material.set_shader_parameter("border_highlight_color", border_highlight_color)
	material.set_shader_parameter("floor_edge_color", _floor_edge_color(floor_color))

	var sprite := Sprite2D.new()
	sprite.name = "TileVisual_%02d_%02d" % [cell.x, cell.y]
	sprite.position = _cell_center(cell)
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = Vector2(
		1.0 + CELL_VISUAL_BLEED_PX / float(_tile_size.x),
		1.0 + CELL_VISUAL_BLEED_PX / float(_tile_size.y)
	)
	sprite.material = material
	sprite.set_meta("asset_id", asset_id)
	sprite.set_meta("cell", cell)
	sprite.set_meta("visual_role", "floor" if is_floor else "obstacle")
	sprite.set_meta("visual_stack_rank", stack_rank)
	sprite.set_meta("visual_stack_group", "floor" if is_floor else "obstacle")
	sprite.set_meta("content_main_color", content_color)
	sprite.set_meta("border_color", border_color)
	sprite.set_meta("border_highlight_color", border_highlight_color)
	sprite.set_meta(
		"corner_radius_px",
		FLOOR_CORNER_RADIUS_PX if is_floor else OBSTACLE_CORNER_RADIUS_PX
	)
	sprite.set_meta("border_width_px", 0.0 if is_floor else OBSTACLE_BORDER_WIDTH_PX)
	sprite.set_meta("border_motion", not is_floor)
	sprite.set_meta("visual_bleed_px", CELL_VISUAL_BLEED_PX)
	sprite.set_meta("source_crop_px", FLOOR_SOURCE_CROP_PX if is_floor else 0.0)
	sprite.set_meta("floor_edge_breathing", is_floor)
	_tile_visual_layer.add_child(sprite)
	_tile_visual_materials.append(material)


func _build_seam_fill() -> void:
	var floor_color: Color = _asset_main_colors.get(
		_default_tile_asset_id,
		Color(0.5, 0.5, 0.5, 1.0)
	)
	var extent := Vector2(
		float(_grid_size.x * _tile_size.x),
		float(_grid_size.y * _tile_size.y)
	)
	var margin := CELL_VISUAL_BLEED_PX
	var backing := Polygon2D.new()
	backing.name = "ContinuousSeamBacking"
	backing.polygon = PackedVector2Array([
		Vector2(-margin, -margin),
		Vector2(extent.x + margin, -margin),
		Vector2(extent.x + margin, extent.y + margin),
		Vector2(-margin, extent.y + margin),
	])
	backing.color = _floor_backdrop_color(floor_color)
	backing.set_meta("visual_role", "continuous_seam_underlay")
	backing.set_meta("coverage_px", extent)
	_seam_fill_layer.add_child(backing)


func _build_cell_metadata(cell: Vector2i, asset_id: String) -> Dictionary:
	var asset: Dictionary = _assets_by_id[asset_id]
	var is_obstacle := _obstacle_asset_ids.has(asset_id)
	var layers: Array[String] = [LAYER_CELL_TILES]
	if is_obstacle:
		layers.append(LAYER_COLLISION)
	return {
		"cell": [cell.x, cell.y],
		"layers": layers,
		"asset_id": asset_id,
		"tile": _metadata_for_asset(asset),
		"tags": _string_array(asset.get("tags", [])),
		"footprint_cells": [1, 1],
		"collision": _runtime_collision_metadata(is_obstacle),
		"interaction": _interaction_for_asset(asset),
		"cell_composition": "exclusive",
	}


func _build_collision_runtime() -> void:
	for placement: Dictionary in _obstacle_placements:
		var asset_id := String(placement.get("asset_id", ""))
		var cell: Vector2i = placement.get("cell", Vector2i.ZERO)
		var obstacle_index := int(placement.get("obstacle_index", 0))
		_add_full_cell_collision_body(asset_id, cell, obstacle_index)
		_add_full_cell_collision_outline(cell, obstacle_index)


func _add_full_cell_collision_body(asset_id: String, cell: Vector2i, obstacle_index: int) -> void:
	var body := StaticBody2D.new()
	body.name = "TileCollision_%02d" % obstacle_index
	body.position = _cell_center(cell)
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("asset_id", asset_id)
	body.set_meta("cell", cell)
	body.set_meta("coverage", "full_cell")

	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(_tile_size)
	var shape_node := CollisionShape2D.new()
	shape_node.name = "Shape"
	shape_node.shape = rectangle
	body.add_child(shape_node)
	_collision_bodies.add_child(body)


func _add_full_cell_collision_outline(cell: Vector2i, obstacle_index: int) -> void:
	var origin := Vector2(cell * _tile_size)
	var inset := 3.0
	var far_corner := Vector2(_tile_size) - Vector2(inset, inset)
	var points := PackedVector2Array([
		origin + Vector2(inset, inset),
		origin + Vector2(far_corner.x, inset),
		origin + far_corner,
		origin + Vector2(inset, far_corner.y),
		origin + Vector2(inset, inset),
	])
	var line := _make_line(points, Color(0.96, 0.50, 0.16, 0.92), 3.0)
	line.name = "CollisionOutline_%02d" % obstacle_index
	_collision_overlay.add_child(line)


func _build_metadata_grid() -> void:
	for x in range(_grid_size.x + 1):
		var x_position := float(x * _tile_size.x)
		_metadata.add_child(_make_line(
			PackedVector2Array([
				Vector2(x_position, 0.0),
				Vector2(x_position, float(_grid_size.y * _tile_size.y)),
			]),
			Color(0.78, 0.88, 0.78, 0.30),
			1.0
		))
	for y in range(_grid_size.y + 1):
		var y_position := float(y * _tile_size.y)
		_metadata.add_child(_make_line(
			PackedVector2Array([
				Vector2(0.0, y_position),
				Vector2(float(_grid_size.x * _tile_size.x), y_position),
			]),
			Color(0.78, 0.88, 0.78, 0.30),
			1.0
		))

	_hover_highlight = Polygon2D.new()
	_hover_highlight.name = "HoverHighlight"
	_hover_highlight.polygon = PackedVector2Array([
		Vector2(4.0, 4.0),
		Vector2(float(_tile_size.x) - 4.0, 4.0),
		Vector2(float(_tile_size.x) - 4.0, float(_tile_size.y) - 4.0),
		Vector2(4.0, float(_tile_size.y) - 4.0),
	])
	_hover_highlight.color = Color(0.80, 0.94, 0.62, 0.14)
	_hover_highlight.visible = false
	_metadata.add_child(_hover_highlight)


func _make_line(points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = true
	return line


func _compose_layout_signature() -> String:
	var assignment_parts := PackedStringArray()
	for y in range(_grid_size.y):
		for x in range(_grid_size.x):
			var cell := Vector2i(x, y)
			assignment_parts.append("%d,%d:%s" % [x, y, String(_cell_assignments.get(cell, ""))])
	return "composition=exclusive|grid=%dx%d|cells=%s" % [
		_grid_size.x,
		_grid_size.y,
		";".join(assignment_parts),
	]


func _metadata_for_asset(asset: Dictionary) -> Dictionary:
	var authored_collision_value: Variant = asset.get("collision", {})
	var authored_collision: Dictionary = {}
	if authored_collision_value is Dictionary:
		authored_collision = (authored_collision_value as Dictionary).duplicate(true)
	return {
		"id": String(asset.get("id", "")),
		"role": String(asset.get("role", "")),
		"visual_occupancy": String(asset.get("visual_occupancy", "")),
		"alpha_mode": String(asset.get("alpha_mode", "")),
		"footprint_cells": [1, 1],
		"footprint_shape": String(asset.get("footprint_shape", "")),
		"anchor_point_px": _int_array(asset.get("anchor_point_px", [])),
		"orientation_read": String(asset.get("orientation_read", "")),
		"tags": _string_array(asset.get("tags", [])),
		"authored_collision": authored_collision,
	}


func _has_full_cell_collision(asset: Dictionary) -> bool:
	var collision_value: Variant = asset.get("collision", null)
	if not collision_value is Dictionary:
		return false
	var collision: Dictionary = collision_value
	return (
		String(collision.get("shape", "")) == "rectangle"
		and _array_to_vector2i(collision.get("size_px", [])) == _tile_size
		and _array_to_vector2i(collision.get("offset_px", [])) == Vector2i.ZERO
	)


func _runtime_collision_metadata(is_obstacle: bool) -> Dictionary:
	if not is_obstacle:
		return {"shape": "none", "coverage": "none"}
	return {
		"shape": "rectangle",
		"size_px": [_tile_size.x, _tile_size.y],
		"offset_px": [0, 0],
		"coverage": "full_cell",
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


func _load_runtime_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty():
		return null
	var resolved_path := texture_path
	if texture_path.begins_with("res://") or texture_path.begins_with("user://"):
		resolved_path = ProjectSettings.globalize_path(texture_path)
	var image := Image.new()
	var load_error := image.load(resolved_path)
	if load_error != OK:
		push_error("Failed to load universal Tile image: %s (%s)" % [texture_path, load_error])
		return null
	return ImageTexture.create_from_image(image)


func _tile_visual_shader_instance() -> Shader:
	if _tile_visual_shader == null:
		_tile_visual_shader = Shader.new()
		_tile_visual_shader.code = TILE_VISUAL_SHADER_CODE
	return _tile_visual_shader


func _sample_main_color(texture: Texture2D) -> Color:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Color(0.5, 0.5, 0.5, 1.0)
	var samples: Array[Color] = []
	var value_sum: float = 0.0
	for y in range(4, image.get_height(), 8):
		for x in range(4, image.get_width(), 8):
			var sample := image.get_pixel(x, y)
			samples.append(sample)
			value_sum += sample.v
	if samples.is_empty():
		return Color(0.5, 0.5, 0.5, 1.0)
	var value_cutoff := value_sum / float(samples.size())
	var red_sum: float = 0.0
	var green_sum: float = 0.0
	var blue_sum: float = 0.0
	var sample_count: int = 0
	for sample: Color in samples:
		if sample.v < value_cutoff:
			continue
		red_sum += sample.r
		green_sum += sample.g
		blue_sum += sample.b
		sample_count += 1
	if sample_count == 0:
		return Color(0.5, 0.5, 0.5, 1.0)
	var divisor := float(sample_count)
	return Color(red_sum / divisor, green_sum / divisor, blue_sum / divisor, 1.0)


func _deep_content_color(content_color: Color) -> Color:
	var target_value := maxf(content_color.v * 0.73, 0.08)
	target_value = minf(target_value, maxf(content_color.v - 0.08, 0.04))
	return Color.from_hsv(
		content_color.h,
		clampf(maxf(content_color.s * 1.08, 0.38), 0.0, 0.92),
		clampf(target_value, 0.04, 0.52),
		1.0
	)


func _content_edge_highlight(content_color: Color) -> Color:
	var border_color := _deep_content_color(content_color)
	var maximum_value := minf(content_color.v * 0.88, content_color.v - 0.04)
	var target_value := minf(border_color.v + 0.08, maximum_value)
	return Color.from_hsv(
		content_color.h,
		clampf(maxf(content_color.s * 1.02, 0.34), 0.0, 0.88),
		clampf(maxf(target_value, border_color.v + 0.02), 0.06, 0.56),
		1.0
	)


func _floor_edge_color(floor_color: Color) -> Color:
	return Color(
		clampf(floor_color.r * 1.08 + 0.035, 0.0, 1.0),
		clampf(floor_color.g * 1.08 + 0.045, 0.0, 1.0),
		clampf(floor_color.b * 1.04 + 0.055, 0.0, 1.0),
		1.0
	)


func _floor_backdrop_color(floor_color: Color) -> Color:
	return Color(
		clampf(floor_color.r * 0.94 + 0.015, 0.0, 1.0),
		clampf(floor_color.g * 0.95 + 0.018, 0.0, 1.0),
		clampf(floor_color.b * 0.96 + 0.020, 0.0, 1.0),
		1.0
	)


func _visual_phase(cell: Vector2i, asset_id: String) -> float:
	var stable_value := absi(cell.x * 97 + cell.y * 193 + asset_id.hash()) % 10_000
	return float(stable_value) / 10_000.0 * TAU


func _apply_layer_visibility() -> void:
	if _cell_tile_layer != null:
		_cell_tile_layer.visible = bool(_layer_visibility[LAYER_CELL_TILES])
	if _seam_fill_layer != null:
		_seam_fill_layer.visible = bool(_layer_visibility[LAYER_CELL_TILES])
	if _tile_visual_layer != null:
		_tile_visual_layer.visible = bool(_layer_visibility[LAYER_CELL_TILES])
	if _collision_overlay != null:
		_collision_overlay.visible = bool(_layer_visibility[LAYER_COLLISION])
	if _detail != null:
		_detail.visible = bool(_layer_visibility[LAYER_DETAIL])
	if _metadata != null:
		_metadata.visible = bool(_layer_visibility[LAYER_METADATA])


func _clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.free()


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
		(float(cell.x) + 0.5) * float(_tile_size.x),
		(float(cell.y) + 0.5) * float(_tile_size.y)
	)


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
