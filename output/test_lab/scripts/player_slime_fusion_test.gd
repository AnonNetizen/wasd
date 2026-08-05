extends Node2D

const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const PLAYER_SLIME_SCRIPT := preload("res://scripts/player_slime_fusion.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const ACTUAL_ARENA := Rect2(145.0, 225.0, 375.0, 315.0)
const ACTUAL_CENTER := Vector2(325.0, 385.0)
const PREVIEW_MAIN_POSITION := Vector2(720.0, 375.0)
const PREVIEW_SWAP_POSITION := Vector2(1040.0, 375.0)
const PREVIEW_SCALE: float = 4.35
const PLAYER_RADIUS: float = 25.0
const MAIN_A_PRIMARY := Color("68bcdd")
const MAIN_B_PRIMARY := Color("ed2f72")

var _actual_player: Node2D
var _preview_main: Node2D
var _preview_swap: Node2D
var _metrics_label: Label
var _pause_button: Button
var _auto_button: Button
var _simulation_time: float = 0.0
var _next_fire_time: float = 0.55
var _next_hit_time: float = 1.85
var _next_swap_time: float = 4.4
var _hit_flash_remaining: float = 0.0
var _fixed_step_mode: bool = false
var _simulation_paused: bool = false
var _auto_demo_enabled: bool = true
var _actual_swapped: bool = false
var _pressed_keys: Dictionary = {}


func _ready() -> void:
	_build_stage()
	debug_reset()
	_update_buttons()
	_update_metrics()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _fixed_step_mode or _simulation_paused:
		return
	var manual_motion: Vector2 = _manual_motion_direction()
	if manual_motion.length_squared() > 0.0001:
		_advance_scene(delta, manual_motion.normalized() * 220.0, true)
	else:
		_advance_scene(delta, Vector2.ZERO, false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
			and not _is_pointer_over_button()
		):
			var aim: Vector2 = mouse_event.position - _actual_player.position
			debug_fire(aim)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		if key_event.pressed:
			_pressed_keys[key_event.keycode] = true
		else:
			_pressed_keys.erase(key_event.keycode)
		get_viewport().set_input_as_handled()
		return
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_H:
			debug_hit(Vector2(-25.0, -9.0))
		KEY_X:
			debug_swap_actual_fragments()
		KEY_SPACE:
			debug_set_paused(not _simulation_paused)
		KEY_R:
			debug_reset()
		KEY_F:
			debug_fire(Vector2(0.88, -0.48))
		KEY_T:
			debug_set_auto_demo(not _auto_demo_enabled)
		KEY_ESCAPE:
			_return_to_index()
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.010, 0.014, 0.026, 1.0))
	_draw_grid()
	draw_rect(ACTUAL_ARENA, Color(0.035, 0.044, 0.071, 0.78), true)
	draw_rect(ACTUAL_ARENA, Color(0.24, 0.28, 0.46, 0.72), false, 1.5)
	if _actual_player != null:
		draw_arc(
			_actual_player.position,
			PLAYER_RADIUS,
			0.0,
			TAU,
			72,
			Color(0.74, 0.78, 0.94, 0.44),
			1.0,
			true
		)
	_draw_bullet_scale_references()


func debug_set_fixed_step_mode(enabled: bool) -> void:
	_fixed_step_mode = enabled
	for visual: Node2D in _all_visuals():
		visual.call("set_fixed_step_mode", true)


func debug_advance_fixed_step(
	delta: float,
	motion_velocity: Vector2 = Vector2.ZERO,
	aim_direction: Vector2 = Vector2(0.88, -0.48)
) -> void:
	if not _fixed_step_mode or _simulation_paused:
		return
	_advance_scene(delta, motion_velocity, true, aim_direction)


func debug_fire(direction: Vector2 = Vector2.RIGHT) -> void:
	var safe_direction: Vector2 = direction.normalized()
	if safe_direction.length_squared() <= 0.0001:
		safe_direction = Vector2.RIGHT
	for visual: Node2D in _all_visuals():
		visual.call("apply_fire_impulse", safe_direction)


