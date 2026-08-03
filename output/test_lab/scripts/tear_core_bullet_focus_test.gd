class_name TestLabTearCoreBulletFocus
extends Node2D

## Dedicated oversized material and motion study for the selected tear-core bullet.

const SAMPLE_SCRIPT := preload("res://scripts/bullet_vfx_sample.gd")

const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const FOCUS_HIT_RADIUS: float = 10.0
const FOCUS_SCALE: float = 14.5
const PLAYER_RADIUS: float = 8.0
const PLAYER_SPEED: float = 520.0
const ENEMY_RADIUS: float = 5.0
const ENEMY_SPEED: float = 280.0
const LANE_START_X: float = 90.0
const LANE_END_X: float = 1190.0

const COLOR_BACKGROUND: Color = Color("02070b")
const COLOR_BACKGROUND_GRID: Color = Color("061116")
const COLOR_BACKGROUND_LAYER: Color = Color("100b19")
const COLOR_GRID: Color = Color(0.18, 0.55, 0.52, 0.10)
const COLOR_PANEL: Color = Color(0.025, 0.045, 0.058, 0.96)
const COLOR_PANEL_BORDER: Color = Color(0.28, 0.88, 0.74, 0.30)
const COLOR_TEXT: Color = Color("e9f7f4")
const COLOR_TEXT_DIM: Color = Color("8ca5ad")
const COLOR_ACCENT: Color = Color("74f0c8")
const COLOR_PLAYER: Color = Color("ffffff")
const COLOR_ENEMY: Color = Color("ff4a46")

var _samples: Array[Node2D] = []
var _focus_samples: Array[Node2D] = []
var _moving_samples: Array[Node2D] = []
var _preview_time: float = 0.0
var _paused: bool = false
var _show_hitboxes: bool = false
var _show_trails: bool = true
var _focus_impact_mode: bool = false
var _background_mode: int = 1


func _ready() -> void:
	_build_samples()
	_apply_preview_time()
	queue_redraw()


func _process(delta: float) -> void:
	if not _paused:
		_preview_time += minf(delta, 0.05)
		_apply_preview_time()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_SPACE:
			_paused = not _paused
		KEY_R:
			debug_reset()
		KEY_D:
			_show_hitboxes = not _show_hitboxes
			_apply_sample_toggles()
		KEY_T:
			_show_trails = not _show_trails
			_apply_sample_toggles()
		KEY_H:
			_focus_impact_mode = not _focus_impact_mode
			_apply_preview_time()
		KEY_B:
			_background_mode = (_background_mode + 1) % 3
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")
	queue_redraw()


func _draw() -> void:
	_draw_background()
	_draw_header()
	_draw_focus_panel(
		Rect2(50.0, 112.0, 560.0, 398.0),
		"人物白弹 / PLAYER WHITE",
		false
	)
	_draw_focus_panel(
		Rect2(670.0, 112.0, 560.0, 398.0),
		"敌方红弹 / ENEMY RED",
		true
	)
	_draw_flight_lanes()
	_draw_footer()


func debug_set_preview_time(value: float) -> void:
	_preview_time = maxf(value, 0.0)
	_paused = true
	_apply_preview_time()
	queue_redraw()


func debug_reset() -> void:
	_preview_time = 0.0
	_paused = false
	_focus_impact_mode = false
	for sample: Node2D in _samples:
		sample.call("reset_preview")
	_apply_preview_time()
	queue_redraw()


func debug_sample_count() -> int:
	return _samples.size()


func debug_focus_pair_matches() -> bool:
	if _focus_samples.size() != 2:
		return false
	return _focus_samples[0].call("geometry_signature") == _focus_samples[1].call("geometry_signature")


func debug_focus_visual_diameter() -> float:
	if _focus_samples.is_empty():
		return 0.0
	return float(_focus_samples[0].call("visual_body_extent")) * 2.0


func debug_all_body_extents_fit() -> bool:
	for sample: Node2D in _samples:
		if float(sample.call("visual_body_extent")) > float(sample.call("collision_radius")) + 0.001:
			return false
	return true


func debug_player_flight_config() -> Vector2:
	if _moving_samples.size() != 2:
		return Vector2.ZERO
	return Vector2(
		float(_moving_samples[0].call("configured_hit_radius")),
		float(_moving_samples[0].call("preview_speed"))
	)


