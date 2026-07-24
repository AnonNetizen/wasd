# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/正式项目工作规划.md F4
class_name GameplayRunLoop
extends Node2D


signal quit_to_title_requested()
signal restart_requested()
signal restore_failed()
signal run_prepared()
signal run_prepare_failed(reason: String, restoring: bool)
signal debug_test_arena_setup_requested()

enum RunPurpose {
	STANDARD,
	DEBUG_TEST_ARENA,
}

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const DAMAGE_NUMBER_SCENE := preload("res://scenes/gameplay/damage_number.tscn")
const GAME_MODES := preload("res://scripts/contracts/game_modes.gd")
const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")
const HAZARD_SCENE := preload("res://scenes/gameplay/hazard.tscn")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const BULLET_SCENE := preload("res://scenes/gameplay/bullet.tscn")
const GAME_OVER_PANEL_SCENE := preload("res://scenes/ui/game_over_panel.tscn")
const HIT_SPARK_SCENE := preload("res://scenes/gameplay/hit_spark.tscn")
const INTEREST_POINT_CACHE_SCENE := preload("res://scenes/gameplay/interest_point_cache.tscn")
const INTEREST_POINT_TARGET_SCENE := preload("res://scenes/gameplay/interest_point_target.tscn")
const LEVEL_UP_PANEL_SCENE := preload("res://scenes/ui/level_up_panel.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const PICKUP_ORB_SCENE := preload("res://scenes/gameplay/pickup_orb.tscn")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const SKILL_RESOURCES := preload("res://scripts/contracts/skill_resources.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const VFX_CUES := preload("res://scripts/contracts/vfx_cues.gd")
const WARZONE_DIRECTOR_SCRIPT := preload("res://scripts/gameplay/warzone_director.gd")
const MODULE_PLACEMENT_TYPES := preload("res://scripts/contracts/module_placement_types.gd")
const MODULE_ROLES := preload("res://scripts/contracts/module_roles.gd")
const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")

const BULLET_POOL_SIZE: int = 192
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 160.0)
const ENEMY_POOL_SIZE: int = 96
const FEEDBACK_POOL_SIZE: int = 128
const HAZARD_POOL_SIZE: int = 32
const PICKUP_POOL_SIZE: int = 128
const RUN_SNAPSHOT_SCHEMA_VERSION: int = 4
const ACTIVE_POOL_GROUPS: Array[String] = ["active_hazards", "active_enemies", "active_bullets", "active_pickups"]
const UI_RESTORE_LEVEL_UP: String = "level_up"
const UI_RESTORE_PAUSED: String = "paused"
const UI_RESTORE_PLAYING: String = "playing"
const UI_RESTORE_UNDERLYING_STATE: String = "underlying_state"
const INPUT_PARTICIPANT_ID: String = "player_0"
const DEFAULT_DEBUG_GROWTH_POOL: String = "default_level_up"
const LOADING_BATCH_SIZE: int = 8
const NAVIGATION_FLOW_OBSTACLE_BUFFER_CELLS: int = 2
const PRESENTATION_ENEMY_DEFAULT: String = "presentation_enemy_default"
const PRESENTATION_GAMEPLAY_DEFAULT: String = "presentation_gameplay_default"
const PRESENTATION_HAZARD_DEFAULT: String = "presentation_hazard_default"
const PRESENTATION_PICKUP_DEFAULT: String = "presentation_pickup_default"
const PRESENTATION_PLAYER_DEFAULT: String = "presentation_player_default"
const PRESENTATION_SKILL_DEFAULT: String = "presentation_skill_default"
const PRESENTATION_SKILL_OVERDRIVE: String = "presentation_skill_overdrive"
const PRESENTATION_STATUS_DEFAULT: String = "presentation_status_default"
const DEBUG_TEST_ARENA_AI: String = "ai"
const DEBUG_TEST_ARENA_STATIONARY: String = "stationary"

@export_group("Extraction Visual Style")
@export var extraction_zone_fill_color: Color = Color(0.18, 0.82, 0.68, 0.16)
@export var extraction_zone_progress_color: Color = Color(0.38, 0.96, 0.78, 0.35)
@export var extraction_zone_ring_color: Color = Color(0.38, 0.96, 0.78, 0.92)
@export_range(0.5, 12.0, 0.1) var extraction_zone_ring_width: float = 4.0

var _active_world: Node2D = null
var _actor_scene_cache: Dictionary = {}
var _camera_controller: Node2D = null
var _character_id: String = CHARACTER_IDS.CHARACTER_DEFAULT
var _current_level: int = 1
var _current_xp: int = 0
var _enemy_rows: Dictionary = {}
var _extraction_active: bool = false
var _extraction_hold_time: float = 0.0
var _extraction_position: Vector2 = Vector2.ZERO
var _extraction_progress: float = 0.0
var _extraction_radius: float = 0.0
var _extraction_source_point_id: String = ""
var _growth_curve: Array[Dictionary] = []
var _growth_entries: Array[Dictionary] = []
var _gameplay_feedback: GameplayFeedbackController = null
var _game_over_panel: CanvasLayer = null
var _hazard_rows: Dictionary = {}
var _hud: CanvasLayer = null
var _interest_point_caches: Dictionary = {}
var _interest_points: Dictionary = {}
var _interest_point_targets: Dictionary = {}
var _kills: int = 0
var _level_panel: CanvasLayer = null
var _pending_loot: Dictionary = {}
var _pending_level_up_choices: Array[Dictionary] = []
var _pending_restore_snapshot: Dictionary = {}
var _pause_menu: CanvasLayer = null
var _player: CharacterBody2D = null
var _player_host: Node2D = null
var _map_layout: Dictionary = {}
var _map_manager: Node2D = null
var _module_extraction_point_id: String = ""
var _module_world_definition: Dictionary = {}
var _module_world_enabled: bool = true
var _module_world_technical_slice: bool = false
var _module_world_manager: Node2D = null
var _settings_panel: CanvasLayer = null
var _skill_system: Node = null
var _spawn_states: Dictionary = {}
var _debug_next_gear_mod_drop_forced_roll: float = -1.0
var _debug_test_arena_config: Dictionary = {}
var _debug_test_arena_controller: Node = null
var _run_completed: bool = false
var _run_purpose: RunPurpose = RunPurpose.STANDARD
var _warzone_director = null
var _waves: Array[Dictionary] = []
var _weapon_system: Node = null
var _vfx_host: VfxHost = null
var _requested_character_id: String = CHARACTER_IDS.CHARACTER_DEFAULT
var _registered_enemy_pool_ids: Array[String] = []
var _player_loading_mode: bool = false
var _run_activated: bool = false
var _run_prepared: bool = false
var _run_start_failed: bool = false
var _pending_ui_restore: Dictionary = {}


func _ready() -> void:
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)
	_start_run(_pending_restore_snapshot)


func _exit_tree() -> void:
	if InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.disconnect(_on_input_action_pressed)
	_clear_interest_point_caches()
	_release_active_world_pool_entities()
	if _vfx_host != null:
		_vfx_host.cancel_all()
	if Combat.damage_applied.is_connected(_on_combat_damage_applied):
		Combat.damage_applied.disconnect(_on_combat_damage_applied)


func _draw() -> void:
	if not _extraction_active:
		return
	var half_extents: Vector2 = _extraction_half_extents()
	var zone_points: PackedVector2Array = PackedVector2Array([
		_extraction_position + Vector2(-half_extents.x, -half_extents.y),
		_extraction_position + Vector2(half_extents.x, -half_extents.y),
		_extraction_position + Vector2(half_extents.x, half_extents.y),
		_extraction_position + Vector2(-half_extents.x, half_extents.y),
	])
	draw_colored_polygon(zone_points, extraction_zone_fill_color)
	_draw_polygon_outline(zone_points, extraction_zone_ring_color, extraction_zone_ring_width)
	var progress_ratio: float = clampf(_extraction_progress / maxf(_extraction_hold_time, 0.001), 0.0, 1.0)
	if progress_ratio > 0.0:
		var progress_half_extents: Vector2 = half_extents * progress_ratio
		if progress_half_extents.x >= 0.5 and progress_half_extents.y >= 0.5:
			draw_rect(
				Rect2(_extraction_position - progress_half_extents, progress_half_extents * 2.0),
				extraction_zone_progress_color,
				true
			)


func _process(delta: float) -> void:
	_update_stats_panel()
	if not GameState.is_state(GameState.PLAYING):
		return
	if _is_debug_test_arena():
		return
	if _module_world_enabled:
		_update_module_world()
	_update_interest_points()
	if not GameState.is_state(GameState.PLAYING):
		return
	_update_extraction(delta)
	if not GameState.is_state(GameState.PLAYING):
		return
	if not _module_world_enabled:
		_update_spawner()


func _on_input_action_pressed(action_id: StringName, participant_id: String) -> void:
	if participant_id != INPUT_PARTICIPANT_ID:
		return
	if _is_debug_test_arena():
		if (
			GameState.is_state(GameState.PLAYING)
			and action_id == StringName(ACTIONS.PAUSE)
			and _debug_test_arena_controller != null
		):
			_debug_test_arena_controller.call("open_panel")
		return
	if GameState.is_state(GameState.PLAYING):
		if action_id == StringName(ACTIONS.INTERACT):
			_try_interact_interest_point()
			return
		if action_id == StringName(ACTIONS.PAUSE):
			_show_pause_menu()
			return
	if GameState.is_state(GameState.GAME_OVER) and action_id == StringName(ACTIONS.PAUSE):
		restart_requested.emit()


func configure_restore_snapshot(snapshot_data: Dictionary) -> void:
	_pending_restore_snapshot = snapshot_data.duplicate(true)


## Must be called before the run loop enters the scene tree.
func configure_debug_test_arena(config: Dictionary) -> void:
	if is_inside_tree():
		push_error(
			"[GameplayRunLoop] debug test arena must be configured before entering tree"
		)
		return
	_run_purpose = RunPurpose.DEBUG_TEST_ARENA
	_debug_test_arena_config = config.duplicate(true)
	_module_world_enabled = false


## Must be called before the run loop enters the scene tree.
func configure_character_id(character_id: String) -> void:
	_requested_character_id = character_id


## Enables the user-facing cooperative loading path. Headless and replay tools keep
## the synchronous path unless their harness explicitly opts in.
func configure_player_loading_mode(enabled: bool) -> void:
	_player_loading_mode = enabled


func activate_prepared_run() -> bool:
	if not _run_prepared or _run_activated or _run_start_failed:
		return false
	_run_activated = true
	GameState.change_state(GameState.PLAYING, {
		"mode": GAME_MODES.MODE_STANDARD_SURVIVAL,
		"character": _character_id,
		"run_purpose": (
			"debug_test_arena"
			if _is_debug_test_arena()
			else "standard"
		),
	})
	if (
		_is_debug_test_arena()
		and _debug_test_arena_controller != null
		and _debug_test_arena_controller.has_method("activate")
	):
		_debug_test_arena_controller.call("activate")
	if not _pending_ui_restore.is_empty():
		_restore_ui_state(_pending_ui_restore)
	_pending_ui_restore.clear()
	return true


func debug_force_next_gear_mod_drop_roll(roll: float) -> void:
	_debug_next_gear_mod_drop_forced_roll = roll


## Regression-only toggle. The module world is the standard carrier; F12 open-warzone
## behavior remains opt-in so old runtime and golden comparisons can still be exercised.
func debug_enable_open_warzone() -> void:
	_module_world_enabled = false


func debug_enable_module_world_technical_slice() -> void:
	_module_world_enabled = true
	_module_world_technical_slice = true


func debug_enable_level_up_growth(pool_id: String = DEFAULT_DEBUG_GROWTH_POOL) -> void:
	_growth_curve = _load_growth_curve()
	_growth_entries = _load_growth_entries({
		"resource_pools": {
			"growth_pools": [
				{
					"id": pool_id,
					"weight": 100,
				},
			],
		},
	})
	_refresh_xp_hud()


func create_run_snapshot() -> Dictionary:
	if _is_debug_test_arena():
		return {}
	return {
		"schema_version": RUN_SNAPSHOT_SCHEMA_VERSION,
		"mode": GAME_MODES.MODE_STANDARD_SURVIVAL,
		"character": _character_id,
		"level": _current_level,
		"xp": _current_xp,
		"kills": _kills,
		"game_clock": GameClock.snapshot(),
		"rng": RNG.snapshot(),
		"map": _map_manager.call("snapshot") if _map_manager != null and _map_manager.has_method("snapshot") else {},
		"interest_points": _interest_points_snapshot(),
		"extraction": _extraction_snapshot(),
		"pending_loot": _pending_loot.duplicate(true),
		"spawn_states": _spawn_states.duplicate(true),
		"player": _player.call("snapshot") if _player != null and _player.has_method("snapshot") else {},
		"weapon": _weapon_system.call("snapshot") if _weapon_system != null and _weapon_system.has_method("snapshot") else {},
		"skills": _skill_system.call("snapshot") if _skill_system != null and _skill_system.has_method("snapshot") else {},
		"hazards": _entity_snapshots("active_hazards"),
		"enemies": _entity_snapshots("active_enemies"),
		"bullets": _entity_snapshots("active_bullets"),
		"pickups": _entity_snapshots("active_pickups"),
		"module_world": _module_world_snapshot(),
		"ui_restore": _ui_restore_snapshot(),
	}


func _start_run(restore_snapshot: Dictionary = {}) -> void:
	GameClock.reset()
	_active_world = get_node_or_null("ActiveWorld") as Node2D
	if _active_world == null:
		_fail_run_start("missing ActiveWorld scene node", not restore_snapshot.is_empty())
		return
	if _is_debug_test_arena():
		_debug_test_arena_controller = get_node_or_null(
			"DebugTestArenaController"
		)
		if (
			_debug_test_arena_controller == null
			or not _debug_test_arena_controller.has_method("map_layout")
		):
			_fail_run_start(
				"missing DebugTestArenaController scene node",
				false
			)
			return
	_vfx_host = _active_world.get_node_or_null("VfxHost") as VfxHost
	_gameplay_feedback = get_node_or_null("GameplayFeedbackController") as GameplayFeedbackController
	if _vfx_host == null or _gameplay_feedback == null:
		_fail_run_start(
			"missing VfxHost or GameplayFeedbackController scene node",
			not restore_snapshot.is_empty()
		)
		return
	_gameplay_feedback.configure_host(_vfx_host)
	_camera_controller = _active_world.get_node_or_null("GameplayCameraController") as Node2D
	if _camera_controller == null or not _camera_controller.has_method("configure"):
		_fail_run_start(
			"missing or invalid GameplayCameraController scene node",
			not restore_snapshot.is_empty()
		)
		return
	var enemy_csv_rows: Array[Dictionary] = DataLoader.load_csv(DataLoader.ENEMIES_PATH)
	PoolManager.clear_pool(POOL_IDS.BULLET_BASIC)
	_clear_enemy_pools(enemy_csv_rows)
	PoolManager.clear_pool(POOL_IDS.HAZARD_SPIKE)
	PoolManager.clear_pool(POOL_IDS.HIT_SPARK)
	PoolManager.clear_pool(POOL_IDS.DAMAGE_NUMBER)
	PoolManager.clear_pool(POOL_IDS.PICKUP_ORB)
	PoolManager.clear_pool(POOL_IDS.VFX_WEAPON_MUZZLE_FLASH)
	var configured_character_id: String = String(
		_debug_test_arena_config.get(
			"character_id",
			_requested_character_id
		)
	)
	var selected_character_id: String = String(
		restore_snapshot.get(
			"character",
			configured_character_id
			if _is_debug_test_arena()
			else _requested_character_id
		)
	).strip_edges()
	var character: Dictionary = _find_item(
		_load_array(DataLoader.CHARACTERS_PATH, "characters"),
		selected_character_id
	)
	if character.is_empty():
		_fail_run_start(
			"unknown character id: %s" % selected_character_id,
			not restore_snapshot.is_empty()
		)
		return
	_character_id = selected_character_id
	_enemy_rows = _load_enemy_rows(_load_enemy_ai_profiles(), enemy_csv_rows)
	var actor_scenes_ready: bool = false
	if _player_loading_mode:
		actor_scenes_ready = await _preload_actor_scenes_threaded(character)
	else:
		actor_scenes_ready = _preload_actor_scenes(character)
	if not actor_scenes_ready:
		_fail_run_start("actor scene preload failed", not restore_snapshot.is_empty())
		return

	PoolManager.register_pool(POOL_IDS.BULLET_BASIC, _create_bullet_node, BULLET_POOL_SIZE)
	var enemy_pools_ready: bool = false
	if _player_loading_mode:
		enemy_pools_ready = await _register_enemy_pools_staged()
	else:
		enemy_pools_ready = _register_enemy_pools()
	if not enemy_pools_ready:
		_fail_run_start("enemy pool registration failed", not restore_snapshot.is_empty())
		return
	PoolManager.register_pool(POOL_IDS.HAZARD_SPIKE, _create_hazard_node, HAZARD_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.HIT_SPARK, _create_hit_spark_node, FEEDBACK_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.DAMAGE_NUMBER, _create_damage_number_node, FEEDBACK_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.PICKUP_ORB, _create_pickup_orb_node, PICKUP_POOL_SIZE)
	if not _vfx_host.register_declared_pools():
		_fail_run_start("VFX pool registration failed", not restore_snapshot.is_empty())
		return
	if _player_loading_mode:
		if not await _prewarm_standard_pools_staged():
			_fail_run_start("pool prewarm interrupted", not restore_snapshot.is_empty())
			return
	else:
		_prewarm_standard_pools()
	if not Combat.damage_applied.is_connected(_on_combat_damage_applied):
		Combat.damage_applied.connect(_on_combat_damage_applied)

	_map_manager = _active_world.get_node_or_null("MapManager") as Node2D
	if _map_manager == null:
		push_error("[GameplayRunLoop] missing MapManager scene node")
		return

	var mode: Dictionary = _find_item(_load_array(DataLoader.GAME_MODES_PATH, "modes"), GAME_MODES.MODE_STANDARD_SURVIVAL)
	var player_stats: Dictionary = _merged_player_stats(character, mode)
	var raw_loadout: Variant = character.get("starting_loadout", {})
	var loadout: Dictionary = (
		(raw_loadout as Dictionary).duplicate(true)
		if raw_loadout is Dictionary
		else {}
	)
	if _is_debug_test_arena():
		loadout["weapon_id"] = String(
			_debug_test_arena_config.get(
				"weapon_id",
				loadout.get("weapon_id", "")
			)
		)
		loadout["skill_ids"] = [
			String(
				_debug_test_arena_config.get(
					"primary_skill_id",
					""
				)
			),
		]
	var weapon: Dictionary = _find_item(
		_load_array(DataLoader.WEAPONS_PATH, "weapons"),
		String(loadout.get("weapon_id", ""))
	)

	_hazard_rows = _load_hazard_rows()
	if _is_debug_test_arena():
		_map_layout = _debug_test_arena_controller.call(
			"map_layout"
		) as Dictionary
	elif _module_world_enabled:
		var module_world_ready: bool = false
		if _player_loading_mode:
			module_world_ready = await _configure_module_world(restore_snapshot, true)
		else:
			module_world_ready = await _configure_module_world(restore_snapshot)
		if not module_world_ready:
			push_error("[GameplayRunLoop] failed to configure module world")
			_fail_run_start("module world configuration failed", not restore_snapshot.is_empty())
			return
		_map_layout = _module_world_map_layout()
	else:
		_map_layout = _load_map_layout(GAME_MODES.MODE_STANDARD_SURVIVAL)
	if _is_debug_test_arena():
		_growth_curve.clear()
		_growth_entries.clear()
		_waves.clear()
	else:
		_growth_curve = _load_growth_curve()
		_growth_entries = _load_growth_entries(mode)
		_waves = _load_waves(GAME_MODES.MODE_STANDARD_SURVIVAL)
	if _module_world_enabled or _is_debug_test_arena():
		_warzone_director = null
	else:
		_warzone_director = WARZONE_DIRECTOR_SCRIPT.new()
		_warzone_director.configure(GAME_MODES.MODE_STANDARD_SURVIVAL, _load_warzone_director(GAME_MODES.MODE_STANDARD_SURVIVAL), _waves)
	_spawn_states.clear()
	_clear_interest_point_caches()
	_interest_points.clear()
	_interest_point_caches.clear()
	_interest_point_targets.clear()
	_current_level = 1
	_current_xp = 0
	_kills = 0
	_pending_loot = _empty_pending_loot()
	_reset_extraction()
	_run_completed = false

	_player_host = _active_world.get_node_or_null("PlayerHost") as Node2D
	if _player_host == null:
		_fail_run_start("missing PlayerHost scene node", not restore_snapshot.is_empty())
		return
	_player = _instantiate_character(character)
	if _player == null:
		_fail_run_start(
			"character scene root must be CharacterBody2D",
			not restore_snapshot.is_empty()
		)
		return
	_player.global_position = Vector2.ZERO
	_player.call("configure", player_stats)
	_configure_actor_presentation_profile(
		_player,
		String(character.get("presentation_profile_id", ""))
	)
	_map_manager.call("configure", _map_layout, _hazard_rows)
	var map_player_start: Vector2 = _map_manager.call("player_start")
	_player.global_position = map_player_start
	_apply_player_movement_bounds()
	var camera_feedback: Dictionary = DataLoader.load_json(DataLoader.CAMERA_FEEDBACK_PATH)
	_camera_controller.call("configure", _player, camera_feedback)
	_player.connect("life_changed", Callable(self, "_on_player_life_changed"))
	_player.connect("died", Callable(self, "_on_player_died"), CONNECT_ONE_SHOT)
	_connect_status_feedback(_player)
	_play_feedback(_actor_profile_id(_player, PRESENTATION_PLAYER_DEFAULT), VFX_CUES.SPAWN, {
		"owner": _player,
		"world_position": _player.global_position,
	})

	var background: Node2D = _active_world.get_node_or_null("WorldBackground") as Node2D
	if background == null:
		push_error("[GameplayRunLoop] missing WorldBackground scene node")
		return
	background.call("configure", _player, _map_grid_cell_size())

	_weapon_system = _player.get_node_or_null("WeaponSystem")
	if _weapon_system == null:
		push_error("[GameplayRunLoop] missing WeaponSystem scene node")
		return
	_weapon_system.call("configure", _player, _active_world, weapon)
	_connect_weapon_feedback()
	_configure_skill_system(character, loadout)
	_apply_loadout_modifiers()

	_hud = get_node_or_null("GameplayHud") as CanvasLayer
	if _hud == null:
		push_error("[GameplayRunLoop] missing GameplayHud scene node")
		return
	_hud.call("set_life", _player.call("current_life"), _player.call("max_life"))
	_hud.call("set_kills", _kills)
	_hud.call("set_level", _current_level)
	_refresh_xp_hud()
	if _is_debug_test_arena():
		_hud.visible = false
		_debug_test_arena_controller.call(
			"configure",
			self,
			_player,
			_skill_system,
			_weapon_system,
			_enemy_rows_array()
		)

	if not restore_snapshot.is_empty():
		var restore_succeeded: bool = false
		if _player_loading_mode:
			restore_succeeded = await _restore_run_snapshot(restore_snapshot, true)
		else:
			restore_succeeded = await _restore_run_snapshot(restore_snapshot)
		if not restore_succeeded:
			_fail_run_start("run snapshot restore failed", true)
			return
		_pending_ui_restore = _dictionary_or_empty(
			restore_snapshot.get("ui_restore", {})
		).duplicate(true)
	elif _is_debug_test_arena():
		pass
	elif _module_world_enabled:
		if _player_loading_mode:
			if not await _start_module_world_fresh_staged():
				_fail_run_start("module world activation interrupted", false)
				return
		else:
			_start_module_world_fresh()
	else:
		var hazard_placements: Array[Dictionary] = _generate_map_hazard_placements()
		_configure_interest_points(hazard_placements)
		_spawn_map_hazards(hazard_placements)
		_spawn_interest_point_caches()
		_spawn_interest_point_targets()
		if _player_loading_mode and not await _yield_loading_frame():
			_fail_run_start("open warzone activation interrupted", false)
			return

	_run_prepared = true
	if _player_loading_mode:
		run_prepared.emit()
	else:
		activate_prepared_run()


