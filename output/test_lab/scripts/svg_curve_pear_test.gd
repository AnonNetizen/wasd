extends Node2D

const BASE_POSITION := Vector2(492.0, 374.0)
const DISPLAY_SCALE: float = 1.25
const DEFAULT_BORDER_WIDTH: float = 12.0
const MIN_BORDER_WIDTH: float = 2.0
const MAX_BORDER_WIDTH: float = 30.0
const BORDER_WIDTH_STEP: float = 2.0
const BORDER_PULSE_WIDTH: float = 0.9
const BORDER_BASE_COLOR := Color(0.48, 0.82, 0.58, 1.0)
const BORDER_HIGHLIGHT_COLOR := Color(0.72, 1.0, 0.72, 1.0)
const BREATH_SPEED: float = 1.05
const HORIZONTAL_SWAY: float = 34.0
const VERTICAL_FLOAT: float = 12.0
const MAX_TILT_DEGREES: float = 2.3
const GROUND_SHADOW_Y: float = 645.0
const AMBIENT_MOTE_COUNT: int = 3
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const PEAR_SHAPE_SCRIPT := preload("res://scripts/svg_curve_outline_shape.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)

var _base_border_width: float = DEFAULT_BORDER_WIDTH
var _curve_shape: TestLabSvgCurveOutlineShape
var _controls_button: Button
var _motion_paused: bool = false
var _status_label: Label
var _time: float = 0.0


func _ready() -> void:
	_build_stage()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_update_presentation()
	_update_buttons()
	queue_redraw()


func _process(delta: float) -> void:
	if not _motion_paused:
		_time += delta
	_update_presentation()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_SPACE:
			debug_set_motion_paused(not _motion_paused)
		KEY_Q:
			_adjust_border_width(-BORDER_WIDTH_STEP)
		KEY_E:
			_adjust_border_width(BORDER_WIDTH_STEP)
		KEY_D:
			debug_set_controls_visible(not debug_controls_visible())
		KEY_R:
			debug_reset()
		KEY_ESCAPE:
			_return_to_index()
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.005, 0.008, 0.022, 1.0))
	if _curve_shape == null:
		return

	var hover_height := clampf(
		(GROUND_SHADOW_Y - _curve_shape.position.y) / 300.0,
		0.72,
		1.08
	)
	var shadow_center := Vector2(_curve_shape.position.x, GROUND_SHADOW_Y)
	var shadow_width: float = 112.0 / hover_height
	var shadow_height: float = 9.0 / hover_height
	for layer_index in range(3):
		var layer_ratio: float = 1.0 - float(layer_index) * 0.19
		draw_set_transform(
			shadow_center,
			0.0,
			Vector2(shadow_width * layer_ratio, shadow_height * layer_ratio)
		)
		draw_circle(
			Vector2.ZERO,
			1.0,
			Color(0.24, 0.68, 0.39, 0.035 + float(layer_index) * 0.018)
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for mote_index in range(AMBIENT_MOTE_COUNT):
		var mote_position: Vector2 = _ambient_mote_position(mote_index)
		var mote_pulse: float = 0.5 + 0.5 * sin(_time * 1.7 + float(mote_index) * 2.1)
		draw_circle(
			mote_position,
			2.2 + mote_pulse * 1.4,
			Color(0.54, 1.0, 0.64, 0.16 + mote_pulse * 0.20)
		)


func debug_set_preview_time(time_seconds: float) -> void:
	_time = maxf(time_seconds, 0.0)
	_motion_paused = true
	_update_presentation()


func debug_set_motion_paused(paused: bool) -> void:
	_motion_paused = paused
	_update_status()


func debug_set_border_width(width: float) -> void:
	_base_border_width = clampf(width, MIN_BORDER_WIDTH, MAX_BORDER_WIDTH)
	_update_presentation()


func debug_border_width() -> float:
	return _base_border_width


func debug_render_border_width() -> float:
	return _curve_shape.border_width() * DISPLAY_SCALE if _curve_shape != null else 0.0


func debug_set_controls_visible(controls_visible: bool) -> void:
	if _curve_shape != null:
		_curve_shape.set_controls_visible(controls_visible)
	_update_status()
	_update_buttons()


func debug_controls_visible() -> bool:
	return _curve_shape != null and _curve_shape.controls_visible()


func debug_controls_overlay_count() -> int:
	return _curve_shape.controls_overlay_count() if _curve_shape != null else 0


func debug_control_anchor_count() -> int:
	return _curve_shape.control_anchor_count() if _curve_shape != null else 0


func debug_control_handle_count() -> int:
	return _curve_shape.control_handle_count() if _curve_shape != null else 0


func debug_reset() -> void:
	_time = 0.0
	_motion_paused = false
	debug_set_border_width(DEFAULT_BORDER_WIDTH)
	debug_set_controls_visible(true)
	_update_presentation()


func debug_subpath_count() -> int:
	return _curve_shape.subpath_count() if _curve_shape != null else 0


func debug_path_node_count() -> int:
	return _curve_shape.path_node_count() if _curve_shape != null else 0


func debug_border_line_count() -> int:
	return _curve_shape.border_line_count() if _curve_shape != null else 0


func debug_border_uses_shader() -> bool:
	return _curve_shape != null and _curve_shape.border_uses_shader()


func debug_curve_segment_count() -> int:
	return _curve_shape.curve_segment_count() if _curve_shape != null else 0


func debug_curve_point_count() -> int:
	return _curve_shape.curve_point_count() if _curve_shape != null else 0


func debug_tessellated_point_count() -> int:
	return _curve_shape.tessellated_point_count() if _curve_shape != null else 0


func debug_triangle_count() -> int:
	return _curve_shape.triangle_count() if _curve_shape != null else 0


func debug_fill_area_ratio() -> float:
	return _curve_shape.fill_area_ratio() if _curve_shape != null else 0.0


func debug_all_curves_closed() -> bool:
	return _curve_shape != null and _curve_shape.all_curves_closed()


func debug_curve_display_size() -> Vector2:
	return (
		_curve_shape.source_bounds().size * DISPLAY_SCALE
		if _curve_shape != null
		else Vector2.ZERO
	)


func debug_curve_shape_position() -> Vector2:
	return _curve_shape.position if _curve_shape != null else Vector2.ZERO


func debug_curve_shape_rotation() -> float:
	return _curve_shape.rotation if _curve_shape != null else 0.0


func debug_curve_shape_scale() -> Vector2:
	return _curve_shape.scale if _curve_shape != null else Vector2.ZERO


func debug_ambient_mote_count() -> int:
	return AMBIENT_MOTE_COUNT


func debug_perspective_material() -> ShaderMaterial:
	return _curve_shape.perspective_material() if _curve_shape != null else null


func debug_border_color() -> Color:
	return _curve_shape.border_color() if _curve_shape != null else Color.TRANSPARENT


func debug_fill_screen_samples() -> PackedVector2Array:
	var screen_samples := PackedVector2Array()
	if _curve_shape == null:
		return screen_samples
	for local_point in _curve_shape.fill_sample_points():
		screen_samples.append(_curve_shape.to_global(local_point))
	return screen_samples


func debug_border_screen_samples() -> PackedVector2Array:
	var screen_samples := PackedVector2Array()
	if _curve_shape == null:
		return screen_samples
	for local_point in _curve_shape.border_sample_points():
		screen_samples.append(_curve_shape.to_global(local_point))
	return screen_samples


func debug_control_anchor_screen_samples() -> PackedVector2Array:
	return _to_screen_samples(_curve_shape.control_anchor_points())


func debug_control_in_handle_screen_samples() -> PackedVector2Array:
	return _to_screen_samples(_curve_shape.control_in_handle_points())


func debug_control_out_handle_screen_samples() -> PackedVector2Array:
	return _to_screen_samples(_curve_shape.control_out_handle_points())


func debug_control_anchor_color() -> Color:
	return _curve_shape.control_anchor_color() if _curve_shape != null else Color.TRANSPARENT


func debug_control_in_handle_color() -> Color:
	return _curve_shape.control_in_handle_color() if _curve_shape != null else Color.TRANSPARENT


func debug_control_out_handle_color() -> Color:
	return _curve_shape.control_out_handle_color() if _curve_shape != null else Color.TRANSPARENT


func _build_stage() -> void:
	_curve_shape = PEAR_SHAPE_SCRIPT.new() as TestLabSvgCurveOutlineShape
	_curve_shape.name = "SvgCurvePear"
	_curve_shape.position = BASE_POSITION
	_curve_shape.scale = Vector2.ONE * DISPLAY_SCALE
	add_child(_curve_shape)
	debug_set_border_width(DEFAULT_BORDER_WIDTH)

	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	add_child(overlay)
	_add_header(overlay)
	_add_info_panel(overlay)
	_add_controls(overlay)


func _add_header(overlay: CanvasLayer) -> void:
	var header := ColorRect.new()
	header.name = "Header"
	header.color = Color(0.006, 0.010, 0.028, 0.95)
	header.position = Vector2.ZERO
	header.size = Vector2(VIEWPORT_SIZE.x, 104.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.text = "SVG 单曲线梨透视窗 / SVG OUTLINE PEAR"
	title.position = Vector2(30.0, 16.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.80, 0.94, 0.72, 1.0))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "单一 SVG 闭合曲线 · 呼吸浮动与轮缘脉冲 · Bézier 控制柄可视化"
	subtitle.position = Vector2(32.0, 60.0)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.76, 0.66, 1.0))
	header.add_child(subtitle)

	var exit_button := Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "返回实验索引 [Esc]"
	exit_button.position = Vector2(1060.0, 28.0)
	exit_button.size = Vector2(190.0, 48.0)
	exit_button.pressed.connect(_return_to_index)
	header.add_child(exit_button)


