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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))


func _check_input_map() -> void:
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
	var movement_blocked := false
	for index: int in range(8):
		installed_player.update_movement(1.0 / 60.0, Vector2.RIGHT)
		movement_blocked = movement_blocked or installed_player.get_slide_collision_count() > 0
	_check(
		movement_blocked and installed_player.global_position.x < 2.7,
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
	var weapon_attachment := _find_descendant_named(player, &"WeaponAttachment") as BoneAttachment3D
	_check(weapon_attachment != null, "pulse rifle is attached to the astronaut hand bone")
	player.update_movement(0.1, Vector2.RIGHT)
	_check(player.get_animation_state() == &"move", "player movement enters the run animation")
	_check(_clip_ends_with(player.get_animation_clip(), "Run_Gun"), "player movement uses the armed run clip")
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
