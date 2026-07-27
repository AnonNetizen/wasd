# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5.2, docs/决策记录.md ADR #148
class_name GameplayCameraController
extends Node2D


const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const PLAYER_DAMAGE_SHAKE_PROFILE: String = "player_damage_shake"
const WEAPON_RECOIL_SHAKE_PROFILE: String = "weapon_recoil_shake"
const CAMERA_ZOOM: Vector2 = Vector2.ONE
const CAMERA_HOST_LAYER: int = 1
const PLAYER_CAMERA_PRIORITY: int = 10

var _feedback_configured: bool = false
var _weapon_recoil_amplitude_exponent: float = 1.0
var _weapon_recoil_max_amplitude: float = 0.0

@onready var _camera: Camera2D = $CenteredCamera
@onready var _host: PhantomCameraHost = $CenteredCamera/PhantomCameraHost
@onready var _player_camera: PhantomCamera2D = $PlayerCamera
@onready var _player_damage_shake: PhantomCameraNoiseEmitter2D = $PlayerDamageShake
@onready var _weapon_recoil_shake: PhantomCameraNoiseEmitter2D = $WeaponRecoilShake


func _ready() -> void:
	_configure_camera_nodes()
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)
	if not _screen_shake_enabled():
		_stop_all_feedback()


func _exit_tree() -> void:
	if Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.disconnect(_on_setting_changed)


func configure(target: Node2D, feedback_config: Dictionary) -> void:
	if target == null:
		push_error("[GameplayCameraController] missing follow target")
		return
	var raw_damage_profile: Variant = feedback_config.get(
		PLAYER_DAMAGE_SHAKE_PROFILE,
		{}
	)
	var raw_recoil_profile: Variant = feedback_config.get(
		WEAPON_RECOIL_SHAKE_PROFILE,
		{}
	)
	if not raw_damage_profile is Dictionary:
		push_error("[GameplayCameraController] missing player damage shake profile")
		return
	if not raw_recoil_profile is Dictionary:
		push_error("[GameplayCameraController] missing weapon recoil shake profile")
		return

	_player_camera.follow_target = target
	_player_camera.teleport_position()
	_player_camera.priority = PLAYER_CAMERA_PRIORITY
	_camera.enabled = true
	_camera.make_current()
	if not _configure_emitter(
		_player_damage_shake,
		raw_damage_profile as Dictionary
	):
		return
	if not _configure_emitter(
		_weapon_recoil_shake,
		raw_recoil_profile as Dictionary
	):
		return
	var recoil_profile: Dictionary = raw_recoil_profile as Dictionary
	_weapon_recoil_max_amplitude = maxf(
		float(recoil_profile.get("amplitude", 0.0)),
		0.0
	)
	_weapon_recoil_amplitude_exponent = maxf(
		float(recoil_profile.get("amplitude_exponent", 1.0)),
		0.0
	)
	_feedback_configured = true


func play_player_damage_shake() -> void:
	if not _feedback_configured or not _screen_shake_enabled():
		return
	_player_damage_shake.emit()


func play_weapon_recoil_shake(context: Dictionary) -> void:
	if not _feedback_configured or not _screen_shake_enabled():
		return
	var recoil_ratio: float = clampf(
		float(context.get("recoil_ratio", 0.0)),
		0.0,
		1.0
	)
	if recoil_ratio <= 0.0:
		return
	var requested_amplitude: float = (
		_weapon_recoil_max_amplitude
		* pow(recoil_ratio, _weapon_recoil_amplitude_exponent)
	)
	if requested_amplitude <= 0.0:
		return
	var noise: PhantomCameraNoise2D = _weapon_recoil_shake.noise
	if noise == null:
		return
	noise.amplitude = (
		maxf(noise.amplitude, requested_amplitude)
		if _weapon_recoil_shake.is_emitting()
		else requested_amplitude
	)
	_weapon_recoil_shake.emit()


func play_feedback(feedback_id: String, context: Dictionary = {}) -> void:
	match feedback_id:
		PLAYER_DAMAGE_SHAKE_PROFILE:
			play_player_damage_shake()
		WEAPON_RECOIL_SHAKE_PROFILE:
			play_weapon_recoil_shake(context)
		_:
			push_warning(
				"[GameplayCameraController] unknown camera feedback: %s"
				% feedback_id
			)


func is_player_damage_shake_emitting() -> bool:
	return _player_damage_shake.is_emitting()


func is_weapon_recoil_shake_emitting() -> bool:
	return _weapon_recoil_shake.is_emitting()


func weapon_recoil_shake_amplitude() -> float:
	var noise: PhantomCameraNoise2D = _weapon_recoil_shake.noise
	return noise.amplitude if noise != null else 0.0


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
	_weapon_recoil_shake.continuous = false
	_weapon_recoil_shake.noise_emitter_layer = CAMERA_HOST_LAYER


func _screen_shake_enabled() -> bool:
	return bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true))


func _stop_player_damage_shake() -> void:
	_player_damage_shake.stop(false)
	_camera.offset = Vector2.ZERO


func _stop_weapon_recoil_shake() -> void:
	_weapon_recoil_shake.stop(false)
	_camera.offset = Vector2.ZERO


func _stop_all_feedback() -> void:
	_stop_player_damage_shake()
	_stop_weapon_recoil_shake()


func _configure_emitter(
	emitter: PhantomCameraNoiseEmitter2D,
	profile: Dictionary
) -> bool:
	var noise: PhantomCameraNoise2D = emitter.noise
	if noise == null:
		push_error("[GameplayCameraController] missing camera noise resource")
		return false
	noise.amplitude = maxf(float(profile.get("amplitude", 0.0)), 0.0)
	noise.frequency = maxf(float(profile.get("frequency", 0.0)), 0.0)
	noise.positional_multiplier_x = clampf(
		float(profile.get("positional_multiplier_x", 1.0)),
		0.0,
		1.0
	)
	noise.positional_multiplier_y = clampf(
		float(profile.get("positional_multiplier_y", 1.0)),
		0.0,
		1.0
	)
	emitter.growth_time = maxf(float(profile.get("growth_time", 0.0)), 0.0)
	emitter.duration = maxf(float(profile.get("duration", 0.0)), 0.0)
	emitter.decay_time = maxf(float(profile.get("decay_time", 0.0)), 0.0)
	return true


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE and not bool(value):
		_stop_all_feedback()
