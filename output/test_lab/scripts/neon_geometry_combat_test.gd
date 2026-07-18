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
const CAPTURE_DELTA := 1.0 / 60.0
const VFX_SHARD := 0
const VFX_PULSE := 1
const VFX_SPARK := 2
const VFX_GLYPH := 3
const VFX_LENS := 4
const VFX_BURST := 5

const ACTION_LEFT := "lab_neon_move_left"
const ACTION_RIGHT := "lab_neon_move_right"
const ACTION_UP := "lab_neon_move_up"
const ACTION_DOWN := "lab_neon_move_down"
const ACTION_FIRE := "lab_neon_fire"
const ACTION_RESET := "lab_neon_reset"
const ACTION_BACK := "lab_back"

const COLOR_BACKGROUND := Color("030208")
const COLOR_BACKGROUND_ALT := Color("0b0820")
const COLOR_BACKGROUND_DEEP := Color("010105")
const COLOR_GRID := Color("241b46")
const COLOR_BORDER := Color("6b45a5")
const COLOR_NEBULA_VIOLET := Color("32145f")
const COLOR_NEBULA_CYAN := Color("083745")
const COLOR_PLAYER := Color("f4b94f")
const COLOR_PLAYER_SHELL := Color("85501f")
const COLOR_PLAYER_MID := Color("d18a31")
const COLOR_PLAYER_CORE := Color("ffe58a")
const COLOR_PLAYER_HOT := Color("fff8d6")
const COLOR_PLAYER_ACCENT := Color("9d6cff")
const COLOR_HUNTER := Color("ff3d7f")
const COLOR_HUNTER_SHELL := Color("701433")
const COLOR_HUNTER_MID := Color("b52557")
const COLOR_HUNTER_CORE := Color("ff8bb1")
const COLOR_HUNTER_DARK := Color("31051d")
const COLOR_GUNNER := Color("4de1ff")
const COLOR_GUNNER_SHELL := Color("0b5869")
const COLOR_GUNNER_MID := Color("168ca3")
const COLOR_GUNNER_CORE := Color("b5f5ff")
const COLOR_GUNNER_DARK := Color("052a35")
const COLOR_ENEMY_PROJECTILE := Color("ff405f")
const COLOR_ENEMY_HOT := Color("ffc0ca")
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
var _background_fragments: Array[Dictionary] = []
var _player_trail: Array[Vector2] = []
var _upgrade_active: bool = false
var _player_fire_cooldown: float = 0.0
var _elapsed: float = 0.0
var _spawn_serial: int = 0
var _vfx_spawn_serial: int = 0
var _capture_mode: bool = false
var _capture_cursor_position := Vector2(640.0, 180.0)
var _screen_kick_remaining: float = 0.0
var _screen_kick_strength: float = 0.0
var _screen_flash_strength: float = 0.0
var _upgrade_wave_remaining: float = 0.0
var _hit_stop_remaining: float = 0.0


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
	var safe_delta := CAPTURE_DELTA if _capture_mode else minf(delta, 0.05)
	var simulation_delta := 0.0 if _hit_stop_remaining > 0.0 else safe_delta
	_elapsed += safe_delta
	if Input.is_action_just_pressed(ACTION_BACK) and not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/test_lab_index.tscn")
		return
	if Input.is_action_just_pressed(ACTION_RESET) and not _capture_mode:
		debug_reset_scene()

	if simulation_delta > 0.0:
		_update_actor_timers(simulation_delta)
		_update_player(simulation_delta)
		_update_enemies(simulation_delta)
		_update_projectiles(simulation_delta)
		_update_pickup()
		_update_player_trail()
	_update_vfx(safe_delta)
	_update_screen_feedback(safe_delta)
	queue_redraw()


func debug_reset_scene() -> void:
	_elapsed = 0.0
	_spawn_serial = 0
	_vfx_spawn_serial = 0
	_capture_mode = false
	_upgrade_active = false
	_player_fire_cooldown = 0.0
	_screen_kick_remaining = 0.0
	_screen_kick_strength = 0.0
	_screen_flash_strength = 0.0
	_upgrade_wave_remaining = 0.0
	_hit_stop_remaining = 0.0
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
	_upgrade_wave_remaining = 1.15
	_screen_flash_strength = maxf(_screen_flash_strength, 0.7)
	_add_screen_kick(0.22, 3.5)
	_spawn_pulse(UPGRADE_POSITION, COLOR_UPGRADE, 0.9, 78.0)
	_spawn_pulse(UPGRADE_POSITION, COLOR_PLAYER_ACCENT, 0.62, 48.0)
	_spawn_shards(UPGRADE_POSITION, COLOR_UPGRADE, 10, Vector2.UP)
	for index in range(6):
		var direction := Vector2.from_angle(float(index) * TAU / 6.0)
		_spawn_vfx(VFX_GLYPH, UPGRADE_POSITION + direction * 18.0, direction * 54.0, 0.72, COLOR_UPGRADE, 9.0)


func debug_prepare_capture() -> void:
	debug_reset_scene()
	_capture_mode = true
	debug_activate_upgrade()
	for slot: Dictionary in _vfx_slots:
		slot["active"] = false
	_vfx_spawn_serial = 0
	_screen_kick_remaining = 0.0
	_screen_kick_strength = 0.0
	_screen_flash_strength = 0.0
	_upgrade_wave_remaining = 0.0
	_player.position = Vector2(560.0, 532.0)
	_capture_cursor_position = Vector2(716.0, 190.0)
	_player.aim_toward(_capture_cursor_position)
	_player_trail.clear()
	for trail_index in range(10):
		_player_trail.append(_player.position + Vector2(-5.0, 5.5) * float(trail_index))
	_ring_hunter.position = Vector2(318.0, 244.0)
	_ring_hunter.aim_toward(_player.position)
	_tri_axis.position = Vector2(956.0, 238.0)
	_tri_axis.aim_toward(_player.position)
	var capture_shot_direction := _player.position.direction_to(_capture_cursor_position)
	_spawn_player_volley(_player.position + capture_shot_direction * 24.0, capture_shot_direction)
	_spawn_player_volley(_player.position + capture_shot_direction * 116.0, capture_shot_direction)
	var impact_direction := _player.position.direction_to(_tri_axis.position)
	_spawn_projectile(
		_player_projectiles,
		NeonGeometryProjectile.ProjectileKind.PLAYER_BOLT,
		NeonGeometryProjectile.Team.PLAYER,
		_tri_axis.position - impact_direction * 152.0,
		impact_direction * PLAYER_PROJECTILE_SPEED,
		PLAYER_PROJECTILE_LIFETIME
	)
	_fire_ring_hunter()
	_fire_tri_axis()
	_ring_hunter.warning_remaining = RING_HUNTER_WARNING + 0.052
	_ring_hunter.attack_pending = true
	_tri_axis.warning_remaining = 0.0
	_tri_axis.attack_pending = false
	_screen_flash_strength = 0.08
	_spawn_vfx(VFX_GLYPH, _player.position, Vector2.ZERO, 1.05, COLOR_UPGRADE, 22.0)
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
	_trigger_hit_stop(0.045 if actor == _player else 0.032)
	actor.recoil_strength = maxf(actor.recoil_strength, 0.58)
	_screen_flash_strength = maxf(_screen_flash_strength, 0.26)
	_add_screen_kick(0.14, 2.5)
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
		"active_vfx_kind_count": _count_active_vfx_kinds(),
		"projectile_teams_valid": _projectile_teams_are_valid(),
		"player_respawn_remaining": _player.respawn_remaining,
		"player_invulnerability_remaining": _player.invulnerability_remaining,
		"screen_kick_remaining": _screen_kick_remaining,
		"screen_flash_strength": _screen_flash_strength,
		"upgrade_wave_remaining": _upgrade_wave_remaining,
		"hit_stop_remaining": _hit_stop_remaining,
	}


func _draw() -> void:
	_draw_background()
	var world_offset := _world_draw_offset()
	draw_set_transform(world_offset)
	_draw_local_light_fields()
	_draw_aim_tether()
	_draw_player_trail()
	_draw_upgrade_pickup()
	_draw_upgrade_transformation()
	_draw_projectile_pool(_player_projectiles)
	_draw_projectile_pool(_enemy_projectiles)
	_draw_vfx(false)
	_draw_actor(_ring_hunter)
	_draw_actor(_tri_axis)
	_draw_actor(_player)
	_draw_vfx(true)
	draw_set_transform(Vector2.ZERO)
	_draw_foreground_overlay()
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
	for _index in range(92):
		_background_points.append({
			"position": Vector2(
				random.randf_range(ARENA_RECT.position.x, ARENA_RECT.end.x),
				random.randf_range(ARENA_RECT.position.y, ARENA_RECT.end.y)
			),
			"radius": random.randf_range(0.65, 2.35),
			"phase": random.randf_range(0.0, TAU),
			"accent": random.randi_range(0, 5) == 0,
			"depth": random.randf_range(0.25, 1.0),
			"drift": random.randf_range(2.0, 11.0),
		})
	for _index in range(18):
		_background_fragments.append({
			"position": Vector2(
				random.randf_range(ARENA_RECT.position.x + 40.0, ARENA_RECT.end.x - 40.0),
				random.randf_range(ARENA_RECT.position.y + 40.0, ARENA_RECT.end.y - 40.0)
			),
			"radius": random.randf_range(7.0, 18.0),
			"sides": random.randi_range(3, 6),
			"rotation": random.randf_range(0.0, TAU),
			"phase": random.randf_range(0.0, TAU),
		})


func _update_actor_timers(delta: float) -> void:
	for actor: NeonGeometryActor in _actors:
		actor.tick_timers(delta)
		actor.motion_phase += delta
		if actor.alive or actor.respawn_remaining > 0.0:
			continue
		var invulnerability := PLAYER_RESPAWN_INVULNERABILITY if actor == _player else 0.0
		actor.reset_actor(invulnerability)
		actor.spawn_flash_remaining = 0.7
		_spawn_pulse(actor.position, _actor_color(actor), 0.8, actor.hit_radius * 3.4)
		_spawn_vfx(VFX_GLYPH, actor.position, Vector2.ZERO, 0.72, _actor_color(actor), actor.hit_radius * 0.85)


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


