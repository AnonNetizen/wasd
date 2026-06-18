extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const F4_ENEMY_SCRIPT := preload("res://scripts/gameplay/f4_enemy.gd")
const F4_PLAYER_SCRIPT := preload("res://scripts/gameplay/f4_player.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const AIM_FRAMES: int = 4
const BOOT_FRAMES: int = 8
const INVULNERABILITY_FRAMES: int = 50
const LEVEL_UP_FRAMES: int = 24
const MOVE_FRAMES: int = 8
const PICKUP_FEEDBACK_FRAMES: int = 40
const SPAWN_FRAMES: int = 10

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 1920, "default viewport width should be 1920")
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 1080, "default viewport height should be 1080")
	_expect(not bool(ProjectSettings.get_setting("display/window/size/resizable")), "window should not allow arbitrary resizing")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/mode")) == "canvas_items", "window stretch mode should scale canvas items")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep", "window stretch aspect should preserve ratio with letterboxing")
	_expect(PoolManager.has_pool(POOL_IDS.BULLET_BASIC), "bullet pool should be registered")
	_expect(PoolManager.has_pool(POOL_IDS.ENEMY_CHASER), "enemy pool should be registered")
	_expect(PoolManager.has_pool(POOL_IDS.ENEMY_SWARM), "swarm enemy pool should be registered")
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

	var isolated_player: Node2D = F4_PLAYER_SCRIPT.new()
	isolated_player.name = "SmokeIsolatedPlayer"
	run_loop.add_child(isolated_player)
	var isolated_stats: Dictionary = {}
	isolated_stats[STATS.MAX_HP] = 6
	isolated_stats[STATS.MOVE_SPEED] = 0.0
	isolated_stats[STATS.DAMAGE_INVULNERABILITY_DURATION] = 0.7
	isolated_player.call("configure", isolated_stats)
	var contact_source: Node = Node.new()
	contact_source.name = "SmokeContactSource"
	run_loop.add_child(contact_source)
	var first_player_life: float = float(isolated_player.call("current_life"))
	var contact_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		1.0,
		DAMAGE_TYPES.PHYSICAL,
		contact_source,
		isolated_player,
		"team_enemy",
		"team_player"
	)
	var first_contact_result: Dictionary = Combat.apply_damage(isolated_player, contact_info)
	var damaged_player_life: float = float(isolated_player.call("current_life"))
	_expect(bool(first_contact_result.get("applied", false)), "first contact should damage the player")
	_expect(damaged_player_life < first_player_life, "first contact should reduce player life")

	var blocked_contact_result: Dictionary = Combat.apply_damage(isolated_player, contact_info)
	_expect(not bool(blocked_contact_result.get("applied", true)), "contact should be blocked during player invulnerability")
	_expect(String(blocked_contact_result.get("reason", "")) == "invulnerable", "blocked contact should report invulnerable")
	_expect(is_equal_approx(float(isolated_player.call("current_life")), damaged_player_life), "blocked contact should not reduce player life")

	await _wait_player_vulnerability(isolated_player)
	var refreshed_contact_result: Dictionary = Combat.apply_damage(isolated_player, contact_info)
	_expect(bool(refreshed_contact_result.get("applied", false)), "same contact source should damage after invulnerability expires")
	isolated_player.queue_free()
	contact_source.queue_free()

	await _expect_enemy_center_separation(run_loop, player)
	await _expect_swarm_enemy_spawn(run_loop, player)
	await _expect_pickup_orb_draw_order(run_loop, player)
	await _expect_pickup_orb_feedback(run_loop, player)
	await _expect_level_up_choice(run_loop, player)

	for _index: int in range(SPAWN_FRAMES):
		await get_tree().process_frame
		await get_tree().physics_frame

	_expect(_pool_stat(POOL_IDS.BULLET_BASIC, "acquired") > 0, "WeaponSystem should acquire bullets")
	_expect(PoolManager.active_count(POOL_IDS.ENEMY_CHASER) > 0, "Spawner should spawn active enemies")
	_expect(_pool_stat(POOL_IDS.PICKUP_ORB, "acquired") > 0, "experience pickup pool should be acquired")

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
		_expect(enemy.has_method("is_defeat_feedback_active") and bool(enemy.call("is_defeat_feedback_active")), "defeated enemies should show defeat feedback before pooling")
		_expect(not enemy.is_in_group("f4_enemies"), "defeated enemies should leave the live enemy group during feedback")

	await _wait_player_vulnerability(player)
	var smoke_player_damage_source: Node = Node.new()
	smoke_player_damage_source.name = "SmokePlayerDamageSource"
	run_loop.add_child(smoke_player_damage_source)
	var player_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		float(player.call("max_life")),
		DAMAGE_TYPES.PHYSICAL,
		smoke_player_damage_source,
		player,
		"team_enemy",
		"team_player"
	)
	var player_result: Dictionary = Combat.apply_damage(player, player_info)
	_expect(bool(player_result.get("applied", false)), "Combat should apply player damage")
	_expect(bool(player_result.get("defeated", false)), "Combat should defeat the player")
	_expect(GameState.is_state(GameState.GAME_OVER), "player death should enter GAME_OVER")
	_expect(_find_node_by_name(get_tree().root, "F4GameOverPanel") != null, "player death should show game-over panel")
	var game_over_time: float = GameClock.now()
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	_expect(is_equal_approx(GameClock.now(), game_over_time), "GameClock should freeze in GAME_OVER")
	smoke_player_damage_source.queue_free()

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


