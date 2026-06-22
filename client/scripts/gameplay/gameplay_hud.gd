# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §9.4
class_name GameplayHud
extends CanvasLayer


const UPGRADE_FEEDBACK_DURATION: float = 1.35
const UPGRADE_FEEDBACK_FADE_RATIO: float = 0.36
const UPGRADE_FEEDBACK_TEXT_COLOR: Color = Color(1.0, 0.82, 0.28)
const UPGRADE_FEEDBACK_TEXT_SHADOW_COLOR: Color = Color(0.05, 0.04, 0.03, 0.92)
const STATS_PANEL_ROWS: Array[Dictionary] = [
	{"key": "life", "label_key": "ui_stats_life"},
	{"key": "level", "label_key": "ui_stats_level"},
	{"key": "xp", "label_key": "ui_stats_xp"},
	{"key": "kills", "label_key": "ui_stats_kills"},
	{"key": "run_time", "label_key": "ui_stats_run_time"},
	{"key": "damage", "label_key": "ui_stats_damage"},
	{"key": "fire_rate", "label_key": "ui_stats_fire_rate"},
	{"key": "move_speed", "label_key": "ui_stats_move_speed"},
	{"key": "bullet_speed", "label_key": "ui_stats_bullet_speed"},
	{"key": "bullet_range", "label_key": "ui_stats_bullet_range"},
	{"key": "bullet_count", "label_key": "ui_stats_bullet_count"},
	{"key": "pierce_count", "label_key": "ui_stats_pierce_count"},
	{"key": "crit_chance", "label_key": "ui_stats_crit_chance"},
	{"key": "crit_mult", "label_key": "ui_stats_crit_mult"},
	{"key": "pickup_range", "label_key": "ui_stats_pickup_range"},
	{"key": "luck", "label_key": "ui_stats_luck"},
	{"key": "skill_resource", "label_key": "ui_stats_skill_resource"},
	{"key": "skill_cooldown", "label_key": "ui_stats_skill_cooldown"},
]

var _life_label: Label = null
var _level_label: Label = null
var _kills_label: Label = null
var _xp_label: Label = null
var _time_label: Label = null
var _message_label: Label = null
var _stats_grid: GridContainer = null
var _stats_label_labels: Dictionary = {}
var _stats_panel: PanelContainer = null
var _stats_title_label: Label = null
var _stats_values: Dictionary = {}
var _stats_value_labels: Dictionary = {}
var _upgrade_feedback_label: Label = null
var _upgrade_feedback_remaining: float = 0.0
var _last_upgrade_name_key: String = ""
var _current_life: float = 0.0
var _max_life: float = 0.0
var _kills: int = 0
var _level: int = 1
var _xp: int = 0
var _xp_required: int = 0


func _ready() -> void:
	_life_label = get_node_or_null("Root/Margin/Layout/LifeLabel") as Label
	_kills_label = get_node_or_null("Root/Margin/Layout/KillsLabel") as Label
	_time_label = get_node_or_null("Root/Margin/Layout/TimeLabel") as Label
	_level_label = get_node_or_null("Root/Margin/Layout/LevelLabel") as Label
	_xp_label = get_node_or_null("Root/Margin/Layout/XpLabel") as Label
	_message_label = get_node_or_null("Root/MessageLabel") as Label
	_stats_panel = get_node_or_null("Root/StatsPanel") as PanelContainer
	_stats_title_label = get_node_or_null("Root/StatsPanel/Margin/Layout/TitleLabel") as Label
	_stats_grid = get_node_or_null("Root/StatsPanel/Margin/Layout/StatsGrid") as GridContainer
	_upgrade_feedback_label = get_node_or_null("Root/UpgradeFeedbackLabel") as Label
	if _life_label == null or _kills_label == null or _time_label == null or _level_label == null or _xp_label == null:
		push_error("[GameplayHud] missing required scene nodes")
		return
	if _message_label == null or _upgrade_feedback_label == null or _stats_panel == null or _stats_title_label == null or _stats_grid == null:
		push_error("[GameplayHud] missing required scene nodes")
		return

	_message_label.hide()
	_stats_panel.hide()
	_build_stats_panel_rows()
	_upgrade_feedback_label.hide()
	_configure_upgrade_feedback_style()
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_refresh_static_labels()


func _process(delta: float) -> void:
	_refresh_time_label()
	if _upgrade_feedback_remaining <= 0.0:
		return
	_upgrade_feedback_remaining = maxf(_upgrade_feedback_remaining - GameClock.delta_scaled(delta), 0.0)
	_update_upgrade_feedback_visual()
	if _upgrade_feedback_remaining <= 0.0:
		_upgrade_feedback_label.hide()


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func set_life(current_life: float, max_life: float) -> void:
	_current_life = current_life
	_max_life = max_life
	_life_label.text = "%s: %d/%d" % [tr("ui_hud_life"), int(ceilf(_current_life)), int(ceilf(_max_life))]


