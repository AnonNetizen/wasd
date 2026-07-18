extends SceneTree

const CONFIG_PATH: String = "res://data/ai_universal_tile_test.json"
const EXPECTED_COUNTS: Dictionary = {
	"marble_floor_01": 18,
	"tree_01": 3,
	"wood_cabinet_01": 3,
}
const EXPECTED_GRID_SIZE: Vector2i = Vector2i(6, 4)
const EXPECTED_TILE_SIZE: Vector2i = Vector2i(128, 128)
const GRID_SCRIPT := preload("res://scripts/universal_tile_grid.gd")
const LAYER_CELL_TILES: String = "cell_tiles"
const LAYER_COLLISION: String = "collision"
const LAYER_DETAIL: String = "detail"
const LAYER_METADATA: String = "metadata"
const SCENE_PATH: String = "res://scenes/ai_universal_tile_test.tscn"
const SUPPORTED_SCHEMA_VERSION: int = 2

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var scene_config := _load_json_dictionary(CONFIG_PATH)
	_check(not scene_config.is_empty(), "Scene config loads as a JSON object.")
	if scene_config.is_empty():
		_finish()
		return

	var style_pack_path := String(scene_config.get("style_pack_path", ""))
	var style_pack := _load_json_dictionary(style_pack_path)
	_check(not style_pack.is_empty(), "Style Pack loads as a JSON object.")
	if style_pack.is_empty():
		_finish()
		return

	_validate_scene_config(scene_config)
	_validate_style_pack(style_pack)
	_validate_asset_images(style_pack)
	_validate_scene_file_shape()
	await _validate_runtime(scene_config)
	_finish()


func _validate_scene_config(scene_config: Dictionary) -> void:
	_check(
		int(scene_config.get("schema_version", 0)) == SUPPORTED_SCHEMA_VERSION,
		"Scene config schema_version is 2."
	)
	_check(
		_array_to_vector2i(scene_config.get("grid_size", [])) == EXPECTED_GRID_SIZE,
		"Scene grid is 6 × 4."
	)
	_check(
		_array_to_vector2i(scene_config.get("tile_size_px", [])) == EXPECTED_TILE_SIZE,
		"Scene tile size is 128 × 128."
	)
	_check(int(scene_config.get("base_seed", 0)) == 20_260_711, "Base seed is 20260711.")
	_check(int(scene_config.get("seed_step", 0)) == 7_919, "Seed step is 7919.")
	_check(
		String(scene_config.get("default_tile_asset_id", "")) == "marble_floor_01",
		"Default cell tile is marble_floor_01."
	)
	_check(
		String(scene_config.get("cell_composition", "")) == "exclusive",
		"Scene composition is mutually exclusive per cell."
	)
	_check(not scene_config.has("base_fill_asset_id"), "Scene config removes the old Base fill authority.")
	_check(not scene_config.has("tile_types"), "Scene config has no duplicate tile_types authority.")

	var generation_rules_value: Variant = scene_config.get("generation_rules", {})
	_check(generation_rules_value is Dictionary, "Scene config has generation_rules.")
	if not generation_rules_value is Dictionary:
		return
	var generation_rules: Dictionary = generation_rules_value
	_check(
		String(generation_rules.get("placement_zone", "")) == "perimeter",
		"Obstacle tiles are constrained to perimeter cells."
	)
	_check(not bool(generation_rules.get("allow_overlap", true)), "Cell overlap is disabled.")

	var requested_counts: Dictionary = {}
	var placements_value: Variant = generation_rules.get("placements", [])
	_check(placements_value is Array, "Generation placements are an array.")
	if placements_value is Array:
		for placement_value: Variant in placements_value:
			_check(placement_value is Dictionary, "Every generation placement is an object.")
			if not placement_value is Dictionary:
				continue
			var placement: Dictionary = placement_value
			var asset_id := String(placement.get("asset_id", ""))
			_check(not requested_counts.has(asset_id), "Generation asset id is unique: %s." % asset_id)
			requested_counts[asset_id] = int(placement.get("count", 0))
	_check(int(requested_counts.get("tree_01", 0)) == 3, "Generation requests three tree tiles.")
	_check(
		int(requested_counts.get("wood_cabinet_01", 0)) == 3,
		"Generation requests three cabinet tiles."
	)
	var requested_obstacle_count := (
		int(requested_counts.get("tree_01", 0))
		+ int(requested_counts.get("wood_cabinet_01", 0))
	)
	_check(
		EXPECTED_GRID_SIZE.x * EXPECTED_GRID_SIZE.y - requested_obstacle_count == 18,
		"The default tile fills the remaining 18 cells."
	)


