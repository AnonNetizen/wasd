# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/正式项目工作规划.md F4
class_name GameplayRunLoop
extends Node2D


signal quit_to_title_requested()
signal restart_requested()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const DAMAGE_NUMBER_SCENE := preload("res://scenes/gameplay/damage_number.tscn")
const GAME_MODES := preload("res://scripts/contracts/game_modes.gd")
const HAZARD_SCENE := preload("res://scenes/gameplay/hazard.tscn")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const BULLET_SCENE := preload("res://scenes/gameplay/bullet.tscn")
const ENEMY_SCENE := preload("res://scenes/gameplay/enemy.tscn")
const GAME_OVER_PANEL_SCENE := preload("res://scenes/ui/game_over_panel.tscn")
const HIT_SPARK_SCENE := preload("res://scenes/gameplay/hit_spark.tscn")
const LEVEL_UP_PANEL_SCENE := preload("res://scenes/ui/level_up_panel.tscn")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const PICKUP_ORB_SCENE := preload("res://scenes/gameplay/pickup_orb.tscn")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const SKILL_RESOURCES := preload("res://scripts/contracts/skill_resources.gd")
const SKILL_SYSTEM_SCRIPT := preload("res://scripts/gameplay/skill_system.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

const BULLET_POOL_SIZE: int = 192
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 80.0)
const ENEMY_POOL_SIZE: int = 96
const FEEDBACK_POOL_SIZE: int = 128
const HAZARD_POOL_SIZE: int = 32
const PICKUP_POOL_SIZE: int = 128
const RUN_SNAPSHOT_SCHEMA_VERSION: int = 2
const ACTIVE_POOL_GROUPS: Array[String] = ["active_hazards", "active_enemies", "active_bullets", "active_pickups"]
const UI_RESTORE_LEVEL_UP: String = "level_up"
const UI_RESTORE_PAUSED: String = "paused"
const UI_RESTORE_PLAYING: String = "playing"
const UI_RESTORE_UNDERLYING_STATE: String = "underlying_state"
const REPLAY_PARTICIPANT_ID: String = "player_0"

var _active_world: Node2D = null
var _current_level: int = 1
var _current_xp: int = 0
var _enemy_rows: Dictionary = {}
var _growth_curve: Array[Dictionary] = []
var _growth_entries: Array[Dictionary] = []
var _game_over_panel: CanvasLayer = null
var _hazard_rows: Dictionary = {}
var _hud: CanvasLayer = null
var _kills: int = 0
var _level_panel: CanvasLayer = null
var _last_settlement: Dictionary = {}
var _pending_level_up_choices: Array[Dictionary] = []
var _pending_restore_snapshot: Dictionary = {}
var _pause_menu: CanvasLayer = null
var _player: CharacterBody2D = null
var _map_layout: Dictionary = {}
var _map_manager: Node2D = null
var _settings_panel: CanvasLayer = null
var _skill_system: Node = null
var _spawn_states: Dictionary = {}
var _waves: Array[Dictionary] = []
var _weapon_system: Node = null


func _ready() -> void:
	_ensure_input_actions()
	_start_run(_pending_restore_snapshot)


func _exit_tree() -> void:
	_release_active_world_pool_entities()
	if Combat.damage_applied.is_connected(_on_combat_damage_applied):
		Combat.damage_applied.disconnect(_on_combat_damage_applied)


func _process(_delta: float) -> void:
	_update_stats_panel()
	if not GameState.is_state(GameState.PLAYING):
		return
	_update_spawner()


func _unhandled_input(event: InputEvent) -> void:
	Replay.record_input_event(event, [ACTIONS.PAUSE], REPLAY_PARTICIPANT_ID)

	if GameState.is_state(GameState.PLAYING) and event.is_action_pressed(ACTIONS.PAUSE):
		get_viewport().set_input_as_handled()
		_show_pause_menu()
		return
	if GameState.is_state(GameState.GAME_OVER) and event.is_action_pressed(ACTIONS.PAUSE):
		restart_requested.emit()


func configure_restore_snapshot(snapshot_data: Dictionary) -> void:
	_pending_restore_snapshot = snapshot_data.duplicate(true)