func debug_hit(local_hit: Vector2 = Vector2(-25.0, -8.0)) -> void:
	for visual: Node2D in _all_visuals():
		visual.call("apply_hit_impulse", local_hit)
	_hit_flash_remaining = 0.16


func debug_swap_actual_fragments() -> void:
	_actual_swapped = not _actual_swapped
	_configure_actual_palette()
	_actual_player.call("apply_fire_impulse", Vector2(0.88, -0.48))
	_update_metrics()


func debug_set_auto_demo(enabled: bool) -> void:
	_auto_demo_enabled = enabled
	_update_buttons()


func debug_set_paused(paused: bool) -> void:
	_simulation_paused = paused
	for visual: Node2D in _all_visuals():
		visual.call("set_simulation_paused", paused)
	_update_buttons()


func debug_reset() -> void:
	_simulation_time = 0.0
	_next_fire_time = 0.55
	_next_hit_time = 1.85
	_next_swap_time = 4.4
	_hit_flash_remaining = 0.0
	_actual_swapped = false
	_pressed_keys.clear()
	if _actual_player != null:
		_actual_player.position = ACTUAL_CENTER
	for visual: Node2D in _all_visuals():
		visual.call("reset_immediately")
		visual.call("set_simulation_paused", _simulation_paused)
	_configure_palettes()
	_apply_presentation_flash()
	_update_metrics()
	queue_redraw()


func debug_control_point_count() -> int:
	return int(_actual_player.call("control_point_count"))


func debug_boundary_point_count() -> int:
	return int(_actual_player.call("boundary_point_count"))


func debug_maximum_render_extent() -> float:
	return _maximum_visual_metric("maximum_render_extent")


func debug_area_ratio() -> float:
	return float(_actual_player.call("current_area_ratio"))


func debug_maximum_render_turn_degrees() -> float:
	return _maximum_visual_metric("maximum_render_turn_degrees")


func debug_maximum_neighbor_displacement_delta() -> float:
	return _maximum_visual_metric("maximum_neighbor_displacement_delta")


func debug_beam_end() -> Vector2:
	return _actual_player.call("beam_end") as Vector2


func debug_animation_time() -> float:
	return float(_actual_player.call("animation_time"))


func debug_simulation_time() -> float:
	return _simulation_time


func debug_geometry_signature() -> String:
	return str(_actual_player.call("geometry_signature"))


func debug_actual_palette() -> Dictionary:
	return _actual_player.call("palette_state") as Dictionary


func debug_preview_main_palette() -> Dictionary:
	return _preview_main.call("palette_state") as Dictionary


func debug_preview_swap_palette() -> Dictionary:
	return _preview_swap.call("palette_state") as Dictionary


func debug_body_material() -> ShaderMaterial:
	return _actual_player.call("body_material") as ShaderMaterial


func debug_body_polygon() -> PackedVector2Array:
	return _actual_player.call("body_polygon") as PackedVector2Array


func debug_visual_node_count() -> int:
	return int(_actual_player.call("visual_node_count"))


func debug_beam_gradient_colors() -> PackedColorArray:
	var colors: PackedColorArray = _actual_player.call("beam_gradient_colors")
	return colors


func debug_last_impulse_control_count() -> int:
	return int(_actual_player.call("last_impulse_control_count"))


func debug_last_impulse_controls_are_contiguous() -> bool:
	return bool(_actual_player.call("last_impulse_controls_are_contiguous"))


func debug_scene_node_count() -> int:
	return _count_nodes(self)


func debug_material_signature() -> String:
	var parts := PackedStringArray()
	for visual: Node2D in _all_visuals():
		var identifiers: PackedInt64Array = visual.call("material_instance_ids")
		for identifier: int in identifiers:
			parts.append(str(identifier))
	return ":".join(parts)


func debug_shader_source() -> String:
	var material: ShaderMaterial = debug_body_material()
	return material.shader.code if material != null and material.shader != null else ""


func debug_is_paused() -> bool:
	return _simulation_paused


