extends SceneTree

const MANIFEST_PATH := "res://asset_sources.json"
const EXPECTED_ASSET_IDS := [
	"zbtPq4dOJL", "4LjT020LQh", "kzpT6fNmM5", "UgBmRVnQ9h", "D5wW2jDO42",
	"4UvIHxnoSR", "MJmAjTeT9h", "1xtAc12dmv", "ijqVDSeIM5", "UyH95ZAeJ2",
	"T7Ge6maWq4", "LbGiYP5iJu", "V7XQDxF8JC", "HtpdTh3Ld6", "s0joFFrQoy",
]

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[lowpoly-survivors-smoke] PASS %s" % label)
	else:
		_failures += 1
		print("[lowpoly-survivors-smoke] FAIL %s" % label)


func _run() -> void:
	_check_assets()
	_check_balance_loader()
	_check_input_map()
	await _check_main_scene()
	await _check_gameplay_loop()
	await _check_online_multiplayer()
	if _failures == 0:
		print("[lowpoly-survivors-smoke] ALL PASS")
	quit(1 if _failures > 0 else 0)


func _check_assets() -> void:
	_check(FileAccess.file_exists(MANIFEST_PATH), "asset manifest exists")
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	_check(file != null, "asset manifest opens")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(parsed is Dictionary, "asset manifest parses")
	if not parsed is Dictionary:
		return
	var entries: Array = (parsed as Dictionary).get("assets", []) as Array
	_check(entries.size() == EXPECTED_ASSET_IDS.size(), "asset manifest contains 15 selected models")
	var found_ids: Dictionary = {}
	for value: Variant in entries:
		if not value is Dictionary:
			continue
		var entry := value as Dictionary
		var public_id := String(entry.get("public_id", ""))
		found_ids[public_id] = true
		_check(String(entry.get("author", "")) == "Quaternius", "asset %s author is Quaternius" % public_id)
		_check(String(entry.get("license", "")) == "CC0 1.0", "asset %s is CC0" % public_id)
		var path := String(entry.get("project_path", ""))
		_check(ResourceLoader.exists(path), "asset %s imports" % public_id)
	for public_id: String in EXPECTED_ASSET_IDS:
		_check(found_ids.has(public_id), "asset %s is declared" % public_id)


func _check_balance_loader() -> void:
	var loader := LowpolyBalanceLoader.new()
	_check(loader.load_balance(), "balance loads and validates")
	_check(loader.get_errors().is_empty(), "balance diagnostics are empty")
	var run := loader.get_run_config()
	_check(int(run.get("regular_enemy_cap", 0)) == 220, "regular enemy cap is 220")
	_check(int(run.get("enemy_projectile_cap", 0)) == 160, "enemy projectile cap is 160")
	_check(int(run.get("player_projectile_cap", 0)) == 120, "player projectile cap is 120")
	_check(int(run.get("pickup_cap", 0)) == 400, "pickup cap is 400")
	_check(is_equal_approx(float(run.get("duration_seconds", 0.0)), 600.0), "run duration is ten minutes")
	_check(
		is_equal_approx(float(loader.get_weapon_config(&"pulse_rifle").get("visual_length", 0.0)), 0.92),
		"pulse rifle has a meter-scale visual target"
	)
	_check(loader.get_stages().size() == 4, "timeline has four stages")
	var stages := loader.get_stages()
	_check((stages[0].get("weights", {}) as Dictionary).keys() == ["enemy_small"], "stage one uses small enemies")
	_check((stages[1].get("weights", {}) as Dictionary).has("enemy_flying"), "stage two introduces flying enemies")
	_check((stages[2].get("weights", {}) as Dictionary).has("enemy_large"), "stage three introduces large enemies")
	_check((stages[3].get("weights", {}) as Dictionary).has("enemy_fox_mech"), "stage four includes ranged mechs")
	for profile_id: StringName in [
		&"player", &"enemy_small", &"enemy_flying", &"enemy_large",
		&"enemy_fox_mech", &"final_boss",
	]:
		_check(not loader.get_animation_config(profile_id).is_empty(), "animation profile %s exists" % profile_id)
	var invalid_data := loader.get_data()
	(invalid_data.get("run", {}) as Dictionary)["regular_enemy_cap"] = 0
	var invalid_path := "user://invalid_balance.json"
	var invalid_file := FileAccess.open(invalid_path, FileAccess.WRITE)
	_check(invalid_file != null, "invalid balance fixture opens")
	if invalid_file != null:
		invalid_file.store_string(JSON.stringify(invalid_data))
		invalid_file.close()
	var invalid_loader := LowpolyBalanceLoader.new()
	_check(not invalid_loader.load_balance(invalid_path), "invalid balance fails closed")
	_check(
		"run.regular_enemy_cap must be a positive integer" in invalid_loader.get_errors(),
		"invalid balance reports the failing field"
	)
	(invalid_data.get("run", {}) as Dictionary)["regular_enemy_cap"] = 220
	(invalid_data.get("weapons", {}) as Dictionary).erase("pulse_rifle")
	invalid_file = FileAccess.open(invalid_path, FileAccess.WRITE)
	if invalid_file != null:
		invalid_file.store_string(JSON.stringify(invalid_data))
		invalid_file.close()
	var missing_weapon_loader := LowpolyBalanceLoader.new()
	_check(not missing_weapon_loader.load_balance(invalid_path), "missing weapon config fails closed")
	_check(
		"weapons.pulse_rifle must be an object" in missing_weapon_loader.get_errors(),
		"missing weapon config reports the stable ID"
	)
	var invalid_animation_data := loader.get_data()
	((invalid_animation_data.get("animations", {}) as Dictionary).get("player", {}) as Dictionary).erase("fire")
	invalid_file = FileAccess.open(invalid_path, FileAccess.WRITE)
	if invalid_file != null:
		invalid_file.store_string(JSON.stringify(invalid_animation_data))
		invalid_file.close()
	var missing_animation_loader := LowpolyBalanceLoader.new()
	_check(not missing_animation_loader.load_balance(invalid_path), "missing animation mapping fails closed")
	_check(
		"animations.player.fire must be a non-empty string" in missing_animation_loader.get_errors(),
		"missing animation mapping reports the semantic state"
	)
	var invalid_yaw_data := loader.get_data()
	(invalid_yaw_data.get("player", {}) as Dictionary)["model_yaw_degrees"] = 999.0
	invalid_file = FileAccess.open(invalid_path, FileAccess.WRITE)
	if invalid_file != null:
		invalid_file.store_string(JSON.stringify(invalid_yaw_data))
		invalid_file.close()
	var invalid_yaw_loader := LowpolyBalanceLoader.new()
	_check(not invalid_yaw_loader.load_balance(invalid_path), "out-of-range model yaw fails closed")
	var yaw_error_reported := false
	for error: String in invalid_yaw_loader.get_errors():
		if error.begins_with("player.model_yaw_degrees"):
			yaw_error_reported = true
			break
	_check(yaw_error_reported, "invalid model yaw reports the failing field")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))