func create_run_snapshot() -> Dictionary:
	return {
		"schema_version": RUN_SNAPSHOT_SCHEMA_VERSION,
		"mode": GAME_MODES.MODE_STANDARD_SURVIVAL,
		"character": CHARACTER_IDS.CHARACTER_DEFAULT,
		"level": _current_level,
		"xp": _current_xp,
		"kills": _kills,
		"game_clock": GameClock.snapshot(),
		"rng": RNG.snapshot(),
		"map": _map_manager.call("snapshot") if _map_manager != null and _map_manager.has_method("snapshot") else {},
		"spawn_states": _spawn_states.duplicate(true),
		"player": _player.call("snapshot") if _player != null and _player.has_method("snapshot") else {},
		"weapon": _weapon_system.call("snapshot") if _weapon_system != null and _weapon_system.has_method("snapshot") else {},
		"skills": _skill_system.call("snapshot") if _skill_system != null and _skill_system.has_method("snapshot") else {},
		"hazards": _entity_snapshots("active_hazards"),
		"enemies": _entity_snapshots("active_enemies"),
		"bullets": _entity_snapshots("active_bullets"),
		"pickups": _entity_snapshots("active_pickups"),
		"ui_restore": _ui_restore_snapshot(),
	}


func _start_run(restore_snapshot: Dictionary = {}) -> void:
	GameClock.reset()
	PoolManager.clear_pool(POOL_IDS.BULLET_BASIC)
	PoolManager.clear_pool(POOL_IDS.ENEMY_CHASER)
	PoolManager.clear_pool(POOL_IDS.ENEMY_SWARM)
	PoolManager.clear_pool(POOL_IDS.HAZARD_SPIKE)
	PoolManager.clear_pool(POOL_IDS.HIT_SPARK)
	PoolManager.clear_pool(POOL_IDS.DAMAGE_NUMBER)
	PoolManager.clear_pool(POOL_IDS.PICKUP_ORB)
	PoolManager.register_pool(POOL_IDS.BULLET_BASIC, _create_bullet_node, BULLET_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.ENEMY_CHASER, _create_enemy_node, ENEMY_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.ENEMY_SWARM, _create_enemy_node, ENEMY_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.HAZARD_SPIKE, _create_hazard_node, HAZARD_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.HIT_SPARK, _create_hit_spark_node, FEEDBACK_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.DAMAGE_NUMBER, _create_damage_number_node, FEEDBACK_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.PICKUP_ORB, _create_pickup_orb_node, PICKUP_POOL_SIZE)
	PoolManager.prewarm(POOL_IDS.BULLET_BASIC, 24)
	PoolManager.prewarm(POOL_IDS.ENEMY_CHASER, 12)
	PoolManager.prewarm(POOL_IDS.ENEMY_SWARM, 8)
	PoolManager.prewarm(POOL_IDS.HAZARD_SPIKE, 8)
	PoolManager.prewarm(POOL_IDS.HIT_SPARK, 16)
	PoolManager.prewarm(POOL_IDS.DAMAGE_NUMBER, 16)
	PoolManager.prewarm(POOL_IDS.PICKUP_ORB, 16)
	if not Combat.damage_applied.is_connected(_on_combat_damage_applied):
		Combat.damage_applied.connect(_on_combat_damage_applied)

	_active_world = get_node_or_null("ActiveWorld") as Node2D
	if _active_world == null:
		push_error("[GameplayRunLoop] missing ActiveWorld scene node")
		return
	_map_manager = _active_world.get_node_or_null("MapManager") as Node2D
	if _map_manager == null:
		push_error("[GameplayRunLoop] missing MapManager scene node")
		return

	var mode: Dictionary = _find_item(_load_array(DataLoader.GAME_MODES_PATH, "modes"), GAME_MODES.MODE_STANDARD_SURVIVAL)
	var character: Dictionary = _find_item(_load_array(DataLoader.CHARACTERS_PATH, "characters"), CHARACTER_IDS.CHARACTER_DEFAULT)
	var player_stats: Dictionary = _merged_player_stats(character, mode)
	var loadout: Dictionary = character.get("starting_loadout", {})
	var weapon: Dictionary = _find_item(_load_array(DataLoader.WEAPONS_PATH, "weapons"), String(loadout.get("weapon_id", "")))

	_enemy_rows = _load_enemy_rows(_load_enemy_ai_profiles())
	_hazard_rows = _load_hazard_rows()
	_map_layout = _load_map_layout(GAME_MODES.MODE_STANDARD_SURVIVAL)
	_growth_curve = _load_growth_curve()
	_growth_entries = _load_growth_entries(mode)
	_waves = _load_waves(GAME_MODES.MODE_STANDARD_SURVIVAL)
	_spawn_states.clear()
	_current_level = 1
	_current_xp = 0
	_kills = 0
	_last_settlement.clear()

	_player = _active_world.get_node_or_null("Player") as CharacterBody2D
	if _player == null:
		push_error("[GameplayRunLoop] missing Player scene node")
		return
	_player.global_position = Vector2.ZERO
	_player.call("configure", player_stats)
	_map_manager.call("configure", _map_layout, _hazard_rows)
	var map_player_start: Vector2 = _map_manager.call("player_start")
	_player.global_position = map_player_start
	_apply_player_movement_bounds()
	_player.connect("life_changed", Callable(self, "_on_player_life_changed"))
	_player.connect("died", Callable(self, "_on_player_died"), CONNECT_ONE_SHOT)

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
	_configure_skill_system(character)
	_apply_meta_modifiers(MetaProgressionSystem.current_modifiers())

	_hud = get_node_or_null("GameplayHud") as CanvasLayer
	if _hud == null:
		push_error("[GameplayRunLoop] missing GameplayHud scene node")
		return
	_hud.call("set_life", _player.call("current_life"), _player.call("max_life"))
	_hud.call("set_kills", _kills)
	_hud.call("set_level", _current_level)
	_refresh_xp_hud()

	GameState.change_state(GameState.PLAYING, {
		"mode": GAME_MODES.MODE_STANDARD_SURVIVAL,
		"character": CHARACTER_IDS.CHARACTER_DEFAULT,
	})

	if not restore_snapshot.is_empty():
		_restore_run_snapshot(restore_snapshot)
		_restore_ui_state(restore_snapshot.get("ui_restore", {}))
	else:
		var hazard_placements: Array[Dictionary] = _map_manager.call("generate_hazard_placements", _map_layout)
		_spawn_map_hazards(hazard_placements)


