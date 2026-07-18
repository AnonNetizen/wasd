extends Node2D

## Playable pure-neon geometry combat art experiment.
## The scene owns simulation, drawing, lightweight pools, capture state, and smoke hooks.

const NeonGeometryActor := preload("res://scripts/neon_geometry_actor.gd")
const NeonGeometryProjectile := preload("res://scripts/neon_geometry_projectile.gd")

const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const ARENA_RECT := Rect2(Vector2(64.0, 74.0), Vector2(1152.0, 626.0))
const PLAYER_SPAWN := Vector2(640.0, 586.0)
const RING_HUNTER_SPAWN := Vector2(286.0, 230.0)
const TRI_AXIS_SPAWN := Vector2(994.0, 224.0)
const UPGRADE_POSITION := Vector2(640.0, 314.0)
const BACKGROUND_SEED: int = 20_260_718

const PLAYER_SPEED := 300.0
const PLAYER_MAX_HP := 5
const PLAYER_FIRE_INTERVAL := 0.11
const PLAYER_PROJECTILE_SPEED := 720.0
const PLAYER_PROJECTILE_LIFETIME := 1.3
const PLAYER_RESPAWN_DELAY := 1.2
const PLAYER_RESPAWN_INVULNERABILITY := 0.8
const RING_HUNTER_SPEED := 120.0
const RING_HUNTER_MAX_HP := 4
const RING_HUNTER_WARNING := 0.45
const RING_HUNTER_ATTACK_INTERVAL := 1.65
const ENEMY_WEDGE_SPEED := 320.0
const ENEMY_WEDGE_LIFETIME := 2.0
const TRI_AXIS_SPEED := 70.0
const TRI_AXIS_MAX_HP := 7
const TRI_AXIS_WARNING := 0.6
const TRI_AXIS_ATTACK_INTERVAL := 2.2
const ENEMY_RING_SPEED := 190.0
const ENEMY_RING_LIFETIME := 4.2
const ENEMY_RESPAWN_DELAY := 1.0
const PLAYER_POOL_SIZE := 48
const ENEMY_POOL_SIZE := 48
const VFX_POOL_SIZE := 64

const ACTION_LEFT := "lab_neon_move_left"
const ACTION_RIGHT := "lab_neon_move_right"
const ACTION_UP := "lab_neon_move_up"
const ACTION_DOWN := "lab_neon_move_down"
const ACTION_FIRE := "lab_neon_fire"
const ACTION_RESET := "lab_neon_reset"
const ACTION_BACK := "lab_back"

const COLOR_BACKGROUND := Color("05040b")
const COLOR_BACKGROUND_ALT := Color("0b0820")
const COLOR_GRID := Color("241b46")
const COLOR_BORDER := Color("4b3277")
const COLOR_PLAYER := Color("f4b94f")
const COLOR_PLAYER_CORE := Color("ffe58a")
const COLOR_PLAYER_ACCENT := Color("9d6cff")
const COLOR_HUNTER := Color("ff3d7f")
const COLOR_HUNTER_CORE := Color("ff8bb1")
const COLOR_GUNNER := Color("4de1ff")
const COLOR_GUNNER_CORE := Color("b5f5ff")
const COLOR_ENEMY_PROJECTILE := Color("ff405f")
const COLOR_UPGRADE := Color("5fffc1")
const COLOR_TEXT := Color("dcd7f2")
const COLOR_TEXT_DIM := Color("82799f")

var _player: NeonGeometryActor
var _ring_hunter: NeonGeometryActor
var _tri_axis: NeonGeometryActor
var _actors: Array[NeonGeometryActor] = []
var _player_projectiles: Array[NeonGeometryProjectile] = []
var _enemy_projectiles: Array[NeonGeometryProjectile] = []
var _vfx_slots: Array[Dictionary] = []
var _background_points: Array[Dictionary] = []
var _player_trail: Array[Vector2] = []
var _upgrade_active: bool = false
var _player_fire_cooldown: float = 0.0
var _elapsed: float = 0.0
var _spawn_serial: int = 0
var _vfx_spawn_serial: int = 0
var _capture_mode: bool = false
var _capture_cursor_position := Vector2(640.0, 180.0)


func _ready() -> void:
	_register_input_actions()
	_build_background()
	_build_actor_data()
	_build_pools()
	debug_reset_scene()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	queue_redraw()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	var safe_delta := minf(delta, 0.05)
	_elapsed += safe_delta
	if Input.is_action_just_pressed(ACTION_BACK) and not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")
		return
	if Input.is_action_just_pressed(ACTION_RESET) and not _capture_mode:
		debug_reset_scene()

	_update_actor_timers(safe_delta)
	_update_player(safe_delta)
	_update_enemies(safe_delta)
	_update_projectiles(safe_delta)
	_update_vfx(safe_delta)
	_update_pickup()
	_update_player_trail()
	queue_redraw()


func debug_reset_scene() -> void:
	_elapsed = 0.0
	_spawn_serial = 0
	_vfx_spawn_serial = 0
	_capture_mode = false
	_upgrade_active = false
	_player_fire_cooldown = 0.0
	_player.reset_actor()
	_ring_hunter.reset_actor()
	_tri_axis.reset_actor()
	_ring_hunter.attack_cooldown = 0.7
	_tri_axis.attack_cooldown = 1.15
	for projectile: NeonGeometryProjectile in _player_projectiles:
		projectile.deactivate()
	for projectile: NeonGeometryProjectile in _enemy_projectiles:
		projectile.deactivate()
	for slot: Dictionary in _vfx_slots:
		slot["active"] = false
	_player_trail.clear()
	for _index in range(10):
		_player_trail.append(_player.position)
	queue_redraw()


