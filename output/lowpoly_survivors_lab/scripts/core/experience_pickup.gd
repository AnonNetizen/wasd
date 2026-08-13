class_name LowpolyExperiencePickup
extends Node3D

enum Kind { EXPERIENCE, HEALTH }

var kind: Kind = Kind.EXPERIENCE
var amount: int = 1
var active: bool = false
var network_entity_id: int = 0
var attraction_speed: float = 13.0
var _model: Node3D
var _model_kind: int = -1


func activate_from_pool(payload: Dictionary) -> void:
	kind = int(payload.get("kind", Kind.EXPERIENCE)) as Kind
	amount = int(payload.get("amount", 1))
	network_entity_id = int(payload.get("network_entity_id", 0))
	global_position = payload.get("position", Vector3.ZERO) as Vector3
	global_position.y = 0.35
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_ensure_model()


func deactivate_to_pool() -> void:
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	network_entity_id = 0


func update_pickup(delta: float, player_position: Vector3, pickup_radius: float) -> bool:
	if not active:
		return false
	rotate_y(delta * 2.8)
	var offset: Vector3 = player_position - global_position
	offset.y = 0.0
	if offset.length() <= pickup_radius and not offset.is_zero_approx():
		global_position += offset.normalized() * attraction_speed * delta
	return offset.length_squared() <= 0.75 * 0.75


func is_pool_active() -> bool:
	return active


func make_network_state() -> Dictionary:
	return {
		"entity_id": network_entity_id,
		"kind": int(kind),
		"amount": amount,
		"position": [global_position.x, global_position.y, global_position.z],
	}


func apply_network_state(snapshot: Dictionary) -> void:
	network_entity_id = int(snapshot.get("entity_id", network_entity_id))
	kind = int(snapshot.get("kind", int(kind))) as Kind
	amount = int(snapshot.get("amount", amount))
	var position_values: Array = snapshot.get("position", [])
	if position_values.size() == 3:
		global_position = Vector3(
			float(position_values[0]), float(position_values[1]), float(position_values[2])
		)
	_ensure_model()


func _ensure_model() -> void:
	if _model != null and _model_kind == kind:
		return
	if is_instance_valid(_model):
		_model.queue_free()
	var path := "res://assets/models/pickup_experience_sphere.glb"
	var fallback_color := Color(0.25, 1.0, 0.72)
	if kind == Kind.HEALTH:
		path = "res://assets/models/pickup_health.glb"
		fallback_color = Color(1.0, 0.2, 0.3)
	_model = _instantiate_model(path, fallback_color)
	_model_kind = kind
	add_child(_model)


func _instantiate_model(path: String, fallback_color: Color) -> Node3D:
	if ResourceLoader.exists(path):
		var resource := load(path)
		if resource is PackedScene:
			var instance := (resource as PackedScene).instantiate() as Node3D
			if instance != null:
				instance.scale = Vector3.ONE * 0.65
				return instance
	var fallback := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.24
	mesh.height = 0.48
	fallback.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = fallback_color
	material.emission_enabled = true
	material.emission = fallback_color
	fallback.material_override = material
	return fallback