func _create_bullet_node() -> Node:
	return BULLET_SCENE.instantiate()


func _create_enemy_node() -> Node:
	return ENEMY_SCENE.instantiate()


func _create_hazard_node() -> Node:
	return HAZARD_SCENE.instantiate()


func _create_hit_spark_node() -> Node:
	return HIT_SPARK_SCENE.instantiate()


func _create_damage_number_node() -> Node:
	return DAMAGE_NUMBER_SCENE.instantiate()


func _create_pickup_orb_node() -> Node:
	return PICKUP_ORB_SCENE.instantiate()


func _configure_skill_system(character: Dictionary) -> void:
	if _skill_system != null and is_instance_valid(_skill_system):
		_skill_system.queue_free()
	_skill_system = SKILL_SYSTEM_SCRIPT.new()
	_skill_system.name = "SkillSystem"
	add_child(_skill_system)
	var loadout: Dictionary = character.get("starting_loadout", {}) if character.get("starting_loadout", {}) is Dictionary else {}
	_skill_system.call(
		"configure",
		_player,
		_active_world,
		_load_skill_definitions(loadout),
		_typed_dictionary_array(character.get("skill_resources", []))
	)


func current_level() -> int:
	return _current_level


func current_xp() -> int:
	return _current_xp


func current_level_xp() -> int:
	return _xp_progress_for_level(_current_level)


func current_level_xp_required() -> int:
	return _xp_required_within_level(_current_level)


