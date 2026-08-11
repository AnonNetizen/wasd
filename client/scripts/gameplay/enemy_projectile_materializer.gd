# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyProjectileMaterializer
extends RefCounted
## Stateless pooled-projectile materialization for Enemy ranged attacks.


const STATS := preload("res://scripts/contracts/stats.gd")

const REASON_CONFIGURE_FAILED: String = "configure_failed"
const REASON_CONFIGURE_UNAVAILABLE: String = "configure_unavailable"
const REASON_INVALID_DIRECTION: String = "invalid_direction"
const REASON_INVALID_PORTS: String = "invalid_ports"
const REASON_INVALID_PROJECTILE_NODE: String = "invalid_projectile_node"
const REASON_INVALID_REQUEST: String = "invalid_request"
const REASON_POOL_UNAVAILABLE: String = "pool_unavailable"


class Spec:
	extends RefCounted

	var pool_id: String = ""
	var muzzle_distance: float = 0.0
	var damage: float = 0.0
	var speed: float = 0.0
	var max_range: float = 0.0
	var element_id: String = ""
	var damage_target_groups: Array[String] = []
	var hit_radius: float = 0.0
	var lifetime: float = 0.0
	var source_team: String = ""
	var target_team: String = ""


class Request:
	extends RefCounted

	var spec: Spec = Spec.new()
	var source: Node2D = null
	var active_parent: Node = null
	var source_position: Vector2 = Vector2.ZERO
	var target_direction: Vector2 = Vector2.ZERO


class Ports:
	extends RefCounted

	var _acquire_handler: Callable = Callable()
	var _configure_handler: Callable = Callable()


	func _init(
		acquire_handler: Callable = Callable(),
		configure_handler: Callable = Callable()
	) -> void:
		_acquire_handler = acquire_handler
		_configure_handler = configure_handler


	func is_valid() -> bool:
		return (
			_acquire_handler.is_valid()
			and _configure_handler.is_valid()
		)


	func acquire(pool_id: String) -> Node:
		var raw_node: Variant = _acquire_handler.call(pool_id)
		if raw_node is Node:
			return raw_node as Node
		return null


	func configure(
		projectile: Node2D,
		stats: Dictionary,
		projectile_data: Dictionary,
		direction: Vector2,
		source: Node
	) -> bool:
		return bool(_configure_handler.call(
			projectile,
			stats,
			projectile_data,
			direction,
			source
		))


class Result:
	extends RefCounted

	var ok: bool = false
	var reason: String = ""
	var projectile: Node2D = null
	var direction: Vector2 = Vector2.ZERO
	var muzzle_position: Vector2 = Vector2.ZERO


static func materialize(request: Request, ports: Ports) -> Result:
	var result: Result = Result.new()
	if request == null or request.spec == null:
		result.reason = REASON_INVALID_REQUEST
		return result
	if request.target_direction.length_squared() <= 0.0:
		result.reason = REASON_INVALID_DIRECTION
		return result
	if ports == null or not ports.is_valid():
		result.reason = REASON_INVALID_PORTS
		return result

	var raw_node: Node = ports.acquire(request.spec.pool_id)
	if raw_node == null:
		result.reason = REASON_POOL_UNAVAILABLE
		return result
	if not raw_node is Node2D:
		result.reason = REASON_INVALID_PROJECTILE_NODE
		return result
	if not raw_node.has_method("configure"):
		result.reason = REASON_CONFIGURE_UNAVAILABLE
		return result

	var direction: Vector2 = request.target_direction.normalized()
	var muzzle_position: Vector2 = (
		request.source_position
		+ direction * request.spec.muzzle_distance
	)
	var projectile: Node2D = raw_node as Node2D
	projectile.global_position = muzzle_position
	_reparent_to_active_parent(projectile, request.active_parent)

	result.projectile = projectile
	result.direction = direction
	result.muzzle_position = muzzle_position
	if not ports.configure(
		projectile,
		{
			STATS.DAMAGE: request.spec.damage,
			STATS.BULLET_SPEED: request.spec.speed,
			STATS.BULLET_RANGE: request.spec.max_range,
			STATS.PIERCE_COUNT: 0,
		},
		{
			"element_id": request.spec.element_id,
			"damage_target_groups": (
				request.spec.damage_target_groups.duplicate()
			),
			"hit_radius": request.spec.hit_radius,
			"lifetime": request.spec.lifetime,
			"source_team": request.spec.source_team,
			"target_team": request.spec.target_team,
		},
		direction,
		request.source
	):
		result.reason = REASON_CONFIGURE_FAILED
		return result

	result.ok = true
	return result


static func failed_result(reason: String) -> Result:
	var result: Result = Result.new()
	result.reason = reason
	return result


static func _reparent_to_active_parent(
	node: Node,
	active_parent: Node
) -> void:
	if active_parent == null:
		return
	var old_parent: Node = node.get_parent()
	if old_parent == active_parent:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	active_parent.add_child(node)