func debug_activate_upgrade() -> void:
	if _upgrade_active:
		return
	_upgrade_active = true
	_spawn_pulse(UPGRADE_POSITION, COLOR_UPGRADE, 0.55, 54.0)
	_spawn_shards(UPGRADE_POSITION, COLOR_UPGRADE, 12, Vector2.UP)


func debug_prepare_capture() -> void:
	debug_reset_scene()
	_capture_mode = true
	debug_activate_upgrade()
	_player.position = Vector2(640.0, 564.0)
	_player.aim_toward(Vector2(640.0, 180.0))
	_ring_hunter.position = Vector2(330.0, 248.0)
	_ring_hunter.aim_toward(_player.position)
	_tri_axis.position = Vector2(956.0, 230.0)
	_tri_axis.aim_toward(_player.position)
	_ring_hunter.warning_remaining = RING_HUNTER_WARNING * 0.72
	_ring_hunter.attack_pending = true
	_tri_axis.warning_remaining = TRI_AXIS_WARNING * 0.58
	_tri_axis.attack_pending = true
	for offset in [-22.0, 0.0, 22.0]:
		_spawn_player_volley(_player.position + Vector2(offset, -18.0), Vector2.UP)
	_fire_ring_hunter()
	_fire_tri_axis()
	_spawn_pulse(_player.position, COLOR_PLAYER_ACCENT, 0.7, 46.0)
	queue_redraw()


func debug_force_defeat(target_index: int) -> void:
	if target_index < 0 or target_index >= _actors.size():
		return
	var actor: NeonGeometryActor = _actors[target_index]
	if actor.alive:
		_defeat_actor(actor)


func debug_apply_hit(target_index: int) -> void:
	if target_index < 0 or target_index >= _actors.size():
		return
	var actor: NeonGeometryActor = _actors[target_index]
	if not actor.alive:
		return
	var defeated := actor.apply_damage(1)
	_spawn_hit(actor.position, _actor_color(actor), -actor.aim_direction)
	if defeated:
		_defeat_actor(actor)


func debug_state() -> Dictionary:
	return {
		"actor_count": _actors.size(),
		"active_enemy_count": int(_ring_hunter.alive) + int(_tri_axis.alive),
		"player_alive": _player.alive,
		"player_hp": _player.hp,
		"player_hit_flash_remaining": _player.hit_flash_remaining,
		"player_position": _player.position,
		"enemy_positions": [_ring_hunter.position, _tri_axis.position],
		"actor_motion_phases": [
			_player.motion_phase,
			_ring_hunter.motion_phase,
			_tri_axis.motion_phase,
		],
		"background_seed": BACKGROUND_SEED,
		"simulation_elapsed": _elapsed,
		"upgrade_active": _upgrade_active,
		"player_modules_expanded": _upgrade_active,
		"current_volley_size": 3 if _upgrade_active else 1,
		"player_projectile_count": _count_projectiles(
			_player_projectiles,
			NeonGeometryProjectile.ProjectileKind.PLAYER_BOLT
		),
		"enemy_wedge_count": _count_projectiles(
			_enemy_projectiles,
			NeonGeometryProjectile.ProjectileKind.ENEMY_WEDGE
		),
		"enemy_ring_count": _count_projectiles(
			_enemy_projectiles,
			NeonGeometryProjectile.ProjectileKind.ENEMY_RING
		),
		"player_pool_size": _player_projectiles.size(),
		"enemy_pool_size": _enemy_projectiles.size(),
		"vfx_pool_size": _vfx_slots.size(),
		"active_vfx_count": _count_active_vfx(),
		"projectile_teams_valid": _projectile_teams_are_valid(),
		"player_respawn_remaining": _player.respawn_remaining,
		"player_invulnerability_remaining": _player.invulnerability_remaining,
	}


func _draw() -> void:
	_draw_background()
	_draw_player_trail()
	_draw_upgrade_pickup()
	_draw_projectile_pool(_player_projectiles)
	_draw_projectile_pool(_enemy_projectiles)
	_draw_vfx()
	_draw_actor(_ring_hunter)
	_draw_actor(_tri_axis)
	_draw_actor(_player)
	_draw_crosshair()
	_draw_hud()


func _build_actor_data() -> void:
	_player = NeonGeometryActor.new() as NeonGeometryActor
	_player.configure(
		NeonGeometryActor.ActorKind.PLAYER,
		PLAYER_SPAWN,
		PLAYER_MAX_HP,
		18.0
	)
	_ring_hunter = NeonGeometryActor.new() as NeonGeometryActor
	_ring_hunter.configure(
		NeonGeometryActor.ActorKind.RING_HUNTER,
		RING_HUNTER_SPAWN,
		RING_HUNTER_MAX_HP,
		22.0,
		0.8
	)
	_tri_axis = NeonGeometryActor.new() as NeonGeometryActor
	_tri_axis.configure(
		NeonGeometryActor.ActorKind.TRI_AXIS_GUNNER,
		TRI_AXIS_SPAWN,
		TRI_AXIS_MAX_HP,
		28.0,
		1.7
	)
	_actors.assign([_player, _ring_hunter, _tri_axis])


