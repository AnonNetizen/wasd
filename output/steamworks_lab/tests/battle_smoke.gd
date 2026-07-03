extends SceneTree

# 单机战斗循环 headless smoke：
#   godot --headless --path output/steamworks_lab --script res://tests/battle_smoke.gd

const BATTLE_DIRECTOR_SCRIPT := preload("res://scripts/battle_director.gd")
const LAB_SAVE_SCRIPT := preload("res://scripts/lab_save.gd")
const LAB_SETTINGS_SCRIPT := preload("res://scripts/lab_settings.gd")
const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")
const PLAYER_SCRIPT := preload("res://scripts/slime_player.gd")

const SETTINGS_PATH: String = "user://settings.cfg"
const SETTINGS_FILE_NAME: String = "settings.cfg"
const SAVE_PATH: String = "user://save.cfg"
const SAVE_FILE_NAME: String = "save.cfg"

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
	var settings_backup := _backup_settings_file()
	var save_backup := _backup_save_file()
	_remove_settings_file()
	_remove_save_file()
	_check_language_defaults()
	_check_save_helper_defaults()
	_check_project_window_defaults()

	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	root.add_child(main_scene)
	await process_frame
	_check_runtime_viewport_defaults(main_scene)
	await _check_settings_ui(main_scene)
	await _check_records_ui(main_scene)
	await _check_customize_ui(main_scene)

	main_scene.call("_begin_single_player")
	await process_frame

	var director: Node = main_scene.get("_director")
	_check(director != null, "director created on single player start")
	if director == null:
		_restore_settings_file(settings_backup)
		_restore_save_file(save_backup)
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
	var screen_flash_rect := main_scene.get("_screen_flash_rect") as ColorRect
	var game_status_label := main_scene.get("_game_status_label") as Label
	_check(game_status_label == null, "game HUD does not show debug session text")
	_check(battle_hud != null and battle_hud.get_node_or_null("ActiveItemLabel") != null, "battle HUD exposes active item slot label")
	_check(
		screen_flash_rect != null and screen_flash_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"impact flash overlay does not swallow input"
	)
	main_scene.call("request_screen_shake", 6.0, 0.2)
	main_scene.call("request_screen_flash", Color(1.0, 0.24, 0.12, 1.0), 0.2, 0.15)
	var fx_state: Dictionary = main_scene.call("screen_fx_state")
	_check(float(fx_state.get("shake_remaining", 0.0)) > 0.0, "screen shake can be requested")
	_check(bool(fx_state.get("flash_visible", false)), "impact flash can be requested")
	main_scene.call("_update_screen_effects", 0.35)
	fx_state = main_scene.call("screen_fx_state")
	_check(is_equal_approx(float(fx_state.get("shake_remaining", 1.0)), 0.0), "screen shake fades out")
	_check(not bool(fx_state.get("flash_visible", true)), "impact flash fades out")
	main_scene.call("_on_language_selected", 1)
	await process_frame
	main_scene.call("_refresh_battle_hud")
	await process_frame
	var active_label := battle_hud.get_node_or_null("ActiveItemLabel") as Label
	_check(active_label != null and active_label.text == "Empty", "English HUD active slot localizes empty state")
	_check(buff_panel != null and buff_panel.get_node_or_null("Dimmer") != null, "buff panel exposes animated dimmer")
	main_scene.call("_open_buff_panel", PackedInt32Array([
		BATTLE_DIRECTOR_SCRIPT.BUFF_FIRE_RATE,
		BATTLE_DIRECTOR_SCRIPT.BUFF_DAMAGE,
		BATTLE_DIRECTOR_SCRIPT.BUFF_MULTI_SHOT,
	]))
	await process_frame
	_check(_node_tree_has_text(buff_panel, "Choose a Boost"), "English buff panel title localizes")
	_check(_node_tree_has_text(buff_panel, "Fire Rate Boost\nFire cooldown ×0.85"), "English buff option localizes")
	buff_panel.call("close")
	for index in range(12):
		await process_frame
	main_scene.call("_on_language_selected", 0)
	main_scene.call("_refresh_battle_hud")
	await process_frame
	_check(active_label != null and active_label.text == "空", "Chinese HUD active slot localizes empty state")
	_check(InputMap.has_action("active_item"), "active item input action registered")
	var q_bound := false
	for event in InputMap.action_get_events("active_item"):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == KEY_Q:
			q_bound = true
	_check(q_bound, "active item input action binds Q")
	_check(InputMap.has_action("pause_menu"), "pause menu input action registered")
	var esc_bound := false
	for event in InputMap.action_get_events("pause_menu"):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == KEY_ESCAPE:
			esc_bound = true
	_check(esc_bound, "pause menu input action binds Esc")

	var players: Dictionary = main_scene.call("player_nodes")
	var player := players.get(1) as Node
	_check(player != null, "player 1 exists")
	if player == null:
		_restore_settings_file(settings_backup)
		_restore_save_file(save_backup)
		quit(1)
		return
	var runtime_world_rect: Rect2 = main_scene.call("current_world_rect")
	var director_world_rect: Rect2 = director.get("_world_rect")
	_check(_rects_match(director_world_rect, runtime_world_rect), "director uses current world rect")
	var player_body := player.get_node_or_null("SlimeBody") as Node2D
	var movement_bounds: Rect2 = player_body.get("movement_bounds") if player_body != null else Rect2()
	_check(_rects_match(movement_bounds, runtime_world_rect), "player movement bounds use current world rect")
	var player_name_label := player.get_node_or_null("NameLabel") as Label
	var appearance: Dictionary = player.call("appearance_state")
	_check(String(appearance.get("name", "")) == "Nova", "single player applies custom nickname")
	_check(int(appearance.get("slime_palette_id", -1)) == 4, "single player applies custom slime palette")
	_check(int(appearance.get("bullet_palette_id", -1)) == 6, "single player applies custom bullet palette")
	var expected_bullet_palette: Dictionary = PLAYER_SCRIPT.bullet_palette_option(6)
	var active_bullet_palette: Dictionary = player.call("bullet_palette")
	_check(active_bullet_palette.get("fill") == expected_bullet_palette.get("fill"), "player bullet fill uses custom bullet palette")
	_check(active_bullet_palette.get("edge") == expected_bullet_palette.get("edge"), "player bullet edge uses custom bullet palette")
	_check(player_name_label != null and player_name_label.visible and player_name_label.text == "Nova", "custom nickname label is visible")

	var appearance_snapshot: Dictionary = main_scene.call("_build_snapshot")
	var snapshot_players: Array = appearance_snapshot.get("players", [])
	var snapshot_player: Dictionary = snapshot_players[0] if snapshot_players.size() > 0 and snapshot_players[0] is Dictionary else {}
	var snapshot_appearance: Dictionary = snapshot_player.get("appearance", {})
	_check(String(snapshot_appearance.get("name", "")) == "Nova", "snapshot carries custom nickname")
	_check(int(snapshot_appearance.get("slime_palette_id", -1)) == 4, "snapshot carries slime palette id")
	_check(int(snapshot_appearance.get("bullet_palette_id", -1)) == 6, "snapshot carries bullet palette id")
	var mirror_scene := main_packed.instantiate()
	root.add_child(mirror_scene)
	await process_frame
	mirror_scene.call("_on_snapshot_received", appearance_snapshot)
	await process_frame
	var mirror_players: Dictionary = mirror_scene.call("player_nodes")
	var mirror_player := mirror_players.get(1) as Node
	var mirror_appearance: Dictionary = mirror_player.call("appearance_state") if mirror_player != null else {}
	_check(String(mirror_appearance.get("name", "")) == "Nova", "snapshot mirror applies custom nickname")
	_check(int(mirror_appearance.get("slime_palette_id", -1)) == 4, "snapshot mirror applies slime palette")
	_check(int(mirror_appearance.get("bullet_palette_id", -1)) == 6, "snapshot mirror applies bullet palette")
	mirror_scene.queue_free()
	await process_frame

	var pause_panel := main_scene.get("_pause_panel") as Control
	_check(pause_panel != null, "pause panel exists")
	var pause_clock_before := float(director.call("battle_state").get("time", 0.0))
	player.set("invuln_remaining", 1.0)
	var invuln_before_pause := float(player.get("invuln_remaining"))
	main_scene.call("_open_pause_menu")
	await process_frame
	_check(bool(main_scene.get("_pause_menu_open")), "single player pause opens menu")
	_check(pause_panel != null and pause_panel.visible, "pause panel is visible")
	for index in range(60):
		player.call("_process", 1.0 / 60.0)
		main_scene.call("_update_gameplay", 1.0 / 60.0)
	var pause_clock_after := float(director.call("battle_state").get("time", 0.0))
	_check(is_equal_approx(pause_clock_before, pause_clock_after), "battle clock frozen while paused")
	_check(is_equal_approx(invuln_before_pause, float(player.get("invuln_remaining"))), "shield invulnerability frozen while paused")
	main_scene.call("_on_language_selected", 1)
	await process_frame
	_check(_node_tree_has_text(pause_panel, "Paused"), "English pause title localizes")
	_check(_node_tree_has_text(pause_panel, "Resume"), "English pause resume localizes")
	_check(_node_tree_has_text(pause_panel, "Back to Menu"), "English pause back localizes")
	main_scene.call("_on_language_selected", 0)
	await process_frame
	_check(_node_tree_has_text(pause_panel, "暂停"), "Chinese pause title localizes")
	var esc_event := InputEventKey.new()
	esc_event.keycode = KEY_ESCAPE
	esc_event.pressed = true
	main_scene.call("_unhandled_input", esc_event)
	await process_frame
	_check(not bool(main_scene.get("_pause_menu_open")), "Esc closes pause menu")
	var invuln_before_pause_resume := float(player.get("invuln_remaining"))
	main_scene.call("_update_gameplay", 0.25)
	player.call("_process", 0.25)
	var pause_clock_resumed := float(director.call("battle_state").get("time", 0.0))
	_check(pause_clock_resumed > pause_clock_after, "battle clock resumes after pause")
	_check(float(player.get("invuln_remaining")) < invuln_before_pause_resume, "shield invulnerability resumes after pause")

	for index in range(720):
		main_scene.call("_update_gameplay", 1.0 / 60.0)
	var state: Dictionary = director.call("battle_state")
	_check(float(state.get("time", 0.0)) > 11.5, "battle clock advanced (%.1f)" % float(state.get("time", 0.0)))
	_check(int(state.get("enemy_count", 0)) > 0, "enemies spawned (%d)" % int(state.get("enemy_count", 0)))

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
	var game_over_state: Dictionary = director.call("battle_state")
	var game_over_seconds := float(game_over_state.get("time", 0.0))
	var active_save := main_scene.get("_save") as RefCounted
	var best_seconds := float(active_save.get("best_survival_seconds")) if active_save != null else 0.0
	_check(best_seconds >= game_over_seconds and best_seconds > 0.0, "game over records best survival time")
	var save_config := ConfigFile.new()
	var save_load_error := save_config.load(SAVE_PATH)
	var saved_seconds := float(save_config.get_value("records", "best_survival_seconds", 0.0)) if save_load_error == OK else 0.0
	_check(saved_seconds >= game_over_seconds and saved_seconds > 0.0, "best survival is written to save.cfg")
	if active_save != null:
		var improved_record := bool(active_save.call("record_survival_time", 125.0))
		var lowered_record := bool(active_save.call("record_survival_time", 60.0))
		best_seconds = float(active_save.get("best_survival_seconds"))
		_check(improved_record and not lowered_record and is_equal_approx(best_seconds, 125.0), "lower survival time does not overwrite record")
		var records_panel := main_scene.get("_records_panel") as Control
		main_scene.call("_on_records_pressed")
		await process_frame
		_check(records_panel != null and records_panel.visible, "records panel can reopen with saved record")
		_check(_node_tree_has_text(records_panel, "02:05"), "records panel formats best survival as MM:SS")
		if records_panel != null:
			records_panel.call("close")
			for index in range(12):
				await process_frame

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
	player.set("invuln_remaining", 1.0)
	var invuln_before_choice := float(player.get("invuln_remaining"))
	for index in range(300):
		player.call("_process", 1.0 / 60.0)
		main_scene.call("_update_gameplay", 1.0 / 60.0)
	var clock_after := float(director.call("battle_state").get("time", 0.0))
	_check(int(director.get("phase")) == 1, "single player choice has no timeout")
	_check(is_equal_approx(clock_before, clock_after), "battle clock frozen while choosing")
	_check(is_equal_approx(invuln_before_choice, float(player.get("invuln_remaining"))), "shield invulnerability frozen while choosing")

	director.call("submit_buff_choice", 1, 0)
	_check(int(director.get("phase")) == 0, "choice resumes battle")
	var invuln_before_resume := float(player.get("invuln_remaining"))
	player.call("_process", 0.25)
	_check(float(player.get("invuln_remaining")) < invuln_before_resume, "shield invulnerability resumes after choosing")
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
		fx_state = main_scene.call("screen_fx_state")
		_check(float(fx_state.get("shake_remaining", 0.0)) > 0.0, "player damage triggers screen shake")
		_check(float(fx_state.get("flash_alpha", 0.0)) > 0.0, "player damage triggers impact flash")
		main_scene.call("_clear_screen_fx")

		director.call("_spawn_enemy_at", 0, blocking_obstacle.global_position)
		var blocking_enemies: Dictionary = director.get("_enemies")
		var pushed_enemy: Node2D = null
		var closest_distance := INF
		for enemy_id in blocking_enemies.keys():
			var enemy := blocking_enemies[enemy_id] as Node2D
			if enemy == null:
				continue
			var enemy_distance := enemy.global_position.distance_to(blocking_obstacle.global_position)
			if enemy_distance < closest_distance:
				closest_distance = enemy_distance
				pushed_enemy = enemy
		if pushed_enemy != null:
			pushed_enemy.global_position = blocking_obstacle.global_position
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
	_clear_director_pickups(director)
	var action_position := runtime_world_rect.get_center() + Vector2(0.0, runtime_world_rect.size.y * 0.28)
	player.call("revive_full")
	player.call("warp_to", action_position)
	var pickup_id := int(director.call("force_spawn_active_pickup", repair_id, player.call("body_center")))
	_check(pickup_id > 0, "active pickup can be force spawned")
	main_scene.call("_update_gameplay", 1.0 / 60.0)
	var held_item: Dictionary = director.call("active_item_for_peer", 1)
	_check(int(held_item.get("id", -1)) == repair_id, "player collects active pickup")
	_check(held_item.get("color", null) is Color, "active pickup exposes HUD icon color")

	director.call("force_spawn_active_pickup", clear_id, player.call("body_center"))
	main_scene.call("_update_gameplay", 1.0 / 60.0)
	held_item = director.call("active_item_for_peer", 1)
	_check(int(held_item.get("id", -1)) == clear_id, "new active pickup replaces held item")

	var player_two := main_scene.call("_ensure_player", 2, "Peer 2") as Node
	player_two.call("set_local_or_host_simulated", true)
	player_two.call("warp_to", action_position + Vector2(80.0, 0.0))
	player.call("revive_full")
	player_two.call("revive_full")
	player.set("hp", 2)
	player_two.set("hp", 2)
	director.call("force_grant_active_item", 1, repair_id)
	main_scene.call("_try_active_item")
	_check(int(player.get("hp")) == 3 and int(player_two.get("hp")) == 3, "repair wave heals the team")
	held_item = director.call("active_item_for_peer", 1)
	_check(not bool(held_item.get("held", true)), "active item is consumed after use")

	var enemy_test_position := runtime_world_rect.position + Vector2(runtime_world_rect.size.x * 0.5, 160.0)
	director.call("_spawn_enemy_at", 0, enemy_test_position)
	var enemies_before_clear: int = (director.get("_enemies") as Dictionary).size()
	director.call("_spawn_enemy_volley", enemy_test_position + Vector2(0.0, 30.0), PackedVector2Array([Vector2.DOWN]), 120.0)
	_check((director.get("_enemy_bullets") as Array).size() > 0, "enemy bullet available before clear pulse")
	director.call("force_grant_active_item", 1, clear_id)
	main_scene.call("_try_active_item")
	_check((director.get("_enemy_bullets") as Array).is_empty(), "clear pulse removes enemy bullets")
	_check((director.get("_enemies") as Dictionary).size() < enemies_before_clear, "clear pulse damages enemies")

	var stasis_test_position := runtime_world_rect.position + Vector2(runtime_world_rect.size.x * 0.5, 180.0)
	director.call("_spawn_enemy_at", 0, stasis_test_position)
	var stasis_enemy: Node2D = null
	for enemy_id in (director.get("_enemies") as Dictionary).keys():
		var enemy_node := (director.get("_enemies") as Dictionary)[enemy_id] as Node2D
		if enemy_node != null and enemy_node.global_position.distance_to(stasis_test_position) < 4.0:
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

	director.call("force_spawn_active_pickup", shield_id, runtime_world_rect.get_center())
	director.call("force_grant_active_item", 1, shield_id)
	var active_snapshot: Dictionary = director.call("battle_snapshot")
	_check((active_snapshot.get("active_pickups", []) as Array).size() > 0, "snapshot carries active pickups")
	_check((active_snapshot.get("active_items", []) as Array).size() > 0, "snapshot carries held active items")
	_check(not (active_snapshot.get("active_effects", {}) as Dictionary).is_empty(), "snapshot carries active effects")
	var mirror_director := BATTLE_DIRECTOR_SCRIPT.new() as Node2D
	root.add_child(mirror_director)
	mirror_director.call("setup", main_scene, main_scene.get("_session"), runtime_world_rect)
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
	var ready_director: Node = ready_scene.get("_director")
	var multiplayer_pause_panel := ready_scene.get("_pause_panel") as Control
	ready_scene.call("_open_pause_menu")
	await process_frame
	_check(bool(ready_scene.get("_pause_menu_open")), "multiplayer pause opens local menu")
	_check(multiplayer_pause_panel != null and multiplayer_pause_panel.visible, "multiplayer pause panel is visible")
	var multiplayer_clock_before := float(ready_director.call("battle_state").get("time", 0.0))
	for index in range(30):
		ready_scene.call("_update_gameplay", 1.0 / 60.0)
	var multiplayer_clock_after := float(ready_director.call("battle_state").get("time", 0.0))
	_check(multiplayer_clock_after > multiplayer_clock_before, "multiplayer pause does not freeze host clock")
	ready_scene.call("_close_pause_menu")
	ready_scene.call("_on_multiplayer_leave_pressed")
	ready_scene.queue_free()

	_restore_settings_file(settings_backup)
	_restore_save_file(save_backup)
	if _failures == 0:
		print("[battle-smoke] ALL PASS")
	else:
		print("[battle-smoke] %d FAILURES" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_language_defaults() -> void:
	_check(
		LAB_SETTINGS_SCRIPT.default_locale_for_language("schinese") == LAB_LOCALE_SCRIPT.LOCALE_ZH_CN,
		"Steam schinese maps to zh_CN"
	)
	_check(
		LAB_SETTINGS_SCRIPT.default_locale_for_language("tchinese") == LAB_LOCALE_SCRIPT.LOCALE_ZH_CN,
		"Steam tchinese maps to zh_CN"
	)
	_check(
		LAB_SETTINGS_SCRIPT.default_locale_for_language("zh_TW") == LAB_LOCALE_SCRIPT.LOCALE_ZH_CN,
		"system zh_TW maps to zh_CN"
	)
	_check(
		LAB_SETTINGS_SCRIPT.default_locale_for_language("english") == LAB_LOCALE_SCRIPT.LOCALE_EN,
		"Steam english maps to en"
	)
	_check(
		LAB_SETTINGS_SCRIPT.default_locale_for_language("japanese") == LAB_LOCALE_SCRIPT.LOCALE_EN,
		"non-Chinese languages map to en"
	)


func _check_save_helper_defaults() -> void:
	var save := LAB_SAVE_SCRIPT.new()
	var loaded := bool(save.call("load_save"))
	_check(not loaded, "missing save file reports unloaded")
	_check(is_equal_approx(float(save.get("best_survival_seconds")), 0.0), "missing save defaults best survival to zero")
	_check(LAB_SAVE_SCRIPT.format_survival_time(127.0) == "02:07", "survival time formats as MM:SS")


func _check_project_window_defaults() -> void:
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 720, "project viewport width defaults to 720")
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 1280, "project viewport height defaults to 1280")
	_check(String(ProjectSettings.get_setting("display/window/stretch/mode")) == "canvas_items", "project stretch mode uses canvas_items")
	_check(String(ProjectSettings.get_setting("display/window/stretch/aspect")) == "expand", "project stretch aspect expands")


