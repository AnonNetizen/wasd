extends Node2D

const BASE_POSITION := Vector2(488.0, 384.0)
const DISPLAY_SCALE: float = 1.55
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const PEAR_SHAPE_SCRIPT := preload("res://scripts/svg_curve_compound_shape.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)

var _curve_shape: TestLabSvgCurveCompoundShape
var _curve_button: Button
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
		KEY_D:
			debug_set_curve_overlay(not debug_curve_overlay_visible())
		KEY_R:
			debug_reset()
		KEY_ESCAPE:
			_return_to_index()
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.005, 0.008, 0.022, 1.0))


func debug_set_preview_time(time_seconds: float) -> void:
	_time = maxf(time_seconds, 0.0)
	_motion_paused = true
	_update_presentation()


func debug_set_motion_paused(paused: bool) -> void:
	_motion_paused = paused
	_update_status()


func debug_set_curve_overlay(visible: bool) -> void:
	if _curve_shape != null:
		_curve_shape.set_curve_overlay_visible(visible)
	_update_buttons()


func debug_curve_overlay_visible() -> bool:
	return _curve_shape != null and _curve_shape.curve_overlay_visible()


func debug_reset() -> void:
	_time = 0.0
	_motion_paused = false
	debug_set_curve_overlay(false)
	_update_presentation()


func debug_subpath_count() -> int:
	return _curve_shape.subpath_count() if _curve_shape != null else 0


func debug_path_node_count() -> int:
	return _curve_shape.path_node_count() if _curve_shape != null else 0


func debug_curve_segment_count() -> int:
	return _curve_shape.curve_segment_count() if _curve_shape != null else 0


func debug_curve_point_count() -> int:
	return _curve_shape.curve_point_count() if _curve_shape != null else 0


func debug_tessellated_point_count() -> int:
	return _curve_shape.tessellated_point_count() if _curve_shape != null else 0


func debug_hole_count() -> int:
	return _curve_shape.hole_count() if _curve_shape != null else 0


func debug_triangle_count() -> int:
	return _curve_shape.triangle_count() if _curve_shape != null else 0


func debug_edge_triangle_count() -> int:
	return _curve_shape.edge_triangle_count() if _curve_shape != null else 0


func debug_fill_area_ratio() -> float:
	return _curve_shape.fill_area_ratio() if _curve_shape != null else 0.0


func debug_edge_area_ratio() -> float:
	return _curve_shape.edge_area_ratio() if _curve_shape != null else 0.0


func debug_edge_uses_shader() -> bool:
	return _curve_shape != null and _curve_shape.edge_uses_shader()


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


func debug_perspective_material() -> ShaderMaterial:
	return _curve_shape.perspective_material() if _curve_shape != null else null


func debug_fill_screen_samples() -> PackedVector2Array:
	var screen_samples := PackedVector2Array()
	if _curve_shape == null:
		return screen_samples
	for local_point in _curve_shape.fill_sample_points():
		screen_samples.append(_curve_shape.to_global(local_point))
	return screen_samples


func debug_fill_screen_sample_groups() -> Array[PackedVector2Array]:
	var screen_groups: Array[PackedVector2Array] = []
	if _curve_shape == null:
		return screen_groups
	for local_group in _curve_shape.fill_sample_groups():
		var screen_group := PackedVector2Array()
		for local_point in local_group:
			screen_group.append(_curve_shape.to_global(local_point))
		screen_groups.append(screen_group)
	return screen_groups


func _build_stage() -> void:
	_curve_shape = PEAR_SHAPE_SCRIPT.new() as TestLabSvgCurveCompoundShape
	_curve_shape.name = "SvgCurvePear"
	_curve_shape.position = BASE_POSITION
	_curve_shape.scale = Vector2.ONE * DISPLAY_SCALE
	add_child(_curve_shape)

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
	title.text = "SVG 曲线梨透视窗 / SVG CURVE PEAR"
	title.position = Vector2(30.0, 16.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.80, 0.94, 0.72, 1.0))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "SVG 黑色路径作边框 · 梨身与叶片内部填透视 Shader · 无软体物理"
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
	heading.text = "曲线是形状权威"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.70, 0.92, 0.66, 1.0))
	rows.add_child(heading)

	var description := Label.new()
	description.text = (
		"直接读取 pear_source.svg\n"
		+ "• 解析 M / m / L / l / H / V / C / c / Z\n"
		+ "• 保留 translate + scale 坐标变换\n"
		+ "• 三个闭合 Curve2D 子路径\n"
		+ "• 原黑色复合区域生成无 Shader 的实心边框\n"
		+ "• 梨身、叶片两个被围区域填充透视 Shader\n\n"
		+ "Curve2D 细分只生成渲染网格；没有弹簧、\n"
		+ "面积压力、软体质点或轮廓形变。"
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
	instruction.text = "整条 SVG 曲线只做平移 · D 可查看三条原始曲线边界"
	instruction.position = Vector2(210.0, 655.0)
	instruction.size = Vector2(550.0, 28.0)
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 14)
	instruction.add_theme_color_override("font_color", Color(0.64, 0.78, 0.68, 1.0))
	overlay.add_child(instruction)

	var controls := HBoxContainer.new()
	controls.position = Vector2(276.0, 698.0)
	controls.size = Vector2(420.0, 48.0)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 10)
	overlay.add_child(controls)

	_add_button(controls, "PauseButton", "暂停 [Space]", 130.0, _toggle_motion_pause)
	_curve_button = _add_button(controls, "CurveButton", "曲线：关 [D]", 126.0, _toggle_curve_overlay)
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
	_curve_shape.position = BASE_POSITION + Vector2(
		sin(_time * 0.62) * 48.0,
		sin(_time * 0.41 + 0.6) * 14.0
	)
	_curve_shape.set_animation_time(_time)
	_update_status()


func _update_status() -> void:
	if _status_label == null or _curve_shape == null:
		return
	_status_label.text = (
		"状态  %s\n"
		+ "Curve2D 子路径 / 内部区域  %d / %d\n"
		+ "贝塞尔段 / 曲线锚点  %d / %d\n"
		+ "细分点 / 边框 / 内部三角形  %d / %d / %d\n"
		+ "边框 / 内部面积匹配  %.2f%% / %.2f%%"
	) % [
		"固定预览" if _motion_paused else "移动中",
		debug_subpath_count(),
		debug_hole_count(),
		debug_curve_segment_count(),
		debug_curve_point_count(),
		debug_tessellated_point_count(),
		debug_edge_triangle_count(),
		debug_triangle_count(),
		debug_edge_area_ratio() * 100.0,
		debug_fill_area_ratio() * 100.0,
	]


func _update_buttons() -> void:
	if _curve_button != null:
		_curve_button.text = "曲线：开 [D]" if debug_curve_overlay_visible() else "曲线：关 [D]"


func _toggle_motion_pause() -> void:
	debug_set_motion_paused(not _motion_paused)


func _toggle_curve_overlay() -> void:
	debug_set_curve_overlay(not debug_curve_overlay_visible())


func _on_viewport_size_changed() -> void:
	if _curve_shape == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_curve_shape.set_viewport_aspect(viewport_size.x / maxf(viewport_size.y, 1.0))


func _return_to_index() -> void:
	var error: Error = get_tree().change_scene_to_file(INDEX_SCENE_PATH)
	if error != OK:
		push_error("Failed to return to Test Lab index: %s" % error)
