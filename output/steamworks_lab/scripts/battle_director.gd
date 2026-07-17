class_name SteamLabBattleDirector
extends Node2D

signal phase_changed(phase: int, payload: Dictionary)
signal buff_options_ready(peer_id: int, options: PackedInt32Array)
signal active_item_used(peer_id: int, item_id: int, origin: Vector2)
signal player_enemy_hit(peer_id: int, defeated: bool, is_boss: bool)

const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const ENEMY_BULLET_SCRIPT := preload("res://scripts/enemy_bullet.gd")
const BURST_EFFECT_SCRIPT := preload("res://scripts/burst_effect.gd")
const BOSS_SCRIPT := preload("res://scripts/boss.gd")
const OBSTACLE_SCRIPT := preload("res://scripts/obstacle.gd")
const ACTIVE_PICKUP_SCRIPT := preload("res://scripts/active_pickup.gd")

enum Phase { BATTLE, CHOOSING_BUFF, GAME_OVER }
enum AiBlockerKind { ENEMY, BOSS, OBSTACLE }

const BUFF_FIRE_RATE: int = 0
const BUFF_DAMAGE: int = 1
const BUFF_MULTI_SHOT: int = 2
const BUFF_MOVE_SPEED: int = 3
const BUFF_HEAL: int = 4
const BUFF_BULLET_SPEED: int = 5
const BUFF_PIERCE: int = 6

const BUFF_DEFS: Array[Dictionary] = [
	{"id": BUFF_FIRE_RATE, "name": "射速强化", "desc": "开火冷却 ×0.85", "name_key": "buff_fire_rate_name", "desc_key": "buff_fire_rate_desc"},
	{"id": BUFF_DAMAGE, "name": "弹头强化", "desc": "子弹伤害 +1", "name_key": "buff_damage_name", "desc_key": "buff_damage_desc"},
	{"id": BUFF_MULTI_SHOT, "name": "多重散射", "desc": "每次多射出 1 颗子弹", "name_key": "buff_multi_shot_name", "desc_key": "buff_multi_shot_desc"},
	{"id": BUFF_MOVE_SPEED, "name": "机动强化", "desc": "移动速度 ×1.12", "name_key": "buff_move_speed_name", "desc_key": "buff_move_speed_desc"},
	{"id": BUFF_HEAL, "name": "紧急修复", "desc": "恢复 1 点生命", "name_key": "buff_heal_name", "desc_key": "buff_heal_desc"},
	{"id": BUFF_BULLET_SPEED, "name": "高速弹道", "desc": "子弹速度 ×1.2", "name_key": "buff_bullet_speed_name", "desc_key": "buff_bullet_speed_desc"},
	{"id": BUFF_PIERCE, "name": "穿透弹芯", "desc": "子弹可再穿透 1 个敌人", "name_key": "buff_pierce_name", "desc_key": "buff_pierce_desc"},
]

const ACTIVE_REPAIR_WAVE: int = 0
const ACTIVE_CLEAR_PULSE: int = 1
const ACTIVE_STASIS_FIELD: int = 2
const ACTIVE_TEAM_OVERLOAD: int = 3
const ACTIVE_EMERGENCY_SHIELD: int = 4

const ACTIVE_ITEM_DEFS: Array[Dictionary] = [
	{"id": ACTIVE_REPAIR_WAVE, "name": "修复波", "name_key": "active_repair_wave", "color": Color(0.52, 0.95, 0.68, 0.96)},
	{"id": ACTIVE_CLEAR_PULSE, "name": "清场脉冲", "name_key": "active_clear_pulse", "color": Color(0.92, 0.84, 0.48, 0.96)},
	{"id": ACTIVE_STASIS_FIELD, "name": "凝滞场", "name_key": "active_stasis_field", "color": Color(0.42, 0.82, 1.0, 0.96)},
	{"id": ACTIVE_TEAM_OVERLOAD, "name": "团队过载", "name_key": "active_team_overload", "color": Color(1.0, 0.58, 0.28, 0.96)},
	{"id": ACTIVE_EMERGENCY_SHIELD, "name": "应急护膜", "name_key": "active_emergency_shield", "color": Color(0.66, 0.62, 1.0, 0.96)},
]

const BUFF_INTERVAL: float = 30.0
const BUFF_CHOICE_TIMEOUT: float = 20.0
const BOSS_INTERVAL: float = 120.0
const BASE_SPAWN_INTERVAL: float = 1.6
const WAVE_BURST_INTERVAL: float = 12.0
const OBSTACLE_INTERVAL_MIN: float = 8.0
const OBSTACLE_INTERVAL_MAX: float = 14.0
const MAX_ALIVE_ENEMIES: int = 28
const MAX_ALIVE_ENEMY_BULLETS: int = 160
const MAX_ALIVE_OBSTACLES: int = 5
const MAX_ACTIVE_PICKUPS: int = 6
const PLAYER_BASE_FIRE_COOLDOWN: float = 0.18
const PLAYER_MIN_FIRE_COOLDOWN: float = 0.06
const PLAYER_BASE_MOVE_SPEED: float = 340.0
const ENEMY_SPAWN_MARGIN: float = 40.0
const ENEMY_DESPAWN_MARGIN: float = 90.0
const DRIFT_MARGIN: float = 24.0
const BOSS_SPAWN_RATE_SCALE: float = 2.0
const OBSTACLE_BLOCK_PADDING: float = 2.0
const ACTIVE_DROP_CHANCE: float = 0.12
const ACTIVE_PICKUP_LIFETIME: float = 18.0
const ACTIVE_PICKUP_COLLECT_PADDING: float = 6.0
const ACTIVE_CLEAR_DAMAGE: int = 4
const ACTIVE_STASIS_DURATION: float = 4.5
const ACTIVE_OVERLOAD_DURATION: float = 8.0
const ACTIVE_OVERLOAD_FIRE_COOLDOWN_SCALE: float = 0.72
const ACTIVE_OVERLOAD_DAMAGE_BONUS: int = 1
const ACTIVE_OVERLOAD_BULLET_SPEED_SCALE: float = 1.35
const ACTIVE_SHIELD_INVULNERABILITY: float = 2.8
const SHAKE_HIT_PLAYER: float = 9.0
const SHAKE_KILL_ENEMY: float = 1.4
const SHAKE_DESTROY_OBSTACLE: float = 5.5
const SHAKE_KILL_BOSS: float = 14.0
const SHAKE_ACTIVE_ITEM_LIGHT: float = 3.0
const SHAKE_ACTIVE_ITEM_HEAVY: float = 8.5

var phase: int = Phase.BATTLE
var tier: int = 0
var battle_clock: float = 0.0
var boss_kills: int = 0

var _main: Node2D
var _session: Node
var _world_rect: Rect2 = Rect2()
var _rng := RandomNumberGenerator.new()
var _enemies: Dictionary = {}
var _enemy_bullets: Array[Node] = []
var _player_bullets: Array[Node] = []
var _player_buffs: Dictionary = {}
var _next_entity_id: int = 1
var _spawn_timer: float = 1.2
var _wave_timer: float = WAVE_BURST_INTERVAL
var _next_buff_at: float = BUFF_INTERVAL
var _pending_buff_peers: Dictionary = {}
var _peer_buff_options: Dictionary = {}
var _choice_timeout_remaining: float = 0.0
var _boss: Node2D
var _obstacles: Dictionary = {}
var _obstacle_timer: float = OBSTACLE_INTERVAL_MIN
var _next_boss_at: float = BOSS_INTERVAL
var _active_pickups: Dictionary = {}
var _player_active_items: Dictionary = {}
var _stasis_remaining: float = 0.0
var _overload_remaining: float = 0.0
var _enemy_bullets_frozen: bool = false


func setup(main: Node2D, session: Node, world_rect: Rect2) -> void:
	_main = main
	_session = session
	_world_rect = world_rect
	_rng.randomize()


func set_world_rect(world_rect: Rect2) -> void:
	_world_rect = world_rect


