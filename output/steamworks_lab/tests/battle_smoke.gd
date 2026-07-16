extends SceneTree

# 单机战斗循环 headless smoke：
#   py -3 tools/steamworks_lab_toolchain.py smoke --suite battle

const BATTLE_DIRECTOR_SCRIPT := preload("res://scripts/battle_director.gd")
const ENEMY_BULLET_SCRIPT := preload("res://scripts/enemy_bullet.gd")
const LAB_SAVE_SCRIPT := preload("res://scripts/lab_save.gd")
const LAB_SETTINGS_SCRIPT := preload("res://scripts/lab_settings.gd")
const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")
const MAIN_SCRIPT := preload("res://scripts/steamworks_lab.gd")
const NETWORK_SESSION_SCRIPT := preload("res://scripts/network_session.gd")
const PLAYER_SCRIPT := preload("res://scripts/slime_player.gd")
const TRANSPORT_SCRIPT := preload("res://scripts/transport_adapter.gd")

const SETTINGS_PATH: String = "user://battle_smoke_settings.cfg"
const SETTINGS_FILE_NAME: String = "battle_smoke_settings.cfg"
const SAVE_PATH: String = "user://battle_smoke_save.cfg"
const SAVE_FILE_NAME: String = "battle_smoke_save.cfg"
const SAVE_ROUNDTRIP_PATH: String = "user://battle_smoke_save_roundtrip.cfg"
const SAVE_ROUNDTRIP_FILE_NAME: String = "battle_smoke_save_roundtrip.cfg"
const STEAM_CLIENT_SAVE_PATH: String = "user://battle_smoke_steam_client_save.cfg"
const STEAM_CLIENT_SAVE_FILE_NAME: String = "battle_smoke_steam_client_save.cfg"
const EXPECTED_STEAM_APP_ID: int = 4_955_670

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
	_check(_remove_settings_file() == OK, "settings fixture removal succeeds")
	_check(_remove_save_file() == OK, "save fixture removal succeeds")
	_check(
		_remove_user_file(STEAM_CLIENT_SAVE_PATH, STEAM_CLIENT_SAVE_FILE_NAME) == OK,
		"Steam client record fixture removal succeeds"
	)
	_check_language_defaults()
	_check_save_helper_defaults()
	_check_network_session_defaults()
	_check_steam_app_configuration()
	_check_project_window_defaults()

	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_scene := main_packed.instantiate()
	_configure_test_paths(main_scene)
	root.add_child(main_scene)
	await process_frame
	_check_active_fixture_paths(main_scene, SAVE_PATH)
	_check_runtime_viewport_defaults(main_scene)
	await _check_settings_ui(main_scene)
	await _check_records_ui(main_scene)
	await _check_steam_client_record_chain(main_packed)
	await _check_customize_ui(main_scene)
	await _check_steam_invite_ui(main_scene)

	main_scene.call("_begin_single_player")
	await process_frame

	var director: Node = main_scene.get("_director")
	_check(director != null, "director created on single player start")
	if director == null:
		_remove_settings_file()
		_remove_save_file()
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
	_check(InputMap.has_action("merge"), "merge input action registered")
	var merge_bound := false
	for event in InputMap.action_get_events("merge"):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == KEY_E:
			merge_bound = true
	_check(merge_bound, "merge input action binds E")

	var players: Dictionary = main_scene.call("player_nodes")
	var player := players.get(1) as Node
	_check(player != null, "player 1 exists")
	if player == null:
		_remove_settings_file()
		_remove_save_file()
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
	_configure_test_paths(mirror_scene)
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
	var best_single_seconds := (
		float(active_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.SINGLE))
		if active_save != null
		else 0.0
	)
	var best_multiplayer_seconds := (
		float(active_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER))
		if active_save != null
		else 0.0
	)
	_check(
		(best_single_seconds >= game_over_seconds or is_equal_approx(best_single_seconds, game_over_seconds))
		and best_single_seconds > 0.0,
		"single-player game over records the single-player survival time"
	)
	_check(is_zero_approx(best_multiplayer_seconds), "single-player game over does not change the multiplayer record")
	var save_config := ConfigFile.new()
	var save_load_error := save_config.load(SAVE_PATH)
	var saved_single_seconds := (
		float(save_config.get_value("records", "best_single_survival_seconds", 0.0))
		if save_load_error == OK
		else 0.0
	)
	var saved_multiplayer_seconds := (
		float(save_config.get_value("records", "best_multiplayer_survival_seconds", 0.0))
		if save_load_error == OK
		else 0.0
	)
	_check(
		(saved_single_seconds >= game_over_seconds or is_equal_approx(saved_single_seconds, game_over_seconds))
		and saved_single_seconds > 0.0,
		"single-player record is written to save.cfg (saved %.3f, expected %.3f, load %d)" % [
			saved_single_seconds,
			game_over_seconds,
			save_load_error,
		]
	)
	_check(is_zero_approx(saved_multiplayer_seconds), "single-player save leaves multiplayer record at zero")
	if active_save != null:
		var improved_record := bool(active_save.call(
			"record_survival_time",
			LAB_SAVE_SCRIPT.RecordCategory.SINGLE,
			125.0
		))
		var lowered_record := bool(active_save.call(
			"record_survival_time",
			LAB_SAVE_SCRIPT.RecordCategory.SINGLE,
			60.0
		))
		best_single_seconds = float(active_save.call(
			"best_survival_seconds",
			LAB_SAVE_SCRIPT.RecordCategory.SINGLE
		))
		_check(
			improved_record and not lowered_record and is_equal_approx(best_single_seconds, 125.0),
			"lower single-player survival time does not overwrite its record"
		)
		var records_panel := main_scene.get("_records_panel") as Control
		main_scene.call("_on_records_pressed")
		await process_frame
		_check(records_panel != null and records_panel.visible, "records panel can reopen with saved record")
		_check(_node_tree_has_text(records_panel, "02:05"), "records panel formats the single-player record as MM:SS")
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
		var blocking_obstacle_id: int = int(obstacle_ids_for_block[0])
		var blocking_obstacle := obstacles[blocking_obstacle_id] as Node2D
		blocking_obstacle.global_position = Vector2(270.0, 520.0)
		blocking_obstacle.set("radius", 48.0)
		var all_obstacles: Dictionary = obstacles.duplicate()
		var all_enemies: Dictionary = (director.get("_enemies") as Dictionary).duplicate()
		var active_boss := director.get("_boss") as Node2D
		director.set("_obstacles", {blocking_obstacle_id: blocking_obstacle})
		director.set("_enemies", {})
		director.set("_boss", null)
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
		director.set("_enemies", all_enemies)
		director.set("_boss", active_boss)

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
		director.set("_obstacles", all_obstacles)
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
	director.call("_resolve_active_pickup_collection")
	var held_item: Dictionary = director.call("active_item_for_peer", 1)
	_check(int(held_item.get("id", -1)) == repair_id, "player collects active pickup")
	_check(held_item.get("color", null) is Color, "active pickup exposes HUD icon color")

	director.call("force_spawn_active_pickup", clear_id, player.call("body_center"))
	director.call("_resolve_active_pickup_collection")
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
	_configure_test_paths(ready_scene)
	root.add_child(ready_scene)
	await process_frame
	var couch_router: Node = ready_scene.call("local_input_router")
	var empty_devices: Array[Dictionary] = []
	couch_router.call("debug_set_connected_devices", empty_devices)
	ready_scene.call("_on_start_couch_pressed")
	await process_frame
	_check(ready_scene.get("_director") == null, "local couch waits in ready room")
	ready_scene.call("_on_ready_start_battle_pressed")
	_check(ready_scene.get("_director") == null, "local couch blocks launch without a controller")
	var one_controller: Array[Dictionary] = [{"device_id": 20, "device_name": "Smoke Pad"}]
	couch_router.call("debug_set_connected_devices", one_controller)
	ready_scene.call("_update_status")
	var start_button := ready_scene.get("_start_battle_button") as Button
	_check(start_button != null and not start_button.disabled, "local couch start enabled with P1 and one controller")
	ready_scene.call("_on_ready_start_battle_pressed")
	_check(ready_scene.get("_director") != null, "local couch starts in one process")
	var ready_director: Node = ready_scene.get("_director")
	var ready_world_rect: Rect2 = ready_scene.call("current_world_rect")
	var ready_players: Dictionary = ready_scene.call("player_nodes")
	var ready_player_1 := ready_players.get(1) as Node
	var ready_player_2 := ready_players.get(2) as Node
	var merge_center := ready_world_rect.get_center()
	ready_player_1.call("warp_to", merge_center + Vector2(-18.0, 0.0))
	ready_player_2.call("warp_to", merge_center + Vector2(18.0, 0.0))
	ready_scene.call("_set_merge_intent", 1, true)
	ready_scene.call("_set_merge_intent", 2, true)
	for index in range(50):
		ready_scene.call("_update_gameplay", 1.0 / 60.0)
	var active_merges: Dictionary = ready_scene.get("_active_merges")
	_check(active_merges.size() == 1, "merge forms after both nearby players hold E")
	var merge_id := int(active_merges.keys()[0]) if not active_merges.is_empty() else 0
	var merge_state: Dictionary = active_merges.get(merge_id, {})
	_check(int(merge_state.get("driver", 0)) == 1 and int(merge_state.get("gunner", 0)) == 2, "merge assigns first holder as driver and teammate as gunner")
	_check(ready_player_1 != null and not ready_player_1.visible and ready_player_2 != null and not ready_player_2.visible, "merged participants are hidden while merged")
	var merge_snapshot: Dictionary = ready_scene.call("_build_snapshot")
	_check((merge_snapshot.get("merges", []) as Array).size() == 1, "snapshot carries active merge state")
	var merge_mirror_scene := main_packed.instantiate()
	_configure_test_paths(merge_mirror_scene)
	root.add_child(merge_mirror_scene)
	await process_frame
	merge_mirror_scene.call("_ensure_player", 1, "Host")
	merge_mirror_scene.call("_ensure_player", 2, "Peer 2")
	merge_mirror_scene.call("_apply_merge_snapshots", merge_snapshot.get("merges", []))
	var merge_mirror_merges: Dictionary = merge_mirror_scene.get("_active_merges")
	var merge_mirror_players: Dictionary = merge_mirror_scene.call("player_nodes")
	var merge_mirror_player_1 := merge_mirror_players.get(1) as Node
	_check(merge_mirror_merges.size() == 1, "snapshot mirror creates merged slime")
	_check(merge_mirror_player_1 != null and not merge_mirror_player_1.visible, "snapshot mirror hides merged participant")
	merge_mirror_scene.queue_free()

	var bullets_before := (ready_scene.get("_bullets") as Array).size()
	var driver_damage := int(ready_director.call("player_bullet_damage", 1))
	var driver_pierce := int(ready_director.call("player_pierce_count", 1))
	ready_scene.call("_fire_player_shots", 1, Vector2.UP, false)
	var bullets_after_driver: Array = ready_scene.get("_bullets")
	var bullets_after_driver_count := bullets_after_driver.size()
	var driver_bullet := bullets_after_driver[bullets_after_driver.size() - 1] as Node
	_check(bullets_after_driver.size() == bullets_before + 1, "merge driver fires one main cannon shot")
	_check(int(driver_bullet.get("damage")) == driver_damage + 1, "merge driver main cannon gains damage")
	_check(int(driver_bullet.get("pierce_remaining")) == driver_pierce + 1, "merge driver main cannon gains pierce")
	var gunner_palette: Dictionary = ready_player_2.call("bullet_palette")
	ready_scene.call("_fire_player_shots", 2, Vector2.RIGHT, false)
	var bullets_after_gunner: Array = ready_scene.get("_bullets")
	var gunner_bullet := bullets_after_gunner[bullets_after_gunner.size() - 1] as Node
	_check(bullets_after_gunner.size() == bullets_after_driver_count + 2, "merge gunner fires two side cannon shots")
	_check(gunner_bullet.get("_fill_color") == gunner_palette.get("fill"), "merge gunner side cannon uses gunner bullet color")

	var enemy_bullet := ENEMY_BULLET_SCRIPT.new() as Node2D
	ready_director.add_child(enemy_bullet)
	enemy_bullet.call("configure", merge_state.get("position", merge_center), Vector2.DOWN, 1.0, ready_world_rect)
	(ready_director.get("_enemy_bullets") as Array).append(enemy_bullet)
	var hp_before_merge_hit := int(ready_player_1.get("hp"))
	ready_director.call("_resolve_enemy_bullet_hits")
	active_merges = ready_scene.get("_active_merges")
	merge_state = active_merges.get(merge_id, {})
	_check(int(merge_state.get("shield", 0)) == 2, "enemy bullet hit damages merge shield")
	_check(int(ready_player_1.get("hp")) == hp_before_merge_hit, "enemy bullet hit does not damage merged participant directly")
	for index in range(30):
		ready_scene.call("_update_gameplay", 1.0 / 60.0)
	ready_scene.call("apply_merge_damage", merge_id, 2)
	active_merges = ready_scene.get("_active_merges")
	_check(active_merges.is_empty(), "merge breaks when shield reaches zero")
	_check(ready_player_1.visible and ready_player_2.visible, "participants reappear after merge breaks")
	var merge_cooldowns: Dictionary = ready_scene.get("_merge_cooldowns")
	_check(float(merge_cooldowns.get(1, 0.0)) > 19.0 and float(merge_cooldowns.get(2, 0.0)) > 19.0, "merge break starts cooldown for both participants")

	var multiplayer_pause_panel := ready_scene.get("_pause_panel") as Control
	ready_scene.call("_open_pause_menu")
	await process_frame
	_check(bool(ready_scene.get("_pause_menu_open")), "local couch pause opens shared menu")
	_check(multiplayer_pause_panel != null and multiplayer_pause_panel.visible, "local couch pause panel is visible")
	var multiplayer_clock_before := float(ready_director.call("battle_state").get("time", 0.0))
	for index in range(30):
		ready_scene.call("_update_gameplay", 1.0 / 60.0)
	var multiplayer_clock_after := float(ready_director.call("battle_state").get("time", 0.0))
	_check(is_equal_approx(multiplayer_clock_after, multiplayer_clock_before), "local couch pause freezes the authoritative battle")
	ready_scene.call("_close_pause_menu")
	ready_scene.call("_on_multiplayer_leave_pressed")
	_check((ready_scene.get("_active_merges") as Dictionary).is_empty(), "leaving local couch clears merge state")
	ready_scene.queue_free()

	_check(_remove_settings_file() == OK, "settings fixture cleanup succeeds")
	_check(_remove_save_file() == OK, "save fixture cleanup succeeds")
	_check(
		_remove_user_file(STEAM_CLIENT_SAVE_PATH, STEAM_CLIENT_SAVE_FILE_NAME) == OK,
		"Steam client record fixture cleanup succeeds"
	)
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
	var save := LAB_SAVE_SCRIPT.new(SAVE_PATH)
	var loaded := bool(save.call("load_save"))
	_check(not loaded, "missing save file reports unloaded")
	_check(
		is_zero_approx(float(save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.SINGLE))),
		"missing save defaults the single-player record to zero"
	)
	_check(
		is_zero_approx(float(save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER))),
		"missing save defaults the multiplayer record to zero"
	)
	_check(LAB_SAVE_SCRIPT.format_survival_time(127.0) == "02:07", "survival time formats as MM:SS")

	var failing_save := LAB_SAVE_SCRIPT.new("user://")
	var failed_record := bool(failing_save.call(
		"record_survival_time",
		LAB_SAVE_SCRIPT.RecordCategory.SINGLE,
		42.0
	))
	_check(not failed_record, "record update reports failure when save path cannot be written")
	_check(
		is_zero_approx(float(failing_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.SINGLE))),
		"failed record write rolls back the target category"
	)
	_check(
		is_zero_approx(float(failing_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER))),
		"failed single-player write leaves the multiplayer category unchanged"
	)

	_check(_remove_user_file(SAVE_ROUNDTRIP_PATH, SAVE_ROUNDTRIP_FILE_NAME) == OK, "roundtrip save fixture starts clean")
	var roundtrip_save := LAB_SAVE_SCRIPT.new(SAVE_ROUNDTRIP_PATH)
	_check(
		bool(roundtrip_save.call("record_survival_time", LAB_SAVE_SCRIPT.RecordCategory.SINGLE, 73.0)),
		"single-player record update succeeds after durable write"
	)
	_check(
		bool(roundtrip_save.call("record_survival_time", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER, 91.0)),
		"multiplayer record update succeeds independently"
	)
	_check(
		not bool(roundtrip_save.call("record_survival_time", LAB_SAVE_SCRIPT.RecordCategory.SINGLE, 70.0)),
		"lower single-player time does not overwrite its record"
	)
	_check(
		not bool(roundtrip_save.call("record_survival_time", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER, INF)),
		"invalid multiplayer time does not overwrite its record"
	)
	roundtrip_save.set("_config_path", "user://")
	_check(
		not bool(roundtrip_save.call("record_survival_time", LAB_SAVE_SCRIPT.RecordCategory.SINGLE, 80.0)),
		"failed improved single-player write reports failure"
	)
	_check(
		is_equal_approx(
			float(roundtrip_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.SINGLE)),
			73.0
		),
		"failed improved write rolls back only the single-player category"
	)
	_check(
		is_equal_approx(
			float(roundtrip_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER)),
			91.0
		),
		"single-player rollback preserves the multiplayer category"
	)
	var reloaded_save := LAB_SAVE_SCRIPT.new(SAVE_ROUNDTRIP_PATH)
	_check(bool(reloaded_save.call("load_save")), "saved record reloads from disk")
	_check(
		is_equal_approx(
			float(reloaded_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.SINGLE)),
			73.0
		),
		"reloaded single-player record matches the flushed value"
	)
	_check(
		is_equal_approx(
			float(reloaded_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER)),
			91.0
		),
		"reloaded multiplayer record matches the flushed value"
	)
	var saved_config := ConfigFile.new()
	_check(saved_config.load(SAVE_ROUNDTRIP_PATH) == OK, "v2 record config reloads for schema assertions")
	_check(
		int(saved_config.get_value("records", "schema_version", 0)) == LAB_SAVE_SCRIPT.SCHEMA_VERSION,
		"record config writes schema version 2"
	)
	_check(
		not saved_config.has_section_key("records", "best_survival_seconds"),
		"v2 record config does not write the legacy mixed key"
	)

	var legacy_config := ConfigFile.new()
	legacy_config.set_value("records", "best_survival_seconds", 137.0)
	_check(
		_write_text_file(SAVE_ROUNDTRIP_PATH, legacy_config.encode_to_text()) == OK,
		"legacy record fixture writes successfully"
	)
	var migrated_save := LAB_SAVE_SCRIPT.new(SAVE_ROUNDTRIP_PATH)
	_check(bool(migrated_save.call("load_save")), "legacy mixed record migrates to v2")
	_check(
		is_zero_approx(float(migrated_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.SINGLE)))
		and is_zero_approx(float(migrated_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER))),
		"legacy mixed record is cleared instead of assigned to either category"
	)
	var migrated_config := ConfigFile.new()
	_check(migrated_config.load(SAVE_ROUNDTRIP_PATH) == OK, "migrated record config reloads")
	_check(
		int(migrated_config.get_value("records", "schema_version", 0)) == LAB_SAVE_SCRIPT.SCHEMA_VERSION
		and not migrated_config.has_section_key("records", "best_survival_seconds"),
		"legacy migration persists v2 and removes the mixed key"
	)

	var future_config := ConfigFile.new()
	future_config.set_value("records", "schema_version", LAB_SAVE_SCRIPT.SCHEMA_VERSION + 1)
	future_config.set_value("records", "best_single_survival_seconds", 444.0)
	_check(
		_write_text_file(SAVE_ROUNDTRIP_PATH, future_config.encode_to_text()) == OK,
		"future record fixture writes successfully"
	)
	var future_text_before := _read_text_file(SAVE_ROUNDTRIP_PATH)
	var future_save := LAB_SAVE_SCRIPT.new(SAVE_ROUNDTRIP_PATH)
	_check(not bool(future_save.call("load_save")), "unknown future record schema is rejected")
	_check(
		not bool(future_save.call("record_survival_time", LAB_SAVE_SCRIPT.RecordCategory.SINGLE, 555.0)),
		"rejected future schema blocks later record writes"
	)
	var untouched_future_config := ConfigFile.new()
	_check(
		untouched_future_config.load(SAVE_ROUNDTRIP_PATH) == OK
		and int(untouched_future_config.get_value("records", "schema_version", 0)) == LAB_SAVE_SCRIPT.SCHEMA_VERSION + 1
		and is_equal_approx(
			float(untouched_future_config.get_value("records", "best_single_survival_seconds", 0.0)),
			444.0
		),
		"rejected future schema is not overwritten"
	)
	_check(
		_read_text_file(SAVE_ROUNDTRIP_PATH) == future_text_before,
		"rejected future schema remains byte-for-byte unchanged"
	)
	_check(_remove_user_file(SAVE_ROUNDTRIP_PATH, SAVE_ROUNDTRIP_FILE_NAME) == OK, "roundtrip save fixture cleanup succeeds")


