extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const ENEMY_AI_ACTIONS := preload("res://scripts/contracts/enemy_ai_actions.gd")
const ENEMY_DEFEAT_CAUSES := preload(
	"res://scripts/contracts/enemy_defeat_causes.gd"
)
const ENEMY_SCENE := preload("res://scenes/gameplay/actors/enemies/enemy_chaser.tscn")
const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const PLAYER_SCENE := preload("res://scenes/gameplay/actors/characters/character_default.tscn")
const WORLD_EVENT_DEFENSE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_defense.tscn"
)
const DAMAGE_TARGET_GROUPS := preload(
	"res://scripts/contracts/damage_target_groups.gd"
)
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SETTINGS_KEYS := preload("res://scripts/contracts/settings_keys.gd")
const SKILL_RESOURCES := preload("res://scripts/contracts/skill_resources.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const RETIRED_AMMO_POOL_ID: String = "ammo_magazine"
const RETIRED_AMMO_RNG_STREAM: String = "ammo"
const RETIRED_RELOAD_ACTION: String = "reload"
const AIM_FRAMES: int = 4
const BOOT_FRAMES: int = 8
const CAMERA_LOOK_SETTLE_FRAMES: int = 120
const UI_TRANSITION_FRAMES: int = 120
const INVULNERABILITY_FRAMES: int = 50
const REWARD_CHOICE_FRAMES: int = 24
const MOVE_FRAMES: int = 8
const PICKUP_FEEDBACK_FRAMES: int = 40
const SPAWN_FRAMES: int = 10
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"
const BULLET_PLAYER_BODY_COLOR: Color = Color("dceaf2")
const BULLET_PLAYER_RIM_COLOR: Color = Color("f6fbff")
const BULLET_ENEMY_BODY_COLOR: Color = Color("e62935")
const BULLET_ENEMY_RIM_COLOR: Color = Color("ff5963")
const BULLET_GEOMETRY_SIGNATURE: String = (
	"circle:r1.0:four_edge_nodes:catmull_rom:"
	+ "no_highlight:no_shader:no_glow:no_trail"
)

var _failures: Array[String] = []
var _original_screen_shake: bool = true
var _ranged_commit_times: Array[float] = []
var _ranged_windup_contexts: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	RNG.set_run_seed(4242)
	_original_screen_shake = bool(Settings.get_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true))
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true)

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
	_expect(PoolManager.has_pool(POOL_IDS.ENEMY_CHASER), "chaser enemy pool should be registered")
	_expect(PoolManager.has_pool(POOL_IDS.ENEMY_SWARM), "swarm enemy pool should be registered")
	_expect(PoolManager.has_pool(POOL_IDS.ENEMY_STALKER), "stalker enemy pool should be registered")
	_expect(PoolManager.has_pool(POOL_IDS.ENEMY_BULWARK), "bulwark enemy pool should be registered")
	_expect(PoolManager.has_pool(POOL_IDS.ENEMY_SPITTER), "spitter enemy pool should be registered")
	_expect(PoolManager.has_pool(POOL_IDS.HAZARD_SPIKE), "hazard pool should be registered")
	_expect(InputService.action_resource(ACTIONS.MOVE) != null, "InputService should expose the Vector2 move action")
	_expect(InputService.action_resource(ACTIONS.AIM) != null, "InputService should expose the Vector2 aim action")
	_expect(InputService.action_resource(ACTIONS.SHOW_STATS_PANEL) != null, "InputService should expose show_stats_panel")
	_expect_gold_progression_curve_and_transactions()
	_expect_reward_choice_controller_contract()

	var player: Node2D = _find_node_by_name(run_loop, "Player") as Node2D
	_expect(player != null, "Player should exist")
	if player == null:
		_finish()
		return
	_expect(
		player.scene_file_path == PLAYER_SCENE.resource_path,
		"default character should instantiate its data-bound dedicated scene"
	)
	_expect_ammunition_removed(run_loop, player)
	var initial_run_snapshot: Dictionary = (
		run_loop.call("create_run_snapshot") as Dictionary
	)
	_expect(
		int(initial_run_snapshot.get("schema_version", 0)) == 16,
		"new runs should use Run schema v16"
	)
	_expect(player is CharacterBody2D, "Player should keep 2D CharacterBody2D movement")
	_expect(_find_node_by_name(player, "Player3DVisual") == null, "Player should use the top-down 2D placeholder instead of a 3D orthographic visual child")
	var player_visual: PlayerSlimeVisual = (
		player.get_node_or_null("Visual") as PlayerSlimeVisual
	)
	_expect(player_visual != null, "Player should use a scene-authored PlayerSlimeVisual")
	_expect(_find_node_by_name(player, "FacingBeam") is Line2D, "Player aim marker should be a scene-authored FacingBeam")
	_expect(_find_node_by_name(player, "FacingLine") == null, "Player should remove the old long FacingLine")
	_expect(_find_node_by_name(player, "FacingArrow") == null, "Player should remove the old FacingArrow")
	_expect(_find_node_by_name(player, "Eye") == null, "Player should remove the old Eye marker")
	_expect_composition_hud_colors(run_loop)

	await _expect_stats_panel_hold_to_show(run_loop)

	var active_world: Node = run_loop.get_node_or_null("ActiveWorld")
	var camera_controller: Node = run_loop.get_node_or_null(
		"ActiveWorld/GameplayCameraController"
	)
	var camera: Camera2D = _find_node_by_name(camera_controller, "CenteredCamera") as Camera2D
	var camera_host: Node = _find_node_by_name(camera_controller, "PhantomCameraHost")
	var player_camera: Node2D = _find_node_by_name(camera_controller, "PlayerCamera") as Node2D
	_expect(camera != null and camera.enabled, "CenteredCamera should be enabled")
	_expect(
		camera_controller != null and camera_controller.get_parent() == active_world,
		"ActiveWorld should own the gameplay camera controller"
	)
	_expect(
		player.get_node_or_null("GameplayCameraController") == null,
		"Player should not own the run-level gameplay camera controller"
	)
	_expect(camera_host != null, "CenteredCamera should own a PhantomCameraHost")
	_expect(player_camera != null, "gameplay camera controller should own a PlayerCamera PhantomCamera2D")
	_expect(Engine.has_singleton("PhantomCameraManager"), "PhantomCameraManager should be registered as the stable project autoload")
	_expect(is_equal_approx(Engine.physics_jitter_fix, 0.5), "formal client should keep the Godot default physics jitter fix")
	if camera != null:
		_expect(camera.ignore_rotation, "CenteredCamera should keep the screen horizon level")
		_expect(absf(camera.rotation_degrees) < 0.01, "CenteredCamera should not roll the viewport")
		_expect(is_equal_approx(camera.zoom.x, camera.zoom.y), "CenteredCamera should keep uniform zoom so screen-space movement matches 2D math")
		_expect(get_viewport().get_camera_2d() == camera, "CenteredCamera should be the active viewport camera")
	if camera_host != null and player_camera != null:
		_expect(camera_host.call("get_active_pcam") == player_camera, "PhantomCameraHost should select PlayerCamera")
		_expect(int(player_camera.get("follow_mode")) == 1, "PlayerCamera should use GLUED follow mode")
		_expect(player_camera.get("follow_target") == player, "PlayerCamera should follow the active Player")
		_expect(player_camera.get("zoom") == Vector2.ONE, "PlayerCamera should keep the established 1:1 zoom")
		_expect(
			(player_camera.get("follow_offset") as Vector2).is_zero_approx(),
			"PlayerCamera should start centered before the first valid aim input"
		)
	_expect(
		player.has_method("set_camera_look_offset"),
		"Player should expose the camera look offset interface"
	)
	_expect_camera_preserves_screen_axis_scale(player)
	_expect(_find_node_by_name(player, "Camera3D") == null, "Player should not rely on an internal Camera3D for the formal top-down view")
	await _expect_aim_directed_camera(
		player,
		camera_controller,
		camera,
		player_camera
	)
	await _expect_weapon_recoil_runtime(player, camera_controller)
	_expect(_find_node_by_name(run_loop, "WorldBackground") != null, "WorldBackground should provide movement reference")
	_expect(_find_node_by_name(run_loop, "MapManager") != null, "finite MapManager should be mounted")
	_expect(_map_summary_has_finite_bounds(run_loop), "MapManager should expose finite map bounds")
	_expect(_map_boundary_is_rectangle(run_loop), "MapManager should expose a rectangular top-down boundary")
	_expect(_map_safe_zone_is_rectangle(run_loop), "MapManager should draw the spawn safe zone as a grid-aligned rectangle")
	_expect(_map_summary_has_rect_grid(run_loop), "MapManager should expose a positive rectangular grid cell size")
	_expect(_warzone_director_initial_summary_is_ready(run_loop), "WarzoneDirector should expose the standard warmup phase debug summary")
	_expect_enemy_spawn_reward_snapshots(run_loop, player)
	_expect_open_warzone_difficulty_and_wave_gating(run_loop)
	_expect(_map_clamps_to_rect_boundary(run_loop), "MapManager should clamp positions to the rectangular logic boundary")
	_expect(_player_clamps_to_rect_boundary(run_loop, player), "Player should clamp to the rectangular logic boundary")
	_expect(PoolManager.active_count(POOL_IDS.HAZARD_SPIKE) > 0, "PCG map should spawn active hazards")
	_expect(_active_hazards_are_on_grid(run_loop), "spawned hazards should align to radius-aware rectangular grid anchors")
	_expect(_map_has_director_interest_point_hazard(run_loop), "WarzoneDirector interest points should add director-sourced map hazards")
	_expect(_interest_point_targets_are_on_grid(run_loop), "interest point targets should align to rectangular grid anchors")
	_expect(_interest_point_targets_avoid_hazards(run_loop), "interest point targets should not overlap active hazards")
	_expect(_interest_point_caches_are_on_grid(run_loop), "interest point caches should align to rectangular grid anchors")
	_expect(_interest_point_caches_avoid_hazards(run_loop), "interest point caches should not overlap active hazards")
	await _expect_bullet_hits_interest_point_target(run_loop, player)
	_expect(_map_restore_snaps_legacy_hazards(run_loop), "restored legacy hazard placements should snap to radius-aware rectangular grid anchors")
	_expect(_map_normalizes_edge_hazards_to_grid(run_loop), "edge hazard normalization should keep positions on rectangular grid anchors")

	var start_position: Vector2 = player.global_position
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.RIGHT)
	for _index: int in range(MOVE_FRAMES):
		await get_tree().physics_frame
	InputService.inject_playback_value(ACTIONS.MOVE, Vector2.ZERO)
	InputService.set_playback_active(false)
	_expect(player.global_position.x > start_position.x + 1.0, "WASD movement should move the player")
	for _index: int in range(2):
		await get_tree().physics_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	if camera != null:
		var active_look_offset: Vector2 = camera_controller.call(
			"current_look_offset"
		)
		var tracked_position: Vector2 = (
			player.global_position
			+ active_look_offset
		)
		_expect(
			camera.global_position.distance_to(tracked_position) < 0.5,
			"Phantom Camera should track player movement plus aim look without follow damping actual=%s expected=%s"
			% [camera.global_position, tracked_position]
		)

	var before_aim_position: Vector2 = player.global_position
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.AIM, Vector2.UP)
	for _index: int in range(AIM_FRAMES):
		await get_tree().physics_frame
	InputService.inject_playback_value(ACTIONS.AIM, Vector2.ZERO)
	InputService.set_playback_active(false)
	_expect(player.get("aim_direction") == Vector2.UP, "arrow aim fallback should point to Vector2.UP")
	_expect(player.global_position.distance_to(before_aim_position) < 1.0, "arrow aim fallback should not move the player")

	player.call("aim_at_world_position", player.global_position + Vector2(180.0, -90.0))
	for _index: int in range(AIM_FRAMES):
		await get_tree().physics_frame
	var mouse_aim: Vector2 = player.get("aim_direction")
	_expect(mouse_aim.x > 0.75 and mouse_aim.y < -0.25, "mouse aim should support diagonal mouse direction")
	_expect(absf(mouse_aim.x) < 0.98 and absf(mouse_aim.y) > 0.1, "mouse aim should not snap back to four directions")
	_expect(_player_top_down_visual_tracks_aim_direction(player, mouse_aim), "top-down player placeholder should expose full aim direction")
	_expect(_interest_point_caches_use_ground_layer(run_loop, player), "interest point caches should render on the ground layer below actors")

	var isolated_player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	isolated_player.name = "SmokeIsolatedPlayer"
	run_loop.add_child(isolated_player)
	var isolated_stats: Dictionary = {}
	isolated_stats[STATS.MAX_HP] = 600.0
	isolated_stats[STATS.HEALTH_REGEN] = 30.0
	isolated_stats[STATS.MOVE_SPEED] = 0.0
	isolated_player.call("configure", isolated_stats)
	var direct_damage_source: Node = Node.new()
	direct_damage_source.name = "SmokeDirectDamageSource"
	run_loop.add_child(direct_damage_source)
	var first_player_life: float = float(isolated_player.call("current_life"))
	var direct_damage_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		100.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		direct_damage_source,
		isolated_player,
		"team_enemy",
		"team_player"
	)
	var first_direct_result: Dictionary = Combat.apply_damage(
		isolated_player,
		direct_damage_info
	)
	var damaged_player_life: float = float(isolated_player.call("current_life"))
	_expect(bool(first_direct_result.get("applied", false)), "first direct hit should damage the player")
	_expect(damaged_player_life < first_player_life, "first direct hit should reduce player life")

	var repeated_direct_result: Dictionary = Combat.apply_damage(
		isolated_player,
		direct_damage_info
	)
	_expect(
		bool(repeated_direct_result.get("applied", false)),
		"direct repeated damage should no longer be blocked by global hit invulnerability"
	)
	_expect(
		float(isolated_player.call("current_life")) < damaged_player_life,
		"direct repeated damage should reduce player life"
	)

	var repeated_damaged_player_life: float = float(
		isolated_player.call("current_life")
	)
	await get_tree().process_frame
	var regenerated_player_life: float = float(isolated_player.call("current_life"))
	_expect(
		regenerated_player_life > repeated_damaged_player_life,
		"configured player health_regen should remain available for explicit test fixtures"
	)
	_expect(regenerated_player_life <= first_player_life, "player health_regen should not exceed max life")
	var refreshed_direct_result: Dictionary = Combat.apply_damage(
		isolated_player,
		direct_damage_info
	)
	_expect(bool(refreshed_direct_result.get("applied", false)), "same source may deal direct damage again")
	isolated_player.queue_free()
	direct_damage_source.queue_free()

	await _expect_enemy_center_separation(run_loop, player)
	await _expect_player_enemy_separation(run_loop, player)
	await _expect_enemy_movement_bounds(run_loop, player)
	await _expect_swarm_enemy_spawn(run_loop, player)
	await _expect_enemy_player_targeting(run_loop, player)
	await _expect_route_aware_enemy_perception(run_loop, player)
	await _expect_explicit_enemy_attacks(run_loop, player)
	await _expect_world_event_defense_targeting(run_loop, player)
	await _expect_ranged_enemy_projectile_damage(run_loop, player)
	await _expect_overdrive_rounds_skill(run_loop, player)
	await _expect_gold_orb_draw_order(run_loop, player)
	await _expect_gold_orb_feedback(run_loop, player)
	await _expect_gold_progression(run_loop, player)
	await _expect_interest_point_rewards(run_loop, player)

	var restored_run: Dictionary = await _expect_pause_save_resume(run_loop, player)
	var restored_run_loop_value: Node = restored_run.get("run_loop", run_loop) as Node
	var restored_player_value: Node2D = restored_run.get("player", player) as Node2D
	if (
		restored_run_loop_value == null
		or not is_instance_valid(restored_run_loop_value)
		or restored_player_value == null
		or not is_instance_valid(restored_player_value)
	):
		_finish()
		return
	run_loop = restored_run_loop_value
	player = restored_player_value
	var reward_restored_run: Dictionary = await _expect_reward_choice(
		run_loop,
		player
	)
	var reward_restored_loop_value: Node = reward_restored_run.get(
		"run_loop",
		run_loop
	) as Node
	var reward_restored_player_value: Node2D = reward_restored_run.get(
		"player",
		player
	) as Node2D
	if (
		reward_restored_loop_value == null
		or not is_instance_valid(reward_restored_loop_value)
		or reward_restored_player_value == null
		or not is_instance_valid(reward_restored_player_value)
	):
		_finish()
		return
	run_loop = reward_restored_loop_value
	player = reward_restored_player_value
	_expect(
		player.scene_file_path == PLAYER_SCENE.resource_path,
		"restored character id should recreate its data-bound dedicated scene"
	)
	active_world = run_loop.get_node_or_null("ActiveWorld")
	camera_controller = run_loop.get_node_or_null("ActiveWorld/GameplayCameraController")
	camera = _find_node_by_name(camera_controller, "CenteredCamera") as Camera2D
	camera_host = _find_node_by_name(camera_controller, "PhantomCameraHost")
	player_camera = _find_node_by_name(camera_controller, "PlayerCamera") as Node2D
	_expect(camera != null and camera.enabled, "restored run should reactivate CenteredCamera")
	_expect(
		camera_controller != null and camera_controller.get_parent() == active_world,
		"restored run should keep the gameplay camera controller under ActiveWorld"
	)
	_expect(
		player.get_node_or_null("GameplayCameraController") == null,
		"restored Player should not own the run-level gameplay camera controller"
	)
	_expect(camera_host != null and camera_host.call("get_active_pcam") == player_camera, "restored run should reactivate PlayerCamera")
	_expect(
		player_camera != null and player_camera.get("follow_target") == player,
		"restored PlayerCamera should follow the recreated Player instance"
	)
	_expect(
		camera_controller != null
		and (
			camera_controller.call("current_look_offset") as Vector2
		).is_zero_approx(),
		"restored run should rebind the camera with zero initial look offset"
	)

	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	for _index: int in range(SPAWN_FRAMES):
		await get_tree().process_frame
		await get_tree().physics_frame
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	InputService.set_playback_active(false)

	_expect(_pool_stat(POOL_IDS.BULLET_BASIC, "acquired") > 0, "WeaponSystem should acquire bullets")
	_expect(PoolManager.active_count(POOL_IDS.ENEMY_CHASER) > 0, "Spawner should spawn active enemies")
	_expect(PoolManager.has_pool(POOL_IDS.GOLD_ORB), "gold orb pool should remain registered after continue")
	_expect(PoolManager.active_count(POOL_IDS.HAZARD_SPIKE) > 0, "hazards should remain active after continue")

	var enemy: Node = _first_enemy_with_name_prefix(POOL_IDS.ENEMY_CHASER)
	_expect(enemy != null, "at least one chaser enemy should be in active_enemies")
	var ranks_before_forced_drop: Dictionary = _run_gear_mod_ranks(run_loop)
	var pickups_before_forced_drop: int = _active_gear_mod_pickup_count(run_loop)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, false)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true)
	if enemy != null:
		if run_loop.has_method("debug_force_next_gear_mod_drop_roll"):
			run_loop.call("debug_force_next_gear_mod_drop_roll", 0.0)
		var enemy_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
			999.0,
			ELEMENTS.ELEMENT_NEUTRAL,
			player,
			enemy,
			"team_player",
			"team_enemy"
		)
		var enemy_result: Dictionary = Combat.apply_damage(enemy, enemy_info)
		_expect(bool(enemy_result.get("applied", false)), "Combat should apply enemy damage")
		_expect(bool(enemy_result.get("defeated", false)), "Combat should defeat the smoke enemy")
		_expect(
			camera_controller != null and not bool(camera_controller.call("is_player_damage_shake_emitting")),
			"enemy damage should not trigger player camera shake"
		)
		_expect(enemy.has_method("is_defeat_feedback_active") and bool(enemy.call("is_defeat_feedback_active")), "defeated enemies should show defeat feedback before pooling")
		_expect(not enemy.is_in_group("active_enemies"), "defeated enemies should leave the live enemy group during feedback")
		_expect(_pool_stat(POOL_IDS.HIT_SPARK, "acquired") > 0, "enemy damage should acquire hit spark feedback")
		_expect(_pool_stat(POOL_IDS.DAMAGE_NUMBER, "acquired") > 0, "enemy damage should acquire damage number feedback")
		var ranks_after_drop_spawn: Dictionary = _run_gear_mod_ranks(run_loop)
		_expect(
			_active_gear_mod_pickup_count(run_loop)
			== pickups_before_forced_drop + 1,
			"forced player-attributed enemy defeat should spawn one Gear Mod pickup"
		)
		_expect(
			ranks_after_drop_spawn == ranks_before_forced_drop,
			"enemy Gear Mod drops should not advance rank before interaction"
		)
		var enemy_drop: Node2D = _first_active_gear_mod_pickup(run_loop)
		_expect(enemy_drop != null, "enemy Gear Mod pickup should remain active until interacted")
		if enemy_drop != null:
			player.global_position = enemy_drop.global_position
			for _frame: int in range(BOOT_FRAMES):
				await get_tree().process_frame
			_expect(
				_run_gear_mod_ranks(run_loop) == ranks_before_forced_drop,
				"contact with a Gear Mod pickup should not grant it automatically"
			)
			await _push_action_once(ACTIONS.INTERACT)
			var ranks_after_forced_drop: Dictionary = _run_gear_mod_ranks(run_loop)
			_expect(
				ranks_after_forced_drop != ranks_before_forced_drop,
				"interact should grant the enemy Gear Mod pickup"
			)
			var gear_mod_hud: Node = _find_node_by_name(run_loop, "GameplayHud")
			_expect(
				gear_mod_hud != null
				and gear_mod_hud.has_method("is_gear_mod_drop_feedback_visible")
				and bool(gear_mod_hud.call("is_gear_mod_drop_feedback_visible")),
				"successful Gear Mod pickup should show grant HUD feedback"
			)

	var smoke_player_damage_source: Node = Node.new()
	smoke_player_damage_source.name = "SmokePlayerDamageSource"
	run_loop.add_child(smoke_player_damage_source)
	player.call("debug_heal", float(player.call("max_life")))
	await _wait_player_vulnerability(player)
	var feedback_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		1.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		smoke_player_damage_source,
		player,
		"team_enemy",
		"team_player"
	)
	var feedback_result: Dictionary = Combat.apply_damage(player, feedback_info)
	_expect(bool(feedback_result.get("applied", false)), "effective player damage should apply before camera feedback checks")
	_expect(
		camera_controller != null and bool(camera_controller.call("is_player_damage_shake_emitting")),
		"effective player damage should trigger camera shake"
	)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, false)
	_expect(
		camera_controller != null and not bool(camera_controller.call("is_player_damage_shake_emitting")),
		"disabling screen shake should stop an active emission immediately"
	)
	if camera != null:
		_expect(camera.offset == Vector2.ZERO, "disabling screen shake should reset the camera offset")
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true)
	var repeated_feedback_result: Dictionary = Combat.apply_damage(
		player,
		feedback_info
	)
	_expect(
		bool(repeated_feedback_result.get("applied", false)),
		"repeated player damage should apply without global hit invulnerability"
	)
	_expect(
		camera_controller != null and bool(camera_controller.call("is_player_damage_shake_emitting")),
		"repeated effective player damage should trigger camera shake"
	)

	await _wait_player_vulnerability(player)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, false)
	var disabled_feedback_result: Dictionary = Combat.apply_damage(player, feedback_info)
	_expect(bool(disabled_feedback_result.get("applied", false)), "player damage should still apply while screen shake is disabled")
	_expect(
		camera_controller != null and not bool(camera_controller.call("is_player_damage_shake_emitting")),
		"disabled screen shake should suppress effective player damage feedback"
	)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true)
	player.call("debug_heal", float(player.call("max_life")))
	if player.has_method("debug_set_shield"):
		player.call("debug_set_shield", 0.0, 0.0)
	var build_ranks_before_death: Dictionary = _run_gear_mod_ranks(run_loop)
	var build_mod_ids: Array[String] = []
	for raw_mod_id: Variant in build_ranks_before_death.keys():
		build_mod_ids.append(String(raw_mod_id))
	build_mod_ids.sort()
	var expected_build_name: String = ""
	if not build_mod_ids.is_empty():
		expected_build_name = tr(String(
			GearModSystem.mod_definition(build_mod_ids[0]).get("name_key", "")
		))
	var player_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		float(player.call("max_life")) * 10.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		smoke_player_damage_source,
		player,
		"team_enemy",
		"team_player"
	)
	var player_result: Dictionary = Combat.apply_damage(player, player_info)
	_expect(bool(player_result.get("applied", false)), "Combat should apply player damage")
	_expect(bool(player_result.get("defeated", false)), "Combat should defeat the player")
	_expect(
		camera_controller != null and bool(camera_controller.call("is_player_damage_shake_emitting")),
		"fatal player damage should still trigger camera shake"
	)
	_expect(GameState.is_state(GameState.GAME_OVER), "player death should enter GAME_OVER")
	var game_over_panel: Node = _find_node_by_name(get_tree().root, "GameOverPanel")
	_expect(game_over_panel != null, "player death should show game-over panel")
	_expect(not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), "player death should consume the active run save")
	_expect(_find_node_by_name(game_over_panel, "SettlementLabel") == null, "game-over panel should not show legacy meta settlement rewards")
	var game_over_summary: Label = _find_node_by_name(game_over_panel, "SummaryLabel") as Label
	var game_over_summary_text: String = String(game_over_summary.text) if game_over_summary != null else ""
	_expect(
		game_over_summary != null
		and game_over_summary_text.contains(tr("ui_result_build_header"))
		and not expected_build_name.is_empty()
		and game_over_summary_text.contains(expected_build_name),
		"player death result panel should list the current run build: %s" % game_over_summary_text
	)
	_expect(
		_run_gear_mod_ranks(run_loop).is_empty(),
		"player death should clear the in-memory run Gear Mod state"
	)
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


