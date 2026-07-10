extends Node3D

const ACTION_BACK: String = "lab_back"
const ACTION_FIRE: String = "lab_fire"
const ACTION_MOVE_BACK: String = "lab_move_back"
const ACTION_MOVE_FORWARD: String = "lab_move_forward"
const ACTION_MOVE_LEFT: String = "lab_move_left"
const ACTION_MOVE_RIGHT: String = "lab_move_right"
const AIM_PLANE_HEIGHT: float = 0.0
const FIRE_INTERVAL: float = 0.14
const MOUSE_AIM_DEADZONE: float = 0.08
const MOVE_SPEED: float = 4.8
const PLAYER_MARGIN: float = 0.72
const PROJECTILE_LIFETIME: float = 1.8
const PROJECTILE_ROOM_MARGIN: float = 0.5
const PROJECTILE_SPEED: float = 13.0
const ROOM_HALF_EXTENTS := Vector2(8.0, 6.0)
const SCREEN_AXIS_SAMPLE_OFFSET: float = 64.0

@onready var _aim_marker: MeshInstance3D = get_node_or_null("World3D/AimMarker") as MeshInstance3D
@onready var _back_button: Button = get_node_or_null("Overlay/Panel/Margin/Rows/BackButton") as Button
@onready var _camera: Camera3D = get_node_or_null("PerspectiveCamera") as Camera3D
@onready var _muzzle: Marker3D = get_node_or_null("World3D/Actors/Slime3D/Muzzle") as Marker3D
@onready var _projectiles_root: Node3D = get_node_or_null("World3D/Projectiles") as Node3D
@onready var _shot_count_label: Label = get_node_or_null("Overlay/Panel/Margin/Rows/ShotCount") as Label
@onready var _slime_root: Node3D = get_node_or_null("World3D/Actors/Slime3D") as Node3D
@onready var _slime_skirt: Node3D = get_node_or_null("World3D/Actors/Slime3D/SlimeVisual/Skirt") as Node3D
@onready var _slime_visual: Node3D = get_node_or_null("World3D/Actors/Slime3D/SlimeVisual") as Node3D

var _aim_direction := Vector3.FORWARD
var _animation_time: float = 0.0
var _edge_lobe_base_positions: Array[Vector3] = []
var _edge_lobe_base_scales: Array[Vector3] = []
var _edge_lobes: Array[MeshInstance3D] = []
var _fire_cooldown: float = 0.0
var _last_fired_direction := Vector3.FORWARD
var _movement_strength: float = 0.0
var _projectile_cursor: int = 0
var _projectile_directions: Array[Vector3] = []
var _projectile_lifetimes := PackedFloat32Array()
var _projectile_nodes: Array[MeshInstance3D] = []
var _recoil: float = 0.0
var _shot_count: int = 0


func _ready() -> void:
	_ensure_input_actions()
	_collect_slime_edge_lobes()
	_collect_projectile_pool()
	if _back_button != null:
		_back_button.pressed.connect(_return_to_index)
	_update_shot_count_label()


func _process(delta: float) -> void:
	_animation_time += delta
	_update_slime_animation(delta)


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


func debug_fire_at_world(world_position: Vector3) -> void:
	_apply_aim_world_position(world_position)
	_fire_projectile()


func debug_last_fired_direction() -> Vector3:
	return _last_fired_direction


func debug_player_position() -> Vector3:
	if _slime_root == null:
		return Vector3.ZERO
	return _slime_root.global_position


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
			0.035,
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


func _collect_slime_edge_lobes() -> void:
	_edge_lobes.clear()
	_edge_lobe_base_positions.clear()
	_edge_lobe_base_scales.clear()
	if _slime_skirt == null:
		return

	for child in _slime_skirt.get_children():
		if child is MeshInstance3D:
			var edge_lobe := child as MeshInstance3D
			_edge_lobes.append(edge_lobe)
			_edge_lobe_base_positions.append(edge_lobe.position)
			_edge_lobe_base_scales.append(edge_lobe.scale)


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
	projectile.global_position = _muzzle.global_position if _muzzle != null else _slime_root.global_position
	projectile.scale = Vector3.ONE
	projectile.visible = true
	_projectile_directions[projectile_index] = _aim_direction
	_projectile_lifetimes[projectile_index] = PROJECTILE_LIFETIME
	_projectile_cursor = (_projectile_cursor + 1) % _projectile_nodes.size()

	_last_fired_direction = _aim_direction
	_fire_cooldown = FIRE_INTERVAL
	_recoil = 0.16
	_shot_count += 1
	_update_shot_count_label()