func _update_screen_feedback(delta: float) -> void:
	_hit_stop_remaining = maxf(_hit_stop_remaining - delta, 0.0)
	_screen_kick_remaining = maxf(_screen_kick_remaining - delta, 0.0)
	if _screen_kick_remaining <= 0.0:
		_screen_kick_strength = 0.0
	_screen_flash_strength *= pow(0.035, delta)
	_upgrade_wave_remaining = maxf(_upgrade_wave_remaining - delta, 0.0)


func _update_pickup() -> void:
	if _upgrade_active or not _player.alive:
		return
	if _player.position.distance_to(UPGRADE_POSITION) <= _player.hit_radius + 24.0:
		debug_activate_upgrade()


func _update_player_trail() -> void:
	if not _player.alive:
		return
	if _capture_mode:
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
	_player.recoil_strength = 1.0
	_add_screen_kick(0.08, 1.25 if _upgrade_active else 0.75)
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
	_ring_hunter.recoil_strength = 1.0
	_add_screen_kick(0.13, 1.7)
	_spawn_pulse(_ring_hunter.position, COLOR_HUNTER, 0.34, 38.0)
	_spawn_vfx(VFX_SPARK, _ring_hunter.position + base_direction * 28.0, base_direction * 85.0, 0.18, COLOR_ENEMY_HOT, 11.0)
	_spawn_vfx(VFX_BURST, _ring_hunter.position + base_direction * 34.0, base_direction * 48.0, 0.2, COLOR_ENEMY_HOT, 24.0)


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
	_tri_axis.recoil_strength = 1.0
	_add_screen_kick(0.18, 2.3)
	_spawn_pulse(_tri_axis.position, COLOR_ENEMY_PROJECTILE, 0.5, 50.0)
	_spawn_vfx(VFX_GLYPH, _tri_axis.position, base_direction * 30.0, 0.38, COLOR_ENEMY_PROJECTILE, 17.0)
	_spawn_vfx(VFX_LENS, _tri_axis.position, Vector2.ZERO, 0.58, COLOR_GUNNER, 58.0)
	_spawn_vfx(VFX_BURST, _tri_axis.position + base_direction * 38.0, base_direction * 62.0, 0.25, COLOR_ENEMY_HOT, 29.0)


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
			_trigger_hit_stop(0.035)
			enemy.recoil_strength = maxf(enemy.recoil_strength, 0.42)
			_screen_flash_strength = maxf(_screen_flash_strength, 0.18)
			_add_screen_kick(0.12, 2.0)
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
		_trigger_hit_stop(0.055)
		_player.recoil_strength = maxf(_player.recoil_strength, 0.65)
		_screen_flash_strength = maxf(_screen_flash_strength, 0.36)
		_add_screen_kick(0.18, 3.2)
		if defeated:
			_defeat_actor(_player)


func _defeat_actor(actor: NeonGeometryActor) -> void:
	var actor_position := actor.position
	var color := _actor_color(actor)
	var shard_count := 14 if actor == _tri_axis else 10
	_spawn_shards(actor_position, color, shard_count, actor.aim_direction)
	_spawn_pulse(actor_position, color, 0.72, actor.hit_radius * 3.9)
	_spawn_pulse(actor_position, Color.WHITE, 0.28, actor.hit_radius * 2.1)
	_spawn_vfx(VFX_LENS, actor_position, Vector2.ZERO, 0.54, color, actor.hit_radius * 3.5)
	_spawn_vfx(VFX_BURST, actor_position, actor.aim_direction * 24.0, 0.32, Color.WHITE, actor.hit_radius * 1.35)
	_spawn_actor_breakup(actor, color)
	for index in range(4):
		var direction := Vector2.from_angle(float(index) * TAU / 4.0 + actor.aim_direction.angle())
		_spawn_vfx(VFX_GLYPH, actor_position, direction * 74.0, 0.58, color, actor.hit_radius * 0.55)
	_screen_flash_strength = maxf(_screen_flash_strength, 0.48 if actor == _player else 0.28)
	_add_screen_kick(0.28, 6.0 if actor == _player else 4.5)
	_trigger_hit_stop(0.075 if actor == _player else 0.052)
	var delay := PLAYER_RESPAWN_DELAY if actor == _player else ENEMY_RESPAWN_DELAY
	actor.defeat(delay)


func _spawn_actor_breakup(actor: NeonGeometryActor, color: Color) -> void:
	match actor.kind:
		NeonGeometryActor.ActorKind.PLAYER:
			for side in [-1.0, 1.0]:
				var fork_direction := actor.aim_direction.rotated(float(side) * 0.34)
				_spawn_vfx(VFX_SHARD, actor.position + fork_direction * 18.0, fork_direction * 176.0, 0.46, COLOR_PLAYER, 11.0)
				var module_direction := actor.aim_direction.orthogonal() * float(side)
				_spawn_vfx(VFX_BURST, actor.position + module_direction * 24.0, module_direction * 72.0, 0.32, COLOR_PLAYER_ACCENT, 16.0)
		NeonGeometryActor.ActorKind.RING_HUNTER:
			for segment_index in range(6):
				var radial := Vector2.from_angle(actor.aim_direction.angle() + 0.82 + float(segment_index) * TAU / 6.0)
				var tangent := radial.orthogonal()
				_spawn_vfx(VFX_SHARD, actor.position + radial * 30.0, tangent * (118.0 + float(segment_index % 2) * 28.0), 0.5, COLOR_HUNTER, 10.0)
			_spawn_vfx(VFX_BURST, actor.position, -actor.aim_direction * 38.0, 0.38, COLOR_HUNTER_CORE, 21.0)
		NeonGeometryActor.ActorKind.TRI_AXIS_GUNNER:
			for arm_index in range(3):
				var arm_direction := actor.aim_direction.rotated(float(arm_index) * TAU / 3.0)
				_spawn_vfx(VFX_SHARD, actor.position + arm_direction * 30.0, arm_direction * 152.0, 0.54, COLOR_GUNNER, 13.0)
				_spawn_vfx(VFX_BURST, actor.position + arm_direction * 18.0, arm_direction * 58.0, 0.34, COLOR_GUNNER_CORE, 17.0)
		_:
			return


func _spawn_muzzle(position: Vector2, direction: Vector2) -> void:
	for sign_value in [-1.0, 1.0]:
		var tangent := direction.orthogonal() * float(sign_value)
		_spawn_vfx(VFX_SHARD, position, direction * 92.0 + tangent * 74.0, 0.12, COLOR_PLAYER_CORE, 7.0)
	_spawn_vfx(VFX_SPARK, position, direction * 118.0, 0.11, COLOR_PLAYER_HOT, 13.0)
	_spawn_vfx(VFX_BURST, position, direction * 54.0, 0.18, COLOR_PLAYER_HOT, 21.0 if _upgrade_active else 16.0)
	_spawn_pulse(position, COLOR_PLAYER_ACCENT, 0.16, 17.0)


func _spawn_hit(position: Vector2, color: Color, direction: Vector2) -> void:
	_spawn_pulse(position, color, 0.3, 31.0)
	_spawn_shards(position, color, 6, direction)
	_spawn_vfx(VFX_SPARK, position, direction * 66.0, 0.2, Color.WHITE, 15.0)
	_spawn_vfx(VFX_BURST, position, direction * 42.0, 0.24, Color.WHITE, 22.0)
	_spawn_vfx(VFX_LENS, position, Vector2.ZERO, 0.38, color, 44.0)


func _trigger_hit_stop(duration: float) -> void:
	_hit_stop_remaining = maxf(_hit_stop_remaining, duration)


func _spawn_shards(position: Vector2, color: Color, count: int, bias: Vector2) -> void:
	var base_angle := bias.angle() if not bias.is_zero_approx() else 0.0
	for index in range(count):
		var ratio := float(index) / float(maxi(count, 1))
		var angle := base_angle + ratio * TAU + sin(float(_spawn_serial + index) * 1.73) * 0.22
		var speed := 82.0 + float(index % 4) * 24.0
		_spawn_vfx(VFX_SHARD, position, Vector2.from_angle(angle) * speed, 0.34 + float(index % 3) * 0.05, color, 5.0)


