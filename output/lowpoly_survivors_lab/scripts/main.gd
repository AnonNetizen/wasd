extends Node3D
## Standalone composition root for the low-poly survivor experiment.

enum RunState {
	MENU,
	RUNNING,
	LEVEL_UP,
	PAUSED,
	VICTORY,
	DEFEAT,
}

const DIRECTOR_SCRIPT_PATH := "res://scripts/core/run_director.gd"
const MODEL_PATHS := {
	"base": "res://assets/models/env_base_large.glb",
	"dome": "res://assets/models/env_geodesic_dome.glb",
	"solar": "res://assets/models/env_solar_panel_ground.glb",
	"radar": "res://assets/models/env_roof_radar.glb",
	"rock": "res://assets/models/env_rock.glb",
	"plant": "res://assets/models/env_plant.glb",
}
const ARENA_HALF_EXTENT: float = 80.0
const CENTRAL_CLEAR_RADIUS: float = 52.0
const CAMERA_FOLLOW_OFFSET := Vector3(0.0, 58.0, 58.0)

var _director: Node

@onready var _structure_root: Node3D = $World/PerimeterStructures
@onready var _vegetation: MultiMeshInstance3D = $World/VegetationMultiMesh
@onready var _rocks: MultiMeshInstance3D = $World/RockMultiMesh
@onready var _camera: Camera3D = $FixedCamera
@onready var _ui: LowpolyLabUI = $LabUI
@onready var _audio: GeneratedLabAudio = $GeneratedAudio


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_perimeter_environment()
	_build_multimesh_scatter()
	_director = _install_director()
	_connect_ui()
	if _director == null:
		_ui.set_status_message("核心运行脚本尚未安装，当前只能预览场景。", true)
		return
	_connect_director()
	if _director.has_method("get_state"):
		_ui.show_state(int(_director.call("get_state")))