func _validate_style_pack(style_pack: Dictionary) -> void:
	_check(
		int(style_pack.get("schema_version", 0)) == SUPPORTED_SCHEMA_VERSION,
		"Style Pack schema_version is 2."
	)
	_check(not String(style_pack.get("style_id", "")).is_empty(), "Style Pack has a style_id.")
	_check(
		String(style_pack.get("projection", "")) == "orthographic_top_down",
		"Style Pack projection is top-down orthographic."
	)
	_check(
		String(style_pack.get("composition_mode", "")) == "exclusive_cell_tiles",
		"Style Pack declares exclusive full-cell composition."
	)
	_check(
		_array_to_vector2i(style_pack.get("tile_size_px", [])) == EXPECTED_TILE_SIZE,
		"Style Pack tile size is 128 × 128."
	)
	_check(style_pack.get("palette", null) is Dictionary, "Style Pack declares a palette.")

	var assets_value: Variant = style_pack.get("assets", [])
	_check(assets_value is Array and (assets_value as Array).size() == 3, "Style Pack contains exactly three assets.")
	if not assets_value is Array:
		return
	var asset_ids: Dictionary = {}
	for asset_value: Variant in assets_value:
		_check(asset_value is Dictionary, "Every Style Pack asset is an object.")
		if not asset_value is Dictionary:
			continue
		var asset: Dictionary = asset_value
		var asset_id := String(asset.get("id", ""))
		_check(not asset_id.is_empty(), "Every asset has an id.")
		_check(not asset_ids.has(asset_id), "Asset id is unique: %s." % asset_id)
		asset_ids[asset_id] = true
		_check(
			_array_to_vector2i(asset.get("size_px", [])) == EXPECTED_TILE_SIZE,
			"%s is 128 × 128." % asset_id
		)
		_check(
			_array_to_vector2i(asset.get("footprint_cells", [])) == Vector2i.ONE,
			"%s has a strict 1 × 1 footprint." % asset_id
		)
		_check(
			String(asset.get("footprint_shape", "")) == "square",
			"%s declares a square logical footprint." % asset_id
		)
		_check(
			String(asset.get("alpha_mode", "")) == "opaque",
			"%s declares an opaque full-cell image." % asset_id
		)
		_check(
			String(asset.get("role", "")) == "cell_tile",
			"%s uses the cell_tile runtime role." % asset_id
		)
		_check(
			String(asset.get("visual_occupancy", "")) == "full_cell",
			"%s visually occupies the full cell." % asset_id
		)
		_check(asset.get("tags", null) is Array, "%s declares tags." % asset_id)
		_check(asset.get("generation", null) is Dictionary, "%s records generation provenance." % asset_id)
		_validate_generation_provenance(asset, asset_id)

	_check(asset_ids.has("marble_floor_01"), "Style Pack includes marble_floor_01.")
	_check(asset_ids.has("tree_01"), "Style Pack includes tree_01.")
	_check(asset_ids.has("wood_cabinet_01"), "Style Pack includes wood_cabinet_01.")
	_validate_expected_asset_metadata(style_pack)


func _validate_expected_asset_metadata(style_pack: Dictionary) -> void:
	var floor_asset := _find_asset(style_pack, "marble_floor_01")
	var tree_asset := _find_asset(style_pack, "tree_01")
	var cabinet_asset := _find_asset(style_pack, "wood_cabinet_01")
	_check(
		String(floor_asset.get("asset_type", "")) == "ground_range",
		"Marble uses the ground_range asset type."
	)
	_check(String(tree_asset.get("asset_type", "")) == "obstacle", "Tree uses the obstacle asset type.")
	_check(
		String(cabinet_asset.get("asset_type", "")) == "obstacle",
		"Cabinet uses the obstacle asset type."
	)
	_check(floor_asset.get("collision", null) == null, "Marble has no authored collision.")
	_validate_full_cell_authored_collision(tree_asset, "Tree")
	_validate_full_cell_authored_collision(cabinet_asset, "Cabinet")


