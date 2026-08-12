# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5, docs/决策记录.md ADR #199
class_name TeleportFadeOverlay
extends CanvasLayer


signal transition_finished(succeeded: bool)

var _transitioning: bool = false
var _tween: Tween = null

@onready var _blackout: ColorRect = get_node_or_null("Blackout") as ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _blackout == null:
		push_error("[TeleportFadeOverlay] missing Blackout node")
		return
	_set_alpha(0.0)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fades to black, invokes the synchronous commit on a fully black frame, and
## always fades back in. The return value is the commit result.
func transition(
	commit: Callable,
	fade_out_duration: float,
	fade_in_duration: float
) -> bool:
	if _transitioning or _blackout == null:
		return false
	_transitioning = true
	_blackout.mouse_filter = Control.MOUSE_FILTER_STOP
	await _tween_alpha(1.0, maxf(fade_out_duration, 0.0))
	await get_tree().process_frame
	var succeeded: bool = false
	if commit.is_valid():
		var result: Variant = commit.call()
		succeeded = result is bool and bool(result)
	await get_tree().process_frame
	await _tween_alpha(0.0, maxf(fade_in_duration, 0.0))
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false
	transition_finished.emit(succeeded)
	return succeeded


func set_black_immediate(black: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_transitioning = false
	_set_alpha(1.0 if black else 0.0)
	if _blackout != null:
		_blackout.mouse_filter = (
			Control.MOUSE_FILTER_STOP
			if black
			else Control.MOUSE_FILTER_IGNORE
		)


func is_transitioning() -> bool:
	return _transitioning


func _tween_alpha(target_alpha: float, duration: float) -> void:
	if duration <= 0.0:
		_set_alpha(target_alpha)
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_alpha, _blackout.color.a, target_alpha, duration)
	await _tween.finished
	_tween = null


func _set_alpha(alpha: float) -> void:
	if _blackout == null:
		return
	_blackout.color = Color(0.0, 0.0, 0.0, clampf(alpha, 0.0, 1.0))
