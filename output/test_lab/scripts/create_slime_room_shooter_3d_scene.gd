extends SceneTree

const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const OUTPUT_SCENE_PATH: String = "res://scenes/slime_room_shooter_3d.tscn"
const PROJECTILE_POOL_SIZE: int = 24
const ROOM_FX_SCRIPT_PATH: String = "res://scripts/dungeon_room_fx_3d.gd"
const SCENE_SCRIPT_PATH: String = "res://scripts/slime_room_shooter_3d.gd"
const SLIME_CONTROL_POINT_COUNT: int = 24
const SLIME_MEMBRANE_SCRIPT_PATH: String = "res://scripts/slime_membrane_3d.gd"


func _initialize() -> void:
	var scene_root: Node3D = _build_scene()
	root.add_child(scene_root)
	current_scene = scene_root
	_aim_scene_nodes(scene_root)
	_assign_owner(scene_root, scene_root)

	var save_error: Error = _save_packed_scene(scene_root, OUTPUT_SCENE_PATH)
	if save_error != OK:
		quit(save_error)
		return

	var index_error: Error = _register_index_button()
	if index_error != OK:
		quit(index_error)
		return

	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	print("Registered Test Lab entry: SlimeRoomShooterButton")
	quit(0)


func _add_aim_marker(world_root: Node3D) -> void:
	var marker_material: StandardMaterial3D = _make_material(
		Color(0.66, 0.43, 0.18, 0.72),
		Color(0.95, 0.48, 0.16),
		0.72,
		0.38
	)
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var marker_mesh := TorusMesh.new()
	marker_mesh.inner_radius = 0.19
	marker_mesh.outer_radius = 0.28
	marker_mesh.rings = 8
	marker_mesh.ring_segments = 24
	var marker: MeshInstance3D = _add_mesh(
		world_root,
		"AimMarker",
		marker_mesh,
		marker_material,
		Vector3(0.0, 0.075, 0.0),
		Vector3(1.0, 0.22, 1.0)
	)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tick_material: StandardMaterial3D = _make_material(
		Color(0.92, 0.66, 0.28),
		Color(1.0, 0.42, 0.10),
		0.82,
		0.32
	)
	for tick_index in range(4):
		var tick_angle: float = float(tick_index) * PI * 0.5
		var tick: MeshInstance3D = _add_box(
			marker,
			"Tick%d" % tick_index,
			Vector3(0.055, 0.026, 0.15),
			Vector3(sin(tick_angle) * 0.36, 0.018, cos(tick_angle) * 0.36),
			tick_material
		)
		tick.rotation.y = tick_angle
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_camera(root_node: Node3D) -> void:
	var camera := Camera3D.new()
	camera.name = "PerspectiveCamera"
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.2
	camera.near = 0.1
	camera.far = 100.0
	camera.position = Vector3(0.0, 15.5, 10.3)
	root_node.add_child(camera)


func _add_environment(root_node: Node3D) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.020, 0.014, 0.018)
	sky_material.sky_horizon_color = Color(0.065, 0.040, 0.042)
	sky_material.ground_bottom_color = Color(0.008, 0.006, 0.009)
	sky_material.ground_horizon_color = Color(0.040, 0.026, 0.030)
	sky_material.sky_energy_multiplier = 0.22
	sky_material.ground_energy_multiplier = 0.16

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_SKY
	environment_resource.sky = sky
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.27, 0.25, 0.31)
	environment_resource.ambient_light_energy = 0.40
	environment_resource.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_resource.glow_enabled = true
	environment_resource.glow_intensity = 0.26
	environment_resource.glow_strength = 0.48
	environment_resource.adjustment_enabled = true
	environment_resource.adjustment_brightness = 1.04
	environment_resource.adjustment_contrast = 1.06
	environment_resource.adjustment_saturation = 0.90

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment_resource
	root_node.add_child(world_environment)


func _add_floor_tiles(room_root: Node3D) -> void:
	var tile_root := Node3D.new()
	tile_root.name = "StoneTiles"
	room_root.add_child(tile_root)
	var tile_materials: Array[StandardMaterial3D] = [
		_make_material(Color(0.185, 0.160, 0.182), Color.BLACK, 0.0, 0.92),
		_make_material(Color(0.215, 0.178, 0.188), Color.BLACK, 0.0, 0.88),
		_make_material(Color(0.158, 0.145, 0.166), Color.BLACK, 0.0, 0.95),
		_make_material(Color(0.245, 0.195, 0.184), Color.BLACK, 0.0, 0.86),
	]
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(1.92, 0.06, 1.92)
	for x_index in range(8):
		for z_index in range(6):
			var tile_variant: int = posmod(x_index * 5 + z_index * 3 + x_index * z_index, tile_materials.size())
			var tile: MeshInstance3D = _add_mesh(
				tile_root,
				"Tile%02d%02d" % [x_index, z_index],
				tile_mesh,
				tile_materials[tile_variant],
				Vector3(-7.0 + float(x_index) * 2.0, 0.025, -5.0 + float(z_index) * 2.0)
			)
			tile.rotation.y = (float((x_index + z_index) % 3) - 1.0) * 0.006

	var crack_material: StandardMaterial3D = _make_material(Color(0.032, 0.024, 0.030), Color.BLACK, 0.0, 1.0)
	var crack_specs: Array[Vector4] = [
		Vector4(-5.8, -4.1, 0.58, 0.34),
		Vector4(4.7, -4.8, 0.72, -0.42),
		Vector4(-6.3, 1.2, 0.46, -0.22),
		Vector4(5.4, 2.1, 0.64, 0.52),
		Vector4(-3.7, 4.2, 0.52, 0.18),
		Vector4(3.2, 3.8, 0.45, -0.58),
	]
	for crack_index in range(crack_specs.size()):
		var spec: Vector4 = crack_specs[crack_index]
		var crack: MeshInstance3D = _add_box(
			tile_root,
			"Crack%02d" % crack_index,
			Vector3(spec.z, 0.012, 0.035),
			Vector3(spec.x, 0.064, spec.y),
			crack_material
		)
		crack.rotation.y = spec.w