func _spawn_pulse(position: Vector2, color: Color, lifetime: float, size: float) -> void:
	_spawn_vfx(VFX_PULSE, position, Vector2.ZERO, lifetime, color, size)


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
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), COLOR_BACKGROUND_DEEP, true)
	draw_rect(ARENA_RECT, COLOR_BACKGROUND, true)
	_draw_nebula_lobe(Vector2(390.0, 270.0), 250.0, COLOR_NEBULA_VIOLET)
	_draw_nebula_lobe(Vector2(930.0, 470.0), 230.0, COLOR_NEBULA_CYAN)
	_draw_nebula_lobe(Vector2(660.0, 350.0), 180.0, COLOR_BACKGROUND_ALT)

	for x_index in range(17):
		var x := ARENA_RECT.position.x + float(x_index) * ARENA_RECT.size.x / 16.0
		var major := x_index % 4 == 0
		draw_line(
			Vector2(x, ARENA_RECT.position.y),
			Vector2(x, ARENA_RECT.end.y),
			Color(COLOR_GRID.r, COLOR_GRID.g, COLOR_GRID.b, 0.2 if major else 0.075),
			1.2 if major else 1.0
		)
	for y_index in range(11):
		var y := ARENA_RECT.position.y + float(y_index) * ARENA_RECT.size.y / 10.0
		var major := y_index % 5 == 0
		draw_line(
			Vector2(ARENA_RECT.position.x, y),
			Vector2(ARENA_RECT.end.x, y),
			Color(COLOR_GRID.r, COLOR_GRID.g, COLOR_GRID.b, 0.17 if major else 0.06),
			1.2 if major else 1.0
		)

	for fragment: Dictionary in _background_fragments:
		var fragment_position: Vector2 = fragment["position"] as Vector2
		fragment_position += Vector2(
			sin(_elapsed * 0.08 + float(fragment["phase"])) * 8.0,
			cos(_elapsed * 0.065 + float(fragment["phase"])) * 5.0
		)
		var fragment_points := _regular_polygon(
			fragment_position,
			float(fragment["radius"]),
			int(fragment["sides"]),
			float(fragment["rotation"]) + _elapsed * 0.025
		)
		draw_polyline(
			_close_polygon(fragment_points),
			Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.055),
			1.0,
			true
		)

	for point: Dictionary in _background_points:
		var point_position := _background_point_position(point)
		var depth: float = float(point["depth"])
		var pulse := 0.42 + 0.38 * sin(_elapsed * (0.5 + depth * 0.55) + float(point["phase"]))
		var color := COLOR_PLAYER_ACCENT if bool(point["accent"]) else COLOR_GUNNER
		var radius: float = float(point["radius"]) * (0.7 + depth * 0.45)
		draw_circle(point_position, radius * 2.6, Color(color.r, color.g, color.b, pulse * 0.025))
		if bool(point["accent"]):
			draw_line(point_position - Vector2(radius * 3.0, 0.0), point_position + Vector2(radius * 3.0, 0.0), Color(color.r, color.g, color.b, pulse * 0.16), 1.0)
			draw_line(point_position - Vector2(0.0, radius * 3.0), point_position + Vector2(0.0, radius * 3.0), Color(color.r, color.g, color.b, pulse * 0.12), 1.0)
		draw_circle(point_position, radius, Color(color.r, color.g, color.b, pulse * (0.2 + depth * 0.15)))

	var orbit_center := Vector2(640.0, 370.0)
	for orbit_index in range(4):
		var radius := 126.0 + float(orbit_index) * 92.0
		var start_angle := _elapsed * (0.025 + float(orbit_index) * 0.012) + float(orbit_index)
		for arc_offset in [0.0, PI]:
			draw_arc(
				orbit_center,
				radius,
				start_angle + arc_offset,
				start_angle + arc_offset + PI * (0.34 + float(orbit_index) * 0.035),
				64,
				Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.075),
				1.0,
				true
			)
	_draw_arena_frame()


func _draw_nebula_lobe(center: Vector2, radius: float, color: Color) -> void:
	for band in range(7, 0, -1):
		var ratio := float(band) / 7.0
		draw_circle(
			center + Vector2(sin(_elapsed * 0.025 + ratio * 3.0), cos(_elapsed * 0.02 + ratio)) * 14.0,
			radius * ratio,
			Color(color.r, color.g, color.b, 0.008 + (1.0 - ratio) * 0.006)
		)


func _background_point_position(point: Dictionary) -> Vector2:
	var base_position: Vector2 = point["position"] as Vector2
	var depth: float = float(point["depth"])
	var local_y := fposmod(
		base_position.y - ARENA_RECT.position.y + _elapsed * float(point["drift"]) * depth,
		ARENA_RECT.size.y
	)
	return Vector2(
		base_position.x + sin(_elapsed * 0.11 + float(point["phase"])) * depth * 4.0,
		ARENA_RECT.position.y + local_y
	)


func _draw_arena_frame() -> void:
	draw_rect(ARENA_RECT, Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.24), false, 1.0)
	var corner_length := 34.0
	for corner in [
		Vector2(ARENA_RECT.position.x, ARENA_RECT.position.y),
		Vector2(ARENA_RECT.end.x, ARENA_RECT.position.y),
		Vector2(ARENA_RECT.end.x, ARENA_RECT.end.y),
		Vector2(ARENA_RECT.position.x, ARENA_RECT.end.y),
	]:
		var x_sign := 1.0 if corner.x < ARENA_RECT.get_center().x else -1.0
		var y_sign := 1.0 if corner.y < ARENA_RECT.get_center().y else -1.0
		_draw_glow_line(corner, corner + Vector2(x_sign * corner_length, 0.0), COLOR_PLAYER_ACCENT, 2.0)
		_draw_glow_line(corner, corner + Vector2(0.0, y_sign * corner_length), COLOR_PLAYER_ACCENT, 2.0)
	for index in range(1, 12):
		var ratio := float(index) / 12.0
		var top := Vector2(lerpf(ARENA_RECT.position.x, ARENA_RECT.end.x, ratio), ARENA_RECT.position.y)
		var tick := 4.0 if index % 3 == 0 else 2.0
		draw_line(top, top + Vector2(0.0, tick), Color(COLOR_GUNNER.r, COLOR_GUNNER.g, COLOR_GUNNER.b, 0.35), 1.0)


func _draw_local_light_fields() -> void:
	if _player.alive:
		_draw_soft_light(_player.position, 118.0, COLOR_PLAYER, 0.12)
		_draw_soft_light(_player.position - _player.aim_direction * 18.0, 68.0, COLOR_PLAYER_ACCENT, 0.075)
	if _ring_hunter.alive:
		_draw_soft_light(_ring_hunter.position, 96.0, COLOR_HUNTER, 0.085)
	if _tri_axis.alive:
		_draw_soft_light(_tri_axis.position, 110.0, COLOR_GUNNER, 0.08)
	for projectile: NeonGeometryProjectile in _player_projectiles:
		if projectile.active:
			_draw_soft_light(projectile.position, 28.0, COLOR_PLAYER, 0.055)
	for projectile: NeonGeometryProjectile in _enemy_projectiles:
		if projectile.active:
			_draw_soft_light(projectile.position, 23.0, COLOR_ENEMY_PROJECTILE, 0.04)


func _draw_soft_light(center: Vector2, radius: float, color: Color, strength: float) -> void:
	for band_index in range(7, 0, -1):
		var ratio := float(band_index) / 7.0
		var falloff := pow(1.0 - ratio * 0.82, 2.0)
		draw_circle(
			center,
			radius * ratio,
			Color(color.r, color.g, color.b, strength * falloff * 0.22)
		)


func _draw_aim_tether() -> void:
	if not _player.alive:
		return
	var cursor_position := _capture_cursor_position if _capture_mode else get_global_mouse_position()
	var direction := _player.position.direction_to(cursor_position)
	if direction.is_zero_approx():
		return
	for angle_offset in ([-10.0, 0.0, 10.0] if _upgrade_active else [0.0]):
		var ray_direction := direction.rotated(deg_to_rad(float(angle_offset)))
		for segment_index in range(4):
			var from_distance := 46.0 + float(segment_index) * 16.0
			var alpha := 0.2 - float(segment_index) * 0.035
			draw_line(
				_player.position + ray_direction * from_distance,
				_player.position + ray_direction * (from_distance + 8.0),
				Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, alpha if _upgrade_active else alpha * 0.55),
				1.0,
				true
			)


func _draw_upgrade_transformation() -> void:
	if not _upgrade_active or _upgrade_wave_remaining <= 0.0:
		return
	var ratio := clampf(_upgrade_wave_remaining / 1.15, 0.0, 1.0)
	var progress := 1.0 - ratio
	var core_target := _player.position - _player.aim_direction * 3.0
	for side in [-1.0, 0.0, 1.0]:
		var target := core_target + _player.aim_direction.orthogonal() * float(side) * 32.0
		var elbow := UPGRADE_POSITION.lerp(target, 0.45) + Vector2(float(side) * 34.0, -22.0)
		var path_points := PackedVector2Array([UPGRADE_POSITION, elbow, target])
		draw_polyline(path_points, Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, ratio * 0.26), 1.4, true)
		var mover_position := UPGRADE_POSITION.lerp(elbow, minf(progress * 2.0, 1.0)) if progress < 0.5 else elbow.lerp(target, (progress - 0.5) * 2.0)
		_draw_glow_polygon(_regular_polygon(mover_position, 4.0 + ratio * 3.0, 4, _elapsed * 4.0), COLOR_UPGRADE)
	var wave_radius := lerpf(24.0, 112.0, progress)
	draw_arc(_player.position, wave_radius, -PI * 0.82, PI * 0.82, 56, Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, ratio * 0.32), 2.0, true)


func _draw_foreground_overlay() -> void:
	for inset_index in range(5):
		var inset := float(inset_index) * 9.0
		var alpha := 0.035 + float(inset_index) * 0.012
		draw_rect(ARENA_RECT.grow(-inset), Color(0.0, 0.0, 0.0, alpha), false, 12.0)
	for y_index in range(15):
		var y := ARENA_RECT.position.y + float(y_index) * ARENA_RECT.size.y / 14.0
		draw_line(Vector2(ARENA_RECT.position.x, y), Vector2(ARENA_RECT.end.x, y), Color(0.3, 0.2, 0.5, 0.018), 1.0)
	if _screen_flash_strength > 0.01:
		var flash_color := COLOR_UPGRADE if _upgrade_wave_remaining > 0.0 else Color.WHITE
		draw_rect(ARENA_RECT, Color(flash_color.r, flash_color.g, flash_color.b, _screen_flash_strength * 0.085), true)


func _world_draw_offset() -> Vector2:
	if _screen_kick_remaining <= 0.0:
		return Vector2.ZERO
	var ratio := clampf(_screen_kick_remaining / 0.28, 0.0, 1.0)
	return Vector2(
		sin(_elapsed * 103.0),
		cos(_elapsed * 79.0)
	) * _screen_kick_strength * ratio


func _add_screen_kick(duration: float, strength: float) -> void:
	_screen_kick_remaining = maxf(_screen_kick_remaining, duration)
	_screen_kick_strength = maxf(_screen_kick_strength, strength)


func _draw_glow_rect(rect: Rect2, color: Color) -> void:
	for width in [14.0, 8.0, 4.0]:
		draw_rect(rect, Color(color.r, color.g, color.b, 0.028), false, width)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.72), false, 1.5)


