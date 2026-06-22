extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const ENEMY_AI_ACTIONS := preload("res://scripts/contracts/enemy_ai_actions.gd")
const ENEMY_SCENE := preload("res://scenes/gameplay/enemy.tscn")
const PLAYER_SCENE := preload("res://scenes/gameplay/player.tscn")
const META_CURRENCIES := preload("res://scripts/contracts/meta_currencies.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SKILL_RESOURCES := preload("res://scripts/contracts/skill_resources.gd")
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
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)

	var run_loop: Node = null
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		run_loop = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if run_loop != null:
			break

	_expect(run_loop != null, "GameplayRunLoop should be mounted after formal boot")
	_expect(GameState.is_state(GameState.PLAYING), "GameState should enter PLAYING")
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 1920, "default viewport width should be 1920")
	_expect(int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 1080, "default viewport height should be 1080")
	_expect(not bool(ProjectSettings.get_setting("display/window/size/resizable")), "window should not allow arbitrary resizing")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/mode")) == "canvas_items", "window stretch mode should scale canvas items")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/aspect")) == "keep", "window stretch aspect should preserve ratio with letterboxing")
	_expect(tr("ui_start") != "ui_start", "registered translations should resolve UI keys")
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
	_expect(_find_node_by_name(run_loop, "WorldBackground") != null, "WorldBackground should provide movement reference")

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
	_expect(player.get("aim_direction") == Vector2.UP, "arrow aim fallback should point to Vector2.UP")
	_expect(player.global_position.distance_to(before_aim_position) < 1.0, "arrow aim fallback should not move the player")

	player.call("aim_at_world_position", player.global_position + Vector2(180.0, -90.0))
	for _index: int in range(AIM_FRAMES):
		await get_tree().physics_frame
	var mouse_aim: Vector2 = player.get("aim_direction")
	_expect(mouse_aim.x > 0.75 and mouse_aim.y < -0.25, "mouse aim should support diagonal mouse direction")
	_expect(absf(mouse_aim.x) < 0.98 and absf(mouse_aim.y) > 0.1, "mouse aim should not snap back to four directions")

	var isolated_player: Node2D = PLAYER_SCENE.instantiate() as Node2D
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
	await _expect_player_enemy_separation(run_loop, player)
	await _expect_swarm_enemy_spawn(run_loop, player)
	await _expect_enemy_ecology_ai(run_loop, player)
	await _expect_whirlwind_slash_skill(run_loop, player)
	await _expect_pickup_orb_draw_order(run_loop, player)
	await _expect_pickup_orb_feedback(run_loop, player)
	var level_restored_run: Dictionary = await _expect_level_up_choice(run_loop, player)
	var level_restored_run_loop_value: Node = level_restored_run.get("run_loop", run_loop) as Node
	var level_restored_player_value: Node2D = level_restored_run.get("player", player) as Node2D
	if level_restored_run_loop_value != null:
		run_loop = level_restored_run_loop_value
	if level_restored_player_value != null:
		player = level_restored_player_value

	var restored_run: Dictionary = await _expect_pause_save_resume(run_loop, player)
	var restored_run_loop_value: Node = restored_run.get("run_loop", run_loop) as Node
	var restored_player_value: Node2D = restored_run.get("player", player) as Node2D
	if restored_run_loop_value != null:
		run_loop = restored_run_loop_value
	if restored_player_value != null:
		player = restored_player_value

	for _index: int in range(SPAWN_FRAMES):
		await get_tree().process_frame
		await get_tree().physics_frame

	_expect(_pool_stat(POOL_IDS.BULLET_BASIC, "acquired") > 0, "WeaponSystem should acquire bullets")
	_expect(PoolManager.active_count(POOL_IDS.ENEMY_CHASER) > 0, "Spawner should spawn active enemies")
	_expect(PoolManager.has_pool(POOL_IDS.PICKUP_ORB), "experience pickup pool should remain registered after continue")

	var enemy: Node = _first_enemy()
	_expect(enemy != null, "at least one enemy should be in active_enemies")
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
		_expect(not enemy.is_in_group("active_enemies"), "defeated enemies should leave the live enemy group during feedback")
		_expect(_pool_stat(POOL_IDS.HIT_SPARK, "acquired") > 0, "enemy damage should acquire hit spark feedback")
		_expect(_pool_stat(POOL_IDS.DAMAGE_NUMBER, "acquired") > 0, "enemy damage should acquire damage number feedback")

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
	var game_over_panel: Node = _find_node_by_name(get_tree().root, "GameOverPanel")
	_expect(game_over_panel != null, "player death should show game-over panel")
	_expect(not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), "player death should consume the active run save")
	_expect(SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META), "player death should write a meta save")
	var meta_profile: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	_expect(int((meta_profile.get("currencies", {}) as Dictionary).get(META_CURRENCIES.META_ESSENCE, 0)) >= 8, "player death should grant configured meta currency")
	var settlement_label: Label = _find_node_by_name(game_over_panel, "SettlementLabel") as Label
	_expect(settlement_label != null and settlement_label.visible and not String(settlement_label.text).is_empty(), "game-over panel should show settlement rewards")
	var game_over_hud: Node = _find_node_by_name(run_loop, "GameplayHud")
	_expect(
		game_over_hud != null
		and game_over_hud.has_method("is_game_over_message_visible")
		and not bool(game_over_hud.call("is_game_over_message_visible")),
		"player death should not show a second HUD game-over message behind the panel"
	)
	var game_over_time: float = GameClock.now()
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	_expect(is_equal_approx(GameClock.now(), game_over_time), "GameClock should freeze in GAME_OVER")
	smoke_player_damage_source.queue_free()
	if game_over_panel != null:
		await _expect_game_over_buttons(game_over_panel)
	await _expect_bad_run_notice()

	_finish()


