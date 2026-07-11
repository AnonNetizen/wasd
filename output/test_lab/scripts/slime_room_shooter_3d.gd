extends Node3D

const ACTION_BACK: String = "lab_back"
const ACTION_FIRE: String = "lab_fire"
const ACTION_MOVE_BACK: String = "lab_move_back"
const ACTION_MOVE_FORWARD: String = "lab_move_forward"
const ACTION_MOVE_LEFT: String = "lab_move_left"
const ACTION_MOVE_RIGHT: String = "lab_move_right"
const AIM_MARKER_HEIGHT: float = 0.078
const AIM_PLANE_HEIGHT: float = 0.0
const FIRE_INTERVAL: float = 0.14
const FIRE_POSE_DAMPING: float = 11.5
const FIRE_POSE_IMPULSE: float = 0.62
const FIRE_POSE_MAX: float = 1.0
const FIRE_POSE_MIN: float = -0.30
const FIRE_POSE_STIFFNESS: float = 68.0
const FIRE_POSE_VELOCITY_IMPULSE: float = 1.15
const FIRE_POSE_VELOCITY_MAX: float = 2.4
const MOUSE_AIM_DEADZONE: float = 0.08
const MOVE_SPEED: float = 4.8
const PLAYER_MARGIN: float = 0.72
const PROJECTILE_LIFETIME: float = 1.8
const PROJECTILE_ROOM_MARGIN: float = 0.5
const PROJECTILE_SPEED: float = 13.0
const ROOM_HALF_EXTENTS := Vector2(8.0, 6.0)
const SCREEN_AXIS_SAMPLE_OFFSET: float = 64.0

@onready var _aim_marker: MeshInstance3D = get_node_or_null("World3D/AimMarker") as MeshInstance3D
@onready var _back_button: Button = get_node_or_null("Overlay/ExitButton") as Button
@onready var _camera: Camera3D = get_node_or_null("PerspectiveCamera") as Camera3D
@onready var _contact_layer: Node3D = get_node_or_null("World3D/Actors/Slime3D/ContactLayer") as Node3D
@onready var _muzzle: Marker3D = get_node_or_null("World3D/Actors/Slime3D/Muzzle") as Marker3D
@onready var _muzzle_flash: Node3D = get_node_or_null("World3D/Actors/Slime3D/MuzzleFlash") as Node3D
@onready var _muzzle_flash_light: OmniLight3D = get_node_or_null("World3D/Actors/Slime3D/MuzzleFlash/FlashLight") as OmniLight3D
@onready var _projectiles_root: Node3D = get_node_or_null("World3D/Projectiles") as Node3D
@onready var _shot_count_label: Label = get_node_or_null("Overlay/AmmoPanel/Margin/Rows/ShotCount") as Label
@onready var _slime_membrane: Node3D = get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/SlimeMembrane") as Node3D
@onready var _slime_root: Node3D = get_node_or_null("World3D/Actors/Slime3D") as Node3D
@onready var _slime_visual: Node3D = get_node_or_null("World3D/Actors/Slime3D/SlimeVisual") as Node3D

var _aim_direction := Vector3.FORWARD
var _animation_time: float = 0.0
var _fire_cooldown: float = 0.0
var _fire_pose: float = 0.0
var _fire_pose_velocity: float = 0.0
var _last_fired_direction := Vector3.FORWARD
var _movement_strength: float = 0.0
var _muzzle_flash_time: float = 0.0
var _projectile_cursor: int = 0
var _projectile_directions: Array[Vector3] = []
var _projectile_lifetimes := PackedFloat32Array()
var _projectile_nodes: Array[MeshInstance3D] = []
var _shot_count: int = 0


func _ready() -> void:
	_ensure_input_actions()
	_collect_projectile_pool()
	if _back_button != null:
		_back_button.pressed.connect(_return_to_index)
	_update_shot_count_label()
	_update_membrane_visual_state()


