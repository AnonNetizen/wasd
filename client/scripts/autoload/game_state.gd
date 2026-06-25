# Doc: docs/代码/game_state.md
# Authority: docs/游戏设计文档.md §9.12, docs/决策记录.md ADR #21
class_name GameStateAutoload
extends Node


signal state_changed(old_state: StringName, new_state: StringName, context: Dictionary)
signal state_entered(state: StringName, context: Dictionary)
signal state_exited(state: StringName, context: Dictionary)

const MAIN_MENU: StringName = &"main_menu"
const LOADING: StringName = &"loading"
const PLAYING: StringName = &"playing"
const PAUSED: StringName = &"paused"
const LEVEL_UP: StringName = &"level_up"
const GAME_OVER: StringName = &"game_over"
const RESULT: StringName = &"result"
const STATES: Array[StringName] = [
	MAIN_MENU,
	LOADING,
	PLAYING,
	PAUSED,
	LEVEL_UP,
	GAME_OVER,
	RESULT,
]

var _current_state: StringName = MAIN_MENU
var _context: Dictionary = {}


func _ready() -> void:
	_apply_tree_pause_for_state(_current_state)
	state_entered.emit(_current_state, _context.duplicate(true))


func current() -> StringName:
	return _current_state


func context() -> Dictionary:
	return _context.duplicate(true)


func is_state(state: StringName) -> bool:
	return _current_state == state


func can_change_to(new_state: StringName) -> bool:
	return STATES.has(new_state)


func change_state(new_state: StringName, context_data: Dictionary = {}) -> bool:
	if not can_change_to(new_state):
		push_error("[GameState] unknown state: %s" % String(new_state))
		return false

	if new_state == _current_state:
		_context = context_data.duplicate(true)
		return false

	var old_state: StringName = _current_state
	var old_context: Dictionary = _context.duplicate(true)

	state_exited.emit(old_state, old_context)
	_current_state = new_state
	_context = context_data.duplicate(true)
	_apply_tree_pause_for_state(_current_state)
	state_changed.emit(old_state, _current_state, _context.duplicate(true))
	state_entered.emit(_current_state, _context.duplicate(true))
	return true


func _apply_tree_pause_for_state(state: StringName) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = state == PAUSED or state == LEVEL_UP