func _first_enemy() -> Node:
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
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
	for active_enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
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
	var enemy_a: Node2D = ENEMY_SCENE.instantiate() as Node2D
	var enemy_b: Node2D = ENEMY_SCENE.instantiate() as Node2D
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


func _expect_player_enemy_separation(run_loop: Node, player: Node2D) -> void:
	var isolated_player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	isolated_player.name = "SmokeSeparatedPlayer"
	run_loop.add_child(isolated_player)
	isolated_player.global_position = player.global_position + Vector2(600.0, 0.0)
	var player_stats: Dictionary = {}
	player_stats[STATS.MAX_HP] = 6
	player_stats[STATS.MOVE_SPEED] = 0.0
	player_stats[STATS.DAMAGE_INVULNERABILITY_DURATION] = 0.7
	player_stats[STATS.PLAYER_SEPARATION_RADIUS] = 10.0
	isolated_player.call("configure", player_stats)

	var enemy_data: Dictionary = {
		"max_hp": 5,
		"move_speed": 0.0,
		"contact_damage": 1,
		"contact_damage_type": DAMAGE_TYPES.PHYSICAL,
		"exp_reward": 0,
		"hit_radius": 24.0,
		"separation_radius": 9.0,
	}
	var enemy: Node2D = ENEMY_SCENE.instantiate() as Node2D
	enemy.name = "SmokePlayerSeparatedEnemy"
	run_loop.add_child(enemy)
	enemy.global_position = isolated_player.global_position
	enemy.call("configure", enemy_data, isolated_player)
	var player_life_before_contact: float = float(isolated_player.call("current_life"))

	for _index: int in range(BOOT_FRAMES):
		await get_tree().physics_frame
	var minimum_distance: float = float(enemy.call("separation_radius")) + float(isolated_player.call("separation_radius"))
	var center_distance: float = enemy.global_position.distance_to(isolated_player.global_position)
	_expect(center_distance >= minimum_distance - 0.5, "player separation should push enemies away from the player center")
	_expect(float(isolated_player.call("current_life")) < player_life_before_contact, "separated enemies should still apply contact damage")
	enemy.remove_from_group("active_enemies")
	enemy.queue_free()
	isolated_player.queue_free()


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


func _expect_enemy_ecology_ai(run_loop: Node, player: Node2D) -> void:
	var prey: Node2D = _spawn_smoke_enemy(run_loop, "enemy_swarm", "smoke_ecology_prey")
	var predator: Node2D = _spawn_smoke_enemy(run_loop, "enemy_stalker", "smoke_ecology_predator")
	_expect(prey != null, "ecology smoke should spawn prey enemy")
	_expect(predator != null, "ecology smoke should spawn predator enemy")
	if prey == null or predator == null:
		if prey != null:
			PoolManager.release(prey)
		if predator != null:
			PoolManager.release(predator)
		return

	var ecology_origin: Vector2 = player.global_position + Vector2(2400.0, 1400.0)
	prey.global_position = ecology_origin
	predator.global_position = ecology_origin + Vector2(110.0, 0.0)
	for _index: int in range(10):
		await get_tree().physics_frame

	var prey_summary: Dictionary = prey.call("ai_debug_summary")
	var predator_summary: Dictionary = predator.call("ai_debug_summary")
	_expect(String(prey_summary.get("profile_id", "")) == "enemy_ai_prey_swarm", "prey enemy should use prey AI profile")
	_expect(String(predator_summary.get("profile_id", "")) == "enemy_ai_predator_stalker", "predator enemy should use predator AI profile")
	_expect(String(prey_summary.get("action", "")) == ENEMY_AI_ACTIONS.AI_ACTION_FLEE_THREAT, "prey enemy should flee nearby predator")
	var predator_action: String = String(predator_summary.get("action", ""))
	_expect(
		predator_action == ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
		or predator_action == ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
		"predator enemy should hunt nearby prey"
	)
	PoolManager.release(prey)
	PoolManager.release(predator)