func reset_battle() -> void:
	phase = Phase.BATTLE
	tier = 0
	battle_clock = 0.0
	boss_kills = 0
	_next_entity_id = 1
	_spawn_timer = 1.2
	_wave_timer = WAVE_BURST_INTERVAL
	_next_buff_at = BUFF_INTERVAL
	_player_buffs.clear()
	_pending_buff_peers.clear()
	_peer_buff_options.clear()
	_choice_timeout_remaining = 0.0
	_obstacle_timer = OBSTACLE_INTERVAL_MIN
	_next_boss_at = BOSS_INTERVAL
	_player_active_items.clear()
	_stasis_remaining = 0.0
	_overload_remaining = 0.0
	_enemy_bullets_frozen = false
	clear_entities()


func clear_entities() -> void:
	_enemies.clear()
	_enemy_bullets.clear()
	_player_bullets.clear()
	_obstacles.clear()
	_active_pickups.clear()
	_boss = null
	for child in get_children():
		if is_instance_valid(child):
			child.queue_free()


func is_authority() -> bool:
	if _session == null:
		return true
	return bool(_session.call("is_host")) or String(_session.call("active_transport")) == "offline"


func host_tick(delta: float) -> void:
	match phase:
		Phase.BATTLE:
			_battle_tick(delta)
		Phase.CHOOSING_BUFF:
			_choice_tick(delta)


func _battle_tick(delta: float) -> void:
	battle_clock += delta
	_update_active_effects(delta)
	_prune_entities()
	_update_active_pickups(delta)
	if not _stasis_active():
		_update_spawning(delta)
		_update_boss(delta)
		_update_obstacles(delta)
		_advance_enemies(delta)
		_resolve_enemy_obstacle_blocking()
	_resolve_player_bullet_hits()
	_resolve_enemy_bullet_hits()
	_resolve_contact_hits()
	_resolve_active_pickup_collection()
	_check_game_over()
	if phase == Phase.BATTLE and battle_clock >= _next_buff_at:
		_next_buff_at += BUFF_INTERVAL
		_enter_buff_choice()


func _update_boss(delta: float) -> void:
	if _boss == null and battle_clock >= _next_boss_at:
		_next_boss_at += BOSS_INTERVAL
		_spawn_boss()
	if _boss == null or not is_instance_valid(_boss):
		return
	var volleys: Array[Dictionary] = _boss.call("advance", delta, _alive_player_positions())
	for volley in volleys:
		if _enemy_bullets.size() >= MAX_ALIVE_ENEMY_BULLETS:
			break
		var directions: PackedVector2Array = volley.get("directions", PackedVector2Array())
		_spawn_enemy_volley(_boss.global_position, directions, float(volley.get("speed", 200.0)))


func _spawn_boss() -> void:
	var boss := BOSS_SCRIPT.new() as Node2D
	boss.name = "Boss%d" % (boss_kills + 1)
	add_child(boss)
	var hover := Vector2(_world_rect.get_center().x, _world_rect.position.y + 80.0)
	boss.call("configure", boss_kills + 1, tier, hover)
	_boss = boss
	_request_impact_feedback(5.0, 0.18, Color(1.0, 0.48, 0.30, 1.0), 0.12, 0.14)


func _update_obstacles(delta: float) -> void:
	_obstacle_timer -= delta
	if _obstacle_timer <= 0.0:
		_obstacle_timer = _rng.randf_range(OBSTACLE_INTERVAL_MIN, OBSTACLE_INTERVAL_MAX)
		if _obstacles.size() < MAX_ALIVE_OBSTACLES:
			_spawn_obstacle()
	for obstacle_id in _obstacles.keys():
		var obstacle := _obstacles.get(obstacle_id) as Node2D
		if obstacle == null or not is_instance_valid(obstacle):
			_obstacles.erase(obstacle_id)
			continue
		obstacle.call("advance", delta)
		if obstacle.global_position.y > _world_rect.end.y + ENEMY_DESPAWN_MARGIN:
			_obstacles.erase(obstacle_id)
			obstacle.queue_free()


func _spawn_obstacle() -> void:
	var obstacle := OBSTACLE_SCRIPT.new() as Node2D
	var obstacle_id := _next_entity_id
	_next_entity_id += 1
	obstacle.name = "Obstacle%d" % obstacle_id
	add_child(obstacle)
	var obstacle_radius := _rng.randf_range(36.0, 64.0)
	var spawn_x := _rng.randf_range(
		_world_rect.position.x + obstacle_radius + DRIFT_MARGIN,
		_world_rect.end.x - obstacle_radius - DRIFT_MARGIN
	)
	obstacle.call(
		"configure",
		obstacle_id,
		obstacle_radius,
		_rng.randf_range(40.0, 70.0),
		12.0 + 4.0 * float(tier),
		Vector2(spawn_x, _world_rect.position.y - obstacle_radius - 20.0),
		_rng.randi()
	)
	_obstacles[obstacle_id] = obstacle


func _update_active_effects(delta: float) -> void:
	if _stasis_remaining > 0.0:
		_stasis_remaining = maxf(0.0, _stasis_remaining - delta)
	if _overload_remaining > 0.0:
		_overload_remaining = maxf(0.0, _overload_remaining - delta)
	_set_enemy_bullets_frozen(_stasis_active())


func _stasis_active() -> bool:
	return _stasis_remaining > 0.0


func _overload_active() -> bool:
	return _overload_remaining > 0.0


func _set_enemy_bullets_frozen(frozen: bool) -> void:
	if _enemy_bullets_frozen == frozen:
		return
	_enemy_bullets_frozen = frozen
	for bullet in _enemy_bullets:
		if is_instance_valid(bullet) and bullet.has_method("set_battle_frozen"):
			bullet.call("set_battle_frozen", frozen)


func _update_active_pickups(delta: float) -> void:
	for pickup_id in _active_pickups.keys():
		var pickup := _active_pickups.get(pickup_id) as Node2D
		if pickup == null or not is_instance_valid(pickup):
			_active_pickups.erase(pickup_id)
			continue
		pickup.call("advance", delta)
		if bool(pickup.call("is_expired")):
			_active_pickups.erase(pickup_id)
			pickup.queue_free()


func _choice_tick(delta: float) -> void:
	if _session == null or String(_session.call("active_transport")) == "offline":
		return
	_choice_timeout_remaining -= delta
	if _choice_timeout_remaining > 0.0:
		return
	for peer_id in _pending_buff_peers.keys():
		var options: PackedInt32Array = _peer_buff_options.get(peer_id, PackedInt32Array())
		if options.size() > 0:
			apply_buff(peer_id, options[_rng.randi_range(0, options.size() - 1)])
		_pending_buff_peers.erase(peer_id)
	_check_choice_complete()


func _enter_buff_choice() -> void:
	phase = Phase.CHOOSING_BUFF
	tier += 1
	_choice_timeout_remaining = BUFF_CHOICE_TIMEOUT
	_pending_buff_peers.clear()
	_peer_buff_options.clear()
	set_battle_frozen(true)
	if _main != null:
		_main.call("set_player_bullets_frozen", true)
	for player in _alive_players():
		var peer_id := int(player.get("peer_id"))
		_pending_buff_peers[peer_id] = true
		_peer_buff_options[peer_id] = _roll_buff_options(peer_id)
	phase_changed.emit(Phase.CHOOSING_BUFF, {"tier": tier, "timeout": BUFF_CHOICE_TIMEOUT})
	for peer_id in _peer_buff_options.keys():
		buff_options_ready.emit(peer_id, _peer_buff_options[peer_id])
	if _pending_buff_peers.is_empty():
		_resume_battle()


func submit_buff_choice(peer_id: int, option_index: int) -> void:
	if phase != Phase.CHOOSING_BUFF:
		return
	if not _pending_buff_peers.has(peer_id):
		return
	var options: PackedInt32Array = _peer_buff_options.get(peer_id, PackedInt32Array())
	if option_index < 0 or option_index >= options.size():
		return
	apply_buff(peer_id, options[option_index])
	_pending_buff_peers.erase(peer_id)
	_check_choice_complete()