func _build_pools() -> void:
	for _index in range(PLAYER_POOL_SIZE):
		_player_projectiles.append(NeonGeometryProjectile.new() as NeonGeometryProjectile)
	for _index in range(ENEMY_POOL_SIZE):
		_enemy_projectiles.append(NeonGeometryProjectile.new() as NeonGeometryProjectile)
	for _index in range(VFX_POOL_SIZE):
		_vfx_slots.append({
			"active": false,
			"kind": 0,
			"position": Vector2.ZERO,
			"velocity": Vector2.ZERO,
			"lifetime": 0.0,
			"initial_lifetime": 0.0,
			"color": Color.WHITE,
			"size": 1.0,
			"spawn_serial": 0,
		})


func _build_background() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = BACKGROUND_SEED
	for _index in range(70):
		_background_points.append({
			"position": Vector2(
				random.randf_range(ARENA_RECT.position.x, ARENA_RECT.end.x),
				random.randf_range(ARENA_RECT.position.y, ARENA_RECT.end.y)
			),
			"radius": random.randf_range(0.7, 2.2),
			"phase": random.randf_range(0.0, TAU),
			"accent": random.randi_range(0, 4) == 0,
		})


func _update_actor_timers(delta: float) -> void:
	for actor: NeonGeometryActor in _actors:
		actor.tick_timers(delta)
		actor.motion_phase += delta
		if actor.alive or actor.respawn_remaining > 0.0:
			continue
		var invulnerability := PLAYER_RESPAWN_INVULNERABILITY if actor == _player else 0.0
		actor.reset_actor(invulnerability)
		_spawn_pulse(actor.position, _actor_color(actor), 0.65, actor.hit_radius * 2.7)


func _update_player(delta: float) -> void:
	_player_fire_cooldown = maxf(_player_fire_cooldown - delta, 0.0)
	if not _player.alive:
		return

	var cursor_position := _capture_cursor_position if _capture_mode else get_global_mouse_position()
	_player.aim_toward(cursor_position)
	if _capture_mode:
		_player.velocity = Vector2.ZERO
		return

	var input_vector := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	_player.velocity = input_vector * PLAYER_SPEED
	_player.position += _player.velocity * delta
	_player.position = _clamp_to_arena(_player.position, _player.hit_radius)
	if Input.is_action_pressed(ACTION_FIRE) and _player_fire_cooldown <= 0.0:
		_spawn_player_volley(_player.position, _player.aim_direction)
		_player_fire_cooldown = PLAYER_FIRE_INTERVAL


func _update_enemies(delta: float) -> void:
	if not _player.alive:
		return
	_update_ring_hunter(delta)
	_update_tri_axis(delta)


func _update_ring_hunter(delta: float) -> void:
	if not _ring_hunter.alive:
		return
	_ring_hunter.aim_toward(_player.position)
	var toward_player := _ring_hunter.position.direction_to(_player.position)
	var tangent := toward_player.orthogonal() * sin(_elapsed * 1.7 + _ring_hunter.motion_phase)
	var movement := (toward_player + tangent * 0.42).normalized()
	_ring_hunter.velocity = movement * RING_HUNTER_SPEED
	if not _capture_mode:
		_ring_hunter.position += _ring_hunter.velocity * delta
		_ring_hunter.position = _clamp_to_arena(_ring_hunter.position, _ring_hunter.hit_radius)
	if _ring_hunter.attack_pending and _ring_hunter.warning_remaining <= 0.0:
		_fire_ring_hunter()
		_ring_hunter.attack_pending = false
		_ring_hunter.attack_cooldown = RING_HUNTER_ATTACK_INTERVAL
	elif not _ring_hunter.attack_pending and _ring_hunter.attack_cooldown <= 0.0:
		_ring_hunter.warning_remaining = RING_HUNTER_WARNING
		_ring_hunter.attack_pending = true


func _update_tri_axis(delta: float) -> void:
	if not _tri_axis.alive:
		return
	_tri_axis.aim_toward(_player.position)
	var offset := _player.position - _tri_axis.position
	var distance := offset.length()
	var radial := offset.normalized() if distance > 0.01 else Vector2.RIGHT
	var tangent := radial.orthogonal()
	var distance_push := clampf((distance - 360.0) / 140.0, -1.0, 1.0)
	var movement := (radial * distance_push + tangent * 0.36).normalized()
	_tri_axis.velocity = movement * TRI_AXIS_SPEED
	if not _capture_mode:
		_tri_axis.position += _tri_axis.velocity * delta
		_tri_axis.position = _clamp_to_arena(_tri_axis.position, _tri_axis.hit_radius)
	if _tri_axis.attack_pending and _tri_axis.warning_remaining <= 0.0:
		_fire_tri_axis()
		_tri_axis.attack_pending = false
		_tri_axis.attack_cooldown = TRI_AXIS_ATTACK_INTERVAL
	elif not _tri_axis.attack_pending and _tri_axis.attack_cooldown <= 0.0:
		_tri_axis.warning_remaining = TRI_AXIS_WARNING
		_tri_axis.attack_pending = true


func _update_projectiles(delta: float) -> void:
	for projectile: NeonGeometryProjectile in _player_projectiles:
		projectile.tick(delta)
		if projectile.active and not ARENA_RECT.grow(80.0).has_point(projectile.position):
			projectile.deactivate()
	for projectile: NeonGeometryProjectile in _enemy_projectiles:
		projectile.tick(delta)
		if projectile.active and not ARENA_RECT.grow(80.0).has_point(projectile.position):
			projectile.deactivate()
	_resolve_player_projectile_hits()
	_resolve_enemy_projectile_hits()