func _build_stage() -> void:
	_actual_player = _create_visual("ActualPlayer", ACTUAL_CENTER, 1.0)
	_preview_main = _create_visual("PreviewMain", PREVIEW_MAIN_POSITION, PREVIEW_SCALE)
	_preview_swap = _create_visual("PreviewSwap", PREVIEW_SWAP_POSITION, PREVIEW_SCALE)
	_configure_palettes()
	_build_overlay()


func _create_visual(
	visual_name: String,
	visual_position: Vector2,
	visual_scale: float
) -> Node2D:
	var visual := PLAYER_SLIME_SCRIPT.new() as Node2D
	visual.name = visual_name
	visual.position = visual_position
	visual.scale = Vector2.ONE * visual_scale
	visual.call("set_fixed_step_mode", true)
	add_child(visual)
	return visual


func _configure_palettes() -> void:
	_configure_actual_palette()
	_preview_main.call(
		"configure_palette",
		MAIN_A_PRIMARY,
		MAIN_B_PRIMARY
	)
	_preview_swap.call(
		"configure_palette",
		MAIN_B_PRIMARY,
		MAIN_A_PRIMARY
	)


func _configure_actual_palette() -> void:
	if _actual_player == null:
		return
	if _actual_swapped:
		_actual_player.call(
			"configure_palette",
			MAIN_B_PRIMARY,
			MAIN_A_PRIMARY
		)
	else:
		_actual_player.call(
			"configure_palette",
			MAIN_A_PRIMARY,
			MAIN_B_PRIMARY
		)


func _advance_scene(
	delta: float,
	motion_velocity: Vector2,
	force_motion: bool,
	aim_override: Vector2 = Vector2.ZERO
) -> void:
	if _simulation_paused:
		return
	var safe_delta: float = clampf(delta, 0.0001, 0.033)
	var previous_position: Vector2 = _actual_player.position
	_simulation_time += safe_delta
	var resolved_motion: Vector2 = motion_velocity
	if not force_motion and _auto_demo_enabled:
		var target := Vector2(
			ACTUAL_CENTER.x + sin(_simulation_time * 0.92) * 118.0,
			ACTUAL_CENTER.y + sin(_simulation_time * 1.36) * 84.0
		)
		_actual_player.position = target
		resolved_motion = (target - previous_position) / safe_delta
	else:
		_actual_player.position += resolved_motion * safe_delta
		_actual_player.position.x = clampf(
			_actual_player.position.x,
			ACTUAL_ARENA.position.x + PLAYER_RADIUS,
			ACTUAL_ARENA.end.x - PLAYER_RADIUS
		)
		_actual_player.position.y = clampf(
			_actual_player.position.y,
			ACTUAL_ARENA.position.y + PLAYER_RADIUS,
			ACTUAL_ARENA.end.y - PLAYER_RADIUS
		)
	var aim_direction: Vector2 = aim_override.normalized()
	if aim_direction.length_squared() <= 0.0001:
		aim_direction = Vector2(0.88, -0.48)
		if not _fixed_step_mode:
			var mouse_aim: Vector2 = get_viewport().get_mouse_position() - _actual_player.position
			if mouse_aim.length_squared() > 64.0:
				aim_direction = mouse_aim.normalized()

	for visual: Node2D in _all_visuals():
		visual.call("advance_fixed_step", safe_delta, resolved_motion, aim_direction)
	_advance_auto_events()
	_hit_flash_remaining = maxf(_hit_flash_remaining - safe_delta, 0.0)
	_apply_presentation_flash()
	_update_metrics()
	queue_redraw()


func _advance_auto_events() -> void:
	if not _auto_demo_enabled:
		return
	if _simulation_time >= _next_fire_time:
		debug_fire(Vector2(0.88, -0.48))
		_next_fire_time += 0.72
	if _simulation_time >= _next_hit_time:
		debug_hit(Vector2(-25.0, -8.0))
		_next_hit_time += 2.55
	if _simulation_time >= _next_swap_time:
		debug_swap_actual_fragments()
		_next_swap_time += 4.4