func _map_summary_has_finite_bounds(run_loop: Node) -> bool:
	return _map_bounds(run_loop).size.x > 0.0 and _map_bounds(run_loop).size.y > 0.0


func _map_summary_has_rect_grid(run_loop: Node) -> bool:
	var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
	return grid_cell_size.x > 0.0 and grid_cell_size.y > 0.0


func _warzone_director_initial_summary_is_ready(run_loop: Node) -> bool:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return false
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_director: Variant = summary.get("warzone_director", {})
	if not raw_director is Dictionary:
		return false
	var director: Dictionary = raw_director as Dictionary
	var raw_wave_ids: Variant = director.get("wave_ids", [])
	var raw_interest_point_ids: Variant = director.get("interest_point_ids", [])
	if not raw_wave_ids is Array or not raw_interest_point_ids is Array:
		return false
	var wave_ids: Array = raw_wave_ids as Array
	var interest_point_ids: Array = raw_interest_point_ids as Array
	return (
		bool(director.get("configured", false))
		and String(director.get("director_id", "")) == "director_standard_warzone"
		and String(director.get("mutation_id", "")) == "nest_mutation_hunting_ground"
		and String(director.get("phase_id", "")) == "phase_insertion"
		and wave_ids.has("wave_standard_early_chasers")
		and wave_ids.has("wave_standard_ranged_spitters")
		and _array_has_all_strings(interest_point_ids, [
			"poi_elite_nest",
			"poi_mod_cache",
			"poi_resource_cache",
			"poi_minor_nest_core",
		])
	)


func _expect_open_warzone_difficulty_and_wave_gating(run_loop: Node) -> void:
	var initial_difficulty: Dictionary = run_loop.call(
		"debug_difficulty_snapshot"
	) as Dictionary
	_expect(
		float(initial_difficulty.get("elapsed", 0.0)) > 0.0,
		"open warzone should advance difficulty time immediately"
	)
	var progression: DifficultyProgression = run_loop.get(
		"_difficulty_progression"
	) as DifficultyProgression
	_expect(
		progression != null,
		"open warzone should own a mode-level difficulty progression"
	)
	if progression == null:
		return
	var progression_snapshot: Dictionary = progression.snapshot()
	var spawn_states_before: Dictionary = (
		run_loop.get("_spawn_states") as Dictionary
	).duplicate(true)
	var rng_snapshot: Dictionary = RNG.snapshot()
	var active_enemy_ids_before: Dictionary = {}
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		active_enemy_ids_before[enemy.get_instance_id()] = true
	var elapsed: float = float(initial_difficulty.get("elapsed", 0.0))
	progression.advance(maxf(60.001 - elapsed, 0.0))
	var advanced_summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var advanced_director: Dictionary = advanced_summary.get(
		"warzone_director",
		{}
	) as Dictionary
	_expect(
		String(advanced_director.get("phase_id", ""))
		== "phase_first_reward_node"
		and (
			advanced_director.get("wave_ids", []) as Array
		).has("wave_standard_swarm_mix"),
		"WarzoneDirector phase and wave gating should read difficulty time"
	)
	run_loop.call("_update_spawner")
	var spawn_states_after: Dictionary = run_loop.get(
		"_spawn_states"
	) as Dictionary
	_expect(
		spawn_states_after.has("wave_standard_swarm_mix"),
		"open-warzone spawner should enable the 60-second wave from difficulty time"
	)
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if not active_enemy_ids_before.has(enemy.get_instance_id()):
			PoolManager.release(enemy)
	run_loop.set("_spawn_states", spawn_states_before)
	RNG.restore_snapshot(rng_snapshot)
	_expect(
		progression.restore_snapshot(progression_snapshot),
		"open-warzone difficulty gating test should restore its progression snapshot"
	)


func _expect_enemy_spawn_reward_snapshots(
	run_loop: Node,
	player: Node2D
) -> void:
	var progression: DifficultyProgression = run_loop.get(
		"_difficulty_progression"
	) as DifficultyProgression
	_expect(
		progression != null,
		"enemy reward smoke should access difficulty progression"
	)
	if progression == null:
		return
	var progression_snapshot: Dictionary = progression.snapshot()
	var rng_snapshot: Dictionary = RNG.snapshot()
	var expected_ranges: Dictionary = {
		"enemy_chaser": Vector2i(9, 11),
		"enemy_swarm": Vector2i(6, 7),
		"enemy_stalker": Vector2i(15, 18),
		"enemy_bulwark": Vector2i(18, 22),
		"enemy_spitter": Vector2i(9, 11),
	}
	var expected_value_multipliers: Dictionary = {
		"enemy_chaser": 1.0,
		"enemy_swarm": 0.6666667,
		"enemy_stalker": 1.6666667,
		"enemy_bulwark": 2.0,
		"enemy_spitter": 1.0,
	}
	for enemy_id: String in expected_ranges:
		var spawn_key: String = "reward_range_%s" % enemy_id
		var spawned: bool = bool(
			run_loop.call(
				"_spawn_enemy_at",
				enemy_id,
				player.global_position + Vector2(500.0, 0.0),
				spawn_key
			)
		)
		_expect(spawned, "%s reward range smoke should spawn" % enemy_id)
		var enemy: Node = _enemy_with_wave_key(spawn_key)
		_expect(enemy != null, "%s reward range smoke should find its enemy" % enemy_id)
		if enemy == null:
			continue
		var enemy_snapshot: Dictionary = enemy.call("snapshot") as Dictionary
		var reward: Dictionary = enemy_snapshot.get(
			"reward_snapshot",
			{}
		) as Dictionary
		var expected_range: Vector2i = expected_ranges[enemy_id] as Vector2i
		var gold_reward: int = int(reward.get("gold_reward", 0))
		_expect(
			bool(reward.get("valid", false))
			and gold_reward >= expected_range.x
			and gold_reward <= expected_range.y,
			"%s should lock a standard opening reward inside %d-%d"
			% [enemy_id, expected_range.x, expected_range.y]
		)
		_expect(
			int(reward.get("spawn_tier", -1)) == 0
			and is_equal_approx(
				float(reward.get("difficulty_coefficient", 0.0)),
				1.0
			)
			and is_equal_approx(
				float(reward.get("monster_value_multiplier", 0.0)),
				float(expected_value_multipliers[enemy_id])
			)
			and is_equal_approx(
				float(reward.get("specialization_multiplier", 0.0)),
				1.0
			)
			and is_equal_approx(
				float(reward.get("time_multiplier", 0.0)),
				1.0
			)
			and float(reward.get("random_multiplier", 0.0)) >= 0.9
			and float(reward.get("random_multiplier", 0.0)) <= 1.1,
			"%s reward snapshot should preserve every formula multiplier"
			% enemy_id
		)
		PoolManager.release(enemy)

	var streams_before_invalid: Dictionary = (
		RNG.snapshot().get("streams", {}) as Dictionary
	).duplicate(true)
	_expect(
		not bool(
			run_loop.call(
				"_spawn_enemy_at",
				"enemy_missing",
				player.global_position,
				"reward_invalid"
			)
		),
		"unknown enemy should fail before reward RNG is consumed"
	)
	var streams_after_invalid: Dictionary = (
		RNG.snapshot().get("streams", {}) as Dictionary
	).duplicate(true)
	_expect(
		streams_after_invalid == streams_before_invalid,
		"failed enemy spawn should not consume any RNG stream"
	)

	var streams_before_spawn: Dictionary = (
		RNG.snapshot().get("streams", {}) as Dictionary
	).duplicate(true)
	var locked_spawn_key: String = "reward_locked_at_spawn"
	_expect(
		bool(
			run_loop.call(
				"_spawn_enemy_at",
				"enemy_chaser",
				player.global_position + Vector2(540.0, 0.0),
				locked_spawn_key
			)
		),
		"reward lock smoke should spawn a chaser"
	)
	var streams_after_spawn: Dictionary = (
		RNG.snapshot().get("streams", {}) as Dictionary
	).duplicate(true)
	for stream_id: String in streams_before_spawn:
		if stream_id == "economy":
			_expect(
				streams_after_spawn.get(stream_id, {})
				!= streams_before_spawn.get(stream_id, {}),
				"successful enemy spawn should consume RNG.economy"
			)
		else:
			_expect(
				streams_after_spawn.get(stream_id, {})
				== streams_before_spawn.get(stream_id, {}),
				"enemy reward resolution should not perturb RNG.%s"
				% stream_id
			)
	var locked_enemy: Node = _enemy_with_wave_key(locked_spawn_key)
	_expect(
		locked_enemy != null,
		"reward lock smoke should find its spawned enemy"
	)
	if locked_enemy != null:
		var reward_before_tier: Dictionary = (
			locked_enemy.call("snapshot") as Dictionary
		).get("reward_snapshot", {}) as Dictionary
		var elapsed: float = float(
			progression.current_snapshot().get("elapsed", 0.0)
		)
		progression.advance(maxf(90.001 - elapsed, 0.0))
		var reward_after_tier: Dictionary = (
			locked_enemy.call("snapshot") as Dictionary
		).get("reward_snapshot", {}) as Dictionary
		_expect(
			reward_after_tier == reward_before_tier,
			"spawned enemy reward should remain locked after crossing a tier"
		)
		PoolManager.release(locked_enemy)

	var fixed_difficulty_key: String = "reward_actual_spawn_tier"
	_expect(
		bool(
			run_loop.call(
				"_spawn_enemy_at",
				"enemy_chaser",
				player.global_position + Vector2(580.0, 0.0),
				fixed_difficulty_key,
				"",
				{"reward_specialization_multiplier": 1.0},
				{
					"health_multiplier": 1.0,
					"damage_multiplier": 1.0,
				}
			)
		),
		"fixed combat-difficulty enemy should spawn"
	)
	var fixed_difficulty_enemy: Node = _enemy_with_wave_key(
		fixed_difficulty_key
	)
	_expect(
		fixed_difficulty_enemy != null,
		"fixed combat-difficulty reward smoke should find its enemy"
	)
	if fixed_difficulty_enemy != null:
		var fixed_snapshot: Dictionary = (
			fixed_difficulty_enemy.call("snapshot") as Dictionary
		)
		var fixed_reward: Dictionary = fixed_snapshot.get(
			"reward_snapshot",
			{}
		) as Dictionary
		_expect(
			int(fixed_reward.get("spawn_tier", -1)) == 1
			and is_equal_approx(
				float(fixed_snapshot.get("spawn_health_multiplier", 0.0)),
				1.0
			)
			and is_equal_approx(
				float(fixed_snapshot.get("spawn_damage_multiplier", 0.0)),
				1.0
			),
			"event-style fixed combat scaling should still use actual spawn tier for gold"
		)
		PoolManager.release(fixed_difficulty_enemy)

	_expect(
		progression.restore_snapshot(progression_snapshot),
		"enemy reward smoke should restore difficulty progression"
	)
	RNG.restore_snapshot(rng_snapshot)


func _interest_point_position(run_loop: Node, point_id: String) -> Vector2:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return Vector2.ZERO
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_points: Variant = summary.get("interest_points", {})
	if not raw_points is Dictionary:
		return Vector2.ZERO
	var points: Dictionary = raw_points as Dictionary
	var point: Dictionary = points.get(point_id, {}) as Dictionary
	return _dict_to_vector(point.get("position", {}), Vector2.ZERO)


func _map_boundary_is_rectangle(run_loop: Node) -> bool:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return false
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_map: Variant = summary.get("map", {})
	if not raw_map is Dictionary:
		return false
	var map_summary: Dictionary = raw_map as Dictionary
	if String(map_summary.get("boundary_shape", "")) != "rectangle":
		return false
	var raw_points: Variant = map_summary.get("boundary_points", [])
	if not raw_points is Array:
		return false
	var points: Array = raw_points as Array
	if points.size() != 4:
		return false
	var center: Vector2 = _map_boundary_center(run_loop)
	var half_extents: Vector2 = _map_boundary_half_extents(run_loop)
	var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
	if half_extents.x <= 0.0 or half_extents.y <= 0.0 or grid_cell_size.x <= 0.0 or grid_cell_size.y <= 0.0:
		return false
	if absf(fmod(half_extents.x * 2.0, grid_cell_size.x)) > 0.01:
		return false
	if absf(fmod(half_extents.y * 2.0, grid_cell_size.y)) > 0.01:
		return false
	var expected_points: Array[Vector2] = [
		center + Vector2(-half_extents.x, -half_extents.y),
		center + Vector2(half_extents.x, -half_extents.y),
		center + Vector2(half_extents.x, half_extents.y),
		center + Vector2(-half_extents.x, half_extents.y),
	]
	for index: int in range(expected_points.size()):
		if not points[index] is Dictionary:
			return false
		var point: Vector2 = _dict_to_vector(points[index], Vector2(1.0e20, 1.0e20))
		if point.distance_to(expected_points[index]) > 0.01:
			return false
	return true


func _map_safe_zone_is_rectangle(run_loop: Node) -> bool:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return false
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_map: Variant = summary.get("map", {})
	if not raw_map is Dictionary:
		return false
	var map_summary: Dictionary = raw_map as Dictionary
	if float(map_summary.get("safe_radius", 0.0)) <= 0.0:
		return false
	if String(map_summary.get("safe_zone_shape", "")) != "rectangle":
		return false
	var raw_points: Variant = map_summary.get("safe_zone_points", [])
	if not raw_points is Array:
		return false
	var points: Array = raw_points as Array
	if points.size() != 4:
		return false
	var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
	var half_extents: Vector2 = _dict_to_vector(map_summary.get("safe_zone_half_extents", {}), Vector2.ZERO)
	if half_extents.x <= 0.0 or half_extents.y <= 0.0 or grid_cell_size.x <= 0.0 or grid_cell_size.y <= 0.0:
		return false
	if absf(fmod(half_extents.x, grid_cell_size.x)) > 0.01:
		return false
	if absf(fmod(half_extents.y, grid_cell_size.y)) > 0.01:
		return false
	var start_position: Vector2 = _dict_to_vector(map_summary.get("player_start", {}), Vector2.ZERO)
	var expected_points: Array[Vector2] = [
		start_position + Vector2(-half_extents.x, -half_extents.y),
		start_position + Vector2(half_extents.x, -half_extents.y),
		start_position + Vector2(half_extents.x, half_extents.y),
		start_position + Vector2(-half_extents.x, half_extents.y),
	]
	for index: int in range(expected_points.size()):
		if not points[index] is Dictionary:
			return false
		var point: Vector2 = _dict_to_vector(points[index], Vector2(1.0e20, 1.0e20))
		if point.distance_to(expected_points[index]) > 0.01:
			return false
	return true


func _map_clamps_to_rect_boundary(run_loop: Node) -> bool:
	var map_manager: Node = _find_node_by_name(run_loop, "MapManager")
	if map_manager == null or not map_manager.has_method("clamp_position"):
		return false
	var bounds: Rect2 = _map_bounds(run_loop)
	var outside_corner: Vector2 = bounds.end + Vector2(128.0, 128.0)
	var clamped: Vector2 = map_manager.call("clamp_position", outside_corner)
	return clamped.distance_to(outside_corner) > 1.0 and _position_inside_map_boundary(run_loop, clamped)


func _player_clamps_to_rect_boundary(run_loop: Node, player: Node2D) -> bool:
	if player == null or not player.has_method("set_movement_bounds"):
		return false
	var original_position: Vector2 = player.global_position
	var bounds: Rect2 = _map_bounds(run_loop)
	var outside_corner: Vector2 = bounds.end + Vector2(128.0, 128.0)
	player.global_position = outside_corner
	player.call("set_movement_bounds", bounds)
	var clamped: Vector2 = player.global_position
	var radius: float = float(player.call("hit_radius"))
	var radius_aware: bool = (
		clamped.x >= bounds.position.x + radius - 0.001
		and clamped.x <= bounds.end.x - radius + 0.001
		and clamped.y >= bounds.position.y + radius - 0.001
		and clamped.y <= bounds.end.y - radius + 0.001
	)
	var tiny_bounds := Rect2(Vector2(100.0, 200.0), Vector2(30.0, 40.0))
	player.global_position = tiny_bounds.end + Vector2(64.0, 64.0)
	player.call("set_movement_bounds", tiny_bounds)
	var tiny_clamped: Vector2 = player.global_position
	var tiny_centered: bool = tiny_clamped.is_equal_approx(tiny_bounds.get_center())
	player.global_position = original_position
	player.call("set_movement_bounds", bounds)
	return (
		clamped.distance_to(outside_corner) > 1.0
		and _position_inside_map_boundary(run_loop, clamped)
		and radius_aware
		and tiny_centered
	)


func _expect_composition_hud_colors(run_loop: Node) -> void:
	var hud: Node = run_loop.get_node_or_null("GameplayHud")
	var composition: Label = (
		hud.get_node_or_null("Root/Margin/Layout/CompositionLabel") as Label
		if hud != null
		else null
	)
	var energy: Label = (
		hud.get_node_or_null("Root/Margin/Layout/EnergyLabel") as Label
		if hud != null
		else null
	)
	var expected_colors: Array[Color] = [
		Color("68bcdd"),
		Color("68bcdd"),
		Color("ed2f72"),
		Color("ed2f72"),
	]
	var original_name: String = composition.text if composition != null else ""
	_expect(composition != null, "HUD should expose the composition label")
	_expect(energy != null, "HUD should expose the shared energy label")
	if composition != null:
		_expect(
			composition.get_theme_color("font_color").is_equal_approx(Color("68bcdd")),
			"HUD composition name should use the main fragment primary"
		)
	if energy != null:
		_expect(
			energy.get_theme_color("font_color").is_equal_approx(Color.WHITE),
			"HUD shared energy should remain neutral white"
		)
	for slot_index: int in range(4):
		var slot: Label = (
			hud.get_node_or_null(
				"Root/CombatTray/Skill%d/SkillLabel" % (slot_index + 1)
			) as Label
			if hud != null
			else null
		)
		_expect(slot != null, "HUD should expose skill slot %d" % (slot_index + 1))
		if slot != null:
			_expect(
				slot.get_theme_color("font_color").is_equal_approx(
					expected_colors[slot_index]
				),
				"HUD skill slot %d should follow its fragment primary"
				% (slot_index + 1)
			)
	if hud == null:
		return
	hud.call(
		"set_composition",
		original_name,
		Color("ed2f72"),
		Color("68bcdd")
	)
	if composition != null:
		_expect(
			composition.get_theme_color("font_color").is_equal_approx(
				Color("ed2f72")
			),
			"HUD composition name should swap to the new main primary"
		)
	for slot_index: int in range(4):
		var slot: Label = hud.get_node_or_null(
			"Root/CombatTray/Skill%d/SkillLabel" % (slot_index + 1)
		) as Label
		var swapped_color: Color = (
			Color("ed2f72") if slot_index < 2 else Color("68bcdd")
		)
		_expect(
			slot != null
			and slot.get_theme_color("font_color").is_equal_approx(
				swapped_color
			),
			"HUD skill slot %d should swap with its fragment primary"
			% (slot_index + 1)
		)
	hud.call(
		"set_composition",
		original_name,
		Color("68bcdd"),
		Color("ed2f72")
	)


func _active_hazards_are_on_grid(run_loop: Node) -> bool:
	var map_manager: Node = _find_node_by_name(run_loop, "MapManager")
	if map_manager == null or not map_manager.has_method("normalize_hazard_position"):
		return false
	var saw_hazard: bool = false
	for hazard: Node in get_tree().get_nodes_in_group("active_hazards"):
		if not hazard is Node2D or not _is_descendant_of(hazard, run_loop):
			continue
		saw_hazard = true
		var hazard_2d: Node2D = hazard as Node2D
		var hazard_id: String = String(hazard.call("hazard_id")) if hazard.has_method("hazard_id") else ""
		if not _hazard_position_matches_anchor(map_manager, hazard_2d.global_position, hazard_id):
			var normalized_position: Vector2 = map_manager.call("normalize_hazard_position", hazard_2d.global_position, hazard_id)
			push_error("[RuntimeSmoke] hazard anchor mismatch id=%s position=%s normalized=%s" % [hazard_id, hazard_2d.global_position, normalized_position])
			return false
	return saw_hazard


func _map_has_director_interest_point_hazard(run_loop: Node) -> bool:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return false
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_map: Variant = summary.get("map", {})
	if not raw_map is Dictionary:
		return false
	var map_summary: Dictionary = raw_map as Dictionary
	var raw_sources: Variant = map_summary.get("hazard_sources", {})
	if not raw_sources is Dictionary:
		return false
	var sources: Dictionary = raw_sources as Dictionary
	return int(sources.get("director", 0)) >= 4


func _interest_point_targets_are_on_grid(run_loop: Node) -> bool:
	var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
	if grid_cell_size.x <= 0.0 or grid_cell_size.y <= 0.0:
		return false
	var saw_target: bool = false
	for target: Node in get_tree().get_nodes_in_group("active_interest_point_targets"):
		if not target is Node2D or not _is_descendant_of(target, run_loop):
			continue
		saw_target = true
		var target_2d: Node2D = target as Node2D
		var snapped_position: Vector2 = _snap_to_rect_grid(target_2d.global_position, grid_cell_size)
		if target_2d.global_position.distance_to(snapped_position) > 0.01:
			return false
	return saw_target


func _interest_point_targets_avoid_hazards(run_loop: Node) -> bool:
	var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
	var fallback_radius: float = maxf(grid_cell_size.x * 0.5, 1.0)
	var saw_target: bool = false
	for target: Node in get_tree().get_nodes_in_group("active_interest_point_targets"):
		if not target is Node2D or not _is_descendant_of(target, run_loop):
			continue
		saw_target = true
		var target_2d: Node2D = target as Node2D
		var target_radius: float = float(target.call("hit_radius")) if target.has_method("hit_radius") else fallback_radius
		for hazard: Node in get_tree().get_nodes_in_group("active_hazards"):
			if not hazard is Node2D or not _is_descendant_of(hazard, run_loop):
				continue
			var hazard_2d: Node2D = hazard as Node2D
			var hazard_radius: float = _hazard_spacing_radius(hazard, grid_cell_size)
			if target_2d.global_position.distance_to(hazard_2d.global_position) < target_radius + hazard_radius:
				return false
	return saw_target