func _update_vfx(delta: float) -> void:
	for slot: Dictionary in _vfx_slots:
		if not bool(slot["active"]):
			continue
		var lifetime: float = float(slot["lifetime"]) - delta
		slot["lifetime"] = lifetime
		if lifetime <= 0.0:
			slot["active"] = false
			continue
		slot["position"] = (slot["position"] as Vector2) + (slot["velocity"] as Vector2) * delta
		slot["velocity"] = (slot["velocity"] as Vector2) * pow(0.08, delta)


func _update_pickup() -> void:
	if _upgrade_active or not _player.alive:
		return
	if _player.position.distance_to(UPGRADE_POSITION) <= _player.hit_radius + 24.0:
		debug_activate_upgrade()


func _update_player_trail() -> void:
	if not _player.alive:
		return
	_player_trail.push_front(_player.position)
	while _player_trail.size() > 10:
		_player_trail.pop_back()


func _spawn_player_volley(origin: Vector2, direction: Vector2) -> void:
	var base_direction := direction.normalized()
	var angles: Array[float] = [0.0]
	if _upgrade_active:
		angles.assign([deg_to_rad(-10.0), 0.0, deg_to_rad(10.0)])
	for angle_offset: float in angles:
		var shot_direction := base_direction.rotated(angle_offset)
		_spawn_projectile(
			_player_projectiles,
			NeonGeometryProjectile.ProjectileKind.PLAYER_BOLT,
			NeonGeometryProjectile.Team.PLAYER,
			origin + shot_direction * 31.0,
			shot_direction * PLAYER_PROJECTILE_SPEED,
			PLAYER_PROJECTILE_LIFETIME
		)
	_spawn_muzzle(origin + base_direction * 28.0, base_direction)


func _fire_ring_hunter() -> void:
	if not _ring_hunter.alive or not _player.alive:
		return
	var base_direction := _ring_hunter.position.direction_to(_player.position)
	for angle_offset in [-12.0, 0.0, 12.0]:
		var shot_direction := base_direction.rotated(deg_to_rad(float(angle_offset)))
		_spawn_projectile(
			_enemy_projectiles,
			NeonGeometryProjectile.ProjectileKind.ENEMY_WEDGE,
			NeonGeometryProjectile.Team.ENEMY,
			_ring_hunter.position + shot_direction * 28.0,
			shot_direction * ENEMY_WEDGE_SPEED,
			ENEMY_WEDGE_LIFETIME
		)
	_spawn_pulse(_ring_hunter.position, COLOR_HUNTER, 0.28, 32.0)


func _fire_tri_axis() -> void:
	if not _tri_axis.alive or not _player.alive:
		return
	var base_direction := _tri_axis.position.direction_to(_player.position)
	for angle_offset in [-24.0, -12.0, 0.0, 12.0, 24.0]:
		var shot_direction := base_direction.rotated(deg_to_rad(float(angle_offset)))
		_spawn_projectile(
			_enemy_projectiles,
			NeonGeometryProjectile.ProjectileKind.ENEMY_RING,
			NeonGeometryProjectile.Team.ENEMY,
			_tri_axis.position + shot_direction * 35.0,
			shot_direction * ENEMY_RING_SPEED,
			ENEMY_RING_LIFETIME
		)
	_spawn_pulse(_tri_axis.position, COLOR_ENEMY_PROJECTILE, 0.42, 42.0)


func _spawn_projectile(
	pool: Array[NeonGeometryProjectile],
	kind: NeonGeometryProjectile.ProjectileKind,
	team: NeonGeometryProjectile.Team,
	origin: Vector2,
	velocity: Vector2,
	lifetime: float
) -> void:
	_spawn_serial += 1
	var projectile := _acquire_projectile(pool)
	projectile.activate(kind, team, origin, velocity, lifetime, _spawn_serial)


func _acquire_projectile(pool: Array[NeonGeometryProjectile]) -> NeonGeometryProjectile:
	var oldest: NeonGeometryProjectile = pool[0]
	for projectile: NeonGeometryProjectile in pool:
		if not projectile.active:
			return projectile
		if projectile.spawn_serial < oldest.spawn_serial:
			oldest = projectile
	oldest.deactivate()
	return oldest


func _resolve_player_projectile_hits() -> void:
	for projectile: NeonGeometryProjectile in _player_projectiles:
		if not projectile.active:
			continue
		for enemy: NeonGeometryActor in [_ring_hunter, _tri_axis]:
			if not enemy.alive:
				continue
			if projectile.position.distance_to(enemy.position) > projectile.hit_radius + enemy.hit_radius:
				continue
			projectile.deactivate()
			var defeated := enemy.apply_damage(1)
			_spawn_hit(projectile.position, COLOR_PLAYER, projectile.velocity.normalized())
			if defeated:
				_defeat_actor(enemy)
			break


func _resolve_enemy_projectile_hits() -> void:
	if not _player.alive:
		return
	for projectile: NeonGeometryProjectile in _enemy_projectiles:
		if not projectile.active:
			continue
		if projectile.position.distance_to(_player.position) > projectile.hit_radius + _player.hit_radius:
			continue
		var old_hp := _player.hp
		var defeated := _player.apply_damage(1)
		if _player.hp == old_hp:
			continue
		projectile.deactivate()
		_spawn_hit(projectile.position, COLOR_ENEMY_PROJECTILE, projectile.velocity.normalized())
		if defeated:
			_defeat_actor(_player)