func _apply_presentation_flash() -> void:
	var flash_ratio: float = clampf(_hit_flash_remaining / 0.16, 0.0, 1.0)
	var tint: Color = Color.WHITE.lerp(Color(1.0, 0.52, 0.60, 1.0), flash_ratio)
	if _actual_player != null:
		_actual_player.call("set_presentation_state", tint, 1.0, 1.0)
	if _preview_main != null:
		_preview_main.call("set_presentation_state", tint, 1.0, PREVIEW_SCALE)
	if _preview_swap != null:
		_preview_swap.call("set_presentation_state", tint, 1.0, PREVIEW_SCALE)


func _all_visuals() -> Array[Node2D]:
	var visuals: Array[Node2D] = []
	if _actual_player != null:
		visuals.append(_actual_player)
	if _preview_main != null:
		visuals.append(_preview_main)
	if _preview_swap != null:
		visuals.append(_preview_swap)
	return visuals


func _maximum_visual_metric(method_name: StringName) -> float:
	var maximum_value: float = 0.0
	for visual: Node2D in _all_visuals():
		maximum_value = maxf(maximum_value, float(visual.call(method_name)))
	return maximum_value


func _manual_motion_direction() -> Vector2:
	var direction := Vector2.ZERO
	if _pressed_keys.has(KEY_A) or _pressed_keys.has(KEY_LEFT):
		direction.x -= 1.0
	if _pressed_keys.has(KEY_D) or _pressed_keys.has(KEY_RIGHT):
		direction.x += 1.0
	if _pressed_keys.has(KEY_W) or _pressed_keys.has(KEY_UP):
		direction.y -= 1.0
	if _pressed_keys.has(KEY_S) or _pressed_keys.has(KEY_DOWN):
		direction.y += 1.0
	return direction


func _build_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	add_child(overlay)
	_add_header(overlay)
	_add_labels(overlay)
	_add_metrics(overlay)
	_add_controls(overlay)


func _add_header(overlay: CanvasLayer) -> void:
	var header := ColorRect.new()
	header.name = "Header"
	header.position = Vector2.ZERO
	header.size = Vector2(VIEWPORT_SIZE.x, 104.0)
	header.color = Color(0.006, 0.010, 0.021, 0.96)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(header)

	var title := Label.new()
	title.text = "双涡旋史莱姆玩家 / DUAL-VORTEX PLAYER"
	title.position = Vector2(28.0, 16.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.83, 0.80, 1.0, 1.0))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "20 控制点 → 100 点有界二次边界 · 25 px 判定 · 主副 primary 50/50 反向流"
	subtitle.position = Vector2(30.0, 60.0)
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.64, 0.70, 0.83, 1.0))
	header.add_child(subtitle)

	var exit_button := Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "返回实验索引 [Esc]"
	exit_button.position = Vector2(1060.0, 28.0)
	exit_button.size = Vector2(190.0, 48.0)
	exit_button.pressed.connect(_return_to_index)
	header.add_child(exit_button)


func _add_labels(overlay: CanvasLayer) -> void:
	_add_label(
		overlay,
		"ActualLabel",
		"实战 1× · r=25\n与 r=12 子弹同屏",
		Vector2(165.0, 132.0),
		Vector2(340.0, 58.0),
		18,
		Color(0.78, 0.84, 1.0, 1.0)
	)
	_add_label(
		overlay,
		"MainPreviewLabel",
		"主：冷静 primary\n副：愤怒 primary · 4.35×",
		Vector2(590.0, 126.0),
		Vector2(260.0, 70.0),
		17,
		MAIN_A_PRIMARY.lightened(0.24)
	)
	_add_label(
		overlay,
		"SwapPreviewLabel",
		"主：愤怒 primary\n副：冷静 primary · 4.35×",
		Vector2(910.0, 126.0),
		Vector2(270.0, 70.0),
		17,
		MAIN_B_PRIMARY.lightened(0.18)
	)


func _add_metrics(overlay: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.name = "MetricsPanel"
	panel.position = Vector2(560.0, 572.0)
	panel.size = Vector2(620.0, 92.0)
	overlay.add_child(panel)

	_metrics_label = Label.new()
	_metrics_label.name = "Metrics"
	_metrics_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_metrics_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_metrics_label.add_theme_font_size_override("font_size", 14)
	_metrics_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.95, 1.0))
	panel.add_child(_metrics_label)


