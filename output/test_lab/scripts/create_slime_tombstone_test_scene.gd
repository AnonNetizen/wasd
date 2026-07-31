extends SceneTree

const OUTPUT_SCENE_PATH: String = "res://scenes/slime_tombstone_test.tscn"
const SCENE_SCRIPT_PATH: String = "res://scripts/slime_tombstone_test.gd"
const TOMBSTONE_SCRIPT_PATH: String = "res://scripts/slime_tombstone.gd"

const TOMBSTONE_OUTLINE: Array[Vector2] = [
	Vector2(-1.20, 0.00),
	Vector2(-1.27, 0.46),
	Vector2(-1.30, 1.22),
	Vector2(-1.28, 2.28),
	Vector2(-1.17, 3.05),
	Vector2(-0.94, 3.58),
	Vector2(-0.62, 4.02),
	Vector2(-0.22, 4.28),
	Vector2(0.22, 4.28),
	Vector2(0.62, 4.02),
	Vector2(0.94, 3.58),
	Vector2(1.17, 3.05),
	Vector2(1.28, 2.28),
	Vector2(1.30, 1.22),
	Vector2(1.27, 0.46),
	Vector2(1.20, 0.00),
	Vector2(0.45, -0.10),
	Vector2(-0.45, -0.10),
]


func _initialize() -> void:
	var scene_root: Node3D = _build_scene()
	root.add_child(scene_root)
	current_scene = scene_root
	_aim_scene(scene_root)
	_assign_owner(scene_root, scene_root)

	var packed_scene := PackedScene.new()
	var pack_error: Error = packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack slime tombstone scene: %s" % pack_error)
		quit(pack_error)
		return

	var save_error: Error = ResourceSaver.save(
		packed_scene,
		OUTPUT_SCENE_PATH,
		ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES
	)
	if save_error != OK:
		push_error("Failed to save slime tombstone scene: %s" % save_error)
		quit(save_error)
		return

	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	quit(0)


func _build_scene() -> Node3D:
	var scene_root := Node3D.new()
	scene_root.name = "SlimeTombstoneTest"
	scene_root.set_script(load(SCENE_SCRIPT_PATH))
	_add_environment(scene_root)
	_add_camera(scene_root)
	_add_lights(scene_root)

	var world := Node3D.new()
	world.name = "World3D"
	scene_root.add_child(world)
	_add_ground(world)
	_add_background(world)
	_add_tombstone_stage(world)
	_add_overlay(scene_root)
	return scene_root


func _add_environment(scene_root: Node3D) -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.018, 0.026, 0.040, 1.0)
	environment.background_energy_multiplier = 0.72
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.31, 0.36, 1.0)
	environment.ambient_light_energy = 0.68
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.04
	environment.adjustment_contrast = 1.09
	environment.adjustment_saturation = 0.86
	world_environment.environment = environment
	scene_root.add_child(world_environment)


func _add_camera(scene_root: Node3D) -> void:
	var camera := Camera3D.new()
	camera.name = "TombstoneCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.2
	camera.position = Vector3(6.9, 5.25, 10.8)
	camera.current = true
	scene_root.add_child(camera)


func _add_lights(scene_root: Node3D) -> void:
	var key_light := DirectionalLight3D.new()
	key_light.name = "MoonKey"
	key_light.light_color = Color(0.56, 0.78, 0.90, 1.0)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	key_light.position = Vector3(-4.0, 7.0, 6.0)
	scene_root.add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.name = "JadeFill"
	fill_light.light_color = Color(0.19, 0.92, 0.67, 1.0)
	fill_light.light_energy = 2.15
	fill_light.omni_range = 8.5
	fill_light.position = Vector3(-2.6, 2.2, 4.2)
	scene_root.add_child(fill_light)


func _add_ground(world: Node3D) -> void:
	var ground_material := _standard_material(
		Color(0.045, 0.065, 0.070, 1.0),
		0.94
	)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(22.0, 18.0)
	_add_mesh_instance(
		world,
		"Ground",
		ground_mesh,
		ground_material,
		Vector3.ZERO
	)

	var rune_material := _standard_material(
		Color(0.04, 0.16, 0.14, 1.0),
		0.42,
		Color(0.05, 0.68, 0.46, 1.0),
		1.6
	)
	var rune_mesh := TorusMesh.new()
	rune_mesh.inner_radius = 2.35
	rune_mesh.outer_radius = 2.39
	rune_mesh.rings = 72
	rune_mesh.ring_segments = 8
	_add_mesh_instance(
		world,
		"GroundRune",
		rune_mesh,
		rune_material,
		Vector3(0.0, 0.035, 0.0)
	)