func _check_input_map() -> void:
	_check(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == 1920
		and int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == 1080,
		"design viewport is 1920x1080"
	)
	_check(
		int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)) == 1920
		and int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)) == 1080,
		"default window is 1920x1080"
	)
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"pause_run"]:
		_check(InputMap.has_action(action), "InputMap has %s" % action)
	var move_events := InputMap.action_get_events(&"move_left")
	_check(move_events.any(func(event: InputEvent) -> bool: return event is InputEventKey), "keyboard movement events exist")
	_check(move_events.any(func(event: InputEvent) -> bool: return event is InputEventJoypadMotion), "joy movement events exist")


func _check_main_scene() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		return
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	_check(main.get_node_or_null("FixedCamera") is Camera3D, "fixed camera exists")
	var fixed_camera := main.get_node("FixedCamera") as Camera3D
	_check(main.get_viewport().get_camera_3d() == fixed_camera, "fixed camera owns the gameplay viewport")
	_check(not fixed_camera.is_position_behind(Vector3.ZERO), "arena origin is in front of the fixed camera")
	var projected_origin := fixed_camera.unproject_position(Vector3.ZERO)
	var viewport_size := main.get_viewport().get_visible_rect().size
	_check(
		Rect2(Vector2.ZERO, viewport_size).has_point(projected_origin),
		"arena origin projects inside the gameplay viewport"
	)
	_check(main.get_node_or_null("World/VegetationMultiMesh") is MultiMeshInstance3D, "vegetation MultiMesh exists")
	_check(main.get_node_or_null("World/RockMultiMesh") is MultiMeshInstance3D, "rock MultiMesh exists")
	var vegetation := main.get_node("World/VegetationMultiMesh") as MultiMeshInstance3D
	var rocks := main.get_node("World/RockMultiMesh") as MultiMeshInstance3D
	_check(vegetation.multimesh != null and vegetation.multimesh.instance_count == 64, "64 vegetation instances created")
	_check(rocks.multimesh != null and rocks.multimesh.instance_count == 52, "52 rock instances created")
	var world_obstacles := get_nodes_in_group("lowpoly_world_obstacle")
	_check(world_obstacles.size() == 11, "perimeter structures create 11 collision proxies")
	for obstacle: Node in world_obstacles:
		var body := obstacle as StaticBody3D
		var shape_node := body.get_node_or_null("CollisionShape") as CollisionShape3D if body != null else null
		_check(
			body != null and body.collision_layer == 4 and body.collision_mask == 0,
			"world collision proxy uses the obstacle-only layer"
		)
		_check(
			shape_node != null and shape_node.shape is BoxShape3D,
			"world collision proxy has a generated box shape"
		)
	_check(main.get_node_or_null("RunDirector") is LowpolyRunDirector, "main installs RunDirector")
	var installed_director := main.get_node("RunDirector") as LowpolyRunDirector
	installed_director.start_run(47_013)
	_check(not main.get_node("LabUI/MenuLayer").visible, "running state hides the title dimmer")
	var installed_player := installed_director.get_player()
	var installed_player_shape := installed_player.get_node_or_null("CollisionShape") as CollisionShape3D
	_check(installed_player_shape != null and installed_player_shape.shape is CapsuleShape3D, "player has a capsule collider")
	_check(
		installed_player.collision_layer == 1 and installed_player.collision_mask == 6,
		"player collides with enemies and world obstacles"
	)
	var collision_probe := StaticBody3D.new()
	collision_probe.collision_layer = 4
	collision_probe.collision_mask = 0
	collision_probe.position = Vector3(4.0, 1.0, 0.0)
	var probe_shape := CollisionShape3D.new()
	var probe_box := BoxShape3D.new()
	probe_box.size = Vector3(2.0, 2.0, 2.0)
	probe_shape.shape = probe_box
	collision_probe.add_child(probe_shape)
	main.add_child(collision_probe)
	installed_player.global_position = Vector3(2.2, 0.0, 0.0)
	await physics_frame
	for index: int in range(8):
		installed_player.update_movement(1.0 / 60.0, Vector2.RIGHT)
	_check(
		installed_player.global_position.x < 2.7,
		"player movement is blocked by the world collision layer"
	)
	collision_probe.queue_free()
	installed_player.global_position = Vector3(18.0, 0.0, -12.0)
	main.call("_process", 1.0)
	_check(not fixed_camera.is_position_behind(installed_player.global_position), "camera follows a moved player")
	_check(
		Rect2(Vector2.ZERO, viewport_size).has_point(
			fixed_camera.unproject_position(installed_player.global_position)
		),
		"followed player projects inside the gameplay viewport"
	)
	var pause_event := InputEventKey.new()
	pause_event.physical_keycode = KEY_ESCAPE
	pause_event.pressed = true
	main.call("_unhandled_input", pause_event)
	_check(installed_director.get_state() == LowpolyRunDirector.RunState.PAUSED, "Escape pauses through the main input route")
	installed_director.return_to_menu()
	main.queue_free()
	await process_frame


