# Doc: docs/代码/difficulty_marker.md
class_name DifficultyMarker
extends PanelContainer


const STAGE_NAME_KEYS: Array[String] = [
	"ui_difficulty_stage_dormant",
	"ui_difficulty_stage_alert",
	"ui_difficulty_stage_hunt",
	"ui_difficulty_stage_clash",
	"ui_difficulty_stage_siege",
	"ui_difficulty_stage_lethal",
	"ui_difficulty_stage_unbound",
	"ui_difficulty_stage_collapse",
	"ui_difficulty_stage_nestfall",
]
const STAGE_COLORS: Array[Color] = [
	Color(0.45, 0.78, 0.94),
	Color(0.58, 0.82, 0.48),
	Color(0.86, 0.82, 0.34),
	Color(0.98, 0.66, 0.25),
	Color(0.96, 0.46, 0.22),
	Color(0.94, 0.30, 0.27),
	Color(0.84, 0.26, 0.55),
	Color(0.67, 0.25, 0.72),
	Color(0.50, 0.20, 0.58),
]
const LOCKED_COLOR: Color = Color(0.50, 0.72, 0.90)
const HIGHLIGHT_SCALE: Vector2 = Vector2(1.035, 1.035)
const HIGHLIGHT_DURATION: float = 0.22

var _combat_locked: bool = false
var _highlight_tween: Tween = null
var _last_level: int = 0
var _level_label: Label = null
var _lock_label: Label = null
var _panel_style: StyleBoxFlat = null
var _progress_bar: ProgressBar = null
var _progress_fill_style: StyleBoxFlat = null
var _snapshot: Dictionary = {}
var _stage_label: Label = null
var _time_label: Label = null


func _ready() -> void:
	_time_label = get_node_or_null("Margin/Layout/Header/TimeLabel") as Label
	_level_label = get_node_or_null("Margin/Layout/Header/LevelLabel") as Label
	_stage_label = get_node_or_null("Margin/Layout/StageLabel") as Label
	_progress_bar = get_node_or_null("Margin/Layout/ProgressBar") as ProgressBar
	_lock_label = get_node_or_null("Margin/Layout/LockLabel") as Label
	if (
		_time_label == null
		or _level_label == null
		or _stage_label == null
		or _progress_bar == null
		or _lock_label == null
	):
		push_error("[DifficultyMarker] missing required scene nodes")
		return
	var panel_style: StyleBox = get_theme_stylebox("panel")
	if panel_style is StyleBoxFlat:
		_panel_style = panel_style.duplicate() as StyleBoxFlat
		add_theme_stylebox_override("panel", _panel_style)
	var progress_fill: StyleBox = _progress_bar.get_theme_stylebox("fill")
	if progress_fill is StyleBoxFlat:
		_progress_fill_style = progress_fill.duplicate() as StyleBoxFlat
		_progress_bar.add_theme_stylebox_override("fill", _progress_fill_style)
	pivot_offset = size * 0.5
	_refresh_content()
	_apply_stage_style(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size * 0.5


func set_snapshot(snapshot: Dictionary, combat_locked: bool) -> void:
	var next_level: int = maxi(int(snapshot.get("difficulty_level", 1)), 1)
	var level_changed: bool = _last_level > 0 and next_level != _last_level
	var lock_changed: bool = combat_locked != _combat_locked
	_snapshot = snapshot.duplicate(true)
	_combat_locked = combat_locked
	_refresh_content()
	if _last_level == 0 or level_changed or lock_changed:
		_apply_stage_style(level_changed)
	_last_level = next_level


func refresh_locale() -> void:
	_refresh_content()


func _refresh_content() -> void:
	if (
		_time_label == null
		or _level_label == null
		or _stage_label == null
		or _progress_bar == null
		or _lock_label == null
	):
		return
	var elapsed_seconds: float = maxf(float(_snapshot.get("elapsed", 0.0)), 0.0)
	var difficulty_level: int = maxi(int(_snapshot.get("difficulty_level", 1)), 1)
	var stage_name_key: String = String(_snapshot.get("name_key", ""))
	if stage_name_key.is_empty():
		stage_name_key = STAGE_NAME_KEYS[mini(difficulty_level - 1, STAGE_NAME_KEYS.size() - 1)]
	_time_label.text = _format_elapsed(elapsed_seconds)
	_level_label.text = tr("ui_difficulty_level").format({"level": difficulty_level})
	_stage_label.text = tr(stage_name_key)
	_progress_bar.value = clampf(float(_snapshot.get("progress", 0.0)), 0.0, 1.0) * 100.0
	_lock_label.text = tr("ui_difficulty_paused_combat_locked")
	_lock_label.visible = _combat_locked


func _apply_stage_style(play_highlight: bool) -> void:
	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()
	_highlight_tween = null
	scale = Vector2.ONE
	var difficulty_level: int = maxi(int(_snapshot.get("difficulty_level", 1)), 1)
	var stage_index: int = mini(difficulty_level - 1, STAGE_COLORS.size() - 1)
	var stage_color: Color = LOCKED_COLOR if _combat_locked else STAGE_COLORS[stage_index]
	_stage_label.add_theme_color_override("font_color", stage_color)
	_level_label.add_theme_color_override("font_color", stage_color)
	if _progress_fill_style != null:
		_progress_fill_style.bg_color = stage_color
	if _panel_style != null:
		_panel_style.border_color = stage_color
		_set_border_width(2)
	if not play_highlight:
		return
	_play_highlight(stage_color)


func _play_highlight(stage_color: Color) -> void:
	if _highlight_tween != null and _highlight_tween.is_valid():
		_highlight_tween.kill()
	scale = Vector2.ONE
	if _panel_style != null:
		_panel_style.border_color = stage_color.lightened(0.26)
		_set_border_width(3)
	_highlight_tween = create_tween()
	_highlight_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_highlight_tween.tween_property(
		self,
		"scale",
		HIGHLIGHT_SCALE,
		HIGHLIGHT_DURATION * 0.42
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_highlight_tween.tween_property(
		self,
		"scale",
		Vector2.ONE,
		HIGHLIGHT_DURATION * 0.58
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_highlight_tween.tween_callback(_finish_highlight.bind(stage_color))


func _finish_highlight(stage_color: Color) -> void:
	_highlight_tween = null
	scale = Vector2.ONE
	if _panel_style != null:
		_panel_style.border_color = stage_color
		_set_border_width(2)


func _set_border_width(width: int) -> void:
	if _panel_style == null:
		return
	_panel_style.border_width_left = width
	_panel_style.border_width_top = width
	_panel_style.border_width_right = width
	_panel_style.border_width_bottom = width


func _format_elapsed(elapsed_seconds: float) -> String:
	var whole_seconds: int = maxi(int(floor(elapsed_seconds)), 0)
	return "%02d:%02d" % [floori(float(whole_seconds) / 60.0), whole_seconds % 60]
