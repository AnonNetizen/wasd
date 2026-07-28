# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5.2, docs/决策记录.md ADR #148 / #167
class_name GameplayCameraController
extends Node2D


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const AIM_LOOK_PROFILE: String = "aim_look"
const PLAYER_DAMAGE_SHAKE_PROFILE: String = "player_damage_shake"
const WEAPON_RECOIL_SHAKE_PROFILE: String = "weapon_recoil_shake"
const CAMERA_ZOOM: Vector2 = Vector2.ONE
const CAMERA_HOST_LAYER: int = 1
const PLAYER_CAMERA_PRIORITY: int = 10
const CAMERA_PHYSICS_PRIORITY: int = -100
const CAMERA_RENDER_PRIORITY: int = 400
const LOOK_OFFSET_EPSILON_SQUARED: float = 0.0001

var _current_look_offset: Vector2 = Vector2.ZERO
var _feedback_configured: bool = false
var _has_direction_look: bool = false
var _has_pointer_look: bool = false
var _last_direction_look: Vector2 = Vector2.ZERO
var _look_configured: bool = false
var _look_max_offset: float = 0.0
var _look_pointer_dead_zone: float = 0.0
var _look_pointer_offset_ratio: float = 0.0
var _look_smoothing_time: float = 0.0
var _target: Node2D = null
var _weapon_recoil_amplitude_exponent: float = 1.0
var _weapon_recoil_max_amplitude: float = 0.0

@onready var _camera: Camera2D = $CenteredCamera
@onready var _host: PhantomCameraHost = $CenteredCamera/PhantomCameraHost
@onready var _player_camera: PhantomCamera2D = $PlayerCamera
@onready var _player_damage_shake: PhantomCameraNoiseEmitter2D = $PlayerDamageShake
@onready var _weapon_recoil_shake: PhantomCameraNoiseEmitter2D = $WeaponRecoilShake


func _ready() -> void:
	process_priority = CAMERA_RENDER_PRIORITY
	process_physics_priority = CAMERA_PHYSICS_PRIORITY
	set_process(false)
	set_physics_process(false)
	_configure_camera_nodes()
	if not Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.connect(_on_setting_changed)
	if not InputService.pointer_activity.is_connected(_on_pointer_activity):
		InputService.pointer_activity.connect(_on_pointer_activity)
	if not _screen_shake_enabled():
		_stop_all_feedback()


func _exit_tree() -> void:
	if Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.disconnect(_on_setting_changed)
	if InputService.pointer_activity.is_connected(_on_pointer_activity):
		InputService.pointer_activity.disconnect(_on_pointer_activity)
	_reset_target_look_offset()


func _physics_process(delta: float) -> void:
	if not _look_configured or _target == null or not is_instance_valid(_target):
		return
	var desired_offset: Vector2 = _desired_look_offset()
	var smoothing_alpha: float = 1.0 - exp(-delta / _look_smoothing_time)
	_current_look_offset = _current_look_offset.lerp(
		desired_offset,
		clampf(smoothing_alpha, 0.0, 1.0)
	)
	if _current_look_offset.distance_squared_to(desired_offset) <= LOOK_OFFSET_EPSILON_SQUARED:
		_current_look_offset = desired_offset
	_apply_look_offset(_current_look_offset)


func _process(_delta: float) -> void:
	_apply_camera_position()


func configure(target: Node2D, feedback_config: Dictionary) -> void:
	if target == null:
		push_error("[GameplayCameraController] missing follow target")
		return
	if not target.has_method("set_camera_look_offset"):
		push_error("[GameplayCameraController] follow target is missing camera look interface")
		return
	var raw_aim_look: Variant = feedback_config.get(AIM_LOOK_PROFILE, {})
	var raw_damage_profile: Variant = feedback_config.get(
		PLAYER_DAMAGE_SHAKE_PROFILE,
		{}
	)
	var raw_recoil_profile: Variant = feedback_config.get(
		WEAPON_RECOIL_SHAKE_PROFILE,
		{}
	)
	if not raw_aim_look is Dictionary:
		push_error("[GameplayCameraController] missing aim look profile")
		return
	if not raw_damage_profile is Dictionary:
		push_error("[GameplayCameraController] missing player damage shake profile")
		return
	if not raw_recoil_profile is Dictionary:
		push_error("[GameplayCameraController] missing weapon recoil shake profile")
		return

	_reset_target_look_offset()
	if not _configure_aim_look(raw_aim_look as Dictionary):
		return
	_target = target
	_current_look_offset = Vector2.ZERO
	_last_direction_look = Vector2.ZERO
	_has_direction_look = false
	_has_pointer_look = false
	_player_camera.follow_target = target
	_player_camera.follow_offset = Vector2.ZERO
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
	_look_configured = true
	_apply_look_offset(Vector2.ZERO)
	set_process(true)
	set_physics_process(true)


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


