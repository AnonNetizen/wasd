extends Node2D

const AUTO_PULSE_INTERVAL: float = 2.25
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const SLIME_CROSS_SCRIPT := preload("res://scripts/slime_cross_2d.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)

var _auto_pulse_enabled: bool = true
var _auto_pulse_index: int = 0
var _auto_pulse_timer: float = 0.75
var _time: float = 0.0
var _slime_cross: Node2D
var _metrics_label: Label
var _auto_button: Button


func _ready() -> void:
	_build_stage()
	_update_auto_button()
	_update_metrics()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _auto_pulse_enabled and _slime_cross != null:
		_auto_pulse_timer -= delta
		if _auto_pulse_timer <= 0.0:
			_run_auto_pulse()
			_auto_pulse_timer = AUTO_PULSE_INTERVAL
	_update_metrics()
	queue_redraw()


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
			debug_squash()
		KEY_R:
			debug_reset()
		KEY_A:
			_toggle_auto_pulse()
		KEY_ESCAPE:
			_return_to_index()
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.012, 0.020, 0.034, 1.0))
	for x in range(0, int(VIEWPORT_SIZE.x) + 1, 48):
		var alpha: float = 0.055 if x % 192 != 0 else 0.10
		draw_line(
			Vector2(float(x), 104.0),
			Vector2(float(x), VIEWPORT_SIZE.y),
			Color(0.20, 0.78, 0.66, alpha),
			1.0
		)
	for y in range(104, int(VIEWPORT_SIZE.y) + 1, 48):
		var alpha: float = 0.055 if y % 192 != 0 else 0.10
		draw_line(
			Vector2(0.0, float(y)),
			Vector2(VIEWPORT_SIZE.x, float(y)),
			Color(0.20, 0.78, 0.66, alpha),
			1.0
		)

	var pulse: float = 0.5 + sin(_time * 1.4) * 0.5
	draw_circle(Vector2(500.0, 405.0), 246.0, Color(0.03, 0.16, 0.17, 0.20))
	draw_arc(
		Vector2(500.0, 405.0),
		256.0 + pulse * 5.0,
		0.0,
		TAU,
		96,
		Color(0.20, 0.92, 0.70, 0.16),
		2.0,
		true
	)
	draw_arc(
		Vector2(500.0, 405.0),
		276.0,
		-2.65,
		-0.46,
		72,
		Color(0.45, 1.0, 0.83, 0.20),
		3.0,
		true
	)
	draw_rect(Rect2(286.0, 640.0, 430.0, 18.0), Color(0.025, 0.075, 0.085, 0.92))
	draw_rect(Rect2(318.0, 632.0, 366.0, 8.0), Color(0.18, 0.70, 0.58, 0.34))

	_draw_reference_cross(Vector2(760.0, 574.0), 0.22)


func debug_poke(local_hit: Vector2 = Vector2(-118.0, -103.0), strength: float = 1.0) -> void:
	if _slime_cross == null:
		return
	_slime_cross.call("apply_poke", local_hit, strength)


func debug_squash(strength: float = 1.0) -> void:
	if _slime_cross == null:
		return
	_slime_cross.call("apply_squash", strength)


func debug_reset() -> void:
	if _slime_cross != null:
		_slime_cross.call("reset_immediately")
	_auto_pulse_timer = 0.75


func debug_set_auto_pulse(enabled: bool) -> void:
	_auto_pulse_enabled = enabled
	_update_auto_button()


func debug_control_point_count() -> int:
	return int(_slime_cross.call("control_point_count")) if _slime_cross != null else 0


func debug_concave_corner_count() -> int:
	return int(_slime_cross.call("concave_corner_count")) if _slime_cross != null else 0


func debug_area_ratio() -> float:
	return float(_slime_cross.call("current_area_ratio")) if _slime_cross != null else 0.0


func debug_deformation_amount() -> float:
	return float(_slime_cross.call("deformation_amount")) if _slime_cross != null else 0.0


func debug_silhouette_size() -> Vector2:
	return _slime_cross.call("silhouette_size") if _slime_cross != null else Vector2.ZERO


func debug_arm_span() -> float:
	return float(_slime_cross.call("arm_span")) if _slime_cross != null else 0.0


func debug_stem_width() -> float:
	return float(_slime_cross.call("stem_width")) if _slime_cross != null else 0.0


func debug_notch_clearance() -> float:
	return float(_slime_cross.call("notch_clearance")) if _slime_cross != null else 0.0


func _build_stage() -> void:
	_slime_cross = SLIME_CROSS_SCRIPT.new() as Node2D
	_slime_cross.name = "SlimeCross"
	_slime_cross.position = Vector2(500.0, 405.0)
	add_child(_slime_cross)

	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	add_child(overlay)
	_add_header(overlay)
	_add_info_panel(overlay)
	_add_controls(overlay)


