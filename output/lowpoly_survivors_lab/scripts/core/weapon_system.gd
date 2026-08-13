class_name LowpolyWeaponSystem
extends Node3D

signal levels_changed(snapshot: Dictionary)

const WEAPON_IDS: Array[StringName] = [&"pulse_rifle", &"orbital_drone", &"ion_pulse"]
const PASSIVE_IDS: Array[StringName] = [
	&"passive_damage", &"passive_cooldown", &"passive_move_speed",
	&"passive_max_health", &"passive_pickup_range"
]

var _director: Node
var _player: LowpolyPlayer
var _balance: LowpolyBalanceLoader
var _levels: Dictionary = {}
var _pulse_cooldown_left: float = 0.0
var _drone_cooldown_left: float = 0.0
var _ion_cooldown_left: float = 0.0
var _pending_second_ion: float = -1.0
var _drone_angle: float = 0.0
var _drone_visuals: Array[MeshInstance3D] = []


func setup(director: Node, player: LowpolyPlayer, balance: LowpolyBalanceLoader) -> void:
	_director = director
	_player = player
	_balance = balance
	reset()


func reset() -> void:
	_levels.clear()
	for weapon_id: StringName in WEAPON_IDS:
		_levels[weapon_id] = 1 if weapon_id == &"pulse_rifle" else 0
	for passive_id: StringName in PASSIVE_IDS:
		_levels[passive_id] = 0
	_pulse_cooldown_left = 0.1
	_drone_cooldown_left = 0.0
	_ion_cooldown_left = 0.5
	_pending_second_ion = -1.0
	_drone_angle = 0.0
	_refresh_player_modifiers()
	_refresh_drone_visuals()
	levels_changed.emit(get_levels())