func _expect_whirlwind_slash_skill(run_loop: Node, player: Node2D) -> void:
	var enemy: Node2D = _spawn_smoke_enemy(run_loop, "enemy_chaser", "smoke_skill_whirlwind")
	_expect(enemy != null, "whirlwind smoke should spawn a target enemy")
	if enemy == null:
		return
	enemy.global_position = player.global_position + Vector2(64.0, 0.0)
	enemy.set_physics_process(false)
	var before_summary: Dictionary = run_loop.call("debug_summary")
	var mana_before: float = _skill_resource_current(before_summary, SKILL_RESOURCES.MANA)
	var result: Dictionary = run_loop.call("debug_cast_primary_skill")
	_expect(bool(result.get("ok", false)), "whirlwind slash should cast from the runtime skill system")
	_expect(int(result.get("applied_targets", 0)) >= 1, "whirlwind slash should damage at least one nearby enemy")
	var after_summary: Dictionary = run_loop.call("debug_summary")
	var mana_after: float = _skill_resource_current(after_summary, SKILL_RESOURCES.MANA)
	_expect(mana_after < mana_before, "whirlwind slash should spend mana")
	var cooldown_result: Dictionary = run_loop.call("debug_cast_primary_skill")
	_expect(not bool(cooldown_result.get("ok", true)), "whirlwind slash should not immediately recast")
	_expect(String(cooldown_result.get("reason", "")) == "cooldown", "whirlwind recast should report cooldown")
	PoolManager.release(enemy)


func _skill_resource_current(summary: Dictionary, resource_id: String) -> float:
	var skill_summary: Dictionary = summary.get("skills", {}) as Dictionary
	var resources: Dictionary = skill_summary.get("resources", {}) as Dictionary
	var resource: Dictionary = resources.get(resource_id, {}) as Dictionary
	return float(resource.get("current", 0.0))


func _spawn_smoke_enemy(run_loop: Node, enemy_id: String, wave_key: String) -> Node2D:
	var before_ids: Dictionary = _active_enemy_instance_ids()
	var spawned: bool = bool(run_loop.call("_spawn_enemy", {
		"enemy_id": enemy_id,
	}, wave_key))
	_expect(spawned, "%s should spawn for ecology smoke" % enemy_id)
	if not spawned:
		return null
	for raw_enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if before_ids.has(raw_enemy.get_instance_id()):
			continue
		if raw_enemy is Node2D:
			return raw_enemy as Node2D
	_expect(false, "%s should add an active enemy node" % enemy_id)
	return null


func _active_enemy_instance_ids() -> Dictionary:
	var result: Dictionary = {}
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		result[enemy.get_instance_id()] = true
	return result


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
	var enemy: Node2D = ENEMY_SCENE.instantiate() as Node2D
	enemy.name = "SmokeDrawOrderEnemy"
	run_loop.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(500.0, 0.0)
	enemy.call("configure", enemy_data, player)
	enemy.set_physics_process(false)

	run_loop.call("_spawn_pickup_orb", enemy.global_position, 1)
	await get_tree().process_frame

	var pickup_orb: Node2D = null
	for raw_pickup: Node in get_tree().get_nodes_in_group("active_pickups"):
		if raw_pickup is Node2D:
			pickup_orb = raw_pickup as Node2D
			break
	_expect(pickup_orb != null, "pickup orb should be active for draw-order smoke")
	_expect(pickup_orb != null and pickup_orb.z_index < enemy.z_index, "pickup orbs should draw below enemies")
	if pickup_orb != null:
		PoolManager.release(pickup_orb)
	enemy.remove_from_group("active_enemies")
	enemy.queue_free()


func _expect_pickup_orb_feedback(run_loop: Node, player: Node2D) -> void:
	run_loop.call("_spawn_pickup_orb", player.global_position + Vector2(40.0, 0.0), 0)
	await get_tree().physics_frame
	await get_tree().process_frame

	var pickup_orb: Node2D = null
	for raw_pickup: Node in get_tree().get_nodes_in_group("active_pickups"):
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
	_expect(not pickup_orb.is_in_group("active_pickups"), "collected pickup orb should leave active pickup group during feedback")
	for _index: int in range(PICKUP_FEEDBACK_FRAMES):
		await get_tree().process_frame
	_expect(not bool(pickup_orb.call("is_collect_feedback_active")), "pickup orb collect feedback should finish and release")


