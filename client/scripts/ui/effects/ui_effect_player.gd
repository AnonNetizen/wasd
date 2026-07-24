# Doc: docs/代码/ui_effects.md
class_name UIEffectPlayer
extends Node


signal effect_finished(effect_name: StringName)

const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const REDUCED_MOTION_MAX_DURATION: float = 0.10

var _tween: Tween = null


func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func fade(
		target: CanvasItem,
		from_alpha: float,
		to_alpha: float,
		duration: float,
		effect_name: StringName = &"fade"
	) -> void:
	cancel()
	if target == null or not is_instance_valid(target):
		effect_finished.emit(effect_name)
		return
	var safe_duration: float = adjusted_duration(duration)
	var color: Color = target.modulate
	color.a = clampf(from_alpha, 0.0, 1.0)
	target.modulate = color
	if safe_duration <= 0.0:
		color.a = clampf(to_alpha, 0.0, 1.0)
		target.modulate = color
		effect_finished.emit(effect_name)
		return
	_tween = create_effect_tween()
	_tween.tween_property(
		target,
		"modulate:a",
		clampf(to_alpha, 0.0, 1.0),
		safe_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_on_tween_finished.bind(effect_name), CONNECT_ONE_SHOT)


func pulse(
		target: CanvasItem,
		highlight: Color = Color(1.16, 1.10, 0.82, 1.0),
		duration: float = 0.16
	) -> void:
	cancel()
	if target == null or not is_instance_valid(target):
		effect_finished.emit(&"pulse")
		return
	var safe_duration: float = adjusted_duration(duration)
	var original: Color = target.self_modulate
	if safe_duration <= 0.0:
		target.self_modulate = original
		effect_finished.emit(&"pulse")
		return
	_tween = create_effect_tween()
	_tween.tween_property(
		target,
		"self_modulate",
		highlight,
		safe_duration * 0.42
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		target,
		"self_modulate",
		original,
		safe_duration * 0.58
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.finished.connect(_on_tween_finished.bind(&"pulse"), CONNECT_ONE_SHOT)


func adjusted_duration(duration: float) -> float:
	var safe_duration: float = maxf(duration, 0.0)
	if reduced_motion_enabled():
		return minf(safe_duration, REDUCED_MOTION_MAX_DURATION)
	return safe_duration


func reduced_motion_enabled() -> bool:
	return bool(Settings.get_value(SETTINGS_KEYS.ACCESSIBILITY_REDUCED_MOTION, false))


func create_effect_tween() -> Tween:
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


func _on_tween_finished(effect_name: StringName) -> void:
	_tween = null
	effect_finished.emit(effect_name)