func _defeat_actor(actor: NeonGeometryActor) -> void:
	var actor_position := actor.position
	var color := _actor_color(actor)
	var shard_count := 14 if actor == _tri_axis else 10
	_spawn_shards(actor_position, color, shard_count, actor.aim_direction)
	_spawn_pulse(actor_position, color, 0.58, actor.hit_radius * 3.2)
	var delay := PLAYER_RESPAWN_DELAY if actor == _player else ENEMY_RESPAWN_DELAY
	actor.defeat(delay)


func _spawn_muzzle(position: Vector2, direction: Vector2) -> void:
	for sign_value in [-1.0, 1.0]:
		var tangent := direction.orthogonal() * float(sign_value)
		_spawn_vfx(0, position, direction * 92.0 + tangent * 74.0, 0.12, COLOR_PLAYER_CORE, 7.0)


func _spawn_hit(position: Vector2, color: Color, direction: Vector2) -> void:
	_spawn_pulse(position, color, 0.22, 24.0)
	_spawn_shards(position, color, 5, direction)


func _spawn_shards(position: Vector2, color: Color, count: int, bias: Vector2) -> void:
	var base_angle := bias.angle() if not bias.is_zero_approx() else 0.0
	for index in range(count):
		var ratio := float(index) / float(maxi(count, 1))
		var angle := base_angle + ratio * TAU + sin(float(_spawn_serial + index) * 1.73) * 0.22
		var speed := 82.0 + float(index % 4) * 24.0
		_spawn_vfx(0, position, Vector2.from_angle(angle) * speed, 0.34 + float(index % 3) * 0.05, color, 5.0)


func _spawn_pulse(position: Vector2, color: Color, lifetime: float, size: float) -> void:
	_spawn_vfx(1, position, Vector2.ZERO, lifetime, color, size)


func _spawn_vfx(
	kind: int,
	position: Vector2,
	velocity: Vector2,
	lifetime: float,
	color: Color,
	size: float
) -> void:
	_vfx_spawn_serial += 1
	var slot := _acquire_vfx_slot()
	slot["active"] = true
	slot["kind"] = kind
	slot["position"] = position
	slot["velocity"] = velocity
	slot["lifetime"] = lifetime
	slot["initial_lifetime"] = lifetime
	slot["color"] = color
	slot["size"] = size
	slot["spawn_serial"] = _vfx_spawn_serial


func _acquire_vfx_slot() -> Dictionary:
	var oldest: Dictionary = _vfx_slots[0]
	for slot: Dictionary in _vfx_slots:
		if not bool(slot["active"]):
			return slot
		if int(slot["spawn_serial"]) < int(oldest["spawn_serial"]):
			oldest = slot
	oldest["active"] = false
	return oldest


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), COLOR_BACKGROUND, true)
	for band in range(8):
		var inset := float(band) * 12.0
		var alpha := 0.045 - float(band) * 0.004
		draw_rect(
			ARENA_RECT.grow(-inset),
			Color(COLOR_BACKGROUND_ALT.r, COLOR_BACKGROUND_ALT.g, COLOR_BACKGROUND_ALT.b, alpha),
			false,
			1.0
		)
	for x_index in range(15):
		var x := ARENA_RECT.position.x + float(x_index) * ARENA_RECT.size.x / 14.0
		draw_line(
			Vector2(x, ARENA_RECT.position.y),
			Vector2(x, ARENA_RECT.end.y),
			Color(COLOR_GRID.r, COLOR_GRID.g, COLOR_GRID.b, 0.22),
			1.0
		)
	for y_index in range(9):
		var y := ARENA_RECT.position.y + float(y_index) * ARENA_RECT.size.y / 8.0
		draw_line(
			Vector2(ARENA_RECT.position.x, y),
			Vector2(ARENA_RECT.end.x, y),
			Color(COLOR_GRID.r, COLOR_GRID.g, COLOR_GRID.b, 0.18),
			1.0
		)
	for point: Dictionary in _background_points:
		var pulse := 0.45 + 0.35 * sin(_elapsed * 0.75 + float(point["phase"]))
		var color := COLOR_PLAYER_ACCENT if bool(point["accent"]) else COLOR_GUNNER
		draw_circle(
			point["position"] as Vector2,
			float(point["radius"]),
			Color(color.r, color.g, color.b, pulse * 0.22)
		)
	var orbit_center := Vector2(640.0, 370.0)
	for orbit_index in range(3):
		var radius := 170.0 + float(orbit_index) * 118.0
		var start_angle := _elapsed * (0.025 + float(orbit_index) * 0.012) + float(orbit_index)
		draw_arc(
			orbit_center,
			radius,
			start_angle,
			start_angle + PI * 0.66,
			80,
			Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.09),
			1.0,
			true
		)
	_draw_glow_rect(ARENA_RECT, COLOR_BORDER)


func _draw_glow_rect(rect: Rect2, color: Color) -> void:
	for width in [9.0, 5.0]:
		draw_rect(rect, Color(color.r, color.g, color.b, 0.035), false, width)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.55), false, 1.5)


func _draw_player_trail() -> void:
	if not _player.alive or _player_trail.size() < 2:
		return
	for index in range(_player_trail.size() - 1):
		var alpha := (1.0 - float(index) / float(_player_trail.size())) * 0.19
		draw_line(
			_player_trail[index],
			_player_trail[index + 1],
			Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, alpha),
			5.0 - float(index) * 0.34,
			true
		)