func _flattened_direction(direction: Vector3, fallback: Vector3) -> Vector3:
	var flattened := Vector3(direction.x, 0.0, direction.z)
	if flattened.length_squared() <= 0.0001:
		return fallback.normalized()
	return flattened.normalized()


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

	var screen_input := Vector2.ZERO
	screen_input.y += Input.get_action_strength(ACTION_MOVE_FORWARD)
	screen_input.y -= Input.get_action_strength(ACTION_MOVE_BACK)
	screen_input.x -= Input.get_action_strength(ACTION_MOVE_LEFT)
	screen_input.x += Input.get_action_strength(ACTION_MOVE_RIGHT)
	_movement_strength = minf(1.0, screen_input.length())
	if screen_input.length_squared() <= 0.0:
		return

	var movement_direction: Vector3 = _screen_relative_ground_direction(screen_input.normalized())
	var movement: Vector3 = movement_direction * MOVE_SPEED * delta
	_slime_root.position += movement
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


func _update_shot_count_label() -> void:
	if _shot_count_label != null:
		_shot_count_label.text = "Shots fired: %d" % _shot_count


func _update_slime_edge_lobes(animation_speed: float, blend: float) -> void:
	if _edge_lobes.is_empty():
		return

	var outward_amplitude: float = lerpf(0.007, 0.034, _movement_strength)
	var vertical_amplitude: float = lerpf(0.010, 0.046, _movement_strength)
	var scale_amplitude: float = lerpf(0.018, 0.050, _movement_strength)
	for index in range(_edge_lobes.size()):
		var phase: float = (
			TAU * float(index) / float(_edge_lobes.size())
			+ sin(float(index) * 2.17) * 0.35
		)
		var lobe_wave: float = sin(_animation_time * animation_speed + phase)
		var base_position: Vector3 = _edge_lobe_base_positions[index]
		var radial_direction := Vector3(base_position.x, 0.0, base_position.z).normalized()
		var target_position := (
			base_position
			+ radial_direction * lobe_wave * outward_amplitude
			+ Vector3.UP * lobe_wave * vertical_amplitude
		)
		var scale_pulse: float = lobe_wave * scale_amplitude
		var target_scale: Vector3 = _edge_lobe_base_scales[index] * Vector3(
			1.0 + scale_pulse,
			1.0 - scale_pulse * 1.25,
			1.0 + scale_pulse
		)
		var edge_lobe: MeshInstance3D = _edge_lobes[index]
		edge_lobe.position = edge_lobe.position.lerp(target_position, blend)
		edge_lobe.scale = edge_lobe.scale.lerp(target_scale, blend)


func _update_slime_animation(delta: float) -> void:
	if _slime_visual == null:
		return

	var animation_speed: float = lerpf(3.0, 9.0, _movement_strength)
	var wave: float = sin(_animation_time * animation_speed)
	var squash_amount: float = lerpf(0.025, 0.085, _movement_strength)
	var target_scale := Vector3(
		1.0 + wave * squash_amount,
		1.0 - wave * squash_amount * 0.85,
		1.0 + wave * squash_amount
	)
	var blend: float = minf(1.0, delta * 12.0)
	_slime_visual.scale = _slime_visual.scale.lerp(target_scale, blend)
	_update_slime_edge_lobes(animation_speed, blend)
	_recoil = move_toward(_recoil, 0.0, delta * 1.8)
	_slime_visual.position = Vector3(0.0, absf(wave) * 0.025 * _movement_strength, _recoil)
