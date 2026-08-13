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
var _initialized: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not initialize():
		push_error("Lowpoly Survivors core initialization failed: %s" % "; ".join(_balance.get_errors()))


func _physics_process(delta: float) -> void:
	if _state != RunState.RUNNING:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	simulate_step(delta, input_vector)


func initialize() -> bool:
	if _initialized:
		return true
	_balance = LowpolyBalanceLoader.new()
	if not _balance.load_balance(balance_path):
		return false
	_run_config = _balance.get_run_config()
	_create_containers()
	_create_player_and_weapons()
	_create_pools()
	_player.visible = false
	_initialized = true
	return true


func start_run(seed: int = -1) -> void:
	if not initialize():
		return
	_release_all_entities()
	_run_seed = seed if seed >= 0 else int(_run_config.get("fixed_test_seed", 47013))
	_rng.seed = _run_seed
	_elapsed = 0.0
	_spawn_accumulator = 0.0
	_level = 1
	_experience = 0
	_kills = 0
	_elite_spawned = [false, false, false]
	_boss = null
	_boss_started = false
	_upgrade_options.clear()
	_experience_required = _required_experience_for_level(_level)
	_player.max_health = float(_balance.get_player_config().get("max_health", 100.0))
	_player.reset_for_run()
	_weapon_system.reset()
	_set_state(RunState.RUNNING)
	health_changed.emit(_player.health, _player.max_health)
	experience_changed.emit(_experience, _experience_required, _level)
	time_changed.emit(_elapsed, float(_run_config.get("duration_seconds", 600.0)))
	kill_count_changed.emit(_kills)
	weapon_levels_changed.emit(_weapon_system.get_levels())
	boss_health_changed.emit(0.0, 0.0)


func restart_run() -> void:
	start_run(_run_seed)


func return_to_menu() -> void:
	_release_all_entities()
	if is_instance_valid(_player):
		_player.set_run_active(false)
		_player.visible = false
	_set_state(RunState.MENU)


func toggle_pause() -> void:
	if _state == RunState.RUNNING:
		_player.set_run_active(false)
		_set_state(RunState.PAUSED)
	elif _state == RunState.PAUSED:
		_player.set_run_active(true)
		_set_state(RunState.RUNNING)


func choose_upgrade(upgrade_id: StringName) -> bool:
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


func simulate_step(delta: float, input_vector: Vector2 = Vector2.ZERO) -> void:
	if _state != RunState.RUNNING or delta <= 0.0:
		return
	var duration: float = float(_run_config.get("duration_seconds", 600.0))
	_elapsed = minf(_elapsed + delta, duration)
	_process_timeline_events()
	_update_regular_spawning(delta)
	_player.update_movement(delta, input_vector)
	_rebuild_spatial_grid()
	_update_enemies(delta)
	_rebuild_spatial_grid()
	_weapon_system.update_weapons(delta)
	_update_projectiles(delta)
	_update_pickups(delta)
	_update_effects(delta)
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
		"enemy_projectiles": _enemy_projectile_pool.get_active_count(),
		"player_projectiles": _player_projectile_pool.get_active_count(),
		"pickups": _pickup_pool.get_active_count(),
		"effects": _effect_pool.get_active_count(),
		"boss_started": _boss_started,
		"boss_active": is_instance_valid(_boss) and _boss.active,
		"weapon_levels": _weapon_system.get_levels(),
		"upgrade_options": get_upgrade_options(),
	}


func find_nearest_enemy(position: Vector3, radius: float) -> Node3D:
	return _spatial_grid.find_nearest(position, radius)