func _check_runtime_viewport_defaults(main_scene: Node) -> void:
	var design_size: Vector2 = main_scene.call("design_viewport_size")
	var viewport_size: Vector2 = main_scene.call("current_viewport_size")
	var world_rect: Rect2 = main_scene.call("current_world_rect")
	_check(design_size == Vector2(720.0, 1280.0), "runtime design viewport is 720x1280")
	_check(viewport_size.x >= 720.0 and viewport_size.y >= 1280.0, "runtime viewport helper is at least design size")
	_check(world_rect.size.x > 660.0 and world_rect.size.y > 1150.0, "runtime world rect scales up for 720x1280")


func _check_settings_ui(main_scene: Node) -> void:
	var settings_page := main_scene.get("_settings_page") as Control
	var language_option := main_scene.get("_language_option") as OptionButton
	var fullscreen_check := main_scene.get("_fullscreen_check") as CheckButton
	_check(settings_page != null, "settings page exists")
	_check(language_option != null and language_option.item_count == 2, "settings language has exactly 2 options")
	_check(fullscreen_check != null and fullscreen_check.visible, "settings fullscreen toggle is visible")

	main_scene.call("_show_settings_page", "start")
	await process_frame
	main_scene.call("_on_language_selected", 1)
	await process_frame
	_check(_node_tree_has_text(main_scene.get("_start_page") as Node, "Single Player"), "English main menu text refreshes")
	_check(_find_button_with_text(main_scene.get("_start_page") as Node, "Quit Game") != null, "English main exit button localizes")
	_check(_node_tree_has_text(settings_page, "Settings"), "English settings page text refreshes")
	var active_settings: RefCounted = main_scene.get("_settings")
	_check(active_settings != null and String(active_settings.get("locale")) == LAB_LOCALE_SCRIPT.LOCALE_EN, "English locale stored in lab settings")

	main_scene.call("_on_fullscreen_toggled", true)
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	_check(load_error == OK and bool(config.get_value("settings", "fullscreen", false)), "fullscreen toggle writes settings file")

	main_scene.call("_on_language_selected", 0)
	await process_frame
	_check(_node_tree_has_text(main_scene.get("_start_page") as Node, "开始单人游戏"), "Chinese main menu text refreshes")
	_check(_find_button_with_text(main_scene.get("_start_page") as Node, "退出游戏") != null, "Chinese main exit button localizes")
	_check(_node_tree_has_text(settings_page, "设置"), "Chinese settings page text refreshes")
	main_scene.call("_on_settings_back_pressed")
	for index in range(20):
		await process_frame


