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
var network_entity_id: int = 0
var network_user_id: String = ""
var network_slot: int = 0
var network_connected: bool = true
var network_removed: bool = false
var _invulnerability_duration: float = 0.32
var _invulnerability_left: float = 0.0
var _hit_animation_cooldown: float = 0.22
var _hit_animation_cooldown_left: float = 0.0
var _model: Node3D
var _weapon_model: Node3D
var _weapon_mount: Node3D
var _weapon_skeleton: Skeleton3D
var _weapon_bone_index: int = -1
var _animator: LowpolyModelAnimator


func _init() -> void:
	collision_layer = COLLISION_LAYER_PLAYER
	collision_mask = COLLISION_LAYER_ENEMY | COLLISION_LAYER_WORLD
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	safe_margin = 0.04


func _process(_delta: float) -> void:
	_sync_weapon_mount()


func setup(
	config: Dictionary,
	half_extent: float,
	weapon_config: Dictionary,
	animation_config: Dictionary
) -> void:
	max_health = float(config.get("max_health", 100.0))
	base_move_speed = float(config.get("move_speed", 8.5))
	base_pickup_radius = float(config.get("pickup_radius", 4.0))
	_invulnerability_duration = float(config.get("contact_invulnerability", 0.32))
	_hit_animation_cooldown = float(animation_config.get("hit_cooldown", 0.22))
	arena_half_extent = half_extent
	_build_body(
		String(config.get("model_path", "")),
		float(config.get("model_yaw_degrees", 0.0)),
		animation_config
	)
	_build_weapon(weapon_config)
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
	network_connected = true
	network_removed = false
	visible = true
	if _animator != null:
		_animator.reset()
	health_changed.emit(health, max_health)


func set_run_active(value: bool) -> void:
	active = value and network_connected and not network_removed and health > 0.0
	if not value:
		velocity = Vector3.ZERO
		if _animator != null:
			_animator.set_locomotion(false)


func update_movement(delta: float, input_vector: Vector2) -> void:
	if not is_combat_available():
		return
	_invulnerability_left = maxf(_invulnerability_left - delta, 0.0)
	_hit_animation_cooldown_left = maxf(_hit_animation_cooldown_left - delta, 0.0)
	var normalized_input: Vector2 = input_vector.limit_length(1.0)
	velocity = Vector3(normalized_input.x, 0.0, normalized_input.y) * get_move_speed()
	# Use the supplied simulation delta so host authority, client prediction and
	# rollback replay advance by the same amount even outside the local physics tick.
	var collision := move_and_collide(velocity * maxf(delta, 0.0), false, safe_margin, true)
	if collision != null:
		var slide_motion := collision.get_remainder().slide(collision.get_normal())
		if slide_motion.length_squared() > 0.000001:
			move_and_collide(slide_motion)
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
	if not is_combat_available() or amount <= 0.0:
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


func set_network_identity(entity_id: int, user_id: String, slot: int) -> void:
	network_entity_id = entity_id
	network_user_id = user_id
	network_slot = slot


func set_network_connected(value: bool) -> void:
	network_connected = value
	if not value:
		active = false
		velocity = Vector3.ZERO
		if _animator != null:
			_animator.set_locomotion(false)
	elif not network_removed and health > 0.0:
		active = true


func remove_network_slot() -> void:
	network_removed = true
	network_connected = false
	active = false
	velocity = Vector3.ZERO
	visible = false


func is_combat_available() -> bool:
	return active and network_connected and not network_removed and health > 0.0