func _create_bullet_node() -> Node:
	return BULLET_SCENE.instantiate()


func _create_actor_node(scene_path: String) -> Node:
	var actor_scene: PackedScene = _actor_scene_cache.get(scene_path, null) as PackedScene
	if actor_scene == null:
		push_error("[GameplayRunLoop] actor scene was not preloaded: %s" % scene_path)
		return null
	return actor_scene.instantiate()


func _instantiate_character(character: Dictionary) -> CharacterBody2D:
	var scene_path: String = String(character.get("scene_path", ""))
	var raw_node: Node = _create_actor_node(scene_path)
	if not raw_node is CharacterBody2D:
		if raw_node != null:
			raw_node.free()
		return null
	var player: CharacterBody2D = raw_node as CharacterBody2D
	player.name = "Player"
	_player_host.add_child(player)
	return player


func _preload_actor_scenes(character: Dictionary) -> bool:
	_actor_scene_cache.clear()
	if not _cache_actor_scene(String(character.get("scene_path", ""))):
		return false
	for raw_enemy_data: Variant in _enemy_rows.values():
		if not raw_enemy_data is Dictionary:
			continue
		var enemy_data: Dictionary = raw_enemy_data as Dictionary
		if not _cache_actor_scene(String(enemy_data.get("scene_path", ""))):
			return false
	return true


func _preload_actor_scenes_threaded(character: Dictionary) -> bool:
	var scene_paths: Array[String] = [String(character.get("scene_path", ""))]
	for raw_enemy_data: Variant in _enemy_rows.values():
		if not raw_enemy_data is Dictionary:
			continue
		var enemy_data: Dictionary = raw_enemy_data as Dictionary
		scene_paths.append(String(enemy_data.get("scene_path", "")))
	var load_result: Dictionary = await _load_packed_scenes_threaded(scene_paths)
	if not bool(load_result.get("ok", false)):
		return false
	_actor_scene_cache = _dictionary_or_empty(
		load_result.get("resources", {})
	).duplicate()
	return true


func _cache_actor_scene(scene_path: String) -> bool:
	if scene_path.is_empty():
		push_error("[GameplayRunLoop] actor scene path is empty")
		return false
	if _actor_scene_cache.has(scene_path):
		return true
	var loaded_resource: Resource = ResourceLoader.load(scene_path, "PackedScene")
	if not loaded_resource is PackedScene:
		push_error("[GameplayRunLoop] actor scene is not a PackedScene: %s" % scene_path)
		return false
	_actor_scene_cache[scene_path] = loaded_resource
	return true


func _load_packed_scenes_threaded(scene_paths: Array[String]) -> Dictionary:
	var unique_paths: Array[String] = []
	for raw_path: String in scene_paths:
		var scene_path: String = raw_path.strip_edges()
		if scene_path.is_empty():
			push_error("[GameplayRunLoop] threaded scene path is empty")
			return {"ok": false, "resources": {}}
		if not unique_paths.has(scene_path):
			unique_paths.append(scene_path)

	var resources: Dictionary = {}
	var requested_paths: Array[String] = []
	for scene_path: String in unique_paths:
		if ResourceLoader.has_cached(scene_path):
			var cached_resource: Resource = ResourceLoader.load(scene_path, "PackedScene")
			if not cached_resource is PackedScene:
				push_error("[GameplayRunLoop] cached resource is not a PackedScene: %s" % scene_path)
				return {"ok": false, "resources": {}}
			resources[scene_path] = cached_resource
			continue
		var request_error: Error = ResourceLoader.load_threaded_request(
			scene_path,
			"PackedScene",
			false
		)
		if request_error != OK and request_error != ERR_BUSY:
			push_error(
				"[GameplayRunLoop] threaded scene request failed for %s: %s"
				% [scene_path, error_string(request_error)]
			)
			return {"ok": false, "resources": {}}
		requested_paths.append(scene_path)

	while not requested_paths.is_empty():
		for path_index: int in range(requested_paths.size() - 1, -1, -1):
			var scene_path: String = requested_paths[path_index]
			var load_status: int = ResourceLoader.load_threaded_get_status(scene_path)
			if load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue
			if load_status != ResourceLoader.THREAD_LOAD_LOADED:
				push_error("[GameplayRunLoop] threaded scene load failed: %s" % scene_path)
				return {"ok": false, "resources": {}}
			var loaded_resource: Resource = ResourceLoader.load_threaded_get(scene_path)
			if not loaded_resource is PackedScene:
				push_error("[GameplayRunLoop] threaded resource is not a PackedScene: %s" % scene_path)
				return {"ok": false, "resources": {}}
			resources[scene_path] = loaded_resource
			requested_paths.remove_at(path_index)
		if not requested_paths.is_empty() and not await _yield_loading_frame():
			return {"ok": false, "resources": {}}

	return {"ok": true, "resources": resources}


func _register_enemy_pools() -> bool:
	_registered_enemy_pool_ids.clear()
	for raw_enemy_data: Variant in _enemy_rows.values():
		if not raw_enemy_data is Dictionary:
			continue
		var enemy_data: Dictionary = raw_enemy_data as Dictionary
		if not _register_enemy_pool(enemy_data):
			_rollback_registered_enemy_pools()
			return false
		PoolManager.prewarm(
			String(enemy_data.get("pool_id", "")),
			int(enemy_data.get("pool_prewarm", 0))
		)
	return true


func _register_enemy_pools_staged() -> bool:
	_registered_enemy_pool_ids.clear()
	for raw_enemy_data: Variant in _enemy_rows.values():
		if not raw_enemy_data is Dictionary:
			continue
		var enemy_data: Dictionary = raw_enemy_data as Dictionary
		if not _register_enemy_pool(enemy_data):
			_rollback_registered_enemy_pools()
			return false
		if not await _prewarm_pool_staged(
			String(enemy_data.get("pool_id", "")),
			int(enemy_data.get("pool_prewarm", 0))
		):
			_rollback_registered_enemy_pools()
			return false
	return true


func _register_enemy_pool(enemy_data: Dictionary) -> bool:
	var pool_id: String = String(enemy_data.get("pool_id", ""))
	var scene_path: String = String(enemy_data.get("scene_path", ""))
	if pool_id.is_empty() or _registered_enemy_pool_ids.has(pool_id):
		push_error("[GameplayRunLoop] invalid or duplicate enemy pool id: %s" % pool_id)
		return false
	var factory: Callable = Callable(self, "_create_actor_node").bind(scene_path)
	if not PoolManager.register_pool(pool_id, factory, ENEMY_POOL_SIZE):
		return false
	_registered_enemy_pool_ids.append(pool_id)
	return true


func _prewarm_standard_pools() -> void:
	PoolManager.prewarm(POOL_IDS.BULLET_BASIC, 24)
	PoolManager.prewarm(POOL_IDS.HAZARD_SPIKE, 8)
	PoolManager.prewarm(POOL_IDS.PICKUP_ORB, 16)
	for request: Dictionary in _vfx_host.declared_pool_requests():
		PoolManager.prewarm(
			String(request.get("pool_id", "")),
			int(request.get("count", 0))
		)


func _prewarm_standard_pools_staged() -> bool:
	var requests: Array[Dictionary] = [
		{"pool_id": POOL_IDS.BULLET_BASIC, "count": 24},
		{"pool_id": POOL_IDS.HAZARD_SPIKE, "count": 8},
		{"pool_id": POOL_IDS.PICKUP_ORB, "count": 16},
	]
	requests.append_array(_vfx_host.declared_pool_requests())
	for request: Dictionary in requests:
		if not await _prewarm_pool_staged(
			String(request.get("pool_id", "")),
			int(request.get("count", 0))
		):
			return false
	return true


func _prewarm_pool_staged(pool_id: String, count: int) -> bool:
	var remaining: int = maxi(count, 0)
	while remaining > 0:
		var batch_size: int = mini(remaining, LOADING_BATCH_SIZE)
		var created_count: int = PoolManager.prewarm(pool_id, batch_size)
		if created_count != batch_size:
			push_error(
				"[GameplayRunLoop] staged pool prewarm failed for %s: %d/%d"
				% [pool_id, created_count, batch_size]
			)
			return false
		remaining -= created_count
		if not await _yield_loading_frame():
			return false
	return true


func _rollback_registered_enemy_pools() -> void:
	for pool_id: String in _registered_enemy_pool_ids:
		PoolManager.clear_pool(pool_id)
	_registered_enemy_pool_ids.clear()


func _clear_enemy_pools(enemy_csv_rows: Array[Dictionary]) -> void:
	var pool_ids: Dictionary = {}
	for pool_id: String in _registered_enemy_pool_ids:
		pool_ids[pool_id] = true
	for enemy_row: Dictionary in enemy_csv_rows:
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		if not pool_id.is_empty():
			pool_ids[pool_id] = true
	for raw_pool_id: Variant in pool_ids.keys():
		PoolManager.clear_pool(String(raw_pool_id))
	_registered_enemy_pool_ids.clear()


func _fail_run_start(message: String, restoring: bool) -> void:
	if _run_start_failed:
		return
	_run_start_failed = true
	push_error("[GameplayRunLoop] %s" % message)
	if _player_loading_mode:
		run_prepare_failed.emit(message, restoring)
	if restoring:
		restore_failed.emit()


func _yield_loading_frame() -> bool:
	if not _player_loading_mode:
		return true
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	await tree.process_frame
	return is_instance_valid(self) and is_inside_tree()


func _create_hazard_node() -> Node:
	return HAZARD_SCENE.instantiate()


func _create_hit_spark_node() -> Node:
	return HIT_SPARK_SCENE.instantiate()


func _create_damage_number_node() -> Node:
	return DAMAGE_NUMBER_SCENE.instantiate()


func _create_pickup_orb_node() -> Node:
	return PICKUP_ORB_SCENE.instantiate()


func _configure_skill_system(
	character: Dictionary,
	loadout_override: Dictionary = {}
) -> void:
	_skill_system = get_node_or_null("SkillSystem")
	if _skill_system == null:
		push_error("[GameplayRunLoop] missing scene-authored SkillSystem")
		return
	var raw_loadout: Variant = character.get("starting_loadout", {})
	var loadout: Dictionary = (
		loadout_override.duplicate(true)
		if not loadout_override.is_empty()
		else (
			(raw_loadout as Dictionary).duplicate(true)
			if raw_loadout is Dictionary
			else {}
		)
	)
	_skill_system.call(
		"configure",
		_player,
		_active_world,
		_load_skill_definitions(loadout),
		_typed_dictionary_array(character.get("skill_resources", []))
	)
	var cast_callback: Callable = Callable(self, "_on_skill_cast")
	if not _skill_system.is_connected("skill_cast", cast_callback):
		_skill_system.connect("skill_cast", cast_callback)
	var failed_callback: Callable = Callable(self, "_on_skill_failed")
	if not _skill_system.is_connected("skill_failed", failed_callback):
		_skill_system.connect("skill_failed", failed_callback)
	_connect_status_feedback(_skill_system)


func current_level() -> int:
	return _current_level


func current_xp() -> int:
	return _current_xp


func current_level_xp() -> int:
	if not _has_level_up_growth():
		return 0
	return _xp_progress_for_level(_current_level)


func current_level_xp_required() -> int:
	if not _has_level_up_growth():
		return 0
	return _xp_required_within_level(_current_level)


func debug_summary() -> Dictionary:
	return {
		"level": _current_level,
		"xp": _current_xp,
		"level_xp": current_level_xp(),
		"level_xp_required": current_level_xp_required(),
		"level_up_growth_enabled": _has_level_up_growth(),
		"kills": _kills,
		"player_life": float(_player.call("current_life")) if _player != null and _player.has_method("current_life") else 0.0,
		"player_max_life": float(_player.call("max_life")) if _player != null and _player.has_method("max_life") else 0.0,
		"active_enemies": _active_enemy_count(),
		"active_hazards": PoolManager.active_count(POOL_IDS.HAZARD_SPIKE),
		"interest_points": _interest_point_debug_summary(),
		"extraction": _extraction_snapshot(),
		"pending_loot": _pending_loot.duplicate(true),
		"map": _map_manager.call("debug_summary") if _map_manager != null and _map_manager.has_method("debug_summary") else {},
		"module_world": _module_world_manager.call("debug_summary") if _module_world_manager != null and _module_world_manager.has_method("debug_summary") else {},
		"skills": _skill_system.call("debug_summary") if _skill_system != null and _skill_system.has_method("debug_summary") else {},
		"warzone_director": _warzone_director.debug_summary(GameClock.now()) if _warzone_director != null else {},
	}


func debug_spawn_enemy(enemy_id: String, count: int = 1) -> Dictionary:
	if _active_world == null or _player == null:
		return _debug_result(false, "run_not_ready")
	if not _enemy_rows.has(enemy_id):
		return _debug_result(false, "unknown_enemy")
	var spawn_count: int = clampi(count, 1, ENEMY_POOL_SIZE)
	var spawned: int = 0
	var wave_key: String = "debug_%s" % enemy_id
	var state: Dictionary = _spawn_states.get(wave_key, {
		"next_time": GameClock.now(),
		"spawned": 0,
		"alive": 0,
	})
	for _index: int in range(spawn_count):
		if _spawn_enemy({"enemy_id": enemy_id}, wave_key):
			spawned += 1
	state["spawned"] = int(state.get("spawned", 0)) + spawned
	state["alive"] = int(state.get("alive", 0)) + spawned
	state["next_time"] = GameClock.now()
	_spawn_states[wave_key] = state
	return {
		"ok": spawned > 0,
		"reason": "" if spawned > 0 else "pool_unavailable",
		"spawned": spawned,
	}