func debug_enemy_flight_config() -> Vector2:
	if _moving_samples.size() != 2:
		return Vector2.ZERO
	return Vector2(
		float(_moving_samples[1].call("configured_hit_radius")),
		float(_moving_samples[1].call("preview_speed"))
	)


func debug_all_trails_bounded() -> bool:
	for sample: Node2D in _samples:
		if int(sample.call("trail_sample_count")) > SAMPLE_SCRIPT.MAX_TRAIL_SAMPLES:
			return false
	return true


func debug_moving_trail_total() -> int:
	var total: int = 0
	for sample: Node2D in _moving_samples:
		total += int(sample.call("trail_sample_count"))
	return total


func debug_force_moving_impacts(progress: float) -> void:
	for sample: Node2D in _moving_samples:
		sample.call("debug_force_impact", progress)
	queue_redraw()


func debug_no_trail_residue() -> bool:
	for sample: Node2D in _samples:
		if int(sample.call("trail_sample_count")) != 0:
			return false
	return true


func debug_all_effects_childless() -> bool:
	for sample: Node2D in _samples:
		if int(sample.call("effect_child_count")) != 0:
			return false
	return true


func debug_set_focus_impact_mode(enabled: bool) -> void:
	_focus_impact_mode = enabled
	_apply_preview_time()
	queue_redraw()


func debug_focus_impacts_active() -> bool:
	if _focus_samples.size() != 2:
		return false
	for sample: Node2D in _focus_samples:
		if not bool(sample.call("is_impact_active")):
			return false
	return true


func _build_samples() -> void:
	for sample: Node2D in _samples:
		if is_instance_valid(sample):
			sample.queue_free()
	_samples.clear()
	_focus_samples.clear()
	_moving_samples.clear()

	_add_focus_sample(SAMPLE_SCRIPT.TeamPalette.PLAYER_WHITE, Vector2(330.0, 310.0))
	_add_focus_sample(SAMPLE_SCRIPT.TeamPalette.ENEMY_RED, Vector2(950.0, 310.0))
	_add_moving_sample(
		SAMPLE_SCRIPT.TeamPalette.PLAYER_WHITE,
		Vector2(LANE_START_X, 590.0),
		PLAYER_RADIUS,
		PLAYER_SPEED
	)
	_add_moving_sample(
		SAMPLE_SCRIPT.TeamPalette.ENEMY_RED,
		Vector2(LANE_START_X, 655.0),
		ENEMY_RADIUS,
		ENEMY_SPEED
	)
	_apply_sample_toggles()


func _add_focus_sample(team_palette: int, sample_position: Vector2) -> void:
	var sample: Node2D = SAMPLE_SCRIPT.new() as Node2D
	sample.position = sample_position
	add_child(sample)
	sample.call(
		"configure",
		SAMPLE_SCRIPT.VariantId.TEAR_CORE,
		team_palette,
		FOCUS_HIT_RADIUS,
		FOCUS_SCALE
	)
	_samples.append(sample)
	_focus_samples.append(sample)


func _add_moving_sample(
	team_palette: int,
	sample_position: Vector2,
	hit_radius: float,
	speed: float
) -> void:
	var sample: Node2D = SAMPLE_SCRIPT.new() as Node2D
	sample.position = sample_position
	add_child(sample)
	sample.call(
		"configure",
		SAMPLE_SCRIPT.VariantId.TEAR_CORE,
		team_palette,
		hit_radius,
		1.0,
		speed,
		LANE_END_X - LANE_START_X
	)
	_samples.append(sample)
	_moving_samples.append(sample)


func _apply_preview_time() -> void:
	for sample: Node2D in _focus_samples:
		sample.call("set_preview_time", _preview_time)
		if _focus_impact_mode:
			sample.call("debug_force_impact", _focus_impact_progress())
	for sample: Node2D in _moving_samples:
		sample.call("set_preview_time", _preview_time)


func _focus_impact_progress() -> float:
	return clampf(fposmod(_preview_time, 1.0), 0.04, 0.96)


func _apply_sample_toggles() -> void:
	for sample: Node2D in _samples:
		sample.call("set_hitbox_visible", _show_hitboxes)
		sample.call("set_trail_visible", _show_trails)


