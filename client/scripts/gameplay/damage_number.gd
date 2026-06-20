# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F9-ContentDemoPolish.md
class_name DamageNumber
extends Node2D


const DEFEATED_COLOR: Color = Color(1.0, 0.72, 0.28)
const DURATION: float = 0.52
const PLAYER_DAMAGE_COLOR: Color = Color(1.0, 0.34, 0.30)
const TEXT_COLOR: Color = Color(1.0, 0.96, 0.72)
const VERTICAL_DRIFT: float = 28.0

var _label: Label = null
var _remaining: float = 0.0
var _start_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_label = get_node_or_null("Label") as Label
	if _label == null:
		push_error("[DamageNumber] missing Label scene node")
		return
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.04, 0.03, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.add_theme_font_size_override("font_size", 20)
	visible = false


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(_remaining - GameClock.delta_scaled(delta), 0.0)
	_update_visual()
	if _remaining <= 0.0:
		PoolManager.release(self)


func configure(spawn_position: Vector2, amount: float, defeated: bool, player_damage: bool) -> void:
	global_position = spawn_position
	_start_position = spawn_position
	_remaining = DURATION
	if _label != null:
		_label.text = str(int(ceilf(amount)))
		_label.add_theme_color_override("font_color", _text_color(defeated, player_damage))
	_update_visual()
	visible = true


func _pool_reset() -> void:
	_remaining = 0.0
	_start_position = Vector2.ZERO
	position = Vector2.ZERO
	scale = Vector2.ONE
	modulate = Color.WHITE
	visible = true
	if _label != null:
		_label.text = ""


func _pool_release() -> void:
	_remaining = 0.0
	visible = false


func _update_visual() -> void:
	var elapsed_ratio: float = 1.0 - clampf(_remaining / DURATION, 0.0, 1.0)
	global_position = _start_position + Vector2.UP * VERTICAL_DRIFT * elapsed_ratio
	var alpha: float = 1.0 - elapsed_ratio
	modulate = Color(1.0, 1.0, 1.0, alpha)
	scale = Vector2.ONE * lerpf(1.12, 0.92, elapsed_ratio)


func _text_color(defeated: bool, player_damage: bool) -> Color:
	if player_damage:
		return PLAYER_DAMAGE_COLOR
	if defeated:
		return DEFEATED_COLOR
	return TEXT_COLOR