func _draw_upgrade_pickup() -> void:
	if _upgrade_active:
		return
	var spin := _elapsed * 1.2
	var outer := _regular_polygon(UPGRADE_POSITION, 27.0, 4, spin + PI * 0.25)
	var inner := _regular_polygon(UPGRADE_POSITION, 13.0, 4, -spin + PI * 0.25)
	_draw_glow_polyline(_close_polygon(outer), COLOR_UPGRADE, 2.0)
	draw_colored_polygon(inner, Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.55))
	draw_arc(
		UPGRADE_POSITION,
		38.0 + sin(_elapsed * 2.5) * 3.0,
		spin,
		spin + PI * 1.35,
		32,
		Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.32),
		2.0,
		true
	)


func _draw_actor(actor: NeonGeometryActor) -> void:
	if not actor.alive:
		return
	match actor.kind:
		NeonGeometryActor.ActorKind.PLAYER:
			_draw_player_actor(actor)
		NeonGeometryActor.ActorKind.RING_HUNTER:
			_draw_ring_hunter(actor)
		NeonGeometryActor.ActorKind.TRI_AXIS_GUNNER:
			_draw_tri_axis(actor)


func _draw_player_actor(actor: NeonGeometryActor) -> void:
	var angle := actor.aim_direction.angle()
	var pulse := 1.0 + sin(_elapsed * 4.0) * 0.035
	var body := PackedVector2Array([
		Vector2(35.0, 0.0),
		Vector2(6.0, -11.0),
		Vector2(-16.0, -15.0),
		Vector2(-25.0, 0.0),
		Vector2(-16.0, 15.0),
		Vector2(6.0, 11.0),
	])
	body = _transform_points(body, actor.position, angle, pulse)
	_draw_glow_polygon(body, COLOR_PLAYER)
	var core := _regular_polygon(actor.position, 10.0, 5, angle)
	_draw_glow_polygon(core, COLOR_PLAYER_CORE)
	var module_offset := 26.0 if _upgrade_active else 20.0
	for side in [-1.0, 1.0]:
		var local_module := PackedVector2Array([
			Vector2(4.0, float(side) * module_offset),
			Vector2(-16.0, float(side) * (module_offset + 7.0)),
			Vector2(-10.0, float(side) * (module_offset - 6.0)),
		])
		_draw_glow_polygon(_transform_points(local_module, actor.position, angle, 1.0), COLOR_PLAYER_ACCENT)
	if actor.invulnerability_remaining > 0.0:
		var alpha := 0.25 + 0.25 * sin(_elapsed * 18.0)
		draw_arc(
			actor.position,
			31.0,
			0.0,
			TAU,
			48,
			Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, alpha),
			2.0,
			true
		)
	_draw_hit_flash(actor)


func _draw_ring_hunter(actor: NeonGeometryActor) -> void:
	var facing := actor.aim_direction.angle()
	var rotation_offset := _elapsed * 0.58 + actor.motion_phase * 0.18
	for segment_index in range(7):
		var segment_start := facing + deg_to_rad(56.0) + float(segment_index) * deg_to_rad(38.0) + rotation_offset
		var segment_end := segment_start + deg_to_rad(25.0)
		for width in [9.0, 5.0]:
			draw_arc(
				actor.position,
				30.0 + sin(_elapsed * 2.7 + float(segment_index)) * 2.0,
				segment_start,
				segment_end,
				8,
				Color(COLOR_HUNTER.r, COLOR_HUNTER.g, COLOR_HUNTER.b, 0.055),
				width,
				true
			)
		draw_arc(
			actor.position,
			30.0 + sin(_elapsed * 2.7 + float(segment_index)) * 2.0,
			segment_start,
			segment_end,
			8,
			COLOR_HUNTER,
			3.0,
			true
		)
	var mouth_start := actor.position + actor.aim_direction * 12.0
	var mouth_end := actor.position + actor.aim_direction * 34.0
	_draw_glow_line(mouth_start, mouth_end, COLOR_HUNTER_CORE, 3.0)
	draw_circle(actor.position, 7.0, COLOR_HUNTER_CORE)
	if actor.warning_remaining > 0.0:
		var ratio := 1.0 - actor.warning_remaining / RING_HUNTER_WARNING
		_draw_warning_fan(actor.position, facing, ratio, 84.0, deg_to_rad(34.0))
	_draw_hit_flash(actor)


func _draw_tri_axis(actor: NeonGeometryActor) -> void:
	var base_rotation := _elapsed * -0.72 + actor.motion_phase * 0.22
	for arm_index in range(3):
		var arm_angle := base_rotation + float(arm_index) * TAU / 3.0
		var arm_length := 42.0 if arm_index == 0 else 32.0
		var arm_end := actor.position + Vector2.from_angle(arm_angle) * arm_length
		_draw_glow_line(actor.position, arm_end, COLOR_GUNNER, 4.0)
		var triangle := PackedVector2Array([
			Vector2(10.0, 0.0),
			Vector2(-6.0, -6.0),
			Vector2(-6.0, 6.0),
		])
		var arm_color := COLOR_ENEMY_PROJECTILE if actor.warning_remaining > 0.0 and arm_index == 0 else COLOR_GUNNER
		_draw_glow_polygon(_transform_points(triangle, arm_end, arm_angle, 1.0), arm_color)
	var core := _regular_polygon(actor.position, 13.0, 6, -base_rotation * 0.55)
	_draw_glow_polygon(core, COLOR_GUNNER_CORE)
	if actor.warning_remaining > 0.0:
		var ratio := 1.0 - actor.warning_remaining / TRI_AXIS_WARNING
		var line_end := actor.position + actor.aim_direction * lerpf(78.0, 170.0, ratio)
		_draw_glow_line(actor.position, line_end, COLOR_ENEMY_PROJECTILE, 1.5)
		draw_arc(
			actor.position,
			48.0,
			-base_rotation,
			-base_rotation + TAU * ratio,
			42,
			Color(COLOR_ENEMY_PROJECTILE.r, COLOR_ENEMY_PROJECTILE.g, COLOR_ENEMY_PROJECTILE.b, 0.72),
			2.0,
			true
		)
	_draw_hit_flash(actor)


