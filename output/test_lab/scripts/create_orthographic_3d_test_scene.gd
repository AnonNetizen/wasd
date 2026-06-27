extends SceneTree

const CAMERA_DISTANCE: float = 18.0
const CAMERA_ELEVATION_DEGREES: float = 30.0
const CAMERA_ORTHO_SIZE: float = 13.5
const CAMERA_YAW_DEGREES: float = 45.0
const CELL_SIZE: float = 2.0
const GRID_HALF_CELLS: int = 6
const OUTPUT_SCENE_PATH := "res://scenes/orthographic_3d_test.tscn"
const SCENE_SCRIPT_PATH := "res://scripts/orthographic_3d_test.gd"


func _initialize() -> void:
	var scene_root := _build_scene()
	root.add_child(scene_root)
	current_scene = scene_root
	_aim_camera(scene_root)
	_assign_owner(scene_root, scene_root)

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack scene: %s" % pack_error)
		quit(pack_error)
		return

	var save_error := ResourceSaver.save(packed_scene, OUTPUT_SCENE_PATH)
	if save_error != OK:
		push_error("Failed to save scene: %s" % save_error)
		quit(save_error)
		return

	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	quit(0)


func _build_scene() -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "Orthographic3DTest"
	root_node.set_script(load(SCENE_SCRIPT_PATH))

	var camera := Camera3D.new()
	camera.name = "OrthographicCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_ORTHO_SIZE
	camera.current = true
	camera.position = _camera_offset()
	root_node.add_child(camera)

	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = Color(0.045, 0.041, 0.048)
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color(0.46, 0.43, 0.38)
	world_environment.ambient_light_energy = 0.8
	environment.environment = world_environment
	root_node.add_child(environment)

	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.light_energy = 2.2
	light.shadow_enabled = true
	light.position = Vector3(-5.0, 8.0, 4.0)
	root_node.add_child(light)

	var world_root := Node3D.new()
	world_root.name = "World3D"
	root_node.add_child(world_root)
	_add_floor(world_root)
	_add_grid(world_root)
	_add_cache(world_root, Vector3(-1.8, 0.0, 1.2))
	_add_wall(world_root, Vector3(2.1, 0.7, 1.3), Vector3(3.2, 1.4, 0.28))
	_add_column(world_root, "SideColumn", Vector3(2.8, 0.8, -1.9))
	_add_column(world_root, "RearColumn", Vector3(-3.2, 0.8, -2.6))
	_add_player(world_root, Vector3(-2.0, 0.0, -1.4))
	_add_overlay(root_node)
	return root_node


func _aim_camera(scene_root: Node3D) -> void:
	var camera := scene_root.get_node("OrthographicCamera") as Camera3D
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	var light := scene_root.get_node("KeyLight") as DirectionalLight3D
	light.look_at_from_position(light.position, Vector3.ZERO, Vector3.UP)


func _add_floor(world_root: Node3D) -> void:
	var floor_size: float = float(GRID_HALF_CELLS * 2) * CELL_SIZE
	_add_box(
		"Floor",
		Vector3(0.0, -0.035, 0.0),
		Vector3(floor_size, 0.06, floor_size),
		Color(0.115, 0.101, 0.09),
		world_root
	)
	_add_box(
		"ProjectedCellFootprint",
		Vector3(0.0, 0.01, 0.0),
		Vector3(CELL_SIZE, 0.018, CELL_SIZE),
		Color(0.42, 0.32, 0.19, 0.34),
		world_root,
		true
	)


func _add_grid(world_root: Node3D) -> void:
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
			world_root
		)
		_add_box_with_material(
			"GridZ%s" % index,
			Vector3(0.0, 0.026, offset),
			Vector3(grid_size, 0.025, line_thickness),
			line_material,
			world_root
		)


func _add_cache(world_root: Node3D, origin: Vector3) -> void:
	var cache_root := Node3D.new()
	cache_root.name = "CacheBox3D"
	cache_root.position = origin
	world_root.add_child(cache_root)

	_add_box("CacheFootprint", Vector3(0.0, 0.02, 0.0), Vector3(CELL_SIZE * 0.92, 0.025, CELL_SIZE * 0.92), Color(0.08, 0.07, 0.055, 0.32), cache_root, true)
	_add_box("CacheBody", Vector3(0.0, 0.24, 0.0), Vector3(1.2, 0.48, 0.86), Color(0.42, 0.32, 0.22), cache_root)
	_add_box("CacheLid", Vector3(0.0, 0.54, -0.08), Vector3(1.32, 0.18, 0.92), Color(0.72, 0.54, 0.34), cache_root)
	_add_box("CacheAccent", Vector3(0.0, 0.66, -0.09), Vector3(0.32, 0.04, 0.18), Color(0.25, 0.56, 0.92), cache_root)


func _add_wall(world_root: Node3D, position: Vector3, size: Vector3) -> void:
	_add_box("ForegroundWall", position, size, Color(0.27, 0.24, 0.22), world_root)
	_add_box(
		"WallTop",
		position + Vector3(0.0, size.y * 0.5 + 0.035, 0.0),
		Vector3(size.x, 0.07, size.z * 1.25),
		Color(0.52, 0.43, 0.31),
		world_root
	)


func _add_column(world_root: Node3D, column_name: String, position: Vector3) -> void:
	var column := MeshInstance3D.new()
	column.name = column_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.42
	mesh.height = 1.6
	mesh.radial_segments = 8
	column.mesh = mesh
	column.material_override = _make_material(Color(0.38, 0.33, 0.28))
	column.position = position
	world_root.add_child(column)


func _add_player(world_root: Node3D, position: Vector3) -> void:
	var player_root := Node3D.new()
	player_root.name = "Player3D"
	player_root.position = position
	world_root.add_child(player_root)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.36
	body.mesh = capsule
	body.material_override = _make_material(Color(0.28, 0.55, 0.88))
	body.position = Vector3(0.0, 0.78, 0.0)
	player_root.add_child(body)

	_add_box("AimMarker", Vector3(0.0, 0.34, -0.48), Vector3(0.22, 0.16, 0.58), Color(0.92, 0.74, 0.42), player_root)
	_add_box("PlayerShadow", Vector3(0.0, 0.025, 0.0), Vector3(0.88, 0.02, 0.64), Color(0.02, 0.018, 0.015, 0.42), player_root, true)


func _add_overlay(root_node: Node3D) -> void:
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	root_node.add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.02
	panel.anchor_top = 0.02
	panel.anchor_right = 0.33
	panel.anchor_bottom = 0.18
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	var label := Label.new()
	label.name = "Info"
	label.text = "3D Orthographic Grid\n45 deg yaw / 30 deg elevation\nWASD move, Esc back"
	label.add_theme_color_override("font_color", Color(0.92, 0.83, 0.68))
	rows.add_child(label)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = "Back"
	rows.add_child(back_button)


func _camera_offset() -> Vector3:
	var yaw: float = deg_to_rad(CAMERA_YAW_DEGREES)
	var elevation: float = deg_to_rad(CAMERA_ELEVATION_DEGREES)
	var horizontal_distance: float = CAMERA_DISTANCE * cos(elevation)
	return Vector3(
		cos(yaw) * horizontal_distance,
		sin(elevation) * CAMERA_DISTANCE,
		sin(yaw) * horizontal_distance
	)


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


func _assign_owner(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for child in node.get_children():
		_assign_owner(child, owner_node)
