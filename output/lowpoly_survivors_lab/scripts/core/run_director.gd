class_name LowpolyRunDirector
extends Node3D

signal state_changed(previous: int, current: int)
signal health_changed(current: float, maximum: float)
signal experience_changed(current: int, required: int, level: int)
signal upgrade_requested(options: Array[Dictionary])
signal boss_spawned(enemy: LowpolyEnemy)
signal boss_health_changed(current: float, maximum: float)
signal run_finished(victory: bool, summary: Dictionary)
signal time_changed(elapsed: float, remaining: float)
signal kill_count_changed(count: int)
signal weapon_levels_changed(snapshot: Dictionary)
signal audio_cue_requested(cue: StringName)
signal player_roster_changed(snapshot: Array[Dictionary])
signal network_upgrade_requested(slot: int, user_id: String, options: Array[Dictionary])
signal network_upgrade_progress(pending_slots: Array[int])

enum RunState {
	MENU,
	RUNNING,
	LEVEL_UP,
	PAUSED,
	VICTORY,
	DEFEAT,
}

const BALANCE_PATH: String = "res://data/balance.json"
const REGULAR_ENEMY_IDS: Array[StringName] = [
	&"enemy_small", &"enemy_flying", &"enemy_large", &"enemy_fox_mech"
]

@export_file("*.json") var balance_path: String = BALANCE_PATH

var _state: RunState = RunState.MENU
var _balance: LowpolyBalanceLoader
var _run_config: Dictionary = {}
var _network_config: Dictionary = {}
var _player: LowpolyPlayer
var _weapon_system: LowpolyWeaponSystem
var _actors: Node3D
var _projectiles: Node3D
var _pickups: Node3D
var _effects: Node3D
var _enemy_pools: Dictionary = {}
var _player_projectile_pool: LowpolyObjectPool
var _enemy_projectile_pool: LowpolyObjectPool
var _pickup_pool: LowpolyObjectPool
var _effect_pool: LowpolyObjectPool
var _spatial_grid: LowpolySpatialGrid = LowpolySpatialGrid.new(4.0)
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _run_seed: int = 0
var _elapsed: float = 0.0
var _spawn_accumulator: float = 0.0
var _level: int = 1
var _experience: int = 0
var _experience_required: int = 8
var _kills: int = 0
var _upgrade_options: Array[Dictionary] = []
var _elite_spawned: Array[bool] = [false, false, false]
var _boss: LowpolyEnemy
var _boss_started: bool = false
var _dying_enemies: Array[LowpolyEnemy] = []
var _initialized: bool = false
var _base_player: LowpolyPlayer
var _base_weapon_system: LowpolyWeaponSystem
var _players_by_slot: Dictionary = {}
var _weapon_systems_by_slot: Dictionary = {}
var _user_to_slot: Dictionary = {}
var _local_slot: int = 0
var _network_mode: bool = false
var _network_authority: bool = true
var _difficulty_players: int = 1
var _network_inputs: Dictionary = {}
var _upgrade_options_by_slot: Dictionary = {}
var _pending_upgrade_slots: Dictionary = {}
var _next_network_entity_id: int = 1
var _authority_tick: int = 0
var _network_entity_ticks: Dictionary = {}
var _network_removed_entity_ticks: Dictionary = {}
var _touch_input: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not initialize():
		push_error("Lowpoly Survivors core initialization failed: %s" % "; ".join(_balance.get_errors()))


func _physics_process(delta: float) -> void:
	if _state != RunState.RUNNING:
		return
	if _network_mode:
		return
	var hardware_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var input_vector := (
		hardware_input
		if hardware_input.length_squared() >= _touch_input.length_squared()
		else _touch_input
	).limit_length(1.0)
	simulate_step(delta, input_vector)


func initialize() -> bool:
	if _initialized:
		return true
	_balance = LowpolyBalanceLoader.new()
	if not _balance.load_balance(balance_path):
		return false
	_run_config = _balance.get_run_config()
	_network_config = _balance.get_network_config()
	_create_containers()
	_create_player_and_weapons()
	_create_pools()
	_player.visible = false
	_initialized = true
	return true


func start_run(seed: int = -1) -> void:
	if not initialize():
		return
	_network_mode = false
	_network_authority = true
	_difficulty_players = 1
	_local_slot = 0
	_restore_offline_roster()
	_reset_run(seed)


func set_touch_input(value: Vector2) -> void:
	_touch_input = value.limit_length(1.0)


func start_network_run(match_data: Dictionary, local_user_id: String, authority: bool) -> bool:
	if not initialize():
		return false
	var roster: Array = match_data.get("roster", [])
	if roster.is_empty() or roster.size() > 4:
		return false
	if not _setup_network_roster(roster, local_user_id):
		return false
	_network_mode = true
	_network_authority = authority
	_difficulty_players = clampi(int(match_data.get("difficulty_players", roster.size())), 1, 4)
	_reset_run(int(match_data.get("seed", int(_run_config.get("fixed_test_seed", 47013)))))
	return true


func _reset_run(seed: int = -1) -> void:
	_release_all_entities()
	_touch_input = Vector2.ZERO
	_run_seed = seed if seed >= 0 else int(_run_config.get("fixed_test_seed", 47013))
	_rng.seed = _run_seed
	_authority_tick = 0
	_next_network_entity_id = 1
	_network_entity_ticks.clear()
	_network_removed_entity_ticks.clear()
	_elapsed = 0.0
	_spawn_accumulator = 0.0
	_level = 1
	_experience = 0
	_kills = 0
	_elite_spawned = [false, false, false]
	_boss = null
	_boss_started = false
	_upgrade_options.clear()
	_upgrade_options_by_slot.clear()
	_pending_upgrade_slots.clear()
	_experience_required = _required_experience_for_level(_level)
	var player_config := _balance.get_player_config()
	for slot_value: Variant in _players_by_slot.keys():
		var slot := int(slot_value)
		var run_player := _players_by_slot[slot] as LowpolyPlayer
		if run_player == null:
			continue
		run_player.max_health = float(player_config.get("max_health", 100.0))
		run_player.reset_for_run()
		var angle := TAU * float(slot) / float(maxi(_players_by_slot.size(), 1))
		run_player.global_position = Vector3(cos(angle), 0.0, sin(angle)) * (2.0 if _players_by_slot.size() > 1 else 0.0)
		var system := _weapon_systems_by_slot.get(slot) as LowpolyWeaponSystem
		if system != null:
			system.reset()
	_set_state(RunState.RUNNING)
	health_changed.emit(_player.health, _player.max_health)
	experience_changed.emit(_experience, _experience_required, _level)
	time_changed.emit(_elapsed, float(_run_config.get("duration_seconds", 600.0)))
	kill_count_changed.emit(_kills)
	weapon_levels_changed.emit(_weapon_system.get_levels())
	player_roster_changed.emit(get_player_roster_snapshot())
	boss_health_changed.emit(0.0, 0.0)


func restart_run() -> void:
	if _network_mode:
		_reset_run(_run_seed)
	else:
		start_run(_run_seed)


func return_to_menu() -> void:
	_release_all_entities()
	_touch_input = Vector2.ZERO
	for run_player: LowpolyPlayer in _all_players():
		run_player.set_run_active(false)
		run_player.visible = false
	_network_mode = false
	_network_authority = true
	_restore_offline_roster()
	_set_state(RunState.MENU)


func toggle_pause() -> void:
	if _network_mode:
		return
	if _state == RunState.RUNNING:
		_player.set_run_active(false)
		_set_state(RunState.PAUSED)
	elif _state == RunState.PAUSED:
		_player.set_run_active(true)
		_set_state(RunState.RUNNING)


func choose_upgrade(upgrade_id: StringName) -> bool:
	if _network_mode:
		return choose_network_upgrade(_local_slot, upgrade_id)
	if _state != RunState.LEVEL_UP:
		return false
	var available: bool = false
	for option: Dictionary in _upgrade_options:
		if StringName(option.get("id", "")) == upgrade_id:
			available = true
			break
	if not available or not _weapon_system.apply_upgrade(upgrade_id):
		return false
	_upgrade_options.clear()
	weapon_levels_changed.emit(_weapon_system.get_levels())
	if _experience >= _experience_required:
		_experience -= _experience_required
		_level += 1
		_experience_required = _required_experience_for_level(_level)
		experience_changed.emit(_experience, _experience_required, _level)
		if _experience >= _experience_required:
			_request_level_up()
		else:
			_player.set_run_active(true)
			_set_state(RunState.RUNNING)
	else:
		_player.set_run_active(true)
		_set_state(RunState.RUNNING)
	return true