func _add_lights(root_node: Node3D) -> void:
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.light_color = Color(0.72, 0.67, 0.78)
	key_light.light_energy = 0.82
	key_light.shadow_enabled = true
	key_light.position = Vector3(-7.0, 12.0, 5.0)
	root_node.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_color = Color(0.20, 0.25, 0.42)
	fill_light.light_energy = 0.18
	fill_light.shadow_enabled = false
	fill_light.position = Vector3(8.0, 7.0, -6.0)
	root_node.add_child(fill_light)

	var slime_light := OmniLight3D.new()
	slime_light.name = "SlimeGlowLight"
	slime_light.light_color = Color(0.28, 1.0, 0.42)
	slime_light.light_energy = 0.16
	slime_light.omni_range = 2.4
	slime_light.position = Vector3(0.0, 1.2, -1.8)
	root_node.add_child(slime_light)


func _add_mesh(
	parent: Node,
	node_name: String,
	mesh: Mesh,
	material: Material,
	position: Vector3,
	scale: Vector3 = Vector3.ONE
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.scale = scale
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_overlay(root_node: Node3D) -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	overlay.layer = 10
	root_node.add_child(overlay)

	var room_plate := PanelContainer.new()
	room_plate.name = "RoomPlate"
	room_plate.anchor_left = 0.018
	room_plate.anchor_top = 0.025
	room_plate.anchor_right = 0.225
	room_plate.anchor_bottom = 0.132
	room_plate.add_theme_stylebox_override(
		"panel",
		_make_hud_panel_style(Color(0.060, 0.046, 0.050, 0.96), Color(0.43, 0.30, 0.19), 2)
	)
	overlay.add_child(room_plate)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	room_plate.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 2)
	margin.add_child(rows)

	var cell_label := Label.new()
	cell_label.name = "CellLabel"
	cell_label.text = "CELL A-03  ·  EMBER VAULT"
	cell_label.add_theme_color_override("font_color", Color(0.66, 0.56, 0.43))
	cell_label.add_theme_font_size_override("font_size", 11)
	rows.add_child(cell_label)

	var title := Label.new()
	title.name = "Title"
	title.text = "SLIME BALLISTICS"
	title.add_theme_color_override("font_color", Color(0.94, 0.87, 0.74))
	title.add_theme_color_override("font_shadow_color", Color(0.02, 0.015, 0.018, 0.92))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_font_size_override("font_size", 18)
	rows.add_child(title)

	var exit_button := Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "LEAVE  [ESC]"
	exit_button.anchor_left = 0.86
	exit_button.anchor_top = 0.028
	exit_button.anchor_right = 0.982
	exit_button.anchor_bottom = 0.082
	exit_button.add_theme_color_override("font_color", Color(0.88, 0.78, 0.62))
	exit_button.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.56))
	exit_button.add_theme_font_size_override("font_size", 13)
	exit_button.add_theme_stylebox_override(
		"normal",
		_make_hud_panel_style(Color(0.055, 0.040, 0.044, 0.94), Color(0.34, 0.24, 0.17), 2)
	)
	exit_button.add_theme_stylebox_override(
		"hover",
		_make_hud_panel_style(Color(0.12, 0.075, 0.055, 0.98), Color(0.78, 0.52, 0.24), 2)
	)
	exit_button.add_theme_stylebox_override(
		"pressed",
		_make_hud_panel_style(Color(0.045, 0.032, 0.035, 1.0), Color(0.93, 0.62, 0.28), 2)
	)
	overlay.add_child(exit_button)

	var hint_panel := PanelContainer.new()
	hint_panel.name = "ControlHint"
	hint_panel.anchor_left = 0.018
	hint_panel.anchor_top = 0.915
	hint_panel.anchor_right = 0.39
	hint_panel.anchor_bottom = 0.972
	hint_panel.add_theme_stylebox_override(
		"panel",
		_make_hud_panel_style(Color(0.050, 0.038, 0.042, 0.88), Color(0.29, 0.21, 0.16), 1)
	)
	overlay.add_child(hint_panel)
	var hint_margin := MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_left", 12)
	hint_margin.add_theme_constant_override("margin_right", 12)
	hint_margin.add_theme_constant_override("margin_top", 7)
	hint_margin.add_theme_constant_override("margin_bottom", 7)
	hint_panel.add_child(hint_margin)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "WASD MOVE   ·   MOUSE AIM   ·   HOLD LMB FIRE"
	hint.add_theme_color_override("font_color", Color(0.73, 0.66, 0.55))
	hint.add_theme_font_size_override("font_size", 13)
	hint_margin.add_child(hint)

	var ammo_panel := PanelContainer.new()
	ammo_panel.name = "AmmoPanel"
	ammo_panel.anchor_left = 0.84
	ammo_panel.anchor_top = 0.835
	ammo_panel.anchor_right = 0.982
	ammo_panel.anchor_bottom = 0.972
	ammo_panel.add_theme_stylebox_override(
		"panel",
		_make_hud_panel_style(Color(0.060, 0.044, 0.046, 0.96), Color(0.43, 0.30, 0.19), 2)
	)
	overlay.add_child(ammo_panel)
	var ammo_margin := MarginContainer.new()
	ammo_margin.name = "Margin"
	ammo_margin.add_theme_constant_override("margin_left", 14)
	ammo_margin.add_theme_constant_override("margin_top", 9)
	ammo_margin.add_theme_constant_override("margin_right", 14)
	ammo_margin.add_theme_constant_override("margin_bottom", 9)
	ammo_panel.add_child(ammo_margin)
	var ammo_rows := VBoxContainer.new()
	ammo_rows.name = "Rows"
	ammo_rows.add_theme_constant_override("separation", 1)
	ammo_margin.add_child(ammo_rows)
	var ammo_title := Label.new()
	ammo_title.name = "AmmoTitle"
	ammo_title.text = "AMMO   ∞"
	ammo_title.add_theme_color_override("font_color", Color(0.94, 0.87, 0.74))
	ammo_title.add_theme_font_size_override("font_size", 20)
	ammo_rows.add_child(ammo_title)
	var shot_count := Label.new()
	shot_count.name = "ShotCount"
	shot_count.text = "FIRED  000"
	shot_count.add_theme_color_override("font_color", Color(0.93, 0.58, 0.22))
	shot_count.add_theme_color_override("font_outline_color", Color(0.055, 0.026, 0.018))
	shot_count.add_theme_constant_override("outline_size", 2)
	shot_count.add_theme_font_size_override("font_size", 16)
	ammo_rows.add_child(shot_count)


