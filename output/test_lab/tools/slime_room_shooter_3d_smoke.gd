extends SceneTree

const ACTION_MOVE_RIGHT: String = "lab_move_right"
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

	_expect(scene.get_node_or_null("PerspectiveCamera") is Camera3D, "PerspectiveCamera is missing.")
	_expect(scene.get_node_or_null("World3D/Room/Floor") is MeshInstance3D, "Room floor is missing.")
	_expect(scene.get_node_or_null("World3D/Actors/Slime3D") is Node3D, "3D slime is missing.")
	_expect(scene.get_node_or_null("World3D/AimMarker") is MeshInstance3D, "Mouse aim marker is missing.")
	var pool_size: int = scene.call("debug_projectile_pool_size")
	_expect(pool_size == EXPECTED_PROJECTILE_POOL_SIZE, "Projectile pool size should be %d, got %d." % [EXPECTED_PROJECTILE_POOL_SIZE, pool_size])

	var start_position: Vector3 = scene.call("debug_player_position")
	Input.action_press(ACTION_MOVE_RIGHT, 1.0)
	for _frame in range(12):
		await physics_frame
	Input.action_release(ACTION_MOVE_RIGHT)
	var moved_position: Vector3 = scene.call("debug_player_position")
	_expect(start_position.distance_to(moved_position) > 0.20, "WASD/InputMap movement did not move the slime.")

	var target_position := Vector3(5.0, 0.0, -4.0)
	var raw_expected: Vector3 = target_position - moved_position
	var expected_direction := Vector3(raw_expected.x, 0.0, raw_expected.z).normalized()
	scene.call("debug_fire_at_world", target_position)
	var fired_direction: Vector3 = scene.call("debug_last_fired_direction")
	_expect(fired_direction.dot(expected_direction) > 0.999, "Projectile direction does not match the requested mouse-world aim direction.")
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
	print("[SlimeRoomShooter3DSmoke] Passed movement, aim, room, and projectile-pool wrap checks.")
	quit(0)
