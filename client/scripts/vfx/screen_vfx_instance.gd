# Doc: docs/代码/visual_effects.md
class_name ScreenVfxInstance
extends ColorRect
## Screen-space one-shot lifecycle driven by an AnimationPlayer.


signal finished(instance: Node)

@export var animation_player_path: NodePath = NodePath("AnimationPlayer")
@export var playback_animation: StringName = &"play"

var _animation_player: AnimationPlayer = null
var _finished_emitted: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _animation_player != null and not _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.connect(_on_animation_finished)


func configure(_request: VfxPlayRequest) -> void:
	_finished_emitted = false
	visible = true


func play() -> void:
	_finished_emitted = false
	if _animation_player == null or not _animation_player.has_animation(playback_animation):
		call_deferred("_finish")
		return
	if _animation_player.has_animation(&"RESET"):
		_animation_player.play(&"RESET")
		_animation_player.advance(0.0)
	_animation_player.play(playback_animation)


func cancel(_immediate: bool = false) -> void:
	if _animation_player != null:
		_animation_player.stop()
	_finish()


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == playback_animation:
		_finish()


func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	finished.emit(self)
