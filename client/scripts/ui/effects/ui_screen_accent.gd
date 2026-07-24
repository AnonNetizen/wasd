# Doc: docs/代码/ui_effects.md
class_name UIScreenAccent
extends ColorRect


signal accent_finished()

const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const DEFAULT_DURATION: float = 0.14

var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


func flash(accent_color: Color, strength: float = 0.22, duration: float = DEFAULT_DURATION) -> bool:
	if not bool(Settings.get_value(SETTINGS_KEYS.ACCESSIBILITY_SCREEN_FLASHES, true)):
		return false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	color = accent_color
	modulate.a = clampf(strength, 0.0, 1.0)
	var safe_duration: float = maxf(duration, 0.0)
	if bool(Settings.get_value(SETTINGS_KEYS.ACCESSIBILITY_REDUCED_MOTION, false)):
		safe_duration = minf(safe_duration, UIEffectPlayer.REDUCED_MOTION_MAX_DURATION)
	if safe_duration <= 0.0:
		modulate.a = 0.0
		accent_finished.emit()
		return true
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(
		self,
		"modulate:a",
		0.0,
		safe_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(_on_flash_finished, CONNECT_ONE_SHOT)
	return true


func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	modulate.a = 0.0


func _on_flash_finished() -> void:
	_tween = null
	accent_finished.emit()
