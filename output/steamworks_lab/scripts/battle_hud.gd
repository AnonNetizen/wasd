class_name SteamLabBattleHud
extends Control

signal restart_requested()
signal leave_requested()

const UI_STYLE_SCRIPT := preload("res://scripts/ui_style.gd")

const HEART_RADIUS: float = 11.0
const HEART_SPACING: float = 30.0
const HEART_ORIGIN := Vector2(34.0, 34.0)
const BOSS_BAR_RECT := Rect2(Vector2(70.0, 14.0), Vector2(400.0, 14.0))
const ACTIVE_SLOT_RECT := Rect2(Vector2(24.0, 62.0), Vector2(238.0, 32.0))
const ACTIVE_KEY_RECT := Rect2(Vector2(31.0, 68.0), Vector2(32.0, 20.0))
const ACTIVE_ICON_RECT := Rect2(Vector2(70.0, 67.0), Vector2(24.0, 22.0))

var _hp: int = 3
var _max_hp: int = 3
var _alive: bool = true
var _active_item_id: int = -1
var _active_item_name: String = "空"
var _active_item_held: bool = false
var _active_item_color: Color = Color(0.58, 0.66, 0.62, 0.82)
var _boss_hp: float = 0.0
var _boss_max_hp: float = 0.0
var _boss_visible: bool = false
var _is_authority: bool = true
var _game_over_visible: bool = false
var _hp_flash: float = 0.0
var _active_slot_flash: float = 0.0
var _boss_flash: float = 0.0
var _hud_tweens: Dictionary = {}

var _time_label: Label
var _tier_label: Label
var _active_item_label: Label
var _spectator_label: Label
var _game_over_panel: PanelContainer
var _game_over_stats_label: Label
var _restart_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	_create_labels()
	_create_game_over_panel()


func _process(delta: float) -> void:
	if _hp_flash <= 0.0 and _active_slot_flash <= 0.0 and _boss_flash <= 0.0:
		return
	_hp_flash = maxf(0.0, _hp_flash - delta * 3.6)
	_active_slot_flash = maxf(0.0, _active_slot_flash - delta * 3.0)
	_boss_flash = maxf(0.0, _boss_flash - delta * 4.2)
	queue_redraw()