func debug_summary() -> Dictionary:
	return {
		"level": _current_level,
		"xp": _current_xp,
		"level_xp": current_level_xp(),
		"level_xp_required": current_level_xp_required(),
		"kills": _kills,
		"player_life": float(_player.call("current_life")) if _player != null and _player.has_method("current_life") else 0.0,
		"player_max_life": float(_player.call("max_life")) if _player != null and _player.has_method("max_life") else 0.0,
		"active_enemies": _active_enemy_count(),
		"active_hazards": PoolManager.active_count(POOL_IDS.HAZARD_SPIKE),
		"map": _map_manager.call("debug_summary") if _map_manager != null and _map_manager.has_method("debug_summary") else {},
		"skills": _skill_system.call("debug_summary") if _skill_system != null and _skill_system.has_method("debug_summary") else {},
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


func debug_cast_primary_skill() -> Dictionary:
	if _skill_system == null or not _skill_system.has_method("cast_primary_skill"):
		return _debug_result(false, "skill_system_unavailable")
	return _skill_system.call("cast_primary_skill") as Dictionary


func _update_spawner() -> void:
	var elapsed: float = GameClock.now()
	for wave: Dictionary in _waves:
		if elapsed < float(wave.get("start_time", 0.0)) or elapsed > float(wave.get("end_time", 0.0)):
			continue
		var wave_key: String = String(wave.get("id", ""))
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
	enemy.call("configure", enemy_data, _player)
	_apply_enemy_movement_bounds(enemy)
	_connect_enemy_defeated(enemy, wave_key)
	return true


func _spawn_map_hazards(placements: Array[Dictionary]) -> void:
	for placement: Dictionary in placements:
		_spawn_hazard(placement)


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
	hazard.call("configure", hazard_data, _player, _map_grid_cell_size())
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
			PoolManager.release(root_node)
			return


func _on_enemy_defeated(_enemy: Node, _exp_reward: int, wave_key: String) -> void:
	var defeated_by_player: bool = true
	if _enemy != null and _enemy.has_method("was_defeated_by_player"):
		defeated_by_player = bool(_enemy.call("was_defeated_by_player"))
	if defeated_by_player:
		_kills += 1
		if _hud != null:
			_hud.call("set_kills", _kills)
		if _enemy is Node2D and _exp_reward > 0:
			_spawn_pickup_orb((_enemy as Node2D).global_position, _exp_reward)
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
	var collected_callback: Callable = Callable(self, "_on_pickup_orb_collected")
	if not pickup_orb.is_connected("collected", collected_callback):
		pickup_orb.connect("collected", collected_callback, CONNECT_ONE_SHOT)


func _on_pickup_orb_collected(amount: int) -> void:
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
	_spawn_hit_spark(target_2d.global_position)
	_spawn_damage_number(target_2d.global_position + Vector2.UP * 18.0, amount, defeated, player_damage)


func _spawn_hit_spark(spawn_position: Vector2) -> void:
	var raw_node: Node = PoolManager.acquire(POOL_IDS.HIT_SPARK)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return
	var hit_spark: Node2D = raw_node as Node2D
	_reparent_to_active_world(hit_spark)
	hit_spark.call("configure", spawn_position)


func _spawn_damage_number(spawn_position: Vector2, amount: float, defeated: bool, player_damage: bool) -> void:
	var raw_node: Node = PoolManager.acquire(POOL_IDS.DAMAGE_NUMBER)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return
	var damage_number: Node2D = raw_node as Node2D
	_reparent_to_active_world(damage_number)
	damage_number.call("configure", spawn_position, amount, defeated, player_damage)


func _on_player_died() -> void:
	_last_settlement = MetaProgressionSystem.apply_run_settlement(_run_settlement_summary())
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	GameState.change_state(GameState.GAME_OVER, {
		"kills": _kills,
		"run_time": GameClock.now(),
		"settlement": _last_settlement.duplicate(true),
	})
	_show_game_over_panel()


func _show_game_over_panel() -> void:
	_game_over_panel = UIManager.push(GAME_OVER_PANEL_SCENE, {"source": "game_over"}) as CanvasLayer
	if _game_over_panel == null:
		return
	_game_over_panel.call("configure", _kills, GameClock.now(), _last_settlement)
	_game_over_panel.connect("restart_requested", Callable(self, "_on_game_over_restart_requested"), CONNECT_ONE_SHOT)
	_game_over_panel.connect("quit_to_title_requested", Callable(self, "_on_game_over_quit_to_title_requested"), CONNECT_ONE_SHOT)


func _on_game_over_restart_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	restart_requested.emit()


func _on_game_over_quit_to_title_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	quit_to_title_requested.emit()


func _run_settlement_summary() -> Dictionary:
	return {
		"kills": _kills,
		"run_time": GameClock.now(),
		"first_boss_defeated": false,
	}


func _apply_meta_modifiers(modifiers: Array[Dictionary]) -> void:
	if modifiers.is_empty():
		return
	if _player != null and _player.has_method("apply_modifiers"):
		_player.call("apply_modifiers", modifiers)
	if _weapon_system != null and _weapon_system.has_method("apply_modifiers"):
		_weapon_system.call("apply_modifiers", modifiers)


func _show_pause_menu() -> void:
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


func _is_active_world_entity(node: Node) -> bool:
	if node == null or _active_world == null:
		return false
	return node == _active_world or _active_world.is_ancestor_of(node)


func _restore_run_snapshot(snapshot_data: Dictionary) -> void:
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
	if hazard_snapshots.is_empty() and _map_manager != null and _map_manager.has_method("generate_hazard_placements"):
		var hazard_placements: Array[Dictionary] = _map_manager.call("generate_hazard_placements", _map_layout)
		_spawn_map_hazards(hazard_placements)
	else:
		_restore_hazard_snapshots(hazard_snapshots)
	_restore_enemy_snapshots(_array_or_empty(snapshot_data.get("enemies", [])))
	_restore_bullet_snapshots(_array_or_empty(snapshot_data.get("bullets", [])))
	_restore_pickup_snapshots(_array_or_empty(snapshot_data.get("pickups", [])))

	var clock_snapshot: Variant = snapshot_data.get("game_clock", {})
	if clock_snapshot is Dictionary:
		GameClock.restore_snapshot(clock_snapshot as Dictionary)

	if _hud != null:
		_hud.call("set_life", _player.call("current_life"), _player.call("max_life"))
		_hud.call("set_kills", _kills)
		_hud.call("set_level", _current_level)
	_refresh_xp_hud()


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
		}
		var restored_snapshot: Dictionary = snapshot_data.duplicate(true)
		restored_snapshot["position"] = restored_position_data
		var hazard: Node2D = _spawn_hazard(placement)
		if hazard != null and hazard.has_method("restore_snapshot"):
			hazard.call("restore_snapshot", restored_snapshot)