func _expect_level_up_choice(run_loop: Node, player: Node2D) -> Dictionary:
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
		level_panel = _find_node_by_name(get_tree().root, "LevelUpPanel")
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
		return {
			"run_loop": run_loop,
			"player": player,
		}

	var choice_id: String = String(level_panel.call("choice_id", 0))
	var snapshot_payload: Dictionary = run_loop.call("create_run_snapshot")
	var ui_restore: Dictionary = snapshot_payload.get("ui_restore", {}) as Dictionary
	_expect(String(ui_restore.get("state", "")) == "level_up", "run snapshot should remember a pending level-up panel")
	_expect(ui_restore.get("choices", []) is Array and (ui_restore.get("choices", []) as Array).size() > 0, "level-up restore point should keep rolled choices")
	_expect(SaveManager.save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN, snapshot_payload), "smoke should save a pending level-up run")
	var formal_boot: Node = _find_node_by_name(get_tree().root, "FormalClientBoot")
	_expect(formal_boot != null, "FormalClientBoot should exist before level-up restore smoke")
	if formal_boot == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	formal_boot.call_deferred("_show_title_menu")
	await get_tree().process_frame
	await _wait_for_title_menu()

	var title_menu: Node = _find_node_by_name(get_tree().root, "TitleMenu")
	var continue_button: Button = _find_node_by_name(title_menu, "ContinueRunButton") as Button
	await _verify_title_settings_entry(title_menu)
	await _verify_meta_progression_entry(title_menu)
	_expect(continue_button != null and continue_button.visible and not continue_button.disabled, "title menu should continue a pending level-up run")
	if continue_button == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	await _click_button(continue_button)

	var restored_run_loop: Node = await _wait_for_state_run_loop(GameState.LEVEL_UP)
	_expect(restored_run_loop != null, "continue should restore into LEVEL_UP when saved at a level-up choice")
	if restored_run_loop == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	run_loop = restored_run_loop
	player = _find_node_by_name(run_loop, "Player") as Node2D
	weapon_system = _find_node_by_name(player, "WeaponSystem") if player != null else null
	level_panel = _find_node_by_name(get_tree().root, "LevelUpPanel")
	_expect(player != null, "level-up restore should rebuild the player")
	_expect(level_panel != null, "level-up restore should show the level-up panel")
	if level_panel == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	_expect(String(level_panel.call("choice_id", 0)) == choice_id, "level-up restore should keep the same rolled first choice")
	await _expect_level_up_pause_overlay(run_loop)
	level_panel = _find_node_by_name(get_tree().root, "LevelUpPanel")
	_expect(level_panel != null, "level-up panel should remain after closing pause overlay")
	if level_panel == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}

	var choice_button: Button = _find_first_button(level_panel)
	_expect(choice_button != null, "level-up panel should expose clickable option buttons")
	if choice_button != null:
		_expect(choice_button.process_mode == Node.PROCESS_MODE_ALWAYS, "level-up buttons should accept input while the tree is paused")
		_expect(choice_button.visible, "level-up option button should be visible before click")
		_expect(not choice_button.disabled, "level-up option button should be enabled before click")
		await _click_button(choice_button)
	_expect(GameState.is_state(GameState.PLAYING), "choosing a level-up option should resume PLAYING")
	var hud: Node = _find_node_by_name(run_loop, "GameplayHud")
	_expect(hud != null and hud.has_method("is_upgrade_feedback_visible") and bool(hud.call("is_upgrade_feedback_visible")), "choosing a level-up option should show upgrade feedback")
	if choice_id == "growth_damage_small" and weapon_system != null:
		_expect(float(weapon_system.call("stat_value", STATS.DAMAGE)) > previous_damage, "damage upgrade should apply immediately")
	elif choice_id == "growth_fire_rate_small" and weapon_system != null:
		_expect(float(weapon_system.call("stat_value", STATS.FIRE_RATE)) > previous_fire_rate, "fire-rate upgrade should apply immediately")
	elif choice_id == "growth_pickup_range_small":
		_expect(float(player.call("pickup_range")) > previous_pickup_range, "pickup-range upgrade should apply immediately")
	else:
		_expect(false, "level-up choice should be a known growth option")
	return {
		"run_loop": run_loop,
		"player": player,
	}