func _add_projectile_pool(world_root: Node3D) -> void:
	var projectiles_root := Node3D.new()
	projectiles_root.name = "Projectiles"
	world_root.add_child(projectiles_root)

	var projectile_mesh := BoxMesh.new()
	projectile_mesh.size = Vector3(0.17, 0.14, 0.52)
	var projectile_material: StandardMaterial3D = _make_material(
		Color(0.96, 0.46, 0.08),
		Color(1.0, 0.28, 0.025),
		3.8,
		0.26
	)
	var projectile_core_mesh := BoxMesh.new()
	projectile_core_mesh.size = Vector3(0.08, 0.08, 0.38)
	var projectile_core_material: StandardMaterial3D = _make_material(
		Color(1.0, 0.95, 0.66),
		Color(1.0, 0.72, 0.18),
		4.8,
		0.14
	)
	for index in range(PROJECTILE_POOL_SIZE):
		var projectile: MeshInstance3D = _add_mesh(
			projectiles_root,
			"Projectile%02d" % index,
			projectile_mesh,
			projectile_material,
			Vector3(0.0, 0.72, 0.0)
		)
		projectile.visible = false
		projectile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var projectile_core: MeshInstance3D = _add_mesh(
			projectile,
			"Core",
			projectile_core_mesh,
			projectile_core_material,
			Vector3.ZERO
		)
		projectile_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_room(world_root: Node3D) -> void:
	var room_root := Node3D.new()
	room_root.name = "Room"
	var room_fx_script := load(ROOM_FX_SCRIPT_PATH) as Script
	if room_fx_script == null:
		push_error("Failed to load dungeon room FX script: %s" % ROOM_FX_SCRIPT_PATH)
	else:
		room_root.set_script(room_fx_script)
	world_root.add_child(room_root)

	var darkness_material: StandardMaterial3D = _make_material(Color(0.012, 0.009, 0.013), Color.BLACK, 0.0, 1.0)
	var floor_material: StandardMaterial3D = _make_material(Color(0.050, 0.040, 0.048), Color.BLACK, 0.0, 0.96)
	var wall_material: StandardMaterial3D = _make_material(Color(0.155, 0.112, 0.108), Color.BLACK, 0.0, 0.88)
	var trim_material: StandardMaterial3D = _make_material(
		Color(0.30, 0.205, 0.145),
		Color(0.12, 0.055, 0.028),
		0.08,
		0.68
	)
	_add_box(room_root, "SurroundingDarkness", Vector3(48.0, 0.12, 48.0), Vector3(0.0, -0.40, 0.0), darkness_material)
	_add_box(room_root, "Floor", Vector3(17.0, 0.24, 13.0), Vector3(0.0, -0.12, 0.0), floor_material)
	_add_floor_tiles(room_root)
	_add_carpet(room_root)
	_add_box(room_root, "RearWall", Vector3(17.0, 2.55, 0.46), Vector3(0.0, 1.275, -6.25), wall_material)
	_add_box(room_root, "LeftWall", Vector3(0.46, 2.55, 13.0), Vector3(-8.25, 1.275, 0.0), wall_material)
	_add_box(room_root, "RightWall", Vector3(0.46, 2.55, 13.0), Vector3(8.25, 1.275, 0.0), wall_material)
	_add_box(room_root, "FrontWallLeft", Vector3(6.9, 0.62, 0.46), Vector3(-5.05, 0.31, 6.25), wall_material)
	_add_box(room_root, "FrontWallRight", Vector3(6.9, 0.62, 0.46), Vector3(5.05, 0.31, 6.25), wall_material)
	_add_box(room_root, "RearTrim", Vector3(17.3, 0.20, 0.62), Vector3(0.0, 2.56, -6.25), trim_material)
	_add_box(room_root, "LeftTrim", Vector3(0.62, 0.20, 13.0), Vector3(-8.25, 2.56, 0.0), trim_material)
	_add_box(room_root, "RightTrim", Vector3(0.62, 0.20, 13.0), Vector3(8.25, 2.56, 0.0), trim_material)
	_add_wall_blocks(room_root)
	_add_dungeon_gate(room_root)
	_add_entrance_steps(room_root)
	_add_brazier(room_root, "LeftBrazier", Vector3(-5.75, 0.0, -4.35))
	_add_brazier(room_root, "RightBrazier", Vector3(5.75, 0.0, -4.35))
	_add_dungeon_target(room_root, "LeftTarget", Vector3(-6.25, 0.0, -1.45))
	_add_dungeon_target(room_root, "RightTarget", Vector3(6.25, 0.0, -0.75))
	_add_crate_cluster(room_root, "LeftCrates", Vector3(-6.55, 0.0, 3.70), -0.08)
	_add_crate_cluster(room_root, "RightCrates", Vector3(6.45, 0.0, 3.55), 0.12)