func _add_controls(overlay: CanvasLayer) -> void:
	var controls := HBoxContainer.new()
	controls.name = "Controls"
	controls.position = Vector2(88.0, 692.0)
	controls.size = Vector2(1104.0, 48.0)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", 9)
	overlay.add_child(controls)

	_add_button(controls, "FireButton", "开火 [F / 左键]", 145.0, debug_fire)
	_add_button(controls, "HitButton", "受击 [H]", 110.0, debug_hit)
	_add_button(controls, "SwapButton", "主副交换 [X]", 135.0, debug_swap_actual_fragments)
	_pause_button = _add_button(controls, "PauseButton", "暂停 [Space]", 130.0, _toggle_pause)
	_auto_button = _add_button(controls, "AutoButton", "自动演示：开 [T]", 155.0, _toggle_auto)
	_add_button(controls, "ResetButton", "复位 [R]", 105.0, debug_reset)


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


func _add_label(
	parent: CanvasLayer,
	label_name: String,
	label_text: String,
	label_position: Vector2,
	label_size: Vector2,
	font_size: int,
	font_color: Color
) -> void:
	var label := Label.new()
	label.name = label_name
	label.text = label_text
	label.position = label_position
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	parent.add_child(label)


func _draw_grid() -> void:
	for x in range(0, int(VIEWPORT_SIZE.x) + 1, 64):
		draw_line(
			Vector2(float(x), 104.0),
			Vector2(float(x), VIEWPORT_SIZE.y),
			Color(0.20, 0.27, 0.46, 0.075),
			1.0
		)
	for y in range(104, int(VIEWPORT_SIZE.y) + 1, 64):
		draw_line(
			Vector2(0.0, float(y)),
			Vector2(VIEWPORT_SIZE.x, float(y)),
			Color(0.20, 0.27, 0.46, 0.075),
			1.0
		)


func _draw_bullet_scale_references() -> void:
	for index in range(4):
		var travel: float = fmod(_simulation_time * 150.0 + float(index) * 95.0, 360.0)
		var center := Vector2(150.0 + travel, 575.0 + float(index % 2) * 30.0)
		var fill: Color = Color("dceaf2") if index % 2 == 0 else Color("e62935")
		var rim: Color = Color("f6fbff") if index % 2 == 0 else Color("ff5963")
		draw_circle(center, 12.0, rim)
		draw_circle(center, 10.8, fill)


func _update_metrics() -> void:
	if _metrics_label == null or _actual_player == null:
		return
	_metrics_label.text = (
		"控制 / 边界：%d / %d　轮缘 extent：%.2f / 25 px　面积：%.1f%%\n"
		+ "最大转角：%.1f°　邻点位移差：%.2f px　枪口：%.0f px　实际主碎片：%s"
	) % [
		debug_control_point_count(),
		debug_boundary_point_count(),
		debug_maximum_render_extent(),
		debug_area_ratio() * 100.0,
		debug_maximum_render_turn_degrees(),
		debug_maximum_neighbor_displacement_delta(),
		debug_beam_end().x,
		"愤怒" if _actual_swapped else "冷静",
	]


func _update_buttons() -> void:
	if _pause_button != null:
		_pause_button.text = "继续 [Space]" if _simulation_paused else "暂停 [Space]"
	if _auto_button != null:
		_auto_button.text = "自动演示：开 [T]" if _auto_demo_enabled else "自动演示：关 [T]"


func _toggle_pause() -> void:
	debug_set_paused(not _simulation_paused)


func _toggle_auto() -> void:
	debug_set_auto_demo(not _auto_demo_enabled)


func _is_pointer_over_button() -> bool:
	return get_viewport().gui_get_hovered_control() is Button


func _count_nodes(node: Node) -> int:
	var count: int = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


func _return_to_index() -> void:
	var error: Error = get_tree().change_scene_to_file(INDEX_SCENE_PATH)
	if error != OK:
		push_error("Failed to return to Test Lab index: %s" % error)
