extends SceneTree

const CONFIG_PATH: String = "res://data/ai_universal_tile_test.json"
const EXPECTED_GRID_SIZE: Vector2i = Vector2i(6, 4)
const EXPECTED_TILE_SIZE: Vector2i = Vector2i(128, 128)
const GRID_SCRIPT := preload("res://scripts/universal_tile_grid.gd")
const SCENE_PATH: String = "res://scenes/ai_universal_tile_test.tscn"
const SUPPORTED_SCHEMA_VERSION: int = 1

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
	_check(int(scene_config.get("schema_version", 0)) == SUPPORTED_SCHEMA_VERSION, "Scene config schema_version is 1.")
	_check(_array_to_vector2i(scene_config.get("grid_size", [])) == EXPECTED_GRID_SIZE, "Scene grid is 6 × 4.")
	_check(_array_to_vector2i(scene_config.get("tile_size_px", [])) == EXPECTED_TILE_SIZE, "Scene tile size is 128 × 128.")
	_check(int(scene_config.get("base_seed", 0)) == 20_260_711, "Base seed is 20260711.")
	_check(int(scene_config.get("seed_step", 0)) == 7_919, "Seed step is 7919.")
	_check(String(scene_config.get("base_fill_asset_id", "")) == "marble_floor_01", "Base fill uses marble_floor_01.")

	_check(not scene_config.has("tile_types"), "Scene composition has no duplicate tile_types authority.")
	var generation_rules_value: Variant = scene_config.get("generation_rules", {})
	_check(generation_rules_value is Dictionary, "Scene config has generation_rules.")
	if not generation_rules_value is Dictionary:
		return
	var generation_rules: Dictionary = generation_rules_value
	_check(String(generation_rules.get("placement_zone", "")) == "perimeter", "Objects are constrained to perimeter cells.")
	_check(not bool(generation_rules.get("allow_overlap", true)), "Object overlap is disabled.")
	var counts: Dictionary = {}
	var placements_value: Variant = generation_rules.get("placements", [])
	if placements_value is Array:
		for placement_value: Variant in placements_value:
			if placement_value is Dictionary:
				var placement: Dictionary = placement_value
				counts[String(placement.get("asset_id", ""))] = int(placement.get("count", 0))
	_check(int(counts.get("tree_01", 0)) == 3, "Generation requests three trees.")
	_check(int(counts.get("wood_cabinet_01", 0)) == 3, "Generation requests three cabinets.")


func _validate_style_pack(style_pack: Dictionary) -> void:
	_check(int(style_pack.get("schema_version", 0)) == SUPPORTED_SCHEMA_VERSION, "Style Pack schema_version is 1.")
	_check(not String(style_pack.get("style_id", "")).is_empty(), "Style Pack has a style_id.")
	_check(String(style_pack.get("projection", "")) == "orthographic_top_down", "Style Pack projection is top-down orthographic.")
	_check(_array_to_vector2i(style_pack.get("tile_size_px", [])) == EXPECTED_TILE_SIZE, "Style Pack tile size is 128 × 128.")
	_check(style_pack.get("palette", null) is Dictionary, "Style Pack declares a palette.")
	_check(style_pack.get("lighting", null) is Dictionary, "Style Pack declares unified lighting.")

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
		_check(_array_to_vector2i(asset.get("size_px", [])) == EXPECTED_TILE_SIZE, "%s is 128 × 128." % asset_id)
		_check(_array_to_vector2i(asset.get("footprint_cells", [])) == Vector2i.ONE, "%s has a strict 1 × 1 footprint." % asset_id)
		_check(String(asset.get("footprint_shape", "")) == "square", "%s declares a square logical footprint." % asset_id)
		_check(_array_to_vector2i(asset.get("anchor_point_px", [])) == Vector2i(64, 64), "%s uses the centered single-cell anchor." % asset_id)
		_check(asset.get("tags", null) is Array, "%s declares tags." % asset_id)
		_check(asset.get("generation", null) is Dictionary, "%s records generation provenance." % asset_id)

	_check(asset_ids.has("marble_floor_01"), "Style Pack includes marble_floor_01.")
	_check(asset_ids.has("tree_01"), "Style Pack includes tree_01.")
	_check(asset_ids.has("wood_cabinet_01"), "Style Pack includes wood_cabinet_01.")
	_validate_expected_asset_metadata(style_pack)