func make_network_state() -> Dictionary:
	return {
		"entity_id": network_entity_id,
		"user_id": network_user_id,
		"slot": network_slot,
		"position": [global_position.x, global_position.y, global_position.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"health": health,
		"max_health": max_health,
		"connected": network_connected,
		"removed": network_removed,
		"active": active,
	}


func apply_network_state(snapshot: Dictionary, interpolate_weight: float = 1.0) -> void:
	network_entity_id = int(snapshot.get("entity_id", network_entity_id))
	network_user_id = String(snapshot.get("user_id", network_user_id))
	network_slot = int(snapshot.get("slot", network_slot))
	var position_values: Array = snapshot.get("position", [])
	if position_values.size() == 3:
		var target := Vector3(
			float(position_values[0]), float(position_values[1]), float(position_values[2])
		)
		global_position = global_position.lerp(target, clampf(interpolate_weight, 0.0, 1.0))
	var velocity_values: Array = snapshot.get("velocity", [])
	if velocity_values.size() == 3:
		velocity = Vector3(
			float(velocity_values[0]), float(velocity_values[1]), float(velocity_values[2])
		)
	max_health = float(snapshot.get("max_health", max_health))
	health = clampf(float(snapshot.get("health", health)), 0.0, max_health)
	network_connected = bool(snapshot.get("connected", network_connected))
	network_removed = bool(snapshot.get("removed", network_removed))
	active = bool(snapshot.get("active", active)) and network_connected and not network_removed
	visible = not network_removed
	health_changed.emit(health, max_health)


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


func get_weapon_world_visual_size() -> Vector3:
	return _get_node_world_visual_size(_weapon_model)


func get_body_world_visual_size() -> Vector3:
	return _get_node_world_visual_size(_model)


func get_visual_forward_direction() -> Vector3:
	return _model.global_basis.z.normalized() if is_instance_valid(_model) else Vector3.ZERO


func _get_node_world_visual_size(node: Node3D) -> Vector3:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return Vector3.ZERO
	var bounds: Array[AABB] = []
	_collect_world_bounds(node, bounds)
	if bounds.is_empty():
		return Vector3.ZERO
	var merged := bounds[0]
	for index: int in range(1, bounds.size()):
		merged = merged.merge(bounds[index])
	return merged.size


func _build_body(
	model_path: String,
	model_yaw_degrees: float,
	animation_config: Dictionary
) -> void:
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
	_model.rotation_degrees.y = model_yaw_degrees
	add_child(_model)
	_animator = LowpolyModelAnimator.new()
	if not _animator.setup(_model, animation_config):
		push_warning("Player animation profile is incomplete: %s" % _animator.get_missing_states())


func _build_weapon(config: Dictionary) -> void:
	var model_path := String(config.get("model_path", ""))
	if not ResourceLoader.exists(model_path):
		return
	var resource := load(model_path)
	if not resource is PackedScene:
		return
	_weapon_model = (resource as PackedScene).instantiate() as Node3D
	if _weapon_model == null:
		return
	_weapon_model.name = "PulseRifleModel"
	var source_bounds := _model_local_bounds(_weapon_model)
	var source_length := maxf(source_bounds.size.x, maxf(source_bounds.size.y, source_bounds.size.z))
	var target_length := float(config.get("visual_length", 0.92))
	var uniform_scale := target_length / source_length if source_length > 0.001 else 0.05
	var skeleton := _find_skeleton(_model)
	if skeleton != null and skeleton.find_bone("Middle1.R") >= 0:
		_weapon_skeleton = skeleton
		_weapon_bone_index = skeleton.find_bone("Middle1.R")
		_weapon_mount = Node3D.new()
		_weapon_mount.name = "WeaponAttachment"
		_weapon_mount.top_level = true
		add_child(_weapon_mount)
		_weapon_model.position = Vector3(0.0, 0.015, -0.16)
		_weapon_model.rotation_degrees = Vector3(0.0, 90.0, -8.0)
		_weapon_model.scale = Vector3.ONE * uniform_scale
		_weapon_mount.add_child(_weapon_model)
		_sync_weapon_mount()
	else:
		_weapon_model.position = Vector3(0.28, 1.05, -0.28)
		_weapon_model.rotation_degrees = Vector3(0.0, 90.0, -8.0)
		_weapon_model.scale = Vector3.ONE * uniform_scale
		add_child(_weapon_model)


func _sync_weapon_mount() -> void:
	if (
		not is_instance_valid(_weapon_mount)
		or not is_instance_valid(_weapon_skeleton)
		or _weapon_bone_index < 0
		or not _weapon_skeleton.is_inside_tree()
	):
		return
	var bone_world := (
		_weapon_skeleton.global_transform
		* _weapon_skeleton.get_bone_global_pose(_weapon_bone_index)
	)
	_weapon_mount.global_transform = Transform3D(bone_world.basis.orthonormalized(), bone_world.origin)


func _model_local_bounds(model: Node3D) -> AABB:
	var bounds: Array[AABB] = []
	_collect_model_bounds(model, Transform3D.IDENTITY, bounds)
	if bounds.is_empty():
		return AABB()
	var merged := bounds[0]
	for index: int in range(1, bounds.size()):
		merged = merged.merge(bounds[index])
	return merged


func _collect_model_bounds(
	node: Node,
	transform_to_root: Transform3D,
	bounds: Array[AABB]
) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			bounds.append(transform_to_root * mesh_instance.get_aabb())
	for child: Node in node.get_children():
		var child_transform := transform_to_root
		if child is Node3D:
			child_transform *= (child as Node3D).transform
		_collect_model_bounds(child, child_transform, bounds)


func _collect_world_bounds(node: Node, bounds: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			bounds.append(mesh_instance.global_transform * mesh_instance.get_aabb())
	for child: Node in node.get_children():
		_collect_world_bounds(child, bounds)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var result := _find_skeleton(child)
		if result != null:
			return result
	return null
