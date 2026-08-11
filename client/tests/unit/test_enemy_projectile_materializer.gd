extends SmokeHarness


const MATERIALIZER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_projectile_materializer.gd"
)
const STATS := preload("res://scripts/contracts/stats.gd")

const TEST_POOL_ID: String = "test_enemy_projectile_materializer"

var _acquired_node: Node = null
var _configure_ok: bool = true
var _configured_projectile_data: Dictionary = {}
var _configured_stats: Dictionary = {}
var _events: Array[String] = []


class RecordingProjectile:
	extends Node2D

	var events: Array[String] = []
	var record_parenting: bool = false
	var parented_global_position: Vector2 = Vector2.ZERO
	var configured_global_position: Vector2 = Vector2.ZERO
	var configured_direction: Vector2 = Vector2.ZERO
	var configured_source: Node = null


	func _notification(what: int) -> void:
		if what == NOTIFICATION_PARENTED and record_parenting:
			events.append("reparent")
			parented_global_position = global_position


	func configure(
		_stats: Dictionary,
		_projectile_data: Dictionary,
		direction: Vector2,
		source: Node
	) -> void:
		configured_global_position = global_position
		configured_direction = direction
		configured_source = source


func before_each() -> void:
	_acquired_node = null
	_configure_ok = true
	_configured_projectile_data.clear()
	_configured_stats.clear()
	_events.clear()


func test_success_preserves_materialization_order_and_config_values() -> void:
	var pool_parent := Node2D.new()
	pool_parent.position = Vector2(100.0, 0.0)
	add_child_autofree(pool_parent)
	var active_parent := Node2D.new()
	active_parent.position = Vector2(200.0, 0.0)
	add_child_autofree(active_parent)
	var source := Node2D.new()
	add_child_autofree(source)
	var projectile := RecordingProjectile.new()
	projectile.events = _events
	pool_parent.add_child(projectile)
	projectile.record_parenting = true
	_acquired_node = projectile

	var request: MATERIALIZER_SCRIPT.Request = _request(
		source,
		active_parent,
		Vector2(40.0, 20.0),
		Vector2(2.0, 0.0)
	)
	var result: MATERIALIZER_SCRIPT.Result = (
		MATERIALIZER_SCRIPT.materialize(request, _ports())
	)

	assert_true(result.ok)
	assert_eq(result.reason, "")
	assert_same(result.projectile, projectile)
	assert_eq(result.direction, Vector2.RIGHT)
	assert_eq(result.muzzle_position, Vector2(64.0, 20.0))
	assert_eq(_events, [
		"acquire:%s" % TEST_POOL_ID,
		"reparent",
		"configure",
	])
	assert_same(projectile.get_parent(), active_parent)
	# The old implementation sets global position under the pool parent before
	# remove/add reparenting, so transformed parents intentionally expose order.
	assert_eq(projectile.parented_global_position, Vector2(164.0, 20.0))
	assert_eq(projectile.configured_global_position, Vector2(164.0, 20.0))
	assert_eq(projectile.configured_direction, Vector2.RIGHT)
	assert_same(projectile.configured_source, source)
	assert_almost_eq(
		float(_configured_stats.get(STATS.DAMAGE, 0.0)),
		27.0,
		0.0
	)
	assert_almost_eq(
		float(_configured_stats.get(STATS.BULLET_SPEED, 0.0)),
		350.0,
		0.0
	)
	assert_almost_eq(
		float(_configured_stats.get(STATS.BULLET_RANGE, 0.0)),
		720.0,
		0.0
	)
	assert_eq(int(_configured_stats.get(STATS.PIERCE_COUNT, -1)), 0)
	assert_eq(
		_configured_projectile_data.get("damage_target_groups"),
		["active_player", "active_projectile_blockers"]
	)
	assert_eq(
		request.spec.damage_target_groups,
		["active_player", "active_projectile_blockers"]
	)


func test_missing_active_parent_still_configures_without_reparenting() -> void:
	var pool_parent := Node2D.new()
	pool_parent.position = Vector2(100.0, 0.0)
	add_child_autofree(pool_parent)
	var source := Node2D.new()
	add_child_autofree(source)
	var projectile := RecordingProjectile.new()
	projectile.events = _events
	pool_parent.add_child(projectile)
	projectile.record_parenting = true
	_acquired_node = projectile

	var result: MATERIALIZER_SCRIPT.Result = (
		MATERIALIZER_SCRIPT.materialize(
			_request(
				source,
				null,
				Vector2(40.0, 20.0),
				Vector2.RIGHT
			),
			_ports()
		)
	)

	assert_true(result.ok)
	assert_eq(result.reason, "")
	assert_same(result.projectile, projectile)
	assert_same(projectile.get_parent(), pool_parent)
	assert_eq(projectile.configured_global_position, Vector2(64.0, 20.0))
	assert_eq(projectile.configured_direction, Vector2.RIGHT)
	assert_same(projectile.configured_source, source)
	assert_eq(_events, [
		"acquire:%s" % TEST_POOL_ID,
		"configure",
	])


