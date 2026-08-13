class_name LowpolyPlayer
extends CharacterBody3D

signal health_changed(current: float, maximum: float)
signal died

const COLLISION_LAYER_PLAYER: int = 1
const COLLISION_LAYER_ENEMY: int = 2
const COLLISION_LAYER_WORLD: int = 4

var max_health: float = 100.0
var health: float = 100.0
var base_move_speed: float = 8.5
var move_speed_multiplier: float = 1.0
var base_pickup_radius: float = 4.0
var pickup_radius_multiplier: float = 1.0
var arena_half_extent: float = 78.0
var active: bool = false
var _invulnerability_duration: float = 0.32
var _invulnerability_left: float = 0.0
var _hit_animation_cooldown: float = 0.22
var _hit_animation_cooldown_left: float = 0.0
var _model: Node3D
var _weapon_model: Node3D
var _animator: LowpolyModelAnimator


func _init() -> void:
	collision_layer = COLLISION_LAYER_PLAYER
	collision_mask = COLLISION_LAYER_ENEMY | COLLISION_LAYER_WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	safe_margin = 0.04


func setup(
	config: Dictionary,
	half_extent: float,
	weapon_model_path: String,
	animation_config: Dictionary
) -> void:
	max_health = float(config.get("max_health", 100.0))
	base_move_speed = float(config.get("move_speed", 8.5))
	base_pickup_radius = float(config.get("pickup_radius", 4.0))
	_invulnerability_duration = float(config.get("contact_invulnerability", 0.32))
	_hit_animation_cooldown = float(animation_config.get("hit_cooldown", 0.22))
	arena_half_extent = half_extent
	_build_body(String(config.get("model_path", "")), animation_config)
	_build_weapon(weapon_model_path)
	reset_for_run()


func reset_for_run() -> void:
	global_position = Vector3.ZERO
	velocity = Vector3.ZERO
	move_speed_multiplier = 1.0
	pickup_radius_multiplier = 1.0
	health = max_health
	_invulnerability_left = 0.0
	_hit_animation_cooldown_left = 0.0
	active = true
	visible = true
	if _animator != null:
		_animator.reset()
	health_changed.emit(health, max_health)


func set_run_active(value: bool) -> void:
	active = value
	if not value:
		velocity = Vector3.ZERO
		if _animator != null:
			_animator.set_locomotion(false)


func update_movement(delta: float, input_vector: Vector2) -> void:
	if not active:
		return
	_invulnerability_left = maxf(_invulnerability_left - delta, 0.0)
	_hit_animation_cooldown_left = maxf(_hit_animation_cooldown_left - delta, 0.0)
	var normalized_input: Vector2 = input_vector.limit_length(1.0)
	velocity = Vector3(normalized_input.x, 0.0, normalized_input.y) * get_move_speed()
	move_and_slide()
	global_position.x = clampf(global_position.x, -arena_half_extent, arena_half_extent)
	global_position.z = clampf(global_position.z, -arena_half_extent, arena_half_extent)
	global_position.y = 0.0
	if velocity.length_squared() > 0.01:
		look_at(global_position + Vector3(velocity.x, 0.0, velocity.z), Vector3.UP)
	if _animator != null:
		_animator.set_locomotion(
			not normalized_input.is_zero_approx(),
			get_move_speed() / maxf(base_move_speed, 0.01)
		)


func take_damage(amount: float, bypass_invulnerability: bool = false) -> bool:
	if not active or amount <= 0.0:
		return false
	if _invulnerability_left > 0.0 and not bypass_invulnerability:
		return false
	health = maxf(health - amount, 0.0)
	_invulnerability_left = _invulnerability_duration
	health_changed.emit(health, max_health)
	if health <= 0.0:
		active = false
		velocity = Vector3.ZERO
		if _animator != null:
			_animator.play_death()
		died.emit()
	elif _animator != null and _hit_animation_cooldown_left <= 0.0:
		_animator.play_one_shot(LowpolyModelAnimator.STATE_HIT)
		_hit_animation_cooldown_left = _hit_animation_cooldown
	return true


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func add_max_health(amount: float) -> void:
	if amount <= 0.0:
		return
	max_health += amount
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func get_move_speed() -> float:
	return base_move_speed * move_speed_multiplier


func get_pickup_radius() -> float:
	return base_pickup_radius * pickup_radius_multiplier


func play_fire_animation() -> bool:
	return _animator != null and _animator.play_one_shot(LowpolyModelAnimator.STATE_FIRE)


func set_animation_paused(value: bool) -> void:
	if _animator != null:
		_animator.set_paused(value)


func get_animation_state() -> StringName:
	return _animator.get_current_state() if _animator != null else &""


func get_animation_clip() -> StringName:
	return _animator.get_current_clip() if _animator != null else &""


func get_animation_position() -> float:
	return _animator.get_animation_position() if _animator != null else 0.0


func get_animation_missing_states() -> PackedStringArray:
	return _animator.get_missing_states() if _animator != null else PackedStringArray(["animator"])


func _build_body(model_path: String, animation_config: Dictionary) -> void:
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape"
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	if ResourceLoader.exists(model_path):
		var resource: Resource = load(model_path)
		if resource is PackedScene:
			_model = (resource as PackedScene).instantiate() as Node3D
	if _model == null:
		var fallback: MeshInstance3D = MeshInstance3D.new()
		var mesh: CapsuleMesh = CapsuleMesh.new()
		mesh.radius = 0.45
		mesh.height = 1.7
		fallback.mesh = mesh
		_model = fallback
	_model.position.y = 0.85
	add_child(_model)
	_animator = LowpolyModelAnimator.new()
	if not _animator.setup(_model, animation_config):
		push_warning("Player animation profile is incomplete: %s" % _animator.get_missing_states())


func _build_weapon(model_path: String) -> void:
	if not ResourceLoader.exists(model_path):
		return
	var resource := load(model_path)
	if not resource is PackedScene:
		return
	_weapon_model = (resource as PackedScene).instantiate() as Node3D
	if _weapon_model == null:
		return
	_weapon_model.name = "PulseRifleModel"
	var skeleton := _find_skeleton(_model)
	if skeleton != null and skeleton.find_bone("Middle1.R") >= 0:
		var attachment := BoneAttachment3D.new()
		attachment.name = "WeaponAttachment"
		attachment.bone_name = "Middle1.R"
		skeleton.add_child(attachment)
		_weapon_model.position = Vector3(0.0, 0.015, -0.16)
		_weapon_model.rotation_degrees = Vector3(0.0, 90.0, -8.0)
		_weapon_model.scale = Vector3.ONE * 0.38
		attachment.add_child(_weapon_model)
	else:
		_weapon_model.position = Vector3(0.28, 1.05, -0.28)
		_weapon_model.rotation_degrees = Vector3(0.0, 90.0, -8.0)
		_weapon_model.scale = Vector3.ONE * 0.42
		add_child(_weapon_model)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var result := _find_skeleton(child)
		if result != null:
			return result
	return null
