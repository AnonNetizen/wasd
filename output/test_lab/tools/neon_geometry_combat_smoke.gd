extends SceneTree

const SCENE_PATH := "res://scenes/neon_geometry_combat_test.tscn"
const INDEX_SCENE_PATH := "res://scenes/test_lab_index.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	await _check_index_entry()
	var packed_scene := load(SCENE_PATH) as PackedScene
	_check(packed_scene != null, "Neon geometry combat scene loads.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _index in range(4):
		await process_frame

	_check_debug_api(scene)
	scene.call("debug_reset_scene")
	var initial_state := _state(scene)
	var initial_child_count := scene.get_child_count()
	_check(initial_child_count == 0, "Experiment keeps all actors, projectiles, and VFX in fixed data pools.")
	_check(int(initial_state.get("actor_count", 0)) == 3, "Scene owns one player and two enemies.")
	_check(int(initial_state.get("active_enemy_count", 0)) == 2, "Both enemy archetypes start active.")
	_check(bool(initial_state.get("player_alive", false)), "Player starts alive.")
	_check(int(initial_state.get("player_hp", 0)) == 5, "Player starts with five health.")
	_check(not bool(initial_state.get("upgrade_active", true)), "Refraction upgrade starts inactive.")
	_check(int(initial_state.get("current_volley_size", 0)) == 1, "Base player volley is one projectile.")
	_check(int(initial_state.get("player_pool_size", 0)) == 48, "Player projectile pool is fixed at 48.")
	_check(int(initial_state.get("enemy_pool_size", 0)) == 48, "Enemy projectile pool is fixed at 48.")
	_check(int(initial_state.get("vfx_pool_size", 0)) == 64, "VFX pool is fixed at 64.")
	var initial_player_position: Vector2 = initial_state.get("player_position", Vector2.ZERO) as Vector2
	var initial_enemy_positions: Array = initial_state.get("enemy_positions", []) as Array
	var initial_motion_phases: Array = initial_state.get("actor_motion_phases", []) as Array
	var initial_background_seed := int(initial_state.get("background_seed", 0))
	_check(InputMap.has_action("lab_neon_fire"), "Playable fire action is registered.")
	Input.action_press("lab_neon_fire")
	await process_frame
	Input.action_release("lab_neon_fire")
	var fired_state := _state(scene)
	_check(int(fired_state.get("player_projectile_count", 0)) == 1, "Holding the fire action emits the base single projectile.")
	scene.call("debug_reset_scene")
	scene.call("debug_apply_hit", 0)
	var hit_state := _state(scene)
	_check(int(hit_state.get("player_hp", 0)) == 4, "A live hit removes exactly one player health.")
	_check(float(hit_state.get("player_hit_flash_remaining", 0.0)) > 0.0, "A live hit starts the player hit flash.")
	_check(float(hit_state.get("screen_kick_remaining", 0.0)) > 0.0, "A live hit starts world-layer impact feedback.")
	_check(float(hit_state.get("screen_flash_strength", 0.0)) > 0.0, "A live hit starts a restrained screen flash.")
	_check(float(hit_state.get("hit_stop_remaining", 0.0)) > 0.0, "A live hit starts a short simulation hit-stop.")
	_check(int(hit_state.get("active_vfx_kind_count", 0)) >= 5, "A live hit layers pulse, debris, spark, lens, and burst VFX.")

	scene.call("debug_activate_upgrade")
	var upgraded_state := _state(scene)
	_check(bool(upgraded_state.get("upgrade_active", false)), "Refraction upgrade activates.")
	_check(bool(upgraded_state.get("player_modules_expanded", false)), "Upgrade expands player side modules.")
	_check(int(upgraded_state.get("current_volley_size", 0)) == 3, "Upgrade changes the player volley to three projectiles.")
	_check(float(upgraded_state.get("upgrade_wave_remaining", 0.0)) > 0.0, "Upgrade starts the refraction deployment wave.")

	scene.call("debug_prepare_capture")
	for _index in range(4):
		await process_frame
	var capture_state := _state(scene)
	_check(int(capture_state.get("player_projectile_count", 0)) >= 6, "Capture state contains two depth-separated tri-volley patterns.")
	_check(int(capture_state.get("enemy_wedge_count", 0)) >= 3, "Capture state contains hunter wedge projectiles.")
	_check(int(capture_state.get("enemy_ring_count", 0)) >= 5, "Capture state contains tri-axis ring projectiles.")
	_check(bool(capture_state.get("projectile_teams_valid", false)), "All three projectile kinds stay in their correct team pools.")
	_check(int(capture_state.get("active_vfx_count", 0)) > 0, "Capture state contains active geometric VFX.")
	_check(int(capture_state.get("active_vfx_kind_count", 0)) >= 5, "Capture state exercises at least five layered VFX families.")
	_check(int(capture_state.get("player_pool_size", 0)) == 48, "Player pool capacity stays fixed during capture setup.")
	_check(int(capture_state.get("enemy_pool_size", 0)) == 48, "Enemy pool capacity stays fixed during capture setup.")
	_check(scene.get_child_count() == initial_child_count, "Capture setup does not grow the scene tree.")

	scene.call("debug_reset_scene")
	scene.call("debug_activate_upgrade")
	scene.call("debug_force_defeat", 0)
	var defeated_player_state := _state(scene)
	_check(not bool(defeated_player_state.get("player_alive", true)), "Forced player defeat enters the dead state.")
	_check(float(defeated_player_state.get("player_respawn_remaining", 0.0)) > 0.0, "Player defeat starts a respawn timer.")
	await create_timer(1.32).timeout
	var respawned_player_state := _state(scene)
	_check(bool(respawned_player_state.get("player_alive", false)), "Player automatically respawns.")
	_check(float(respawned_player_state.get("player_invulnerability_remaining", 0.0)) > 0.0, "Respawn grants a visible invulnerability window.")
	_check(bool(respawned_player_state.get("upgrade_active", false)), "Player respawn preserves the refraction upgrade.")

	scene.call("debug_force_defeat", 1)
	var defeated_enemy_state := _state(scene)
	_check(int(defeated_enemy_state.get("active_enemy_count", 0)) == 1, "Forced enemy defeat removes exactly one active enemy.")
	await create_timer(1.08).timeout
	var respawned_enemy_state := _state(scene)
	_check(int(respawned_enemy_state.get("active_enemy_count", 0)) == 2, "Enemy automatically respawns.")

	scene.call("debug_reset_scene")
	var reset_state := _state(scene)
	_check(bool(reset_state.get("player_alive", false)), "Reset restores the player.")
	_check(int(reset_state.get("player_hp", 0)) == 5, "Reset restores player health.")
	_check(not bool(reset_state.get("upgrade_active", true)), "Reset clears the refraction upgrade.")
	_check(int(reset_state.get("player_projectile_count", -1)) == 0, "Reset clears player projectiles.")
	_check(int(reset_state.get("enemy_wedge_count", -1)) == 0, "Reset clears wedge projectiles.")
	_check(int(reset_state.get("enemy_ring_count", -1)) == 0, "Reset clears ring projectiles.")
	_check(int(reset_state.get("active_vfx_count", -1)) == 0, "Reset clears VFX slots.")
	_check(is_zero_approx(float(reset_state.get("screen_kick_remaining", -1.0))), "Reset clears world-layer impact feedback.")
	_check(is_zero_approx(float(reset_state.get("upgrade_wave_remaining", -1.0))), "Reset clears the refraction deployment wave.")
	_check(is_zero_approx(float(reset_state.get("hit_stop_remaining", -1.0))), "Reset clears simulation hit-stop.")
	_check(reset_state.get("player_position", Vector2.ZERO) == initial_player_position, "Reset restores the fixed player position.")
	_check(reset_state.get("enemy_positions", []) == initial_enemy_positions, "Reset restores both fixed enemy positions.")
	_check(reset_state.get("actor_motion_phases", []) == initial_motion_phases, "Reset restores deterministic actor motion phases.")
	_check(int(reset_state.get("background_seed", 0)) == initial_background_seed, "Reset preserves the fixed background seed.")
	_check(is_zero_approx(float(reset_state.get("simulation_elapsed", -1.0))), "Reset restores simulation time to zero.")
	_check(scene.get_child_count() == initial_child_count, "Reset preserves the fixed scene-tree size.")

	_finish()


func _check_index_entry() -> void:
	var packed_index := load(INDEX_SCENE_PATH) as PackedScene
	_check(packed_index != null, "Test Lab index scene loads.")
	if packed_index == null:
		return
	var index_scene := packed_index.instantiate()
	root.add_child(index_scene)
	for _index in range(3):
		await process_frame
	var button := index_scene.get_node_or_null(
		"Panel/Margin/Rows/ButtonScroll/ButtonRows/NeonGeometryCombatButton"
	) as Button
	_check(button != null, "Test Lab index exposes the neon geometry combat entry.")
	if button != null:
		_check(button.text == "Neon Geometry Combat Test", "Test Lab entry uses the expected label.")
		_check(button.get_index() == 0, "Neon geometry combat is pinned to the top of the Test Lab index.")
	index_scene.queue_free()
	await process_frame


func _check_debug_api(scene: Node) -> void:
	for method_name in [
		"debug_reset_scene",
		"debug_activate_upgrade",
		"debug_prepare_capture",
		"debug_apply_hit",
		"debug_force_defeat",
		"debug_state",
	]:
		_check(scene.has_method(method_name), "Scene exposes %s()." % method_name)


func _state(scene: Node) -> Dictionary:
	var value: Variant = scene.call("debug_state")
	_check(value is Dictionary, "debug_state() returns a Dictionary.")
	if value is Dictionary:
		return value as Dictionary
	return {}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	_failures.append(message)
	push_error("[FAIL] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("NEON_GEOMETRY_COMBAT_SMOKE_OK")
		quit(0)
		return
	push_error("Neon geometry combat smoke failed with %s failure(s)." % _failures.size())
	quit(1)
