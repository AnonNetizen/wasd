class_name SteamLabBattleHud
extends Control

signal restart_requested()
signal leave_requested()

const HEART_RADIUS: float = 11.0
const HEART_SPACING: float = 30.0
const HEART_ORIGIN := Vector2(34.0, 34.0)
const BOSS_BAR_RECT := Rect2(Vector2(70.0, 14.0), Vector2(400.0, 14.0))

var _hp: int = 3
var _max_hp: int = 3
var _alive: bool = true
var _boss_hp: float = 0.0
var _boss_max_hp: float = 0.0
var _boss_visible: bool = false
var _is_authority: bool = true
var _game_over_visible: bool = false

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
	_create_labels()
	_create_game_over_panel()


func refresh(state: Dictionary) -> void:
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
	var active_item_name := String(active_item.get("name", "空"))
	var active_item_held := bool(active_item.get("held", false))
	_active_item_label.text = "Q %s" % active_item_name
	_active_item_label.add_theme_color_override(
		"font_color",
		Color(0.94, 1.0, 0.74, 0.96) if active_item_held else Color(0.58, 0.66, 0.62, 0.82)
	)
	_spectator_label.visible = not _alive and not bool(state.get("game_over", false))

	var game_over := bool(state.get("game_over", false))
	if game_over != _game_over_visible:
		_game_over_visible = game_over
		_game_over_panel.visible = game_over
		if game_over:
			_game_over_stats_label.text = "存活时间 %02d:%02d\nTier %d · 击破 Boss %d" % [
				total_seconds / 60,
				total_seconds % 60,
				int(state.get("tier", 0)),
				int(state.get("boss_kills", 0)),
			]
	_restart_button.visible = _is_authority
	queue_redraw()


func _draw() -> void:
	for index in range(_max_hp):
		var center := HEART_ORIGIN + Vector2(float(index) * HEART_SPACING, 0.0)
		if index < _hp:
			draw_circle(center, HEART_RADIUS, Color(0.94, 0.30, 0.34, 0.95))
			draw_circle(center, HEART_RADIUS * 0.55, Color(1.0, 0.62, 0.60, 0.85))
		else:
			draw_circle(center, HEART_RADIUS, Color(0.30, 0.30, 0.32, 0.65))
		draw_circle(center, HEART_RADIUS, Color(1.0, 0.86, 0.84, 0.85), false, 1.6, true)
	if _boss_visible:
		draw_rect(BOSS_BAR_RECT.grow(2.0), Color(0.06, 0.05, 0.06, 0.85), true)
		var fill_ratio := clampf(_boss_hp / _boss_max_hp, 0.0, 1.0)
		var fill_rect := Rect2(BOSS_BAR_RECT.position, Vector2(BOSS_BAR_RECT.size.x * fill_ratio, BOSS_BAR_RECT.size.y))
		draw_rect(fill_rect, Color(0.86, 0.24, 0.30, 0.95), true)
		draw_rect(BOSS_BAR_RECT.grow(2.0), Color(1.0, 0.66, 0.54, 0.9), false, 1.6)


func _create_labels() -> void:
	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.position = Vector2(244.0, 22.0)
	_time_label.add_theme_font_size_override("font_size", 20)
	_time_label.add_theme_color_override("font_color", Color(0.92, 0.98, 0.94, 0.95))
	add_child(_time_label)

	_tier_label = Label.new()
	_tier_label.name = "TierLabel"
	_tier_label.position = Vector2(444.0, 26.0)
	_tier_label.add_theme_font_size_override("font_size", 15)
	_tier_label.add_theme_color_override("font_color", Color(0.86, 0.92, 0.66, 0.92))
	add_child(_tier_label)

	_active_item_label = Label.new()
	_active_item_label.name = "ActiveItemLabel"
	_active_item_label.text = "Q 空"
	_active_item_label.position = Vector2(24.0, 56.0)
	_active_item_label.size = Vector2(210.0, 28.0)
	_active_item_label.add_theme_font_size_override("font_size", 15)
	_active_item_label.add_theme_color_override("font_color", Color(0.58, 0.66, 0.62, 0.82))
	add_child(_active_item_label)

	_spectator_label = Label.new()
	_spectator_label.name = "SpectatorLabel"
	_spectator_label.text = "观战中…"
	_spectator_label.position = Vector2(210.0, 120.0)
	_spectator_label.visible = false
	_spectator_label.add_theme_font_size_override("font_size", 22)
	_spectator_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92, 0.85))
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
	center.add_child(_game_over_panel)

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
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	rows.add_child(_restart_button)

	var leave_button := Button.new()
	leave_button.text = "离开"
	leave_button.custom_minimum_size = Vector2(0.0, 38.0)
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	rows.add_child(leave_button)