func choose_network_upgrade(slot: int, upgrade_id: StringName) -> bool:
	if not _network_mode or not _network_authority or _state != RunState.LEVEL_UP:
		return false
	if not _pending_upgrade_slots.has(slot):
		return false
	var options: Array = _upgrade_options_by_slot.get(slot, [])
	var available := false
	for value: Variant in options:
		if value is Dictionary and StringName((value as Dictionary).get("id", "")) == upgrade_id:
			available = true
			break
	var system := _weapon_systems_by_slot.get(slot) as LowpolyWeaponSystem
	if not available or system == null or not system.apply_upgrade(upgrade_id):
		return false
	_pending_upgrade_slots.erase(slot)
	_upgrade_options_by_slot.erase(slot)
	if slot == _local_slot:
		_upgrade_options.clear()
		weapon_levels_changed.emit(system.get_levels())
	network_upgrade_progress.emit(_pending_slot_array())
	if _pending_upgrade_slots.is_empty():
		_complete_team_level_up()
	return true


func get_network_upgrade_options(slot: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in _upgrade_options_by_slot.get(slot, []):
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


func set_network_player_connected(user_id: String, connected: bool) -> bool:
	if not _user_to_slot.has(user_id):
		return false
	var slot := int(_user_to_slot[user_id])
	var run_player := _players_by_slot.get(slot) as LowpolyPlayer
	if run_player == null or run_player.network_removed:
		return false
	run_player.set_network_connected(connected)
	player_roster_changed.emit(get_player_roster_snapshot())
	return true


func remove_network_player(user_id: String) -> bool:
	if not _user_to_slot.has(user_id):
		return false
	var slot := int(_user_to_slot[user_id])
	var run_player := _players_by_slot.get(slot) as LowpolyPlayer
	if run_player == null:
		return false
	run_player.remove_network_slot()
	_pending_upgrade_slots.erase(slot)
	_upgrade_options_by_slot.erase(slot)
	player_roster_changed.emit(get_player_roster_snapshot())
	network_upgrade_progress.emit(_pending_slot_array())
	if _state == RunState.LEVEL_UP and _pending_upgrade_slots.is_empty():
		_complete_team_level_up()
	elif _state == RunState.RUNNING and _all_remaining_players_dead():
		_finish_run(false)
	return true


func predict_local_player(delta: float, input_vector: Vector2) -> void:
	if not _network_mode or _network_authority or _state != RunState.RUNNING:
		return
	if is_instance_valid(_player) and _player.is_combat_available():
		_player.update_movement(delta, input_vector)


func get_player_for_slot(slot: int) -> LowpolyPlayer:
	return _players_by_slot.get(slot) as LowpolyPlayer


func get_slot_for_user(user_id: String) -> int:
	return int(_user_to_slot.get(user_id, -1))


func get_local_slot() -> int:
	return _local_slot


func is_network_mode() -> bool:
	return _network_mode


func is_network_authority() -> bool:
	return _network_authority


func set_network_authority(value: bool) -> void:
	_network_authority = value


func get_player_roster_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var slots: Array = _players_by_slot.keys()
	slots.sort()
	for slot_value: Variant in slots:
		var run_player := _players_by_slot[slot_value] as LowpolyPlayer
		if run_player == null:
			continue
		var state := run_player.make_network_state()
		var system := _weapon_systems_by_slot.get(slot_value) as LowpolyWeaponSystem
		state["weapon_levels"] = system.get_levels() if system != null else {}
		result.append(state)
	return result


func simulate_step(delta: float, input_vector: Vector2 = Vector2.ZERO) -> void:
	if _state != RunState.RUNNING or delta <= 0.0:
		return
	_simulate_authority_step(delta, {_local_slot: input_vector})


func simulate_network_step(delta: float, inputs_by_slot: Dictionary) -> void:
	if not _network_mode or not _network_authority or _state != RunState.RUNNING or delta <= 0.0:
		return
	_simulate_authority_step(delta, inputs_by_slot)


func _simulate_authority_step(delta: float, inputs_by_slot: Dictionary) -> void:
	_authority_tick += 1
	var duration: float = float(_run_config.get("duration_seconds", 600.0))
	_elapsed = minf(_elapsed + delta, duration)
	_process_timeline_events()
	_update_regular_spawning(delta)
	for slot_value: Variant in _players_by_slot.keys():
		var slot := int(slot_value)
		var run_player := _players_by_slot[slot] as LowpolyPlayer
		if run_player != null and run_player.is_combat_available():
			var raw_input: Variant = inputs_by_slot.get(slot, Vector2.ZERO)
			var movement := raw_input as Vector2 if raw_input is Vector2 else Vector2.ZERO
			run_player.update_movement(delta, movement)
	_rebuild_spatial_grid()
	_update_enemies(delta)
	_rebuild_spatial_grid()
	for system_value: Variant in _weapon_systems_by_slot.values():
		var system := system_value as LowpolyWeaponSystem
		if system != null:
			system.update_weapons(delta)
	_update_projectiles(delta)
	_update_pickups(delta)
	_update_effects(delta)
	_update_dying_enemies(delta)
	time_changed.emit(_elapsed, maxf(duration - _elapsed, 0.0))


func force_test_time(seconds: float) -> void:
	if _state != RunState.RUNNING:
		return
	_elapsed = clampf(seconds, 0.0, float(_run_config.get("duration_seconds", 600.0)))
	_process_timeline_events()
	time_changed.emit(
		_elapsed,
		maxf(float(_run_config.get("duration_seconds", 600.0)) - _elapsed, 0.0)
	)


func get_state() -> RunState:
	return _state


func get_player() -> LowpolyPlayer:
	return _player


func get_upgrade_options() -> Array[Dictionary]:
	return _upgrade_options.duplicate(true)


func get_debug_snapshot() -> Dictionary:
	return {
		"state": int(_state),
		"seed": _run_seed,
		"elapsed": _elapsed,
		"kills": _kills,
		"level": _level,
		"experience": _experience,
		"regular_enemies": _regular_enemy_count(),
		"dying_enemies": _dying_enemies.size(),
		"enemy_projectiles": _enemy_projectile_pool.get_active_count(),
		"player_projectiles": _player_projectile_pool.get_active_count(),
		"pickups": _pickup_pool.get_active_count(),
		"effects": _effect_pool.get_active_count(),
		"boss_started": _boss_started,
		"boss_active": is_instance_valid(_boss) and _boss.active,
		"weapon_levels": _weapon_system.get_levels(),
		"upgrade_options": get_upgrade_options(),
		"network_mode": _network_mode,
		"network_authority": _network_authority,
		"authority_tick": _authority_tick,
		"difficulty_players": _difficulty_players,
		"players": get_player_roster_snapshot(),
		"pending_upgrade_slots": _pending_slot_array(),
	}


func get_network_tuning() -> Dictionary:
	return _network_config.duplicate(true)


func make_network_snapshot(
	interest_center: Vector3 = Vector3.ZERO,
	interest_radius: float = 62.0
) -> Dictionary:
	var radius_squared := interest_radius * interest_radius
	var enemies: Array[Dictionary] = []
	for enemy: LowpolyEnemy in _active_enemies():
		if enemy.boss or enemy.global_position.distance_squared_to(interest_center) <= radius_squared:
			enemies.append(_quantize_spatial_state(enemy.make_network_state()))
	var player_projectiles: Array[Dictionary] = []
	for node: Node in _player_projectile_pool.get_active_nodes():
		var projectile := node as LowpolyProjectile
		if projectile != null and projectile.global_position.distance_squared_to(interest_center) <= radius_squared:
			player_projectiles.append(_quantize_spatial_state(projectile.make_network_state()))
	var enemy_projectiles: Array[Dictionary] = []
	for node: Node in _enemy_projectile_pool.get_active_nodes():
		var projectile := node as LowpolyProjectile
		if projectile != null and projectile.global_position.distance_squared_to(interest_center) <= radius_squared:
			enemy_projectiles.append(_quantize_spatial_state(projectile.make_network_state()))
	var pickups: Array[Dictionary] = []
	for node: Node in _pickup_pool.get_active_nodes():
		var pickup := node as LowpolyExperiencePickup
		if pickup != null and pickup.global_position.distance_squared_to(interest_center) <= radius_squared:
			pickups.append(_quantize_spatial_state(pickup.make_network_state()))
	var players: Array[Dictionary] = []
	for state: Dictionary in get_player_roster_snapshot():
		players.append(_quantize_spatial_state(state))
	return {
		"tick": _authority_tick,
		"seed": _run_seed,
		"state": int(_state),
		"elapsed": snappedf(_elapsed, 0.01),
		"level": _level,
		"experience": _experience,
		"experience_required": _experience_required,
		"kills": _kills,
		"boss_started": _boss_started,
		"boss_entity_id": _boss.network_entity_id if is_instance_valid(_boss) else 0,
		"players": players,
		"enemies": enemies,
		"player_projectiles": player_projectiles,
		"enemy_projectiles": enemy_projectiles,
		"pickups": pickups,
		"pending_upgrade_slots": _pending_slot_array(),
	}


func apply_network_snapshot(snapshot: Dictionary, local_player_immediate: bool = false) -> bool:
	if not _apply_network_snapshot_header(snapshot, local_player_immediate):
		return false
	_reconcile_enemy_states(snapshot.get("enemies", []))
	_reconcile_projectile_states(snapshot.get("player_projectiles", []), _player_projectile_pool, LowpolyProjectile.Team.PLAYER)
	_reconcile_projectile_states(snapshot.get("enemy_projectiles", []), _enemy_projectile_pool, LowpolyProjectile.Team.ENEMY)
	_reconcile_pickup_states(snapshot.get("pickups", []))
	_emit_network_snapshot_signals()
	return true


func apply_network_core_snapshot(snapshot: Dictionary, local_player_immediate: bool = false) -> bool:
	if not _apply_network_snapshot_header(snapshot, local_player_immediate):
		return false
	_emit_network_snapshot_signals()
	return true


func apply_network_entity_batch(category: StringName, raw_states: Variant, tick: int) -> bool:
	if not _network_mode or _network_authority or not raw_states is Array or tick < 0:
		return false
	if category not in [&"enemies", &"player_projectiles", &"enemy_projectiles", &"pickups"]:
		return false
	for value: Variant in raw_states:
		if not value is Dictionary:
			continue
		var state: Dictionary = value
		var entity_id := int(state.get("entity_id", 0))
		if (
			entity_id <= 0
			or tick < int(_network_entity_ticks.get(entity_id, -1))
			or tick <= int(_network_removed_entity_ticks.get(entity_id, -1))
		):
			continue
		_network_removed_entity_ticks.erase(entity_id)
		match category:
			&"enemies":
				var enemy := _find_enemy_by_network_id(entity_id)
				if enemy == null:
					enemy = _spawn_enemy_network_view(state)
				if enemy != null:
					enemy.apply_network_state(state, 0.62)
					var target_slot := int(state.get("target_slot", -1))
					if _players_by_slot.has(target_slot):
						enemy.player = _players_by_slot[target_slot] as LowpolyPlayer
					if enemy.boss:
						_boss = enemy
			&"player_projectiles":
				_apply_projectile_network_update(state, _player_projectile_pool, LowpolyProjectile.Team.PLAYER)
			&"enemy_projectiles":
				_apply_projectile_network_update(state, _enemy_projectile_pool, LowpolyProjectile.Team.ENEMY)
			&"pickups":
				var pickup := _find_pickup_by_network_id(entity_id)
				if pickup == null:
					pickup = _spawn_pickup_network_view(state)
				if pickup != null:
					pickup.apply_network_state(state)
		_network_entity_ticks[entity_id] = tick
	return true


func _apply_network_snapshot_header(snapshot: Dictionary, local_player_immediate: bool) -> bool:
	if not _network_mode or _network_authority:
		return false
	var incoming_tick := int(snapshot.get("tick", _authority_tick))
	if incoming_tick < _authority_tick:
		return false
	_authority_tick = incoming_tick
	_elapsed = float(snapshot.get("elapsed", _elapsed))
	_level = int(snapshot.get("level", _level))
	_experience = int(snapshot.get("experience", _experience))
	_experience_required = int(snapshot.get("experience_required", _experience_required))
	_kills = int(snapshot.get("kills", _kills))
	_boss_started = bool(snapshot.get("boss_started", _boss_started))
	_apply_player_states(snapshot.get("players", []), false, local_player_immediate)
	var next_state := int(snapshot.get("state", int(_state))) as RunState
	if next_state != _state:
		_set_state(next_state)
	return true


func _emit_network_snapshot_signals() -> void:
	health_changed.emit(_player.health, _player.max_health)
	experience_changed.emit(_experience, _experience_required, _level)
	time_changed.emit(_elapsed, maxf(float(_run_config.get("duration_seconds", 600.0)) - _elapsed, 0.0))
	kill_count_changed.emit(_kills)
	weapon_levels_changed.emit(_weapon_system.get_levels())


func apply_network_entity_delta(delta: Dictionary) -> bool:
	if not _network_mode or _network_authority:
		return false
	var tick := int(delta.get("tick", _authority_tick))
	for value: Variant in delta.get("spawned", []):
		if not value is Dictionary:
			continue
		var entry: Dictionary = value
		var category := String(entry.get("category", ""))
		var state: Dictionary = entry.get("state", {})
		var entity_id := int(state.get("entity_id", 0))
		if entity_id <= 0 or tick < int(_network_removed_entity_ticks.get(entity_id, -1)):
			continue
		_network_removed_entity_ticks.erase(entity_id)
		_network_entity_ticks[entity_id] = maxi(tick, int(_network_entity_ticks.get(entity_id, -1)))
		if _has_network_entity(entity_id):
			continue
		match category:
			"enemies":
				var enemy := _spawn_enemy_network_view(state)
				if enemy != null:
					enemy.apply_network_state(state)
			"player_projectiles":
				var projectile := _player_projectile_pool.acquire(
					_projectile_payload_from_state(state, LowpolyProjectile.Team.PLAYER)
				) as LowpolyProjectile
				if projectile != null:
					projectile.apply_network_state(state)
			"enemy_projectiles":
				var projectile := _enemy_projectile_pool.acquire(
					_projectile_payload_from_state(state, LowpolyProjectile.Team.ENEMY)
				) as LowpolyProjectile
				if projectile != null:
					projectile.apply_network_state(state)
			"pickups":
				_spawn_pickup_network_view(state)
	for entity_value: Variant in delta.get("removed", []):
		var entity_id := int(entity_value)
		if (
			entity_id <= 0
			or tick < int(_network_removed_entity_ticks.get(entity_id, -1))
			or tick < int(_network_entity_ticks.get(entity_id, -1))
		):
			continue
		_release_network_entity(entity_id)
		_network_removed_entity_ticks[entity_id] = tick
	return true


func apply_network_result(victory: bool, summary: Dictionary) -> bool:
	if not _network_mode or _network_authority:
		return false
	if _state == RunState.VICTORY or _state == RunState.DEFEAT:
		return true
	for run_player: LowpolyPlayer in _all_players():
		run_player.set_run_active(false)
	_set_state(RunState.VICTORY if victory else RunState.DEFEAT)
	run_finished.emit(victory, summary.duplicate(true))
	return true


func make_authority_checkpoint() -> Dictionary:
	var weapons: Dictionary = {}
	for slot_value: Variant in _weapon_systems_by_slot.keys():
		var system := _weapon_systems_by_slot[slot_value] as LowpolyWeaponSystem
		if system != null:
			weapons[int(slot_value)] = system.make_checkpoint()
	var enemies: Array[Dictionary] = []
	for enemy: LowpolyEnemy in _active_enemies():
		enemies.append(enemy.make_network_state())
	var player_projectiles: Array[Dictionary] = []
	for node: Node in _player_projectile_pool.get_active_nodes():
		var projectile := node as LowpolyProjectile
		if projectile != null:
			player_projectiles.append(projectile.make_network_state())
	var enemy_projectiles: Array[Dictionary] = []
	for node: Node in _enemy_projectile_pool.get_active_nodes():
		var projectile := node as LowpolyProjectile
		if projectile != null:
			enemy_projectiles.append(projectile.make_network_state())
	var pickups: Array[Dictionary] = []
	for node: Node in _pickup_pool.get_active_nodes():
		var pickup := node as LowpolyExperiencePickup
		if pickup != null:
			pickups.append(pickup.make_network_state())
	return {
		"version": 1,
		"tick": _authority_tick,
		"rng_state": _rng.state,
		"seed": _run_seed,
		"next_entity_id": _next_network_entity_id,
		"state": int(_state),
		"elapsed": _elapsed,
		"spawn_accumulator": _spawn_accumulator,
		"level": _level,
		"experience": _experience,
		"experience_required": _experience_required,
		"kills": _kills,
		"elite_spawned": _elite_spawned.duplicate(),
		"boss_started": _boss_started,
		"boss_entity_id": _boss.network_entity_id if is_instance_valid(_boss) else 0,
		"difficulty_players": _difficulty_players,
		"players": get_player_roster_snapshot(),
		"weapons": weapons,
		"enemies": enemies,
		"player_projectiles": player_projectiles,
		"enemy_projectiles": enemy_projectiles,
		"pickups": pickups,
		"upgrade_options": _upgrade_options_by_slot.duplicate(true),
		"pending_upgrade_slots": _pending_upgrade_slots.duplicate(true),
	}


func restore_authority_checkpoint(checkpoint: Dictionary) -> bool:
	if int(checkpoint.get("version", 0)) != 1 or not _network_mode:
		return false
	_release_all_entities()
	_authority_tick = int(checkpoint.get("tick", 0))
	_run_seed = int(checkpoint.get("seed", _run_seed))
	_rng.seed = _run_seed
	_rng.state = int(checkpoint.get("rng_state", _rng.state))
	_next_network_entity_id = int(checkpoint.get("next_entity_id", 1))
	_elapsed = float(checkpoint.get("elapsed", 0.0))
	_spawn_accumulator = float(checkpoint.get("spawn_accumulator", 0.0))
	_level = int(checkpoint.get("level", 1))
	_experience = int(checkpoint.get("experience", 0))
	_experience_required = int(checkpoint.get("experience_required", 8))
	_kills = int(checkpoint.get("kills", 0))
	_elite_spawned.assign(checkpoint.get("elite_spawned", [false, false, false]))
	_boss_started = bool(checkpoint.get("boss_started", false))
	_difficulty_players = int(checkpoint.get("difficulty_players", _difficulty_players))
	_apply_player_states(checkpoint.get("players", []), true)
	var weapon_states: Dictionary = checkpoint.get("weapons", {})
	for slot_value: Variant in _weapon_systems_by_slot.keys():
		var system := _weapon_systems_by_slot[slot_value] as LowpolyWeaponSystem
		var state: Dictionary = weapon_states.get(slot_value, weapon_states.get(str(slot_value), {}))
		if system != null and not state.is_empty():
			system.restore_checkpoint(state)
	_reconcile_enemy_states(checkpoint.get("enemies", []), true)
	_reconcile_projectile_states(checkpoint.get("player_projectiles", []), _player_projectile_pool, LowpolyProjectile.Team.PLAYER, true)
	_reconcile_projectile_states(checkpoint.get("enemy_projectiles", []), _enemy_projectile_pool, LowpolyProjectile.Team.ENEMY, true)
	_reconcile_pickup_states(checkpoint.get("pickups", []), true)
	_upgrade_options_by_slot = (checkpoint.get("upgrade_options", {}) as Dictionary).duplicate(true)
	_pending_upgrade_slots = (checkpoint.get("pending_upgrade_slots", {}) as Dictionary).duplicate(true)
	_upgrade_options = get_network_upgrade_options(_local_slot)
	var boss_id := int(checkpoint.get("boss_entity_id", 0))
	_boss = _find_enemy_by_network_id(boss_id)
	_set_state(int(checkpoint.get("state", int(RunState.RUNNING))) as RunState)
	_network_authority = true
	return true


func find_nearest_enemy(position: Vector3, radius: float) -> Node3D:
	return _spatial_grid.find_nearest(position, radius)


func spawn_player_projectile(payload: Dictionary) -> bool:
	var enriched: Dictionary = payload.duplicate(true)
	enriched["team"] = LowpolyProjectile.Team.PLAYER
	enriched["network_entity_id"] = _allocate_entity_id()
	var spawned: bool = _player_projectile_pool.acquire(enriched) != null
	if spawned:
		audio_cue_requested.emit(&"laser")
	return spawned


func spawn_effect(position: Vector3, size: float, color: Color, lifetime: float) -> bool:
	return _effect_pool.acquire({
		"position": position,
		"size": maxf(size, 0.1),
		"color": color,
		"lifetime": maxf(lifetime, 0.01),
	}) != null


func damage_enemies_in_radius(position: Vector3, radius: float, damage: float) -> int:
	var hit_count: int = 0
	for node: Node3D in _spatial_grid.query_radius(position, radius):
		if node is LowpolyEnemy and (node as LowpolyEnemy).take_damage(damage):
			hit_count += 1
	return hit_count


func add_experience_for_test(amount: int) -> void:
	_add_experience(maxi(amount, 0))


func defeat_boss_for_test() -> bool:
	if not is_instance_valid(_boss) or not _boss.active:
		return false
	return _boss.take_damage(_boss.health)


func _create_containers() -> void:
	_actors = Node3D.new()
	_actors.name = "Actors"
	add_child(_actors)
	_projectiles = Node3D.new()
	_projectiles.name = "Projectiles"
	add_child(_projectiles)
	_pickups = Node3D.new()
	_pickups.name = "Pickups"
	add_child(_pickups)
	_effects = Node3D.new()
	_effects.name = "Effects"
	add_child(_effects)


func _create_player_and_weapons() -> void:
	_player = LowpolyPlayer.new()
	_player.name = "Player"
	_actors.add_child(_player)
	var player_config: Dictionary = _balance.get_player_config()
	var animation_profile := StringName(player_config.get("animation_profile", "player"))
	_player.setup(
		player_config,
		float(_run_config.get("arena_half_extent", 78.0)),
		_balance.get_weapon_config(&"pulse_rifle"),
		_balance.get_animation_config(animation_profile)
	)
	_player.set_network_identity(_allocate_entity_id(), "offline", 0)
	_player.health_changed.connect(_on_player_health_changed.bind(0))
	_player.died.connect(_on_player_died.bind(0))
	_weapon_system = LowpolyWeaponSystem.new()
	_weapon_system.name = "WeaponSystem"
	add_child(_weapon_system)
	_weapon_system.setup(self, _player, _balance, 0)
	_weapon_system.levels_changed.connect(_on_weapon_levels_changed.bind(0))
	_base_player = _player
	_base_weapon_system = _weapon_system
	_players_by_slot[0] = _player
	_weapon_systems_by_slot[0] = _weapon_system
	_user_to_slot["offline"] = 0


func _setup_network_roster(roster: Array, local_user_id: String) -> bool:
	_restore_offline_roster()
	_user_to_slot.clear()
	var found_local := false
	for value: Variant in roster:
		if not value is Dictionary:
			return false
		var member: Dictionary = value
		var slot := int(member.get("slot", -1))
		var user_id := String(member.get("user_id", ""))
		if slot < 0 or slot >= 4 or user_id.is_empty() or _user_to_slot.has(user_id):
			return false
		var run_player: LowpolyPlayer
		var system: LowpolyWeaponSystem
		if slot == 0:
			run_player = _base_player
			system = _base_weapon_system
		else:
			run_player = _create_additional_player(slot)
			system = _create_additional_weapon_system(run_player, slot)
		run_player.set_network_identity(1000 + slot, user_id, slot)
		run_player.name = "Player_%d" % slot
		_players_by_slot[slot] = run_player
		_weapon_systems_by_slot[slot] = system
		_user_to_slot[user_id] = slot
		if user_id == local_user_id:
			_local_slot = slot
			found_local = true
	if not found_local:
		return false
	_player = _players_by_slot[_local_slot] as LowpolyPlayer
	_weapon_system = _weapon_systems_by_slot[_local_slot] as LowpolyWeaponSystem
	return true


func _restore_offline_roster() -> void:
	for slot_value: Variant in _players_by_slot.keys():
		var slot := int(slot_value)
		if slot == 0:
			continue
		var extra_player := _players_by_slot[slot] as LowpolyPlayer
		if is_instance_valid(extra_player):
			extra_player.queue_free()
		var extra_system := _weapon_systems_by_slot.get(slot) as LowpolyWeaponSystem
		if is_instance_valid(extra_system):
			extra_system.queue_free()
	_players_by_slot = {0: _base_player}
	_weapon_systems_by_slot = {0: _base_weapon_system}
	_user_to_slot = {"offline": 0}
	_local_slot = 0
	_player = _base_player
	_weapon_system = _base_weapon_system
	if is_instance_valid(_base_player):
		_base_player.set_network_identity(1000, "offline", 0)


func _create_additional_player(slot: int) -> LowpolyPlayer:
	var run_player := LowpolyPlayer.new()
	_actors.add_child(run_player)
	var player_config: Dictionary = _balance.get_player_config()
	var animation_profile := StringName(player_config.get("animation_profile", "player"))
	run_player.setup(
		player_config,
		float(_run_config.get("arena_half_extent", 78.0)),
		_balance.get_weapon_config(&"pulse_rifle"),
		_balance.get_animation_config(animation_profile)
	)
	run_player.health_changed.connect(_on_player_health_changed.bind(slot))
	run_player.died.connect(_on_player_died.bind(slot))
	return run_player


func _create_additional_weapon_system(run_player: LowpolyPlayer, slot: int) -> LowpolyWeaponSystem:
	var system := LowpolyWeaponSystem.new()
	system.name = "WeaponSystem_%d" % slot
	add_child(system)
	system.setup(self, run_player, _balance, slot)
	system.levels_changed.connect(_on_weapon_levels_changed.bind(slot))
	return system


func _create_pools() -> void:
	for enemy_id: StringName in REGULAR_ENEMY_IDS + [&"final_boss"]:
		var config: Dictionary = _balance.get_enemy_config(enemy_id)
		var capacity: int = int(config.get("pool", 1))
		var pool: LowpolyObjectPool = LowpolyObjectPool.new()
		pool.setup(_create_enemy.bind(enemy_id), _actors, mini(capacity, 4), capacity)
		_enemy_pools[enemy_id] = pool
	_player_projectile_pool = LowpolyObjectPool.new()
	_player_projectile_pool.setup(
		_create_player_projectile, _projectiles, 24,
		int(_run_config.get("player_projectile_cap", 120))
	)
	_enemy_projectile_pool = LowpolyObjectPool.new()
	_enemy_projectile_pool.setup(
		_create_enemy_projectile, _projectiles, 24,
		int(_run_config.get("enemy_projectile_cap", 160))
	)
	_pickup_pool = LowpolyObjectPool.new()
	_pickup_pool.setup(_create_pickup, _pickups, 32, int(_run_config.get("pickup_cap", 400)))
	_effect_pool = LowpolyObjectPool.new()
	_effect_pool.setup(_create_effect, _effects, 12, int(_run_config.get("effect_cap", 96)))


func _create_enemy(enemy_id: StringName) -> LowpolyEnemy:
	var enemy: LowpolyEnemy = LowpolyEnemy.new()
	enemy.name = "Pooled_%s" % enemy_id
	enemy.died.connect(_on_enemy_died)
	enemy.damage_player_requested.connect(_on_enemy_damage_player_requested)
	enemy.projectile_volley_requested.connect(_on_enemy_projectile_volley_requested)
	enemy.minions_requested.connect(_on_boss_minions_requested)
	return enemy


func _create_player_projectile() -> LowpolyProjectile:
	var projectile: LowpolyProjectile = LowpolyProjectile.new()
	projectile.name = "PlayerProjectile"
	return projectile


func _create_enemy_projectile() -> LowpolyProjectile:
	var projectile: LowpolyProjectile = LowpolyProjectile.new()
	projectile.name = "EnemyProjectile"
	return projectile


func _create_pickup() -> LowpolyExperiencePickup:
	var pickup: LowpolyExperiencePickup = LowpolyExperiencePickup.new()
	pickup.name = "Pickup"
	return pickup


func _create_effect() -> LowpolyEffectEntity:
	var effect: LowpolyEffectEntity = LowpolyEffectEntity.new()
	effect.name = "Effect"
	return effect


func _set_state(next_state: RunState) -> void:
	if next_state == _state:
		return
	var previous: RunState = _state
	_state = next_state
	_set_actor_animations_paused(_state == RunState.LEVEL_UP or _state == RunState.PAUSED)
	state_changed.emit(int(previous), int(_state))


func _process_timeline_events() -> void:
	var elite_times: Array = _run_config.get("elite_times", []) as Array
	for index: int in range(mini(elite_times.size(), _elite_spawned.size())):
		if not _elite_spawned[index] and _elapsed >= float(elite_times[index]):
			_elite_spawned[index] = true
			_spawn_enemy(&"enemy_large" if index != 2 else &"enemy_fox_mech", true)
	if not _boss_started and _elapsed >= float(_run_config.get("duration_seconds", 600.0)):
		_spawn_boss()


func _update_regular_spawning(delta: float) -> void:
	if _boss_started or _regular_enemy_count() >= int(_run_config.get("regular_enemy_cap", 220)):
		return
	var stage: Dictionary = _stage_for_time(_elapsed)
	if stage.is_empty():
		return
	_spawn_accumulator += delta
	var interval: float = float(stage.get("spawn_interval", 1.0)) / (
		1.0 + float(_network_config.get("difficulty_spawn_rate_per_extra_player", 0.32)) * float(_difficulty_players - 1)
	)
	while _spawn_accumulator >= interval:
		_spawn_accumulator -= interval
		for index: int in range(int(stage.get("batch", 1))):
			if _regular_enemy_count() >= int(_run_config.get("regular_enemy_cap", 220)):
				return
			_spawn_enemy(_weighted_enemy_id(stage.get("weights", {}) as Dictionary), false)


func _spawn_enemy(
	enemy_id: StringName,
	elite: bool,
	forced_position: Variant = null,
	use_reserved_slot: bool = false
) -> LowpolyEnemy:
	var pool: LowpolyObjectPool = _enemy_pools.get(enemy_id) as LowpolyObjectPool
	if pool == null:
		return null
	if enemy_id != &"final_boss" and not elite and not use_reserved_slot:
		if pool.get_active_count() >= pool.get_capacity() - 1:
			return null
	var position: Vector3 = _random_spawn_position()
	if forced_position is Vector3:
		position = forced_position as Vector3
	var config: Dictionary = _balance.get_enemy_config(enemy_id).duplicate(true)
	if _network_mode and _difficulty_players > 1:
		config["health"] = float(config.get("health", 1.0)) * (
			1.0 + float(_network_config.get("difficulty_health_per_extra_player", 0.52)) * float(_difficulty_players - 1)
		)
		config["damage"] = float(config.get("damage", 1.0)) * (
			1.0 + float(_network_config.get("difficulty_damage_per_extra_player", 0.14)) * float(_difficulty_players - 1)
		)
	var animation_profile := StringName(config.get("animation_profile", String(enemy_id)))
	var instance: Node = pool.acquire({
		"enemy_id": enemy_id,
		"config": config,
		"animation_config": _balance.get_animation_config(animation_profile),
		"player": _first_combat_player(),
		"network_entity_id": _allocate_entity_id(),
		"target_lock_seconds": float(_network_config.get("enemy_target_lock_seconds", 0.55)),
		"elite": elite,
		"boss": enemy_id == &"final_boss",
		"position": position,
	})
	return instance as LowpolyEnemy


func _spawn_boss() -> void:
	_boss_started = true
	_boss = _spawn_enemy(&"final_boss", false)
	if _boss == null:
		_finish_run(false)
		return
	if not _boss.health_changed.is_connected(_on_boss_health_changed):
		_boss.health_changed.connect(_on_boss_health_changed)
	boss_spawned.emit(_boss)
	boss_health_changed.emit(_boss.health, _boss.max_health)


func _update_enemies(delta: float) -> void:
	var targets := _combat_players()
	for enemy: LowpolyEnemy in _active_enemies():
		enemy.choose_nearest_target(targets)
		var nearby: Array[Node3D] = _spatial_grid.query_radius(enemy.global_position, 3.0)
		enemy.update_enemy(delta, nearby)


func _update_dying_enemies(delta: float) -> void:
	for index: int in range(_dying_enemies.size() - 1, -1, -1):
		var enemy: LowpolyEnemy = _dying_enemies[index]
		if not is_instance_valid(enemy):
			_dying_enemies.remove_at(index)
			continue
		if not enemy.advance_death(delta):
			continue
		var pool: LowpolyObjectPool = _enemy_pools.get(enemy.enemy_id) as LowpolyObjectPool
		if pool != null:
			pool.release(enemy)
		_dying_enemies.remove_at(index)


func _update_projectiles(delta: float) -> void:
	for node: Node in _player_projectile_pool.get_active_nodes():
		var projectile: LowpolyProjectile = node as LowpolyProjectile
		if projectile == null:
			continue
		if not projectile.advance(delta):
			_player_projectile_pool.release(projectile)
			continue
		for target: Node3D in _spatial_grid.query_radius(projectile.global_position, 2.6):
			if not target is LowpolyEnemy:
				continue
			var enemy: LowpolyEnemy = target as LowpolyEnemy
			var hit_distance: float = projectile.hit_radius + enemy.get_collision_radius()
			if projectile.global_position.distance_squared_to(enemy.global_position) > hit_distance * hit_distance:
				continue
			if projectile.register_hit(enemy):
				enemy.take_damage(projectile.damage)
				spawn_effect(enemy.global_position + Vector3.UP * 0.5, 0.4, Color(0.2, 0.9, 1.0), 0.12)
				audio_cue_requested.emit(&"hit")
			if projectile.should_release_after_hit():
				_player_projectile_pool.release(projectile)
				break
	for node: Node in _enemy_projectile_pool.get_active_nodes():
		var projectile: LowpolyProjectile = node as LowpolyProjectile
		if projectile == null:
			continue
		if not projectile.advance(delta):
			_enemy_projectile_pool.release(projectile)
			continue
		for target_player: LowpolyPlayer in _combat_players():
			if projectile.global_position.distance_squared_to(target_player.global_position) <= 0.85 * 0.85:
				target_player.take_damage(projectile.damage, true)
				_enemy_projectile_pool.release(projectile)
				break


func _update_pickups(delta: float) -> void:
	for node: Node in _pickup_pool.get_active_nodes():
		var pickup: LowpolyExperiencePickup = node as LowpolyExperiencePickup
		if pickup == null:
			continue
		var collector := _nearest_pickup_player(pickup.global_position)
		if collector == null:
			continue
		if pickup.update_pickup(delta, collector.global_position, collector.get_pickup_radius()):
			if pickup.kind == LowpolyExperiencePickup.Kind.EXPERIENCE:
				_add_experience(pickup.amount)
			else:
				collector.heal(float(pickup.amount))
			_pickup_pool.release(pickup)
			if _state != RunState.RUNNING:
				return


func _update_effects(delta: float) -> void:
	for node: Node in _effect_pool.get_active_nodes():
		var effect: LowpolyEffectEntity = node as LowpolyEffectEntity
		if effect != null and not effect.advance(delta):
			_effect_pool.release(effect)


func _rebuild_spatial_grid() -> void:
	var nodes: Array[Node] = []
	for enemy: LowpolyEnemy in _active_enemies():
		nodes.append(enemy)
	_spatial_grid.rebuild(nodes)


func _active_enemies() -> Array[LowpolyEnemy]:
	var result: Array[LowpolyEnemy] = []
	for value: Variant in _enemy_pools.values():
		var pool: LowpolyObjectPool = value as LowpolyObjectPool
		if pool == null:
			continue
		for node: Node in pool.get_active_nodes():
			if node is LowpolyEnemy and (node as LowpolyEnemy).active:
				result.append(node as LowpolyEnemy)
	return result


func _regular_enemy_count() -> int:
	var count: int = 0
	for enemy_id: StringName in REGULAR_ENEMY_IDS:
		var pool: LowpolyObjectPool = _enemy_pools.get(enemy_id) as LowpolyObjectPool
		if pool != null:
			count += pool.get_active_count()
	return count


func _stage_for_time(time: float) -> Dictionary:
	for stage: Dictionary in _balance.get_stages():
		if time >= float(stage.get("start", 0.0)) and time < float(stage.get("end", 0.0)):
			return stage
	return {}


func _weighted_enemy_id(weights: Dictionary) -> StringName:
	var total: float = 0.0
	for value: Variant in weights.values():
		total += float(value)
	var cursor: float = _rng.randf_range(0.0, total)
	for key: Variant in weights.keys():
		cursor -= float(weights[key])
		if cursor <= 0.0:
			return StringName(key)
	return StringName(weights.keys().back())


func _random_spawn_position() -> Vector3:
	var angle: float = _rng.randf_range(0.0, TAU)
	var distance: float = _rng.randf_range(
		float(_run_config.get("spawn_min_distance", 28.0)),
		float(_run_config.get("spawn_max_distance", 48.0))
	)
	var anchor := _first_combat_player()
	var anchor_position := anchor.global_position if anchor != null else Vector3.ZERO
	var position: Vector3 = anchor_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
	var half_extent: float = float(_run_config.get("arena_half_extent", 78.0))
	position.x = clampf(position.x, -half_extent, half_extent)
	position.z = clampf(position.z, -half_extent, half_extent)
	return position


func _add_experience(amount: int) -> void:
	if amount <= 0 or _state != RunState.RUNNING:
		return
	_experience += amount
	experience_changed.emit(_experience, _experience_required, _level)
	if _experience >= _experience_required:
		_request_level_up()


func _request_level_up() -> void:
	if _network_mode:
		_request_network_level_up()
		return
	var candidates: Array[Dictionary] = _weapon_system.get_upgrade_candidates()
	_upgrade_options.clear()
	while not candidates.is_empty() and _upgrade_options.size() < 3:
		var index: int = _rng.randi_range(0, candidates.size() - 1)
		_upgrade_options.append(candidates.pop_at(index))
	if _upgrade_options.is_empty():
		_experience = mini(_experience, _experience_required - 1)
		experience_changed.emit(_experience, _experience_required, _level)
		return
	_player.set_run_active(false)
	_set_state(RunState.LEVEL_UP)
	upgrade_requested.emit(get_upgrade_options())


func _request_network_level_up() -> void:
	_upgrade_options_by_slot.clear()
	_pending_upgrade_slots.clear()
	var any_options := false
	for slot_value: Variant in _players_by_slot.keys():
		var slot := int(slot_value)
		var run_player := _players_by_slot[slot] as LowpolyPlayer
		if run_player == null or run_player.network_removed or not run_player.network_connected:
			continue
		var system := _weapon_systems_by_slot.get(slot) as LowpolyWeaponSystem
		if system == null:
			continue
		var candidates := system.get_upgrade_candidates()
		var options: Array[Dictionary] = []
		while not candidates.is_empty() and options.size() < 3:
			options.append(candidates.pop_at(_rng.randi_range(0, candidates.size() - 1)))
		if options.is_empty():
			continue
		any_options = true
		_upgrade_options_by_slot[slot] = options
		_pending_upgrade_slots[slot] = true
		if slot == _local_slot:
			_upgrade_options = options.duplicate(true)
		network_upgrade_requested.emit(slot, run_player.network_user_id, options.duplicate(true))
	if not any_options:
		_experience = mini(_experience, _experience_required - 1)
		experience_changed.emit(_experience, _experience_required, _level)
		return
	for run_player: LowpolyPlayer in _all_players():
		run_player.set_run_active(false)
	_set_state(RunState.LEVEL_UP)
	network_upgrade_progress.emit(_pending_slot_array())
	if _upgrade_options_by_slot.has(_local_slot):
		upgrade_requested.emit(get_network_upgrade_options(_local_slot))


func _complete_team_level_up() -> void:
	if _state != RunState.LEVEL_UP:
		return
	_upgrade_options.clear()
	if _experience >= _experience_required:
		_experience -= _experience_required
		_level += 1
		_experience_required = _required_experience_for_level(_level)
	experience_changed.emit(_experience, _experience_required, _level)
	if _experience >= _experience_required:
		_request_network_level_up()
		return
	for run_player: LowpolyPlayer in _all_players():
		if run_player.network_connected and not run_player.network_removed and run_player.health > 0.0:
			run_player.set_run_active(true)
	_set_state(RunState.RUNNING)


func _required_experience_for_level(level: int) -> int:
	var config: Dictionary = _balance.get_experience_config()
	var base: float = float(config.get("base_required", 8))
	var growth: float = float(config.get("growth", 1.28))
	var flat_growth: float = float(config.get("flat_growth", 3))
	return maxi(1, roundi(base * pow(growth, level - 1) + flat_growth * (level - 1)))


func _release_all_entities() -> void:
	_dying_enemies.clear()
	for value: Variant in _enemy_pools.values():
		var pool: LowpolyObjectPool = value as LowpolyObjectPool
		if pool != null:
			pool.release_all()
	if _player_projectile_pool != null:
		_player_projectile_pool.release_all()
	if _enemy_projectile_pool != null:
		_enemy_projectile_pool.release_all()
	if _pickup_pool != null:
		_pickup_pool.release_all()
	if _effect_pool != null:
		_effect_pool.release_all()


func _on_player_health_changed(current: float, maximum: float, slot: int) -> void:
	if slot == _local_slot:
		health_changed.emit(current, maximum)
	if _network_mode:
		player_roster_changed.emit(get_player_roster_snapshot())


func _on_player_died(_slot: int) -> void:
	if _state == RunState.RUNNING and _all_remaining_players_dead():
		_finish_run(false)


func _on_enemy_died(enemy: LowpolyEnemy, reward: int) -> void:
	if _state != RunState.RUNNING:
		return
	var was_boss: bool = enemy == _boss
	var death_position: Vector3 = enemy.global_position
	if not _dying_enemies.has(enemy):
		_dying_enemies.append(enemy)
	spawn_effect(death_position + Vector3.UP * 0.5, 1.0 if not was_boss else 3.0, Color(1.0, 0.4, 0.12), 0.3)
	_kills += 1
	kill_count_changed.emit(_kills)
	if was_boss:
		_finish_run(true)
	elif reward > 0:
		_pickup_pool.acquire({
			"kind": LowpolyExperiencePickup.Kind.EXPERIENCE,
			"amount": reward,
			"position": death_position,
			"network_entity_id": _allocate_entity_id(),
		})
		if _rng.randf() < 0.08:
			_pickup_pool.acquire({
				"kind": LowpolyExperiencePickup.Kind.HEALTH,
				"amount": 18,
				"position": death_position + Vector3(0.4, 0.0, 0.0),
				"network_entity_id": _allocate_entity_id(),
			})


func _set_actor_animations_paused(value: bool) -> void:
	for run_player: LowpolyPlayer in _all_players():
		run_player.set_animation_paused(value)
	for pool_value: Variant in _enemy_pools.values():
		var pool := pool_value as LowpolyObjectPool
		if pool == null:
			continue
		for node: Node in pool.get_active_nodes():
			var enemy := node as LowpolyEnemy
			if enemy != null:
				enemy.set_animation_paused(value)


func _on_enemy_damage_player_requested(target: LowpolyPlayer, amount: float) -> void:
	if _state == RunState.RUNNING and is_instance_valid(target) and target.is_combat_available():
		target.take_damage(amount)


func _on_enemy_projectile_volley_requested(
	origin: Vector3,
	direction: Vector3,
	speed: float,
	damage: float,
	count: int,
	spread_degrees: float,
	radial: bool
) -> void:
	if _state != RunState.RUNNING:
		return
	for index: int in range(count):
		var shot_direction: Vector3
		if radial:
			shot_direction = Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / float(count))
		else:
			var offset: float = float(index) - float(count - 1) * 0.5
			shot_direction = direction.rotated(Vector3.UP, deg_to_rad(offset * spread_degrees))
		_enemy_projectile_pool.acquire({
			"team": LowpolyProjectile.Team.ENEMY,
			"position": origin,
			"direction": shot_direction,
			"speed": speed,
			"damage": damage,
			"lifetime": 5.0,
			"pierce": 0,
			"network_entity_id": _allocate_entity_id(),
		})