func _add_info_panel(overlay: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "InfoPanel"
	panel.position = Vector2(820.0, 142.0)
	panel.size = Vector2(408.0, 478.0)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)

	var heading := Label.new()
	heading.text = "一条曲线控制轮廓与边"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.70, 0.92, 0.66, 1.0))
	rows.add_child(heading)

	var description := Label.new()
	description.text = (
		"直接读取新版 pear_source.svg\n"
		+ "• 一个闭合 Curve2D / Path2D\n"
		+ "• 黄色锚点、青色入柄、粉色出柄\n"
		+ "• 曲线内部三角化并填透视 Shader\n"
		+ "• 同一细分曲线生成一个闭合 Line2D\n"
		+ "• 浮动、微倾、呼吸与轮缘脉冲待机\n\n"
		+ "没有内外双轮廓、弹簧、面积压力、\n"
		+ "软体质点、局部曲线形变或额外轮廓。"
	)
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color(0.72, 0.82, 0.75, 1.0))
	rows.add_child(description)

	var separator := HSeparator.new()
	rows.add_child(separator)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.74, 0.90, 0.74, 1.0))
	rows.add_child(_status_label)


func _add_controls(overlay: CanvasLayer) -> void:
	var instruction := Label.new()
	instruction.text = "Space 暂停待机动画 · D 显示 / 隐藏控制柄 · Q / E 调节基础边宽"
	instruction.position = Vector2(140.0, 655.0)
	instruction.size = Vector2(700.0, 28.0)
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 14)
	instruction.add_theme_color_override("font_color", Color(0.64, 0.78, 0.68, 1.0))
	overlay.add_child(instruction)

	var controls := HBoxContainer.new()
	controls.position = Vector2(140.0, 698.0)
	controls.size = Vector2(696.0, 48.0)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 10)
	overlay.add_child(controls)

	_add_button(controls, "PauseButton", "暂停 [Space]", 130.0, _toggle_motion_pause)
	_add_button(controls, "NarrowButton", "边细 [Q]", 108.0, _narrow_border)
	_add_button(controls, "WideButton", "边粗 [E]", 108.0, _widen_border)
	_controls_button = _add_button(
		controls,
		"ControlsButton",
		"控制点：开 [D]",
		130.0,
		_toggle_controls
	)
	_add_button(controls, "ResetButton", "复原 [R]", 100.0, debug_reset)