func _interest_point_caches_are_on_grid(run_loop: Node) -> bool:
	var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
	if grid_cell_size.x <= 0.0 or grid_cell_size.y <= 0.0:
		return false
	var saw_cache: bool = false
	for cache: Node in get_tree().get_nodes_in_group("active_interest_point_caches"):
		if not cache is Node2D or not _is_descendant_of(cache, run_loop):
			continue
		saw_cache = true
		var cache_2d: Node2D = cache as Node2D
		var snapped_position: Vector2 = _snap_to_rect_grid(cache_2d.global_position, grid_cell_size)
		if cache_2d.global_position.distance_to(snapped_position) > 0.01:
			return false
	return saw_cache


func _interest_point_caches_avoid_hazards(run_loop: Node) -> bool:
	var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
	var fallback_radius: float = maxf(grid_cell_size.x * 0.5, 1.0)
	var saw_cache: bool = false
	for cache: Node in get_tree().get_nodes_in_group("active_interest_point_caches"):
		if not cache is Node2D or not _is_descendant_of(cache, run_loop):
			continue
		saw_cache = true
		var cache_2d: Node2D = cache as Node2D
		var cache_radius: float = float(cache.call("spacing_radius")) if cache.has_method("spacing_radius") else fallback_radius
		for hazard: Node in get_tree().get_nodes_in_group("active_hazards"):
			if not hazard is Node2D or not _is_descendant_of(hazard, run_loop):
				continue
			var hazard_2d: Node2D = hazard as Node2D
			var hazard_radius: float = _hazard_spacing_radius(hazard, grid_cell_size)
			if cache_2d.global_position.distance_to(hazard_2d.global_position) < cache_radius + hazard_radius:
				return false
	return saw_cache


func _player_top_down_visual_tracks_aim_direction(player: Node2D, expected_direction: Vector2) -> bool:
	var actual_direction: Vector2 = player.get("aim_direction")
	return actual_direction.distance_to(expected_direction.normalized()) <= 0.01


func _interest_point_caches_use_ground_layer(run_loop: Node, player: Node2D) -> bool:
	var map_manager: CanvasItem = _find_node_by_name(run_loop, "MapManager") as CanvasItem
	var saw_cache: bool = false
	for cache: Node in get_tree().get_nodes_in_group("active_interest_point_caches"):
		if not cache is CanvasItem or not _is_descendant_of(cache, run_loop):
			continue
		saw_cache = true
		var cache_item: CanvasItem = cache as CanvasItem
		if map_manager != null and cache_item.z_index <= map_manager.z_index:
			return false
		if cache_item.z_index >= 0:
			return false
		if cache_item.z_index >= player.z_index:
			return false
	return saw_cache


func _hazard_spacing_radius(hazard: Node, grid_cell_size: Vector2) -> float:
	var hazard_id: String = String(hazard.call("hazard_id")) if hazard.has_method("hazard_id") else ""
	for row: Dictionary in DataLoader.load_csv("res://data/hazards.csv"):
		if String(row.get("id", "")) == hazard_id:
			var radius_tiles: int = maxi(int(row.get("radius_tiles", 1)), 1)
			var half_extents: Vector2 = grid_cell_size * 0.5 * float(radius_tiles)
			return maxf(half_extents.x, half_extents.y)
	return maxf(grid_cell_size.x * 0.5, 1.0)


func _expect_bullet_hits_interest_point_target(run_loop: Node, player: Node2D) -> void:
	var target: Node2D = _first_interest_point_target("poi_elite_nest")
	_expect(target != null, "smoke should find a live elite nest interest point target")
	if target == null:
		return
	_expect(target.has_method("snapshot"), "interest point target should expose a snapshot for smoke damage checks")
	if not target.has_method("snapshot"):
		return
	var before_snapshot: Dictionary = target.call("snapshot") as Dictionary
	var life_before: float = float(before_snapshot.get("life_points", 0.0))
	var raw_bullet: Node = PoolManager.acquire(POOL_IDS.BULLET_BASIC)
	_expect(raw_bullet is Node2D and raw_bullet.has_method("configure"), "bullet pool should provide a configurable Bullet node")
	if not raw_bullet is Node2D or not raw_bullet.has_method("configure"):
		return
	var bullet: Node2D = raw_bullet as Node2D
	_expect(_find_node_by_name(bullet, "Visual") != null, "pooled bullets should keep their scene-authored visual subtree")
	_expect(
		bullet.get_node_or_null("EnemyVisual") == null
		and bullet.get_node_or_null("RibbonTrail") == null
		and bullet.get_node_or_null("EnemyRibbonTrail") == null,
		"pooled bullets should keep one trail-free shared visual"
	)
	bullet.global_position = target.global_position
	var old_parent: Node = bullet.get_parent()
	if old_parent != null:
		old_parent.remove_child(bullet)
	target.get_parent().add_child(bullet)
	bullet.call("configure", {
		STATS.DAMAGE: 7.0,
		STATS.BULLET_SPEED: 0.0,
		STATS.BULLET_RANGE: 96.0,
		STATS.PIERCE_COUNT: 0,
	}, {
		"element_id": ELEMENTS.ELEMENT_NEUTRAL,
		"hit_radius": 12.0,
		"lifetime": 1.0,
	}, Vector2.RIGHT, player)
	_expect_slime_bullet_visual(bullet, false, 12.0, "player target-hit bullet")
	for _index: int in range(2):
		await get_tree().physics_frame
	var after_snapshot: Dictionary = target.call("snapshot") as Dictionary
	_expect(float(after_snapshot.get("life_points", life_before)) < life_before, "real Bullet physics should damage interest point targets before claim_start_time")


func _first_interest_point_target(point_id: String) -> Node2D:
	for target: Node in get_tree().get_nodes_in_group("active_interest_point_targets"):
		if not target is Node2D:
			continue
		if target.has_method("point_id") and String(target.call("point_id")) == point_id:
			return target as Node2D
	return null


func _array_has_all_strings(values: Array, expected_values: Array[String]) -> bool:
	for expected_value: String in expected_values:
		if not values.has(expected_value):
			return false
	return true


func _map_restore_snaps_legacy_hazards(run_loop: Node) -> bool:
	var map_manager: Node = _find_node_by_name(run_loop, "MapManager")
	if map_manager == null or not map_manager.has_method("snapshot") or not map_manager.has_method("restore_snapshot") or not map_manager.has_method("hazard_placements"):
		return false
	var original_snapshot: Dictionary = map_manager.call("snapshot") as Dictionary
	var legacy_snapshot: Dictionary = original_snapshot.duplicate(true)
	legacy_snapshot["hazard_placements"] = [{
		"hazard_id": "hazard_fea_12_pulse",
		"position": {
			"x": 1919.0,
			"y": 1279.0,
		},
		"source": "manual",
	}]
	map_manager.call("restore_snapshot", legacy_snapshot)
	var placements: Array = map_manager.call("hazard_placements") as Array
	var snapped: bool = false
	if not placements.is_empty() and placements[0] is Dictionary:
		var placement: Dictionary = placements[0] as Dictionary
		var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
		var position: Vector2 = _dict_to_vector(placement.get("position", {}), Vector2.ZERO)
		var hazard_id: String = String(placement.get("hazard_id", ""))
		var half_extents: Vector2 = grid_cell_size
		snapped = (
			_hazard_position_matches_anchor(map_manager, position, hazard_id)
			and _position_inside_map_boundary(run_loop, position, half_extents)
		)
	map_manager.call("restore_snapshot", original_snapshot)
	return snapped


func _map_normalizes_edge_hazards_to_grid(run_loop: Node) -> bool:
	var map_manager: Node = _find_node_by_name(run_loop, "MapManager")
	if map_manager == null or not map_manager.has_method("snapshot") or not map_manager.has_method("restore_snapshot") or not map_manager.has_method("normalize_hazard_position"):
		return false
	var original_snapshot: Dictionary = map_manager.call("snapshot") as Dictionary
	var edge_snapshot: Dictionary = original_snapshot.duplicate(true)
	edge_snapshot["bounds"] = {
		"x": -1920.0,
		"y": -960.0,
		"width": 3840.0,
		"height": 1920.0,
	}
	map_manager.call("restore_snapshot", edge_snapshot)
	var grid_cell_size: Vector2 = _map_grid_cell_size(run_loop)
	var bounds: Rect2 = _map_bounds(run_loop)
	var hazard_id: String = "hazard_fea_12_pulse"
	var position: Vector2 = map_manager.call("normalize_hazard_position", bounds.end - Vector2.ONE, hazard_id)
	var half_extents: Vector2 = grid_cell_size
	var normalized: bool = (
		_hazard_position_matches_anchor(map_manager, position, hazard_id)
		and _position_inside_map_boundary(run_loop, position, half_extents)
	)
	map_manager.call("restore_snapshot", original_snapshot)
	return normalized


func _hazard_position_matches_anchor(map_manager: Node, position: Vector2, hazard_id: String) -> bool:
	if map_manager == null or not map_manager.has_method("normalize_hazard_position"):
		return false
	var normalized_position: Vector2 = map_manager.call("normalize_hazard_position", position, hazard_id)
	return position.distance_to(normalized_position) <= 0.01


func _map_grid_cell_size(run_loop: Node) -> Vector2:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return Vector2.ZERO
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_map: Variant = summary.get("map", {})
	if not raw_map is Dictionary:
		return Vector2.ZERO
	var map_summary: Dictionary = raw_map as Dictionary
	var raw_grid: Variant = map_summary.get("grid_cell_size", {})
	if not raw_grid is Dictionary:
		return Vector2.ZERO
	var grid: Dictionary = raw_grid as Dictionary
	return Vector2(float(grid.get("x", 0.0)), float(grid.get("y", 0.0)))


func _snap_to_rect_grid(world_position: Vector2, grid_cell_size: Vector2) -> Vector2:
	return Vector2(
		roundf(world_position.x / maxf(grid_cell_size.x, 1.0)) * grid_cell_size.x,
		roundf(world_position.y / maxf(grid_cell_size.y, 1.0)) * grid_cell_size.y
	)


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))


func _snapshot_has_hazards(snapshot: Dictionary) -> bool:
	return snapshot.get("hazards", []) is Array and (snapshot.get("hazards", []) as Array).size() > 0


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	return node == ancestor or (ancestor != null and ancestor.is_ancestor_of(node))


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


func _expect_camera_preserves_screen_axis_scale(player: Node2D) -> void:
	var screen_transform: Transform2D = get_viewport().get_canvas_transform()
	var origin_screen: Vector2 = screen_transform * player.global_position
	var horizontal_screen: Vector2 = screen_transform * (player.global_position + Vector2(100.0, 0.0))
	var vertical_screen: Vector2 = screen_transform * (player.global_position + Vector2(0.0, 100.0))
	var horizontal_length: float = origin_screen.distance_to(horizontal_screen)
	var vertical_length: float = origin_screen.distance_to(vertical_screen)
	_expect(
		absf(horizontal_length - vertical_length) < 0.01,
		"CenteredCamera should preserve equal screen scale for horizontal and vertical world units horizontal=%.4f vertical=%.4f" % [
			horizontal_length,
			vertical_length,
		]
	)


func _expect_aim_directed_camera(
	player: Node2D,
	camera_controller: Node,
	camera: Camera2D,
	player_camera: Node2D
) -> void:
	_expect(
		camera_controller != null
		and camera_controller.has_method("current_look_offset"),
		"gameplay camera controller should expose its current look offset"
	)
	if camera_controller == null or player_camera == null:
		return
	var feedback_config: Dictionary = DataLoader.load_json(
		DataLoader.CAMERA_FEEDBACK_PATH
	)
	var aim_look: Dictionary = feedback_config.get("aim_look", {}) as Dictionary
	var max_offset: float = float(aim_look.get("max_offset_px", 0.0))
	var dead_zone: float = float(aim_look.get("pointer_dead_zone_px", 0.0))
	var ratio: float = float(aim_look.get("pointer_offset_ratio", 0.0))
	_expect(
		is_equal_approx(max_offset, 240.0)
		and is_equal_approx(dead_zone, 32.0)
		and is_equal_approx(ratio, 0.3),
		"runtime camera aim look should use the validated schema v3 profile"
	)

	var screen_offset: Vector2 = Vector2(480.0, -240.0)
	var viewport_center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var viewport_position: Vector2 = viewport_center + screen_offset
	var pointer_event: InputEventMouseMotion = InputEventMouseMotion.new()
	pointer_event.position = viewport_position
	pointer_event.global_position = viewport_position
	pointer_event.relative = Vector2.ONE
	Input.parse_input_event(pointer_event)
	await get_tree().process_frame
	camera_controller.call("configure", player, feedback_config)
	await _wait_physics_frames(AIM_FRAMES)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).is_zero_approx(),
		"camera rebind should ignore pointer activity that happened before configure"
	)
	Input.parse_input_event(pointer_event)
	await get_tree().process_frame
	await _wait_physics_frames(AIM_FRAMES)
	await _wait_physics_frames(CAMERA_LOOK_SETTLE_FRAMES)
	screen_offset = (
		InputService.pointer_viewport_position() - viewport_center
	)

	var expected_look_offset: Vector2 = camera_controller.call(
		"_pointer_look_target",
		screen_offset
	)
	var actual_look_offset: Vector2 = camera_controller.call(
		"current_look_offset"
	)
	_expect(
		actual_look_offset.distance_to(expected_look_offset) < 0.1,
		"mouse camera look should apply the dead zone, ratio, cap, and exponential smoothing actual=%s expected=%s"
		% [actual_look_offset, expected_look_offset]
	)
	_expect(
		(player_camera.get("follow_offset") as Vector2).distance_to(
			actual_look_offset
		) < 0.01,
		"PlayerCamera follow_offset should mirror the controller look offset"
	)
	var expected_direction: Vector2 = (
		screen_offset + actual_look_offset
	).normalized()
	var actual_direction: Vector2 = player.get("aim_direction")
	var aim_distance: float = actual_direction.distance_to(expected_direction)
	_expect(
		aim_distance < 0.02,
		"mouse aim should use the player's actual screen position actual=%s expected=%s distance=%.4f" % [
			actual_direction,
			expected_direction,
			aim_distance,
		]
	)
	var held_look_offset: Vector2 = actual_look_offset
	await _wait_physics_frames(AIM_FRAMES)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(held_look_offset) < 0.01,
		"a stationary pointer should keep its look offset"
	)

	if camera != null:
		camera.offset = Vector2(90.0, -40.0)
		await get_tree().physics_frame
		_expect(
			(player.get("aim_direction") as Vector2).distance_to(
				expected_direction
			) < 0.02,
			"Camera2D shake offset should not contaminate pointer aim"
		)
		camera.offset = Vector2.ZERO
	var look_before_shake_toggle: Vector2 = camera_controller.call(
		"current_look_offset"
	)
	var position_before_shake_toggle: Vector2 = player.global_position
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, false)
	await get_tree().physics_frame
	_expect(
		(player.get("aim_direction") as Vector2).distance_to(
			expected_direction
		) < 0.02,
		"screen shake setting should not change pointer aim direction"
	)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(look_before_shake_toggle) < 0.01,
		"screen shake setting should not clear the stable aim look offset"
	)
	_expect(
		player.global_position.distance_to(position_before_shake_toggle) < 0.01,
		"screen shake setting should not change gameplay position"
	)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true)

	_expect(
		(
			camera_controller.call(
				"_pointer_look_target",
				Vector2(dead_zone * 0.5, 0.0)
			) as Vector2
		).is_zero_approx(),
		"pointer inside the camera dead zone should target zero look offset"
	)
	_expect(
		(
			camera_controller.call(
				"_pointer_look_target",
				Vector2(dead_zone + 100.0, 0.0)
			) as Vector2
		).distance_to(Vector2.RIGHT * 100.0 * ratio) < 0.001,
		"pointer camera look should use the configured offset ratio after the dead zone"
	)
	_expect(
		(
			camera_controller.call(
				"_pointer_look_target",
				Vector2(5000.0, 0.0)
			) as Vector2
		).distance_to(Vector2.RIGHT * max_offset) < 0.001,
		"pointer camera look should cap at the configured maximum offset"
	)

	await _inject_runtime_key(KEY_RIGHT, true)
	await _wait_physics_frames(CAMERA_LOOK_SETTLE_FRAMES)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(Vector2.RIGHT * max_offset) < 0.1,
		"keyboard aim should use the configured maximum camera look offset"
	)
	await _inject_runtime_key(KEY_RIGHT, false)
	await _wait_physics_frames(AIM_FRAMES)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(Vector2.RIGHT * max_offset) < 0.1,
		"releasing keyboard aim should preserve the last camera look direction"
	)

	var virtual_device_id: int = GUIDE._input_state.connect_virtual_stick(0)
	await _inject_runtime_joy_axis(
		virtual_device_id,
		JOY_AXIS_RIGHT_Y,
		-1.0
	)
	await _wait_physics_frames(CAMERA_LOOK_SETTLE_FRAMES)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(Vector2.UP * max_offset) < 0.1,
		"gamepad aim should use the configured maximum camera look offset"
	)
	await _inject_runtime_joy_axis(
		virtual_device_id,
		JOY_AXIS_RIGHT_Y,
		0.0
	)
	GUIDE._input_state.disconnect_virtual_stick(virtual_device_id)

	InputService.set_playback_active(true)
	var replay_direction: Vector2 = Vector2(-0.6, 0.8)
	InputService.inject_playback_value(ACTIONS.AIM, replay_direction)
	await _wait_physics_frames(CAMERA_LOOK_SETTLE_FRAMES)
	var replay_target: Vector2 = replay_direction.normalized() * max_offset
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(replay_target) < 0.1,
		"Replay aim should reproduce its final direction at the maximum camera look offset actual=%s expected=%s"
		% [
			camera_controller.call("current_look_offset") as Vector2,
			replay_target,
		]
	)
	InputService.inject_playback_value(ACTIONS.AIM, Vector2.ZERO)
	await _wait_physics_frames(AIM_FRAMES)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(replay_target) < 0.1,
		"released Replay aim should preserve the last camera look direction"
	)

	var before_pause: Vector2 = camera_controller.call("current_look_offset")
	GameState.change_state(GameState.PAUSED, {"source": "runtime_smoke_camera"})
	InputService.inject_playback_value(ACTIONS.AIM, Vector2.DOWN)
	await _wait_physics_frames(AIM_FRAMES)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(before_pause) < 0.01,
		"paused gameplay should freeze camera look smoothing"
	)
	GameState.change_state(GameState.PLAYING, {"source": "runtime_smoke_camera"})
	await _wait_physics_frames(CAMERA_LOOK_SETTLE_FRAMES)
	_expect(
		(
			camera_controller.call("current_look_offset") as Vector2
		).distance_to(Vector2.DOWN * max_offset) < 0.1,
		"camera look smoothing should continue after gameplay resumes"
	)
	InputService.inject_playback_value(ACTIONS.AIM, Vector2.ZERO)
	InputService.set_playback_active(false)
	Input.parse_input_event(pointer_event)
	await get_tree().process_frame


func _inject_runtime_key(keycode: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	InputService.debug_inject_input(event)
	await get_tree().process_frame
	await get_tree().physics_frame


func _inject_runtime_joy_axis(
	device_id: int,
	axis: JoyAxis,
	value: float
) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = axis
	event.axis_value = value
	InputService.debug_inject_input(event)
	await get_tree().process_frame
	await get_tree().physics_frame


func _wait_physics_frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().physics_frame


func _expect_weapon_recoil_runtime(
	player: Node2D,
	camera_controller: Node
) -> void:
	var weapon_system: Node = player.get_node_or_null("WeaponSystem")
	_expect(weapon_system != null, "weapon recoil smoke requires WeaponSystem")
	if weapon_system == null:
		return
	_release_active_bullets()
	var original_rng_snapshot: Dictionary = RNG.snapshot()
	var original_player_snapshot: Dictionary = player.call("snapshot")
	var original_weapon_snapshot: Dictionary = weapon_system.call("snapshot")
	var fired_contexts: Array[Dictionary] = []
	var capture_context: Callable = func(context: Dictionary) -> void:
		fired_contexts.append(context.duplicate(true))
	weapon_system.connect("weapon_fired", capture_context)

	var center_direction: Vector2 = player.get("aim_direction")
	RNG.set_run_seed(7331)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true)
	camera_controller.call(
		"play_feedback",
		"weapon_recoil_shake",
		{"recoil_ratio": 0.0}
	)
	_expect(
		not bool(
			camera_controller.call("is_weapon_recoil_shake_emitting")
		),
		"zero recoil should not start weapon camera feedback"
	)
	weapon_system.call(
		"_fire_once",
		weapon_system.call("_effective_runtime_stats")
	)
	_expect(
		fired_contexts.size() == 1,
		"one trigger pull should emit one weapon_fired context"
	)
	var first_context: Dictionary = (
		fired_contexts[0]
		if not fired_contexts.is_empty()
		else {}
	)
	_expect(
		is_equal_approx(float(first_context.get("recoil", 0.0)), 20.0)
		and absf(
			float(first_context.get("spread_angle_degrees", 0.0))
			- 60.0 * pow(0.2, 1.5)
		) < 0.001
		and is_equal_approx(
			float(first_context.get("kickback_initial_speed", 0.0)),
			70.0
		),
		"weapon_fired should expose the resolved recoil snapshot"
	)
	_expect(
		camera_controller != null
		and bool(
			camera_controller.call("is_weapon_recoil_shake_emitting")
		),
		"weapon fire should trigger the dedicated recoil camera emitter"
	)
	var expected_base_amplitude: float = 6.0 * pow(0.2, 0.75)
	_expect(
		absf(
			float(
				camera_controller.call(
					"weapon_recoil_shake_amplitude"
				)
			)
			- expected_base_amplitude
		) < 0.001,
		"weapon recoil camera amplitude should scale from the firing context"
	)
	camera_controller.call(
		"play_feedback",
		"weapon_recoil_shake",
		{"recoil_ratio": 0.1}
	)
	_expect(
		absf(
			float(
				camera_controller.call(
					"weapon_recoil_shake_amplitude"
				)
			)
			- expected_base_amplitude
		) < 0.001,
		"weaker repeated recoil should keep the stronger active amplitude"
	)
	camera_controller.call(
		"play_feedback",
		"weapon_recoil_shake",
		{"recoil_ratio": 0.5}
	)
	_expect(
		absf(
			float(
				camera_controller.call(
					"weapon_recoil_shake_amplitude"
				)
			)
			- 6.0 * pow(0.5, 0.75)
		) < 0.001,
		"stronger repeated recoil should refresh to the stronger amplitude"
	)
	_expect(
		(player.call("weapon_recoil_velocity") as Vector2).dot(
			center_direction
		) < 0.0,
		"weapon fire should add a backward player impulse"
	)
	var first_bullets: Array[Node] = get_tree().get_nodes_in_group(
		"active_bullets"
	)
	_expect(
		first_bullets.size() == 1,
		"basic weapon fire should spawn one projectile"
	)
	var first_direction: Vector2 = Vector2.ZERO
	if not first_bullets.is_empty():
		var first_bullet: Node2D = first_bullets[0] as Node2D
		var first_snapshot: Dictionary = first_bullet.call("snapshot")
		var velocity_dict: Dictionary = first_snapshot.get(
			"velocity",
			{}
		) as Dictionary
		first_direction = Vector2(
			float(velocity_dict.get("x", 0.0)),
			float(velocity_dict.get("y", 0.0))
		).normalized()
		var muzzle_offset: Vector2 = (
			first_bullet.global_position - player.global_position
		)
		_expect(
			muzzle_offset.distance_to(center_direction * 38.0) < 0.01,
			"spread should not move the central muzzle position"
		)
		_expect(
			absf(rad_to_deg(center_direction.angle_to(first_direction)))
			<= float(
				first_context.get("spread_angle_degrees", 0.0)
			) * 0.5 + 0.001,
			"projectile direction should remain inside the resolved spread cone"
		)
	var player_visual: PlayerSlimeVisual = (
		player.get_node_or_null("Visual") as PlayerSlimeVisual
	)
	_expect(
		player_visual != null
		and player_visual.last_impulse_control_count() == 5
		and player_visual.last_impulse_controls_are_contiguous(),
		"real weapon_fired feedback should deform five contiguous front controls"
	)
	_release_active_bullets()

	player.call("restore_snapshot", original_player_snapshot)
	RNG.set_run_seed(7331)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, false)
	weapon_system.call(
		"_fire_once",
		weapon_system.call("_effective_runtime_stats")
	)
	var disabled_bullets: Array[Node] = get_tree().get_nodes_in_group(
		"active_bullets"
	)
	var disabled_direction: Vector2 = Vector2.ZERO
	if not disabled_bullets.is_empty():
		var disabled_snapshot: Dictionary = disabled_bullets[0].call(
			"snapshot"
		)
		var disabled_velocity: Dictionary = disabled_snapshot.get(
			"velocity",
			{}
		) as Dictionary
		disabled_direction = Vector2(
			float(disabled_velocity.get("x", 0.0)),
			float(disabled_velocity.get("y", 0.0))
		).normalized()
	_expect(
		disabled_direction.is_equal_approx(first_direction),
		"screen shake setting should not alter deterministic projectile spread"
	)
	_expect(
		not bool(
			camera_controller.call("is_weapon_recoil_shake_emitting")
		),
		"disabled screen shake should suppress recoil camera feedback"
	)
	_expect(
		(player.call("weapon_recoil_velocity") as Vector2).dot(
			center_direction
		) < 0.0,
		"disabled screen shake should not suppress gameplay kickback"
	)
	_release_active_bullets()

	weapon_system.call("restore_snapshot", original_weapon_snapshot)
	weapon_system.call(
		"apply_modifiers",
		[
			{
				"stat": STATS.SPREAD_ANGLE_MAX,
				"type": "mult",
				"value": 0.0,
			},
		]
	)
	RNG.set_run_seed(9917)
	weapon_system.call(
		"_fire_once",
		weapon_system.call("_effective_runtime_stats")
	)
	var next_roll_after_zero_spread: float = RNG.combat.randf()
	_release_active_bullets()
	RNG.set_run_seed(9917)
	RNG.combat.randf()
	var expected_next_roll: float = RNG.combat.randf()
	_expect(
		is_equal_approx(next_roll_after_zero_spread, expected_next_roll),
		"zero spread should still consume one RNG.combat roll per projectile"
	)

	weapon_system.call("restore_snapshot", original_weapon_snapshot)
	weapon_system.call(
		"apply_modifiers",
		[
			{
				"stat": STATS.BULLET_COUNT,
				"type": "add",
				"value": 2.0,
			},
		]
	)
	var context_count_before_multishot: int = fired_contexts.size()
	player.call("restore_snapshot", original_player_snapshot)
	weapon_system.call(
		"_fire_once",
		weapon_system.call("_effective_runtime_stats")
	)
	_expect(
		fired_contexts.size() == context_count_before_multishot + 1,
		"multi-projectile fire should still emit one recoil context"
	)
	_expect(
		get_tree().get_nodes_in_group("active_bullets").size() == 3,
		"bullet_count should draw and spawn each projectile independently"
	)
	_release_active_bullets()

	if weapon_system.is_connected("weapon_fired", capture_context):
		weapon_system.disconnect("weapon_fired", capture_context)
	weapon_system.call("restore_snapshot", original_weapon_snapshot)
	player.call("restore_snapshot", original_player_snapshot)
	RNG.restore_snapshot(original_rng_snapshot)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, true)


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