func _check_network_session_defaults() -> void:
	_check(NETWORK_SESSION_SCRIPT.MAX_PLAYERS == 4, "network session caps multiplayer at 4 players")
	_check(NETWORK_SESSION_SCRIPT.SNAPSHOT_CHUNK_SIZE == 900, "snapshot wire payload cap is 900 bytes")
	var enemies: Array[Dictionary] = []
	for enemy_index in range(96):
		enemies.append({
			"id": enemy_index,
			"position": Vector2(float(enemy_index * 7), float(enemy_index * 11)),
			"hp": 3 + enemy_index % 4,
			"kind": "snapshot_roundtrip_enemy_%02d" % enemy_index,
		})
	var snapshot := {
		"players": {1: {"position": Vector2(120.0, 240.0), "hp": 3}},
		"enemies": enemies,
		"time": 31.25,
		"transport": "local",
	}
	var encoded: Dictionary = NETWORK_SESSION_SCRIPT.encode_snapshot_chunks(snapshot)
	var chunks: Array = encoded.get("chunks", [])
	var max_chunk_size := 0
	for raw_chunk in chunks:
		var chunk := raw_chunk as PackedByteArray
		max_chunk_size = maxi(max_chunk_size, chunk.size())
	_check(not chunks.is_empty(), "snapshot dictionary encodes to compressed wire chunks")
	_check(chunks.size() > 1, "snapshot codec fixture spans multiple wire chunks")
	_check(max_chunk_size > 0 and max_chunk_size <= 900, "encoded snapshot chunks stay within the payload cap")
	var decoded: Dictionary = NETWORK_SESSION_SCRIPT.decode_snapshot_chunks(chunks, int(encoded.get("raw_size", 0)))
	_check(decoded == snapshot, "compressed snapshot wire codec roundtrips the application dictionary")
	_check(
		NETWORK_SESSION_SCRIPT.decode_snapshot_chunks(chunks, NETWORK_SESSION_SCRIPT.MAX_SNAPSHOT_RAW_SIZE + 1).is_empty(),
		"snapshot decoder rejects oversized metadata"
	)
	var non_dictionary_raw := var_to_bytes(["not", "a", "snapshot"])
	var non_dictionary_compressed := non_dictionary_raw.compress(FileAccess.COMPRESSION_FASTLZ)
	_check(
		NETWORK_SESSION_SCRIPT.decode_snapshot_chunks([non_dictionary_compressed], non_dictionary_raw.size()).is_empty(),
		"snapshot decoder rejects non-dictionary payloads"
	)

	var assembly_session := NETWORK_SESSION_SCRIPT.new() as Node
	root.add_child(assembly_session)
	var received_snapshots: Array[Dictionary] = []
	assembly_session.connect(
		"snapshot_received",
		func(received_snapshot: Dictionary) -> void:
			received_snapshots.append(received_snapshot)
	)
	assembly_session.call(
		"_receive_snapshot_chunk",
		7,
		int(encoded.get("raw_size", 0)),
		0,
		chunks.size(),
		chunks[0]
	)
	for chunk_index in range(chunks.size()):
		assembly_session.call(
			"_receive_snapshot_chunk",
			8,
			int(encoded.get("raw_size", 0)),
			chunk_index,
			chunks.size(),
			chunks[chunk_index]
		)
	for chunk_index in range(1, chunks.size()):
		assembly_session.call(
			"_receive_snapshot_chunk",
			7,
			int(encoded.get("raw_size", 0)),
			chunk_index,
			chunks.size(),
			chunks[chunk_index]
		)
	_check(
		received_snapshots.size() == 1 and received_snapshots[0] == snapshot,
		"snapshot assembly emits only the latest complete sequence"
	)
	assembly_session.call(
		"_receive_snapshot_chunk",
		9,
		int(encoded.get("raw_size", 0)),
		0,
		chunks.size(),
		chunks[0]
	)
	assembly_session.call(
		"_receive_snapshot_chunk",
		9,
		int(encoded.get("raw_size", 0)) + 1,
		1,
		chunks.size(),
		chunks[1]
	)
	_check((assembly_session.get("_incoming_snapshot_chunks") as Array).is_empty(), "snapshot assembly rejects conflicting metadata")
	assembly_session.call(
		"_receive_snapshot_chunk",
		10,
		int(encoded.get("raw_size", 0)),
		0,
		chunks.size(),
		chunks[0]
	)
	assembly_session.call("leave_session")
	_check((assembly_session.get("_incoming_snapshot_chunks") as Array).is_empty(), "leaving a session clears partial snapshot chunks")
	assembly_session.free()


