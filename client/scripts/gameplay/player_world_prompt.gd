# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §3.2
class_name PlayerWorldPrompt
extends Node2D


const DISPLAY_DURATION: float = 1.2
const FADE_DURATION: float = 0.35
const VERTICAL_DRIFT: float = 14.0

var _base_position: Vector2 = Vector2.ZERO
var _label: Label = null
var _remaining: float = 0.0


func _ready() -> void:
	_base_position = position
	_label = get_node_or_null("Label") as Label
	if _label == null:
		push_error("[PlayerWorldPrompt] missing Label scene node")
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return
	_remaining = maxf(_remaining - scaled_delta, 0.0)
	_update_visual()
	if _remaining <= 0.0:
		dismiss()


func show_message(message: String) -> void:
	if _label == null or message.is_empty():
		return
	_label.text = message
	_remaining = DISPLAY_DURATION
	position = _base_position
	modulate = Color.WHITE
	visible = true
	set_process(true)


func dismiss() -> void:
	_remaining = 0.0
	position = _base_position
	modulate = Color.WHITE
	visible = false
	set_process(false)


func _update_visual() -> void:
	var elapsed_ratio: float = 1.0 - clampf(
		_remaining / DISPLAY_DURATION,
		0.0,
		1.0
	)
	position = _base_position + Vector2.UP * VERTICAL_DRIFT * elapsed_ratio
	var alpha: float = clampf(_remaining / FADE_DURATION, 0.0, 1.0)
	modulate = Color(1.0, 1.0, 1.0, alpha)