func current_look_offset() -> Vector2:
	return _current_look_offset


func _configure_camera_nodes() -> void:
	_camera.enabled = false
	_camera.position_smoothing_enabled = false
	_camera.ignore_rotation = true
	_camera.rotation = 0.0
	_camera.zoom = CAMERA_ZOOM

	_host.host_layers = CAMERA_HOST_LAYER
	_player_camera.priority = 0
	_player_camera.follow_mode = PhantomCamera2D.FollowMode.GLUED
	_player_camera.follow_offset = Vector2.ZERO
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


func _configure_aim_look(profile: Dictionary) -> bool:
	var pointer_offset_ratio: float = float(
		profile.get("pointer_offset_ratio", 0.0)
	)
	var max_offset: float = float(profile.get("max_offset_px", 0.0))
	var pointer_dead_zone: float = float(
		profile.get("pointer_dead_zone_px", -1.0)
	)
	var smoothing_time: float = float(
		profile.get("smoothing_time_seconds", 0.0)
	)
	if pointer_offset_ratio <= 0.0 or pointer_offset_ratio > 1.0:
		push_error("[GameplayCameraController] invalid pointer offset ratio")
		return false
	if max_offset < 0.0:
		push_error("[GameplayCameraController] invalid maximum look offset")
		return false
	if pointer_dead_zone < 0.0:
		push_error("[GameplayCameraController] invalid pointer dead zone")
		return false
	if smoothing_time <= 0.0:
		push_error("[GameplayCameraController] invalid look smoothing time")
		return false
	_look_pointer_offset_ratio = pointer_offset_ratio
	_look_max_offset = max_offset
	_look_pointer_dead_zone = pointer_dead_zone
	_look_smoothing_time = smoothing_time
	return true


func _desired_look_offset() -> Vector2:
	if InputService.should_use_pointer_aim():
		if not _has_pointer_look:
			return Vector2.ZERO
		var viewport_center: Vector2 = (
			get_viewport().get_visible_rect().size * 0.5
		)
		var pointer_offset: Vector2 = (
			InputService.pointer_viewport_position() - viewport_center
		)
		return _pointer_look_target(pointer_offset)

	var direction_input: Vector2 = InputService.vector(ACTIONS.AIM)
	if direction_input.length_squared() > 0.0:
		_last_direction_look = direction_input.normalized()
		_has_direction_look = true
	if not _has_direction_look:
		return Vector2.ZERO
	return _last_direction_look * _look_max_offset


func _pointer_look_target(pointer_offset: Vector2) -> Vector2:
	var pointer_distance: float = pointer_offset.length()
	if pointer_distance <= _look_pointer_dead_zone:
		return Vector2.ZERO
	var pointer_magnitude: float = minf(
		(pointer_distance - _look_pointer_dead_zone)
		* _look_pointer_offset_ratio,
		_look_max_offset
	)
	return pointer_offset / pointer_distance * pointer_magnitude


func _apply_look_offset(offset: Vector2) -> void:
	_player_camera.follow_offset = offset
	if _target != null and is_instance_valid(_target):
		_target.call("set_camera_look_offset", offset)
	_apply_camera_position()


func _apply_camera_position() -> void:
	if not _look_configured or _target == null or not is_instance_valid(_target):
		return
	# Bundled Phantom Camera keeps GLUED deterministic but ignores follow_offset.
	# Apply that stable offset after its host update; Camera2D.offset stays noise-only.
	_camera.global_position = _target.global_position + _current_look_offset


func _reset_target_look_offset() -> void:
	set_process(false)
	set_physics_process(false)
	_look_configured = false
	_current_look_offset = Vector2.ZERO
	_player_camera.follow_offset = Vector2.ZERO
	if _target != null and is_instance_valid(_target):
		_target.call("set_camera_look_offset", Vector2.ZERO)
	_target = null


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


func _on_pointer_activity() -> void:
	if _look_configured:
		_has_pointer_look = true