func _add_background(world: Node3D) -> void:
	var background := Node3D.new()
	background.name = "BackgroundGraves"
	world.add_child(background)
	var grave_material := _standard_material(Color(0.105, 0.135, 0.145, 1.0), 0.88)
	var positions: Array[Vector3] = [
		Vector3(-5.4, 0.0, -2.8),
		Vector3(-3.2, 0.0, -4.5),
		Vector3(3.7, 0.0, -4.2),
		Vector3(5.3, 0.0, -2.2),
		Vector3(-6.6, 0.0, 1.2),
		Vector3(6.7, 0.0, 0.8),
	]
	for index in range(positions.size()):
		_add_background_grave(
			background,
			"RigidGrave%02d" % index,
			positions[index],
			grave_material,
			0.74 + float(index % 3) * 0.11
		)

	var moon_material := _standard_material(
		Color(0.32, 0.54, 0.60, 1.0),
		0.40,
		Color(0.32, 0.72, 0.78, 1.0),
		2.2
	)
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 1.35
	moon_mesh.height = 2.7
	moon_mesh.radial_segments = 32
	moon_mesh.rings = 16
	_add_mesh_instance(
		background,
		"Moon",
		moon_mesh,
		moon_material,
		Vector3(-4.7, 6.7, -7.6)
	)

	var mote_material := _standard_material(
		Color(0.18, 0.72, 0.52, 1.0),
		0.24,
		Color(0.10, 0.82, 0.55, 1.0),
		1.8
	)
	for index in range(14):
		var mote_mesh := SphereMesh.new()
		var radius: float = 0.026 + float(index % 4) * 0.008
		mote_mesh.radius = radius
		mote_mesh.height = radius * 2.0
		mote_mesh.radial_segments = 8
		mote_mesh.rings = 4
		var x: float = -6.0 + float((index * 37) % 120) * 0.10
		var y: float = 0.55 + float((index * 23) % 48) * 0.075
		var z: float = -1.2 - float((index * 17) % 42) * 0.09
		_add_mesh_instance(
			background,
			"Mote%02d" % index,
			mote_mesh,
			mote_material,
			Vector3(x, y, z)
		)


func _add_background_grave(
	parent: Node3D,
	grave_name: String,
	position: Vector3,
	material: Material,
	scale_factor: float
) -> void:
	var grave := Node3D.new()
	grave.name = grave_name
	parent.add_child(grave)
	grave.position = position
	grave.rotation.y = deg_to_rad(-12.0 + float(grave.get_index() % 5) * 5.0)

	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.05, 1.72, 0.34) * scale_factor
	_add_mesh_instance(
		grave,
		"Body",
		body_mesh,
		material,
		Vector3(0.0, 0.86 * scale_factor, 0.0)
	)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.53 * scale_factor
	head_mesh.height = 1.06 * scale_factor
	head_mesh.radial_segments = 18
	head_mesh.rings = 8
	var head := _add_mesh_instance(
		grave,
		"Arch",
		head_mesh,
		material,
		Vector3(0.0, 1.69 * scale_factor, 0.0)
	)
	head.scale.z = 0.34


func _add_tombstone_stage(world: Node3D) -> void:
	var stage := Node3D.new()
	stage.name = "TombstoneStage"
	world.add_child(stage)

	var shadow_material := _standard_material(Color(0.006, 0.012, 0.014, 0.58), 1.0)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var shadow_mesh := CylinderMesh.new()
	shadow_mesh.top_radius = 1.58
	shadow_mesh.bottom_radius = 1.58
	shadow_mesh.height = 0.018
	var shadow := _add_mesh_instance(
		stage,
		"ContactShadow",
		shadow_mesh,
		shadow_material,
		Vector3(0.0, 0.045, 0.0)
	)
	shadow.scale.z = 0.52
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var plinth_material := _standard_material(Color(0.095, 0.135, 0.135, 1.0), 0.82)
	var plinth_mesh := BoxMesh.new()
	plinth_mesh.size = Vector3(3.45, 0.34, 1.55)
	_add_mesh_instance(
		stage,
		"Plinth",
		plinth_mesh,
		plinth_material,
		Vector3(0.0, 0.17, 0.0)
	)

	var tombstone := Node3D.new()
	tombstone.name = "SlimeTombstone"
	tombstone.position = Vector3(0.0, 0.37, 0.0)
	tombstone.set_script(load(TOMBSTONE_SCRIPT_PATH))
	stage.add_child(tombstone)

	var placeholder_mesh := BoxMesh.new()
	placeholder_mesh.size = Vector3(2.6, 4.3, 0.5)
	for layer_name in ["Surface", "WetCoat", "OutlineShell"]:
		var layer := MeshInstance3D.new()
		layer.name = layer_name
		layer.mesh = placeholder_mesh
		if layer_name != "Surface":
			layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tombstone.add_child(layer)

	var face_mark := Label3D.new()
	face_mark.name = "FaceMark"
	face_mark.text = "RIP"
	face_mark.font_size = 74
	face_mark.outline_size = 12
	face_mark.modulate = Color(0.68, 0.91, 0.78, 1.0)
	face_mark.outline_modulate = Color(0.025, 0.075, 0.068, 0.96)
	face_mark.position = Vector3(0.0, 2.34, 0.36)
	face_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	face_mark.render_priority = 2
	tombstone.add_child(face_mark)

	var edge_rig := Node3D.new()
	edge_rig.name = "EdgeRig"
	tombstone.add_child(edge_rig)
	for index in range(TOMBSTONE_OUTLINE.size()):
		var marker := Marker3D.new()
		marker.name = "EdgePoint%02d" % index
		var point: Vector2 = TOMBSTONE_OUTLINE[index]
		marker.position = Vector3(point.x, point.y, 0.0)
		edge_rig.add_child(marker)

	var impact_light := OmniLight3D.new()
	impact_light.name = "ImpactLight"
	impact_light.light_color = Color(0.28, 1.0, 0.70, 1.0)
	impact_light.light_energy = 0.0
	impact_light.omni_range = 5.8
	impact_light.position = Vector3(0.0, 2.45, 2.3)
	stage.add_child(impact_light)