func _process(delta: float) -> void:
	_animation_time += delta
	_update_fire_pose(delta)
	_update_membrane_visual_state()
	_update_slime_animation(delta)
	_update_muzzle_flash(delta)


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed(ACTION_BACK):
		_return_to_index()
		return

	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_update_player(delta)
	_update_mouse_aim()
	_update_projectiles(delta)

	if Input.is_action_pressed(ACTION_FIRE) and _fire_cooldown <= 0.0 and not _is_pointer_over_button():
		_fire_projectile()


func debug_active_projectile_count() -> int:
	var active_count: int = 0
	for projectile in _projectile_nodes:
		if projectile.visible:
			active_count += 1
	return active_count


func debug_aim_at_world(world_position: Vector3) -> void:
	_apply_aim_world_position(world_position)
	_update_membrane_visual_state()


func debug_fire_at_world(world_position: Vector3) -> void:
	_apply_aim_world_position(world_position)
	_fire_projectile()
	_update_membrane_visual_state()


func debug_last_fired_direction() -> Vector3:
	return _last_fired_direction


func debug_fire_pose() -> float:
	return _fire_pose


func debug_membrane_control_point_count() -> int:
	if _slime_membrane == null or not _slime_membrane.has_method("control_point_count"):
		return 0
	return int(_slime_membrane.call("control_point_count"))


func debug_membrane_deformation() -> float:
	if _slime_membrane == null or not _slime_membrane.has_method("deformation_amount"):
		return 0.0
	return float(_slime_membrane.call("deformation_amount"))


func debug_player_position() -> Vector3:
	if _slime_root == null:
		return Vector3.ZERO
	return _slime_root.global_position


func debug_slime_visual_local_position() -> Vector3:
	if _slime_visual == null:
		return Vector3.ZERO
	return _slime_visual.position


func debug_slime_visual_scale() -> Vector3:
	if _slime_visual == null:
		return Vector3.ONE
	return _slime_visual.scale


func debug_slime_visual_layer_count() -> int:
	if _slime_membrane == null or not _slime_membrane.has_method("visual_layer_count"):
		return 0
	return int(_slime_membrane.call("visual_layer_count"))


func debug_slime_layers_share_mesh() -> bool:
	if _slime_membrane == null or not _slime_membrane.has_method("visual_layers_share_mesh"):
		return false
	return bool(_slime_membrane.call("visual_layers_share_mesh"))


func debug_slime_face_world_direction() -> Vector3:
	if _slime_membrane == null or not _slime_membrane.has_method("face_world_direction"):
		return Vector3.ZERO
	var direction: Variant = _slime_membrane.call("face_world_direction")
	if direction is Vector3:
		return direction
	return Vector3.ZERO


func debug_slime_face_look_offset() -> Vector2:
	if _slime_membrane == null or not _slime_membrane.has_method("face_look_offset"):
		return Vector2.ZERO
	var look_offset: Variant = _slime_membrane.call("face_look_offset")
	if look_offset is Vector2:
		return look_offset
	return Vector2.ZERO


func debug_slime_core_offset_amount() -> float:
	if _slime_membrane == null or not _slime_membrane.has_method("core_offset_amount"):
		return 0.0
	return float(_slime_membrane.call("core_offset_amount"))


func debug_projectile_pool_size() -> int:
	return _projectile_nodes.size()


func debug_set_player_position(world_position: Vector3) -> void:
	if _slime_root == null:
		return
	_slime_root.global_position = Vector3(
		clampf(world_position.x, -ROOM_HALF_EXTENTS.x + PLAYER_MARGIN, ROOM_HALF_EXTENTS.x - PLAYER_MARGIN),
		0.0,
		clampf(world_position.z, -ROOM_HALF_EXTENTS.y + PLAYER_MARGIN, ROOM_HALF_EXTENTS.y - PLAYER_MARGIN)
	)