func _check_steam_app_configuration() -> void:
	_check(TRANSPORT_SCRIPT.configured_app_id() == EXPECTED_STEAM_APP_ID, "Steam ProjectSettings uses the production App ID")
	_check(TRANSPORT_SCRIPT.development_app_id() == EXPECTED_STEAM_APP_ID, "steam_appid.txt matches the production App ID")
	_check(TRANSPORT_SCRIPT.app_id_configuration_is_valid(), "Steam development and runtime App ID sources agree")
	_check(TRANSPORT_SCRIPT.LAB_VERSION_VALUE == "2", "Steam lobby advertises snapshot wire protocol version 2")
	_check(TRANSPORT_SCRIPT.steam_init_result_succeeded(true), "Steam boolean init success is accepted")
	_check(not TRANSPORT_SCRIPT.steam_init_result_succeeded(false), "Steam boolean init failure is rejected")
	_check(TRANSPORT_SCRIPT.steam_init_result_succeeded({"status": 0}), "Steam dictionary init success is accepted")
	_check(not TRANSPORT_SCRIPT.steam_init_result_succeeded({"status": 1}), "Steam dictionary init failure is rejected")
	_check(
		TRANSPORT_SCRIPT.lobby_metadata_is_compatible(
			TRANSPORT_SCRIPT.LAB_MARKER_VALUE,
			TRANSPORT_SCRIPT.LAB_VERSION_VALUE
		),
		"Steam lobby marker and protocol version are accepted"
	)
	_check(
		not TRANSPORT_SCRIPT.lobby_metadata_is_compatible("wrong_marker", TRANSPORT_SCRIPT.LAB_VERSION_VALUE),
		"Steam lobby marker mismatch is rejected"
	)
	_check(
		not TRANSPORT_SCRIPT.lobby_metadata_is_compatible(TRANSPORT_SCRIPT.LAB_MARKER_VALUE, "1"),
		"Steam lobby rejects the legacy snapshot wire protocol version"
	)
	_check(
		TRANSPORT_SCRIPT.steam_disabled_from_args(PackedStringArray(["--disable-steam"])),
		"Steam can be disabled explicitly for deterministic offline smoke"
	)


