# Doc: docs/代码/pool_manager.md
# Authority: docs/游戏设计文档.md §9.13, docs/词表与契约.md §8
class_name PoolManagerAutoload
extends Node


signal pool_registered(pool_id: String, max_size: int)
signal pool_warmed(pool_id: String, requested: int, available: int)
signal node_acquired(pool_id: String, node: Node)
signal node_released(pool_id: String, node: Node)
signal pool_overflow(pool_id: String, active_count: int, max_size: int)
signal pool_cleared(pool_id: String)

const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const DEFAULT_MAX_SIZE: int = 256

var _pools: Dictionary = {}
var _node_to_pool: Dictionary = {}


func registered_pool_ids() -> Array[String]:
	var result: Array[String] = []
	for pool_id: String in POOL_IDS.VALUES:
		result.append(pool_id)
	return result


func pool_count() -> int:
	return _pools.size()


func has_pool(pool_id: String) -> bool:
	return _pools.has(pool_id)


func register_pool(pool_id: String, factory: Callable, max_size: int = DEFAULT_MAX_SIZE) -> bool:
	if not _is_registered_pool_id(pool_id):
		push_error("[PoolManager] unknown pool id: %s" % pool_id)
		return false
	if not factory.is_valid():
		push_error("[PoolManager] invalid factory for pool id: %s" % pool_id)
		return false
	if _pools.has(pool_id):
		push_error("[PoolManager] pool already registered: %s" % pool_id)
		return false

	var normalized_max_size: int = maxi(max_size, 1)
	_pools[pool_id] = {
		"factory": factory,
		"available": [],
		"active": {},
		"created": 0,
		"acquired": 0,
		"released": 0,
		"overflows": 0,
		"max_size": normalized_max_size,
	}
	pool_registered.emit(pool_id, normalized_max_size)
	return true


func prewarm(pool_id: String, count: int) -> int:
	if not _pools.has(pool_id):
		push_error("[PoolManager] cannot prewarm an unregistered pool: %s" % pool_id)
		return 0

	var pool_data: Dictionary = _pools[pool_id]
	var requested_count: int = maxi(count, 0)
	var created_count: int = 0
	while created_count < requested_count and _total_count(pool_data) < int(pool_data["max_size"]):
		var node: Node = _create_node(pool_id, pool_data)
		if node == null:
			break
		_store_inactive_node(node)
		var available: Array = pool_data["available"]
		available.append(node)
		created_count += 1

	pool_warmed.emit(pool_id, requested_count, available_count(pool_id))
	return created_count


func acquire(pool_id: String) -> Node:
	if not _pools.has(pool_id):
		push_error("[PoolManager] cannot acquire from an unregistered pool: %s" % pool_id)
		return null

	var pool_data: Dictionary = _pools[pool_id]
	var available: Array = pool_data["available"]
	var node: Node = null
	if available.is_empty():
		if _total_count(pool_data) >= int(pool_data["max_size"]):
			_emit_overflow(pool_id, pool_data)
			return null
		node = _create_node(pool_id, pool_data)
	else:
		node = available.pop_back() as Node

	if node == null:
		return null

	_activate_node(pool_id, node, pool_data)
	return node