func _apply_aim_world_position(world_position: Vector3) -> void:
	if _slime_root == null:
		return

	if _aim_marker != null:
		_aim_marker.global_position = Vector3(
			clampf(world_position.x, -ROOM_HALF_EXTENTS.x, ROOM_HALF_EXTENTS.x),
			AIM_MARKER_HEIGHT,
			clampf(world_position.z, -ROOM_HALF_EXTENTS.y, ROOM_HALF_EXTENTS.y)
		)

	var raw_aim: Vector3 = world_position - _slime_root.global_position
	var flat_aim := Vector3(raw_aim.x, 0.0, raw_aim.z)
	if flat_aim.length_squared() <= MOUSE_AIM_DEADZONE * MOUSE_AIM_DEADZONE:
		return

	_aim_direction = flat_aim.normalized()
	_slime_root.rotation.y = atan2(-_aim_direction.x, -_aim_direction.z)


func _collect_projectile_pool() -> void:
	_projectile_nodes.clear()
	_projectile_directions.clear()
	_projectile_lifetimes.clear()
	if _projectiles_root == null:
		return

	for child in _projectiles_root.get_children():
		if child is MeshInstance3D:
			var projectile := child as MeshInstance3D
			projectile.visible = false
			_projectile_nodes.append(projectile)
			_projectile_directions.append(Vector3.FORWARD)

	_projectile_lifetimes.resize(_projectile_nodes.size())


func _deactivate_projectile(index: int) -> void:
	_projectile_nodes[index].visible = false
	_projectile_lifetimes[index] = 0.0


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_MOVE_FORWARD, KEY_W)
	_register_key_action(ACTION_MOVE_FORWARD, KEY_UP)
	_register_key_action(ACTION_MOVE_BACK, KEY_S)
	_register_key_action(ACTION_MOVE_BACK, KEY_DOWN)
	_register_key_action(ACTION_MOVE_LEFT, KEY_A)
	_register_key_action(ACTION_MOVE_LEFT, KEY_LEFT)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_D)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_RIGHT)
	_register_key_action(ACTION_BACK, KEY_ESCAPE)
	_register_mouse_action(ACTION_FIRE, MOUSE_BUTTON_LEFT)


func _fire_projectile() -> void:
	if _projectile_nodes.is_empty() or _slime_root == null:
		return

	var projectile_index: int = _projectile_cursor
	var projectile: MeshInstance3D = _projectile_nodes[projectile_index]
	var spawn_position: Vector3 = _muzzle.global_position if _muzzle != null else _slime_root.global_position
	if _slime_membrane != null and _slime_membrane.has_method("emit_surface_bud"):
		var membrane_surface: Variant = _slime_membrane.call("emit_surface_bud", _aim_direction)
		if membrane_surface is Vector3:
			spawn_position = membrane_surface
	projectile.global_position = spawn_position
	projectile.rotation = Vector3(0.0, atan2(_aim_direction.x, _aim_direction.z), 0.0)
	projectile.scale = Vector3.ONE
	projectile.visible = true
	_projectile_directions[projectile_index] = _aim_direction
	_projectile_lifetimes[projectile_index] = PROJECTILE_LIFETIME
	_projectile_cursor = (_projectile_cursor + 1) % _projectile_nodes.size()

	_last_fired_direction = _aim_direction
	_fire_cooldown = FIRE_INTERVAL
	_kick_fire_pose()
	_muzzle_flash_time = 0.075
	if _muzzle_flash != null:
		_muzzle_flash.visible = true
	_shot_count += 1
	_update_shot_count_label()


func _flattened_direction(direction: Vector3, fallback: Vector3) -> Vector3:
	var flattened := Vector3(direction.x, 0.0, direction.z)
	if flattened.length_squared() <= 0.0001:
		return fallback.normalized()
	return flattened.normalized()


func _kick_fire_pose() -> void:
	_fire_pose = minf(FIRE_POSE_MAX, maxf(_fire_pose, 0.0) + FIRE_POSE_IMPULSE)
	_fire_pose_velocity = minf(
		FIRE_POSE_VELOCITY_MAX,
		_fire_pose_velocity + FIRE_POSE_VELOCITY_IMPULSE
	)