func _draw_hit_flash(actor: NeonGeometryActor) -> void:
	if actor.hit_flash_remaining <= 0.0:
		return
	var ratio := actor.hit_flash_remaining / 0.11
	draw_circle(actor.position, actor.hit_radius + 7.0, Color(1.0, 1.0, 1.0, ratio * 0.55), false, 3.0)


func _draw_warning_fan(origin: Vector2, angle: float, ratio: float, radius: float, half_angle: float) -> void:
	var color := Color(COLOR_ENEMY_PROJECTILE.r, COLOR_ENEMY_PROJECTILE.g, COLOR_ENEMY_PROJECTILE.b, 0.25 + ratio * 0.55)
	draw_arc(origin, radius, angle - half_angle, angle + half_angle, 24, color, 2.0, true)
	draw_line(origin, origin + Vector2.from_angle(angle - half_angle) * radius, color, 1.5, true)
	draw_line(origin, origin + Vector2.from_angle(angle + half_angle) * radius, color, 1.5, true)


func _draw_projectile_pool(pool: Array[NeonGeometryProjectile]) -> void:
	for projectile: NeonGeometryProjectile in pool:
		if not projectile.active:
			continue
		match projectile.kind:
			NeonGeometryProjectile.ProjectileKind.PLAYER_BOLT:
				_draw_player_projectile(projectile)
			NeonGeometryProjectile.ProjectileKind.ENEMY_WEDGE:
				_draw_enemy_wedge(projectile)
			NeonGeometryProjectile.ProjectileKind.ENEMY_RING:
				_draw_enemy_ring(projectile)


func _draw_player_projectile(projectile: NeonGeometryProjectile) -> void:
	var angle := projectile.facing_angle()
	var diamond := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(0.0, -4.0),
		Vector2(-13.0, 0.0),
		Vector2(0.0, 4.0),
	])
	var points := _transform_points(diamond, projectile.position, angle, 1.0)
	_draw_glow_polygon(points, COLOR_PLAYER_CORE)
	var tail_end := projectile.position - projectile.velocity.normalized() * 23.0
	_draw_glow_line(projectile.position, tail_end, COLOR_PLAYER_ACCENT, 2.0)


func _draw_enemy_wedge(projectile: NeonGeometryProjectile) -> void:
	var wedge := PackedVector2Array([
		Vector2(11.0, 0.0),
		Vector2(-8.0, -7.0),
		Vector2(-3.0, 0.0),
		Vector2(-8.0, 7.0),
	])
	_draw_glow_polygon(_transform_points(wedge, projectile.position, projectile.facing_angle(), 1.0), COLOR_ENEMY_PROJECTILE)


func _draw_enemy_ring(projectile: NeonGeometryProjectile) -> void:
	var spin := projectile.facing_angle() + _elapsed * 2.1
	var points := _regular_polygon(projectile.position, 12.0, 8, spin)
	var broken := PackedVector2Array()
	for index in range(1, points.size()):
		broken.append(points[index])
	_draw_glow_polyline(broken, COLOR_ENEMY_PROJECTILE, 2.4)
	draw_circle(projectile.position, 2.2, Color(COLOR_ENEMY_PROJECTILE.r, COLOR_ENEMY_PROJECTILE.g, COLOR_ENEMY_PROJECTILE.b, 0.82))


func _draw_vfx() -> void:
	for slot: Dictionary in _vfx_slots:
		if not bool(slot["active"]):
			continue
		var lifetime: float = float(slot["lifetime"])
		var initial_lifetime: float = maxf(float(slot["initial_lifetime"]), 0.001)
		var ratio := clampf(lifetime / initial_lifetime, 0.0, 1.0)
		var color: Color = slot["color"] as Color
		var position: Vector2 = slot["position"] as Vector2
		var size: float = float(slot["size"])
		if int(slot["kind"]) == 0:
			var velocity: Vector2 = slot["velocity"] as Vector2
			var direction := velocity.normalized() if not velocity.is_zero_approx() else Vector2.RIGHT
			var side := direction.orthogonal() * size * 0.42
			var shard := PackedVector2Array([
				position + direction * size,
				position - direction * size * 0.7 + side,
				position - direction * size * 0.7 - side,
			])
			draw_colored_polygon(shard, Color(color.r, color.g, color.b, ratio))
		else:
			var pulse_radius := size * (1.0 - ratio * 0.72)
			draw_arc(
				position,
				pulse_radius,
				0.0,
				TAU,
				36,
				Color(color.r, color.g, color.b, ratio * 0.62),
				2.0 + ratio * 3.0,
				true
			)