func debug_give_xp(amount: int) -> Dictionary:
	var applied_amount: int = maxi(amount, 0)
	if applied_amount <= 0:
		return _debug_result(false, "non_positive_amount")
	_on_pickup_orb_collected(applied_amount)
	return {
		"ok": true,
		"xp": _current_xp,
		"level": _current_level,
	}


func debug_heal_player(amount: float) -> Dictionary:
	if _player == null or not _player.has_method("debug_heal"):
		return _debug_result(false, "player_unavailable")
	var result: Dictionary = _player.call("debug_heal", amount)
	result["ok"] = true
	return result


func debug_set_player_hp(amount: float) -> Dictionary:
	if _player == null or not _player.has_method("debug_set_life"):
		return _debug_result(false, "player_unavailable")
	var result: Dictionary = _player.call("debug_set_life", amount)
	result["ok"] = true
	return result


func debug_damage_player(amount: float) -> Dictionary:
	if _player == null:
		return _debug_result(false, "player_unavailable")
	var applied_amount: float = maxf(amount, 0.0)
	if applied_amount <= 0.0:
		return _debug_result(false, "non_positive_amount")
	if _player.has_method("debug_clear_invulnerability"):
		_player.call("debug_clear_invulnerability")
	var result: Dictionary = Combat.apply_damage(_player, _damage_info(applied_amount, _player))
	return {
		"ok": bool(result.get("applied", false)),
		"reason": String(result.get("reason", "")),
		"life": float(_player.call("current_life")) if _player.has_method("current_life") else 0.0,
		"max_life": float(_player.call("max_life")) if _player.has_method("max_life") else 0.0,
		"combat_result": result.duplicate(true),
	}


func debug_kill_player() -> Dictionary:
	if _player == null or not _player.has_method("max_life"):
		return _debug_result(false, "player_unavailable")
	return debug_damage_player(float(_player.call("max_life")) * 10.0)


func debug_kill_enemies() -> Dictionary:
	var killed: int = 0
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if not _is_active_world_entity(enemy):
			continue
		var result: Dictionary = Combat.apply_damage(enemy, _damage_info(999999.0, enemy))
		if bool(result.get("applied", false)):
			killed += 1
	return {
		"ok": true,
		"count": killed,
	}


func debug_clear_enemies() -> Dictionary:
	var cleared: int = 0
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if not _is_active_world_entity(enemy):
			continue
		if PoolManager.release(enemy):
			cleared += 1
	for wave_key: String in _spawn_states.keys():
		if String(wave_key).begins_with("debug_"):
			var state: Dictionary = _spawn_states[wave_key]
			state["alive"] = 0
			_spawn_states[wave_key] = state
	return {
		"ok": true,
		"count": cleared,
	}


func debug_module_world_enabled() -> bool:
	return _module_world_enabled


func debug_module_world_state() -> Dictionary:
	return _module_world_snapshot()


func debug_module_world_tick() -> Dictionary:
	if _module_world_manager == null or _player == null:
		return {}
	return _module_world_manager.call("tick", _player.global_position) as Dictionary


func debug_set_player_position(world_position: Vector2) -> void:
	if _player != null and is_instance_valid(_player):
		_player.global_position = world_position


func debug_cast_primary_skill() -> Dictionary:
	if _skill_system == null or not _skill_system.has_method("cast_primary_skill"):
		return _debug_result(false, "skill_system_unavailable")
	return _skill_system.call("cast_primary_skill") as Dictionary


func debug_test_arena_spawn_at(
	enemy_id: String,
	target_kind: String,
	spawn_position: Vector2,
	stationary_max_hp: float
) -> Dictionary:
	if not _is_debug_test_arena():
		return _debug_result(false, "not_debug_test_arena")
	if not _enemy_rows.has(enemy_id):
		return _debug_result(false, "unknown_enemy")
	if not target_kind in [
		DEBUG_TEST_ARENA_AI,
		DEBUG_TEST_ARENA_STATIONARY,
	]:
		return _debug_result(false, "unknown_target_kind")
	var enemy_data: Dictionary = (
		_enemy_rows[enemy_id] as Dictionary
	).duplicate(true)
	var pool_id: String = String(enemy_data.get("pool_id", ""))
	var raw_node: Node = PoolManager.acquire(pool_id)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return _debug_result(false, "pool_unavailable")
	var enemy: Node2D = raw_node as Node2D
	enemy.global_position = spawn_position
	_reparent_to_active_world(enemy)
	enemy.set_meta("wave_key", "debug_test_arena_%s" % target_kind)
	if enemy.has_meta("module_slot"):
		enemy.remove_meta("module_slot")
	enemy.call("configure", enemy_data, _player, null)
	enemy.set_meta("debug_test_arena_kind", target_kind)
	if (
		target_kind == DEBUG_TEST_ARENA_STATIONARY
		and enemy.has_method("debug_configure_training_target")
	):
		enemy.call(
			"debug_configure_training_target",
			stationary_max_hp,
			spawn_position
		)
	_apply_enemy_movement_bounds(enemy)
	_connect_enemy_defeated(
		enemy,
		"debug_test_arena_%s" % target_kind
	)
	return {
		"ok": true,
		"reason": "",
		"enemy": enemy,
	}


func debug_test_arena_clear_targets(
	target_kind: String = ""
) -> Dictionary:
	if not _is_debug_test_arena():
		return _debug_result(false, "not_debug_test_arena")
	var cleared: int = 0
	for child: Node in _active_world.get_children():
		if not child.has_meta("debug_test_arena_kind"):
			continue
		if (
			not target_kind.is_empty()
			and String(child.get_meta("debug_test_arena_kind"))
			!= target_kind
		):
			continue
		if _vfx_host != null:
			_vfx_host.cancel_owner(child)
		if PoolManager.release(child):
			cleared += 1
	return {
		"ok": true,
		"count": cleared,
	}


func debug_test_arena_kill_ai() -> Dictionary:
	if not _is_debug_test_arena():
		return _debug_result(false, "not_debug_test_arena")
	var killed: int = 0
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			not _is_active_world_entity(enemy)
			or not enemy.has_meta("debug_test_arena_kind")
			or String(enemy.get_meta("debug_test_arena_kind"))
			!= DEBUG_TEST_ARENA_AI
		):
			continue
		var result: Dictionary = Combat.apply_damage(
			enemy,
			_debug_test_arena_damage_info(9999999.0, enemy)
		)
		if bool(result.get("applied", false)):
			killed += 1
	return {
		"ok": true,
		"count": killed,
	}


func debug_test_arena_reset_stationary_targets() -> Dictionary:
	if not _is_debug_test_arena():
		return _debug_result(false, "not_debug_test_arena")
	var reset_count: int = 0
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			not _is_active_world_entity(enemy)
			or not enemy.has_meta("debug_test_arena_kind")
			or String(enemy.get_meta("debug_test_arena_kind"))
			!= DEBUG_TEST_ARENA_STATIONARY
		):
			continue
		if enemy.has_method("debug_reset_training_target"):
			enemy.call("debug_reset_training_target")
			reset_count += 1
	return {
		"ok": true,
		"count": reset_count,
	}


func debug_test_arena_damage_first_target(
	target_kind: String,
	amount: float
) -> Dictionary:
	if not _is_debug_test_arena():
		return _debug_result(false, "not_debug_test_arena")
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			not _is_active_world_entity(enemy)
			or not enemy.has_meta("debug_test_arena_kind")
			or String(enemy.get_meta("debug_test_arena_kind"))
			!= target_kind
		):
			continue
		var result: Dictionary = Combat.apply_damage(
			enemy,
			_debug_test_arena_damage_info(
				maxf(amount, 0.0),
				enemy
			)
		)
		var response: Dictionary = result.duplicate(true)
		response["ok"] = bool(result.get("applied", false))
		response["target"] = enemy
		return response
	return _debug_result(false, "target_unavailable")


func debug_test_arena_clear_projectiles() -> Dictionary:
	if not _is_debug_test_arena():
		return _debug_result(false, "not_debug_test_arena")
	var cleared: int = 0
	for bullet: Node in get_tree().get_nodes_in_group("active_bullets"):
		if _is_active_world_entity(bullet) and PoolManager.release(bullet):
			cleared += 1
	return {
		"ok": true,
		"count": cleared,
	}


func debug_test_arena_reset_player() -> Dictionary:
	if not _is_debug_test_arena() or _player == null:
		return _debug_result(false, "player_unavailable")
	if _player.has_method("debug_reset_transient_state"):
		_player.call("debug_reset_transient_state", Vector2.ZERO)
	if _skill_system != null and _skill_system.has_method("debug_refresh"):
		_skill_system.call("debug_refresh")
	if _weapon_system != null and _weapon_system.has_method("debug_refresh"):
		_weapon_system.call("debug_refresh")
	var died_callback: Callable = Callable(self, "_on_player_died")
	if not _player.is_connected("died", died_callback):
		_player.connect(
			"died",
			died_callback,
			CONNECT_ONE_SHOT
		)
	return {
		"ok": true,
		"life": float(_player.call("current_life")),
		"max_life": float(_player.call("max_life")),
	}


func debug_test_arena_request_setup() -> void:
	if _is_debug_test_arena():
		debug_test_arena_setup_requested.emit()


func debug_test_arena_request_title() -> void:
	if _is_debug_test_arena():
		quit_to_title_requested.emit()


func debug_test_arena_open_panel() -> void:
	if (
		_is_debug_test_arena()
		and _debug_test_arena_controller != null
	):
		_debug_test_arena_controller.call("open_panel")


func debug_test_arena_close_panel() -> void:
	if (
		_is_debug_test_arena()
		and _debug_test_arena_controller != null
	):
		_debug_test_arena_controller.call("close_panel")


func debug_test_arena_set_god_mode(enabled: bool) -> void:
	if _debug_test_arena_controller != null:
		_debug_test_arena_controller.call("set_god_mode", enabled)


func debug_test_arena_set_free_skills(enabled: bool) -> void:
	if _debug_test_arena_controller != null:
		_debug_test_arena_controller.call("set_free_skills", enabled)


func debug_test_arena_refresh_skills() -> void:
	if _debug_test_arena_controller != null:
		_debug_test_arena_controller.call("refresh_skills")


func debug_test_arena_teleport_to_spawn() -> void:
	if _debug_test_arena_controller != null:
		_debug_test_arena_controller.call("teleport_to_spawn")


func debug_test_arena_reset_damage_stats() -> void:
	if _debug_test_arena_controller != null:
		_debug_test_arena_controller.call("reset_damage_stats")


func debug_test_arena_summary() -> Dictionary:
	return {
		"active": _is_debug_test_arena(),
		"config": _debug_test_arena_config.duplicate(true),
		"player_position": (
			_vector_to_dict(_player.global_position)
			if _player != null
			else {}
		),
		"player_life": (
			float(_player.call("current_life"))
			if _player != null
			else 0.0
		),
		"player_max_life": (
			float(_player.call("max_life"))
			if _player != null
			else 0.0
		),
		"weapon_damage": (
			float(_weapon_system.call("stat_value", STATS.DAMAGE))
			if _weapon_system != null
			else 0.0
		),
		"skills": (
			_skill_system.call("debug_summary")
			if _skill_system != null
			else {}
		),
		"controller": (
			_debug_test_arena_controller.call("debug_summary")
			if _debug_test_arena_controller != null
			else {}
		),
	}


func debug_claim_interest_point(point_id: String) -> Dictionary:
	return _claim_interest_point(point_id, true)


func debug_damage_interest_point_target(point_id: String, amount: float) -> Dictionary:
	var target: Node = _interest_point_targets.get(point_id, null) as Node
	if target == null or not is_instance_valid(target):
		return _debug_result(false, "missing_interest_point_target")
	if target.has_method("debug_force_vulnerable"):
		target.call("debug_force_vulnerable")
	var result: Dictionary = Combat.apply_damage(target, _damage_info(amount, target))
	if not bool(result.get("applied", false)):
		return _debug_result(false, String(result.get("reason", "damage_failed")))
	var debug_result: Dictionary = result.duplicate(true)
	debug_result["ok"] = true
	return debug_result


func _update_extraction(delta: float) -> void:
	if not _extraction_active or _player == null or _run_completed:
		return
	if not _is_position_in_extraction_zone(_player.global_position):
		if _extraction_progress > 0.0:
			_extraction_progress = 0.0
			queue_redraw()
		return
	_extraction_progress += GameClock.delta_scaled(delta)
	queue_redraw()
	if _extraction_progress >= _extraction_hold_time:
		_complete_run(_extraction_source_point_id)


func _activate_extraction(point_id: String, state: Dictionary) -> void:
	_extraction_active = true
	_extraction_source_point_id = point_id
	_extraction_position = _dict_to_vector(state.get("position", {}), Vector2.ZERO)
	_extraction_radius = maxf(float(state.get("extraction_radius", 0.0)), float(state.get("claim_radius", 0.0)))
	_extraction_hold_time = maxf(float(state.get("extraction_hold_time", 0.0)), 0.0)
	_extraction_progress = 0.0
	if _hud != null and _hud.has_method("show_extraction_feedback"):
		_hud.call("show_extraction_feedback")
	queue_redraw()
	if _extraction_hold_time <= 0.0:
		_complete_run(point_id)


func _reset_extraction() -> void:
	_extraction_active = false
	_extraction_source_point_id = ""
	_extraction_position = Vector2.ZERO
	_extraction_radius = 0.0
	_extraction_hold_time = 0.0
	_extraction_progress = 0.0
	queue_redraw()


func _update_spawner() -> void:
	var elapsed: float = GameClock.now()
	for wave: Dictionary in _waves:
		var wave_key: String = String(wave.get("id", ""))
		if _warzone_director != null and not _warzone_director.is_wave_enabled(wave_key, elapsed):
			continue
		if elapsed < float(wave.get("start_time", 0.0)) or elapsed > float(wave.get("end_time", 0.0)):
			continue
		var state: Dictionary = _spawn_states.get(wave_key, {
			"next_time": float(wave.get("start_time", 0.0)),
			"spawned": 0,
			"alive": 0,
		})
		if elapsed < float(state.get("next_time", 0.0)):
			_spawn_states[wave_key] = state
			continue
		if int(state.get("spawned", 0)) >= int(wave.get("spawn_budget", 0)):
			_spawn_states[wave_key] = state
			continue
		if int(state.get("alive", 0)) >= int(wave.get("max_alive", 0)):
			_spawn_states[wave_key] = state
			continue

		if _spawn_enemy(wave, wave_key):
			state["spawned"] = int(state.get("spawned", 0)) + 1
			state["alive"] = int(state.get("alive", 0)) + 1
			state["next_time"] = elapsed + float(wave.get("spawn_interval", 1.0))
		_spawn_states[wave_key] = state


func _spawn_enemy(wave: Dictionary, wave_key: String) -> bool:
	var requested_id: String = String(wave.get("enemy_id", ""))
	if not _enemy_rows.has(requested_id):
		return false
	var enemy_data: Dictionary = _enemy_rows[requested_id]
	var pool_id: String = String(enemy_data.get("pool_id", ""))
	var raw_node: Node = PoolManager.acquire(pool_id)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return false

	var enemy: Node2D = raw_node as Node2D
	enemy.global_position = _spawn_position()
	_reparent_to_active_world(enemy)
	enemy.set_meta("wave_key", wave_key)
	if enemy.has_meta("module_slot"):
		enemy.remove_meta("module_slot")
	enemy.call("configure", enemy_data, _player, _enemy_navigation_provider())
	_apply_enemy_movement_bounds(enemy)
	_connect_enemy_defeated(enemy, wave_key)
	return true


func _spawn_map_hazards(placements: Array[Dictionary]) -> void:
	for placement: Dictionary in placements:
		_spawn_hazard(placement)


func _configure_module_world(
	restore_snapshot: Dictionary,
	threaded_loading: bool = false
) -> bool:
	_ensure_module_world_manager()
	if _module_world_manager == null:
		return false
	var worlds_payload: Dictionary = _dictionary_or_empty(DataLoader.load_json(DataLoader.MODULE_WORLDS_PATH))
	var worlds: Array[Dictionary] = _typed_dictionary_array(worlds_payload.get("worlds", []))
	if worlds.is_empty():
		return false
	_module_world_definition = worlds[0].duplicate(true)
	var registry_payload: Dictionary = _dictionary_or_empty(DataLoader.load_json(DataLoader.MODULE_TEMPLATES_PATH))
	var registry_by_id: Dictionary = {}
	var templates_by_id: Dictionary = {}
	var generated_scene_paths_by_id: Dictionary = {}
	for entry: Dictionary in _typed_dictionary_array(registry_payload.get("templates", [])):
		var template_id: String = String(entry.get("id", ""))
		var template_path: String = String(entry.get("path", ""))
		if template_id.is_empty() or template_path.is_empty():
			continue
		registry_by_id[template_id] = entry.duplicate(true)
		var template_data: Dictionary = _dictionary_or_empty(DataLoader.load_json(template_path))
		if not template_data.is_empty():
			templates_by_id[template_id] = _module_gameplay_projection(
				template_data
			)
		generated_scene_paths_by_id[template_id] = (
			"res://scenes/generated/modules/%s/rotation_0.tscn"
			% template_id
		)
	if threaded_loading:
		var generated_scene_paths: Array[String] = []
		for raw_scene_path: Variant in generated_scene_paths_by_id.values():
			generated_scene_paths.append(String(raw_scene_path))
		var load_result: Dictionary = await _load_packed_scenes_threaded(
			generated_scene_paths
		)
		if not bool(load_result.get("ok", false)):
			return false
		var loaded_scenes: Dictionary = _dictionary_or_empty(
			load_result.get("resources", {})
		)
		for template_id: String in generated_scene_paths_by_id.keys():
			var generated_scene_path: String = String(
				generated_scene_paths_by_id[template_id]
			)
			generated_scene_paths_by_id[template_id] = loaded_scenes.get(
				generated_scene_path
			)
	var module_snapshot: Dictionary = _dictionary_or_empty(restore_snapshot.get("module_world", {}))
	var world_seed: int = int(module_snapshot.get("run_seed", RNG.run_seed()))
	var navigation_flow_radius_cells: int = _navigation_flow_radius_cells(_module_world_definition)
	var configured: bool = bool(_module_world_manager.call(
		"configure",
		_module_world_definition,
		registry_by_id,
		templates_by_id,
		generated_scene_paths_by_id,
		world_seed,
		navigation_flow_radius_cells
	))
	if not configured:
		return false
	if _module_world_technical_slice and module_snapshot.is_empty():
		return bool(_module_world_manager.call("build_technical_slice_assignment"))
	return true