func _validate_generation_provenance(asset: Dictionary, asset_id: String) -> void:
	var generation_value: Variant = asset.get("generation", {})
	if not generation_value is Dictionary:
		return
	var generation: Dictionary = generation_value
	_check(
		String(generation.get("tool", "")) == "builtin_imagegen",
		"%s records the built-in image generator." % asset_id
	)
	_check(String(generation.get("mode", "")) == "generate", "%s records opaque generation mode." % asset_id)
	_check(int(generation.get("revision", 0)) == 2, "%s records workflow revision 2." % asset_id)
	_check(not String(generation.get("prompt", "")).is_empty(), "%s records its complete final prompt." % asset_id)
	var postprocess := _string_array(generation.get("postprocess", []))
	_check(postprocess.has("lanczos_resize_128"), "%s records Lanczos normalization." % asset_id)
	_check(postprocess.has("force_rgb_opaque"), "%s records forced opaque RGB output." % asset_id)
	var uses_chroma_key: bool = false
	for step: String in postprocess:
		uses_chroma_key = uses_chroma_key or step.contains("chroma")
	_check(not uses_chroma_key, "%s no longer records chroma-key removal." % asset_id)


func _validate_full_cell_authored_collision(asset: Dictionary, label: String) -> void:
	var collision_value: Variant = asset.get("collision", {})
	_check(collision_value is Dictionary, "%s declares collision metadata." % label)
	if not collision_value is Dictionary:
		return
	var collision: Dictionary = collision_value
	_check(String(collision.get("shape", "")) == "rectangle", "%s collision is rectangular." % label)
	_check(
		_array_to_vector2i(collision.get("size_px", [])) == EXPECTED_TILE_SIZE,
		"%s authored collision spans 128 × 128 px." % label
	)
	_check(
		_array_to_vector2i(collision.get("offset_px", [])) == Vector2i.ZERO,
		"%s authored collision is centered." % label
	)


func _validate_asset_images(style_pack: Dictionary) -> void:
	var assets_value: Variant = style_pack.get("assets", [])
	if not assets_value is Array:
		return
	for asset_value: Variant in assets_value:
		if not asset_value is Dictionary:
			continue
		var asset: Dictionary = asset_value
		var asset_id := String(asset.get("id", ""))
		var texture_path := String(asset.get("texture_path", ""))
		_check(FileAccess.file_exists(texture_path), "%s texture exists." % asset_id)
		var image := _load_image(texture_path)
		_check(image != null, "%s texture can be decoded without import cache." % asset_id)
		if image == null:
			continue
		_check(
			Vector2i(image.get_size()) == EXPECTED_TILE_SIZE,
			"%s decoded size is 128 × 128." % asset_id
		)
		_check(_image_is_fully_opaque(image), "%s is fully opaque." % asset_id)
		if asset_id == "marble_floor_01":
			_check(
				_average_opposite_edge_difference(image) <= 0.08,
				"Marble opposite-edge mean color difference is at most 0.08."
			)


func _validate_scene_file_shape() -> void:
	_check(FileAccess.file_exists(SCENE_PATH), "Generated scene file exists.")
	if not FileAccess.file_exists(SCENE_PATH):
		return
	var file := FileAccess.open(SCENE_PATH, FileAccess.READ)
	_check(file != null, "Generated scene file is readable.")
	if file == null:
		return
	var scene_text := file.get_as_text()
	_check(scene_text.find("sub_resource type=\"Image\"") < 0, "Scene does not embed Image sub-resources.")
	_check(scene_text.find("PackedByteArray") < 0, "Scene does not embed PackedByteArray texture data.")