func spawn_player_projectile(payload: Dictionary) -> bool:
	var enriched: Dictionary = payload.duplicate(true)
	enriched["team"] = LowpolyProjectile.Team.PLAYER
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
	_player.setup(
		_balance.get_player_config(),
		float(_run_config.get("arena_half_extent", 78.0)),
		String(_balance.get_weapon_config(&"pulse_rifle").get("model_path", ""))
	)
	_player.health_changed.connect(_on_player_health_changed)
	_player.died.connect(_on_player_died)
	_weapon_system = LowpolyWeaponSystem.new()
	_weapon_system.name = "WeaponSystem"
	add_child(_weapon_system)
	_weapon_system.setup(self, _player, _balance)
	_weapon_system.levels_changed.connect(_on_weapon_levels_changed)


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
	var interval: float = float(stage.get("spawn_interval", 1.0))
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
	var instance: Node = pool.acquire({
		"enemy_id": enemy_id,
		"config": _balance.get_enemy_config(enemy_id),
		"player": _player,
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
	for enemy: LowpolyEnemy in _active_enemies():
		var nearby: Array[Node3D] = _spatial_grid.query_radius(enemy.global_position, 3.0)
		enemy.update_enemy(delta, nearby)


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
		if projectile.global_position.distance_squared_to(_player.global_position) <= 0.85 * 0.85:
			_player.take_damage(projectile.damage, true)
			_enemy_projectile_pool.release(projectile)


func _update_pickups(delta: float) -> void:
	for node: Node in _pickup_pool.get_active_nodes():
		var pickup: LowpolyExperiencePickup = node as LowpolyExperiencePickup
		if pickup == null:
			continue
		if pickup.update_pickup(delta, _player.global_position, _player.get_pickup_radius()):
			if pickup.kind == LowpolyExperiencePickup.Kind.EXPERIENCE:
				_add_experience(pickup.amount)
			else:
				_player.heal(float(pickup.amount))
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
	var position: Vector3 = _player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
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


func _required_experience_for_level(level: int) -> int:
	var config: Dictionary = _balance.get_experience_config()
	var base: float = float(config.get("base_required", 8))
	var growth: float = float(config.get("growth", 1.28))
	var flat_growth: float = float(config.get("flat_growth", 3))
	return maxi(1, roundi(base * pow(growth, level - 1) + flat_growth * (level - 1)))


func _release_all_entities() -> void:
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


func _on_player_health_changed(current: float, maximum: float) -> void:
	health_changed.emit(current, maximum)


func _on_player_died() -> void:
	if _state == RunState.RUNNING:
		_finish_run(false)


func _on_enemy_died(enemy: LowpolyEnemy, reward: int) -> void:
	if _state != RunState.RUNNING:
		return
	var was_boss: bool = enemy == _boss
	var death_position: Vector3 = enemy.global_position
	var pool: LowpolyObjectPool = _enemy_pools.get(enemy.enemy_id) as LowpolyObjectPool
	if pool != null:
		pool.release(enemy)
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
		})
		if _rng.randf() < 0.08:
			_pickup_pool.acquire({
				"kind": LowpolyExperiencePickup.Kind.HEALTH,
				"amount": 18,
				"position": death_position + Vector3(0.4, 0.0, 0.0),
			})


func _on_enemy_damage_player_requested(amount: float) -> void:
	if _state == RunState.RUNNING:
		_player.take_damage(amount)


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
		})


func _on_boss_minions_requested(count: int) -> void:
	if _state != RunState.RUNNING:
		return
	for index: int in range(count):
		if _regular_enemy_count() >= int(_run_config.get("regular_enemy_cap", 220)):
			return
		var angle: float = TAU * float(index) / float(maxi(count, 1))
		var origin: Vector3 = _boss.global_position if is_instance_valid(_boss) else _player.global_position
		_spawn_enemy(
			&"enemy_small", false,
			origin + Vector3(cos(angle), 0.0, sin(angle)) * 4.0,
			true
		)


func _on_boss_health_changed(current: float, maximum: float) -> void:
	boss_health_changed.emit(current, maximum)


func _on_weapon_levels_changed(snapshot: Dictionary) -> void:
	weapon_levels_changed.emit(snapshot)


func _finish_run(victory: bool) -> void:
	if _state == RunState.VICTORY or _state == RunState.DEFEAT:
		return
	_player.set_run_active(false)
	_set_state(RunState.VICTORY if victory else RunState.DEFEAT)
	run_finished.emit(victory, {
		"elapsed": _elapsed,
		"kills": _kills,
		"level": _level,
		"state": int(_state),
		"seed": _run_seed,
	})