func _add_brazier(parent: Node3D, brazier_name: String, position: Vector3) -> void:
	var brazier_root := Node3D.new()
	brazier_root.name = brazier_name
	brazier_root.position = position
	parent.add_child(brazier_root)

	var shadow_material: StandardMaterial3D = _make_material(Color(0.012, 0.008, 0.010, 0.62), Color.BLACK, 0.0, 1.0)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var stone_material: StandardMaterial3D = _make_material(Color(0.19, 0.14, 0.13), Color.BLACK, 0.0, 0.92)
	var iron_material: StandardMaterial3D = _make_material(Color(0.055, 0.050, 0.058), Color.BLACK, 0.0, 0.52)
	var outer_flame_material: StandardMaterial3D = _make_material(
		Color(1.0, 0.31, 0.045),
		Color(1.0, 0.14, 0.015),
		4.6,
		0.28
	)
	var inner_flame_material: StandardMaterial3D = _make_material(
		Color(1.0, 0.92, 0.48),
		Color(1.0, 0.54, 0.10),
		5.2,
		0.18
	)

	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.72
	shadow_mesh.bottom_radius = 0.72
	shadow_mesh.height = 0.012
	_add_mesh(brazier_root, "ContactShadow", shadow_mesh, shadow_material, Vector3(0.0, 0.072, 0.0), Vector3(1.0, 0.35, 0.68))
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.34
	base_mesh.bottom_radius = 0.46
	base_mesh.height = 0.28
	_add_mesh(brazier_root, "StoneBase", base_mesh, stone_material, Vector3(0.0, 0.20, 0.0))
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.10
	stem_mesh.bottom_radius = 0.16
	stem_mesh.height = 0.76
	_add_mesh(brazier_root, "IronStem", stem_mesh, iron_material, Vector3(0.0, 0.70, 0.0))
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.48
	bowl_mesh.bottom_radius = 0.28
	bowl_mesh.height = 0.24
	_add_mesh(brazier_root, "Bowl", bowl_mesh, iron_material, Vector3(0.0, 1.12, 0.0))

	var outer_flame_mesh := SphereMesh.new()
	outer_flame_mesh.radius = 0.24
	outer_flame_mesh.height = 0.48
	outer_flame_mesh.radial_segments = 12
	outer_flame_mesh.rings = 6
	var outer_flame: MeshInstance3D = _add_mesh(
		brazier_root,
		"OuterFlame",
		outer_flame_mesh,
		outer_flame_material,
		Vector3(0.0, 1.48, 0.0),
		Vector3(0.82, 1.42, 0.82)
	)
	outer_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outer_flame.add_to_group("dungeon_flame", true)
	var inner_flame_mesh := SphereMesh.new()
	inner_flame_mesh.radius = 0.13
	inner_flame_mesh.height = 0.26
	inner_flame_mesh.radial_segments = 10
	inner_flame_mesh.rings = 5
	var inner_flame: MeshInstance3D = _add_mesh(
		brazier_root,
		"InnerFlame",
		inner_flame_mesh,
		inner_flame_material,
		Vector3(0.0, 1.42, -0.02),
		Vector3(0.72, 1.35, 0.72)
	)
	inner_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner_flame.add_to_group("dungeon_flame", true)

	var torch_light := OmniLight3D.new()
	torch_light.name = "TorchLight"
	torch_light.light_color = Color(1.0, 0.43, 0.16)
	torch_light.light_energy = 1.82
	torch_light.omni_range = 4.45
	torch_light.shadow_enabled = false
	torch_light.position = Vector3(0.0, 1.58, 0.0)
	torch_light.add_to_group("dungeon_torch_light", true)
	brazier_root.add_child(torch_light)


func _add_carpet(room_root: Node3D) -> void:
	var carpet_material: StandardMaterial3D = _make_material(Color(0.31, 0.070, 0.070), Color.BLACK, 0.0, 0.96)
	var faded_material: StandardMaterial3D = _make_material(Color(0.42, 0.15, 0.095), Color.BLACK, 0.0, 0.92)
	var brass_material: StandardMaterial3D = _make_material(Color(0.64, 0.38, 0.14), Color(0.18, 0.065, 0.018), 0.10, 0.72)
	_add_box(room_root, "CarpetRunner", Vector3(3.45, 0.035, 8.60), Vector3(0.0, 0.077, 1.36), carpet_material)
	_add_box(room_root, "CarpetFade", Vector3(2.75, 0.010, 0.62), Vector3(0.0, 0.101, -2.60), faded_material)
	_add_box(room_root, "CarpetTrimLeft", Vector3(0.09, 0.042, 8.60), Vector3(-1.63, 0.086, 1.36), brass_material)
	_add_box(room_root, "CarpetTrimRight", Vector3(0.09, 0.042, 8.60), Vector3(1.63, 0.086, 1.36), brass_material)
	_add_box(room_root, "CarpetTrimFront", Vector3(3.35, 0.042, 0.09), Vector3(0.0, 0.086, 5.63), brass_material)


func _add_crate_cluster(parent: Node3D, cluster_name: String, position: Vector3, rotation_y: float) -> void:
	var cluster := Node3D.new()
	cluster.name = cluster_name
	cluster.position = position
	cluster.rotation.y = rotation_y
	parent.add_child(cluster)
	var wood_material: StandardMaterial3D = _make_material(Color(0.32, 0.155, 0.095), Color.BLACK, 0.0, 0.86)
	var iron_material: StandardMaterial3D = _make_material(Color(0.095, 0.080, 0.080), Color.BLACK, 0.0, 0.58)
	var shadow_material: StandardMaterial3D = _make_material(Color(0.014, 0.009, 0.012, 0.58), Color.BLACK, 0.0, 1.0)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_add_box(cluster, "Shadow", Vector3(2.25, 0.015, 1.45), Vector3(0.0, 0.074, 0.0), shadow_material)
	_add_box(cluster, "CrateA", Vector3(1.08, 0.92, 1.02), Vector3(-0.42, 0.52, 0.02), wood_material)
	_add_box(cluster, "CrateABand", Vector3(1.16, 0.14, 1.10), Vector3(-0.42, 0.57, 0.02), iron_material)
	_add_box(cluster, "CrateB", Vector3(0.88, 0.70, 0.84), Vector3(0.60, 0.43, 0.18), wood_material)
	_add_box(cluster, "CrateBBand", Vector3(0.96, 0.11, 0.92), Vector3(0.60, 0.46, 0.18), iron_material)
	_add_box(cluster, "Plank", Vector3(0.16, 0.08, 1.42), Vector3(-0.42, 0.57, 0.02), iron_material).rotation.y = 0.52