func _draw_crosshair() -> void:
	var position := _capture_cursor_position if _capture_mode else get_global_mouse_position()
	var pulse := 1.0 + sin(_elapsed * 4.0) * 0.12
	for arm_index in range(4):
		var direction := Vector2.from_angle(float(arm_index) * PI * 0.5)
		draw_line(
			position + direction * 8.0 * pulse,
			position + direction * 15.0 * pulse,
			Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.8),
			2.0,
			true
		)
	draw_circle(position, 3.0, COLOR_PLAYER_CORE, false, 1.5, true)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var hp_text := "FRACTURE LANCE  " + "◆".repeat(_player.hp) + "◇".repeat(_player.max_hp - _player.hp)
	draw_string(font, Vector2(84.0, 45.0), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, COLOR_TEXT)
	var upgrade_text := "REFRACTION CORE: ONLINE · TRI-LANCE" if _upgrade_active else "REFRACTION CORE: ACQUIRE SIGNAL PRISM"
	draw_string(font, Vector2(770.0, 45.0), upgrade_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, COLOR_UPGRADE if _upgrade_active else COLOR_TEXT_DIM)
	draw_string(
		font,
		Vector2(326.0, 738.0),
		"WASD / ARROWS  MOVE    MOUSE  AIM    HOLD LMB  FIRE    R  RESET    ESC  BACK",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		COLOR_TEXT_DIM
	)


func _draw_glow_polygon(points: PackedVector2Array, color: Color) -> void:
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= float(maxi(points.size(), 1))
	for scale_value in [1.35, 1.16]:
		var glow_points := PackedVector2Array()
		for point: Vector2 in points:
			glow_points.append(center + (point - center) * float(scale_value))
		draw_colored_polygon(glow_points, Color(color.r, color.g, color.b, 0.045))
	draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.92))
	draw_polyline(_close_polygon(points), Color(1.0, 1.0, 1.0, 0.42), 1.0, true)


func _draw_glow_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	for extra_width in [8.0, 4.0]:
		draw_polyline(points, Color(color.r, color.g, color.b, 0.055), width + float(extra_width), true)
	draw_polyline(points, color, width, true)


func _draw_glow_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	for extra_width in [8.0, 4.0]:
		draw_line(from, to, Color(color.r, color.g, color.b, 0.055), width + float(extra_width), true)
	draw_line(from, to, color, width, true)


func _regular_polygon(center: Vector2, radius: float, sides: int, rotation_offset: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(sides):
		points.append(center + Vector2.from_angle(rotation_offset + float(index) * TAU / float(sides)) * radius)
	return points


func _transform_points(
	local_points: PackedVector2Array,
	origin: Vector2,
	angle: float,
	scale_value: float
) -> PackedVector2Array:
	var transformed := PackedVector2Array()
	for point: Vector2 in local_points:
		transformed.append(origin + (point * scale_value).rotated(angle))
	return transformed


func _close_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	if not points.is_empty():
		closed.append(points[0])
	return closed


func _clamp_to_arena(position: Vector2, radius: float) -> Vector2:
	return Vector2(
		clampf(position.x, ARENA_RECT.position.x + radius, ARENA_RECT.end.x - radius),
		clampf(position.y, ARENA_RECT.position.y + radius, ARENA_RECT.end.y - radius)
	)


func _actor_color(actor: NeonGeometryActor) -> Color:
	match actor.kind:
		NeonGeometryActor.ActorKind.PLAYER:
			return COLOR_PLAYER
		NeonGeometryActor.ActorKind.RING_HUNTER:
			return COLOR_HUNTER
		NeonGeometryActor.ActorKind.TRI_AXIS_GUNNER:
			return COLOR_GUNNER
	return Color.WHITE


func _count_projectiles(pool: Array[NeonGeometryProjectile], kind: int) -> int:
	var count := 0
	for projectile: NeonGeometryProjectile in pool:
		if projectile.active and projectile.kind == kind:
			count += 1
	return count


func _count_active_vfx() -> int:
	var count := 0
	for slot: Dictionary in _vfx_slots:
		if bool(slot["active"]):
			count += 1
	return count


func _projectile_teams_are_valid() -> bool:
	for projectile: NeonGeometryProjectile in _player_projectiles:
		if projectile.active and projectile.team != NeonGeometryProjectile.Team.PLAYER:
			return false
	for projectile: NeonGeometryProjectile in _enemy_projectiles:
		if projectile.active and projectile.team != NeonGeometryProjectile.Team.ENEMY:
			return false
	return true


func _register_input_actions() -> void:
	_register_key_action(ACTION_LEFT, [KEY_A, KEY_LEFT])
	_register_key_action(ACTION_RIGHT, [KEY_D, KEY_RIGHT])
	_register_key_action(ACTION_UP, [KEY_W, KEY_UP])
	_register_key_action(ACTION_DOWN, [KEY_S, KEY_DOWN])
	_register_key_action(ACTION_RESET, [KEY_R])
	_register_key_action(ACTION_BACK, [KEY_ESCAPE])
	if not InputMap.has_action(ACTION_FIRE):
		InputMap.add_action(ACTION_FIRE)
	var has_mouse_binding := false
	for event: InputEvent in InputMap.action_get_events(ACTION_FIRE):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			has_mouse_binding = true
			break
	if not has_mouse_binding:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event(ACTION_FIRE, mouse_event)


func _register_key_action(action_name: String, keycodes: Array[Key]) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for keycode: Key in keycodes:
		var already_bound := false
		for event: InputEvent in InputMap.action_get_events(action_name):
			if event is InputEventKey and (event as InputEventKey).keycode == keycode:
				already_bound = true
				break
		if already_bound:
			continue
		var key_event := InputEventKey.new()
		key_event.keycode = keycode
		InputMap.action_add_event(action_name, key_event)