func _restore_enemy_snapshots(enemy_snapshots: Array) -> void:
	for raw_snapshot: Variant in enemy_snapshots:
		if not raw_snapshot is Dictionary:
			continue
		var snapshot_data: Dictionary = raw_snapshot as Dictionary
		var enemy_id: String = String(snapshot_data.get("enemy_id", ""))
		if not _enemy_rows.has(enemy_id):
			continue
		var enemy_data: Dictionary = _enemy_rows[enemy_id]
		var pool_id: String = String(enemy_data.get("pool_id", ""))
		var raw_node: Node = PoolManager.acquire(pool_id)
		if not raw_node is Node2D or not raw_node.has_method("configure"):
			continue

		var enemy: Node2D = raw_node as Node2D
		_reparent_to_active_world(enemy)
		var wave_key: String = String(snapshot_data.get("wave_key", ""))
		enemy.set_meta("wave_key", wave_key)
		enemy.call("configure", enemy_data, _player)
		_apply_enemy_movement_bounds(enemy)
		if enemy.has_method("restore_snapshot"):
			enemy.call("restore_snapshot", snapshot_data)
		_connect_enemy_defeated(enemy, wave_key)


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
		var collected_callback: Callable = Callable(self, "_on_pickup_orb_collected")
		if not pickup_orb.is_connected("collected", collected_callback):
			pickup_orb.connect("collected", collected_callback, CONNECT_ONE_SHOT)


func _apply_enemy_movement_bounds(enemy: Node2D) -> void:
	if _map_manager == null or not _map_manager.has_method("bounds"):
		return
	if not enemy.has_method("set_movement_bounds"):
		return
	enemy.call("set_movement_bounds", _map_manager.call("bounds"))
	if (
		enemy.has_method("set_movement_diamond_boundary")
		and _map_manager.has_method("boundary_center")
		and _map_manager.has_method("boundary_half_extents")
	):
		enemy.call("set_movement_diamond_boundary", _map_manager.call("boundary_center"), _map_manager.call("boundary_half_extents"))


func _apply_player_movement_bounds() -> void:
	if _player == null or _map_manager == null or not _map_manager.has_method("bounds"):
		return
	if _player.has_method("set_movement_bounds"):
		_player.call("set_movement_bounds", _map_manager.call("bounds"))
	if (
		_player.has_method("set_movement_diamond_boundary")
		and _map_manager.has_method("boundary_center")
		and _map_manager.has_method("boundary_half_extents")
	):
		_player.call("set_movement_diamond_boundary", _map_manager.call("boundary_center"), _map_manager.call("boundary_half_extents"))


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


