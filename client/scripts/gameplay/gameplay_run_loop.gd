# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/正式项目工作规划.md F4
class_name GameplayRunLoop
extends Node2D


signal quit_to_title_requested()
signal restart_requested()
signal restore_failed()
signal run_prepared()
signal run_prepare_failed(reason: String, restoring: bool)
signal debug_test_arena_exit_requested()
signal debug_test_arena_setup_requested()
signal reward_choice_resolved(
	trigger_id: String,
	pool_id: String,
	entry_id: String
)

enum RunPurpose {
	STANDARD,
	DEBUG_TEST_ARENA,
}

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const CONTENT_UNLOCK_PROGRESS_COUNTERS := preload(
	"res://scripts/contracts/content_unlock_progress_counters.gd"
)
const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DIFFICULTY_PROGRESSION_SCRIPT := preload(
	"res://scripts/data/difficulty_progression.gd"
)
const ENEMY_REWARD_RESOLVER_SCRIPT := preload(
	"res://scripts/data/enemy_reward_resolver.gd"
)
const ENEMY_DEFEAT_CAUSES := preload(
	"res://scripts/contracts/enemy_defeat_causes.gd"
)
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const ELEMENT_RESOLVER_SCRIPT := preload("res://scripts/data/element_resolver.gd")
const EFFECTS := preload("res://scripts/contracts/effects.gd")
const HERO_COMPOSITION_RESOLVER := preload(
	"res://scripts/data/hero_composition_resolver.gd"
)
const DAMAGE_NUMBER_SCENE := preload("res://scenes/gameplay/damage_number.tscn")
const GAME_MODES := preload("res://scripts/contracts/game_modes.gd")
const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")
const HAZARD_SCENE := preload("res://scenes/gameplay/hazard.tscn")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const BULLET_SCENE := preload("res://scenes/gameplay/bullet.tscn")
const GAME_OVER_PANEL_SCENE := preload("res://scenes/ui/game_over_panel.tscn")
const GOLD_TRANSACTION_REASONS := preload(
	"res://scripts/contracts/gold_transaction_reasons.gd"
)
const HIT_SPARK_SCENE := preload("res://scenes/gameplay/hit_spark.tscn")
const INTEREST_POINT_CACHE_SCENE := preload("res://scenes/gameplay/interest_point_cache.tscn")
const INTEREST_POINT_TARGET_SCENE := preload("res://scenes/gameplay/interest_point_target.tscn")
const REWARD_CHOICE_PANEL_SCENE := preload(
	"res://scenes/ui/reward_choice_panel.tscn"
)
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const GOLD_ORB_SCENE := preload("res://scenes/gameplay/gold_orb.tscn")
const ENERGY_ORB_SCENE := preload("res://scenes/gameplay/energy_orb.tscn")
const PROJECTILE_BARRIER_SCENE := preload(
	"res://scenes/gameplay/projectile_barrier.tscn"
)
const REWARD_CHOICE_TRIGGERS := preload(
	"res://scripts/contracts/reward_choice_triggers.gd"
)
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const SKILL_RESOURCES := preload("res://scripts/contracts/skill_resources.gd")
const SKILL_SLOTS := preload("res://scripts/contracts/skill_slots.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const VFX_CUES := preload("res://scripts/contracts/vfx_cues.gd")
const WARZONE_DIRECTOR_SCRIPT := preload("res://scripts/gameplay/warzone_director.gd")
const MODULE_PLACEMENT_TYPES := preload("res://scripts/contracts/module_placement_types.gd")
const MODULE_ROLES := preload("res://scripts/contracts/module_roles.gd")
const MODULE_CELL_TOKENS := preload("res://scripts/contracts/module_cell_tokens.gd")
const DAMAGE_TARGET_GROUPS := preload(
	"res://scripts/contracts/damage_target_groups.gd"
)
const WORLD_EVENT_KINDS := preload(
	"res://scripts/contracts/world_event_kinds.gd"
)
const WORLD_EVENT_IDS := preload(
	"res://scripts/contracts/world_event_ids.gd"
)
const WORLD_EVENT_REWARD_TYPES := preload(
	"res://scripts/contracts/world_event_reward_types.gd"
)
const WORLD_EVENT_STATES := preload(
	"res://scripts/contracts/world_event_states.gd"
)
const WORLD_EVENT_DEFENSE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_defense.tscn"
)
const WORLD_EVENT_SURVIVAL_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_survival.tscn"
)
const WORLD_EVENT_CAPTURE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_capture.tscn"
)
const WORLD_EVENT_GOLD_SHRINE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_gold_shrine.tscn"
)
const WORLD_EVENT_BLOOD_SHRINE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_blood_shrine.tscn"
)

const BULLET_POOL_SIZE: int = 192
const BULLET_POOL_PREWARM: int = 64
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 160.0)
const ENEMY_POOL_SIZE: int = 96
const FEEDBACK_POOL_SIZE: int = 128
const HAZARD_POOL_SIZE: int = 32
const PICKUP_POOL_SIZE: int = 128
const ENERGY_ORB_POOL_SIZE: int = 64
const PROJECTILE_BARRIER_POOL_SIZE: int = 4
const RUN_SNAPSHOT_SCHEMA_VERSION: int = 15
const ACTIVE_POOL_GROUPS: Array[String] = [
	"active_hazards",
	"active_enemies",
	"active_bullets",
	"active_gold_orbs",
	"active_energy_orbs",
	"active_deployables",
]
const UI_RESTORE_REWARD_CHOICE: String = "reward_choice"
const UI_RESTORE_PAUSED: String = "paused"
const UI_RESTORE_PLAYING: String = "playing"
const UI_RESTORE_UNDERLYING_STATE: String = "underlying_state"
const INPUT_PARTICIPANT_ID: String = "player_0"
const DEFAULT_DEBUG_REWARD_POOL: String = "default_reward_choice"
const LOADING_BATCH_SIZE: int = 8
const NAVIGATION_FLOW_OBSTACLE_BUFFER_CELLS: int = 2
const PRESENTATION_ENEMY_DEFAULT: String = "presentation_enemy_default"
const PRESENTATION_GAMEPLAY_DEFAULT: String = "presentation_gameplay_default"
const PRESENTATION_HAZARD_DEFAULT: String = "presentation_hazard_default"
const PRESENTATION_MODULE_ENCOUNTER: String = "presentation_module_encounter"
const PRESENTATION_PICKUP_DEFAULT: String = "presentation_pickup_default"
const PRESENTATION_PLAYER_DEFAULT: String = "presentation_player_default"
const PRESENTATION_SKILL_DEFAULT: String = "presentation_skill_default"
const PRESENTATION_SKILL_OVERDRIVE: String = "presentation_skill_overdrive"
const PRESENTATION_STATUS_DEFAULT: String = "presentation_status_default"
const DEBUG_TEST_ARENA_AI: String = "ai"
const DEBUG_TEST_ARENA_STATIONARY: String = "stationary"
const MODULE_ENCOUNTER_STATE_TELEGRAPHING: String = "telegraphing"
const MODULE_ENCOUNTER_STATE_SPAWNED: String = "spawned"
const WORLD_EVENT_TARGET_MODE_EVENT_PRIMARY: String = (
	"event_primary"
)

var _active_world: Node2D = null
var _actor_scene_cache: Dictionary = {}
var _camera_controller: Node2D = null
var _character_id: String = CHARACTER_IDS.CHARACTER_PRIMARY_A
var _difficulty_progression: DifficultyProgression = null
var _configured_difficulty_profile_id: String = ""
var _configured_content_availability: Dictionary = {}
var _content_availability: Dictionary = {}
var _content_progress_commits_enabled: bool = true
var _content_progress_delta: Dictionary = {}
var _enemy_rows: Dictionary = {}
var _enemy_reward_config: Dictionary = {}
var _energy_drop_config: Dictionary = {}
var _gold_drop_config: Dictionary = {}
var _gold_progression: GoldProgression = null
var _gameplay_feedback: GameplayFeedbackController = null
var _game_over_panel: CanvasLayer = null
var _hazard_rows: Dictionary = {}
var _hero_composition: Dictionary = {}
var _hud: CanvasLayer = null
var _interest_point_caches: Dictionary = {}
var _interest_points: Dictionary = {}
var _interest_point_targets: Dictionary = {}
var _kills: int = 0
var _main_hero_id: String = CHARACTER_IDS.CHARACTER_PRIMARY_A
var _reward_choice_panel: CanvasLayer = null
var _run_gear_mod_ranks: Dictionary = {}
var _pending_restore_snapshot: Dictionary = {}
var _pause_menu: CanvasLayer = null
var _player: CharacterBody2D = null
var _player_host: Node2D = null
var _map_layout: Dictionary = {}
var _map_manager: Node2D = null
var _module_world_definition: Dictionary = {}
var _module_world_enabled: bool = true
var _module_world_technical_slice: bool = false
var _module_world_manager: Node2D = null
var _module_encounter_vfx: Dictionary = {}
var _next_enemy_spawn_serial: int = 1
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
var _requested_main_hero_id: String = CHARACTER_IDS.CHARACTER_PRIMARY_A
var _requested_sub_hero_id: String = CHARACTER_IDS.CHARACTER_PRIMARY_B
var _reward_choice_controller: RewardChoiceController = null
var _registered_enemy_pool_ids: Array[String] = []
var _player_loading_mode: bool = false
var _run_activated: bool = false
var _run_prepared: bool = false
var _run_start_failed: bool = false
var _sub_hero_id: String = CHARACTER_IDS.CHARACTER_PRIMARY_B
var _pending_ui_restore: Dictionary = {}
var _world_event_controller: WorldEventController = null
var _world_event_host: Node2D = null
var _world_event_nodes: Dictionary = {}
var _world_event_module_coords: Dictionary = {}
var _world_event_wave_plans: Dictionary = {}


func _ready() -> void:
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)
	_start_run(_pending_restore_snapshot)


func _exit_tree() -> void:
	if InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.disconnect(_on_input_action_pressed)
	_clear_interest_point_caches()
	_clear_world_events()
	_release_active_world_pool_entities()
	if _vfx_host != null:
		_vfx_host.cancel_all()
	if Combat.damage_applied.is_connected(_on_combat_damage_applied):
		Combat.damage_applied.disconnect(_on_combat_damage_applied)


func _process(delta: float) -> void:
	_update_stats_panel()
	_update_combat_hud()
	_refresh_difficulty_hud()
	if not GameState.is_state(GameState.PLAYING):
		return
	if _is_debug_test_arena():
		return
	if _module_world_enabled:
		_update_module_world(delta)
	else:
		_advance_difficulty(delta)
	if _world_event_controller != null:
		_world_event_controller.tick(
			delta,
			_player,
			_world_event_context()
		)
		_update_world_event_background_pins()
	_update_interest_points()
	_update_combined_interaction_prompt()
	_refresh_world_event_hud()
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
			_try_interact_nearest()
			return
		if action_id == StringName(ACTIONS.PAUSE):
			_show_pause_menu()
			return
	if GameState.is_state(GameState.GAME_OVER) and action_id == StringName(ACTIONS.PAUSE):
		restart_requested.emit()


func configure_restore_snapshot(snapshot_data: Dictionary) -> void:
	_pending_restore_snapshot = snapshot_data.duplicate(true)
	var saved_difficulty: Dictionary = _dictionary_or_empty(
		snapshot_data.get("difficulty", {})
	)
	var saved_profile_id: String = String(
		saved_difficulty.get("profile_id", "")
	).strip_edges()
	if not saved_profile_id.is_empty():
		_configured_difficulty_profile_id = saved_profile_id


## Must be called before the run loop enters the scene tree. Replay playback uses
## the recording's frozen pool snapshot instead of the local Meta state.
func configure_content_availability(snapshot_data: Dictionary) -> void:
	if is_inside_tree():
		push_error(
			"[GameplayRunLoop] content availability must be configured before entering tree"
		)
		return
	_configured_content_availability = snapshot_data.duplicate(true)


## Test and replay harnesses disable permanent progression writes through this
## pre-tree switch. Debug test arenas are isolated regardless of this value.
func configure_content_progress_commits_enabled(enabled: bool) -> void:
	if is_inside_tree():
		push_error(
			"[GameplayRunLoop] progression commits must be configured before entering tree"
		)
		return
	_content_progress_commits_enabled = enabled


## Must be called before the run loop enters the scene tree. Empty selects the
## current mode's default profile.
func configure_difficulty_profile_id(profile_id: String) -> void:
	if is_inside_tree():
		push_error(
			"[GameplayRunLoop] difficulty profile must be configured before entering tree"
		)
		return
	_configured_difficulty_profile_id = profile_id.strip_edges()


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
	_requested_main_hero_id = character_id
	if _requested_sub_hero_id == character_id:
		for candidate_id: String in CHARACTER_IDS.VALUES:
			if candidate_id != character_id:
				_requested_sub_hero_id = candidate_id
				break


## Must be called before the run loop enters the scene tree.
func configure_hero_composition(
	main_hero_id: String,
	sub_hero_id: String
) -> void:
	if is_inside_tree():
		push_error(
			"[GameplayRunLoop] hero composition must be configured before entering tree"
		)
		return
	_requested_main_hero_id = main_hero_id
	_requested_sub_hero_id = sub_hero_id


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
		"main_hero_id": _main_hero_id,
		"sub_hero_id": _sub_hero_id,
		"run_purpose": (
			"debug_test_arena"
			if _is_debug_test_arena()
			else "standard"
		),
	})
	if not _is_debug_test_arena() and Replay.is_enabled():
		if Replay.is_recording():
			Replay.stop_recording("replaced_by_new_run")
		Replay.clear_recording()
		var replay_context: Dictionary = {
			"mode": GAME_MODES.MODE_STANDARD_SURVIVAL,
			"main_hero_id": _main_hero_id,
			"sub_hero_id": _sub_hero_id,
			"difficulty_profile_id": String(
				_difficulty_snapshot().get("profile_id", "")
			),
			"difficulty_coefficient": float(
				_difficulty_snapshot().get(
					"difficulty_coefficient",
					1.0
				)
			),
			"content_availability": _content_availability.duplicate(true),
		}
		if Replay.start_recording(replay_context):
			Replay.record_decision(
				ANALYTICS_EVENTS.RUN_START,
				replay_context
			)
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


func debug_request_reward_choice(
	candidate_count: int = 3,
	pool_id: String = DEFAULT_DEBUG_REWARD_POOL
) -> Dictionary:
	return request_reward_choice(
		pool_id,
		REWARD_CHOICE_TRIGGERS.DEBUG_COMMAND,
		candidate_count
	)


func create_run_snapshot() -> Dictionary:
	if _is_debug_test_arena():
		return {}
	return {
		"schema_version": RUN_SNAPSHOT_SCHEMA_VERSION,
		"mode": GAME_MODES.MODE_STANDARD_SURVIVAL,
		"character": _character_id,
		"hero_composition": {
			"main_hero_id": _main_hero_id,
			"sub_hero_id": _sub_hero_id,
		},
		"gold_progression": (
			_gold_progression.snapshot()
			if _gold_progression != null
			else {}
		),
		"kills": _kills,
		"next_enemy_spawn_serial": _next_enemy_spawn_serial,
		"game_clock": GameClock.snapshot(),
		"difficulty": (
			_difficulty_progression.snapshot()
			if _difficulty_progression != null
			else {}
		),
		"rng": RNG.snapshot(),
		"map": _map_manager.call("snapshot") if _map_manager != null and _map_manager.has_method("snapshot") else {},
		"interest_points": _interest_points_snapshot(),
		"gear_mods": _run_gear_mod_snapshot(),
		"content_availability": _content_availability.duplicate(true),
		"content_progress_delta": _content_progress_delta.duplicate(true),
		"spawn_states": _spawn_states.duplicate(true),
		"player": _player.call("snapshot") if _player != null and _player.has_method("snapshot") else {},
		"weapon": _weapon_system.call("snapshot") if _weapon_system != null and _weapon_system.has_method("snapshot") else {},
		"skills": _skill_system.call("snapshot") if _skill_system != null and _skill_system.has_method("snapshot") else {},
		"hazards": _entity_snapshots("active_hazards"),
		"enemies": _entity_snapshots("active_enemies"),
		"bullets": _entity_snapshots("active_bullets"),
		"gold_orbs": _entity_snapshots("active_gold_orbs"),
		"energy_orbs": _entity_snapshots("active_energy_orbs"),
		"module_world": _module_world_snapshot(),
		"world_events": _world_events_snapshot(),
		"reward_choice": (
			_reward_choice_controller.snapshot()
			if _reward_choice_controller != null
			else {}
		),
		"ui_restore": _ui_restore_snapshot(),
	}