func _expect_level_up_pause_overlay(run_loop: Node) -> void:
	await _push_action_once(ACTIONS.PAUSE)
	var pause_menu: Node = null
	for _index: int in range(BOOT_FRAMES * 2):
		await get_tree().process_frame
		pause_menu = _find_node_by_name(get_tree().root, "PauseMenu")
		if pause_menu != null:
			break
	_expect(GameState.is_state(GameState.PAUSED), "pressing pause during LEVEL_UP should open pause state")
	_expect(pause_menu != null, "pressing pause during LEVEL_UP should show the pause menu")
	var paused_snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var ui_restore: Dictionary = paused_snapshot.get("ui_restore", {}) as Dictionary
	_expect(String(ui_restore.get("state", "")) == "paused", "pause overlay on level-up should snapshot as paused")
	_expect(String(ui_restore.get("underlying_state", "")) == "level_up", "pause overlay on level-up should preserve the underlying level-up state")

	await _push_action_once(ACTIONS.UI_BACK)
	var restored_run_loop: Node = await _wait_for_state_run_loop(GameState.LEVEL_UP)
	_expect(restored_run_loop == run_loop, "ui_back on pause overlay should return to the same LEVEL_UP run loop")
	_expect(_find_node_by_name(get_tree().root, "PauseMenu") == null, "ui_back on pause overlay should remove the pause menu")


func _expect_pause_save_resume(run_loop: Node, player: Node2D) -> Dictionary:
	var saved_position: Vector2 = player.global_position
	var saved_level: int = int(run_loop.call("current_level"))
	var saved_xp: int = int(run_loop.call("current_xp"))
	var saved_time: float = GameClock.now()

	await _push_action_once(ACTIONS.PAUSE)
	var pause_menu: Node = null
	for _index: int in range(BOOT_FRAMES * 2):
		await get_tree().process_frame
		pause_menu = _find_node_by_name(get_tree().root, "PauseMenu")
		if pause_menu != null:
			break
	_expect(GameState.is_state(GameState.PAUSED), "pressing pause should enter PAUSED")
	_expect(pause_menu != null, "pressing pause should show the pause menu")
	if pause_menu == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	await _verify_pause_settings_entry(pause_menu)

	var paused_time: float = GameClock.now()
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	_expect(is_equal_approx(GameClock.now(), paused_time), "GameClock should freeze while pause menu is open")

	var save_button: Button = _find_node_by_name(pause_menu, "SaveAndQuitButton") as Button
	_expect(save_button != null, "pause menu should expose save-and-quit")
	if save_button == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	await _click_button(save_button)
	await _wait_for_title_menu()
	_expect(GameState.is_state(GameState.MAIN_MENU), "save-and-quit should return to MAIN_MENU")
	_expect(SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), "save-and-quit should write a run save")

	var title_menu: Node = _find_node_by_name(get_tree().root, "TitleMenu")
	var continue_button: Button = _find_node_by_name(title_menu, "ContinueRunButton") as Button
	_expect(continue_button != null, "title menu should expose continue when a run save exists")
	if continue_button == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	_expect(continue_button.visible and not continue_button.disabled, "continue button should be enabled when a run save exists")
	await _click_button(continue_button)

	var restored_run_loop: Node = await _wait_for_state_run_loop(GameState.PAUSED)
	_expect(restored_run_loop != null, "continue should mount a paused restored GameplayRunLoop")
	if restored_run_loop == null:
		return {
			"run_loop": null,
			"player": null,
		}
	var restored_player: Node2D = _find_node_by_name(restored_run_loop, "Player") as Node2D
	_expect(restored_player != null, "continue should restore a player")
	if restored_player == null:
		return {
			"run_loop": restored_run_loop,
			"player": player,
		}

	_expect(restored_player.global_position.distance_to(saved_position) < 1.0, "continue should restore player position")
	_expect(int(restored_run_loop.call("current_level")) == saved_level, "continue should restore level")
	_expect(int(restored_run_loop.call("current_xp")) == saved_xp, "continue should restore total xp")
	_expect(absf(GameClock.now() - saved_time) < 0.2, "continue should restore GameClock time")
	var restored_pause_menu: Node = _find_node_by_name(get_tree().root, "PauseMenu")
	_expect(restored_pause_menu != null, "continue should restore the pause menu when the run was saved while paused")
	var resume_button: Button = _find_node_by_name(restored_pause_menu, "ResumeButton") as Button
	_expect(resume_button != null, "restored pause menu should expose resume")
	await _push_action_once(ACTIONS.UI_BACK)
	var resumed_run_loop: Node = await _wait_for_playing_run_loop()
	_expect(resumed_run_loop == restored_run_loop, "ui_back on restored pause menu should keep the same run loop")
	return {
		"run_loop": restored_run_loop,
		"player": restored_player,
	}


