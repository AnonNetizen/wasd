class_name TestLabBulletVfxSelection
extends Node2D

## Six-way red/white procedural bullet comparison wall for human selection.

const SAMPLE_SCRIPT := preload("res://scripts/bullet_vfx_sample.gd")

const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const CARD_SIZE := Vector2(400.0, 296.0)
const CARD_START := Vector2(22.0, 94.0)
const CARD_GAP := Vector2(18.0, 16.0)
const LANE_START_X: float = 44.0
const LANE_END_X: float = 362.0
const PLAYER_RADIUS: float = 8.0
const PLAYER_SPEED: float = 520.0
const ENEMY_RADIUS: float = 5.0
const ENEMY_SPEED: float = 280.0
const STATIC_SCALE: float = 4.0

const COLOR_BACKGROUND: Color = Color("03090d")
const COLOR_BACKGROUND_GRID: Color = Color("061116")
const COLOR_BACKGROUND_LAYER: Color = Color("120d1d")
const COLOR_GRID: Color = Color(0.18, 0.55, 0.52, 0.11)
const COLOR_CARD: Color = Color(0.035, 0.055, 0.068, 0.96)
const COLOR_CARD_BORDER: Color = Color(0.28, 0.88, 0.74, 0.28)
const COLOR_TEXT: Color = Color("e9f7f4")
const COLOR_TEXT_DIM: Color = Color("8ca5ad")
const COLOR_ACCENT: Color = Color("74f0c8")
const COLOR_PLAYER: Color = Color("ffffff")
const COLOR_ENEMY: Color = Color("ff4a46")

const VARIANT_NAMES: Array[String] = [
	"01  泪核胶珠 / TEAR CORE",
	"02  十字胶籽 / CROSS SEED",
	"03  缺口胶环 / GAP RING",
	"04  圆头胶囊 / ROUND CAPSULE",
	"05  三瓣胶冠 / TRI-LOBE CROWN",
	"06  棱面胶矢 / FACET DART",
]

var _samples: Array[Node2D] = []
var _preview_time: float = 0.0
var _paused: bool = false
var _show_hitboxes: bool = false
var _show_trails: bool = true
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
		KEY_B:
			_background_mode = (_background_mode + 1) % 3
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")
	queue_redraw()


func _draw() -> void:
	_draw_background()
	_draw_header()
	for variant_index in range(SAMPLE_SCRIPT.VARIANT_COUNT):
		_draw_card(variant_index, _card_origin(variant_index))
	_draw_footer()


func debug_set_preview_time(value: float) -> void:
	_preview_time = maxf(value, 0.0)
	_paused = true
	_apply_preview_time()
	queue_redraw()


func debug_reset() -> void:
	_preview_time = 0.0
	_paused = false
	for sample: Node2D in _samples:
		sample.call("reset_preview")
	_apply_preview_time()


func debug_variant_count() -> int:
	return SAMPLE_SCRIPT.VARIANT_COUNT


func debug_team_pair_count() -> int:
	var complete_pair_count: int = 0
	for variant_index in range(SAMPLE_SCRIPT.VARIANT_COUNT):
		if _variant_has_complete_samples(variant_index):
			complete_pair_count += 1
	return complete_pair_count


func debug_sample_count() -> int:
	return _samples.size()


func debug_geometry_pairs_match() -> bool:
	for variant_index in range(SAMPLE_SCRIPT.VARIANT_COUNT):
		var player_sample: Node2D = _moving_sample(variant_index, false)
		var enemy_sample: Node2D = _moving_sample(variant_index, true)
		if player_sample.call("geometry_signature") != enemy_sample.call("geometry_signature"):
			return false
	return true


func debug_unique_geometry_count() -> int:
	var signatures: Dictionary = {}
	for variant_index in range(SAMPLE_SCRIPT.VARIANT_COUNT):
		var sample: Node2D = _moving_sample(variant_index, false)
		signatures[String(sample.call("geometry_signature"))] = true
	return signatures.size()


func debug_all_body_extents_fit() -> bool:
	for sample: Node2D in _samples:
		if float(sample.call("visual_body_extent")) > float(sample.call("collision_radius")) + 0.001:
			return false
	return true


func debug_all_trails_bounded() -> bool:
	for sample: Node2D in _samples:
		if int(sample.call("trail_sample_count")) > SAMPLE_SCRIPT.MAX_TRAIL_SAMPLES:
			return false
	return true