func _release_active_bullets() -> void:
	for active_bullet: Node in get_tree().get_nodes_in_group("active_bullets"):
		PoolManager.release(active_bullet)


func _expect_enemy_center_separation(run_loop: Node, player: Node2D) -> void:
	var enemy_data: Dictionary = {
		"max_hp": 6,
		"move_speed": 0.0,
		"gold_reward": 0,
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
	player_stats[STATS.MAX_HP] = 600.0
	player_stats[STATS.HEALTH_REGEN] = 0.0
	player_stats[STATS.MOVE_SPEED] = 0.0
	player_stats[STATS.PLAYER_SEPARATION_RADIUS] = 25.0
	isolated_player.call("configure", player_stats)
	isolated_player.call(
		"configure_runtime_rules",
		DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	)

	var enemy_data: Dictionary = {
		"max_hp": 5,
		"move_speed": 0.0,
		"gold_reward": 0,
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
	_expect(
		is_equal_approx(
			float(isolated_player.call("current_life")),
			player_life_before_contact
		),
		"ordinary player/enemy overlap should never apply contact damage"
	)
	enemy.remove_from_group("active_enemies")
	enemy.queue_free()
	isolated_player.queue_free()


func _expect_enemy_movement_bounds(run_loop: Node, _player: Node2D) -> void:
	var bounds: Rect2 = _map_bounds(run_loop)
	_expect(bounds.size.x > 0.0 and bounds.size.y > 0.0, "enemy movement bounds smoke should read finite map bounds")
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	var enemy: Node2D = _spawn_smoke_enemy(run_loop, "enemy_swarm", "smoke_bounds_enemy")
	_expect(enemy != null, "movement bounds smoke should spawn an enemy")
	if enemy == null:
		return

	var edge_y: float = clampf(0.0, bounds.position.y + 160.0, bounds.end.y - 160.0)
	enemy.set_physics_process(false)
	enemy.global_position = Vector2(bounds.end.x - 2.0, edge_y)
	enemy.call("_move_in_direction", Vector2.RIGHT, 1.0, 2.0)
	_expect(_position_inside_map_boundary(run_loop, enemy.global_position), "enemy movement should stay inside rectangular map bounds")
	_expect(enemy.global_position.x <= bounds.end.x + 0.01, "enemy movement should clamp at the map right edge")

	var snapshot: Dictionary = enemy.call("snapshot")
	snapshot["position"] = {
		"x": bounds.end.x + 240.0,
		"y": bounds.end.y + 240.0,
	}
	snapshot["home_position"] = {
		"x": bounds.end.x + 240.0,
		"y": bounds.end.y + 240.0,
	}
	enemy.call("restore_snapshot", snapshot)
	_expect(_position_inside_map_boundary(run_loop, enemy.global_position), "enemy restore should clamp position inside rectangular map bounds")

	PoolManager.release(enemy)


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
			"second enemy type should keep its scene-authored visual color"
		)


func _expect_enemy_player_targeting(run_loop: Node, player: Node2D) -> void:
	_disable_enemy_physics()
	var chaser: Node2D = _spawn_smoke_enemy(run_loop, "enemy_chaser", "smoke_player_target_chaser")
	var swarm: Node2D = _spawn_smoke_enemy(run_loop, "enemy_swarm", "smoke_player_target_swarm")
	var stalker: Node2D = _spawn_smoke_enemy(run_loop, "enemy_stalker", "smoke_player_target_stalker")
	var bulwark: Node2D = _spawn_smoke_enemy(run_loop, "enemy_bulwark", "smoke_player_target_bulwark")
	var enemies: Array[Node2D] = [chaser, swarm, stalker, bulwark]
	for enemy: Node2D in enemies:
		_expect(enemy != null, "player-targeting smoke should spawn every melee archetype")
	if enemies.any(func(enemy: Node2D) -> bool: return enemy == null):
		for enemy: Node2D in enemies:
			if enemy != null:
				PoolManager.release(enemy)
		return

	var bounds: Rect2 = _map_bounds(run_loop)
	var test_origin: Vector2 = Vector2(
		clampf(player.global_position.x + 220.0, bounds.position.x + 360.0, bounds.end.x - 360.0),
		clampf(player.global_position.y, bounds.position.y + 260.0, bounds.end.y - 260.0)
	)
	player.global_position = test_origin
	chaser.global_position = test_origin + Vector2(220.0, -120.0)
	swarm.global_position = test_origin + Vector2(220.0, 0.0)
	stalker.global_position = swarm.global_position
	bulwark.global_position = test_origin + Vector2(220.0, 120.0)
	for enemy: Node2D in enemies:
		enemy.set_physics_process(true)
	for _index: int in range(8):
		await get_tree().physics_frame

	var chaser_summary: Dictionary = chaser.call("ai_debug_summary")
	var swarm_summary: Dictionary = swarm.call("ai_debug_summary")
	var stalker_summary: Dictionary = stalker.call("ai_debug_summary")
	var bulwark_summary: Dictionary = bulwark.call("ai_debug_summary")
	_expect(swarm.global_position.distance_to(stalker.global_position) >= 4.0, "different enemy types should keep non-damaging center separation")
	var expected_focus: String = String(player.name)
	for summary: Dictionary in [chaser_summary, swarm_summary, stalker_summary]:
		_expect(String(summary.get("focus_target", "")) == expected_focus, "attacking melee archetypes should target only the player")
	var bulwark_focus: String = String(bulwark_summary.get("focus_target", ""))
	_expect(bulwark_focus.is_empty() or bulwark_focus == expected_focus, "home guard should target only the player or its home position")
	_expect(String(chaser_summary.get("profile_id", "")) == "enemy_ai_exploder", "chaser id should use the exploder profile")
	_expect(String(swarm_summary.get("profile_id", "")) == "enemy_ai_melee_swarm", "swarm should use the directional melee profile")
	_expect(String(stalker_summary.get("profile_id", "")) == "enemy_ai_charge_stalker", "stalker should use the player-charge profile")
	_expect(String(bulwark_summary.get("profile_id", "")) == "enemy_ai_ram_bulwark", "bulwark should use the ram profile")
	_expect(String(chaser_summary.get("action", "")) == ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, "chaser should approach the player")
	_expect(String(swarm_summary.get("action", "")) == ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET, "swarm should approach the player")
	_expect(
		[ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET, ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET].has(String(stalker_summary.get("action", ""))),
		"stalker should charge or approach the player"
	)
	_expect(
		[ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET, ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET].has(String(bulwark_summary.get("action", ""))),
		"bulwark should ram or approach the player without a guard-home action"
	)

	var life_before: float = float((swarm.call("snapshot") as Dictionary).get("life_points", 0.0))
	var friendly_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		999.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		stalker,
		swarm,
		String(stalker.call("combat_team_id")),
		String(swarm.call("combat_team_id"))
	)
	var friendly_result: Dictionary = Combat.apply_damage(swarm, friendly_info)
	var life_after: float = float((swarm.call("snapshot") as Dictionary).get("life_points", 0.0))
	_expect(not bool(friendly_result.get("applied", true)), "enemy friendly fire should be rejected")
	_expect(String(friendly_result.get("reason", "")) == "friendly_fire_blocked", "enemy friendly fire should report its rejection reason")
	_expect(is_equal_approx(life_after, life_before), "enemy friendly fire should not change life")

	var legacy_snapshot: Dictionary = swarm.call("snapshot")
	legacy_snapshot["current_action"] = "ai_action_flee_threat"
	legacy_snapshot["action_state"] = "charge_release"
	legacy_snapshot["action_timer"] = 1.0
	swarm.call("restore_snapshot", legacy_snapshot)
	_expect(String((swarm.call("ai_debug_summary") as Dictionary).get("action", "")) == "", "removed legacy action should be cleared during restore")
	await get_tree().physics_frame
	_expect(
		String((swarm.call("ai_debug_summary") as Dictionary).get("action", "")) == ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
		"restored legacy snapshot should choose a current player action on the next decision tick"
	)

	for enemy: Node2D in enemies:
		PoolManager.release(enemy)


func _expect_route_aware_enemy_perception(run_loop: Node, player: Node2D) -> void:
	_disable_enemy_physics()
	var probe: Node = NavigationProbe.new()
	add_child(probe)
	var enemy_rows: Dictionary = run_loop.get("_enemy_rows") as Dictionary
	var origin := Vector2(200.0, 0.0)
	player.global_position = Vector2.ZERO

	var chaser: Node2D = _spawn_smoke_enemy(run_loop, "enemy_chaser", "smoke_navigation_chaser")
	_expect(chaser != null, "navigation smoke should spawn a chaser")
	if chaser == null:
		probe.queue_free()
		return
	chaser.global_position = origin
	probe.set("active_target_position", player.global_position)
	probe.set("next_position", player.global_position)
	probe.set("local_next_position", player.global_position)
	chaser.call("configure", enemy_rows["enemy_chaser"], player, probe)
	chaser.set_physics_process(true)
	var direct_start: Vector2 = chaser.global_position
	await get_tree().physics_frame
	var direct_summary: Dictionary = chaser.call("ai_debug_summary")
	_expect(chaser.global_position.x < direct_start.x, "clear terrain should keep smooth direct pursuit")
	_expect(String(direct_summary.get("perception_state", "")) == "visible", "clear sight inside sight radius should perceive the player")
	_expect(String(direct_summary.get("navigation_mode", "")) == "direct", "clear pursuit should report direct navigation")

	chaser.set_physics_process(false)
	chaser.global_position = Vector2(400.0, 0.0)
	probe.set("line_of_sight", false)
	probe.set("corridor_clear", false)
	probe.set("reachable", true)
	probe.set("path_distance", 480.0)
	probe.set("next_position", Vector2(400.0, 160.0))
	chaser.call("configure", enemy_rows["enemy_chaser"], player, probe)
	chaser.set_physics_process(true)
	var detour_start: Vector2 = chaser.global_position
	for _index: int in range(4):
		await get_tree().physics_frame
	var detour_summary: Dictionary = chaser.call("ai_debug_summary")
	_expect(chaser.global_position.y > detour_start.y, "blocked pursuit should follow the legal flow waypoint instead of pushing straight into the wall")
	_expect(String(detour_summary.get("perception_state", "")) == "path_aware", "nearby player behind terrain should be sensed by path distance")
	_expect(String(detour_summary.get("navigation_mode", "")) == "flow_field", "blocked pursuit should report shared flow-field navigation")

	chaser.set_physics_process(false)
	chaser.global_position = Vector2(400.0, 0.0)
	probe.set("path_distance", 501.0)
	chaser.call("configure", enemy_rows["enemy_chaser"], player, probe)
	chaser.set_physics_process(true)
	await get_tree().physics_frame
	_expect(
		String((chaser.call("ai_debug_summary") as Dictionary).get("perception_state", "")) == "unaware",
		"player beyond path-awareness radius should not be sensed through terrain"
	)

	chaser.set_physics_process(false)
	chaser.global_position = origin
	probe.set("line_of_sight", true)
	probe.set("corridor_clear", true)
	probe.set("reachable", true)
	probe.set("path_distance", 200.0)
	chaser.call("configure", enemy_rows["enemy_chaser"], player, probe)
	chaser.set_physics_process(true)
	await get_tree().physics_frame
	var remembered_position: Vector2 = player.global_position
	probe.set("line_of_sight", false)
	probe.set("corridor_clear", false)
	probe.set("reachable", false)
	player.global_position = Vector2(-600.0, 600.0)
	for _index: int in range(12):
		await get_tree().physics_frame
	var memory_summary: Dictionary = chaser.call("ai_debug_summary")
	var memory_position: Dictionary = memory_summary.get("last_known_position", {}) as Dictionary
	_expect(String(memory_summary.get("perception_state", "")) == "memory", "lost perception should enter short-term memory")
	_expect(
		Vector2(float(memory_position.get("x", INF)), float(memory_position.get("y", INF))).is_equal_approx(remembered_position),
		"memory pursuit should retain the last known position instead of reading the live player position"
	)
	for _index: int in range(100):
		await get_tree().physics_frame
	_expect(
		String((chaser.call("ai_debug_summary") as Dictionary).get("perception_state", "")) == "unaware",
		"memory pursuit should stop after the configured 1.5 seconds"
	)
	PoolManager.release(chaser)

	player.global_position = Vector2.ZERO
	probe.set("active_target_position", player.global_position)
	probe.set("line_of_sight", false)
	probe.set("corridor_clear", false)
	probe.set("reachable", false)
	probe.set("local_reachable", true)
	probe.set("local_next_position", Vector2(520.0, 160.0))
	var bulwark: Node2D = _spawn_smoke_enemy(run_loop, "enemy_bulwark", "smoke_navigation_bulwark")
	_expect(bulwark != null, "navigation smoke should spawn a ram bulwark")
	if bulwark != null:
		bulwark.global_position = Vector2(200.0, 0.0)
		bulwark.call("configure", enemy_rows["enemy_bulwark"], player, probe)
		bulwark.global_position = Vector2(520.0, 0.0)
		bulwark.set_physics_process(true)
		for _index: int in range(4):
			await get_tree().physics_frame
		var bulwark_summary: Dictionary = bulwark.call("ai_debug_summary")
		_expect(
			String(bulwark_summary.get("action", ""))
			== ENEMY_AI_ACTIONS.AI_ACTION_APPROACH_TARGET,
			"unaware bulwark should retain its generic approach action"
		)
		_expect(
			String(bulwark_summary.get("navigation_mode", ""))
			!= "local_astar",
			"ram bulwark should not execute removed return-home navigation"
		)
		PoolManager.release(bulwark)

	probe.set("reachable", true)
	probe.set("path_distance", 300.0)
	probe.set("local_reachable", true)
	var stalker: Node2D = _spawn_smoke_enemy(run_loop, "enemy_stalker", "smoke_navigation_stalker")
	_expect(stalker != null, "navigation smoke should spawn a charge stalker")
	if stalker != null:
		stalker.global_position = Vector2(300.0, 0.0)
		stalker.call("configure", enemy_rows["enemy_stalker"], player, probe)
		stalker.set_physics_process(true)
		await get_tree().physics_frame
		_expect(
			String((stalker.call("ai_debug_summary") as Dictionary).get("action", "")) != ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET,
			"charge should not start through a blocked corridor"
		)
		PoolManager.release(stalker)

	var spitter: Node2D = _spawn_smoke_enemy(run_loop, "enemy_spitter", "smoke_navigation_spitter")
	_expect(spitter != null, "navigation smoke should spawn a ranged spitter")
	if spitter != null:
		spitter.global_position = Vector2(320.0, 0.0)
		spitter.call("configure", enemy_rows["enemy_spitter"], player, probe)
		spitter.set_physics_process(true)
		var bullets_before: int = _pool_stat(POOL_IDS.BULLET_BASIC, "acquired")
		for _index: int in range(100):
			await get_tree().physics_frame
		_expect(_pool_stat(POOL_IDS.BULLET_BASIC, "acquired") == bullets_before, "ranged enemy should not fire through blocked terrain")
		PoolManager.release(spitter)
	probe.queue_free()