func _process(delta: float) -> void:
	if _director == null or not _director.has_method("get_player"):
		return
	var player: Node3D = _director.call("get_player") as Node3D
	if not is_instance_valid(player):
		return
	var target_position := player.global_position + CAMERA_FOLLOW_OFFSET
	_camera.global_position = _camera.global_position.lerp(target_position, minf(delta * 6.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause_run") or event.is_echo():
		return
	if _director == null or not _director.has_method("get_state"):
		return
	var state := int(_director.call("get_state"))
	if state == RunState.RUNNING or state == RunState.PAUSED:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func director() -> Node:
	return _director


func _install_director() -> Node:
	var placeholder := get_node_or_null("RunDirector")
	if placeholder != null and placeholder.get_script() != null:
		return placeholder
	if not ResourceLoader.exists(DIRECTOR_SCRIPT_PATH):
		return null
	var director_script := load(DIRECTOR_SCRIPT_PATH) as Script
	if director_script == null:
		return null
	var instance: Variant = director_script.new()
	if not instance is Node:
		return null
	if placeholder != null:
		remove_child(placeholder)
		placeholder.queue_free()
	var director_node := instance as Node
	director_node.name = "RunDirector"
	add_child(director_node)
	return director_node


func _connect_ui() -> void:
	_ui.start_requested.connect(_on_start_requested)
	_ui.pause_requested.connect(_toggle_pause)
	_ui.upgrade_selected.connect(_on_upgrade_selected)
	_ui.restart_requested.connect(_on_restart_requested)
	_ui.menu_requested.connect(_on_menu_requested)


func _connect_director() -> void:
	_connect_optional_signal(&"state_changed", _on_state_changed)
	_connect_optional_signal(&"health_changed", _ui.set_health)
	_connect_optional_signal(&"experience_changed", _ui.set_experience)
	_connect_optional_signal(&"upgrade_requested", _on_upgrade_requested)
	_connect_optional_signal(&"boss_spawned", _on_boss_spawned)
	_connect_optional_signal(&"boss_health_changed", _ui.set_boss_health)
	_connect_optional_signal(&"run_finished", _on_run_finished)
	_connect_optional_signal(&"time_changed", _ui.set_time)
	_connect_optional_signal(&"kill_count_changed", _ui.set_kills)
	_connect_optional_signal(&"weapon_levels_changed", _ui.set_weapon_levels)
	_connect_optional_signal(&"audio_cue_requested", _audio.play_cue)


func _connect_optional_signal(signal_name: StringName, callable: Callable) -> void:
	if _director.has_signal(signal_name) and not _director.is_connected(signal_name, callable):
		_director.connect(signal_name, callable)


func _on_start_requested() -> void:
	_audio.play_cue(&"click")
	if _director == null or not _director.has_method("start_run"):
		_ui.set_status_message("无法启动：RunDirector 不可用。", true)
		return
	_director.call("start_run")


func _toggle_pause() -> void:
	if _director == null or not _director.has_method("toggle_pause"):
		return
	_audio.play_cue(&"click")
	_director.call("toggle_pause")


func _on_upgrade_selected(upgrade_id: String) -> void:
	if _director == null or not _director.has_method("choose_upgrade"):
		return
	_audio.play_cue(&"click")
	_director.call("choose_upgrade", StringName(upgrade_id))


func _on_restart_requested() -> void:
	_audio.play_cue(&"click")
	if _director != null and _director.has_method("restart_run"):
		_director.call("restart_run")


func _on_menu_requested() -> void:
	_audio.play_cue(&"click")
	if _director != null and _director.has_method("return_to_menu"):
		_director.call("return_to_menu")


func _on_state_changed(_previous: int, current: int) -> void:
	_ui.show_state(current)


func _on_upgrade_requested(options: Array[Dictionary]) -> void:
	_audio.play_cue(&"upgrade")
	_ui.show_upgrade(options)


func _on_boss_spawned(enemy: Variant) -> void:
	_audio.play_cue(&"alarm")
	_ui.show_boss(enemy)


func _on_run_finished(victory: bool, summary: Dictionary) -> void:
	_audio.play_cue(&"victory" if victory else &"defeat")
	_ui.show_result(victory, summary)


func _build_perimeter_environment() -> void:
	_add_model("base", Vector3(-61.0, 0.0, -54.0), -0.15, 2.5, "BaseWest")
	_add_model("base", Vector3(59.0, 0.0, 54.0), PI + 0.10, 2.1, "BaseEast")
	_add_model("dome", Vector3(58.0, 0.0, -55.0), 0.0, 2.9, "ResearchDome")
	_add_model("dome", Vector3(-56.0, 0.0, 58.0), PI * 0.25, 1.9, "HabitatDome")
	for index in range(5):
		var z := -44.0 + float(index) * 18.0
		_add_model("solar", Vector3(69.0, 0.0, z), -PI * 0.5, 2.0, "SolarArray%d" % (index + 1))
	_add_model("radar", Vector3(-66.0, 0.0, -15.0), PI * 0.5, 2.4, "RadarNorth")
	_add_model("radar", Vector3(-66.0, 0.0, 18.0), PI * 0.5, 2.0, "RadarSouth")
	_add_perimeter_landing_pads()


func _add_model(
	model_key: String,
	position: Vector3,
	y_rotation: float,
	uniform_scale: float,
	node_name: String
) -> void:
	var path := String(MODEL_PATHS.get(model_key, ""))
	if path == "" or not ResourceLoader.exists(path):
		push_warning("Lowpoly environment model missing: %s" % path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Lowpoly environment model could not be loaded: %s" % path)
		return
	var instance := packed.instantiate()
	if not instance is Node3D:
		instance.queue_free()
		return
	var model := instance as Node3D
	model.name = node_name
	model.position = position
	model.rotation.y = y_rotation
	model.scale = Vector3.ONE * uniform_scale
	_structure_root.add_child(model)


func _add_perimeter_landing_pads() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.18, 0.22, 1.0)
	material.roughness = 0.78
	material.emission_enabled = true
	material.emission = Color(0.02, 0.14, 0.18, 1.0)
	material.emission_energy_multiplier = 1.2
	for pad_data in [
		[Vector3(-61.0, 0.08, -54.0), Vector3(25.0, 0.16, 21.0)],
		[Vector3(59.0, 0.08, 54.0), Vector3(23.0, 0.16, 20.0)],
		[Vector3(58.0, 0.07, -55.0), Vector3(20.0, 0.14, 20.0)],
		[Vector3(-56.0, 0.07, 58.0), Vector3(18.0, 0.14, 18.0)],
	]:
		var mesh := BoxMesh.new()
		mesh.size = pad_data[1]
		mesh.material = material
		var pad := MeshInstance3D.new()
		pad.mesh = mesh
		pad.position = pad_data[0]
		_structure_root.add_child(pad)


func _build_multimesh_scatter() -> void:
	_vegetation.multimesh = _make_scatter_multimesh("plant", 64, 58.0, 76.0, 0.82, 1.45, 17.0)
	_rocks.multimesh = _make_scatter_multimesh("rock", 52, 56.0, 77.0, 0.70, 1.65, 43.0)


func _make_scatter_multimesh(
	model_key: String,
	count: int,
	minimum_radius: float,
	maximum_radius: float,
	minimum_scale: float,
	maximum_scale: float,
	angle_offset_degrees: float
) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _extract_first_mesh(String(MODEL_PATHS.get(model_key, "")), model_key)
	multimesh.instance_count = count
	var golden_angle := TAU * 0.38196601125
	var angle_offset := deg_to_rad(angle_offset_degrees)
	for index in range(count):
		var angle := angle_offset + float(index) * golden_angle
		var radial_wave := 0.5 + 0.5 * sin(float(index) * 2.173 + angle_offset)
		var radius := lerpf(minimum_radius, maximum_radius, radial_wave)
		radius = maxf(radius, CENTRAL_CLEAR_RADIUS + 3.0)
		var scale_factor := lerpf(minimum_scale, maximum_scale, 0.5 + 0.5 * sin(float(index) * 1.317))
		var basis := Basis(Vector3.UP, -angle + PI * 0.5)
		basis = basis.scaled(Vector3.ONE * scale_factor)
		var origin := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		origin.x = clampf(origin.x, -ARENA_HALF_EXTENT + 2.0, ARENA_HALF_EXTENT - 2.0)
		origin.z = clampf(origin.z, -ARENA_HALF_EXTENT + 2.0, ARENA_HALF_EXTENT - 2.0)
		multimesh.set_instance_transform(index, Transform3D(basis, origin))
	return multimesh


func _extract_first_mesh(path: String, model_key: String) -> Mesh:
	if path != "" and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var instance := packed.instantiate()
			var found := _find_mesh(instance)
			instance.free()
			if found != null:
				return found
	if model_key == "plant":
		var fallback_plant := PrismMesh.new()
		fallback_plant.size = Vector3(0.7, 2.4, 0.7)
		return fallback_plant
	var fallback_rock := SphereMesh.new()
	fallback_rock.height = 1.2
	fallback_rock.radius = 0.85
	return fallback_rock


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			return mesh_instance.mesh
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