func _validate_expected_asset_metadata(style_pack: Dictionary) -> void:
	var floor_asset := _find_asset(style_pack, "marble_floor_01")
	var tree_asset := _find_asset(style_pack, "tree_01")
	var cabinet_asset := _find_asset(style_pack, "wood_cabinet_01")
	_check(String(floor_asset.get("role", "")) == "base", "Marble is a Base asset.")
	_check(String(floor_asset.get("asset_type", "")) == "ground_range", "Marble uses the ground_range asset type.")
	_check(String(floor_asset.get("alpha_mode", "")) == "opaque", "Marble is opaque.")
	_check(String(floor_asset.get("repeat_mode", "")) == "seamless", "Marble declares seamless repeat.")
	_check(String(tree_asset.get("role", "")) == "object", "Tree is an Object asset.")
	_check(String(tree_asset.get("asset_type", "")) == "obstacle", "Tree uses the obstacle asset type.")
	_check(String(cabinet_asset.get("role", "")) == "object", "Cabinet is an Object asset.")
	_check(String(cabinet_asset.get("asset_type", "")) == "obstacle", "Cabinet uses the obstacle asset type.")

	var tree_collision: Dictionary = tree_asset.get("collision", {})
	_check(String(tree_collision.get("shape", "")) == "circle", "Tree collision is circular.")
	_check(is_equal_approx(float(tree_collision.get("radius_px", 0.0)), 26.0), "Tree collision radius is 26 px.")
	_check(_array_to_vector2i(tree_collision.get("offset_px", [])) == Vector2i(0, 18), "Tree collision offset is (0, 18).")
	var tree_shadow: Dictionary = tree_asset.get("shadow", {})
	_check(String(tree_shadow.get("shape", "")) == "ellipse", "Tree shadow shape is elliptical.")
	_check(_array_to_vector2i(tree_shadow.get("size_px", [])) == Vector2i(88, 44), "Tree shadow ellipse is 88 × 44 px.")
	_check(_array_to_vector2i(tree_shadow.get("offset_px", [])) == Vector2i(10, 16), "Tree shadow offset is (10, 16).")
	_check(is_equal_approx(float(tree_shadow.get("opacity", 0.0)), 0.28), "Tree shadow opacity is 0.28.")

	var cabinet_collision: Dictionary = cabinet_asset.get("collision", {})
	_check(String(cabinet_collision.get("shape", "")) == "rectangle", "Cabinet collision is rectangular.")
	_check(_array_to_vector2i(cabinet_collision.get("size_px", [])) == Vector2i(84, 58), "Cabinet collision size is 84 × 58 px.")
	_check(_array_to_vector2i(cabinet_collision.get("offset_px", [])) == Vector2i(0, 14), "Cabinet collision offset is (0, 14).")
	var cabinet_shadow: Dictionary = cabinet_asset.get("shadow", {})
	_check(String(cabinet_shadow.get("shape", "")) == "ellipse", "Cabinet shadow shape is elliptical.")
	_check(_array_to_vector2i(cabinet_shadow.get("size_px", [])) == Vector2i(92, 38), "Cabinet shadow ellipse is 92 × 38 px.")
	_check(_array_to_vector2i(cabinet_shadow.get("offset_px", [])) == Vector2i(8, 18), "Cabinet shadow offset is (8, 18).")
	_check(is_equal_approx(float(cabinet_shadow.get("opacity", 0.0)), 0.24), "Cabinet shadow opacity is 0.24.")
	var cabinet_interaction: Dictionary = cabinet_asset.get("interaction", {})
	_check(bool(cabinet_interaction.get("interactable", false)), "Cabinet is marked interactable.")
	_check(bool(cabinet_interaction.get("lootable", false)), "Cabinet is marked lootable.")


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
		_check(Vector2i(image.get_size()) == EXPECTED_TILE_SIZE, "%s decoded size is 128 × 128." % asset_id)
		if asset_id == "marble_floor_01":
			_validate_floor_image(image)
		else:
			_validate_object_image(image, asset_id)


func _validate_floor_image(image: Image) -> void:
	var opaque: bool = true
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a < 0.999:
				opaque = false
				break
		if not opaque:
			break
	_check(opaque, "Marble floor is fully opaque.")
	var edge_difference := _average_opposite_edge_difference(image)
	_check(edge_difference <= 0.08, "Marble opposite-edge mean RGB difference is ≤ 0.08 (actual %.4f)." % edge_difference)