func _draw_player_trail() -> void:
	if not _player.alive or _player_trail.size() < 2:
		return
	for index in range(_player_trail.size() - 1):
		var ratio := 1.0 - float(index) / float(_player_trail.size())
		var from := _player_trail[index]
		var to := _player_trail[index + 1]
		var direction := from.direction_to(to)
		var side := direction.orthogonal() * (2.0 + ratio * 3.0)
		draw_line(from + side, to + side, Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, ratio * 0.16), 2.0 + ratio * 2.0, true)
		draw_line(from - side, to - side, Color(COLOR_PLAYER.r, COLOR_PLAYER.g, COLOR_PLAYER.b, ratio * 0.11), 1.0 + ratio * 1.4, true)
		if index % 3 == 0:
			draw_circle(to, 1.5 + ratio * 1.5, Color(COLOR_PLAYER_CORE.r, COLOR_PLAYER_CORE.g, COLOR_PLAYER_CORE.b, ratio * 0.22))


func _draw_upgrade_pickup() -> void:
	if _upgrade_active:
		return
	var spin := _elapsed * 1.2
	var lift := sin(_elapsed * 2.2) * 4.0
	var pickup_position := UPGRADE_POSITION + Vector2(0.0, lift)
	var outer := _regular_polygon(pickup_position, 29.0, 4, spin + PI * 0.25)
	var inner := _regular_polygon(pickup_position, 13.0, 4, -spin + PI * 0.25)
	_draw_glow_polyline(_close_polygon(outer), COLOR_UPGRADE, 2.3)
	draw_colored_polygon(inner, Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.62))
	draw_colored_polygon(_regular_polygon(pickup_position, 6.0, 4, spin), COLOR_PLAYER_HOT)
	for index in range(3):
		var orbit_angle := -spin * 0.72 + float(index) * TAU / 3.0
		var satellite_position := pickup_position + Vector2.from_angle(orbit_angle) * 42.0
		var satellite := _regular_polygon(satellite_position, 5.5, 3, orbit_angle)
		_draw_glow_polygon(satellite, COLOR_PLAYER_ACCENT)
	draw_line(pickup_position - Vector2(0.0, 54.0), pickup_position + Vector2(0.0, 54.0), Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.08), 2.0)
	draw_arc(
		pickup_position,
		38.0 + sin(_elapsed * 2.5) * 3.0,
		spin,
		spin + PI * 1.35,
		32,
		Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.46),
		2.0,
		true
	)


func _draw_actor(actor: NeonGeometryActor) -> void:
	if not actor.alive:
		_draw_respawn_preview(actor)
		return
	match actor.kind:
		NeonGeometryActor.ActorKind.PLAYER:
			_draw_player_actor(actor)
		NeonGeometryActor.ActorKind.RING_HUNTER:
			_draw_ring_hunter(actor)
		NeonGeometryActor.ActorKind.TRI_AXIS_GUNNER:
			_draw_tri_axis(actor)
	if actor.kind != NeonGeometryActor.ActorKind.PLAYER and actor.spawn_flash_remaining > 0.0:
		var ratio := actor.spawn_flash_remaining / 0.7
		_draw_glow_arc(actor.position, actor.hit_radius + 18.0 * ratio, -PI * ratio, TAU - PI * ratio, _actor_color(actor), 2.0)


func _draw_respawn_preview(actor: NeonGeometryActor) -> void:
	if actor.respawn_remaining > 0.45 or actor.respawn_remaining <= 0.0:
		return
	var progress := 1.0 - actor.respawn_remaining / 0.45
	var color := _actor_color(actor)
	var sides := 5
	match actor.kind:
		NeonGeometryActor.ActorKind.RING_HUNTER:
			sides = 7
		NeonGeometryActor.ActorKind.TRI_AXIS_GUNNER:
			sides = 6
		_:
			sides = 5
	var ghost := _regular_polygon(actor.spawn_position, actor.hit_radius + 8.0, sides, _elapsed * (1.0 if actor.kind == NeonGeometryActor.ActorKind.PLAYER else -0.8))
	draw_polyline(_close_polygon(ghost), Color(color.r, color.g, color.b, progress * 0.42), 1.5, true)
	for index in range(sides):
		var direction := Vector2.from_angle(float(index) * TAU / float(sides) + _elapsed * 0.35)
		var outer_position := actor.spawn_position + direction * lerpf(64.0, actor.hit_radius + 13.0, progress)
		draw_line(outer_position, actor.spawn_position + direction * (actor.hit_radius + 6.0), Color(color.r, color.g, color.b, progress * 0.38), 1.2, true)
	draw_circle(actor.spawn_position, lerpf(2.0, 7.0, progress), Color(color.r, color.g, color.b, progress * 0.66))


func _draw_player_actor(actor: NeonGeometryActor) -> void:
	var angle := actor.aim_direction.angle()
	var visual_scale := 1.17
	var pulse := 1.0 + sin(_elapsed * 3.4) * 0.028
	var visual_position := actor.position - actor.aim_direction * actor.recoil_strength * 7.0
	var tail_position := visual_position - actor.aim_direction * 27.0 * visual_scale
	var exhaust_length := 17.0 + sin(_elapsed * 18.0) * 3.0 + actor.velocity.length() * 0.025
	_draw_glow_line(tail_position, tail_position - actor.aim_direction * exhaust_length, COLOR_PLAYER_ACCENT, 3.0)
	draw_line(tail_position, tail_position - actor.aim_direction * exhaust_length * 0.62, COLOR_PLAYER_HOT, 1.2, true)
	var body := PackedVector2Array([
		Vector2(41.0, -4.0),
		Vector2(13.0, -16.0),
		Vector2(-10.0, -20.0),
		Vector2(-31.0, -10.0),
		Vector2(-23.0, 0.0),
		Vector2(-31.0, 10.0),
		Vector2(-10.0, 20.0),
		Vector2(13.0, 16.0),
		Vector2(41.0, 4.0),
		Vector2(15.0, 5.5),
		Vector2(15.0, -5.5),
	])
	body = _transform_points(body, visual_position, angle, pulse * visual_scale)
	var shell_shadow := _scaled_polygon(body, visual_position, 1.13)
	draw_colored_polygon(shell_shadow, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.96))
	draw_colored_polygon(_scaled_polygon(body, visual_position, 1.055), Color(COLOR_PLAYER.r, COLOR_PLAYER.g, COLOR_PLAYER.b, 0.07))
	draw_colored_polygon(body, COLOR_PLAYER_SHELL)
	_draw_glow_polyline(_close_polygon(body), COLOR_PLAYER, 2.0)
	var upper_facet := _transform_points(PackedVector2Array([
		Vector2(31.0, -4.0), Vector2(7.0, -13.0), Vector2(-15.0, -14.0), Vector2(-2.0, -3.0),
	]), visual_position, angle, visual_scale)
	var lower_facet := _transform_points(PackedVector2Array([
		Vector2(31.0, 4.0), Vector2(7.0, 13.0), Vector2(-15.0, 14.0), Vector2(-2.0, 3.0),
	]), visual_position, angle, visual_scale)
	draw_colored_polygon(upper_facet, Color(COLOR_PLAYER_MID.r, COLOR_PLAYER_MID.g, COLOR_PLAYER_MID.b, 0.92))
	draw_colored_polygon(lower_facet, Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.28))
	var upper_rim_start := visual_position + (Vector2(-16.0, -14.0) * visual_scale).rotated(angle)
	var upper_rim_end := visual_position + (Vector2(30.0, -4.0) * visual_scale).rotated(angle)
	draw_line(upper_rim_start, upper_rim_end, Color(COLOR_PLAYER_HOT.r, COLOR_PLAYER_HOT.g, COLOR_PLAYER_HOT.b, 0.76), 1.4, true)
	var lower_rim_start := visual_position + (Vector2(-14.0, 14.0) * visual_scale).rotated(angle)
	var lower_rim_end := visual_position + (Vector2(26.0, 4.0) * visual_scale).rotated(angle)
	draw_line(lower_rim_start, lower_rim_end, Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.55), 1.2, true)
	var split_start := visual_position + actor.aim_direction * 11.0 * visual_scale
	var split_end := visual_position + actor.aim_direction * 40.0 * visual_scale
	draw_line(split_start, split_end, COLOR_BACKGROUND_DEEP, 5.5 * visual_scale, true)
	for side in [-1.0, 1.0]:
		var split_offset := actor.aim_direction.orthogonal() * float(side) * 3.2
		draw_line(split_start + split_offset, split_end + split_offset * 0.45, Color(COLOR_PLAYER_HOT.r, COLOR_PLAYER_HOT.g, COLOR_PLAYER_HOT.b, 0.72), 1.1, true)
	var core_position := visual_position - actor.aim_direction * 4.0 * visual_scale
	var core := _regular_polygon(core_position, 11.0 * visual_scale, 5, angle)
	_draw_material_polygon(core, COLOR_PLAYER_CORE, angle - PI * 0.55, 1.0)
	_draw_energy_core(core_position, 5.6 * visual_scale, COLOR_PLAYER_CORE, _elapsed * 3.4)
	var module_offset := 34.0 if _upgrade_active else 21.0
	for side in [-1.0, 1.0]:
		var local_module := PackedVector2Array([
			Vector2(8.0, float(side) * module_offset),
			Vector2(-17.0, float(side) * (module_offset + 7.0)),
			Vector2(-12.0, float(side) * (module_offset - 7.0)),
		])
		var module_points := _transform_points(local_module, visual_position, angle, visual_scale)
		_draw_material_polygon(module_points, COLOR_PLAYER_ACCENT, angle - PI * 0.45, 0.78)
		var module_anchor := visual_position + (Vector2(-5.0, float(side) * (module_offset - 1.0)) * visual_scale).rotated(angle)
		_draw_glow_line(visual_position - actor.aim_direction * 5.0, module_anchor, COLOR_PLAYER_ACCENT, 1.4)
		if _upgrade_active:
			_draw_energy_core(module_anchor, 4.6, COLOR_UPGRADE, _elapsed * 5.1 + float(side))
	if _upgrade_active:
		for side in [-1.0, 1.0]:
			var muzzle_angle := angle + deg_to_rad(10.0) * float(side)
			var muzzle_start := visual_position + Vector2.from_angle(muzzle_angle) * 27.0 * visual_scale
			var muzzle_end := visual_position + Vector2.from_angle(muzzle_angle) * 42.0 * visual_scale
			draw_line(muzzle_start, muzzle_end, Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.62), 1.4, true)
		draw_arc(visual_position, 45.0 * visual_scale, angle - 0.72, angle + 0.72, 28, Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.19), 1.4, true)
	if actor.recoil_strength > 0.045:
		var flare_strength := clampf(actor.recoil_strength, 0.0, 1.0)
		_draw_weapon_flare(visual_position + actor.aim_direction * 43.0 * visual_scale, actor.aim_direction, COLOR_PLAYER_CORE, flare_strength, 25.0 * visual_scale)
		if _upgrade_active:
			for side in [-1.0, 1.0]:
				var side_direction := actor.aim_direction.rotated(deg_to_rad(10.0) * float(side))
				_draw_weapon_flare(visual_position + side_direction * 40.0 * visual_scale, side_direction, COLOR_UPGRADE, flare_strength * 0.8, 17.0 * visual_scale)
	if actor.invulnerability_remaining > 0.0:
		var alpha := 0.25 + 0.25 * sin(_elapsed * 18.0)
		draw_arc(
			visual_position,
			48.0 * visual_scale,
			0.0,
			TAU,
			48,
			Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, alpha),
			2.0,
			true
		)
	if actor.spawn_flash_remaining > 0.0:
		var spawn_ratio := actor.spawn_flash_remaining / 0.7
		draw_arc(visual_position, lerpf(62.0, 34.0, spawn_ratio) * visual_scale, -angle, TAU - angle, 48, Color(COLOR_PLAYER_HOT.r, COLOR_PLAYER_HOT.g, COLOR_PLAYER_HOT.b, spawn_ratio * 0.65), 2.0, true)
	_draw_hit_flash(actor)