func _wait_player_vulnerability(player: Node2D) -> void:
	for _index: int in range(INVULNERABILITY_FRAMES * 3):
		_disable_enemy_physics()
		if float(player.call("invulnerability_remaining")) <= 0.0:
			return
		await get_tree().physics_frame
	_expect(false, "player invulnerability should expire while GameState is PLAYING")


func _disable_enemy_physics() -> void:
	for active_enemy: Node in get_tree().get_nodes_in_group("f4_enemies"):
		active_enemy.set_physics_process(false)


func _expect_enemy_center_separation(run_loop: Node, player: Node2D) -> void:
	var enemy_data: Dictionary = {
		"max_hp": 6,
		"move_speed": 0.0,
		"contact_damage": 1,
		"contact_damage_type": DAMAGE_TYPES.PHYSICAL,
		"exp_reward": 0,
		"hit_radius": 14.0,
		"separation_radius": 9.0,
	}
	var enemy_a: Node2D = F4_ENEMY_SCRIPT.new()
	var enemy_b: Node2D = F4_ENEMY_SCRIPT.new()
	enemy_a.name = "SmokeSeparatedEnemyA"
	enemy_b.name = "SmokeSeparatedEnemyB"
	run_loop.add_child(enemy_a)
	run_loop.add_child(enemy_b)
	var overlap_position: Vector2 = player.global_position + Vector2(300.0, 300.0)
	enemy_a.global_position = overlap_position
	enemy_b.global_position = overlap_position
	enemy_a.call("configure", enemy_data, player)
	enemy_b.call("configure", enemy_data, player)

	for _index: int in range(8):
		await get_tree().physics_frame
	var center_distance: float = enemy_a.global_position.distance_to(enemy_b.global_position)
	_expect(center_distance >= 16.0, "enemy center separation should prevent full overlap")
	enemy_a.queue_free()
	enemy_b.queue_free()


func _expect_swarm_enemy_spawn(run_loop: Node, _player: Node2D) -> void:
	var before_count: int = PoolManager.active_count(POOL_IDS.ENEMY_SWARM)
	var spawned: bool = bool(run_loop.call("_spawn_enemy", {
		"enemy_id": "enemy_swarm",
	}, "smoke_swarm"))
	await get_tree().process_frame
	_expect(spawned, "second enemy type should spawn from data")
	_expect(PoolManager.active_count(POOL_IDS.ENEMY_SWARM) > before_count, "second enemy type should use its own pool")
	var swarm_enemy: Node = _first_enemy_with_name_prefix("enemy_swarm")
	_expect(swarm_enemy != null, "second enemy type should be active")
	if swarm_enemy != null and swarm_enemy.has_method("visual_color"):
		var color: Color = swarm_enemy.call("visual_color")
		var expected_color: Color = Color.html("#58d68d")
		_expect(
			is_equal_approx(color.r, expected_color.r)
			and is_equal_approx(color.g, expected_color.g)
			and is_equal_approx(color.b, expected_color.b),
			"second enemy type should use data-driven visual color"
		)


func _expect_pickup_orb_draw_order(run_loop: Node, player: Node2D) -> void:
	var enemy_data: Dictionary = {
		"max_hp": 6,
		"move_speed": 0.0,
		"contact_damage": 0,
		"contact_damage_type": DAMAGE_TYPES.PHYSICAL,
		"exp_reward": 0,
		"hit_radius": 14.0,
		"separation_radius": 0.0,
	}
	var enemy: Node2D = F4_ENEMY_SCRIPT.new()
	enemy.name = "SmokeDrawOrderEnemy"
	run_loop.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(500.0, 0.0)
	enemy.call("configure", enemy_data, player)
	enemy.set_physics_process(false)

	run_loop.call("_spawn_pickup_orb", enemy.global_position, 1)
	await get_tree().process_frame

	var pickup_orb: Node2D = null
	for raw_pickup: Node in get_tree().get_nodes_in_group("f4_pickups"):
		if raw_pickup is Node2D:
			pickup_orb = raw_pickup as Node2D
			break
	_expect(pickup_orb != null, "pickup orb should be active for draw-order smoke")
	_expect(pickup_orb != null and pickup_orb.z_index < enemy.z_index, "pickup orbs should draw below enemies")
	if pickup_orb != null:
		PoolManager.release(pickup_orb)
	enemy.remove_from_group("f4_enemies")
	enemy.queue_free()