func _check_project_window_defaults() -> void:
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_width")) == 540, "project viewport width defaults to 540")
	_check(int(ProjectSettings.get_setting("display/window/size/viewport_height")) == 960, "project viewport height defaults to 960")
	_check(String(ProjectSettings.get_setting("display/window/stretch/mode")) == "canvas_items", "project stretch mode uses canvas_items")
	_check(String(ProjectSettings.get_setting("display/window/stretch/aspect")) == "expand", "project stretch aspect expands")


func _check_runtime_viewport_defaults(main_scene: Node) -> void:
	var design_size: Vector2 = main_scene.call("design_viewport_size")
	var viewport_size: Vector2 = main_scene.call("current_viewport_size")
	var world_rect: Rect2 = main_scene.call("current_world_rect")
	var design_origin := (viewport_size - design_size) * 0.5
	var expected_world_rect := Rect2(design_origin + Vector2(20.0, 70.0), Vector2(500.0, 870.0))
	_check(design_size == Vector2(540.0, 960.0), "runtime design viewport is 540x960")
	_check(viewport_size.x >= 540.0 and viewport_size.y >= 960.0, "runtime viewport helper is at least design size")
	_check(_rects_match(world_rect, expected_world_rect), "runtime world rect centers the fixed design inside the expanded viewport")
	_check(
		world_rect.position - design_origin == Vector2(20.0, 70.0)
		and design_origin + design_size - world_rect.end == Vector2(20.0, 20.0),
		"runtime world rect preserves the 500x870 battle area and design margins"
	)