func notify_peer_left(peer_id: int) -> void:
	_player_buffs.erase(peer_id)
	_player_active_items.erase(peer_id)
	if _pending_buff_peers.has(peer_id):
		_pending_buff_peers.erase(peer_id)
		_check_choice_complete()


func pending_choice_count() -> int:
	return _pending_buff_peers.size()


func peer_buff_options(peer_id: int) -> PackedInt32Array:
	return _peer_buff_options.get(peer_id, PackedInt32Array())


func _roll_buff_options(peer_id: int) -> PackedInt32Array:
	var candidates: Array[int] = []
	for def in BUFF_DEFS:
		var buff_id := int(def.get("id", -1))
		if buff_id == BUFF_HEAL:
			var player := _player_node(peer_id)
			if player != null and int(player.get("hp")) >= 3:
				continue
		candidates.append(buff_id)
	var options := PackedInt32Array()
	for index in range(3):
		if candidates.is_empty():
			break
		var pick := _rng.randi_range(0, candidates.size() - 1)
		options.append(candidates[pick])
		candidates.remove_at(pick)
	return options


func _check_choice_complete() -> void:
	if phase != Phase.CHOOSING_BUFF:
		return
	if _pending_buff_peers.is_empty():
		_resume_battle()


func _resume_battle() -> void:
	phase = Phase.BATTLE
	_peer_buff_options.clear()
	set_battle_frozen(false)
	_set_enemy_bullets_frozen(_stasis_active())
	if _main != null:
		_main.call("set_player_bullets_frozen", false)
	phase_changed.emit(Phase.BATTLE, {"tier": tier})


func register_player_bullet(bullet: Node) -> void:
	_player_bullets.append(bullet)


func active_item_for_peer(peer_id: int) -> Dictionary:
	if not _player_active_items.has(peer_id):
		return {"held": false, "id": -1, "name": "空", "name_key": "hud_empty_item"}
	var item_id := int(_player_active_items.get(peer_id, -1))
	var def := active_item_def(item_id)
	return {
		"held": not def.is_empty(),
		"id": item_id,
		"name": String(def.get("name", "空")),
		"name_key": String(def.get("name_key", "hud_empty_item")),
		"color": def.get("color", Color(0.58, 0.66, 0.62, 0.82)),
	}


func active_item_def(item_id: int) -> Dictionary:
	for def in ACTIVE_ITEM_DEFS:
		if int(def.get("id", -1)) == item_id:
			return def
	return {}


func force_grant_active_item(peer_id: int, item_id: int) -> void:
	if active_item_def(item_id).is_empty():
		return
	_player_active_items[peer_id] = item_id


func force_spawn_active_pickup(item_id: int, spawn_position: Vector2) -> int:
	return _spawn_active_pickup(item_id, spawn_position)


func use_active_item(peer_id: int) -> Dictionary:
	if not is_authority() or phase != Phase.BATTLE:
		return {}
	if not _player_active_items.has(peer_id):
		return {}
	var item_id := int(_player_active_items.get(peer_id, -1))
	if active_item_def(item_id).is_empty():
		_player_active_items.erase(peer_id)
		return {}
	var player := _player_node(peer_id)
	if player == null or not bool(player.get("alive")):
		return {}
	var origin: Vector2 = player.call("body_center")
	_player_active_items.erase(peer_id)
	_apply_active_item(peer_id, item_id, origin)
	active_item_used.emit(peer_id, item_id, origin)
	return {
		"ok": true,
		"peer_id": peer_id,
		"item_id": item_id,
		"origin": {"x": origin.x, "y": origin.y},
	}


func play_active_item_feedback(_peer_id: int, item_id: int, origin: Vector2) -> void:
	_spawn_active_item_feedback(item_id, origin)


func client_tick(_delta: float) -> void:
	if is_authority():
		return
	var live_bullets: Array[Node] = []
	for bullet in _player_bullets:
		if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
			live_bullets.append(bullet)
	_player_bullets = live_bullets
	for bullet in _player_bullets:
		if not bool(bullet.call("is_live_for_damage")):
			continue
		var bullet_node := bullet as Node2D
		var bullet_radius := float(bullet.call("hit_radius"))
		if _visual_bullet_blocked(bullet_node.global_position, bullet_radius):
			spawn_burst(bullet_node.global_position, Color(0.9, 1.0, 0.8, 0.7), 4, 80.0)
			bullet.queue_free()


func _visual_bullet_blocked(bullet_position: Vector2, bullet_radius: float) -> bool:
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if bullet_position.distance_to(enemy.global_position) <= float(enemy.get("radius")) + bullet_radius:
			return true
	if _boss != null and is_instance_valid(_boss):
		if bullet_position.distance_to(_boss.global_position) <= float(_boss.get("radius")) + bullet_radius:
			return true
	for obstacle_id in _obstacles.keys():
		var obstacle := _obstacles.get(obstacle_id) as Node2D
		if obstacle == null or not is_instance_valid(obstacle):
			continue
		if bullet_position.distance_to(obstacle.global_position) <= float(obstacle.get("radius")) + bullet_radius:
			return true
	return false


func battle_snapshot() -> Dictionary:
	var enemy_rows: Array = []
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		enemy_rows.append([
			enemy_id,
			int(enemy.get("kind")),
			enemy.global_position.x,
			enemy.global_position.y,
			float(enemy.get("hp")),
			float(enemy.get("max_hp")),
		])
	var obstacle_rows: Array = []
	for obstacle_id in _obstacles.keys():
		var obstacle := _obstacles.get(obstacle_id) as Node2D
		if obstacle == null or not is_instance_valid(obstacle):
			continue
		obstacle_rows.append([
			obstacle_id,
			obstacle.global_position.x,
			obstacle.global_position.y,
			float(obstacle.get("hp")),
			float(obstacle.get("max_hp")),
			float(obstacle.get("radius")),
		])
	var active_pickup_rows: Array = []
	for pickup_id in _active_pickups.keys():
		var pickup := _active_pickups.get(pickup_id) as Node2D
		if pickup == null or not is_instance_valid(pickup):
			continue
		active_pickup_rows.append([
			pickup_id,
			int(pickup.get("item_id")),
			pickup.global_position.x,
			pickup.global_position.y,
			float(pickup.get("life_remaining")),
		])
	var active_item_rows: Array = []
	for peer_id in _player_active_items.keys():
		active_item_rows.append([peer_id, int(_player_active_items.get(peer_id, -1))])
	var boss_data: Dictionary = {}
	if _boss != null and is_instance_valid(_boss):
		boss_data = {
			"x": _boss.global_position.x,
			"y": _boss.global_position.y,
			"hp": float(_boss.get("hp")),
			"max_hp": float(_boss.get("max_hp")),
			"index": int(_boss.get("boss_index")),
		}
	return {
		"phase": phase,
		"tier": tier,
		"time": battle_clock,
		"boss_kills": boss_kills,
		"boss": boss_data,
		"enemies": enemy_rows,
		"obstacles": obstacle_rows,
		"active_pickups": active_pickup_rows,
		"active_items": active_item_rows,
		"active_effects": {
			"stasis": _stasis_remaining,
			"overload": _overload_remaining,
		},
	}


func apply_snapshot_battle(snapshot: Dictionary) -> void:
	tier = int(snapshot.get("tier", tier))
	battle_clock = float(snapshot.get("time", battle_clock))
	boss_kills = int(snapshot.get("boss_kills", boss_kills))
	var new_phase := int(snapshot.get("phase", phase))
	if new_phase != phase:
		apply_phase(new_phase, {})
	_reconcile_enemies(snapshot.get("enemies", []))
	_reconcile_boss(snapshot.get("boss", {}))
	_reconcile_obstacles(snapshot.get("obstacles", []))
	_reconcile_active_pickups(snapshot.get("active_pickups", []))
	_apply_active_item_snapshot(snapshot.get("active_items", []))
	_apply_active_effect_snapshot(snapshot.get("active_effects", {}))