func _expect_explicit_enemy_attacks(
	run_loop: Node,
	player: Node2D
) -> void:
	var player_snapshot: Dictionary = player.call("snapshot")
	var bounds: Rect2 = _map_bounds(run_loop)
	var origin := Vector2(
		clampf(0.0, bounds.position.x + 480.0, bounds.end.x - 480.0),
		clampf(0.0, bounds.position.y + 480.0, bounds.end.y - 480.0)
	)
	await _expect_all_enemy_bodies_are_harmless(
		run_loop,
		player,
		origin
	)
	_expect_prearmed_exploder_defeat_rewards(
		run_loop,
		player,
		origin
	)
	_expect_explosion_terrain_blocking(
		run_loop,
		player,
		origin
	)
	player.call("debug_reset_transient_state", origin + Vector2(500.0, 0.0))

	var first: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_chaser",
		origin,
		60
	)
	var chain_target: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_chaser",
		origin + Vector2(48.0, 0.0),
		50
	)
	var nonlethal_target: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_chaser",
		origin + Vector2(36.0, 0.0),
		40
	)
	var later_serial_victim: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_swarm",
		origin + Vector2(72.0, 0.0),
		30
	)
	var earlier_serial_victim: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_swarm",
		origin + Vector2(84.0, 0.0),
		20
	)
	var chain_nodes: Array[Node2D] = [
		first,
		chain_target,
		nonlethal_target,
		later_serial_victim,
		earlier_serial_victim,
	]
	if chain_nodes.any(func(node: Node2D) -> bool: return node == null):
		_expect(false, "explicit explosion smoke should instantiate all targets")
		for node: Node2D in chain_nodes:
			if node != null:
				node.queue_free()
		player.call("restore_snapshot", player_snapshot)
		return

	for node: Node2D in chain_nodes:
		node.call(
			"debug_configure_training_target",
			200.0 if node == nonlethal_target else (
				12.0 if node == first or node == chain_target else 6.0
			),
			node.global_position
		)
	var victim_serials: Array[int] = []
	var victim_causes: Array[String] = []
	var detonation_events: Array[Dictionary] = []
	for victim: Node2D in [later_serial_victim, earlier_serial_victim]:
		victim.connect(
			"defeated",
			func(
				defeated_enemy: Node,
				_gold_reward: int,
				counts_as_kill: bool,
				drops_rewards: bool,
				cause_id: String
			) -> void:
				victim_serials.append(
					int(defeated_enemy.call("runtime_spawn_serial"))
				)
				victim_causes.append(cause_id)
				_expect(
					counts_as_kill and drops_rewards,
					"ordinary enemies killed by an explosion should keep kill and reward credit"
				)
		)
	for exploder: Node2D in [first, chain_target]:
		exploder.connect(
			"defeated",
			func(
				_defeated_enemy: Node,
				_gold_reward: int,
				counts_as_kill: bool,
				drops_rewards: bool,
				cause_id: String
			) -> void:
				detonation_events.append({
					"counts_as_kill": counts_as_kill,
					"drops_rewards": drops_rewards,
					"cause_id": cause_id,
				})
		)

	first.call("_arm_explosion", false)
	_expect(bool(first.call("is_armed")), "exploder should become armed immediately")
	var frozen_windup: float = float(
		(first.call("snapshot") as Dictionary).get("action_timer", 0.0)
	)
	GameState.change_state(GameState.PAUSED, {"source": "runtime_attack_pause"})
	first.call("_physics_process", 1.0)
	_expect(
		is_equal_approx(
			float(
				(first.call("snapshot") as Dictionary).get(
					"action_timer",
					0.0
				)
			),
			frozen_windup
		),
		"enemy attack windup should freeze outside PLAYING"
	)
	GameState.change_state(GameState.PLAYING, {"source": "runtime_attack_resume"})
	var armed_damage: Dictionary = Combat.apply_damage(
		first,
		DAMAGE_INFO_SCRIPT.new().setup(
			9999.0,
			ELEMENTS.ELEMENT_NEUTRAL,
			player,
			first,
			"team_player",
			"team_enemy"
		)
	)
	_expect(
		not bool(armed_damage.get("applied", true)),
		"armed exploder should reject damage immediately"
	)
	var pre_detonation_target_life: float = float(
		nonlethal_target.call("current_life")
	)
	var armed_source_damage: Dictionary = Combat.apply_damage(
		nonlethal_target,
		DAMAGE_INFO_SCRIPT.new().setup(
			1.0,
			ELEMENTS.ELEMENT_NEUTRAL,
			first,
			nonlethal_target,
			"team_enemy",
			"team_enemy"
		)
	)
	_expect(
		not bool(armed_source_damage.get("applied", true))
		and String(armed_source_damage.get("reason", "")) == "friendly_fire_blocked"
		and is_equal_approx(
			float(nonlethal_target.call("current_life")),
			pre_detonation_target_life
		),
		"armed exploder should not bypass friendly fire before detonation"
	)
	for _index: int in range(42):
		await get_tree().physics_frame
	_expect(
		bool(chain_target.call("is_armed")),
		"a lethal explosion should arm another exploder"
	)
	_expect(
		not bool(nonlethal_target.call("is_armed"))
		and float(nonlethal_target.call("current_life")) > 0.0,
		"a nonlethal explosion should only reduce exploder life"
	)
	_expect(
		victim_serials == [20, 30],
		"explosion victims should settle by runtime_spawn_serial"
	)
	var all_victim_causes_match: bool = true
	for cause_id: String in victim_causes:
		if cause_id != ENEMY_DEFEAT_CAUSES.ENEMY_EXPLOSION:
			all_victim_causes_match = false
			break
	_expect(
		all_victim_causes_match,
		"ordinary explosion victims should report enemy_explosion"
	)
	_expect(
		detonation_events.size() == 1,
		"the chained exploder should not recurse in the source detonation frame"
	)
	var chain_snapshot: Dictionary = chain_target.call("snapshot")
	_expect(
		float(chain_snapshot.get("action_timer", 0.0)) > 0.0,
		"each chain generation should retain a full delayed windup"
	)
	for _index: int in range(45):
		await get_tree().physics_frame
	_expect(
		detonation_events.size() >= 2,
		"the chained exploder should detonate after its own windup"
	)
	for event: Dictionary in detonation_events:
		_expect(
			not bool(event.get("counts_as_kill", true))
			and not bool(event.get("drops_rewards", true))
			and String(event.get("cause_id", ""))
			== ENEMY_DEFEAT_CAUSES.EXPLODER_DETONATION,
			"every actual exploder detonation should suppress kill and reward credit"
		)

	for node: Node2D in chain_nodes:
		if is_instance_valid(node):
			_release_direct_attack_enemy(node)
	await get_tree().process_frame

	player.call("debug_reset_transient_state", origin + Vector2(40.0, 0.0))
	var melee: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_swarm",
		origin,
		70
	)
	if melee != null:
		melee.set_physics_process(false)
		melee.set("_current_action", ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
		melee.call("_start_melee_attack")
		player.global_position = origin + Vector2(-40.0, 0.0)
		var defense_before_miss: float = _player_total_defense(player)
		melee.call("_update_attack_state", 0.24)
		_expect(
			is_equal_approx(
				_player_total_defense(player),
				defense_before_miss
			),
			"melee should use its locked windup direction and miss a player who sidesteps behind"
		)
		_expect(
			float(
				(melee.call("snapshot") as Dictionary).get(
					"attack_cooldown_remaining",
					0.0
				)
			) > 0.0,
			"a missed melee should still enter cooldown"
		)
		player.call(
			"debug_reset_transient_state",
			origin + Vector2(40.0, 0.0)
		)
		var defense_before_hit: float = _player_total_defense(player)
		melee.set("_current_action", ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
		melee.call("_start_melee_attack")
		melee.call("_update_attack_state", 0.24)
		_expect(
			_player_total_defense(player) < defense_before_hit,
			"directional melee should damage a player who remains in its front arc"
		)
		_release_direct_attack_enemy(melee)

	player.call("debug_reset_transient_state", origin + Vector2(100.0, 0.0))
	var charge_wall := StaticBody2D.new()
	charge_wall.position = origin + Vector2(30.0, 0.0)
	var charge_wall_shape := CollisionShape2D.new()
	var charge_wall_rectangle := RectangleShape2D.new()
	charge_wall_rectangle.size = Vector2(4.0, 160.0)
	charge_wall_shape.shape = charge_wall_rectangle
	charge_wall.add_child(charge_wall_shape)
	(run_loop.get_node("ActiveWorld") as Node).add_child(charge_wall)
	var blocked_stalker: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_stalker",
		origin,
		79
	)
	if blocked_stalker != null:
		blocked_stalker.set_physics_process(false)
		blocked_stalker.set(
			"_current_action",
			ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
		)
		blocked_stalker.call("_start_charge")
		blocked_stalker.call("_update_attack_state", 0.34)
		var blocked_defense_before: float = _player_total_defense(player)
		blocked_stalker.call("_update_attack_state", 0.42)
		var blocked_summary: Dictionary = blocked_stalker.call(
			"ai_debug_summary"
		) as Dictionary
		_expect(
			String(blocked_summary.get("action_state", "")).is_empty(),
			"charge should end immediately when it collides with terrain"
		)
		_expect(
			is_equal_approx(
				_player_total_defense(player),
				blocked_defense_before
			),
			"wall-stopped charge should not sweep damage through terrain"
		)
		_release_direct_attack_enemy(blocked_stalker)
	charge_wall.queue_free()
	await get_tree().physics_frame

	var stalker: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_stalker",
		origin,
		80
	)
	if stalker != null:
		stalker.set_physics_process(false)
		stalker.set("_current_action", ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
		stalker.call("_start_charge")
		stalker.call("_update_attack_state", 0.34)
		var stalker_defense_before: float = _player_total_defense(player)
		stalker.call("_update_attack_state", 0.4)
		var stalker_defense_after: float = _player_total_defense(player)
		var stalker_position_after_hit: Vector2 = stalker.global_position
		stalker.call("_update_attack_state", 0.01)
		_expect(
			stalker_defense_after < stalker_defense_before,
			"stalker release sweep should hit a crossed player"
		)
		_expect(
			is_equal_approx(
				_player_total_defense(player),
				stalker_defense_after
			),
			"one charge release should damage the player at most once"
		)
		_expect(
			stalker.global_position.x > stalker_position_after_hit.x,
			"stalker should continue its charge after a hit"
		)
		_release_direct_attack_enemy(stalker)

	player.call("debug_reset_transient_state", origin + Vector2(50.0, 0.0))
	player.call("debug_set_invulnerable", true)
	var avoided_bulwark: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_bulwark",
		origin,
		89
	)
	if avoided_bulwark != null:
		avoided_bulwark.set_physics_process(false)
		avoided_bulwark.set(
			"_current_action",
			ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
		)
		avoided_bulwark.call("_start_charge")
		avoided_bulwark.call("_update_attack_state", 0.48)
		avoided_bulwark.call("_update_attack_state", 0.45)
		_expect(
			is_zero_approx(
				float(player.call("external_knockback_remaining"))
			),
			"blocked bulwark damage should not apply external knockback"
		)
		_release_direct_attack_enemy(avoided_bulwark)
	player.call("debug_reset_transient_state", origin + Vector2(50.0, 0.0))
	var bulwark: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_bulwark",
		origin,
		90
	)
	if bulwark != null:
		bulwark.set_physics_process(false)
		bulwark.set("_current_action", ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
		bulwark.call("_start_charge")
		bulwark.call("_update_attack_state", 0.48)
		bulwark.call("_update_attack_state", 0.45)
		var bulwark_summary: Dictionary = bulwark.call("ai_debug_summary")
		_expect(
			String(bulwark_summary.get("action_state", "")).is_empty(),
			"bulwark should stop its charge immediately after a hit"
		)
		_expect(
			float(player.call("external_knockback_remaining")) > 0.0,
			"successful bulwark damage should apply external player knockback"
		)
		_release_direct_attack_enemy(bulwark)

	player.call("restore_snapshot", player_snapshot)
	await get_tree().process_frame


func _expect_all_enemy_bodies_are_harmless(
	run_loop: Node,
	player: Node2D,
	origin: Vector2
) -> void:
	var original_player_snapshot: Dictionary = player.call("snapshot")
	var enemy_ids: Array[String] = [
		"enemy_chaser",
		"enemy_swarm",
		"enemy_stalker",
		"enemy_bulwark",
		"enemy_spitter",
	]
	for index: int in range(enemy_ids.size()):
		player.call("debug_reset_transient_state", origin)
		var enemy: Node2D = _create_direct_attack_enemy(
			run_loop,
			player,
			enemy_ids[index],
			origin,
			100 + index
		)
		_expect(enemy != null, "%s should instantiate for overlap smoke" % enemy_ids[index])
		if enemy == null:
			continue
		var defense_before: float = _player_total_defense(player)
		for _frame: int in range(2):
			await get_tree().physics_frame
		_expect(
			is_equal_approx(
				_player_total_defense(player),
				defense_before
			),
			"%s body overlap should not deal contact damage" % enemy_ids[index]
		)
		_release_direct_attack_enemy(enemy)
	player.call("restore_snapshot", original_player_snapshot)


func _expect_prearmed_exploder_defeat_rewards(
	run_loop: Node,
	player: Node2D,
	origin: Vector2
) -> void:
	var exploder: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_chaser",
		origin,
		120
	)
	_expect(exploder != null, "pre-armed exploder should instantiate")
	if exploder == null:
		return
	exploder.set_physics_process(false)
	var defeat_events: Array[Dictionary] = []
	exploder.connect(
		"defeated",
		func(
			_enemy: Node,
			_gold_reward: int,
			counts_as_kill: bool,
			drops_rewards: bool,
			cause_id: String
		) -> void:
			defeat_events.append({
				"counts_as_kill": counts_as_kill,
				"drops_rewards": drops_rewards,
				"cause_id": cause_id,
			})
	)
	var damage_result: Dictionary = Combat.apply_damage(
		exploder,
		DAMAGE_INFO_SCRIPT.new().setup(
			9999.0,
			ELEMENTS.ELEMENT_NEUTRAL,
			player,
			exploder,
			"team_player",
			"team_enemy"
		)
	)
	_expect(
		bool(damage_result.get("defeated", false)),
		"exploder should be killable before entering windup"
	)
	_expect(
		defeat_events.size() == 1
		and bool(defeat_events[0].get("counts_as_kill", false))
		and bool(defeat_events[0].get("drops_rewards", false))
		and String(defeat_events[0].get("cause_id", ""))
		== ENEMY_DEFEAT_CAUSES.PLAYER_DAMAGE,
		"pre-windup exploder defeat should keep kill and reward credit"
	)


func _expect_explosion_terrain_blocking(
	run_loop: Node,
	player: Node2D,
	origin: Vector2
) -> void:
	var player_snapshot: Dictionary = player.call("snapshot")
	player.call("debug_reset_transient_state", origin + Vector2(40.0, 0.0))
	var probe := NavigationProbe.new()
	probe.line_of_sight = false
	run_loop.add_child(probe)
	var source: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_chaser",
		origin,
		130,
		probe
	)
	var victim: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_swarm",
		origin + Vector2(30.0, 0.0),
		131,
		probe
	)
	_expect(
		source != null and victim != null,
		"terrain-blocked explosion fixture should instantiate"
	)
	if source == null or victim == null:
		_release_direct_attack_enemy(source)
		_release_direct_attack_enemy(victim)
		player.call("restore_snapshot", player_snapshot)
		probe.queue_free()
		return
	source.set_physics_process(false)
	victim.set_physics_process(false)
	var defense_before: float = _player_total_defense(player)
	var victim_life_before: float = float(victim.call("current_life"))
	source.call("_arm_explosion", false)
	source.call("_update_armed_state", 0.65)
	_expect(
		is_equal_approx(
			_player_total_defense(player),
			defense_before
		),
		"terrain line of sight should block explosion damage to the player"
	)
	_expect(
		is_equal_approx(
			float(victim.call("current_life")),
			victim_life_before
		),
		"terrain line of sight should block explosion damage to enemies"
	)
	_release_direct_attack_enemy(victim)
	player.call("restore_snapshot", player_snapshot)
	probe.queue_free()


func _expect_world_event_defense_targeting(
	run_loop: Node,
	player: Node2D
) -> void:
	var active_world: Node = run_loop.get_node_or_null("ActiveWorld")
	var packed: PackedScene = WORLD_EVENT_DEFENSE_SCENE
	var raw_event: Node = packed.instantiate()
	_expect(
		raw_event is WorldEventInteractable,
		"defense event scene should instantiate for combat smoke"
	)
	if not raw_event is WorldEventInteractable or active_world == null:
		raw_event.queue_free()
		return
	var event_node: WorldEventInteractable = (
		raw_event as WorldEventInteractable
	)
	active_world.add_child(event_node)
	var target: WorldEventDefenseTarget = (
		event_node.defense_target()
	)
	_expect(
		target != null,
		"defense event should expose its combat target"
	)
	if target == null:
		event_node.queue_free()
		return
	var player_snapshot: Dictionary = player.call("snapshot")
	var origin: Vector2 = player.global_position + Vector2(900.0, 0.0)
	var context: Dictionary = {
		"event_instance_id": "runtime_defense_event",
		"primary_target": target,
		"damage_target_groups": [
			DAMAGE_TARGET_GROUPS.ACTIVE_PROJECTILE_BLOCKERS,
			DAMAGE_TARGET_GROUPS
			.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS,
			DAMAGE_TARGET_GROUPS.ACTIVE_PLAYER,
		],
	}

	event_node.global_position = origin + Vector2(40.0, 0.0)
	target.configure(
		"runtime_defense_event",
		1200.0,
		48.0,
		DAMAGE_TARGET_GROUPS
		.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS
	)
	target.activate()
	player.call(
		"debug_reset_transient_state",
		origin + Vector2(400.0, 0.0)
	)
	var melee: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_swarm",
		origin,
		310,
		null,
		context
	)
	if melee != null:
		melee.set_physics_process(false)
		melee.set(
			"_current_action",
			ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK
		)
		var health_before: float = target.current_health()
		melee.call("_start_melee_attack")
		melee.call("_update_attack_state", 0.24)
		_expect(
			target.current_health() < health_before,
			"event melee enemy should damage the defense target"
		)
		_release_direct_attack_enemy(melee)

	target.configure(
		"runtime_defense_event",
		1200.0,
		48.0,
		DAMAGE_TARGET_GROUPS
		.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS
	)
	target.activate()
	event_node.global_position = origin + Vector2(90.0, 0.0)
	player.call(
		"debug_reset_transient_state",
		origin + Vector2(45.0, 0.0)
	)
	var charge: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_stalker",
		origin,
		311,
		null,
		context
	)
	if charge != null:
		charge.set_physics_process(false)
		charge.set(
			"_current_action",
			ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
		)
		var target_before: float = target.current_health()
		var player_before: float = _player_total_defense(player)
		charge.call("_start_charge")
		charge.call("_update_attack_state", 0.34)
		charge.call("_update_attack_state", 0.5)
		_expect(
			target.current_health() < target_before,
			"event charge enemy should damage the defense target"
		)
		_expect(
			_player_total_defense(player) < player_before,
			"event charge should still damage a crossed player"
		)
		_release_direct_attack_enemy(charge)

	target.configure(
		"runtime_defense_event",
		1200.0,
		48.0,
		DAMAGE_TARGET_GROUPS
		.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS
	)
	target.activate()
	event_node.global_position = origin + Vector2(55.0, 0.0)
	player.call(
		"debug_reset_transient_state",
		origin + Vector2(70.0, 0.0)
	)
	var exploder: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_chaser",
		origin,
		312,
		null,
		context
	)
	if exploder != null:
		exploder.set_physics_process(false)
		var target_before: float = target.current_health()
		var player_before: float = _player_total_defense(player)
		exploder.call("_arm_explosion", false)
		exploder.call("_update_armed_state", 0.7)
		_expect(
			target.current_health() < target_before,
			"event explosion should damage the defense target"
		)
		_expect(
			_player_total_defense(player) < player_before,
			"event explosion should still damage a nearby player"
		)

	var committed_exploder: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_chaser",
		origin,
		314,
		null,
		context
	)
	if committed_exploder != null:
		committed_exploder.set_physics_process(false)
		committed_exploder.call("_arm_explosion", false)
		var armed_before: Dictionary = (
			committed_exploder.call("ai_debug_summary") as Dictionary
		)
		committed_exploder.call(
			"convert_to_player_target",
			player
		)
		var armed_after: Dictionary = (
			committed_exploder.call("ai_debug_summary") as Dictionary
		)
		_expect(
			bool(armed_after.get("armed", false))
			and (
				String(armed_after.get("action_state", ""))
				== String(armed_before.get("action_state", ""))
			)
			and is_equal_approx(
				float(armed_after.get("attack_time_remaining", 0.0)),
				float(armed_before.get("attack_time_remaining", -1.0))
			),
			"event cleanup should preserve an armed explosion commitment"
		)
		_release_direct_attack_enemy(committed_exploder)

	target.configure(
		"runtime_defense_event",
		1200.0,
		48.0,
		DAMAGE_TARGET_GROUPS
		.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS
	)
	target.activate()
	event_node.global_position = origin + Vector2(90.0, 0.0)
	player.call(
		"debug_reset_transient_state",
		origin + Vector2(180.0, 0.0)
	)
	var gunner: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_spitter",
		origin,
		313,
		null,
		context
	)
	if gunner != null:
		gunner.set_physics_process(false)
		gunner.set(
			"_current_action",
			ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
		)
		var target_before: float = target.current_health()
		var player_before: float = _player_total_defense(player)
		gunner.call("_fire_ranged_projectile", Vector2.RIGHT)
		for _frame_index: int in range(40):
			await get_tree().physics_frame
		_expect(
			target.current_health() < target_before,
			"event projectile should damage the defense target"
		)
		_expect(
			is_equal_approx(
				_player_total_defense(player),
				player_before
			),
			"shared projectile should hit the nearer defense target only"
		)
		_release_direct_attack_enemy(gunner)

	var committed_gunner: Node2D = _create_direct_attack_enemy(
		run_loop,
		player,
		"enemy_spitter",
		origin,
		315,
		null,
		context
	)
	if committed_gunner != null:
		committed_gunner.set_physics_process(false)
		committed_gunner.set(
			"_current_action",
			ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
		)
		committed_gunner.call(
			"_start_ranged_burst",
			Vector2.RIGHT
		)
		committed_gunner.call("_update_attack_state", 0.32)
		var burst_before: Dictionary = (
			committed_gunner.call("ai_debug_summary") as Dictionary
		)
		committed_gunner.call(
			"convert_to_player_target",
			player
		)
		var burst_after: Dictionary = (
			committed_gunner.call("ai_debug_summary") as Dictionary
		)
		_expect(
			String(burst_after.get("action_state", ""))
			== "ranged_burst"
			and int(burst_after.get("burst_shots_remaining", 0))
			== int(burst_before.get("burst_shots_remaining", -1))
			and is_equal_approx(
				float(burst_after.get("attack_time_remaining", 0.0)),
				float(burst_before.get("attack_time_remaining", -1.0))
			),
			"event cleanup should preserve a committed ranged burst"
		)
		_expect(
			not (
				burst_after.get("damage_target_groups", []) as Array
			).has(
				DAMAGE_TARGET_GROUPS
				.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS
			),
			"event cleanup should retarget remaining burst shots to player groups"
		)
		_release_direct_attack_enemy(committed_gunner)
		for raw_bullet: Node in get_tree().get_nodes_in_group(
			"active_bullets"
		):
			PoolManager.release(raw_bullet)

	target.deactivate()
	player.call("restore_snapshot", player_snapshot)
	event_node.queue_free()
	await get_tree().process_frame


func _create_direct_attack_enemy(
	run_loop: Node,
	player: Node2D,
	enemy_id: String,
	position: Vector2,
	serial: int,
	navigation_provider: Node = null,
	spawn_context: Dictionary = {}
) -> Node2D:
	var enemy_rows: Dictionary = run_loop.get("_enemy_rows") as Dictionary
	if not enemy_rows.has(enemy_id):
		return null
	var enemy_data: Dictionary = enemy_rows[enemy_id] as Dictionary
	var enemy: Node2D = PoolManager.acquire(
		String(enemy_data.get("pool_id", ""))
	) as Node2D
	var active_world: Node = run_loop.get_node_or_null("ActiveWorld")
	if enemy == null or active_world == null:
		return null
	var old_parent: Node = enemy.get_parent()
	if old_parent != null and old_parent != active_world:
		old_parent.remove_child(enemy)
	if enemy.get_parent() != active_world:
		active_world.add_child(enemy)
	enemy.global_position = position
	enemy.call(
		"configure",
		enemy_data,
		player,
		navigation_provider,
		{
			"health_multiplier": 1.0,
			"damage_multiplier": 1.0,
		},
		spawn_context
	)
	enemy.call("set_runtime_spawn_serial", serial)
	return enemy


func _release_direct_attack_enemy(enemy: Node2D) -> void:
	if (
		enemy != null
		and is_instance_valid(enemy)
		and enemy.is_in_group("active_enemies")
	):
		PoolManager.release(enemy)


func _player_total_defense(player: Node2D) -> float:
	return (
		float(player.call("current_life"))
		+ float(player.call("current_shield"))
		+ float(player.call("current_overshield"))
	)


func _expect_ranged_enemy_projectile_damage(run_loop: Node, player: Node2D) -> void:
	_disable_enemy_physics()
	var spitter: Node2D = _spawn_smoke_enemy(run_loop, "enemy_spitter", "smoke_ranged_spitter")
	_expect(spitter != null, "ranged smoke should spawn the spitter enemy")
	if spitter == null:
		return

	var bounds: Rect2 = _map_bounds(run_loop)
	var test_position: Vector2 = Vector2(
		clampf(player.global_position.x + 120.0, bounds.position.x + 360.0, bounds.end.x - 360.0),
		clampf(player.global_position.y, bounds.position.y + 260.0, bounds.end.y - 260.0)
	)
	player.global_position = test_position
	spitter.global_position = test_position + Vector2(320.0, 0.0)
	_ranged_commit_times.clear()
	_ranged_windup_contexts.clear()
	var windup_callable: Callable = Callable(
		self,
		"_on_ranged_windup_started"
	)
	var commit_callable: Callable = Callable(
		self,
		"_on_ranged_attack_committed"
	)
	spitter.connect("attack_windup_started", windup_callable)
	spitter.connect("attack_committed", commit_callable)
	spitter.set_physics_process(true)
	var reached_windup: bool = false
	for _index: int in range(120):
		await get_tree().physics_frame
		var summary: Dictionary = spitter.call("ai_debug_summary")
		if String(summary.get("action_state", "")) == "ranged_windup":
			reached_windup = true
			break
	_expect(reached_windup, "ranged enemy should enter its muzzle-charge windup")
	_expect(
		String(
			(spitter.call("ai_debug_summary") as Dictionary).get(
				"focus_target",
				""
			)
		) == String(player.name),
		"ranged enemy should target only the player"
	)
	var windup_snapshot: Dictionary = spitter.call("snapshot")
	var locked_direction: Vector2 = _dict_to_vector(
		windup_snapshot.get("locked_direction", {}),
		Vector2.ZERO
	)
	var locked_position: Vector2 = spitter.global_position
	_expect(
		int(
			(spitter.call("ai_debug_summary") as Dictionary).get(
				"burst_shots_remaining",
				0
			)
		) == 4,
		"ranged AI debug summary should expose four remaining windup shots"
	)
	_expect(
		_ranged_windup_contexts.size() == 1,
		"one burst should emit exactly one ranged windup event"
	)
	if not _ranged_windup_contexts.is_empty():
		_expect(
			not _ranged_windup_contexts[0].has("scale"),
			"ranged windup should not expose trajectory geometry"
		)
		_expect(
			is_equal_approx(
				float(_ranged_windup_contexts[0].get("duration", 0.0)),
				0.32
			),
			"ranged fire preparation should keep the 0.32 second windup"
		)
	var frozen_timer: float = float(windup_snapshot.get("action_timer", 0.0))
	GameState.change_state(GameState.PAUSED, {"source": "runtime_ranged_pause"})
	spitter.call("_physics_process", 0.5)
	_expect(
		is_equal_approx(
			float(
				(spitter.call("snapshot") as Dictionary).get(
					"action_timer",
					0.0
				)
			),
			frozen_timer
		),
		"pause should freeze the ranged windup timer"
	)
	GameState.change_state(
		GameState.PLAYING,
		{"source": "runtime_ranged_resume"}
	)
	if not locked_direction.is_zero_approx():
		var perpendicular: Vector2 = Vector2(
			-locked_direction.y,
			locked_direction.x
		)
		var sidestep_target: Vector2 = test_position + perpendicular * 180.0
		player.global_position = Vector2(
			clampf(
				sidestep_target.x,
				bounds.position.x + 80.0,
				bounds.end.x - 80.0
			),
			clampf(
				sidestep_target.y,
				bounds.position.y + 80.0,
				bounds.end.y - 80.0
			)
		)

	if player.has_method("debug_clear_invulnerability"):
		player.call("debug_clear_invulnerability")
	_release_active_bullets()
	var bullets_before: int = _pool_stat(POOL_IDS.BULLET_BASIC, "acquired")
	for _index: int in range(90):
		await get_tree().physics_frame
		if _ranged_commit_times.size() >= 4:
			break
	_expect(
		_ranged_commit_times.size() == 4,
		"ranged enemy should commit exactly four shots per burst"
	)
	_expect(
		_pool_stat(POOL_IDS.BULLET_BASIC, "acquired") - bullets_before == 4,
		"one ranged burst should acquire exactly four shared bullets"
	)
	for index: int in range(1, _ranged_commit_times.size()):
		_expect(
			absf(
				_ranged_commit_times[index]
				- _ranged_commit_times[index - 1]
				- 0.12
			) <= 0.035,
			"ranged burst shots should keep the configured 0.12 second interval"
		)
	_expect(
		spitter.global_position.distance_to(locked_position) < 0.1,
		"ranged enemy should stop moving throughout windup and burst"
	)
	var post_burst_summary: Dictionary = spitter.call("ai_debug_summary")
	_expect(
		int(post_burst_summary.get("burst_shots_remaining", -1)) == 0,
		"ranged burst should clear its remaining shot count"
	)
	_expect(
		float(post_burst_summary.get("attack_cooldown_remaining", 0.0))
		>= 0.9,
		"ranged burst should enter its 0.95 second cooldown"
	)
	var active_enemy_bullets: Array[Node] = []
	for bullet: Node in get_tree().get_nodes_in_group("active_bullets"):
		var candidate_snapshot: Dictionary = bullet.call("snapshot")
		if String(candidate_snapshot.get("source_team", "")) == TEAM_ENEMY:
			active_enemy_bullets.append(bullet)
	_expect(
		not active_enemy_bullets.is_empty(),
		"sidestepping the locked direction should leave enemy bullets active"
	)
	var newest_enemy_bullet_life: float = 0.0
	for bullet: Node in active_enemy_bullets:
		var bullet_snapshot: Dictionary = bullet.call("snapshot")
		var bullet_velocity: Vector2 = _dict_to_vector(
			bullet_snapshot.get("velocity", {}),
			Vector2.ZERO
		)
		var bullet_direction: Vector2 = bullet_velocity.normalized()
		_expect(
			bullet_direction.dot(locked_direction) > 0.999,
			"all burst bullets should retain the windup lock direction"
		)
		_expect(
			is_equal_approx(bullet_velocity.length(), 350.0),
			"ranged bullets should use the configured 350 px/s speed"
		)
		_expect(
			is_equal_approx(
				float(bullet_snapshot.get("max_range", 0.0)),
				720.0
			),
			"ranged bullets should retain the configured 720 px range"
		)
		newest_enemy_bullet_life = maxf(
			newest_enemy_bullet_life,
			float(bullet_snapshot.get("remaining_life", 0.0))
		)
	_expect(
		newest_enemy_bullet_life >= 2.0
		and newest_enemy_bullet_life <= 2.1,
		"the newest ranged bullet should retain the 2.1 second lifetime"
	)
	_expect_enemy_bullet_visual(active_enemy_bullets)
	if spitter.is_connected("attack_windup_started", windup_callable):
		spitter.disconnect("attack_windup_started", windup_callable)
	if spitter.is_connected("attack_committed", commit_callable):
		spitter.disconnect("attack_committed", commit_callable)
	_release_active_bullets()
	_expect_ranged_snapshot_restore(spitter)
	PoolManager.release(spitter)
	_release_active_bullets()

	_expect_shared_bullet_player_visual(player)
	var damage_spitter: Node2D = _spawn_smoke_enemy(
		run_loop,
		"enemy_spitter",
		"smoke_ranged_damage"
	)
	_expect(damage_spitter != null, "ranged damage smoke should spawn the gunner")
	if damage_spitter == null:
		return
	player.global_position = test_position
	damage_spitter.global_position = test_position + Vector2(320.0, 0.0)
	damage_spitter.set_physics_process(true)
	var defense_before: float = _player_total_defense(player)
	for _index: int in range(150):
		await get_tree().physics_frame
		if _player_total_defense(player) < defense_before:
			break
	_expect(
		_player_total_defense(player) < defense_before,
		"ranged enemy projectile should damage a player defense layer through Combat"
	)
	PoolManager.release(damage_spitter)
	_release_active_bullets()