func _check_settings_ui(main_scene: Node) -> void:
	var settings_page := main_scene.get("_settings_page") as Control
	var language_option := main_scene.get("_language_option") as OptionButton
	var resolution_option := main_scene.get("_resolution_option") as OptionButton
	var fullscreen_check := main_scene.get("_fullscreen_check") as CheckButton
	_check(settings_page != null, "settings page exists")
	_check(language_option != null and language_option.item_count == 2, "settings language has exactly 2 options")
	_check(resolution_option != null and resolution_option.item_count == 3, "settings resolution has exactly 3 options")
	_check(fullscreen_check != null and fullscreen_check.visible, "settings fullscreen toggle is visible")

	main_scene.call("_show_settings_page", "start")
	await process_frame
	main_scene.call("_on_language_selected", 1)
	await process_frame
	_check(_node_tree_has_text(main_scene.get("_start_page") as Node, "Single Player"), "English main menu text refreshes")
	_check(_find_button_with_text(main_scene.get("_start_page") as Node, "Quit Game") != null, "English main exit button localizes")
	_check(_node_tree_has_text(settings_page, "Settings"), "English settings page text refreshes")
	_check(resolution_option != null and resolution_option.get_item_text(0) == "540×960 (1080p)", "English 1080p resolution label localizes")
	_check(resolution_option != null and resolution_option.get_item_text(1) == "720×1280 (2K)", "English 2K resolution label localizes")
	_check(resolution_option != null and resolution_option.get_item_text(2) == "1080×1920 (4K)", "English 4K resolution label localizes")
	var active_settings: RefCounted = main_scene.get("_settings")
	_check(active_settings != null and String(active_settings.get("locale")) == LAB_LOCALE_SCRIPT.LOCALE_EN, "English locale stored in lab settings")
	var base_design_size: Vector2 = main_scene.call("design_viewport_size")
	var base_world_rect: Rect2 = main_scene.call("current_world_rect")

	main_scene.call("_on_resolution_selected", 2)
	await process_frame
	var selected_size: Vector2i = active_settings.call("selected_window_size") if active_settings != null else Vector2i.ZERO
	var selected_design_size: Vector2 = main_scene.call("design_viewport_size")
	var selected_world_rect: Rect2 = main_scene.call("current_world_rect")
	_check(active_settings != null and int(active_settings.get("resolution_preset_id")) == 2, "4K resolution stored in lab settings")
	_check(selected_size == Vector2i(1080, 1920), "4K resolution maps to 1080x1920")
	_check(selected_design_size == base_design_size, "runtime design viewport stays fixed across resolution presets")
	_check(_rects_match(selected_world_rect, base_world_rect), "runtime world rect stays fixed across resolution presets")
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	_check(load_error == OK and int(config.get_value("settings", "resolution_preset_id", -1)) == 2, "resolution option writes settings file")
	main_scene.call("_on_resolution_selected", 0)
	await process_frame

	main_scene.call("_on_fullscreen_toggled", true)
	config = ConfigFile.new()
	load_error = config.load(SETTINGS_PATH)
	_check(load_error == OK and bool(config.get_value("settings", "fullscreen", false)), "fullscreen toggle writes settings file")

	main_scene.call("_on_language_selected", 0)
	await process_frame
	_check(_node_tree_has_text(main_scene.get("_start_page") as Node, "开始单人游戏"), "Chinese main menu text refreshes")
	_check(_find_button_with_text(main_scene.get("_start_page") as Node, "退出游戏") != null, "Chinese main exit button localizes")
	_check(_node_tree_has_text(settings_page, "设置"), "Chinese settings page text refreshes")
	_check(resolution_option != null and resolution_option.get_item_text(0) == "540×960（适配 1080p）", "Chinese 1080p resolution label localizes")
	main_scene.call("_on_settings_back_pressed")
	for index in range(20):
		await process_frame


