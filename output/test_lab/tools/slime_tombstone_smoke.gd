extends SceneTree

const EXPECTED_CONTROL_POINT_COUNT: int = 18
const EXPECTED_VISUAL_LAYER_COUNT: int = 3
const SCENE_PATH: String = "res://scenes/slime_tombstone_test.tscn"

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[SlimeTombstoneSmoke] %s" % message)


func _run_smoke() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[SlimeTombstoneSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	var camera := scene.get_node_or_null("TombstoneCamera") as Camera3D
	var tombstone := scene.get_node_or_null(
		"World3D/TombstoneStage/SlimeTombstone"
	) as Node3D
	var surface := scene.get_node_or_null(
		"World3D/TombstoneStage/SlimeTombstone/Surface"
	) as MeshInstance3D
	var wet_coat := scene.get_node_or_null(
		"World3D/TombstoneStage/SlimeTombstone/WetCoat"
	) as MeshInstance3D
	var outline := scene.get_node_or_null(
		"World3D/TombstoneStage/SlimeTombstone/OutlineShell"
	) as MeshInstance3D
	var face_mark := scene.get_node_or_null(
		"World3D/TombstoneStage/SlimeTombstone/FaceMark"
	) as Label3D
	var edge_rig := scene.get_node_or_null(
		"World3D/TombstoneStage/SlimeTombstone/EdgeRig"
	) as Node3D

	_expect(camera != null, "Orthogonal inspection camera is missing.")
	_expect(
		camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"Inspection camera should use orthogonal projection."
	)
	_expect(scene.get_node_or_null("World3D/Ground") is MeshInstance3D, "Ground is missing.")
	_expect(scene.get_node_or_null("World3D/BackgroundGraves") is Node3D, "Rigid comparison graves are missing.")
	_expect(scene.get_node_or_null("World3D/TombstoneStage/Plinth") is MeshInstance3D, "Tombstone plinth is missing.")
	_expect(tombstone != null, "Soft tombstone node is missing.")
	_expect(face_mark != null and face_mark.text == "RIP", "Tombstone face mark is missing.")
	_expect(edge_rig != null, "Tombstone contour rig is missing.")
	_expect(
		edge_rig != null and edge_rig.get_child_count() == EXPECTED_CONTROL_POINT_COUNT,
		"Tombstone contour rig should contain %d markers." % EXPECTED_CONTROL_POINT_COUNT
	)
	_expect(surface != null and surface.mesh is ArrayMesh, "Dynamic tombstone surface mesh is missing.")
	_expect(wet_coat != null and wet_coat.mesh is ArrayMesh, "Wet coat layer is missing.")
	_expect(outline != null and outline.mesh is ArrayMesh, "Outline shell layer is missing.")
	_expect(
		scene.call("debug_control_point_count") == EXPECTED_CONTROL_POINT_COUNT,
		"Runtime contour-point contract changed."
	)
	_expect(
		scene.call("debug_visual_layer_count") == EXPECTED_VISUAL_LAYER_COUNT,
		"Tombstone should expose three dynamic render layers."
	)
	_expect(
		bool(scene.call("debug_visual_layers_share_mesh")),
		"Surface, wet coat, and outline stopped sharing the same ArrayMesh."
	)

	scene.call("debug_set_auto_pulse", false)
	scene.call("debug_reset")
	await physics_frame
	var rest_size: Vector2 = scene.call("debug_silhouette_size")
	var rest_area_ratio: float = scene.call("debug_area_ratio")
	var rest_deformation: float = scene.call("debug_deformation_amount")
	_expect(
		rest_size.y > rest_size.x * 1.45,
		"Rest shape no longer reads as a tall gravestone silhouette: %s." % rest_size
	)
	_expect(
		absf(rest_area_ratio - 1.0) < 0.03,
		"Rest shape should begin near its authored area, got %.3f." % rest_area_ratio
	)

	scene.call("debug_poke", Vector2(-1.05, 3.15), 1.2)
	for _frame in range(8):
		await physics_frame
		await process_frame
	var impact_deformation: float = scene.call("debug_deformation_amount")
	var impact_anchor_deformation: float = scene.call("debug_anchored_deformation_amount")
	var impact_area_ratio: float = scene.call("debug_area_ratio")
	_expect(
		impact_deformation > rest_deformation + 0.06,
		"Localized poke did not visibly deform the arbitrary silhouette."
	)
	_expect(
		impact_anchor_deformation < impact_deformation * 0.58,
		"Bottom anchors moved too much during a localized impact."
	)
	_expect(
		impact_area_ratio > 0.78 and impact_area_ratio < 1.24,
		"Area pressure failed to keep the impacted tombstone coherent: %.3f." % impact_area_ratio
	)
	_expect(
		bool(scene.call("debug_visual_layers_share_mesh")),
		"Render layers stopped sharing the mesh after deformation."
	)

	for _frame in range(150):
		await physics_frame
	var recovered_deformation: float = scene.call("debug_deformation_amount")
	_expect(
		recovered_deformation < impact_deformation * 0.52,
		"Spring membrane did not recover toward its tombstone silhouette."
	)

	scene.call("debug_squash", 1.0)
	for _frame in range(9):
		await physics_frame
	var squash_size: Vector2 = scene.call("debug_silhouette_size")
	var squash_deformation: float = scene.call("debug_deformation_amount")
	_expect(
		squash_deformation > recovered_deformation + 0.05,
		"Squash action did not excite the soft tombstone."
	)
	_expect(
		squash_size.x > rest_size.x * 0.98,
		"Squash should preserve or widen the gravestone base."
	)
	_expect(
		squash_size.y > rest_size.y * 0.75,
		"Squash destroyed the recognizable tall silhouette."
	)

	if _failed:
		quit(1)
		return
	print(
		"[SlimeTombstoneSmoke] Passed arbitrary silhouette, shared mesh, "
		+ "localized deformation, anchored base, area pressure, and recovery checks."
	)
	quit(0)