func _module_gameplay_projection(module_data: Dictionary) -> Dictionary:
	var terrain_rows: Array = _array_or_empty(
		module_data.get("terrain_rows", [])
	)
	return {
		# Godot's JSON parser represented the schema-v1 numeric fields as floats.
		# Preserve those exact Variant types because the legacy map hash serializes
		# content types as well as values.
		"schema_version": 1.0,
		"id": String(module_data.get("id", "")),
		"columns": 11.0,
		"rows": 11.0,
		"terrain_rows": terrain_rows.duplicate(true),
		"edge_sockets": _derive_module_edge_sockets(terrain_rows),
		"placements": _array_or_empty(
			module_data.get("placements", [])
		).duplicate(true),
	}


func _derive_module_edge_sockets(terrain_rows: Array) -> Dictionary:
	var result: Dictionary = {
		"edge_north": [],
		"edge_south": [],
		"edge_east": [],
		"edge_west": [],
	}
	if terrain_rows.size() != 11:
		return result
	for row_value: Variant in terrain_rows:
		if not row_value is Array or (row_value as Array).size() != 11:
			return result
	for index: int in range(11):
		if String((terrain_rows[0] as Array)[index]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result["edge_north"] as Array).append(float(index))
		if String((terrain_rows[10] as Array)[index]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result["edge_south"] as Array).append(float(index))
		if String((terrain_rows[index] as Array)[10]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result["edge_east"] as Array).append(float(index))
		if String((terrain_rows[index] as Array)[0]) == MODULE_CELL_TOKENS.MODULE_CELL_FLOOR:
			(result["edge_west"] as Array).append(float(index))
	return result


func _navigation_flow_radius_cells(world_definition: Dictionary) -> int:
	var cell_size: float = maxf(float(world_definition.get("cell_size", 160.0)), 1.0)
	var maximum_sight_radius: float = 0.0
	for raw_enemy_data: Variant in _enemy_rows.values():
		if not raw_enemy_data is Dictionary:
			continue
		var enemy_data: Dictionary = raw_enemy_data as Dictionary
		var ai_profile: Dictionary = _dictionary_or_empty(enemy_data.get("ai_profile", {}))
		var perception: Dictionary = _dictionary_or_empty(ai_profile.get("perception", {}))
		maximum_sight_radius = maxf(maximum_sight_radius, float(perception.get("sight_radius", 0.0)))
	return maxi(ceili(maximum_sight_radius / cell_size) + NAVIGATION_FLOW_OBSTACLE_BUFFER_CELLS, 1)


func _ensure_module_world_manager() -> void:
	if _module_world_manager != null and is_instance_valid(_module_world_manager):
		return
	_module_world_manager = _active_world.get_node_or_null("ModuleWorldManager") as Node2D if _active_world != null else null
	if _module_world_manager == null:
		push_error("[GameplayRunLoop] missing scene-authored ModuleWorldManager")


func _module_world_map_layout() -> Dictionary:
	var cell_size: float = maxf(float(_module_world_definition.get("cell_size", 160.0)), 1.0)
	var start_position: Vector2 = Vector2.ZERO
	var start_slot: Vector2i = _dict_to_vector2i(_module_world_definition.get("start_slot", {}))
	for placement: Dictionary in _module_world_manager.call("placements_at", start_slot):
		if String(placement.get("type", "")) == MODULE_PLACEMENT_TYPES.MODULE_PLACE_PLAYER_START:
			start_position = _dict_to_vector(placement.get("world_position", {}), Vector2.ZERO)
			break
	return {
		"id": String(_module_world_definition.get("id", "module_world_9x9")),
		"mode_id": GAME_MODES.MODE_STANDARD_SURVIVAL,
		"bounds": {"width": 99.0 * cell_size, "height": 99.0 * cell_size},
		"grid": {"cell_width": cell_size, "cell_height": cell_size},
		"player_start": _vector_to_dict(start_position),
		"safe_radius": cell_size * 2.0,
		"enemy_spawn_margin": cell_size,
		"pcg": {"hazards": []},
		"manual_hazards": [],
	}


func _start_module_world_fresh() -> void:
	if _module_world_manager == null or _player == null:
		return
	_register_all_module_interest_points()
	var stream_change: Dictionary = _module_world_manager.call("tick", _player.global_position)
	_handle_module_stream_change(stream_change)
	_refresh_module_world_hud()


func _start_module_world_fresh_staged() -> bool:
	if _module_world_manager == null or _player == null:
		return false
	_register_all_module_interest_points()
	var stream_change: Dictionary = _module_world_manager.call(
		"tick",
		_player.global_position
	)
	if not await _handle_module_stream_change_staged(stream_change):
		return false
	_refresh_module_world_hud()
	return true


func _update_module_world() -> void:
	if _module_world_manager == null or _player == null:
		return
	var stream_change: Dictionary = _module_world_manager.call("tick", _player.global_position)
	_handle_module_stream_change(stream_change)
	_refresh_module_world_hud()


func _handle_module_stream_change(stream_change: Dictionary) -> void:
	for raw_coord: Variant in _array_or_empty(stream_change.get("deactivated", [])):
		_deactivate_module_slot(_dict_to_vector2i(raw_coord))
	for raw_coord: Variant in _array_or_empty(stream_change.get("activated", [])):
		_activate_module_slot(_dict_to_vector2i(raw_coord), true)


func _handle_module_stream_change_staged(stream_change: Dictionary) -> bool:
	for raw_coord: Variant in _array_or_empty(stream_change.get("deactivated", [])):
		_deactivate_module_slot(_dict_to_vector2i(raw_coord))
	for raw_coord: Variant in _array_or_empty(stream_change.get("activated", [])):
		_activate_module_slot(_dict_to_vector2i(raw_coord), true)
		if not await _yield_loading_frame():
			return false
	return true


func _activate_module_slot(module_coord: Vector2i, restore_stored_entities: bool) -> void:
	var slot_key: String = _module_slot_key(module_coord)
	var state: Dictionary = _module_world_manager.call("slot_state", module_coord)
	var placements: Array[Dictionary] = _module_world_manager.call("placements_at", module_coord)
	for placement: Dictionary in placements:
		_register_module_interest_point(module_coord, placement)
	if bool(state.get("initialized", false)):
		if restore_stored_entities:
			_restore_hazard_snapshots(_array_or_empty(state.get("hazard_snapshots", [])))
			_restore_enemy_snapshots(_array_or_empty(state.get("enemy_snapshots", [])))
			_restore_bullet_snapshots(_array_or_empty(state.get("bullet_snapshots", [])))
			_restore_pickup_snapshots(_array_or_empty(state.get("pickup_snapshots", [])))
			state["hazard_snapshots"] = []
			state["enemy_snapshots"] = []
			state["bullet_snapshots"] = []
			state["pickup_snapshots"] = []
	else:
		_spawn_module_placements(module_coord, placements)
		state["initialized"] = true
	state["slot_key"] = slot_key
	_module_world_manager.call("set_slot_state", module_coord, state)
	# During full run restore, interest-point state is applied after active slots are rebuilt.
	# Delay their visuals until then so a claimed/destroyed target cannot briefly reappear
	# with default HP and survive the second spawn pass as an already-existing node.
	if restore_stored_entities:
		_spawn_module_interest_visuals(slot_key)


func _deactivate_module_slot(module_coord: Vector2i) -> void:
	var slot_key: String = _module_slot_key(module_coord)
	var state: Dictionary = _module_world_manager.call("slot_state", module_coord)
	state["enemy_snapshots"] = _capture_and_release_module_group("active_enemies", slot_key)
	state["hazard_snapshots"] = _capture_and_release_module_group("active_hazards", slot_key)
	state["bullet_snapshots"] = _capture_and_release_module_group("active_bullets", slot_key)
	state["pickup_snapshots"] = _capture_and_release_module_group("active_pickups", slot_key)
	_module_world_manager.call("set_slot_state", module_coord, state)
	_deactivate_module_interest_visuals(slot_key)


func _capture_and_release_module_group(group_name: String, slot_key: String) -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if not _is_active_world_entity(node) or not _entity_belongs_to_module_slot(node, group_name, slot_key):
			continue
		if node.has_method("snapshot"):
			var snapshot_data: Dictionary = node.call("snapshot")
			snapshot_data["module_slot"] = slot_key
			if group_name == "active_enemies":
				snapshot_data["wave_key"] = String(node.get_meta("wave_key", ""))
			snapshots.append(snapshot_data)
		PoolManager.release(node)
	return snapshots


func _entity_belongs_to_module_slot(node: Node, group_name: String, slot_key: String) -> bool:
	if group_name == "active_enemies" or group_name == "active_hazards":
		return String(node.get_meta("module_slot", "")) == slot_key
	if not node is Node2D or _module_world_manager == null:
		return false
	# Projectiles and pickups can cross a seam after spawning, so their current
	# world position—not their origin template—owns the transient slot snapshot.
	var global_cell: Vector2i = _module_world_manager.call("world_to_global_cell", (node as Node2D).global_position)
	var module_and_local: Dictionary = _module_world_manager.call("global_cell_to_module_and_local", global_cell)
	var module_coord: Vector2i = module_and_local.get("module_coord", Vector2i(-1, -1)) as Vector2i
	return _module_slot_key(module_coord) == slot_key


func _spawn_module_placements(module_coord: Vector2i, placements: Array[Dictionary]) -> void:
	var slot_key: String = _module_slot_key(module_coord)
	var wave_key: String = "module_%s" % slot_key.replace(",", "_")
	for placement: Dictionary in placements:
		var placement_type: String = String(placement.get("type", ""))
		var world_position: Vector2 = _dict_to_vector(placement.get("world_position", {}), Vector2.ZERO)
		if placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_ENEMY_SPAWN:
			for _index: int in range(maxi(int(placement.get("count", 1)), 1)):
				_spawn_enemy_at(String(placement.get("enemy_id", "")), world_position, wave_key, slot_key)
		elif placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_HAZARD:
			_spawn_hazard({
				"hazard_id": String(placement.get("hazard_id", "")),
				"position": _vector_to_dict(world_position),
				"module_slot": slot_key,
			})


func _spawn_enemy_at(enemy_id: String, spawn_position: Vector2, spawn_key: String, module_slot: String = "") -> bool:
	if not _enemy_rows.has(enemy_id):
		return false
	if not module_slot.is_empty() and not _is_module_world_position_walkable(spawn_position):
		return false
	var enemy_data: Dictionary = _enemy_rows[enemy_id]
	var pool_id: String = String(enemy_data.get("pool_id", ""))
	var raw_node: Node = PoolManager.acquire(pool_id)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return false
	var enemy: Node2D = raw_node as Node2D
	enemy.global_position = spawn_position
	_reparent_to_active_world(enemy)
	enemy.set_meta("wave_key", spawn_key)
	if module_slot.is_empty():
		if enemy.has_meta("module_slot"):
			enemy.remove_meta("module_slot")
	else:
		enemy.set_meta("module_slot", module_slot)
	enemy.call("configure", enemy_data, _player, _enemy_navigation_provider())
	_apply_enemy_movement_bounds(enemy)
	_connect_enemy_defeated(enemy, spawn_key)
	return true


func _register_all_module_interest_points() -> void:
	if _module_world_manager == null:
		return
	for row_index: int in range(9):
		for column_index: int in range(9):
			var module_coord := Vector2i(column_index, row_index)
			var placements: Array[Dictionary] = _module_world_manager.call("placements_at", module_coord)
			for placement: Dictionary in placements:
				_register_module_interest_point(module_coord, placement)


func _register_module_interest_point(module_coord: Vector2i, placement: Dictionary) -> void:
	var placement_type: String = String(placement.get("type", ""))
	if not placement_type in [
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE,
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_OBJECTIVE,
		MODULE_PLACEMENT_TYPES.MODULE_PLACE_EXTRACTION,
	]:
		return
	var local_cell: Vector2i = _dict_to_vector2i(placement.get("cell", {}))
	var point_id: String = "module_%d_%d_%s_%d_%d" % [
		module_coord.x,
		module_coord.y,
		placement_type.trim_prefix("module_place_"),
		local_cell.x,
		local_cell.y,
	]
	if _interest_points.has(point_id):
		if placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_EXTRACTION:
			_module_extraction_point_id = point_id
		return
	var generic_placement: Dictionary = {
		"interest_point_id": point_id,
		"interest_point_kind": placement_type,
		"position": placement.get("world_position", {}),
		"interest_point_claim_radius": 0.0,
		"interest_point_claim_start_time": 0.0,
		"interest_point_requires_interaction": false,
		"interest_point_resource_rewards": [],
		"interest_point_gear_mod_rewards": [],
		"interest_point_completes_run": false,
		"interest_point_extraction_radius": 0.0,
		"interest_point_extraction_hold_time": 0.0,
		"interest_point_target_hp": 0.0,
		"interest_point_target_hit_radius": 24.0,
	}
	if placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE:
		generic_placement["interest_point_claim_radius"] = maxf(float(placement.get("claim_radius", 180.0)), 1.0)
		generic_placement["interest_point_requires_interaction"] = true
		var rewards: Array[Dictionary] = []
		for reward: Dictionary in _typed_dictionary_array(placement.get("resource_rewards", [])):
			rewards.append({
				"resource_id": String(reward.get("id", "")),
				"amount": int(reward.get("amount", 0)),
			})
		generic_placement["interest_point_resource_rewards"] = rewards
	elif placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_OBJECTIVE:
		generic_placement["interest_point_completes_run"] = true
		generic_placement["interest_point_target_hp"] = maxf(float(placement.get("target_hp", 1.0)), 1.0)
		generic_placement["interest_point_target_hit_radius"] = maxf(float(placement.get("target_hit_radius", 24.0)), 1.0)
	elif placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_EXTRACTION:
		generic_placement["interest_point_extraction_radius"] = maxf(float(placement.get("radius", 160.0)), 1.0)
		generic_placement["interest_point_extraction_hold_time"] = maxf(float(placement.get("hold_time", 1.0)), 0.0)
		_module_extraction_point_id = point_id
	var state: Dictionary = _new_interest_point_state(point_id, generic_placement)
	state["module_slot"] = _module_slot_key(module_coord)
	_interest_points[point_id] = state


func _spawn_module_interest_visuals(slot_key: String) -> void:
	for point_key: Variant in _interest_points.keys():
		var point_id: String = String(point_key)
		var state: Dictionary = _interest_points[point_key] as Dictionary
		if String(state.get("module_slot", "")) != slot_key:
			continue
		if bool(state.get("requires_interaction", false)):
			_spawn_module_interest_cache(point_id, state)
		elif _interest_point_has_target(state):
			_spawn_module_interest_target(point_id, state)


func _spawn_module_interest_cache(point_id: String, state: Dictionary) -> void:
	var existing: Node = _interest_point_caches.get(point_id, null) as Node
	if existing != null and is_instance_valid(existing):
		return
	var cache: Node2D = INTEREST_POINT_CACHE_SCENE.instantiate() as Node2D
	if cache == null or not cache.has_method("configure"):
		return
	cache.name = "InterestPointCache_%s" % point_id
	cache.global_position = _dict_to_vector(state.get("position", {}), Vector2.ZERO)
	cache.call("configure", point_id, String(state.get("kind", "")), _map_grid_cell_size(), bool(state.get("claimed", false)))
	_active_world.add_child(cache)
	_interest_point_caches[point_id] = cache


func _spawn_module_interest_target(point_id: String, state: Dictionary) -> void:
	if bool(state.get("claimed", false)) or bool(state.get("target_destroyed", false)):
		return
	var existing: Node = _interest_point_targets.get(point_id, null) as Node
	if existing != null and is_instance_valid(existing):
		return
	var target: Node2D = INTEREST_POINT_TARGET_SCENE.instantiate() as Node2D
	if target == null or not target.has_method("configure"):
		return
	target.global_position = _dict_to_vector(state.get("position", {}), Vector2.ZERO)
	target.call(
		"configure",
		point_id,
		String(state.get("kind", "")),
		float(state.get("target_hp", 0.0)),
		float(state.get("target_hit_radius", 24.0)),
		_map_grid_cell_size()
	)
	var target_snapshot: Dictionary = _dictionary_or_empty(state.get("target_snapshot", {}))
	if not target_snapshot.is_empty() and target.has_method("restore_snapshot"):
		target.call("restore_snapshot", target_snapshot)
	target.connect("destroyed", Callable(self, "_on_interest_point_target_destroyed"))
	_active_world.add_child(target)
	_interest_point_targets[point_id] = target


func _deactivate_module_interest_visuals(slot_key: String) -> void:
	for point_key: Variant in _interest_points.keys():
		var point_id: String = String(point_key)
		var state: Dictionary = _interest_points[point_key] as Dictionary
		if String(state.get("module_slot", "")) != slot_key:
			continue
		var cache: Node = _interest_point_caches.get(point_id, null) as Node
		if cache != null and is_instance_valid(cache):
			cache.queue_free()
		_interest_point_caches.erase(point_id)
		var target: Node = _interest_point_targets.get(point_id, null) as Node
		if target != null and is_instance_valid(target):
			if target.has_method("snapshot"):
				state["target_snapshot"] = target.call("snapshot")
			target.queue_free()
		_interest_point_targets.erase(point_id)
		_interest_points[point_id] = state


func _module_world_snapshot() -> Dictionary:
	if not _module_world_enabled or _module_world_manager == null:
		return {}
	return _module_world_manager.call("snapshot") as Dictionary


func _refresh_module_world_hud() -> void:
	if _hud == null or _module_world_manager == null or not _hud.has_method("set_module_world_state"):
		return
	var state: Dictionary = {
		"visited_slots": _module_world_manager.call("visited_module_coords"),
		"current_slot": _coord_to_dict(_module_world_manager.call("current_module_coord") as Vector2i),
		"objective_slot": _coord_to_dict(_module_world_manager.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_OBJECTIVE) as Vector2i),
		"extraction_slot": _coord_to_dict(_module_world_manager.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_EXTRACTION) as Vector2i),
		"extraction_active": _extraction_active,
	}
	_hud.call("set_module_world_state", state)


func _module_slot_key(module_coord: Vector2i) -> String:
	return "%d,%d" % [module_coord.x, module_coord.y]


func _configure_interest_points(placements: Array[Dictionary]) -> void:
	_interest_points.clear()
	for placement: Dictionary in placements:
		var point_id: String = String(placement.get("interest_point_id", ""))
		if point_id.is_empty():
			continue
		var state: Dictionary = _interest_points.get(point_id, _new_interest_point_state(point_id, placement))
		if placement.has("interest_point_target_position"):
			state["position"] = _dictionary_or_empty(placement.get("interest_point_target_position", {}))
			state["_placement_count"] = 1
		elif placement.has("interest_point_cache_position"):
			state["position"] = _dictionary_or_empty(placement.get("interest_point_cache_position", {}))
			state["_placement_count"] = 1
		else:
			var position: Vector2 = _dict_to_vector(placement.get("position", {}), Vector2.ZERO)
			var placement_count: int = int(state.get("_placement_count", 0))
			var previous_position: Vector2 = _dict_to_vector(state.get("position", {}), position)
			var averaged_position: Vector2 = ((previous_position * float(placement_count)) + position) / float(placement_count + 1)
			state["position"] = _vector_to_dict(averaged_position)
			state["_placement_count"] = placement_count + 1
		_interest_points[point_id] = state


