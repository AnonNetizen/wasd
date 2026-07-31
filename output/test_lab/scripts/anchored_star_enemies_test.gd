extends Node2D

const SHADER_PATH: String = "res://shaders/anchored_star_window.gdshader"
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const ACTION_BACK: String = "lab_back"
const ACTION_TOGGLE_PAUSE: String = "lab_toggle_star_motion"
const ACTION_RESET: String = "lab_reset_star_motion"
const ENEMY_RADII := [94.0, 80.0, 66.0]
const ENEMY_COLORS := [
	Color(1.0, 0.18, 0.42, 1.0),
	Color(0.92, 0.33, 1.0, 1.0),
	Color(1.0, 0.48, 0.16, 1.0),
]
const MOTION_CENTERS := [
	Vector2(0.28, 0.42),
	Vector2(0.52, 0.47),
	Vector2(0.76, 0.58),
]
const MOTION_AMPLITUDES := [
	Vector2(0.17, 0.14),
	Vector2(0.18, 0.20),
	Vector2(0.14, 0.16),
]
const MOTION_FREQUENCIES := [
	Vector2(0.72, 1.08),
	Vector2(0.86, 0.59),
	Vector2(0.53, 0.94),
]
const MOTION_PHASES := [
	Vector2(0.00, 0.82),
	Vector2(1.72, 0.10),
	Vector2(3.02, 1.84),
]

var _enemies: Array[Node2D] = []
var _shared_star_material: ShaderMaterial
var _status_label: Label
var _motion_time: float = 0.0
var _motion_paused: bool = false
var _viewport_size: Vector2 = Vector2(1280.0, 760.0)


func _ready() -> void:
	_ensure_input_actions()
	_create_shared_material()
	if _shared_star_material == null:
		return
	_create_enemies()
	_create_hud()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_update_motion(0.0)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(ACTION_BACK):
		var error := get_tree().change_scene_to_file(INDEX_SCENE_PATH)
		if error != OK:
			push_error("Failed to return to Test Lab index: %s" % error)
		return
	if Input.is_action_just_pressed(ACTION_TOGGLE_PAUSE):
		set_motion_paused(not _motion_paused)
	if Input.is_action_just_pressed(ACTION_RESET):
		reset_motion()

	if not _motion_paused:
		_motion_time += delta
		_update_motion(_motion_time)
	_shared_star_material.set_shader_parameter("animation_time", _motion_time)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _viewport_size), Color(0.006, 0.010, 0.027, 1.0), true)

	var grid_color := Color(0.16, 0.31, 0.46, 0.15)
	for x in range(0, int(_viewport_size.x) + 1, 64):
		draw_line(Vector2(float(x), 0.0), Vector2(float(x), _viewport_size.y), grid_color, 1.0)
	for y in range(0, int(_viewport_size.y) + 1, 64):
		draw_line(Vector2(0.0, float(y)), Vector2(_viewport_size.x, float(y)), grid_color, 1.0)

	for enemy_index in range(ENEMY_RADII.size()):
		var path := PackedVector2Array()
		for sample_index in range(121):
			var sample_time := float(sample_index) / 120.0 * 8.0
			path.append(_motion_position(enemy_index, sample_time))
		var path_color: Color = ENEMY_COLORS[enemy_index]
		path_color.a = 0.18
		draw_polyline(path, path_color, 1.25, true)

	for anchor_index in range(11):
		var seed := float(anchor_index)
		var anchor := Vector2(
			fmod(97.0 + seed * 173.0, maxf(_viewport_size.x, 1.0)),
			fmod(151.0 + seed * 109.0, maxf(_viewport_size.y, 1.0))
		)
		draw_line(anchor - Vector2(7.0, 0.0), anchor + Vector2(7.0, 0.0), Color(0.35, 0.64, 0.82, 0.18), 1.0)
		draw_line(anchor - Vector2(0.0, 7.0), anchor + Vector2(0.0, 7.0), Color(0.35, 0.64, 0.82, 0.18), 1.0)


func set_motion_paused(paused: bool) -> void:
	_motion_paused = paused
	_update_status_label()


func reset_motion() -> void:
	_motion_time = 0.0
	_motion_paused = false
	_update_motion(_motion_time)
	_shared_star_material.set_shader_parameter("animation_time", _motion_time)
	_update_status_label()