func set_kills(kills: int) -> void:
	_kills = kills
	_kills_label.text = "%s: %d" % [tr("ui_hud_kills"), _kills]


func set_level(level: int) -> void:
	_level = level
	_level_label.text = "%s: %d" % [tr("ui_hud_level"), _level]


func set_xp(xp: int, xp_required: int) -> void:
	_xp = xp
	_xp_required = xp_required
	_xp_label.text = "%s: %d/%d" % [tr("ui_hud_xp"), _xp, _xp_required]


func show_game_over() -> void:
	_message_label.hide()


func show_upgrade_feedback(name_key: String) -> void:
	_last_upgrade_name_key = name_key
	_refresh_upgrade_feedback()
	_upgrade_feedback_remaining = UPGRADE_FEEDBACK_DURATION
	_update_upgrade_feedback_visual()
	_upgrade_feedback_label.show()


func is_upgrade_feedback_visible() -> bool:
	return _upgrade_feedback_label != null and _upgrade_feedback_label.visible


func is_game_over_message_visible() -> bool:
	return _message_label != null and _message_label.visible


func set_stats_panel_visible(is_visible: bool) -> void:
	if _stats_panel == null:
		return
	_stats_panel.visible = is_visible
	if is_visible:
		_refresh_stats_panel()


func set_detailed_stats(stats: Dictionary) -> void:
	_stats_values = stats.duplicate(true)
	if _stats_panel != null and _stats_panel.visible:
		_refresh_stats_panel()


func is_stats_panel_visible() -> bool:
	return _stats_panel != null and _stats_panel.visible


func _refresh_static_labels() -> void:
	set_life(_current_life, _max_life)
	set_kills(_kills)
	set_level(_level)
	set_xp(_xp, _xp_required)
	_refresh_time_label()
	if _upgrade_feedback_label.visible:
		_refresh_upgrade_feedback()
	_refresh_stats_panel()


func _refresh_time_label() -> void:
	if _time_label == null:
		return
	_time_label.text = "%s: %d" % [tr("ui_hud_time"), int(GameClock.now())]


func _refresh_upgrade_feedback() -> void:
	if _upgrade_feedback_label == null:
		return
	_upgrade_feedback_label.text = tr("ui_upgrade_applied").format({
		"name": tr(_last_upgrade_name_key),
	})


func _configure_upgrade_feedback_style() -> void:
	_upgrade_feedback_label.add_theme_color_override("font_color", UPGRADE_FEEDBACK_TEXT_COLOR)
	_upgrade_feedback_label.add_theme_color_override("font_shadow_color", UPGRADE_FEEDBACK_TEXT_SHADOW_COLOR)
	_upgrade_feedback_label.add_theme_constant_override("shadow_offset_x", 2)
	_upgrade_feedback_label.add_theme_constant_override("shadow_offset_y", 2)
	_upgrade_feedback_label.modulate = Color.WHITE


func _build_stats_panel_rows() -> void:
	_stats_label_labels.clear()
	_stats_value_labels.clear()
	for child: Node in _stats_grid.get_children():
		child.queue_free()
	for row: Dictionary in STATS_PANEL_ROWS:
		var row_key: String = String(row["key"])
		var label: Label = Label.new()
		label.name = "%sLabel" % row_key.to_pascal_case()
		label.custom_minimum_size = Vector2(180.0, 0.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.theme_type_variation = "Label"
		_stats_grid.add_child(label)
		_stats_label_labels[row_key] = label

		var value_label: Label = Label.new()
		value_label.name = "%sValueLabel" % row_key.to_pascal_case()
		value_label.custom_minimum_size = Vector2(150.0, 0.0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_stats_grid.add_child(value_label)
		_stats_value_labels[row_key] = value_label
	_refresh_stats_panel()


func _refresh_stats_panel() -> void:
	if _stats_title_label == null or _stats_grid == null:
		return
	_stats_title_label.text = tr("ui_stats_panel_title")
	for row: Dictionary in STATS_PANEL_ROWS:
		var row_key: String = String(row["key"])
		var label: Label = _stats_label_labels.get(row_key) as Label
		var value_label: Label = _stats_value_labels.get(row_key) as Label
		if label != null:
			label.text = tr(String(row["label_key"]))
		if value_label != null:
			value_label.text = String(_stats_values.get(row_key, "-"))


func _update_upgrade_feedback_visual() -> void:
	if _upgrade_feedback_label == null:
		return
	var remaining_ratio: float = clampf(_upgrade_feedback_remaining / UPGRADE_FEEDBACK_DURATION, 0.0, 1.0)
	var alpha: float = 1.0
	if remaining_ratio < UPGRADE_FEEDBACK_FADE_RATIO:
		alpha = remaining_ratio / UPGRADE_FEEDBACK_FADE_RATIO
	_upgrade_feedback_label.modulate = Color(1.0, 1.0, 1.0, alpha)


func _on_locale_changed(_locale: String) -> void:
	_refresh_static_labels()
