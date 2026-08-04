extends "res://scripts/slime_cross_perspective_test.gd"

const APPLE_BASE_POSITION := Vector2(490.0, 382.0)
const PERSPECTIVE_APPLE_SCRIPT := preload("res://scripts/slime_apple_perspective.gd")


func debug_apple_size() -> Vector2:
	return _perspective_cross.call("apple_size") if _perspective_cross != null else Vector2.ZERO


func debug_apple_body_size() -> Vector2:
	return (
		_perspective_cross.call("apple_body_size")
		if _perspective_cross != null
		else Vector2.ZERO
	)


func debug_stem_height() -> float:
	return float(_perspective_cross.call("stem_height")) if _perspective_cross != null else 0.0


func debug_leaf_reach() -> float:
	return float(_perspective_cross.call("leaf_reach")) if _perspective_cross != null else 0.0


func debug_top_notch_depth() -> float:
	return (
		float(_perspective_cross.call("top_notch_depth"))
		if _perspective_cross != null
		else 0.0
	)


func debug_bottom_rounding_depth() -> float:
	return (
		float(_perspective_cross.call("bottom_rounding_depth"))
		if _perspective_cross != null
		else 0.0
	)


func debug_internal_feature_line_count() -> int:
	return (
		int(_perspective_cross.call("internal_feature_line_count"))
		if _perspective_cross != null
		else -1
	)


func debug_draws_debug_rig() -> bool:
	return (
		bool(_perspective_cross.call("draws_debug_rig"))
		if _perspective_cross != null
		else true
	)


func _build_stage() -> void:
	_perspective_cross = PERSPECTIVE_APPLE_SCRIPT.new() as Node2D
	_perspective_cross.name = "PerspectiveSlimeApple"
	_perspective_cross.position = APPLE_BASE_POSITION
	add_child(_perspective_cross)

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
	title.text = "史莱姆苹果透视窗 / SLIME APPLE PERSPECTIVE"
	title.position = Vector2(30.0, 16.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.76, 0.94, 0.80, 1.0))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "单一闭合软体轮廓 · 无内部装饰线 · SCREEN_UV 深空间内容"
	subtitle.position = Vector2(32.0, 60.0)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.60, 0.76, 0.68, 1.0))
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
	heading.text = "只用外轮廓读苹果"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.64, 0.92, 0.70, 1.0))
	rows.add_child(heading)

	var description := Label.new()
	description.text = (
		"沿用十字实验的实现方式\n"
		+ "• 单一 20 点闭合软体轮廓\n"
		+ "• 同一弹簧 / 邻点保形 / 面积压力\n"
		+ "• 同一 SCREEN_UV 固定空间 Shader\n\n"
		+ "苹果只靠轮廓辨认\n"
		+ "• 圆润果腹与顶部凹肩\n"
		+ "• 短果柄和一片外伸叶子\n\n"
		+ "没有叶脉、分割线、装饰线或内部标记。"
	)
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color(0.72, 0.82, 0.76, 1.0))
	rows.add_child(description)

	var separator := HSeparator.new()
	rows.add_child(separator)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.90, 0.78, 1.0))
	rows.add_child(_status_label)


func _add_controls(overlay: CanvasLayer) -> void:
	var instruction := Label.new()
	instruction.text = "左键冲击苹果边缘 · 整颗苹果沿轨迹移动以展示固定空间采样"
	instruction.position = Vector2(206.0, 655.0)
	instruction.size = Vector2(572.0, 28.0)
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 14)
	instruction.add_theme_color_override("font_color", Color(0.64, 0.78, 0.69, 1.0))
	overlay.add_child(instruction)

	var controls := HBoxContainer.new()
	controls.position = Vector2(190.0, 698.0)
	controls.size = Vector2(600.0, 48.0)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 8)
	overlay.add_child(controls)

	_add_button(controls, "PokeButton", "戳苹果", 104.0, _poke_arm)
	_add_button(controls, "SquashButton", "压扁 [F]", 104.0, debug_squash)
	_add_button(controls, "PauseButton", "暂停 [Space]", 126.0, _toggle_motion_pause)
	_add_button(controls, "ResetButton", "复原 [R]", 96.0, debug_reset)
	_auto_button = _add_button(controls, "AutoButton", "自动脉冲：开", 126.0, _toggle_auto_pulse)


func _cross_position(time_seconds: float) -> Vector2:
	return APPLE_BASE_POSITION + Vector2(
		sin(time_seconds * 0.69) * 56.0,
		sin(time_seconds * 0.45 + 0.5) * 16.0
	)


func _poke_from_screen(screen_position: Vector2) -> void:
	if _perspective_cross == null:
		return
	var local_hit: Vector2 = _perspective_cross.to_local(screen_position)
	if absf(local_hit.x) > 178.0 or absf(local_hit.y) > 190.0:
		return
	debug_poke(local_hit, 1.0)


func _poke_arm() -> void:
	debug_poke(Vector2(138.0, -6.0), 1.06)


func _run_auto_pulse() -> void:
	var pulse_points: Array[Vector2] = [
		Vector2(138.0, -6.0),
		Vector2(-132.0, 24.0),
		Vector2(0.0, 158.0),
		Vector2(70.0, -148.0),
	]
	debug_poke(pulse_points[_auto_pulse_index % pulse_points.size()], 0.72)
	_auto_pulse_index += 1


func _update_buttons() -> void:
	if _auto_button != null:
		_auto_button.text = "自动脉冲：开" if _auto_pulse_enabled else "自动脉冲：关"


func _update_status() -> void:
	if _status_label == null or _perspective_cross == null:
		return
	var apple_size: Vector2 = debug_apple_size()
	_status_label.text = (
		"状态  %s\n"
		+ "轮廓控制点  %d\n"
		+ "果柄高度 / 叶片外伸  %.1f / %.1f px\n"
		+ "内部结构线  %d\n"
		+ "Shader 填充点  %d\n"
		+ "轮廓宽高  %.0f × %.0f px"
	) % [
		"固定预览" if _motion_paused else "移动中",
		debug_control_point_count(),
		debug_stem_height(),
		debug_leaf_reach(),
		debug_internal_feature_line_count(),
		debug_fill_point_count(),
		apple_size.x,
		apple_size.y,
	]