func _check_gameplay_loop() -> void:
	var director := LowpolyRunDirector.new()
	root.add_child(director)
	await process_frame
	_check(director.get_state() == LowpolyRunDirector.RunState.MENU, "director starts in menu")
	director.start_run(47_013)
	_check(director.get_state() == LowpolyRunDirector.RunState.RUNNING, "start_run enters running")
	_check(director.get_player() != null and director.get_player().visible, "player model is active")
	var player := director.get_player()
	_check(player.get_animation_missing_states().is_empty(), "player GLB resolves every required animation")
	_check(player.get_animation_state() == &"idle", "player starts in idle animation state")
	_check(_clip_ends_with(player.get_animation_clip(), "Idle_Gun"), "player idle maps to the gun-ready clip")
	var weapon_attachment := _find_descendant_named(player, &"WeaponAttachment") as Node3D
	_check(
		weapon_attachment != null and weapon_attachment.top_level,
		"pulse rifle follows the astronaut hand without inheriting bone scale"
	)
	await process_frame
	var weapon_size := player.get_weapon_world_visual_size()
	var weapon_longest_side := maxf(weapon_size.x, maxf(weapon_size.y, weapon_size.z))
	var body_size := player.get_body_world_visual_size()
	var body_height := body_size.y
	_check(
		weapon_longest_side >= 0.7 and weapon_longest_side <= 1.0,
		"pulse rifle world visual length is human-scale (actual %.3f m)" % weapon_longest_side
	)
	_check(
		body_height > 0.0 and weapon_longest_side / body_height <= 0.65,
		"pulse rifle stays proportional to the astronaut (ratio %.3f)" % (
			weapon_longest_side / maxf(body_height, 0.001)
		)
	)
	player.update_movement(0.1, Vector2.RIGHT)
	_check(player.get_animation_state() == &"move", "player movement enters the run animation")
	_check(_clip_ends_with(player.get_animation_clip(), "Run_Gun"), "player movement uses the armed run clip")
	_check(
		player.get_visual_forward_direction().dot(player.velocity.normalized()) > 0.95,
		"player visual front faces the movement direction"
	)
	player.global_position = Vector3.ZERO
	player.update_movement(0.0, Vector2.ZERO)
	_check(player.get_animation_state() == &"idle", "player returns to idle when movement stops")
	_check_enemy_animation_profiles(director)
	var start_snapshot := director.get_debug_snapshot()
	_check(int(start_snapshot.get("seed", 0)) == 47_013, "fixed seed is applied")
	_check(int((start_snapshot.get("weapon_levels", {}) as Dictionary).get("pulse_rifle", 0)) == 1, "pulse rifle starts at level one")

	for index: int in range(22):
		director.simulate_step(0.1, Vector2(1.0, 1.0))
	var deterministic_enemy_count := int(director.get_debug_snapshot().get("regular_enemies", 0))
	var movement := Vector2(director.get_player().global_position.x, director.get_player().global_position.z)
	_check(movement.length() > 0.1, "normalized movement advances player")
	_check(movement.length() <= 8.5 * 2.2 + 0.1, "diagonal input is normalized")
	_check(deterministic_enemy_count > 0, "first stage spawns enemies")
	_check(int(director.get_debug_snapshot().get("player_projectiles", 0)) > 0, "pulse rifle auto-targets and fires")
	_check(player.get_animation_state() == &"fire", "automatic pulse rifle triggers the fire animation")
	_check(_clip_ends_with(player.get_animation_clip(), "Run_Gun_Shoot"), "pulse rifle uses the armed shooting clip")
	var collision_target := director.find_nearest_enemy(director.get_player().global_position, 80.0) as LowpolyEnemy
	_check(collision_target != null, "collision test finds an active enemy")
	if collision_target != null:
		var enemy_shape := collision_target.get_node_or_null("CollisionShape") as CollisionShape3D
		_check(enemy_shape != null and enemy_shape.shape is CapsuleShape3D and not enemy_shape.disabled, "active enemy has an enabled capsule collider")
		_check(
			collision_target.collision_layer == 2 and collision_target.collision_mask == 5,
			"enemy collides with player and world but not other enemies"
		)
		collision_target.take_damage(collision_target.health)
		_check(collision_target.dying and collision_target.visible, "dead enemy remains visible during its death animation")
		_check(enemy_shape.disabled, "dead enemy disables collision immediately")
		_check(collision_target.get_animation_state() == &"death", "dead enemy enters the death animation")
		_check(int(director.get_debug_snapshot().get("dying_enemies", 0)) == 1, "director tracks delayed death cleanup")
		director.simulate_step(0.3, Vector2.ZERO)
		_check(collision_target.visible, "death pose is held before pool release")
		director.simulate_step(0.5, Vector2.ZERO)
		_check(not collision_target.visible and not collision_target.dying, "death animation completes before pool release")
	director.get_player().global_position = Vector3(77.5, 0.0, 0.0)
	director.get_player().update_movement(1.0, Vector2.RIGHT)
	_check(director.get_player().global_position.x <= 78.0, "player movement respects the arena boundary")
	director.get_player().global_position = Vector3(movement.x, 0.0, movement.y)
	var weapon_system := director.get_node("WeaponSystem") as LowpolyWeaponSystem
	_check(weapon_system != null, "weapon system is installed")
	if weapon_system != null:
		var candidates := weapon_system.get_upgrade_candidates()
		var candidate_ids: Dictionary = {}
		for candidate: Dictionary in candidates:
			candidate_ids[String(candidate.get("id", ""))] = true
			_check(int(candidate.get("max_level", 0)) == 5, "upgrade candidates cap at level five")
		_check(candidate_ids.has("pulse_rifle"), "pulse rifle has upgrade data")
		_check(candidate_ids.has("orbital_drone"), "orbital drone has upgrade data")
		_check(candidate_ids.has("ion_pulse"), "ion pulse has upgrade data")
		_check(weapon_system.apply_upgrade(&"orbital_drone"), "orbital drone unlocks")
		_check(weapon_system.apply_upgrade(&"ion_pulse"), "ion pulse unlocks")
		for index: int in range(4):
			_check(weapon_system.apply_upgrade(&"pulse_rifle"), "pulse rifle advances toward overload")
		var capped_candidates := weapon_system.get_upgrade_candidates()
		_check(
			not capped_candidates.any(
				func(candidate: Dictionary) -> bool: return String(candidate.get("id", "")) == "pulse_rifle"
			),
			"max-level upgrades are excluded from candidates"
		)
		var maximum_effects := 0
		for index: int in range(7):
			director.simulate_step(0.1, Vector2.ZERO)
			maximum_effects = maxi(maximum_effects, int(director.get_debug_snapshot().get("effects", 0)))
		_check(maximum_effects > 0, "ion pulse creates its range effect")
	var damage_target := director.find_nearest_enemy(director.get_player().global_position, 80.0) as LowpolyEnemy
	_check(damage_target != null, "weapon test has a target")
	if damage_target != null:
		var health_before := damage_target.health
		director.damage_enemies_in_radius(damage_target.global_position, 1.0, 5.0)
		_check(damage_target.health < health_before, "weapon damage reaches enemies")

	director.toggle_pause()
	_check(director.get_state() == LowpolyRunDirector.RunState.PAUSED, "pause enters paused state")
	var paused_elapsed := float(director.get_debug_snapshot().get("elapsed", 0.0))
	var paused_animation_position := player.get_animation_position()
	director.simulate_step(2.0, Vector2.RIGHT)
	_check(is_equal_approx(float(director.get_debug_snapshot().get("elapsed", -1.0)), paused_elapsed), "pause freezes gameplay time")
	await create_timer(0.08).timeout
	_check(
		is_equal_approx(player.get_animation_position(), paused_animation_position),
		"pause freezes model animation playback"
	)
	director.toggle_pause()
	_check(director.get_state() == LowpolyRunDirector.RunState.RUNNING, "pause resumes run")
	await create_timer(0.08).timeout
	_check(
		not is_equal_approx(player.get_animation_position(), paused_animation_position),
		"resuming continues model animation playback"
	)

	director.add_experience_for_test(8)
	_check(director.get_state() == LowpolyRunDirector.RunState.LEVEL_UP, "experience opens level-up")
	var level_up_animation_position := player.get_animation_position()
	await create_timer(0.08).timeout
	_check(
		is_equal_approx(player.get_animation_position(), level_up_animation_position),
		"level-up freezes model animation playback"
	)
	var options := director.get_upgrade_options()
	_check(options.size() == 3, "level-up offers three choices")
	var option_ids: Dictionary = {}
	for option: Dictionary in options:
		option_ids[String(option.get("id", ""))] = true
	_check(option_ids.size() == options.size(), "level-up choices are unique")
	var chosen_id := StringName(options[0].get("id", "")) if not options.is_empty() else &""
	_check(chosen_id != &"" and director.choose_upgrade(chosen_id), "valid upgrade is applied")
	_check(director.get_state() == LowpolyRunDirector.RunState.RUNNING, "upgrade resumes run")
	var upgraded_levels := director.get_debug_snapshot().get("weapon_levels", {}) as Dictionary
	_check(int(upgraded_levels.get(chosen_id, 0)) >= 1, "selected upgrade level changes")

	director.force_test_time(180.0)
	_check(int(director.get_debug_snapshot().get("regular_enemies", 0)) >= 1, "first elite timeline event fires")
	director.force_test_time(600.0)
	var boss_snapshot := director.get_debug_snapshot()
	var regulars_before_patterns := int(boss_snapshot.get("regular_enemies", 0))
	_check(bool(boss_snapshot.get("boss_started", false)), "ten-minute event starts boss")
	_check(bool(boss_snapshot.get("boss_active", false)), "final boss is active")
	var boss := director.get("_boss") as LowpolyEnemy
	if boss != null:
		boss.global_position = director.get_player().global_position + Vector3(0.0, 0.0, 15.0)
	var maximum_projectiles := 0
	var maximum_regulars := regulars_before_patterns
	for index: int in range(24):
		director.simulate_step(0.5, Vector2.ZERO)
		maximum_projectiles = maxi(
			maximum_projectiles,
			int(director.get_debug_snapshot().get("enemy_projectiles", 0))
		)
		maximum_regulars = maxi(
			maximum_regulars,
			int(director.get_debug_snapshot().get("regular_enemies", 0))
		)
	_check(maximum_projectiles > 0, "boss emits projectile patterns")
	_check(maximum_projectiles <= 160, "enemy projectile population respects its cap")
	_check(maximum_regulars > regulars_before_patterns, "boss summons a minion wave")
	_check(director.defeat_boss_for_test(), "boss can be defeated")
	_check(director.get_state() == LowpolyRunDirector.RunState.VICTORY, "boss death wins run")
	if boss != null:
		var boss_shape := boss.get_node_or_null("CollisionShape") as CollisionShape3D
		_check(boss.dying and boss.visible, "Boss victory keeps the death animation visible")
		_check(boss_shape != null and boss_shape.disabled, "dead Boss cannot collide after victory")
		_check(boss.get_animation_state() == &"death", "Boss victory plays the death clip")

	director.restart_run()
	_check(director.get_state() == LowpolyRunDirector.RunState.RUNNING, "restart begins a clean run")
	var restart_snapshot := director.get_debug_snapshot()
	_check(is_zero_approx(float(restart_snapshot.get("elapsed", -1.0))), "restart resets time")
	_check(int(restart_snapshot.get("regular_enemies", -1)) == 0, "restart releases enemies")
	if collision_target != null and is_instance_valid(collision_target):
		var recycled_shape := collision_target.get_node("CollisionShape") as CollisionShape3D
		_check(recycled_shape.disabled, "pooled enemy disables its collider when released")
	for pool_key: String in ["enemy_projectiles", "player_projectiles", "pickups", "effects"]:
		_check(int(restart_snapshot.get(pool_key, -1)) == 0, "restart resets %s pool" % pool_key)
	director.force_test_time(600.0)
	_check(
		bool(director.get_debug_snapshot().get("boss_active", false)),
		"pooled boss can spawn on a restarted run"
	)
	_check(director.defeat_boss_for_test(), "restarted run can release the pooled boss")
	director.restart_run()
	for index: int in range(22):
		director.simulate_step(0.1, Vector2(1.0, 1.0))
	_check(
		int(director.get_debug_snapshot().get("regular_enemies", -1)) == deterministic_enemy_count,
		"fixed seed reproduces the opening summary"
	)
	director.restart_run()
	director.simulate_step(240.0, Vector2.ZERO)
	_check(
		int(director.get_debug_snapshot().get("regular_enemies", 0)) <= 220,
		"regular enemy population respects its cap"
	)
	director.get_player().take_damage(director.get_player().health, true)
	_check(director.get_state() == LowpolyRunDirector.RunState.DEFEAT, "player death ends the run in defeat")
	director.return_to_menu()
	_check(director.get_state() == LowpolyRunDirector.RunState.MENU, "return_to_menu closes run")
	director.queue_free()
	await process_frame