func _expect_ranged_snapshot_restore(spitter: Node2D) -> void:
	spitter.set_physics_process(false)
	var windup_snapshot: Dictionary = spitter.call("snapshot")
	windup_snapshot["current_action"] = (
		ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	)
	windup_snapshot["action_state"] = "ranged_windup"
	windup_snapshot["action_timer"] = 0.17
	windup_snapshot["attack_cooldown_remaining"] = 0.0
	windup_snapshot["burst_shots_remaining"] = 4
	windup_snapshot["locked_direction"] = {"x": -1.0, "y": 0.0}
	spitter.call("restore_snapshot", windup_snapshot)
	var restored_windup: Dictionary = spitter.call("snapshot")
	_expect(
		String(restored_windup.get("action_state", "")) == "ranged_windup"
		and is_equal_approx(
			float(restored_windup.get("action_timer", 0.0)),
			0.17
		)
		and int(restored_windup.get("burst_shots_remaining", 0)) == 4,
		"Run v8 enemy snapshot should restore ranged windup timing and shots"
	)

	var burst_snapshot: Dictionary = restored_windup.duplicate(true)
	burst_snapshot["action_state"] = "ranged_burst"
	burst_snapshot["action_timer"] = 0.07
	burst_snapshot["burst_shots_remaining"] = 2
	spitter.call("restore_snapshot", burst_snapshot)
	var restored_burst: Dictionary = spitter.call("snapshot")
	_expect(
		String(restored_burst.get("action_state", "")) == "ranged_burst"
		and is_equal_approx(
			float(restored_burst.get("action_timer", 0.0)),
			0.07
		)
		and int(restored_burst.get("burst_shots_remaining", 0)) == 2,
		"Run v8 enemy snapshot should restore mid-burst timing and shots"
	)
	var bullets_before: int = _pool_stat(POOL_IDS.BULLET_BASIC, "acquired")
	spitter.call("_update_attack_state", 0.07)
	spitter.call("_update_attack_state", 0.12)
	_expect(
		_pool_stat(POOL_IDS.BULLET_BASIC, "acquired") - bullets_before == 2,
		"restored mid-burst state should neither duplicate nor omit shots"
	)
	_expect(
		int(
			(spitter.call("snapshot") as Dictionary).get(
				"burst_shots_remaining",
				-1
			)
		) == 0,
		"restored burst should finish with no remaining shots"
	)
	_release_active_bullets()

	var invalid_snapshot: Dictionary = windup_snapshot.duplicate(true)
	invalid_snapshot["action_state"] = "ranged_burst"
	invalid_snapshot["action_timer"] = 0.08
	invalid_snapshot["burst_shots_remaining"] = 4
	spitter.call("restore_snapshot", invalid_snapshot)
	var cleared_invalid: Dictionary = spitter.call("snapshot")
	_expect(
		String(cleared_invalid.get("current_action", "")).is_empty()
		and String(cleared_invalid.get("action_state", "")).is_empty()
		and int(cleared_invalid.get("burst_shots_remaining", -1)) == 0
		and float(
			cleared_invalid.get("attack_cooldown_remaining", 0.0)
		) >= 0.95,
		"invalid burst snapshots should clear the attack and apply one cooldown"
	)

	var invalid_action_snapshot: Dictionary = invalid_snapshot.duplicate(true)
	invalid_action_snapshot["current_action"] = "corrupt_ranged_action"
	invalid_action_snapshot["burst_shots_remaining"] = 5
	invalid_action_snapshot["attack_cooldown_remaining"] = 0.0
	spitter.call("restore_snapshot", invalid_action_snapshot)
	var cleared_invalid_action: Dictionary = spitter.call("snapshot")
	_expect(
		String(cleared_invalid_action.get("current_action", "")).is_empty()
		and String(
			cleared_invalid_action.get("action_state", "")
		).is_empty()
		and int(
			cleared_invalid_action.get("burst_shots_remaining", -1)
		) == 0
		and float(
			cleared_invalid_action.get(
				"attack_cooldown_remaining",
				0.0
			)
		) >= 0.95,
		"corrupt ranged action snapshots should still apply one cooldown"
	)

	var invalid_timer_snapshot: Dictionary = windup_snapshot.duplicate(true)
	invalid_timer_snapshot["action_timer"] = -0.01
	invalid_timer_snapshot["attack_cooldown_remaining"] = 0.0
	spitter.call("restore_snapshot", invalid_timer_snapshot)
	var cleared_invalid_timer: Dictionary = spitter.call("snapshot")
	_expect(
		String(cleared_invalid_timer.get("current_action", "")).is_empty()
		and String(
			cleared_invalid_timer.get("action_state", "")
		).is_empty()
		and int(
			cleared_invalid_timer.get("burst_shots_remaining", -1)
		) == 0
		and float(
			cleared_invalid_timer.get(
				"attack_cooldown_remaining",
				0.0
			)
		) >= 0.95,
		"negative ranged snapshot timers should clear into one cooldown"
	)

	var legacy_snapshot: Dictionary = windup_snapshot.duplicate(true)
	legacy_snapshot.erase("burst_shots_remaining")
	legacy_snapshot["attack_cooldown_remaining"] = 0.0
	spitter.call("restore_snapshot", legacy_snapshot)
	var restored_legacy: Dictionary = spitter.call("snapshot")
	_expect(
		String(restored_legacy.get("current_action", "")).is_empty()
		and String(restored_legacy.get("action_state", "")).is_empty()
		and int(restored_legacy.get("burst_shots_remaining", -1)) == 0
		and is_zero_approx(
			float(
				restored_legacy.get(
					"attack_cooldown_remaining",
					-1.0
				)
			)
		),
		"older Run v8 snapshots without burst state should restore as idle"
	)


func _on_ranged_windup_started(
	_enemy: Node,
	action_id: String,
	context: Dictionary
) -> void:
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK:
		_ranged_windup_contexts.append(context.duplicate(true))


func _on_ranged_attack_committed(
	_enemy: Node,
	action_id: String,
	_context: Dictionary
) -> void:
	if action_id == ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK:
		_ranged_commit_times.append(GameClock.now())


func _expect_enemy_bullet_visual(active_bullets: Array[Node]) -> void:
	if active_bullets.is_empty():
		return
	_expect_slime_bullet_visual(
		active_bullets[0],
		true,
		12.0,
		"shared enemy bullet"
	)


func _expect_shared_bullet_player_visual(player: Node2D) -> void:
	var raw_bullet: Node = PoolManager.acquire(POOL_IDS.BULLET_BASIC)
	_expect(
		raw_bullet != null and raw_bullet.has_method("configure"),
		"shared bullet visual smoke should acquire a reusable bullet"
	)
	if raw_bullet == null or not raw_bullet.has_method("configure"):
		return
	var instance_id: int = raw_bullet.get_instance_id()
	var bullet_child_count: int = raw_bullet.get_child_count()
	var visual: Node = raw_bullet.get_node_or_null("Visual")
	var visual_child_count: int = visual.get_child_count() if visual != null else -1
	for source_team: String in [TEAM_ENEMY, TEAM_PLAYER, TEAM_ENEMY, TEAM_PLAYER]:
		raw_bullet.call("configure", {
			STATS.DAMAGE: 1.0,
			STATS.BULLET_SPEED: 350.0,
			STATS.BULLET_RANGE: 650.0,
			STATS.PIERCE_COUNT: 0,
		}, {
			"damage_target_groups": ["active_enemies"],
			"hit_radius": 12.0,
			"lifetime": 1.9,
			"source_team": source_team,
			"target_team": (
				TEAM_PLAYER if source_team == TEAM_ENEMY else TEAM_ENEMY
			),
		}, Vector2.RIGHT, player)
		_expect_slime_bullet_visual(
			raw_bullet,
			source_team == TEAM_ENEMY,
			12.0,
			"shared bullet palette reuse"
		)
		_expect(
			raw_bullet.get_child_count() == bullet_child_count
			and visual != null
			and visual.get_child_count() == visual_child_count,
			"repeated configure should not grow the shared bullet node tree"
		)
	PoolManager.release(raw_bullet)
	var reused_bullet: Node = PoolManager.acquire(POOL_IDS.BULLET_BASIC)
	_expect(
		reused_bullet != null
		and reused_bullet.get_instance_id() == instance_id,
		"bullet pool should reacquire the released shared bullet instance"
	)
	if reused_bullet != null:
		_expect_slime_bullet_visual(
			reused_bullet,
			false,
			3.0,
			"released bullet reset"
		)
		_expect(
			reused_bullet.get_child_count() == bullet_child_count
			and reused_bullet.get_node("Visual").get_child_count()
			== visual_child_count,
			"pool release and reset should not grow the bullet node tree"
		)
		PoolManager.release(reused_bullet)


func _expect_slime_bullet_visual(
	bullet: Node,
	enemy_palette: bool,
	expected_radius: float,
	context: String
) -> void:
	var visual: Node2D = bullet.get_node_or_null("Visual") as Node2D
	_expect(visual != null, "%s should keep the shared Visual" % context)
	if visual == null:
		return
	_expect(
		bullet.get_child_count() == 1
		and visual.get_child_count() == 6,
		"%s should keep one visual with four persistent edge nodes" % context
	)
	_expect(
		bullet.get_node_or_null("EnemyVisual") == null
		and bullet.get_node_or_null("RibbonTrail") == null
		and bullet.get_node_or_null("EnemyRibbonTrail") == null,
		"%s should have no duplicate visual or trail nodes" % context
	)
	var body: Polygon2D = visual.get_node_or_null("Body") as Polygon2D
	var rim: Line2D = visual.get_node_or_null("Rim") as Line2D
	_expect(
		body != null
		and rim != null
		and body.material == null
		and rim.material == null,
		"%s should use unshaded Body and Rim canvas nodes" % context
	)
	for edge_name: String in ["EdgeEast", "EdgeSouth", "EdgeWest", "EdgeNorth"]:
		_expect(
			visual.get_node_or_null(edge_name) is Node2D,
			"%s should keep %s" % [context, edge_name]
		)
	_expect(
		visual.has_method("body_render_mode")
		and String(visual.call("body_render_mode")) == "four_node_slime_rim"
		and visual.has_method("geometry_signature")
		and String(visual.call("geometry_signature"))
		== BULLET_GEOMETRY_SIGNATURE,
		"%s should expose the expected four-node geometry signature" % context
	)
	_expect(
		visual.has_method("edge_control_node_count")
		and int(visual.call("edge_control_node_count")) == 4
		and visual.has_method("smoothed_boundary_point_count")
		and int(visual.call("smoothed_boundary_point_count")) == 64
		and visual.has_method("edge_controls_form_cardinal_ring")
		and bool(visual.call("edge_controls_form_cardinal_ring")),
		"%s should keep four cardinal controls and a 64-point boundary" % context
	)
	_expect(
		visual.has_method("normalized_visual_extent")
		and float(visual.call("normalized_visual_extent")) <= 1.0001
		and is_equal_approx(visual.scale.x, expected_radius)
		and is_equal_approx(visual.scale.y, expected_radius),
		"%s should remain inside its %.1f px collision radius" % [
			context,
			expected_radius,
		]
	)
	var expected_body: Color = (
		BULLET_ENEMY_BODY_COLOR if enemy_palette else BULLET_PLAYER_BODY_COLOR
	)
	var expected_rim: Color = (
		BULLET_ENEMY_RIM_COLOR if enemy_palette else BULLET_PLAYER_RIM_COLOR
	)
	var actual_body: Color = visual.call("body_color")
	var actual_rim: Color = visual.call("rim_color")
	_expect(
		visual.has_method("uses_enemy_palette")
		and bool(visual.call("uses_enemy_palette")) == enemy_palette
		and visual.has_method("body_color")
		and actual_body.is_equal_approx(expected_body)
		and visual.has_method("rim_color")
		and actual_rim.is_equal_approx(expected_rim),
		"%s should use only its faction body and rim colors" % context
	)
	_expect(
		visual.has_method("has_shader_material")
		and not bool(visual.call("has_shader_material")),
		"%s should contain no ShaderMaterial" % context
	)
	if body != null and rim != null:
		_expect(
			body.polygon.size() == 64
			and rim.points.size() == 64
			and rim.closed,
			"%s should build one closed 64-point Body and Rim" % context
		)


func _expect_overdrive_rounds_skill(run_loop: Node, player: Node2D) -> void:
	var before_summary: Dictionary = run_loop.call("debug_summary")
	var mana_before: float = _skill_resource_current(before_summary, SKILL_RESOURCES.ENERGY)
	var result: Dictionary = run_loop.call("debug_cast_primary_skill")
	_expect(bool(result.get("ok", false)), "slot 1 barrier should cast from the runtime skill system")
	var after_summary: Dictionary = run_loop.call("debug_summary")
	var mana_after: float = _skill_resource_current(after_summary, SKILL_RESOURCES.ENERGY)
	_expect(mana_after < mana_before, "slot 1 barrier should spend energy")
	var cooldown_result: Dictionary = run_loop.call("debug_cast_primary_skill")
	_expect(not bool(cooldown_result.get("ok", true)), "slot 1 barrier should not immediately recast")
	_expect(String(cooldown_result.get("reason", "")) == "cooldown", "slot 1 recast should report cooldown")


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
	_expect(spawned, "%s should spawn for enemy AI smoke" % enemy_id)
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


func _map_bounds(run_loop: Node) -> Rect2:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return Rect2()
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_map_summary: Variant = summary.get("map", {})
	if not raw_map_summary is Dictionary:
		return Rect2()
	var map_summary: Dictionary = raw_map_summary as Dictionary
	var raw_bounds: Variant = map_summary.get("bounds", {})
	if not raw_bounds is Dictionary:
		return Rect2()
	var bounds: Dictionary = raw_bounds as Dictionary
	return Rect2(
		Vector2(float(bounds.get("x", 0.0)), float(bounds.get("y", 0.0))),
		Vector2(float(bounds.get("width", 0.0)), float(bounds.get("height", 0.0)))
	)


func _map_boundary_center(run_loop: Node) -> Vector2:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return Vector2.ZERO
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_map_summary: Variant = summary.get("map", {})
	if not raw_map_summary is Dictionary:
		return Vector2.ZERO
	var map_summary: Dictionary = raw_map_summary as Dictionary
	return _dict_to_vector(map_summary.get("boundary_center", {}), _map_bounds(run_loop).get_center())


func _map_boundary_half_extents(run_loop: Node) -> Vector2:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return Vector2.ZERO
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_map_summary: Variant = summary.get("map", {})
	if not raw_map_summary is Dictionary:
		return Vector2.ZERO
	var map_summary: Dictionary = raw_map_summary as Dictionary
	return _dict_to_vector(map_summary.get("boundary_half_extents", {}), Vector2.ZERO)


func _position_inside_bounds(bounds: Rect2, position: Vector2) -> bool:
	return (
		position.x >= bounds.position.x - 0.01
		and position.x <= bounds.end.x + 0.01
		and position.y >= bounds.position.y - 0.01
		and position.y <= bounds.end.y + 0.01
	)


func _position_inside_map_boundary(run_loop: Node, position: Vector2, inset_extents: Vector2 = Vector2.ZERO) -> bool:
	var center: Vector2 = _map_boundary_center(run_loop)
	var half_extents: Vector2 = _map_boundary_half_extents(run_loop)
	if half_extents.x <= 0.0 or half_extents.y <= 0.0:
		return false
	var usable_half_extents: Vector2 = Vector2(
		half_extents.x - maxf(inset_extents.x, 0.0),
		half_extents.y - maxf(inset_extents.y, 0.0)
	)
	if usable_half_extents.x < 0.0 or usable_half_extents.y < 0.0:
		return false
	var offset: Vector2 = position - center
	return absf(offset.x) <= usable_half_extents.x + 0.01 and absf(offset.y) <= usable_half_extents.y + 0.01


func _expect_stats_panel_hold_to_show(run_loop: Node) -> void:
	var hud: Node = _find_node_by_name(run_loop, "GameplayHud")
	_expect(hud != null, "GameplayHud should exist for stats panel smoke")
	if hud == null or not hud.has_method("is_stats_panel_visible"):
		return
	_expect(not bool(hud.call("is_stats_panel_visible")), "stats panel should start hidden")
	var state_before: StringName = GameState.current()
	var tick_before: int = GameClock.tick()
	InputService.set_playback_active(true)
	InputService.inject_playback_value(ACTIONS.SHOW_STATS_PANEL, true)
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	_expect(bool(hud.call("is_stats_panel_visible")), "holding stats panel action should show the HUD panel")
	_expect(GameState.current() == state_before and GameState.is_state(GameState.PLAYING), "holding stats panel action should keep gameplay state")
	_expect(GameClock.tick() > tick_before, "holding stats panel action should not freeze gameplay time")
	var title_label: Label = _find_node_by_name(hud, "TitleLabel") as Label
	var damage_value_label: Label = _find_node_by_name(hud, "DamageValueLabel") as Label
	var health_regen_value_label: Label = _find_node_by_name(hud, "HealthRegenValueLabel") as Label
	var gold_balance_value_label: Label = _find_node_by_name(hud, "GoldBalanceValueLabel") as Label
	var gold_total_value_label: Label = _find_node_by_name(hud, "GoldEarnedTotalValueLabel") as Label
	var level_progress_value_label: Label = _find_node_by_name(hud, "LevelProgressValueLabel") as Label
	var luck_value_label: Label = _find_node_by_name(hud, "LuckValueLabel") as Label
	var gold_progress_label: Label = _find_node_by_name(hud, "GoldProgressLabel") as Label
	_expect(title_label != null and String(title_label.text) == tr("ui_stats_panel_title"), "stats panel title should use localized text")
	_expect(damage_value_label != null and not String(damage_value_label.text).is_empty(), "stats panel should show current damage")
	_expect(health_regen_value_label != null and String(health_regen_value_label.text).contains("/s"), "stats panel should show current health regen")
	_expect(gold_balance_value_label != null, "stats panel should show gold balance")
	_expect(gold_total_value_label != null, "stats panel should show total gold earned")
	_expect(level_progress_value_label != null, "stats panel should show current level progress")
	_expect(luck_value_label != null, "stats panel should retain luck")
	_expect(
		gold_progress_label != null
		and String(gold_progress_label.text).contains("·"),
		"persistent HUD should show gold balance and level progress together"
	)
	InputService.inject_playback_value(ACTIONS.SHOW_STATS_PANEL, false)
	InputService.set_playback_active(false)
	for _index: int in range(UI_TRANSITION_FRAMES):
		await get_tree().process_frame
		if not bool(hud.call("is_stats_panel_visible")):
			break
	_expect(not bool(hud.call("is_stats_panel_visible")), "releasing stats panel action should hide the HUD panel")


func _expect_gold_orb_draw_order(run_loop: Node, player: Node2D) -> void:
	var enemy_data: Dictionary = {
		"max_hp": 6,
		"move_speed": 0.0,
		"gold_reward": 0,
		"hit_radius": 14.0,
		"separation_radius": 0.0,
	}
	var enemy: Node2D = ENEMY_SCENE.instantiate() as Node2D
	enemy.name = "SmokeDrawOrderEnemy"
	run_loop.add_child(enemy)
	enemy.global_position = player.global_position + Vector2(500.0, 0.0)
	enemy.call("configure", enemy_data, player)
	enemy.set_physics_process(false)

	run_loop.call("_spawn_gold_orb", enemy.global_position, 1)
	await get_tree().process_frame

	var gold_orb: Node2D = null
	for raw_orb: Node in get_tree().get_nodes_in_group("active_gold_orbs"):
		if raw_orb is Node2D:
			gold_orb = raw_orb as Node2D
			break
	_expect(gold_orb != null, "gold orb should be active for draw-order smoke")
	_expect(gold_orb != null and gold_orb.z_index < enemy.z_index, "gold orbs should draw below enemies")
	_expect(gold_orb != null and _find_node_by_name(gold_orb, "AttractRing") is Line2D, "gold orbs should use scene-authored editable visual nodes")
	_expect(
		gold_orb != null
		and is_equal_approx(
			float((gold_orb.call("snapshot") as Dictionary).get("pickup_speed", 0.0)),
			360.0
		),
		"gold orb should use gold_drop.pickup_speed"
	)
	if gold_orb != null:
		PoolManager.release(gold_orb)
	enemy.remove_from_group("active_enemies")
	enemy.queue_free()


func _expect_gold_orb_feedback(run_loop: Node, player: Node2D) -> void:
	run_loop.call("_spawn_gold_orb", player.global_position + Vector2(40.0, 0.0), 1)
	await get_tree().physics_frame
	await get_tree().process_frame

	var gold_orb: Node2D = null
	for raw_orb: Node in get_tree().get_nodes_in_group("active_gold_orbs"):
		if raw_orb is Node2D:
			gold_orb = raw_orb as Node2D
			break
	_expect(gold_orb != null, "gold orb should be active for feedback smoke")
	if gold_orb == null:
		return
	_expect(gold_orb.has_method("is_attracting") and bool(gold_orb.call("is_attracting")), "gold orb should expose attraction feedback inside pickup range")

	gold_orb.global_position = player.global_position
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(gold_orb.has_method("is_collect_feedback_active") and bool(gold_orb.call("is_collect_feedback_active")), "gold orb should show collect feedback before pooling")
	_expect(not gold_orb.is_in_group("active_gold_orbs"), "collected gold orb should leave active group during feedback")
	for _index: int in range(PICKUP_FEEDBACK_FRAMES):
		await get_tree().process_frame
	_expect(not bool(gold_orb.call("is_collect_feedback_active")), "gold orb collect feedback should finish and release")