func _new_interest_point_state(point_id: String, placement: Dictionary) -> Dictionary:
	return {
		"id": point_id,
		"kind": String(placement.get("interest_point_kind", "")),
		"position": placement.get("position", {}),
		"claim_radius": maxf(float(placement.get("interest_point_claim_radius", 0.0)), 0.0),
		"claim_start_time": maxf(float(placement.get("interest_point_claim_start_time", 0.0)), 0.0),
		"requires_interaction": bool(placement.get("interest_point_requires_interaction", false)),
		"resource_rewards": _typed_dictionary_array(placement.get("interest_point_resource_rewards", [])),
		"gear_mod_rewards": _typed_dictionary_array(placement.get("interest_point_gear_mod_rewards", [])),
		"completes_run": bool(placement.get("interest_point_completes_run", false)),
		"extraction_radius": maxf(float(placement.get("interest_point_extraction_radius", 0.0)), 0.0),
		"extraction_hold_time": maxf(float(placement.get("interest_point_extraction_hold_time", 0.0)), 0.0),
		"target_hp": maxf(float(placement.get("interest_point_target_hp", 0.0)), 0.0),
		"target_hit_radius": maxf(float(placement.get("interest_point_target_hit_radius", 24.0)), 1.0),
		"target_destroyed": false,
		"claimed": false,
		"claimed_time": 0.0,
		"_placement_count": 0,
	}


func _update_interest_points() -> void:
	if _player == null or _run_completed:
		return
	for point_key: Variant in _interest_points.keys():
		var point_id: String = String(point_key)
		var state: Dictionary = _interest_points[point_key] as Dictionary
		if bool(state.get("claimed", false)):
			continue
		if _interest_point_has_target(state) and not bool(state.get("target_destroyed", false)):
			continue
		if GameClock.now() < float(state.get("claim_start_time", 0.0)):
			continue
		var claim_radius: float = float(state.get("claim_radius", 0.0))
		if claim_radius <= 0.0:
			continue
		var position: Vector2 = _dict_to_vector(state.get("position", {}), Vector2.ZERO)
		if _player.global_position.distance_to(position) <= claim_radius:
			if bool(state.get("requires_interaction", false)):
				continue
			_claim_interest_point(point_id)
			if _run_completed:
				return
	_update_interaction_prompt(_nearest_interactable_interest_point())


func _claim_interest_point(point_id: String, force: bool = false) -> Dictionary:
	if not _interest_points.has(point_id):
		return _debug_result(false, "unknown_interest_point")
	var state: Dictionary = _interest_points[point_id] as Dictionary
	if bool(state.get("claimed", false)):
		return _debug_result(false, "already_claimed")
	if not force and GameClock.now() < float(state.get("claim_start_time", 0.0)):
		return _debug_result(false, "not_ready")

	var rewards: Dictionary = _grant_interest_point_rewards(state)
	state["claimed"] = true
	state["claimed_time"] = GameClock.now()
	state["reward_result"] = rewards
	state["target_destroyed"] = true
	_interest_points[point_id] = state
	_mark_interest_point_target_claimed(point_id)
	_mark_interest_point_cache_opened(point_id)
	if _hud != null and _hud.has_method("hide_interaction_prompt"):
		_hud.call("hide_interaction_prompt")
	if bool(state.get("completes_run", false)):
		if not _module_extraction_point_id.is_empty() and _interest_points.has(_module_extraction_point_id):
			_activate_extraction(
				_module_extraction_point_id,
				_interest_points[_module_extraction_point_id] as Dictionary
			)
		else:
			_activate_extraction(point_id, state)

	var result: Dictionary = rewards.duplicate(true)
	result["ok"] = true
	result["interest_point_id"] = point_id
	result["completed_run"] = false
	result["extraction_active"] = _extraction_active
	return result


func _try_interact_interest_point() -> bool:
	var point_id: String = _nearest_interactable_interest_point()
	if point_id.is_empty():
		return false
	var result: Dictionary = _claim_interest_point(point_id)
	return bool(result.get("ok", false))


func _update_interaction_prompt(point_id: String) -> void:
	if _hud == null:
		return
	if point_id.is_empty():
		if _hud.has_method("hide_interaction_prompt"):
			_hud.call("hide_interaction_prompt")
		return
	if _hud.has_method("show_interaction_prompt"):
		_hud.call("show_interaction_prompt", _interaction_binding_label())


func _nearest_interactable_interest_point() -> String:
	if _player == null:
		return ""
	var best_point_id: String = ""
	var best_distance: float = INF
	for point_key: Variant in _interest_points.keys():
		var point_id: String = String(point_key)
		var state: Dictionary = _interest_points[point_key] as Dictionary
		if not _is_interest_point_interactable(state):
			continue
		var position: Vector2 = _dict_to_vector(state.get("position", {}), Vector2.ZERO)
		var distance: float = _player.global_position.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best_point_id = point_id
	return best_point_id


func _is_interest_point_interactable(state: Dictionary) -> bool:
	if _player == null:
		return false
	if bool(state.get("claimed", false)):
		return false
	if not bool(state.get("requires_interaction", false)):
		return false
	if _interest_point_has_target(state) and not bool(state.get("target_destroyed", false)):
		return false
	if GameClock.now() < float(state.get("claim_start_time", 0.0)):
		return false
	var claim_radius: float = float(state.get("claim_radius", 0.0))
	if claim_radius <= 0.0:
		return false
	var position: Vector2 = _dict_to_vector(state.get("position", {}), Vector2.ZERO)
	return _player.global_position.distance_to(position) <= claim_radius


func _interaction_binding_label() -> String:
	return InputService.prompt_text(ACTIONS.INTERACT)


func _grant_interest_point_rewards(state: Dictionary) -> Dictionary:
	var granted_resources: Array[Dictionary] = []
	for reward: Dictionary in _typed_dictionary_array(state.get("resource_rewards", [])):
		var resource_id: String = String(reward.get("resource_id", ""))
		var amount: int = maxi(int(reward.get("amount", 0)), 0)
		if resource_id.is_empty() or amount <= 0:
			continue
		_add_pending_resource(resource_id, amount)
		granted_resources.append({
			"resource_id": resource_id,
			"amount": amount,
		})
		if _hud != null and _hud.has_method("show_gear_mod_resource_feedback"):
			_hud.call("show_gear_mod_resource_feedback", "%s_name" % resource_id, amount)

	var granted_mods: Array[Dictionary] = []
	for reward: Dictionary in _typed_dictionary_array(state.get("gear_mod_rewards", [])):
		var mod_id: String = String(reward.get("mod_id", ""))
		var count: int = maxi(int(reward.get("count", 1)), 1)
		if mod_id.is_empty():
			continue
		for _index: int in range(count):
			var name_key: String = _gear_mod_name_key(mod_id)
			_add_pending_mod(mod_id, name_key)
			granted_mods.append({
				"mod_id": mod_id,
				"name_key": name_key,
			})
			if not name_key.is_empty() and _hud != null and _hud.has_method("show_gear_mod_drop_feedback"):
				_hud.call("show_gear_mod_drop_feedback", name_key)

	return {
		"resources": granted_resources,
		"gear_mods": granted_mods,
	}


func _spawn_interest_point_caches() -> void:
	_clear_interest_point_caches()
	for point_key: Variant in _interest_points.keys():
		var point_id: String = String(point_key)
		var state: Dictionary = _interest_points[point_key] as Dictionary
		if not bool(state.get("requires_interaction", false)):
			continue
		var cache: Node2D = INTEREST_POINT_CACHE_SCENE.instantiate() as Node2D
		if cache == null or not cache.has_method("configure"):
			continue
		cache.name = "InterestPointCache_%s" % point_id
		cache.global_position = _dict_to_vector(state.get("position", {}), Vector2.ZERO)
		cache.call(
			"configure",
			point_id,
			String(state.get("kind", "")),
			_map_grid_cell_size(),
			bool(state.get("claimed", false))
		)
		_active_world.add_child(cache)
		_interest_point_caches[point_id] = cache


func _clear_interest_point_caches() -> void:
	for cache_key: Variant in _interest_point_caches.keys():
		var cache: Node = _interest_point_caches[cache_key] as Node
		if cache != null and is_instance_valid(cache):
			cache.queue_free()
	_interest_point_caches.clear()


func _mark_interest_point_cache_opened(point_id: String) -> void:
	var cache: Node = _interest_point_caches.get(point_id, null) as Node
	if cache == null or not is_instance_valid(cache):
		return
	if cache.has_method("mark_opened"):
		cache.call("mark_opened")


func _spawn_interest_point_targets() -> void:
	for point_key: Variant in _interest_points.keys():
		var point_id: String = String(point_key)
		var state: Dictionary = _interest_points[point_key] as Dictionary
		if bool(state.get("claimed", false)) or bool(state.get("target_destroyed", false)):
			continue
		if not _interest_point_has_target(state):
			continue
		var target: Node2D = INTEREST_POINT_TARGET_SCENE.instantiate() as Node2D
		if target == null or not target.has_method("configure"):
			continue
		target.global_position = _dict_to_vector(state.get("position", {}), Vector2.ZERO)
		target.call(
			"configure",
			point_id,
			String(state.get("kind", "")),
			float(state.get("target_hp", 0.0)),
			float(state.get("target_hit_radius", 24.0)),
			_map_grid_cell_size()
		)
		var target_snapshot: Dictionary = _dictionary_or_empty(state.get("target_snapshot", {}))
		if not target_snapshot.is_empty() and target.has_method("restore_snapshot"):
			target.call("restore_snapshot", target_snapshot)
		target.connect("destroyed", Callable(self, "_on_interest_point_target_destroyed"))
		_active_world.add_child(target)
		_interest_point_targets[point_id] = target


func _on_interest_point_target_destroyed(point_id: String) -> void:
	if not _interest_points.has(point_id):
		return
	var state: Dictionary = _interest_points[point_id] as Dictionary
	state["target_destroyed"] = true
	_interest_points[point_id] = state
	_claim_interest_point(point_id, true)


func _mark_interest_point_target_claimed(point_id: String) -> void:
	var target: Node = _interest_point_targets.get(point_id, null) as Node
	if target == null or not is_instance_valid(target):
		return
	if target.has_method("mark_claimed"):
		target.call("mark_claimed")


func _generate_map_hazard_placements() -> Array[Dictionary]:
	if _map_manager == null or not _map_manager.has_method("generate_hazard_placements"):
		return []
	var director_interest_points: Array[Dictionary] = []
	if _warzone_director != null and _warzone_director.has_method("interest_points_for_layout"):
		director_interest_points = _typed_dictionary_array(_warzone_director.call(
			"interest_points_for_layout",
			String(_map_layout.get("id", ""))
		))
	return _map_manager.call("generate_hazard_placements", _map_layout, director_interest_points)


func _spawn_hazard(placement: Dictionary) -> Node2D:
	var hazard_id: String = String(placement.get("hazard_id", ""))
	if not _hazard_rows.has(hazard_id):
		return null
	var hazard_data: Dictionary = _hazard_rows[hazard_id]
	var pool_id: String = String(hazard_data.get("pool_id", ""))
	var raw_node: Node = PoolManager.acquire(pool_id)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return null

	var hazard: Node2D = raw_node as Node2D
	hazard.global_position = _dict_to_vector(placement.get("position", {}), Vector2.ZERO)
	_reparent_to_active_world(hazard)
	var module_slot: String = String(placement.get("module_slot", ""))
	if module_slot.is_empty():
		if hazard.has_meta("module_slot"):
			hazard.remove_meta("module_slot")
	else:
		hazard.set_meta("module_slot", module_slot)
	hazard.call("configure", hazard_data, _player, _map_grid_cell_size())
	var activated_callback: Callable = Callable(self, "_on_hazard_activated")
	if not hazard.is_connected("activated", activated_callback):
		hazard.connect("activated", activated_callback)
	_play_feedback(_profile_or_fallback(
		String(hazard_data.get("presentation_profile_id", "")),
		PRESENTATION_HAZARD_DEFAULT
	), VFX_CUES.HAZARD_TELEGRAPH, {
		"owner": hazard,
		"world_position": hazard.global_position,
		"footprint": Rect2(
			hazard.global_position - _map_grid_cell_size() * 0.5 * float(int(hazard_data.get("radius_tiles", 1))),
			_map_grid_cell_size() * float(int(hazard_data.get("radius_tiles", 1)))
		),
	})
	return hazard


func _spawn_position() -> Vector2:
	if _map_manager != null and _map_manager.has_method("spawn_position"):
		var map_spawn_position: Vector2 = _map_manager.call("spawn_position", _player.global_position, get_viewport_rect().size)
		return map_spawn_position
	var viewport_size: Vector2 = get_viewport_rect().size
	var radius: float = maxf(viewport_size.x, viewport_size.y) * 0.55
	var angle: float = RNG.spawn.randf_range(0.0, TAU)
	return _player.global_position + Vector2.RIGHT.rotated(angle) * radius


func _map_grid_cell_size() -> Vector2:
	if _map_manager != null and _map_manager.has_method("grid_cell_size"):
		return _map_manager.call("grid_cell_size")
	return DEFAULT_GRID_CELL_SIZE


func _extraction_half_extents() -> Vector2:
	var grid_size: Vector2 = _map_grid_cell_size()
	var half_width: float = maxf(ceilf(_extraction_radius / maxf(grid_size.x, 1.0)) * grid_size.x, grid_size.x)
	var half_height: float = maxf(ceilf(_extraction_radius / maxf(grid_size.y, 1.0)) * grid_size.y, grid_size.y)
	return Vector2(half_width, half_height)


func _is_position_in_extraction_zone(world_position: Vector2) -> bool:
	if not _extraction_active:
		return false
	var half_extents: Vector2 = _extraction_half_extents()
	if half_extents.x <= 0.0 or half_extents.y <= 0.0:
		return false
	var offset: Vector2 = world_position - _extraction_position
	return absf(offset.x) <= half_extents.x and absf(offset.y) <= half_extents.y


func _draw_polygon_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	for index: int in range(points.size()):
		var start_point: Vector2 = points[index]
		var end_point: Vector2 = points[(index + 1) % points.size()]
		draw_line(start_point, end_point, color, width)


func _reparent_to_active_world(node: Node) -> void:
	var old_parent: Node = node.get_parent()
	if old_parent == _active_world:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	_active_world.add_child(node)


func _release_active_world_pool_entities() -> void:
	if _active_world == null or not is_instance_valid(_active_world):
		return
	_release_pool_entities_under(_active_world)


func _release_pool_entities_under(root_node: Node) -> void:
	for child: Node in root_node.get_children():
		_release_pool_entities_under(child)
	for group_name: String in ACTIVE_POOL_GROUPS:
		if root_node.is_in_group(group_name):
			if _vfx_host != null:
				_vfx_host.cancel_owner(root_node)
			PoolManager.release(root_node)
			return


func _on_enemy_defeated(_enemy: Node, _exp_reward: int, wave_key: String) -> void:
	if _vfx_host != null and _enemy != null:
		_vfx_host.cancel_owner(_enemy)
	var defeated_by_player: bool = true
	if _enemy != null and _enemy.has_method("was_defeated_by_player"):
		defeated_by_player = bool(_enemy.call("was_defeated_by_player"))
	if _is_debug_test_arena():
		if defeated_by_player:
			_kills += 1
		if _spawn_states.has(wave_key):
			var arena_state: Dictionary = _spawn_states[wave_key]
			arena_state["alive"] = maxi(
				int(arena_state.get("alive", 0)) - 1,
				0
			)
			_spawn_states[wave_key] = arena_state
		return
	if defeated_by_player:
		_kills += 1
		if _hud != null:
			_hud.call("set_kills", _kills)
		if _has_level_up_growth() and _enemy is Node2D and _exp_reward > 0:
			_spawn_pickup_orb((_enemy as Node2D).global_position, _exp_reward)
		if _enemy != null:
			_roll_gear_mod_drop(_enemy)
	if _spawn_states.has(wave_key):
		var state: Dictionary = _spawn_states[wave_key]
		state["alive"] = maxi(int(state.get("alive", 0)) - 1, 0)
		_spawn_states[wave_key] = state


func _spawn_pickup_orb(spawn_position: Vector2, amount: int) -> void:
	var raw_node: Node = PoolManager.acquire(POOL_IDS.PICKUP_ORB)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return

	var pickup_orb: Node2D = raw_node as Node2D
	pickup_orb.global_position = spawn_position
	_reparent_to_active_world(pickup_orb)
	pickup_orb.call("configure", amount, _player, float(_player.call("pickup_orb_speed")))
	_play_feedback(PRESENTATION_PICKUP_DEFAULT, VFX_CUES.PICKUP_SPAWN, {
		"owner": pickup_orb,
		"world_position": spawn_position,
	})
	_connect_pickup_orb_feedback(pickup_orb)


func _connect_pickup_orb_feedback(pickup_orb: Node2D) -> void:
	var attraction_callback: Callable = Callable(
		self,
		"_on_pickup_orb_attraction_started"
	).bind(pickup_orb)
	if not pickup_orb.is_connected("attraction_started", attraction_callback):
		pickup_orb.connect(
			"attraction_started",
			attraction_callback,
			CONNECT_ONE_SHOT
		)
	var collected_callback: Callable = Callable(self, "_on_pickup_orb_collected").bind(pickup_orb)
	if not pickup_orb.is_connected("collected", collected_callback):
		pickup_orb.connect("collected", collected_callback, CONNECT_ONE_SHOT)


func _on_pickup_orb_attraction_started(pickup_orb: Node2D) -> void:
	if pickup_orb == null or not is_instance_valid(pickup_orb):
		return
	_play_feedback(PRESENTATION_PICKUP_DEFAULT, VFX_CUES.PICKUP_ATTRACT, {
		"owner": pickup_orb,
		"world_position": pickup_orb.global_position,
	})


func _on_pickup_orb_collected(amount: int, pickup_orb: Node2D = null) -> void:
	var collect_position: Vector2 = (
		pickup_orb.global_position
		if pickup_orb != null and is_instance_valid(pickup_orb)
		else (_player.global_position if _player != null else Vector2.ZERO)
	)
	_play_feedback(PRESENTATION_PICKUP_DEFAULT, VFX_CUES.PICKUP_COLLECT, {
		"owner": _player,
		"world_position": collect_position,
		"follow_owner": false,
		"amount": amount,
	})
	_current_xp += amount
	_refresh_xp_hud()
	if GameState.is_state(GameState.PLAYING) and _can_level_up():
		_begin_level_up()


func _begin_level_up() -> void:
	var target_level: int = _current_level + 1
	var choices: Array[Dictionary] = _roll_growth_choices(target_level)
	if choices.is_empty():
		return

	_current_level = target_level
	if _hud != null:
		_hud.call("set_level", _current_level)
	_refresh_xp_hud()
	_show_level_up_panel(choices)


