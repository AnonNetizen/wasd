class_name TestLabGlowOrbBulletFocus
extends "res://scripts/tear_core_bullet_focus_test.gd"

## Dedicated comparison scene for four-control-point slime-rim projectiles.

const ORB_SAMPLE_SCRIPT := preload("res://scripts/glow_orb_bullet_sample.gd")


func debug_rim_pair_matches() -> bool:
	if _focus_samples.size() != 2:
		return false
	return (
		_focus_samples[0].call("body_render_mode")
		== _focus_samples[1].call("body_render_mode")
	)


func debug_circle_geometry_locked() -> bool:
	if _focus_samples.size() != 2:
		return false
	var expected: String = (
		"circle:r1.0:four_edge_nodes:catmull_rom:no_highlight:no_shader:no_glow"
	)
	return (
		str(_focus_samples[0].call("geometry_signature")) == expected
		and str(_focus_samples[1].call("geometry_signature")) == expected
	)


func debug_uses_four_node_slime_rim() -> bool:
	for sample: Node2D in _samples:
		if str(sample.call("body_render_mode")) != "four_node_slime_rim":
			return false
	return true


func debug_all_edge_controls_ready() -> bool:
	for sample: Node2D in _samples:
		if int(sample.call("edge_control_node_count")) != 4:
			return false
		if int(sample.call("smoothed_boundary_point_count")) != 64:
			return false
		if not bool(sample.call("edge_controls_form_cardinal_ring")):
			return false
	return true


func debug_no_localized_highlight() -> bool:
	for sample: Node2D in _samples:
		if bool(sample.call("has_localized_highlight")):
			return false
	return true


func debug_all_rim_colors_differ() -> bool:
	for sample: Node2D in _samples:
		if not bool(sample.call("rim_color_differs_from_body")):
			return false
	return true


func debug_actual_scale_rims_visible() -> bool:
	if _moving_samples.size() != 2:
		return false
	for sample: Node2D in _moving_samples:
		var rim_width: float = float(sample.call("rim_width_pixels"))
		var body_radius: float = float(sample.call("collision_radius"))
		if rim_width < 1.0 or rim_width >= body_radius * 0.5:
			return false
	return true


func debug_no_external_glow() -> bool:
	for sample: Node2D in _samples:
		if not is_zero_approx(float(sample.call("external_glow_extent"))):
			return false
	return true


func debug_enemy_is_red_dominant() -> bool:
	if _focus_samples.size() != 2:
		return false
	var color: Color = _focus_samples[1].call("primary_color")
	return color.r > color.g * 3.0 and color.r > color.b * 2.5


func _build_samples() -> void:
	for sample: Node2D in _samples:
		if is_instance_valid(sample):
			sample.queue_free()
	_samples.clear()
	_focus_samples.clear()
	_moving_samples.clear()

	_add_orb_focus_sample(ORB_SAMPLE_SCRIPT.TeamPalette.PLAYER_WHITE, Vector2(330.0, 320.0))
	_add_orb_focus_sample(ORB_SAMPLE_SCRIPT.TeamPalette.ENEMY_RED, Vector2(950.0, 320.0))
	_add_orb_moving_sample(
		ORB_SAMPLE_SCRIPT.TeamPalette.PLAYER_WHITE,
		Vector2(LANE_START_X, 590.0),
		PLAYER_RADIUS,
		PLAYER_SPEED
	)
	_add_orb_moving_sample(
		ORB_SAMPLE_SCRIPT.TeamPalette.ENEMY_RED,
		Vector2(LANE_START_X, 655.0),
		ENEMY_RADIUS,
		ENEMY_SPEED
	)
	_apply_sample_toggles()


func _add_orb_focus_sample(team_palette: int, sample_position: Vector2) -> void:
	var sample: Node2D = ORB_SAMPLE_SCRIPT.new() as Node2D
	sample.position = sample_position
	add_child(sample)
	sample.call(
		"configure",
		team_palette,
		FOCUS_HIT_RADIUS,
		FOCUS_SCALE
	)
	_samples.append(sample)
	_focus_samples.append(sample)


func _add_orb_moving_sample(
	team_palette: int,
	sample_position: Vector2,
	hit_radius: float,
	speed: float
) -> void:
	var sample: Node2D = ORB_SAMPLE_SCRIPT.new() as Node2D
	sample.position = sample_position
	add_child(sample)
	sample.call(
		"configure",
		team_palette,
		hit_radius,
		1.0,
		speed,
		LANE_END_X - LANE_START_X
	)
	_samples.append(sample)
	_moving_samples.append(sample)


func _draw_header() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(28.0, 38.0),
		"四节点史莱姆边圆球 / FOUR-NODE SLIME RIM ORB",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		24,
		COLOR_ACCENT
	)
	draw_string(
		font,
		Vector2(28.0, 70.0),
		"4 个边缘控制节点 · Catmull-Rom 圆边 · 双色平涂 · 无 Shader / 高光 / 外发光",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		COLOR_TEXT_DIM
	)
	var state_text: String = "命中放大" if _focus_impact_mode else "弹体放大"
	if _paused:
		state_text += " · 已暂停"
	draw_string(
		font,
		Vector2(1038.0, 39.0),
		state_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		COLOR_ACCENT
	)


func _draw_focus_panel(rect: Rect2, title: String, enemy: bool) -> void:
	var font: Font = ThemeDB.fallback_font
	var team_color: Color = COLOR_ENEMY if enemy else COLOR_PLAYER
	draw_rect(rect, COLOR_PANEL, true)
	draw_rect(rect, COLOR_PANEL_BORDER, false, 1.5)
	draw_string(
		font,
		rect.position + Vector2(18.0, 30.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		18,
		team_color
	)
	draw_string(
		font,
		rect.position + Vector2(18.0, 58.0),
		"四点软边 · 统一边色 + 内部平涂 · 无 Shader / 高光 / 外发光",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		COLOR_TEXT_DIM
	)
	var swatch_colors: Array[Color]
	if enemy:
		swatch_colors = [Color("e62935"), Color("ff5963")]
	else:
		swatch_colors = [Color("dceaf2"), Color("f6fbff")]
	var swatch_labels := PackedStringArray(["内部", "边缘"])
	for index in range(swatch_colors.size()):
		var swatch_position: Vector2 = rect.position + Vector2(18.0 + float(index) * 132.0, 365.0)
		draw_rect(Rect2(swatch_position, Vector2(28.0, 16.0)), swatch_colors[index], true)
		draw_rect(
			Rect2(swatch_position, Vector2(28.0, 16.0)),
			Color(1.0, 1.0, 1.0, 0.24),
			false,
			1.0
		)
		draw_string(
			font,
			swatch_position + Vector2(36.0, 14.0),
			swatch_labels[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			COLOR_TEXT_DIM
		)


func _draw_footer() -> void:
	var font: Font = ThemeDB.fallback_font
	var background_names := PackedStringArray(["纯暗", "低对比网格", "低饱和意识层"])
	var controls: String = (
		"[Space] 暂停  [R] 重置  [H] 弹体/命中  [D] 判定圆  [T] 拖尾  [B] 背景：%s  [Esc] 返回"
		% background_names[_background_mode]
	)
	draw_string(font, Vector2(28.0, 730.0), controls, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COLOR_TEXT_DIM)
	draw_string(font, Vector2(1090.0, 730.0), "待人工确认", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COLOR_ACCENT)