func _validate_runtime(scene_config: Dictionary) -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_check(packed_scene != null, "Generated scene loads as PackedScene.")
	if packed_scene == null:
		return
	var scene := packed_scene.instantiate()
	_check(scene != null, "Generated scene instantiates.")
	if scene == null:
		return
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var grid: GRID_SCRIPT = scene.get_node_or_null("UniversalTileGrid") as GRID_SCRIPT
	_check(grid != null, "Scene exposes UniversalTileGrid.")
	if grid == null:
		return

	_validate_determinism(grid, scene_config)
	var summary: Dictionary = grid.get_generation_summary()
	var tile_counts: Dictionary = summary.get("tile_counts", {})
	_check(int(summary.get("cell_count", 0)) == 24, "Runtime reports exactly 24 cells.")
	_check(int(summary.get("tile_count", 0)) == 24, "Runtime creates exactly 24 cell tiles.")
	_check(int(tile_counts.get("marble_floor_01", 0)) == 18, "Runtime creates 18 marble tiles.")
	_check(int(tile_counts.get("tree_01", 0)) == 3, "Runtime creates three tree tiles.")
	_check(int(tile_counts.get("wood_cabinet_01", 0)) == 3, "Runtime creates three cabinet tiles.")
	_check(int(summary.get("collision_count", 0)) == 6, "Runtime creates six blocking cells.")
	_check(int(summary.get("walkable_count", 0)) == 18, "Runtime reports 18 walkable cells.")
	_check(int(summary.get("blocked_count", 0)) == 6, "Runtime reports six blocked cells.")
	_check(bool(summary.get("full_grid", false)), "Runtime fills the complete 6 × 4 grid.")
	_check(bool(summary.get("mutually_exclusive", false)), "Runtime keeps exactly one tile per cell.")
	_check(bool(summary.get("perimeter_only", false)), "Runtime keeps all six obstacles on perimeter cells.")
	_check(bool(summary.get("overlap_free", false)), "Runtime keeps all six obstacle placements non-overlapping.")
	_check(int(summary.get("detail_count", -1)) == 0, "Detail layer is intentionally empty.")
	_validate_visual_style(summary)

	_validate_runtime_layers(grid)
	_validate_runtime_metadata(grid)
	_validate_runtime_collisions(grid.get_node_or_null("CollisionBodies") as Node2D)
	_validate_layer_visibility(grid)
	_validate_scene_ui(scene)


func _validate_determinism(grid: GRID_SCRIPT, scene_config: Dictionary) -> void:
	var base_seed := int(scene_config.get("base_seed", 0))
	var next_seed := base_seed + int(scene_config.get("seed_step", 0))
	grid.regenerate(base_seed)
	var first_signature := grid.get_layout_signature()
	var first_assignments := _compose_assignment_signature(grid)
	grid.regenerate(base_seed)
	var repeated_signature := grid.get_layout_signature()
	var repeated_assignments := _compose_assignment_signature(grid)
	grid.regenerate(next_seed)
	var next_signature := grid.get_layout_signature()
	var next_assignments := _compose_assignment_signature(grid)
	_check(not first_signature.is_empty(), "Layout signature is non-empty.")
	_check(first_signature.find("seed=") < 0, "Layout signature describes layout rather than echoing the seed.")
	_check(first_signature == repeated_signature, "Same seed produces the same layout signature.")
	_check(first_assignments == repeated_assignments, "Same seed produces identical cell assignments.")
	_check(first_signature != next_signature, "Next deterministic seed produces a different public layout signature.")
	_check(first_assignments != next_assignments, "Next deterministic seed changes the actual cell assignments.")
	grid.regenerate(base_seed)


func _compose_assignment_signature(grid: GRID_SCRIPT) -> String:
	var assignments := PackedStringArray()
	for y in range(EXPECTED_GRID_SIZE.y):
		for x in range(EXPECTED_GRID_SIZE.x):
			var metadata: Dictionary = grid.get_cell_metadata(Vector2i(x, y))
			var tile_value: Variant = metadata.get("tile", {})
			var asset_id := ""
			if tile_value is Dictionary:
				asset_id = String((tile_value as Dictionary).get("id", ""))
			assignments.append("%d,%d:%s" % [x, y, asset_id])
	return ";".join(assignments)