func _draw_ring_hunter(actor: NeonGeometryActor) -> void:
	var facing := actor.aim_direction.angle()
	var visual_position := actor.position - actor.aim_direction * actor.recoil_strength * 6.0
	var inner_rotation := _elapsed * 0.82 + actor.motion_phase * 0.12
	for echo_index in range(2, 0, -1):
		var echo_position := visual_position - actor.aim_direction * float(echo_index) * 7.0
		draw_arc(echo_position, 34.0, facing + 0.72, facing + TAU - 0.72, 48, Color(COLOR_HUNTER.r, COLOR_HUNTER.g, COLOR_HUNTER.b, 0.035 * float(echo_index)), 2.0, true)
	for segment_index in range(6):
		var segment_start := facing + deg_to_rad(48.0) + float(segment_index) * deg_to_rad(50.0)
		var segment_length := deg_to_rad(31.0 + float(segment_index % 2) * 5.0)
		var segment_radius := 34.0 + sin(_elapsed * 2.1 + float(segment_index)) * 1.6
		_draw_arc_plate(
			visual_position,
			segment_radius - 5.0,
			segment_radius + 5.0,
			segment_start,
			segment_start + segment_length,
			COLOR_HUNTER_SHELL,
			COLOR_HUNTER,
			segment_index % 2 == 0
		)
	for segment_index in range(5):
		var inner_start := inner_rotation + float(segment_index) * TAU / 5.0
		_draw_glow_arc(visual_position, 20.0, inner_start, inner_start + 0.48, Color(COLOR_HUNTER_CORE.r, COLOR_HUNTER_CORE.g, COLOR_HUNTER_CORE.b, 0.68), 2.2)
	for side in [-1.0, 1.0]:
		var jaw_angle := facing + float(side) * deg_to_rad(39.0)
		var jaw_base := visual_position + Vector2.from_angle(jaw_angle) * 25.0
		var jaw_tip := visual_position + Vector2.from_angle(facing + float(side) * deg_to_rad(16.0)) * 43.0
		_draw_glow_line(jaw_base, jaw_tip, COLOR_HUNTER_CORE, 4.0)
	var mouth_start := visual_position + actor.aim_direction * 11.0
	var mouth_end := visual_position + actor.aim_direction * 39.0
	_draw_glow_line(mouth_start, mouth_end, COLOR_HUNTER_CORE, 3.0)
	if actor.recoil_strength > 0.045:
		_draw_weapon_flare(mouth_end, actor.aim_direction, COLOR_ENEMY_HOT, clampf(actor.recoil_strength, 0.0, 1.0), 28.0)
	draw_circle(visual_position, 14.0, Color(COLOR_HUNTER.r, COLOR_HUNTER.g, COLOR_HUNTER.b, 0.07))
	draw_circle(visual_position, 12.0, COLOR_HUNTER_DARK)
	draw_arc(visual_position, 11.0, 0.0, TAU, 28, COLOR_HUNTER_MID, 3.5, true)
	draw_arc(visual_position, 11.0, facing - 1.1, facing + 0.25, 18, COLOR_HUNTER_CORE, 1.4, true)
	var eye_position := visual_position + actor.aim_direction * 3.0
	_draw_energy_core(eye_position, 5.8, COLOR_HUNTER_CORE, _elapsed * 4.2)
	draw_circle(eye_position + actor.aim_direction * 1.5, 2.4, COLOR_BACKGROUND_DEEP)
	if actor.warning_remaining > 0.0:
		var ratio := clampf(1.0 - actor.warning_remaining / RING_HUNTER_WARNING, 0.0, 1.0)
		_draw_warning_fan(visual_position, facing, ratio, 168.0, deg_to_rad(31.0))
	_draw_hit_flash(actor)