func refresh(state: Dictionary) -> void:
	var previous_hp := _hp
	var previous_active_id := _active_item_id
	var previous_active_held := _active_item_held
	var previous_boss_hp := _boss_hp
	var previous_boss_visible := _boss_visible

	_hp = int(state.get("hp", 0))
	_max_hp = int(state.get("max_hp", 3))
	_alive = bool(state.get("alive", true))
	_is_authority = bool(state.get("authority", true))
	var boss: Dictionary = state.get("boss", {})
	_boss_visible = not boss.is_empty()
	_boss_hp = float(boss.get("hp", 0.0))
	_boss_max_hp = maxf(float(boss.get("max_hp", 1.0)), 1.0)

	var total_seconds := int(state.get("time", 0.0))
	_time_label.text = "%02d:%02d" % [total_seconds / 60, total_seconds % 60]
	_tier_label.text = "Tier %d" % int(state.get("tier", 0))
	var active_item: Dictionary = state.get("active_item", {})
	_active_item_id = int(active_item.get("id", -1))
	_active_item_name = String(active_item.get("name", "空"))
	_active_item_held = bool(active_item.get("held", false))
	var raw_active_item_color: Variant = active_item.get("color", Color(0.58, 0.66, 0.62, 0.82))
	_active_item_color = raw_active_item_color if raw_active_item_color is Color else Color(0.58, 0.66, 0.62, 0.82)
	_active_item_label.text = _active_item_name
	_active_item_label.add_theme_color_override(
		"font_color",
		Color(0.96, 1.0, 0.70, 0.98) if _active_item_held else UI_STYLE_SCRIPT.MUTED_TEXT_COLOR
	)
	_spectator_label.visible = not _alive and not bool(state.get("game_over", false))

	var game_over := bool(state.get("game_over", false))
	if game_over != _game_over_visible:
		if game_over:
			_game_over_stats_label.text = "存活时间 %02d:%02d\nTier %d · 击破 Boss %d" % [
				total_seconds / 60,
				total_seconds % 60,
				int(state.get("tier", 0)),
				int(state.get("boss_kills", 0)),
			]
		_set_game_over_visible(game_over)
	_restart_button.visible = _is_authority

	if _hp != previous_hp:
		_hp_flash = 1.0
		_pulse_control(_time_label, 1.08)
	if _active_item_id != previous_active_id or _active_item_held != previous_active_held:
		_active_slot_flash = 1.0
		_pulse_control(_active_item_label, 1.10)
	if _boss_visible != previous_boss_visible or (_boss_visible and _boss_hp < previous_boss_hp):
		_boss_flash = 1.0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2(18.0, 18.0), Vector2(250.0, 84.0)), Color(0.0, 0.0, 0.0, 0.18), true)
	for index in range(_max_hp):
		var center := HEART_ORIGIN + Vector2(float(index) * HEART_SPACING, 0.0)
		if index < _hp:
			var flash := _hp_flash * 0.20
			draw_circle(center, HEART_RADIUS + _hp_flash * 1.6, Color(1.0, 0.38 + flash, 0.34, 0.95))
			draw_circle(center, HEART_RADIUS * 0.55, Color(1.0, 0.70, 0.58, 0.86))
		else:
			draw_circle(center, HEART_RADIUS, Color(0.16, 0.20, 0.19, 0.72))
		draw_circle(center, HEART_RADIUS + _hp_flash * 1.6, Color(1.0, 0.86, 0.74, 0.85), false, 1.6, true)

	var slot_fill := Color(0.030, 0.046, 0.046, 0.88)
	var slot_edge := Color(0.24, 0.48, 0.42, 0.74)
	if _active_item_held:
		slot_fill = Color(0.080, 0.180, 0.120, 0.94).lerp(Color(0.18, 0.42, 0.20, 0.98), _active_slot_flash)
		slot_edge = UI_STYLE_SCRIPT.SLIME_COLOR.lerp(UI_STYLE_SCRIPT.AMBER_COLOR, _active_slot_flash * 0.55)
	_draw_capsule(ACTIVE_SLOT_RECT, slot_fill, slot_edge, 2.0)
	_draw_capsule(ACTIVE_KEY_RECT, Color(0.0, 0.0, 0.0, 0.35), UI_STYLE_SCRIPT.AMBER_COLOR, 1.4)
	_draw_active_item_icon(ACTIVE_ICON_RECT, _active_item_id, _active_item_color if _active_item_held else UI_STYLE_SCRIPT.MUTED_TEXT_COLOR, _active_item_held)
	var font := get_theme_default_font()
	_draw_centered_text(font, "Q", ACTIVE_KEY_RECT.get_center() + Vector2(0.0, -1.0), 15, Color(1.0, 0.88, 0.40, 1.0))

	if _boss_visible:
		draw_rect(BOSS_BAR_RECT.grow(2.0), Color(0.06, 0.05, 0.06, 0.85), true)
		var fill_ratio := clampf(_boss_hp / _boss_max_hp, 0.0, 1.0)
		var fill_rect := Rect2(BOSS_BAR_RECT.position, Vector2(BOSS_BAR_RECT.size.x * fill_ratio, BOSS_BAR_RECT.size.y))
		var fill_color := Color(0.86, 0.24, 0.30, 0.95).lerp(Color(1.0, 0.82, 0.34, 0.98), _boss_flash)
		draw_rect(fill_rect, fill_color, true)
		draw_rect(BOSS_BAR_RECT.grow(2.0), Color(1.0, 0.66 + _boss_flash * 0.24, 0.54, 0.9), false, 1.8)


