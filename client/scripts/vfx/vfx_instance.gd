# Doc: docs/代码/visual_effects.md
class_name VfxInstance
extends Node2D
## Base lifecycle for reusable spawned VFX scenes.


signal finished(instance: Node)

@export var animation_player_path: NodePath = NodePath("AnimationPlayer")
@export var playback_animation: StringName = &"play"

var _animation_player: AnimationPlayer = null
var _finished_emitted: bool = false
var _request: VfxPlayRequest = null


func _ready() -> void:
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _animation_player != null and not _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.connect(_on_animation_finished)


func configure(request: VfxPlayRequest) -> void:
	_request = request.clone() if request != null else VfxPlayRequest.new()
	_finished_emitted = false
	rotation = _request.rotation
	scale = _request.scale_value
	modulate = Color.WHITE
	var raw_tint: Variant = _request.payload.get("tint")
	if raw_tint is Color:
		modulate = raw_tint as Color
	elif raw_tint is String and Color.html_is_valid(String(raw_tint)):
		modulate = Color.html(String(raw_tint))


func play() -> void:
	_finished_emitted = false
	_reset_animation()
	_set_particles_emitting(self, true)
	if _animation_player == null or not _animation_player.has_animation(playback_animation):
		call_deferred("_finish")
		return
	_animation_player.play(playback_animation)


func cancel(immediate: bool = false) -> void:
	if _animation_player != null:
		_animation_player.stop()
	_set_particles_emitting(self, false)
	if immediate:
		visible = false
	_finish()


func _pool_reset() -> void:
	_finished_emitted = false
	visible = true
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	_reset_animation()
	_set_particles_emitting(self, false)


func _pool_release() -> void:
	if _animation_player != null:
		_animation_player.stop()
	_set_particles_emitting(self, false)
	visible = false
	_request = null


func _reset_animation() -> void:
	if _animation_player == null:
		return
	_animation_player.stop()
	if _animation_player.has_animation(&"RESET"):
		_animation_player.play(&"RESET")
		_animation_player.advance(0.0)
		_animation_player.stop()


func _set_particles_emitting(node: Node, emitting: bool) -> void:
	for child: Node in node.get_children():
		if child is GPUParticles2D:
			var gpu_particles := child as GPUParticles2D
			gpu_particles.emitting = emitting
			if emitting:
				gpu_particles.restart()
			elif gpu_particles.one_shot:
				gpu_particles.restart()
				gpu_particles.emitting = false
		elif child is CPUParticles2D:
			var cpu_particles := child as CPUParticles2D
			cpu_particles.emitting = emitting
			if emitting:
				cpu_particles.restart()
		_set_particles_emitting(child, emitting)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == playback_animation:
		_finish()


func _finish() -> void:
	if _finished_emitted:
		return
	_finished_emitted = true
	finished.emit(self)
