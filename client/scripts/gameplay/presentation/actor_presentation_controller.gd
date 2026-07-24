# Doc: docs/代码/visual_effects.md
# Authority: docs/游戏设计文档.md §9
class_name ActorPresentationController
extends Node


signal defeat_finished()
signal target_effect_finished()

const ANIMATION_DEFEAT: StringName = &"defeat"
const ANIMATION_FLASH: StringName = &"flash"
const ANIMATION_HIT: StringName = &"hit"
const ANIMATION_RESET: StringName = &"RESET"

@export_group("Scene Bindings")
@export var presentation_profile: PresentationProfileRef = null
@export var visual_root_path: NodePath = ^"../Visual"
@export var body_path: NodePath = ^"../Visual/Body"
@export var outline_path: NodePath = ^"../Visual/Outline"
@export var eye_outline_path: NodePath = ^"../Visual/EyeOutline"
@export var direction_path: NodePath = ^"../Visual/Direction"
@export var forward_anchor_path: NodePath = ^"../VfxAnchors/Forward"

var hit_progress: float = -1.0:
	set(value):
		hit_progress = value
		_refresh_visuals()
var defeat_progress: float = -1.0:
	set(value):
		defeat_progress = value
		_refresh_visuals()

var _base_color: Color = Color.WHITE
var _base_scale: Vector2 = Vector2.ONE
var _defeat_color: Color = Color.WHITE
var _defeat_end_alpha: float = 0.0
var _defeat_end_scale: Vector2 = Vector2(1.35, 1.35)
var _defeat_finished_emitted: bool = false
var _hit_color: Color = Color.WHITE
var _outline_alpha: float = 1.0
var _profile_id_override: String = ""
var _visual_root: Node2D = null
var _body_visual: Polygon2D = null
var _outline_visual: Polygon2D = null
var _eye_outline_visual: Polygon2D = null
var _direction_visual: Node2D = null
var _forward_anchor: Node2D = null

@onready var _animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_resolve_scene_nodes()
	if not _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.connect(_on_animation_finished)
	reset_presentation()


func _physics_process(delta: float) -> void:
	if not _animation_player.is_playing():
		return
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta > 0.0:
		_animation_player.advance(scaled_delta)


func configure_visual(
	base_color: Color,
	hit_color: Color,
	defeat_color: Color,
	outline_alpha: float,
	base_scale: Vector2 = Vector2.ONE
) -> void:
	_base_color = base_color
	_hit_color = hit_color
	_defeat_color = defeat_color
	_outline_alpha = clampf(outline_alpha, 0.0, 1.0)
	_base_scale = base_scale
	_resolve_scene_nodes()
	if _forward_anchor != null:
		_forward_anchor.scale.x = -1.0 if _base_scale.x < 0.0 else 1.0
	_refresh_visuals()


func resolved_profile_id(fallback: String) -> String:
	if not _profile_id_override.is_empty():
		return _profile_id_override
	if presentation_profile == null or presentation_profile.profile_id.is_empty():
		return fallback
	return presentation_profile.profile_id


func configure_profile_id(profile_id: String) -> void:
	_profile_id_override = profile_id.strip_edges()


func set_direction(direction: Vector2) -> void:
	if direction.length_squared() <= 0.0:
		return
	_resolve_scene_nodes()
	if _direction_visual != null:
		_direction_visual.rotation = direction.angle()
	if _forward_anchor != null:
		_forward_anchor.rotation = direction.angle()


func set_facing_sign(facing_sign: float) -> void:
	var normalized_sign: float = -1.0 if facing_sign < 0.0 else 1.0
	_base_scale.x = absf(_base_scale.x) * normalized_sign
	if _forward_anchor != null:
		_forward_anchor.scale.x = normalized_sign
	_refresh_visuals()


func play_hit() -> void:
	if is_defeat_active():
		return
	hit_progress = 0.0
	_animation_player.speed_scale = 1.0
	_animation_player.stop()
	_animation_player.play(ANIMATION_HIT)
	_animation_player.advance(0.0)
	_apply_reduced_motion_duration()


func play_defeat() -> void:
	_defeat_finished_emitted = false
	hit_progress = -1.0
	defeat_progress = 0.0
	_animation_player.speed_scale = 1.0
	_animation_player.stop()
	_animation_player.play(ANIMATION_DEFEAT)
	_animation_player.advance(0.0)
	_apply_reduced_motion_duration()