func _add_header(overlay: CanvasLayer) -> void:
	var header := ColorRect.new()
	header.name = "Header"
	header.color = Color(0.008, 0.016, 0.028, 0.94)
	header.position = Vector2.ZERO
	header.size = Vector2(VIEWPORT_SIZE.x, 104.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.text = "2D 软体十字架 / JELLY CROSS"
	title.position = Vector2(30.0, 18.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.70, 1.0, 0.86, 1.0))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "用史莱姆的轮廓弹簧、邻点保形与面积压力，挑战四个内凹拐角"
	subtitle.position = Vector2(32.0, 61.0)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.61, 0.73, 0.76, 1.0))
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
	panel.position = Vector2(824.0, 142.0)
	panel.size = Vector2(400.0, 448.0)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)

	var heading := Label.new()
	heading.text = "凹形轮廓验证"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.52, 1.0, 0.80, 1.0))
	rows.add_child(heading)

	var description := Label.new()
	description.text = (
		"不是把圆形贴成十字，而是让 20 个轮廓点\n"
		+ "直接构成横臂、竖干与四个内凹角。\n\n"
		+ "观察重点\n"
		+ "• 横臂受击后是否仍与竖干分离\n"
		+ "• 内凹角回弹时是否粘连或翻折\n"
		+ "• 湿润边缘与深色内馅是否保留形状"
	)
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color(0.72, 0.80, 0.82, 1.0))
	rows.add_child(description)

	var separator := HSeparator.new()
	rows.add_child(separator)

	_metrics_label = Label.new()
	_metrics_label.name = "Metrics"
	_metrics_label.text = "初始化中…"
	_metrics_label.add_theme_font_size_override("font_size", 15)
	_metrics_label.add_theme_color_override("font_color", Color(0.67, 0.94, 0.82, 1.0))
	rows.add_child(_metrics_label)


func _add_controls(overlay: CanvasLayer) -> void:
	var instruction := Label.new()
	instruction.name = "Instruction"
	instruction.text = "左键点击十字架任意边缘施加局部冲击"
	instruction.position = Vector2(286.0, 665.0)
	instruction.size = Vector2(430.0, 26.0)
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 14)
	instruction.add_theme_color_override("font_color", Color(0.68, 0.80, 0.82, 1.0))
	overlay.add_child(instruction)

	var controls := HBoxContainer.new()
	controls.name = "Controls"
	controls.position = Vector2(264.0, 701.0)
	controls.size = Vector2(480.0, 48.0)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 9)
	overlay.add_child(controls)

	_add_button(controls, "PokeButton", "戳横臂", 105.0, _poke_arm)
	_add_button(controls, "SquashButton", "压扁 [Space]", 125.0, debug_squash)
	_add_button(controls, "ResetButton", "复原 [R]", 98.0, debug_reset)
	_auto_button = _add_button(
		controls,
		"AutoButton",
		"自动脉冲：开",
		128.0,
		_toggle_auto_pulse
	)


func _add_button(
	parent: Control,
	button_name: String,
	text: String,
	width: float,
	callback: Callable
) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.custom_minimum_size = Vector2(width, 48.0)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _draw_reference_cross(center: Vector2, scale_factor: float) -> void:
	var points := PackedVector2Array()
	for point in SLIME_CROSS_SCRIPT.REST_OUTLINE:
		points.append(center + point * scale_factor)
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_colored_polygon(points, Color(0.10, 0.22, 0.24, 0.28))
	draw_polyline(closed, Color(0.36, 0.78, 0.68, 0.30), 3.0, true)


func _is_pointer_over_button() -> bool:
	return get_viewport().gui_get_hovered_control() is Button


func _poke_from_screen(screen_position: Vector2) -> void:
	if _slime_cross == null:
		return
	var local_hit: Vector2 = _slime_cross.to_local(screen_position)
	if absf(local_hit.x) > 170.0 or absf(local_hit.y) > 265.0:
		return
	debug_poke(local_hit, 1.0)


func _poke_arm() -> void:
	debug_poke(Vector2(-120.0, -102.0), 1.1)


func _run_auto_pulse() -> void:
	var pulse_points: Array[Vector2] = [
		Vector2(-120.0, -105.0),
		Vector2(120.0, -91.0),
		Vector2(29.0, -208.0),
		Vector2(-38.0, 116.0),
	]
	debug_poke(pulse_points[_auto_pulse_index % pulse_points.size()], 0.82)
	_auto_pulse_index += 1


func _toggle_auto_pulse() -> void:
	_auto_pulse_enabled = not _auto_pulse_enabled
	_auto_pulse_timer = 0.55
	_update_auto_button()


func _update_auto_button() -> void:
	if _auto_button == null:
		return
	_auto_button.text = "自动脉冲：开" if _auto_pulse_enabled else "自动脉冲：关"


func _update_metrics() -> void:
	if _metrics_label == null or _slime_cross == null:
		return
	var size: Vector2 = debug_silhouette_size()
	_metrics_label.text = (
		"轮廓控制点  %d\n"
		+ "内凹拐角  %d\n"
		+ "横臂 / 竖干  %.2f×\n"
		+ "凹角净距  %.1f px\n"
		+ "形变  %.2f px\n"
		+ "面积保持  %.1f%%\n"
		+ "轮廓宽高  %.0f × %.0f px"
	) % [
		debug_control_point_count(),
		debug_concave_corner_count(),
		debug_arm_span() / maxf(debug_stem_width(), 0.001),
		debug_notch_clearance(),
		debug_deformation_amount(),
		debug_area_ratio() * 100.0,
		size.x,
		size.y,
	]


func _return_to_index() -> void:
	var error: Error = get_tree().change_scene_to_file(INDEX_SCENE_PATH)
	if error != OK:
		push_error("Failed to return to Test Lab index: %s" % error)