func apply_phase(new_phase: int, payload: Dictionary) -> void:
	phase = new_phase
	if not payload.is_empty():
		tier = int(payload.get("tier", tier))
		if new_phase == Phase.GAME_OVER:
			battle_clock = float(payload.get("time", battle_clock))
			boss_kills = int(payload.get("boss_kills", boss_kills))
	var frozen := new_phase == Phase.CHOOSING_BUFF
	set_battle_frozen(frozen)
	if _main != null:
		_main.call("set_player_bullets_frozen", frozen)
	phase_changed.emit(new_phase, payload)


func spawn_volley_visual(origin: Vector2, directions: PackedVector2Array, speed: float) -> void:
	_spawn_enemy_volley(origin, directions, speed)


func _reconcile_enemies(rows: Variant) -> void:
	if not rows is Array:
		return
	var seen: Dictionary = {}
	for row in rows:
		if not row is Array:
			continue
		var row_data: Array = row
		if row_data.size() < 6:
			continue
		var enemy_id := int(row_data[0])
		seen[enemy_id] = true
		var target_position := Vector2(float(row_data[2]), float(row_data[3]))
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			enemy = ENEMY_SCRIPT.new() as Node2D
			enemy.name = "Enemy%d" % enemy_id
			add_child(enemy)
			var kind := int(row_data[1])
			enemy.call("configure", enemy_id, kind, {
				"radius": _radius_for_kind(kind),
				"hp": float(row_data[4]),
				"max_hp": float(row_data[5]),
			}, target_position)
			enemy.call("set_remote_driven", true)
			_enemies[enemy_id] = enemy
		enemy.call("set_authoritative_state", target_position, float(row_data[4]), float(row_data[5]))
	for enemy_id in _enemies.keys():
		if seen.has(enemy_id):
			continue
		var enemy := _enemies.get(enemy_id) as Node2D
		_enemies.erase(enemy_id)
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.global_position.y < _world_rect.end.y - 30.0 and _world_rect.grow(30.0).has_point(enemy.global_position):
			spawn_burst(enemy.global_position, Color(1.0, 0.62, 0.34, 0.9), 10, 150.0)
			_request_screen_shake(SHAKE_KILL_ENEMY, 0.06)
		enemy.queue_free()


func _reconcile_boss(data: Variant) -> void:
	if not data is Dictionary or (data as Dictionary).is_empty():
		if _boss != null and is_instance_valid(_boss):
			spawn_burst(_boss.global_position, Color(1.0, 0.48, 0.36, 0.95), 26, 260.0)
			_request_impact_feedback(SHAKE_KILL_BOSS, 0.34, Color(1.0, 0.48, 0.28, 1.0), 0.26, 0.24)
			_boss.queue_free()
		_boss = null
		return
	var boss_data: Dictionary = data
	var boss_position := Vector2(float(boss_data.get("x", 0.0)), float(boss_data.get("y", 0.0)))
	if _boss == null or not is_instance_valid(_boss):
		_boss = BOSS_SCRIPT.new() as Node2D
		_boss.name = "Boss%d" % int(boss_data.get("index", 1))
		add_child(_boss)
		_boss.call("configure", int(boss_data.get("index", 1)), tier, boss_position)
		_boss.call("set_remote_driven", true)
		_boss.global_position = boss_position
		_request_impact_feedback(5.0, 0.18, Color(1.0, 0.48, 0.30, 1.0), 0.12, 0.14)
	_boss.call(
		"set_authoritative_state",
		boss_position,
		float(boss_data.get("hp", 1.0)),
		float(boss_data.get("max_hp", 1.0))
	)


func _reconcile_obstacles(rows: Variant) -> void:
	if not rows is Array:
		return
	var seen: Dictionary = {}
	for row in rows:
		if not row is Array:
			continue
		var row_data: Array = row
		if row_data.size() < 6:
			continue
		var obstacle_id := int(row_data[0])
		seen[obstacle_id] = true
		var target_position := Vector2(float(row_data[1]), float(row_data[2]))
		var obstacle := _obstacles.get(obstacle_id) as Node2D
		if obstacle == null or not is_instance_valid(obstacle):
			obstacle = OBSTACLE_SCRIPT.new() as Node2D
			obstacle.name = "Obstacle%d" % obstacle_id
			add_child(obstacle)
			obstacle.call(
				"configure",
				obstacle_id,
				float(row_data[5]),
				0.0,
				float(row_data[3]),
				target_position,
				obstacle_id
			)
			obstacle.call("set_remote_driven", true)
			_obstacles[obstacle_id] = obstacle
		obstacle.call("set_authoritative_state", target_position, float(row_data[3]), float(row_data[4]))
	for obstacle_id in _obstacles.keys():
		if seen.has(obstacle_id):
			continue
		var obstacle := _obstacles.get(obstacle_id) as Node2D
		_obstacles.erase(obstacle_id)
		if obstacle == null or not is_instance_valid(obstacle):
			continue
		if obstacle.global_position.y < _world_rect.end.y - 30.0:
			spawn_burst(obstacle.global_position, Color(0.58, 0.54, 0.48, 0.92), 12, 130.0)
			_request_impact_feedback(SHAKE_DESTROY_OBSTACLE, 0.16, Color(0.86, 0.76, 0.58, 1.0), 0.11, 0.12)
		obstacle.queue_free()


func _reconcile_active_pickups(rows: Variant) -> void:
	if not rows is Array:
		return
	var seen: Dictionary = {}
	for row in rows:
		if not row is Array:
			continue
		var row_data: Array = row
		if row_data.size() < 5:
			continue
		var pickup_id := int(row_data[0])
		var item_id := int(row_data[1])
		var target_position := Vector2(float(row_data[2]), float(row_data[3]))
		var life_remaining := float(row_data[4])
		var def := active_item_def(item_id)
		if def.is_empty():
			continue
		seen[pickup_id] = true
		var pickup := _active_pickups.get(pickup_id) as Node2D
		if pickup == null or not is_instance_valid(pickup):
			pickup = ACTIVE_PICKUP_SCRIPT.new() as Node2D
			pickup.name = "ActivePickup%d" % pickup_id
			add_child(pickup)
			pickup.call(
				"configure",
				pickup_id,
				item_id,
				String(def.get("name", "")),
				target_position,
				life_remaining,
				def.get("color", Color(0.66, 0.95, 0.78, 0.96))
			)
			pickup.call("set_remote_driven", true)
			_active_pickups[pickup_id] = pickup
		pickup.call("set_authoritative_state", target_position, life_remaining)
	for pickup_id in _active_pickups.keys():
		if seen.has(pickup_id):
			continue
		var pickup := _active_pickups.get(pickup_id) as Node2D
		_active_pickups.erase(pickup_id)
		if pickup == null or not is_instance_valid(pickup):
			continue
		spawn_burst(pickup.global_position, Color(0.66, 0.95, 0.78, 0.72), 7, 90.0)
		pickup.queue_free()


func _apply_active_item_snapshot(rows: Variant) -> void:
	_player_active_items.clear()
	if not rows is Array:
		return
	for row in rows:
		if not row is Array:
			continue
		var row_data: Array = row
		if row_data.size() < 2:
			continue
		var peer_id := int(row_data[0])
		var item_id := int(row_data[1])
		if peer_id <= 0 or active_item_def(item_id).is_empty():
			continue
		_player_active_items[peer_id] = item_id


func _apply_active_effect_snapshot(data: Variant) -> void:
	if not data is Dictionary:
		_stasis_remaining = 0.0
		_overload_remaining = 0.0
		_set_enemy_bullets_frozen(false)
		return
	var effects: Dictionary = data
	_stasis_remaining = maxf(float(effects.get("stasis", 0.0)), 0.0)
	_overload_remaining = maxf(float(effects.get("overload", 0.0)), 0.0)
	_set_enemy_bullets_frozen(_stasis_active())


func _radius_for_kind(kind: int) -> float:
	match kind:
		ENEMY_SCRIPT.KIND_GUNNER:
			return 20.0
		ENEMY_SCRIPT.KIND_STRAFER:
			return 14.0
		_:
			return 16.0