func update_weapons(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.active:
		return
	_pulse_cooldown_left -= delta
	_drone_cooldown_left -= delta
	_ion_cooldown_left -= delta
	if _pending_second_ion >= 0.0:
		_pending_second_ion -= delta
		if _pending_second_ion <= 0.0:
			_fire_ion_pulse()
			_pending_second_ion = -1.0
	_update_pulse_rifle()
	_update_orbital_drone(delta)
	_update_ion_pulse()


func apply_upgrade(upgrade_id: StringName) -> bool:
	if not _levels.has(upgrade_id):
		return false
	var config: Dictionary = _get_upgrade_config(upgrade_id)
	var current_level: int = int(_levels[upgrade_id])
	var max_level: int = int(config.get("max_level", 0))
	if current_level >= max_level:
		return false
	_levels[upgrade_id] = current_level + 1
	if upgrade_id == &"passive_max_health":
		_player.add_max_health(float(config.get("per_level", 15.0)))
	_refresh_player_modifiers()
	_refresh_drone_visuals()
	levels_changed.emit(get_levels())
	return true


func get_upgrade_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item_id: StringName in WEAPON_IDS + PASSIVE_IDS:
		var config: Dictionary = _get_upgrade_config(item_id)
		var current_level: int = int(_levels.get(item_id, 0))
		var max_level: int = int(config.get("max_level", 0))
		if current_level >= max_level:
			continue
		result.append({
			"id": item_id,
			"name": String(config.get("name", item_id)),
			"description": String(config.get("description", "")),
			"level": current_level,
			"next_level": current_level + 1,
			"max_level": max_level,
		})
	return result


func get_levels() -> Dictionary:
	return _levels.duplicate(true)


func get_damage_multiplier() -> float:
	var config: Dictionary = _balance.get_passive_config(&"passive_damage")
	return 1.0 + float(config.get("per_level", 0.12)) * int(_levels.get(&"passive_damage", 0))


func get_cooldown_multiplier() -> float:
	var config: Dictionary = _balance.get_passive_config(&"passive_cooldown")
	return maxf(0.35, 1.0 - float(config.get("per_level", 0.08)) * int(_levels.get(&"passive_cooldown", 0)))


func _update_pulse_rifle() -> void:
	var level: int = int(_levels.get(&"pulse_rifle", 0))
	if level <= 0 or _pulse_cooldown_left > 0.0:
		return
	var config: Dictionary = _balance.get_weapon_config(&"pulse_rifle")
	var target: Node3D = _director.call(
		"find_nearest_enemy", _player.global_position, float(config.get("range", 34.0))
	) as Node3D
	if target == null:
		return
	var direction: Vector3 = target.global_position - _player.global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		return
	var projectile_count: int = 1 + (1 if level >= 3 else 0) + (1 if level >= 5 else 0)
	var pierce: int = 1 if level >= 4 else 0
	var damage: float = float(config.get("base_damage", 13.0)) * (1.0 + 0.22 * (level - 1))
	if level >= 5:
		damage *= 1.35
	for index: int in range(projectile_count):
		var offset: float = float(index) - float(projectile_count - 1) * 0.5
		var shot_direction: Vector3 = direction.normalized().rotated(Vector3.UP, deg_to_rad(offset * 8.0))
		_director.call("spawn_player_projectile", {
			"position": _player.global_position + Vector3.UP * 0.8,
			"direction": shot_direction,
			"speed": float(config.get("projectile_speed", 24.0)),
			"damage": damage * get_damage_multiplier(),
			"pierce": pierce,
			"lifetime": float(config.get("range", 34.0)) / float(config.get("projectile_speed", 24.0)),
		})
	_pulse_cooldown_left = (
		float(config.get("cooldown", 0.42)) * pow(0.88, level - 1) * get_cooldown_multiplier()
	)


func _update_orbital_drone(delta: float) -> void:
	var level: int = int(_levels.get(&"orbital_drone", 0))
	if level <= 0:
		return
	var config: Dictionary = _balance.get_weapon_config(&"orbital_drone")
	_drone_angle = fmod(_drone_angle + delta * (1.7 + level * 0.18), TAU)
	var count: int = _drone_count(level)
	var radius: float = float(config.get("radius", 4.2)) + 0.2 * level
	for index: int in range(count):
		var angle: float = _drone_angle + TAU * float(index) / float(count)
		var position: Vector3 = _player.global_position + Vector3(cos(angle), 0.85, sin(angle)) * radius
		if index < _drone_visuals.size():
			_drone_visuals[index].global_position = position
	if _drone_cooldown_left > 0.0:
		return
	var damage: float = float(config.get("base_damage", 10.0)) * (1.0 + 0.28 * (level - 1)) * get_damage_multiplier()
	for visual: MeshInstance3D in _drone_visuals:
		_director.call("damage_enemies_in_radius", visual.global_position, 1.05, damage)
	_drone_cooldown_left = float(config.get("cooldown", 0.34)) * get_cooldown_multiplier()


func _update_ion_pulse() -> void:
	var level: int = int(_levels.get(&"ion_pulse", 0))
	if level <= 0 or _ion_cooldown_left > 0.0:
		return
	_fire_ion_pulse()
	var config: Dictionary = _balance.get_weapon_config(&"ion_pulse")
	_ion_cooldown_left = float(config.get("cooldown", 5.2)) * pow(0.91, level - 1) * get_cooldown_multiplier()
	if level >= 5:
		_pending_second_ion = 0.28


func _fire_ion_pulse() -> void:
	var level: int = int(_levels.get(&"ion_pulse", 0))
	var config: Dictionary = _balance.get_weapon_config(&"ion_pulse")
	var radius: float = float(config.get("radius", 7.0)) * (1.0 + 0.09 * (level - 1))
	var damage: float = float(config.get("base_damage", 22.0)) * (1.0 + 0.30 * (level - 1)) * get_damage_multiplier()
	_director.call("damage_enemies_in_radius", _player.global_position, radius, damage)
	_director.call("spawn_effect", _player.global_position, radius, Color(0.2, 0.75, 1.0), 0.32)


func _refresh_player_modifiers() -> void:
	if not is_instance_valid(_player) or _balance == null:
		return
	var move_config: Dictionary = _balance.get_passive_config(&"passive_move_speed")
	_player.move_speed_multiplier = 1.0 + float(move_config.get("per_level", 0.08)) * int(_levels.get(&"passive_move_speed", 0))
	var pickup_config: Dictionary = _balance.get_passive_config(&"passive_pickup_range")
	_player.pickup_radius_multiplier = 1.0 + float(pickup_config.get("per_level", 0.20)) * int(_levels.get(&"passive_pickup_range", 0))


func _refresh_drone_visuals() -> void:
	var count: int = _drone_count(int(_levels.get(&"orbital_drone", 0)))
	while _drone_visuals.size() < count:
		var visual: MeshInstance3D = MeshInstance3D.new()
		var mesh: SphereMesh = SphereMesh.new()
		mesh.radius = 0.28
		mesh.height = 0.56
		visual.mesh = mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.9, 0.75, 0.15)
		material.emission_enabled = true
		material.emission = Color(0.9, 0.5, 0.08)
		visual.material_override = material
		add_child(visual)
		_drone_visuals.append(visual)
	for index: int in range(_drone_visuals.size()):
		_drone_visuals[index].visible = index < count


func _drone_count(level: int) -> int:
	if level <= 0:
		return 0
	return 1 + (1 if level >= 2 else 0) + (1 if level >= 4 else 0) + (1 if level >= 5 else 0)


func _get_upgrade_config(upgrade_id: StringName) -> Dictionary:
	if WEAPON_IDS.has(upgrade_id):
		return _balance.get_weapon_config(upgrade_id)
	return _balance.get_passive_config(upgrade_id)
