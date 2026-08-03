class_name TestLabGlowOrbBulletFocus
extends "res://scripts/tear_core_bullet_focus_test.gd"

## Dedicated comparison scene for simple glowing circular projectiles.

const ORB_SAMPLE_SCRIPT := preload("res://scripts/glow_orb_bullet_sample.gd")


func debug_gradient_pair_matches() -> bool:
	if _focus_samples.size() != 2:
		return false
	return (
		_focus_samples[0].call("gradient_step_count")
		== _focus_samples[1].call("gradient_step_count")
	)


func debug_circle_geometry_locked() -> bool:
	if _focus_samples.size() != 2:
		return false
	var expected: String = "circle:r1.0:gradient10:highlight_nw"
	return (
		str(_focus_samples[0].call("geometry_signature")) == expected
		and str(_focus_samples[1].call("geometry_signature")) == expected
	)


func debug_gradient_step_count() -> int:
	if _focus_samples.is_empty():
		return 0
	return int(_focus_samples[0].call("gradient_step_count"))


func debug_all_glows_bounded() -> bool:
	for sample: Node2D in _samples:
		var radius: float = float(sample.call("collision_radius"))
		var glow_extent: float = float(sample.call("glow_visual_extent"))
		if glow_extent <= radius or glow_extent > radius * 1.50 + 0.001:
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
		"发光圆球子弹 / GLOW ORB BULLET — 极简高辨识方案",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		24,
		COLOR_ACCENT
	)
	draw_string(
		font,
		Vector2(28.0, 70.0),
		"无贴图 · 无 Shader · 无材质切换 · 圆球暗边与十级径向渐变",
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
		"圆球剪影 · 暗边 · 同色渐变 · 左上白热高光 · 轻外发光",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		COLOR_TEXT_DIM
	)
	var swatch_colors: Array[Color]
	if enemy:
		swatch_colors = [Color("2b080b"), Color("981019"), Color("e62935"), Color("fff2ed")]
	else:
		swatch_colors = [Color("111722"), Color("8099a7"), Color("dceaf2"), Color("ffffff")]
	var swatch_labels := PackedStringArray(["暗边", "球缘", "主体", "高光"])
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