func _on_boss_minions_requested(count: int) -> void:
	if _state != RunState.RUNNING:
		return
	for index: int in range(count):
		if _regular_enemy_count() >= int(_run_config.get("regular_enemy_cap", 220)):
			return
		var angle: float = TAU * float(index) / float(maxi(count, 1))
		var fallback_target := _first_combat_player()
		var fallback_position := fallback_target.global_position if fallback_target != null else Vector3.ZERO
		var origin: Vector3 = _boss.global_position if is_instance_valid(_boss) else fallback_position
		_spawn_enemy(
			&"enemy_small", false,
			origin + Vector3(cos(angle), 0.0, sin(angle)) * 4.0,
			true
		)


func _on_boss_health_changed(current: float, maximum: float) -> void:
	boss_health_changed.emit(current, maximum)


func _on_weapon_levels_changed(snapshot: Dictionary, slot: int) -> void:
	if slot == _local_slot:
		weapon_levels_changed.emit(snapshot)


func _all_players() -> Array[LowpolyPlayer]:
	var result: Array[LowpolyPlayer] = []
	for value: Variant in _players_by_slot.values():
		var run_player := value as LowpolyPlayer
		if run_player != null:
			result.append(run_player)
	return result


func _combat_players() -> Array[LowpolyPlayer]:
	var result: Array[LowpolyPlayer] = []
	for run_player: LowpolyPlayer in _all_players():
		if run_player.is_combat_available():
			result.append(run_player)
	return result


