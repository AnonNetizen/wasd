extends SceneTree

const CAMERA_DISTANCE: float = 18.0
const CAMERA_ELEVATION_DEGREES: float = 30.0
const CAMERA_ORTHO_SIZE: float = 14.6
const CAMERA_YAW_DEGREES: float = 45.0
const CELL_SIZE: float = 2.0
const GRID_HALF_CELLS: int = 6
const OUTPUT_SCENE_PATH := "res://scenes/orthographic_3d_test.tscn"
const SCENE_SCRIPT_PATH := "res://scripts/orthographic_3d_test.gd"
const STAGE_SIZE: float = float(GRID_HALF_CELLS * 2) * CELL_SIZE


func _initialize() -> void:
	var scene_root := _build_scene()
	root.add_child(scene_root)
	current_scene = scene_root
	_aim_scene_lights(scene_root)
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

	_add_camera(root_node)
	_add_environment(root_node)
	_add_lights(root_node)

	var world_root := Node3D.new()
	world_root.name = "World3D"
	root_node.add_child(world_root)

	var backdrop_root := _add_group(world_root, "Backdrop")
	_add_backdrop(backdrop_root)

	var stage_root := _add_group(world_root, "Stage")
	_add_stage(stage_root)

	var props_root := _add_group(world_root, "Props")
	_add_cache(props_root, Vector3(-1.8, 0.0, 1.2))
	_add_wall(props_root, Vector3(2.1, 0.7, 1.3), Vector3(3.2, 1.4, 0.28))
	_add_column(props_root, "SideColumn", Vector3(2.8, 0.0, -1.9))
	_add_column(props_root, "RearColumn", Vector3(-3.2, 0.0, -2.6))
	_add_beacon(props_root, "BlueBeacon", Vector3(-4.8, 0.0, 2.2), Color(0.18, 0.72, 1.0))
	_add_beacon(props_root, "AmberBeacon", Vector3(4.9, 0.0, -3.0), Color(1.0, 0.56, 0.18))

	var actors_root := _add_group(world_root, "Actors")
	_add_player(actors_root, Vector3(-2.0, 0.0, -1.4))

	_add_overlay(root_node)
	return root_node


func _add_camera(root_node: Node3D) -> void:
	var camera := Camera3D.new()
	camera.name = "OrthographicCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_ORTHO_SIZE
	camera.current = true
	camera.position = _camera_offset()
	root_node.add_child(camera)


func _add_environment(root_node: Node3D) -> void:
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.012, 0.018, 0.030)
	sky_material.sky_horizon_color = Color(0.030, 0.042, 0.058)
	sky_material.sky_curve = 0.28
	sky_material.sky_energy_multiplier = 0.34
	sky_material.ground_bottom_color = Color(0.006, 0.007, 0.010)
	sky_material.ground_horizon_color = Color(0.026, 0.024, 0.026)
	sky_material.ground_curve = 0.40
	sky_material.ground_energy_multiplier = 0.42
	sky_material.sun_angle_max = 0.0
	sky_material.sun_curve = 0.01

	var sky := Sky.new()
	sky.sky_material = sky_material

	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_SKY
	world_environment.sky = sky
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color(0.22, 0.30, 0.38)
	world_environment.ambient_light_energy = 0.30
	world_environment.glow_enabled = true
	world_environment.glow_intensity = 0.38
	world_environment.glow_strength = 0.62
	world_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.tonemap_exposure = 0.92
	environment.environment = world_environment
	root_node.add_child(environment)