func _draw_tri_axis(actor: NeonGeometryActor) -> void:
	var facing := actor.aim_direction.angle()
	var visual_position := actor.position - actor.aim_direction * actor.recoil_strength * 8.0
	var base_rotation := facing + sin(_elapsed * 0.62 + actor.motion_phase) * 0.12
	var orbit_rotation := _elapsed * -0.4 + actor.motion_phase * 0.16
	_draw_glow_arc(visual_position, 43.0, orbit_rotation, orbit_rotation + 1.2, COLOR_GUNNER, 2.0)
	_draw_glow_arc(visual_position, 43.0, orbit_rotation + PI, orbit_rotation + PI + 0.82, COLOR_GUNNER, 2.0)
	for arm_index in range(3):
		var arm_angle := base_rotation + float(arm_index) * TAU / 3.0
		var arm_length := 49.0 if arm_index == 0 else 35.0 - float(arm_index) * 2.0
		var arm_end := visual_position + Vector2.from_angle(arm_angle) * arm_length
		var arm_side := Vector2.from_angle(arm_angle).orthogonal() * (5.0 if arm_index == 0 else 4.0)
		var arm_plate := PackedVector2Array([
			visual_position + arm_side,
			arm_end + arm_side * 0.45,
			arm_end - arm_side * 0.45,
			visual_position - arm_side,
		])
		_draw_material_polygon(
			arm_plate,
			COLOR_GUNNER_MID if arm_index == 0 else COLOR_GUNNER_SHELL,
			arm_angle - PI * 0.42,
			1.0 if arm_index == 0 else 0.7
		)
		var rail_start := visual_position + Vector2.from_angle(arm_angle) * 8.0
		var rail_end := arm_end - Vector2.from_angle(arm_angle) * 5.0
		draw_line(rail_start, rail_end, Color(COLOR_GUNNER_CORE.r, COLOR_GUNNER_CORE.g, COLOR_GUNNER_CORE.b, 0.46 if arm_index == 0 else 0.2), 1.0, true)
		var triangle := PackedVector2Array([
			Vector2(12.0, 0.0),
			Vector2(-7.0, -7.0),
			Vector2(-7.0, 7.0),
		])
		var arm_color := COLOR_ENEMY_PROJECTILE if actor.warning_remaining > 0.0 and arm_index == 0 else COLOR_GUNNER
		_draw_material_polygon(_transform_points(triangle, arm_end, arm_angle, 1.0), arm_color, arm_angle - 0.7, 0.9)
	for satellite_index in range(3):
		var satellite_angle := orbit_rotation + float(satellite_index) * TAU / 3.0
		var satellite_position := visual_position + Vector2.from_angle(satellite_angle) * 48.0
		draw_colored_polygon(_regular_polygon(satellite_position, 4.0, 3, satellite_angle), Color(COLOR_GUNNER.r, COLOR_GUNNER.g, COLOR_GUNNER.b, 0.58))
	if actor.recoil_strength > 0.045:
		var main_muzzle := visual_position + actor.aim_direction * 54.0
		_draw_weapon_flare(main_muzzle, actor.aim_direction, COLOR_ENEMY_HOT, clampf(actor.recoil_strength, 0.0, 1.0), 32.0)
	var core := _regular_polygon(visual_position, 16.0, 6, -orbit_rotation * 0.55)
	draw_colored_polygon(_scaled_polygon(core, visual_position, 1.18), COLOR_BACKGROUND_DEEP)
	_draw_material_polygon(core, COLOR_GUNNER_MID, facing - PI * 0.52, 0.92)
	draw_circle(visual_position, 8.0, COLOR_GUNNER_DARK)
	_draw_energy_core(visual_position, 5.4, COLOR_GUNNER_CORE, _elapsed * 2.7)
	draw_circle(visual_position + actor.aim_direction * 2.0, 3.2, COLOR_BACKGROUND_DEEP)
	if actor.warning_remaining > 0.0:
		var ratio := clampf(1.0 - actor.warning_remaining / TRI_AXIS_WARNING, 0.0, 1.0)
		var line_end := visual_position + actor.aim_direction * lerpf(76.0, 172.0, ratio)
		draw_line(visual_position, line_end, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.9), 5.0, true)
		_draw_glow_line(visual_position, line_end, COLOR_ENEMY_PROJECTILE, 1.6)
		for charge_index in range(3):
			var charge_ratio := fposmod(ratio + float(charge_index) / 3.0, 1.0)
			var charge_position := visual_position.lerp(line_end, charge_ratio * 0.42)
			draw_circle(charge_position, 3.0 + ratio * 2.0, COLOR_ENEMY_HOT)
		draw_arc(
			visual_position,
			50.0,
			-orbit_rotation,
			-orbit_rotation + TAU * ratio,
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
	draw_circle(actor.position, actor.hit_radius + 9.0, Color(1.0, 1.0, 1.0, ratio * 0.62), false, 3.0)
	var cut_direction := actor.aim_direction.orthogonal()
	draw_line(actor.position - cut_direction * actor.hit_radius, actor.position + cut_direction * actor.hit_radius, Color(1.0, 1.0, 1.0, ratio * 0.72), 2.0, true)


func _draw_warning_fan(origin: Vector2, angle: float, ratio: float, radius: float, half_angle: float) -> void:
	var warning_pulse := 0.82 + sin(_elapsed * 18.0) * 0.18
	var color := Color(COLOR_ENEMY_PROJECTILE.r, COLOR_ENEMY_PROJECTILE.g, COLOR_ENEMY_PROJECTILE.b, (0.38 + ratio * 0.56) * warning_pulse)
	var left_end := origin + Vector2.from_angle(angle - half_angle) * radius
	var right_end := origin + Vector2.from_angle(angle + half_angle) * radius
	draw_colored_polygon(
		_sector_polygon(origin, radius, angle - half_angle, angle + half_angle, 28),
		Color(COLOR_ENEMY_PROJECTILE.r, COLOR_ENEMY_PROJECTILE.g, COLOR_ENEMY_PROJECTILE.b, 0.06 + ratio * 0.075)
	)
	draw_colored_polygon(
		_sector_polygon(origin, radius * (0.38 + ratio * 0.42), angle - half_angle, angle + half_angle, 24),
		Color(COLOR_HUNTER.r, COLOR_HUNTER.g, COLOR_HUNTER.b, 0.06 + ratio * 0.08)
	)
	draw_arc(origin, radius, angle - half_angle, angle + half_angle, 28, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.94), 8.0, true)
	draw_arc(origin, radius, angle - half_angle, angle + half_angle, 28, color, 3.2 + ratio * 1.8, true)
	draw_line(origin, left_end, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.9), 5.0, true)
	draw_line(origin, right_end, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.9), 5.0, true)
	draw_line(origin, left_end, color, 1.7, true)
	draw_line(origin, right_end, color, 1.7, true)
	for tick_index in range(7):
		var tick_ratio := float(tick_index + 1) / 8.0
		if tick_ratio > ratio + 0.16:
			continue
		var tick_angle := lerpf(angle - half_angle, angle + half_angle, tick_ratio)
		var tick_direction := Vector2.from_angle(tick_angle)
		draw_line(origin + tick_direction * (radius - 13.0), origin + tick_direction * radius, Color(COLOR_ENEMY_HOT.r, COLOR_ENEMY_HOT.g, COLOR_ENEMY_HOT.b, 0.45 + ratio * 0.45), 2.0, true)
	var sweep_angle := lerpf(angle - half_angle, angle + half_angle, ratio)
	draw_line(origin + Vector2.from_angle(sweep_angle) * radius * 0.56, origin + Vector2.from_angle(sweep_angle) * radius, COLOR_ENEMY_HOT, 3.0, true)
	var projection_direction := Vector2.from_angle(angle)
	for segment_index in range(3):
		var segment_start := radius + 18.0 + float(segment_index) * 28.0
		draw_line(
			origin + projection_direction * segment_start,
			origin + projection_direction * (segment_start + 15.0),
			Color(COLOR_ENEMY_PROJECTILE.r, COLOR_ENEMY_PROJECTILE.g, COLOR_ENEMY_PROJECTILE.b, 0.22 - float(segment_index) * 0.05),
			1.5,
			true
		)


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
	var fade := smoothstep(0.0, 0.15, projectile.life_ratio())
	var direction := projectile.velocity.normalized()
	for echo_index in range(3, 0, -1):
		var echo_position := projectile.position - direction * float(echo_index) * 9.0
		var echo_alpha := fade * (0.035 + float(3 - echo_index) * 0.035)
		draw_line(echo_position, echo_position - direction * 11.0, Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, echo_alpha), 5.0 - float(echo_index) * 0.7, true)
	var diamond := PackedVector2Array([
		Vector2(15.0, 0.0),
		Vector2(1.0, -4.5),
		Vector2(-13.0, 0.0),
		Vector2(1.0, 4.5),
	])
	var points := _transform_points(diamond, projectile.position, angle, 1.0)
	_draw_material_polygon(points, COLOR_PLAYER_MID, angle - PI * 0.5, 1.0)
	draw_line(
		projectile.position - direction * 8.0,
		projectile.position + direction * 11.0,
		Color(COLOR_PLAYER_HOT.r, COLOR_PLAYER_HOT.g, COLOR_PLAYER_HOT.b, 0.95 * fade),
		1.6,
		true
	)
	var tail_end := projectile.position - direction * 27.0
	_draw_glow_line(projectile.position, tail_end, COLOR_PLAYER_ACCENT, 2.4)
	draw_line(projectile.position + direction * 10.0, tail_end + direction * 12.0, Color(COLOR_PLAYER_HOT.r, COLOR_PLAYER_HOT.g, COLOR_PLAYER_HOT.b, fade), 1.2, true)
	if _upgrade_active:
		draw_polyline(_close_polygon(points), Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.52 * fade), 1.0, true)


func _draw_enemy_wedge(projectile: NeonGeometryProjectile) -> void:
	var direction := projectile.velocity.normalized()
	var angle := projectile.facing_angle()
	for echo_index in range(2, 0, -1):
		var echo_position := projectile.position - direction * float(echo_index) * 8.0
		draw_line(
			echo_position,
			echo_position - direction * (5.0 + float(2 - echo_index) * 3.0),
			Color(COLOR_ENEMY_PROJECTILE.r, COLOR_ENEMY_PROJECTILE.g, COLOR_ENEMY_PROJECTILE.b, 0.045 * float(3 - echo_index)),
			2.0 + float(2 - echo_index) * 0.6,
			true
		)
	var wedge := PackedVector2Array([
		Vector2(13.0, 0.0),
		Vector2(-9.0, -8.0),
		Vector2(-3.0, 0.0),
		Vector2(-9.0, 8.0),
	])
	var points := _transform_points(wedge, projectile.position, angle, 1.0)
	draw_colored_polygon(_scaled_polygon(points, projectile.position, 1.18), Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.9))
	_draw_material_polygon(points, COLOR_HUNTER_MID, angle - PI * 0.4, 0.9)
	var notch := _transform_points(PackedVector2Array([
		Vector2(-9.0, -3.0), Vector2(-2.0, 0.0), Vector2(-9.0, 3.0),
	]), projectile.position, angle, 1.0)
	draw_colored_polygon(notch, COLOR_BACKGROUND_DEEP)
	draw_line(projectile.position + direction * 5.0, projectile.position + direction * 11.0, COLOR_ENEMY_HOT, 1.4, true)


func _draw_enemy_ring(projectile: NeonGeometryProjectile) -> void:
	var facing := projectile.facing_angle()
	var direction := projectile.velocity.normalized()
	for echo_index in range(2, 0, -1):
		var echo_position := projectile.position - direction * float(echo_index) * 9.0
		var echo_radius := 12.0 - float(echo_index) * 2.2
		draw_arc(
			echo_position,
			echo_radius,
			facing + 0.58,
			facing + TAU - 0.58,
			20,
			Color(COLOR_ENEMY_PROJECTILE.r, COLOR_ENEMY_PROJECTILE.g, COLOR_ENEMY_PROJECTILE.b, 0.038 * float(3 - echo_index)),
			1.5,
			true
		)
	_draw_glow_arc(projectile.position, 13.0, facing + 0.52, facing + TAU - 0.52, COLOR_ENEMY_PROJECTILE, 3.4)
	draw_arc(projectile.position, 8.5, facing + 0.82, facing + TAU - 0.82, 24, Color(COLOR_ENEMY_HOT.r, COLOR_ENEMY_HOT.g, COLOR_ENEMY_HOT.b, 0.72), 1.5, true)
	draw_circle(projectile.position, 4.2, COLOR_HUNTER_DARK)
	_draw_energy_core(projectile.position, 2.8, COLOR_ENEMY_HOT, _elapsed * 6.0 + float(projectile.spawn_serial))