func set_preview_time(time_seconds: float) -> void:
	_motion_time = maxf(time_seconds, 0.0)
	_motion_paused = true
	_update_motion(_motion_time)
	_shared_star_material.set_shader_parameter("animation_time", _motion_time)
	_update_status_label()


func debug_enemy_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for enemy in _enemies:
		positions.append(enemy.position)
	return positions


func debug_uses_single_material() -> bool:
	if _enemies.size() != 3 or _shared_star_material == null:
		return false
	for enemy in _enemies:
		var fill := enemy.get_node_or_null("StarFill") as Polygon2D
		if fill == null or fill.material != _shared_star_material:
			return false
	return true


func debug_shared_material() -> ShaderMaterial:
	return _shared_star_material


func _create_shared_material() -> void:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_error("Failed to load anchored star shader: %s" % SHADER_PATH)
		return
	_shared_star_material = ShaderMaterial.new()
	_shared_star_material.shader = shader
	_shared_star_material.set_shader_parameter("animation_time", 0.0)
	_shared_star_material.set_shader_parameter("star_scale", 1.0)


func _create_enemies() -> void:
	var enemy_layer := Node2D.new()
	enemy_layer.name = "EnemyLayer"
	add_child(enemy_layer)

	for enemy_index in range(ENEMY_RADII.size()):
		var enemy := _build_enemy(enemy_index)
		enemy_layer.add_child(enemy)
		_enemies.append(enemy)


func _build_enemy(enemy_index: int) -> Node2D:
	var radius: float = ENEMY_RADII[enemy_index]
	var accent: Color = ENEMY_COLORS[enemy_index]
	var enemy := Node2D.new()
	enemy.name = "StarEnemy%d" % (enemy_index + 1)
	enemy.add_to_group("star_enemy")
	enemy.set_meta("enemy_index", enemy_index)
	enemy.set_meta("radius", radius)

	var fill := Polygon2D.new()
	fill.name = "StarFill"
	fill.polygon = _circle_points(radius, 96, false)
	fill.color = Color.WHITE
	fill.material = _shared_star_material
	fill.z_index = 1
	enemy.add_child(fill)

	var outer_glow := Line2D.new()
	outer_glow.name = "OuterGlow"
	outer_glow.points = _circle_points(radius + 4.0, 96, true)
	outer_glow.closed = true
	outer_glow.width = 16.0
	outer_glow.default_color = Color(accent.r, accent.g, accent.b, 0.18)
	outer_glow.antialiased = true
	outer_glow.joint_mode = Line2D.LINE_JOINT_ROUND
	outer_glow.z_index = 0
	enemy.add_child(outer_glow)

	var outer_rim := Line2D.new()
	outer_rim.name = "OuterRim"
	outer_rim.points = _circle_points(radius + 1.0, 96, true)
	outer_rim.closed = true
	outer_rim.width = 6.0
	outer_rim.default_color = accent
	outer_rim.antialiased = true
	outer_rim.joint_mode = Line2D.LINE_JOINT_ROUND
	outer_rim.z_index = 2
	enemy.add_child(outer_rim)

	var inner_rim := Line2D.new()
	inner_rim.name = "InnerRim"
	inner_rim.points = _circle_points(radius - 8.0, 96, true)
	inner_rim.closed = true
	inner_rim.width = 2.0
	inner_rim.default_color = Color(0.90, 0.97, 1.0, 0.52)
	inner_rim.antialiased = true
	inner_rim.z_index = 2
	enemy.add_child(inner_rim)

	var attack_marker := Polygon2D.new()
	attack_marker.name = "AttackMarker"
	attack_marker.polygon = PackedVector2Array([
		Vector2(0.0, -radius - 18.0),
		Vector2(-10.0, -radius - 3.0),
		Vector2(10.0, -radius - 3.0),
	])
	attack_marker.color = accent
	attack_marker.z_index = 3
	enemy.add_child(attack_marker)

	var core_marker := Polygon2D.new()
	core_marker.name = "CoreMarker"
	core_marker.polygon = _circle_points(4.0, 20, false)
	core_marker.color = Color(1.0, 0.96, 0.82, 0.90)
	core_marker.z_index = 3
	enemy.add_child(core_marker)

	return enemy


