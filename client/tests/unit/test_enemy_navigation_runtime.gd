extends SmokeHarness


const ENEMY_NAVIGATION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_navigation_runtime.gd"
)


class FakeNavigationProvider:
	extends Node

	var active_query_positions: Array[Vector2] = []
	var calls: Array[String] = []
	var corridor_open: bool = false
	var local_next_position: Vector2 = Vector2(9.0, 4.0)
	var local_reachable: bool = true
	var active_next_position: Vector2 = Vector2(4.0, 3.0)
	var active_reachable: bool = true
	var reachable_band_positions: Array[Vector2] = []
	var route_distance_by_position: Dictionary = {}
	var visited_cells: Array[Vector2i] = []

	func navigation_query_to_active_target(
		from_position: Vector2
	) -> Dictionary:
		calls.append("active")
		active_query_positions.append(from_position)
		var band_reachable: bool = reachable_band_positions.has(
			from_position
		)
		if not reachable_band_positions.is_empty():
			return {
				"reachable": band_reachable,
				"distance": float(
					route_distance_by_position.get(from_position, INF)
				),
				"next_position": from_position,
			}
		return {
			"reachable": active_reachable,
			"distance": from_position.distance_to(Vector2(10.0, 0.0)),
			"next_position": active_next_position,
		}

	func navigation_query(
		from_position: Vector2,
		target_position: Vector2
	) -> Dictionary:
		calls.append("local")
		return {
			"reachable": local_reachable,
			"distance": from_position.distance_to(target_position),
			"next_position": local_next_position,
			"target_position": target_position,
		}

	func has_terrain_line_of_sight(
		_from_position: Vector2,
		_target_position: Vector2
	) -> bool:
		calls.append("los")
		return false

	func has_clear_corridor(
		_from_position: Vector2,
		_target_position: Vector2,
		_clearance: float
	) -> bool:
		calls.append("corridor")
		return corridor_open

	func world_to_global_cell(_world_position: Vector2) -> Vector2i:
		calls.append("world_to_cell")
		return Vector2i.ZERO

	func global_cell_to_world(cell: Vector2i) -> Vector2:
		calls.append("cell_to_world")
		visited_cells.append(cell)
		return Vector2(cell)


func test_direct_fallbacks_are_lazy_and_select_direct_mode() -> void:
	var runtime: ENEMY_NAVIGATION_RUNTIME_SCRIPT = (
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.new()
	)
	runtime.configure(null)

	var query: Dictionary = runtime.active_navigation_query(
		Vector2.ZERO,
		Vector2(3.0, 4.0),
		true
	)
	assert_true(bool(query.get("reachable", false)))
	assert_almost_eq(float(query.get("distance", 0.0)), 5.0, 0.0)
	assert_eq(
		runtime.movement_direction_to(
			Vector2.ZERO,
			Vector2(3.0, 4.0),
			12.0,
			true,
			true
		),
		Vector2(3.0, 4.0)
	)
	assert_eq(
		runtime.mode(),
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_MODE_DIRECT
	)
	assert_true(runtime.has_terrain_line_of_sight(
		Vector2.ZERO,
		Vector2.ONE
	))
	assert_true(runtime.has_clear_corridor(
		Vector2.ZERO,
		Vector2.ONE,
		12.0
	))


func test_movement_queries_corridor_before_route_and_sets_mode() -> void:
	var provider := FakeNavigationProvider.new()
	add_child_autofree(provider)
	var runtime: ENEMY_NAVIGATION_RUNTIME_SCRIPT = (
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.new()
	)
	runtime.configure(provider)

	var direction: Vector2 = runtime.movement_direction_to(
		Vector2.ZERO,
		Vector2(10.0, 0.0),
		12.0,
		true,
		true
	)
	assert_eq(provider.calls, ["corridor", "active"])
	assert_eq(direction, provider.active_next_position)
	assert_eq(
		runtime.mode(),
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_MODE_FLOW_FIELD
	)

	provider.calls.clear()
	direction = runtime.movement_direction_to(
		Vector2.ZERO,
		Vector2(10.0, 0.0),
		12.0,
		false,
		false
	)
	assert_eq(provider.calls, ["corridor", "local"])
	assert_eq(direction, provider.local_next_position)
	assert_eq(
		runtime.mode(),
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_MODE_LOCAL_ASTAR
	)

	provider.calls.clear()
	provider.local_reachable = false
	direction = runtime.movement_direction_to(
		Vector2.ZERO,
		Vector2(10.0, 0.0),
		12.0,
		false,
		false
	)
	assert_eq(provider.calls, ["corridor", "local"])
	assert_eq(direction, Vector2.ZERO)
	assert_eq(
		runtime.mode(),
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_MODE_NONE
	)


