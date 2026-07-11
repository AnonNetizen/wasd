extends SceneTree

const ACTION_MOVE_RIGHT: String = "lab_move_right"
const EXPECTED_VISUAL_LAYER_COUNT: int = 4
const EXPECTED_MEMBRANE_CONTROL_POINT_COUNT: int = 24
const EXPECTED_PROJECTILE_POOL_SIZE: int = 24
const MAX_CORE_OFFSET_AMOUNT: float = 0.0385
const MAX_FACE_LOOK_OFFSET: float = 0.1815
const SCENE_PATH: String = "res://scenes/slime_room_shooter_3d.tscn"

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[SlimeRoomShooter3DSmoke] %s" % message)


func _layers_share_array_mesh(
	surface: MeshInstance3D,
	wet_coat: MeshInstance3D,
	face_paint: MeshInstance3D,
	outline_shell: MeshInstance3D
) -> bool:
	if surface == null or wet_coat == null or face_paint == null or outline_shell == null:
		return false
	if not surface.mesh is ArrayMesh:
		return false
	return (
		wet_coat.mesh == surface.mesh
		and face_paint.mesh == surface.mesh
		and outline_shell.mesh == surface.mesh
	)


func _expect_visual_layer_contract(
	scene: Node3D,
	surface: MeshInstance3D,
	wet_coat: MeshInstance3D,
	face_paint: MeshInstance3D,
	outline_shell: MeshInstance3D,
	stage: String
) -> void:
	_expect(
		_layers_share_array_mesh(surface, wet_coat, face_paint, outline_shell),
		"The four slime render layers stopped sharing one ArrayMesh %s." % stage
	)
	if not scene.has_method("debug_slime_visual_layer_count"):
		_expect(false, "Slime visual layer-count debug contract is missing.")
	else:
		var reported_count: int = scene.call("debug_slime_visual_layer_count")
		_expect(
			reported_count == EXPECTED_VISUAL_LAYER_COUNT,
			"Slime should report %d dynamic visual layers %s, got %d."
			% [EXPECTED_VISUAL_LAYER_COUNT, stage, reported_count]
		)
	if not scene.has_method("debug_slime_layers_share_mesh"):
		_expect(false, "Slime shared-mesh debug contract is missing.")
	else:
		_expect(
			bool(scene.call("debug_slime_layers_share_mesh")),
			"Slime shared-mesh debug contract failed %s." % stage
		)


func _maximum_look_offset_distance(offsets: Array[Vector2]) -> float:
	var maximum_distance: float = 0.0
	for first_index in range(offsets.size()):
		for second_index in range(first_index + 1, offsets.size()):
			maximum_distance = maxf(
				maximum_distance,
				offsets[first_index].distance_to(offsets[second_index])
			)
	return maximum_distance