func _show_level_up_panel(choices: Array[Dictionary]) -> void:
	_pending_level_up_choices = choices.duplicate(true)

	_level_panel = UIManager.push(LEVEL_UP_PANEL_SCENE, {"source": "level_up"}) as CanvasLayer
	if _level_panel == null:
		return
	_level_panel.call("configure", choices)
	_level_panel.connect("choice_selected", Callable(self, "_on_level_up_choice_selected"), CONNECT_ONE_SHOT)
	_level_panel.connect("pause_requested", Callable(self, "_on_level_up_pause_requested"))
	GameState.change_state(GameState.LEVEL_UP, {
		"level": _current_level,
		"choices": _choice_ids(_pending_level_up_choices),
	})


func _on_level_up_pause_requested() -> void:
	if _pause_menu != null:
		return
	_show_pause_menu()


func _on_level_up_choice_selected(choice: Dictionary) -> void:
	_record_level_up_decision(choice)
	var modifiers: Array = choice.get("modifiers", []) if choice.get("modifiers", []) is Array else []
	if _player != null and _player.has_method("apply_modifiers"):
		_player.call("apply_modifiers", modifiers)
	if _weapon_system != null and _weapon_system.has_method("apply_modifiers"):
		_weapon_system.call("apply_modifiers", modifiers)
	if _hud != null and _hud.has_method("show_upgrade_feedback"):
		_hud.call("show_upgrade_feedback", String(choice.get("name_key", "")))
	if UIManager.top() == _level_panel:
		UIManager.pop()
	elif _level_panel != null:
		_level_panel.queue_free()
	_level_panel = null
	_pending_level_up_choices.clear()
	GameState.change_state(GameState.PLAYING, {
		"level": _current_level,
		"choice": String(choice.get("id", "")),
	})
	if _can_level_up():
		_begin_level_up()


func _record_level_up_decision(choice: Dictionary) -> void:
	var luck_value: float = float(_player.call("luck")) if _player != null and _player.has_method("luck") else 0.0
	Replay.record_decision(ANALYTICS_EVENTS.LEVEL_UP, {
		"level": _current_level,
		"candidate_count": _pending_level_up_choices.size(),
		"choices": _choice_ids(_pending_level_up_choices),
		"selected": String(choice.get("id", "")),
		"luck": luck_value,
	})


func _on_player_life_changed(current_life: float, max_life: float) -> void:
	if _hud != null:
		_hud.call("set_life", current_life, max_life)


func _on_combat_damage_applied(target: Node, _info: RefCounted, result: Dictionary) -> void:
	if not bool(result.get("applied", false)):
		return
	if not target is Node2D or not _is_active_world_entity(target):
		return
	var target_2d: Node2D = target as Node2D
	var amount: float = float(result.get("amount", 0.0))
	var defeated: bool = bool(result.get("defeated", false))
	var player_damage: bool = target == _player
	var enemy_damage: bool = target.has_method("enemy_id")
	var fallback_profile: String = PRESENTATION_GAMEPLAY_DEFAULT
	if player_damage:
		fallback_profile = PRESENTATION_PLAYER_DEFAULT
	elif enemy_damage:
		fallback_profile = PRESENTATION_ENEMY_DEFAULT
	var profile_id: String = _actor_profile_id(
		target_2d,
		fallback_profile
	)
	var context: Dictionary = {
		"owner": target_2d,
		"target": target_2d,
		"world_position": target_2d.global_position,
		"amount": amount,
		"defeated": defeated,
		"player_damage": player_damage,
		"camera_controller": _camera_controller,
	}
	_play_feedback(profile_id, VFX_CUES.HIT, context)
	if defeated and enemy_damage:
		_play_feedback(profile_id, VFX_CUES.DEFEAT, context)
	elif player_damage or enemy_damage:
		_play_feedback(profile_id, VFX_CUES.HURT, context)


func _play_feedback(profile_id: String, cue: String, context: Dictionary = {}) -> void:
	if _gameplay_feedback == null or not is_instance_valid(_gameplay_feedback):
		return
	_gameplay_feedback.play(profile_id, cue, context)


func _actor_profile_id(actor: Node, fallback: String) -> String:
	if actor == null:
		return fallback
	var presentation: Node = actor.get_node_or_null("Presentation")
	if presentation != null and presentation.has_method("resolved_profile_id"):
		return String(presentation.call("resolved_profile_id", fallback))
	return fallback


func _configure_actor_presentation_profile(actor: Node, profile_id: String) -> void:
	if actor == null:
		return
	var presentation: Node = actor.get_node_or_null("Presentation")
	if presentation != null and presentation.has_method("configure_profile_id"):
		presentation.call("configure_profile_id", profile_id)


func _profile_or_fallback(profile_id: String, fallback: String) -> String:
	var normalized: String = profile_id.strip_edges()
	return fallback if normalized.is_empty() else normalized


func _connect_weapon_feedback() -> void:
	if _weapon_system == null:
		return
	var fired_callback: Callable = Callable(self, "_on_weapon_fired")
	if not _weapon_system.is_connected("weapon_fired", fired_callback):
		_weapon_system.connect("weapon_fired", fired_callback)
	var started_callback: Callable = Callable(self, "_on_temporary_modifier_started")
	if not _weapon_system.is_connected("temporary_modifier_started", started_callback):
		_weapon_system.connect("temporary_modifier_started", started_callback)
	var refreshed_callback: Callable = Callable(
		self,
		"_on_temporary_modifier_refreshed"
	)
	if not _weapon_system.is_connected(
		"temporary_modifier_refreshed",
		refreshed_callback
	):
		_weapon_system.connect("temporary_modifier_refreshed", refreshed_callback)
	var expired_callback: Callable = Callable(self, "_on_temporary_modifier_expired")
	if not _weapon_system.is_connected("temporary_modifier_expired", expired_callback):
		_weapon_system.connect("temporary_modifier_expired", expired_callback)
	var restored_callback: Callable = Callable(self, "_on_temporary_modifiers_restored")
	if not _weapon_system.is_connected("temporary_modifiers_restored", restored_callback):
		_weapon_system.connect("temporary_modifiers_restored", restored_callback)


func _connect_status_feedback(owner: Node) -> void:
	if owner == null:
		return
	var status_component: Node = owner.get_node_or_null("StatusEffectComponent")
	if status_component == null:
		return
	var applied_callback: Callable = Callable(self, "_on_status_effect_applied").bind(owner)
	if not status_component.is_connected("effect_applied", applied_callback):
		status_component.connect("effect_applied", applied_callback)
	var expired_callback: Callable = Callable(self, "_on_status_effect_expired").bind(owner)
	if not status_component.is_connected("effect_expired", expired_callback):
		status_component.connect("effect_expired", expired_callback)
	var restored_callback: Callable = Callable(self, "_on_status_effect_restored").bind(owner)
	if not status_component.is_connected("effect_restored", restored_callback):
		status_component.connect("effect_restored", restored_callback)


func _on_skill_cast(_skill_id: String, result: Dictionary) -> void:
	_play_feedback(_profile_or_fallback(
		String(result.get("presentation_profile_id", "")),
		PRESENTATION_SKILL_DEFAULT
	), VFX_CUES.SKILL_CAST, {
		"owner": _player,
		"world_position": _player.global_position if _player != null else Vector2.ZERO,
		"result": result,
	})


func _on_skill_failed(_skill_id: String, result: Dictionary) -> void:
	_play_feedback(_profile_or_fallback(
		String(result.get("presentation_profile_id", "")),
		PRESENTATION_SKILL_DEFAULT
	), VFX_CUES.SKILL_FAILED, {
		"owner": _player,
		"world_position": _player.global_position if _player != null else Vector2.ZERO,
		"result": result,
	})


func _on_weapon_fired(context: Dictionary) -> void:
	_play_feedback(_profile_or_fallback(
		String(context.get("presentation_profile_id", "")),
		"presentation_weapon_default"
	), VFX_CUES.WEAPON_FIRE, context)


func _on_temporary_modifier_started(snapshot_data: Dictionary) -> void:
	_play_feedback(PRESENTATION_SKILL_OVERDRIVE, VFX_CUES.MODIFIER_STARTED, {
		"owner": _player,
		"world_position": _player.global_position if _player != null else Vector2.ZERO,
		"modifier": snapshot_data,
	})


func _on_temporary_modifier_refreshed(snapshot_data: Dictionary) -> void:
	_play_feedback(PRESENTATION_SKILL_OVERDRIVE, VFX_CUES.MODIFIER_REFRESHED, {
		"owner": _player,
		"world_position": _player.global_position if _player != null else Vector2.ZERO,
		"modifier": snapshot_data,
	})


func _on_temporary_modifier_expired(snapshot_data: Dictionary) -> void:
	_play_feedback(PRESENTATION_SKILL_OVERDRIVE, VFX_CUES.MODIFIER_EXPIRED, {
		"owner": _player,
		"world_position": _player.global_position if _player != null else Vector2.ZERO,
		"modifier": snapshot_data,
	})


func _on_temporary_modifiers_restored(active: Array[Dictionary]) -> void:
	for snapshot_data: Dictionary in active:
		_play_feedback(PRESENTATION_SKILL_OVERDRIVE, VFX_CUES.MODIFIER_REFRESHED, {
			"owner": _player,
			"world_position": _player.global_position if _player != null else Vector2.ZERO,
			"modifier": snapshot_data,
		})


func _on_status_effect_applied(
	status_id: String,
	snapshot_data: Dictionary,
	status_owner: Node
) -> void:
	var presentation_owner: Node = status_owner if status_owner is Node2D else _player
	_play_feedback(PRESENTATION_STATUS_DEFAULT, VFX_CUES.STATUS_APPLIED, {
		"owner": presentation_owner,
		"world_position": (
			(presentation_owner as Node2D).global_position
			if presentation_owner is Node2D
			else Vector2.ZERO
		),
		"status_id": status_id,
		"status": snapshot_data,
	})


func _on_status_effect_expired(
	status_id: String,
	snapshot_data: Dictionary,
	status_owner: Node
) -> void:
	var presentation_owner: Node = status_owner if status_owner is Node2D else _player
	_play_feedback(PRESENTATION_STATUS_DEFAULT, VFX_CUES.STATUS_EXPIRED, {
		"owner": presentation_owner,
		"world_position": (
			(presentation_owner as Node2D).global_position
			if presentation_owner is Node2D
			else Vector2.ZERO
		),
		"status_id": status_id,
		"status": snapshot_data,
	})


func _on_status_effect_restored(
	status_id: String,
	snapshot_data: Dictionary,
	status_owner: Node
) -> void:
	var restored_snapshot: Dictionary = snapshot_data.duplicate(true)
	restored_snapshot["restored"] = true
	_on_status_effect_applied(status_id, restored_snapshot, status_owner)


func _on_hazard_activated(context: Dictionary) -> void:
	_play_feedback(_profile_or_fallback(
		String(context.get("presentation_profile_id", "")),
		PRESENTATION_HAZARD_DEFAULT
	), VFX_CUES.HAZARD_ACTIVATED, context)


func _on_player_died() -> void:
	if _is_debug_test_arena():
		call_deferred("_reset_debug_test_arena_after_player_death")
		return
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	GameState.change_state(GameState.GAME_OVER, {
		"kills": _kills,
		"run_time": GameClock.now(),
		"completed": false,
		"lost_loot": _pending_loot.duplicate(true),
	})
	_show_game_over_panel(false, _lost_loot_summary())


func _complete_run(point_id: String) -> void:
	if _run_completed:
		return
	_run_completed = true
	var settlement: Dictionary = _commit_pending_loot()
	_reset_extraction()
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	GameState.change_state(GameState.GAME_OVER, {
		"kills": _kills,
		"run_time": GameClock.now(),
		"completed": true,
		"interest_point_id": point_id,
		"settlement": settlement.duplicate(true),
	})
	_show_game_over_panel(true, settlement)


func _show_game_over_panel(completed: bool = false, loot_summary: Dictionary = {}) -> void:
	_game_over_panel = UIManager.push(GAME_OVER_PANEL_SCENE, {"source": "game_over"}) as CanvasLayer
	if _game_over_panel == null:
		return
	_game_over_panel.call("configure", _kills, GameClock.now(), completed, loot_summary)
	_game_over_panel.connect("restart_requested", Callable(self, "_on_game_over_restart_requested"), CONNECT_ONE_SHOT)
	_game_over_panel.connect("quit_to_title_requested", Callable(self, "_on_game_over_quit_to_title_requested"), CONNECT_ONE_SHOT)


func _on_game_over_restart_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	restart_requested.emit()


func _on_game_over_quit_to_title_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	quit_to_title_requested.emit()


func _roll_gear_mod_drop(enemy: Node) -> void:
	var enemy_id: String = ""
	if enemy.has_method("enemy_id"):
		enemy_id = String(enemy.call("enemy_id"))
	elif enemy.has_meta("enemy_id"):
		enemy_id = String(enemy.get_meta("enemy_id"))
	if enemy_id.is_empty():
		return
	var forced_roll: float = _debug_next_gear_mod_drop_forced_roll
	_debug_next_gear_mod_drop_forced_roll = -1.0
	var drop_result: Dictionary = GearModSystem.roll_drop_for_enemy(enemy_id, 1, SaveManager.DEFAULT_SLOT, forced_roll, false)
	for raw_drop: Variant in drop_result.get("drops", []):
		if not raw_drop is Dictionary:
			continue
		var drop: Dictionary = raw_drop as Dictionary
		var mod_id: String = String(drop.get("mod_id", ""))
		var name_key: String = String(drop.get("name_key", ""))
		if not mod_id.is_empty():
			_add_pending_mod(mod_id, name_key)
		if name_key.is_empty():
			continue
		if _hud != null and _hud.has_method("show_gear_mod_drop_feedback"):
			_hud.call("show_gear_mod_drop_feedback", name_key)


func _apply_loadout_modifiers() -> void:
	var hero_modifiers: Array[Dictionary] = []
	var weapon_modifiers: Array[Dictionary] = []
	if _is_debug_test_arena():
		var preview: Dictionary = GearModSystem.resolve_preview_loadout(
			_array_or_empty(_debug_test_arena_config.get("gear_mods", [])),
			int(_debug_test_arena_config.get("capacity", 8))
		)
		var all_modifiers: Dictionary = _dictionary_or_empty(
			preview.get("modifiers", {})
		)
		hero_modifiers = _typed_dictionary_array(
			all_modifiers.get(GEAR_MOD_SLOTS.HERO, [])
		)
		weapon_modifiers = _typed_dictionary_array(
			all_modifiers.get(GEAR_MOD_SLOTS.WEAPON, [])
		)
	else:
		hero_modifiers = GearModSystem.current_modifiers(
			GEAR_MOD_SLOTS.HERO
		)
		weapon_modifiers = GearModSystem.current_modifiers(
			GEAR_MOD_SLOTS.WEAPON
		)
	if _player != null and _player.has_method("apply_modifiers"):
		_player.call("apply_modifiers", hero_modifiers)
	if _weapon_system != null and _weapon_system.has_method("apply_modifiers"):
		_weapon_system.call("apply_modifiers", weapon_modifiers)


func _show_pause_menu() -> void:
	if _is_debug_test_arena():
		if _debug_test_arena_controller != null:
			_debug_test_arena_controller.call("open_panel")
		return
	_pause_menu = UIManager.push(PAUSE_MENU_SCENE, {"source": "pause"}) as CanvasLayer
	if _pause_menu == null:
		return
	_pause_menu.connect("resume_requested", Callable(self, "_on_pause_resume_requested"), CONNECT_ONE_SHOT)
	_pause_menu.connect("save_and_quit_requested", Callable(self, "_on_pause_save_and_quit_requested"), CONNECT_ONE_SHOT)
	_pause_menu.connect("settings_requested", Callable(self, "_on_pause_settings_requested"))
	_pause_menu.connect("restart_requested", Callable(self, "_on_pause_restart_requested"), CONNECT_ONE_SHOT)
	_pause_menu.connect("quit_to_title_requested", Callable(self, "_on_pause_quit_to_title_requested"), CONNECT_ONE_SHOT)


func _on_pause_resume_requested() -> void:
	if UIManager.top() == _pause_menu:
		UIManager.pop()
	elif _pause_menu != null:
		_pause_menu.queue_free()
	_pause_menu = null


func _on_pause_save_and_quit_requested() -> void:
	var payload: Dictionary = create_run_snapshot()
	if not SaveManager.save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN, payload):
		push_error("[GameplayRunLoop] failed to save run snapshot: %s" % SaveManager.last_error())
		_on_pause_resume_requested()
		return
	quit_to_title_requested.emit()


func _on_pause_settings_requested() -> void:
	if _settings_panel != null and is_instance_valid(_settings_panel):
		return
	_settings_panel = UIManager.push(SETTINGS_PANEL_SCENE, {"source": "pause_menu"}) as CanvasLayer
	if _settings_panel == null:
		return
	_settings_panel.connect("closed_requested", Callable(self, "_on_settings_panel_closed"), CONNECT_ONE_SHOT)


func _on_settings_panel_closed() -> void:
	if UIManager.top() == _settings_panel:
		UIManager.pop()
	_settings_panel = null


func _on_pause_restart_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	restart_requested.emit()


func _on_pause_quit_to_title_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	quit_to_title_requested.emit()