func _validate_object_image(image: Image, asset_id: String) -> void:
	var corner_alpha := maxf(
		maxf(image.get_pixel(0, 0).a, image.get_pixel(image.get_width() - 1, 0).a),
		maxf(image.get_pixel(0, image.get_height() - 1).a, image.get_pixel(image.get_width() - 1, image.get_height() - 1).a)
	)
	_check(corner_alpha <= 0.05, "%s corner alpha is ≤ 0.05." % asset_id)
	var visible_pixels: int = 0
	var magenta_pixels: int = 0
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	var pixel_count := image.get_width() * image.get_height()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a > 0.05:
				visible_pixels += 1
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
				if color.r > 0.80 and color.b > 0.80 and color.g < 0.24:
					magenta_pixels += 1
	var coverage := float(visible_pixels) / float(pixel_count)
	var magenta_ratio := float(magenta_pixels) / float(maxi(visible_pixels, 1))
	_check(coverage >= 0.20 and coverage <= 0.80, "%s alpha coverage is 20%%–80%% (actual %.2f%%)." % [asset_id, coverage * 100.0])
	if visible_pixels > 0:
		var minimum_margin := mini(
			mini(min_x, min_y),
			mini(image.get_width() - 1 - max_x, image.get_height() - 1 - max_y)
		)
		_check(minimum_margin >= 8, "%s keeps at least an 8 px alpha safety margin (actual %d px)." % [asset_id, minimum_margin])
	_check(magenta_ratio <= 0.002, "%s has no material chroma-key residue (actual %.3f%%)." % [asset_id, magenta_ratio * 100.0])


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

	var base_seed := int(scene_config.get("base_seed", 0))
	var next_seed := base_seed + int(scene_config.get("seed_step", 0))
	grid.regenerate(base_seed)
	var first_signature := grid.get_layout_signature()
	grid.regenerate(base_seed)
	var repeated_signature := grid.get_layout_signature()
	grid.regenerate(next_seed)
	var next_signature := grid.get_layout_signature()
	_check(not first_signature.is_empty(), "Layout signature is non-empty.")
	_check(first_signature == repeated_signature, "Same seed produces the same layout signature.")
	_check(first_signature != next_signature, "Next deterministic seed produces a different layout signature.")
	grid.regenerate(base_seed)

	var summary := grid.get_generation_summary()
	var object_counts: Dictionary = summary.get("object_counts", {})
	_check(int(summary.get("base_cell_count", 0)) == 24, "Runtime creates 24 Base cells.")
	_check(int(summary.get("object_count", 0)) == 6, "Runtime creates six objects.")
	_check(int(object_counts.get("tree_01", 0)) == 3, "Runtime creates three trees.")
	_check(int(object_counts.get("wood_cabinet_01", 0)) == 3, "Runtime creates three cabinets.")
	_check(int(summary.get("collision_count", 0)) == 6, "Runtime creates six collision bodies.")
	_check(bool(summary.get("perimeter_only", false)), "All runtime objects are on perimeter cells.")
	_check(bool(summary.get("overlap_free", false)), "Runtime object cells do not overlap.")
	_check(int(summary.get("detail_count", -1)) == 0, "Detail layer is intentionally empty.")

	var base_layer := grid.get_node_or_null("BaseLayer") as TileMapLayer
	var shadow_layer := grid.get_node_or_null("ShadowLayer") as Node2D
	var object_layer := grid.get_node_or_null("ObjectLayer") as Node2D
	var detail_layer := grid.get_node_or_null("DetailLayer") as Node2D
	var collision_layer := grid.get_node_or_null("CollisionLayer") as Node2D
	var metadata_overlay := grid.get_node_or_null("MetadataOverlay") as Node2D
	_check(base_layer != null and base_layer.get_used_cells().size() == 24, "Base uses TileMapLayer with 24 used cells.")
	if base_layer != null and base_layer.tile_set != null:
		var source_id := int(base_layer.get_meta("atlas_source_id", -1))
		var atlas_source := base_layer.tile_set.get_source(source_id) as TileSetAtlasSource
		_check(atlas_source != null, "Base TileMapLayer uses a TileSetAtlasSource.")
	_check(shadow_layer != null and shadow_layer.get_child_count() == 6, "Shadow layer has six procedural shadows.")
	_check(object_layer != null and object_layer.get_child_count() == 6, "Object layer has six sprites.")
	_check(detail_layer != null and detail_layer.get_child_count() == 0, "Detail layer has no children.")
	_check(collision_layer != null and collision_layer.get_child_count() == 6, "Collision layer has six bodies.")
	_check(metadata_overlay != null, "Metadata overlay exists separately.")

	_validate_runtime_metadata(grid)
	_validate_runtime_collisions(collision_layer)
	_validate_layer_visibility(grid)


