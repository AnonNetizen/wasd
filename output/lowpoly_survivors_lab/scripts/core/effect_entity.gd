class_name LowpolyEffectEntity
extends Node3D

var active: bool = false
var lifetime: float = 0.0
var total_lifetime: float = 0.0
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _init() -> void:
	_mesh_instance = MeshInstance3D.new()
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	_mesh_instance.mesh = mesh
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.emission_enabled = true
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)


func activate_from_pool(payload: Dictionary) -> void:
	global_position = payload.get("position", Vector3.ZERO) as Vector3
	var size: float = float(payload.get("size", 1.0))
	scale = Vector3.ONE * size
	lifetime = float(payload.get("lifetime", 0.22))
	total_lifetime = lifetime
	var color: Color = payload.get("color", Color.WHITE) as Color
	_material.albedo_color = Color(color, 0.55)
	_material.emission = color
	active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT


func deactivate_to_pool() -> void:
	active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	scale = Vector3.ONE


func advance(delta: float) -> bool:
	if not active:
		return false
	lifetime -= delta
	scale *= 1.0 + delta * 3.0
	return lifetime > 0.0


func is_pool_active() -> bool:
	return active
