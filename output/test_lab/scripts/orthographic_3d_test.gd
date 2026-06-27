extends Node3D

const ACTION_BACK: String = "lab_back"
const ACTION_MOVE_BACK: String = "lab_move_back"
const ACTION_MOVE_FORWARD: String = "lab_move_forward"
const ACTION_MOVE_LEFT: String = "lab_move_left"
const ACTION_MOVE_RIGHT: String = "lab_move_right"
const CAMERA_DISTANCE: float = 18.0
const CAMERA_ELEVATION_DEGREES: float = 30.0
const CAMERA_ORTHO_SIZE: float = 13.5
const CAMERA_YAW_DEGREES: float = 45.0
const CELL_SIZE: float = 2.0
const GRID_HALF_CELLS: int = 6
const MOVE_SPEED: float = 4.0
const PLAYER_BOUNDS: float = 5.5

var _camera: Camera3D
var _player_root: Node3D
var _world_root: Node3D


func _ready() -> void:
	_ensure_input_actions()
	_build_scene()
	set_process(true)


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


func _build_scene() -> void:
	_world_root = Node3D.new()
	_world_root.name = "World3D"
	add_child(_world_root)

	_add_camera()
	_add_lighting()
	_add_floor()
	_add_grid()
	_add_cache(Vector3(-1.8, 0.0, 1.2))
	_add_wall(Vector3(2.1, 0.7, 1.3), Vector3(3.2, 1.4, 0.28))
	_add_column(Vector3(2.8, 0.8, -1.9))
	_add_column(Vector3(-3.2, 0.8, -2.6))
	_add_player(Vector3(-2.0, 0.0, -1.4))
	_add_overlay()


func _add_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "OrthographicCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_ORTHO_SIZE
	_camera.current = true
	_camera.position = _camera_offset()
	add_child(_camera)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _add_lighting() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = Color(0.045, 0.041, 0.048)
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color(0.46, 0.43, 0.38)
	world_environment.ambient_light_energy = 0.8
	environment.environment = world_environment
	add_child(environment)

	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.light_energy = 2.2
	light.shadow_enabled = true
	light.position = Vector3(-5.0, 8.0, 4.0)
	add_child(light)
	light.look_at(Vector3.ZERO, Vector3.UP)


func _add_floor() -> void:
	var floor_size: float = float(GRID_HALF_CELLS * 2) * CELL_SIZE
	_add_box(
		"Floor",
		Vector3.ZERO + Vector3(0.0, -0.035, 0.0),
		Vector3(floor_size, 0.06, floor_size),
		Color(0.115, 0.101, 0.09),
		_world_root
	)

	var safe_zone := _add_box(
		"ProjectedCellFootprint",
		Vector3(0.0, 0.01, 0.0),
		Vector3(CELL_SIZE, 0.018, CELL_SIZE),
		Color(0.42, 0.32, 0.19, 0.34),
		_world_root,
		true
	)
	safe_zone.rotation_degrees.y = 0.0


func _add_grid() -> void:
	var line_material := _make_material(Color(0.56, 0.47, 0.35, 0.62), true, true)
	var grid_size: float = float(GRID_HALF_CELLS * 2) * CELL_SIZE
	var line_thickness: float = 0.035
	for index in range(-GRID_HALF_CELLS, GRID_HALF_CELLS + 1):
		var offset: float = float(index) * CELL_SIZE
		_add_box_with_material(
			"GridX%s" % index,
			Vector3(offset, 0.025, 0.0),
			Vector3(line_thickness, 0.025, grid_size),
			line_material,
			_world_root
		)
		_add_box_with_material(
			"GridZ%s" % index,
			Vector3(0.0, 0.026, offset),
			Vector3(grid_size, 0.025, line_thickness),
			line_material,
			_world_root
		)


func _add_cache(origin: Vector3) -> void:
	var cache_root := Node3D.new()
	cache_root.name = "CacheBox3D"
	cache_root.position = origin
	_world_root.add_child(cache_root)

	_add_box(
		"CacheFootprint",
		Vector3(0.0, 0.02, 0.0),
		Vector3(CELL_SIZE * 0.92, 0.025, CELL_SIZE * 0.92),
		Color(0.08, 0.07, 0.055, 0.32),
		cache_root,
		true
	)
	_add_box("CacheBody", Vector3(0.0, 0.24, 0.0), Vector3(1.2, 0.48, 0.86), Color(0.42, 0.32, 0.22), cache_root)
	_add_box("CacheLid", Vector3(0.0, 0.54, -0.08), Vector3(1.32, 0.18, 0.92), Color(0.72, 0.54, 0.34), cache_root)
	_add_box("CacheAccent", Vector3(0.0, 0.66, -0.09), Vector3(0.32, 0.04, 0.18), Color(0.25, 0.56, 0.92), cache_root)


func _add_wall(position: Vector3, size: Vector3) -> void:
	_add_box("ForegroundWall", position, size, Color(0.27, 0.24, 0.22), _world_root)
	_add_box(
		"WallTop",
		position + Vector3(0.0, size.y * 0.5 + 0.035, 0.0),
		Vector3(size.x, 0.07, size.z * 1.25),
		Color(0.52, 0.43, 0.31),
		_world_root
	)


func _add_column(position: Vector3) -> void:
	var column := MeshInstance3D.new()
	column.name = "Column"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.42
	mesh.height = 1.6
	mesh.radial_segments = 8
	column.mesh = mesh
	column.material_override = _make_material(Color(0.38, 0.33, 0.28))
	column.position = position
	_world_root.add_child(column)


func _add_player(position: Vector3) -> void:
	_player_root = Node3D.new()
	_player_root.name = "Player3D"
	_player_root.position = position
	_world_root.add_child(_player_root)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.36
	body.mesh = capsule
	body.material_override = _make_material(Color(0.28, 0.55, 0.88))
	body.position = Vector3(0.0, 0.78, 0.0)
	_player_root.add_child(body)

	_add_box("AimMarker", Vector3(0.0, 0.34, -0.48), Vector3(0.22, 0.16, 0.58), Color(0.92, 0.74, 0.42), _player_root)
	_add_box("PlayerShadow", Vector3(0.0, 0.025, 0.0), Vector3(0.88, 0.02, 0.64), Color(0.02, 0.018, 0.015, 0.42), _player_root, true)


func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.02
	panel.anchor_top = 0.02
	panel.anchor_right = 0.33
	panel.anchor_bottom = 0.18
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	var label := Label.new()
	label.text = "3D Orthographic Grid\n45 deg yaw / 30 deg elevation\nWASD move, Esc back"
	label.add_theme_color_override("font_color", Color(0.92, 0.83, 0.68))
	rows.add_child(label)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(_return_to_index)
	rows.add_child(back_button)


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


func _camera_offset() -> Vector3:
	var yaw: float = deg_to_rad(CAMERA_YAW_DEGREES)
	var elevation: float = deg_to_rad(CAMERA_ELEVATION_DEGREES)
	var horizontal_distance: float = CAMERA_DISTANCE * cos(elevation)
	return Vector3(
		cos(yaw) * horizontal_distance,
		sin(elevation) * CAMERA_DISTANCE,
		sin(yaw) * horizontal_distance
	)


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


func _add_box(name: String, position: Vector3, size: Vector3, color: Color, parent: Node, transparent: bool = false) -> MeshInstance3D:
	return _add_box_with_material(name, position, size, _make_material(color, transparent), parent)


func _add_box_with_material(name: String, position: Vector3, size: Vector3, material: Material, parent: Node) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	return mesh_instance


func _make_material(color: Color, transparent: bool = false, unshaded: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