func _add_dungeon_gate(parent: Node3D) -> void:
	var gate_root := Node3D.new()
	gate_root.name = "DungeonGate"
	parent.add_child(gate_root)
	var recess_material: StandardMaterial3D = _make_material(Color(0.018, 0.014, 0.019), Color.BLACK, 0.0, 1.0)
	var iron_material: StandardMaterial3D = _make_material(Color(0.065, 0.055, 0.060), Color.BLACK, 0.0, 0.54)
	var frame_material: StandardMaterial3D = _make_material(Color(0.23, 0.16, 0.13), Color.BLACK, 0.0, 0.86)
	var brass_material: StandardMaterial3D = _make_material(Color(0.52, 0.31, 0.12), Color(0.22, 0.075, 0.020), 0.18, 0.58)
	_add_box(gate_root, "DoorRecess", Vector3(2.65, 2.15, 0.18), Vector3(0.0, 1.10, -5.97), recess_material)
	_add_box(gate_root, "LeftFrame", Vector3(0.36, 2.65, 0.42), Vector3(-1.52, 1.33, -5.90), frame_material)
	_add_box(gate_root, "RightFrame", Vector3(0.36, 2.65, 0.42), Vector3(1.52, 1.33, -5.90), frame_material)
	_add_box(gate_root, "TopFrame", Vector3(3.40, 0.38, 0.44), Vector3(0.0, 2.48, -5.90), frame_material)
	for bar_index in range(5):
		_add_box(
			gate_root,
			"Bar%d" % bar_index,
			Vector3(0.11, 1.95, 0.10),
			Vector3(-0.92 + float(bar_index) * 0.46, 1.08, -5.80),
			iron_material
		)
	_add_box(gate_root, "CrossBar", Vector3(2.30, 0.13, 0.12), Vector3(0.0, 1.18, -5.76), iron_material)
	var seal_mesh := CylinderMesh.new()
	seal_mesh.top_radius = 0.28
	seal_mesh.bottom_radius = 0.28
	seal_mesh.height = 0.08
	var seal: MeshInstance3D = _add_mesh(gate_root, "BrassSeal", seal_mesh, brass_material, Vector3(0.0, 1.55, -5.70))
	seal.rotation.x = PI * 0.5


func _add_dungeon_target(parent: Node3D, target_name: String, position: Vector3) -> void:
	var target_root := Node3D.new()
	target_root.name = target_name
	target_root.position = position
	parent.add_child(target_root)
	var shadow_material: StandardMaterial3D = _make_material(Color(0.014, 0.009, 0.012, 0.54), Color.BLACK, 0.0, 1.0)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var stone_material: StandardMaterial3D = _make_material(Color(0.18, 0.14, 0.14), Color.BLACK, 0.0, 0.92)
	var iron_material: StandardMaterial3D = _make_material(Color(0.060, 0.055, 0.060), Color.BLACK, 0.0, 0.55)
	var red_material: StandardMaterial3D = _make_material(Color(0.42, 0.095, 0.105), Color.BLACK, 0.0, 0.74)
	var brass_material: StandardMaterial3D = _make_material(Color(0.57, 0.34, 0.13), Color(0.18, 0.055, 0.015), 0.10, 0.62)
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 0.65
	shadow_mesh.bottom_radius = 0.65
	shadow_mesh.height = 0.012
	_add_mesh(target_root, "ContactShadow", shadow_mesh, shadow_material, Vector3(0.0, 0.072, 0.0), Vector3(1.0, 0.3, 0.62))
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.42
	base_mesh.bottom_radius = 0.58
	base_mesh.height = 0.24
	_add_mesh(target_root, "StoneBase", base_mesh, stone_material, Vector3(0.0, 0.18, 0.0))
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.10
	post_mesh.bottom_radius = 0.16
	post_mesh.height = 1.16
	_add_mesh(target_root, "IronPost", post_mesh, iron_material, Vector3(0.0, 0.78, 0.0))
	var outer_mesh := CylinderMesh.new()
	outer_mesh.top_radius = 0.48
	outer_mesh.bottom_radius = 0.48
	outer_mesh.height = 0.15
	var outer: MeshInstance3D = _add_mesh(target_root, "OuterShield", outer_mesh, iron_material, Vector3(0.0, 1.32, 0.0))
	outer.rotation.x = PI * 0.5
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.34
	ring_mesh.bottom_radius = 0.34
	ring_mesh.height = 0.17
	var ring: MeshInstance3D = _add_mesh(target_root, "RedRing", ring_mesh, red_material, Vector3(0.0, 1.32, 0.09))
	ring.rotation.x = PI * 0.5
	var center_mesh := CylinderMesh.new()
	center_mesh.top_radius = 0.16
	center_mesh.bottom_radius = 0.16
	center_mesh.height = 0.19
	var center: MeshInstance3D = _add_mesh(target_root, "BrassCenter", center_mesh, brass_material, Vector3(0.0, 1.32, 0.19))
	center.rotation.x = PI * 0.5


func _add_entrance_steps(parent: Node3D) -> void:
	var step_material: StandardMaterial3D = _make_material(Color(0.15, 0.115, 0.12), Color.BLACK, 0.0, 0.94)
	_add_box(parent, "EntranceStepTop", Vector3(3.10, 0.18, 0.70), Vector3(0.0, -0.02, 6.34), step_material)
	_add_box(parent, "EntranceStepLow", Vector3(3.70, 0.18, 0.72), Vector3(0.0, -0.18, 6.82), step_material)