func _entity_snapshots(group_name: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(group_name):
		if not _is_active_world_entity(node):
			continue
		if not node.has_method("snapshot"):
			continue
		var snapshot_data: Dictionary = node.call("snapshot")
		if group_name == "active_enemies" and node.has_meta("wave_key"):
			snapshot_data["wave_key"] = String(node.get_meta("wave_key"))
		if node.has_meta("module_slot"):
			snapshot_data["module_slot"] = String(node.get_meta("module_slot"))
		result.append(snapshot_data)
	return result


func _ui_restore_snapshot() -> Dictionary:
	if _pause_menu != null and not _pending_level_up_choices.is_empty():
		return {
			"state": UI_RESTORE_PAUSED,
			UI_RESTORE_UNDERLYING_STATE: UI_RESTORE_LEVEL_UP,
			"level": _current_level,
			"choices": _pending_level_up_choices.duplicate(true),
		}
	if (GameState.is_state(GameState.LEVEL_UP) or _level_panel != null) and not _pending_level_up_choices.is_empty():
		return {
			"state": UI_RESTORE_LEVEL_UP,
			"level": _current_level,
			"choices": _pending_level_up_choices.duplicate(true),
		}
	if GameState.is_state(GameState.PAUSED) or _pause_menu != null:
		return {
			"state": UI_RESTORE_PAUSED,
		}
	return {
		"state": UI_RESTORE_PLAYING,
	}


func _interest_points_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for point_key: Variant in _interest_points.keys():
		var point_id: String = String(point_key)
		var state: Dictionary = _interest_points[point_key] as Dictionary
		result[point_id] = {
			"claimed": bool(state.get("claimed", false)),
			"claimed_time": float(state.get("claimed_time", 0.0)),
			"reward_result": _dictionary_or_empty(state.get("reward_result", {})),
			"target_destroyed": bool(state.get("target_destroyed", false)),
			"target": _interest_point_target_snapshot(point_id, state),
		}
	return result


func _extraction_snapshot() -> Dictionary:
	return {
		"active": _extraction_active,
		"source_point_id": _extraction_source_point_id,
		"position": _vector_to_dict(_extraction_position),
		"radius": _extraction_radius,
		"hold_time": _extraction_hold_time,
		"progress": _extraction_progress,
	}


func _interest_point_debug_summary() -> Dictionary:
	var result: Dictionary = {}
	for point_key: Variant in _interest_points.keys():
		var point_id: String = String(point_key)
		var state: Dictionary = _interest_points[point_key] as Dictionary
		result[point_id] = {
			"kind": String(state.get("kind", "")),
			"position": _dictionary_or_empty(state.get("position", {})),
			"claim_radius": float(state.get("claim_radius", 0.0)),
			"claim_start_time": float(state.get("claim_start_time", 0.0)),
			"requires_interaction": bool(state.get("requires_interaction", false)),
			"interactable": _is_interest_point_interactable(state),
			"claimed": bool(state.get("claimed", false)),
			"claimed_time": float(state.get("claimed_time", 0.0)),
			"completes_run": bool(state.get("completes_run", false)),
			"extraction_radius": float(state.get("extraction_radius", 0.0)),
			"extraction_hold_time": float(state.get("extraction_hold_time", 0.0)),
			"target_hp": float(state.get("target_hp", 0.0)),
			"target_destroyed": bool(state.get("target_destroyed", false)),
			"resource_reward_count": _typed_dictionary_array(state.get("resource_rewards", [])).size(),
			"gear_mod_reward_count": _typed_dictionary_array(state.get("gear_mod_rewards", [])).size(),
		}
	return result


func _interest_point_target_snapshot(point_id: String, state: Dictionary) -> Dictionary:
	var target: Node = _interest_point_targets.get(point_id, null) as Node
	if target != null and is_instance_valid(target) and target.has_method("snapshot"):
		return target.call("snapshot") as Dictionary
	return _dictionary_or_empty(state.get("target_snapshot", {}))


func _interest_point_has_target(state: Dictionary) -> bool:
	return float(state.get("target_hp", 0.0)) > 0.0


func _is_active_world_entity(node: Node) -> bool:
	if node == null or _active_world == null:
		return false
	return node == _active_world or _active_world.is_ancestor_of(node)


func _restore_run_snapshot(
	snapshot_data: Dictionary,
	staged_loading: bool = false
) -> bool:
	var module_snapshot: Dictionary = _dictionary_or_empty(snapshot_data.get("module_world", {}))
	if _module_world_enabled and _module_world_manager != null:
		if module_snapshot.is_empty() or not bool(_module_world_manager.call("restore_state", module_snapshot)):
			push_error("[GameplayRunLoop] module-world snapshot restore failed")
			return false
		_register_all_module_interest_points()
		var active_coords: Array[Vector2i] = _module_world_manager.call("active_module_coords")
		for module_coord: Vector2i in active_coords:
			_activate_module_slot(module_coord, false)
			if staged_loading and not await _yield_loading_frame():
				return false

	_current_level = maxi(int(snapshot_data.get("level", 1)), 1)
	_current_xp = maxi(int(snapshot_data.get("xp", 0)), 0)
	_kills = maxi(int(snapshot_data.get("kills", 0)), 0)
	_spawn_states = _dictionary_or_empty(snapshot_data.get("spawn_states", {}))

	var rng_snapshot: Variant = snapshot_data.get("rng", {})
	if rng_snapshot is Dictionary:
		RNG.restore_snapshot(rng_snapshot as Dictionary)

	var map_snapshot: Variant = snapshot_data.get("map", {})
	if _map_manager != null and _map_manager.has_method("restore_snapshot") and map_snapshot is Dictionary:
		_map_manager.call("restore_snapshot", map_snapshot as Dictionary)
	_apply_player_movement_bounds()

	if _player != null and _player.has_method("restore_snapshot") and snapshot_data.get("player", {}) is Dictionary:
		_player.call("restore_snapshot", snapshot_data.get("player", {}) as Dictionary)
	if _weapon_system != null and _weapon_system.has_method("restore_snapshot") and snapshot_data.get("weapon", {}) is Dictionary:
		_weapon_system.call("restore_snapshot", snapshot_data.get("weapon", {}) as Dictionary)
	if _skill_system != null and _skill_system.has_method("restore_snapshot") and snapshot_data.get("skills", {}) is Dictionary:
		_skill_system.call("restore_snapshot", snapshot_data.get("skills", {}) as Dictionary)

	var hazard_snapshots: Array = _array_or_empty(snapshot_data.get("hazards", []))
	if hazard_snapshots.is_empty() and not _module_world_enabled and _map_manager != null and _map_manager.has_method("generate_hazard_placements"):
		var hazard_placements: Array[Dictionary] = _generate_map_hazard_placements()
		_spawn_map_hazards(hazard_placements)
	elif staged_loading:
		if not await _restore_snapshots_staged(
			hazard_snapshots,
			Callable(self, "_restore_hazard_snapshots")
		):
			return false
	else:
		_restore_hazard_snapshots(hazard_snapshots)
	if not _module_world_enabled and _map_manager != null and _map_manager.has_method("hazard_placements"):
		_configure_interest_points(_typed_dictionary_array(_map_manager.call("hazard_placements")))
	_restore_interest_points(snapshot_data.get("interest_points", {}))
	_restore_pending_loot(snapshot_data.get("pending_loot", {}))
	_restore_extraction(snapshot_data.get("extraction", {}))
	if _module_world_enabled and _module_world_manager != null:
		var active_module_coords: Array[Vector2i] = _module_world_manager.call("active_module_coords")
		for module_coord: Vector2i in active_module_coords:
			_spawn_module_interest_visuals(_module_slot_key(module_coord))
	else:
		_spawn_interest_point_caches()
		_spawn_interest_point_targets()
	if staged_loading and not await _yield_loading_frame():
		return false
	var enemy_snapshots: Array = _array_or_empty(snapshot_data.get("enemies", []))
	var bullet_snapshots: Array = _array_or_empty(snapshot_data.get("bullets", []))
	var pickup_snapshots: Array = _array_or_empty(snapshot_data.get("pickups", []))
	if staged_loading:
		if not await _restore_snapshots_staged(
			enemy_snapshots,
			Callable(self, "_restore_enemy_snapshots")
		):
			return false
		if not await _restore_snapshots_staged(
			bullet_snapshots,
			Callable(self, "_restore_bullet_snapshots")
		):
			return false
		if not await _restore_snapshots_staged(
			pickup_snapshots,
			Callable(self, "_restore_pickup_snapshots")
		):
			return false
	else:
		_restore_enemy_snapshots(enemy_snapshots)
		_restore_bullet_snapshots(bullet_snapshots)
		_restore_pickup_snapshots(pickup_snapshots)

	var clock_snapshot: Variant = snapshot_data.get("game_clock", {})
	if clock_snapshot is Dictionary:
		GameClock.restore_snapshot(clock_snapshot as Dictionary)

	if _hud != null:
		_hud.call("set_life", _player.call("current_life"), _player.call("max_life"))
		_hud.call("set_kills", _kills)
		_hud.call("set_level", _current_level)
	_refresh_xp_hud()
	_refresh_module_world_hud()
	return true


func _restore_interest_points(raw_value: Variant) -> void:
	var saved_points: Dictionary = _dictionary_or_empty(raw_value)
	for point_key: Variant in saved_points.keys():
		var point_id: String = String(point_key)
		if not _interest_points.has(point_id):
			continue
		var saved_state: Dictionary = _dictionary_or_empty(saved_points[point_key])
		var state: Dictionary = _interest_points[point_id] as Dictionary
		state["claimed"] = bool(saved_state.get("claimed", state.get("claimed", false)))
		state["claimed_time"] = float(saved_state.get("claimed_time", state.get("claimed_time", 0.0)))
		state["target_destroyed"] = bool(saved_state.get("target_destroyed", state.get("target_destroyed", false)))
		if saved_state.has("reward_result"):
			state["reward_result"] = _dictionary_or_empty(saved_state.get("reward_result", {}))
		if saved_state.has("target"):
			state["target_snapshot"] = _dictionary_or_empty(saved_state.get("target", {}))
		_interest_points[point_id] = state


func _restore_pending_loot(raw_value: Variant) -> void:
	var saved_loot: Dictionary = _dictionary_or_empty(raw_value)
	_pending_loot = _empty_pending_loot()
	var resources: Dictionary = _dictionary_or_empty(saved_loot.get("resources", {}))
	for resource_key: Variant in resources.keys():
		var resource_id: String = String(resource_key)
		var amount: int = maxi(int(resources.get(resource_key, 0)), 0)
		if resource_id.is_empty() or amount <= 0:
			continue
		_add_pending_resource(resource_id, amount)
	for entry: Dictionary in _typed_dictionary_array(saved_loot.get("gear_mods", [])):
		var mod_id: String = String(entry.get("mod_id", ""))
		if mod_id.is_empty():
			continue
		_add_pending_mod(mod_id, String(entry.get("name_key", _gear_mod_name_key(mod_id))))


func _restore_extraction(raw_value: Variant) -> void:
	var saved_state: Dictionary = _dictionary_or_empty(raw_value)
	if saved_state.is_empty() or not bool(saved_state.get("active", false)):
		_reset_extraction()
		return
	_extraction_active = true
	_extraction_source_point_id = String(saved_state.get("source_point_id", ""))
	_extraction_position = _dict_to_vector(saved_state.get("position", {}), Vector2.ZERO)
	_extraction_radius = maxf(float(saved_state.get("radius", 0.0)), 0.0)
	_extraction_hold_time = maxf(float(saved_state.get("hold_time", 0.0)), 0.0)
	_extraction_progress = clampf(float(saved_state.get("progress", 0.0)), 0.0, _extraction_hold_time)
	queue_redraw()


func _empty_pending_loot() -> Dictionary:
	return {
		"resources": {},
		"gear_mods": [],
	}


func _add_pending_resource(resource_id: String, amount: int) -> void:
	if resource_id.is_empty() or amount <= 0:
		return
	var resources: Dictionary = _dictionary_or_empty(_pending_loot.get("resources", {}))
	resources[resource_id] = int(resources.get(resource_id, 0)) + amount
	_pending_loot["resources"] = resources


func _add_pending_mod(mod_id: String, name_key: String) -> void:
	if mod_id.is_empty():
		return
	var mods: Array = _array_or_empty(_pending_loot.get("gear_mods", []))
	mods.append({
		"mod_id": mod_id,
		"name_key": name_key if not name_key.is_empty() else _gear_mod_name_key(mod_id),
	})
	_pending_loot["gear_mods"] = mods


func _gear_mod_name_key(mod_id: String) -> String:
	for mod: Dictionary in _typed_dictionary_array(_load_array(DataLoader.GEAR_MODS_PATH, "mods")):
		if String(mod.get("id", "")) == mod_id:
			return String(mod.get("name_key", ""))
	return ""


func _commit_pending_loot() -> Dictionary:
	var settlement: Dictionary = _empty_pending_loot()
	var resources: Dictionary = _dictionary_or_empty(_pending_loot.get("resources", {}))
	for resource_key: Variant in resources.keys():
		var resource_id: String = String(resource_key)
		var amount: int = maxi(int(resources.get(resource_key, 0)), 0)
		if resource_id.is_empty() or amount <= 0:
			continue
		var grant: Dictionary = GearModSystem.grant_resource(resource_id, amount, SaveManager.DEFAULT_SLOT)
		if bool(grant.get("ok", false)):
			var settled_resources: Dictionary = _dictionary_or_empty(settlement.get("resources", {}))
			settled_resources[resource_id] = int(settled_resources.get(resource_id, 0)) + amount
			settlement["resources"] = settled_resources

	for entry: Dictionary in _typed_dictionary_array(_pending_loot.get("gear_mods", [])):
		var mod_id: String = String(entry.get("mod_id", ""))
		if mod_id.is_empty():
			continue
		var grant: Dictionary = GearModSystem.grant_mod(mod_id, 1, SaveManager.DEFAULT_SLOT)
		if bool(grant.get("ok", false)):
			var settled_mods: Array = _array_or_empty(settlement.get("gear_mods", []))
			settled_mods.append({
				"mod_id": mod_id,
				"name_key": String(grant.get("name_key", entry.get("name_key", ""))),
				"instance_ids": grant.get("instance_ids", []),
			})
			settlement["gear_mods"] = settled_mods

	_pending_loot = _empty_pending_loot()
	return settlement


func _lost_loot_summary() -> Dictionary:
	return _pending_loot.duplicate(true)


func _restore_ui_state(raw_ui_restore: Variant) -> void:
	if not raw_ui_restore is Dictionary:
		return
	var ui_restore: Dictionary = raw_ui_restore as Dictionary
	var state: String = String(ui_restore.get("state", UI_RESTORE_PLAYING))
	if state == UI_RESTORE_PAUSED:
		if String(ui_restore.get(UI_RESTORE_UNDERLYING_STATE, "")) == UI_RESTORE_LEVEL_UP:
			var paused_level_up_choices: Array[Dictionary] = _typed_choice_array(ui_restore.get("choices", []))
			if not paused_level_up_choices.is_empty():
				_show_level_up_panel(paused_level_up_choices)
		_show_pause_menu()
		return
	if state == UI_RESTORE_LEVEL_UP:
		var typed_choices: Array[Dictionary] = _typed_choice_array(ui_restore.get("choices", []))
		if typed_choices.is_empty():
			return
		_show_level_up_panel(typed_choices)


func _typed_choice_array(raw_value: Variant) -> Array[Dictionary]:
	var choices: Array = _array_or_empty(raw_value)
	var typed_choices: Array[Dictionary] = []
	for raw_choice: Variant in choices:
		if raw_choice is Dictionary:
			typed_choices.append((raw_choice as Dictionary).duplicate(true))
	return typed_choices


func _restore_hazard_snapshots(hazard_snapshots: Array) -> void:
	for raw_snapshot: Variant in hazard_snapshots:
		if not raw_snapshot is Dictionary:
			continue
		var snapshot_data: Dictionary = raw_snapshot as Dictionary
		var hazard_id: String = String(snapshot_data.get("hazard_id", ""))
		if not _hazard_rows.has(hazard_id):
			continue
		var restored_position: Vector2 = _dict_to_vector(snapshot_data.get("position", {}), Vector2.ZERO)
		if _map_manager != null and _map_manager.has_method("normalize_hazard_position"):
			restored_position = _map_manager.call("normalize_hazard_position", restored_position, hazard_id)
		elif _map_manager != null and _map_manager.has_method("snap_to_grid"):
			restored_position = _map_manager.call("snap_to_grid", restored_position)
			if _map_manager.has_method("clamp_position"):
				restored_position = _map_manager.call("clamp_position", restored_position)
		var restored_position_data: Dictionary = {
			"x": restored_position.x,
			"y": restored_position.y,
		}
		var placement: Dictionary = {
			"hazard_id": hazard_id,
			"position": restored_position_data,
			"module_slot": String(snapshot_data.get("module_slot", "")),
		}
		var restored_snapshot: Dictionary = snapshot_data.duplicate(true)
		restored_snapshot["position"] = restored_position_data
		var hazard: Node2D = _spawn_hazard(placement)
		if hazard != null and hazard.has_method("restore_snapshot"):
			hazard.call("restore_snapshot", restored_snapshot)


func _restore_snapshots_staged(
	snapshots: Array,
	restore_batch: Callable
) -> bool:
	var batch: Array = []
	for raw_snapshot: Variant in snapshots:
		batch.append(raw_snapshot)
		if batch.size() < LOADING_BATCH_SIZE:
			continue
		restore_batch.call(batch)
		batch.clear()
		if not await _yield_loading_frame():
			return false
	if not batch.is_empty():
		restore_batch.call(batch)
		if not await _yield_loading_frame():
			return false
	return true


func _restore_enemy_snapshots(enemy_snapshots: Array) -> void:
	for raw_snapshot: Variant in enemy_snapshots:
		if not raw_snapshot is Dictionary:
			continue
		var snapshot_data: Dictionary = raw_snapshot as Dictionary
		var enemy_id: String = String(snapshot_data.get("enemy_id", ""))
		if not _enemy_rows.has(enemy_id):
			continue
		var module_slot: String = String(snapshot_data.get("module_slot", ""))
		var restored_position: Vector2 = _dict_to_vector(snapshot_data.get("position", {}), Vector2.ZERO)
		if not module_slot.is_empty() and not _is_module_world_position_walkable(restored_position):
			continue
		var enemy_data: Dictionary = _enemy_rows[enemy_id]
		var pool_id: String = String(enemy_data.get("pool_id", ""))
		var raw_node: Node = PoolManager.acquire(pool_id)
		if not raw_node is Node2D or not raw_node.has_method("configure"):
			continue

		var enemy: Node2D = raw_node as Node2D
		_reparent_to_active_world(enemy)
		enemy.global_position = restored_position
		var wave_key: String = String(snapshot_data.get("wave_key", ""))
		enemy.set_meta("wave_key", wave_key)
		if module_slot.is_empty():
			if enemy.has_meta("module_slot"):
				enemy.remove_meta("module_slot")
		else:
			enemy.set_meta("module_slot", module_slot)
		enemy.call("configure", enemy_data, _player, _enemy_navigation_provider())
		_apply_enemy_movement_bounds(enemy)
		_connect_enemy_defeated(enemy, wave_key)
		if enemy.has_method("restore_snapshot"):
			enemy.call("restore_snapshot", snapshot_data)


func _is_module_world_position_walkable(world_position: Vector2) -> bool:
	return (
		_module_world_enabled
		and _module_world_manager != null
		and _module_world_manager.has_method("is_world_position_walkable")
		and bool(_module_world_manager.call("is_world_position_walkable", world_position))
	)


func _enemy_navigation_provider() -> Node:
	if _module_world_enabled and _module_world_manager != null:
		return _module_world_manager
	return null


func _restore_bullet_snapshots(bullet_snapshots: Array) -> void:
	for raw_snapshot: Variant in bullet_snapshots:
		if not raw_snapshot is Dictionary:
			continue
		var raw_node: Node = PoolManager.acquire(POOL_IDS.BULLET_BASIC)
		if not raw_node is Node2D or not raw_node.has_method("restore_snapshot"):
			continue

		var bullet: Node2D = raw_node as Node2D
		_reparent_to_active_world(bullet)
		bullet.call("restore_snapshot", raw_snapshot as Dictionary, _player)


func _restore_pickup_snapshots(pickup_snapshots: Array) -> void:
	for raw_snapshot: Variant in pickup_snapshots:
		if not raw_snapshot is Dictionary:
			continue
		var raw_node: Node = PoolManager.acquire(POOL_IDS.PICKUP_ORB)
		if not raw_node is Node2D or not raw_node.has_method("restore_snapshot"):
			continue

		var pickup_orb: Node2D = raw_node as Node2D
		_reparent_to_active_world(pickup_orb)
		pickup_orb.call("restore_snapshot", raw_snapshot as Dictionary, _player)
		_connect_pickup_orb_feedback(pickup_orb)


func _apply_enemy_movement_bounds(enemy: Node2D) -> void:
	if _map_manager == null or not _map_manager.has_method("bounds"):
		return
	if not enemy.has_method("set_movement_bounds"):
		return
	enemy.call("set_movement_bounds", _map_manager.call("bounds"))


func _apply_player_movement_bounds() -> void:
	if _player == null or _map_manager == null or not _map_manager.has_method("bounds"):
		return
	if _player.has_method("set_movement_bounds"):
		_player.call("set_movement_bounds", _map_manager.call("bounds"))


func _connect_enemy_defeated(enemy: Node, wave_key: String) -> void:
	var callback: Callable = Callable(self, "_on_enemy_defeated").bind(wave_key)
	for connection: Dictionary in enemy.get_signal_connection_list("defeated"):
		var raw_callable: Variant = connection.get("callable")
		if not raw_callable is Callable:
			continue
		var existing_callback: Callable = raw_callable as Callable
		if existing_callback.get_object() == self and existing_callback.get_method() == "_on_enemy_defeated":
			enemy.disconnect("defeated", existing_callback)
	enemy.connect("defeated", callback, CONNECT_ONE_SHOT)
	_connect_status_feedback(enemy)
	if enemy is Node2D:
		_play_feedback(_actor_profile_id(enemy, PRESENTATION_ENEMY_DEFAULT), VFX_CUES.SPAWN, {
			"owner": enemy,
			"world_position": (enemy as Node2D).global_position,
		})


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))