func _expect_gold_progression(run_loop: Node, player: Node2D) -> void:
	var previous_level: int = int(run_loop.call("current_level"))
	var previous_balance: int = int(run_loop.call("gold_balance"))
	var previous_total: int = int(run_loop.call("gold_earned_total"))
	var level_cost_remaining: int = (
		int(run_loop.call("current_level_gold_required"))
		- int(run_loop.call("current_level_gold"))
	)
	var add_result: Dictionary = run_loop.call(
		"add_gold",
		level_cost_remaining,
		"event_reward"
	) as Dictionary
	_expect(bool(add_result.get("ok", false)), "gold progression should accept a registered positive reward")
	_expect(int(run_loop.call("current_level")) == previous_level + 1, "gold earned total should raise the level")
	_expect(int(run_loop.call("gold_balance")) == previous_balance + level_cost_remaining, "gold reward should increase spendable balance")
	_expect(int(run_loop.call("gold_earned_total")) == previous_total + level_cost_remaining, "gold reward should increase earned total")
	_expect(GameState.is_state(GameState.PLAYING), "level advancement should not pause gameplay")
	_expect(_find_node_by_name(get_tree().root, "RewardChoicePanel") == null, "level advancement should not open reward choice")

	var spend_result: Dictionary = run_loop.call(
		"try_spend_gold",
		level_cost_remaining,
		"event_cost"
	) as Dictionary
	_expect(bool(spend_result.get("ok", false)), "gold spend should succeed when affordable")
	_expect(int(run_loop.call("current_level")) == previous_level + 1, "spending gold should not lower the level")
	_expect(int(run_loop.call("gold_earned_total")) == previous_total + level_cost_remaining, "spending gold should not lower earned total")

	var active_orbs_before: int = PoolManager.active_count(POOL_IDS.GOLD_ORB)
	var spawn_result: Dictionary = run_loop.call("debug_spawn_enemy", "enemy_chaser", 1)
	_expect(bool(spawn_result.get("ok", false)), "gold drop smoke should spawn a chaser")
	var enemy: Node = _first_enemy_with_name_prefix(POOL_IDS.ENEMY_CHASER)
	_expect(enemy != null, "gold drop smoke should find the spawned chaser")
	if enemy == null:
		return
	var enemy_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		999.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		player,
		enemy,
		"team_player",
		"team_enemy"
	)
	var enemy_result: Dictionary = Combat.apply_damage(enemy, enemy_info)
	_expect(bool(enemy_result.get("defeated", false)), "gold drop smoke should defeat the chaser")
	await get_tree().process_frame
	_expect(
		PoolManager.active_count(POOL_IDS.GOLD_ORB) == active_orbs_before + 1,
		"player-attributed enemy defeat should spawn exactly one gold orb"
	)
	var non_player_orbs_before: int = PoolManager.active_count(POOL_IDS.GOLD_ORB)
	var non_player_spawn: Dictionary = run_loop.call(
		"debug_spawn_enemy",
		"enemy_chaser",
		1
	) as Dictionary
	_expect(bool(non_player_spawn.get("ok", false)), "non-player drop smoke should spawn a chaser")
	var non_player_enemy: Node = _first_enemy_with_name_prefix(POOL_IDS.ENEMY_CHASER)
	if non_player_enemy == null:
		_expect(false, "non-player drop smoke should find a chaser")
		return
	var non_player_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		999.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		run_loop,
		non_player_enemy,
		"team_environment",
		"team_enemy"
	)
	var non_player_result: Dictionary = Combat.apply_damage(
		non_player_enemy,
		non_player_info
	)
	_expect(bool(non_player_result.get("defeated", false)), "non-player damage should defeat the chaser")
	await get_tree().process_frame
	_expect(
		PoolManager.active_count(POOL_IDS.GOLD_ORB) == non_player_orbs_before,
		"non-player-attributed defeat should not spawn gold"
	)


func _expect_gold_progression_curve_and_transactions() -> void:
	var progression: GoldProgression = GoldProgression.new()
	var config: Dictionary = DataLoader.load_json(
		DataLoader.LEVEL_PROGRESSION_PATH
	) as Dictionary
	_expect(progression.configure(config), "standalone gold progression should accept canonical data")
	var segment_costs: Array[int] = [
		100,
		130,
		169,
		220,
		286,
		372,
		484,
		630,
		819,
		1065,
	]
	var thresholds: Array[int] = [
		100,
		230,
		399,
		619,
		905,
		1277,
		1761,
		2391,
		3210,
		4275,
	]
	for index: int in range(segment_costs.size()):
		_expect(
			progression.current_level_gold_required() == segment_costs[index],
			"gold progression segment %d should match the 1.3x ceil curve" % (index + 1)
		)
		var result: Dictionary = progression.add_gold(
			segment_costs[index],
			"event_reward"
		)
		_expect(bool(result.get("ok", false)), "gold curve step should be accepted")
		_expect(
			progression.gold_earned_total() == thresholds[index],
			"gold progression cumulative threshold should match level %d" % (index + 2)
		)
		_expect(
			progression.current_level() == index + 2,
			"gold progression should advance exactly one level per segment"
		)

	progression.reset()
	var multi_result: Dictionary = progression.add_gold(4275, "event_reward")
	_expect(bool(multi_result.get("ok", false)), "one gold transaction should cross multiple levels")
	_expect(int(multi_result.get("levels_gained", 0)) == 10, "4275 gold should advance from level 1 to level 11")
	_expect(progression.current_level() == 11, "4275 cumulative gold should derive level 11")
	var spend_result: Dictionary = progression.try_spend_gold(4000, "event_cost")
	_expect(bool(spend_result.get("ok", false)), "affordable gold spend should succeed")
	_expect(progression.current_level() == 11, "spending should not reduce derived level")
	_expect(progression.gold_earned_total() == 4275, "spending should not reduce earned total")
	var before_failure: Dictionary = progression.snapshot()
	_expect(
		not bool(progression.try_spend_gold(276, "event_cost").get("ok", true)),
		"insufficient gold spend should fail"
	)
	_expect(progression.snapshot() == before_failure, "failed spend should be atomic")
	_expect(
		not bool(progression.add_gold(1, "unknown_reason").get("ok", true)),
		"unknown gold reason should fail"
	)
	_expect(progression.snapshot() == before_failure, "invalid gold reason should be atomic")
	_expect(progression.restore(GoldProgression.MAX_INT, GoldProgression.MAX_INT), "max int state should restore")
	var before_overflow: Dictionary = progression.snapshot()
	var overflow_result: Dictionary = progression.add_gold(1, "event_reward")
	_expect(String(overflow_result.get("reason", "")) == "integer_overflow", "gold overflow should report integer_overflow")
	_expect(progression.snapshot() == before_overflow, "gold overflow should be atomic")
	progression.free()


func _expect_reward_choice_controller_contract() -> void:
	var controller: RewardChoiceController = RewardChoiceController.new()
	var config: Dictionary = DataLoader.load_json(
		DataLoader.REWARD_CHOICE_POOLS_PATH
	) as Dictionary
	_expect(controller.configure(config), "standalone reward controller should accept canonical data")
	for candidate_count: int in [2, 3, 5]:
		var result: Dictionary = controller.request_choice(
			"default_reward_choice",
			"debug_command",
			candidate_count,
			3
		)
		_expect(bool(result.get("ok", false)), "%d-candidate reward request should succeed" % candidate_count)
		_expect(
			(result.get("choices", []) as Array).size() == candidate_count,
			"reward request should return the caller-selected candidate count"
		)
		controller.clear()

	for invalid_count: int in [1, 6]:
		var rng_before: Dictionary = RNG.snapshot()
		var invalid_result: Dictionary = controller.request_choice(
			"default_reward_choice",
			"debug_command",
			invalid_count,
			3
		)
		_expect(
			String(invalid_result.get("reason", "")) == "invalid_candidate_count",
			"reward candidate count %d should fail atomically" % invalid_count
		)
		_expect(RNG.snapshot() == rng_before, "invalid candidate count should not consume RNG")
		_expect(not controller.is_busy(), "invalid candidate count should not create an active request")

	var insufficient_rng: Dictionary = RNG.snapshot()
	var insufficient: Dictionary = controller.request_choice(
		"default_reward_choice",
		"debug_command",
		5,
		1
	)
	_expect(String(insufficient.get("reason", "")) == "insufficient_candidates", "level filtering should reject insufficient candidates")
	_expect(RNG.snapshot() == insufficient_rng, "insufficient candidates should not consume RNG")
	var unknown_rng: Dictionary = RNG.snapshot()
	var unknown: Dictionary = controller.request_choice(
		"unknown_pool",
		"debug_command",
		2,
		3
	)
	_expect(String(unknown.get("reason", "")) == "unknown_pool", "unknown reward pool should fail")
	_expect(RNG.snapshot() == unknown_rng, "unknown reward pool should not consume RNG")
	controller.free()


func _expect_interest_point_rewards(run_loop: Node, player: Node2D) -> void:
	_expect(run_loop.has_method("debug_claim_interest_point"), "runtime should expose a smoke hook for interest point claims")
	if not run_loop.has_method("debug_claim_interest_point"):
		return
	_expect(run_loop.has_method("debug_damage_interest_point_target"), "runtime should expose a smoke hook for interest point target damage")
	if not run_loop.has_method("debug_damage_interest_point_target"):
		return
	_expect(InputService.action_resource(ACTIONS.INTERACT) != null, "InputService should expose interact")

	var gold_before_resource_cache: int = int(run_loop.call("gold_balance"))
	player.global_position = _interest_point_position(run_loop, "poi_resource_cache")
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	var hud: Node = _find_node_by_name(run_loop, "GameplayHud")
	_expect(
		hud != null
		and hud.has_method("is_interaction_prompt_visible")
		and bool(hud.call("is_interaction_prompt_visible")),
		"resource cache should show an interaction prompt before opening"
	)
	var pre_interact_snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var pre_interact_points: Dictionary = pre_interact_snapshot.get("interest_points", {}) as Dictionary
	var pre_interact_resource_state: Dictionary = pre_interact_points.get("poi_resource_cache", {}) as Dictionary
	_expect(not bool(pre_interact_resource_state.get("claimed", true)), "resource cache should not auto-claim while the player only stands nearby")
	await _push_action_once(ACTIONS.INTERACT)
	var resource_snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var resource_points: Dictionary = resource_snapshot.get("interest_points", {}) as Dictionary
	var resource_claimed_state: Dictionary = resource_points.get("poi_resource_cache", {}) as Dictionary
	_expect(bool(resource_claimed_state.get("claimed", false)), "interact should open the resource cache")
	var resource_reward: Dictionary = resource_claimed_state.get("reward_result", {}) as Dictionary
	var resource_gold: int = int(resource_reward.get("gold_amount", 0))
	_expect(
		resource_gold > 0
		and int(run_loop.call("gold_balance"))
		== gold_before_resource_cache + resource_gold,
		"resource cache should grant configured gold immediately: reward=%d before=%d after=%d"
		% [
			resource_gold,
			gold_before_resource_cache,
			int(run_loop.call("gold_balance")),
		]
	)

	var ranks_before_mod_cache: Dictionary = _run_gear_mod_ranks(run_loop)
	var pickups_before_mod_cache: int = _active_gear_mod_pickup_count(run_loop)
	GameClock.restore_snapshot({
		"elapsed": 240.0,
		"tick": GameClock.tick(),
		"time_scale": GameClock.time_scale(),
	})
	player.global_position = _interest_point_position(run_loop, "poi_mod_cache")
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	_expect(
		hud != null
		and hud.has_method("is_interaction_prompt_visible")
		and bool(hud.call("is_interaction_prompt_visible")),
		"mod cache should show an interaction prompt before opening"
	)
	await _push_action_once(ACTIONS.INTERACT)
	var mod_snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var mod_points: Dictionary = mod_snapshot.get("interest_points", {}) as Dictionary
	var mod_claimed_state: Dictionary = mod_points.get("poi_mod_cache", {}) as Dictionary
	_expect(bool(mod_claimed_state.get("claimed", false)), "interact should open the mod cache")
	var mod_reward: Dictionary = mod_claimed_state.get("reward_result", {}) as Dictionary
	var dropped_mods: Array = mod_reward.get("gear_mods", []) as Array
	var ranks_after_mod_cache_spawn: Dictionary = _run_gear_mod_ranks(run_loop)
	_expect(
		dropped_mods.size() == 2
		and _active_gear_mod_pickup_count(run_loop)
		== pickups_before_mod_cache + 2
		and ranks_after_mod_cache_spawn == ranks_before_mod_cache,
		"mod cache should spawn two Gear Mod pickups without granting them: reward=%s before=%s after=%s"
		% [dropped_mods, ranks_before_mod_cache, ranks_after_mod_cache_spawn]
	)
	await _push_action_once(ACTIONS.INTERACT)
	var ranks_after_mod_cache: Dictionary = _run_gear_mod_ranks(run_loop)
	_expect(
		ranks_after_mod_cache != ranks_before_mod_cache
		and _active_gear_mod_pickup_count(run_loop)
		== pickups_before_mod_cache + 1,
		"one interact press should collect only the nearest Mod cache pickup"
	)
	_expect(
		hud != null
		and hud.has_method("is_gear_mod_drop_feedback_visible")
		and bool(hud.call("is_gear_mod_drop_feedback_visible")),
		"Mod cache pickup should show Gear Mod HUD feedback only after interaction"
	)

	var duplicate_claim: Dictionary = run_loop.call("debug_claim_interest_point", "poi_resource_cache") as Dictionary
	_expect(not bool(duplicate_claim.get("ok", true)), "claimed interest points should not pay rewards twice")
	_expect(String(duplicate_claim.get("reason", "")) == "already_claimed", "duplicate interest point claim should report already_claimed")

	var snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var points: Dictionary = snapshot.get("interest_points", {}) as Dictionary
	var resource_state: Dictionary = points.get("poi_resource_cache", {}) as Dictionary
	_expect(bool(resource_state.get("claimed", false)), "run snapshot should persist claimed interest point state")
	var gear_mod_state: Dictionary = snapshot.get("gear_mods", {}) as Dictionary
	var saved_ranks: Dictionary = gear_mod_state.get("ranks", {}) as Dictionary
	_expect(
		saved_ranks == ranks_after_mod_cache,
		"run snapshot should persist run-scoped Gear Mod ranks"
	)
	_expect(
		(snapshot.get("gear_mod_pickups", []) as Array).size()
		== _active_gear_mod_pickup_count(run_loop),
		"run snapshot should persist every uncollected Gear Mod pickup"
	)


func _expect_reward_choice(run_loop: Node, player: Node2D) -> Dictionary:
	var weapon_system: Node = _find_node_by_name(player, "WeaponSystem")
	_expect(weapon_system != null, "WeaponSystem should be available before reward choice")
	var previous_damage: float = float(weapon_system.call("stat_value", STATS.DAMAGE)) if weapon_system != null else 0.0
	var previous_fire_rate: float = float(weapon_system.call("stat_value", STATS.FIRE_RATE)) if weapon_system != null else 0.0
	var previous_pickup_range: float = float(player.call("pickup_range"))
	var previous_luck: float = float(player.call("luck"))

	var invalid_rng: Dictionary = RNG.snapshot()
	var invalid_request: Dictionary = run_loop.call(
		"request_reward_choice",
		"default_reward_choice",
		"debug_command",
		1
	) as Dictionary
	_expect(String(invalid_request.get("reason", "")) == "invalid_candidate_count", "runtime should reject one reward candidate")
	_expect(RNG.snapshot() == invalid_rng, "invalid runtime reward request should not consume RNG")
	_expect(GameState.is_state(GameState.PLAYING), "invalid reward request should not change state")
	var request_result: Dictionary = run_loop.call(
		"request_reward_choice",
		"default_reward_choice",
		"debug_command",
		3
	) as Dictionary
	_expect(bool(request_result.get("ok", false)), "valid generic reward request should succeed")
	var busy_rng: Dictionary = RNG.snapshot()
	var busy_result: Dictionary = run_loop.call(
		"request_reward_choice",
		"default_reward_choice",
		"debug_command",
		2
	) as Dictionary
	_expect(String(busy_result.get("reason", "")) == "busy", "second runtime reward request should report busy")
	_expect(RNG.snapshot() == busy_rng, "busy runtime reward request should not consume RNG")
	var reward_panel: Node = null
	for _index: int in range(REWARD_CHOICE_FRAMES):
		await get_tree().process_frame
		reward_panel = _find_node_by_name(get_tree().root, "RewardChoicePanel")
		if reward_panel != null:
			break

	_expect(GameState.is_state(GameState.REWARD_CHOICE), "reward request should enter REWARD_CHOICE")
	_expect(reward_panel != null, "reward-choice panel should appear")
	var panel_frame: Control = _find_node_by_name(reward_panel, "RewardChoicePanelFrame") as Control
	_expect(panel_frame != null, "reward-choice panel frame should use responsive layout")
	if panel_frame != null:
		_expect(panel_frame.custom_minimum_size.x >= 520.0, "reward-choice panel frame should keep a readable minimum width")
		_expect(panel_frame.custom_minimum_size.x <= 720.0, "reward-choice panel frame should keep a responsive maximum width")
	if reward_panel == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}

	var choice_id: String = String(reward_panel.call("choice_id", 0))
	var snapshot_payload: Dictionary = run_loop.call("create_run_snapshot")
	var ui_restore: Dictionary = snapshot_payload.get("ui_restore", {}) as Dictionary
	var reward_snapshot: Dictionary = snapshot_payload.get("reward_choice", {}) as Dictionary
	_expect(String(ui_restore.get("state", "")) == "reward_choice", "run snapshot should remember a pending reward panel")
	_expect(
		reward_snapshot.get("choice_ids", []) is Array
		and (reward_snapshot.get("choice_ids", []) as Array).size() == 3,
		"reward restore point should keep the exact rolled choices"
	)
	_expect(SaveManager.save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN, snapshot_payload), "smoke should save a pending reward-choice run")
	var formal_boot: Node = _find_node_by_name(get_tree().root, "FormalClientBoot")
	_expect(formal_boot != null, "FormalClientBoot should exist before reward-choice restore smoke")
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
	_verify_no_meta_progression_entry(title_menu)
	_expect(continue_button != null and continue_button.visible and not continue_button.disabled, "title menu should continue a pending reward-choice run")
	if continue_button == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	await _click_button(continue_button)

	var restored_run_loop: Node = await _wait_for_state_run_loop(GameState.REWARD_CHOICE)
	_expect(restored_run_loop != null, "continue should restore into REWARD_CHOICE")
	if restored_run_loop == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	run_loop = restored_run_loop
	player = _find_node_by_name(run_loop, "Player") as Node2D
	weapon_system = _find_node_by_name(player, "WeaponSystem") if player != null else null
	reward_panel = _find_node_by_name(get_tree().root, "RewardChoicePanel")
	_expect(player != null, "reward-choice restore should rebuild the player")
	_expect(reward_panel != null, "reward-choice restore should show its panel")
	if reward_panel == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}
	_expect(String(reward_panel.call("choice_id", 0)) == choice_id, "reward restore should keep the same rolled first choice")
	await _expect_reward_choice_pause_overlay(run_loop)
	reward_panel = _find_node_by_name(get_tree().root, "RewardChoicePanel")
	_expect(reward_panel != null, "reward panel should remain after closing pause overlay")
	if reward_panel == null:
		return {
			"run_loop": run_loop,
			"player": player,
		}

	var choice_button: Button = _find_first_button(reward_panel)
	_expect(choice_button != null, "reward panel should expose clickable option buttons")
	if choice_button != null:
		_expect(choice_button.process_mode == Node.PROCESS_MODE_ALWAYS, "reward buttons should accept input while the tree is paused")
		_expect(choice_button.visible, "reward option button should be visible before click")
		_expect(not choice_button.disabled, "reward option button should be enabled before click")
		await _click_button(choice_button)
	_expect(GameState.is_state(GameState.PLAYING), "choosing a reward should resume PLAYING")
	var hud: Node = _find_node_by_name(run_loop, "GameplayHud")
	_expect(hud != null and hud.has_method("is_upgrade_feedback_visible") and bool(hud.call("is_upgrade_feedback_visible")), "choosing a reward should show upgrade feedback")
	if choice_id == "reward_damage_small" and weapon_system != null:
		_expect(float(weapon_system.call("stat_value", STATS.DAMAGE)) > previous_damage, "damage reward should apply immediately")
	elif choice_id == "reward_fire_rate_small" and weapon_system != null:
		_expect(float(weapon_system.call("stat_value", STATS.FIRE_RATE)) > previous_fire_rate, "fire-rate reward should apply immediately")
	elif choice_id == "reward_pickup_range_small":
		_expect(float(player.call("pickup_range")) > previous_pickup_range, "pickup-range reward should apply immediately")
	else:
		_expect(false, "reward choice should be a known modifier")
	_expect(
		is_equal_approx(float(player.call("luck")), previous_luck),
		"reward selection should not consume or reinterpret reserved luck"
	)
	return {
		"run_loop": run_loop,
		"player": player,
	}


func _expect_reward_choice_pause_overlay(run_loop: Node) -> void:
	await _push_action_once(ACTIONS.PAUSE)
	var pause_menu: Node = null
	for _index: int in range(BOOT_FRAMES * 2):
		await get_tree().process_frame
		pause_menu = _find_node_by_name(get_tree().root, "PauseMenu")
		if pause_menu != null:
			break
	_expect(GameState.is_state(GameState.PAUSED), "pressing pause during REWARD_CHOICE should open pause state")
	_expect(pause_menu != null, "pressing pause during REWARD_CHOICE should show the pause menu")
	var paused_request_rng: Dictionary = RNG.snapshot()
	var paused_request: Dictionary = run_loop.call(
		"request_reward_choice",
		"default_reward_choice",
		"debug_command",
		2
	) as Dictionary
	_expect(String(paused_request.get("reason", "")) == "busy", "reward request should remain busy while pause overlays the choice")
	_expect(RNG.snapshot() == paused_request_rng, "invalid-state reward request should not consume RNG")
	var paused_snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var ui_restore: Dictionary = paused_snapshot.get("ui_restore", {}) as Dictionary
	_expect(String(ui_restore.get("state", "")) == "paused", "reward pause overlay should snapshot as paused")
	_expect(String(ui_restore.get("underlying_state", "")) == "reward_choice", "pause overlay should preserve the underlying reward state")

	await _push_action_once(ACTIONS.PAUSE)
	var restored_run_loop: Node = await _wait_for_state_run_loop(GameState.REWARD_CHOICE)
	_expect(restored_run_loop == run_loop, "closing pause should return to the same REWARD_CHOICE run loop")
	_expect(_find_node_by_name(get_tree().root, "PauseMenu") == null, "closing pause overlay should remove the pause menu")