func _add_overlay(scene_root: Node3D) -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	scene_root.add_child(overlay)

	var top_band := ColorRect.new()
	top_band.name = "TopBand"
	top_band.color = Color(0.012, 0.020, 0.030, 0.88)
	top_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_band.offset_bottom = 118.0
	overlay.add_child(top_band)

	var title := Label.new()
	title.name = "Title"
	title.text = "软体墓碑 / JELLY TOMBSTONE"
	title.position = Vector2(34.0, 20.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.70, 1.0, 0.84, 1.0))
	top_band.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "同一套史莱姆弹簧膜、面积压力与共享网格材质，改用非圆形拱顶轮廓"
	subtitle.position = Vector2(36.0, 66.0)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.74, 0.77, 1.0))
	top_band.add_child(subtitle)

	var metrics_panel := PanelContainer.new()
	metrics_panel.name = "MetricsPanel"
	metrics_panel.anchor_left = 1.0
	metrics_panel.anchor_right = 1.0
	metrics_panel.offset_left = -320.0
	metrics_panel.offset_top = 18.0
	metrics_panel.offset_right = -26.0
	metrics_panel.offset_bottom = 151.0
	overlay.add_child(metrics_panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	metrics_panel.add_child(margin)
	var metrics := Label.new()
	metrics.name = "Metrics"
	metrics.text = "初始化中…"
	metrics.add_theme_font_size_override("font_size", 14)
	metrics.add_theme_color_override("font_color", Color(0.72, 0.91, 0.84, 1.0))
	margin.add_child(metrics)

	var controls := HBoxContainer.new()
	controls.name = "Controls"
	controls.anchor_left = 0.5
	controls.anchor_right = 0.5
	controls.anchor_top = 1.0
	controls.anchor_bottom = 1.0
	controls.offset_left = -372.0
	controls.offset_top = -77.0
	controls.offset_right = 372.0
	controls.offset_bottom = -25.0
	controls.add_theme_constant_override("separation", 10)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(controls)
	_add_button(controls, "PokeButton", "点一下", 120.0)
	_add_button(controls, "SquashButton", "压扁 [Space]", 140.0)
	_add_button(controls, "ResetButton", "复原 [R]", 120.0)
	_add_button(controls, "AutoButton", "自动脉冲：开", 150.0)

	var instruction := Label.new()
	instruction.name = "Instruction"
	instruction.text = "左键点击墓碑任意位置施加局部冲击；观察碑底是否稳定、拱顶是否仍可辨认。"
	instruction.anchor_top = 1.0
	instruction.anchor_bottom = 1.0
	instruction.offset_left = 28.0
	instruction.offset_top = -112.0
	instruction.offset_right = 760.0
	instruction.offset_bottom = -83.0
	instruction.add_theme_font_size_override("font_size", 15)
	instruction.add_theme_color_override("font_color", Color(0.70, 0.79, 0.82, 1.0))
	overlay.add_child(instruction)

	var exit_button := Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "返回实验索引 [Esc]"
	exit_button.anchor_left = 1.0
	exit_button.anchor_right = 1.0
	exit_button.offset_left = -214.0
	exit_button.offset_top = 168.0
	exit_button.offset_right = -28.0
	exit_button.offset_bottom = 214.0
	overlay.add_child(exit_button)


func _add_button(parent: Control, button_name: String, text: String, width: float) -> void:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.custom_minimum_size = Vector2(width, 48.0)
	parent.add_child(button)


func _add_mesh_instance(
	parent: Node,
	node_name: String,
	mesh: Mesh,
	material: Material,
	position: Vector3
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	return mesh_instance


func _aim_scene(scene_root: Node3D) -> void:
	var camera := scene_root.get_node_or_null("TombstoneCamera") as Camera3D
	if camera != null:
		camera.look_at_from_position(camera.position, Vector3(0.0, 2.15, 0.0), Vector3.UP)
	var key_light := scene_root.get_node_or_null("MoonKey") as DirectionalLight3D
	if key_light != null:
		key_light.look_at_from_position(
			key_light.position,
			Vector3(0.0, 1.8, 0.0),
			Vector3.UP
		)


func _assign_owner(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_assign_owner(child, owner)


func _standard_material(
	color: Color,
	roughness: float,
	emission: Color = Color(0.0, 0.0, 0.0, 1.0),
	emission_energy: float = 0.0
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material