func _check_enemy_animation_profiles(director: LowpolyRunDirector) -> void:
	var loader := LowpolyBalanceLoader.new()
	_check(loader.load_balance(), "animation profile fixture loads")
	if not loader.is_loaded():
		return
	for enemy_id: StringName in [
		&"enemy_small", &"enemy_flying", &"enemy_large", &"enemy_fox_mech", &"final_boss",
	]:
		var config := loader.get_enemy_config(enemy_id)
		_check(
			is_equal_approx(float(config.get("model_yaw_degrees", 0.0)), 180.0),
			"%s declares its imported-model forward correction" % enemy_id
		)
		var profile_id := StringName(config.get("animation_profile", String(enemy_id)))
		var profile := loader.get_animation_config(profile_id)
		var enemy := LowpolyEnemy.new()
		root.add_child(enemy)
		enemy.activate_from_pool({
			"enemy_id": enemy_id,
			"config": config,
			"animation_config": profile,
			"player": director.get_player(),
			"boss": enemy_id == &"final_boss",
			"position": Vector3(18.0, 0.0, float(enemy.get_instance_id() % 7)),
		})
		_check(enemy.get_animation_missing_states().is_empty(), "%s resolves every required GLB animation" % enemy_id)
		_check(_clip_ends_with(enemy.get_animation_clip(), String(profile.get("idle", ""))), "%s maps idle animation" % enemy_id)
		enemy.update_enemy(0.1, [])
		_check(_clip_ends_with(enemy.get_animation_clip(), String(profile.get("move", ""))), "%s maps movement animation" % enemy_id)
		_check(
			not enemy.velocity.is_zero_approx()
			and enemy.get_visual_forward_direction().dot(enemy.velocity.normalized()) > 0.95,
			"%s visual front faces its movement direction" % enemy_id
		)
		enemy.call("_play_action", &"attack")
		_check(_clip_ends_with(enemy.get_animation_clip(), String(profile.get("attack", ""))), "%s maps attack animation" % enemy_id)
		if enemy_id == &"final_boss":
			for boss_state: StringName in [&"attack_aimed", &"attack_radial", &"summon"]:
				enemy.call("_play_action", boss_state)
				_check(
					_clip_ends_with(enemy.get_animation_clip(), String(profile.get(boss_state, ""))),
					"Boss maps %s animation" % boss_state
				)
		enemy.take_damage(1.0)
		_check(_clip_ends_with(enemy.get_animation_clip(), String(profile.get("hit", ""))), "%s maps hit reaction" % enemy_id)
		enemy.take_damage(enemy.health)
		_check(_clip_ends_with(enemy.get_animation_clip(), String(profile.get("death", ""))), "%s maps death animation" % enemy_id)
		enemy.free()


