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
const CAMERA_LOOK_HEIGHT: float = 0.8
const COLLISION_LAYER_WORLD: int = 4
const COLLISION_PROXY_HORIZONTAL_SCALE: float = 0.9

var _director: Node
var _session: LowpolyOnlineSession
var _network_bridge: LowpolyNetworkRunBridge
var _pending_online_action: StringName = &""
var _pending_room_code: String = ""

@onready var _structure_root: Node3D = $World/PerimeterStructures
@onready var _ground: StaticBody3D = $World/Ground
@onready var _vegetation: MultiMeshInstance3D = $World/VegetationMultiMesh
@onready var _rocks: MultiMeshInstance3D = $World/RockMultiMesh
@onready var _camera: Camera3D = $FixedCamera
@onready var _ui: LowpolyLabUI = $LabUI
@onready var _audio: GeneratedLabAudio = $GeneratedAudio


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ground.collision_layer = 0
	_ground.collision_mask = 0
	_build_perimeter_environment()
	_build_multimesh_scatter()
	_camera.look_at(Vector3.UP * CAMERA_LOOK_HEIGHT, Vector3.UP)
	_director = _install_director()
	_connect_ui()
	if _director == null:
		_ui.set_status_message("核心运行脚本尚未安装，当前只能预览场景。", true)
		return
	_connect_director()
	_install_online_bridge()
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
	_camera.look_at(player.global_position + Vector3.UP * CAMERA_LOOK_HEIGHT, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause_run") or event.is_echo():
		return
	if _director == null or not _director.has_method("get_state"):
		return
	var state := int(_director.call("get_state"))
	if _session != null and _session.is_online_match():
		_ui.show_local_menu(not _ui.is_local_menu_open(), true)
		get_viewport().set_input_as_handled()
		return
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
	_ui.create_room_requested.connect(_on_create_room_requested)
	_ui.join_room_requested.connect(_on_join_room_requested)
	_ui.ready_requested.connect(_on_ready_requested)
	_ui.lobby_start_requested.connect(_on_lobby_start_requested)
	_ui.leave_room_requested.connect(_on_leave_room_requested)
	_ui.touch_input_changed.connect(_on_touch_input_changed)


func _install_online_bridge() -> void:
	_session = OnlineSession as LowpolyOnlineSession
	if _session == null or not _director is LowpolyRunDirector:
		_ui.set_online_status("联机会话模块不可用；单人模式仍可用。", true)
		return
	_network_bridge = LowpolyNetworkRunBridge.new()
	_network_bridge.name = "NetworkRunBridge"
	add_child(_network_bridge)
	_network_bridge.setup(_session, _director as LowpolyRunDirector)
	_session.state_changed.connect(_on_session_state_changed)
	_session.room_changed.connect(_on_online_room_changed)
	_session.session_error.connect(_on_online_error)
	_session.connection_progress.connect(_on_connection_progress)
	_network_bridge.match_started.connect(_on_online_match_started)
	_network_bridge.upgrade_offer_received.connect(_on_online_upgrade_offer)
	_network_bridge.latency_changed.connect(_ui.set_latency)
	_network_bridge.migration_notice.connect(_ui.show_migration)
	_network_bridge.online_match_interrupted.connect(_on_online_interrupted)
	if _director.has_signal("player_roster_changed"):
		_director.connect("player_roster_changed", _on_player_roster_changed)


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
	if _session != null and _session.get_state() != LowpolyOnlineSession.State.OFFLINE:
		_session.leave_room()
	if _network_bridge != null:
		_network_bridge.stop_match()
	if _director == null or not _director.has_method("start_run"):
		_ui.set_status_message("无法启动：RunDirector 不可用。", true)
		return
	_director.call("start_run")


func _toggle_pause() -> void:
	if _director == null or not _director.has_method("toggle_pause"):
		return
	_audio.play_cue(&"click")
	if _session != null and _session.is_online_match():
		_ui.show_local_menu(not _ui.is_local_menu_open(), true)
		return
	_director.call("toggle_pause")


func _on_upgrade_selected(upgrade_id: String) -> void:
	if _director == null or not _director.has_method("choose_upgrade"):
		return
	_audio.play_cue(&"click")
	if _session != null and _session.is_online_match() and _network_bridge != null:
		_network_bridge.submit_upgrade_choice(StringName(upgrade_id))
	else:
		_director.call("choose_upgrade", StringName(upgrade_id))


func _on_restart_requested() -> void:
	_audio.play_cue(&"click")
	if _session != null and _session.is_online_match():
		_on_menu_requested()
		return
	if _director != null and _director.has_method("restart_run"):
		_director.call("restart_run")


func _on_menu_requested() -> void:
	_audio.play_cue(&"click")
	_ui.show_local_menu(false, false)
	_ui.hide_lobby()
	if _network_bridge != null:
		_network_bridge.stop_match()
	if _session != null:
		_session.leave_room()
	if _director != null and _director.has_method("return_to_menu"):
		_director.call("return_to_menu")


func _on_state_changed(_previous: int, current: int) -> void:
	if current != RunState.PAUSED:
		_ui.show_local_menu(false, _session != null and _session.is_online_match())
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


func _on_create_room_requested(display_name: String) -> void:
	_begin_online_action(&"create", display_name, "")


func _on_join_room_requested(display_name: String, room_code: String) -> void:
	_begin_online_action(&"join", display_name, room_code)


func _begin_online_action(action: StringName, display_name: String, room_code: String) -> void:
	if _session == null:
		_ui.set_online_status("联机会话模块不可用。", true)
		return
	_pending_online_action = action
	_pending_room_code = room_code
	var state := _session.get_state()
	if state == LowpolyOnlineSession.State.IDLE:
		_execute_pending_online_action()
		return
	if state != LowpolyOnlineSession.State.OFFLINE and state != LowpolyOnlineSession.State.ERROR:
		_ui.set_online_status("EOS 正在处理上一项操作，请稍候。", true)
		return
	_ui.set_online_status("正在初始化 EOS Device ID……")
	_session.initialize_online(display_name)


func _execute_pending_online_action() -> void:
	if _pending_online_action == &"create":
		_session.create_room()
	elif _pending_online_action == &"join":
		_session.join_room(_pending_room_code)
	_pending_online_action = &""
	_pending_room_code = ""


func _on_session_state_changed(_previous: int, current: int) -> void:
	match current:
		LowpolyOnlineSession.State.IDLE:
			_ui.set_online_status("EOS 已连接。")
			if not _pending_online_action.is_empty():
				_execute_pending_online_action()
		LowpolyOnlineSession.State.CREATING_ROOM:
			_ui.set_online_status("正在创建房间……")
		LowpolyOnlineSession.State.JOINING_ROOM:
			_ui.set_online_status("正在加入房间……")
		LowpolyOnlineSession.State.CONNECTING:
			_ui.set_online_status("正在建立 EOS P2P/Relay 连接……")
		LowpolyOnlineSession.State.HOST_MIGRATING:
			_ui.show_migration(true, "房主迁移中，战斗已冻结……")
		_:
			pass


func _on_online_room_changed(snapshot: Dictionary) -> void:
	if (
		_session != null
		and not snapshot.is_empty()
		and _session.get_state() in [
			LowpolyOnlineSession.State.CREATING_ROOM,
			LowpolyOnlineSession.State.JOINING_ROOM,
			LowpolyOnlineSession.State.LOBBY,
			LowpolyOnlineSession.State.CONNECTING,
		]
	):
		_ui.show_lobby(snapshot, _session.get_local_user_id())


func _on_ready_requested(ready: bool) -> void:
	if _session != null and not _session.set_ready(ready):
		_ui.set_online_status("无法更新准备状态。", true)


func _on_lobby_start_requested() -> void:
	if _session == null:
		_ui.set_online_status("联机会话模块不可用。", true)
		return
	if not _session.can_start_match():
		_ui.set_online_status("需要房主且所有玩家均已准备。", true)
		return
	_session.start_match()


func _on_leave_room_requested() -> void:
	_ui.hide_lobby()
	if _session != null:
		_session.leave_room()
	if _director != null and _director.has_method("return_to_menu"):
		_director.call("return_to_menu")


func _on_online_match_started(_local_slot: int, _role: int) -> void:
	_ui.hide_lobby()
	_ui.show_local_menu(false, true)
	_ui.show_state(RunState.RUNNING)


func _on_online_upgrade_offer(options: Array[Dictionary]) -> void:
	_ui.show_upgrade(options)
	_ui.show_state(RunState.LEVEL_UP)


func _on_player_roster_changed(roster: Array[Dictionary]) -> void:
	if _director is LowpolyRunDirector:
		_ui.set_teammates(roster, (_director as LowpolyRunDirector).get_local_slot())


func _on_touch_input_changed(value: Vector2) -> void:
	if _director != null and _director.has_method("set_touch_input"):
		_director.call("set_touch_input", value)
	if _network_bridge != null:
		_network_bridge.set_touch_input(value)


func _on_online_error(message: String) -> void:
	_ui.set_online_status(message, true)


func _on_connection_progress(message: String) -> void:
	_ui.set_online_status(message)
	_ui.set_connection_diagnostic(message)


func _on_online_interrupted(message: String) -> void:
	if _network_bridge != null:
		_network_bridge.stop_match()
	if _director != null and _director.has_method("return_to_menu"):
		_director.call("return_to_menu")
	_ui.set_online_status("联机中断：%s" % message, true)
	_ui.show_migration(false, "联机中断")


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
	_add_collision_proxy(model)


func _add_collision_proxy(model: Node3D) -> void:
	var bounds := _model_local_bounds(model)
	if bounds.size.is_zero_approx():
		push_warning("Lowpoly environment model has no mesh bounds: %s" % model.name)
		return
	var body := StaticBody3D.new()
	body.name = "CollisionProxy"
	body.collision_layer = COLLISION_LAYER_WORLD
	body.collision_mask = 0
	body.position = bounds.get_center()
	body.add_to_group("lowpoly_world_obstacle")
	model.add_child(body)
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(bounds.size.x * COLLISION_PROXY_HORIZONTAL_SCALE, 0.4),
		maxf(bounds.size.y, 0.8),
		maxf(bounds.size.z * COLLISION_PROXY_HORIZONTAL_SCALE, 0.4)
	)
	collision_shape.shape = box
	body.add_child(collision_shape)


func _model_local_bounds(model: Node3D) -> AABB:
	var bounds: Array[AABB] = []
	_collect_model_bounds(model, model, bounds)
	if bounds.is_empty():
		return AABB()
	var merged: AABB = bounds[0]
	for index: int in range(1, bounds.size()):
		merged = merged.merge(bounds[index])
	return merged


func _collect_model_bounds(root: Node3D, node: Node, bounds: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var relative_transform := root.global_transform.affine_inverse() * mesh_instance.global_transform
			bounds.append(relative_transform * mesh_instance.get_aabb())
	for child: Node in node.get_children():
		_collect_model_bounds(root, child, bounds)


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