func _validate_runtime_layers(grid: GRID_SCRIPT) -> void:
	var cell_tile_layer := grid.get_node_or_null("CellTileLayer") as TileMapLayer
	var tile_visual_layer := grid.get_node_or_null("TileVisualLayer") as Node2D
	var collision_bodies := grid.get_node_or_null("CollisionBodies") as Node2D
	var collision_overlay := grid.get_node_or_null("CollisionOverlay") as Node2D
	var detail_layer := grid.get_node_or_null("DetailLayer") as Node2D
	var metadata_layer := grid.get_node_or_null("MetadataOverlay") as Node2D
	_check(cell_tile_layer != null, "CellTileLayer exists.")
	_check(tile_visual_layer != null, "TileVisualLayer exists.")
	_check(
		tile_visual_layer != null and tile_visual_layer.get_child_count() == 24,
		"TileVisualLayer contains exactly 24 code-shaped cells."
	)
	_check(collision_bodies != null, "CollisionBodies exists.")
	_check(
		collision_overlay != null and collision_overlay.get_child_count() == 6,
		"CollisionOverlay exists with six full-cell outlines."
	)
	_check(detail_layer != null and detail_layer.get_child_count() == 0, "DetailLayer exists and is empty.")
	_check(metadata_layer != null, "MetadataOverlay exists.")

	_check(grid.get_node_or_null("BaseLayer") == null, "Legacy BaseLayer is absent.")
	_check(grid.get_node_or_null("ShadowLayer") == null, "Legacy ShadowLayer is absent.")
	_check(grid.get_node_or_null("ObjectLayer") == null, "Legacy ObjectLayer is absent.")

	if cell_tile_layer == null:
		return
	var used_cells := cell_tile_layer.get_used_cells()
	_check(used_cells.size() == 24, "CellTileLayer has 24 used cells.")
	var unique_cells: Dictionary = {}
	var used_source_ids: Dictionary = {}
	var atlas_sources_valid: bool = cell_tile_layer.tile_set != null
	for cell: Vector2i in used_cells:
		unique_cells[cell] = true
		var source_id := cell_tile_layer.get_cell_source_id(cell)
		used_source_ids[source_id] = true
		if cell_tile_layer.tile_set == null:
			atlas_sources_valid = false
			continue
		var source := cell_tile_layer.tile_set.get_source(source_id)
		atlas_sources_valid = atlas_sources_valid and source is TileSetAtlasSource
	_check(unique_cells.size() == 24, "All 24 TileMap cells have unique coordinates.")
	_check(used_source_ids.size() == 3, "The grid uses one atlas source for each of the three tile images.")
	_check(atlas_sources_valid, "Every used cell resolves through a TileSetAtlasSource.")
	_check(cell_tile_layer.self_modulate.a <= 0.001, "Logical TileMap rendering is hidden behind the code-shaped skin.")
	_validate_visual_cells(tile_visual_layer, grid)


func _validate_visual_style(summary: Dictionary) -> void:
	var visual_value: Variant = summary.get("visual_style", {})
	_check(visual_value is Dictionary, "Runtime summary exposes visual_style.")
	if not visual_value is Dictionary:
		return
	var visual: Dictionary = visual_value
	_check(int(visual.get("rounded_cell_count", 0)) == 24, "All 24 cells use rounded code rendering.")
	_check(int(visual.get("obstacle_border_count", 0)) == 6, "All six obstacles receive content-colored borders.")
	_check(bool(visual.get("floor_edge_breathing", false)), "Floor edge breathing is enabled.")
	_check(float(visual.get("floor_corner_radius_px", 0.0)) > 0.0, "Floor cells have a positive corner radius.")
	_check(
		float(visual.get("obstacle_corner_radius_px", 0.0))
		> float(visual.get("floor_corner_radius_px", 0.0)),
		"Obstacle cells use the stronger rounded silhouette."
	)
	_check(float(visual.get("obstacle_border_width_px", 0.0)) >= 6.0, "Obstacle border width is visually legible.")
	_check(String(visual.get("render_source", "")) == "runtime_shader", "Rounded styling is produced by runtime code.")