func debug_moving_trail_sample_total() -> int:
	var total: int = 0
	for sample: Node2D in _samples:
		if sample.get_meta("moving", false):
			total += int(sample.call("trail_sample_count"))
	return total


func debug_all_effects_childless() -> bool:
	for sample: Node2D in _samples:
		if int(sample.call("effect_child_count")) != 0:
			return false
	return true


func debug_red_palette_dominant() -> bool:
	for variant_index in range(SAMPLE_SCRIPT.VARIANT_COUNT):
		var color: Color = _moving_sample(variant_index, true).call("primary_color")
		if color.r <= color.g * 2.2 or color.r <= color.b * 1.8:
			return false
	return true


func debug_force_all_impacts(progress: float) -> void:
	for sample: Node2D in _samples:
		if sample.get_meta("moving", false):
			sample.call("debug_force_impact", progress)
	queue_redraw()


func debug_no_trail_residue() -> bool:
	for sample: Node2D in _samples:
		if int(sample.call("trail_sample_count")) != 0:
			return false
	return true


func debug_background_mode() -> int:
	return _background_mode


func _build_samples() -> void:
	for existing_sample: Node2D in _samples:
		if is_instance_valid(existing_sample):
			existing_sample.queue_free()
	_samples.clear()

	for variant_index in range(SAMPLE_SCRIPT.VARIANT_COUNT):
		var card_origin: Vector2 = _card_origin(variant_index)
		_add_sample(
			variant_index,
			SAMPLE_SCRIPT.TeamPalette.PLAYER_WHITE,
			card_origin + Vector2(112.0, 96.0),
			PLAYER_RADIUS,
			STATIC_SCALE,
			0.0,
			0.0,
			false
		)
		_add_sample(
			variant_index,
			SAMPLE_SCRIPT.TeamPalette.ENEMY_RED,
			card_origin + Vector2(286.0, 96.0),
			ENEMY_RADIUS,
			STATIC_SCALE,
			0.0,
			0.0,
			false
		)
		_add_sample(
			variant_index,
			SAMPLE_SCRIPT.TeamPalette.PLAYER_WHITE,
			card_origin + Vector2(LANE_START_X, 184.0),
			PLAYER_RADIUS,
			1.0,
			PLAYER_SPEED,
			LANE_END_X - LANE_START_X,
			true
		)
		_add_sample(
			variant_index,
			SAMPLE_SCRIPT.TeamPalette.ENEMY_RED,
			card_origin + Vector2(LANE_START_X, 232.0),
			ENEMY_RADIUS,
			1.0,
			ENEMY_SPEED,
			LANE_END_X - LANE_START_X,
			true
		)
	_apply_sample_toggles()


func _add_sample(
	variant_index: int,
	team_palette: int,
	sample_position: Vector2,
	hit_radius: float,
	preview_scale: float,
	speed: float,
	lane_length: float,
	moving: bool
) -> void:
	var sample: Node2D = SAMPLE_SCRIPT.new() as Node2D
	sample.position = sample_position
	sample.set_meta("variant_index", variant_index)
	sample.set_meta("team_palette", team_palette)
	sample.set_meta("moving", moving)
	add_child(sample)
	sample.call(
		"configure",
		variant_index,
		team_palette,
		hit_radius,
		preview_scale,
		speed,
		lane_length
	)
	_samples.append(sample)


func _apply_preview_time() -> void:
	for sample: Node2D in _samples:
		sample.call("set_preview_time", _preview_time)


func _apply_sample_toggles() -> void:
	for sample: Node2D in _samples:
		sample.call("set_hitbox_visible", _show_hitboxes)
		sample.call("set_trail_visible", _show_trails)


func _moving_sample(variant_index: int, enemy: bool) -> Node2D:
	var sample_offset: int = 3 if enemy else 2
	return _samples[variant_index * 4 + sample_offset]


func _variant_has_complete_samples(variant_index: int) -> bool:
	var static_player_count: int = 0
	var static_enemy_count: int = 0
	var moving_player_count: int = 0
	var moving_enemy_count: int = 0
	for sample: Node2D in _samples:
		if int(sample.get_meta("variant_index", -1)) != variant_index:
			continue
		var moving: bool = bool(sample.get_meta("moving", false))
		var enemy: bool = int(sample.get_meta("team_palette", -1)) == SAMPLE_SCRIPT.TeamPalette.ENEMY_RED
		if moving and enemy:
			moving_enemy_count += 1
		elif moving:
			moving_player_count += 1
		elif enemy:
			static_enemy_count += 1
		else:
			static_player_count += 1
	return (
		static_player_count == 1
		and static_enemy_count == 1
		and moving_player_count == 1
		and moving_enemy_count == 1
	)