func _create_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Hud"
	add_child(canvas)

	var header_panel := ColorRect.new()
	header_panel.name = "HeaderPanel"
	header_panel.position = Vector2(24.0, 20.0)
	header_panel.size = Vector2(570.0, 74.0)
	header_panel.color = Color(0.02, 0.035, 0.075, 0.88)
	header_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(header_panel)

	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(18.0, 10.0)
	title.text = "ANCHORED STAR WINDOWS"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 1.0))
	header_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.position = Vector2(18.0, 43.0)
	subtitle.text = "Three moving circular enemies · one screen-space star field"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.53, 0.76, 0.92, 0.88))
	header_panel.add_child(subtitle)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.size = Vector2(270.0, 34.0)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.43, 0.67, 0.96))
	canvas.add_child(_status_label)

	var hint := Label.new()
	hint.name = "Hints"
	hint.text = "SPACE  Pause / Resume     R  Reset     ESC  Back"
	hint.size = Vector2(520.0, 28.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.64, 0.72, 0.82, 0.82))
	canvas.add_child(hint)
	hint.set_meta("layout_role", "bottom_hint")

	_update_status_label()


func _on_viewport_size_changed() -> void:
	_viewport_size = get_viewport_rect().size
	if _viewport_size.x <= 0.0 or _viewport_size.y <= 0.0:
		_viewport_size = Vector2(1280.0, 760.0)
	if _shared_star_material != null:
		_shared_star_material.set_shader_parameter(
			"viewport_aspect",
			_viewport_size.x / maxf(_viewport_size.y, 1.0)
		)
	if _status_label != null:
		_status_label.position = Vector2(_viewport_size.x - 294.0, 32.0)
	var hint := get_node_or_null("Hud/Hints") as Label
	if hint != null:
		hint.position = Vector2((_viewport_size.x - hint.size.x) * 0.5, _viewport_size.y - 48.0)
	_update_motion(_motion_time)
	queue_redraw()


func _update_motion(time_seconds: float) -> void:
	for enemy_index in range(_enemies.size()):
		_enemies[enemy_index].position = _motion_position(enemy_index, time_seconds)


func _motion_position(enemy_index: int, time_seconds: float) -> Vector2:
	var top_margin := 108.0
	var bottom_margin := 74.0
	var play_height := maxf(_viewport_size.y - top_margin - bottom_margin, 1.0)
	var center_ratio: Vector2 = MOTION_CENTERS[enemy_index]
	var amplitude_ratio: Vector2 = MOTION_AMPLITUDES[enemy_index]
	var frequency: Vector2 = MOTION_FREQUENCIES[enemy_index]
	var phase: Vector2 = MOTION_PHASES[enemy_index]
	var center := Vector2(
		_viewport_size.x * center_ratio.x,
		top_margin + play_height * center_ratio.y
	)
	var amplitude := Vector2(
		_viewport_size.x * amplitude_ratio.x,
		play_height * amplitude_ratio.y
	)
	return center + Vector2(
		sin(time_seconds * frequency.x + phase.x) * amplitude.x,
		sin(time_seconds * frequency.y + phase.y) * amplitude.y
	)


func _circle_points(radius: float, segment_count: int, close_loop: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var point_count := segment_count + 1 if close_loop else segment_count
	for point_index in range(point_count):
		var angle := TAU * float(point_index % segment_count) / float(segment_count)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _update_status_label() -> void:
	if _status_label == null:
		return
	if _motion_paused:
		_status_label.text = "SCREEN-LOCKED · PAUSED"
	else:
		_status_label.text = "SCREEN-LOCKED · MOVING"


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_BACK, [KEY_ESCAPE])
	_register_key_action(ACTION_TOGGLE_PAUSE, [KEY_SPACE])
	_register_key_action(ACTION_RESET, [KEY_R])


func _register_key_action(action_name: String, keycodes: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for keycode in keycodes:
		var already_bound := false
		for input_event in InputMap.action_get_events(action_name):
			var key_event := input_event as InputEventKey
			if key_event != null and key_event.keycode == keycode:
				already_bound = true
				break
		if already_bound:
			continue
		var event := InputEventKey.new()
		event.keycode = keycode
		InputMap.action_add_event(action_name, event)