func _expect_pause_save_resume(run_loop: Node, player: Node2D) -> Dictionary:
	var saved_attack_enemy: Node2D = _spawn_smoke_enemy(
		run_loop,
		"enemy_chaser",
		"smoke_attack_restore"
	)
	var saved_attack_serial: int = 0
	var saved_attack_reward: Dictionary = {}
	if saved_attack_enemy != null:
		saved_attack_enemy.set_physics_process(false)
		saved_attack_enemy.call("_arm_explosion", false)
		saved_attack_serial = int(
			saved_attack_enemy.call("runtime_spawn_serial")
		)
		saved_attack_reward = (
			saved_attack_enemy.call("snapshot") as Dictionary
		).get("reward_snapshot", {}) as Dictionary
	var saved_ranged_enemy: Node2D = _spawn_smoke_enemy(
		run_loop,
		"enemy_spitter",
		"smoke_ranged_restore"
	)
	var saved_ranged_serial: int = 0
	var saved_ranged_timer: float = 0.0
	var saved_ranged_reward: Dictionary = {}
	if saved_ranged_enemy != null:
		saved_ranged_enemy.set_physics_process(false)
		var ranged_snapshot: Dictionary = saved_ranged_enemy.call("snapshot")
		ranged_snapshot["current_action"] = (
			ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
		)
		ranged_snapshot["action_state"] = "ranged_windup"
		ranged_snapshot["action_timer"] = 0.19
		ranged_snapshot["attack_cooldown_remaining"] = 0.0
		ranged_snapshot["burst_shots_remaining"] = 4
		ranged_snapshot["locked_direction"] = {"x": -1.0, "y": 0.0}
		saved_ranged_enemy.call("restore_snapshot", ranged_snapshot)
		saved_ranged_serial = int(
			saved_ranged_enemy.call("runtime_spawn_serial")
		)
		saved_ranged_timer = float(
			(saved_ranged_enemy.call("snapshot") as Dictionary).get(
				"action_timer",
				0.0
			)
		)
		saved_ranged_reward = (
			saved_ranged_enemy.call("snapshot") as Dictionary
		).get("reward_snapshot", {}) as Dictionary
	player.call(
		"apply_weapon_recoil",
		player.get("aim_direction") as Vector2,
		70.0,
		0.08
	)
	_expect(
		bool(
			player.call(
				"apply_external_knockback",
				Vector2.RIGHT,
				48.0,
				0.15
			)
		),
		"pause-save fixture should start external enemy knockback"
	)

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
	var saved_recoil_velocity: Vector2 = player.call(
		"weapon_recoil_velocity"
	) as Vector2
	var saved_recoil_remaining: float = float(
		player.call("weapon_recoil_remaining")
	)
	var saved_knockback_velocity: Vector2 = player.call(
		"external_knockback_velocity"
	) as Vector2
	var saved_knockback_remaining: float = float(
		player.call("external_knockback_remaining")
	)
	var saved_position: Vector2 = player.global_position
	var saved_level: int = int(run_loop.call("current_level"))
	var saved_gold_balance: int = int(run_loop.call("gold_balance"))
	var saved_gold_total: int = int(run_loop.call("gold_earned_total"))
	var saved_time: float = GameClock.now()
	var paused_visual: PlayerSlimeVisual = (
		player.get_node_or_null("Visual") as PlayerSlimeVisual
	)
	var saved_visual_time: float = (
		paused_visual.animation_time()
		if paused_visual != null
		else -1.0
	)
	var saved_attack_timer: float = (
		float(
			(saved_attack_enemy.call("snapshot") as Dictionary).get(
				"action_timer",
				0.0
			)
		)
		if saved_attack_enemy != null
		else 0.0
	)
	var paused_run_snapshot: Dictionary = run_loop.call(
		"create_run_snapshot"
	) as Dictionary
	var saved_economy_rng: Dictionary = (
		(
			paused_run_snapshot.get("rng", {}) as Dictionary
		).get("streams", {}) as Dictionary
	).get("economy", {}) as Dictionary
	var saved_gear_mod_ranks: Dictionary = (
		paused_run_snapshot.get("gear_mods", {}) as Dictionary
	).get("ranks", {}) as Dictionary
	var saved_gear_mod_pickups: Array = (
		paused_run_snapshot.get("gear_mod_pickups", []) as Array
	).duplicate(true)
	_expect(
		not saved_gear_mod_pickups.is_empty(),
		"pause-save fixture should retain at least one uncollected Gear Mod pickup"
	)
	await _verify_pause_settings_entry(pause_menu)

	var paused_time: float = GameClock.now()
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	_expect(is_equal_approx(GameClock.now(), paused_time), "GameClock should freeze while pause menu is open")
	_expect(
		paused_visual == null
		or is_equal_approx(paused_visual.animation_time(), saved_visual_time),
		"PlayerSlimeVisual should freeze while the run is paused"
	)
	var invalid_state_rng: Dictionary = RNG.snapshot()
	var invalid_state_request: Dictionary = run_loop.call(
		"request_reward_choice",
		"default_reward_choice",
		"debug_command",
		2
	) as Dictionary
	_expect(String(invalid_state_request.get("reason", "")) == "invalid_state", "reward request should reject PAUSED without an active request")
	_expect(RNG.snapshot() == invalid_state_rng, "invalid-state reward request should not consume RNG")

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
	_expect(
		(restored_player.call("weapon_recoil_velocity") as Vector2).is_equal_approx(
			saved_recoil_velocity
		),
		"continue should restore active weapon recoil velocity"
	)
	_expect(
		is_equal_approx(
			float(restored_player.call("weapon_recoil_remaining")),
			saved_recoil_remaining
		),
		"continue should restore active weapon recoil remaining time"
	)
	_expect(
		(restored_player.call("external_knockback_velocity") as Vector2).is_equal_approx(
			saved_knockback_velocity
		),
		"continue should restore active enemy knockback velocity"
	)
	_expect(
		is_equal_approx(
			float(restored_player.call("external_knockback_remaining")),
			saved_knockback_remaining
		),
		"continue should restore active enemy knockback remaining time"
	)
	var restored_attack_enemy: Node = _enemy_by_spawn_serial(
		saved_attack_serial
	)
	_expect(
		restored_attack_enemy != null
		and bool(restored_attack_enemy.call("is_armed")),
		"continue should restore an armed exploder without rerolling its state"
	)
	if restored_attack_enemy != null:
		var restored_attack_snapshot: Dictionary = restored_attack_enemy.call(
			"snapshot"
		) as Dictionary
		_expect(
			String(restored_attack_snapshot.get("action_state", ""))
			== "armed_windup"
			and is_equal_approx(
				float(restored_attack_snapshot.get("action_timer", 0.0)),
				saved_attack_timer
			),
			"continue should restore the exact remaining exploder windup"
		)
		_expect(
			_reward_snapshots_match(
				saved_attack_reward,
				restored_attack_snapshot.get("reward_snapshot", {}) as Dictionary
			),
			(
				"continue should restore the exploder reward without rerolling; "
				+ "saved=%s restored=%s"
			) % [
				saved_attack_reward,
				restored_attack_snapshot.get("reward_snapshot", {}),
			]
		)
	var restored_ranged_enemy: Node = _enemy_by_spawn_serial(
		saved_ranged_serial
	)
	_expect(
		restored_ranged_enemy != null,
		"continue should restore the saved Assault Gunner"
	)
	if restored_ranged_enemy != null:
		var restored_ranged_snapshot: Dictionary = (
			restored_ranged_enemy.call("snapshot") as Dictionary
		)
		_expect(
			String(restored_ranged_snapshot.get("action_state", ""))
			== "ranged_windup"
			and is_equal_approx(
				float(
					restored_ranged_snapshot.get(
						"action_timer",
						0.0
					)
				),
				saved_ranged_timer
			)
			and int(
				restored_ranged_snapshot.get(
					"burst_shots_remaining",
					0
				)
			) == 4,
			"continue should restore exact ranged windup timing and shots"
		)
		_expect(
			_reward_snapshots_match(
				saved_ranged_reward,
				restored_ranged_snapshot.get("reward_snapshot", {}) as Dictionary
			),
			(
				"continue should restore the Assault Gunner reward without rerolling; "
				+ "saved=%s restored=%s"
			) % [
				saved_ranged_reward,
				restored_ranged_snapshot.get("reward_snapshot", {}),
			]
		)
	_expect(int(restored_run_loop.call("current_level")) == saved_level, "continue should restore level")
	_expect(int(restored_run_loop.call("gold_balance")) == saved_gold_balance, "continue should restore gold balance")
	_expect(int(restored_run_loop.call("gold_earned_total")) == saved_gold_total, "continue should restore earned gold total")
	_expect(absf(GameClock.now() - saved_time) < 0.2, "continue should restore GameClock time")
	var restored_pause_menu: Node = _find_node_by_name(get_tree().root, "PauseMenu")
	_expect(restored_pause_menu != null, "continue should restore the pause menu when the run was saved while paused")
	var restored_snapshot: Dictionary = restored_run_loop.call("create_run_snapshot")
	var restored_economy_rng: Dictionary = (
		(
			restored_snapshot.get("rng", {}) as Dictionary
		).get("streams", {}) as Dictionary
	).get("economy", {}) as Dictionary
	_expect(
		restored_economy_rng == saved_economy_rng,
		"restoring active enemies should not consume RNG.economy"
	)
	_expect(_snapshot_has_hazards(restored_snapshot), "continue should restore finite map hazards")
	var restored_points: Dictionary = restored_snapshot.get("interest_points", {}) as Dictionary
	var restored_resource_state: Dictionary = restored_points.get("poi_resource_cache", {}) as Dictionary
	_expect(bool(restored_resource_state.get("claimed", false)), "continue should restore claimed interest point state")
	var restored_gear_mod_ranks: Dictionary = (
		restored_snapshot.get("gear_mods", {}) as Dictionary
	).get("ranks", {}) as Dictionary
	_expect(
		restored_gear_mod_ranks == saved_gear_mod_ranks,
		"continue should restore exact run-scoped Gear Mod ranks"
	)
	_expect(
		(restored_snapshot.get("gear_mod_pickups", []) as Array)
		== saved_gear_mod_pickups,
		"continue should restore exact uncollected Gear Mod pickup snapshots"
	)
	_expect(
		not bool(restored_run_loop.call(
			"_restore_run_gear_mods",
			{"ranks": {"missing_gear_mod": 0}}
		)),
		"Run v16 restore should reject unknown Gear Mod ids"
	)
	_expect(
		not bool(restored_run_loop.call(
			"_restore_run_gear_mods",
			{
				"ranks": {
					GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST: 6,
				},
			}
		)),
		"Run v16 restore should reject out-of-range Gear Mod ranks"
	)
	_expect(
		bool(restored_run_loop.call(
			"_restore_run_gear_mods",
			{"ranks": saved_gear_mod_ranks}
		)),
		"valid Gear Mod ranks should remain restorable after rejection checks"
	)
	restored_run_loop.call("_apply_run_gear_modifiers")
	var resume_button: Button = _find_node_by_name(restored_pause_menu, "ResumeButton") as Button
	_expect(resume_button != null, "restored pause menu should expose resume")
	await _wait_for_ui_active(restored_pause_menu)
	await _push_action_once(ACTIONS.UI_BACK)
	var resumed_run_loop: Node = await _wait_for_playing_run_loop()
	_expect(resumed_run_loop == restored_run_loop, "ui_back on restored pause menu should keep the same run loop")
	var restored_pickup: Node2D = _first_active_gear_mod_pickup(
		restored_run_loop
	)
	var ranks_before_restored_pickup: Dictionary = _run_gear_mod_ranks(
		restored_run_loop
	)
	var pickup_count_before_resume_interact: int = (
		_active_gear_mod_pickup_count(restored_run_loop)
	)
	_expect(
		restored_pickup != null,
		"pause-continue should remount an interactable Gear Mod pickup"
	)
	if restored_pickup != null:
		restored_player.global_position = restored_pickup.global_position
		await _push_action_once(ACTIONS.INTERACT)
		_expect(
			_active_gear_mod_pickup_count(restored_run_loop)
			== pickup_count_before_resume_interact - 1
			and _run_gear_mod_ranks(restored_run_loop)
			!= ranks_before_restored_pickup,
			"a restored Gear Mod pickup should remain collectable after continue"
		)
	return {
		"run_loop": restored_run_loop,
		"player": restored_player,
	}


func _enemy_by_spawn_serial(spawn_serial: int) -> Node:
	if spawn_serial <= 0:
		return null
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			enemy.has_method("runtime_spawn_serial")
			and int(enemy.call("runtime_spawn_serial")) == spawn_serial
		):
			return enemy
	return null


func _enemy_with_wave_key(wave_key: String) -> Node:
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if String(enemy.get_meta("wave_key", "")) == wave_key:
			return enemy
	return null


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


func _verify_no_meta_progression_entry(title_menu: Node) -> void:
	_expect(_find_node_by_name(title_menu, "MetaProfileSummaryLabel") == null, "title menu should not show legacy meta summary")
	_expect(_find_node_by_name(title_menu, "MetaProgressionButton") == null, "title menu should not expose the legacy meta progression entry")


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
	await _wait_for_ui_active(settings_panel)
	await _push_action_once(ACTIONS.UI_BACK)
	for _index: int in range(UI_TRANSITION_FRAMES):
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
	await _wait_for_ui_active(settings_panel)
	await _push_action_once(ACTIONS.UI_BACK)
	for _index: int in range(UI_TRANSITION_FRAMES):
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


func _wait_for_ui_active(node: Node) -> void:
	for _index: int in range(UI_TRANSITION_FRAMES):
		if (
			node == null
			or not is_instance_valid(node)
			or UIManager.ui_state(node) == UIManager.UIState.ACTIVE
		):
			return
		await get_tree().process_frame


func _push_action_once(action_id: String) -> void:
	InputService.set_playback_active(true)
	InputService.inject_playback_value(StringName(action_id), true)
	await get_tree().process_frame

	InputService.inject_playback_value(StringName(action_id), false)
	InputService.set_playback_active(false)
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


func _run_gear_mod_ranks(run_loop: Node) -> Dictionary:
	if run_loop == null or not run_loop.has_method("create_run_snapshot"):
		return {}
	var snapshot: Dictionary = run_loop.call("create_run_snapshot") as Dictionary
	var gear_mods: Dictionary = snapshot.get("gear_mods", {}) as Dictionary
	return (gear_mods.get("ranks", {}) as Dictionary).duplicate(true)


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
	var seed_before_restart: int = RNG.run_seed()
	await _click_button(restart_button)

	var restarted_run_loop: Node = await _wait_for_playing_run_loop()
	_expect(restarted_run_loop != null, "clicking restart should mount GameplayRunLoop")
	_expect(GameState.is_state(GameState.PLAYING), "clicking restart should resume PLAYING")
	_expect(_find_node_by_name(get_tree().root, "GameOverPanel") == null, "clicking restart should close the game-over panel")
	_expect(RNG.run_seed() != seed_before_restart, "clicking restart should generate a new run seed")
	if restarted_run_loop == null:
		return

	var restarted_player: Node2D = _find_node_by_name(restarted_run_loop, "Player") as Node2D
	_expect(restarted_player != null, "restarted run should create a player")
	if restarted_player == null:
		return

	await _expect_minor_nest_core_completion(restarted_run_loop)
	var completion_panel: Node = _find_node_by_name(get_tree().root, "GameOverPanel")
	_expect(completion_panel != null, "minor nest core completion should show the result panel")
	if completion_panel == null:
		return
	var completion_title: Label = _find_node_by_name(completion_panel, "TitleLabel") as Label
	_expect(completion_title != null and String(completion_title.text) == tr("ui_run_complete"), "completion result panel should use the localized completion title")
	var completion_summary: Label = _find_node_by_name(completion_panel, "SummaryLabel") as Label
	var completion_summary_text: String = String(completion_summary.text) if completion_summary != null else ""
	_expect(
		completion_summary != null
		and completion_summary_text.contains(tr("ui_result_no_build")),
		"completion result panel should show the empty current run build: %s" % completion_summary_text
	)
	_expect(
		_run_gear_mod_ranks(restarted_run_loop).is_empty(),
		"Mind Core completion should clear the in-memory run Gear Mod state"
	)
	var completion_restart_button: Button = _find_node_by_name(completion_panel, "RestartButton") as Button
	_expect(completion_restart_button != null, "completion panel should expose restart")
	if completion_restart_button == null:
		return
	await _click_button(completion_restart_button)

	restarted_run_loop = await _wait_for_playing_run_loop()
	_expect(restarted_run_loop != null, "restart from completion panel should mount GameplayRunLoop")
	if restarted_run_loop == null:
		return
	restarted_player = _find_node_by_name(restarted_run_loop, "Player") as Node2D
	_expect(restarted_player != null, "second restarted run should create a player")
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


func _expect_minor_nest_core_completion(run_loop: Node) -> void:
	_expect(run_loop.has_method("debug_damage_interest_point_target"), "runtime should expose minor nest core target damage hook")
	if not run_loop.has_method("debug_damage_interest_point_target"):
		return
	var core_damage: Dictionary = run_loop.call("debug_damage_interest_point_target", "poi_minor_nest_core", 9999.0) as Dictionary
	await get_tree().process_frame
	_expect(bool(core_damage.get("ok", false)), "minor nest core target damage should apply")
	_expect(GameState.is_state(GameState.GAME_OVER), "minor nest core destruction should complete the run immediately")
	_expect(not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), "minor nest core completion should consume the active run save")


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
	for _index: int in range(UI_TRANSITION_FRAMES):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if run_loop != null and GameState.is_state(expected_state):
			return run_loop
	var current_run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
	var current_top: Node = UIManager.top()
	push_error(
		"[RuntimeSmoke] state wait timed out; expected=%s current=%s run_loop=%s ui_top=%s ui_state=%s"
		% [
			String(expected_state),
			String(GameState.current()),
			"present" if current_run_loop != null else "missing",
			current_top.name if current_top != null else "<none>",
			str(UIManager.ui_state(current_top)) if current_top != null else "<none>",
		]
	)
	return null


func _defeat_player_for_game_over(run_loop: Node, player: Node2D) -> void:
	await _wait_player_vulnerability(player)
	if player.has_method("debug_set_shield"):
		player.call("debug_set_shield", 0.0, 0.0)
	if player.has_method("debug_clear_invulnerability"):
		player.call("debug_clear_invulnerability")
	var source: Node = Node.new()
	source.name = "SmokeSecondPlayerDamageSource"
	run_loop.add_child(source)
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		float(player.call("max_life")) * 10.0,
		ELEMENTS.ELEMENT_NEUTRAL,
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
	for _index: int in range(UI_TRANSITION_FRAMES):
		await get_tree().process_frame
		var title_menu: Node = _find_node_by_name(get_tree().root, "TitleMenu")
		if (
			GameState.is_state(GameState.MAIN_MENU)
			and title_menu != null
			and UIManager.ui_state(title_menu) == UIManager.UIState.ACTIVE
		):
			return
	_expect(false, "title menu should appear after quit-to-title")


func _first_enemy_with_name_prefix(name_prefix: String) -> Node:
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if String(enemy.name).begins_with(name_prefix):
			return enemy
	return null


func _array_or_empty(value: Variant) -> Array:
	if value is Array:
		return (value as Array).duplicate(true)
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	return {}


func _expect_ammunition_removed(
	run_loop: Node,
	player: Node2D
) -> void:
	var weapon: Node = player.get_node_or_null("WeaponSystem")
	_expect(weapon != null, "ammunition removal smoke requires WeaponSystem")
	if weapon == null:
		return
	_expect(
		not DataLoader.has_contract_value("pool_ids", RETIRED_AMMO_POOL_ID)
		and not PoolManager.has_pool(RETIRED_AMMO_POOL_ID),
		"ammunition pickup pool should be absent from contracts and runtime"
	)
	_expect(
		not DataLoader.has_contract_value(
			"rng_streams",
			RETIRED_AMMO_RNG_STREAM
		)
		and not (RNG.snapshot().get("streams", {}) as Dictionary).has(
			RETIRED_AMMO_RNG_STREAM
		),
		"ammunition RNG stream should be absent from contracts and snapshots"
	)
	_expect(
		InputService.action_resource(RETIRED_RELOAD_ACTION) == null,
		"reload action should be absent from InputService"
	)
	_expect(
		not player.has_node("WorldPrompt"),
		"player scene should not retain the ammunition world prompt"
	)
	var run_snapshot: Dictionary = run_loop.call("create_run_snapshot")
	var weapon_snapshot: Dictionary = _dictionary_or_empty(
		run_snapshot.get("weapon", {})
	)
	_expect(
		not run_snapshot.has("ammo_drop_misses")
		and not run_snapshot.has("ammo_magazines")
		and not weapon_snapshot.has("magazine_ammo")
		and not weapon_snapshot.has("reserve_ammo")
		and not weapon_snapshot.has("is_reloading")
		and not weapon_snapshot.has("reload_remaining"),
		"Run v12 snapshots should not contain ammunition or reload fields"
	)
	for retired_method: String in [
		"ammo_state",
		"can_accept_ammo",
		"add_ammo",
		"request_reload",
	]:
		_expect(
			not weapon.has_method(retired_method),
			"WeaponSystem should not retain %s" % retired_method
		)

	var existing_bullet_ids: Dictionary = {}
	for bullet: Node in get_tree().get_nodes_in_group("active_bullets"):
		existing_bullet_ids[bullet.get_instance_id()] = true
	var combat_rng_snapshot: Dictionary = RNG.combat.snapshot()
	var stats: Dictionary = weapon.call("_effective_runtime_stats")
	var fired_count: int = 0
	for _shot_index: int in range(31):
		if bool(weapon.call("_fire_once", stats)):
			fired_count += 1
	_expect(
		fired_count == 31,
		"WeaponSystem should fire beyond the retired 30-round boundary"
	)
	for bullet: Node in get_tree().get_nodes_in_group("active_bullets"):
		if not existing_bullet_ids.has(bullet.get_instance_id()):
			PoolManager.release(bullet)
	RNG.combat.restore_snapshot(combat_rng_snapshot)


func _active_gear_mod_pickup_count(run_loop: Node) -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(
		"active_gear_mod_pickups"
	):
		if run_loop.is_ancestor_of(node):
			count += 1
	return count


func _first_active_gear_mod_pickup(run_loop: Node) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group(
		"active_gear_mod_pickups"
	):
		if node is Node2D and run_loop.is_ancestor_of(node):
			return node as Node2D
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[RuntimeSmoke] %s" % message)


func _reward_snapshots_match(expected: Dictionary, actual: Dictionary) -> bool:
	if expected.size() != actual.size():
		return false
	if (
		bool(expected.get("valid", false))
		!= bool(actual.get("valid", false))
		or int(expected.get("gold_reward", -1))
		!= int(actual.get("gold_reward", -1))
		or int(expected.get("spawn_tier", -1))
		!= int(actual.get("spawn_tier", -1))
	):
		return false
	for field_name: String in [
		"base_coefficient",
		"difficulty_coefficient",
		"monster_value_multiplier",
		"specialization_multiplier",
		"time_multiplier",
		"random_multiplier",
	]:
		if (
			not expected.has(field_name)
			or not actual.has(field_name)
			or not is_equal_approx(
				float(expected[field_name]),
				float(actual[field_name])
			)
		):
			return false
	return true


func _finish() -> void:
	InputService.clear_playback_values()
	InputService.set_playback_active(false)
	Settings.set_value(SETTINGS_KEYS.GAMEPLAY_SCREEN_SHAKE, _original_screen_shake)
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


class NavigationProbe:
	extends Node

	var active_target_position: Vector2 = Vector2.ZERO
	var corridor_clear: bool = true
	var line_of_sight: bool = true
	var local_next_position: Vector2 = Vector2.ZERO
	var local_reachable: bool = true
	var next_position: Vector2 = Vector2.ZERO
	var path_distance: float = 0.0
	var reachable: bool = true


	func navigation_query_to_active_target(_from_position: Vector2) -> Dictionary:
		return {
			"reachable": reachable,
			"distance": path_distance if reachable else INF,
			"next_position": next_position,
			"target_position": active_target_position,
		}


	func navigation_query(_from_position: Vector2, target_position: Vector2) -> Dictionary:
		return {
			"reachable": local_reachable,
			"distance": path_distance if local_reachable else INF,
			"next_position": local_next_position,
			"target_position": target_position,
		}


	func has_terrain_line_of_sight(_from_position: Vector2, _target_position: Vector2) -> bool:
		return line_of_sight


	func has_clear_corridor(_from_position: Vector2, _target_position: Vector2, _clearance: float) -> bool:
		return corridor_clear


	func world_to_global_cell(world_position: Vector2) -> Vector2i:
		return Vector2i(roundi(world_position.x / 160.0), roundi(world_position.y / 160.0))


	func global_cell_to_world(global_cell: Vector2i) -> Vector2:
		return Vector2(global_cell) * 160.0