func test_invalid_direction_and_pool_failure_stop_before_reparent() -> void:
	var request: MATERIALIZER_SCRIPT.Request = _request(
		Node2D.new(),
		Node.new(),
		Vector2.ZERO,
		Vector2.ZERO
	)
	var invalid_direction: MATERIALIZER_SCRIPT.Result = (
		MATERIALIZER_SCRIPT.materialize(request, _ports())
	)
	assert_false(invalid_direction.ok)
	assert_eq(
		invalid_direction.reason,
		MATERIALIZER_SCRIPT.REASON_INVALID_DIRECTION
	)
	assert_true(_events.is_empty())

	request.target_direction = Vector2.RIGHT
	var unavailable: MATERIALIZER_SCRIPT.Result = (
		MATERIALIZER_SCRIPT.materialize(request, _ports())
	)
	assert_false(unavailable.ok)
	assert_eq(
		unavailable.reason,
		MATERIALIZER_SCRIPT.REASON_POOL_UNAVAILABLE
	)
	assert_eq(_events, ["acquire:%s" % TEST_POOL_ID])
	request.source.free()
	request.active_parent.free()


func test_invalid_node_or_missing_configure_is_not_reparented() -> void:
	var pool_parent := Node.new()
	add_child_autofree(pool_parent)
	var active_parent := Node.new()
	add_child_autofree(active_parent)
	var source := Node2D.new()
	add_child_autofree(source)

	var plain_node := Node.new()
	pool_parent.add_child(plain_node)
	_acquired_node = plain_node
	var request: MATERIALIZER_SCRIPT.Request = _request(
		source,
		active_parent,
		Vector2.ZERO,
		Vector2.RIGHT
	)
	var invalid_node: MATERIALIZER_SCRIPT.Result = (
		MATERIALIZER_SCRIPT.materialize(request, _ports())
	)
	assert_false(invalid_node.ok)
	assert_eq(
		invalid_node.reason,
		MATERIALIZER_SCRIPT.REASON_INVALID_PROJECTILE_NODE
	)
	assert_same(plain_node.get_parent(), pool_parent)

	_events.clear()
	var missing_configure := Node2D.new()
	pool_parent.add_child(missing_configure)
	_acquired_node = missing_configure
	var unavailable: MATERIALIZER_SCRIPT.Result = (
		MATERIALIZER_SCRIPT.materialize(request, _ports())
	)
	assert_false(unavailable.ok)
	assert_eq(
		unavailable.reason,
		MATERIALIZER_SCRIPT.REASON_CONFIGURE_UNAVAILABLE
	)
	assert_same(missing_configure.get_parent(), pool_parent)
	assert_eq(_events, ["acquire:%s" % TEST_POOL_ID])


func test_configure_failure_keeps_acquired_node_and_returns_diagnostics() -> void:
	var pool_parent := Node.new()
	add_child_autofree(pool_parent)
	var active_parent := Node.new()
	add_child_autofree(active_parent)
	var source := Node2D.new()
	add_child_autofree(source)
	var projectile := RecordingProjectile.new()
	projectile.events = _events
	pool_parent.add_child(projectile)
	projectile.record_parenting = true
	_acquired_node = projectile
	_configure_ok = false

	var result: MATERIALIZER_SCRIPT.Result = (
		MATERIALIZER_SCRIPT.materialize(
			_request(
				source,
				active_parent,
				Vector2(10.0, 4.0),
				Vector2.UP
			),
			_ports()
		)
	)
	assert_false(result.ok)
	assert_eq(
		result.reason,
		MATERIALIZER_SCRIPT.REASON_CONFIGURE_FAILED
	)
	assert_same(result.projectile, projectile)
	assert_same(projectile.get_parent(), active_parent)
	assert_eq(_events, [
		"acquire:%s" % TEST_POOL_ID,
		"reparent",
		"configure",
	])


func _request(
	source: Node2D,
	active_parent: Node,
	source_position: Vector2,
	target_direction: Vector2
) -> MATERIALIZER_SCRIPT.Request:
	var request: MATERIALIZER_SCRIPT.Request = (
		MATERIALIZER_SCRIPT.Request.new()
	)
	request.source = source
	request.active_parent = active_parent
	request.source_position = source_position
	request.target_direction = target_direction
	request.spec.pool_id = TEST_POOL_ID
	request.spec.muzzle_distance = 24.0
	request.spec.damage = 27.0
	request.spec.speed = 350.0
	request.spec.max_range = 720.0
	request.spec.element_id = "element_neutral"
	request.spec.damage_target_groups = [
		"active_player",
		"active_projectile_blockers",
	]
	request.spec.hit_radius = 12.0
	request.spec.lifetime = 2.1
	request.spec.source_team = "team_enemy"
	request.spec.target_team = "team_player"
	return request


func _ports() -> MATERIALIZER_SCRIPT.Ports:
	return MATERIALIZER_SCRIPT.Ports.new(
		Callable(self, "_acquire"),
		Callable(self, "_configure")
	)


func _acquire(pool_id: String) -> Node:
	_events.append("acquire:%s" % pool_id)
	return _acquired_node


func _configure(
	projectile: Node2D,
	stats: Dictionary,
	projectile_data: Dictionary,
	direction: Vector2,
	source: Node
) -> bool:
	_events.append("configure")
	_configured_stats = stats.duplicate(true)
	_configured_projectile_data = projectile_data.duplicate(true)
	projectile.call(
		"configure",
		stats,
		projectile_data,
		direction,
		source
	)
	var raw_groups: Variant = projectile_data.get("damage_target_groups", [])
	if raw_groups is Array:
		(raw_groups as Array).append("mutated_by_port")
	return _configure_ok
