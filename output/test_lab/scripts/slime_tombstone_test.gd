extends Node3D

const AUTO_PULSE_INTERVAL: float = 2.35
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"

var _auto_pulse_enabled: bool = true
var _auto_pulse_index: int = 0
var _auto_pulse_timer: float = 0.85
var _impact_light_energy: float = 0.0

@onready var _auto_button: Button = get_node_or_null("Overlay/Controls/AutoButton") as Button
@onready var _camera: Camera3D = get_node_or_null("TombstoneCamera") as Camera3D
@onready var _exit_button: Button = get_node_or_null("Overlay/ExitButton") as Button
@onready var _impact_light: OmniLight3D = get_node_or_null("World3D/TombstoneStage/ImpactLight") as OmniLight3D
@onready var _metrics_label: Label = get_node_or_null("Overlay/MetricsPanel/Margin/Metrics") as Label
@onready var _poke_button: Button = get_node_or_null("Overlay/Controls/PokeButton") as Button
@onready var _reset_button: Button = get_node_or_null("Overlay/Controls/ResetButton") as Button
@onready var _squash_button: Button = get_node_or_null("Overlay/Controls/SquashButton") as Button
@onready var _tombstone: Node3D = get_node_or_null(
	"World3D/TombstoneStage/SlimeTombstone"
) as Node3D


func _ready() -> void:
	if _poke_button != null:
		_poke_button.pressed.connect(_poke_center)
	if _squash_button != null:
		_squash_button.pressed.connect(_squash)
	if _reset_button != null:
		_reset_button.pressed.connect(_reset)
	if _auto_button != null:
		_auto_button.pressed.connect(_toggle_auto_pulse)
	if _exit_button != null:
		_exit_button.pressed.connect(_return_to_index)
	_update_auto_button()
	_update_metrics()


func _process(delta: float) -> void:
	if _auto_pulse_enabled and _tombstone != null:
		_auto_pulse_timer -= delta
		if _auto_pulse_timer <= 0.0:
			_run_auto_pulse()
			_auto_pulse_timer = AUTO_PULSE_INTERVAL

	_impact_light_energy = move_toward(_impact_light_energy, 0.0, delta * 3.8)
	if _impact_light != null:
		_impact_light.light_energy = _impact_light_energy
	_update_metrics()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if not _is_pointer_over_button():
				_poke_from_screen(mouse_event.position)
				get_viewport().set_input_as_handled()
		return

	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_SPACE:
			_squash()
		KEY_R:
			_reset()
		KEY_A:
			_toggle_auto_pulse()
		KEY_ESCAPE:
			_return_to_index()
		_:
			return
	get_viewport().set_input_as_handled()


func debug_poke(local_hit: Vector2 = Vector2(-0.95, 3.25), strength: float = 1.0) -> void:
	if _tombstone == null:
		return
	_tombstone.call("apply_poke", local_hit, strength)
	_flash_impact()


func debug_squash(strength: float = 1.0) -> void:
	if _tombstone == null:
		return
	_tombstone.call("apply_squash", strength)
	_flash_impact()


func debug_reset() -> void:
	_reset()


func debug_set_auto_pulse(enabled: bool) -> void:
	_auto_pulse_enabled = enabled
	_update_auto_button()


func debug_control_point_count() -> int:
	return int(_tombstone.call("control_point_count")) if _tombstone != null else 0


func debug_deformation_amount() -> float:
	return float(_tombstone.call("deformation_amount")) if _tombstone != null else 0.0


func debug_anchored_deformation_amount() -> float:
	return float(_tombstone.call("anchored_deformation_amount")) if _tombstone != null else 0.0


func debug_area_ratio() -> float:
	return float(_tombstone.call("current_area_ratio")) if _tombstone != null else 0.0


func debug_silhouette_size() -> Vector2:
	return _tombstone.call("silhouette_size") if _tombstone != null else Vector2.ZERO


func debug_visual_layer_count() -> int:
	return int(_tombstone.call("visual_layer_count")) if _tombstone != null else 0


func debug_visual_layers_share_mesh() -> bool:
	return bool(_tombstone.call("visual_layers_share_mesh")) if _tombstone != null else false


func _flash_impact() -> void:
	_impact_light_energy = 2.8


func _is_pointer_over_button() -> bool:
	var hovered_control: Control = get_viewport().gui_get_hovered_control()
	return hovered_control is Button


func _poke_center() -> void:
	debug_poke(Vector2(0.62, 2.55), 1.05)


func _poke_from_screen(screen_position: Vector2) -> void:
	if _camera == null or _tombstone == null:
		return
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_position)
	var plane_normal: Vector3 = _tombstone.global_basis.z.normalized()
	var tombstone_plane := Plane(
		plane_normal,
		plane_normal.dot(_tombstone.global_position)
	)
	var intersection: Variant = tombstone_plane.intersects_ray(ray_origin, ray_direction)
	if intersection == null or not intersection is Vector3:
		return
	var world_hit: Vector3 = intersection
	var local_hit_3d: Vector3 = _tombstone.to_local(world_hit)
	var local_hit := Vector2(
		clampf(local_hit_3d.x, -1.55, 1.55),
		clampf(local_hit_3d.y, -0.15, 4.55)
	)
	debug_poke(local_hit, 1.0)


func _reset() -> void:
	if _tombstone != null:
		_tombstone.call("reset_immediately")
	_auto_pulse_timer = 0.85
	_impact_light_energy = 0.0


func _return_to_index() -> void:
	var error: Error = get_tree().change_scene_to_file(INDEX_SCENE_PATH)
	if error != OK:
		push_error("Failed to return to Test Lab index: %s" % error)


func _run_auto_pulse() -> void:
	var pulse_points: Array[Vector2] = [
		Vector2(-1.10, 2.75),
		Vector2(0.95, 3.45),
		Vector2(0.10, 4.20),
		Vector2(1.18, 1.60),
	]
	var local_hit: Vector2 = pulse_points[_auto_pulse_index % pulse_points.size()]
	_auto_pulse_index += 1
	debug_poke(local_hit, 0.78)


func _squash() -> void:
	debug_squash(1.0)


func _toggle_auto_pulse() -> void:
	_auto_pulse_enabled = not _auto_pulse_enabled
	_auto_pulse_timer = 0.55
	_update_auto_button()


func _update_auto_button() -> void:
	if _auto_button == null:
		return
	_auto_button.text = "自动脉冲：开" if _auto_pulse_enabled else "自动脉冲：关"


func _update_metrics() -> void:
	if _metrics_label == null or _tombstone == null:
		return
	var size: Vector2 = _tombstone.call("silhouette_size")
	_metrics_label.text = (
		"轮廓控制点  %d\n动态渲染层  %d（共享网格）\n"
		+ "形变  %.3f\n面积保持  %.1f%%\n轮廓宽高  %.2f × %.2f"
	) % [
		int(_tombstone.call("control_point_count")),
		int(_tombstone.call("visual_layer_count")),
		float(_tombstone.call("deformation_amount")),
		float(_tombstone.call("current_area_ratio")) * 100.0,
		size.x,
		size.y,
	]
