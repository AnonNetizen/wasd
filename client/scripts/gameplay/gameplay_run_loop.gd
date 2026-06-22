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

const BULLET_POOL_SIZE: int = 192
const ENEMY_POOL_SIZE: int = 96
const FEEDBACK_POOL_SIZE: int = 128
const PICKUP_POOL_SIZE: int = 128
const RUN_SNAPSHOT_SCHEMA_VERSION: int = 1
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
var _hud: CanvasLayer = null
var _kills: int = 0
var _level_panel: CanvasLayer = null
var _last_settlement: Dictionary = {}
var _pending_level_up_choices: Array[Dictionary] = []
var _pending_restore_snapshot: Dictionary = {}
var _pause_menu: CanvasLayer = null
var _player: CharacterBody2D = null
var _settings_panel: CanvasLayer = null
var _spawn_states: Dictionary = {}
var _waves: Array[Dictionary] = []
var _weapon_system: Node = null


func _ready() -> void:
	_ensure_input_actions()
	_start_run(_pending_restore_snapshot)


func _exit_tree() -> void:
	if Combat.damage_applied.is_connected(_on_combat_damage_applied):
		Combat.damage_applied.disconnect(_on_combat_damage_applied)


func _process(_delta: float) -> void:
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
		"spawn_states": _spawn_states.duplicate(true),
		"player": _player.call("snapshot") if _player != null and _player.has_method("snapshot") else {},
		"weapon": _weapon_system.call("snapshot") if _weapon_system != null and _weapon_system.has_method("snapshot") else {},
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
	PoolManager.clear_pool(POOL_IDS.HIT_SPARK)
	PoolManager.clear_pool(POOL_IDS.DAMAGE_NUMBER)
	PoolManager.clear_pool(POOL_IDS.PICKUP_ORB)
	PoolManager.register_pool(POOL_IDS.BULLET_BASIC, _create_bullet_node, BULLET_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.ENEMY_CHASER, _create_enemy_node, ENEMY_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.ENEMY_SWARM, _create_enemy_node, ENEMY_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.HIT_SPARK, _create_hit_spark_node, FEEDBACK_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.DAMAGE_NUMBER, _create_damage_number_node, FEEDBACK_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.PICKUP_ORB, _create_pickup_orb_node, PICKUP_POOL_SIZE)
	PoolManager.prewarm(POOL_IDS.BULLET_BASIC, 24)
	PoolManager.prewarm(POOL_IDS.ENEMY_CHASER, 12)
	PoolManager.prewarm(POOL_IDS.ENEMY_SWARM, 8)
	PoolManager.prewarm(POOL_IDS.HIT_SPARK, 16)
	PoolManager.prewarm(POOL_IDS.DAMAGE_NUMBER, 16)
	PoolManager.prewarm(POOL_IDS.PICKUP_ORB, 16)
	if not Combat.damage_applied.is_connected(_on_combat_damage_applied):
		Combat.damage_applied.connect(_on_combat_damage_applied)

	_active_world = get_node_or_null("ActiveWorld") as Node2D
	if _active_world == null:
		push_error("[GameplayRunLoop] missing ActiveWorld scene node")
		return

	var mode: Dictionary = _find_item(_load_array(DataLoader.GAME_MODES_PATH, "modes"), GAME_MODES.MODE_STANDARD_SURVIVAL)
	var character: Dictionary = _find_item(_load_array(DataLoader.CHARACTERS_PATH, "characters"), CHARACTER_IDS.CHARACTER_DEFAULT)
	var player_stats: Dictionary = _merged_player_stats(character, mode)
	var loadout: Dictionary = character.get("starting_loadout", {})
	var weapon: Dictionary = _find_item(_load_array(DataLoader.WEAPONS_PATH, "weapons"), String(loadout.get("weapon_id", "")))

	_enemy_rows = _load_enemy_rows(_load_enemy_ai_profiles())
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
	_player.connect("life_changed", Callable(self, "_on_player_life_changed"))
	_player.connect("died", Callable(self, "_on_player_died"), CONNECT_ONE_SHOT)

	var background: Node2D = _active_world.get_node_or_null("WorldBackground") as Node2D
	if background == null:
		push_error("[GameplayRunLoop] missing WorldBackground scene node")
		return
	background.call("configure", _player)

	_weapon_system = _player.get_node_or_null("WeaponSystem")
	if _weapon_system == null:
		push_error("[GameplayRunLoop] missing WeaponSystem scene node")
		return
	_weapon_system.call("configure", _player, _active_world, weapon)
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


func _create_bullet_node() -> Node:
	return BULLET_SCENE.instantiate()


func _create_enemy_node() -> Node:
	return ENEMY_SCENE.instantiate()


func _create_hit_spark_node() -> Node:
	return HIT_SPARK_SCENE.instantiate()


func _create_damage_number_node() -> Node:
	return DAMAGE_NUMBER_SCENE.instantiate()


func _create_pickup_orb_node() -> Node:
	return PICKUP_ORB_SCENE.instantiate()


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
	enemy.connect("defeated", Callable(self, "_on_enemy_defeated").bind(wave_key), CONNECT_ONE_SHOT)
	return true


func _spawn_position() -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var radius: float = maxf(viewport_size.x, viewport_size.y) * 0.55
	var angle: float = RNG.spawn.randf_range(0.0, TAU)
	return _player.global_position + Vector2.RIGHT.rotated(angle) * radius


func _reparent_to_active_world(node: Node) -> void:
	var old_parent: Node = node.get_parent()
	if old_parent == _active_world:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	_active_world.add_child(node)


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

	if _player != null and _player.has_method("restore_snapshot") and snapshot_data.get("player", {}) is Dictionary:
		_player.call("restore_snapshot", snapshot_data.get("player", {}) as Dictionary)
	if _weapon_system != null and _weapon_system.has_method("restore_snapshot") and snapshot_data.get("weapon", {}) is Dictionary:
		_weapon_system.call("restore_snapshot", snapshot_data.get("weapon", {}) as Dictionary)

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
		if enemy.has_method("restore_snapshot"):
			enemy.call("restore_snapshot", snapshot_data)
		enemy.connect("defeated", Callable(self, "_on_enemy_defeated").bind(wave_key), CONNECT_ONE_SHOT)


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


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _load_array(path: String, key: String) -> Array:
	var data: Variant = DataLoader.load_json(path)
	if not data is Dictionary:
		return []
	var raw_items: Variant = (data as Dictionary).get(key, [])
	return raw_items if raw_items is Array else []


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


func _parse_tag_list(raw_value: Variant) -> Array[String]:
	var tags: Array[String] = []
	for raw_tag: String in String(raw_value).split("|", false):
		var tag: String = raw_tag.strip_edges()
		if not tag.is_empty():
			tags.append(tag)
	return tags


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