func _find_first_button(root_node: Node) -> Button:
	if root_node == null:
		return null
	if root_node is Button:
		return root_node as Button
	for child: Node in root_node.get_children():
		var button: Button = _find_first_button(child)
		if button != null:
			return button
	return null


func _click_button(button: Button) -> void:
	await get_tree().process_frame
	var center: Vector2 = button.get_global_rect().get_center()
	button.grab_focus()

	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	get_viewport().push_input(press, true)
	await get_tree().process_frame

	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	release.global_position = center
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _verify_meta_progression_entry(title_menu: Node) -> void:
	var summary_label: Label = _find_node_by_name(title_menu, "MetaProfileSummaryLabel") as Label
	var expected_summary_text: String = tr("ui_meta_title_summary").format({
		"level": 1,
		"currency": tr("meta_currency_essence_name"),
		"amount": 0,
	})
	_expect(summary_label != null and String(summary_label.text) == expected_summary_text, "title menu should show account level and meta balance summary")
	var meta_button: Button = _find_node_by_name(title_menu, "MetaProgressionButton") as Button
	_expect(meta_button != null and meta_button.visible and not meta_button.disabled, "title menu should expose the meta progression entry")
	if meta_button == null:
		return
	_expect(String(meta_button.text) == tr("ui_meta_progression"), "title meta progression button should use the base label when no upgrade is affordable")
	await _click_button(meta_button)

	var panel: Node = null
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		panel = _find_node_by_name(get_tree().root, "MetaProgressionPanel")
		if panel != null:
			break
	_expect(panel != null, "clicking the meta progression entry should open MetaProgressionPanel")
	if panel == null:
		return

	var upgrade_list: Node = _find_node_by_name(panel, "MetaUpgradeList")
	_expect(upgrade_list != null and upgrade_list.get_child_count() > 0, "MetaProgressionPanel should show upgrade rows")
	_expect(not _focus_is_inside(panel), "MetaProgressionPanel should not receive focus after pointer push")
	await _push_joypad_navigation_once()
	_expect(_focus_is_inside(panel), "MetaProgressionPanel should receive focus after joypad navigation")
	var close_button: Button = _find_node_by_name(panel, "CloseButton") as Button
	_expect(close_button != null, "MetaProgressionPanel should expose a close button")
	await _push_action_once(ACTIONS.UI_BACK)
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		if _find_node_by_name(get_tree().root, "MetaProgressionPanel") == null:
			break
	_expect(_find_node_by_name(get_tree().root, "MetaProgressionPanel") == null, "ui_back should close MetaProgressionPanel")
	_expect(_find_node_by_name(get_tree().root, "TitleMenu") == title_menu, "closing meta progression with ui_back should leave TitleMenu visible")


func _verify_title_settings_entry(title_menu: Node) -> void:
	var settings_button: Button = _find_node_by_name(title_menu, "SettingsButton") as Button
	_expect(settings_button != null and String(settings_button.text) == tr("ui_settings"), "title menu should expose the settings entry")
	if settings_button == null:
		return
	await _click_button(settings_button)
	var settings_panel: Node = await _wait_for_node("SettingsPanel")
	_expect(settings_panel != null, "clicking title settings should open SettingsPanel")
	if settings_panel == null:
		return
	var title_label: Label = _find_node_by_name(settings_panel, "TitleLabel") as Label
	_expect(title_label != null and String(title_label.text) == tr("ui_settings_title"), "SettingsPanel should use localized title from title menu")
	_expect(not _focus_is_inside(settings_panel), "title SettingsPanel should not receive focus after pointer push")
	var close_button: Button = _find_node_by_name(settings_panel, "CloseButton") as Button
	_expect(close_button != null, "SettingsPanel should expose close button")
	await _push_action_once(ACTIONS.UI_BACK)
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		if _find_node_by_name(get_tree().root, "SettingsPanel") == null:
			break
	_expect(_find_node_by_name(get_tree().root, "SettingsPanel") == null, "ui_back should pop title SettingsPanel")
	_expect(_find_node_by_name(get_tree().root, "TitleMenu") != null, "ui_back on title SettingsPanel should leave TitleMenu visible")