func _draw_vfx(foreground: bool) -> void:
	for slot: Dictionary in _vfx_slots:
		if not bool(slot["active"]):
			continue
		var kind := int(slot["kind"])
		var is_foreground := kind == VFX_SHARD or kind == VFX_SPARK or kind == VFX_BURST
		if is_foreground != foreground:
			continue
		var lifetime: float = float(slot["lifetime"])
		var initial_lifetime: float = maxf(float(slot["initial_lifetime"]), 0.001)
		var ratio := clampf(lifetime / initial_lifetime, 0.0, 1.0)
		var color: Color = slot["color"] as Color
		var position: Vector2 = slot["position"] as Vector2
		var size: float = float(slot["size"])
		var velocity: Vector2 = slot["velocity"] as Vector2
		var direction := velocity.normalized() if not velocity.is_zero_approx() else Vector2.RIGHT
		match kind:
			VFX_SHARD:
				var side := direction.orthogonal() * size * 0.42
				var shard := PackedVector2Array([
					position + direction * size,
					position - direction * size * 0.7 + side,
					position - direction * size * 0.7 - side,
				])
				draw_colored_polygon(_scaled_polygon(shard, position, 1.55), Color(color.r, color.g, color.b, ratio * 0.055))
				draw_colored_polygon(shard, Color(color.r, color.g, color.b, ratio))
				draw_line(position, position - direction * size * 1.7, Color(color.r, color.g, color.b, ratio * 0.36), 1.2, true)
			VFX_PULSE:
				var pulse_radius := size * (1.0 - ratio * 0.76)
				_draw_glow_arc(position, pulse_radius, 0.0, TAU, Color(color.r, color.g, color.b, ratio * 0.72), 1.5 + ratio * 2.7)
				draw_arc(position, pulse_radius * 0.72, -PI * ratio, PI * (1.0 - ratio), 28, Color(color.r, color.g, color.b, ratio * 0.28), 1.0, true)
				for tick_index in range(4):
					var tick_direction := Vector2.from_angle(float(tick_index) * PI * 0.5 + float(slot["spawn_serial"]) * 0.17)
					draw_line(position + tick_direction * pulse_radius * 0.82, position + tick_direction * pulse_radius, Color(color.r, color.g, color.b, ratio * 0.5), 1.2, true)
			VFX_SPARK:
				var spark_length := size * (0.7 + ratio * 1.35)
				draw_line(position - direction * spark_length, position + direction * spark_length, Color(color.r, color.g, color.b, ratio * 0.16), 8.0, true)
				draw_line(position - direction * spark_length, position + direction * spark_length, Color(color.r, color.g, color.b, ratio), 2.0, true)
				var cross := direction.orthogonal() * spark_length * 0.45
				draw_line(position - cross, position + cross, Color(1.0, 1.0, 1.0, ratio * 0.8), 1.4, true)
			VFX_GLYPH:
				var rotation := float(slot["spawn_serial"]) * 0.37 + (1.0 - ratio) * 1.8
				var glyph := _regular_polygon(position, size * (0.5 + ratio * 0.75), 6, rotation)
				_draw_glow_polyline(_close_polygon(glyph), Color(color.r, color.g, color.b, ratio * 0.72), 1.6)
				for index in range(0, glyph.size(), 2):
					draw_line(position, glyph[index], Color(color.r, color.g, color.b, ratio * 0.18), 1.0, true)
			VFX_LENS:
				var lens_progress := 1.0 - ratio
				var lens_radius := size * (0.22 + lens_progress * 0.78)
				for ring_index in range(3):
					var ring_radius := lens_radius * (1.0 - float(ring_index) * 0.16)
					var ring_offset := Vector2(float(ring_index - 1) * 2.0 * lens_progress, 0.0)
					var ring_alpha := ratio * (0.34 - float(ring_index) * 0.065)
					var ring_color := color if ring_index == 1 else (COLOR_PLAYER_ACCENT if ring_index == 0 else COLOR_GUNNER)
					draw_arc(
						position + ring_offset,
						ring_radius,
						float(ring_index) * 0.62 + lens_progress,
						float(ring_index) * 0.62 + lens_progress + PI * 1.45,
						42,
						Color(ring_color.r, ring_color.g, ring_color.b, ring_alpha),
						2.6 - float(ring_index) * 0.45,
						true
					)
				draw_circle(position, size * 0.11 * ratio, Color(color.r, color.g, color.b, ratio * 0.12))
			VFX_BURST:
				var burst_direction := direction
				var tangent := burst_direction.orthogonal()
				var burst_length := size * (0.58 + ratio * 0.82)
				var burst_width := size * (0.14 + ratio * 0.28)
				var star := PackedVector2Array([
					position + burst_direction * burst_length,
					position + tangent * burst_width,
					position - burst_direction * burst_length * 0.5,
					position - tangent * burst_width,
				])
				draw_colored_polygon(_scaled_polygon(star, position, 1.75), Color(color.r, color.g, color.b, ratio * 0.055))
				draw_colored_polygon(star, Color(color.r, color.g, color.b, ratio * 0.72))
				draw_line(position - burst_direction * burst_length, position + burst_direction * burst_length, Color(1.0, 1.0, 1.0, ratio * 0.9), 2.0, true)
				draw_line(position - tangent * burst_width * 1.6, position + tangent * burst_width * 1.6, Color(color.r, color.g, color.b, ratio * 0.62), 1.4, true)
				draw_circle(position, size * 0.16 * ratio, Color(1.0, 1.0, 1.0, ratio))
			_:
				continue


func _draw_crosshair() -> void:
	var position := _capture_cursor_position if _capture_mode else get_global_mouse_position()
	var pulse := 1.0 + sin(_elapsed * 4.0) * 0.1
	var rotation := _elapsed * 0.62
	draw_arc(position, 21.0 * pulse, rotation, rotation + PI * 0.34, 12, Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.42), 1.2, true)
	draw_arc(position, 21.0 * pulse, rotation + PI, rotation + PI * 1.34, 12, Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.42), 1.2, true)
	for arm_index in range(4):
		var direction := Vector2.from_angle(float(arm_index) * PI * 0.5)
		draw_line(
			position + direction * 11.0 * pulse,
			position + direction * 18.0 * pulse,
			Color(COLOR_PLAYER_ACCENT.r, COLOR_PLAYER_ACCENT.g, COLOR_PLAYER_ACCENT.b, 0.8),
			1.5,
			true
		)
		draw_line(
			position + direction * 26.0,
			position + direction * 32.0,
			Color(COLOR_PLAYER.r, COLOR_PLAYER.g, COLOR_PLAYER.b, 0.48),
			1.0,
			true
		)
	if _upgrade_active:
		var aim_angle := _player.aim_direction.angle()
		for angle_offset in [-10.0, 0.0, 10.0]:
			var direction := Vector2.from_angle(aim_angle + deg_to_rad(float(angle_offset)))
			var marker_position := position + direction * 27.0
			var marker_tangent := direction.orthogonal()
			draw_line(
				marker_position - marker_tangent * 3.2,
				marker_position + marker_tangent * 3.2,
				Color(COLOR_UPGRADE.r, COLOR_UPGRADE.g, COLOR_UPGRADE.b, 0.82),
				1.6,
				true
			)
	var center_diamond := _regular_polygon(position, 5.2, 4, PI * 0.25)
	draw_colored_polygon(center_diamond, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.88))
	draw_polyline(_close_polygon(center_diamond), COLOR_PLAYER_CORE, 1.2, true)
	draw_circle(position, 1.3, COLOR_PLAYER_HOT)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	var player_panel := Rect2(74.0, 17.0, 370.0, 44.0)
	var upgrade_panel := Rect2(742.0, 17.0, 464.0, 44.0)
	var controls_panel := Rect2(274.0, 714.0, 732.0, 34.0)
	_draw_hud_panel(player_panel, COLOR_PLAYER)
	_draw_hud_panel(upgrade_panel, COLOR_UPGRADE if _upgrade_active else COLOR_BORDER)
	_draw_hud_panel(controls_panel, COLOR_PLAYER_ACCENT)
	draw_string(font, Vector2(94.0, 34.0), "FRACTURE LANCE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, COLOR_TEXT_DIM)
	draw_string(font, Vector2(94.0, 53.0), "LATTICE INTEGRITY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COLOR_TEXT)
	for hp_index in range(_player.max_hp):
		var hp_position := Vector2(302.0 + float(hp_index) * 25.0, 40.0)
		var hp_shape := _regular_polygon(hp_position, 8.0, 5, -PI * 0.5)
		if hp_index < _player.hp:
			draw_colored_polygon(_scaled_polygon(hp_shape, hp_position, 1.55), Color(COLOR_PLAYER.r, COLOR_PLAYER.g, COLOR_PLAYER.b, 0.06))
			draw_colored_polygon(hp_shape, COLOR_PLAYER_CORE)
			draw_polyline(_close_polygon(hp_shape), COLOR_PLAYER_HOT, 1.0, true)
		else:
			draw_polyline(_close_polygon(hp_shape), Color(COLOR_TEXT_DIM.r, COLOR_TEXT_DIM.g, COLOR_TEXT_DIM.b, 0.45), 1.2, true)
	var prism_position := Vector2(770.0, 39.0)
	var prism := _regular_polygon(prism_position, 12.0, 4, PI * 0.25)
	draw_polyline(_close_polygon(prism), COLOR_UPGRADE if _upgrade_active else COLOR_TEXT_DIM, 1.8, true)
	if _upgrade_active:
		draw_colored_polygon(_regular_polygon(prism_position, 5.0, 4, -PI * 0.25), COLOR_UPGRADE)
	var upgrade_title := "REFRACTION // TRI-LANCE" if _upgrade_active else "REFRACTION // DORMANT"
	var upgrade_detail := "THREE MUZZLES · ±10°" if _upgrade_active else "ACQUIRE SIGNAL PRISM"
	draw_string(font, Vector2(796.0, 35.0), upgrade_title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COLOR_UPGRADE if _upgrade_active else COLOR_TEXT_DIM)
	draw_string(font, Vector2(796.0, 53.0), upgrade_detail, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, COLOR_TEXT_DIM)
	var control_groups: Array[String] = ["WASD  MOVE", "MOUSE  VECTOR", "LMB  FIRE", "R  RESET", "ESC  BACK"]
	var control_offsets: Array[float] = [126.0, 142.0, 112.0, 99.0, 0.0]
	var control_x := 299.0
	for group_index in range(control_groups.size()):
		var label: String = control_groups[group_index]
		draw_string(font, Vector2(control_x, 736.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, COLOR_TEXT_DIM)
		control_x += control_offsets[group_index]
		if group_index < control_groups.size() - 1:
			draw_line(Vector2(control_x - 14.0, 722.0), Vector2(control_x - 14.0, 740.0), Color(COLOR_BORDER.r, COLOR_BORDER.g, COLOR_BORDER.b, 0.42), 1.0)


func _draw_hud_panel(rect: Rect2, accent: Color) -> void:
	var panel := _chamfered_rect(rect, 8.0)
	draw_colored_polygon(panel, Color(COLOR_BACKGROUND_ALT.r, COLOR_BACKGROUND_ALT.g, COLOR_BACKGROUND_ALT.b, 0.82))
	draw_polyline(_close_polygon(panel), Color(accent.r, accent.g, accent.b, 0.34), 1.2, true)
	draw_line(rect.position + Vector2(12.0, rect.size.y - 2.0), rect.position + Vector2(rect.size.x * 0.42, rect.size.y - 2.0), Color(accent.r, accent.g, accent.b, 0.74), 2.0, true)


func _draw_weapon_flare(
	position: Vector2,
	direction: Vector2,
	color: Color,
	strength: float,
	size: float
) -> void:
	var safe_direction := direction.normalized()
	if safe_direction.is_zero_approx():
		safe_direction = Vector2.RIGHT
	var tangent := safe_direction.orthogonal()
	var flare_points := PackedVector2Array([
		position + safe_direction * size * strength,
		position + tangent * size * 0.28 * strength,
		position - safe_direction * size * 0.45 * strength,
		position - tangent * size * 0.28 * strength,
	])
	draw_colored_polygon(_scaled_polygon(flare_points, position, 1.8), Color(color.r, color.g, color.b, strength * 0.055))
	draw_colored_polygon(flare_points, Color(color.r, color.g, color.b, strength * 0.66))
	draw_line(position - safe_direction * size * 0.6, position + safe_direction * size, Color(1.0, 1.0, 1.0, strength * 0.92), 1.7, true)
	draw_line(position - tangent * size * 0.38, position + tangent * size * 0.38, Color(color.r, color.g, color.b, strength * 0.72), 1.2, true)
	draw_circle(position, size * 0.12 * strength, Color(1.0, 1.0, 1.0, strength))


func _draw_material_polygon(
	points: PackedVector2Array,
	color: Color,
	light_angle: float,
	energy: float
) -> void:
	if points.size() < 3:
		return
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= float(points.size())
	var alpha := color.a
	draw_colored_polygon(
		_scaled_polygon(points, center, 1.16),
		Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.94 * alpha)
	)
	for glow_scale in [1.5, 1.27, 1.1]:
		var glow_alpha := 0.018 if glow_scale > 1.4 else (0.045 if glow_scale > 1.2 else 0.09)
		draw_colored_polygon(
			_scaled_polygon(points, center, float(glow_scale)),
			Color(color.r, color.g, color.b, glow_alpha * alpha * energy)
		)
	var light_direction := Vector2.from_angle(light_angle)
	for index in range(points.size()):
		var next_index := (index + 1) % points.size()
		var edge_midpoint := (points[index] + points[next_index]) * 0.5
		var facet_direction := center.direction_to(edge_midpoint)
		var light_value := clampf((facet_direction.dot(light_direction) + 1.0) * 0.5, 0.0, 1.0)
		var shade_amount := lerpf(0.62, 0.18, light_value)
		var facet_color := color.darkened(shade_amount)
		facet_color.a = alpha
		draw_colored_polygon(
			PackedVector2Array([center, points[index], points[next_index]]),
			facet_color
		)
	var rim_color := Color(color.r, color.g, color.b, 0.78 * alpha)
	draw_polyline(_close_polygon(points), rim_color, 1.25 + energy * 0.55, true)
	var best_edge := 0
	var best_light := -2.0
	for index in range(points.size()):
		var next_index := (index + 1) % points.size()
		var edge_midpoint := (points[index] + points[next_index]) * 0.5
		var edge_light := center.direction_to(edge_midpoint).dot(light_direction)
		if edge_light > best_light:
			best_light = edge_light
			best_edge = index
	var hot_end := (best_edge + 1) % points.size()
	draw_line(
		points[best_edge].lerp(points[hot_end], 0.12),
		points[best_edge].lerp(points[hot_end], 0.82),
		Color(1.0, 1.0, 1.0, 0.72 * alpha * energy),
		1.15,
		true
	)


func _draw_arc_plate(
	center: Vector2,
	inner_radius: float,
	outer_radius: float,
	start_angle: float,
	end_angle: float,
	shell_color: Color,
	rim_color: Color,
	hot_outer_edge: bool
) -> void:
	var points := PackedVector2Array()
	var segment_count := 8
	for index in range(segment_count + 1):
		var ratio := float(index) / float(segment_count)
		points.append(center + Vector2.from_angle(lerpf(start_angle, end_angle, ratio)) * outer_radius)
	for index in range(segment_count, -1, -1):
		var ratio := float(index) / float(segment_count)
		points.append(center + Vector2.from_angle(lerpf(start_angle, end_angle, ratio)) * inner_radius)
	draw_colored_polygon(points, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.96))
	var inset_points := _scaled_polygon(points, center, 0.975)
	draw_colored_polygon(inset_points, shell_color)
	draw_arc(center, outer_radius, start_angle, end_angle, 12, Color(rim_color.r, rim_color.g, rim_color.b, 0.22), 8.0, true)
	draw_arc(center, outer_radius, start_angle, end_angle, 12, rim_color, 1.8 if hot_outer_edge else 1.2, true)
	draw_arc(center, inner_radius, start_angle, end_angle, 12, Color(rim_color.r, rim_color.g, rim_color.b, 0.38), 1.0, true)
	var cap_color := Color(rim_color.r, rim_color.g, rim_color.b, 0.5)
	draw_line(center + Vector2.from_angle(start_angle) * inner_radius, center + Vector2.from_angle(start_angle) * outer_radius, cap_color, 1.0, true)
	draw_line(center + Vector2.from_angle(end_angle) * inner_radius, center + Vector2.from_angle(end_angle) * outer_radius, cap_color, 1.0, true)


func _draw_energy_core(center: Vector2, radius: float, color: Color, phase: float) -> void:
	var pulse := 0.88 + sin(phase) * 0.12
	for scale_value in [3.0, 2.2, 1.55]:
		var alpha := 0.018 if scale_value > 2.5 else (0.045 if scale_value > 2.0 else 0.11)
		draw_circle(center, radius * float(scale_value) * pulse, Color(color.r, color.g, color.b, alpha))
	draw_circle(center, radius * 1.18, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.92))
	draw_circle(center, radius * pulse, Color(color.r * 0.74, color.g * 0.74, color.b * 0.74, 1.0))
	draw_circle(center - Vector2(radius * 0.18, radius * 0.22), radius * 0.48, Color(1.0, 1.0, 1.0, 0.92))
	draw_line(center - Vector2(radius * 1.65, 0.0), center + Vector2(radius * 1.65, 0.0), Color(color.r, color.g, color.b, 0.28), 1.0, true)
	draw_line(center - Vector2(0.0, radius * 1.65), center + Vector2(0.0, radius * 1.65), Color(color.r, color.g, color.b, 0.22), 1.0, true)