func _validate_visual_cells(tile_visual_layer: Node2D, grid: GRID_SCRIPT) -> void:
	if tile_visual_layer == null:
		return
	var floor_count: int = 0
	var obstacle_count: int = 0
	for child: Node in tile_visual_layer.get_children():
		var sprite := child as Sprite2D
		_check(sprite != null, "Every code-shaped cell is a Sprite2D.")
		if sprite == null:
			continue
		var material := sprite.material as ShaderMaterial
		_check(material != null and material.shader != null, "%s uses the rounded-cell shader." % sprite.name)
		if material == null:
			continue
		var visual_role := String(sprite.get_meta("visual_role", ""))
		var border_width := float(sprite.get_meta("border_width_px", -1.0))
		var corner_radius := float(sprite.get_meta("corner_radius_px", 0.0))
		_check(corner_radius > 0.0, "%s has rounded corners." % sprite.name)
		_check(float(material.get_shader_parameter("wobble_strength_px")) > 0.0, "%s uses a non-straight contour." % sprite.name)
		if visual_role == "floor":
			floor_count += 1
			_check(is_zero_approx(border_width), "%s floor cell has no obstacle border." % sprite.name)
			_check(bool(sprite.get_meta("floor_edge_breathing", false)), "%s floor cell breathes at its edge." % sprite.name)
			_check(float(material.get_shader_parameter("floor_edge_width_px")) > 0.0, "%s floor edge band is present." % sprite.name)
			continue
		obstacle_count += 1
		_check(border_width > 0.0, "%s obstacle has a dark border." % sprite.name)
		_check(not bool(sprite.get_meta("floor_edge_breathing", true)), "%s obstacle does not reuse the floor pulse." % sprite.name)
		var content_color: Color = sprite.get_meta("content_main_color", Color.WHITE)
		var border_color: Color = sprite.get_meta("border_color", Color.WHITE)
		_check(_color_value(border_color) < _color_value(content_color), "%s border is darker than its content color." % sprite.name)
		_check(_dominant_channel(border_color) == _dominant_channel(content_color), "%s border keeps the content's dominant color channel." % sprite.name)
	_check(floor_count == 18, "Visual skin contains 18 breathing floor cells.")
	_check(obstacle_count == 6, "Visual skin contains six irregularly bordered obstacles.")

	grid.debug_prepare_capture()
	for child: Node in tile_visual_layer.get_children():
		var sprite := child as Sprite2D
		var material: ShaderMaterial = null
		if sprite != null:
			material = sprite.material as ShaderMaterial
		if material == null:
			continue
		_check(bool(material.get_shader_parameter("freeze_animation")), "%s can freeze its breathing phase for capture." % sprite.name)
		_check(is_equal_approx(float(material.get_shader_parameter("frozen_time")), 1.75), "%s uses the deterministic capture phase." % sprite.name)


func _validate_runtime_metadata(grid: GRID_SCRIPT) -> void:
	var counts: Dictionary = {}
	var seen_cells: Dictionary = {}
	for y in range(EXPECTED_GRID_SIZE.y):
		for x in range(EXPECTED_GRID_SIZE.x):
			var cell := Vector2i(x, y)
			var metadata: Dictionary = grid.get_cell_metadata(cell)
			_check(not metadata.is_empty(), "Cell (%d, %d) exposes metadata." % [x, y])
			_check(not seen_cells.has(cell), "Cell (%d, %d) metadata is unique." % [x, y])
			seen_cells[cell] = true
			_check(not metadata.has("base"), "Cell (%d, %d) has no legacy Base metadata." % [x, y])
			_check(not metadata.has("object"), "Cell (%d, %d) has no legacy Object metadata." % [x, y])
			var tile_value: Variant = metadata.get("tile", {})
			_check(tile_value is Dictionary, "Cell (%d, %d) exposes one tile object." % [x, y])
			if not tile_value is Dictionary:
				continue
			var tile: Dictionary = tile_value
			var asset_id := String(tile.get("id", ""))
			_check(EXPECTED_COUNTS.has(asset_id), "Cell (%d, %d) uses a known tile id." % [x, y])
			_check(
				String(metadata.get("asset_id", "")) == asset_id,
				"Cell (%d, %d) exposes one consistent asset id." % [x, y]
			)
			_check(
				String(metadata.get("cell_composition", "")) == "exclusive",
				"Cell (%d, %d) declares exclusive composition." % [x, y]
			)
			_check(
				String(tile.get("role", "")) == "cell_tile"
				and String(tile.get("visual_occupancy", "")) == "full_cell"
				and String(tile.get("alpha_mode", "")) == "opaque",
				"Cell (%d, %d) metadata describes one opaque full-cell tile." % [x, y]
			)
			counts[asset_id] = int(counts.get(asset_id, 0)) + 1
			_check(
				_array_to_vector2i(metadata.get("footprint_cells", [])) == Vector2i.ONE,
				"Cell (%d, %d) has a 1 × 1 footprint." % [x, y]
			)
			_validate_cell_collision_metadata(metadata, asset_id, cell)
	_check(seen_cells.size() == 24, "Metadata covers exactly 24 unique cells.")
	for asset_id: String in EXPECTED_COUNTS:
		_check(
			int(counts.get(asset_id, 0)) == int(EXPECTED_COUNTS[asset_id]),
			"Metadata count for %s is %d." % [asset_id, int(EXPECTED_COUNTS[asset_id])]
		)