func _verify_pause_settings_entry(pause_menu: Node) -> void:
	var settings_button: Button = _find_node_by_name(pause_menu, "SettingsButton") as Button
	_expect(settings_button != null and String(settings_button.text) == tr("ui_settings"), "pause menu should expose the settings entry")
	if settings_button == null:
		return
	await _click_button(settings_button)
	var settings_panel: Node = await _wait_for_node("SettingsPanel")
	_expect(settings_panel != null, "clicking pause settings should open SettingsPanel")
	_expect(GameState.is_state(GameState.PAUSED), "opening settings from pause should keep GameState PAUSED")
	if settings_panel == null:
		return
	_expect(not _focus_is_inside(settings_panel), "pause SettingsPanel should not receive focus after pointer push")
	var close_button: Button = _find_node_by_name(settings_panel, "CloseButton") as Button
	_expect(close_button != null, "pause SettingsPanel should expose close button")
	await _push_action_once(ACTIONS.UI_BACK)
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		if _find_node_by_name(get_tree().root, "SettingsPanel") == null:
			break
	_expect(_find_node_by_name(get_tree().root, "SettingsPanel") == null, "ui_back should pop pause SettingsPanel")
	_expect(_find_node_by_name(get_tree().root, "PauseMenu") == pause_menu, "ui_back on pause SettingsPanel should return to the same PauseMenu")
	_expect(GameState.is_state(GameState.PAUSED), "ui_back on pause SettingsPanel should keep pause state")


func _wait_for_node(node_name: String) -> Node:
	for _index: int in range(BOOT_FRAMES * 2):
		await get_tree().process_frame
		var node: Node = _find_node_by_name(get_tree().root, node_name)
		if node != null:
			return node
	return null


func _push_action_once(action_id: String) -> void:
	var press: InputEventAction = InputEventAction.new()
	press.action = action_id
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().process_frame

	var release: InputEventAction = InputEventAction.new()
	release.action = action_id
	release.pressed = false
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _push_joypad_navigation_once() -> void:
	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_DPAD_DOWN
	press.pressed = true
	get_viewport().push_input(press, true)
	await get_tree().process_frame

	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.button_index = JOY_BUTTON_DPAD_DOWN
	release.pressed = false
	get_viewport().push_input(release, true)
	await get_tree().process_frame


func _focus_is_inside(root_node: Node) -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused != null and (focused == root_node or root_node.is_ancestor_of(focused))


func _write_text(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_expect(false, "smoke should open path for text write: %s" % path)
		return
	file.store_string(content)
	file.flush()


func _run_save_path() -> String:
	return SaveManager.save_root().path_join(SaveManager.DEFAULT_SLOT).path_join("%s.save" % SAVE_KINDS.RUN)


func _expect_game_over_buttons(game_over_panel: Node) -> void:
	_expect(
		_find_node_by_name(game_over_panel, "PurchaseUpgradeButton") == null,
		"game-over panel should not expose direct meta upgrade purchase"
	)
	_expect(
		_find_node_by_name(game_over_panel, "MetaProgressionButton") == null,
		"game-over panel should not expose meta progression entry"
	)

	var restart_button: Button = _find_node_by_name(game_over_panel, "RestartButton") as Button
	_expect(restart_button != null, "game-over panel should expose a restart button")
	if restart_button == null:
		return
	_expect(restart_button.process_mode == Node.PROCESS_MODE_ALWAYS, "game-over restart button should accept input")
	_expect(restart_button.visible, "game-over restart button should be visible before click")
	_expect(not restart_button.disabled, "game-over restart button should be enabled before click")
	await _click_button(restart_button)

	var restarted_run_loop: Node = await _wait_for_playing_run_loop()
	_expect(restarted_run_loop != null, "clicking restart should mount GameplayRunLoop")
	_expect(GameState.is_state(GameState.PLAYING), "clicking restart should resume PLAYING")
	_expect(_find_node_by_name(get_tree().root, "GameOverPanel") == null, "clicking restart should close the game-over panel")
	if restarted_run_loop == null:
		return

	var restarted_player: Node2D = _find_node_by_name(restarted_run_loop, "Player") as Node2D
	_expect(restarted_player != null, "restarted run should create a player")
	if restarted_player == null:
		return

	await _defeat_player_for_game_over(restarted_run_loop, restarted_player)
	var second_game_over_panel: Node = _find_node_by_name(get_tree().root, "GameOverPanel")
	_expect(second_game_over_panel != null, "second player death should show game-over panel")
	if second_game_over_panel == null:
		return

	var quit_button: Button = _find_node_by_name(second_game_over_panel, "QuitToTitleButton") as Button
	_expect(quit_button != null, "game-over panel should expose a quit-to-title button")
	if quit_button == null:
		return
	_expect(quit_button.process_mode == Node.PROCESS_MODE_ALWAYS, "game-over quit-to-title button should accept input")
	_expect(quit_button.visible, "game-over quit-to-title button should be visible before click")
	_expect(not quit_button.disabled, "game-over quit-to-title button should be enabled before click")
	await _click_button(quit_button)
	await _wait_for_title_menu()
	_expect(GameState.is_state(GameState.MAIN_MENU), "clicking quit-to-title should return to MAIN_MENU")
	_expect(_find_node_by_name(get_tree().root, "TitleMenu") != null, "clicking quit-to-title should show the title menu")


func _expect_bad_run_notice() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	_expect(SaveManager.save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN, {"smoke": "bad_run"}), "smoke should create a run save before corruption")
	_write_text(_run_save_path(), "{bad_run")

	var formal_boot: Node = _find_node_by_name(get_tree().root, "FormalClientBoot")
	_expect(formal_boot != null, "FormalClientBoot should exist before bad-run notice smoke")
	if formal_boot == null:
		return
	formal_boot.call_deferred("_show_title_menu")
	await get_tree().process_frame
	await _wait_for_title_menu()

	var title_menu: Node = _find_node_by_name(get_tree().root, "TitleMenu")
	var continue_button: Button = _find_node_by_name(title_menu, "ContinueRunButton") as Button
	_expect(continue_button != null, "bad-run smoke should expose continue before loading corrupted save")
	if continue_button == null:
		return
	_expect(continue_button.visible and not continue_button.disabled, "corrupted run file should make continue visible before load")
	await _click_button(continue_button)

	for _index: int in range(BOOT_FRAMES * 4):
		await get_tree().process_frame
		title_menu = _find_node_by_name(get_tree().root, "TitleMenu")
		var notice_label: Label = _find_node_by_name(title_menu, "RunSaveNoticeLabel") as Label
		if notice_label != null and notice_label.visible:
			_expect(not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), "bad run save should be consumed or quarantined after failed continue")
			_expect(String(notice_label.text) == tr("ui_run_save_unavailable"), "bad run save should show a localized title notice")
			_expect(String(notice_label.text) != "ui_run_save_unavailable", "bad run notice key should resolve through translations")
			var refreshed_continue_button: Button = _find_node_by_name(title_menu, "ContinueRunButton") as Button
			_expect(refreshed_continue_button != null and not refreshed_continue_button.visible, "continue should hide after bad run save is reset")
			return
	_expect(false, "bad run save should show a title notice after failed continue")


