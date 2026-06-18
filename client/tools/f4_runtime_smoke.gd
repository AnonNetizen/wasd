extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const AIM_FRAMES: int = 4
const BOOT_FRAMES: int = 8
const MOVE_FRAMES: int = 8
const SPAWN_FRAMES: int = 10

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	RNG.set_run_seed(4242)

	var run_loop: Node = null
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		run_loop = _find_node_by_name(get_tree().root, "F4RunLoop")
		if run_loop != null:
			break

	_expect(run_loop != null, "F4RunLoop should be mounted after formal boot")
	_expect(GameState.is_state(GameState.PLAYING), "GameState should enter PLAYING")
	_expect(PoolManager.has_pool(POOL_IDS.BULLET_BASIC), "bullet pool should be registered")
	_expect(PoolManager.has_pool(POOL_IDS.ENEMY_CHASER), "enemy pool should be registered")
	_expect(_action_has_key(ACTIONS.MOVE_UP, KEY_W), "move_up should include KEY_W")
	_expect(not _action_has_key(ACTIONS.MOVE_UP, KEY_UP), "move_up should not include KEY_UP")
	_expect(_action_has_key(ACTIONS.AIM_UP, KEY_UP), "aim_up should include KEY_UP")

	var player: Node2D = _find_node_by_name(run_loop, "Player") as Node2D
	_expect(player != null, "Player should exist")
	if player == null:
		_finish()
		return

	var camera: Camera2D = _find_node_by_name(player, "CenteredCamera") as Camera2D
	_expect(camera != null and camera.enabled, "CenteredCamera should be enabled")
	_expect(_find_node_by_name(run_loop, "F4Background") != null, "F4Background should provide movement reference")

	var start_position: Vector2 = player.global_position
	Input.action_press(ACTIONS.MOVE_RIGHT)
	for _index: int in range(MOVE_FRAMES):
		await get_tree().physics_frame
	Input.action_release(ACTIONS.MOVE_RIGHT)
	_expect(player.global_position.x > start_position.x + 1.0, "WASD movement should move the player")

	var before_aim_position: Vector2 = player.global_position
	Input.action_press(ACTIONS.AIM_UP)
	for _index: int in range(AIM_FRAMES):
		await get_tree().physics_frame
	Input.action_release(ACTIONS.AIM_UP)
	_expect(player.get("aim_direction") == Vector2.UP, "arrow aim should snap to Vector2.UP")
	_expect(player.global_position.distance_to(before_aim_position) < 1.0, "arrow aim should not move the player")

	for _index: int in range(SPAWN_FRAMES):
		await get_tree().process_frame
		await get_tree().physics_frame

	_expect(_pool_stat(POOL_IDS.BULLET_BASIC, "acquired") > 0, "WeaponSystem should acquire bullets")
	_expect(PoolManager.active_count(POOL_IDS.ENEMY_CHASER) > 0, "Spawner should spawn active enemies")

	var enemy: Node = _first_enemy()
	_expect(enemy != null, "at least one enemy should be in f4_enemies")
	if enemy != null:
		var enemy_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
			999.0,
			DAMAGE_TYPES.PHYSICAL,
			player,
			enemy,
			"team_player",
			"team_enemy"
		)
		var enemy_result: Dictionary = Combat.apply_damage(enemy, enemy_info)
		_expect(bool(enemy_result.get("applied", false)), "Combat should apply enemy damage")
		_expect(bool(enemy_result.get("defeated", false)), "Combat should defeat the smoke enemy")

	var player_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		float(player.call("max_life")),
		DAMAGE_TYPES.PHYSICAL,
		enemy,
		player,
		"team_enemy",
		"team_player"
	)
	var player_result: Dictionary = Combat.apply_damage(player, player_info)
	_expect(bool(player_result.get("applied", false)), "Combat should apply player damage")
	_expect(bool(player_result.get("defeated", false)), "Combat should defeat the player")
	_expect(GameState.is_state(GameState.GAME_OVER), "player death should enter GAME_OVER")
	var game_over_time: float = GameClock.now()
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	_expect(is_equal_approx(GameClock.now(), game_over_time), "GameClock should freeze in GAME_OVER")

	_finish()


func _first_enemy() -> Node:
	for enemy: Node in get_tree().get_nodes_in_group("f4_enemies"):
		return enemy
	return null


func _find_node_by_name(root_node: Node, target_name: String) -> Node:
	if root_node == null:
		return null
	if root_node.name == target_name:
		return root_node
	for child: Node in root_node.get_children():
		var match_node: Node = _find_node_by_name(child, target_name)
		if match_node != null:
			return match_node
	return null


func _action_has_key(action_id: String, keycode: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action_id):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return true
	return false


func _pool_stat(pool_id: String, key: String) -> int:
	var stats: Dictionary = PoolManager.stats(pool_id)
	return int(stats.get(key, 0))


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[F4Smoke] %s" % message)


func _finish() -> void:
	Input.action_release(ACTIONS.MOVE_RIGHT)
	Input.action_release(ACTIONS.AIM_UP)
	if _failures.is_empty():
		print("[F4Smoke] passed; time=%.2f bullets_acquired=%d enemies_acquired=%d state=%s" % [
			GameClock.now(),
			_pool_stat(POOL_IDS.BULLET_BASIC, "acquired"),
			_pool_stat(POOL_IDS.ENEMY_CHASER, "acquired"),
			String(GameState.current()),
		])
		get_tree().quit(0)
		return

	print("[F4Smoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