func _add_button(
	parent: Control,
	button_name: String,
	button_text: String,
	width: float,
	callback: Callable
) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = button_text
	button.custom_minimum_size = Vector2(width, 48.0)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _update_presentation() -> void:
	if _curve_shape == null:
		return
	var breath_wave: float = sin(_time * BREATH_SPEED + 1.1)
	var border_pulse: float = 0.5 + 0.5 * sin(_time * 1.4 - 0.35)
	_curve_shape.position = BASE_POSITION + Vector2(
		sin(_time * 0.62) * HORIZONTAL_SWAY,
		sin(_time * 0.82 + 0.6) * VERTICAL_FLOAT
	)
	_curve_shape.rotation = deg_to_rad(
		MAX_TILT_DEGREES
		* (sin(_time * 0.70) * 0.78 + sin(_time * 0.31) * 0.22)
	)
	_curve_shape.scale = Vector2(
		DISPLAY_SCALE * (1.0 + breath_wave * 0.018),
		DISPLAY_SCALE * (1.0 - breath_wave * 0.024)
	)
	_curve_shape.set_border_width(
		(_base_border_width + border_pulse * BORDER_PULSE_WIDTH) / DISPLAY_SCALE
	)
	_curve_shape.set_border_color(
		BORDER_BASE_COLOR.lerp(BORDER_HIGHLIGHT_COLOR, border_pulse * 0.72)
	)
	_curve_shape.set_animation_time(_time)
	_update_status()


