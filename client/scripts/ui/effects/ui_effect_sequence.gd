# Doc: docs/代码/ui_effects.md
class_name UIEffectSequence
extends UIEffectPlayer


signal sequence_finished()

var _generation: int = 0


func play(steps: Array[Dictionary]) -> void:
	_generation += 1
	_play_steps(steps.duplicate(true), _generation)


func cancel() -> void:
	_generation += 1


func _play_steps(steps: Array[Dictionary], generation: int) -> void:
	for step: Dictionary in steps:
		if generation != _generation:
			return
		var callback: Callable = step.get("callable", Callable()) as Callable
		if callback.is_valid():
			callback.call()
		var delay: float = maxf(float(step.get("delay", 0.0)), 0.0)
		if reduced_motion_enabled():
			delay = 0.0
		if delay <= 0.0:
			continue
		var timer: SceneTreeTimer = get_tree().create_timer(
			delay,
			true,
			false,
			true
		)
		await timer.timeout
		if not is_instance_valid(self):
			return
	if generation == _generation:
		sequence_finished.emit()
