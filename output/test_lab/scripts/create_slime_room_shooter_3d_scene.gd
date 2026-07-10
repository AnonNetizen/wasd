extends SceneTree

const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const OUTPUT_SCENE_PATH: String = "res://scenes/slime_room_shooter_3d.tscn"
const PROJECTILE_POOL_SIZE: int = 24
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
		Color(0.20, 0.88, 1.0),
		Color(0.10, 0.78, 1.0),
		1.8,
		0.22
	)
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.24
	marker_mesh.bottom_radius = 0.24
	marker_mesh.height = 0.025
	_add_mesh(world_root, "AimMarker", marker_mesh, marker_material, Vector3(0.0, 0.035, 0.0))


func _add_camera(root_node: Node3D) -> void:
	var camera := Camera3D.new()
	camera.name = "PerspectiveCamera"
	camera.current = true
	camera.fov = 48.0
	camera.near = 0.1
	camera.far = 100.0
	camera.position = Vector3(0.0, 12.8, 12.4)
	root_node.add_child(camera)


func _add_environment(root_node: Node3D) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.014, 0.024, 0.040)
	sky_material.sky_horizon_color = Color(0.055, 0.075, 0.095)
	sky_material.ground_bottom_color = Color(0.008, 0.012, 0.018)
	sky_material.ground_horizon_color = Color(0.035, 0.045, 0.052)
	sky_material.sky_energy_multiplier = 0.45
	sky_material.ground_energy_multiplier = 0.32

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_SKY
	environment_resource.sky = sky
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.24, 0.34, 0.42)
	environment_resource.ambient_light_energy = 0.68
	environment_resource.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_resource.glow_enabled = true
	environment_resource.glow_intensity = 0.45
	environment_resource.glow_strength = 0.72

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment_resource
	root_node.add_child(world_environment)


func _add_grid(room_root: Node3D) -> void:
	var grid_root := Node3D.new()
	grid_root.name = "GridLines"
	room_root.add_child(grid_root)
	var grid_material: StandardMaterial3D = _make_material(
		Color(0.12, 0.25, 0.30),
		Color(0.08, 0.28, 0.34),
		0.35,
		0.6
	)
	for x_position in range(-8, 9, 2):
		_add_box(
			grid_root,
			"GridX%d" % x_position,
			Vector3(0.025, 0.012, 12.0),
			Vector3(float(x_position), 0.012, 0.0),
			grid_material
		)
	for z_position in range(-6, 7, 2):
		_add_box(
			grid_root,
			"GridZ%d" % z_position,
			Vector3(16.0, 0.012, 0.025),
			Vector3(0.0, 0.013, float(z_position)),
			grid_material
		)


func _add_lights(root_node: Node3D) -> void:
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.light_color = Color(0.82, 1.0, 0.78)
	key_light.light_energy = 2.15
	key_light.shadow_enabled = true
	key_light.position = Vector3(-7.0, 11.0, 7.0)
	root_node.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_color = Color(0.34, 0.56, 1.0)
	fill_light.light_energy = 0.72
	fill_light.shadow_enabled = false
	fill_light.position = Vector3(8.0, 7.0, -6.0)
	root_node.add_child(fill_light)

	var slime_light := OmniLight3D.new()
	slime_light.name = "SlimeGlowLight"
	slime_light.light_color = Color(0.28, 1.0, 0.42)
	slime_light.light_energy = 0.65
	slime_light.omni_range = 4.4
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
	root_node.add_child(overlay)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.02
	panel.anchor_top = 0.02
	panel.anchor_right = 0.31
	panel.anchor_bottom = 0.25
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.075, 0.085, 0.94)
	panel_style.border_color = Color(0.22, 0.80, 0.58, 0.92)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	var title := Label.new()
	title.name = "Title"
	title.text = "3D Slime Room Shooter"
	title.add_theme_color_override("font_color", Color(0.58, 1.0, 0.66))
	title.add_theme_font_size_override("font_size", 22)
	rows.add_child(title)

	var info := Label.new()
	info.name = "Info"
	info.text = "WASD / arrows: move\nMouse: aim\nHold left click: fire\nEsc: back"
	info.add_theme_color_override("font_color", Color(0.82, 0.91, 0.90))
	rows.add_child(info)

	var shot_count := Label.new()
	shot_count.name = "ShotCount"
	shot_count.text = "Shots fired: 0"
	shot_count.add_theme_color_override("font_color", Color(1.0, 0.76, 0.30))
	rows.add_child(shot_count)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(0.0, 36.0)
	rows.add_child(back_button)