func _check_records_ui(main_scene: Node) -> void:
	var start_page := main_scene.get("_start_page") as Control
	var records_panel := main_scene.get("_records_panel") as Control
	var active_save := main_scene.get("_save") as RefCounted
	_check(active_save != null and is_equal_approx(float(active_save.get("best_survival_seconds")), 0.0), "main scene save defaults best survival to zero")
	_check(records_panel != null, "records panel exists")

	main_scene.call("_show_start_page")
	await process_frame
	main_scene.call("_on_language_selected", 1)
	await process_frame
	_check(_node_tree_has_text(start_page, "Records"), "English records main button localizes")
	main_scene.call("_on_records_pressed")
	await process_frame
	_check(records_panel != null and records_panel.visible, "records panel opens from main menu")
	_check(_node_tree_has_text(records_panel, "Records"), "English records title localizes")
	_check(_node_tree_has_text(records_panel, "Best Survival"), "English records label localizes")
	_check(_node_tree_has_text(records_panel, "No record yet"), "English no-record text localizes")
	var english_close_button := _find_button_with_text(records_panel, "Close")
	_check(english_close_button != null, "English records close button exists")
	if english_close_button != null:
		english_close_button.pressed.emit()
		for index in range(12):
			await process_frame
		_check(not records_panel.visible, "records close button closes panel")

	main_scene.call("_on_language_selected", 0)
	await process_frame
	_check(_node_tree_has_text(start_page, "记录"), "Chinese records main button localizes")
	main_scene.call("_on_records_pressed")
	await process_frame
	_check(_node_tree_has_text(records_panel, "记录"), "Chinese records title localizes")
	_check(_node_tree_has_text(records_panel, "最长存活时间"), "Chinese records label localizes")
	_check(_node_tree_has_text(records_panel, "暂无记录"), "Chinese no-record text localizes")
	_check(_find_button_with_text(records_panel, "关闭") != null, "Chinese records close button localizes")
	if records_panel != null:
		records_panel.call("close")
		for index in range(12):
			await process_frame