func _expect_pickup_orb_feedback(run_loop: Node, player: Node2D) -> void:
	run_loop.call("_spawn_pickup_orb", player.global_position + Vector2(40.0, 0.0), 0)
	await get_tree().physics_frame
	await get_tree().process_frame

	var pickup_orb: Node2D = null
	for raw_pickup: Node in get_tree().get_nodes_in_group("f4_pickups"):
		if raw_pickup is Node2D:
			pickup_orb = raw_pickup as Node2D
			break
	_expect(pickup_orb != null, "pickup orb should be active for feedback smoke")
	if pickup_orb == null:
		return
	_expect(pickup_orb.has_method("is_attracting") and bool(pickup_orb.call("is_attracting")), "pickup orb should expose attraction feedback inside pickup range")

	pickup_orb.global_position = player.global_position
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(pickup_orb.has_method("is_collect_feedback_active") and bool(pickup_orb.call("is_collect_feedback_active")), "pickup orb should show collect feedback before pooling")
	_expect(not pickup_orb.is_in_group("f4_pickups"), "collected pickup orb should leave active pickup group during feedback")
	for _index: int in range(PICKUP_FEEDBACK_FRAMES):
		await get_tree().process_frame
	_expect(not bool(pickup_orb.call("is_collect_feedback_active")), "pickup orb collect feedback should finish and release")


func _expect_level_up_choice(run_loop: Node, player: Node2D) -> void:
	var weapon_system: Node = _find_node_by_name(player, "WeaponSystem")
	_expect(weapon_system != null, "WeaponSystem should be available before level up")
	var previous_damage: float = float(weapon_system.call("stat_value", STATS.DAMAGE)) if weapon_system != null else 0.0
	var previous_fire_rate: float = float(weapon_system.call("stat_value", STATS.FIRE_RATE)) if weapon_system != null else 0.0
	var previous_pickup_range: float = float(player.call("pickup_range"))

	run_loop.call("_spawn_pickup_orb", player.global_position, 20)
	var level_panel: Node = null
	for _index: int in range(LEVEL_UP_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame
		level_panel = _find_node_by_name(get_tree().root, "F4LevelUpPanel")
		if level_panel != null:
			break

	_expect(GameState.is_state(GameState.LEVEL_UP), "experience pickup should enter LEVEL_UP")
	_expect(level_panel != null, "level-up panel should appear")
	var panel_frame: Control = _find_node_by_name(level_panel, "LevelUpPanelFrame") as Control
	_expect(panel_frame != null, "level-up panel frame should use responsive layout")
	if panel_frame != null:
		_expect(panel_frame.custom_minimum_size.x >= 520.0, "level-up panel frame should keep a readable minimum width")
		_expect(panel_frame.custom_minimum_size.x <= 720.0, "level-up panel frame should keep a responsive maximum width")
	_expect(int(run_loop.call("current_level")) == 2, "experience pickup should raise the player to level 2")
	_expect(int(run_loop.call("current_xp")) == 20, "total xp should remain cumulative after level up")
	_expect(int(run_loop.call("current_level_xp")) == 0, "current-level xp should reset after level up")
	_expect(int(run_loop.call("current_level_xp_required")) == 35, "current-level xp requirement should use the next level segment")
	if level_panel == null:
		return

	var choice_id: String = String(level_panel.call("choice_id", 0))
	level_panel.call("choose_index", 0)
	await get_tree().process_frame
	_expect(GameState.is_state(GameState.PLAYING), "choosing a level-up option should resume PLAYING")
	var hud: Node = _find_node_by_name(run_loop, "F4Hud")
	_expect(hud != null and hud.has_method("is_upgrade_feedback_visible") and bool(hud.call("is_upgrade_feedback_visible")), "choosing a level-up option should show upgrade feedback")
	if choice_id == "growth_damage_small" and weapon_system != null:
		_expect(float(weapon_system.call("stat_value", STATS.DAMAGE)) > previous_damage, "damage upgrade should apply immediately")
	elif choice_id == "growth_fire_rate_small" and weapon_system != null:
		_expect(float(weapon_system.call("stat_value", STATS.FIRE_RATE)) > previous_fire_rate, "fire-rate upgrade should apply immediately")
	elif choice_id == "growth_pickup_range_small":
		_expect(float(player.call("pickup_range")) > previous_pickup_range, "pickup-range upgrade should apply immediately")
	else:
		_expect(false, "level-up choice should be a known growth option")


func _first_enemy_with_name_prefix(name_prefix: String) -> Node:
	for enemy: Node in get_tree().get_nodes_in_group("f4_enemies"):
		if String(enemy.name).begins_with(name_prefix):
			return enemy
	return null


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