func _ground_point_from_screen(screen_point: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_point)
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_point)
	if is_zero_approx(ray_direction.y):
		return ray_origin
	var distance_to_ground: float = (AIM_PLANE_HEIGHT - ray_origin.y) / ray_direction.y
	return ray_origin + ray_direction * distance_to_ground


func _is_pointer_over_button() -> bool:
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	return hovered_control is Button


func _register_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for input_event in InputMap.action_get_events(action_name):
		var key_event := input_event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return

	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action_name, event)


func _register_mouse_action(action_name: String, button_index: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for input_event in InputMap.action_get_events(action_name):
		var mouse_event := input_event as InputEventMouseButton
		if mouse_event != null and mouse_event.button_index == button_index:
			return

	var event := InputEventMouseButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action_name, event)


func _return_to_index() -> void:
	var error: Error = get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")
	if error != OK:
		push_error("Failed to return to the test lab index: %s" % error)


func _screen_relative_ground_direction(screen_input: Vector2) -> Vector3:
	if _camera == null:
		return Vector3(screen_input.x, 0.0, -screen_input.y).normalized()
	var viewport: Viewport = get_viewport()
	var screen_center: Vector2 = viewport.get_visible_rect().size * 0.5
	var center_point: Vector3 = _ground_point_from_screen(screen_center)
	var right_point: Vector3 = _ground_point_from_screen(screen_center + Vector2(SCREEN_AXIS_SAMPLE_OFFSET, 0.0))
	var up_point: Vector3 = _ground_point_from_screen(screen_center + Vector2(0.0, -SCREEN_AXIS_SAMPLE_OFFSET))
	var right_axis: Vector3 = _flattened_direction(right_point - center_point, Vector3.RIGHT)
	var up_axis: Vector3 = _flattened_direction(up_point - center_point, Vector3.FORWARD)
	return (right_axis * screen_input.x + up_axis * screen_input.y).normalized()


func _update_mouse_aim() -> void:
	_apply_aim_world_position(_ground_point_from_screen(get_viewport().get_mouse_position()))


func _update_player(delta: float) -> void:
	if _slime_root == null:
		return

	var start_position: Vector3 = _slime_root.position
	var screen_input := Vector2.ZERO
	screen_input.y += Input.get_action_strength(ACTION_MOVE_FORWARD)
	screen_input.y -= Input.get_action_strength(ACTION_MOVE_BACK)
	screen_input.x -= Input.get_action_strength(ACTION_MOVE_LEFT)
	screen_input.x += Input.get_action_strength(ACTION_MOVE_RIGHT)
	_movement_strength = minf(1.0, screen_input.length())
	if screen_input.length_squared() > 0.0:
		var movement_direction: Vector3 = _screen_relative_ground_direction(screen_input.normalized())
		_slime_root.position += movement_direction * MOVE_SPEED * delta
	_slime_root.position.x = clampf(
		_slime_root.position.x,
		-ROOM_HALF_EXTENTS.x + PLAYER_MARGIN,
		ROOM_HALF_EXTENTS.x - PLAYER_MARGIN
	)
	_slime_root.position.z = clampf(
		_slime_root.position.z,
		-ROOM_HALF_EXTENTS.y + PLAYER_MARGIN,
		ROOM_HALF_EXTENTS.y - PLAYER_MARGIN
	)
	if _slime_membrane != null and _slime_membrane.has_method("set_drive_velocity"):
		var actual_velocity: Vector3 = Vector3.ZERO
		if delta > 0.0001:
			actual_velocity = (_slime_root.position - start_position) / delta
		_slime_membrane.call("set_drive_velocity", actual_velocity)


func _update_projectiles(delta: float) -> void:
	for index in range(_projectile_nodes.size()):
		var projectile: MeshInstance3D = _projectile_nodes[index]
		if not projectile.visible:
			continue

		projectile.position += _projectile_directions[index] * PROJECTILE_SPEED * delta
		_projectile_lifetimes[index] -= delta
		var pulse: float = 1.0 + sin(_projectile_lifetimes[index] * 20.0) * 0.08
		projectile.scale = Vector3.ONE * pulse
		var outside_room: bool = (
			absf(projectile.position.x) > ROOM_HALF_EXTENTS.x + PROJECTILE_ROOM_MARGIN
			or absf(projectile.position.z) > ROOM_HALF_EXTENTS.y + PROJECTILE_ROOM_MARGIN
		)
		if _projectile_lifetimes[index] <= 0.0 or outside_room:
			_deactivate_projectile(index)


