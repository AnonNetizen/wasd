extends SceneTree
## Focused bake validation coverage without modifying tracked authoring artifacts.

const MODULE_SCENE_BAKER := preload("res://scripts/editor/module_scene_baker.gd")
const MODULE_AUTHORING_ROOT := preload("res://scripts/editor/module_authoring_root.gd")
const MODULE_PLACEMENT_MARKER := preload("res://scripts/editor/module_placement_marker.gd")
const MODULE_BAKED_DATA := preload("res://scripts/gameplay/module_baked_data.gd")
const MODULE_BAKED_ROTATION := preload("res://scripts/gameplay/module_baked_rotation.gd")
const TILE_SET: TileSet = preload("res://resources/modules/module_placeholder_tileset.tres")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_expect_invalid("missing cell", _missing_cell, "Ground is missing cell")
	_expect_invalid("out of bounds", _out_of_bounds, "out-of-bounds cell")
	_expect_invalid("unsnapped marker", _unsnapped_marker, "is not snapped")
	_expect_invalid("unknown id", _unknown_placement, "unknown enemy_id")
	_expect_invalid("placement on wall", _placement_on_wall, "lands on a blocked cell")
	_expect_invalid("disconnected socket", _disconnect_floor, "disconnected walkable cells")
	_test_missing_rotation_resource()
	_test_stale_source_hash()
	_test_approval_gate()
	for failure: String in _failures:
		printerr("[module-bake-smoke] %s" % failure)
	print("[module-bake-smoke] ok=%s assertions=9" % str(_failures.is_empty()).to_lower())
	quit(0 if _failures.is_empty() else 1)


func _expect_invalid(label: String, mutation: Callable, expected_message: String) -> void:
	var root: ModuleAuthoringRoot = _valid_root()
	mutation.call(root)
	var result: Dictionary = MODULE_SCENE_BAKER.inspect_scene_root(root, "test_module", "<smoke>")
	var joined: String = "\n".join(result.get("errors", PackedStringArray()) as PackedStringArray)
	if bool(result.get("ok", false)) or not joined.contains(expected_message):
		_failures.append("%s did not report %s; got %s" % [label, expected_message, joined])
	root.free()


func _valid_root() -> ModuleAuthoringRoot:
	var root := MODULE_AUTHORING_ROOT.new() as ModuleAuthoringRoot
	root.module_id = "test_module"
	for layer_name: String in ["Ground", "Obstacles", "Decoration"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = TILE_SET
		root.add_child(layer)
	var ground: TileMapLayer = root.get_node("Ground") as TileMapLayer
	for y: int in range(11):
		for x: int in range(11):
			ground.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	var placements := Node2D.new()
	placements.name = "Placements"
	root.add_child(placements)
	var marker := MODULE_PLACEMENT_MARKER.new() as ModulePlacementMarker
	marker.name = "PlayerStart"
	marker.position = Vector2.ZERO
	placements.add_child(marker)
	return root


func _missing_cell(root: ModuleAuthoringRoot) -> void:
	(root.get_node("Ground") as TileMapLayer).erase_cell(Vector2i(10, 10))


func _out_of_bounds(root: ModuleAuthoringRoot) -> void:
	(root.get_node("Ground") as TileMapLayer).set_cell(Vector2i(11, 0), 0, Vector2i.ZERO)


func _unsnapped_marker(root: ModuleAuthoringRoot) -> void:
	(root.get_node("Placements/PlayerStart") as Marker2D).position = Vector2(1.0, 0.0)


func _unknown_placement(root: ModuleAuthoringRoot) -> void:
	var marker: ModulePlacementMarker = root.get_node("Placements/PlayerStart") as ModulePlacementMarker
	marker.placement_type = "module_place_enemy_spawn"
	marker.payload = {"enemy_id": "enemy_unknown", "count": 1}


func _placement_on_wall(root: ModuleAuthoringRoot) -> void:
	(root.get_node("Obstacles") as TileMapLayer).set_cell(Vector2i.ZERO, 0, Vector2i(1, 0))


func _disconnect_floor(root: ModuleAuthoringRoot) -> void:
	var obstacles: TileMapLayer = root.get_node("Obstacles") as TileMapLayer
	for y: int in range(11):
		obstacles.set_cell(Vector2i(5, y), 0, Vector2i(1, 0))


func _test_missing_rotation_resource() -> void:
	var expected: ModuleBakedData = _baked_data("same", [0, 90])
	var actual: ModuleBakedData = _baked_data("same", [0])
	var path: String = "user://module_bake_smoke_missing_rotation.tres"
	ResourceSaver.save(actual, path)
	if MODULE_SCENE_BAKER._baked_artifact_matches(path, expected):
		_failures.append("missing rotation resource was accepted")


func _test_stale_source_hash() -> void:
	var expected: ModuleBakedData = _baked_data("new", [0])
	var actual: ModuleBakedData = _baked_data("old", [0])
	var path: String = "user://module_bake_smoke_stale.tres"
	ResourceSaver.save(actual, path)
	if MODULE_SCENE_BAKER._baked_artifact_matches(path, expected):
		_failures.append("stale source hash was accepted")


func _test_approval_gate() -> void:
	if MODULE_SCENE_BAKER.is_approval_current("module_review_approved", false):
		_failures.append("changed approved source did not require reapproval")
	if not MODULE_SCENE_BAKER.is_approval_current("module_review_candidate", false):
		_failures.append("candidate source was incorrectly treated as an approval failure")


func _baked_data(source_hash: String, rotations: Array[int]) -> ModuleBakedData:
	var data := MODULE_BAKED_DATA.new() as ModuleBakedData
	data.module_id = "test_module"
	data.source_content_hash = source_hash
	for degrees: int in rotations:
		var rotation := MODULE_BAKED_ROTATION.new() as ModuleBakedRotation
		rotation.rotation_degrees = degrees
		rotation.ground_pattern = TileMapPattern.new()
		rotation.obstacle_pattern = TileMapPattern.new()
		rotation.decoration_pattern = TileMapPattern.new()
		rotation.terrain_collision = ConcavePolygonShape2D.new()
		data.rotations.append(rotation)
	return data