func _wait_for_playing_run_loop() -> Node:
	var run_loop: Node = await _wait_for_state_run_loop(GameState.PLAYING)
	return run_loop


func _wait_for_state_run_loop(expected_state: StringName) -> Node:
	for _index: int in range(BOOT_FRAMES * 4):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if run_loop != null and GameState.is_state(expected_state):
			return run_loop
	return null


func _defeat_player_for_game_over(run_loop: Node, player: Node2D) -> void:
	await _wait_player_vulnerability(player)
	var source: Node = Node.new()
	source.name = "SmokeSecondPlayerDamageSource"
	run_loop.add_child(source)
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		float(player.call("max_life")),
		DAMAGE_TYPES.PHYSICAL,
		source,
		player,
		"team_enemy",
		"team_player"
	)
	var result: Dictionary = Combat.apply_damage(player, info)
	_expect(bool(result.get("applied", false)), "Combat should apply restarted player damage")
	_expect(bool(result.get("defeated", false)), "Combat should defeat restarted player")
	_expect(GameState.is_state(GameState.GAME_OVER), "restarted player death should enter GAME_OVER")
	source.queue_free()
	await get_tree().process_frame


func _wait_for_title_menu() -> void:
	for _index: int in range(BOOT_FRAMES * 4):
		await get_tree().process_frame
		if GameState.is_state(GameState.MAIN_MENU) and _find_node_by_name(get_tree().root, "TitleMenu") != null:
			return
	_expect(false, "title menu should appear after quit-to-title")


func _first_enemy_with_name_prefix(name_prefix: String) -> Node:
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if String(enemy.name).begins_with(name_prefix):
			return enemy
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[RuntimeSmoke] %s" % message)


func _finish() -> void:
	Input.action_release(ACTIONS.MOVE_RIGHT)
	Input.action_release(ACTIONS.AIM_UP)
	if _failures.is_empty():
		print("[RuntimeSmoke] passed; time=%.2f bullets_acquired=%d enemies_acquired=%d state=%s" % [
			GameClock.now(),
			_pool_stat(POOL_IDS.BULLET_BASIC, "acquired"),
			_pool_stat(POOL_IDS.ENEMY_CHASER, "acquired"),
			String(GameState.current()),
		])
		get_tree().quit(0)
		return

	print("[RuntimeSmoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