func _check_records_ui(main_scene: Node) -> void:
	var start_page := main_scene.get("_start_page") as Control
	var records_panel := main_scene.get("_records_panel") as Control
	var active_save := main_scene.get("_save") as RefCounted
	_check(
		active_save != null
		and is_zero_approx(float(active_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.SINGLE)))
		and is_zero_approx(float(active_save.call("best_survival_seconds", LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER))),
		"main scene save defaults both survival records to zero"
	)
	_check(records_panel != null, "records panel exists")
	_check(
		int(main_scene.call("_record_category_for_play_mode", MAIN_SCRIPT.PlayMode.SINGLE))
		== LAB_SAVE_SCRIPT.RecordCategory.SINGLE,
		"single-player mode maps to the single-player record"
	)
	_check(
		int(main_scene.call("_record_category_for_play_mode", MAIN_SCRIPT.PlayMode.COUCH))
		== LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER,
		"local couch mode maps to the multiplayer record"
	)
	_check(
		int(main_scene.call("_record_category_for_play_mode", MAIN_SCRIPT.PlayMode.STEAM_HOST))
		== LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER
		and int(main_scene.call("_record_category_for_play_mode", MAIN_SCRIPT.PlayMode.STEAM_CLIENT))
		== LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER,
		"Steam host and client modes map to the multiplayer record"
	)
	_check(
		int(main_scene.call("_record_category_for_play_mode", MAIN_SCRIPT.PlayMode.MENU)) < 0,
		"menu mode does not map to a record category"
	)

	main_scene.call("_show_start_page")
	await process_frame
	main_scene.call("_on_language_selected", 1)
	await process_frame
	_check(_node_tree_has_text(start_page, "Records"), "English records main button localizes")
	main_scene.call("_on_records_pressed")
	await process_frame
	_check(records_panel != null and records_panel.visible, "records panel opens from main menu")
	_check(_node_tree_has_text(records_panel, "Records"), "English records title localizes")
	_check(_node_tree_has_text(records_panel, "Single Player Best"), "English single-player record label localizes")
	_check(_node_tree_has_text(records_panel, "Multiplayer Best"), "English multiplayer record label localizes")
	var single_time_label := records_panel.find_child("SingleSurvivalTime", true, false) as Label
	var multiplayer_time_label := records_panel.find_child("MultiplayerSurvivalTime", true, false) as Label
	_check(
		single_time_label != null and single_time_label.text == "No record yet",
		"English single-player empty state localizes"
	)
	_check(
		multiplayer_time_label != null and multiplayer_time_label.text == "No record yet",
		"English multiplayer empty state localizes"
	)
	records_panel.call("set_survival_records", 65.0, 142.0)
	_check(single_time_label != null and single_time_label.text == "01:05", "single-player row formats its own time")
	_check(multiplayer_time_label != null and multiplayer_time_label.text == "02:22", "multiplayer row formats its own time")
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
	_check(_node_tree_has_text(records_panel, "单人最长存活"), "Chinese single-player record label localizes")
	_check(_node_tree_has_text(records_panel, "多人最长存活"), "Chinese multiplayer record label localizes")
	_check(single_time_label != null and single_time_label.text == "暂无记录", "Chinese single-player empty state localizes")
	_check(multiplayer_time_label != null and multiplayer_time_label.text == "暂无记录", "Chinese multiplayer empty state localizes")
	_check(_find_button_with_text(records_panel, "关闭") != null, "Chinese records close button localizes")
	if records_panel != null:
		records_panel.call("close")
		for index in range(12):
			await process_frame


