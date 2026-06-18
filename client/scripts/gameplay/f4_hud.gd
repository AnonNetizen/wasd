# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §9.4
class_name F4Hud
extends CanvasLayer


var _life_label: Label = null
var _level_label: Label = null
var _kills_label: Label = null
var _xp_label: Label = null
var _time_label: Label = null
var _message_label: Label = null
var _current_life: float = 0.0
var _max_life: float = 0.0
var _kills: int = 0
var _level: int = 1
var _xp: int = 0
var _xp_required: int = 0


func _ready() -> void:
	_life_label = _make_label(Vector2(16.0, 14.0))
	_kills_label = _make_label(Vector2(16.0, 38.0))
	_time_label = _make_label(Vector2(16.0, 62.0))
	_level_label = _make_label(Vector2(16.0, 86.0))
	_xp_label = _make_label(Vector2(16.0, 110.0))
	_message_label = _make_label(Vector2(0.0, 150.0))
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_message_label.hide()
	add_child(_life_label)
	add_child(_kills_label)
	add_child(_time_label)
	add_child(_level_label)
	add_child(_xp_label)
	add_child(_message_label)
	_refresh_static_labels()


func _process(_delta: float) -> void:
	_time_label.text = "%s: %d" % [tr("ui_hud_time"), int(GameClock.now())]


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


func _make_label(offset: Vector2) -> Label:
	var label: Label = Label.new()
	label.offset_left = offset.x
	label.offset_top = offset.y
	label.add_theme_font_size_override("font_size", 18)
	return label


func _refresh_static_labels() -> void:
	set_life(_current_life, _max_life)
	set_kills(_kills)
	set_level(_level)
	set_xp(_xp, _xp_required)