func _add_lights(root_node: Node3D) -> void:
	var key_light := DirectionalLight3D.new()
	key_light.name = "WarmKeyLight"
	key_light.light_color = Color(1.0, 0.76, 0.46)
	key_light.light_energy = 3.05
	key_light.shadow_enabled = true
	key_light.position = Vector3(-6.5, 9.5, 5.0)
	root_node.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "CoolFillLight"
	fill_light.light_color = Color(0.34, 0.52, 0.86)
	fill_light.light_energy = 0.34
	fill_light.shadow_enabled = false
	fill_light.position = Vector3(6.0, 5.0, -5.5)
	root_node.add_child(fill_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.name = "RimLight"
	rim_light.light_color = Color(0.52, 0.82, 1.0)
	rim_light.light_energy = 1.42
	rim_light.shadow_enabled = false
	rim_light.position = Vector3(0.0, 6.5, -8.0)
	root_node.add_child(rim_light)

	_add_omni_light(root_node, "PoiBlueGlowLight", Vector3(0.0, 0.85, 0.0), Color(0.18, 0.64, 1.0), 0.80, 6.0)
	_add_omni_light(root_node, "CacheWarmGlowLight", Vector3(-1.8, 0.9, 1.2), Color(1.0, 0.55, 0.18), 0.42, 3.4)
	_add_omni_light(root_node, "AmberBeaconGlowLight", Vector3(4.9, 0.85, -3.0), Color(1.0, 0.56, 0.18), 0.34, 3.0)
	_add_omni_light(root_node, "BlueBeaconGlowLight", Vector3(-4.8, 0.85, 2.2), Color(0.18, 0.72, 1.0), 0.34, 3.0)


func _aim_scene_lights(scene_root: Node3D) -> void:
	var camera := scene_root.get_node("OrthographicCamera") as Camera3D
	camera.look_at_from_position(camera.position, Vector3.ZERO, Vector3.UP)
	var key_light := scene_root.get_node("WarmKeyLight") as DirectionalLight3D
	key_light.look_at_from_position(key_light.position, Vector3.ZERO, Vector3.UP)
	var fill_light := scene_root.get_node("CoolFillLight") as DirectionalLight3D
	fill_light.look_at_from_position(fill_light.position, Vector3.ZERO, Vector3.UP)
	var rim_light := scene_root.get_node("RimLight") as DirectionalLight3D
	rim_light.look_at_from_position(rim_light.position, Vector3.ZERO, Vector3.UP)


func _add_backdrop(backdrop_root: Node3D) -> void:
	_add_box(
		"VoidFloor",
		Vector3(0.0, -0.30, 0.0),
		Vector3(STAGE_SIZE * 1.55, 0.08, STAGE_SIZE * 1.55),
		Color(0.010, 0.022, 0.030),
		backdrop_root
	)
	_add_box(
		"VoidCoolSheen",
		Vector3(0.0, -0.235, 0.0),
		Vector3(STAGE_SIZE * 1.34, 0.018, STAGE_SIZE * 1.34),
		Color(0.060, 0.140, 0.180, 0.16),
		backdrop_root,
		true,
		true,
		0.24,
		Color(0.08, 0.42, 0.62)
	)
	_add_box(
		"FarHorizon",
		Vector3(0.0, 1.2, -STAGE_SIZE * 0.62),
		Vector3(STAGE_SIZE * 1.18, 2.8, 0.08),
		Color(0.012, 0.018, 0.028, 0.38),
		backdrop_root,
		true
	)
	_add_box(
		"HorizonGlow",
		Vector3(0.0, 0.18, -STAGE_SIZE * 0.60),
		Vector3(STAGE_SIZE * 1.12, 0.10, 0.10),
		Color(0.62, 0.28, 0.08, 0.08),
		backdrop_root,
		true,
		true,
		0.20,
		Color(0.80, 0.36, 0.12)
	)
	_add_silhouette(backdrop_root, "DistantPillarLeft", Vector3(-8.8, 1.15, -14.2), Vector3(0.60, 2.30, 0.26))
	_add_silhouette(backdrop_root, "DistantPillarMid", Vector3(-5.1, 0.92, -14.4), Vector3(0.48, 1.85, 0.22))
	_add_silhouette(backdrop_root, "DistantPillarRight", Vector3(7.0, 1.05, -14.0), Vector3(0.70, 2.10, 0.28))


func _add_silhouette(backdrop_root: Node3D, name: String, position: Vector3, size: Vector3) -> void:
	_add_box(name, position, size, Color(0.008, 0.011, 0.016, 0.62), backdrop_root, true)


func _add_stage(stage_root: Node3D) -> void:
	_add_box(
		"Floor",
		Vector3(0.0, -0.11, 0.0),
		Vector3(STAGE_SIZE, 0.22, STAGE_SIZE),
		Color(0.060, 0.074, 0.072),
		stage_root
	)
	_add_floor_variation(stage_root)
	_add_stage_borders(stage_root)
	_add_poi_focus(stage_root)
	_add_grid(stage_root)


func _add_floor_variation(stage_root: Node3D) -> void:
	_add_box("FloorPlateA", Vector3(-4.0, -0.001, -1.6), Vector3(4.4, 0.012, 1.10), Color(0.060, 0.090, 0.096, 0.58), stage_root, true)
	_add_box("FloorPlateB", Vector3(4.3, 0.000, 2.8), Vector3(3.6, 0.012, 1.20), Color(0.160, 0.104, 0.060, 0.36), stage_root, true)
	_add_box("FloorPlateC", Vector3(1.2, 0.002, -4.6), Vector3(5.2, 0.012, 0.80), Color(0.035, 0.056, 0.072, 0.52), stage_root, true)
	_add_box("InsetLineA", Vector3(-3.8, 0.018, 2.2), Vector3(5.8, 0.018, 0.045), Color(0.38, 0.22, 0.10, 0.32), stage_root, true, true)
	_add_box("InsetLineB", Vector3(3.0, 0.019, -2.9), Vector3(0.045, 0.018, 4.8), Color(0.18, 0.30, 0.36, 0.30), stage_root, true, true)
	_add_box("CrackA", Vector3(-0.7, 0.020, 4.4), Vector3(2.2, 0.016, 0.030), Color(0.018, 0.016, 0.014, 0.55), stage_root, true)
	_add_box("CrackB", Vector3(5.0, 0.021, -0.9), Vector3(0.030, 0.016, 2.0), Color(0.018, 0.016, 0.014, 0.45), stage_root, true)
	_add_box("ScorchMarkA", Vector3(-5.6, 0.024, 3.7), Vector3(1.35, 0.014, 0.72), Color(0.010, 0.009, 0.008, 0.30), stage_root, true)
	_add_box("ScorchMarkB", Vector3(5.1, 0.024, 3.0), Vector3(1.10, 0.014, 0.54), Color(0.010, 0.009, 0.008, 0.24), stage_root, true)


func _add_stage_borders(stage_root: Node3D) -> void:
	var border_color := Color(0.84, 0.43, 0.15)
	var inner_glow := Color(0.95, 0.62, 0.22, 0.24)
	_add_box("StageSkirtNorth", Vector3(0.0, -0.18, -STAGE_SIZE * 0.5 - 0.05), Vector3(STAGE_SIZE, 0.30, 0.12), Color(0.055, 0.040, 0.026), stage_root)
	_add_box("StageSkirtSouth", Vector3(0.0, -0.18, STAGE_SIZE * 0.5 + 0.05), Vector3(STAGE_SIZE, 0.30, 0.12), Color(0.090, 0.048, 0.026), stage_root)
	_add_box("StageSkirtWest", Vector3(-STAGE_SIZE * 0.5 - 0.05, -0.18, 0.0), Vector3(0.12, 0.30, STAGE_SIZE), Color(0.055, 0.040, 0.026), stage_root)
	_add_box("StageSkirtEast", Vector3(STAGE_SIZE * 0.5 + 0.05, -0.18, 0.0), Vector3(0.12, 0.30, STAGE_SIZE), Color(0.090, 0.048, 0.026), stage_root)
	_add_box("StageBorderNorth", Vector3(0.0, 0.035, -STAGE_SIZE * 0.5), Vector3(STAGE_SIZE, 0.10, 0.09), border_color, stage_root, false, false, 0.16, Color(1.0, 0.45, 0.12))
	_add_box("StageBorderSouth", Vector3(0.0, 0.035, STAGE_SIZE * 0.5), Vector3(STAGE_SIZE, 0.10, 0.09), border_color, stage_root, false, false, 0.16, Color(1.0, 0.45, 0.12))
	_add_box("StageBorderWest", Vector3(-STAGE_SIZE * 0.5, 0.035, 0.0), Vector3(0.09, 0.10, STAGE_SIZE), border_color, stage_root, false, false, 0.16, Color(1.0, 0.45, 0.12))
	_add_box("StageBorderEast", Vector3(STAGE_SIZE * 0.5, 0.035, 0.0), Vector3(0.09, 0.10, STAGE_SIZE), border_color, stage_root, false, false, 0.16, Color(1.0, 0.45, 0.12))
	_add_box("NorthInnerGlow", Vector3(0.0, 0.045, -STAGE_SIZE * 0.5 + 0.16), Vector3(STAGE_SIZE * 0.96, 0.018, 0.045), inner_glow, stage_root, true, true, 0.28, Color(1.0, 0.55, 0.16))
	_add_box("SouthInnerGlow", Vector3(0.0, 0.045, STAGE_SIZE * 0.5 - 0.16), Vector3(STAGE_SIZE * 0.96, 0.018, 0.045), inner_glow, stage_root, true, true, 0.28, Color(1.0, 0.55, 0.16))


func _add_poi_focus(stage_root: Node3D) -> void:
	_add_box(
		"PoiGlow",
		Vector3(0.0, 0.028, 0.0),
		Vector3(CELL_SIZE * 1.80, 0.018, CELL_SIZE * 1.80),
		Color(0.19, 0.47, 0.68, 0.20),
		stage_root,
		true,
		true,
		0.75,
		Color(0.18, 0.72, 1.0)
	)
	_add_box("PoiCorePlate", Vector3(0.0, 0.040, 0.0), Vector3(CELL_SIZE * 0.94, 0.024, CELL_SIZE * 0.94), Color(0.92, 0.54, 0.18, 0.20), stage_root, true)
	_add_box("PoiSlashA", Vector3(0.0, 0.055, 0.0), Vector3(CELL_SIZE * 1.15, 0.020, 0.050), Color(0.22, 0.70, 1.0, 0.34), stage_root, true, true, 0.50, Color(0.24, 0.76, 1.0))
	_add_box("PoiSlashB", Vector3(0.0, 0.056, 0.0), Vector3(0.050, 0.020, CELL_SIZE * 1.15), Color(0.22, 0.70, 1.0, 0.24), stage_root, true, true, 0.38, Color(0.24, 0.76, 1.0))


func _add_grid(stage_root: Node3D) -> void:
	var grid_root := _add_group(stage_root, "GridLines")
	var line_material := _make_material(Color(0.86, 0.50, 0.20, 0.24), true, true)
	var axis_material := _make_material(Color(1.0, 0.70, 0.28, 0.38), true, true, 0.16, Color(1.0, 0.54, 0.18))
	var grid_size: float = STAGE_SIZE
	var line_thickness: float = 0.030
	for index in range(-GRID_HALF_CELLS, GRID_HALF_CELLS + 1):
		var offset: float = float(index) * CELL_SIZE
		var material: Material = axis_material if index == 0 else line_material
		_add_box_with_material(
			"GridX%s" % index,
			Vector3(offset, 0.030, 0.0),
			Vector3(line_thickness, 0.020, grid_size),
			material,
			grid_root
		)
		_add_box_with_material(
			"GridZ%s" % index,
			Vector3(0.0, 0.031, offset),
			Vector3(grid_size, 0.020, line_thickness),
			material,
			grid_root
		)


func _add_cache(props_root: Node3D, origin: Vector3) -> void:
	var cache_root := Node3D.new()
	cache_root.name = "CacheBox3D"
	cache_root.position = origin
	props_root.add_child(cache_root)

	_add_box("CacheShadow", Vector3(0.08, 0.025, 0.16), Vector3(1.62, 0.018, 1.04), Color(0.015, 0.013, 0.011, 0.44), cache_root, true)
	_add_box("CacheFootprint", Vector3(0.0, 0.035, 0.0), Vector3(CELL_SIZE * 0.90, 0.020, CELL_SIZE * 0.90), Color(0.030, 0.024, 0.018, 0.28), cache_root, true)
	_add_box("CacheBody", Vector3(0.0, 0.25, 0.0), Vector3(1.20, 0.50, 0.86), Color(0.52, 0.34, 0.19), cache_root)
	_add_box("CacheDarkFace", Vector3(0.43, 0.27, 0.0), Vector3(0.06, 0.42, 0.82), Color(0.20, 0.15, 0.12), cache_root)
	_add_box("CacheLid", Vector3(0.0, 0.58, -0.08), Vector3(1.36, 0.18, 0.94), Color(0.96, 0.62, 0.28), cache_root, false, false, 0.10, Color(1.0, 0.48, 0.15))
	_add_box("CacheBandLeft", Vector3(-0.42, 0.61, -0.08), Vector3(0.07, 0.22, 0.96), Color(0.16, 0.12, 0.10), cache_root)
	_add_box("CacheBandRight", Vector3(0.42, 0.61, -0.08), Vector3(0.07, 0.22, 0.96), Color(0.16, 0.12, 0.10), cache_root)
	_add_box("CacheAccent", Vector3(0.0, 0.72, -0.10), Vector3(0.32, 0.045, 0.18), Color(0.17, 0.78, 1.0), cache_root, false, false, 1.20, Color(0.18, 0.80, 1.0))
	_add_box("CacheLock", Vector3(0.0, 0.42, -0.48), Vector3(0.18, 0.22, 0.06), Color(0.95, 0.75, 0.34), cache_root, false, false, 0.28, Color(1.0, 0.64, 0.20))


func _add_wall(props_root: Node3D, position: Vector3, size: Vector3) -> void:
	_add_box("WallShadow", Vector3(position.x - 0.22, 0.030, position.z + 0.58), Vector3(size.x * 1.06, 0.018, 0.76), Color(0.012, 0.011, 0.010, 0.42), props_root, true)
	_add_box("ForegroundWall", position, size, Color(0.34, 0.30, 0.27), props_root)
	_add_box("WallSideDark", position + Vector3(size.x * 0.5 + 0.030, 0.0, 0.0), Vector3(0.08, size.y, size.z), Color(0.12, 0.13, 0.14), props_root)
	_add_box(
		"WallTop",
		position + Vector3(0.0, size.y * 0.5 + 0.035, 0.0),
		Vector3(size.x, 0.07, size.z * 1.25),
		Color(0.72, 0.52, 0.30),
		props_root,
		false,
		false,
		0.12,
		Color(1.0, 0.58, 0.20)
	)
	_add_box("WallTopHighlight", position + Vector3(-0.05, size.y * 0.5 + 0.085, -0.12), Vector3(size.x * 0.92, 0.020, 0.045), Color(1.0, 0.74, 0.30, 0.48), props_root, true, true, 0.36, Color(1.0, 0.62, 0.20))


func _add_column(props_root: Node3D, column_name: String, position: Vector3) -> void:
	var column_root := Node3D.new()
	column_root.name = column_name
	column_root.position = position
	props_root.add_child(column_root)
	_add_box("ColumnShadow", Vector3(0.08, 0.020, 0.14), Vector3(0.94, 0.018, 0.66), Color(0.012, 0.011, 0.010, 0.42), column_root, true)
	_add_cylinder("Base", Vector3(0.0, 0.10, 0.0), 0.20, 0.52, 0.58, Color(0.30, 0.26, 0.22), column_root)
	_add_cylinder("Shaft", Vector3(0.0, 0.88, 0.0), 1.54, 0.34, 0.42, Color(0.50, 0.42, 0.34), column_root)
	_add_cylinder("Cap", Vector3(0.0, 1.68, 0.0), 0.18, 0.48, 0.42, Color(0.76, 0.62, 0.45), column_root, false, false, 0.10, Color(1.0, 0.72, 0.38))
	_add_box("ColdRim", Vector3(0.28, 0.90, -0.02), Vector3(0.040, 1.08, 0.16), Color(0.10, 0.22, 0.32, 0.55), column_root, true, true, 0.32, Color(0.18, 0.48, 0.82))


func _add_beacon(props_root: Node3D, beacon_name: String, position: Vector3, glow_color: Color) -> void:
	var beacon_root := Node3D.new()
	beacon_root.name = beacon_name
	beacon_root.position = position
	props_root.add_child(beacon_root)
	_add_box("BeaconShadow", Vector3(0.08, 0.020, 0.10), Vector3(0.70, 0.016, 0.48), Color(0.010, 0.009, 0.008, 0.34), beacon_root, true)
	_add_cylinder("Base", Vector3(0.0, 0.10, 0.0), 0.20, 0.30, 0.36, Color(0.24, 0.22, 0.20), beacon_root)
	_add_cylinder("Stem", Vector3(0.0, 0.44, 0.0), 0.55, 0.12, 0.16, Color(0.38, 0.34, 0.28), beacon_root)
	_add_box("GlowCore", Vector3(0.0, 0.78, 0.0), Vector3(0.34, 0.16, 0.34), Color(glow_color.r, glow_color.g, glow_color.b, 0.70), beacon_root, true, false, 1.35, glow_color)
	_add_box("GlowHalo", Vector3(0.0, 0.58, 0.0), Vector3(0.88, 0.018, 0.88), Color(glow_color.r, glow_color.g, glow_color.b, 0.16), beacon_root, true, true, 0.55, glow_color)


func _add_player(actors_root: Node3D, position: Vector3) -> void:
	var player_root := Node3D.new()
	player_root.name = "Player3D"
	player_root.position = position
	actors_root.add_child(player_root)

	_add_box("PlayerShadow", Vector3(0.0, 0.025, 0.0), Vector3(0.98, 0.020, 0.74), Color(0.008, 0.010, 0.013, 0.52), player_root, true)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.36
	body.mesh = capsule
	body.material_override = _make_material(Color(0.18, 0.65, 1.0), false, false, 0.18, Color(0.20, 0.75, 1.0))
	body.position = Vector3(0.0, 0.78, 0.0)
	player_root.add_child(body)

	_add_box("AimMarker", Vector3(0.0, 0.35, -0.50), Vector3(0.22, 0.16, 0.60), Color(1.0, 0.84, 0.28), player_root, false, false, 0.92, Color(1.0, 0.70, 0.18))
	_add_box("BackRim", Vector3(0.0, 0.84, 0.31), Vector3(0.46, 0.56, 0.045), Color(0.08, 0.18, 0.30, 0.50), player_root, true, true, 0.36, Color(0.16, 0.50, 0.95))
	_add_box("FootLight", Vector3(0.0, 0.055, -0.26), Vector3(0.62, 0.018, 0.08), Color(0.18, 0.72, 1.0, 0.28), player_root, true, true, 0.40, Color(0.18, 0.72, 1.0))


func _add_overlay(root_node: Node3D) -> void:
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	root_node.add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 0.02
	panel.anchor_top = 0.02
	panel.anchor_right = 0.34
	panel.anchor_bottom = 0.19
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
	label.text = "3D Orthographic Slice\nWASD move / mouse aim\nEditable scene nodes"
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


func _add_group(parent: Node, group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	parent.add_child(group)
	return group


func _add_box(
	name: String,
	position: Vector3,
	size: Vector3,
	color: Color,
	parent: Node,
	transparent: bool = false,
	unshaded: bool = false,
	emission_energy: float = 0.0,
	emission_color: Color = Color.WHITE
) -> MeshInstance3D:
	return _add_box_with_material(
		name,
		position,
		size,
		_make_material(color, transparent, unshaded, emission_energy, emission_color),
		parent
	)


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


func _add_omni_light(
	parent: Node,
	light_name: String,
	position: Vector3,
	color: Color,
	energy: float,
	light_range: float
) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	parent.add_child(light)
	return light


func _add_cylinder(
	name: String,
	position: Vector3,
	height: float,
	top_radius: float,
	bottom_radius: float,
	color: Color,
	parent: Node,
	transparent: bool = false,
	unshaded: bool = false,
	emission_energy: float = 0.0,
	emission_color: Color = Color.WHITE
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material(color, transparent, unshaded, emission_energy, emission_color)
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	return mesh_instance


func _make_material(
	color: Color,
	transparent: bool = false,
	unshaded: bool = false,
	emission_energy: float = 0.0,
	emission_color: Color = Color.WHITE
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission_color
		material.emission_energy_multiplier = emission_energy
	return material


func _assign_owner(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for child in node.get_children():
		_assign_owner(child, owner_node)