func play_target_effect(effect_data: Dictionary, _request: VfxPlayRequest) -> Node:
	var resource_path: String = String(effect_data.get("resource_path", ""))
	var preset: Resource = load(resource_path)
	if preset == null:
		return null
	var animation_name: StringName = StringName(preset.get("animation_name"))
	var duration: float = maxf(float(preset.get("duration")), 0.001)
	if animation_name == ANIMATION_DEFEAT:
		_defeat_color = preset.get("tint") as Color
		_defeat_end_scale = preset.get("end_scale") as Vector2
		_defeat_end_alpha = clampf(float(preset.get("end_alpha")), 0.0, 1.0)
		if not is_defeat_active():
			play_defeat()
		_set_current_animation_duration(duration)
	elif animation_name == ANIMATION_FLASH or animation_name == ANIMATION_HIT:
		_hit_color = preset.get("tint") as Color
		if hit_progress < 0.0:
			play_hit()
		_set_current_animation_duration(duration)
	else:
		return null
	return self


func cancel(_immediate: bool = false) -> void:
	reset_presentation()


func reset_presentation() -> void:
	if not is_node_ready():
		return
	_animation_player.speed_scale = 1.0
	_animation_player.stop()
	_animation_player.play(ANIMATION_RESET)
	_animation_player.advance(0.0)
	_animation_player.stop()
	hit_progress = -1.0
	defeat_progress = -1.0
	_defeat_finished_emitted = false
	_defeat_end_alpha = 0.0
	_defeat_end_scale = Vector2(1.35, 1.35)
	_refresh_visuals()


func is_defeat_active() -> bool:
	return defeat_progress >= 0.0


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == ANIMATION_HIT:
		hit_progress = -1.0
		target_effect_finished.emit()
		return
	if animation_name != ANIMATION_DEFEAT or _defeat_finished_emitted:
		return
	_defeat_finished_emitted = true
	target_effect_finished.emit()
	defeat_finished.emit()


func _resolve_scene_nodes() -> void:
	if _visual_root == null:
		_visual_root = get_node_or_null(visual_root_path) as Node2D
	if _body_visual == null:
		_body_visual = get_node_or_null(body_path) as Polygon2D
	if _outline_visual == null:
		_outline_visual = get_node_or_null(outline_path) as Polygon2D
	if _eye_outline_visual == null:
		_eye_outline_visual = get_node_or_null(eye_outline_path) as Polygon2D
	if _direction_visual == null:
		_direction_visual = get_node_or_null(direction_path) as Node2D
	if _forward_anchor == null:
		_forward_anchor = get_node_or_null(forward_anchor_path) as Node2D


func _refresh_visuals() -> void:
	_resolve_scene_nodes()
	if _visual_root == null or _body_visual == null:
		return

	var color: Color = _base_color
	var alpha_scale: float = 1.0
	var scale_multiplier: float = 1.0
	if defeat_progress >= 0.0:
		var normalized_defeat: float = clampf(defeat_progress, 0.0, 1.0)
		color = _defeat_color
		alpha_scale = lerpf(1.0, _defeat_end_alpha, normalized_defeat)
		var scale_ratio: Vector2 = Vector2.ONE.lerp(
			_defeat_end_scale,
			normalized_defeat
		)
		_visual_root.scale = _base_scale * scale_ratio
	elif hit_progress >= 0.0:
		color = _hit_color

	color.a *= alpha_scale
	_body_visual.color = color
	if defeat_progress < 0.0:
		_visual_root.scale = _base_scale * scale_multiplier
	_set_outline_alpha(_outline_visual, _outline_alpha * alpha_scale)
	_set_outline_alpha(_eye_outline_visual, _outline_alpha * alpha_scale)


func _set_outline_alpha(polygon: Polygon2D, alpha: float) -> void:
	if polygon == null:
		return
	var color: Color = polygon.color
	color.a = clampf(alpha, 0.0, 1.0)
	polygon.color = color


func _set_current_animation_duration(duration: float) -> void:
	var animation_name: StringName = _animation_player.current_animation
	var animation: Animation = _animation_player.get_animation(animation_name)
	if animation == null:
		return
	var resolved_duration: float = duration
	if bool(VisualEffects.current_policy().get("reduced_motion", false)):
		resolved_duration = minf(resolved_duration, 0.1)
	_animation_player.speed_scale = animation.length / maxf(resolved_duration, 0.001)


func _apply_reduced_motion_duration() -> void:
	if not bool(VisualEffects.current_policy().get("reduced_motion", false)):
		return
	_set_current_animation_duration(0.1)
