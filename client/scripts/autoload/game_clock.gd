# Doc: docs/代码/game_clock.md
# Authority: docs/游戏设计文档.md §9.18.2, docs/决策记录.md ADR #27
class_name GameClockAutoload
extends Node


signal time_scale_changed(time_scale: float)

var _elapsed: float = 0.0
var _tick: int = 0
var _time_scale: float = 1.0
var _frozen: bool = false


func _ready() -> void:
	if GameState != null:
		GameState.state_changed.connect(_on_game_state_changed)
		_frozen = _state_freezes_clock(GameState.current())


func _process(delta: float) -> void:
	var scaled_delta: float = delta_scaled(delta)
	_elapsed += scaled_delta


func _physics_process(delta: float) -> void:
	if delta_scaled(delta) > 0.0:
		_tick += 1


func now() -> float:
	return _elapsed


func tick() -> int:
	return _tick


func delta_scaled(delta: float) -> float:
	if _frozen:
		return 0.0
	return delta * _time_scale


func wall_now() -> float:
	return Time.get_unix_time_from_system()


func time_scale() -> float:
	return _time_scale


func set_time_scale(value: float) -> void:
	_time_scale = maxf(value, 0.0)
	time_scale_changed.emit(_time_scale)


func reset() -> void:
	_elapsed = 0.0
	_tick = 0
	_time_scale = 1.0
	_frozen = false
	time_scale_changed.emit(_time_scale)


func _on_game_state_changed(_old_state: StringName, new_state: StringName, _context: Dictionary) -> void:
	_frozen = _state_freezes_clock(new_state)


func _state_freezes_clock(state: StringName) -> bool:
	return state == GameState.PAUSED or state == GameState.LEVEL_UP or state == GameState.GAME_OVER