func _check_online_multiplayer() -> void:
	LowpolyFakeTransport.reset_bus_for_tests()
	var sessions: Array[LowpolyOnlineSession] = []
	var transports: Array[LowpolyFakeTransport] = []
	for index: int in range(4):
		var session := LowpolyOnlineSession.new()
		session.name = "FakeSession%d" % index
		root.add_child(session)
		var transport := LowpolyFakeTransport.new()
		transport.forced_user_id = "p%d" % (index + 1)
		_check(session.initialize_online("玩家%d" % (index + 1), transport), "fake client %d initializes" % (index + 1))
		_check(session.get_state() == LowpolyOnlineSession.State.IDLE, "fake client %d authenticates" % (index + 1))
		sessions.append(session)
		transports.append(transport)

	var host := sessions[0]
	_check(host.create_room(), "host creates a six-code lobby")
	var room_code := String(host.get_room_snapshot().get("room_code", ""))
	_check(room_code.length() == 6 and room_code.is_valid_int(), "room code is six digits")
	for index: int in range(1, sessions.size()):
		_check(sessions[index].join_room(room_code), "client %d requests lobby join" % (index + 1))
		_check(
			sessions[index].get_state() == LowpolyOnlineSession.State.LOBBY,
			"client %d joins lobby" % (index + 1)
		)
		_check(
			(host.get_room_snapshot().get("members", []) as Array).size() == index + 1,
			"lobby supports %d players" % (index + 1)
		)
	for session: LowpolyOnlineSession in sessions:
		_check(session.set_ready(true), "lobby member can become ready")
	_check(host.can_start_match(), "host can start only after every member is ready")
	_check(host.start_match(880041), "host locks lobby and starts match")
	for session: LowpolyOnlineSession in sessions:
		_check(session.get_state() == LowpolyOnlineSession.State.IN_MATCH, "all fake clients enter match")
		_check(int(session.get_match_data().get("difficulty_players", 0)) == 4, "start roster locks four-player difficulty")
	_check(bool(host.get_room_snapshot().get("locked", false)), "started lobby is locked")

	var late_session := LowpolyOnlineSession.new()
	root.add_child(late_session)
	var late_transport := LowpolyFakeTransport.new()
	late_transport.forced_user_id = "late"
	late_session.initialize_online("迟到玩家", late_transport)
	late_session.join_room(room_code)
	_check(late_session.get_state() == LowpolyOnlineSession.State.ERROR, "late join is rejected after start")
	late_session.queue_free()

	var received_kinds: Array[StringName] = []
	sessions[1].network_message.connect(
		func(_sender: String, kind: StringName, _payload: Dictionary) -> void:
			received_kinds.append(kind)
	)
	transports[0].duplicate_every_nth = 1
	host.send_message("p2", &"idempotent_test", {"value": 7})
	_check(received_kinds.count(&"idempotent_test") == 1, "reliable duplicate event is idempotent")
	transports[0].duplicate_every_nth = 0
	var before_drop := received_kinds.size()
	transports[0].drop_every_nth = 1
	host.send_message("p2", &"dropped_test", {"value": 1}, false)
	_check(received_kinds.size() == before_drop, "fake transport injects packet loss")
	transports[0].drop_every_nth = 0
	transports[0].latency_seconds = 0.05
	host.send_message("p2", &"latency_test", {"value": 2})
	_check(not received_kinds.has(&"latency_test"), "fake transport holds packets during injected latency")
	transports[1].advance_fake_time(0.06)
	_check(received_kinds.has(&"latency_test"), "fake transport releases delayed packets deterministically")
	transports[0].latency_seconds = 0.0
	transports[0].reorder_next_pair = true
	host.send_message("p2", &"reorder_first", {"sequence": 1}, false)
	host.send_message("p2", &"reorder_second", {"sequence": 2}, false)
	transports[1].advance_fake_time(0.0)
	_check(
		received_kinds.find(&"reorder_second") < received_kinds.find(&"reorder_first"),
		"fake transport injects packet reordering"
	)

	transports[2].simulate_connection_loss()
	_check(
		(host.get_debug_snapshot().get("disconnecting", {}) as Dictionary).has("p3"),
		"host starts a reconnect grace window"
	)
	transports[2].simulate_reconnect()
	_check(
		not (host.get_debug_snapshot().get("disconnecting", {}) as Dictionary).has("p3"),
		"reconnect restores the existing slot"
	)

	var takeover_checkpoint := {"tick": 240, "seed": 880041, "players": [{"slot": 1}]}
	sessions[1].set_cached_checkpoint(takeover_checkpoint)
	var takeover_seen: Array[Dictionary] = [{}]
	sessions[1].host_takeover_requested.connect(
		func(checkpoint: Dictionary, epoch: int) -> void:
			takeover_seen[0] = checkpoint.duplicate(true)
			sessions[1].complete_host_migration(checkpoint)
			_check(epoch == 2, "host migration increments authority epoch")
	)
	transports[0].leave_room()
	await process_frame
	_check(sessions[1].get_role() == LowpolyOnlineSession.NetworkRole.HOST, "EOS lobby owner becomes new host")
	_check(sessions[1].get_state() == LowpolyOnlineSession.State.IN_MATCH, "new host resumes after migration")
	_check(int(takeover_seen[0].get("tick", -1)) == 240, "new host receives the cached checkpoint")
	_check(sessions[2].get_authority_epoch() > 1, "remaining clients advance to the migrated authority epoch")
	var old_epoch_seen: Array[bool] = [false]
	sessions[2].network_message.connect(
		func(_sender: String, kind: StringName, _payload: Dictionary) -> void:
			if kind == &"old_epoch_probe":
				old_epoch_seen[0] = true
	)
	transports[1].send_packet("p3", LowpolyTransport.Channel.RELIABLE, {
		"protocol": LowpolyOnlineSession.PROTOCOL_VERSION,
		"epoch": 1,
		"kind": "old_epoch_probe",
		"sequence": 999,
		"reliable": true,
		"payload": {},
	})
	_check(not old_epoch_seen[0], "remaining clients reject packets from the old authority epoch")
	_check(sessions[0].join_room(room_code), "departed host can request its locked roster slot")
	_check(
		sessions[0].get_state() == LowpolyOnlineSession.State.IN_MATCH
		and sessions[0].get_role() == LowpolyOnlineSession.NetworkRole.CLIENT,
		"departed host returns within the grace window as an ordinary client"
	)
	_check(
		sessions[0].get_authority_epoch() == sessions[1].get_authority_epoch(),
		"returning former host adopts the migrated authority epoch"
	)

	var expired_users: Array[String] = []
	sessions[1].participant_grace_expired.connect(func(user_id: String) -> void: expired_users.append(user_id))
	transports[3].simulate_connection_loss()
	_check(sessions[1].force_reconnect_timeout_for_test("p4"), "reconnect timeout seam targets a disconnected slot")
	sessions[1].call("_process", 0.0)
	_check(expired_users.has("p4"), "sixty-second grace expiry removes only the disconnected slot")
	transports[1].leave_room()
	_check(sessions[2].force_host_migration_timeout_for_test(), "migration timeout seam detects a missing takeover")
	sessions[2].call("_process", 0.0)
	_check(
		sessions[2].get_state() == LowpolyOnlineSession.State.ERROR,
		"host migration ends as an interruption after fifteen seconds"
	)

	await _check_network_authority_core()

	for session: LowpolyOnlineSession in sessions:
		session.queue_free()
	LowpolyFakeTransport.reset_bus_for_tests()
	await process_frame