func _update_status() -> void:
	if _status_label == null or _curve_shape == null:
		return
	_status_label.text = (
		"状态 / 控制点  %s / %s\n"
		+ "Curve2D / Path2D / Line2D  %d / %d / %d\n"
		+ "SVG 唯一锚点 / 控制柄  %d / %d\n"
		+ "贝塞尔段 / 曲线锚点  %d / %d\n"
		+ "细分点 / 内部三角形  %d / %d\n"
		+ "基础 / 动态边宽  %.1f / %.1f px\n"
		+ "填充面积匹配 / 待机倾角  %.2f%% / %+.2f°"
	) % [
		"固定预览" if _motion_paused else "移动中",
		"显示" if debug_controls_visible() else "隐藏",
		debug_subpath_count(),
		debug_path_node_count(),
		debug_border_line_count(),
		debug_control_anchor_count(),
		debug_control_handle_count(),
		debug_curve_segment_count(),
		debug_curve_point_count(),
		debug_tessellated_point_count(),
		debug_triangle_count(),
		debug_border_width(),
		debug_render_border_width(),
		debug_fill_area_ratio() * 100.0,
		rad_to_deg(debug_curve_shape_rotation()),
	]


func _update_buttons() -> void:
	if _controls_button != null:
		_controls_button.text = (
			"控制点：开 [D]" if debug_controls_visible() else "控制点：关 [D]"
		)


func _adjust_border_width(delta: float) -> void:
	debug_set_border_width(debug_border_width() + delta)


func _toggle_motion_pause() -> void:
	debug_set_motion_paused(not _motion_paused)


func _narrow_border() -> void:
	_adjust_border_width(-BORDER_WIDTH_STEP)


func _widen_border() -> void:
	_adjust_border_width(BORDER_WIDTH_STEP)


func _toggle_controls() -> void:
	debug_set_controls_visible(not debug_controls_visible())


func _to_screen_samples(local_samples: PackedVector2Array) -> PackedVector2Array:
	var screen_samples := PackedVector2Array()
	if _curve_shape == null:
		return screen_samples
	for local_point in local_samples:
		screen_samples.append(_curve_shape.to_global(local_point))
	return screen_samples


func _ambient_mote_position(mote_index: int) -> Vector2:
	var phase: float = _time * (0.46 + float(mote_index) * 0.07) + float(mote_index) * 2.2
	var orbit := Vector2(cos(phase) * 246.0, sin(phase) * 174.0)
	return _curve_shape.position + orbit.rotated(_curve_shape.rotation * 0.35)


func _on_viewport_size_changed() -> void:
	if _curve_shape == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_curve_shape.set_viewport_aspect(viewport_size.x / maxf(viewport_size.y, 1.0))


func _return_to_index() -> void:
	var error: Error = get_tree().change_scene_to_file(INDEX_SCENE_PATH)
	if error != OK:
		push_error("Failed to return to Test Lab index: %s" % error)
