# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §9.4
class_name GameplayHud
extends CanvasLayer


const UPGRADE_FEEDBACK_DURATION: float = 1.35

var _life_label: Label = null
var _level_label: Label = null
var _kills_label: Label = null
var _xp_label: Label = null
var _time_label: Label = null
var _message_label: Label = null
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
	_upgrade_feedback_label = get_node_or_null("Root/UpgradeFeedbackLabel") as Label
	if _life_label == null or _kills_label == null or _time_label == null or _level_label == null or _xp_label == null:
		push_error("[GameplayHud] missing required scene nodes")
		return
	if _message_label == null or _upgrade_feedback_label == null:
		push_error("[GameplayHud] missing required scene nodes")
		return

	_message_label.hide()
	_upgrade_feedback_label.hide()
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_refresh_static_labels()


func _process(delta: float) -> void:
	_refresh_time_label()
	if _upgrade_feedback_remaining <= 0.0:
		return
	_upgrade_feedback_remaining = maxf(_upgrade_feedback_remaining - GameClock.delta_scaled(delta), 0.0)
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
	_upgrade_feedback_label.show()


func is_upgrade_feedback_visible() -> bool:
	return _upgrade_feedback_label != null and _upgrade_feedback_label.visible


func is_game_over_message_visible() -> bool:
	return _message_label != null and _message_label.visible


func _refresh_static_labels() -> void:
	set_life(_current_life, _max_life)
	set_kills(_kills)
	set_level(_level)
	set_xp(_xp, _xp_required)
	_refresh_time_label()
	if _upgrade_feedback_label.visible:
		_refresh_upgrade_feedback()


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


func _on_locale_changed(_locale: String) -> void:
	_refresh_static_labels()
