class_name LowpolyModelAnimator
extends RefCounted
## Resolves semantic animation states to imported GLB clips and owns transitions.

signal one_shot_finished(state: StringName)

const STATE_IDLE: StringName = &"idle"
const STATE_MOVE: StringName = &"move"
const STATE_ATTACK: StringName = &"attack"
const STATE_FIRE: StringName = &"fire"
const STATE_HIT: StringName = &"hit"
const STATE_DEATH: StringName = &"death"

var _animation_player: AnimationPlayer
var _clips: Dictionary = {}
var _missing_states: PackedStringArray = []
var _base_state: StringName = STATE_IDLE
var _current_state: StringName = &""
var _one_shot_active: bool = false
var _paused: bool = false
var _playback_speed: float = 1.0
var _blend_seconds: float = 0.1
var _move_speed_scale: float = 1.0


func setup(model: Node, profile: Dictionary) -> bool:
	_disconnect_player()
	_animation_player = _find_animation_player(model)
	_clips.clear()
	_missing_states.clear()
	_blend_seconds = maxf(float(profile.get("blend_seconds", 0.1)), 0.0)
	_move_speed_scale = maxf(float(profile.get("move_speed_scale", 1.0)), 0.1)
	if _animation_player == null:
		_missing_states.append("animation_player")
		return false
	for raw_state: Variant in profile.keys():
		var state := StringName(raw_state)
		var value: Variant = profile[raw_state]
		if not value is String:
			continue
		var suffix := String(value)
		if suffix.is_empty():
			continue
		var clip := _resolve_clip(suffix)
		if clip == &"":
			_missing_states.append(String(state))
			continue
		_clips[state] = clip
		var animation := _animation_player.get_animation(clip)
		if animation != null:
			animation.loop_mode = (
				Animation.LOOP_LINEAR if state == STATE_IDLE or state == STATE_MOVE
				else Animation.LOOP_NONE
			)
	_animation_player.animation_finished.connect(_on_animation_finished)
	reset()
	return _clips.has(STATE_IDLE) and _clips.has(STATE_MOVE) and _clips.has(STATE_DEATH)


func reset() -> void:
	_base_state = STATE_IDLE
	_current_state = &""
	_one_shot_active = false
	_paused = false
	_playback_speed = 1.0
	_play_state(STATE_IDLE, 1.0)


func set_locomotion(moving: bool, speed_ratio: float = 1.0) -> void:
	_base_state = STATE_MOVE if moving and _clips.has(STATE_MOVE) else STATE_IDLE
	if _one_shot_active:
		return
	var speed := clampf(speed_ratio * _move_speed_scale, 0.65, 1.6) if moving else 1.0
	_play_state(_base_state, speed)


func play_one_shot(state: StringName) -> bool:
	if _animation_player == null or not _clips.has(state):
		return false
	if _current_state == STATE_DEATH:
		return false
	if _one_shot_active:
		var current_priority := _state_priority(_current_state)
		var next_priority := _state_priority(state)
		if next_priority < current_priority or state == _current_state:
			return false
	_one_shot_active = true
	_play_state(state, 1.0, true)
	return true


func play_death() -> bool:
	if _animation_player == null or not _clips.has(STATE_DEATH):
		return false
	_one_shot_active = true
	_play_state(STATE_DEATH, 1.0, true)
	return true


func set_paused(value: bool) -> void:
	_paused = value
	_apply_speed()


func is_ready() -> bool:
	return _animation_player != null and _clips.has(STATE_IDLE) and _clips.has(STATE_MOVE)


func has_state(state: StringName) -> bool:
	return _clips.has(state)


func get_current_state() -> StringName:
	return _current_state


func get_current_clip() -> StringName:
	return StringName(_clips.get(_current_state, ""))


func get_animation_position() -> float:
	return _animation_player.current_animation_position if _animation_player != null else 0.0


func get_clip_duration(state: StringName) -> float:
	if _animation_player == null or not _clips.has(state):
		return 0.0
	var animation := _animation_player.get_animation(StringName(_clips[state]))
	return animation.length if animation != null else 0.0


func get_missing_states() -> PackedStringArray:
	return _missing_states.duplicate()


func _play_state(state: StringName, speed: float, force: bool = false) -> void:
	if _animation_player == null or not _clips.has(state):
		return
	var clip := StringName(_clips[state])
	_playback_speed = maxf(speed, 0.01)
	if not force and _current_state == state and _animation_player.current_animation == clip:
		_apply_speed()
		return
	_current_state = state
	_animation_player.play(clip, _blend_seconds, 1.0)
	_apply_speed()


func _apply_speed() -> void:
	if _animation_player != null:
		_animation_player.speed_scale = 0.0 if _paused else _playback_speed


func _resolve_clip(suffix: String) -> StringName:
	var suffix_lower := suffix.to_lower()
	for animation_name: StringName in _animation_player.get_animation_list():
		var candidate := String(animation_name)
		var candidate_lower := candidate.to_lower()
		if candidate_lower == suffix_lower or candidate_lower.ends_with("|" + suffix_lower):
			return animation_name
	return &""


func _on_animation_finished(animation_name: StringName) -> void:
	if not _one_shot_active or animation_name != get_current_clip():
		return
	var finished_state := _current_state
	_one_shot_active = false
	one_shot_finished.emit(finished_state)
	if finished_state != STATE_DEATH:
		_play_state(_base_state, 1.0, true)


func _state_priority(state: StringName) -> int:
	if state == STATE_DEATH:
		return 3
	if state == STATE_HIT:
		return 2
	if state == STATE_IDLE or state == STATE_MOVE:
		return 0
	return 1


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null


func _disconnect_player() -> void:
	if _animation_player != null and _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.disconnect(_on_animation_finished)