func battle_state() -> Dictionary:
	var boss_info: Dictionary = {}
	if _boss != null and is_instance_valid(_boss):
		boss_info = {
			"hp": float(_boss.get("hp")),
			"max_hp": float(_boss.get("max_hp")),
			"index": int(_boss.get("boss_index")),
		}
	return {
		"phase": phase,
		"tier": tier,
		"time": battle_clock,
		"boss_kills": boss_kills,
		"enemy_count": _enemies.size(),
		"boss": boss_info,
		"active_pickup_count": _active_pickups.size(),
		"active_effects": {
			"stasis": _stasis_remaining,
			"overload": _overload_remaining,
		},
	}


func nearest_hostile_position(origin: Vector2) -> Vector2:
	var nearest_position := Vector2.INF
	var nearest_distance := INF
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy) or bool(enemy.call("is_dead")):
			continue
		var distance := origin.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_position = enemy.global_position
	if _boss != null and is_instance_valid(_boss) and not bool(_boss.call("is_dead")):
		var boss_distance := origin.distance_squared_to(_boss.global_position)
		if boss_distance < nearest_distance:
			nearest_position = _boss.global_position
	return nearest_position


func ai_movement_context(origin: Vector2, radius: float = 280.0) -> Dictionary:
	var query_radius := maxf(radius, 0.0)
	var bullets: Array[Dictionary] = []
	var blockers: Array[Dictionary] = []
	for bullet in _enemy_bullets:
		if (
			bullet == null
			or not is_instance_valid(bullet)
			or bullet.is_queued_for_deletion()
			or bool(bullet.call("is_expired"))
		):
			continue
		var bullet_position: Vector2 = bullet.global_position
		if origin.distance_to(bullet_position) > query_radius:
			continue
		bullets.append({
			"position": bullet_position,
			"velocity": (
				Vector2.ZERO
				if _enemy_bullets_frozen
				else bullet.call("motion_velocity") as Vector2
			),
			"radius": float(bullet.call("hit_radius")),
		})
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if (
			enemy == null
			or not is_instance_valid(enemy)
			or enemy.is_queued_for_deletion()
			or bool(enemy.call("is_dead"))
		):
			continue
		_append_ai_blocker(
			blockers,
			origin,
			query_radius,
			enemy.global_position,
			float(enemy.get("radius")),
			AiBlockerKind.ENEMY
		)
	if (
		_boss != null
		and is_instance_valid(_boss)
		and not _boss.is_queued_for_deletion()
		and not bool(_boss.call("is_dead"))
	):
		_append_ai_blocker(
			blockers,
			origin,
			query_radius,
			_boss.global_position,
			float(_boss.get("radius")),
			AiBlockerKind.BOSS
		)
	for obstacle_id in _obstacles.keys():
		var obstacle := _obstacles.get(obstacle_id) as Node2D
		if (
			obstacle == null
			or not is_instance_valid(obstacle)
			or obstacle.is_queued_for_deletion()
			or bool(obstacle.call("is_destroyed"))
		):
			continue
		_append_ai_blocker(
			blockers,
			origin,
			query_radius,
			obstacle.global_position,
			float(obstacle.get("radius")),
			AiBlockerKind.OBSTACLE
		)
	return {"bullets": bullets, "blockers": blockers}


func _append_ai_blocker(
	rows: Array[Dictionary],
	origin: Vector2,
	query_radius: float,
	position: Vector2,
	blocker_radius: float,
	kind: int
) -> void:
	if origin.distance_to(position) > query_radius + blocker_radius:
		return
	rows.append({
		"position": position,
		"radius": maxf(blocker_radius, 0.0),
		"kind": kind,
	})


func buff_def(buff_id: int) -> Dictionary:
	for def in BUFF_DEFS:
		if int(def.get("id", -1)) == buff_id:
			return def
	return {}


func apply_buff(peer_id: int, buff_id: int) -> void:
	var stacks: Dictionary = _player_buffs.get(peer_id, {})
	stacks[buff_id] = int(stacks.get(buff_id, 0)) + 1
	_player_buffs[peer_id] = stacks
	var player := _player_node(peer_id)
	if player == null:
		return
	if buff_id == BUFF_HEAL:
		player.call("heal", 1)
	elif buff_id == BUFF_MOVE_SPEED:
		player.call("set_move_speed", PLAYER_BASE_MOVE_SPEED * player_move_speed_scale(peer_id))


func player_fire_cooldown(peer_id: int) -> float:
	var scale := pow(0.85, float(_buff_stacks(peer_id, BUFF_FIRE_RATE)))
	if _overload_active():
		scale *= ACTIVE_OVERLOAD_FIRE_COOLDOWN_SCALE
	return maxf(PLAYER_BASE_FIRE_COOLDOWN * scale, PLAYER_MIN_FIRE_COOLDOWN)


func player_bullet_damage(peer_id: int) -> int:
	var bonus := ACTIVE_OVERLOAD_DAMAGE_BONUS if _overload_active() else 0
	return 1 + _buff_stacks(peer_id, BUFF_DAMAGE) + bonus


func player_bullet_count(peer_id: int) -> int:
	return mini(1 + _buff_stacks(peer_id, BUFF_MULTI_SHOT), 5)


func player_move_speed_scale(peer_id: int) -> float:
	return minf(pow(1.12, float(_buff_stacks(peer_id, BUFF_MOVE_SPEED))), 1.8)


func player_bullet_speed_scale(peer_id: int) -> float:
	var overload_scale := ACTIVE_OVERLOAD_BULLET_SPEED_SCALE if _overload_active() else 1.0
	return minf(pow(1.2, float(_buff_stacks(peer_id, BUFF_BULLET_SPEED))) * overload_scale, 2.6)


func player_pierce_count(peer_id: int) -> int:
	return _buff_stacks(peer_id, BUFF_PIERCE)


func spawn_burst(origin: Vector2, color: Color, shard_count: int, shard_speed: float) -> void:
	var burst := BURST_EFFECT_SCRIPT.new() as Node2D
	burst.name = "Burst%d" % _next_entity_id
	_next_entity_id += 1
	add_child(burst)
	burst.call("configure", origin, color, shard_count, shard_speed)


func _request_screen_shake(strength: float, duration: float) -> void:
	if _main == null or not _main.has_method("request_screen_shake"):
		return
	_main.call("request_screen_shake", strength, duration)


func _request_screen_flash(color: Color, alpha: float, duration: float) -> void:
	if _main == null or not _main.has_method("request_screen_flash"):
		return
	_main.call("request_screen_flash", color, alpha, duration)


func _request_impact_feedback(
	strength: float,
	duration: float,
	flash_color: Color,
	flash_alpha: float,
	flash_duration: float
) -> void:
	_request_screen_shake(strength, duration)
	_request_screen_flash(flash_color, flash_alpha, flash_duration)


func _apply_active_item(peer_id: int, item_id: int, origin: Vector2) -> void:
	match item_id:
		ACTIVE_REPAIR_WAVE:
			for player in _alive_players():
				player.call("heal", 1)
		ACTIVE_CLEAR_PULSE:
			_clear_enemy_bullets()
			_damage_all_hostiles(ACTIVE_CLEAR_DAMAGE)
		ACTIVE_STASIS_FIELD:
			_stasis_remaining = maxf(_stasis_remaining, ACTIVE_STASIS_DURATION)
			_set_enemy_bullets_frozen(true)
		ACTIVE_TEAM_OVERLOAD:
			_overload_remaining = maxf(_overload_remaining, ACTIVE_OVERLOAD_DURATION)
		ACTIVE_EMERGENCY_SHIELD:
			var player := _player_node(peer_id)
			if player != null:
				player.call("heal", 1)
				player.set(
					"invuln_remaining",
					maxf(float(player.get("invuln_remaining")), ACTIVE_SHIELD_INVULNERABILITY)
				)
		_:
			return
	_spawn_active_item_feedback(item_id, origin)


