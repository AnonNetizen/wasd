class_name SteamLabBattleDirector
extends Node2D

const ENEMY_SCRIPT := preload("res://scripts/enemy.gd")
const ENEMY_BULLET_SCRIPT := preload("res://scripts/enemy_bullet.gd")
const BURST_EFFECT_SCRIPT := preload("res://scripts/burst_effect.gd")

enum Phase { BATTLE, CHOOSING_BUFF, GAME_OVER }

const BUFF_FIRE_RATE: int = 0
const BUFF_DAMAGE: int = 1
const BUFF_MULTI_SHOT: int = 2
const BUFF_MOVE_SPEED: int = 3
const BUFF_HEAL: int = 4
const BUFF_BULLET_SPEED: int = 5
const BUFF_PIERCE: int = 6

const BUFF_DEFS: Array[Dictionary] = [
	{"id": BUFF_FIRE_RATE, "name": "射速强化", "desc": "开火冷却 ×0.85"},
	{"id": BUFF_DAMAGE, "name": "弹头强化", "desc": "子弹伤害 +1"},
	{"id": BUFF_MULTI_SHOT, "name": "多重散射", "desc": "每次多射出 1 颗子弹"},
	{"id": BUFF_MOVE_SPEED, "name": "机动强化", "desc": "移动速度 ×1.12"},
	{"id": BUFF_HEAL, "name": "紧急修复", "desc": "恢复 1 点生命"},
	{"id": BUFF_BULLET_SPEED, "name": "高速弹道", "desc": "子弹速度 ×1.2"},
	{"id": BUFF_PIERCE, "name": "穿透弹芯", "desc": "子弹可再穿透 1 个敌人"},
]

const BUFF_INTERVAL: float = 30.0
const BUFF_CHOICE_TIMEOUT: float = 20.0
const BOSS_INTERVAL: float = 300.0
const BASE_SPAWN_INTERVAL: float = 1.6
const WAVE_BURST_INTERVAL: float = 12.0
const OBSTACLE_INTERVAL_MIN: float = 8.0
const OBSTACLE_INTERVAL_MAX: float = 14.0
const MAX_ALIVE_ENEMIES: int = 28
const MAX_ALIVE_ENEMY_BULLETS: int = 160
const MAX_ALIVE_OBSTACLES: int = 5
const PLAYER_BASE_FIRE_COOLDOWN: float = 0.18
const PLAYER_MIN_FIRE_COOLDOWN: float = 0.06
const PLAYER_BASE_MOVE_SPEED: float = 340.0
const ENEMY_SPAWN_MARGIN: float = 40.0
const ENEMY_DESPAWN_MARGIN: float = 90.0

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


func setup(main: Node2D, session: Node, world_rect: Rect2) -> void:
	_main = main
	_session = session
	_world_rect = world_rect
	_rng.randomize()


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
	clear_entities()


func clear_entities() -> void:
	for enemy_id in _enemies.keys():
		var enemy := _enemies[enemy_id] as Node
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	for bullet in _enemy_bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()
	_enemy_bullets.clear()
	_player_bullets.clear()
	for child in get_children():
		if is_instance_valid(child):
			child.queue_free()


func is_authority() -> bool:
	if _session == null:
		return true
	return bool(_session.call("is_host")) or String(_session.call("active_transport")) == "offline"


func host_tick(delta: float) -> void:
	if phase != Phase.BATTLE:
		return
	battle_clock += delta
	_prune_entities()
	_update_spawning(delta)
	_advance_enemies(delta)
	_resolve_player_bullet_hits()
	_resolve_enemy_bullet_hits()
	_resolve_contact_hits()
	_check_game_over()


func register_player_bullet(bullet: Node) -> void:
	_player_bullets.append(bullet)


func battle_state() -> Dictionary:
	return {
		"phase": phase,
		"tier": tier,
		"time": battle_clock,
		"boss_kills": boss_kills,
		"enemy_count": _enemies.size(),
	}


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
	return maxf(PLAYER_BASE_FIRE_COOLDOWN * scale, PLAYER_MIN_FIRE_COOLDOWN)


func player_bullet_damage(peer_id: int) -> int:
	return 1 + _buff_stacks(peer_id, BUFF_DAMAGE)


