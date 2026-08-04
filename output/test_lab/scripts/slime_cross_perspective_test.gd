extends Node2D

const AUTO_PULSE_INTERVAL: float = 2.4
const BASE_POSITION := Vector2(474.0, 384.0)
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const PERSPECTIVE_CROSS_SCRIPT := preload("res://scripts/slime_cross_perspective.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)

var _auto_pulse_enabled: bool = true
var _auto_pulse_index: int = 0
var _auto_pulse_timer: float = 0.85
var _motion_paused: bool = false
var _time: float = 0.0
var _perspective_cross: Node2D
var _status_label: Label
var _debug_button: Button
var _auto_button: Button


func _ready() -> void:
	_build_stage()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_update_buttons()
	_update_status()
	queue_redraw()


func _process(delta: float) -> void:
	if not _motion_paused:
		_time += delta
		_auto_pulse_timer -= delta
		if _auto_pulse_enabled and _auto_pulse_timer <= 0.0:
			_run_auto_pulse()
			_auto_pulse_timer = AUTO_PULSE_INTERVAL
	_update_presentation()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if not get_viewport().gui_get_hovered_control() is Button:
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
			debug_set_motion_paused(not _motion_paused)
		KEY_F:
			debug_squash()
		KEY_R:
			debug_reset()
		KEY_A:
			debug_set_auto_pulse(not _auto_pulse_enabled)
		KEY_D:
			debug_set_rig_enabled(not debug_rig_enabled())
		KEY_ESCAPE:
			_return_to_index()
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.005, 0.009, 0.024, 1.0))
	for x in range(0, int(VIEWPORT_SIZE.x) + 1, 64):
		var alpha: float = 0.05 if x % 256 != 0 else 0.11
		draw_line(
			Vector2(float(x), 104.0),
			Vector2(float(x), VIEWPORT_SIZE.y),
			Color(0.24, 0.52, 0.76, alpha),
			1.0
		)
	for y in range(104, int(VIEWPORT_SIZE.y) + 1, 64):
		var alpha: float = 0.05 if y % 256 != 0 else 0.11
		draw_line(
			Vector2(0.0, float(y)),
			Vector2(VIEWPORT_SIZE.x, float(y)),
			Color(0.24, 0.52, 0.76, alpha),
			1.0
		)

	var path := PackedVector2Array()
	for sample_index in range(121):
		var sample_time: float = float(sample_index) / 120.0 * 8.0
		path.append(_cross_position(sample_time))
	draw_polyline(path, Color(0.34, 0.75, 1.0, 0.18), 1.5, true)

	for anchor_index in range(9):
		var anchor := Vector2(
			92.0 + float(anchor_index % 5) * 136.0,
			154.0 + float(anchor_index / 5) * 410.0
		)
		draw_line(anchor - Vector2(7.0, 0.0), anchor + Vector2(7.0, 0.0), Color(0.38, 0.76, 1.0, 0.24), 1.0)
		draw_line(anchor - Vector2(0.0, 7.0), anchor + Vector2(0.0, 7.0), Color(0.38, 0.76, 1.0, 0.24), 1.0)


func debug_set_preview_time(time_seconds: float) -> void:
	_time = maxf(time_seconds, 0.0)
	_motion_paused = true
	_update_presentation()
	_update_status()


func debug_set_motion_paused(paused: bool) -> void:
	_motion_paused = paused
	_update_status()


func debug_set_auto_pulse(enabled: bool) -> void:
	_auto_pulse_enabled = enabled
	_update_buttons()


func debug_set_fixed_step_mode(enabled: bool) -> void:
	if _perspective_cross != null:
		_perspective_cross.call("set_fixed_step_mode", enabled)


func debug_advance_fixed_step(delta: float = 1.0 / 60.0) -> void:
	if _perspective_cross != null:
		_perspective_cross.call("advance_fixed_step", delta)


func debug_poke(local_hit: Vector2 = Vector2(-118.0, -103.0), strength: float = 1.0) -> void:
	if _perspective_cross != null:
		_perspective_cross.call("apply_poke", local_hit, strength)