func _add_wall_blocks(parent: Node3D) -> void:
	var block_materials: Array[StandardMaterial3D] = [
		_make_material(Color(0.205, 0.150, 0.142), Color.BLACK, 0.0, 0.91),
		_make_material(Color(0.245, 0.175, 0.155), Color.BLACK, 0.0, 0.87),
		_make_material(Color(0.175, 0.132, 0.135), Color.BLACK, 0.0, 0.94),
	]
	var blocks_root := Node3D.new()
	blocks_root.name = "WallBlocks"
	parent.add_child(blocks_root)
	for row in range(3):
		var row_offset: float = 0.44 if row % 2 == 1 else 0.0
		for column in range(9):
			var x_position: float = -7.12 + float(column) * 1.78 + row_offset
			if absf(x_position) > 7.72:
				continue
			_add_box(
				blocks_root,
				"RearBlock%d_%d" % [row, column],
				Vector3(1.70, 0.68, 0.09),
				Vector3(x_position, 0.39 + float(row) * 0.76, -5.98),
				block_materials[(row * 2 + column) % block_materials.size()]
			)
		for side_index in range(2):
			var x_wall: float = -7.98 if side_index == 0 else 7.98
			for column in range(7):
				var z_position: float = -5.05 + float(column) * 1.70 + row_offset
				if z_position > 5.48:
					continue
				_add_box(
					blocks_root,
					"SideBlock%d_%d_%d" % [side_index, row, column],
					Vector3(0.09, 0.68, 1.62),
					Vector3(x_wall, 0.39 + float(row) * 0.76, z_position),
					block_materials[(side_index + row + column) % block_materials.size()]
				)


func _add_slime(world_root: Node3D) -> void:
	var actors_root := Node3D.new()
	actors_root.name = "Actors"
	world_root.add_child(actors_root)

	var slime_root := Node3D.new()
	slime_root.name = "Slime3D"
	slime_root.position = Vector3(0.0, 0.0, -1.8)
	slime_root.rotation.y = PI
	actors_root.add_child(slime_root)
	var contact_shadow_material: StandardMaterial3D = _make_material(
		Color(0.008, 0.012, 0.009, 0.56),
		Color.BLACK,
		0.0,
		1.0
	)
	contact_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var contact_shadow_mesh := CylinderMesh.new()
	contact_shadow_mesh.top_radius = 0.72
	contact_shadow_mesh.bottom_radius = 0.72
	contact_shadow_mesh.height = 0.014
	var contact_shadow: MeshInstance3D = _add_mesh(
		slime_root,
		"ContactShadow",
		contact_shadow_mesh,
		contact_shadow_material,
		Vector3(0.0, 0.070, 0.0),
		Vector3(1.0, 0.28, 0.70)
	)
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var slime_visual := Node3D.new()
	slime_visual.name = "SlimeVisual"
	slime_root.add_child(slime_visual)

	var membrane_material: ShaderMaterial = _make_slime_membrane_material()
	var outline_material: ShaderMaterial = _make_slime_outline_material()
	var core_material: StandardMaterial3D = _make_material(
		Color(0.03, 0.24, 0.08, 1.0),
		Color(0.02, 0.12, 0.04),
		0.16,
		0.34
	)
	var eye_material: StandardMaterial3D = _make_material(Color(0.94, 1.0, 0.95), Color(0.30, 0.72, 0.34), 0.12, 0.24)
	var pupil_material: StandardMaterial3D = _make_material(Color(0.014, 0.038, 0.024), Color.BLACK, 0.0, 0.48)
	var highlight_material: StandardMaterial3D = _make_material(Color(1.0, 1.0, 0.88), Color(0.70, 1.0, 0.42), 0.48, 0.18)
	var cheek_material: StandardMaterial3D = _make_material(Color(1.0, 0.42, 0.55), Color(0.35, 0.05, 0.08), 0.18, 0.35)

	_add_slime_membrane(slime_visual, membrane_material, outline_material)

	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.43
	core_mesh.height = 0.86
	core_mesh.radial_segments = 24
	core_mesh.rings = 12
	_add_mesh(
		slime_visual,
		"InnerCore",
		core_mesh,
		core_material,
		Vector3(0.0, 0.46, 0.01),
		Vector3(1.0, 0.88, 1.0)
	)

	_add_slime_face(slime_visual, eye_material, pupil_material, highlight_material, cheek_material)

	var aim_fin_material: StandardMaterial3D = _make_material(
		Color(0.96, 1.0, 0.52),
		Color(0.72, 1.0, 0.20),
		1.45,
		0.18
	)
	_add_box(
		slime_root,
		"AimFin",
		Vector3(0.14, 0.07, 0.48),
		Vector3(0.0, 0.42, -0.77),
		aim_fin_material
	)

	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.70, -0.98)
	slime_root.add_child(muzzle)
	_add_muzzle_flash(slime_root)


