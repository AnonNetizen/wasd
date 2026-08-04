class_name TestLabSlimeCrossPerspective
extends TestLabSlimeCross2D

const PERSPECTIVE_SHADER: Shader = preload("res://shaders/anchored_star_window.gdshader")

var _perspective_fill: Polygon2D
var _perspective_material: ShaderMaterial
var _fixed_step_mode: bool = false


func _ready() -> void:
	super()
	_create_perspective_fill()
	set_debug_rig_enabled(false)
	_sync_perspective_fill()


func _physics_process(delta: float) -> void:
	if _fixed_step_mode:
		_sync_perspective_fill()
		return
	super(delta)
	_sync_perspective_fill()


func _draw() -> void:
	if _points.is_empty():
		return
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	var closed_boundary := PackedVector2Array(boundary)
	closed_boundary.append(boundary[0])

	draw_polyline(closed_boundary, Color(0.005, 0.012, 0.032, 0.92), 28.0, true)
	draw_polyline(closed_boundary, Color(0.20, 0.67, 0.96, 0.34), 18.0, true)
	draw_polyline(closed_boundary, Color(0.48, 0.86, 1.0, 0.96), 7.0, true)
	draw_polyline(closed_boundary, Color(0.94, 0.98, 1.0, 0.72), 2.0, true)
	_draw_impact_ripple()
	_draw_debug_rig()


func set_perspective_animation_time(time_seconds: float) -> void:
	if _perspective_material == null:
		return
	_perspective_material.set_shader_parameter("animation_time", maxf(time_seconds, 0.0))


func set_viewport_aspect(viewport_aspect: float) -> void:
	if _perspective_material == null:
		return
	_perspective_material.set_shader_parameter("viewport_aspect", maxf(viewport_aspect, 0.01))


func set_fixed_step_mode(enabled: bool) -> void:
	_fixed_step_mode = enabled


func advance_fixed_step(delta: float) -> void:
	if not _fixed_step_mode or _points.is_empty():
		return
	var safe_delta: float = clampf(delta, 0.0001, 0.033)
	_time += safe_delta
	_update_membrane(safe_delta)
	_impact_strength = move_toward(_impact_strength, 0.0, safe_delta * 1.7)
	_sync_perspective_fill()
	queue_redraw()


func reset_immediately() -> void:
	super()
	_time = 0.0
	_sync_perspective_fill()


func perspective_material() -> ShaderMaterial:
	return _perspective_material


func perspective_fill_point_count() -> int:
	return _perspective_fill.polygon.size() if _perspective_fill != null else 0


func perspective_fill_matches_boundary() -> bool:
	if _perspective_fill == null:
		return false
	var boundary: PackedVector2Array = _smoothed_boundary_points()
	if _perspective_fill.polygon.size() != boundary.size():
		return false
	for index in range(boundary.size()):
		if _perspective_fill.polygon[index].distance_to(boundary[index]) > 0.01:
			return false
	return true


func _create_perspective_fill() -> void:
	_perspective_material = ShaderMaterial.new()
	_perspective_material.shader = PERSPECTIVE_SHADER
	_perspective_material.set_shader_parameter("animation_time", 0.0)
	_perspective_material.set_shader_parameter("star_scale", 0.82)

	_perspective_fill = Polygon2D.new()
	_perspective_fill.name = "PerspectiveFill"
	_perspective_fill.color = Color.WHITE
	_perspective_fill.material = _perspective_material
	_perspective_fill.show_behind_parent = true
	add_child(_perspective_fill)


func _sync_perspective_fill() -> void:
	if _perspective_fill == null or _points.is_empty():
		return
	_perspective_fill.polygon = _smoothed_boundary_points()
