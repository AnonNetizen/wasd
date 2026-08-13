class_name LowpolyEnemy
extends CharacterBody3D

signal died(enemy: LowpolyEnemy, experience_reward: int)
signal health_changed(current: float, maximum: float)
signal damage_player_requested(amount: float)
signal projectile_volley_requested(
	origin: Vector3,
	direction: Vector3,
	speed: float,
	damage: float,
	count: int,
	spread_degrees: float,
	radial: bool
)
signal minions_requested(count: int)

var enemy_id: StringName = &"enemy_small"
var max_health: float = 1.0
var health: float = 1.0
var move_speed: float = 1.0
var contact_damage: float = 1.0
var attack_cooldown: float = 1.0
var collision_radius: float = 0.5
var experience_reward: int = 1
var preferred_range: float = 0.0
var projectile_speed: float = 10.0
var flying_height: float = 0.0
var elite: bool = false
var boss: bool = false
var active: bool = false
var player: LowpolyPlayer
var _attack_left: float = 0.0
var _pattern_index: int = 0
var _separation_velocity: Vector3 = Vector3.ZERO
var _model: Node3D
var _model_path: String = ""


func activate_from_pool(payload: Dictionary) -> void:
	enemy_id = StringName(payload.get("enemy_id", "enemy_small"))
	var config: Dictionary = payload.get("config", {}) as Dictionary
	player = payload.get("player") as LowpolyPlayer
	elite = bool(payload.get("elite", false))
	boss = bool(payload.get("boss", false))
	max_health = float(config.get("health", 1.0))
	move_speed = float(config.get("speed", 1.0))
	contact_damage = float(config.get("damage", 1.0))
	attack_cooldown = float(config.get("attack_cooldown", 1.0))
	collision_radius = float(config.get("radius", 0.5))
	experience_reward = int(config.get("xp", 1))
	preferred_range = float(config.get("preferred_range", 0.0))
	projectile_speed = float(config.get("projectile_speed", 10.0))
	flying_height = float(config.get("flying_height", 0.0))
	if elite:
		max_health *= 3.2
		move_speed *= 1.12
		contact_damage *= 1.45
		experience_reward *= 5
	health = max_health
	global_position = payload.get("position", Vector3.ZERO) as Vector3
	global_position.y = flying_height
	_attack_left = attack_cooldown * 0.45
	_pattern_index = 0
	_separation_velocity = Vector3.ZERO
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_set_model(String(config.get("model_path", "")))
	var base_scale: float = 1.0
	if enemy_id == &"enemy_large":
		base_scale = 1.35
	elif boss:
		base_scale = 2.4
	elif elite:
		base_scale = 1.5
	scale = Vector3.ONE * base_scale
	health_changed.emit(health, max_health)


func deactivate_to_pool() -> void:
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	velocity = Vector3.ZERO
	player = null
	elite = false
	boss = false
	scale = Vector3.ONE


func update_enemy(delta: float, nearby: Array[Node3D]) -> void:
	if not active or not is_instance_valid(player) or not player.active:
		return
	_attack_left -= delta
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var distance_to_player: float = to_player.length()
	var desired_direction: Vector3 = to_player.normalized() if distance_to_player > 0.01 else Vector3.ZERO
	_separation_velocity = _calculate_separation(nearby)
	if preferred_range > 0.0:
		if distance_to_player < preferred_range * 0.72:
			desired_direction = -desired_direction
		elif distance_to_player <= preferred_range * 1.12:
			desired_direction = desired_direction.cross(Vector3.UP) * (1.0 if get_instance_id() % 2 == 0 else -1.0)
	velocity = (desired_direction + _separation_velocity).limit_length(1.0) * move_speed
	move_and_slide()
	global_position.y = flying_height
	if not desired_direction.is_zero_approx():
		look_at(global_position + desired_direction, Vector3.UP)
	if distance_to_player <= collision_radius + 0.65 and _attack_left <= 0.0:
		damage_player_requested.emit(contact_damage)
		_attack_left = attack_cooldown
	if boss:
		_update_boss_attack(distance_to_player, to_player)
	elif enemy_id == &"enemy_fox_mech" and distance_to_player <= preferred_range * 1.45 and _attack_left <= 0.0:
		projectile_volley_requested.emit(
			global_position + Vector3.UP, to_player.normalized(), projectile_speed,
			contact_damage, 1, 0.0, false
		)
		_attack_left = attack_cooldown


func take_damage(amount: float) -> bool:
	if not active or amount <= 0.0:
		return false
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		active = false
		died.emit(self, experience_reward)
	return true


func is_pool_active() -> bool:
	return active


func get_collision_radius() -> float:
	return collision_radius * scale.x


func _update_boss_attack(distance_to_player: float, to_player: Vector3) -> void:
	if _attack_left > 0.0 or distance_to_player > 38.0:
		return
	var phase_multiplier: float = 0.65 if health <= max_health * 0.5 else 1.0
	match _pattern_index % 3:
		0:
			projectile_volley_requested.emit(
				global_position + Vector3.UP * 1.2, to_player.normalized(), projectile_speed,
				contact_damage * 0.7, 5, 12.0, false
			)
		1:
			projectile_volley_requested.emit(
				global_position + Vector3.UP * 1.2, Vector3.FORWARD, projectile_speed * 0.82,
				contact_damage * 0.55, 16, 0.0, true
			)
		2:
			minions_requested.emit(4 if health > max_health * 0.5 else 7)
		_:
			pass
	_pattern_index += 1
	_attack_left = attack_cooldown * phase_multiplier


func _calculate_separation(nearby: Array[Node3D]) -> Vector3:
	var separation: Vector3 = Vector3.ZERO
	var samples: int = 0
	for neighbor: Node3D in nearby:
		if neighbor == self or not neighbor is LowpolyEnemy:
			continue
		var offset: Vector3 = global_position - neighbor.global_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared <= 0.001 or distance_squared > 2.8 * 2.8:
			continue
		separation += offset.normalized() / maxf(distance_squared, 0.1)
		samples += 1
		if samples >= 8:
			break
	return separation * 1.35


func _set_model(path: String) -> void:
	if _model != null and path == _model_path:
		return
	if is_instance_valid(_model):
		_model.queue_free()
	_model = null
	_model_path = path
	if ResourceLoader.exists(path):
		var resource: Resource = load(path)
		if resource is PackedScene:
			_model = (resource as PackedScene).instantiate() as Node3D
	if _model == null:
		var fallback: MeshInstance3D = MeshInstance3D.new()
		var mesh: CapsuleMesh = CapsuleMesh.new()
		mesh.radius = collision_radius
		mesh.height = collision_radius * 2.2
		fallback.mesh = mesh
		_model = fallback
	_model.position.y = maxf(collision_radius, 0.45)
	add_child(_model)
	_play_preferred_animation(_model, ["walk", "run", "idle"])


func _play_preferred_animation(node: Node, preferred: Array[String]) -> void:
	var animation_player := _find_animation_player(node)
	if animation_player == null:
		return
	var animation_names := animation_player.get_animation_list()
	for keyword: String in preferred:
		for animation_name: StringName in animation_names:
			if keyword in String(animation_name).to_lower():
				animation_player.play(animation_name)
				return
	for animation_name: StringName in animation_names:
		if animation_name != &"RESET":
			animation_player.play(animation_name)
			return


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var result := _find_animation_player(child)
		if result != null:
			return result
	return null
