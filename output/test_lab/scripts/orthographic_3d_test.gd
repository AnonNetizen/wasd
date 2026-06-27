extends Node3D

const ACTION_BACK: String = "lab_back"
const ACTION_MOVE_BACK: String = "lab_move_back"
const ACTION_MOVE_FORWARD: String = "lab_move_forward"
const ACTION_MOVE_LEFT: String = "lab_move_left"
const ACTION_MOVE_RIGHT: String = "lab_move_right"
const MOVE_SPEED: float = 4.0
const MOUSE_AIM_DEADZONE: float = 0.08
const PLAYER_BOUNDS: float = 5.5
const SCREEN_AXIS_SAMPLE_OFFSET: float = 64.0

@onready var _camera: Camera3D = get_node_or_null("OrthographicCamera") as Camera3D
@onready var _player_root: Node3D = get_node_or_null("World3D/Player3D") as Node3D
@onready var _back_button: Button = get_node_or_null("Overlay/Panel/Margin/Rows/BackButton") as Button


func _ready() -> void:
	_ensure_input_actions()
	if _back_button != null:
		_back_button.pressed.connect(_return_to_index)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(ACTION_BACK):
		_return_to_index()
		return
	_update_player(delta)
	_update_mouse_aim()


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


func _update_player(delta: float) -> void:
	if _player_root == null:
		return
	var screen_input := Vector2.ZERO
	screen_input.y += Input.get_action_strength(ACTION_MOVE_FORWARD)
	screen_input.y -= Input.get_action_strength(ACTION_MOVE_BACK)
	screen_input.x -= Input.get_action_strength(ACTION_MOVE_LEFT)
	screen_input.x += Input.get_action_strength(ACTION_MOVE_RIGHT)
	if screen_input.length_squared() <= 0.0:
		return

	screen_input = screen_input.normalized()
	var movement_direction := _screen_relative_ground_direction(screen_input)
	if movement_direction.length_squared() <= 0.0:
		return

	var movement := movement_direction * MOVE_SPEED * delta
	_player_root.position += movement
	_player_root.position.x = clampf(_player_root.position.x, -PLAYER_BOUNDS, PLAYER_BOUNDS)
	_player_root.position.z = clampf(_player_root.position.z, -PLAYER_BOUNDS, PLAYER_BOUNDS)


func _update_mouse_aim() -> void:
	if _player_root == null:
		return
	var mouse_ground := _ground_point_from_screen(get_viewport().get_mouse_position())
	var raw_aim := mouse_ground - _player_root.global_position
	var aim_direction := Vector3(raw_aim.x, 0.0, raw_aim.z)
	if aim_direction.length_squared() <= MOUSE_AIM_DEADZONE * MOUSE_AIM_DEADZONE:
		return
	aim_direction = aim_direction.normalized()
	_player_root.rotation.y = atan2(-aim_direction.x, -aim_direction.z)


func _return_to_index() -> void:
	get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")


func _screen_relative_ground_direction(screen_input: Vector2) -> Vector3:
	if _camera == null:
		return Vector3(screen_input.x, 0.0, -screen_input.y).normalized()
	var viewport := get_viewport()
	if viewport == null:
		return Vector3(screen_input.x, 0.0, -screen_input.y).normalized()

	var screen_center: Vector2 = viewport.get_visible_rect().size * 0.5
	var center_point := _ground_point_from_screen(screen_center)
	var right_point := _ground_point_from_screen(screen_center + Vector2(SCREEN_AXIS_SAMPLE_OFFSET, 0.0))
	var up_point := _ground_point_from_screen(screen_center + Vector2(0.0, -SCREEN_AXIS_SAMPLE_OFFSET))
	var right_axis := _flattened_direction(right_point - center_point, Vector3.RIGHT)
	var up_axis := _flattened_direction(up_point - center_point, Vector3.FORWARD)
	return (right_axis * screen_input.x + up_axis * screen_input.y).normalized()


func _ground_point_from_screen(screen_point: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_point)
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_point)
	if is_zero_approx(ray_direction.y):
		return ray_origin
	var distance_to_ground: float = -ray_origin.y / ray_direction.y
	return ray_origin + ray_direction * distance_to_ground


func _flattened_direction(direction: Vector3, fallback: Vector3) -> Vector3:
	var flattened := Vector3(direction.x, 0.0, direction.z)
	if flattened.length_squared() <= 0.0001:
		return fallback.normalized()
	return flattened.normalized()


func _register_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var has_key := false
	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			has_key = true
			break
	if has_key:
		return
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action_name, event)