func _add_muzzle_flash(slime_root: Node3D) -> void:
	var flash_root := Node3D.new()
	flash_root.name = "MuzzleFlash"
	flash_root.position = Vector3(0.0, 0.70, -1.09)
	flash_root.visible = false
	slime_root.add_child(flash_root)
	var outer_material: StandardMaterial3D = _make_material(
		Color(1.0, 0.38, 0.055),
		Color(1.0, 0.16, 0.012),
		5.0,
		0.22
	)
	var inner_material: StandardMaterial3D = _make_material(
		Color(1.0, 0.94, 0.58),
		Color(1.0, 0.62, 0.12),
		5.8,
		0.12
	)
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.12
	core_mesh.height = 0.24
	core_mesh.radial_segments = 12
	core_mesh.rings = 6
	var core: MeshInstance3D = _add_mesh(flash_root, "Core", core_mesh, inner_material, Vector3.ZERO, Vector3(0.92, 0.70, 1.18))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ray_a: MeshInstance3D = _add_box(
		flash_root,
		"RayA",
		Vector3(0.045, 0.045, 0.38),
		Vector3(0.0, 0.0, -0.12),
		outer_material
	)
	ray_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ray_b: MeshInstance3D = _add_box(
		flash_root,
		"RayB",
		Vector3(0.30, 0.042, 0.05),
		Vector3(0.0, 0.0, -0.08),
		outer_material
	)
	ray_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flash_light := OmniLight3D.new()
	flash_light.name = "FlashLight"
	flash_light.light_color = Color(1.0, 0.48, 0.16)
	flash_light.light_energy = 1.25
	flash_light.omni_range = 1.55
	flash_light.shadow_enabled = false
	flash_root.add_child(flash_light)


func _add_slime_membrane(
	slime_visual: Node3D,
	membrane_material: ShaderMaterial,
	outline_material: ShaderMaterial
) -> void:
	var membrane := Node3D.new()
	membrane.name = "SlimeMembrane"
	var membrane_script := load(SLIME_MEMBRANE_SCRIPT_PATH) as Script
	if membrane_script == null:
		push_error("Failed to load slime membrane script: %s" % SLIME_MEMBRANE_SCRIPT_PATH)
	else:
		membrane.set_script(membrane_script)
	slime_visual.add_child(membrane)

	var placeholder_mesh := SphereMesh.new()
	placeholder_mesh.radius = 0.76
	placeholder_mesh.height = 1.08
	placeholder_mesh.radial_segments = 24
	placeholder_mesh.rings = 12

	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	surface.mesh = placeholder_mesh
	surface.material_override = membrane_material
	membrane.add_child(surface)

	var outline_shell := MeshInstance3D.new()
	outline_shell.name = "OutlineShell"
	outline_shell.mesh = placeholder_mesh
	outline_shell.material_override = outline_material
	outline_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	membrane.add_child(outline_shell)

	var edge_rig := Node3D.new()
	edge_rig.name = "EdgeRig"
	membrane.add_child(edge_rig)
	for index in range(SLIME_CONTROL_POINT_COUNT):
		var ratio: float = float(index) / float(SLIME_CONTROL_POINT_COUNT)
		var angle: float = ratio * TAU
		var radius: float = 0.76 + sin(angle * 3.0 + 0.35) * 0.028
		var edge_point := Marker3D.new()
		edge_point.name = "EdgePoint%02d" % index
		edge_point.position = Vector3(cos(angle) * radius, 0.18, sin(angle) * radius)
		edge_rig.add_child(edge_point)


func _add_slime_face(
	slime_visual: Node3D,
	eye_material: StandardMaterial3D,
	pupil_material: StandardMaterial3D,
	highlight_material: StandardMaterial3D,
	cheek_material: StandardMaterial3D
) -> void:
	var face_root := Node3D.new()
	face_root.name = "FaceRig"
	face_root.position = Vector3(0.0, 0.0, -0.22)
	slime_visual.add_child(face_root)

	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.16
	eye_mesh.height = 0.32
	eye_mesh.radial_segments = 20
	eye_mesh.rings = 10
	_add_mesh(face_root, "LeftEye", eye_mesh, eye_material, Vector3(-0.25, 0.73, -0.52), Vector3(0.92, 1.08, 0.62))
	_add_mesh(face_root, "RightEye", eye_mesh, eye_material, Vector3(0.25, 0.73, -0.52), Vector3(0.92, 1.08, 0.62))

	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = 0.075
	pupil_mesh.height = 0.15
	pupil_mesh.radial_segments = 16
	pupil_mesh.rings = 8
	_add_mesh(face_root, "LeftPupil", pupil_mesh, pupil_material, Vector3(-0.25, 0.73, -0.655), Vector3(0.88, 1.10, 0.50))
	_add_mesh(face_root, "RightPupil", pupil_mesh, pupil_material, Vector3(0.25, 0.73, -0.655), Vector3(0.88, 1.10, 0.50))

	var highlight_mesh := SphereMesh.new()
	highlight_mesh.radius = 0.028
	highlight_mesh.height = 0.056
	_add_mesh(face_root, "LeftEyeHighlight", highlight_mesh, highlight_material, Vector3(-0.275, 0.765, -0.705))
	_add_mesh(face_root, "RightEyeHighlight", highlight_mesh, highlight_material, Vector3(0.225, 0.765, -0.705))

	var cheek_mesh := SphereMesh.new()
	cheek_mesh.radius = 0.085
	cheek_mesh.height = 0.17
	_add_mesh(face_root, "LeftCheek", cheek_mesh, cheek_material, Vector3(-0.43, 0.54, -0.57), Vector3(1.15, 0.58, 0.45))
	_add_mesh(face_root, "RightCheek", cheek_mesh, cheek_material, Vector3(0.43, 0.54, -0.57), Vector3(1.15, 0.58, 0.45))

	var mouth_mesh := BoxMesh.new()
	mouth_mesh.size = Vector3(0.22, 0.04, 0.04)
	_add_mesh(face_root, "Mouth", mouth_mesh, pupil_material, Vector3(0.0, 0.50, -0.665))


func _add_atmosphere_overlay(root_node: Node3D) -> void:
	var atmosphere_overlay := CanvasLayer.new()
	atmosphere_overlay.name = "AtmosphereOverlay"
	atmosphere_overlay.layer = 5
	root_node.add_child(atmosphere_overlay)

	var vignette := ColorRect.new()
	vignette.name = "Vignette"
	vignette.anchor_right = 1.0
	vignette.anchor_bottom = 1.0
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = _make_vignette_material()
	atmosphere_overlay.add_child(vignette)

	var edge_frame := PanelContainer.new()
	edge_frame.name = "EdgeFrame"
	edge_frame.anchor_right = 1.0
	edge_frame.anchor_bottom = 1.0
	edge_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	frame_style.border_color = Color(0.09, 0.060, 0.045, 0.82)
	frame_style.set_border_width_all(10)
	edge_frame.add_theme_stylebox_override("panel", frame_style)
	atmosphere_overlay.add_child(edge_frame)


