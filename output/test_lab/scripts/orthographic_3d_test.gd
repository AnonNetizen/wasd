extends Node3D

const ACTION_BACK: String = "lab_back"
const ACTION_MOVE_BACK: String = "lab_move_back"
const ACTION_MOVE_FORWARD: String = "lab_move_forward"
const ACTION_MOVE_LEFT: String = "lab_move_left"
const ACTION_MOVE_RIGHT: String = "lab_move_right"
const MOVE_SPEED: float = 4.0
const PLAYER_BOUNDS: float = 5.5

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
	var input_vector := Vector2.ZERO
	input_vector.y -= Input.get_action_strength(ACTION_MOVE_FORWARD)
	input_vector.y += Input.get_action_strength(ACTION_MOVE_BACK)
	input_vector.x -= Input.get_action_strength(ACTION_MOVE_LEFT)
	input_vector.x += Input.get_action_strength(ACTION_MOVE_RIGHT)
	if input_vector.length_squared() <= 0.0:
		return

	input_vector = input_vector.normalized()
	var movement := Vector3(input_vector.x, 0.0, input_vector.y) * MOVE_SPEED * delta
	_player_root.position += movement
	_player_root.position.x = clampf(_player_root.position.x, -PLAYER_BOUNDS, PLAYER_BOUNDS)
	_player_root.position.z = clampf(_player_root.position.z, -PLAYER_BOUNDS, PLAYER_BOUNDS)
	_player_root.rotation.y = atan2(input_vector.x, input_vector.y)


func _return_to_index() -> void:
	get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")


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