func _update_muzzle_flash(delta: float) -> void:
	if _muzzle_flash == null:
		return
	_muzzle_flash_time = maxf(0.0, _muzzle_flash_time - delta)
	if _muzzle_flash_time <= 0.0:
		_muzzle_flash.visible = false
		return
	var flash_ratio: float = _muzzle_flash_time / 0.075
	_muzzle_flash.visible = true
	_muzzle_flash.scale = Vector3.ONE * lerpf(0.38, 0.92, flash_ratio)
	_muzzle_flash.rotation.z = _animation_time * 18.0
	if _muzzle_flash_light != null:
		_muzzle_flash_light.light_energy = 0.80 * flash_ratio


func _update_membrane_visual_state() -> void:
	if (
		_slime_membrane == null
		or _slime_root == null
		or not _slime_membrane.has_method("set_visual_state")
	):
		return
	var camera_direction := Vector3.BACK
	if _camera != null:
		camera_direction = _flattened_direction(
			_camera.global_position - _slime_root.global_position,
			Vector3.BACK
		)
	_slime_membrane.call(
		"set_visual_state",
		camera_direction,
		_aim_direction,
		clampf(maxf(_fire_pose, 0.0), 0.0, 1.0)
	)


func _update_fire_pose(delta: float) -> void:
	var safe_delta: float = minf(delta, 0.033)
	var acceleration: float = (
		-_fire_pose * FIRE_POSE_STIFFNESS
		- _fire_pose_velocity * FIRE_POSE_DAMPING
	)
	_fire_pose_velocity += acceleration * safe_delta
	_fire_pose = clampf(
		_fire_pose + _fire_pose_velocity * safe_delta,
		FIRE_POSE_MIN,
		FIRE_POSE_MAX
	)
	if absf(_fire_pose) < 0.001 and absf(_fire_pose_velocity) < 0.01:
		_fire_pose = 0.0
		_fire_pose_velocity = 0.0


func _update_shot_count_label() -> void:
	if _shot_count_label != null:
		_shot_count_label.text = "FIRED  %03d" % _shot_count


func _update_slime_animation(delta: float) -> void:
	if _slime_visual == null:
		return

	var animation_speed: float = lerpf(3.0, 9.0, _movement_strength)
	var wave: float = sin(_animation_time * animation_speed)
	var squash_amount: float = lerpf(0.025, 0.085, _movement_strength)
	var movement_scale := Vector3(
		1.0 + wave * squash_amount,
		1.0 - wave * squash_amount * 0.85,
		1.0 + wave * squash_amount
	)
	var fire_scale := Vector3(
		1.0 + _fire_pose * 0.055,
		1.0 - _fire_pose * 0.10,
		1.0 + _fire_pose * 0.035
	)
	var target_scale: Vector3 = movement_scale * fire_scale
	var blend: float = minf(1.0, delta * 18.0)
	_slime_visual.scale = _slime_visual.scale.lerp(target_scale, blend)
	if _contact_layer != null:
		var contact_scale := Vector3(
			clampf(target_scale.x, 0.92, 1.08),
			1.0,
			clampf(target_scale.z, 0.92, 1.08)
		)
		_contact_layer.scale = _contact_layer.scale.lerp(contact_scale, blend)
		_contact_layer.position = Vector3.ZERO
	var movement_bob: float = absf(wave) * 0.025 * _movement_strength
	var rebound_lift: float = maxf(-_fire_pose, 0.0) * 0.018
	var launch_lean: float = -maxf(_fire_pose, 0.0) * 0.035
	_slime_visual.position = Vector3(0.0, movement_bob + rebound_lift, launch_lean)