func _add_projectile_pool(world_root: Node3D) -> void:
	var projectiles_root := Node3D.new()
	projectiles_root.name = "Projectiles"
	world_root.add_child(projectiles_root)

	var projectile_mesh := SphereMesh.new()
	projectile_mesh.radius = 0.13
	projectile_mesh.height = 0.26
	var projectile_material: StandardMaterial3D = _make_material(
		Color(1.0, 0.70, 0.16),
		Color(1.0, 0.38, 0.06),
		3.2,
		0.18
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


func _add_room(world_root: Node3D) -> void:
	var room_root := Node3D.new()
	room_root.name = "Room"
	world_root.add_child(room_root)

	var floor_material: StandardMaterial3D = _make_material(Color(0.075, 0.12, 0.13), Color.BLACK, 0.0, 0.88)
	var wall_material: StandardMaterial3D = _make_material(Color(0.105, 0.15, 0.16), Color.BLACK, 0.0, 0.76)
	var trim_material: StandardMaterial3D = _make_material(
		Color(0.24, 0.70, 0.48),
		Color(0.10, 0.62, 0.38),
		0.82,
		0.44
	)
	_add_box(room_root, "Floor", Vector3(17.0, 0.24, 13.0), Vector3(0.0, -0.12, 0.0), floor_material)
	_add_grid(room_root)
	_add_box(room_root, "RearWall", Vector3(17.0, 2.7, 0.36), Vector3(0.0, 1.35, -6.25), wall_material)
	_add_box(room_root, "LeftWall", Vector3(0.36, 2.7, 13.0), Vector3(-8.25, 1.35, 0.0), wall_material)
	_add_box(room_root, "RightWall", Vector3(0.36, 2.7, 13.0), Vector3(8.25, 1.35, 0.0), wall_material)
	_add_box(room_root, "FrontRail", Vector3(17.0, 0.58, 0.36), Vector3(0.0, 0.29, 6.25), wall_material)
	_add_box(room_root, "RearTrim", Vector3(17.0, 0.08, 0.10), Vector3(0.0, 2.68, -6.02), trim_material)
	_add_box(room_root, "LeftTrim", Vector3(0.10, 0.08, 12.0), Vector3(-8.02, 2.68, 0.0), trim_material)
	_add_box(room_root, "RightTrim", Vector3(0.10, 0.08, 12.0), Vector3(8.02, 2.68, 0.0), trim_material)

	_add_target_pod(room_root, "BlueTarget", Vector3(-5.1, 0.0, -3.7), Color(0.20, 0.70, 1.0))
	_add_target_pod(room_root, "AmberTarget", Vector3(5.0, 0.0, -3.2), Color(1.0, 0.52, 0.16))


func _add_slime(world_root: Node3D) -> void:
	var actors_root := Node3D.new()
	actors_root.name = "Actors"
	world_root.add_child(actors_root)

	var slime_root := Node3D.new()
	slime_root.name = "Slime3D"
	slime_root.position = Vector3(0.0, 0.0, -1.8)
	slime_root.rotation.y = PI
	actors_root.add_child(slime_root)

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


func _add_target_pod(parent: Node3D, pod_name: String, position: Vector3, accent_color: Color) -> void:
	var pod_root := Node3D.new()
	pod_root.name = pod_name
	pod_root.position = position
	parent.add_child(pod_root)

	var base_material: StandardMaterial3D = _make_material(Color(0.12, 0.15, 0.16), Color.BLACK, 0.0, 0.76)
	var accent_material: StandardMaterial3D = _make_material(accent_color, accent_color, 1.7, 0.24)
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.54
	base_mesh.bottom_radius = 0.66
	base_mesh.height = 0.22
	_add_mesh(pod_root, "Base", base_mesh, base_material, Vector3(0.0, 0.11, 0.0))

	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.16
	stem_mesh.bottom_radius = 0.22
	stem_mesh.height = 1.2
	_add_mesh(pod_root, "Stem", stem_mesh, base_material, Vector3(0.0, 0.77, 0.0))

	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.34
	core_mesh.height = 0.68
	_add_mesh(pod_root, "Core", core_mesh, accent_material, Vector3(0.0, 1.43, 0.0))


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
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.35, 0.0), Vector3.UP)
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

uniform vec4 outline_color : source_color = vec4(0.72, 1.0, 0.52, 1.0);
uniform float outline_width = 0.05;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * 0.24;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = -1
	material.set_shader_parameter("outline_color", Color(0.72, 1.0, 0.52, 1.0))
	material.set_shader_parameter("outline_width", 0.05)
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
	button.text = "3D Slime Room Shooter"
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