func _check_customize_ui(main_scene: Node) -> void:
	var start_page := main_scene.get("_start_page") as Control
	var customize_page := main_scene.get("_customize_page") as Control
	var name_input := main_scene.get("_customize_name_input") as LineEdit
	var preview_area := main_scene.get("_customize_preview_area") as Control
	var preview_body := main_scene.get("_customize_preview_body") as Node2D
	var active_settings := main_scene.get("_settings") as RefCounted
	var slime_buttons: Array = main_scene.get("_slime_swatch_buttons")
	var bullet_buttons: Array = main_scene.get("_bullet_swatch_buttons")
	_check(customize_page != null, "customize page exists")
	_check(name_input != null, "customize nickname input exists")
	_check(preview_area != null and preview_area.clip_contents, "customize slime preview area exists")
	_check(preview_body != null, "customize slime preview body exists")
	_check(slime_buttons.size() == 8, "customize slime palette has 8 swatches")
	_check(bullet_buttons.size() == 8, "customize bullet palette has 8 swatches")

	main_scene.call("_show_start_page")
	await process_frame
	main_scene.call("_on_language_selected", 1)
	await process_frame
	_check(_node_tree_has_text(start_page, "Customize"), "English customize main button localizes")
	main_scene.call("_on_customize_pressed")
	await process_frame
	_check(customize_page != null and customize_page.visible, "customize page opens from main menu")
	_check(_node_tree_has_text(customize_page, "Customize Appearance"), "English customize title localizes")
	_check(_node_tree_has_text(customize_page, "Preview"), "English customize preview localizes")
	_check(name_input != null and name_input.placeholder_text == "Leave blank for default name", "English customize placeholder localizes")

	main_scene.call("_on_customize_name_changed", "Nova")
	main_scene.call("_on_slime_palette_selected", 4)
	main_scene.call("_on_bullet_palette_selected", 6)
	await process_frame
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	_check(load_error == OK, "customize writes settings file")
	_check(String(config.get_value("settings", "player_name", "")) == "Nova", "customize writes nickname")
	_check(int(config.get_value("settings", "slime_palette_id", -1)) == 4, "customize writes slime palette id")
	_check(int(config.get_value("settings", "bullet_palette_id", -1)) == 6, "customize writes bullet palette id")
	_check(active_settings != null and String(active_settings.get("player_name")) == "Nova", "customize stores nickname in settings")
	var preview_palette: Dictionary = PLAYER_SCRIPT.slime_palette(4)
	var preview_fill: Color = preview_body.get("_fill_color") if preview_body != null else Color.BLACK
	_check(preview_fill == preview_palette.get("fill"), "customize preview applies selected slime color")

	main_scene.call("_on_language_selected", 0)
	await process_frame
	_check(_node_tree_has_text(start_page, "自定义"), "Chinese customize main button localizes")
	_check(_node_tree_has_text(customize_page, "自定义外观"), "Chinese customize title localizes")
	_check(_node_tree_has_text(customize_page, "预览"), "Chinese customize preview localizes")
	_check(name_input != null and name_input.placeholder_text == "留空则使用默认名称", "Chinese customize placeholder localizes")
	main_scene.call("_on_customize_back_pressed")
	for index in range(12):
		await process_frame