func _validate_runtime_metadata(grid: GRID_SCRIPT) -> void:
	var base_only_count: int = 0
	var tree_count: int = 0
	var cabinet_count: int = 0
	for y in range(EXPECTED_GRID_SIZE.y):
		for x in range(EXPECTED_GRID_SIZE.x):
			var metadata := grid.get_cell_metadata(Vector2i(x, y))
			_check(not metadata.is_empty(), "Cell (%d, %d) exposes metadata." % [x, y])
			var base: Dictionary = metadata.get("base", {})
			_check(String(base.get("id", "")) == "marble_floor_01", "Cell (%d, %d) reports marble Base metadata." % [x, y])
			var object_metadata: Dictionary = metadata.get("object", {})
			match String(object_metadata.get("id", "")):
				"":
					base_only_count += 1
				"tree_01":
					tree_count += 1
					var collision: Dictionary = metadata.get("collision", {})
					_check(String(collision.get("shape", "")) == "circle", "Tree cell reports circle collision metadata.")
				"wood_cabinet_01":
					cabinet_count += 1
					var interaction: Dictionary = metadata.get("interaction", {})
					_check(bool(interaction.get("interactable", false)), "Cabinet cell reports interactable metadata.")
					_check(bool(interaction.get("lootable", false)), "Cabinet cell reports lootable metadata.")
				_:
					_check(false, "Cell reports only one of the three declared tile types.")
	_check(base_only_count == 18, "Exactly 18 cells are Base-only.")
	_check(tree_count == 3, "Exactly three cells carry tree metadata.")
	_check(cabinet_count == 3, "Exactly three cells carry cabinet metadata.")


func _validate_runtime_collisions(collision_layer: Node2D) -> void:
	if collision_layer == null:
		return
	var tree_count: int = 0
	var cabinet_count: int = 0
	for child: Node in collision_layer.get_children():
		var body := child as StaticBody2D
		_check(body != null, "Every collision layer child is StaticBody2D.")
		if body == null:
			continue
		var shape_node := body.get_node_or_null("Shape") as CollisionShape2D
		_check(shape_node != null and shape_node.shape != null, "Every object collision has a shape.")
		if shape_node == null or shape_node.shape == null:
			continue
		match String(body.get_meta("asset_id", "")):
			"tree_01":
				tree_count += 1
				var circle := shape_node.shape as CircleShape2D
				_check(circle != null and is_equal_approx(circle.radius, 26.0), "Tree runtime collision radius is 26 px.")
				_check(Vector2i(shape_node.position) == Vector2i(0, 18), "Tree runtime collision offset is (0, 18).")
			"wood_cabinet_01":
				cabinet_count += 1
				var rectangle := shape_node.shape as RectangleShape2D
				_check(rectangle != null and Vector2i(rectangle.size) == Vector2i(84, 58), "Cabinet runtime collision is 84 × 58 px.")
				_check(Vector2i(shape_node.position) == Vector2i(0, 14), "Cabinet runtime collision offset is (0, 14).")
			_:
				_check(false, "Collision body has a known asset id.")
	_check(tree_count == 3 and cabinet_count == 3, "Collision layer maps to three trees and three cabinets.")


func _validate_layer_visibility(grid: GRID_SCRIPT) -> void:
	var layer_nodes: Dictionary = {
		GRID_SCRIPT.LAYER_BASE: grid.get_node_or_null("BaseLayer"),
		GRID_SCRIPT.LAYER_SHADOW: grid.get_node_or_null("ShadowLayer"),
		GRID_SCRIPT.LAYER_OBJECT: grid.get_node_or_null("ObjectLayer"),
		GRID_SCRIPT.LAYER_DETAIL: grid.get_node_or_null("DetailLayer"),
		GRID_SCRIPT.LAYER_METADATA: grid.get_node_or_null("MetadataOverlay"),
	}
	for layer_id: String in layer_nodes:
		var layer := layer_nodes[layer_id] as CanvasItem
		_check(layer != null, "%s visibility layer exists." % layer_id)
		if layer == null:
			continue
		grid.set_layer_visible(layer_id, false)
		_check(not layer.visible, "%s layer can be hidden independently." % layer_id)
		grid.set_layer_visible(layer_id, true)
		_check(layer.visible, "%s layer can be shown independently." % layer_id)


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