func _check_steam_client_record_chain(main_packed: PackedScene) -> void:
	_check(
		_remove_user_file(STEAM_CLIENT_SAVE_PATH, STEAM_CLIENT_SAVE_FILE_NAME) == OK,
		"Steam client record fixture starts clean"
	)
	var client_scene := main_packed.instantiate() as Node2D
	_configure_test_paths(client_scene, STEAM_CLIENT_SAVE_PATH)
	root.add_child(client_scene)
	await process_frame
	client_scene.set_physics_process(false)
	_check_active_fixture_paths(client_scene, STEAM_CLIENT_SAVE_PATH)

	var client_session := client_scene.get("_session") as Node
	client_session.set("_is_host", false)
	client_session.set("_active_transport", "steam")
	client_scene.set("_play_mode", MAIN_SCRIPT.PlayMode.STEAM_CLIENT)
	client_scene.call("_start_battle")
	var client_director := client_scene.get("_director") as Node
	_check(
		client_director != null and not bool(client_director.call("is_authority")),
		"Steam client record fixture runs a non-authority battle director"
	)
	client_scene.call(
		"_on_phase_received",
		BATTLE_DIRECTOR_SCRIPT.Phase.GAME_OVER,
		{"time": 47.0, "tier": 3, "boss_kills": 2}
	)
	await process_frame

	var client_save := client_scene.get("_save") as RefCounted
	_check(
		client_save != null
		and is_zero_approx(float(client_save.call(
			"best_survival_seconds",
			LAB_SAVE_SCRIPT.RecordCategory.SINGLE
		)))
		and is_equal_approx(float(client_save.call(
			"best_survival_seconds",
			LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER
		)), 47.0),
		"Steam client authority payload records only the multiplayer survival time"
	)
	var client_config := ConfigFile.new()
	_check(
		client_config.load(STEAM_CLIENT_SAVE_PATH) == OK
		and is_equal_approx(float(client_config.get_value(
			"records",
			"best_multiplayer_survival_seconds",
			0.0
		)), 47.0),
		"Steam client phase chain flushes the authoritative Game Over time"
	)
	client_scene.queue_free()
	await process_frame
	_check(
		_remove_user_file(STEAM_CLIENT_SAVE_PATH, STEAM_CLIENT_SAVE_FILE_NAME) == OK,
		"Steam client record fixture cleanup succeeds"
	)


func _check_customize_ui(main_scene: Node) -> void:
	var start_page := main_scene.get("_start_page") as Control
	var customize_page := main_scene.get("_customize_page") as Control
	var name_input := main_scene.get("_customize_name_input") as LineEdit
	var preview_area := main_scene.get("_customize_preview_area") as Control
	var preview_body := main_scene.get("_customize_preview_body") as Node2D
	var preview_name_label := main_scene.get("_customize_preview_name_label") as Label
	var active_settings := main_scene.get("_settings") as RefCounted
	var slime_buttons: Array = main_scene.get("_slime_swatch_buttons")
	var bullet_buttons: Array = main_scene.get("_bullet_swatch_buttons")
	_check(customize_page != null, "customize page exists")
	_check(name_input != null, "customize nickname input exists")
	_check(preview_area != null and preview_area.clip_contents, "customize slime preview area exists")
	_check(preview_body != null, "customize slime preview body exists")
	_check(preview_name_label != null, "customize nickname preview label exists")
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
	_check(preview_name_label != null and preview_name_label.visible and preview_name_label.text == "Nova", "customize preview shows nickname")
	var preview_palette: Dictionary = PLAYER_SCRIPT.slime_palette(4)
	var preview_fill: Color = preview_body.get("_fill_color") if preview_body != null else Color.BLACK
	_check(preview_fill == preview_palette.get("fill"), "customize preview applies selected slime color")
	var preview_bullets: Array = main_scene.get("_customize_preview_bullets")
	var preview_bullet: Node2D = null
	if not preview_bullets.is_empty():
		preview_bullet = preview_bullets[0] as Node2D
	var bullet_palette: Dictionary = PLAYER_SCRIPT.bullet_palette_option(6)
	var preview_bullet_fill: Color = preview_bullet.get("_fill_color") if preview_bullet != null else Color.BLACK
	_check(preview_bullet != null, "customize preview fires a sample bullet")
	_check(preview_bullet_fill == bullet_palette.get("fill"), "customize preview bullet applies selected bullet color")

	main_scene.call("_on_language_selected", 0)
	await process_frame
	_check(_node_tree_has_text(start_page, "自定义"), "Chinese customize main button localizes")
	_check(_node_tree_has_text(customize_page, "自定义外观"), "Chinese customize title localizes")
	_check(_node_tree_has_text(customize_page, "预览"), "Chinese customize preview localizes")
	_check(name_input != null and name_input.placeholder_text == "留空则使用默认名称", "Chinese customize placeholder localizes")
	main_scene.call("_on_customize_back_pressed")
	for index in range(12):
		await process_frame
	preview_bullets = main_scene.get("_customize_preview_bullets")
	_check(preview_bullets.is_empty(), "customize preview bullets clear when leaving page")