func _node_tree_has_text(root_node: Node, expected_text: String) -> bool:
	if root_node == null:
		return false
	if root_node is Label:
		var label := root_node as Label
		if label.text == expected_text:
			return true
	if root_node is Button:
		var button := root_node as Button
		if button.text == expected_text:
			return true
	for child in root_node.get_children():
		if _node_tree_has_text(child, expected_text):
			return true
	return false


func _find_button_with_text(root_node: Node, expected_text: String) -> Button:
	if root_node == null:
		return null
	if root_node is Button:
		var button := root_node as Button
		if button.text == expected_text:
			return button
	for child in root_node.get_children():
		var found_button := _find_button_with_text(child, expected_text)
		if found_button != null:
			return found_button
	return null


func _rects_match(a: Rect2, b: Rect2) -> bool:
	return (
		a.position.distance_to(b.position) < 0.05
		and a.size.distance_to(b.size) < 0.05
	)


func _clear_director_pickups(director: Node) -> void:
	var active_pickups: Dictionary = director.get("_active_pickups")
	for pickup_id in active_pickups.keys():
		var pickup := active_pickups[pickup_id] as Node
		if pickup != null and is_instance_valid(pickup):
			pickup.queue_free()
	active_pickups.clear()


func _backup_settings_file() -> Dictionary:
	var backup := {"exists": FileAccess.file_exists(SETTINGS_PATH), "text": ""}
	if bool(backup["exists"]):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file != null:
			backup["text"] = file.get_as_text()
	return backup


func _restore_settings_file(backup: Dictionary) -> void:
	_remove_settings_file()
	if not bool(backup.get("exists", false)):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(String(backup.get("text", "")))


func _remove_settings_file() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var user_dir := DirAccess.open("user://")
	if user_dir != null:
		user_dir.remove(SETTINGS_FILE_NAME)


func _backup_save_file() -> Dictionary:
	var backup := {"exists": FileAccess.file_exists(SAVE_PATH), "text": ""}
	if bool(backup["exists"]):
		var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file != null:
			backup["text"] = file.get_as_text()
	return backup


func _restore_save_file(backup: Dictionary) -> void:
	_remove_save_file()
	if not bool(backup.get("exists", false)):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(String(backup.get("text", "")))


func _remove_save_file() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var user_dir := DirAccess.open("user://")
	if user_dir != null:
		user_dir.remove(SAVE_FILE_NAME)