func _load_enemy_rows(ai_profiles: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in DataLoader.load_csv(DataLoader.ENEMIES_PATH):
		var requested_id: String = String(row.get("id", ""))
		if requested_id.is_empty():
			continue
		var ai_profile_id: String = String(row.get("ai_profile_id", ""))
		result[requested_id] = {
			"id": requested_id,
			"tags": _parse_tag_list(row.get("tags")),
			"pool_id": String(row.get("pool_id", "")),
			"ai_profile_id": ai_profile_id,
			"ai_profile": ai_profiles.get(ai_profile_id, {}),
			"max_hp": String(row.get("max_hp", "1")).to_int(),
			"move_speed": String(row.get("move_speed", "0.0")).to_float(),
			"contact_damage": String(row.get("contact_damage", "0")).to_int(),
			"contact_damage_type": String(row.get("contact_damage_type", "")),
			"exp_reward": String(row.get("exp_reward", "0")).to_int(),
			"hit_radius": String(row.get("hit_radius", "1.0")).to_float(),
			"separation_radius": String(row.get("separation_radius", "0.0")).to_float(),
			"visual_color": String(row.get("visual_color", "#ff6152")),
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
	return _current_xp >= _xp_required_for_level(_current_level + 1)


func _refresh_xp_hud() -> void:
	if _hud != null:
		_hud.call("set_xp", current_level_xp(), current_level_xp_required())


func _update_stats_panel() -> void:
	if _hud == null or not _hud.has_method("set_stats_panel_visible"):
		return
	var should_show: bool = GameState.is_state(GameState.PLAYING) and Input.is_action_pressed(ACTIONS.SHOW_STATS_PANEL)
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


func _ensure_input_actions() -> void:
	_ensure_axis_action(ACTIONS.MOVE_LEFT, JOY_AXIS_LEFT_X, -1.0)
	_ensure_axis_action(ACTIONS.MOVE_RIGHT, JOY_AXIS_LEFT_X, 1.0)
	_ensure_axis_action(ACTIONS.MOVE_UP, JOY_AXIS_LEFT_Y, -1.0)
	_ensure_axis_action(ACTIONS.MOVE_DOWN, JOY_AXIS_LEFT_Y, 1.0)
	_ensure_axis_action(ACTIONS.AIM_LEFT, JOY_AXIS_RIGHT_X, -1.0)
	_ensure_axis_action(ACTIONS.AIM_RIGHT, JOY_AXIS_RIGHT_X, 1.0)
	_ensure_axis_action(ACTIONS.AIM_UP, JOY_AXIS_RIGHT_Y, -1.0)
	_ensure_axis_action(ACTIONS.AIM_DOWN, JOY_AXIS_RIGHT_Y, 1.0)
	_ensure_button_action(ACTIONS.AIM_UP, JOY_BUTTON_DPAD_UP)
	_ensure_button_action(ACTIONS.AIM_DOWN, JOY_BUTTON_DPAD_DOWN)
	_ensure_button_action(ACTIONS.AIM_LEFT, JOY_BUTTON_DPAD_LEFT)
	_ensure_button_action(ACTIONS.AIM_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_ensure_button_action(ACTIONS.USE_ACTIVE_ITEM, JOY_BUTTON_A)
	_ensure_button_action(ACTIONS.PAUSE, JOY_BUTTON_START)
	_ensure_button_action(ACTIONS.UI_CONFIRM, JOY_BUTTON_A)
	_ensure_button_action(ACTIONS.UI_BACK, JOY_BUTTON_B)


func _ensure_axis_action(action_id: String, axis: JoyAxis, axis_value: float) -> void:
	_ensure_action(action_id)
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	_add_event_if_missing(action_id, event)


func _ensure_button_action(action_id: String, button: JoyButton) -> void:
	_ensure_action(action_id)
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	_add_event_if_missing(action_id, event)


func _ensure_action(action_id: String) -> void:
	if not InputMap.has_action(action_id):
		InputMap.add_action(action_id)


func _add_event_if_missing(action_id: String, event: InputEvent) -> void:
	if not InputMap.action_has_event(action_id, event):
		InputMap.action_add_event(action_id, event)


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


func _active_enemy_count() -> int:
	var result: int = 0
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if _is_active_world_entity(enemy):
			result += 1
	return result


func _debug_result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}
