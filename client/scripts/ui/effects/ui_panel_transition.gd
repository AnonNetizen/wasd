# Doc: docs/代码/ui_effects.md
class_name UIPanelTransition
extends UIEffectPlayer


const DEFAULT_ENTER_DURATION: float = 0.18
const DEFAULT_EXIT_DURATION: float = 0.14

var _backdrop: CanvasItem = null
var _backdrop_alpha: float = 1.0
var _completion: Callable = Callable()
var _target: CanvasItem = null
var _target_alpha: float = 1.0


func configure(target: CanvasItem, backdrop: CanvasItem = null) -> void:
	_target = target
	_backdrop = backdrop
	if _target != null:
		_target_alpha = _target.modulate.a
	if _backdrop != null:
		_backdrop_alpha = _backdrop.modulate.a


func play_enter(completed: Callable = Callable()) -> void:
	_completion = completed
	cancel()
	if _target == null or not is_instance_valid(_target):
		_finish(&"enter")
		return
	var duration: float = adjusted_duration(DEFAULT_ENTER_DURATION)
	_target.modulate.a = 0.0
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.modulate.a = 0.0
	if duration <= 0.0:
		_restore_visuals()
		_finish(&"enter")
		return
	_tween = create_effect_tween()
	_tween.tween_property(
		_target,
		"modulate:a",
		_target_alpha,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _backdrop != null and is_instance_valid(_backdrop):
		_tween.parallel().tween_property(
			_backdrop,
			"modulate:a",
			_backdrop_alpha,
			duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_finish.bind(&"enter"), CONNECT_ONE_SHOT)


func play_exit(completed: Callable = Callable()) -> void:
	_completion = completed
	cancel()
	if _target == null or not is_instance_valid(_target):
		_finish(&"exit")
		return
	var duration: float = adjusted_duration(DEFAULT_EXIT_DURATION)
	if duration <= 0.0:
		_target.modulate.a = 0.0
		if _backdrop != null and is_instance_valid(_backdrop):
			_backdrop.modulate.a = 0.0
		_finish(&"exit")
		return
	_tween = create_effect_tween()
	_tween.tween_property(
		_target,
		"modulate:a",
		0.0,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if _backdrop != null and is_instance_valid(_backdrop):
		_tween.parallel().tween_property(
			_backdrop,
			"modulate:a",
			0.0,
			duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.finished.connect(_finish.bind(&"exit"), CONNECT_ONE_SHOT)


func finish_immediately() -> void:
	cancel()
	_restore_visuals()
	var callback: Callable = _completion
	_completion = Callable()
	if callback.is_valid():
		callback.call()


func _restore_visuals() -> void:
	if _target != null and is_instance_valid(_target):
		_target.modulate.a = _target_alpha
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.modulate.a = _backdrop_alpha


func _finish(effect_name: StringName) -> void:
	_tween = null
	var callback: Callable = _completion
	_completion = Callable()
	effect_finished.emit(effect_name)
	if callback.is_valid():
		callback.call()
