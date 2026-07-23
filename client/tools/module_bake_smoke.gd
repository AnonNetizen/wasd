extends SceneTree
## Focused JSON -> generated TSCN bake regressions without touching tracked files.

const MODULE_SCENE_BAKER := preload("res://scripts/editor/module_scene_baker.gd")

const MODULE_ID: String = "module_start_cross"
const MODULE_PATH: String = "res://data/modules/module_start_cross.json"
const GENERATED_PATH: String = (
	"res://scenes/generated/modules/module_start_cross/rotation_0.tscn"
)
const EDGE_PATHS: Array[String] = [
	"EdgeSeals/North",
	"EdgeSeals/East",
	"EdgeSeals/South",
	"EdgeSeals/West",
]

var _failures: PackedStringArray = []
var _assertions: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry: Dictionary = _read_json(
		"res://data/module_templates.json"
	)
	var entry: Dictionary = _registry_entry(registry, MODULE_ID)
	var context: Dictionary = MODULE_SCENE_BAKER._build_context(entry)
	_expect(bool(context.get("ok", false)), "base module context should validate")
	if bool(context.get("ok", false)):
		_test_rotations(context)
		_test_visual_transform(context)
		_test_edge_masks(context)
		_test_artifact_fingerprint(context)
		_test_stale_approval(entry)
	for failure: String in _failures:
		printerr("[module-bake-smoke] %s" % failure)
	print(
		"[module-bake-smoke] ok=%s assertions=%d"
		% [str(_failures.is_empty()).to_lower(), _assertions]
	)
	quit(0 if _failures.is_empty() else 1)


func _test_rotations(context: Dictionary) -> void:
	var expected_cells: Dictionary = {
		0: Vector2i(5, 5),
		90: Vector2i(5, 5),
		180: Vector2i(5, 5),
		270: Vector2i(5, 5),
	}
	for rotation: int in [0, 90, 180, 270]:
		var root: GeneratedModuleScene = MODULE_SCENE_BAKER._build_generated_scene(
			context,
			rotation
		)
		_expect(root != null, "rotation %d should build" % rotation)
		if root == null:
			continue
		var ground: TileMapLayer = root.get_node("Ground") as TileMapLayer
		var collision: CollisionShape2D = root.get_node(
			"TerrainCollision/MergedBlockedCells"
		) as CollisionShape2D
		_expect(
			ground.get_used_cells().size() == 121,
			"rotation %d must contain all ground cells" % rotation
		)
		_expect(
			collision.shape is ConcavePolygonShape2D
			and not (collision.shape as ConcavePolygonShape2D).get_segments().is_empty(),
			"rotation %d must contain merged collision" % rotation
		)
		var placement: Dictionary = root.placement_snapshot[0]
		_expect(
			_cell(placement.get("cell", {})) == expected_cells[rotation],
			"rotation %d must bake placement snapshot" % rotation
		)
		root.free()


func _test_visual_transform(context: Dictionary) -> void:
	var transformed_context: Dictionary = context.duplicate(true)
	var module_data: Dictionary = (
		transformed_context.get("module_data", {}) as Dictionary
	)
	var layers: Dictionary = module_data.get("visual_layers", {}) as Dictionary
	var decoration: Dictionary = layers.get("decoration", {}) as Dictionary
	decoration["cells"] = [
		{
			"cell": {"x": 2, "y": 3},
			"tile_id": "module_tile_decoration_default",
			"rotation": 90,
			"flip_h": true,
			"flip_v": false,
		}
	]
	var root: GeneratedModuleScene = MODULE_SCENE_BAKER._build_generated_scene(
		transformed_context,
		90
	)
	var decoration_layer: TileMapLayer = root.get_node(
		"Decoration"
	) as TileMapLayer
	var rotated_cell := Vector2i(7, 2)
	var expected_flags: int = MODULE_SCENE_BAKER._compose_transform_flags(
		MODULE_SCENE_BAKER._rotation_transform_flags(90),
		MODULE_SCENE_BAKER._visual_transform_flags(90, true, false)
	)
	_expect(
		decoration_layer.get_cell_alternative_tile(rotated_cell)
		== expected_flags,
		"visual cell transform flags must compose with module rotation"
	)
	root.free()