func _mesh_world_top(mesh_instance: MeshInstance3D) -> float:
	if mesh_instance == null or mesh_instance.mesh == null:
		return -INF
	var bounds: AABB = mesh_instance.get_aabb()
	var local_top_center := Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y + bounds.size.y,
		bounds.position.z + bounds.size.z * 0.5
	)
	return mesh_instance.to_global(local_top_center).y


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
	var slime_root := scene.get_node_or_null("World3D/Actors/Slime3D") as Node3D
	var slime_visual := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeVisual") as Node3D
	_expect(slime_root != null, "3D slime is missing.")
	_expect(slime_visual != null, "3D slime visual is missing.")
	var contact_layer := scene.get_node_or_null("World3D/Actors/Slime3D/ContactLayer") as Node3D
	var contact_shadow := scene.get_node_or_null("World3D/Actors/Slime3D/ContactLayer/ContactShadow") as MeshInstance3D
	var gel_foot := scene.get_node_or_null("World3D/Actors/Slime3D/ContactLayer/GelFoot") as MeshInstance3D
	var carpet_runner := scene.get_node_or_null("World3D/Room/CarpetRunner") as MeshInstance3D
	_expect(contact_layer != null, "Slime contact layer is missing.")
	_expect(contact_shadow != null, "Slime contact shadow is missing from the fixed contact layer.")
	_expect(gel_foot != null, "Slime gel foot is missing from the fixed contact layer.")
	_expect(carpet_runner != null, "Dungeon carpet runner is missing below the slime spawn.")
	if contact_shadow != null and gel_foot != null and carpet_runner != null:
		var carpet_top: float = _mesh_world_top(carpet_runner)
		_expect(
			_mesh_world_top(contact_shadow) > carpet_top + 0.002,
			"Slime contact shadow is buried below the opaque carpet surface."
		)
		_expect(
			_mesh_world_top(gel_foot) > carpet_top + 0.002,
			"Slime gel foot is buried below the opaque carpet surface."
		)
	var slime_fill_light := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeFillLight") as OmniLight3D
	_expect(slime_fill_light != null, "Slime-local fill light is missing.")
	_expect(
		slime_fill_light != null and slime_fill_light.get_parent() == slime_root,
		"SlimeFillLight should be a direct child of the gameplay slime root."
	)
	_expect(scene.get_node_or_null("SlimeGlowLight") == null, "Legacy room-root SlimeGlowLight should be removed.")
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
	var wet_coat := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/SlimeMembrane/WetCoat") as MeshInstance3D
	var face_paint := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/SlimeMembrane/FacePaint") as MeshInstance3D
	var outline_shell := scene.get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/SlimeMembrane/OutlineShell") as MeshInstance3D
	_expect(membrane != null, "The continuous slime membrane is missing.")
	_expect(edge_rig != null, "The membrane edge-control rig is missing.")
	_expect(membrane_surface != null and membrane_surface.mesh is ArrayMesh, "The runtime membrane ArrayMesh is missing.")
	_expect(wet_coat != null and wet_coat.mesh is ArrayMesh, "The wet-coat render layer is missing.")
	_expect(face_paint != null and face_paint.mesh is ArrayMesh, "The procedural face-paint render layer is missing.")
	_expect(outline_shell != null and outline_shell.mesh is ArrayMesh, "The continuous outline shell is missing.")
	_expect_visual_layer_contract(
		scene,
		membrane_surface,
		wet_coat,
		face_paint,
		outline_shell,
		"after scene setup"
	)
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

	_expect(scene.has_method("debug_slime_face_world_direction"), "Slime face-direction debug contract is missing.")
	_expect(scene.has_method("debug_slime_face_look_offset"), "Slime face-look debug contract is missing.")
	_expect(scene.has_method("debug_slime_core_offset_amount"), "Slime core-offset debug contract is missing.")
	if (
		camera != null
		and slime_root != null
		and scene.has_method("debug_slime_face_world_direction")
		and scene.has_method("debug_slime_face_look_offset")
	):
		var aim_directions: Array[Vector3] = [
			Vector3.RIGHT,
			Vector3.LEFT,
			Vector3.FORWARD,
			Vector3.BACK,
		]
		var observed_look_offsets: Array[Vector2] = []
		for aim_direction in aim_directions:
			var aim_target: Vector3 = slime_root.global_position + aim_direction * 5.0
			scene.call("debug_aim_at_world", aim_target)
			for _frame in range(2):
				await physics_frame
				await process_frame
				scene.call("debug_aim_at_world", aim_target)
			var expected_face_direction: Vector3 = camera.global_position - slime_root.global_position
			expected_face_direction.y = 0.0
			expected_face_direction = expected_face_direction.normalized()
			var face_world_direction: Vector3 = scene.call("debug_slime_face_world_direction")
			face_world_direction.y = 0.0
			face_world_direction = face_world_direction.normalized()
			_expect(
				face_world_direction.dot(expected_face_direction) > 0.995,
				"Slime face stopped facing the camera while aiming toward %s." % aim_direction
			)
			var look_offset: Vector2 = scene.call("debug_slime_face_look_offset")
			observed_look_offsets.append(look_offset)
			_expect(
				look_offset.length() <= MAX_FACE_LOOK_OFFSET,
				"Slime pupil offset exceeded its bounded eye radius while aiming toward %s: %.4f."
				% [aim_direction, look_offset.length()]
			)
			var camera_right: Vector3 = Vector3.UP.cross(expected_face_direction).normalized()
			var expected_look_offset := Vector2(
				-aim_direction.dot(camera_right),
				-aim_direction.dot(expected_face_direction)
			) * 0.18
			_expect(
				look_offset.distance_to(expected_look_offset) < 0.006,
				"Slime pupils tracked the wrong screen direction for aim %s (expected %s, got %s)."
				% [aim_direction, expected_look_offset, look_offset]
			)
		_expect(
			_maximum_look_offset_distance(observed_look_offsets) > 0.05,
			"Slime pupils did not visibly track changes across four aim directions."
		)

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
	_expect_visual_layer_contract(
		scene,
		membrane_surface,
		wet_coat,
		face_paint,
		outline_shell,
		"after movement deformation"
	)
	if scene.has_method("debug_slime_core_offset_amount"):
		var moving_core_offset: float = scene.call("debug_slime_core_offset_amount")
		_expect(
			moving_core_offset <= MAX_CORE_OFFSET_AMOUNT,
			"Slime inner-fill lag exceeded 0.05R during movement: %.4f." % moving_core_offset
		)

	var target_position := Vector3(5.0, 0.0, -4.0)
	var raw_expected: Vector3 = target_position - moved_position
	var expected_direction := Vector3(raw_expected.x, 0.0, raw_expected.z).normalized()
	scene.call("debug_aim_at_world", target_position)
	for _frame in range(45):
		await physics_frame
	var settled_deformation: float = scene.call("debug_membrane_deformation")
	var settled_front_extent: float = membrane.call("directional_extent", expected_direction)
	var settled_rear_extent: float = membrane.call("directional_extent", -expected_direction)
	var pre_fire_root_position: Vector3 = scene.call("debug_player_position")
	var pre_fire_contact_position: Vector3 = contact_layer.global_position if contact_layer != null else Vector3.ZERO
	scene.call("debug_fire_at_world", target_position)
	var fired_direction: Vector3 = scene.call("debug_last_fired_direction")
	var firing_deformation: float = scene.call("debug_membrane_deformation")
	var firing_front_extent: float = membrane.call("directional_extent", expected_direction)
	var firing_rear_extent: float = membrane.call("directional_extent", -expected_direction)
	_expect(fired_direction.dot(expected_direction) > 0.999, "Projectile direction does not match the requested mouse-world aim direction.")
	_expect(muzzle_flash != null and muzzle_flash.visible, "Firing did not reveal the short muzzle flash.")
	_expect(
		firing_deformation > settled_deformation + 0.03,
		"Firing did not create a local membrane bud (settled %.3f, firing %.3f)."
		% [settled_deformation, firing_deformation]
	)
	_expect(
		firing_front_extent > settled_front_extent + 0.05,
		"The membrane front did not extend toward the shot (settled %.3f, firing %.3f)."
		% [settled_front_extent, firing_front_extent]
	)
	_expect(
		firing_rear_extent < settled_rear_extent - 0.01,
		"The membrane rear did not compress before its delayed wave (settled %.3f, firing %.3f)."
		% [settled_rear_extent, firing_rear_extent]
	)
	await physics_frame
	await process_frame
	var launch_pose: float = scene.call("debug_fire_pose")
	var launch_position: Vector3 = scene.call("debug_slime_visual_local_position")
	var launch_scale: Vector3 = scene.call("debug_slime_visual_scale")
	var post_fire_root_position: Vector3 = scene.call("debug_player_position")
	var visual_world_offset: Vector3 = Vector3.ZERO
	var current_visual_forward: Vector3 = Vector3.FORWARD
	if slime_root != null and slime_visual != null:
		visual_world_offset = slime_visual.global_position - slime_root.global_position
		current_visual_forward = -slime_root.global_basis.z.normalized()
	_expect(launch_pose > 0.25, "Firing did not start the soft-body compression pose.")
	_expect(launch_scale.y < 1.005, "Firing did not squash the slime body before launch.")
	_expect(launch_position.z < -0.01, "Firing did not lean the slime visual toward its local forward direction.")
	_expect(visual_world_offset.dot(current_visual_forward) > 0.01, "The launch lean did not map to the slime's world-space facing direction.")
	_expect(
		pre_fire_root_position.distance_to(post_fire_root_position) < 0.001,
		"Firing moved the gameplay root instead of deforming the visual membrane."
	)
	if contact_layer != null:
		_expect(
			pre_fire_contact_position.distance_to(contact_layer.global_position) < 0.001,
			"Firing displaced the fixed contact layer with the leaning slime visual."
		)
		_expect(
			contact_layer.position.distance_to(Vector3.ZERO) < 0.001,
			"The fixed contact layer no longer remains centered on the gameplay root."
		)
	_expect_visual_layer_contract(
		scene,
		membrane_surface,
		wet_coat,
		face_paint,
		outline_shell,
		"after firing deformation"
	)
	if scene.has_method("debug_slime_core_offset_amount"):
		var firing_core_offset: float = scene.call("debug_slime_core_offset_amount")
		_expect(
			firing_core_offset <= MAX_CORE_OFFSET_AMOUNT,
			"Slime inner-fill lag exceeded 0.05R during firing: %.4f." % firing_core_offset
		)
	for _frame in range(6):
		await physics_frame
		await process_frame
		scene.call("debug_aim_at_world", target_position)
	var rear_wave_extent: float = membrane.call("directional_extent", -expected_direction)
	_expect(
		rear_wave_extent > firing_rear_extent + 0.008,
		"The compressed rear edge did not receive the delayed elastic rebound wave."
	)
	for _shot in range(EXPECTED_PROJECTILE_POOL_SIZE):
		scene.call("debug_fire_at_world", target_position)
	var stacked_fire_pose: float = scene.call("debug_fire_pose")
	var stacked_deformation: float = scene.call("debug_membrane_deformation")
	var stacked_edge_speed: float = membrane.call("maximum_edge_speed")
	_expect(stacked_fire_pose <= 1.001, "Repeated firing exceeded the bounded slime-pressure pose.")
	_expect(stacked_edge_speed <= 2.401, "Repeated firing exceeded the bounded membrane edge speed.")
	await physics_frame
	if scene.has_method("debug_slime_core_offset_amount"):
		var stacked_core_offset: float = scene.call("debug_slime_core_offset_amount")
		_expect(
			stacked_core_offset <= MAX_CORE_OFFSET_AMOUNT,
			"Slime inner-fill lag exceeded 0.05R during repeated firing: %.4f."
			% stacked_core_offset
		)
	var active_projectiles: int = scene.call("debug_active_projectile_count")
	_expect(
		active_projectiles == EXPECTED_PROJECTILE_POOL_SIZE,
		"Projectile cursor wrap should reuse exactly %d active nodes, got %d."
		% [EXPECTED_PROJECTILE_POOL_SIZE, active_projectiles]
	)
	for _frame in range(50):
		await physics_frame
		await process_frame
	var settled_fire_pose: float = scene.call("debug_fire_pose")
	var post_rebound_deformation: float = scene.call("debug_membrane_deformation")
	var settled_visual_position: Vector3 = scene.call("debug_slime_visual_local_position")
	_expect(absf(settled_fire_pose) < 0.08, "The slime launch pose did not settle after its elastic rebound.")
	_expect(absf(settled_visual_position.z) < 0.005, "The slime visual retained rigid recoil displacement after settling.")
	_expect(post_rebound_deformation < stacked_deformation, "The membrane deformation did not decay after repeated firing.")
	_expect(muzzle_flash != null and not muzzle_flash.visible, "The gel launch splash did not fade after firing.")

	Input.action_release(ACTION_MOVE_RIGHT)
	if _failed:
		quit(1)
		return
	print("[SlimeRoomShooter3DSmoke] Passed layered jelly visuals, camera-facing aim, natural launch/rebound, and projectile-pool checks.")
	quit(0)