func _validate_cell_collision_metadata(metadata: Dictionary, asset_id: String, cell: Vector2i) -> void:
	var layers := _string_array(metadata.get("layers", []))
	var collision_value: Variant = metadata.get("collision", {})
	var collision: Dictionary = collision_value if collision_value is Dictionary else {}
	_check(layers.has(LAYER_CELL_TILES), "Cell %s belongs to the cell_tiles layer." % cell)
	if asset_id == "marble_floor_01":
		_check(String(collision.get("shape", "none")) == "none", "Marble cell %s is not blocking." % cell)
		_check(not layers.has(LAYER_COLLISION), "Marble cell %s has no collision layer." % cell)
		return
	_check(String(collision.get("shape", "")) == "rectangle", "Obstacle cell %s uses rectangle collision." % cell)
	_check(_is_perimeter_cell(cell), "Obstacle cell %s is on the grid perimeter." % cell)
	_check(
		_array_to_vector2i(collision.get("size_px", [])) == EXPECTED_TILE_SIZE,
		"Obstacle cell %s blocks the full 128 × 128 tile." % cell
	)
	_check(
		_array_to_vector2i(collision.get("offset_px", [])) == Vector2i.ZERO,
		"Obstacle cell %s has centered full-cell collision." % cell
	)
	_check(layers.has(LAYER_COLLISION), "Obstacle cell %s belongs to the collision layer." % cell)


func _validate_runtime_collisions(collision_bodies: Node2D) -> void:
	_check(collision_bodies != null, "CollisionBodies exists for physics validation.")
	if collision_bodies == null:
		return
	_check(collision_bodies.get_child_count() == 6, "CollisionBodies contains six blockers.")
	var occupied_cells: Dictionary = {}
	var asset_counts: Dictionary = {}
	for child: Node in collision_bodies.get_children():
		var body := child as StaticBody2D
		_check(body != null, "Every collision child is StaticBody2D.")
		if body == null:
			continue
		var shape_node := body.get_node_or_null("Shape") as CollisionShape2D
		var rectangle := shape_node.shape as RectangleShape2D if shape_node != null else null
		_check(rectangle != null, "Every blocker uses RectangleShape2D.")
		if rectangle == null or shape_node == null:
			continue
		_check(Vector2i(rectangle.size) == EXPECTED_TILE_SIZE, "Every blocker spans 128 × 128 px.")
		_check(Vector2i(shape_node.position) == Vector2i.ZERO, "Every blocker is centered in its cell.")
		var cell_value: Variant = body.get_meta("cell", Vector2i(-1, -1))
		var cell: Vector2i = cell_value if cell_value is Vector2i else Vector2i(-1, -1)
		_check(not occupied_cells.has(cell), "Every blocking cell is unique: %s." % cell)
		occupied_cells[cell] = true
		var asset_id := String(body.get_meta("asset_id", ""))
		asset_counts[asset_id] = int(asset_counts.get(asset_id, 0)) + 1
	_check(occupied_cells.size() == 6, "Exactly six unique cells are blocking.")
	_check(int(asset_counts.get("tree_01", 0)) == 3, "Three tree cells are blocking.")
	_check(int(asset_counts.get("wood_cabinet_01", 0)) == 3, "Three cabinet cells are blocking.")


