# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/正式项目工作规划.md F4
class_name F4RunLoop
extends Node2D


signal quit_to_title_requested()
signal restart_requested()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const GAME_MODES := preload("res://scripts/contracts/game_modes.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const F4_BULLET_SCRIPT := preload("res://scripts/gameplay/f4_bullet.gd")
const F4_BACKGROUND_SCRIPT := preload("res://scripts/gameplay/f4_background.gd")
const F4_ENEMY_SCRIPT := preload("res://scripts/gameplay/f4_enemy.gd")
const F4_HUD_SCRIPT := preload("res://scripts/gameplay/f4_hud.gd")
const F4_GAME_OVER_PANEL_SCRIPT := preload("res://scripts/ui/f4_game_over_panel.gd")
const F4_LEVEL_UP_PANEL_SCRIPT := preload("res://scripts/gameplay/f4_level_up_panel.gd")
const F4_PAUSE_MENU_SCRIPT := preload("res://scripts/ui/f4_pause_menu.gd")
const F4_PICKUP_ORB_SCRIPT := preload("res://scripts/gameplay/f4_pickup_orb.gd")
const F4_PLAYER_SCRIPT := preload("res://scripts/gameplay/f4_player.gd")
const F4_WEAPON_SYSTEM_SCRIPT := preload("res://scripts/gameplay/f4_weapon_system.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const BULLET_POOL_SIZE: int = 192
const ENEMY_POOL_SIZE: int = 96
const PICKUP_POOL_SIZE: int = 128
const RUN_SNAPSHOT_SCHEMA_VERSION: int = 1

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
var _pending_restore_snapshot: Dictionary = {}
var _pause_menu: CanvasLayer = null
var _player: CharacterBody2D = null
var _spawn_states: Dictionary = {}
var _waves: Array[Dictionary] = []
var _weapon_system: Node = null


func _ready() -> void:
	_ensure_input_actions()
	_start_run(_pending_restore_snapshot)


func _process(_delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return
	_update_spawner()


func _unhandled_input(event: InputEvent) -> void:
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
		"enemies": _entity_snapshots("f4_enemies"),
		"bullets": _entity_snapshots("f4_bullets"),
		"pickups": _entity_snapshots("f4_pickups"),
	}


func _start_run(restore_snapshot: Dictionary = {}) -> void:
	GameClock.reset()
	PoolManager.clear_pool(POOL_IDS.BULLET_BASIC)
	PoolManager.clear_pool(POOL_IDS.ENEMY_CHASER)
	PoolManager.clear_pool(POOL_IDS.ENEMY_SWARM)
	PoolManager.clear_pool(POOL_IDS.PICKUP_ORB)
	PoolManager.register_pool(POOL_IDS.BULLET_BASIC, _create_bullet_node, BULLET_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.ENEMY_CHASER, _create_enemy_node, ENEMY_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.ENEMY_SWARM, _create_enemy_node, ENEMY_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.PICKUP_ORB, _create_pickup_orb_node, PICKUP_POOL_SIZE)
	PoolManager.prewarm(POOL_IDS.BULLET_BASIC, 24)
	PoolManager.prewarm(POOL_IDS.ENEMY_CHASER, 12)
	PoolManager.prewarm(POOL_IDS.ENEMY_SWARM, 8)
	PoolManager.prewarm(POOL_IDS.PICKUP_ORB, 16)

	_active_world = Node2D.new()
	_active_world.name = "F4ActiveWorld"
	add_child(_active_world)

	var mode: Dictionary = _find_item(_load_array(DataLoader.GAME_MODES_PATH, "modes"), GAME_MODES.MODE_STANDARD_SURVIVAL)
	var character: Dictionary = _find_item(_load_array(DataLoader.CHARACTERS_PATH, "characters"), CHARACTER_IDS.CHARACTER_DEFAULT)
	var player_stats: Dictionary = _merged_player_stats(character, mode)
	var loadout: Dictionary = character.get("starting_loadout", {})
	var weapon: Dictionary = _find_item(_load_array(DataLoader.WEAPONS_PATH, "weapons"), String(loadout.get("weapon_id", "")))

	_enemy_rows = _load_enemy_rows()
	_growth_curve = _load_growth_curve()
	_growth_entries = _load_growth_entries(mode)
	_waves = _load_waves(GAME_MODES.MODE_STANDARD_SURVIVAL)
	_spawn_states.clear()
	_current_level = 1
	_current_xp = 0
	_kills = 0

	_player = F4_PLAYER_SCRIPT.new()
	_player.name = "Player"
	_player.global_position = Vector2.ZERO
	_player.call("configure", player_stats)
	_player.connect("life_changed", Callable(self, "_on_player_life_changed"))
	_player.connect("died", Callable(self, "_on_player_died"), CONNECT_ONE_SHOT)

	var background: Node2D = F4_BACKGROUND_SCRIPT.new()
	background.name = "F4Background"
	background.call("configure", _player)
	_active_world.add_child(background)
	_active_world.add_child(_player)

	_weapon_system = F4_WEAPON_SYSTEM_SCRIPT.new()
	_weapon_system.name = "WeaponSystem"
	_player.add_child(_weapon_system)
	_weapon_system.call("configure", _player, _active_world, weapon)

	_hud = F4_HUD_SCRIPT.new()
	_hud.name = "F4Hud"
	add_child(_hud)
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


func _create_bullet_node() -> Node:
	return F4_BULLET_SCRIPT.new()


func _create_enemy_node() -> Node:
	return F4_ENEMY_SCRIPT.new()


func _create_pickup_orb_node() -> Node:
	return F4_PICKUP_ORB_SCRIPT.new()


func current_level() -> int:
	return _current_level


func current_xp() -> int:
	return _current_xp


func current_level_xp() -> int:
	return _xp_progress_for_level(_current_level)


func current_level_xp_required() -> int:
	return _xp_required_within_level(_current_level)


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
	enemy.set_meta("f4_wave_key", wave_key)
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

	var panel_template: CanvasLayer = F4_LEVEL_UP_PANEL_SCRIPT.new()
	panel_template.name = "F4LevelUpPanel"
	var panel_scene: PackedScene = PackedScene.new()
	var pack_result: Error = panel_scene.pack(panel_template)
	panel_template.free()
	if pack_result != OK:
		push_error("[F4RunLoop] failed to pack level-up panel: %d" % pack_result)
		return
	_level_panel = UIManager.push(panel_scene, {"source": "f4_level_up"}) as CanvasLayer
	if _level_panel == null:
		return
	_level_panel.call("configure", choices)
	_level_panel.connect("choice_selected", Callable(self, "_on_level_up_choice_selected"), CONNECT_ONE_SHOT)
	GameState.change_state(GameState.LEVEL_UP, {
		"level": _current_level,
		"choices": _choice_ids(choices),
	})


func _on_level_up_choice_selected(choice: Dictionary) -> void:
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
	GameState.change_state(GameState.PLAYING, {
		"level": _current_level,
		"choice": String(choice.get("id", "")),
	})
	if _can_level_up():
		_begin_level_up()


func _on_player_life_changed(current_life: float, max_life: float) -> void:
	if _hud != null:
		_hud.call("set_life", current_life, max_life)


func _on_player_died() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	GameState.change_state(GameState.GAME_OVER, {
		"kills": _kills,
		"run_time": GameClock.now(),
	})
	_show_game_over_panel()


func _show_game_over_panel() -> void:
	var panel_template: CanvasLayer = F4_GAME_OVER_PANEL_SCRIPT.new()
	panel_template.name = "F4GameOverPanel"
	var panel_scene: PackedScene = PackedScene.new()
	var pack_result: Error = panel_scene.pack(panel_template)
	panel_template.free()
	if pack_result != OK:
		push_error("[F4RunLoop] failed to pack game-over panel: %d" % pack_result)
		return
	_game_over_panel = UIManager.push(panel_scene, {"source": "f4_game_over"}) as CanvasLayer
	if _game_over_panel == null:
		return
	_game_over_panel.call("configure", _kills, GameClock.now())
	_game_over_panel.connect("restart_requested", Callable(self, "_on_game_over_restart_requested"), CONNECT_ONE_SHOT)
	_game_over_panel.connect("quit_to_title_requested", Callable(self, "_on_game_over_quit_to_title_requested"), CONNECT_ONE_SHOT)


func _on_game_over_restart_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	restart_requested.emit()


func _on_game_over_quit_to_title_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	quit_to_title_requested.emit()


func _show_pause_menu() -> void:
	var panel_template: CanvasLayer = F4_PAUSE_MENU_SCRIPT.new()
	panel_template.name = "F4PauseMenu"
	var panel_scene: PackedScene = PackedScene.new()
	var pack_result: Error = panel_scene.pack(panel_template)
	panel_template.free()
	if pack_result != OK:
		push_error("[F4RunLoop] failed to pack pause menu: %d" % pack_result)
		return
	_pause_menu = UIManager.push(panel_scene, {"source": "f4_pause"}) as CanvasLayer
	if _pause_menu == null:
		return
	_pause_menu.connect("resume_requested", Callable(self, "_on_pause_resume_requested"), CONNECT_ONE_SHOT)
	_pause_menu.connect("save_and_quit_requested", Callable(self, "_on_pause_save_and_quit_requested"), CONNECT_ONE_SHOT)
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
		push_error("[F4RunLoop] failed to save run snapshot: %s" % SaveManager.last_error())
		_on_pause_resume_requested()
		return
	quit_to_title_requested.emit()


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
		if group_name == "f4_enemies" and node.has_meta("f4_wave_key"):
			snapshot_data["wave_key"] = String(node.get_meta("f4_wave_key"))
		result.append(snapshot_data)
	return result


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
		enemy.set_meta("f4_wave_key", wave_key)
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


func _load_enemy_rows() -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in DataLoader.load_csv(DataLoader.ENEMIES_PATH):
		var requested_id: String = String(row.get("id", ""))
		if requested_id.is_empty():
			continue
		result[requested_id] = {
			"id": requested_id,
			"pool_id": String(row.get("pool_id", "")),
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
	return choices


func _choice_ids(choices: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for choice: Dictionary in choices:
		result.append(String(choice.get("id", "")))
	return result


func _ensure_input_actions() -> void:
	_ensure_key_action(ACTIONS.MOVE_UP, [KEY_W])
	_ensure_key_action(ACTIONS.MOVE_DOWN, [KEY_S])
	_ensure_key_action(ACTIONS.MOVE_LEFT, [KEY_A])
	_ensure_key_action(ACTIONS.MOVE_RIGHT, [KEY_D])
	_ensure_key_action(ACTIONS.AIM_UP, [KEY_UP])
	_ensure_key_action(ACTIONS.AIM_DOWN, [KEY_DOWN])
	_ensure_key_action(ACTIONS.AIM_LEFT, [KEY_LEFT])
	_ensure_key_action(ACTIONS.AIM_RIGHT, [KEY_RIGHT])
	_ensure_key_action(ACTIONS.PAUSE, [KEY_ESCAPE])
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
	_ensure_button_action(ACTIONS.PAUSE, JOY_BUTTON_START)


func _ensure_key_action(action_id: String, keycodes: Array[int]) -> void:
	_ensure_action(action_id)
	for keycode: int in keycodes:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		_add_event_if_missing(action_id, event)


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
