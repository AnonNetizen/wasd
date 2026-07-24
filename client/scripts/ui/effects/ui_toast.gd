# Doc: docs/代码/ui_effects.md
class_name UIToast
extends UIEffectPlayer


var _generation: int = 0


func present(target: CanvasItem, duration: float = 1.35, fade_ratio: float = 0.36) -> void:
	_generation += 1
	var generation: int = _generation
	cancel()
	if target == null or not is_instance_valid(target):
		return
	target.modulate.a = 1.0
	target.show()
	var total_duration: float = maxf(duration, 0.0)
	if total_duration <= 0.0:
		return
	var fade_duration: float = total_duration * clampf(fade_ratio, 0.0, 1.0)
	if reduced_motion_enabled():
		fade_duration = minf(fade_duration, REDUCED_MOTION_MAX_DURATION)
	var hold_duration: float = maxf(total_duration - fade_duration, 0.0)
	_tween = create_effect_tween()
	if hold_duration > 0.0:
		_tween.tween_interval(hold_duration)
	if fade_duration > 0.0:
		_tween.tween_property(
			target,
			"modulate:a",
			0.0,
			fade_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.finished.connect(_on_present_finished.bind(target, generation), CONNECT_ONE_SHOT)


func dismiss(target: CanvasItem) -> void:
	_generation += 1
	cancel()
	if target != null and is_instance_valid(target):
		target.hide()
		target.modulate.a = 1.0


func _on_present_finished(target: CanvasItem, generation: int) -> void:
	_tween = null
	if generation != _generation or target == null or not is_instance_valid(target):
		return
	target.hide()
	target.modulate.a = 1.0
	effect_finished.emit(&"toast")
