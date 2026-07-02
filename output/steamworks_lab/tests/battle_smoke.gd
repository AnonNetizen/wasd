extends SceneTree

# 单机战斗循环 headless smoke：
#   godot --headless --path output/steamworks_lab --script res://tests/battle_smoke.gd

const BATTLE_DIRECTOR_SCRIPT := preload("res://scripts/battle_director.gd")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[battle-smoke] PASS %s" % label)
	else:
		_failures += 1
		print("[battle-smoke] FAIL %s" % label)


func _run() -> void:
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	root.add_child(main_scene)
	await process_frame
	main_scene.call("_begin_single_player")
	await process_frame

	var director: Node = main_scene.get("_director")
	_check(director != null, "director created on single player start")
	if director == null:
		quit(1)
		return

	var ui_root := main_scene.get("_ui_root") as Control
	var start_page := main_scene.get("_start_page") as Control
	var multiplayer_page := main_scene.get("_multiplayer_page") as Control
	var game_page := main_scene.get("_game_page") as Control
	_check(ui_root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "ui root does not swallow mouse input")
	_check(game_page.mouse_filter == Control.MOUSE_FILTER_IGNORE, "game page does not swallow mouse input")
	_check(ui_root.theme != null, "arcade ui theme is installed")
	for index in range(20):
		await process_frame
	_check(start_page != null and not start_page.visible, "start page hidden after game transition")
	_check(multiplayer_page != null and not multiplayer_page.visible, "multiplayer page hidden after game transition")
	_check(game_page != null and game_page.visible, "game page visible after game transition")
	var battle_hud := main_scene.get("_battle_hud") as Control
	var buff_panel := main_scene.get("_buff_panel") as Control
	_check(battle_hud != null and battle_hud.get_node_or_null("ActiveItemLabel") != null, "battle HUD exposes active item slot label")
	_check(buff_panel != null and buff_panel.get_node_or_null("Dimmer") != null, "buff panel exposes animated dimmer")
	_check(InputMap.has_action("active_item"), "active item input action registered")
	var q_bound := false
	for event in InputMap.action_get_events("active_item"):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == KEY_Q:
			q_bound = true
	_check(q_bound, "active item input action binds Q")

	for index in range(720):
		main_scene.call("_update_gameplay", 1.0 / 60.0)
	var state: Dictionary = director.call("battle_state")
	_check(float(state.get("time", 0.0)) > 11.5, "battle clock advanced (%.1f)" % float(state.get("time", 0.0)))
	_check(int(state.get("enemy_count", 0)) > 0, "enemies spawned (%d)" % int(state.get("enemy_count", 0)))

	var players: Dictionary = main_scene.call("player_nodes")
	var player := players.get(1) as Node
	_check(player != null, "player 1 exists")
	if player == null:
		quit(1)
		return

	player.set("invuln_remaining", 0.0)
	var hp_before := int(player.get("hp"))
	var first_hit := bool(player.call("apply_damage", 1))
	var second_hit := bool(player.call("apply_damage", 1))
	_check(first_hit, "first hit lands")
	_check(not second_hit, "second hit blocked by invulnerability")
	_check(int(player.get("hp")) == hp_before - 1, "hp dropped by exactly 1")

	while bool(player.get("alive")):
		player.set("invuln_remaining", 0.0)
		player.call("apply_damage", 1)
	_check(not bool(player.get("alive")), "player dies at 0 hp")

	main_scene.call("_update_gameplay", 1.0 / 60.0)
	var game_over_phase := int(director.get("phase")) == 2
	_check(game_over_phase, "director enters GAME_OVER after full wipe")

	main_scene.call("_reset_battle")
	_check(bool(player.get("alive")), "restart revives player")
	_check(int(player.get("hp")) == 3, "restart restores hp")
	_check(int(director.get("phase")) == 0, "restart returns to BATTLE phase")
	var reset_state: Dictionary = director.call("battle_state")
	_check(int(reset_state.get("enemy_count", 0)) == 0, "restart clears enemies")

	player.set("invuln_remaining", 9999.0)
	var safety := 0
	while int(director.get("phase")) == 0 and safety < 2400:
		main_scene.call("_update_gameplay", 1.0 / 60.0)
		safety += 1
	_check(int(director.get("phase")) == 1, "reaches CHOOSING_BUFF after 30s")
	_check(int(director.get("tier")) == 1, "tier bumped to 1")
	var options: PackedInt32Array = director.call("peer_buff_options", 1)
	_check(options.size() == 3, "3 buff options rolled")

	var clock_before := float(director.call("battle_state").get("time", 0.0))
	for index in range(300):
		main_scene.call("_update_gameplay", 1.0 / 60.0)
	var clock_after := float(director.call("battle_state").get("time", 0.0))
	_check(int(director.get("phase")) == 1, "single player choice has no timeout")
	_check(is_equal_approx(clock_before, clock_after), "battle clock frozen while choosing")

	director.call("submit_buff_choice", 1, 0)
	_check(int(director.get("phase")) == 0, "choice resumes battle")
	var buffs: Dictionary = director.get("_player_buffs")
	var player_buffs: Dictionary = buffs.get(1, {})
	_check(not player_buffs.is_empty(), "buff recorded for player")

	director.set("_next_boss_at", float(director.get("battle_clock")) + 0.4)
	director.set("_obstacle_timer", 0.2)
	for index in range(120):
		main_scene.call("_update_gameplay", 1.0 / 60.0)
	var boss_info: Dictionary = director.call("battle_state").get("boss", {})
	_check(not boss_info.is_empty(), "boss spawned on schedule")
	var obstacles: Dictionary = director.get("_obstacles")
	_check(obstacles.size() > 0, "obstacle spawned")

	var obstacle_ids_for_block: Array = obstacles.keys()
	if not obstacle_ids_for_block.is_empty():
		var blocking_obstacle := obstacles[obstacle_ids_for_block[0]] as Node2D
		blocking_obstacle.global_position = Vector2(270.0, 520.0)
		blocking_obstacle.set("radius", 48.0)
		player.call("revive_full")
		player.set("invuln_remaining", 0.0)
		player.call("warp_to", blocking_obstacle.global_position)
		var hp_before_obstacle := int(player.get("hp"))
		director.call("_resolve_contact_hits")
		var player_center: Vector2 = player.call("body_center")
		var player_distance := player_center.distance_to(blocking_obstacle.global_position)
		var player_clearance := float(player.call("hit_radius")) + float(blocking_obstacle.get("radius"))
		_check(player_distance >= player_clearance - 0.5, "obstacle blocks player movement")
		_check(int(player.get("hp")) == hp_before_obstacle - 1, "obstacle contact still damages player")

		director.call("_spawn_enemy_at", 0, blocking_obstacle.global_position)
		var blocking_enemies: Dictionary = director.get("_enemies")
		var pushed_enemy: Node2D = null
		for enemy_id in blocking_enemies.keys():
			var enemy := blocking_enemies[enemy_id] as Node2D
			if enemy != null and enemy.global_position.distance_to(blocking_obstacle.global_position) < float(blocking_obstacle.get("radius")):
				pushed_enemy = enemy
				break
		director.call("_resolve_enemy_obstacle_blocking")
		if pushed_enemy != null:
			var enemy_clearance := float(pushed_enemy.get("radius")) + float(blocking_obstacle.get("radius"))
			_check(
				pushed_enemy.global_position.distance_to(blocking_obstacle.global_position) >= enemy_clearance - 0.5,
				"obstacle blocks enemy movement"
			)
		else:
			_check(false, "enemy available for obstacle blocking test")
	else:
		_check(false, "obstacle available for blocking test")

	var boss_node := director.get("_boss") as Node2D
	if boss_node != null:
		main_scene.call("_spawn_bullet", 1, boss_node.global_position, Vector2.UP, 560.0)
		var bullets: Array = main_scene.get("_bullets")
		var kill_bullet := bullets.back() as Node2D
		kill_bullet.set("_age", 0.2)
		kill_bullet.global_position = boss_node.global_position
		kill_bullet.set("damage", 999999)
		kill_bullet.set("pierce_remaining", 999)
		main_scene.call("_update_gameplay", 1.0 / 60.0)
	_check(int(director.get("boss_kills")) == 1, "boss killed via bullet hit")
	_check(director.get("_boss") == null, "boss slot cleared after kill")

	var obstacle_ids: Array = (director.get("_obstacles") as Dictionary).keys()
	if not obstacle_ids.is_empty():
		var obstacle := (director.get("_obstacles") as Dictionary)[obstacle_ids[0]] as Node2D
		main_scene.call("_spawn_bullet", 1, obstacle.global_position, Vector2.UP, 560.0)
		var bullets_after: Array = main_scene.get("_bullets")
		var crack_bullet := bullets_after.back() as Node2D
		crack_bullet.set("_age", 0.2)
		crack_bullet.global_position = obstacle.global_position
		crack_bullet.set("damage", 999999)
		crack_bullet.set("pierce_remaining", 999)
		var obstacle_count_before: int = (director.get("_obstacles") as Dictionary).size()
		main_scene.call("_update_gameplay", 1.0 / 60.0)
		var obstacle_count_after: int = (director.get("_obstacles") as Dictionary).size()
		_check(obstacle_count_after == obstacle_count_before - 1, "obstacle destroyed by bullet")
	else:
		_check(false, "obstacle available for destruction test")

	var repair_id: int = BATTLE_DIRECTOR_SCRIPT.ACTIVE_REPAIR_WAVE
	var clear_id: int = BATTLE_DIRECTOR_SCRIPT.ACTIVE_CLEAR_PULSE
	var stasis_id: int = BATTLE_DIRECTOR_SCRIPT.ACTIVE_STASIS_FIELD
	var overload_id: int = BATTLE_DIRECTOR_SCRIPT.ACTIVE_TEAM_OVERLOAD
	var shield_id: int = BATTLE_DIRECTOR_SCRIPT.ACTIVE_EMERGENCY_SHIELD
	player.call("revive_full")
	player.call("warp_to", Vector2(270.0, 820.0))
	var pickup_id := int(director.call("force_spawn_active_pickup", repair_id, player.call("body_center")))
	_check(pickup_id > 0, "active pickup can be force spawned")
	main_scene.call("_update_gameplay", 1.0 / 60.0)
	var held_item: Dictionary = director.call("active_item_for_peer", 1)
	_check(int(held_item.get("id", -1)) == repair_id, "player collects active pickup")

	director.call("force_spawn_active_pickup", clear_id, player.call("body_center"))
	main_scene.call("_update_gameplay", 1.0 / 60.0)
	held_item = director.call("active_item_for_peer", 1)
	_check(int(held_item.get("id", -1)) == clear_id, "new active pickup replaces held item")

	var player_two := main_scene.call("_ensure_player", 2, "Peer 2") as Node
	player_two.call("set_local_or_host_simulated", true)
	player_two.call("warp_to", Vector2(330.0, 820.0))
	player.call("revive_full")
	player_two.call("revive_full")
	player.set("hp", 2)
	player_two.set("hp", 2)
	director.call("force_grant_active_item", 1, repair_id)
	main_scene.call("_try_active_item")
	_check(int(player.get("hp")) == 3 and int(player_two.get("hp")) == 3, "repair wave heals the team")
	held_item = director.call("active_item_for_peer", 1)
	_check(not bool(held_item.get("held", true)), "active item is consumed after use")

	director.call("_spawn_enemy_at", 0, Vector2(270.0, 230.0))
	var enemies_before_clear: int = (director.get("_enemies") as Dictionary).size()
	director.call("_spawn_enemy_volley", Vector2(270.0, 260.0), PackedVector2Array([Vector2.DOWN]), 120.0)
	_check((director.get("_enemy_bullets") as Array).size() > 0, "enemy bullet available before clear pulse")
	director.call("force_grant_active_item", 1, clear_id)
	main_scene.call("_try_active_item")
	_check((director.get("_enemy_bullets") as Array).is_empty(), "clear pulse removes enemy bullets")
	_check((director.get("_enemies") as Dictionary).size() < enemies_before_clear, "clear pulse damages enemies")

	director.call("_spawn_enemy_at", 0, Vector2(270.0, 240.0))
	var stasis_enemy: Node2D = null
	for enemy_id in (director.get("_enemies") as Dictionary).keys():
		var enemy_node := (director.get("_enemies") as Dictionary)[enemy_id] as Node2D
		if enemy_node != null and enemy_node.global_position.distance_to(Vector2(270.0, 240.0)) < 4.0:
			stasis_enemy = enemy_node
			break
	_check(stasis_enemy != null, "enemy available for stasis test")
	var stasis_position := stasis_enemy.global_position if stasis_enemy != null else Vector2.ZERO
	director.call("force_grant_active_item", 1, stasis_id)
	main_scene.call("_try_active_item")
	for index in range(60):
		main_scene.call("_update_gameplay", 1.0 / 60.0)
	if stasis_enemy != null and is_instance_valid(stasis_enemy):
		_check(stasis_enemy.global_position.distance_to(stasis_position) < 0.5, "stasis field freezes enemies")
	_check(float(director.get("_stasis_remaining")) > 0.0, "stasis field keeps remaining duration")

	var cooldown_before_overload := float(director.call("player_fire_cooldown", 1))
	var damage_before_overload := int(director.call("player_bullet_damage", 1))
	director.call("force_grant_active_item", 1, overload_id)
	main_scene.call("_try_active_item")
	_check(float(director.get("_overload_remaining")) > 7.0, "team overload starts timed effect")
	_check(float(director.call("player_fire_cooldown", 1)) < cooldown_before_overload, "team overload improves fire rate")
	_check(int(director.call("player_bullet_damage", 1)) == damage_before_overload + 1, "team overload improves damage")

	director.call("force_spawn_active_pickup", shield_id, Vector2(260.0, 500.0))
	director.call("force_grant_active_item", 1, shield_id)
	var active_snapshot: Dictionary = director.call("battle_snapshot")
	_check((active_snapshot.get("active_pickups", []) as Array).size() > 0, "snapshot carries active pickups")
	_check((active_snapshot.get("active_items", []) as Array).size() > 0, "snapshot carries held active items")
	_check(not (active_snapshot.get("active_effects", {}) as Dictionary).is_empty(), "snapshot carries active effects")
	var mirror_director := BATTLE_DIRECTOR_SCRIPT.new() as Node2D
	root.add_child(mirror_director)
	mirror_director.call("setup", main_scene, main_scene.get("_session"), Rect2(Vector2(20.0, 70.0), Vector2(500.0, 870.0)))
	mirror_director.call("apply_snapshot_battle", active_snapshot)
	_check(
		(mirror_director.get("_active_pickups") as Dictionary).size() == (director.get("_active_pickups") as Dictionary).size(),
		"snapshot mirror reconciles active pickups"
	)
	held_item = mirror_director.call("active_item_for_peer", 1)
	_check(int(held_item.get("id", -1)) == shield_id, "snapshot mirror reconciles held active item")
	_check(float(mirror_director.get("_overload_remaining")) > 0.0, "snapshot mirror reconciles team effect")
	mirror_director.queue_free()

	main_scene.queue_free()
	await process_frame

	var ready_scene := main_packed.instantiate()
	root.add_child(ready_scene)
	await process_frame
	var ready_session: Node = ready_scene.get("_session")
	ready_session.call("host_local", 24569)
	await process_frame
	_check(ready_scene.get("_director") == null, "multiplayer host waits in ready room")
	ready_scene.call("_on_ready_start_battle_pressed")
	_check(ready_scene.get("_director") == null, "ready room blocks solo launch")
	ready_scene.call("_on_peer_joined", 2)
	ready_scene.call("_update_status")
	var start_button := ready_scene.get("_start_battle_button") as Button
	_check(start_button != null and not start_button.disabled, "ready start enabled with two players")
	ready_scene.call("_on_ready_start_battle_pressed")
	_check(ready_scene.get("_director") != null, "ready start launches after peer joins")
	ready_scene.call("_on_multiplayer_leave_pressed")
	ready_scene.queue_free()

	if _failures == 0:
		print("[battle-smoke] ALL PASS")
	else:
		print("[battle-smoke] %d FAILURES" % _failures)
	quit(1 if _failures > 0 else 0)
