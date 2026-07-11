extends Node3D

## Drives deterministic torch-flame motion and light flicker for the dungeon room.

const FLAME_GROUP: StringName = &"dungeon_flame"
const TORCH_LIGHT_GROUP: StringName = &"dungeon_torch_light"
const NODE_PHASE_STEP: float = 1.618
const FLAME_WIDTH_SCALE_AMOUNT: float = 0.018
const FLAME_HEIGHT_SCALE_AMOUNT: float = 0.052
const FLAME_SWAY_AMOUNT: float = 0.018
const FLAME_LIFT_AMOUNT: float = 0.012
const LIGHT_ENERGY_AMOUNT: float = 0.105
const LIGHT_SWAY_AMOUNT: float = 0.014

var _elapsed_time: float = 0.0
var _flames: Array[MeshInstance3D] = []
var _flame_base_scales: Array[Vector3] = []
var _flame_base_positions: Array[Vector3] = []
var _torch_lights: Array[OmniLight3D] = []
var _torch_light_base_energies: Array[float] = []
var _torch_light_base_positions: Array[Vector3] = []


func _ready() -> void:
	_collect_flames()
	_collect_torch_lights()


func _process(delta: float) -> void:
	_elapsed_time += maxf(delta, 0.0)
	_update_flames()
	_update_torch_lights()


func flame_count() -> int:
	return _flames.size()


func torch_light_count() -> int:
	return _torch_lights.size()


func _collect_flames() -> void:
	_flames.clear()
	_flame_base_scales.clear()
	_flame_base_positions.clear()

	var grouped_nodes: Array[Node] = get_tree().get_nodes_in_group(FLAME_GROUP)
	grouped_nodes.sort_custom(_sort_nodes_by_path)
	for node: Node in grouped_nodes:
		if node is not MeshInstance3D:
			continue
		var flame: MeshInstance3D = node as MeshInstance3D
		_flames.append(flame)
		_flame_base_scales.append(flame.scale)
		_flame_base_positions.append(flame.position)


func _collect_torch_lights() -> void:
	_torch_lights.clear()
	_torch_light_base_energies.clear()
	_torch_light_base_positions.clear()

	var grouped_nodes: Array[Node] = get_tree().get_nodes_in_group(TORCH_LIGHT_GROUP)
	grouped_nodes.sort_custom(_sort_nodes_by_path)
	for node: Node in grouped_nodes:
		if node is not OmniLight3D:
			continue
		var torch_light: OmniLight3D = node as OmniLight3D
		_torch_lights.append(torch_light)
		_torch_light_base_energies.append(torch_light.light_energy)
		_torch_light_base_positions.append(torch_light.position)


func _update_flames() -> void:
	for index: int in _flames.size():
		var flame: MeshInstance3D = _flames[index]
		if not is_instance_valid(flame):
			continue
		var phase: float = float(index) * NODE_PHASE_STEP
		var primary_wave: float = sin(_elapsed_time * 7.1 + phase)
		var secondary_wave: float = sin(_elapsed_time * 11.9 + phase * 1.7)
		var slow_wave: float = sin(_elapsed_time * 3.7 + phase * 0.63)
		var shape_wave: float = primary_wave * 0.55 + secondary_wave * 0.28 + slow_wave * 0.17
		var width_factor: float = 1.0 - shape_wave * FLAME_WIDTH_SCALE_AMOUNT
		var height_factor: float = 1.0 + shape_wave * FLAME_HEIGHT_SCALE_AMOUNT
		var base_scale: Vector3 = _flame_base_scales[index]
		flame.scale = Vector3(
			base_scale.x * width_factor,
			base_scale.y * height_factor,
			base_scale.z * width_factor
		)

		var base_position: Vector3 = _flame_base_positions[index]
		var sway_x: float = sin(_elapsed_time * 8.3 + phase * 1.31) * FLAME_SWAY_AMOUNT
		var sway_z: float = sin(_elapsed_time * 9.7 + phase * 1.93) * FLAME_SWAY_AMOUNT
		var lift: float = sin(_elapsed_time * 6.1 + phase * 0.79) * FLAME_LIFT_AMOUNT
		flame.position = base_position + Vector3(sway_x, lift, sway_z)


func _update_torch_lights() -> void:
	for index: int in _torch_lights.size():
		var torch_light: OmniLight3D = _torch_lights[index]
		if not is_instance_valid(torch_light):
			continue
		var phase: float = float(index) * NODE_PHASE_STEP
		var primary_wave: float = sin(_elapsed_time * 6.7 + phase)
		var secondary_wave: float = sin(_elapsed_time * 10.9 + phase * 1.53)
		var slow_wave: float = sin(_elapsed_time * 2.9 + phase * 0.71)
		var energy_wave: float = primary_wave * 0.58 + secondary_wave * 0.27 + slow_wave * 0.15
		var base_energy: float = _torch_light_base_energies[index]
		torch_light.light_energy = maxf(base_energy * (1.0 + energy_wave * LIGHT_ENERGY_AMOUNT), 0.0)

		var base_position: Vector3 = _torch_light_base_positions[index]
		var sway_x: float = sin(_elapsed_time * 5.9 + phase * 1.41) * LIGHT_SWAY_AMOUNT
		var sway_z: float = sin(_elapsed_time * 7.3 + phase * 1.87) * LIGHT_SWAY_AMOUNT
		torch_light.position = base_position + Vector3(sway_x, 0.0, sway_z)


func _sort_nodes_by_path(left: Node, right: Node) -> bool:
	return String(left.get_path()) < String(right.get_path())