func test_cached_waypoint_refresh_direction_and_reset_clear_ownership() -> void:
	var provider := FakeNavigationProvider.new()
	add_child_autofree(provider)
	var runtime: ENEMY_NAVIGATION_RUNTIME_SCRIPT = (
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.new()
	)
	runtime.configure(provider)
	runtime.refresh_cached_waypoint(
		Vector2(1.0, 2.0),
		true,
		Vector2(20.0, 30.0)
	)
	assert_true(runtime.has_cached_waypoint())
	assert_eq(runtime.cached_waypoint(), provider.local_next_position)

	provider.calls.clear()
	var direction: Vector2 = runtime.direction_to_cached_target(
		Vector2(1.0, 2.0),
		Vector2(20.0, 30.0),
		12.0
	)
	assert_eq(provider.calls, ["corridor"])
	assert_eq(direction, provider.local_next_position - Vector2(1.0, 2.0))
	assert_eq(
		runtime.mode(),
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_MODE_LOCAL_ASTAR
	)

	provider.calls.clear()
	runtime.reset()
	assert_false(runtime.has_cached_waypoint())
	assert_eq(runtime.cached_waypoint(), Vector2.ZERO)
	assert_eq(
		runtime.mode(),
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_MODE_NONE
	)
	runtime.navigation_query(Vector2.ZERO, Vector2.ONE)
	assert_true(provider.calls.is_empty())


func test_path_band_uses_fixed_neighbors_corridor_query_and_epsilon_tie() -> void:
	var provider := FakeNavigationProvider.new()
	provider.corridor_open = true
	provider.reachable_band_positions = [Vector2.UP, Vector2.RIGHT]
	provider.route_distance_by_position = {
		Vector2.UP: 5.0,
		Vector2.RIGHT: 5.0,
	}
	add_child_autofree(provider)
	var runtime: ENEMY_NAVIGATION_RUNTIME_SCRIPT = (
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.new()
	)
	runtime.configure(provider)

	var direction: Vector2 = runtime.path_band_direction(
		Vector2.ZERO,
		Vector2(0.0, 10.0),
		true,
		12.0,
		5.0,
		5.0,
		0.0025
	)
	assert_eq(
		provider.visited_cells,
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_NEIGHBOR_OFFSETS
	)
	assert_eq(
		provider.active_query_positions,
		[
			Vector2.UP,
			Vector2.RIGHT,
			Vector2.DOWN,
			Vector2.LEFT,
			Vector2(1.0, -1.0),
			Vector2(1.0, 1.0),
			Vector2(-1.0, 1.0),
			Vector2(-1.0, -1.0),
		]
	)
	assert_eq(provider.calls.front(), "world_to_cell")
	for index: int in range(
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_NEIGHBOR_OFFSETS.size()
	):
		var base_index: int = 1 + index * 3
		assert_eq(provider.calls[base_index], "cell_to_world")
		assert_eq(provider.calls[base_index + 1], "corridor")
		assert_eq(provider.calls[base_index + 2], "active")
	assert_eq(direction, Vector2.UP)
	assert_eq(
		runtime.mode(),
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.NAVIGATION_MODE_FLOW_FIELD
	)


func test_orbit_direction_keeps_radial_and_tangent_weights() -> void:
	var runtime: ENEMY_NAVIGATION_RUNTIME_SCRIPT = (
		ENEMY_NAVIGATION_RUNTIME_SCRIPT.new()
	)
	assert_eq(
		runtime.orbit_direction(
			Vector2(10.0, 0.0),
			Vector2.ZERO,
			5.0,
			1.0
		),
		Vector2(-1.0, 0.7)
	)
	assert_eq(
		runtime.orbit_direction(
			Vector2(3.0, 0.0),
			Vector2.ZERO,
			5.0,
			-1.0
		),
		Vector2(1.0, -0.85)
	)