func _spawn_active_item_feedback(item_id: int, origin: Vector2) -> void:
	var def := active_item_def(item_id)
	var burst_color: Color = def.get("color", Color(0.66, 0.95, 0.78, 0.96))
	var shard_count := 18
	var shard_speed := 180.0
	var shake_strength := SHAKE_ACTIVE_ITEM_LIGHT
	var shake_duration := 0.16
	var flash_alpha := 0.14
	match item_id:
		ACTIVE_REPAIR_WAVE:
			shard_count = 18
			shard_speed = 150.0
			shake_strength = 2.2
			flash_alpha = 0.10
		ACTIVE_CLEAR_PULSE:
			shard_count = 30
			shard_speed = 300.0
			shake_strength = SHAKE_ACTIVE_ITEM_HEAVY
			shake_duration = 0.24
			flash_alpha = 0.22
		ACTIVE_STASIS_FIELD:
			shard_count = 20
			shard_speed = 120.0
			shake_strength = 2.8
			flash_alpha = 0.12
		ACTIVE_TEAM_OVERLOAD:
			shard_count = 24
			shard_speed = 220.0
			shake_strength = 4.5
			flash_alpha = 0.16
		ACTIVE_EMERGENCY_SHIELD:
			shard_count = 16
			shard_speed = 130.0
			shake_strength = 2.4
			flash_alpha = 0.12
		_:
			pass
	spawn_burst(origin, burst_color, shard_count, shard_speed)
	_request_impact_feedback(shake_strength, shake_duration, burst_color, flash_alpha, 0.18)


func _clear_enemy_bullets() -> void:
	for bullet in _enemy_bullets:
		if bullet == null or not is_instance_valid(bullet):
			continue
		var bullet_node := bullet as Node2D
		if bullet_node != null:
			spawn_burst(bullet_node.global_position, Color(1.0, 0.82, 0.52, 0.74), 4, 80.0)
		bullet.queue_free()
	_enemy_bullets.clear()
	_enemy_bullets_frozen = false


func _damage_all_hostiles(amount: int) -> void:
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		enemy.call("take_hit", amount)
		if bool(enemy.call("is_dead")):
			_kill_enemy(enemy_id, enemy)
	if _boss != null and is_instance_valid(_boss):
		_boss.call("take_hit", amount)
		if bool(_boss.call("is_dead")):
			_kill_boss()
	for obstacle_id in _obstacles.keys():
		var obstacle := _obstacles.get(obstacle_id) as Node2D
		if obstacle == null or not is_instance_valid(obstacle):
			continue
		obstacle.call("take_hit", amount)
		if bool(obstacle.call("is_destroyed")):
			_destroy_obstacle(obstacle_id, obstacle)


func _maybe_drop_active_item(drop_position: Vector2) -> void:
	if _active_pickups.size() >= MAX_ACTIVE_PICKUPS:
		return
	if _rng.randf() > ACTIVE_DROP_CHANCE:
		return
	_spawn_active_pickup(_roll_active_item_id(), drop_position)


func _roll_active_item_id() -> int:
	var pick := _rng.randi_range(0, ACTIVE_ITEM_DEFS.size() - 1)
	return int(ACTIVE_ITEM_DEFS[pick].get("id", ACTIVE_REPAIR_WAVE))


func _spawn_active_pickup(item_id: int, spawn_position: Vector2) -> int:
	var def := active_item_def(item_id)
	if def.is_empty():
		return -1
	if _active_pickups.size() >= MAX_ACTIVE_PICKUPS:
		return -1
	var pickup_id := _next_entity_id
	_next_entity_id += 1
	var pickup := ACTIVE_PICKUP_SCRIPT.new() as Node2D
	pickup.name = "ActivePickup%d" % pickup_id
	add_child(pickup)
	var pickup_color: Color = def.get("color", Color(0.66, 0.95, 0.78, 0.96))
	var clamped_position := Vector2(
		clampf(spawn_position.x, _world_rect.position.x + 24.0, _world_rect.end.x - 24.0),
		clampf(spawn_position.y, _world_rect.position.y + 24.0, _world_rect.end.y - 24.0)
	)
	pickup.call(
		"configure",
		pickup_id,
		item_id,
		String(def.get("name", "")),
		clamped_position,
		ACTIVE_PICKUP_LIFETIME,
		pickup_color
	)
	_active_pickups[pickup_id] = pickup
	return pickup_id


func _resolve_active_pickup_collection() -> void:
	if _active_pickups.is_empty():
		return
	for pickup_id in _active_pickups.keys():
		var pickup := _active_pickups.get(pickup_id) as Node2D
		if pickup == null or not is_instance_valid(pickup):
			_active_pickups.erase(pickup_id)
			continue
		for player in _alive_players():
			var player_center: Vector2 = player.call("body_center")
			var player_radius := float(player.call("hit_radius"))
			if player_center.distance_to(pickup.global_position) > player_radius + float(pickup.get("radius")) + ACTIVE_PICKUP_COLLECT_PADDING:
				continue
			_collect_active_pickup(int(player.get("peer_id")), pickup_id, pickup)
			break


func _collect_active_pickup(peer_id: int, pickup_id: int, pickup: Node2D) -> void:
	var item_id := int(pickup.get("item_id"))
	if active_item_def(item_id).is_empty():
		return
	_player_active_items[peer_id] = item_id
	_active_pickups.erase(pickup_id)
	spawn_burst(pickup.global_position, Color(0.70, 1.0, 0.82, 0.82), 8, 110.0)
	pickup.queue_free()


func set_battle_frozen(frozen: bool) -> void:
	for child in get_children():
		if is_instance_valid(child) and child.has_method("set_battle_frozen"):
			child.call("set_battle_frozen", frozen)
	if not frozen:
		_enemy_bullets_frozen = false
		_set_enemy_bullets_frozen(_stasis_active())


func _buff_stacks(peer_id: int, buff_id: int) -> int:
	var stacks: Dictionary = _player_buffs.get(peer_id, {})
	return int(stacks.get(buff_id, 0))


func _player_node(peer_id: int) -> Node:
	if _main == null:
		return null
	var players: Dictionary = _main.call("player_nodes")
	var player := players.get(peer_id) as Node
	if player == null or not is_instance_valid(player):
		return null
	return player


func _alive_players() -> Array[Node]:
	var alive: Array[Node] = []
	if _main == null:
		return alive
	var players: Dictionary = _main.call("player_nodes")
	for peer_id in players.keys():
		var player := players[peer_id] as Node
		if player == null or not is_instance_valid(player):
			continue
		if _main != null and bool(_main.call("is_peer_merged", int(peer_id))):
			continue
		if bool(player.get("alive")):
			alive.append(player)
	return alive


func _active_merge_hitboxes() -> Array[Dictionary]:
	var hitboxes: Array[Dictionary] = []
	if _main == null:
		return hitboxes
	var rows: Variant = _main.call("active_merge_hitboxes")
	if rows is Array:
		for raw_row in rows:
			if raw_row is Dictionary:
				hitboxes.append(raw_row)
	return hitboxes


func _try_damage_merge_targets(targets: Array[Dictionary], hit_position: Vector2, hit_radius: float) -> bool:
	if _main == null:
		return false
	for target in targets:
		var position: Vector2 = target.get("position", Vector2.ZERO)
		var radius := float(target.get("radius", 0.0))
		if hit_position.distance_to(position) > radius + hit_radius:
			continue
		return bool(_main.call("apply_merge_damage", int(target.get("id", 0)), 1))
	return false


func _alive_player_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for player in _alive_players():
		positions.append(player.call("body_center"))
	return positions


func _prune_entities() -> void:
	var live_bullets: Array[Node] = []
	for bullet in _enemy_bullets:
		if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
			live_bullets.append(bullet)
	_enemy_bullets = live_bullets
	var live_player_bullets: Array[Node] = []
	for bullet in _player_bullets:
		if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
			live_player_bullets.append(bullet)
	_player_bullets = live_player_bullets
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			_enemies.erase(enemy_id)
			continue
		if _is_enemy_out_of_bounds(enemy):
			_enemies.erase(enemy_id)
			enemy.queue_free()


