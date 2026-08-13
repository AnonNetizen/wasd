class_name LowpolyProjectile
extends Node3D

enum Team { PLAYER, ENEMY }

var team: Team = Team.PLAYER
var direction: Vector3 = Vector3.FORWARD
var speed: float = 10.0
var damage: float = 1.0
var hit_radius: float = 0.35
var lifetime: float = 2.0
var pierce_left: int = 0
var active: bool = false
var network_entity_id: int = 0
var owner_slot: int = -1
var hit_ids: Dictionary = {}
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _init() -> void:
	_mesh_instance = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.18
	mesh.height = 0.36
	_mesh_instance.mesh = mesh
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)


func activate_from_pool(payload: Dictionary) -> void:
	team = int(payload.get("team", Team.PLAYER)) as Team
	global_position = payload.get("position", Vector3.ZERO) as Vector3
	direction = (payload.get("direction", Vector3.FORWARD) as Vector3).normalized()
	direction.y = 0.0
	speed = float(payload.get("speed", 10.0))
	damage = float(payload.get("damage", 1.0))
	hit_radius = float(payload.get("hit_radius", 0.35))
	lifetime = float(payload.get("lifetime", 2.0))
	pierce_left = int(payload.get("pierce", 0))
	network_entity_id = int(payload.get("network_entity_id", 0))
	owner_slot = int(payload.get("owner_slot", -1))
	hit_ids.clear()
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	var color: Color = Color(0.2, 0.9, 1.0) if team == Team.PLAYER else Color(1.0, 0.25, 0.12)
	_material.albedo_color = color
	_material.emission = color


func deactivate_to_pool() -> void:
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	hit_ids.clear()
	network_entity_id = 0
	owner_slot = -1


func advance(delta: float) -> bool:
	if not active:
		return false
	global_position += direction * speed * delta
	lifetime -= delta
	return lifetime > 0.0


func register_hit(target: Node) -> bool:
	if not active or not is_instance_valid(target):
		return false
	var target_id: int = target.get_instance_id()
	if hit_ids.has(target_id):
		return false
	hit_ids[target_id] = true
	pierce_left -= 1
	return true


func should_release_after_hit() -> bool:
	return pierce_left < 0


func is_pool_active() -> bool:
	return active


func make_network_state() -> Dictionary:
	return {
		"entity_id": network_entity_id,
		"team": int(team),
		"owner_slot": owner_slot,
		"position": [global_position.x, global_position.y, global_position.z],
		"direction": [direction.x, direction.y, direction.z],
		"speed": speed,
		"damage": damage,
		"hit_radius": hit_radius,
		"lifetime": lifetime,
		"pierce": pierce_left,
	}


func apply_network_state(snapshot: Dictionary) -> void:
	network_entity_id = int(snapshot.get("entity_id", network_entity_id))
	owner_slot = int(snapshot.get("owner_slot", owner_slot))
	var position_values: Array = snapshot.get("position", [])
	if position_values.size() == 3:
		global_position = Vector3(
			float(position_values[0]), float(position_values[1]), float(position_values[2])
		)
	var direction_values: Array = snapshot.get("direction", [])
	if direction_values.size() == 3:
		direction = Vector3(
			float(direction_values[0]), float(direction_values[1]), float(direction_values[2])
		).normalized()
	speed = float(snapshot.get("speed", speed))
	damage = float(snapshot.get("damage", damage))
	hit_radius = float(snapshot.get("hit_radius", hit_radius))
	lifetime = float(snapshot.get("lifetime", lifetime))
	pierce_left = int(snapshot.get("pierce", pierce_left))