func _draw_glow_polygon(points: PackedVector2Array, color: Color) -> void:
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= float(maxi(points.size(), 1))
	var alpha := color.a
	draw_colored_polygon(_scaled_polygon(points, center, 1.12), Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.9 * alpha))
	var glow_scales: Array[float] = [1.62, 1.34, 1.16]
	var glow_alphas: Array[float] = [0.018, 0.045, 0.1]
	for glow_index in range(glow_scales.size()):
		var scale_value := glow_scales[glow_index]
		var glow_points := PackedVector2Array()
		for point: Vector2 in points:
			glow_points.append(center + (point - center) * scale_value)
		draw_colored_polygon(glow_points, Color(color.r, color.g, color.b, glow_alphas[glow_index] * alpha))
	var surface := color.darkened(0.36)
	surface.a = 0.92 * alpha
	draw_colored_polygon(points, surface)
	draw_polyline(_close_polygon(points), Color(color.r, color.g, color.b, 0.82 * alpha), 1.35, true)


func _draw_glow_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	var alpha := color.a
	draw_polyline(points, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.82 * alpha), width + 4.0, true)
	for extra_width in [11.0, 6.0, 3.0]:
		draw_polyline(points, Color(color.r, color.g, color.b, 0.035 * alpha), width + float(extra_width), true)
	draw_polyline(points, color, width, true)


func _draw_glow_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var alpha := color.a
	draw_line(from, to, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.82 * alpha), width + 4.0, true)
	for extra_width in [11.0, 6.0, 3.0]:
		draw_line(from, to, Color(color.r, color.g, color.b, 0.035 * alpha), width + float(extra_width), true)
	draw_line(from, to, color, width, true)


func _draw_glow_arc(
	center: Vector2,
	radius: float,
	start_angle: float,
	end_angle: float,
	color: Color,
	width: float
) -> void:
	var alpha := color.a
	draw_arc(center, radius, start_angle, end_angle, 48, Color(COLOR_BACKGROUND_DEEP.r, COLOR_BACKGROUND_DEEP.g, COLOR_BACKGROUND_DEEP.b, 0.88 * alpha), width + 4.0, true)
	for extra_width in [10.0, 5.0]:
		draw_arc(center, radius, start_angle, end_angle, 48, Color(color.r, color.g, color.b, 0.04 * alpha), width + float(extra_width), true)
	draw_arc(center, radius, start_angle, end_angle, 48, color, width, true)


func _regular_polygon(center: Vector2, radius: float, sides: int, rotation_offset: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(sides):
		points.append(center + Vector2.from_angle(rotation_offset + float(index) * TAU / float(sides)) * radius)
	return points


func _sector_polygon(
	center: Vector2,
	radius: float,
	start_angle: float,
	end_angle: float,
	segments: int
) -> PackedVector2Array:
	var points := PackedVector2Array([center])
	for index in range(segments + 1):
		var ratio := float(index) / float(maxi(segments, 1))
		points.append(center + Vector2.from_angle(lerpf(start_angle, end_angle, ratio)) * radius)
	return points


func _scaled_polygon(points: PackedVector2Array, center: Vector2, scale_value: float) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	for point: Vector2 in points:
		scaled.append(center + (point - center) * scale_value)
	return scaled


func _chamfered_rect(rect: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position + Vector2(cut, 0.0),
		Vector2(rect.end.x - cut, rect.position.y),
		Vector2(rect.end.x, rect.position.y + cut),
		rect.end - Vector2(0.0, cut),
		rect.end - Vector2(cut, 0.0),
		Vector2(rect.position.x + cut, rect.end.y),
		Vector2(rect.position.x, rect.end.y - cut),
		rect.position + Vector2(0.0, cut),
	])


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


func _count_active_vfx_kinds() -> int:
	var active_kinds: Dictionary = {}
	for slot: Dictionary in _vfx_slots:
		if bool(slot["active"]):
			active_kinds[int(slot["kind"])] = true
	return active_kinds.size()


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