func _dict_to_vector2i(raw_value: Variant, fallback: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	if raw_value is Vector2i:
		return raw_value as Vector2i
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2i(int(value.get("x", fallback.x)), int(value.get("y", fallback.y)))


func _coord_to_dict(value: Vector2i) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		var text: String = String(item)
		if not text.is_empty():
			result.append(text)
	return result


func _load_array(path: String, key: String) -> Array:
	var data: Variant = DataLoader.load_json(path)
	if not data is Dictionary:
		return []
	var raw_items: Variant = (data as Dictionary).get(key, [])
	return raw_items if raw_items is Array else []


func _load_skill_definitions(loadout: Dictionary) -> Array[Dictionary]:
	var requested_ids: Array[String] = _string_array(loadout.get("skill_ids", []))
	var all_skills: Array = _load_array(DataLoader.SKILLS_PATH, "skills")
	var result: Array[Dictionary] = []
	for skill_id: String in requested_ids:
		var skill: Dictionary = _find_item(all_skills, skill_id)
		if not skill.is_empty():
			result.append(skill)
	return result


func _find_item(items: Array, requested_id: String) -> Dictionary:
	for item: Variant in items:
		if item is Dictionary and String((item as Dictionary).get("id", "")) == requested_id:
			return (item as Dictionary).duplicate(true)
	return {}


func _merged_player_stats(character: Dictionary, mode: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var player_data: Variant = DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	if player_data is Dictionary and (player_data as Dictionary).get("base_stats") is Dictionary:
		result.merge((player_data as Dictionary).get("base_stats") as Dictionary, true)
	if character.get("base_stats") is Dictionary:
		result.merge(character.get("base_stats") as Dictionary, true)
	var overrides: Variant = mode.get("overrides", {})
	if overrides is Dictionary and (overrides as Dictionary).get("player_base_stats") is Dictionary:
		result.merge((overrides as Dictionary).get("player_base_stats") as Dictionary, true)
	return result


func _load_enemy_ai_profiles() -> Dictionary:
	var result: Dictionary = {}
	var data: Variant = DataLoader.load_json(DataLoader.ENEMY_AI_PROFILES_PATH)
	if not data is Dictionary:
		return result
	var profiles: Variant = (data as Dictionary).get("profiles", [])
	if not profiles is Array:
		return result
	for raw_profile: Variant in profiles:
		if not raw_profile is Dictionary:
			continue
		var profile: Dictionary = (raw_profile as Dictionary).duplicate(true)
		var profile_id: String = String(profile.get("id", ""))
		if profile_id.is_empty():
			continue
		result[profile_id] = profile
	return result


func _load_enemy_rows(
	ai_profiles: Dictionary,
	enemy_csv_rows: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in enemy_csv_rows:
		var requested_id: String = String(row.get("id", ""))
		if requested_id.is_empty():
			continue
		var ai_profile_id: String = String(row.get("ai_profile_id", ""))
		result[requested_id] = {
			"id": requested_id,
			"tags": _parse_tag_list(row.get("tags")),
			"pool_id": String(row.get("pool_id", "")),
			"scene_path": String(row.get("scene_path", "")),
			"pool_prewarm": String(row.get("pool_prewarm", "0")).to_int(),
			"ai_profile_id": ai_profile_id,
			"ai_profile": ai_profiles.get(ai_profile_id, {}),
			"max_hp": String(row.get("max_hp", "1")).to_int(),
			"move_speed": String(row.get("move_speed", "0.0")).to_float(),
			"contact_damage": String(row.get("contact_damage", "0")).to_int(),
			"contact_damage_type": String(row.get("contact_damage_type", "")),
			"exp_reward": String(row.get("exp_reward", "0")).to_int(),
			"hit_radius": String(row.get("hit_radius", "1.0")).to_float(),
			"separation_radius": String(row.get("separation_radius", "0.0")).to_float(),
		}
	return result


func _load_hazard_rows() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in DataLoader.load_csv(DataLoader.HAZARDS_PATH):
		var requested_id: String = String(row.get("id", ""))
		if requested_id.is_empty():
			continue
		result[requested_id] = {
			"id": requested_id,
			"tags": _parse_tag_list(row.get("tags")),
			"pool_id": String(row.get("pool_id", "")),
			"damage": String(row.get("damage", "0")).to_int(),
			"damage_type": String(row.get("damage_type", "")),
			"trigger_interval": String(row.get("trigger_interval", "1.0")).to_float(),
			"radius_tiles": String(row.get("radius_tiles", "1")).to_int(),
			"duration": String(row.get("duration", "0.0")).to_float(),
		}
	return result


func _parse_tag_list(raw_value: Variant) -> Array[String]:
	var tags: Array[String] = []
	for raw_tag: String in String(raw_value).split("|", false):
		var tag: String = raw_tag.strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	return tags


func _load_map_layout(mode_id: String) -> Dictionary:
	var data: Variant = DataLoader.load_json(DataLoader.MAP_LAYOUTS_PATH)
	if not data is Dictionary:
		return {}
	var raw_layouts: Variant = (data as Dictionary).get("layouts", [])
	if not raw_layouts is Array:
		return {}
	for raw_layout: Variant in raw_layouts as Array:
		if not raw_layout is Dictionary:
			continue
		var layout: Dictionary = raw_layout as Dictionary
		if String(layout.get("mode_id", "")) == mode_id:
			return layout.duplicate(true)
	return {}


func _load_waves(target_mode: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in DataLoader.load_csv(DataLoader.SPAWN_WAVES_PATH):
		if String(row.get("mode_id", "")) != target_mode:
			continue
		result.append({
			"id": String(row.get("id", "")),
			"start_time": String(row.get("start_time", "0.0")).to_float(),
			"end_time": String(row.get("end_time", "0.0")).to_float(),
			"enemy_id": String(row.get("enemy_id", "")),
			"spawn_interval": String(row.get("spawn_interval", "1.0")).to_float(),
			"max_alive": String(row.get("max_alive", "0")).to_int(),
			"spawn_budget": String(row.get("spawn_budget", "0")).to_int(),
		})
	return result


func _load_warzone_director(target_mode: String) -> Dictionary:
	var data: Variant = DataLoader.load_json(DataLoader.WARZONE_DIRECTORS_PATH)
	if not data is Dictionary:
		return {}
	var raw_directors: Variant = (data as Dictionary).get("directors", [])
	if not raw_directors is Array:
		return {}
	for raw_director: Variant in raw_directors as Array:
		if not raw_director is Dictionary:
			continue
		var director: Dictionary = raw_director as Dictionary
		if String(director.get("mode_id", "")) == target_mode:
			return director.duplicate(true)
	return {}


func _load_growth_curve() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in DataLoader.load_csv(DataLoader.GROWTH_CURVE_PATH):
		result.append({
			"level": String(row.get("level", "1")).to_int(),
			"total_xp_required": String(row.get("total_xp_required", "0")).to_int(),
			"candidate_count": String(row.get("candidate_count", "3")).to_int(),
			"bonus_candidate_chance_per_luck": String(row.get("bonus_candidate_chance_per_luck", "0.0")).to_float(),
			"bonus_candidate_chance_cap": String(row.get("bonus_candidate_chance_cap", "0.0")).to_float(),
		})
	return result


func _load_growth_entries(mode: Dictionary) -> Array[Dictionary]:
	var pool_entries: Dictionary = {}
	var data: Variant = DataLoader.load_json(DataLoader.GROWTH_POOLS_PATH)
	if data is Dictionary:
		for raw_pool: Variant in (data as Dictionary).get("pools", []):
			if raw_pool is Dictionary:
				pool_entries[String((raw_pool as Dictionary).get("id", ""))] = (raw_pool as Dictionary).get("entries", [])

	var result: Array[Dictionary] = []
	var resource_pools: Dictionary = mode.get("resource_pools", {}) if mode.get("resource_pools", {}) is Dictionary else {}
	var growth_pools: Array = resource_pools.get("growth_pools", []) if resource_pools.get("growth_pools", []) is Array else []
	for raw_pool_ref: Variant in growth_pools:
		if not raw_pool_ref is Dictionary:
			continue
		var pool_ref: Dictionary = raw_pool_ref as Dictionary
		var pool_id: String = String(pool_ref.get("id", ""))
		var pool_weight: int = int(pool_ref.get("weight", 0))
		for raw_entry: Variant in pool_entries.get(pool_id, []):
			if not raw_entry is Dictionary:
				continue
			var entry: Dictionary = (raw_entry as Dictionary).duplicate(true)
			entry["weight"] = int(entry.get("weight", 0)) * maxi(pool_weight, 1)
			result.append(entry)
	return result


func _can_level_up() -> bool:
	if not _has_level_up_growth():
		return false
	return _current_xp >= _xp_required_for_level(_current_level + 1)


func _has_level_up_growth() -> bool:
	return not _growth_entries.is_empty() and not _growth_curve.is_empty()


func _refresh_xp_hud() -> void:
	if _hud != null:
		_hud.call("set_xp", current_level_xp(), current_level_xp_required())


func _update_stats_panel() -> void:
	if _hud == null or not _hud.has_method("set_stats_panel_visible"):
		return
	var should_show: bool = (
		GameState.is_state(GameState.PLAYING)
		and InputService.is_pressed(ACTIONS.SHOW_STATS_PANEL, INPUT_PARTICIPANT_ID)
	)
	_hud.call("set_stats_panel_visible", should_show)
	if should_show and _hud.has_method("set_detailed_stats"):
		_hud.call("set_detailed_stats", _stats_panel_snapshot())


func _stats_panel_snapshot() -> Dictionary:
	return {
		"life": "%d/%d" % [
			int(ceilf(float(_player.call("current_life")))) if _player != null and _player.has_method("current_life") else 0,
			int(ceilf(float(_player.call("max_life")))) if _player != null and _player.has_method("max_life") else 0,
		],
		"level": "%d" % _current_level,
		"xp": "%d/%d" % [current_level_xp(), current_level_xp_required()],
		"kills": "%d" % _kills,
		"run_time": "%ds" % int(GameClock.now()),
		"damage": _format_stat_value(_weapon_stat(STATS.DAMAGE)),
		"health_regen": "%s/s" % _format_stat_value(_player_stat(STATS.HEALTH_REGEN)),
		"fire_rate": _format_stat_value(_weapon_stat(STATS.FIRE_RATE)),
		"move_speed": _format_stat_value(_player_stat(STATS.MOVE_SPEED)),
		"bullet_speed": _format_stat_value(_weapon_stat(STATS.BULLET_SPEED)),
		"bullet_range": _format_stat_value(_weapon_stat(STATS.BULLET_RANGE)),
		"bullet_count": _format_stat_value(_weapon_stat(STATS.BULLET_COUNT)),
		"pierce_count": _format_stat_value(_weapon_stat(STATS.PIERCE_COUNT)),
		"crit_chance": _format_percent(_weapon_stat(STATS.CRIT_CHANCE)),
		"crit_mult": "%sx" % _format_stat_value(_weapon_stat(STATS.CRIT_MULT)),
		"pickup_range": _format_stat_value(_player_stat(STATS.PICKUP_RANGE)),
		"luck": _format_stat_value(_player_stat(STATS.LUCK)),
		"skill_resource": _skill_resource_text(),
		"skill_cooldown": _skill_cooldown_text(),
	}


func _player_stat(stat: String) -> float:
	if _player != null and _player.has_method("stat_value"):
		return float(_player.call("stat_value", stat))
	return 0.0


func _weapon_stat(stat: String) -> float:
	if _weapon_system != null and _weapon_system.has_method("stat_value"):
		return float(_weapon_system.call("stat_value", stat))
	return 0.0


func _skill_resource_text() -> String:
	var summary: Dictionary = _skill_summary()
	var resources: Dictionary = summary.get("resources", {}) as Dictionary
	if resources.is_empty():
		return "-"
	var resource_ids: Array[String] = _sorted_dictionary_keys(resources)
	var resource_id: String = resource_ids[0]
	var resource: Dictionary = resources.get(resource_id, {}) as Dictionary
	return "%s %s/%s" % [
		_skill_resource_label(resource_id),
		_format_stat_value(float(resource.get("current", 0.0))),
		_format_stat_value(float(resource.get("max", 0.0))),
	]


func _skill_cooldown_text() -> String:
	var summary: Dictionary = _skill_summary()
	var cooldowns: Dictionary = summary.get("cooldowns", {}) as Dictionary
	if cooldowns.is_empty():
		return "-"
	var skill_ids: Array[String] = _sorted_dictionary_keys(cooldowns)
	return "%ss" % _format_stat_value(float(cooldowns.get(skill_ids[0], 0.0)))


func _skill_summary() -> Dictionary:
	if _skill_system != null and _skill_system.has_method("debug_summary"):
		return _skill_system.call("debug_summary") as Dictionary
	return {}


func _skill_resource_label(resource_id: String) -> String:
	if resource_id == SKILL_RESOURCES.MANA:
		return tr("skill_resource_mana_name")
	return resource_id


func _sorted_dictionary_keys(dictionary: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in dictionary.keys():
		result.append(String(key))
	result.sort()
	return result


func _format_stat_value(value: float) -> String:
	if absf(value - roundf(value)) < 0.05:
		return "%d" % int(roundf(value))
	return "%.1f" % value


func _format_percent(value: float) -> String:
	return "%d%%" % int(roundf(clampf(value, 0.0, 1.0) * 100.0))


func _xp_progress_for_level(level: int) -> int:
	return maxi(_current_xp - _xp_required_for_level(level), 0)


func _xp_required_within_level(level: int) -> int:
	return maxi(_xp_required_for_level(level + 1) - _xp_required_for_level(level), 0)


func _xp_required_for_level(level: int) -> int:
	for row: Dictionary in _growth_curve:
		if int(row.get("level", 0)) == level:
			return int(row.get("total_xp_required", 0))
	return 2_147_483_647


func _growth_row_for_level(level: int) -> Dictionary:
	for row: Dictionary in _growth_curve:
		if int(row.get("level", 0)) == level:
			return row
	return {}


func _roll_growth_choices(target_level: int) -> Array[Dictionary]:
	var row: Dictionary = _growth_row_for_level(target_level)
	if row.is_empty():
		return []

	var candidate_count: int = int(row.get("candidate_count", 3))
	var luck_value: float = float(_player.call("luck")) if _player != null and _player.has_method("luck") else 0.0
	var bonus_chance: float = minf(
		luck_value * float(row.get("bonus_candidate_chance_per_luck", 0.0)),
		float(row.get("bonus_candidate_chance_cap", 0.0))
	)
	if RNG.ui_choice.randf() < bonus_chance:
		candidate_count += 1

	var available: Array[Dictionary] = []
	for entry: Dictionary in _growth_entries:
		if int(entry.get("min_level", 1)) <= target_level:
			available.append(entry.duplicate(true))

	var choices: Array[Dictionary] = []
	while not available.is_empty() and choices.size() < candidate_count:
		var weights: Array[int] = []
		for entry: Dictionary in available:
			weights.append(int(entry.get("weight", 0)))
		var selected: Variant = RNG.ui_choice.weighted_pick(available, weights)
		if not selected is Dictionary:
			break
		var selected_entry: Dictionary = selected as Dictionary
		choices.append(selected_entry.duplicate(true))
		available.erase(selected_entry)
	choices.sort_custom(_sort_growth_choices_by_id)
	return choices


func _sort_growth_choices_by_id(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("id", "")) < String(right.get("id", ""))


func _choice_ids(choices: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for choice: Dictionary in choices:
		result.append(String(choice.get("id", "")))
	return result


func _damage_info(amount: float, target: Node) -> RefCounted:
	return DAMAGE_INFO_SCRIPT.new().setup(
		amount,
		DAMAGE_TYPES.PHYSICAL,
		self,
		target,
		"team_debug",
		"team_target",
		PackedStringArray(["debug"])
	)


func _debug_test_arena_damage_info(
	amount: float,
	target: Node
) -> RefCounted:
	return DAMAGE_INFO_SCRIPT.new().setup(
		amount,
		DAMAGE_TYPES.PHYSICAL,
		_player,
		target,
		"team_player",
		"team_enemy",
		PackedStringArray(["debug_test_arena"])
	)


func _active_enemy_count() -> int:
	var result: int = 0
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if _is_active_world_entity(enemy):
			result += 1
	return result


func _reset_debug_test_arena_after_player_death() -> void:
	if (
		not _is_debug_test_arena()
		or _debug_test_arena_controller == null
	):
		return
	_debug_test_arena_controller.call("reset_after_player_death")


func _enemy_rows_array() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var enemy_ids: Array[String] = _sorted_dictionary_keys(_enemy_rows)
	for enemy_id: String in enemy_ids:
		var raw_row: Variant = _enemy_rows.get(enemy_id, {})
		if raw_row is Dictionary:
			rows.append((raw_row as Dictionary).duplicate(true))
	return rows


func _is_debug_test_arena() -> bool:
	return _run_purpose == RunPurpose.DEBUG_TEST_ARENA


func _debug_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}