func _check_steam_invite_ui(main_scene: Node) -> void:
	var multiplayer_page := main_scene.get("_multiplayer_page") as Control
	var invite_button := main_scene.get("_invite_steam_button") as Button
	var confirm_panel := main_scene.get("_steam_invite_confirm_panel") as Control
	var active_session := main_scene.get("_session") as Node
	_check(invite_button != null, "Steam invite friend button exists")
	_check(confirm_panel != null and not confirm_panel.visible, "Steam invite confirm panel starts hidden")
	_check(
		TRANSPORT_SCRIPT.connect_lobby_from_args(PackedStringArray(["+connect_lobby", "123456"])) == "123456",
		"Steam connect_lobby launch arg parses"
	)
	_check(
		TRANSPORT_SCRIPT.connect_lobby_from_args(PackedStringArray(["+connect_lobby=987654"])) == "987654",
		"Steam connect_lobby equals launch arg parses"
	)
	_check(
		TRANSPORT_SCRIPT.connect_lobby_from_args(PackedStringArray(["+connect_lobby", "abc"])) == "",
		"Steam connect_lobby ignores invalid launch arg"
	)

	main_scene.call("_show_start_page")
	await process_frame
	main_scene.call("_on_language_selected", 1)
	await process_frame
	main_scene.call("_on_start_multiplayer_pressed")
	await process_frame
	_check(multiplayer_page != null and multiplayer_page.visible, "multiplayer page opens for Steam invite checks")
	var multiplayer_panel := multiplayer_page.get_node_or_null("CenterContainer/MultiplayerPanel") as PanelContainer
	var multiplayer_body := multiplayer_page.get_node_or_null("CenterContainer/MultiplayerPanel/MarginContainer/VBoxContainer/MultiplayerBody") as VBoxContainer
	_check(multiplayer_panel != null and multiplayer_panel.size.y <= 960.0, "multiplayer ready-room panel fits inside the design viewport height")
	_check(multiplayer_body != null, "multiplayer page uses a direct body without scrolling")
	_check(multiplayer_page.get_node_or_null("CenterContainer/MultiplayerPanel/MarginContainer/VBoxContainer/SessionSection") == null, "multiplayer page omits session info section")
	_check(multiplayer_page.get_node_or_null("CenterContainer/MultiplayerPanel/MarginContainer/VBoxContainer/MultiplayerBody/StatusLogSection") == null, "multiplayer page omits status log section")
	_check(_node_tree_has_text(multiplayer_page, "Local Couch Co-op"), "multiplayer page exposes local couch co-op")
	_check(not _node_tree_has_text(multiplayer_page, "Join Local"), "player UI removes local ENet join")
	_check(invite_button != null and invite_button.text == "Invite Friend", "English Steam invite button localizes")
	var steam_available := bool(active_session.call("steam_available")) if active_session != null else false
	_check(invite_button != null and invite_button.disabled == not steam_available, "Steam invite button follows availability")

	main_scene.call("_on_language_selected", 0)
	await process_frame
	_check(invite_button != null and invite_button.text == "邀请好友", "Chinese Steam invite button localizes")

	main_scene.call("_begin_single_player")
	await process_frame
	main_scene.call("_on_steam_invite_join_requested", "123456")
	await process_frame
	_check(String(main_scene.get("_pending_steam_invite_lobby_id")) == "123456", "Steam invite request caches pending lobby")
	_check(confirm_panel != null and confirm_panel.visible, "Steam invite request opens confirm panel")
	main_scene.call("_on_steam_invite_confirm_cancel_pressed")
	await process_frame
	_check(String(main_scene.get("_pending_steam_invite_lobby_id")) == "", "Steam invite cancel clears pending lobby")
	_check(confirm_panel != null and not confirm_panel.visible, "Steam invite cancel closes confirm panel")
	_check(main_scene.get("_director") != null, "Steam invite cancel keeps current game")

	main_scene.call("_on_steam_invite_join_requested", "654321")
	await process_frame
	main_scene.call("_on_steam_invite_confirm_accept_pressed")
	await process_frame
	_check(String(main_scene.get("_pending_steam_invite_lobby_id")) == "", "Steam invite accept clears pending lobby")
	_check(confirm_panel != null and not confirm_panel.visible, "Steam invite accept closes confirm panel")
	main_scene.call("_on_leave_game_pressed")
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


func _configure_test_paths(main_scene: Node, save_path: String = SAVE_PATH) -> void:
	main_scene.set("_settings_config_path", SETTINGS_PATH)
	main_scene.set("_save_config_path", save_path)


func _check_active_fixture_paths(main_scene: Node, expected_save_path: String) -> void:
	var active_settings := main_scene.get("_settings") as RefCounted
	var active_save := main_scene.get("_save") as RefCounted
	_check(
		active_settings != null and String(active_settings.get("_config_path")) == SETTINGS_PATH,
		"main scene loads settings from the pre-ready smoke fixture"
	)
	_check(
		active_save != null and String(active_save.get("_config_path")) == expected_save_path,
		"main scene loads records from the pre-ready smoke fixture"
	)


func _remove_settings_file() -> Error:
	return _remove_user_file(SETTINGS_PATH, SETTINGS_FILE_NAME)


func _remove_save_file() -> Error:
	return _remove_user_file(SAVE_PATH, SAVE_FILE_NAME)


func _write_text_file(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	return write_error


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _remove_user_file(path: String, file_name: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var user_dir := DirAccess.open("user://")
	if user_dir == null:
		return DirAccess.get_open_error()
	return user_dir.remove(file_name)
