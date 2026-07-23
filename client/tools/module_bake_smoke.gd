extends SceneTree
## Focused JSON -> generated TSCN bake regressions without touching tracked files.

const MODULE_SCENE_BAKER := preload("res://scripts/editor/module_scene_baker.gd")
const MODULE_CHUNK_SCRIPT := preload("res://scripts/gameplay/module_chunk.gd")

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
		_test_canonical_scene(context)
		_test_runtime_rotations(context)
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


func _test_canonical_scene(context: Dictionary) -> void:
	var root: GeneratedModuleScene = MODULE_SCENE_BAKER._build_generated_scene(
		context
	)
	_expect(root != null, "canonical scene should build")
	if root == null:
		return
	var ground: TileMapLayer = root.get_node("Ground") as TileMapLayer
	var collision: CollisionShape2D = root.get_node(
		"TerrainCollision/MergedBlockedCells"
	) as CollisionShape2D
	_expect(
		root.module_rotation_degrees == 0,
		"generated metadata must describe the canonical zero-degree scene"
	)
	_expect(
		ground.get_used_cells().size() == 121,
		"canonical scene must contain all ground cells"
	)
	_expect(
		collision.shape is ConcavePolygonShape2D
		and not (collision.shape as ConcavePolygonShape2D).get_segments().is_empty(),
		"canonical scene must contain merged collision"
	)
	var placement: Dictionary = root.placement_snapshot[0]
	_expect(
		_cell(placement.get("cell", {})) == Vector2i(5, 5),
		"canonical scene must retain the source placement snapshot"
	)
	_expect(
		MODULE_SCENE_BAKER._obsolete_generated_scene_paths(MODULE_ID).is_empty(),
		"only the canonical generated scene may remain on disk"
	)
	root.free()


func _test_runtime_rotations(context: Dictionary) -> void:
	var canonical: GeneratedModuleScene = MODULE_SCENE_BAKER._build_generated_scene(
		context
	)
	var packed := PackedScene.new()
	_expect(packed.pack(canonical) == OK, "canonical scene should pack for chunk tests")
	canonical.free()
	var expected_positions: Dictionary = {
		0: Vector2.ZERO,
		90: Vector2(1600.0, 0.0),
		180: Vector2(1600.0, 1600.0),
		270: Vector2(0.0, 1600.0),
	}
	var expected_points: Dictionary = {
		0: Vector2(320.0, 480.0),
		90: Vector2(1120.0, 320.0),
		180: Vector2(1280.0, 1120.0),
		270: Vector2(480.0, 1280.0),
	}
	var expected_local_seals: Dictionary = {
		0: "North",
		90: "West",
		180: "South",
		270: "East",
	}
	for rotation: int in [0, 90, 180, 270]:
		var chunk: ModuleChunk = MODULE_CHUNK_SCRIPT.new() as ModuleChunk
		var configured: bool = chunk.configure(
			packed,
			Vector2i.ZERO,
			rotation,
			["edge_north"],
			160.0,
			Vector2.ZERO
		)
		_expect(configured, "runtime rotation %d should configure" % rotation)
		if not configured:
			chunk.free()
			continue
		var generated: GeneratedModuleScene = chunk.generated_instance()
		_expect(
			generated.position.is_equal_approx(expected_positions[rotation]),
			"runtime rotation %d must apply square-pivot compensation" % rotation
		)
		_expect(
			is_equal_approx(generated.rotation_degrees, float(rotation)),
			"runtime rotation %d must rotate the mounted root" % rotation
		)
		_expect(
			(generated.transform * Vector2(320.0, 480.0)).is_equal_approx(
				expected_points[rotation]
			),
			"runtime rotation %d must map canonical cell centers correctly"
			% rotation
		)
		for seal_name: String in ["North", "East", "South", "West"]:
			var edge_root: Node2D = generated.get_node(
				"EdgeSeals/%s" % seal_name
			) as Node2D
			_expect(
				edge_root.visible
				== (seal_name == String(expected_local_seals[rotation])),
				"runtime rotation %d must inverse-map the north world seal"
				% rotation
			)
		chunk.free()


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
		transformed_context
	)
	var decoration_layer: TileMapLayer = root.get_node(
		"Decoration"
	) as TileMapLayer
	var source_cell := Vector2i(2, 3)
	var expected_flags: int = MODULE_SCENE_BAKER._visual_transform_flags(
		90,
		true,
		false
	)
	_expect(
		decoration_layer.get_cell_alternative_tile(source_cell)
		== expected_flags,
		"visual cell transform flags must remain authored in canonical space"
	)
	root.free()


func _test_edge_masks(context: Dictionary) -> void:
	var root: GeneratedModuleScene = MODULE_SCENE_BAKER._build_generated_scene(
		context
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
		context
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
	var obsolete_directory: String = "user://module_bake_smoke_obsolete"
	var obsolete_path: String = "%s/rotation_90.tscn" % obsolete_directory
	var obsolete_save_error: String = MODULE_SCENE_BAKER._save_generated_scene(
		obsolete_path,
		expected
	)
	_expect(
		obsolete_save_error.is_empty(),
		"temporary obsolete direction scene should save"
	)
	_expect(
		MODULE_SCENE_BAKER._obsolete_generated_scene_paths_in(
			obsolete_directory
		) == [obsolete_path],
		"obsolete direction scene discovery must reject noncanonical artifacts"
	)
	if FileAccess.file_exists(obsolete_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(obsolete_path))
	if DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(obsolete_directory)
	):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(obsolete_directory)
		)
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
		"missing canonical generated scene must fail the fingerprint check"
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