func player_bullet_count(peer_id: int) -> int:
	return mini(1 + _buff_stacks(peer_id, BUFF_MULTI_SHOT), 5)


func player_move_speed_scale(peer_id: int) -> float:
	return minf(pow(1.12, float(_buff_stacks(peer_id, BUFF_MOVE_SPEED))), 1.8)


func player_bullet_speed_scale(peer_id: int) -> float:
	return minf(pow(1.2, float(_buff_stacks(peer_id, BUFF_BULLET_SPEED))), 2.2)


func player_pierce_count(peer_id: int) -> int:
	return _buff_stacks(peer_id, BUFF_PIERCE)


func spawn_burst(origin: Vector2, color: Color, shard_count: int, shard_speed: float) -> void:
	var burst := BURST_EFFECT_SCRIPT.new() as Node2D
	burst.name = "Burst%d" % _next_entity_id
	_next_entity_id += 1
	add_child(burst)
	burst.call("configure", origin, color, shard_count, shard_speed)


func set_battle_frozen(frozen: bool) -> void:
	for child in get_children():
		if is_instance_valid(child) and child.has_method("set_battle_frozen"):
			child.call("set_battle_frozen", frozen)


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
		if bool(player.get("alive")):
			alive.append(player)
	return alive


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
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = BASE_SPAWN_INTERVAL * _tier_spawn_interval_scale()
		if _enemies.size() < MAX_ALIVE_ENEMIES:
			_spawn_enemy(_roll_enemy_kind())
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = WAVE_BURST_INTERVAL
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


func _spawn_enemy_volley(origin: Vector2, directions: PackedVector2Array, bullet_speed: float) -> void:
	for direction in directions:
		var bullet := ENEMY_BULLET_SCRIPT.new() as Node2D
		bullet.name = "EnemyBullet%d" % _next_entity_id
		_next_entity_id += 1
		add_child(bullet)
		bullet.call("configure", origin, direction, bullet_speed, _world_rect)
		_enemy_bullets.append(bullet)


func _resolve_player_bullet_hits() -> void:
	for bullet in _player_bullets:
		if bullet == null or not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			continue
		if not bool(bullet.call("is_live_for_damage")):
			continue
		var bullet_node := bullet as Node2D
		var bullet_radius := float(bullet.call("hit_radius"))
		var damage := int(bullet.get("damage"))
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
			if bool(enemy.call("is_dead")):
				_kill_enemy(enemy_id, enemy)
			var pierce_remaining := int(bullet.get("pierce_remaining"))
			if pierce_remaining > 0:
				bullet.set("pierce_remaining", pierce_remaining - 1)
			else:
				bullet.queue_free()
				break


func _kill_enemy(enemy_id: int, enemy: Node2D) -> void:
	_enemies.erase(enemy_id)
	spawn_burst(enemy.global_position, Color(1.0, 0.62, 0.34, 0.9), 10, 150.0)
	enemy.queue_free()


func _resolve_enemy_bullet_hits() -> void:
	var alive := _alive_players()
	if alive.is_empty():
		return
	for bullet in _enemy_bullets:
		if bullet == null or not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			continue
		var bullet_node := bullet as Node2D
		var bullet_radius := float(bullet.call("hit_radius"))
		for player in alive:
			var player_center: Vector2 = player.call("body_center")
			var player_radius := float(player.call("hit_radius"))
			if bullet_node.global_position.distance_to(player_center) > player_radius + bullet_radius:
				continue
			if bool(player.call("apply_damage", 1)):
				spawn_burst(bullet_node.global_position, Color(1.0, 0.42, 0.30, 0.9), 6, 110.0)
				bullet.queue_free()
				break


func _resolve_contact_hits() -> void:
	var alive := _alive_players()
	if alive.is_empty():
		return
	for enemy_id in _enemies.keys():
		var enemy := _enemies.get(enemy_id) as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_radius := float(enemy.get("radius"))
		for player in alive:
			var player_center: Vector2 = player.call("body_center")
			var player_radius := float(player.call("hit_radius"))
			if enemy.global_position.distance_to(player_center) > enemy_radius + player_radius:
				continue
			var hit := bool(player.call("apply_damage", 1))
			if hit and int(enemy.get("kind")) == ENEMY_SCRIPT.KIND_DART:
				_kill_enemy(enemy_id, enemy)
				break


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