func _add_box(
	parent: Node,
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: Material
) -> MeshInstance3D:
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	return _add_mesh(parent, node_name, box_mesh, material, position)


func _aim_scene_nodes(scene_root: Node3D) -> void:
	var camera := scene_root.get_node("PerspectiveCamera") as Camera3D
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.25, -0.25), Vector3.UP)
	var key_light := scene_root.get_node("KeyLight") as DirectionalLight3D
	key_light.look_at_from_position(key_light.position, Vector3.ZERO, Vector3.UP)
	var fill_light := scene_root.get_node("FillLight") as DirectionalLight3D
	fill_light.look_at_from_position(fill_light.position, Vector3.ZERO, Vector3.UP)


func _assign_owner(node: Node, scene_owner: Node) -> void:
	for child in node.get_children():
		child.owner = scene_owner
		_assign_owner(child, scene_owner)


func _build_scene() -> Node3D:
	var root_node := Node3D.new()
	root_node.name = "SlimeRoomShooter3D"
	root_node.set_script(load(SCENE_SCRIPT_PATH))
	_add_camera(root_node)
	_add_environment(root_node)
	_add_lights(root_node)

	var world_root := Node3D.new()
	world_root.name = "World3D"
	root_node.add_child(world_root)
	_add_room(world_root)
	_add_slime(world_root)
	_add_aim_marker(world_root)
	_add_projectile_pool(world_root)
	_add_atmosphere_overlay(root_node)
	_add_overlay(root_node)
	return root_node


func _make_material(
	albedo_color: Color,
	emission_color: Color,
	emission_energy: float,
	roughness: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo_color
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = emission_energy
	return material


func _make_hud_panel_style(background_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(0.008, 0.006, 0.008, 0.82)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0.0, 4.0)
	return style


func _make_vignette_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 centered_uv = UV * 2.0 - 1.0;
	centered_uv.x *= 0.82;
	float edge_distance = length(centered_uv);
	float vignette = smoothstep(0.66, 1.20, edge_distance);
	vec2 grain_cell = floor(UV * vec2(640.0, 360.0));
	float grain = fract(sin(dot(grain_cell, vec2(12.9898, 78.233))) * 43758.5453);
	float alpha = clamp(vignette * 0.44 + (grain - 0.5) * 0.014, 0.0, 0.50);
	COLOR = vec4(0.025, 0.013, 0.020, alpha);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _make_slime_membrane_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back;

uniform vec4 body_color : source_color = vec4(0.018, 0.21, 0.12, 1.0);
uniform vec4 inner_color : source_color = vec4(0.004, 0.052, 0.028, 1.0);
uniform vec4 rim_color : source_color = vec4(0.42, 1.0, 0.46, 1.0);

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.15);
	ALBEDO = mix(inner_color.rgb, body_color.rgb, 0.72 + fresnel * 0.22);
	ROUGHNESS = 0.34;
	SPECULAR = 0.48;
	EMISSION = body_color.rgb * 0.075 + rim_color.rgb * (0.006 + fresnel * 0.06);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("body_color", Color(0.018, 0.21, 0.12, 1.0))
	material.set_shader_parameter("inner_color", Color(0.004, 0.052, 0.028, 1.0))
	material.set_shader_parameter("rim_color", Color(0.42, 1.0, 0.46, 1.0))
	return material


func _make_slime_outline_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.67, 0.94, 0.40, 1.0);
uniform float outline_width = 0.042;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * 0.14;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = -1
	material.set_shader_parameter("outline_color", Color(0.67, 0.94, 0.40, 1.0))
	material.set_shader_parameter("outline_width", 0.042)
	return material


func _register_index_button() -> Error:
	var index_resource := load(INDEX_SCENE_PATH) as PackedScene
	if index_resource == null:
		push_error("Failed to load Test Lab index: %s" % INDEX_SCENE_PATH)
		return ERR_CANT_OPEN

	var index_root: Node = index_resource.instantiate()
	var rows := index_root.get_node_or_null("Panel/Margin/Rows") as VBoxContainer
	var panel := index_root.get_node_or_null("Panel") as PanelContainer
	var template := index_root.get_node_or_null("Panel/Margin/Rows/Orthographic3DButton") as Button
	if rows == null or panel == null or template == null:
		push_error("Test Lab index is missing its expected panel/button structure.")
		index_root.free()
		return ERR_INVALID_DATA

	var button := rows.get_node_or_null("SlimeRoomShooterButton") as Button
	if button == null:
		button = template.duplicate() as Button
		if button == null:
			push_error("Failed to duplicate the Test Lab 3D button template.")
			index_root.free()
			return ERR_CANT_CREATE
		button.name = "SlimeRoomShooterButton"
		rows.add_child(button)
		rows.move_child(button, template.get_index() + 1)
	button.text = "3D Slime Dungeon Shooter"
	panel.anchor_top = 0.07
	panel.anchor_bottom = 0.93
	_assign_owner(index_root, index_root)

	var error: Error = _save_packed_scene(index_root, INDEX_SCENE_PATH)
	index_root.free()
	return error


func _save_packed_scene(scene_root: Node, output_path: String) -> Error:
	var packed_scene := PackedScene.new()
	var pack_error: Error = packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack scene %s: %s" % [output_path, pack_error])
		return pack_error
	var save_error: Error = ResourceSaver.save(packed_scene, output_path)
	if save_error != OK:
		push_error("Failed to save scene %s: %s" % [output_path, save_error])
	return save_error