func _card_origin(variant_index: int) -> Vector2:
	var column: int = variant_index % 3
	var row: int = variant_index / 3
	return CARD_START + Vector2(
		float(column) * (CARD_SIZE.x + CARD_GAP.x),
		float(row) * (CARD_SIZE.y + CARD_GAP.y)
	)


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
	if _background_mode == 0:
		return
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
		return
	for band_index in range(7):
		var band_y: float = 80.0 + float(band_index) * 110.0
		var band_color := Color(0.18, 0.08 + float(band_index) * 0.012, 0.24, 0.055)
		draw_circle(Vector2(180.0 + float(band_index % 3) * 430.0, band_y), 190.0, band_color)


func _draw_header() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(24.0, 35.0),
		"胶质子弹视觉候选 / JELLY BULLET VFX SELECTION",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		24,
		COLOR_ACCENT
	)
	draw_string(
		font,
		Vector2(24.0, 63.0),
		"同形红白配色 · 4× 静态特写 · 1× 实战速度飞行与命中",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		COLOR_TEXT_DIM
	)
	var state_text: String = "动态播放"
	if _paused:
		state_text = "已暂停"
	draw_string(
		font,
		Vector2(1065.0, 35.0),
		state_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		COLOR_ACCENT
	)
	draw_string(
		font,
		Vector2(1030.0, 61.0),
		"等待玩家人工选型",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		COLOR_TEXT_DIM
	)


func _draw_card(variant_index: int, origin: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var card_rect := Rect2(origin, CARD_SIZE)
	draw_rect(card_rect, COLOR_CARD, true)
	draw_rect(card_rect, COLOR_CARD_BORDER, false, 1.5)
	draw_string(
		font,
		origin + Vector2(16.0, 27.0),
		VARIANT_NAMES[variant_index],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		17,
		COLOR_TEXT
	)
	draw_string(
		font,
		origin + Vector2(69.0, 59.0),
		"人物白弹 4×",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		COLOR_PLAYER
	)
	draw_string(
		font,
		origin + Vector2(244.0, 59.0),
		"敌方红弹 4×",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		COLOR_ENEMY
	)
	draw_line(
		origin + Vector2(LANE_START_X, 184.0),
		origin + Vector2(LANE_END_X, 184.0),
		Color(1.0, 1.0, 1.0, 0.10),
		1.0
	)
	draw_line(
		origin + Vector2(LANE_START_X, 232.0),
		origin + Vector2(LANE_END_X, 232.0),
		Color(1.0, 0.20, 0.18, 0.12),
		1.0
	)
	draw_line(
		origin + Vector2(LANE_END_X, 166.0),
		origin + Vector2(LANE_END_X, 250.0),
		Color(0.45, 0.94, 0.80, 0.24),
		1.0
	)
	draw_string(
		font,
		origin + Vector2(16.0, 177.0),
		"白",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		COLOR_PLAYER
	)
	draw_string(
		font,
		origin + Vector2(16.0, 225.0),
		"红",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		COLOR_ENEMY
	)
	draw_string(
		font,
		origin + Vector2(16.0, 278.0),
		"WHITE  r8 / 520 px·s⁻¹     RED  r5 / 280 px·s⁻¹",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
		COLOR_TEXT_DIM
	)


func _draw_footer() -> void:
	var font: Font = ThemeDB.fallback_font
	var background_names: PackedStringArray = PackedStringArray(["纯暗", "低对比网格", "低饱和意识层"])
	var controls: String = (
		"[Space] 暂停  [R] 重置  [D] 判定圆  [T] 拖尾  [B] 背景：%s  [Esc] 返回"
		% background_names[_background_mode]
	)
	draw_string(
		font,
		Vector2(24.0, 742.0),
		controls,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		COLOR_TEXT_DIM
	)
	draw_string(
		font,
		Vector2(1035.0, 742.0),
		"请按编号选择",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		14,
		COLOR_ACCENT
	)