func _first_combat_player() -> LowpolyPlayer:
	var players := _combat_players()
	return players.front() if not players.is_empty() else null


func _nearest_pickup_player(position: Vector3) -> LowpolyPlayer:
	var nearest: LowpolyPlayer
	var nearest_distance := INF
	for run_player: LowpolyPlayer in _combat_players():
		var distance := position.distance_squared_to(run_player.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = run_player
	return nearest


func _all_remaining_players_dead() -> bool:
	var remaining := 0
	for run_player: LowpolyPlayer in _all_players():
		if run_player.network_removed:
			continue
		remaining += 1
		if run_player.health > 0.0:
			return false
	return remaining > 0


func _pending_slot_array() -> Array[int]:
	var result: Array[int] = []
	for value: Variant in _pending_upgrade_slots.keys():
		result.append(int(value))
	result.sort()
	return result


func _allocate_entity_id() -> int:
	var value := _next_network_entity_id
	_next_network_entity_id += 1
	return value


static func _quantize_spatial_state(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	for key: String in ["position", "velocity", "direction"]:
		var values: Array = result.get(key, [])
		if values.size() != 3:
			continue
		result[key] = [
			snappedf(float(values[0]), 0.01),
			snappedf(float(values[1]), 0.01),
			snappedf(float(values[2]), 0.01),
		]
	return result


func _apply_player_states(
	raw_states: Variant,
	immediate: bool = false,
	local_player_immediate: bool = false
) -> void:
	if not raw_states is Array:
		return
	for value: Variant in raw_states:
		if not value is Dictionary:
			continue
		var state: Dictionary = value
		var slot := int(state.get("slot", -1))
		var run_player := _players_by_slot.get(slot) as LowpolyPlayer
		if run_player == null:
			continue
		var weight := (
			1.0
			if immediate or (local_player_immediate and slot == _local_slot)
			else (0.36 if slot == _local_slot else 0.62)
		)
		var position_values: Array = state.get("position", [])
		if slot == _local_slot and position_values.size() == 3:
			var target := Vector3(
				float(position_values[0]), float(position_values[1]), float(position_values[2])
			)
			if run_player.global_position.distance_to(target) > 1.6:
				weight = 1.0
		run_player.apply_network_state(state, weight)
		var weapon_levels: Dictionary = state.get("weapon_levels", {})
		var system := _weapon_systems_by_slot.get(slot) as LowpolyWeaponSystem
		if system != null and not weapon_levels.is_empty():
			var current_checkpoint := system.make_checkpoint()
			current_checkpoint["levels"] = weapon_levels
			system.restore_checkpoint(current_checkpoint)


func _reconcile_enemy_states(raw_states: Variant, immediate: bool = false) -> void:
	if not raw_states is Array:
		return
	var active_by_id: Dictionary = {}
	for enemy: LowpolyEnemy in _active_enemies():
		active_by_id[enemy.network_entity_id] = enemy
	var seen: Dictionary = {}
	for value: Variant in raw_states:
		if not value is Dictionary:
			continue
		var state: Dictionary = value
		var entity_id := int(state.get("entity_id", 0))
		if entity_id <= 0:
			continue
		seen[entity_id] = true
		var enemy := active_by_id.get(entity_id) as LowpolyEnemy
		if enemy == null:
			enemy = _spawn_enemy_network_view(state)
		if enemy != null:
			enemy.apply_network_state(state, 1.0 if immediate else 0.62)
			var target_slot := int(state.get("target_slot", -1))
			if _players_by_slot.has(target_slot):
				enemy.player = _players_by_slot[target_slot] as LowpolyPlayer
			if enemy.boss:
				_boss = enemy
	for entity_value: Variant in active_by_id.keys():
		if seen.has(entity_value):
			continue
		var stale := active_by_id[entity_value] as LowpolyEnemy
		var pool := _enemy_pools.get(stale.enemy_id) as LowpolyObjectPool
		if pool != null:
			pool.release(stale)


func _spawn_enemy_network_view(state: Dictionary) -> LowpolyEnemy:
	var enemy_id := StringName(state.get("enemy_id", "enemy_small"))
	var pool := _enemy_pools.get(enemy_id) as LowpolyObjectPool
	if pool == null:
		return null
	var config := _balance.get_enemy_config(enemy_id).duplicate(true)
	var animation_profile := StringName(config.get("animation_profile", String(enemy_id)))
	var position_values: Array = state.get("position", [])
	var position := Vector3.ZERO
	if position_values.size() == 3:
		position = Vector3(float(position_values[0]), float(position_values[1]), float(position_values[2]))
	return pool.acquire({
		"enemy_id": enemy_id,
		"config": config,
		"animation_config": _balance.get_animation_config(animation_profile),
		"player": _first_combat_player(),
		"network_entity_id": int(state.get("entity_id", 0)),
		"elite": bool(state.get("elite", false)),
		"boss": bool(state.get("boss", enemy_id == &"final_boss")),
		"position": position,
	}) as LowpolyEnemy


func _reconcile_projectile_states(
	raw_states: Variant,
	pool: LowpolyObjectPool,
	team: LowpolyProjectile.Team,
	_immediate: bool = false
) -> void:
	if not raw_states is Array or pool == null:
		return
	var active_by_id: Dictionary = {}
	for node: Node in pool.get_active_nodes():
		var projectile := node as LowpolyProjectile
		if projectile != null:
			active_by_id[projectile.network_entity_id] = projectile
	var seen: Dictionary = {}
	for value: Variant in raw_states:
		if not value is Dictionary:
			continue
		var state: Dictionary = value
		var entity_id := int(state.get("entity_id", 0))
		if entity_id <= 0:
			continue
		seen[entity_id] = true
		var projectile := active_by_id.get(entity_id) as LowpolyProjectile
		if projectile == null:
			projectile = pool.acquire(_projectile_payload_from_state(state, team)) as LowpolyProjectile
		if projectile != null:
			projectile.apply_network_state(state)
	for entity_value: Variant in active_by_id.keys():
		if not seen.has(entity_value):
			pool.release(active_by_id[entity_value] as LowpolyProjectile)


func _projectile_payload_from_state(
	state: Dictionary,
	team: LowpolyProjectile.Team
) -> Dictionary:
	var position_values: Array = state.get("position", [])
	var direction_values: Array = state.get("direction", [])
	return {
		"team": team,
		"network_entity_id": int(state.get("entity_id", 0)),
		"owner_slot": int(state.get("owner_slot", -1)),
		"position": Vector3(
			float(position_values[0]), float(position_values[1]), float(position_values[2])
		) if position_values.size() == 3 else Vector3.ZERO,
		"direction": Vector3(
			float(direction_values[0]), float(direction_values[1]), float(direction_values[2])
		) if direction_values.size() == 3 else Vector3.FORWARD,
		"speed": float(state.get("speed", 10.0)),
		"damage": float(state.get("damage", 1.0)),
		"hit_radius": float(state.get("hit_radius", 0.35)),
		"lifetime": float(state.get("lifetime", 1.0)),
		"pierce": int(state.get("pierce", 0)),
	}


func _apply_projectile_network_update(
	state: Dictionary,
	pool: LowpolyObjectPool,
	team: LowpolyProjectile.Team
) -> void:
	if pool == null:
		return
	var entity_id := int(state.get("entity_id", 0))
	var projectile: LowpolyProjectile
	for node: Node in pool.get_active_nodes():
		var candidate := node as LowpolyProjectile
		if candidate != null and candidate.network_entity_id == entity_id:
			projectile = candidate
			break
	if projectile == null:
		projectile = pool.acquire(_projectile_payload_from_state(state, team)) as LowpolyProjectile
	if projectile != null:
		projectile.apply_network_state(state)


func _reconcile_pickup_states(raw_states: Variant, _immediate: bool = false) -> void:
	if not raw_states is Array:
		return
	var active_by_id: Dictionary = {}
	for node: Node in _pickup_pool.get_active_nodes():
		var pickup := node as LowpolyExperiencePickup
		if pickup != null:
			active_by_id[pickup.network_entity_id] = pickup
	var seen: Dictionary = {}
	for value: Variant in raw_states:
		if not value is Dictionary:
			continue
		var state: Dictionary = value
		var entity_id := int(state.get("entity_id", 0))
		if entity_id <= 0:
			continue
		seen[entity_id] = true
		var pickup := active_by_id.get(entity_id) as LowpolyExperiencePickup
		if pickup == null:
			pickup = _spawn_pickup_network_view(state)
		if pickup != null:
			pickup.apply_network_state(state)
	for entity_value: Variant in active_by_id.keys():
		if not seen.has(entity_value):
			_pickup_pool.release(active_by_id[entity_value] as LowpolyExperiencePickup)


func _spawn_pickup_network_view(state: Dictionary) -> LowpolyExperiencePickup:
	var position_values: Array = state.get("position", [])
	var pickup := _pickup_pool.acquire({
		"network_entity_id": int(state.get("entity_id", 0)),
		"kind": int(state.get("kind", 0)),
		"amount": int(state.get("amount", 1)),
		"position": Vector3(
			float(position_values[0]), float(position_values[1]), float(position_values[2])
		) if position_values.size() == 3 else Vector3.ZERO,
	}) as LowpolyExperiencePickup
	if pickup != null:
		pickup.apply_network_state(state)
	return pickup


func _find_pickup_by_network_id(entity_id: int) -> LowpolyExperiencePickup:
	if entity_id <= 0:
		return null
	for node: Node in _pickup_pool.get_active_nodes():
		var pickup := node as LowpolyExperiencePickup
		if pickup != null and pickup.network_entity_id == entity_id:
			return pickup
	return null


func _has_network_entity(entity_id: int) -> bool:
	if entity_id <= 0:
		return false
	for enemy: LowpolyEnemy in _active_enemies():
		if enemy.network_entity_id == entity_id:
			return true
	for pool: LowpolyObjectPool in [_player_projectile_pool, _enemy_projectile_pool, _pickup_pool]:
		for node: Node in pool.get_active_nodes():
			if int(node.get("network_entity_id")) == entity_id:
				return true
	return false


func _release_network_entity(entity_id: int) -> void:
	if entity_id <= 0:
		return
	_network_entity_ticks.erase(entity_id)
	for enemy: LowpolyEnemy in _active_enemies():
		if enemy.network_entity_id != entity_id:
			continue
		var enemy_pool := _enemy_pools.get(enemy.enemy_id) as LowpolyObjectPool
		if enemy_pool != null:
			enemy_pool.release(enemy)
		return
	for pool: LowpolyObjectPool in [_player_projectile_pool, _enemy_projectile_pool, _pickup_pool]:
		for node: Node in pool.get_active_nodes():
			if int(node.get("network_entity_id")) == entity_id:
				pool.release(node)
				return


func _find_enemy_by_network_id(entity_id: int) -> LowpolyEnemy:
	if entity_id <= 0:
		return null
	for enemy: LowpolyEnemy in _active_enemies():
		if enemy.network_entity_id == entity_id:
			return enemy
	return null


func _finish_run(victory: bool) -> void:
	if _state == RunState.VICTORY or _state == RunState.DEFEAT:
		return
	for run_player: LowpolyPlayer in _all_players():
		run_player.set_run_active(false)
	_set_state(RunState.VICTORY if victory else RunState.DEFEAT)
	run_finished.emit(victory, {
		"elapsed": _elapsed,
		"kills": _kills,
		"level": _level,
		"state": int(_state),
		"seed": _run_seed,
	})