func _validate_layer_visibility(grid: GRID_SCRIPT) -> void:
	var layer_nodes: Dictionary = {
		LAYER_CELL_TILES: [grid.get_node_or_null("CellTileLayer"), grid.get_node_or_null("TileVisualLayer")],
		LAYER_COLLISION: [grid.get_node_or_null("CollisionOverlay")],
		LAYER_DETAIL: [grid.get_node_or_null("DetailLayer")],
		LAYER_METADATA: [grid.get_node_or_null("MetadataOverlay")],
	}
	var collision_bodies := grid.get_node_or_null("CollisionBodies") as Node2D
	for layer_id: String in layer_nodes:
		var nodes: Array = layer_nodes[layer_id]
		var layers: Array[CanvasItem] = []
		for node_value: Variant in nodes:
			var candidate := node_value as CanvasItem
			_check(candidate != null, "%s visibility layer exists." % layer_id)
			if candidate != null:
				layers.append(candidate)
		if layers.is_empty():
			continue
		grid.set_layer_visible(layer_id, false)
		for layer: CanvasItem in layers:
			_check(not layer.visible, "%s layer can be hidden independently." % layer_id)
		if layer_id == LAYER_COLLISION and collision_bodies != null:
			_check(collision_bodies.visible, "Collision visibility only hides the overlay, not physics bodies.")
		grid.set_layer_visible(layer_id, true)
		for layer: CanvasItem in layers:
			_check(layer.visible, "%s layer can be shown independently." % layer_id)


func _color_value(color: Color) -> float:
	return maxf(color.r, maxf(color.g, color.b))


func _dominant_channel(color: Color) -> int:
	if color.r >= color.g and color.r >= color.b:
		return 0
	if color.g >= color.r and color.g >= color.b:
		return 1
	return 2


func _validate_scene_ui(scene: Node) -> void:
	var toggle_root := "Sidebar/Margin/Rows/LayerToggles/"
	for toggle_name: String in ["CellTilesToggle", "CollisionToggle", "DetailToggle", "MetadataToggle"]:
		_check(
			scene.get_node_or_null(toggle_root + toggle_name) is CheckButton,
			"Scene exposes %s." % toggle_name
		)
	for legacy_name: String in ["BaseToggle", "ShadowToggle", "ObjectToggle"]:
		_check(
			scene.get_node_or_null(toggle_root + legacy_name) == null,
			"Legacy %s is absent." % legacy_name
		)


func _image_is_fully_opaque(image: Image) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a < 0.999:
				return false
	return true


func _average_opposite_edge_difference(image: Image) -> float:
	var difference_sum: float = 0.0
	var sample_count: int = 0
	var width := image.get_width()
	var height := image.get_height()
	for x in range(width):
		difference_sum += _rgb_difference(image.get_pixel(x, 0), image.get_pixel(x, height - 1))
		sample_count += 1
	for y in range(height):
		difference_sum += _rgb_difference(image.get_pixel(0, y), image.get_pixel(width - 1, y))
		sample_count += 1
	return difference_sum / float(maxi(sample_count, 1))


func _rgb_difference(first: Color, second: Color) -> float:
	return (absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)) / 3.0


func _find_asset(style_pack: Dictionary, asset_id: String) -> Dictionary:
	var assets_value: Variant = style_pack.get("assets", [])
	if not assets_value is Array:
		return {}
	for asset_value: Variant in assets_value:
		if asset_value is Dictionary and String((asset_value as Dictionary).get("id", "")) == asset_id:
			return (asset_value as Dictionary).duplicate(true)
	return {}


func _load_image(path: String) -> Image:
	if path.is_empty():
		return null
	var image := Image.new()
	var resolved_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	if image.load(resolved_path) != OK:
		return null
	return image


func _load_json_dictionary(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _array_to_vector2i(value: Variant) -> Vector2i:
	if not value is Array or (value as Array).size() != 2:
		return Vector2i.ZERO
	var values: Array = value
	return Vector2i(int(values[0]), int(values[1]))


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value:
		result.append(String(item))
	return result


func _is_perimeter_cell(cell: Vector2i) -> bool:
	return (
		cell.x == 0
		or cell.y == 0
		or cell.x == EXPECTED_GRID_SIZE.x - 1
		or cell.y == EXPECTED_GRID_SIZE.y - 1
	)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures.append(message)
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("AI_UNIVERSAL_TILE_SMOKE_OK")
		quit(0)
		return
	push_error("AI universal Tile smoke failed with %d issue(s)." % _failures.size())
	quit(1)
