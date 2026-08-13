class_name LowpolyObjectPool
extends RefCounted

var _factory: Callable
var _parent: Node
var _capacity: int = 0
var _inactive: Array[Node] = []
var _active: Dictionary = {}


func setup(factory: Callable, parent: Node, prewarm: int, capacity: int) -> void:
	_factory = factory
	_parent = parent
	_capacity = maxi(capacity, 1)
	for index: int in range(mini(prewarm, _capacity)):
		var instance: Node = _create_instance()
		if instance != null:
			_inactive.append(instance)


func acquire(payload: Dictionary = {}) -> Node:
	if _active.size() >= _capacity:
		return null
	var instance: Node = _inactive.pop_back() if not _inactive.is_empty() else _create_instance()
	if instance == null:
		return null
	_active[instance.get_instance_id()] = instance
	if instance.has_method("activate_from_pool"):
		instance.call("activate_from_pool", payload)
	else:
		instance.process_mode = Node.PROCESS_MODE_INHERIT
	return instance


func release(instance: Node) -> bool:
	if not is_instance_valid(instance):
		return false
	var instance_id: int = instance.get_instance_id()
	if not _active.has(instance_id):
		return false
	_active.erase(instance_id)
	if instance.has_method("deactivate_to_pool"):
		instance.call("deactivate_to_pool")
	else:
		instance.process_mode = Node.PROCESS_MODE_DISABLED
	_inactive.append(instance)
	return true


func release_all() -> void:
	var instances: Array[Node] = []
	for value: Variant in _active.values():
		if value is Node:
			instances.append(value as Node)
	for instance: Node in instances:
		release(instance)


func get_active_nodes() -> Array[Node]:
	var result: Array[Node] = []
	for value: Variant in _active.values():
		if value is Node and is_instance_valid(value):
			result.append(value as Node)
	return result


func get_active_count() -> int:
	return _active.size()


func get_capacity() -> int:
	return _capacity


func owns(instance: Node) -> bool:
	return is_instance_valid(instance) and _active.has(instance.get_instance_id())


func _create_instance() -> Node:
	if not _factory.is_valid() or not is_instance_valid(_parent):
		return null
	var value: Variant = _factory.call()
	if not value is Node:
		return null
	var instance: Node = value as Node
	_parent.add_child(instance)
	if instance.has_method("deactivate_to_pool"):
		instance.call("deactivate_to_pool")
	return instance