func _test_edge_masks(context: Dictionary) -> void:
	var root: GeneratedModuleScene = MODULE_SCENE_BAKER._build_generated_scene(
		context,
		0
	)
	var edge_ids: Array[String] = [
		"edge_north",
		"edge_east",
		"edge_south",
		"edge_west",
	]
	for mask: int in range(16):
		var enabled_edges: Array[String] = []
		for edge_index: int in range(4):
			if mask & (1 << edge_index):
				enabled_edges.append(edge_ids[edge_index])
		root.set_masked_edges(enabled_edges)
		for edge_index: int in range(4):
			var edge_root: Node2D = root.get_node(
				EDGE_PATHS[edge_index]
			) as Node2D
			_expect(
				edge_root.visible == bool(mask & (1 << edge_index)),
				"edge mask %d must toggle %s" % [mask, EDGE_PATHS[edge_index]]
			)
	root.free()


func _test_artifact_fingerprint(context: Dictionary) -> void:
	var expected: GeneratedModuleScene = MODULE_SCENE_BAKER._build_generated_scene(
		context,
		0
	)
	_expect(
		MODULE_SCENE_BAKER._generated_artifact_matches(
			GENERATED_PATH,
			expected
		),
		"checked-in generated scene must match in-memory fingerprint"
	)
	var temporary_path: String = "user://module_bake_smoke_modified.tscn"
	var save_error: String = MODULE_SCENE_BAKER._save_generated_scene(
		temporary_path,
		expected
	)
	_expect(save_error.is_empty(), "temporary generated scene should save")
	var packed: PackedScene = load(temporary_path) as PackedScene
	var modified: Node = packed.instantiate()
	var extra := Node2D.new()
	extra.name = "ManualEdit"
	modified.add_child(extra)
	extra.owner = modified
	var modified_packed := PackedScene.new()
	modified_packed.pack(modified)
	ResourceSaver.save(modified_packed, temporary_path)
	modified.free()
	_expect(
		not MODULE_SCENE_BAKER._generated_artifact_matches(
			temporary_path,
			expected
		),
		"manual generated TSCN edits must invalidate the fingerprint"
	)
	_expect(
		not MODULE_SCENE_BAKER._generated_artifact_matches(
			"user://module_bake_smoke_missing.tscn",
			expected
		),
		"missing generated rotation must fail the fingerprint check"
	)
	expected.free()


func _test_stale_approval(entry: Dictionary) -> void:
	var stale_entry: Dictionary = entry.duplicate(true)
	stale_entry["review_status"] = "module_review_approved"
	stale_entry["approved_gameplay_hash"] = "0".repeat(64)
	var result: Dictionary = MODULE_SCENE_BAKER._bake_entry(
		stale_entry,
		false
	)
	_expect(
		not bool(result.get("ok", false))
		and "\n".join(
			result.get("errors", PackedStringArray()) as PackedStringArray
		).contains("approval hash is stale"),
		"stale gameplay approval hash must fail a no-write bake check"
	)


func _registry_entry(registry: Dictionary, module_id: String) -> Dictionary:
	for entry_value: Variant in registry.get("templates", []) as Array:
		if (
			entry_value is Dictionary
			and String((entry_value as Dictionary).get("id", "")) == module_id
		):
			return (entry_value as Dictionary).duplicate(true)
	return {}


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("failed to read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _cell(value: Variant) -> Vector2i:
	if not value is Dictionary:
		return Vector2i(-1, -1)
	var cell: Dictionary = value as Dictionary
	return Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))


func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(message)
