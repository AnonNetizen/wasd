# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §9.4
class_name F4Hud
extends CanvasLayer


const HUD_MARGIN: int = 24
const HUD_SEPARATION: int = 6
const MESSAGE_TOP_MARGIN: int = 140
const UPGRADE_FEEDBACK_DURATION: float = 1.35
const UPGRADE_FEEDBACK_TOP_MARGIN: int = 250

var _life_label: Label = null
var _level_label: Label = null
var _kills_label: Label = null
var _xp_label: Label = null
var _time_label: Label = null
var _message_label: Label = null
var _upgrade_feedback_label: Label = null
var _upgrade_feedback_remaining: float = 0.0
var _current_life: float = 0.0
var _max_life: float = 0.0
var _kills: int = 0
var _level: int = 1
var _xp: int = 0
var _xp_required: int = 0


func _ready() -> void:
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", HUD_MARGIN)
	margin.add_theme_constant_override("margin_top", HUD_MARGIN)
	margin.add_theme_constant_override("margin_right", HUD_MARGIN)
	margin.add_theme_constant_override("margin_bottom", HUD_MARGIN)
	root.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", HUD_SEPARATION)
	layout.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	layout.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(layout)

	_life_label = _make_label()
	_kills_label = _make_label()
	_time_label = _make_label()
	_level_label = _make_label()
	_xp_label = _make_label()
	layout.add_child(_life_label)
	layout.add_child(_kills_label)
	layout.add_child(_time_label)
	layout.add_child(_level_label)
	layout.add_child(_xp_label)

	_message_label = _make_label()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message_label.offset_top = MESSAGE_TOP_MARGIN
	_message_label.hide()
	root.add_child(_message_label)

	_upgrade_feedback_label = _make_label()
	_upgrade_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_upgrade_feedback_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_upgrade_feedback_label.offset_top = UPGRADE_FEEDBACK_TOP_MARGIN
	_upgrade_feedback_label.hide()
	root.add_child(_upgrade_feedback_label)
	_refresh_static_labels()


func _process(delta: float) -> void:
	_time_label.text = "%s: %d" % [tr("ui_hud_time"), int(GameClock.now())]
	if _upgrade_feedback_remaining <= 0.0:
		return
	_upgrade_feedback_remaining = maxf(_upgrade_feedback_remaining - GameClock.delta_scaled(delta), 0.0)
	if _upgrade_feedback_remaining <= 0.0:
		_upgrade_feedback_label.hide()


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
	_message_label.text = "%s\n%s" % [tr("ui_game_over"), tr("ui_restart_hint")]
	_message_label.show()


func show_upgrade_feedback(name_key: String) -> void:
	_upgrade_feedback_label.text = tr("ui_upgrade_applied").format({
		"name": tr(name_key),
	})
	_upgrade_feedback_remaining = UPGRADE_FEEDBACK_DURATION
	_upgrade_feedback_label.show()


func is_upgrade_feedback_visible() -> bool:
	return _upgrade_feedback_label != null and _upgrade_feedback_label.visible


func _make_label() -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", 24)
	return label


func _refresh_static_labels() -> void:
	set_life(_current_life, _max_life)
	set_kills(_kills)
	set_level(_level)
	set_xp(_xp, _xp_required)