func _draw_capsule(rect: Rect2, fill_color: Color, outline_color: Color, outline_width: float) -> void:
	var radius := rect.size.y * 0.5
	var left_center := rect.position + Vector2(radius, radius)
	var right_center := rect.position + Vector2(rect.size.x - radius, radius)
	draw_rect(Rect2(rect.position + Vector2(radius, 0.0), Vector2(rect.size.x - radius * 2.0, rect.size.y)), fill_color, true)
	draw_circle(left_center, radius, fill_color)
	draw_circle(right_center, radius, fill_color)
	draw_line(rect.position + Vector2(radius, 0.0), rect.position + Vector2(rect.size.x - radius, 0.0), outline_color, outline_width)
	draw_line(rect.position + Vector2(radius, rect.size.y), rect.position + Vector2(rect.size.x - radius, rect.size.y), outline_color, outline_width)
	draw_arc(left_center, radius, PI * 0.5, PI * 1.5, 16, outline_color, outline_width, true)
	draw_arc(right_center, radius, PI * -0.5, PI * 0.5, 16, outline_color, outline_width, true)


func _draw_active_item_icon(rect: Rect2, item_id: int, item_color: Color, held: bool) -> void:
	var center := rect.get_center()
	var dim_color := Color(0.06, 0.08, 0.08, 0.78)
	var base_color := item_color if held else UI_STYLE_SCRIPT.MUTED_TEXT_COLOR
	var edge_color := Color(1.0, 1.0, 0.80, 0.88) if held else Color(0.34, 0.42, 0.38, 0.72)
	draw_circle(center, rect.size.x * 0.52, dim_color)
	draw_circle(center, rect.size.x * 0.47, Color(base_color, 0.24 if held else 0.12))
	draw_circle(center, rect.size.x * 0.52, edge_color, false, 1.4, true)
	if not held:
		draw_line(center + Vector2(-5.0, 0.0), center + Vector2(5.0, 0.0), Color(edge_color, 0.70), 1.6, true)
		return

	match item_id:
		0:
			_draw_repair_icon(center, base_color)
		1:
			_draw_clear_icon(center, base_color)
		2:
			_draw_stasis_icon(center, base_color)
		3:
			_draw_overload_icon(center, base_color)
		4:
			_draw_shield_icon(center, base_color)
		_:
			draw_circle(center, 4.0, base_color)


func _draw_repair_icon(center: Vector2, color: Color) -> void:
	draw_line(center + Vector2(-6.0, 0.0), center + Vector2(6.0, 0.0), color, 3.0, true)
	draw_line(center + Vector2(0.0, -6.0), center + Vector2(0.0, 6.0), color, 3.0, true)


func _draw_clear_icon(center: Vector2, color: Color) -> void:
	draw_circle(center, 4.0, color)
	draw_circle(center, 8.0, Color(color, 0.68), false, 1.5, true)
	for index in range(8):
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / 8.0)
		draw_line(center + direction * 5.0, center + direction * 9.0, color, 1.4, true)


func _draw_stasis_icon(center: Vector2, color: Color) -> void:
	for index in range(3):
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / 3.0)
		draw_line(center - direction * 7.0, center + direction * 7.0, color, 1.6, true)
	draw_circle(center, 2.4, Color(0.90, 1.0, 1.0, 0.96))


func _draw_overload_icon(center: Vector2, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(-1.0, -8.0),
		center + Vector2(6.0, -2.0),
		center + Vector2(1.5, -1.0),
		center + Vector2(3.0, 8.0),
		center + Vector2(-6.0, 1.0),
		center + Vector2(-1.5, 0.0),
	])
	draw_colored_polygon(points, color)


func _draw_shield_icon(center: Vector2, color: Color) -> void:
	var points := PackedVector2Array([
		center + Vector2(0.0, -8.0),
		center + Vector2(7.0, -4.0),
		center + Vector2(5.0, 5.0),
		center + Vector2(0.0, 9.0),
		center + Vector2(-5.0, 5.0),
		center + Vector2(-7.0, -4.0),
		center + Vector2(0.0, -8.0),
	])
	draw_polyline(points, color, 2.0, true)
	draw_line(center + Vector2(0.0, -5.0), center + Vector2(0.0, 5.0), Color(color, 0.74), 1.2, true)