func debug_squash(strength: float = 1.0) -> void:
	if _perspective_cross != null:
		_perspective_cross.call("apply_squash", strength)


func debug_reset() -> void:
	_time = 0.0
	_motion_paused = false
	_auto_pulse_timer = 0.85
	if _perspective_cross != null:
		_perspective_cross.call("reset_immediately")
	_update_presentation()
	_update_status()


func debug_set_rig_enabled(enabled: bool) -> void:
	if _perspective_cross != null:
		_perspective_cross.call("set_debug_rig_enabled", enabled)
	_update_buttons()


func debug_rig_enabled() -> bool:
	return (
		bool(_perspective_cross.call("debug_rig_enabled"))
		if _perspective_cross != null
		else false
	)


func debug_control_point_count() -> int:
	return int(_perspective_cross.call("control_point_count")) if _perspective_cross != null else 0


func debug_concave_corner_count() -> int:
	return int(_perspective_cross.call("concave_corner_count")) if _perspective_cross != null else 0


func debug_arm_span() -> float:
	return float(_perspective_cross.call("arm_span")) if _perspective_cross != null else 0.0


func debug_stem_width() -> float:
	return float(_perspective_cross.call("stem_width")) if _perspective_cross != null else 0.0


func debug_area_ratio() -> float:
	return float(_perspective_cross.call("current_area_ratio")) if _perspective_cross != null else 0.0


func debug_deformation_amount() -> float:
	return float(_perspective_cross.call("deformation_amount")) if _perspective_cross != null else 0.0


func debug_fill_point_count() -> int:
	return (
		int(_perspective_cross.call("perspective_fill_point_count"))
		if _perspective_cross != null
		else 0
	)


func debug_fill_matches_boundary() -> bool:
	return (
		bool(_perspective_cross.call("perspective_fill_matches_boundary"))
		if _perspective_cross != null
		else false
	)


func debug_perspective_material() -> ShaderMaterial:
	return (
		_perspective_cross.call("perspective_material") as ShaderMaterial
		if _perspective_cross != null
		else null
	)


func debug_cross_position() -> Vector2:
	return _perspective_cross.position if _perspective_cross != null else Vector2.ZERO


func _build_stage() -> void:
	_perspective_cross = PERSPECTIVE_CROSS_SCRIPT.new() as Node2D
	_perspective_cross.name = "PerspectiveSlimeCross"
	_perspective_cross.position = BASE_POSITION
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
	header.color = Color(0.006, 0.012, 0.032, 0.94)
	header.position = Vector2.ZERO
	header.size = Vector2(VIEWPORT_SIZE.x, 104.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.text = "史莱姆十字透视窗 / SLIME CROSS PERSPECTIVE"
	title.position = Vector2(30.0, 16.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.76, 0.92, 1.0, 1.0))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "保留 20 点凹形软体轮廓 · 内部改用 SCREEN_UV 固定空间 Shader"
	subtitle.position = Vector2(32.0, 60.0)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.56, 0.72, 0.86, 1.0))
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
	heading.text = "组合验证"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color(0.58, 0.84, 1.0, 1.0))
	rows.add_child(heading)

	var description := Label.new()
	description.text = (
		"轮廓与动态\n"
		+ "• 复用原十字架 20 点 / 4 凹角软体求解\n"
		+ "• 圆角、面积压力、局部冲击保持不变\n\n"
		+ "内容显示\n"
		+ "• 直接复用 Anchored Star Window Shader\n"
		+ "• 星点只采样 SCREEN_UV，不跟随十字移动\n"
		+ "• 十字轮廓仅作为会形变的可见窗口\n\n"
		+ "观察十字移动 / 形变时，内部星空是否像固定在\n"
		+ "更深空间，而不是贴在胶体表面的纹理。"
	)
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color(0.70, 0.80, 0.88, 1.0))
	rows.add_child(description)

	var separator := HSeparator.new()
	rows.add_child(separator)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0, 1.0))
	rows.add_child(_status_label)