func _start_run(restore_snapshot: Dictionary = {}) -> void:
	GameClock.reset()
	_content_progress_delta = _empty_content_progress_delta()
	if not _initialize_content_availability(restore_snapshot):
		_fail_run_start(
			"content availability snapshot is missing or invalid",
			not restore_snapshot.is_empty()
		)
		return
	if not restore_snapshot.is_empty():
		_content_progress_delta = _normalize_content_progress_delta(
			_dictionary_or_empty(
				restore_snapshot.get("content_progress_delta", {})
			)
		)
	_next_enemy_spawn_serial = 1
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
	PoolManager.clear_pool(POOL_IDS.GOLD_ORB)
	PoolManager.clear_pool(POOL_IDS.ENERGY_ORB)
	PoolManager.clear_pool(POOL_IDS.PROJECTILE_BARRIER)
	var configured_main_hero_id: String = String(
		_debug_test_arena_config.get(
			"main_hero_id",
			_debug_test_arena_config.get(
				"character_id",
				_requested_main_hero_id
			)
		)
	)
	var configured_sub_hero_id: String = String(
		_debug_test_arena_config.get(
			"sub_hero_id",
			_requested_sub_hero_id
		)
	)
	var saved_composition: Dictionary = _dictionary_or_empty(
		restore_snapshot.get("hero_composition", {})
	)
	var selected_main_hero_id: String = String(
		saved_composition.get(
			"main_hero_id",
			configured_main_hero_id
			if _is_debug_test_arena()
			else _requested_main_hero_id
		)
	).strip_edges()
	var selected_sub_hero_id: String = String(
		saved_composition.get(
			"sub_hero_id",
			configured_sub_hero_id
			if _is_debug_test_arena()
			else _requested_sub_hero_id
		)
	).strip_edges()
	if (
		not _is_content_available(
			CONTENT_UNLOCK_TYPES.CHARACTER,
			selected_main_hero_id
		)
		or not _is_content_available(
			CONTENT_UNLOCK_TYPES.CHARACTER,
			selected_sub_hero_id
		)
	):
		_fail_run_start(
			"hero composition contains locked content",
			not restore_snapshot.is_empty()
		)
		return
	var characters_payload: Variant = DataLoader.load_json(
		DataLoader.CHARACTERS_PATH
	)
	var element_resolver: ElementResolver = ELEMENT_RESOLVER_SCRIPT.new()
	if not element_resolver.load_default():
		_fail_run_start(
			"element resolver configuration failed",
			not restore_snapshot.is_empty()
		)
		return
	_hero_composition = HERO_COMPOSITION_RESOLVER.resolve(
		characters_payload,
		selected_main_hero_id,
		selected_sub_hero_id,
		element_resolver
	)
	if _hero_composition.is_empty():
		_fail_run_start(
			"invalid hero composition: %s + %s" % [
				selected_main_hero_id,
				selected_sub_hero_id,
			],
			not restore_snapshot.is_empty()
		)
		return
	_main_hero_id = selected_main_hero_id
	_sub_hero_id = selected_sub_hero_id
	_character_id = _main_hero_id
	var character: Dictionary = _dictionary_or_empty(
		_hero_composition.get("main_character", {})
	)
	if character.is_empty():
		character = _find_item(
			_load_array(DataLoader.CHARACTERS_PATH, "characters"),
			_main_hero_id
		)
	if character.is_empty():
		_fail_run_start(
			"unknown main hero id: %s" % _main_hero_id,
			not restore_snapshot.is_empty()
		)
		return
	_enemy_rows = _load_enemy_rows(_load_enemy_ai_profiles(), enemy_csv_rows)
	_enemy_reward_config = _dictionary_or_empty(
		DataLoader.load_json(DataLoader.ENEMY_REWARDS_PATH)
	)
	if _enemy_reward_config.is_empty():
		_fail_run_start(
			"enemy reward configuration failed",
			not restore_snapshot.is_empty()
		)
		return
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
	PoolManager.register_pool(
		POOL_IDS.GOLD_ORB,
		_create_gold_orb_node,
		PICKUP_POOL_SIZE
	)
	PoolManager.register_pool(
		POOL_IDS.ENERGY_ORB,
		_create_energy_orb_node,
		ENERGY_ORB_POOL_SIZE
	)
	PoolManager.register_pool(
		POOL_IDS.PROJECTILE_BARRIER,
		_create_projectile_barrier_node,
		PROJECTILE_BARRIER_POOL_SIZE
	)
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
	if not _configure_difficulty_progression(mode):
		_fail_run_start(
			"difficulty progression configuration failed",
			not restore_snapshot.is_empty()
		)
		return
	var player_stats: Dictionary = _merged_player_stats(character, mode)
	var player_runtime_data: Dictionary = _dictionary_or_empty(
		DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	)
	_gold_progression = get_node_or_null(
		"GoldProgression"
	) as GoldProgression
	_reward_choice_controller = get_node_or_null(
		"RewardChoiceController"
	) as RewardChoiceController
	if _gold_progression == null or _reward_choice_controller == null:
		_fail_run_start(
			"missing scene-authored progression controllers",
			not restore_snapshot.is_empty()
		)
		return
	var progression_data: Dictionary = _dictionary_or_empty(
		DataLoader.load_json(DataLoader.LEVEL_PROGRESSION_PATH)
	)
	var reward_choice_data: Dictionary = _dictionary_or_empty(
		DataLoader.load_json(DataLoader.REWARD_CHOICE_POOLS_PATH)
	)
	if not _gold_progression.configure(progression_data):
		_fail_run_start(
			"gold progression configuration failed",
			not restore_snapshot.is_empty()
		)
		return
	if not _reward_choice_controller.configure(reward_choice_data):
		_fail_run_start(
			"reward choice configuration failed",
			not restore_snapshot.is_empty()
		)
		return
	_gold_drop_config = _dictionary_or_empty(
		player_runtime_data.get("gold_drop", {})
	)
	_energy_drop_config = _dictionary_or_empty(
		player_runtime_data.get("energy_drop", {})
	)
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
		var debug_primary_skill_id: String = String(
			_debug_test_arena_config.get("primary_skill_id", "")
		)
		if not debug_primary_skill_id.is_empty():
			var debug_skill_slots: Dictionary = _dictionary_or_empty(
				_hero_composition.get("skill_slots", {})
			)
			debug_skill_slots[SKILL_SLOTS.SKILL_1] = debug_primary_skill_id
			_hero_composition["skill_slots"] = debug_skill_slots
	var weapons_payload: Dictionary = _dictionary_or_empty(
		DataLoader.load_json(DataLoader.WEAPONS_PATH)
	)
	var recoil_model: Dictionary = _dictionary_or_empty(
		weapons_payload.get("recoil_model", {})
	)
	var weapon: Dictionary = _find_item(
		_array_or_empty(weapons_payload.get("weapons", [])),
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
		_waves.clear()
	else:
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
	_gold_progression.reset()
	_reward_choice_controller.clear()
	_kills = 0
	_run_gear_mod_ranks.clear()
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
	if _player.has_method("configure_runtime_rules"):
		_player.call("configure_runtime_rules", player_runtime_data)
	if _player.has_method("configure_weapon_recoil"):
		_player.call("configure_weapon_recoil", recoil_model)
	if _player.has_method("configure_element_damage_taken_multipliers"):
		_player.call(
			"configure_element_damage_taken_multipliers",
			_element_damage_taken_multipliers(
				String(_hero_composition.get("passive_id", ""))
			)
		)
	var composition_visual: Node = _player.get_node_or_null("Visual")
	if composition_visual != null and composition_visual.has_method("configure_palette"):
		composition_visual.call(
			"configure_palette",
			_dictionary_or_empty(_hero_composition.get("palette", {}))
		)
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
	_weapon_system.call(
		"configure",
		_player,
		_active_world,
		weapon,
		recoil_model
	)
	if _weapon_system.has_method("configure_combat_gate"):
		_weapon_system.call(
			"configure_combat_gate",
			Callable(self, "_is_combat_allowed")
		)
	_connect_weapon_feedback()
	_configure_skill_system(character)
	_apply_initial_gear_modifiers()

	_hud = get_node_or_null("GameplayHud") as CanvasLayer
	if _hud == null:
		push_error("[GameplayRunLoop] missing GameplayHud scene node")
		return
	_hud.call("set_life", _player.call("current_life"), _player.call("max_life"))
	_hud.call(
		"set_composition",
		_composition_display_name(),
		_composition_color("main_primary", Color("68bcdd")),
		_composition_color("sub_primary", Color("ed2f72"))
	)
	_hud.call("set_kills", _kills)
	_hud.call("set_level", current_level())
	_update_combat_hud()
	_refresh_difficulty_hud()
	_refresh_gold_hud()
	if (
		_module_world_enabled
		and not _is_debug_test_arena()
		and not _configure_world_event_controller()
	):
		_fail_run_start(
			"world event controller configuration failed",
			not restore_snapshot.is_empty()
		)
		return
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
		if not _is_content_available(
			CONTENT_UNLOCK_TYPES.ENEMY,
			String(enemy_data.get("id", ""))
		):
			continue
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
		if not _is_content_available(
			CONTENT_UNLOCK_TYPES.ENEMY,
			String(enemy_data.get("id", ""))
		):
			continue
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
	PoolManager.prewarm(POOL_IDS.BULLET_BASIC, BULLET_POOL_PREWARM)
	PoolManager.prewarm(POOL_IDS.HAZARD_SPIKE, 8)
	PoolManager.prewarm(POOL_IDS.GOLD_ORB, 16)
	PoolManager.prewarm(POOL_IDS.ENERGY_ORB, 8)
	PoolManager.prewarm(POOL_IDS.PROJECTILE_BARRIER, 2)
	for request: Dictionary in _vfx_host.declared_pool_requests():
		PoolManager.prewarm(
			String(request.get("pool_id", "")),
			int(request.get("count", 0))
		)


func _prewarm_standard_pools_staged() -> bool:
	var requests: Array[Dictionary] = [
		{
			"pool_id": POOL_IDS.BULLET_BASIC,
			"count": BULLET_POOL_PREWARM,
		},
		{"pool_id": POOL_IDS.HAZARD_SPIKE, "count": 8},
		{"pool_id": POOL_IDS.GOLD_ORB, "count": 16},
		{"pool_id": POOL_IDS.ENERGY_ORB, "count": 8},
		{"pool_id": POOL_IDS.PROJECTILE_BARRIER, "count": 2},
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


func _create_gold_orb_node() -> Node:
	return GOLD_ORB_SCENE.instantiate()


func _create_energy_orb_node() -> Node:
	return ENERGY_ORB_SCENE.instantiate()


func _create_projectile_barrier_node() -> Node:
	return PROJECTILE_BARRIER_SCENE.instantiate()


func _configure_skill_system(
	character: Dictionary
) -> void:
	_skill_system = get_node_or_null("SkillSystem")
	if _skill_system == null:
		push_error("[GameplayRunLoop] missing scene-authored SkillSystem")
		return
	var skill_resources: Array[Dictionary] = _typed_dictionary_array(
		_hero_composition.get(
			"skill_resources",
			character.get("skill_resources", [])
		)
	)
	_skill_system.call(
		"configure",
		_player,
		_active_world,
		_load_composition_skill_definitions(),
		skill_resources
	)
	if _skill_system.has_method("configure_combat_gate"):
		_skill_system.call(
			"configure_combat_gate",
			Callable(self, "_is_combat_allowed")
		)
	var cast_callback: Callable = Callable(self, "_on_skill_cast")
	if not _skill_system.is_connected("skill_cast", cast_callback):
		_skill_system.connect("skill_cast", cast_callback)
	var failed_callback: Callable = Callable(self, "_on_skill_failed")
	if not _skill_system.is_connected("skill_failed", failed_callback):
		_skill_system.connect("skill_failed", failed_callback)
	_connect_status_feedback(_skill_system)


func _configure_difficulty_progression(mode: Dictionary) -> bool:
	var profile_id: String = String(
		_configured_difficulty_profile_id
		if not _configured_difficulty_profile_id.is_empty()
		else mode.get("difficulty_profile_id", "")
	).strip_edges()
	var profile: Dictionary = _find_item(
		_load_array(DataLoader.DIFFICULTY_PROFILES_PATH, "profiles"),
		profile_id
	)
	_difficulty_progression = DIFFICULTY_PROGRESSION_SCRIPT.new()
	return _difficulty_progression.configure(
		profile,
		not _is_debug_test_arena()
	)


func _advance_difficulty(delta: float) -> void:
	if (
		_difficulty_progression == null
		or _is_debug_test_arena()
		or not _is_combat_allowed()
	):
		return
	_difficulty_progression.advance(GameClock.delta_scaled(delta))
	_refresh_difficulty_hud()


func _difficulty_snapshot() -> Dictionary:
	if _difficulty_progression == null:
		return {
			"enabled": false,
			"profile_id": "",
			"profile_name_key": "",
			"elapsed": 0.0,
			"tier": 0,
			"progress": 0.0,
			"coefficient": 1.0,
			"difficulty_coefficient": 1.0,
			"health_multiplier": 1.0,
			"damage_multiplier": 1.0,
			"difficulty_level": 1,
			"name_key": "",
		}
	return _difficulty_progression.current_snapshot()


func _difficulty_elapsed() -> float:
	return float(_difficulty_snapshot().get("elapsed", 0.0))


func _enemy_spawn_difficulty() -> Dictionary:
	if _difficulty_progression == null:
		return {
			"health_multiplier": 1.0,
			"damage_multiplier": 1.0,
		}
	return _difficulty_progression.enemy_spawn_snapshot()


func _resolve_enemy_reward_snapshot(
	enemy_data: Dictionary,
	spawn_context: Dictionary
) -> Dictionary:
	var random_minimum: float = float(
		_enemy_reward_config.get("random_multiplier_min", 0.0)
	)
	var random_maximum: float = float(
		_enemy_reward_config.get("random_multiplier_max", 0.0)
	)
	var random_multiplier: float = RNG.economy.randf_range(
		random_minimum,
		random_maximum
	)
	var difficulty: Dictionary = _difficulty_snapshot()
	var resolved: Dictionary = ENEMY_REWARD_RESOLVER_SCRIPT.resolve(
		_enemy_reward_config,
		float(difficulty.get("difficulty_coefficient", 1.0)),
		float(enemy_data.get("gold_value_multiplier", 0.0)),
		float(
			spawn_context.get(
				"reward_specialization_multiplier",
				1.0
			)
		),
		int(difficulty.get("tier", 0)),
		random_multiplier
	)
	if not bool(resolved.get("valid", false)):
		push_error(
			"[GameplayRunLoop] invalid enemy reward inputs for %s"
			% String(enemy_data.get("id", ""))
		)
		return {}
	return resolved


func _is_combat_allowed() -> bool:
	return not _is_combat_locked()


func _is_combat_locked() -> bool:
	if _is_debug_test_arena() or not _module_world_enabled:
		return false
	if _module_world_manager == null or _player == null:
		return true
	var global_cell: Vector2i = _module_world_manager.call(
		"world_to_global_cell",
		_player.global_position
	) as Vector2i
	var module_and_local: Dictionary = _module_world_manager.call(
		"global_cell_to_module_and_local",
		global_cell
	) as Dictionary
	var current_coord: Vector2i = module_and_local.get(
		"module_coord",
		Vector2i(-1, -1)
	) as Vector2i
	var start_coord: Vector2i = _module_world_manager.call(
		"role_module_coord",
		MODULE_ROLES.MODULE_ROLE_START
	) as Vector2i
	return current_coord == start_coord


func _refresh_difficulty_hud() -> void:
	if (
		_hud == null
		or not is_instance_valid(_hud)
		or not _hud.has_method("set_difficulty_snapshot")
	):
		return
	_hud.call(
		"set_difficulty_snapshot",
		_difficulty_snapshot(),
		_is_combat_locked()
	)


func current_level() -> int:
	return (
		_gold_progression.current_level()
		if _gold_progression != null
		else 1
	)


func add_gold(amount: int, reason_id: String) -> Dictionary:
	if _gold_progression == null:
		return _gold_failure("progression_unavailable", amount)
	var result: Dictionary = _gold_progression.add_gold(
		amount,
		reason_id
	)
	if not bool(result.get("ok", false)):
		return result
	_refresh_gold_hud()
	var levels_gained: int = int(result.get("levels_gained", 0))
	if levels_gained > 0:
		if _hud != null:
			_hud.call(
				"set_level",
				int(result.get("new_level", current_level()))
			)
			if _hud.has_method("show_level_advanced_feedback"):
				_hud.call(
					"show_level_advanced_feedback",
					int(result.get("new_level", current_level()))
				)
		Analytics.track_event(ANALYTICS_EVENTS.LEVEL_UP, {
			"old_level": int(result.get("old_level", 1)),
			"new_level": int(result.get("new_level", 1)),
			"levels_gained": levels_gained,
			"gold_earned_total": gold_earned_total(),
		})
	return result


func gold_balance() -> int:
	return (
		_gold_progression.gold_balance()
		if _gold_progression != null
		else 0
	)


func gold_earned_total() -> int:
	return (
		_gold_progression.gold_earned_total()
		if _gold_progression != null
		else 0
	)


func current_level_gold() -> int:
	return (
		_gold_progression.current_level_gold()
		if _gold_progression != null
		else 0
	)


func current_level_gold_required() -> int:
	return (
		_gold_progression.current_level_gold_required()
		if _gold_progression != null
		else 0
	)


func can_afford_gold(amount: int) -> bool:
	return (
		_gold_progression != null
		and _gold_progression.can_afford(amount)
	)


func try_spend_gold(amount: int, reason_id: String) -> Dictionary:
	if _gold_progression == null:
		return _gold_failure("progression_unavailable", amount)
	var result: Dictionary = _gold_progression.try_spend_gold(
		amount,
		reason_id
	)
	if bool(result.get("ok", false)):
		_refresh_gold_hud()
	return result


func request_reward_choice(
	pool_id: String,
	trigger_id: String,
	candidate_count: int
) -> Dictionary:
	if _reward_choice_controller == null:
		return {
			"ok": false,
			"reason": "controller_unavailable",
		}
	if _reward_choice_controller.is_busy():
		return {
			"ok": false,
			"reason": "busy",
		}
	if not GameState.is_state(GameState.PLAYING):
		return {
			"ok": false,
			"reason": "invalid_state",
		}
	var result: Dictionary = _reward_choice_controller.request_choice(
		pool_id,
		trigger_id,
		candidate_count,
		current_level()
	)
	if not bool(result.get("ok", false)):
		return result
	_show_reward_choice_panel(
		_typed_choice_array(result.get("choices", []))
	)
	if _reward_choice_panel == null:
		_reward_choice_controller.clear()
		return {
			"ok": false,
			"reason": "ui_unavailable",
		}
	return result


func debug_summary() -> Dictionary:
	return {
		"level": current_level(),
		"gold_balance": gold_balance(),
		"gold_earned_total": gold_earned_total(),
		"level_gold": current_level_gold(),
		"level_gold_required": current_level_gold_required(),
		"reward_choice_active": (
			_reward_choice_controller.is_busy()
			if _reward_choice_controller != null
			else false
		),
		"kills": _kills,
		"hero_composition": {
			"main_hero_id": _main_hero_id,
			"sub_hero_id": _sub_hero_id,
			"name": _composition_display_name(),
			"palette": _dictionary_or_empty(
				_hero_composition.get("palette", {})
			),
			"passive_id": String(
				_hero_composition.get("passive_id", "")
			),
		},
		"player_life": float(_player.call("current_life")) if _player != null and _player.has_method("current_life") else 0.0,
		"player_max_life": float(_player.call("max_life")) if _player != null and _player.has_method("max_life") else 0.0,
		"player_shield": float(_player.call("current_shield")) if _player != null and _player.has_method("current_shield") else 0.0,
		"player_max_shield": float(_player.call("max_shield")) if _player != null and _player.has_method("max_shield") else 0.0,
		"player_overshield": float(_player.call("current_overshield")) if _player != null and _player.has_method("current_overshield") else 0.0,
		"active_enemies": _active_enemy_count(),
		"active_hazards": PoolManager.active_count(POOL_IDS.HAZARD_SPIKE),
		"interest_points": _interest_point_debug_summary(),
		"gear_mods": _run_gear_mod_snapshot(),
		"difficulty": _difficulty_snapshot(),
		"map": _map_manager.call("debug_summary") if _map_manager != null and _map_manager.has_method("debug_summary") else {},
		"module_world": _module_world_manager.call("debug_summary") if _module_world_manager != null and _module_world_manager.has_method("debug_summary") else {},
		"skills": _skill_system.call("debug_summary") if _skill_system != null and _skill_system.has_method("debug_summary") else {},
		"warzone_director": _warzone_director.debug_summary(_difficulty_elapsed()) if _warzone_director != null else {},
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


func debug_give_gold(amount: int) -> Dictionary:
	return add_gold(amount, GOLD_TRANSACTION_REASONS.DEBUG_COMMAND)


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
	if _player.has_method("debug_set_shield"):
		_player.call("debug_set_shield", 0.0, 0.0)
	if _player.has_method("debug_clear_invulnerability"):
		_player.call("debug_clear_invulnerability")
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


func debug_world_event_summary() -> Dictionary:
	if _world_event_controller == null:
		return {}
	var summary: Dictionary = (
		_world_event_controller.debug_summary()
	)
	summary["registered_node_count"] = (
		_world_event_nodes.size()
	)
	summary["wave_plan_count"] = (
		_world_event_wave_plans.size()
	)
	return summary


func debug_interact_world_event(
	instance_id: String
) -> Dictionary:
	if _world_event_controller == null:
		return {
			"accepted": false,
			"reason": "controller_unavailable",
		}
	return _world_event_controller.interact(
		instance_id,
		_player,
		_world_event_context()
	)


func debug_module_world_tick() -> Dictionary:
	if _module_world_manager == null or _player == null:
		return {}
	return _module_world_manager.call("tick", _player.global_position) as Dictionary


func debug_difficulty_snapshot() -> Dictionary:
	return _difficulty_snapshot()


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
	_assign_enemy_spawn_serial(enemy)
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


func debug_test_arena_request_exit() -> void:
	if _is_debug_test_arena():
		debug_test_arena_exit_requested.emit()


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
		"player_shield": (
			float(_player.call("current_shield"))
			if _player != null
			else 0.0
		),
		"player_overshield": (
			float(_player.call("current_overshield"))
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


func _update_spawner() -> void:
	var elapsed: float = _difficulty_elapsed()
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
	if not _is_content_available(CONTENT_UNLOCK_TYPES.ENEMY, requested_id):
		return false
	if not _enemy_rows.has(requested_id):
		return false
	var enemy_data: Dictionary = _enemy_rows[requested_id]
	var pool_id: String = String(enemy_data.get("pool_id", ""))
	var raw_node: Node = PoolManager.acquire(pool_id)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return false

	var enemy: Node2D = raw_node as Node2D
	var spawn_context: Dictionary = {}
	if not _is_debug_test_arena():
		var reward_snapshot: Dictionary = _resolve_enemy_reward_snapshot(
			enemy_data,
			spawn_context
		)
		if reward_snapshot.is_empty():
			PoolManager.release(enemy)
			return false
		spawn_context["reward_snapshot"] = reward_snapshot
	enemy.global_position = _spawn_position()
	_reparent_to_active_world(enemy)
	enemy.set_meta("wave_key", wave_key)
	if enemy.has_meta("module_slot"):
		enemy.remove_meta("module_slot")
	enemy.call(
		"configure",
		enemy_data,
		_player,
		_enemy_navigation_provider(),
		_enemy_spawn_difficulty(),
		spawn_context
	)
	_assign_enemy_spawn_serial(enemy)
	_apply_enemy_movement_bounds(enemy)
	_connect_enemy_defeated(enemy, wave_key)
	return true


func _spawn_map_hazards(placements: Array[Dictionary]) -> void:
	for placement: Dictionary in placements:
		_spawn_hazard(placement)


func _configure_world_event_controller() -> bool:
	_clear_world_events()
	_world_event_host = (
		_active_world.get_node_or_null("WorldEventHost") as Node2D
	)
	_world_event_controller = (
		get_node_or_null("WorldEventController")
		as WorldEventController
	)
	if _world_event_host == null or _world_event_controller == null:
		return false
	_world_event_controller.configure(
		_dictionary_or_empty(
			DataLoader.load_json(DataLoader.WORLD_EVENTS_PATH)
		)
	)
	_world_event_controller.wave_requested.connect(
		_on_world_event_wave_requested
	)
	_world_event_controller.reward_requested.connect(
		_on_world_event_reward_requested
	)
	_world_event_controller.prompt_requested.connect(
		_on_world_event_prompt_requested
	)
	_world_event_controller.state_changed.connect(
		_on_world_event_state_changed
	)
	_world_event_controller.module_pin_requested.connect(
		_on_world_event_module_pin_requested
	)
	_world_event_controller.terminal_cleanup_requested.connect(
		_on_world_event_terminal_cleanup_requested
	)
	for event_id: String in WORLD_EVENT_IDS.VALUES:
		if _world_event_controller.definition(event_id).is_empty():
			return false
	return true


func _clear_world_events() -> void:
	_world_event_nodes.clear()
	_world_event_module_coords.clear()
	_world_event_wave_plans.clear()
	if _world_event_host != null and is_instance_valid(_world_event_host):
		for child: Node in _world_event_host.get_children():
			child.queue_free()
	_world_event_controller = null
	_world_event_host = null


func _register_all_module_world_events() -> void:
	if (
		_module_world_manager == null
		or _world_event_controller == null
		or _world_event_host == null
		or not _world_event_nodes.is_empty()
	):
		return
	for row_index: int in range(9):
		for column_index: int in range(9):
			var module_coord := Vector2i(
				column_index,
				row_index
			)
			var placements: Array[Dictionary] = (
				_module_world_manager.call(
					"placements_at",
					module_coord
				)
			)
			for placement: Dictionary in placements:
				if (
					String(placement.get("type", ""))
					!= MODULE_PLACEMENT_TYPES
					.MODULE_PLACE_WORLD_EVENT
				):
					continue
				_register_module_world_event(
					module_coord,
					placement
				)


func _register_module_world_event(
	module_coord: Vector2i,
	placement: Dictionary
) -> void:
	var event_id: String = String(
		placement.get("world_event_id", "")
	)
	var scene: PackedScene = _world_event_scene(event_id)
	if scene == null:
		push_error(
			"[GameplayRunLoop] missing world-event scene: %s"
			% event_id
		)
		return
	var instance_id: String = "world_event_%d_%d_%s" % [
		module_coord.x,
		module_coord.y,
		event_id,
	]
	var raw_node: Node = scene.instantiate()
	if not raw_node is WorldEventInteractable:
		raw_node.queue_free()
		push_error(
			"[GameplayRunLoop] world-event scene root is invalid: %s"
			% event_id
		)
		return
	var interactable: WorldEventInteractable = (
		raw_node as WorldEventInteractable
	)
	_world_event_host.add_child(interactable)
	interactable.global_position = _dict_to_vector(
		placement.get("world_position", {}),
		Vector2.ZERO
	)
	var slot_key: String = _module_slot_key(module_coord)
	if not _world_event_controller.register_instance(
		instance_id,
		event_id,
		interactable,
		slot_key,
		interactable.defense_target()
	):
		interactable.queue_free()
		return
	_world_event_nodes[instance_id] = interactable
	_world_event_module_coords[instance_id] = module_coord


func _world_event_scene(event_id: String) -> PackedScene:
	match event_id:
		WORLD_EVENT_IDS.WORLD_EVENT_DEFENSE:
			return WORLD_EVENT_DEFENSE_SCENE
		WORLD_EVENT_IDS.WORLD_EVENT_SURVIVAL:
			return WORLD_EVENT_SURVIVAL_SCENE
		WORLD_EVENT_IDS.WORLD_EVENT_CAPTURE:
			return WORLD_EVENT_CAPTURE_SCENE
		WORLD_EVENT_IDS.WORLD_EVENT_GOLD_SHRINE:
			return WORLD_EVENT_GOLD_SHRINE_SCENE
		WORLD_EVENT_IDS.WORLD_EVENT_BLOOD_SHRINE:
			return WORLD_EVENT_BLOOD_SHRINE_SCENE
		_:
			return null


func _world_event_context() -> Dictionary:
	return {
		"try_spend_gold": Callable(
			self,
			"_world_event_try_spend_gold"
		),
		"roll_world_event_chance": Callable(
			self,
			"_roll_world_event_chance"
		),
		"choose_world_event_mod": Callable(
			self,
			"_choose_world_event_mod"
		),
		"try_sacrifice_combined_health": Callable(
			self,
			"_world_event_try_sacrifice"
		),
		"prepare_world_event_reward": Callable(
			self,
			"_prepare_world_event_reward"
		),
		"player_is_alive": Callable(
			self,
			"_world_event_player_is_alive"
		),
	}


func _world_event_try_spend_gold(
	_instance_id: String,
	amount: int
) -> bool:
	return bool(
		try_spend_gold(
			amount,
			GOLD_TRANSACTION_REASONS.EVENT_COST
		).get("ok", false)
	)


func _roll_world_event_chance(
	_instance_id: String,
	chance: float
) -> bool:
	return (
		RNG.world_event.randf()
		< clampf(chance, 0.0, 1.0)
	)


func _choose_world_event_mod(
	_instance_id: String,
	pool_id: String,
	excluded: Array[String]
) -> String:
	var candidates: Array[String] = []
	for mod_id: String in GearModSystem.reward_pool_ids(
		pool_id,
		_available_content_ids(CONTENT_UNLOCK_TYPES.GEAR_MOD)
	):
		if not excluded.has(mod_id):
			candidates.append(mod_id)
	if candidates.is_empty():
		return ""
	return candidates[
		int(RNG.world_event.randi() % candidates.size())
	]


func _world_event_try_sacrifice(
	_instance_id: String,
	ratio: float
) -> Dictionary:
	if (
		_player == null
		or not _player.has_method(
			"try_sacrifice_combined_health"
		)
	):
		return {
			"accepted": false,
			"reason": "player_unavailable",
		}
	var sacrifice_amount: float = (
		float(_player.call("max_life"))
		+ float(_player.call("max_shield"))
	) * clampf(ratio, 0.0, 1.0)
	var result: Dictionary = _player.call(
		"try_sacrifice_combined_health",
		sacrifice_amount,
		1.0
	) as Dictionary
	return {
		"accepted": bool(result.get("ok", false)),
		"reason": String(
			result.get(
				"reason",
				"insufficient_combined_health"
			)
		),
		"actual_spent": float(result.get("spent", 0.0)),
	}


func _world_event_player_is_alive(_target: Node = null) -> bool:
	return (
		_player != null
		and _player.has_method("is_alive")
		and bool(_player.call("is_alive"))
	)


func _prepare_world_event_reward(
	instance_id: String,
	event_id: String,
	reward_config: Dictionary
) -> Dictionary:
	if not _world_event_wave_plans.has(instance_id):
		_world_event_wave_plans[instance_id] = (
			_build_world_event_wave_plan(
				instance_id,
				event_id
			)
		)
	var pool_id: String = String(
		reward_config.get("mod_pool_id", "")
	)
	var mod_id: String = _choose_world_event_mod(
		instance_id,
		pool_id,
		[]
	)
	if mod_id.is_empty():
		return {}
	return {
		"kind": (
			WORLD_EVENT_REWARD_TYPES
			.WORLD_EVENT_REWARD_GEAR_MOD
		),
		"mod_id": mod_id,
		"pending": false,
	}


func _build_world_event_wave_plan(
	instance_id: String,
	event_id: String
) -> Dictionary:
	if (
		_world_event_controller == null
		or not _world_event_module_coords.has(instance_id)
	):
		return {}
	var definition: Dictionary = (
		_world_event_controller.definition(event_id)
	)
	var module_coord: Vector2i = (
		_world_event_module_coords[instance_id] as Vector2i
	)
	var event_node: Node2D = (
		_world_event_nodes.get(instance_id) as Node2D
	)
	if event_node == null:
		return {}
	var all_positions: Array[Vector2] = []
	var raw_positions: Variant = _module_world_manager.call(
		"empty_floor_positions_at",
		module_coord
	)
	var exclusion_radius: float = maxf(
		float(definition.get("interaction_radius", 0.0)),
		1.0
	) * 1.5
	if raw_positions is Array:
		for raw_position: Variant in raw_positions as Array:
			if (
				raw_position is Vector2
				and (
					raw_position as Vector2
				).distance_to(event_node.global_position)
				> exclusion_radius
			):
				all_positions.append(raw_position as Vector2)
	var waves: Array[Dictionary] = _typed_dictionary_array(
		definition.get("waves", [])
	)
	var planned_waves: Array[Array] = []
	var enemy_pool: Dictionary = (
		_eligible_first_visit_enemy_pool(
			_dictionary_or_empty(
				_module_world_definition.get(
					"first_visit_enemy_spawn",
					{}
				)
			),
			_difficulty_elapsed()
		)
	)
	var enemy_ids: Array = enemy_pool.get("enemy_ids", []) as Array
	var weights: Array = enemy_pool.get("weights", []) as Array
	for wave: Dictionary in waves:
		var wave_spawns: Array = []
		var count: int = maxi(int(wave.get("count", 0)), 0)
		for _spawn_index: int in range(count):
			if all_positions.is_empty() or enemy_ids.is_empty():
				break
			var position_index: int = int(
				RNG.world_event.randi() % all_positions.size()
			)
			var spawn_position: Vector2 = all_positions[
				position_index
			]
			all_positions.remove_at(position_index)
			var enemy_id: String = String(
				RNG.world_event.weighted_pick(
					enemy_ids,
					weights
				)
			)
			wave_spawns.append({
				"enemy_id": enemy_id,
				"world_position": _vector_to_dict(
					spawn_position
				),
			})
		planned_waves.append(wave_spawns)
	return {
		"event_id": event_id,
		"module_slot": _module_slot_key(module_coord),
		"difficulty": _enemy_spawn_difficulty(),
		"waves": planned_waves,
	}


func _on_world_event_wave_requested(
	instance_id: String,
	_event_id: String,
	wave_index: int,
	_enemy_count: int,
	_world_position: Vector2,
	_primary_target: Node,
	_context: Dictionary
) -> void:
	var plan: Dictionary = _dictionary_or_empty(
		_world_event_wave_plans.get(instance_id, {})
	)
	var planned_waves: Array = _array_or_empty(
		plan.get("waves", [])
	)
	if wave_index < 0 or wave_index >= planned_waves.size():
		return
	var module_slot: String = String(
		plan.get("module_slot", "")
	)
	var spawn_context: Dictionary = (
		_world_event_spawn_context(instance_id)
	)
	var fixed_difficulty: Dictionary = _dictionary_or_empty(
		plan.get("difficulty", {})
	)
	var wave_key: String = "world_event_%s_%d" % [
		instance_id,
		wave_index,
	]
	for raw_spawn: Variant in _array_or_empty(
		planned_waves[wave_index]
	):
		if not raw_spawn is Dictionary:
			continue
		var spawn: Dictionary = raw_spawn as Dictionary
		_spawn_enemy_at(
			String(spawn.get("enemy_id", "")),
			_dict_to_vector(
				spawn.get("world_position", {}),
				Vector2.ZERO
			),
			wave_key,
			module_slot,
			spawn_context,
			fixed_difficulty
		)


func _world_event_spawn_context(
	instance_id: String,
	use_event_primary: bool = true
) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var result: Dictionary = {
		"event_instance_id": instance_id,
		"reward_specialization_multiplier": 1.0,
		"primary_target": _player,
		"damage_target_groups": [
			DAMAGE_TARGET_GROUPS
			.ACTIVE_PROJECTILE_BLOCKERS,
			DAMAGE_TARGET_GROUPS.ACTIVE_PLAYER,
		],
	}
	if _world_event_controller == null or not use_event_primary:
		return result
	var event_node: WorldEventInteractable = (
		_world_event_nodes.get(instance_id)
		as WorldEventInteractable
	)
	if event_node == null:
		return result
	var definition: Dictionary = (
		_world_event_controller.definition(
			event_node.event_id()
		)
	)
	if (
		String(definition.get("kind", ""))
		== WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE
	):
		var defense_target: WorldEventDefenseTarget = (
			event_node.defense_target()
		)
		if (
			defense_target != null
			and is_instance_valid(defense_target)
		):
			result["primary_target"] = defense_target
			result["damage_target_groups"] = [
				DAMAGE_TARGET_GROUPS
				.ACTIVE_PROJECTILE_BLOCKERS,
				DAMAGE_TARGET_GROUPS
				.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS,
				DAMAGE_TARGET_GROUPS.ACTIVE_PLAYER,
			]
	return result


func _on_world_event_reward_requested(
	_instance_id: String,
	event_id: String,
	reward: Dictionary
) -> void:
	var reward_kind: String = String(reward.get("kind", ""))
	var source_kind: String = String(reward.get("source", ""))
	var feedback_key: String = ""
	var feedback_context: Dictionary = {
		"name": tr(_world_event_name_key(event_id)),
	}
	if (
		reward_kind
		== WORLD_EVENT_REWARD_TYPES.WORLD_EVENT_REWARD_GOLD
	):
		var amount: int = maxi(
			int(reward.get("amount", 0)),
			0
		)
		if amount <= 0:
			return
		add_gold(
			amount,
			GOLD_TRANSACTION_REASONS.EVENT_REWARD
		)
		feedback_context["amount"] = amount
		feedback_key = (
			"ui_world_event_blood_shrine_success"
			if source_kind
			== WORLD_EVENT_KINDS
			.WORLD_EVENT_KIND_BLOOD_SHRINE
			else "ui_world_event_completed_gold"
		)
	elif (
		reward_kind
		== WORLD_EVENT_REWARD_TYPES
		.WORLD_EVENT_REWARD_GEAR_MOD
	):
		var mod_id: String = String(reward.get("mod_id", ""))
		if mod_id.is_empty():
			return
		_grant_run_gear_mod(mod_id, 1, false)
		feedback_key = (
			"ui_world_event_gold_shrine_success"
			if source_kind
			== WORLD_EVENT_KINDS
			.WORLD_EVENT_KIND_GOLD_SHRINE
			else "ui_world_event_completed_mod"
		)
	if (
		not feedback_key.is_empty()
		and _hud != null
		and _hud.has_method("show_world_event_feedback")
	):
		_hud.call(
			"show_world_event_feedback",
			feedback_key,
			feedback_context
		)


func _on_world_event_prompt_requested(
	_instance_id: String,
	_event_id: String,
	reason: String,
	context: Dictionary
) -> void:
	var feedback_key: String = ""
	match reason:
		"continuous_event_busy":
			feedback_key = "ui_world_event_busy"
		"exhausted", "not_available":
			feedback_key = "ui_world_event_exhausted"
		"insufficient_gold":
			feedback_key = "ui_world_event_insufficient_gold"
		"shrine_failed":
			feedback_key = (
				"ui_world_event_gold_shrine_failure"
			)
		"insufficient_combined_health", "not_alive":
			feedback_key = (
				"ui_world_event_insufficient_health"
			)
		_:
			pass
	if (
		not feedback_key.is_empty()
		and _hud != null
		and _hud.has_method("show_world_event_feedback")
	):
		_hud.call(
			"show_world_event_feedback",
			feedback_key,
			context
		)


func _on_world_event_state_changed(
	_instance_id: String,
	event_id: String,
	state: String,
	_context: Dictionary
) -> void:
	if (
		state == WORLD_EVENT_STATES.WORLD_EVENT_STATE_FAILED
		and _hud != null
		and _hud.has_method("show_world_event_feedback")
	):
		_hud.call(
			"show_world_event_feedback",
			"ui_world_event_failed",
			{
				"name": tr(
					_world_event_name_key(event_id)
				),
			}
		)


func _on_world_event_module_pin_requested(
	instance_id: String,
	_module_slot_id: String,
	pinned: bool
) -> void:
	if (
		_module_world_manager == null
		or not _world_event_module_coords.has(instance_id)
		or not _module_world_manager.has_method(
			"set_slot_pinned"
		)
	):
		return
	_module_world_manager.call(
		"set_slot_pinned",
		_world_event_module_coords[instance_id]
		as Vector2i,
		pinned
	)


func _on_world_event_terminal_cleanup_requested(
	instance_id: String,
	_event_id: String,
	_context: Dictionary
) -> void:
	for raw_enemy: Node in get_tree().get_nodes_in_group(
		"active_enemies"
	):
		if (
			not raw_enemy.has_method("event_instance_id")
			or String(raw_enemy.call("event_instance_id"))
			!= instance_id
		):
			continue
		if raw_enemy.has_method("convert_to_player_target"):
			raw_enemy.call(
				"convert_to_player_target",
				_player
			)
	_try_release_world_event_background_pin(instance_id)


func _world_event_name_key(event_id: String) -> String:
	if _world_event_controller == null:
		return ""
	return String(
		_world_event_controller.definition(event_id).get(
			"name_key",
			""
		)
	)


func _update_world_event_background_pins() -> void:
	if _world_event_controller == null:
		return
	for summary: Dictionary in _typed_dictionary_array(
		_world_event_controller.debug_summary().get(
			"instances",
			[]
		)
	):
		if not bool(summary.get("pinned", false)):
			continue
		var state: String = String(summary.get("state", ""))
		if state not in [
			WORLD_EVENT_STATES.WORLD_EVENT_STATE_SUCCEEDED,
			WORLD_EVENT_STATES.WORLD_EVENT_STATE_FAILED,
		]:
			continue
		_try_release_world_event_background_pin(
			String(summary.get("instance_id", ""))
		)


func _try_release_world_event_background_pin(
	instance_id: String
) -> void:
	if (
		instance_id.is_empty()
		or _world_event_controller == null
		or _module_world_manager == null
		or not _world_event_module_coords.has(instance_id)
	):
		return
	var origin_coord: Vector2i = (
		_world_event_module_coords[instance_id] as Vector2i
	)
	var has_enemy_inside_origin: bool = false
	for raw_enemy: Node in get_tree().get_nodes_in_group(
		"active_enemies"
	):
		if (
			not raw_enemy.has_method("event_instance_id")
			or String(raw_enemy.call("event_instance_id"))
			!= instance_id
			or not raw_enemy is Node2D
		):
			continue
		var enemy_coord: Vector2i = (
			_world_event_module_coord_for_position(
				(raw_enemy as Node2D).global_position
			)
		)
		if enemy_coord == origin_coord:
			has_enemy_inside_origin = true
			continue
		if raw_enemy.has_meta("module_slot"):
			raw_enemy.remove_meta("module_slot")
	if not has_enemy_inside_origin:
		_world_event_controller.release_background_pin(instance_id)


func _world_event_module_coord_for_position(
	world_position: Vector2
) -> Vector2i:
	if _module_world_manager == null:
		return Vector2i(-1, -1)
	var global_cell: Vector2i = _module_world_manager.call(
		"world_to_global_cell",
		world_position
	) as Vector2i
	var module_and_local: Dictionary = (
		_module_world_manager.call(
			"global_cell_to_module_and_local",
			global_cell
		) as Dictionary
	)
	return module_and_local.get(
		"module_coord",
		Vector2i(-1, -1)
	) as Vector2i


func _world_events_snapshot() -> Dictionary:
	if _world_event_controller == null:
		return {}
	return {
		"controller": _world_event_controller.snapshot(),
		"wave_plans": _world_event_wave_plans.duplicate(true),
	}


func _restore_world_events(snapshot_data: Dictionary) -> bool:
	if (
		_world_event_controller == null
		or snapshot_data.is_empty()
	):
		return false
	_world_event_wave_plans = _dictionary_or_empty(
		snapshot_data.get("wave_plans", {})
	).duplicate(true)
	var result: Dictionary = (
		_world_event_controller.restore_snapshot(
			_dictionary_or_empty(
				snapshot_data.get("controller", {})
			)
		)
	)
	if not _array_or_empty(result.get("rejected", [])).is_empty():
		return false
	var active_instance_id: String = (
		_world_event_controller
		.active_continuous_instance_id()
	)
	return (
		active_instance_id.is_empty()
		or _world_event_wave_plans.has(active_instance_id)
	)


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
	var world_columns: int = maxi(int(_module_world_definition.get("columns", 0)), 1)
	var world_rows: int = maxi(int(_module_world_definition.get("rows", 0)), 1)
	var module_columns: int = maxi(int(_module_world_definition.get("module_columns", 0)), 1)
	var module_rows: int = maxi(int(_module_world_definition.get("module_rows", 0)), 1)
	var start_position: Vector2 = Vector2.ZERO
	var start_slot: Vector2i = _dict_to_vector2i(_module_world_definition.get("start_slot", {}))
	for placement: Dictionary in _module_world_manager.call("placements_at", start_slot):
		if String(placement.get("type", "")) == MODULE_PLACEMENT_TYPES.MODULE_PLACE_PLAYER_START:
			start_position = _dict_to_vector(placement.get("world_position", {}), Vector2.ZERO)
			break
	return {
		"id": String(_module_world_definition.get("id", "module_world_7x7")),
		"mode_id": GAME_MODES.MODE_STANDARD_SURVIVAL,
		"bounds": {
			"width": float(world_columns * module_columns) * cell_size,
			"height": float(world_rows * module_rows) * cell_size,
		},
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
	_register_all_module_world_events()
	var stream_change: Dictionary = _module_world_manager.call("tick", _player.global_position)
	_handle_module_stream_change(stream_change)
	_refresh_module_world_hud()


func _start_module_world_fresh_staged() -> bool:
	if _module_world_manager == null or _player == null:
		return false
	_register_all_module_interest_points()
	_register_all_module_world_events()
	var stream_change: Dictionary = _module_world_manager.call(
		"tick",
		_player.global_position
	)
	if not await _handle_module_stream_change_staged(stream_change):
		return false
	_refresh_module_world_hud()
	return true


func _update_module_world(delta: float) -> void:
	if _module_world_manager == null or _player == null:
		return
	var stream_change: Dictionary = _module_world_manager.call("tick", _player.global_position)
	_handle_module_stream_change(stream_change)
	_advance_difficulty(delta)
	_update_module_encounters(GameClock.delta_scaled(delta))
	_refresh_module_world_hud()


func _handle_module_stream_change(stream_change: Dictionary) -> void:
	for raw_coord: Variant in _array_or_empty(stream_change.get("deactivated", [])):
		_deactivate_module_slot(_dict_to_vector2i(raw_coord))
	for raw_coord: Variant in _array_or_empty(stream_change.get("activated", [])):
		_activate_module_slot(_dict_to_vector2i(raw_coord), true)
	_handle_first_module_entry(stream_change)


func _handle_module_stream_change_staged(stream_change: Dictionary) -> bool:
	for raw_coord: Variant in _array_or_empty(stream_change.get("deactivated", [])):
		_deactivate_module_slot(_dict_to_vector2i(raw_coord))
	for raw_coord: Variant in _array_or_empty(stream_change.get("activated", [])):
		_activate_module_slot(_dict_to_vector2i(raw_coord), true)
		if not await _yield_loading_frame():
			return false
	_handle_first_module_entry(stream_change)
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
			_restore_gold_orb_snapshots(
				_array_or_empty(state.get("gold_orb_snapshots", []))
			)
			state["hazard_snapshots"] = []
			state["enemy_snapshots"] = []
			state["bullet_snapshots"] = []
			state["gold_orb_snapshots"] = []
	else:
		_spawn_module_placements(module_coord, placements)
		state["initialized"] = true
	state["slot_key"] = slot_key
	_module_world_manager.call("set_slot_state", module_coord, state)
	if GameState.is_state(GameState.PLAYING):
		_restore_module_encounter_vfx(module_coord)
	# During full run restore, interest-point state is applied after active slots are rebuilt.
	# Delay their visuals until then so a claimed/destroyed target cannot briefly reappear
	# with default HP and survive the second spawn pass as an already-existing node.
	if restore_stored_entities:
		_spawn_module_interest_visuals(slot_key)


func _deactivate_module_slot(module_coord: Vector2i) -> void:
	var slot_key: String = _module_slot_key(module_coord)
	_cancel_module_encounter_vfx(slot_key)
	var state: Dictionary = _module_world_manager.call("slot_state", module_coord)
	state["enemy_snapshots"] = _capture_and_release_module_group("active_enemies", slot_key)
	state["hazard_snapshots"] = _capture_and_release_module_group("active_hazards", slot_key)
	state["bullet_snapshots"] = _capture_and_release_module_group("active_bullets", slot_key)
	state["gold_orb_snapshots"] = _capture_and_release_module_group(
		"active_gold_orbs",
		slot_key
	)
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
	for placement: Dictionary in placements:
		var placement_type: String = String(placement.get("type", ""))
		var world_position: Vector2 = _dict_to_vector(placement.get("world_position", {}), Vector2.ZERO)
		if placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_HAZARD:
			_spawn_hazard({
				"hazard_id": String(placement.get("hazard_id", "")),
				"position": _vector_to_dict(world_position),
				"module_slot": slot_key,
			})


func _handle_first_module_entry(stream_change: Dictionary) -> void:
	if (
		not bool(stream_change.get("entered", false))
		or not bool(stream_change.get("visited_now", false))
	):
		return
	var module_coord: Vector2i = _dict_to_vector2i(
		stream_change.get("current_module", {})
	)
	var start_coord: Vector2i = _module_world_manager.call(
		"role_module_coord",
		MODULE_ROLES.MODULE_ROLE_START
	)
	if module_coord == start_coord:
		return
	var assignment_entry: Dictionary = (
		_module_world_manager.call(
			"assignment_at",
			module_coord
		) as Dictionary
	)
	if (
		String(assignment_entry.get("role", ""))
		== MODULE_ROLES.MODULE_ROLE_WORLD_EVENT
	):
		return
	_start_first_visit_encounter(module_coord)


func _start_first_visit_encounter(module_coord: Vector2i) -> void:
	var state: Dictionary = _module_world_manager.call("slot_state", module_coord)
	if state.get("enemy_encounter") is Dictionary:
		return
	var config: Dictionary = _dictionary_or_empty(
		_module_world_definition.get("first_visit_enemy_spawn", {})
	)
	var raw_positions: Variant = _module_world_manager.call(
		"empty_floor_positions_at",
		module_coord
	)
	var available_positions: Array[Vector2] = []
	if raw_positions is Array:
		for raw_position: Variant in raw_positions as Array:
			if raw_position is Vector2:
				available_positions.append(raw_position as Vector2)
	var count_min: int = maxi(int(config.get("count_min", 0)), 0)
	var count_max: int = maxi(int(config.get("count_max", count_min)), count_min)
	var desired_count: int = count_min
	var count_range: int = count_max - count_min + 1
	if count_range > 1:
		desired_count += int(RNG.spawn.randi() % count_range)
	var spawn_count: int = mini(desired_count, available_positions.size())
	if spawn_count < desired_count:
		push_error(
			"[GameplayRunLoop] module %s requested %d encounter spawns but only %d empty floor cells are available"
			% [_module_slot_key(module_coord), desired_count, available_positions.size()]
		)
	var eligible_pool: Dictionary = _eligible_first_visit_enemy_pool(
		config,
		_difficulty_elapsed()
	)
	var eligible_enemy_ids: Array = eligible_pool.get("enemy_ids", []) as Array
	var eligible_weights: Array = eligible_pool.get("weights", []) as Array
	var spawn_plan: Array[Dictionary] = []
	for _spawn_index: int in range(spawn_count):
		var position_index: int = int(
			RNG.spawn.randi() % available_positions.size()
		)
		var spawn_position: Vector2 = available_positions.pop_at(position_index)
		var enemy_id: String = String(
			RNG.spawn.weighted_pick(eligible_enemy_ids, eligible_weights)
		)
		if enemy_id.is_empty():
			push_error(
				"[GameplayRunLoop] no unlocked enemy is available for module encounter"
			)
			continue
		spawn_plan.append({
			"enemy_id": enemy_id,
			"world_position": _vector_to_dict(spawn_position),
		})
	var telegraph_duration: float = maxf(
		float(config.get("telegraph_duration", 0.0)),
		0.0
	)
	var encounter: Dictionary = {
		"state": (
			MODULE_ENCOUNTER_STATE_TELEGRAPHING
			if telegraph_duration > 0.0 and not spawn_plan.is_empty()
			else MODULE_ENCOUNTER_STATE_SPAWNED
		),
		"remaining_telegraph": telegraph_duration,
		"spawns": spawn_plan,
	}
	state["enemy_encounter"] = encounter
	_module_world_manager.call("set_slot_state", module_coord, state)
	if String(encounter.get("state", "")) == MODULE_ENCOUNTER_STATE_TELEGRAPHING:
		_restore_module_encounter_vfx(module_coord)
	else:
		_spawn_module_encounter_plan(module_coord, encounter)


func _eligible_first_visit_enemy_pool(
	config: Dictionary,
	elapsed_time: float
) -> Dictionary:
	var enemy_ids: Array[String] = []
	var weights: Array[float] = []
	for raw_entry: Variant in _array_or_empty(config.get("enemy_pool", [])):
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		if float(entry.get("unlock_time", 0.0)) > elapsed_time:
			continue
		var enemy_id: String = String(entry.get("enemy_id", ""))
		if not _is_content_available(CONTENT_UNLOCK_TYPES.ENEMY, enemy_id):
			continue
		enemy_ids.append(enemy_id)
		weights.append(float(entry.get("weight", 0.0)))
	return {
		"enemy_ids": enemy_ids,
		"weights": weights,
	}


func _update_module_encounters(scaled_delta: float) -> void:
	if _module_world_manager == null:
		return
	var active_coords: Array[Vector2i] = _module_world_manager.call(
		"active_module_coords"
	)
	for module_coord: Vector2i in active_coords:
		var state: Dictionary = _module_world_manager.call(
			"slot_state",
			module_coord
		)
		var raw_encounter: Variant = state.get("enemy_encounter")
		if not raw_encounter is Dictionary:
			continue
		var encounter: Dictionary = raw_encounter as Dictionary
		if (
			String(encounter.get("state", ""))
			!= MODULE_ENCOUNTER_STATE_TELEGRAPHING
		):
			continue
		var slot_key: String = _module_slot_key(module_coord)
		if not _module_encounter_vfx.has(slot_key):
			_restore_module_encounter_vfx(module_coord)
		var remaining: float = maxf(
			float(encounter.get("remaining_telegraph", 0.0)) - scaled_delta,
			0.0
		)
		encounter["remaining_telegraph"] = remaining
		if remaining <= 0.0:
			encounter["state"] = MODULE_ENCOUNTER_STATE_SPAWNED
			_cancel_module_encounter_vfx(slot_key)
			_spawn_module_encounter_plan(module_coord, encounter)
		state["enemy_encounter"] = encounter
		_module_world_manager.call("set_slot_state", module_coord, state)


func _spawn_module_encounter_plan(
	module_coord: Vector2i,
	encounter: Dictionary
) -> void:
	var slot_key: String = _module_slot_key(module_coord)
	var wave_key: String = "module_%s" % slot_key.replace(",", "_")
	for raw_spawn: Variant in _array_or_empty(encounter.get("spawns", [])):
		if not raw_spawn is Dictionary:
			continue
		var spawn: Dictionary = raw_spawn as Dictionary
		_spawn_enemy_at(
			String(spawn.get("enemy_id", "")),
			_dict_to_vector(spawn.get("world_position", {}), Vector2.ZERO),
			wave_key,
			slot_key
		)


func _restore_module_encounter_vfx(module_coord: Vector2i) -> void:
	var state: Dictionary = _module_world_manager.call("slot_state", module_coord)
	var raw_encounter: Variant = state.get("enemy_encounter")
	if not raw_encounter is Dictionary:
		return
	var encounter: Dictionary = raw_encounter as Dictionary
	if (
		String(encounter.get("state", ""))
		!= MODULE_ENCOUNTER_STATE_TELEGRAPHING
	):
		return
	var slot_key: String = _module_slot_key(module_coord)
	_cancel_module_encounter_vfx(slot_key)
	var remaining: float = maxf(
		float(encounter.get("remaining_telegraph", 0.0)),
		0.0
	)
	var handles: Array[VfxHandle] = []
	for raw_spawn: Variant in _array_or_empty(encounter.get("spawns", [])):
		if not raw_spawn is Dictionary:
			continue
		var spawn: Dictionary = raw_spawn as Dictionary
		handles.append_array(
			_gameplay_feedback.play(
				PRESENTATION_MODULE_ENCOUNTER,
				VFX_CUES.ENEMY_SPAWN_TELEGRAPH,
				{
					"world_position": _dict_to_vector(
						spawn.get("world_position", {}),
						Vector2.ZERO
					),
					"follow_owner": false,
					"duration": remaining,
				}
			)
		)
	_module_encounter_vfx[slot_key] = handles


func _cancel_module_encounter_vfx(slot_key: String) -> void:
	var raw_handles: Variant = _module_encounter_vfx.get(slot_key)
	if raw_handles is Array and _vfx_host != null:
		for raw_handle: Variant in raw_handles as Array:
			if raw_handle is VfxHandle:
				_vfx_host.cancel_handle(raw_handle as VfxHandle, true)
	_module_encounter_vfx.erase(slot_key)


func _spawn_enemy_at(
	enemy_id: String,
	spawn_position: Vector2,
	spawn_key: String,
	module_slot: String = "",
	spawn_context: Dictionary = {},
	fixed_spawn_difficulty: Dictionary = {}
) -> bool:
	if not _is_content_available(CONTENT_UNLOCK_TYPES.ENEMY, enemy_id):
		return false
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
	var configured_spawn_context: Dictionary = spawn_context.duplicate(true)
	if not _is_debug_test_arena():
		var reward_snapshot: Dictionary = _resolve_enemy_reward_snapshot(
			enemy_data,
			configured_spawn_context
		)
		if reward_snapshot.is_empty():
			PoolManager.release(enemy)
			return false
		configured_spawn_context["reward_snapshot"] = reward_snapshot
	enemy.global_position = spawn_position
	_reparent_to_active_world(enemy)
	enemy.set_meta("wave_key", spawn_key)
	if module_slot.is_empty():
		if enemy.has_meta("module_slot"):
			enemy.remove_meta("module_slot")
	else:
		enemy.set_meta("module_slot", module_slot)
	enemy.call(
		"configure",
		enemy_data,
		_player,
		_enemy_navigation_provider(),
		(
			fixed_spawn_difficulty
			if not fixed_spawn_difficulty.is_empty()
			else _enemy_spawn_difficulty()
		),
		configured_spawn_context
	)
	_assign_enemy_spawn_serial(enemy)
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
		return
	var generic_placement: Dictionary = {
		"interest_point_id": point_id,
		"interest_point_kind": placement_type,
		"position": placement.get("world_position", {}),
		"interest_point_claim_radius": 0.0,
		"interest_point_claim_start_time": 0.0,
		"interest_point_requires_interaction": false,
		"interest_point_gold_reward_amount": 0,
		"interest_point_gear_mod_pool_id": "",
		"interest_point_gear_mod_rolls": 0,
		"interest_point_completes_run": false,
		"interest_point_target_hp": 0.0,
		"interest_point_target_hit_radius": 24.0,
	}
	if placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_REWARD_CACHE:
		generic_placement["interest_point_claim_radius"] = maxf(float(placement.get("claim_radius", 180.0)), 1.0)
		generic_placement["interest_point_requires_interaction"] = true
		generic_placement["interest_point_gold_reward_amount"] = maxi(
			int(placement.get("gold_reward_amount", 0)),
			0
		)
		generic_placement["interest_point_gear_mod_pool_id"] = String(
			placement.get("gear_mod_pool_id", "")
		)
		generic_placement["interest_point_gear_mod_rolls"] = maxi(
			int(placement.get("gear_mod_rolls", 0)),
			0
		)
	elif placement_type == MODULE_PLACEMENT_TYPES.MODULE_PLACE_OBJECTIVE:
		generic_placement["interest_point_completes_run"] = true
		generic_placement["interest_point_target_hp"] = maxf(float(placement.get("target_hp", 1.0)), 1.0)
		generic_placement["interest_point_target_hit_radius"] = maxf(float(placement.get("target_hit_radius", 24.0)), 1.0)
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
		"columns": int(_module_world_definition.get("columns", 0)),
		"rows": int(_module_world_definition.get("rows", 0)),
		"visited_slots": _module_world_manager.call("visited_module_coords"),
		"current_slot": _coord_to_dict(_module_world_manager.call("current_module_coord") as Vector2i),
		"objective_slot": _coord_to_dict(_module_world_manager.call("role_module_coord", MODULE_ROLES.MODULE_ROLE_OBJECTIVE) as Vector2i),
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
		"gear_mod_pool_id": String(placement.get("interest_point_gear_mod_pool_id", "")),
		"gear_mod_rolls": maxi(int(placement.get("interest_point_gear_mod_rolls", 0)), 0),
		"gold_reward_amount": maxi(int(placement.get("interest_point_gold_reward_amount", 0)), 0),
		"completes_run": bool(placement.get("interest_point_completes_run", false)),
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
	var completed_run: bool = bool(state.get("completes_run", false))
	if completed_run:
		_complete_run(point_id)

	var result: Dictionary = rewards.duplicate(true)
	result["ok"] = true
	result["interest_point_id"] = point_id
	result["completed_run"] = completed_run
	return result


func _try_interact_interest_point() -> bool:
	var point_id: String = _nearest_interactable_interest_point()
	if point_id.is_empty():
		return false
	var result: Dictionary = _claim_interest_point(point_id)
	return bool(result.get("ok", false))


func _try_interact_nearest() -> bool:
	var candidate: Dictionary = _nearest_interaction_candidate()
	match String(candidate.get("kind", "")):
		"interest_point":
			return _try_interact_interest_point()
		"world_event":
			if _world_event_controller == null:
				return false
			var result: Dictionary = (
				_world_event_controller.interact(
					String(candidate.get("id", "")),
					_player,
					_world_event_context()
				)
			)
			_update_combined_interaction_prompt()
			return bool(result.get("accepted", false))
		_:
			return false


func _nearest_interaction_candidate() -> Dictionary:
	var best: Dictionary = {}
	var interest_point_id: String = (
		_nearest_interactable_interest_point()
	)
	if not interest_point_id.is_empty():
		var interest_state: Dictionary = (
			_interest_points[interest_point_id] as Dictionary
		)
		var interest_position: Vector2 = _dict_to_vector(
			interest_state.get("position", {}),
			Vector2.ZERO
		)
		best = {
			"kind": "interest_point",
			"id": interest_point_id,
			"distance": _player.global_position.distance_to(
				interest_position
			),
		}
	var event_candidate: Dictionary = (
		_nearest_world_event_candidate()
	)
	if (
		not event_candidate.is_empty()
		and (
			best.is_empty()
			or float(event_candidate.get("distance", INF))
			< float(best.get("distance", INF))
		)
	):
		best = event_candidate
	return best


func _nearest_world_event_candidate() -> Dictionary:
	if _player == null or _world_event_controller == null:
		return {}
	var best: Dictionary = {}
	for instance_id_raw: Variant in _world_event_nodes.keys():
		var instance_id: String = String(instance_id_raw)
		var interactable: WorldEventInteractable = (
			_world_event_nodes.get(instance_id)
			as WorldEventInteractable
		)
		if (
			interactable == null
			or not is_instance_valid(interactable)
			or interactable.event_state()
			!= WORLD_EVENT_STATES
			.WORLD_EVENT_STATE_INACTIVE
			or not interactable.can_player_interact(_player)
		):
			continue
		var distance: float = (
			_player.global_position.distance_to(
				interactable.global_position
			)
		)
		if (
			not best.is_empty()
			and distance >= float(best.get("distance", INF))
		):
			continue
		best = {
			"kind": "world_event",
			"id": instance_id,
			"distance": distance,
			"event_id": interactable.event_id(),
		}
	return best


func _update_combined_interaction_prompt() -> void:
	if _hud == null:
		return
	var candidate: Dictionary = _nearest_interaction_candidate()
	if candidate.is_empty():
		if _hud.has_method("hide_interaction_prompt"):
			_hud.call("hide_interaction_prompt")
		return
	if String(candidate.get("kind", "")) == "interest_point":
		_update_interaction_prompt(String(candidate.get("id", "")))
		return
	var instance_id: String = String(candidate.get("id", ""))
	var event_id: String = String(candidate.get("event_id", ""))
	var definition: Dictionary = (
		_world_event_controller.definition(event_id)
	)
	var kind: String = String(definition.get("kind", ""))
	var prompt_key: String = "ui_world_event_interact_start"
	var values: Dictionary = {
		"name": tr(String(definition.get("name_key", ""))),
	}
	var runtime: Dictionary = _world_event_runtime_summary(
		instance_id
	)
	if (
		kind
		== WORLD_EVENT_KINDS.WORLD_EVENT_KIND_GOLD_SHRINE
	):
		prompt_key = "ui_world_event_interact_gold_shrine"
		values["cost"] = int(runtime.get("next_cost", 0))
	elif (
		kind
		== WORLD_EVENT_KINDS.WORLD_EVENT_KIND_BLOOD_SHRINE
	):
		prompt_key = "ui_world_event_interact_blood_shrine"
		var ratios: Array = _array_or_empty(
			definition.get("sacrifice_ratios", [])
		)
		var use_index: int = int(runtime.get("blood_uses", 0))
		var ratio: float = (
			float(ratios[use_index])
			if use_index >= 0 and use_index < ratios.size()
			else 0.0
		)
		values["cost"] = int(ceil(
			(
				float(_player.call("max_life"))
				+ float(_player.call("max_shield"))
			) * ratio
		))
	if _hud.has_method("show_interaction_prompt"):
		_hud.call(
			"show_interaction_prompt",
			_interaction_binding_label(),
			prompt_key,
			values
		)


func _world_event_runtime_summary(
	instance_id: String
) -> Dictionary:
	if _world_event_controller == null:
		return {}
	for summary: Dictionary in _typed_dictionary_array(
		_world_event_controller.debug_summary().get(
			"instances",
			[]
		)
	):
		if String(summary.get("instance_id", "")) == instance_id:
			return summary
	return {}


func _refresh_world_event_hud() -> void:
	if (
		_hud == null
		or not _hud.has_method("set_world_event_status")
	):
		return
	if _world_event_controller == null:
		_hud.call("set_world_event_status", {"visible": false})
		return
	var active_instance_id: String = (
		_world_event_controller
		.active_continuous_instance_id()
	)
	if active_instance_id.is_empty():
		_hud.call("set_world_event_status", {"visible": false})
		return
	var runtime: Dictionary = _world_event_runtime_summary(
		active_instance_id
	)
	var event_id: String = String(runtime.get("event_id", ""))
	var definition: Dictionary = (
		_world_event_controller.definition(event_id)
	)
	var kind: String = String(definition.get("kind", ""))
	var elapsed: float = maxf(
		float(runtime.get("elapsed", 0.0)),
		0.0
	)
	var status: Dictionary = {
		"visible": true,
		"name_key": String(definition.get("name_key", "")),
		"values": {},
	}
	var values: Dictionary = {}
	match kind:
		WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE:
			status["detail_key"] = (
				"ui_world_event_status_defense"
			)
			var defense: Dictionary = _dictionary_or_empty(
				runtime.get("defense_target", {})
			)
			values = {
				"time": _display_event_number(
					maxf(
						float(definition.get("duration", 0.0))
						- elapsed,
						0.0
					)
				),
				"health": _display_event_number(
					float(defense.get("current_health", 0.0))
				),
				"max_health": _display_event_number(
					float(defense.get("max_health", 0.0))
				),
			}
		WORLD_EVENT_KINDS.WORLD_EVENT_KIND_SURVIVAL:
			status["detail_key"] = (
				"ui_world_event_status_survival"
			)
			var wave_total: int = _array_or_empty(
				definition.get("waves", [])
			).size()
			values = {
				"time": _display_event_number(
					maxf(
						float(definition.get("duration", 0.0))
						- elapsed,
						0.0
					)
				),
				"wave": mini(
					int(runtime.get("wave_cursor", 0)),
					wave_total
				),
				"wave_total": wave_total,
			}
		WORLD_EVENT_KINDS.WORLD_EVENT_KIND_CAPTURE:
			status["detail_key"] = (
				"ui_world_event_status_capture"
			)
			values = {
				"progress": _display_event_number(
					float(runtime.get("capture_progress", 0.0))
				),
				"required": _display_event_number(
					float(
						definition.get(
							"capture_duration",
							0.0
						)
					)
				),
				"entry": _display_event_number(
					float(
						runtime.get(
							"entry_delay_progress",
							0.0
						)
					)
				),
				"entry_required": _display_event_number(
					float(definition.get("entry_delay", 0.0))
				),
				"timeout": _display_event_number(
					maxf(
						float(definition.get("timeout", 0.0))
						- elapsed,
						0.0
					)
				),
			}
		_:
			status["visible"] = false
	status["values"] = values
	_hud.call("set_world_event_status", status)


func _display_event_number(value: float) -> String:
	return "%.1f" % maxf(value, 0.0)


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
	var granted_mods: Array[Dictionary] = []
	var pool_id: String = String(state.get("gear_mod_pool_id", ""))
	var pool: Array[String] = GearModSystem.reward_pool_ids(
		pool_id,
		_available_content_ids(CONTENT_UNLOCK_TYPES.GEAR_MOD)
	)
	var rolls: int = maxi(int(state.get("gear_mod_rolls", 0)), 0)
	for _index: int in range(rolls):
		if pool.is_empty():
			break
		var mod_id: String = pool[int(RNG.drop.randi() % pool.size())]
		granted_mods.append(_grant_run_gear_mod(mod_id))
	var gold_amount: int = maxi(int(state.get("gold_reward_amount", 0)), 0)
	if gold_amount > 0:
		add_gold(gold_amount, GOLD_TRANSACTION_REASONS.EVENT_REWARD)

	return {
		"gold_amount": gold_amount,
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


func _on_enemy_defeated(
	_enemy: Node,
	gold_reward: int,
	counts_as_kill: bool,
	drops_rewards: bool,
	_cause_id: String,
	wave_key: String
) -> void:
	if _vfx_host != null and _enemy != null:
		_vfx_host.cancel_owner(_enemy)
	var event_instance_id: String = ""
	if _enemy != null and _enemy.has_method("event_instance_id"):
		event_instance_id = String(
			_enemy.call("event_instance_id")
		)
	if _is_debug_test_arena():
		if counts_as_kill:
			_kills += 1
		if _spawn_states.has(wave_key):
			var arena_state: Dictionary = _spawn_states[wave_key]
			arena_state["alive"] = maxi(
				int(arena_state.get("alive", 0)) - 1,
				0
			)
			_spawn_states[wave_key] = arena_state
		return
	if counts_as_kill:
		_kills += 1
		_record_enemy_defeated_progress(_enemy)
		if _hud != null:
			_hud.call("set_kills", _kills)
	if drops_rewards:
		if _enemy is Node2D and gold_reward > 0:
			_spawn_gold_orb(
				(_enemy as Node2D).global_position,
				gold_reward
			)
		if _enemy is Node2D:
			_try_spawn_energy_orb((_enemy as Node2D).global_position)
		if _enemy != null:
			_roll_gear_mod_drop(_enemy)
	if _spawn_states.has(wave_key):
		var state: Dictionary = _spawn_states[wave_key]
		state["alive"] = maxi(int(state.get("alive", 0)) - 1, 0)
		_spawn_states[wave_key] = state
	if not event_instance_id.is_empty():
		call_deferred(
			"_try_release_world_event_background_pin",
			event_instance_id
		)


func _spawn_gold_orb(spawn_position: Vector2, amount: int) -> void:
	var raw_node: Node = PoolManager.acquire(POOL_IDS.GOLD_ORB)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return

	var gold_orb: Node2D = raw_node as Node2D
	gold_orb.global_position = spawn_position
	_reparent_to_active_world(gold_orb)
	gold_orb.call(
		"configure",
		amount,
		_player,
		float(_gold_drop_config.get("pickup_speed", 0.0))
	)
	_play_feedback(PRESENTATION_PICKUP_DEFAULT, VFX_CUES.PICKUP_SPAWN, {
		"owner": gold_orb,
		"world_position": spawn_position,
	})
	_connect_gold_orb_feedback(gold_orb)


func _try_spawn_energy_orb(spawn_position: Vector2) -> void:
	var chance: float = clampf(
		float(_energy_drop_config.get("chance", 0.0)),
		0.0,
		1.0
	)
	if chance <= 0.0 or RNG.drop.randf() >= chance:
		return
	var raw_node: Node = PoolManager.acquire(POOL_IDS.ENERGY_ORB)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return
	var energy_orb: Node2D = raw_node as Node2D
	energy_orb.global_position = spawn_position
	_reparent_to_active_world(energy_orb)
	energy_orb.call(
		"configure",
		maxf(float(_energy_drop_config.get("amount", 25.0)), 0.0),
		_player,
		_skill_system,
		float(_energy_drop_config.get("pickup_speed", 0.0)),
		SKILL_RESOURCES.ENERGY
	)


func _connect_gold_orb_feedback(gold_orb: Node2D) -> void:
	var attraction_callback: Callable = Callable(
		self,
		"_on_gold_orb_attraction_started"
	).bind(gold_orb)
	if not gold_orb.is_connected("attraction_started", attraction_callback):
		gold_orb.connect(
			"attraction_started",
			attraction_callback,
			CONNECT_ONE_SHOT
		)
	var collected_callback: Callable = Callable(
		self,
		"_on_gold_orb_collected"
	).bind(gold_orb)
	if not gold_orb.is_connected("collected", collected_callback):
		gold_orb.connect(
			"collected",
			collected_callback,
			CONNECT_ONE_SHOT
		)


func _on_gold_orb_attraction_started(gold_orb: Node2D) -> void:
	if gold_orb == null or not is_instance_valid(gold_orb):
		return
	_play_feedback(PRESENTATION_PICKUP_DEFAULT, VFX_CUES.PICKUP_ATTRACT, {
		"owner": gold_orb,
		"world_position": gold_orb.global_position,
	})


func _on_gold_orb_collected(
	amount: int,
	gold_orb: Node2D = null
) -> void:
	var collect_position: Vector2 = (
		gold_orb.global_position
		if gold_orb != null and is_instance_valid(gold_orb)
		else (_player.global_position if _player != null else Vector2.ZERO)
	)
	_play_feedback(PRESENTATION_PICKUP_DEFAULT, VFX_CUES.PICKUP_COLLECT, {
		"owner": _player,
		"world_position": collect_position,
		"follow_owner": false,
		"amount": amount,
	})
	add_gold(amount, GOLD_TRANSACTION_REASONS.ENEMY_DROP)


func _show_reward_choice_panel(
	choices: Array[Dictionary]
) -> void:
	_reward_choice_panel = UIManager.push(
		REWARD_CHOICE_PANEL_SCENE,
		{"source": "reward_choice"}
	) as CanvasLayer
	if _reward_choice_panel == null:
		return
	_reward_choice_panel.call("configure", choices)
	_reward_choice_panel.connect(
		"choice_selected",
		Callable(self, "_on_reward_choice_selected"),
		CONNECT_ONE_SHOT
	)
	_reward_choice_panel.connect(
		"pause_requested",
		Callable(self, "_on_reward_choice_pause_requested")
	)
	var pending: Dictionary = _reward_choice_controller.snapshot()
	GameState.change_state(GameState.REWARD_CHOICE, {
		"pool_id": String(pending.get("pool_id", "")),
		"trigger_id": String(pending.get("trigger_id", "")),
		"choices": _choice_ids(choices),
	})


func _on_reward_choice_pause_requested() -> void:
	if _pause_menu != null:
		return
	_show_pause_menu()


func _on_reward_choice_selected(choice: Dictionary) -> void:
	if _reward_choice_controller == null:
		return
	var result: Dictionary = _reward_choice_controller.resolve(
		String(choice.get("id", ""))
	)
	if not bool(result.get("ok", false)):
		return
	var resolved_choice: Dictionary = _dictionary_or_empty(
		result.get("choice", {})
	)
	_record_reward_choice_decision(result)
	var modifiers: Array = (
		resolved_choice.get("modifiers", [])
		if resolved_choice.get("modifiers", []) is Array
		else []
	)
	if _player != null and _player.has_method("apply_modifiers"):
		_player.call("apply_modifiers", modifiers)
	if _weapon_system != null and _weapon_system.has_method("apply_modifiers"):
		_weapon_system.call("apply_modifiers", modifiers)
	if _hud != null and _hud.has_method("show_upgrade_feedback"):
		_hud.call(
			"show_upgrade_feedback",
			String(resolved_choice.get("name_key", ""))
		)
	if UIManager.top() == _reward_choice_panel:
		UIManager.pop()
	elif _reward_choice_panel != null:
		_reward_choice_panel.queue_free()
	_reward_choice_panel = null
	var trigger_id: String = String(result.get("trigger_id", ""))
	var pool_id: String = String(result.get("pool_id", ""))
	var entry_id: String = String(resolved_choice.get("id", ""))
	GameState.change_state(GameState.PLAYING, {
		"trigger_id": trigger_id,
		"pool_id": pool_id,
		"choice": entry_id,
	})
	reward_choice_resolved.emit(trigger_id, pool_id, entry_id)


func _record_reward_choice_decision(result: Dictionary) -> void:
	var choices: Array[Dictionary] = _typed_choice_array(
		result.get("choices", [])
	)
	var choice: Dictionary = _dictionary_or_empty(
		result.get("choice", {})
	)
	var event_data: Dictionary = {
		"trigger_id": String(result.get("trigger_id", "")),
		"pool_id": String(result.get("pool_id", "")),
		"candidate_count": int(result.get("candidate_count", 0)),
		"choices": _choice_ids(choices),
		"selected": String(choice.get("id", "")),
	}
	Replay.record_decision(
		ANALYTICS_EVENTS.REWARD_CHOICE,
		event_data
	)
	Analytics.track_event(
		ANALYTICS_EVENTS.REWARD_CHOICE,
		event_data
	)


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
	var feedback_context: Dictionary = context.duplicate(true)
	feedback_context["camera_controller"] = _camera_controller
	var raw_direction: Variant = context.get("direction", Vector2.RIGHT)
	var shot_direction: Vector2 = (
		raw_direction
		if raw_direction is Vector2
		else Vector2.RIGHT
	)
	if _player != null:
		var player_visual: Node = _player.get_node_or_null("Visual")
		if player_visual != null and player_visual.has_method("apply_fire_impulse"):
			player_visual.call("apply_fire_impulse", shot_direction)
	if _player != null and _player.has_method("apply_weapon_recoil"):
		_player.call(
			"apply_weapon_recoil",
			shot_direction,
			float(context.get("kickback_initial_speed", 0.0)),
			float(context.get("kickback_duration", 0.0))
		)
	_play_feedback(_profile_or_fallback(
		String(context.get("presentation_profile_id", "")),
		"presentation_weapon_default"
	), VFX_CUES.WEAPON_FIRE, feedback_context)


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
	var difficulty: Dictionary = _difficulty_snapshot()
	var build_summary: Dictionary = _run_gear_mod_build_summary()
	var newly_unlocked: Dictionary = _commit_content_progress(false)
	_finish_run_replay(false)
	_clear_run_gear_mods()
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	GameState.change_state(GameState.GAME_OVER, {
		"kills": _kills,
		"run_time": _difficulty_elapsed(),
		"difficulty": difficulty,
		"completed": false,
		"build": build_summary.duplicate(true),
		"newly_unlocked": newly_unlocked.duplicate(true),
	})
	_show_game_over_panel(false, build_summary, newly_unlocked)


func _complete_run(point_id: String) -> void:
	if _run_completed:
		return
	_run_completed = true
	var difficulty: Dictionary = _difficulty_snapshot()
	var build_summary: Dictionary = _run_gear_mod_build_summary()
	var newly_unlocked: Dictionary = _commit_content_progress(true)
	_finish_run_replay(true)
	_clear_run_gear_mods()
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	GameState.change_state(GameState.GAME_OVER, {
		"kills": _kills,
		"run_time": _difficulty_elapsed(),
		"difficulty": difficulty,
		"completed": true,
		"interest_point_id": point_id,
		"build": build_summary.duplicate(true),
		"newly_unlocked": newly_unlocked.duplicate(true),
	})
	_show_game_over_panel(true, build_summary, newly_unlocked)


func _finish_run_replay(completed: bool) -> void:
	if not Replay.is_recording():
		return
	var difficulty: Dictionary = _difficulty_snapshot()
	Replay.record_decision(ANALYTICS_EVENTS.RUN_END, {
		"completed": completed,
		"kills": _kills,
		"run_time": _difficulty_elapsed(),
		"difficulty_time": float(difficulty.get("elapsed", 0.0)),
		"difficulty_level": int(
			difficulty.get("difficulty_level", 1)
		),
		"enemy_health_multiplier": float(
			difficulty.get("health_multiplier", 1.0)
		),
		"enemy_damage_multiplier": float(
			difficulty.get("damage_multiplier", 1.0)
		),
		"main_hero_id": _main_hero_id,
		"sub_hero_id": _sub_hero_id,
		"gear_mods": _run_gear_mod_snapshot(),
	})
	var recording: Dictionary = Replay.stop_recording(
		"completed" if completed else "player_death"
	)
	if not recording.is_empty():
		Replay.save_recording(recording)


func _show_game_over_panel(
	completed: bool = false,
	build_summary: Dictionary = {},
	newly_unlocked: Dictionary = {}
) -> void:
	_game_over_panel = UIManager.push(GAME_OVER_PANEL_SCENE, {"source": "game_over"}) as CanvasLayer
	if _game_over_panel == null:
		return
	_game_over_panel.call(
		"configure",
		_kills,
		_difficulty_elapsed(),
		completed,
		build_summary,
		newly_unlocked
	)
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
	var drop_result: Dictionary = GearModSystem.roll_drop_for_enemy(
		enemy_id,
		1,
		forced_roll,
		_available_content_ids(CONTENT_UNLOCK_TYPES.GEAR_MOD)
	)
	for raw_drop: Variant in drop_result.get("drops", []):
		if not raw_drop is Dictionary:
			continue
		var drop: Dictionary = raw_drop as Dictionary
		var mod_id: String = String(drop.get("mod_id", ""))
		if not mod_id.is_empty():
			_grant_run_gear_mod(mod_id)


func _apply_initial_gear_modifiers() -> void:
	var hero_modifiers: Array[Dictionary] = []
	var weapon_modifiers: Array[Dictionary] = []
	if _is_debug_test_arena():
		var preview: Dictionary = GearModSystem.resolve_preview_loadout(
			_array_or_empty(_debug_test_arena_config.get("gear_mods", []))
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
	if _player != null and _player.has_method("set_gear_modifiers"):
		_player.call("set_gear_modifiers", hero_modifiers)
	if _weapon_system != null and _weapon_system.has_method("set_gear_modifiers"):
		_weapon_system.call("set_gear_modifiers", weapon_modifiers)


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
	var reward_choice_active: bool = (
		_reward_choice_controller != null
		and _reward_choice_controller.is_busy()
	)
	if _pause_menu != null and reward_choice_active:
		return {
			"state": UI_RESTORE_PAUSED,
			UI_RESTORE_UNDERLYING_STATE: UI_RESTORE_REWARD_CHOICE,
		}
	if (
		reward_choice_active
		and (
			GameState.is_state(GameState.REWARD_CHOICE)
			or _reward_choice_panel != null
		)
	):
		return {
			"state": UI_RESTORE_REWARD_CHOICE,
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
			"target_hp": float(state.get("target_hp", 0.0)),
			"target_destroyed": bool(state.get("target_destroyed", false)),
			"gold_reward_amount": int(state.get("gold_reward_amount", 0)),
			"gear_mod_reward_count": int(state.get("gear_mod_rolls", 0)),
			"gear_mod_pool_id": String(state.get("gear_mod_pool_id", "")),
			"gear_mod_rolls": int(state.get("gear_mod_rolls", 0)),
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
	if (
		int(snapshot_data.get("schema_version", -1))
		!= RUN_SNAPSHOT_SCHEMA_VERSION
	):
		push_error("[GameplayRunLoop] unsupported run snapshot schema")
		return false
	if (
		not snapshot_data.get("content_availability", {}) is Dictionary
		or not snapshot_data.get("content_progress_delta", {}) is Dictionary
	):
		push_error("[GameplayRunLoop] run snapshot content progression is invalid")
		return false
	var difficulty_snapshot: Dictionary = _dictionary_or_empty(
		snapshot_data.get("difficulty", {})
	)
	if (
		_difficulty_progression == null
		or difficulty_snapshot.is_empty()
		or not _difficulty_progression.restore_snapshot(difficulty_snapshot)
	):
		push_error("[GameplayRunLoop] difficulty snapshot restore failed")
		return false
	var module_snapshot: Dictionary = _dictionary_or_empty(snapshot_data.get("module_world", {}))
	if _module_world_enabled and _module_world_manager != null:
		if module_snapshot.is_empty() or not bool(_module_world_manager.call("restore_state", module_snapshot)):
			push_error("[GameplayRunLoop] module-world snapshot restore failed")
			return false
		_register_all_module_interest_points()
		_register_all_module_world_events()
		if not _restore_world_events(
			_dictionary_or_empty(
				snapshot_data.get("world_events", {})
			)
		):
			push_error(
				"[GameplayRunLoop] world-event snapshot restore failed"
			)
			return false
		var active_coords: Array[Vector2i] = _module_world_manager.call("active_module_coords")
		for module_coord: Vector2i in active_coords:
			_activate_module_slot(module_coord, false)
			if staged_loading and not await _yield_loading_frame():
				return false

	var gold_snapshot: Dictionary = _dictionary_or_empty(
		snapshot_data.get("gold_progression", {})
	)
	if (
		_gold_progression == null
		or not _gold_progression.restore(
			int(gold_snapshot.get("gold_balance", -1)),
			int(gold_snapshot.get("gold_earned_total", -1))
		)
	):
		push_error("[GameplayRunLoop] gold progression restore failed")
		return false
	var reward_choice_snapshot: Dictionary = _dictionary_or_empty(
		snapshot_data.get("reward_choice", {})
	)
	if (
		not reward_choice_snapshot.is_empty()
		and (
			_reward_choice_controller == null
			or not _reward_choice_controller.restore_snapshot(
				reward_choice_snapshot,
				current_level()
			)
		)
	):
		push_error("[GameplayRunLoop] reward choice restore failed")
		return false
	_kills = maxi(int(snapshot_data.get("kills", 0)), 0)
	_next_enemy_spawn_serial = maxi(
		int(snapshot_data.get("next_enemy_spawn_serial", 1)),
		1
	)
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
	if not _restore_run_gear_mods(snapshot_data.get("gear_mods", {})):
		push_error("[GameplayRunLoop] Gear Mod snapshot restore failed")
		return false
	_apply_run_gear_modifiers()
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
	var gold_orb_snapshots: Array = _array_or_empty(
		snapshot_data.get("gold_orbs", [])
	)
	var energy_orb_snapshots: Array = _array_or_empty(
		snapshot_data.get("energy_orbs", [])
	)
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
			gold_orb_snapshots,
			Callable(self, "_restore_gold_orb_snapshots")
		):
			return false
		if not await _restore_snapshots_staged(
			energy_orb_snapshots,
			Callable(self, "_restore_energy_orb_snapshots")
		):
			return false
	else:
		_restore_enemy_snapshots(enemy_snapshots)
		_restore_bullet_snapshots(bullet_snapshots)
		_restore_gold_orb_snapshots(gold_orb_snapshots)
		_restore_energy_orb_snapshots(energy_orb_snapshots)

	var clock_snapshot: Variant = snapshot_data.get("game_clock", {})
	if clock_snapshot is Dictionary:
		GameClock.restore_snapshot(clock_snapshot as Dictionary)

	if _hud != null:
		_hud.call("set_life", _player.call("current_life"), _player.call("max_life"))
		_hud.call("set_kills", _kills)
		_hud.call("set_level", current_level())
	_refresh_gold_hud()
	_refresh_module_world_hud()
	_refresh_difficulty_hud()
	_update_combat_hud()
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


func _gear_mod_name_key(mod_id: String) -> String:
	return String(
		GearModSystem.mod_definition(mod_id).get("name_key", "")
	)


func _run_gear_mod_snapshot() -> Dictionary:
	return {"ranks": _run_gear_mod_ranks.duplicate(true)}


func _restore_run_gear_mods(raw_value: Variant) -> bool:
	if not raw_value is Dictionary:
		return false
	var saved_state: Dictionary = raw_value as Dictionary
	if not saved_state.get("ranks", {}) is Dictionary:
		return false
	var saved_ranks: Dictionary = saved_state.get("ranks", {}) as Dictionary
	var restored_ranks: Dictionary = {}
	var mod_ids: Array[String] = []
	for raw_mod_id: Variant in saved_ranks.keys():
		mod_ids.append(String(raw_mod_id))
	mod_ids.sort()
	for mod_id: String in mod_ids:
		var maximum_rank: int = GearModSystem.max_rank(mod_id)
		if maximum_rank < 0:
			return false
		var rank: int = int(saved_ranks.get(mod_id, -1))
		if rank < 0 or rank > maximum_rank:
			return false
		restored_ranks[mod_id] = rank
	_run_gear_mod_ranks = restored_ranks
	return true


func _grant_run_gear_mod(
	mod_id: String,
	count: int = 1,
	show_feedback: bool = true
) -> Dictionary:
	var definition: Dictionary = GearModSystem.mod_definition(mod_id)
	if definition.is_empty() or count <= 0:
		return _debug_result(false, "unknown_gear_mod")
	if not _is_content_available(CONTENT_UNLOCK_TYPES.GEAR_MOD, mod_id):
		return _debug_result(false, "locked_gear_mod")
	var maximum_rank: int = GearModSystem.max_rank(mod_id)
	var rank: int = int(_run_gear_mod_ranks.get(mod_id, -1))
	var overflow_gold: int = 0
	var rank_changed: bool = false
	for _index: int in range(count):
		if rank < 0:
			rank = 0
			rank_changed = true
		elif rank < maximum_rank:
			rank += 1
			rank_changed = true
		else:
			overflow_gold += GearModSystem.overflow_gold()
	if overflow_gold > 0:
		var gold_result: Dictionary = add_gold(
			overflow_gold,
			GOLD_TRANSACTION_REASONS.GEAR_MOD_OVERFLOW
		)
		if not bool(gold_result.get("ok", false)):
			return {
				"ok": false,
				"reason": "overflow_gold_failed",
				"gold_result": gold_result,
			}
	_run_gear_mod_ranks[mod_id] = rank
	if rank_changed:
		_apply_run_gear_modifiers()
	if (
		show_feedback
		and _hud != null
		and _hud.has_method("show_gear_mod_drop_feedback")
	):
		_hud.call(
			"show_gear_mod_drop_feedback",
			String(definition.get("name_key", "")),
			rank + 1,
			overflow_gold
		)
	return {
		"ok": true,
		"mod_id": mod_id,
		"name_key": String(definition.get("name_key", "")),
		"rank": rank,
		"display_rank": rank + 1,
		"overflow_gold": overflow_gold,
	}


func _clear_run_gear_mods() -> void:
	_run_gear_mod_ranks.clear()
	_apply_run_gear_modifiers()


func _apply_run_gear_modifiers() -> void:
	var hero_modifiers: Array[Dictionary] = []
	var weapon_modifiers: Array[Dictionary] = []
	var mod_ids: Array[String] = []
	for raw_mod_id: Variant in _run_gear_mod_ranks.keys():
		mod_ids.append(String(raw_mod_id))
	mod_ids.sort()
	for mod_id: String in mod_ids:
		var definition: Dictionary = GearModSystem.mod_definition(mod_id)
		var modifiers: Array[Dictionary] = GearModSystem.rank_modifiers(
			mod_id,
			int(_run_gear_mod_ranks.get(mod_id, 0))
		)
		match String(definition.get("slot", "")):
			GEAR_MOD_SLOTS.HERO:
				hero_modifiers.append_array(modifiers)
			GEAR_MOD_SLOTS.WEAPON:
				weapon_modifiers.append_array(modifiers)
			_:
				continue
	if _player != null and _player.has_method("set_gear_modifiers"):
		_player.call("set_gear_modifiers", hero_modifiers)
	if _weapon_system != null and _weapon_system.has_method(
		"set_gear_modifiers"
	):
		_weapon_system.call("set_gear_modifiers", weapon_modifiers)


func _run_gear_mod_build_summary() -> Dictionary:
	var mods: Array[Dictionary] = []
	var mod_ids: Array[String] = []
	for raw_mod_id: Variant in _run_gear_mod_ranks.keys():
		mod_ids.append(String(raw_mod_id))
	mod_ids.sort()
	for mod_id: String in mod_ids:
		var rank: int = int(_run_gear_mod_ranks.get(mod_id, 0))
		mods.append({
			"mod_id": mod_id,
			"name_key": _gear_mod_name_key(mod_id),
			"rank": rank,
			"display_rank": rank + 1,
		})
	return {"gear_mods": mods}


func _restore_ui_state(raw_ui_restore: Variant) -> void:
	if not raw_ui_restore is Dictionary:
		return
	var ui_restore: Dictionary = raw_ui_restore as Dictionary
	var state: String = String(ui_restore.get("state", UI_RESTORE_PLAYING))
	if state == UI_RESTORE_PAUSED:
		if String(
			ui_restore.get(UI_RESTORE_UNDERLYING_STATE, "")
		) == UI_RESTORE_REWARD_CHOICE:
			if (
				_reward_choice_controller != null
				and _reward_choice_controller.is_busy()
			):
				_show_reward_choice_panel(
					_reward_choice_controller.choices()
				)
		_show_pause_menu()
		return
	if (
		state == UI_RESTORE_REWARD_CHOICE
		and _reward_choice_controller != null
		and _reward_choice_controller.is_busy()
	):
		_show_reward_choice_panel(
			_reward_choice_controller.choices()
		)


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
		var restored_spawn_context: Dictionary = _world_event_spawn_context(
			String(snapshot_data.get("event_instance_id", "")),
			String(
				snapshot_data.get(
					"target_mode",
					WORLD_EVENT_TARGET_MODE_EVENT_PRIMARY
				)
			) == WORLD_EVENT_TARGET_MODE_EVENT_PRIMARY
		)
		restored_spawn_context["reward_snapshot"] = _dictionary_or_empty(
			snapshot_data.get("reward_snapshot", {})
		)
		enemy.call(
			"configure",
			enemy_data,
			_player,
			_enemy_navigation_provider(),
			{
				"health_multiplier": float(
					snapshot_data.get("spawn_health_multiplier", 1.0)
				),
				"damage_multiplier": float(
					snapshot_data.get("spawn_damage_multiplier", 1.0)
				),
			},
			restored_spawn_context
		)
		if enemy.has_method("set_runtime_spawn_serial"):
			var restored_serial: int = maxi(
				int(snapshot_data.get("runtime_spawn_serial", 0)),
				0
			)
			enemy.call("set_runtime_spawn_serial", restored_serial)
			_next_enemy_spawn_serial = maxi(
				_next_enemy_spawn_serial,
				restored_serial + 1
			)
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


func _restore_gold_orb_snapshots(gold_orb_snapshots: Array) -> void:
	for raw_snapshot: Variant in gold_orb_snapshots:
		if not raw_snapshot is Dictionary:
			continue
		var raw_node: Node = PoolManager.acquire(POOL_IDS.GOLD_ORB)
		if not raw_node is Node2D or not raw_node.has_method("restore_snapshot"):
			continue

		var gold_orb: Node2D = raw_node as Node2D
		_reparent_to_active_world(gold_orb)
		gold_orb.call(
			"restore_snapshot",
			raw_snapshot as Dictionary,
			_player
		)
		_connect_gold_orb_feedback(gold_orb)


func _restore_energy_orb_snapshots(energy_orb_snapshots: Array) -> void:
	for raw_snapshot: Variant in energy_orb_snapshots:
		if not raw_snapshot is Dictionary:
			continue
		var raw_node: Node = PoolManager.acquire(POOL_IDS.ENERGY_ORB)
		if not raw_node is Node2D or not raw_node.has_method("restore_snapshot"):
			continue
		var energy_orb: Node2D = raw_node as Node2D
		_reparent_to_active_world(energy_orb)
		energy_orb.call(
			"restore_snapshot",
			raw_snapshot as Dictionary,
			_player,
			_skill_system
		)


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
	_connect_enemy_attack_feedback(enemy)
	_connect_status_feedback(enemy)
	if enemy is Node2D:
		_play_feedback(_actor_profile_id(enemy, PRESENTATION_ENEMY_DEFAULT), VFX_CUES.SPAWN, {
			"owner": enemy,
			"world_position": (enemy as Node2D).global_position,
		})


func _connect_enemy_attack_feedback(enemy: Node) -> void:
	var windup_callback: Callable = Callable(
		self,
		"_on_enemy_attack_windup_started"
	)
	if (
		enemy.has_signal("attack_windup_started")
		and not enemy.is_connected(
			"attack_windup_started",
			windup_callback
		)
	):
		enemy.connect("attack_windup_started", windup_callback)
	var committed_callback: Callable = Callable(
		self,
		"_on_enemy_attack_committed"
	)
	if (
		enemy.has_signal("attack_committed")
		and not enemy.is_connected(
			"attack_committed",
			committed_callback
		)
	):
		enemy.connect("attack_committed", committed_callback)


func _on_enemy_attack_windup_started(
	enemy: Node,
	_action_id: String,
	context: Dictionary
) -> void:
	_play_feedback(
		_actor_profile_id(enemy, PRESENTATION_ENEMY_DEFAULT),
		VFX_CUES.ENEMY_ATTACK_TELEGRAPH,
		context
	)


func _on_enemy_attack_committed(
	enemy: Node,
	_action_id: String,
	context: Dictionary
) -> void:
	_play_feedback(
		_actor_profile_id(enemy, PRESENTATION_ENEMY_DEFAULT),
		VFX_CUES.ENEMY_ATTACK_IMPACT,
		context
	)


func _assign_enemy_spawn_serial(enemy: Node) -> void:
	if enemy == null or not enemy.has_method("set_runtime_spawn_serial"):
		return
	enemy.call("set_runtime_spawn_serial", _next_enemy_spawn_serial)
	_next_enemy_spawn_serial += 1


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


func _load_composition_skill_definitions() -> Array[Dictionary]:
	var requested_slots: Dictionary = _dictionary_or_empty(
		_hero_composition.get("skill_slots", {})
	)
	var slot_metadata: Dictionary = {}
	for slot_definition: Dictionary in _typed_dictionary_array(
		_hero_composition.get("slot_definitions", [])
	):
		slot_metadata[String(slot_definition.get("slot_id", ""))] = slot_definition
	var all_skills: Array = _load_array(DataLoader.SKILLS_PATH, "skills")
	var result: Array[Dictionary] = []
	for slot_id: String in SKILL_SLOTS.VALUES:
		var skill_id: String = String(requested_slots.get(slot_id, ""))
		var skill: Dictionary = _find_item(all_skills, skill_id)
		if skill.is_empty():
			continue
		var metadata: Dictionary = _dictionary_or_empty(
			slot_metadata.get(slot_id, {})
		)
		skill["slot_id"] = slot_id
		skill["cost_multiplier"] = float(
			metadata.get(
				"energy_cost_multiplier",
				metadata.get("cost_multiplier", 1.0)
			)
		)
		skill["cooldown_multiplier"] = float(
			metadata.get("cooldown_multiplier", 1.0)
		)
		result.append(skill)
	return result


func _element_damage_taken_multipliers(passive_id: String) -> Dictionary:
	var passive: Dictionary = _find_item(
		_load_array(DataLoader.HERO_PASSIVES_PATH, "passives"),
		passive_id
	)
	if (
		passive.is_empty()
		or String(passive.get("effect", ""))
		!= EFFECTS.ELEMENT_DAMAGE_TAKEN_MULTIPLIER
	):
		return {}
	var params: Dictionary = _dictionary_or_empty(passive.get("params", {}))
	var element_id: String = String(params.get("element_id", ""))
	if not ELEMENTS.VALUES.has(element_id):
		return {}
	return {
		element_id: clampf(float(params.get("multiplier", 1.0)), 0.0, 1.0),
	}


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
			"presentation_profile_id": String(
				row.get("presentation_profile_id", "")
			),
			"max_hp": String(row.get("max_hp", "1")).to_int(),
			"move_speed": String(row.get("move_speed", "0.0")).to_float(),
			"gold_value_multiplier": String(
				row.get("gold_value_multiplier", "0.0")
			).to_float(),
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
			"element_id": String(row.get("element_id", "")),
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
		var enemy_id: String = String(row.get("enemy_id", ""))
		if not _is_content_available(CONTENT_UNLOCK_TYPES.ENEMY, enemy_id):
			continue
		result.append({
			"id": String(row.get("id", "")),
			"start_time": String(row.get("start_time", "0.0")).to_float(),
			"end_time": String(row.get("end_time", "0.0")).to_float(),
			"enemy_id": enemy_id,
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


func _refresh_gold_hud() -> void:
	if _hud != null:
		_hud.call(
			"set_gold_progress",
			gold_balance(),
			current_level_gold(),
			current_level_gold_required()
		)


func _update_combat_hud() -> void:
	if (
		_hud == null
		or not is_instance_valid(_hud)
		or _player == null
		or not is_instance_valid(_player)
	):
		return
	if _hud.has_method("set_defense"):
		_hud.call(
			"set_defense",
			float(_player.call("current_life")),
			float(_player.call("max_life")),
			float(_player.call("current_shield"))
			if _player.has_method("current_shield")
			else 0.0,
			float(_player.call("max_shield"))
			if _player.has_method("max_shield")
			else 0.0,
			float(_player.call("current_overshield"))
			if _player.has_method("current_overshield")
			else 0.0
		)
	if _skill_system != null and is_instance_valid(_skill_system):
		if (
			_hud.has_method("set_energy")
			and _skill_system.has_method("resource_amount")
			and _skill_system.has_method("resource_maximum")
		):
			_hud.call(
				"set_energy",
				float(
					_skill_system.call(
						"resource_amount",
						SKILL_RESOURCES.ENERGY
					)
				),
				float(
					_skill_system.call(
						"resource_maximum",
						SKILL_RESOURCES.ENERGY
					)
				)
			)
		if (
			_hud.has_method("set_skill_slots")
			and _skill_system.has_method("debug_summary")
		):
			var skill_summary: Dictionary = _skill_system.call(
				"debug_summary"
			) as Dictionary
			_hud.call(
				"set_skill_slots",
				skill_summary.get("skill_slots", []),
				skill_summary
			)
	if _hud.has_method("set_dash") and _player.has_method(
		"dash_cooldown_remaining"
	):
		_hud.call(
			"set_dash",
			float(_player.call("dash_cooldown_remaining"))
		)
	if _hud.has_method("set_statuses"):
		_hud.call("set_statuses", _hud_status_summary())


func _hud_status_summary() -> Array[Dictionary]:
	var merged_statuses: Dictionary = {}
	if _player != null and _player.has_method("status_summary"):
		_merge_hud_statuses(
			merged_statuses,
			_player.call("status_summary")
		)
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if (
			not _is_active_world_entity(enemy)
			or not enemy.has_method("status_summary")
		):
			continue
		_merge_hud_statuses(
			merged_statuses,
			enemy.call("status_summary")
		)
	var status_ids: Array[String] = []
	for raw_status_id: Variant in merged_statuses.keys():
		status_ids.append(String(raw_status_id))
	status_ids.sort()
	var result: Array[Dictionary] = []
	for status_id: String in status_ids:
		result.append(
			(merged_statuses[status_id] as Dictionary).duplicate(true)
		)
	return result


func _merge_hud_statuses(
	merged_statuses: Dictionary,
	raw_statuses: Variant
) -> void:
	if not raw_statuses is Array:
		return
	for raw_status: Variant in raw_statuses as Array:
		if not raw_status is Dictionary:
			continue
		var status: Dictionary = raw_status as Dictionary
		var status_id: String = String(status.get("id", ""))
		if status_id.is_empty():
			continue
		if not merged_statuses.has(status_id):
			merged_statuses[status_id] = status.duplicate(true)
			continue
		var existing: Dictionary = merged_statuses[status_id] as Dictionary
		existing["stacks"] = maxi(
			int(existing.get("stacks", 1)),
			int(status.get("stacks", 1))
		)
		existing["remaining"] = maxf(
			float(existing.get("remaining", 0.0)),
			float(status.get("remaining", 0.0))
		)
		merged_statuses[status_id] = existing


func _composition_display_name() -> String:
	var characters: Array = _load_array(DataLoader.CHARACTERS_PATH, "characters")
	var main_character: Dictionary = _find_item(characters, _main_hero_id)
	var sub_character: Dictionary = _find_item(characters, _sub_hero_id)
	return tr("character_composition_name_format").format({
		"main": tr(String(main_character.get("name_key", _main_hero_id))),
		"sub": tr(String(sub_character.get("name_key", _sub_hero_id))),
	})


func _composition_color(color_key: String, fallback: Color) -> Color:
	var palette: Dictionary = _dictionary_or_empty(
		_hero_composition.get("palette", {})
	)
	var encoded: String = String(palette.get(color_key, ""))
	if not encoded.is_empty() and Color.html_is_valid(encoded):
		return Color.from_string(encoded, fallback)
	return fallback


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
		"level": "%d" % current_level(),
		"gold_balance": "%d" % gold_balance(),
		"gold_earned_total": "%d" % gold_earned_total(),
		"level_progress": "%d/%d" % [
			current_level_gold(),
			current_level_gold_required(),
		],
		"kills": "%d" % _kills,
		"run_time": "%ds" % int(_difficulty_elapsed()),
		"enemy_health_multiplier": "%sx" % _format_stat_value(
			float(_difficulty_snapshot().get("health_multiplier", 1.0))
		),
		"enemy_damage_multiplier": "%sx" % _format_stat_value(
			float(_difficulty_snapshot().get("damage_multiplier", 1.0))
		),
		"damage": _format_stat_value(_weapon_stat(STATS.DAMAGE)),
		"health_regen": "%s/s" % _format_stat_value(_player_stat(STATS.HEALTH_REGEN)),
		"shield": "%d/%d" % [
			int(ceilf(float(_player.call("current_shield")))),
			int(ceilf(float(_player.call("max_shield")))),
		],
		"overshield": "%d" % int(
			ceilf(float(_player.call("current_overshield")))
		),
		"energy": _skill_resource_text(),
		"armor": _format_stat_value(_player_stat(STATS.ARMOR)),
		"ability_strength": _format_percent(
			_player_stat(STATS.ABILITY_STRENGTH)
		),
		"ability_range": _format_percent(
			_player_stat(STATS.ABILITY_RANGE)
		),
		"ability_efficiency": _format_percent(
			_player_stat(STATS.ABILITY_EFFICIENCY)
		),
		"ability_duration": _format_percent(
			_player_stat(STATS.ABILITY_DURATION)
		),
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
	if resource_id == SKILL_RESOURCES.ENERGY:
		return tr("skill_resource_energy_name")
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


func _choice_ids(choices: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for choice: Dictionary in choices:
		result.append(String(choice.get("id", "")))
	return result


func _damage_info(amount: float, target: Node) -> RefCounted:
	return DAMAGE_INFO_SCRIPT.new().setup(
		amount,
		ELEMENTS.ELEMENT_NEUTRAL,
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
		ELEMENTS.ELEMENT_NEUTRAL,
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


func _initialize_content_availability(restore_snapshot: Dictionary) -> bool:
	if _is_debug_test_arena():
		_content_availability = {}
		return true
	var source: Dictionary = {}
	if not restore_snapshot.is_empty():
		if not restore_snapshot.get("content_availability", {}) is Dictionary:
			return false
		source = _dictionary_or_empty(
			restore_snapshot.get("content_availability", {})
		)
	elif not _configured_content_availability.is_empty():
		source = _configured_content_availability.duplicate(true)
	else:
		source = ContentUnlockSystem.build_run_availability_snapshot()
	_content_availability = _normalize_content_availability(source)
	return (
		_available_content_ids(CONTENT_UNLOCK_TYPES.CHARACTER).size() >= 2
		and not _available_content_ids(CONTENT_UNLOCK_TYPES.GEAR_MOD).is_empty()
		and not _available_content_ids(CONTENT_UNLOCK_TYPES.ENEMY).is_empty()
	)


func _normalize_content_availability(raw_value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for content_type: String in CONTENT_UNLOCK_TYPES.VALUES:
		var ids: Array[String] = []
		var raw_ids: Variant = raw_value.get(content_type, [])
		if not raw_ids is Array:
			result[content_type] = ids
			continue
		for raw_id: Variant in raw_ids as Array:
			var content_id: String = String(raw_id).strip_edges()
			if content_id.is_empty() or ids.has(content_id):
				continue
			ids.append(content_id)
		ids.sort()
		result[content_type] = ids
	return result


func _available_content_ids(content_type: String) -> Array[String]:
	if _is_debug_test_arena():
		return []
	var result: Array[String] = []
	var raw_ids: Variant = _content_availability.get(content_type, [])
	if not raw_ids is Array:
		return result
	for raw_id: Variant in raw_ids as Array:
		var content_id: String = String(raw_id)
		if not content_id.is_empty():
			result.append(content_id)
	return result


func _is_content_available(content_type: String, content_id: String) -> bool:
	if _is_debug_test_arena():
		return true
	return (
		not content_id.is_empty()
		and _available_content_ids(content_type).has(content_id)
	)


func _empty_content_progress_delta() -> Dictionary:
	return {
		CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_ENDED: 0,
		CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_COMPLETED: 0,
		CONTENT_UNLOCK_PROGRESS_COUNTERS.CHARACTER_RUN_COMPLETED: {},
		CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED_TOTAL: 0,
		CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED: {},
	}


func _normalize_content_progress_delta(raw_value: Dictionary) -> Dictionary:
	var result: Dictionary = _empty_content_progress_delta()
	result[CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_ENDED] = maxi(
		int(raw_value.get(CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_ENDED, 0)),
		0
	)
	result[CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_COMPLETED] = maxi(
		int(raw_value.get(CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_COMPLETED, 0)),
		0
	)
	result[CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED_TOTAL] = maxi(
		int(
			raw_value.get(
				CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED_TOTAL,
				0
			)
		),
		0
	)
	for grouped_counter: String in [
		CONTENT_UNLOCK_PROGRESS_COUNTERS.CHARACTER_RUN_COMPLETED,
		CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED,
	]:
		var normalized_counts: Dictionary = {}
		var raw_counts: Variant = raw_value.get(grouped_counter, {})
		if raw_counts is Dictionary:
			for raw_subject_id: Variant in (raw_counts as Dictionary).keys():
				var subject_id: String = String(raw_subject_id).strip_edges()
				var count: int = maxi(
					int((raw_counts as Dictionary).get(raw_subject_id, 0)),
					0
				)
				if not subject_id.is_empty() and count > 0:
					normalized_counts[subject_id] = count
		result[grouped_counter] = normalized_counts
	return result


func _record_enemy_defeated_progress(enemy: Node) -> void:
	if _is_debug_test_arena():
		return
	var enemy_id: String = ""
	if enemy != null and enemy.has_method("enemy_id"):
		enemy_id = String(enemy.call("enemy_id"))
	elif enemy != null and enemy.has_meta("enemy_id"):
		enemy_id = String(enemy.get_meta("enemy_id"))
	_content_progress_delta[
		CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED_TOTAL
	] = int(
		_content_progress_delta.get(
			CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED_TOTAL,
			0
		)
	) + 1
	if enemy_id.is_empty():
		return
	var enemy_counts: Dictionary = _dictionary_or_empty(
		_content_progress_delta.get(
			CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED,
			{}
		)
	)
	enemy_counts[enemy_id] = int(enemy_counts.get(enemy_id, 0)) + 1
	_content_progress_delta[
		CONTENT_UNLOCK_PROGRESS_COUNTERS.ENEMY_DEFEATED
	] = enemy_counts


func _commit_content_progress(completed: bool) -> Dictionary:
	_content_progress_delta[CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_ENDED] = int(
		_content_progress_delta.get(
			CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_ENDED,
			0
		)
	) + 1
	if completed:
		_content_progress_delta[
			CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_COMPLETED
		] = int(
			_content_progress_delta.get(
				CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_COMPLETED,
				0
			)
		) + 1
		var hero_counts: Dictionary = _dictionary_or_empty(
			_content_progress_delta.get(
				CONTENT_UNLOCK_PROGRESS_COUNTERS.CHARACTER_RUN_COMPLETED,
				{}
			)
		)
		for hero_id: String in [_main_hero_id, _sub_hero_id]:
			if not hero_id.is_empty():
				hero_counts[hero_id] = int(hero_counts.get(hero_id, 0)) + 1
		_content_progress_delta[
			CONTENT_UNLOCK_PROGRESS_COUNTERS.CHARACTER_RUN_COMPLETED
		] = hero_counts
	if (
		_is_debug_test_arena()
		or not _content_progress_commits_enabled
		or InputService.playback_active()
	):
		return {}
	var result: Dictionary = ContentUnlockSystem.commit_run_progress(
		_content_progress_delta
	)
	if not bool(result.get("saved", false)):
		push_error("[GameplayRunLoop] content progression commit failed")
		return {}
	return _dictionary_or_empty(result.get("newly_unlocked", {}))


func _is_debug_test_arena() -> bool:
	return _run_purpose == RunPurpose.DEBUG_TEST_ARENA


func _gold_failure(reason: String, amount: int) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"amount": amount,
		"gold_balance": gold_balance(),
		"gold_earned_total": gold_earned_total(),
		"old_level": current_level(),
		"new_level": current_level(),
		"levels_gained": 0,
	}


func _debug_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}
