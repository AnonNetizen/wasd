class_name LowpolySpatialGrid
extends RefCounted

var cell_size: float = 4.0
var _cells: Dictionary = {}


func _init(size: float = 4.0) -> void:
	cell_size = maxf(size, 0.5)


func rebuild(nodes: Array[Node]) -> void:
	_cells.clear()
	for node: Node in nodes:
		if not is_instance_valid(node) or not node is Node3D:
			continue
		if node.has_method("is_pool_active") and not bool(node.call("is_pool_active")):
			continue
		var node_3d: Node3D = node as Node3D
		var key: Vector2i = _key_for(node_3d.global_position)
		if not _cells.has(key):
			_cells[key] = []
		var bucket: Array = _cells[key]
		bucket.append(node_3d)


func query_radius(position: Vector3, radius: float) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var cell_radius: int = ceili(maxf(radius, 0.0) / cell_size)
	var center: Vector2i = _key_for(position)
	var radius_squared: float = radius * radius
	for cell_x: int in range(center.x - cell_radius, center.x + cell_radius + 1):
		for cell_y: int in range(center.y - cell_radius, center.y + cell_radius + 1):
			var bucket: Variant = _cells.get(Vector2i(cell_x, cell_y), [])
			if not bucket is Array:
				continue
			for value: Variant in bucket as Array:
				if value is Node3D and is_instance_valid(value):
					var node: Node3D = value as Node3D
					var offset: Vector3 = node.global_position - position
					offset.y = 0.0
					if offset.length_squared() <= radius_squared:
						result.append(node)
	return result


func find_nearest(position: Vector3, radius: float) -> Node3D:
	var nearest: Node3D = null
	var best_distance_squared: float = radius * radius
	for node: Node3D in query_radius(position, radius):
		var offset: Vector3 = node.global_position - position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared <= best_distance_squared:
			best_distance_squared = distance_squared
			nearest = node
	return nearest


func _key_for(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.z / cell_size))