func _draw_centered_text(font: Font, text: String, center: Vector2, font_size: int, color: Color) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(
		font,
		center + Vector2(text_size.x * -0.5, text_size.y * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


func _refresh_control_pivot(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5


func _pulse_control(control: Control, peak_scale: float) -> void:
	if control == null or not is_instance_valid(control):
		return
	_refresh_control_pivot(control)
	var key := control.get_instance_id()
	var previous_tween := _hud_tweens.get(key) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	var tween := create_tween()
	_hud_tweens[key] = tween
	tween.tween_property(control, "scale", Vector2(peak_scale, peak_scale), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_game_over_visible(visible_now: bool) -> void:
	_game_over_visible = visible_now
	var key := _game_over_panel.get_instance_id()
	var previous_tween := _hud_tweens.get(key) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()

	if visible_now:
		_game_over_panel.visible = true
		_game_over_panel.modulate.a = 0.0
		_game_over_panel.scale = Vector2(0.92, 0.92)
		_refresh_control_pivot(_game_over_panel)
		var tween := create_tween()
		_hud_tweens[key] = tween
		tween.set_parallel(true)
		tween.tween_property(_game_over_panel, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(_game_over_panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return

	var tween := create_tween()
	_hud_tweens[key] = tween
	tween.set_parallel(true)
	tween.tween_property(_game_over_panel, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_game_over_panel, "scale", Vector2(0.96, 0.96), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: _game_over_panel.visible = false)


func _create_labels() -> void:
	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.position = Vector2(244.0, 22.0)
	_time_label.add_theme_font_size_override("font_size", 22)
	_time_label.add_theme_color_override("font_color", Color(0.94, 1.0, 0.88, 0.98))
	_time_label.add_theme_constant_override("outline_size", 3)
	_time_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.62))
	add_child(_time_label)
	_time_label.resized.connect(_refresh_control_pivot.bind(_time_label))

	_tier_label = Label.new()
	_tier_label.name = "TierLabel"
	_tier_label.position = Vector2(444.0, 26.0)
	_tier_label.add_theme_font_size_override("font_size", 15)
	_tier_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.AMBER_COLOR)
	add_child(_tier_label)

	_active_item_label = Label.new()
	_active_item_label.name = "ActiveItemLabel"
	_active_item_label.text = "空"
	_active_item_label.position = Vector2(104.0, 66.0)
	_active_item_label.size = Vector2(146.0, 24.0)
	_active_item_label.add_theme_font_size_override("font_size", 15)
	_active_item_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.MUTED_TEXT_COLOR)
	add_child(_active_item_label)
	_active_item_label.resized.connect(_refresh_control_pivot.bind(_active_item_label))

	_spectator_label = Label.new()
	_spectator_label.name = "SpectatorLabel"
	_spectator_label.text = "观战中…"
	_spectator_label.position = Vector2(210.0, 120.0)
	_spectator_label.visible = false
	_spectator_label.add_theme_font_size_override("font_size", 22)
	_spectator_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92, 0.85))
	_spectator_label.add_theme_constant_override("outline_size", 4)
	_spectator_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.64))
	add_child(_spectator_label)


func _create_game_over_panel() -> void:
	var center := CenterContainer.new()
	center.name = "GameOverCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_game_over_panel = PanelContainer.new()
	_game_over_panel.name = "GameOverPanel"
	_game_over_panel.custom_minimum_size = Vector2(340.0, 260.0)
	_game_over_panel.visible = false
	UI_STYLE_SCRIPT.apply_panel(_game_over_panel, "danger")
	center.add_child(_game_over_panel)
	_game_over_panel.resized.connect(_refresh_control_pivot.bind(_game_over_panel))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_game_over_panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "全员阵亡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.52, 0.44, 0.98))
	rows.add_child(title)

	_game_over_stats_label = Label.new()
	_game_over_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_stats_label.add_theme_font_size_override("font_size", 16)
	rows.add_child(_game_over_stats_label)

	_restart_button = Button.new()
	_restart_button.text = "再来一局"
	_restart_button.custom_minimum_size = Vector2(0.0, 42.0)
	UI_STYLE_SCRIPT.apply_button(_restart_button, true)
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	rows.add_child(_restart_button)

	var leave_button := Button.new()
	leave_button.text = "离开"
	leave_button.custom_minimum_size = Vector2(0.0, 38.0)
	UI_STYLE_SCRIPT.apply_button(leave_button)
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	rows.add_child(leave_button)