func _is_enemy_out_of_bounds(enemy: Node2D) -> bool:
	var position_value := enemy.global_position
	if position_value.y > _world_rect.end.y + ENEMY_DESPAWN_MARGIN:
		return true
	if position_value.x < _world_rect.position.x - ENEMY_DESPAWN_MARGIN * 1.5:
		return true
	if position_value.x > _world_rect.end.x + ENEMY_DESPAWN_MARGIN * 1.5:
		return true
	return false


func _update_spawning(delta: float) -> void:
	var boss_scale := BOSS_SPAWN_RATE_SCALE if _boss != null and is_instance_valid(_boss) else 1.0
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = BASE_SPAWN_INTERVAL * _tier_spawn_interval_scale() * boss_scale
		if _enemies.size() < MAX_ALIVE_ENEMIES:
			_spawn_enemy(_roll_enemy_kind())
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = WAVE_BURST_INTERVAL * boss_scale
		_spawn_dart_wave()


func _roll_enemy_kind() -> int:
	var roll := _rng.randi_range(0, 9)
	if roll < 5:
		return ENEMY_SCRIPT.KIND_DART
	if roll < 8:
		return ENEMY_SCRIPT.KIND_GUNNER
	return ENEMY_SCRIPT.KIND_STRAFER


func _spawn_dart_wave() -> void:
	var wave_size := mini(3 + tier / 2, 5)
	var usable_width := _world_rect.size.x - 80.0
	for index in range(wave_size):
		if _enemies.size() >= MAX_ALIVE_ENEMIES:
			return
		var ratio := float(index + 1) / float(wave_size + 1)
		var spawn_x := _world_rect.position.x + 40.0 + usable_width * ratio
		_spawn_enemy_at(ENEMY_SCRIPT.KIND_DART, Vector2(spawn_x, _world_rect.position.y - ENEMY_SPAWN_MARGIN))


func _spawn_enemy(kind: int) -> void:
	var spawn_position := Vector2.ZERO
	if kind == ENEMY_SCRIPT.KIND_STRAFER:
		var from_left := _rng.randf() < 0.5
		var spawn_x := _world_rect.position.x - ENEMY_SPAWN_MARGIN if from_left else _world_rect.end.x + ENEMY_SPAWN_MARGIN
		spawn_position = Vector2(spawn_x, _world_rect.position.y + _rng.randf_range(30.0, 180.0))
	else:
		spawn_position = Vector2(
			_rng.randf_range(_world_rect.position.x + 40.0, _world_rect.end.x - 40.0),
			_world_rect.position.y - ENEMY_SPAWN_MARGIN
		)
	_spawn_enemy_at(kind, spawn_position)


func _spawn_enemy_at(kind: int, spawn_position: Vector2) -> void:
	var enemy := ENEMY_SCRIPT.new() as Node2D
	var enemy_id := _next_entity_id
	_next_entity_id += 1
	enemy.name = "Enemy%d" % enemy_id
	add_child(enemy)
	var stats := _stats_for_kind(kind)
	enemy.call("configure", enemy_id, kind, stats, spawn_position)
	_enemies[enemy_id] = enemy


func _stats_for_kind(kind: int) -> Dictionary:
	var stats: Dictionary = {}
	match kind:
		ENEMY_SCRIPT.KIND_GUNNER:
			stats = {
				"radius": 20.0,
				"hp": 5.0,
				"move_speed": 90.0,
				"fire_interval": 2.2,
				"bullet_speed": 220.0,
				"fire_fan_count": 3 if tier >= 3 else 1,
				"hover_y": _world_rect.position.y + _rng.randf_range(60.0, 260.0),
				"sway_phase": _rng.randf_range(0.0, 1.0),
			}
		ENEMY_SCRIPT.KIND_STRAFER:
			stats = {
				"radius": 14.0,
				"hp": 2.0,
				"move_speed": 110.0,
				"fire_interval": 1.6,
				"bullet_speed": 220.0,
				"strafe_speed_x": 90.0,
				"strafe_speed_y": 110.0,
			}
		_:
			stats = {
				"radius": 16.0,
				"hp": 3.0,
				"move_speed": 140.0,
				"fire_interval": 0.0,
				"bullet_speed": 0.0,
			}
	stats["hp"] = float(stats.get("hp", 3.0)) * _tier_hp_scale()
	stats["max_hp"] = stats["hp"]
	stats["move_speed"] = float(stats.get("move_speed", 100.0)) * _tier_speed_scale()
	stats["fire_interval"] = float(stats.get("fire_interval", 0.0)) * _tier_fire_interval_scale()
	stats["bullet_speed"] = float(stats.get("bullet_speed", 0.0)) * _tier_bullet_speed_scale()
	if kind == ENEMY_SCRIPT.KIND_STRAFER:
		stats["strafe_speed_x"] = float(stats.get("strafe_speed_x", 90.0)) * _tier_speed_scale()
		stats["strafe_speed_y"] = float(stats.get("strafe_speed_y", 110.0)) * _tier_speed_scale()
		if _rng.randf() < 0.5:
			stats["strafe_speed_x"] = -float(stats["strafe_speed_x"])
	return stats


func _advance_enemies(delta: float) -> void:
	var targets := _alive_player_positions()
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var fire_directions: PackedVector2Array = enemy.call("advance", delta, targets)
		if fire_directions.is_empty():
			continue
		if _enemy_bullets.size() >= MAX_ALIVE_ENEMY_BULLETS:
			continue
		var bullet_speed := float(enemy.get("bullet_speed"))
		_spawn_enemy_volley(enemy.global_position, fire_directions, bullet_speed)


func _resolve_enemy_obstacle_blocking() -> void:
	if _obstacles.is_empty():
		return
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		for obstacle_id in _obstacles.keys():
			var obstacle := _obstacles.get(obstacle_id) as Node2D
			if obstacle == null or not is_instance_valid(obstacle):
				continue
			enemy.call(
				"push_out_of_circle",
				obstacle.global_position,
				float(obstacle.get("radius")),
				OBSTACLE_BLOCK_PADDING
			)


func _spawn_enemy_volley(origin: Vector2, directions: PackedVector2Array, bullet_speed: float) -> void:
	for direction in directions:
		var bullet := ENEMY_BULLET_SCRIPT.new() as Node2D
		bullet.name = "EnemyBullet%d" % _next_entity_id
		_next_entity_id += 1
		add_child(bullet)
		bullet.call("configure", origin, direction, bullet_speed, _world_rect)
		if _stasis_active():
			bullet.call("set_battle_frozen", true)
		_enemy_bullets.append(bullet)
	if _session != null and bool(_session.call("is_host")):
		_session.call("broadcast_enemy_volley", origin, directions, bullet_speed)


func _resolve_player_bullet_hits() -> void:
	for bullet in _player_bullets:
		if bullet == null or not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			continue
		if not bool(bullet.call("is_live_for_damage")):
			continue
		var bullet_node := bullet as Node2D
		var bullet_radius := float(bullet.call("hit_radius"))
		var damage := int(bullet.get("damage"))
		var owner_peer_id := int(bullet.get("owner_peer_id"))
		for enemy_id in _enemies.keys():
			var enemy := _enemies.get(enemy_id) as Node2D
			if enemy == null or not is_instance_valid(enemy):
				continue
			var enemy_radius := float(enemy.get("radius"))
			if bullet_node.global_position.distance_to(enemy.global_position) > enemy_radius + bullet_radius:
				continue
			if not bool(bullet.call("register_pierce_hit", enemy_id)):
				continue
			enemy.call("take_hit", damage)
			spawn_burst(bullet_node.global_position, Color(0.9, 1.0, 0.8, 0.7), 4, 80.0)
			var enemy_defeated := bool(enemy.call("is_dead"))
			player_enemy_hit.emit(owner_peer_id, enemy_defeated, false)
			if enemy_defeated:
				_kill_enemy(enemy_id, enemy)
			var pierce_remaining := int(bullet.get("pierce_remaining"))
			if pierce_remaining > 0:
				bullet.set("pierce_remaining", pierce_remaining - 1)
			else:
				bullet.queue_free()
				break
		if bullet.is_queued_for_deletion():
			continue
		if _boss != null and is_instance_valid(_boss):
			var boss_radius := float(_boss.get("radius"))
			if bullet_node.global_position.distance_to(_boss.global_position) <= boss_radius + bullet_radius:
				_boss.call("take_hit", damage)
				spawn_burst(bullet_node.global_position, Color(1.0, 0.80, 0.58, 0.78), 5, 105.0)
				var boss_defeated := bool(_boss.call("is_dead"))
				player_enemy_hit.emit(owner_peer_id, boss_defeated, true)
				if boss_defeated:
					_kill_boss()
				bullet.queue_free()
				continue
		for obstacle_id in _obstacles.keys():
			var obstacle := _obstacles.get(obstacle_id) as Node2D
			if obstacle == null or not is_instance_valid(obstacle):
				continue
			var obstacle_radius := float(obstacle.get("radius"))
			if bullet_node.global_position.distance_to(obstacle.global_position) > obstacle_radius + bullet_radius:
				continue
			obstacle.call("take_hit", damage)
			spawn_burst(bullet_node.global_position, Color(0.86, 0.78, 0.66, 0.70), 4, 76.0)
			if bool(obstacle.call("is_destroyed")):
				_destroy_obstacle(obstacle_id, obstacle)
			bullet.queue_free()
			break