func _check_network_authority_core() -> void:
	var roster: Array[Dictionary] = [
		{"slot": 0, "user_id": "p1", "display_name": "一号", "connected": true},
		{"slot": 1, "user_id": "p2", "display_name": "二号", "connected": true},
		{"slot": 2, "user_id": "p3", "display_name": "三号", "connected": true},
	]
	var match_data := {
		"roster": roster,
		"seed": 99117,
		"difficulty_players": 3,
	}
	var director := LowpolyRunDirector.new()
	root.add_child(director)
	await process_frame
	_check(director.start_network_run(match_data, "p1", true), "host creates three-player authority state")
	_check(director.get_player_roster_snapshot().size() == 3, "authority creates stable player slots")
	director.add_experience_for_test(8)
	_check(director.get_state() == LowpolyRunDirector.RunState.LEVEL_UP, "shared experience pauses the online run")
	var pending: Array = director.get_debug_snapshot().get("pending_upgrade_slots", [])
	_check(pending == [0, 1, 2], "each connected player receives an independent upgrade choice")
	var option_zero := director.get_network_upgrade_options(0)
	var option_one := director.get_network_upgrade_options(1)
	_check(option_zero.size() == 3 and option_one.size() == 3, "online upgrade offers three legal candidates")
	director.set_network_player_connected("p3", false)
	_check(
		director.choose_network_upgrade(0, StringName(option_zero[0].get("id", ""))),
		"host validates its own upgrade candidate"
	)
	_check(
		director.choose_network_upgrade(1, StringName(option_one[0].get("id", ""))),
		"host validates a remote upgrade candidate"
	)
	_check(director.get_state() == LowpolyRunDirector.RunState.LEVEL_UP, "upgrade waits for a disconnected chooser")
	director.remove_network_player("p3")
	_check(director.get_state() == LowpolyRunDirector.RunState.RUNNING, "timeout removal releases the global upgrade pause")
	var player_builds := director.get_player_roster_snapshot()
	_check(
		(player_builds[0].get("weapon_levels", {}) as Dictionary) != (player_builds[1].get("weapon_levels", {}) as Dictionary)
		or String(option_zero[0].get("id", "")) == String(option_one[0].get("id", "")),
		"players retain independent weapon systems"
	)

	director.start_network_run(match_data, "p1", true)
	director.get_player_for_slot(0).take_damage(9999.0, true)
	director.get_player_for_slot(1).take_damage(9999.0, true)
	director.set_network_player_connected("p3", false)
	_check(director.get_state() == LowpolyRunDirector.RunState.RUNNING, "disconnected living slot prevents premature team defeat")
	director.remove_network_player("p3")
	_check(director.get_state() == LowpolyRunDirector.RunState.DEFEAT, "all remaining players dead ends the run")

	director.start_network_run(match_data, "p1", true)
	director.simulate_network_step(0.25, {0: Vector2.RIGHT, 1: Vector2.LEFT, 2: Vector2.ZERO})
	var checkpoint := director.make_authority_checkpoint()
	_check(int(checkpoint.get("tick", 0)) > 0, "host checkpoint records authority tick")
	var replica := LowpolyRunDirector.new()
	root.add_child(replica)
	await process_frame
	_check(replica.start_network_run(match_data, "p2", false), "client creates matching roster view")
	_check(replica.restore_authority_checkpoint(checkpoint), "new host restores a full checkpoint")
	_check(
		int(replica.get_debug_snapshot().get("authority_tick", -1)) == int(checkpoint.get("tick", -2)),
		"checkpoint preserves authority tick continuity"
	)
	var current_snapshot := director.make_network_snapshot(Vector3.ZERO, 100.0)
	current_snapshot["tick"] = 500
	var client_view := LowpolyRunDirector.new()
	root.add_child(client_view)
	await process_frame
	client_view.start_network_run(match_data, "p2", false)
	_check(client_view.apply_network_snapshot(current_snapshot), "client accepts a current authority snapshot")
	var stale_snapshot := current_snapshot.duplicate(true)
	stale_snapshot["tick"] = 499
	_check(not client_view.apply_network_snapshot(stale_snapshot), "client rejects an out-of-order world snapshot")
	var client_session := LowpolyOnlineSession.new()
	root.add_child(client_session)
	var prediction_bridge := LowpolyNetworkRunBridge.new()
	root.add_child(prediction_bridge)
	prediction_bridge.setup(client_session, client_view)
	var authority_position := Vector3.ZERO
	for value: Variant in current_snapshot.get("players", []):
		if value is Dictionary and int((value as Dictionary).get("slot", -1)) == 1:
			var values: Array = (value as Dictionary).get("position", [])
			if values.size() == 3:
				authority_position = Vector3(float(values[0]), float(values[1]), float(values[2]))
	prediction_bridge.queue_predicted_input_for_test(12, Vector2.LEFT, 0.05)
	_check(
		(prediction_bridge.get_debug_snapshot().get("pending_local_inputs", []) as Array).size() == 1,
		"prediction fixture stores one unacknowledged input"
	)
	var correction_snapshot := current_snapshot.duplicate(true)
	correction_snapshot["tick"] = 501
	correction_snapshot["ack_input_sequence"] = 11
	prediction_bridge.call("_apply_client_snapshot", correction_snapshot)
	_check(
		client_view.get_player_for_slot(1).global_position.x < authority_position.x - 0.01,
		"client rollback replays only unacknowledged predicted input (authority %.3f, replayed %.3f, state %d, combat %s, pending %d)" % [
			authority_position.x,
			client_view.get_player_for_slot(1).global_position.x,
			int(client_view.get_state()),
			str(client_view.get_player_for_slot(1).is_combat_available()),
			(prediction_bridge.get_debug_snapshot().get("pending_local_inputs", []) as Array).size(),
		]
	)
	correction_snapshot["tick"] = 502
	correction_snapshot["ack_input_sequence"] = 12
	prediction_bridge.call("_apply_client_snapshot", correction_snapshot)
	_check(
		(prediction_bridge.get_debug_snapshot().get("pending_local_inputs", []) as Array).is_empty(),
		"authority acknowledgement retires predicted input history"
	)
	prediction_bridge.queue_free()
	client_session.queue_free()

	director.start_network_run(match_data, "p1", true)
	director.force_test_time(600.0)
	_check(bool(director.get_debug_snapshot().get("boss_active", false)), "online host alone starts the ten-minute boss")
	var boss_checkpoint := director.make_authority_checkpoint()
	var checkpoint_boss: Dictionary = {}
	for value: Variant in boss_checkpoint.get("enemies", []):
		if value is Dictionary and bool((value as Dictionary).get("boss", false)):
			checkpoint_boss = value as Dictionary
	_check(
		checkpoint_boss.has("pattern_index") and checkpoint_boss.has("attack_left"),
		"host checkpoint preserves Boss attack pattern state"
	)
	_check(director.defeat_boss_for_test(), "online host alone adjudicates Boss damage")
	_check(director.get_state() == LowpolyRunDirector.RunState.VICTORY, "Boss death wins for the team")

	var validation_session := LowpolyOnlineSession.new()
	root.add_child(validation_session)
	var validation_transport := LowpolyFakeTransport.new()
	validation_transport.forced_user_id = "validator"
	validation_session.initialize_online("验证器", validation_transport)
	var bridge := LowpolyNetworkRunBridge.new()
	root.add_child(bridge)
	bridge.setup(validation_session, replica)
	bridge.call("_accept_input", "p2", {"slot": 0, "sequence": 1, "vector": [1.0, 0.0]})
	_check(
		not (bridge.get_debug_snapshot().get("latest_inputs", {}) as Dictionary).has(1),
		"host rejects input sent for another slot"
	)
	bridge.call("_accept_input", "p2", {"slot": 1, "sequence": 2, "vector": [0.5, 0.0]})
	_check(
		(bridge.get_debug_snapshot().get("latest_inputs", {}) as Dictionary).has(1),
		"host accepts normalized input from the owning PUID"
	)
	bridge.call("_accept_input", "p2", {"slot": 1, "sequence": 2, "vector": [-1.0, 0.0]})
	_check(
		int((bridge.get_debug_snapshot().get("last_input_sequences", {}) as Dictionary).get("p2", 0)) == 2,
		"host rejects duplicate input sequence numbers"
	)
	bridge.call("_accept_input", "attacker", {"slot": 1, "sequence": 99, "vector": [1.0, 0.0]})
	_check(
		not (bridge.get_debug_snapshot().get("last_input_sequences", {}) as Dictionary).has("attacker"),
		"host rejects input from a PUID outside the locked roster"
	)
	bridge.call("_accept_input", "p2", {"slot": 1, "sequence": 3, "vector": [2.0, 0.0]})
	_check(
		int((bridge.get_debug_snapshot().get("last_input_sequences", {}) as Dictionary).get("p2", 0)) == 2,
		"host rejects non-normalized input vectors"
	)
	bridge.call("_accept_input", "p2", {
		"slot": 1,
		"sequence": 3,
		"vector": [0.0, 0.0],
		"padding": "x".repeat(300),
	})
	_check(
		int((bridge.get_debug_snapshot().get("last_input_sequences", {}) as Dictionary).get("p2", 0)) == 2,
		"host rejects oversized input payloads"
	)
	for sequence: int in range(3, 35):
		bridge.call("_accept_input", "p2", {"slot": 1, "sequence": sequence, "vector": [0.0, 0.0]})
	_check(
		int((bridge.get_debug_snapshot().get("last_input_sequences", {}) as Dictionary).get("p2", 0)) == 32,
		"host rate-limits excess input packets"
	)
	bridge.call("_handle_host_message", "p2", &"damage", {"amount": 9999})
	_check(replica.get_player_for_slot(0).health > 0.0, "client cannot submit damage or authority events")

	bridge.queue_free()
	validation_session.queue_free()
	client_view.queue_free()
	replica.queue_free()
	director.queue_free()
	await process_frame


func _clip_ends_with(clip: StringName, expected_suffix: String) -> bool:
	return not expected_suffix.is_empty() and String(clip).to_lower().ends_with(expected_suffix.to_lower())


func _find_descendant_named(node: Node, target_name: StringName) -> Node:
	if node.name == target_name:
		return node
	for child: Node in node.get_children():
		var found := _find_descendant_named(child, target_name)
		if found != null:
			return found
	return null
