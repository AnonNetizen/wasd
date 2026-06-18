# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/正式项目工作规划.md F4
class_name F4RunLoop
extends Node2D


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const GAME_MODES := preload("res://scripts/contracts/game_modes.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const F4_BULLET_SCRIPT := preload("res://scripts/gameplay/f4_bullet.gd")
const F4_BACKGROUND_SCRIPT := preload("res://scripts/gameplay/f4_background.gd")
const F4_ENEMY_SCRIPT := preload("res://scripts/gameplay/f4_enemy.gd")
const F4_HUD_SCRIPT := preload("res://scripts/gameplay/f4_hud.gd")
const F4_PLAYER_SCRIPT := preload("res://scripts/gameplay/f4_player.gd")
const F4_WEAPON_SYSTEM_SCRIPT := preload("res://scripts/gameplay/f4_weapon_system.gd")

const BULLET_POOL_SIZE: int = 192
const ENEMY_POOL_SIZE: int = 96

var _active_world: Node2D = null
var _enemy_rows: Dictionary = {}
var _hud: CanvasLayer = null
var _kills: int = 0
var _player: CharacterBody2D = null
var _spawn_states: Dictionary = {}
var _waves: Array[Dictionary] = []


func _ready() -> void:
	_ensure_input_actions()
	_start_run()


func _process(_delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return
	_update_spawner()


func _unhandled_input(event: InputEvent) -> void:
	if GameState.is_state(GameState.GAME_OVER) and event.is_action_pressed(ACTIONS.PAUSE):
		GameState.change_state(GameState.LOADING)
		get_tree().reload_current_scene()


func _start_run() -> void:
	GameClock.reset()
	PoolManager.clear_pool(POOL_IDS.BULLET_BASIC)
	PoolManager.clear_pool(POOL_IDS.ENEMY_CHASER)
	PoolManager.register_pool(POOL_IDS.BULLET_BASIC, _create_bullet_node, BULLET_POOL_SIZE)
	PoolManager.register_pool(POOL_IDS.ENEMY_CHASER, _create_enemy_node, ENEMY_POOL_SIZE)
	PoolManager.prewarm(POOL_IDS.BULLET_BASIC, 24)
	PoolManager.prewarm(POOL_IDS.ENEMY_CHASER, 12)

	_active_world = Node2D.new()
	_active_world.name = "F4ActiveWorld"
	add_child(_active_world)

	var mode: Dictionary = _find_item(_load_array(DataLoader.GAME_MODES_PATH, "modes"), GAME_MODES.MODE_STANDARD_SURVIVAL)
	var character: Dictionary = _find_item(_load_array(DataLoader.CHARACTERS_PATH, "characters"), CHARACTER_IDS.CHARACTER_DEFAULT)
	var player_stats: Dictionary = _merged_player_stats(character, mode)
	var loadout: Dictionary = character.get("starting_loadout", {})
	var weapon: Dictionary = _find_item(_load_array(DataLoader.WEAPONS_PATH, "weapons"), String(loadout.get("weapon_id", "")))

	_enemy_rows = _load_enemy_rows()
	_waves = _load_waves(GAME_MODES.MODE_STANDARD_SURVIVAL)
	_spawn_states.clear()

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

	var weapon_system: Node = F4_WEAPON_SYSTEM_SCRIPT.new()
	weapon_system.name = "WeaponSystem"
	_player.add_child(weapon_system)
	weapon_system.call("configure", _player, _active_world, weapon)

	_hud = F4_HUD_SCRIPT.new()
	add_child(_hud)
	_hud.call("set_life", _player.call("current_life"), _player.call("max_life"))
	_hud.call("set_kills", _kills)

	GameState.change_state(GameState.PLAYING, {
		"mode": GAME_MODES.MODE_STANDARD_SURVIVAL,
		"character": CHARACTER_IDS.CHARACTER_DEFAULT,
	})


func _create_bullet_node() -> Node:
	return F4_BULLET_SCRIPT.new()


func _create_enemy_node() -> Node:
	return F4_ENEMY_SCRIPT.new()


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
	if _spawn_states.has(wave_key):
		var state: Dictionary = _spawn_states[wave_key]
		state["alive"] = maxi(int(state.get("alive", 0)) - 1, 0)
		_spawn_states[wave_key] = state


func _on_player_life_changed(current_life: float, max_life: float) -> void:
	if _hud != null:
		_hud.call("set_life", current_life, max_life)


func _on_player_died() -> void:
	GameState.change_state(GameState.GAME_OVER, {
		"kills": _kills,
		"run_time": GameClock.now(),
	})
	if _hud != null:
		_hud.call("show_game_over")


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
