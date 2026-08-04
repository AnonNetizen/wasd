extends "res://scripts/slime_cross_perspective_test.gd"

const BOOK_BASE_POSITION := Vector2(474.0, 382.0)
const PERSPECTIVE_BOOK_SCRIPT := preload("res://scripts/slime_book_perspective.gd")


func debug_book_size() -> Vector2:
	return _perspective_cross.call("book_size") if _perspective_cross != null else Vector2.ZERO


func debug_top_spine_notch_depth() -> float:
	return (
		float(_perspective_cross.call("top_spine_notch_depth"))
		if _perspective_cross != null
		else 0.0
	)


func debug_bottom_spine_projection() -> float:
	return (
		float(_perspective_cross.call("bottom_spine_projection"))
		if _perspective_cross != null
		else 0.0
	)


func debug_page_symmetry_error() -> float:
	return (
		float(_perspective_cross.call("page_symmetry_error"))
		if _perspective_cross != null
		else INF
	)


func debug_spine_point_count() -> int:
	return int(_perspective_cross.call("spine_point_count")) if _perspective_cross != null else 0


func debug_page_guide_count() -> int:
	return int(_perspective_cross.call("page_guide_count")) if _perspective_cross != null else 0


func _build_stage() -> void:
	_perspective_cross = PERSPECTIVE_BOOK_SCRIPT.new() as Node2D
	_perspective_cross.name = "PerspectiveSlimeBook"
	_perspective_cross.position = BOOK_BASE_POSITION
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
	header.color = Color(0.006, 0.010, 0.030, 0.95)
	header.position = Vector2.ZERO
	header.size = Vector2(VIEWPORT_SIZE.x, 104.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.text = "史莱姆书本透视窗 / SLIME BOOK PERSPECTIVE"
	title.position = Vector2(30.0, 16.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.80, 0.91, 1.0, 1.0))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "单一闭合软体轮廓 · 固定书脊与页边特征 · SCREEN_UV 深空间内容"
	subtitle.position = Vector2(32.0, 60.0)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.60, 0.72, 0.88, 1.0))
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
	heading.text = "不翻页的书本读形"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.67, 0.84, 1.0, 1.0))
	rows.add_child(heading)

	var description := Label.new()
	description.text = (
		"沿用十字实验的实现方式\n"
		+ "• 单一 20 点闭合软体轮廓\n"
		+ "• 同一弹簧 / 邻点保形 / 面积压力\n"
		+ "• 同一 SCREEN_UV 固定空间 Shader\n\n"
		+ "书本识别特征\n"
		+ "• 顶部中央凹口 + 底部书脊尖\n"
		+ "• 左右宽页保持镜像\n"
		+ "• 中央硬书脊与两条页边线跟随形变\n\n"
		+ "没有翻页、分层页面或 3D 网格。"
	)
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90, 1.0))
	rows.add_child(description)

	var separator := HSeparator.new()
	rows.add_child(separator)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0, 1.0))
	rows.add_child(_status_label)


func _add_controls(overlay: CanvasLayer) -> void:
	var instruction := Label.new()
	instruction.text = "左键冲击书页边缘 · 整本书沿轨迹移动以展示固定空间采样"
	instruction.position = Vector2(220.0, 655.0)
	instruction.size = Vector2(552.0, 28.0)
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 14)
	instruction.add_theme_color_override("font_color", Color(0.65, 0.76, 0.88, 1.0))
	overlay.add_child(instruction)

	var controls := HBoxContainer.new()
	controls.position = Vector2(138.0, 698.0)
	controls.size = Vector2(704.0, 48.0)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 8)
	overlay.add_child(controls)

	_add_button(controls, "PokeButton", "戳左页", 102.0, _poke_arm)
	_add_button(controls, "SquashButton", "压扁 [F]", 104.0, debug_squash)
	_add_button(controls, "PauseButton", "暂停 [Space]", 126.0, _toggle_motion_pause)
	_add_button(controls, "ResetButton", "复原 [R]", 96.0, debug_reset)
	_debug_button = _add_button(controls, "DebugButton", "骨架：关 [D]", 112.0, _toggle_debug_rig)
	_auto_button = _add_button(controls, "AutoButton", "自动脉冲：开", 126.0, _toggle_auto_pulse)


func _cross_position(time_seconds: float) -> Vector2:
	return BOOK_BASE_POSITION + Vector2(
		sin(time_seconds * 0.66) * 52.0,
		sin(time_seconds * 0.43 + 0.7) * 14.0
	)


func _poke_from_screen(screen_position: Vector2) -> void:
	if _perspective_cross == null:
		return
	var local_hit: Vector2 = _perspective_cross.to_local(screen_position)
	if absf(local_hit.x) > 220.0 or absf(local_hit.y) > 180.0:
		return
	debug_poke(local_hit, 1.0)


func _poke_arm() -> void:
	debug_poke(Vector2(-184.0, -34.0), 1.08)


func _run_auto_pulse() -> void:
	var pulse_points: Array[Vector2] = [
		Vector2(-184.0, -34.0),
		Vector2(184.0, 18.0),
		Vector2(-92.0, -145.0),
		Vector2(112.0, 110.0),
	]
	debug_poke(pulse_points[_auto_pulse_index % pulse_points.size()], 0.78)
	_auto_pulse_index += 1


func _update_status() -> void:
	if _status_label == null or _perspective_cross == null:
		return
	var size: Vector2 = debug_book_size()
	_status_label.text = (
		"状态  %s\n"
		+ "轮廓点 / 书脊点  %d / %d\n"
		+ "顶部凹口  %.1f px\n"
		+ "底部书脊尖  %.1f px\n"
		+ "左右对称误差  %.2f px\n"
		+ "Shader 填充点  %d\n"
		+ "轮廓宽高  %.0f × %.0f px"
	) % [
		"固定预览" if _motion_paused else "移动中",
		debug_control_point_count(),
		debug_spine_point_count(),
		debug_top_spine_notch_depth(),
		debug_bottom_spine_projection(),
		debug_page_symmetry_error(),
		debug_fill_point_count(),
		size.x,
		size.y,
	]