func _kill_boss() -> void:
	if _boss == null or not is_instance_valid(_boss):
		_boss = null
		return
	boss_kills += 1
	spawn_burst(_boss.global_position, Color(1.0, 0.48, 0.36, 0.95), 26, 260.0)
	spawn_burst(_boss.global_position, Color(1.0, 0.82, 0.52, 0.9), 14, 150.0)
	_request_impact_feedback(SHAKE_KILL_BOSS, 0.34, Color(1.0, 0.48, 0.28, 1.0), 0.26, 0.24)
	_boss.queue_free()
	_boss = null


func _destroy_obstacle(obstacle_id: int, obstacle: Node2D) -> void:
	_obstacles.erase(obstacle_id)
	spawn_burst(obstacle.global_position, Color(0.58, 0.54, 0.48, 0.92), 12, 130.0)
	_request_impact_feedback(SHAKE_DESTROY_OBSTACLE, 0.16, Color(0.86, 0.76, 0.58, 1.0), 0.11, 0.12)
	obstacle.queue_free()


func _kill_enemy(enemy_id: int, enemy: Node2D) -> void:
	_enemies.erase(enemy_id)
	spawn_burst(enemy.global_position, Color(1.0, 0.62, 0.34, 0.9), 10, 150.0)
	_request_screen_shake(SHAKE_KILL_ENEMY, 0.06)
	_maybe_drop_active_item(enemy.global_position)
	enemy.queue_free()


func _resolve_enemy_bullet_hits() -> void:
	var alive := _alive_players()
	var merge_targets := _active_merge_hitboxes()
	if alive.is_empty() and merge_targets.is_empty():
		return
	for bullet in _enemy_bullets:
		if bullet == null or not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			continue
		var bullet_node := bullet as Node2D
		var bullet_radius := float(bullet.call("hit_radius"))
		if _try_damage_merge_targets(merge_targets, bullet_node.global_position, bullet_radius):
			spawn_burst(bullet_node.global_position, Color(1.0, 0.42, 0.30, 0.9), 6, 110.0)
			_request_impact_feedback(SHAKE_HIT_PLAYER, 0.22, Color(1.0, 0.18, 0.12, 1.0), 0.24, 0.18)
			bullet.queue_free()
			continue
		for player in alive:
			var player_center: Vector2 = player.call("body_center")
			var player_radius := float(player.call("hit_radius"))
			if bullet_node.global_position.distance_to(player_center) > player_radius + bullet_radius:
				continue
			if bool(player.call("apply_damage", 1)):
				spawn_burst(bullet_node.global_position, Color(1.0, 0.42, 0.30, 0.9), 6, 110.0)
				_request_impact_feedback(SHAKE_HIT_PLAYER, 0.22, Color(1.0, 0.18, 0.12, 1.0), 0.24, 0.18)
				bullet.queue_free()
				break


func _resolve_contact_hits() -> void:
	var alive := _alive_players()
	var merge_targets := _active_merge_hitboxes()
	if alive.is_empty() and merge_targets.is_empty():
		return
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_radius := float(enemy.get("radius"))
		if _try_damage_merge_targets(merge_targets, enemy.global_position, enemy_radius):
			_request_impact_feedback(SHAKE_HIT_PLAYER, 0.20, Color(1.0, 0.18, 0.12, 1.0), 0.22, 0.16)
			if int(enemy.get("kind")) == ENEMY_SCRIPT.KIND_DART:
				_kill_enemy(enemy_id, enemy)
				continue
		for player in alive:
			var player_center: Vector2 = player.call("body_center")
			var player_radius := float(player.call("hit_radius"))
			if enemy.global_position.distance_to(player_center) > enemy_radius + player_radius:
				continue
			var hit := bool(player.call("apply_damage", 1))
			if hit:
				_request_impact_feedback(SHAKE_HIT_PLAYER, 0.20, Color(1.0, 0.18, 0.12, 1.0), 0.22, 0.16)
			if hit and int(enemy.get("kind")) == ENEMY_SCRIPT.KIND_DART:
				_kill_enemy(enemy_id, enemy)
				break
	if _boss != null and is_instance_valid(_boss):
		var boss_radius := float(_boss.get("radius"))
		if _try_damage_merge_targets(merge_targets, _boss.global_position, boss_radius):
			_request_impact_feedback(SHAKE_HIT_PLAYER, 0.24, Color(1.0, 0.18, 0.12, 1.0), 0.26, 0.18)
		for player in alive:
			var player_center: Vector2 = player.call("body_center")
			var player_radius := float(player.call("hit_radius"))
			if _boss.global_position.distance_to(player_center) <= boss_radius + player_radius:
				if bool(player.call("apply_damage", 1)):
					_request_impact_feedback(SHAKE_HIT_PLAYER, 0.24, Color(1.0, 0.18, 0.12, 1.0), 0.26, 0.18)
	for obstacle_id in _obstacles.keys():
		var obstacle := _obstacles.get(obstacle_id) as Node2D
		if obstacle == null or not is_instance_valid(obstacle):
			continue
		var obstacle_radius := float(obstacle.get("radius"))
		if _try_damage_merge_targets(merge_targets, obstacle.global_position, obstacle_radius):
			_request_impact_feedback(SHAKE_HIT_PLAYER, 0.20, Color(1.0, 0.30, 0.18, 1.0), 0.22, 0.16)
		for player in alive:
			var player_center: Vector2 = player.call("body_center")
			var player_radius := float(player.call("hit_radius"))
			if obstacle.global_position.distance_to(player_center) > obstacle_radius + player_radius:
				continue
			if bool(player.call("apply_damage", 1)):
				_request_impact_feedback(SHAKE_HIT_PLAYER, 0.20, Color(1.0, 0.30, 0.18, 1.0), 0.22, 0.16)
			player.call(
				"push_out_of_circle",
				obstacle.global_position,
				obstacle_radius,
				OBSTACLE_BLOCK_PADDING
			)


func _check_game_over() -> void:
	if _main == null:
		return
	var players: Dictionary = _main.call("player_nodes")
	if players.is_empty():
		return
	for peer_id in players.keys():
		var player := players[peer_id] as Node
		if player != null and is_instance_valid(player) and bool(player.get("alive")):
			return
	phase = Phase.GAME_OVER
	phase_changed.emit(Phase.GAME_OVER, {
		"time": battle_clock,
		"tier": tier,
		"boss_kills": boss_kills,
	})


func _tier_hp_scale() -> float:
	return 1.0 + 0.35 * float(tier)


func _tier_speed_scale() -> float:
	return minf(pow(1.06, float(tier)), 2.0)


func _tier_fire_interval_scale() -> float:
	return maxf(pow(0.94, float(tier)), 0.55)


func _tier_bullet_speed_scale() -> float:
	return minf(pow(1.05, float(tier)), 1.8)


func _tier_spawn_interval_scale() -> float:
	return maxf(pow(0.92, float(tier)), 0.28)
