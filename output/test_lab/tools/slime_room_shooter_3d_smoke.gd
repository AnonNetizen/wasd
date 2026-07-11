extends SceneTree

const ACTION_MOVE_RIGHT: String = "lab_move_right"
const EXPECTED_MEMBRANE_CONTROL_POINT_COUNT: int = 24
const EXPECTED_PROJECTILE_POOL_SIZE: int = 24
const SCENE_PATH: String = "res://scenes/slime_room_shooter_3d.tscn"

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[SlimeRoomShooter3DSmoke] %s" % message)


func _run_smoke() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[SlimeRoomShooter3DSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	var camera := scene.get_node_or_null("PerspectiveCamera") as Camera3D
	_expect(camera != null, "PerspectiveCamera is missing.")
	_expect(camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Dungeon camera should use orthogonal projection.")
	_expect(scene.get_node_or_null("World3D/Room/Floor") is MeshInstance3D, "Room floor is missing.")
	_expect(scene.get_node_or_null("World3D/Room/StoneTiles") is Node3D, "Dungeon stone tiles are missing.")
	_expect(scene.get_node_or_null("World3D/Room/DungeonGate") is Node3D, "Dungeon gate is missing.")
	_expect(scene.get_node_or_null("World3D/Room/LeftBrazier") is Node3D, "Left dungeon brazier is missing.")
	_expect(scene.get_node_or_null("World3D/Room/RightBrazier") is Node3D, "Right dungeon brazier is missing.")
	var room := scene.get_node_or_null("World3D/Room") as Node3D
	_expect(room != null and room.has_method("flame_count"), "Dungeon room FX controller is missing.")
	if room != null and room.has_method("flame_count"):
		_expect(int(room.call("flame_count")) == 4, "Dungeon room should animate four layered flames.")
		_expect(int(room.call("torch_light_count")) == 2, "Dungeon room should animate two torch lights.")
	_expect(scene.get_node_or_null("World3D/Actors/Slime3D") is Node3D, "3D slime is missing.")
	var muzzle_flash := scene.get_node_or_null("World3D/Actors/Slime3D/MuzzleFlash") as Node3D
	_expect(muzzle_flash != null, "Slime muzzle flash is missing.")
	var aim_marker := scene.get_node_or_null("World3D/AimMarker") as MeshInstance3D
	_expect(aim_marker != null and aim_marker.mesh is TorusMesh, "Dungeon mouse aim ring is missing.")
	_expect(scene.get_node_or_null("AtmosphereOverlay/Vignette") is ColorRect, "Dungeon vignette overlay is missing.")
	_expect(scene.get_node_or_null("Overlay/AmmoPanel/Margin/Rows/ShotCount") is Label, "Compact ammo HUD is missing.")
	_expect(scene.get_node_or_null("Overlay/ExitButton") is Button, "Dungeon exit button is missing.")
	var membrane := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/SlimeMembrane") as Node3D
	var edge_rig := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/SlimeMembrane/EdgeRig") as Node3D
	var membrane_surface := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/SlimeMembrane/Surface") as MeshInstance3D
	var outline_shell := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/SlimeMembrane/OutlineShell") as MeshInstance3D
	_expect(membrane != null, "The continuous slime membrane is missing.")
	_expect(edge_rig != null, "The membrane edge-control rig is missing.")
	_expect(membrane_surface != null and membrane_surface.mesh is ArrayMesh, "The runtime membrane ArrayMesh is missing.")
	_expect(outline_shell != null and outline_shell.mesh is ArrayMesh, "The continuous outline shell is missing.")
	if edge_rig != null:
		_expect(
			edge_rig.get_child_count() == EXPECTED_MEMBRANE_CONTROL_POINT_COUNT,
			"Slime membrane should contain %d edge controls, got %d."
			% [EXPECTED_MEMBRANE_CONTROL_POINT_COUNT, edge_rig.get_child_count()]
		)
	var runtime_control_point_count: int = scene.call("debug_membrane_control_point_count")
	_expect(
		runtime_control_point_count == EXPECTED_MEMBRANE_CONTROL_POINT_COUNT,
		"Runtime membrane should report %d edge controls, got %d."
		% [EXPECTED_MEMBRANE_CONTROL_POINT_COUNT, runtime_control_point_count]
	)
	var pool_size: int = scene.call("debug_projectile_pool_size")
	_expect(pool_size == EXPECTED_PROJECTILE_POOL_SIZE, "Projectile pool size should be %d, got %d." % [EXPECTED_PROJECTILE_POOL_SIZE, pool_size])
	var first_projectile := scene.get_node_or_null("World3D/Projectiles/Projectile00") as MeshInstance3D
	_expect(first_projectile != null and first_projectile.mesh is BoxMesh, "Dungeon projectile should use an elongated BoxMesh.")
	_expect(first_projectile != null and first_projectile.get_node_or_null("Core") is MeshInstance3D, "Dungeon projectile glow core is missing.")

	var start_position: Vector3 = scene.call("debug_player_position")
	var idle_deformation: float = scene.call("debug_membrane_deformation")
	Input.action_press(ACTION_MOVE_RIGHT, 1.0)
	for _frame in range(12):
		await physics_frame
	Input.action_release(ACTION_MOVE_RIGHT)
	var moved_position: Vector3 = scene.call("debug_player_position")
	var moving_deformation: float = scene.call("debug_membrane_deformation")
	_expect(start_position.distance_to(moved_position) > 0.20, "WASD/InputMap movement did not move the slime.")
	_expect(
		moving_deformation > idle_deformation + 0.015,
		"Movement did not visibly deform the spring membrane (idle %.3f, moving %.3f)."
		% [idle_deformation, moving_deformation]
	)

	var target_position := Vector3(5.0, 0.0, -4.0)
	var raw_expected: Vector3 = target_position - moved_position
	var expected_direction := Vector3(raw_expected.x, 0.0, raw_expected.z).normalized()
	for _frame in range(45):
		await physics_frame
	var settled_deformation: float = scene.call("debug_membrane_deformation")
	scene.call("debug_fire_at_world", target_position)
	var fired_direction: Vector3 = scene.call("debug_last_fired_direction")
	var firing_deformation: float = scene.call("debug_membrane_deformation")
	_expect(fired_direction.dot(expected_direction) > 0.999, "Projectile direction does not match the requested mouse-world aim direction.")
	_expect(muzzle_flash != null and muzzle_flash.visible, "Firing did not reveal the short muzzle flash.")
	_expect(
		firing_deformation > settled_deformation + 0.04,
		"Firing did not create a local membrane bud (settled %.3f, firing %.3f)."
		% [settled_deformation, firing_deformation]
	)
	for _shot in range(EXPECTED_PROJECTILE_POOL_SIZE):
		scene.call("debug_fire_at_world", target_position)
	await physics_frame
	var active_projectiles: int = scene.call("debug_active_projectile_count")
	_expect(
		active_projectiles == EXPECTED_PROJECTILE_POOL_SIZE,
		"Projectile cursor wrap should reuse exactly %d active nodes, got %d."
		% [EXPECTED_PROJECTILE_POOL_SIZE, active_projectiles]
	)

	Input.action_release(ACTION_MOVE_RIGHT)
	if _failed:
		quit(1)
		return
	print("[SlimeRoomShooter3DSmoke] Passed dungeon atmosphere, continuous membrane, movement/fire deformation, aim, and projectile-pool checks.")
	quit(0)