func _draw_background() -> void:
	var background_color: Color
	match _background_mode:
		0:
			background_color = COLOR_BACKGROUND
		1:
			background_color = COLOR_BACKGROUND_GRID
		_:
			background_color = COLOR_BACKGROUND_LAYER
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), background_color)
	if _background_mode == 1:
		for x_position in range(0, int(VIEWPORT_SIZE.x) + 1, 32):
			draw_line(
				Vector2(float(x_position), 0.0),
				Vector2(float(x_position), VIEWPORT_SIZE.y),
				COLOR_GRID,
				1.0
			)
		for y_position in range(0, int(VIEWPORT_SIZE.y) + 1, 32):
			draw_line(
				Vector2(0.0, float(y_position)),
				Vector2(VIEWPORT_SIZE.x, float(y_position)),
				COLOR_GRID,
				1.0
			)
	elif _background_mode == 2:
		for ring_index in range(6):
			var ring_center := Vector2(150.0 + float(ring_index) * 220.0, 330.0)
			draw_circle(
				ring_center,
				230.0 - float(ring_index % 2) * 55.0,
				Color(0.28, 0.08, 0.34, 0.045)
			)


func _draw_header() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(28.0, 38.0),
		"01  泪核胶珠 / TEAR CORE — 放大材质与动态检查",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		25,
		COLOR_ACCENT
	)
	draw_string(
		font,
		Vector2(28.0, 70.0),
		"等尺寸超大特写 · 完全同形红白配色 · 底部保留真实 r / 速度",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		COLOR_TEXT_DIM
	)
	var state_text: String = "命中放大" if _focus_impact_mode else "弹体放大"
	if _paused:
		state_text += " · 已暂停"
	draw_string(
		font,
		Vector2(1020.0, 39.0),
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
		"泪滴圆核 · 轴向胶感 · 湿润高光",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		COLOR_TEXT_DIM
	)
	var swatch_colors: Array[Color]
	var swatch_labels: PackedStringArray
	if enemy:
		swatch_colors = [Color("2b080b"), Color("e62935"), Color("ff5a55"), Color("ffd6cf")]
		swatch_labels = PackedStringArray(["反边", "胶体", "内核", "高光"])
	else:
		swatch_colors = [Color("111722"), Color("dceaf2"), Color("9cb7c5"), Color("ffffff")]
		swatch_labels = PackedStringArray(["反边", "胶体", "内馅", "高光"])
	for index in range(swatch_colors.size()):
		var swatch_position: Vector2 = rect.position + Vector2(18.0 + float(index) * 132.0, 365.0)
		draw_rect(Rect2(swatch_position, Vector2(28.0, 16.0)), swatch_colors[index], true)
		draw_rect(Rect2(swatch_position, Vector2(28.0, 16.0)), Color(1.0, 1.0, 1.0, 0.24), false, 1.0)
		draw_string(
			font,
			swatch_position + Vector2(36.0, 14.0),
			swatch_labels[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			COLOR_TEXT_DIM
		)


func _draw_flight_lanes() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(28.0, 548.0),
		"1× 实战读法 / ACTUAL-SCALE READ",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		COLOR_TEXT
	)
	draw_line(Vector2(LANE_START_X, 590.0), Vector2(LANE_END_X, 590.0), Color(1.0, 1.0, 1.0, 0.13), 1.0)
	draw_line(Vector2(LANE_START_X, 655.0), Vector2(LANE_END_X, 655.0), Color(1.0, 0.20, 0.18, 0.14), 1.0)
	draw_line(Vector2(LANE_END_X, 565.0), Vector2(LANE_END_X, 680.0), Color(0.45, 0.94, 0.80, 0.30), 1.0)
	draw_string(font, Vector2(28.0, 595.0), "白", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, COLOR_PLAYER)
	draw_string(font, Vector2(28.0, 660.0), "红", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, COLOR_ENEMY)
	draw_string(
		font,
		Vector2(940.0, 548.0),
		"WHITE r8 / 520 px·s⁻¹   RED r5 / 280 px·s⁻¹",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		COLOR_TEXT_DIM
	)


func _draw_footer() -> void:
	var font: Font = ThemeDB.fallback_font
	var background_names := PackedStringArray(["纯暗", "低对比网格", "低饱和意识层"])
	var controls: String = (
		"[Space] 暂停  [R] 重置  [H] 弹体/命中放大  [D] 判定圆  [T] 拖尾  [B] 背景：%s  [Esc] 返回"
		% background_names[_background_mode]
	)
	draw_string(font, Vector2(28.0, 730.0), controls, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COLOR_TEXT_DIM)
	draw_string(font, Vector2(1080.0, 730.0), "待人工确认", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COLOR_ACCENT)
