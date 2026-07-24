# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5.2, docs/决策记录.md ADR #148
class_name GameplayCameraController
extends Node2D


const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const PLAYER_DAMAGE_SHAKE_PROFILE: String = "player_damage_shake"
const CAMERA_ZOOM: Vector2 = Vector2.ONE
const CAMERA_HOST_LAYER: int = 1
const PLAYER_CAMERA_PRIORITY: int = 10

var _feedback_configured: bool = false

@onready var _camera: Camera2D = $CenteredCamera
@onready var _host: PhantomCameraHost = $CenteredCamera/PhantomCameraHost
@onready var _player_camera: PhantomCamera2D = $PlayerCamera
@onready var _player_damage_shake: PhantomCameraNoiseEmitter2D = $PlayerDamageShake


func _ready() -> void:
	_configure_camera_nodes()
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)
	if not _screen_shake_enabled():
		_stop_player_damage_shake()


func _exit_tree() -> void:
	if Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.disconnect(_on_setting_changed)


func configure(target: Node2D, feedback_config: Dictionary) -> void:
	if target == null:
		push_error("[GameplayCameraController] missing follow target")
		return
	var raw_profile: Variant = feedback_config.get(PLAYER_DAMAGE_SHAKE_PROFILE, {})
	if not raw_profile is Dictionary:
		push_error("[GameplayCameraController] missing player damage shake profile")
		return
	var profile: Dictionary = raw_profile as Dictionary
	var noise: PhantomCameraNoise2D = _player_damage_shake.noise
	if noise == null:
		push_error("[GameplayCameraController] missing player damage noise resource")
		return

	_player_camera.follow_target = target
	_player_camera.teleport_position()
	_player_camera.priority = PLAYER_CAMERA_PRIORITY
	_camera.enabled = true
	_camera.make_current()
	noise.amplitude = float(profile.get("amplitude", 0.0))
	noise.frequency = float(profile.get("frequency", 0.0))
	noise.positional_multiplier_x = float(profile.get("positional_multiplier_x", 1.0))
	noise.positional_multiplier_y = float(profile.get("positional_multiplier_y", 1.0))
	_player_damage_shake.growth_time = float(profile.get("growth_time", 0.0))
	_player_damage_shake.duration = float(profile.get("duration", 0.0))
	_player_damage_shake.decay_time = float(profile.get("decay_time", 0.0))
	_feedback_configured = true


func play_player_damage_shake() -> void:
	if not _feedback_configured or not _screen_shake_enabled():
		return
	_player_damage_shake.emit()


func play_feedback(feedback_id: String) -> void:
	match feedback_id:
		PLAYER_DAMAGE_SHAKE_PROFILE:
			play_player_damage_shake()
		_:
			push_warning(
				"[GameplayCameraController] unknown camera feedback: %s"
				% feedback_id
			)


func is_player_damage_shake_emitting() -> bool:
	return _player_damage_shake.is_emitting()


func _configure_camera_nodes() -> void:
	_camera.enabled = false
	_camera.position_smoothing_enabled = false
	_camera.ignore_rotation = true
	_camera.rotation = 0.0
	_camera.zoom = CAMERA_ZOOM

	_host.host_layers = CAMERA_HOST_LAYER
	_player_camera.priority = 0
	_player_camera.follow_mode = PhantomCamera2D.FollowMode.GLUED
	_player_camera.zoom = CAMERA_ZOOM
	_player_camera.follow_damping = false
	_player_camera.lookahead = false
	_player_camera.auto_zoom = false
	_player_camera.rotate_with_target = false
	_player_camera.rotation_damping = false
	_player_camera.host_layers = CAMERA_HOST_LAYER
	_player_camera.noise_emitter_layer = CAMERA_HOST_LAYER
	_player_camera.tween_on_load = false
	_player_camera.tween_duration = 0.0

	_player_damage_shake.continuous = false
	_player_damage_shake.noise_emitter_layer = CAMERA_HOST_LAYER


func _screen_shake_enabled() -> bool:
	return bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true))


func _stop_player_damage_shake() -> void:
	_player_damage_shake.stop(false)
	_camera.offset = Vector2.ZERO


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE and not bool(value):
		_stop_player_damage_shake()