func release(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		push_error("[PoolManager] cannot release a null or invalid node")
		return false

	var instance_id: int = node.get_instance_id()
	if not _node_to_pool.has(instance_id):
		push_error("[PoolManager] node was not acquired from PoolManager: %s" % node.name)
		return false

	var pool_id: String = _node_to_pool[instance_id]
	var pool_data: Dictionary = _pools[pool_id]
	var active: Dictionary = pool_data["active"]
	var available: Array = pool_data["available"]

	if node.has_method("_pool_release"):
		node.call("_pool_release")

	active.erase(instance_id)
	_node_to_pool.erase(instance_id)
	_store_inactive_node(node)
	available.append(node)
	pool_data["released"] = int(pool_data["released"]) + 1
	node_released.emit(pool_id, node)
	return true


func clear_pool(pool_id: String) -> bool:
	if not _pools.has(pool_id):
		return false

	var pool_data: Dictionary = _pools[pool_id]
	var available: Array = pool_data["available"]
	for raw_node: Variant in available:
		var node: Node = raw_node as Node
		if node != null and is_instance_valid(node):
			node.queue_free()

	var active: Dictionary = pool_data["active"]
	for raw_node: Variant in active.values():
		var node: Node = raw_node as Node
		if node != null and is_instance_valid(node):
			_node_to_pool.erase(node.get_instance_id())
			node.queue_free()

	_pools.erase(pool_id)
	pool_cleared.emit(pool_id)
	return true


func clear_all() -> void:
	for pool_id: String in _pools.keys():
		clear_pool(pool_id)


func available_count(pool_id: String) -> int:
	if not _pools.has(pool_id):
		return 0
	var pool_data: Dictionary = _pools[pool_id]
	var available: Array = pool_data["available"]
	return available.size()


func active_count(pool_id: String) -> int:
	if not _pools.has(pool_id):
		return 0
	var pool_data: Dictionary = _pools[pool_id]
	var active: Dictionary = pool_data["active"]
	return active.size()


func stats(pool_id: String = "") -> Dictionary:
	if not pool_id.is_empty():
		if not _pools.has(pool_id):
			return {}
		return _pool_stats(_pools[pool_id])

	var result: Dictionary = {}
	for registered_id: String in _pools.keys():
		result[registered_id] = _pool_stats(_pools[registered_id])
	return result


func _activate_node(pool_id: String, node: Node, pool_data: Dictionary) -> void:
	var active: Dictionary = pool_data["active"]
	var instance_id: int = node.get_instance_id()
	if node.get_parent() == null:
		add_child(node)

	active[instance_id] = node
	_node_to_pool[instance_id] = pool_id
	pool_data["acquired"] = int(pool_data["acquired"]) + 1
	_set_node_pooled_active(node, true)

	if node.has_method("_pool_reset"):
		node.call("_pool_reset")
	else:
		push_warning("[PoolManager] pooled node lacks _pool_reset(): %s" % node.name)

	node_acquired.emit(pool_id, node)


func _create_node(pool_id: String, pool_data: Dictionary) -> Node:
	var factory: Callable = pool_data["factory"]
	var raw_node: Variant = factory.call()
	var node: Node = raw_node as Node
	if node == null:
		push_error("[PoolManager] factory did not return a Node for pool id: %s" % pool_id)
		return null

	node.name = "%s_%d" % [pool_id, int(pool_data["created"])]
	pool_data["created"] = int(pool_data["created"]) + 1
	return node


func _store_inactive_node(node: Node) -> void:
	var parent: Node = node.get_parent()
	if parent != self:
		if parent != null:
			parent.remove_child(node)
		add_child(node)
	_set_node_pooled_active(node, false)


func _set_node_pooled_active(node: Node, active: bool) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if node is CanvasItem:
		var canvas_item: CanvasItem = node as CanvasItem
		canvas_item.visible = active


func _emit_overflow(pool_id: String, pool_data: Dictionary) -> void:
	pool_data["overflows"] = int(pool_data["overflows"]) + 1
	var active: Dictionary = pool_data["active"]
	pool_overflow.emit(pool_id, active.size(), int(pool_data["max_size"]))
	Analytics.track_event(ANALYTICS_EVENTS.POOL_OVERFLOW, {
		"pool_id": pool_id,
		"active_count": active.size(),
		"available_count": available_count(pool_id),
		"max_size": int(pool_data["max_size"]),
	})


func _pool_stats(pool_data: Dictionary) -> Dictionary:
	var available: Array = pool_data["available"]
	var active: Dictionary = pool_data["active"]
	return {
		"available": available.size(),
		"active": active.size(),
		"created": int(pool_data["created"]),
		"acquired": int(pool_data["acquired"]),
		"released": int(pool_data["released"]),
		"overflows": int(pool_data["overflows"]),
		"max_size": int(pool_data["max_size"]),
	}


func _total_count(pool_data: Dictionary) -> int:
	var available: Array = pool_data["available"]
	var active: Dictionary = pool_data["active"]
	return available.size() + active.size()


func _is_registered_pool_id(pool_id: String) -> bool:
	if Engine.has_singleton("DataLoader") and DataLoader.has_method("has_contract_value"):
		return DataLoader.has_contract_value("pool_ids", pool_id)
	return POOL_IDS.VALUES.has(pool_id)