func _add_controls(overlay: CanvasLayer) -> void:
	var instruction := Label.new()
	instruction.text = "左键冲击边缘 · 十字沿轨迹移动以展示固定空间采样"
	instruction.position = Vector2(244.0, 655.0)
	instruction.size = Vector2(500.0, 28.0)
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 14)
	instruction.add_theme_color_override("font_color", Color(0.64, 0.76, 0.86, 1.0))
	overlay.add_child(instruction)

	var controls := HBoxContainer.new()
	controls.position = Vector2(138.0, 698.0)
	controls.size = Vector2(704.0, 48.0)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 8)
	overlay.add_child(controls)

	_add_button(controls, "PokeButton", "戳横臂", 102.0, _poke_arm)
	_add_button(controls, "SquashButton", "压扁 [F]", 104.0, debug_squash)
	_add_button(controls, "PauseButton", "暂停 [Space]", 126.0, _toggle_motion_pause)
	_add_button(controls, "ResetButton", "复原 [R]", 96.0, debug_reset)
	_debug_button = _add_button(controls, "DebugButton", "骨架：关 [D]", 112.0, _toggle_debug_rig)
	_auto_button = _add_button(controls, "AutoButton", "自动脉冲：开", 126.0, _toggle_auto_pulse)


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


func _on_viewport_size_changed() -> void:
	if _perspective_cross == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_perspective_cross.call(
		"set_viewport_aspect",
		viewport_size.x / maxf(viewport_size.y, 1.0)
	)


func _update_presentation() -> void:
	if _perspective_cross == null:
		return
	_perspective_cross.position = _cross_position(_time)
	_perspective_cross.call("set_perspective_animation_time", _time)
	_update_status()


func _cross_position(time_seconds: float) -> Vector2:
	return BASE_POSITION + Vector2(
		sin(time_seconds * 0.72) * 58.0,
		sin(time_seconds * 0.47 + 0.9) * 18.0
	)


func _poke_from_screen(screen_position: Vector2) -> void:
	if _perspective_cross == null:
		return
	var local_hit: Vector2 = _perspective_cross.to_local(screen_position)
	if absf(local_hit.x) > 170.0 or absf(local_hit.y) > 265.0:
		return
	debug_poke(local_hit, 1.0)


func _poke_arm() -> void:
	debug_poke(Vector2(-120.0, -103.0), 1.12)


func _run_auto_pulse() -> void:
	var pulse_points: Array[Vector2] = [
		Vector2(-120.0, -104.0),
		Vector2(120.0, -92.0),
		Vector2(29.0, -208.0),
		Vector2(-38.0, 116.0),
	]
	debug_poke(pulse_points[_auto_pulse_index % pulse_points.size()], 0.82)
	_auto_pulse_index += 1


func _toggle_motion_pause() -> void:
	debug_set_motion_paused(not _motion_paused)


func _toggle_auto_pulse() -> void:
	debug_set_auto_pulse(not _auto_pulse_enabled)
	_auto_pulse_timer = 0.55


func _toggle_debug_rig() -> void:
	debug_set_rig_enabled(not debug_rig_enabled())


func _update_buttons() -> void:
	if _debug_button != null:
		_debug_button.text = "骨架：开 [D]" if debug_rig_enabled() else "骨架：关 [D]"
	if _auto_button != null:
		_auto_button.text = "自动脉冲：开" if _auto_pulse_enabled else "自动脉冲：关"


func _update_status() -> void:
	if _status_label == null or _perspective_cross == null:
		return
	_status_label.text = (
		"状态  %s\n"
		+ "轮廓控制点  %d　内凹角  %d\n"
		+ "横臂 / 竖干  %.2f×\n"
		+ "Shader 填充点  %d\n"
		+ "面积保持  %.1f%%"
	) % [
		"固定预览" if _motion_paused else "移动中",
		debug_control_point_count(),
		debug_concave_corner_count(),
		debug_arm_span() / maxf(debug_stem_width(), 0.001),
		debug_fill_point_count(),
		debug_area_ratio() * 100.0,
	]


func _return_to_index() -> void:
	var error: Error = get_tree().change_scene_to_file(INDEX_SCENE_PATH)
	if error != OK:
		push_error("Failed to return to Test Lab index: %s" % error)
