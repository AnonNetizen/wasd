extends RefCounted

## Pooled projectile data for the neon geometry combat experiment.

const TRAIL_CAPACITY := 10

enum ProjectileKind {
	PLAYER_BOLT,
	ENEMY_WEDGE,
	ENEMY_RING,
}

enum Team {
	PLAYER,
	ENEMY,
}

var active: bool = false
var kind: ProjectileKind = ProjectileKind.PLAYER_BOLT
var team: Team = Team.PLAYER
var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var lifetime_remaining: float = 0.0
var initial_lifetime: float = 0.0
var spawn_serial: int = 0
var hit_radius: float = 6.0
var _trail_positions := PackedVector2Array()
var _trail_write_index: int = 0
var _trail_sample_count: int = 0


func _init() -> void:
	_trail_positions.resize(TRAIL_CAPACITY)


func activate(
	projectile_kind: ProjectileKind,
	projectile_team: Team,
	spawn_position: Vector2,
	spawn_velocity: Vector2,
	lifetime: float,
	serial: int
) -> void:
	active = true
	kind = projectile_kind
	team = projectile_team
	position = spawn_position
	velocity = spawn_velocity
	lifetime_remaining = lifetime
	initial_lifetime = lifetime
	spawn_serial = serial
	_reset_trail(spawn_position)
	match kind:
		ProjectileKind.PLAYER_BOLT:
			hit_radius = 6.0
		ProjectileKind.ENEMY_WEDGE:
			hit_radius = 8.0
		ProjectileKind.ENEMY_RING:
			hit_radius = 10.0


func tick(delta: float) -> void:
	if not active:
		return
	position += velocity * delta
	_record_trail(position)
	lifetime_remaining -= delta
	if lifetime_remaining <= 0.0:
		deactivate()


func deactivate() -> void:
	active = false
	lifetime_remaining = 0.0
	velocity = Vector2.ZERO
	_trail_write_index = 0
	_trail_sample_count = 0


func facing_angle() -> float:
	if velocity.is_zero_approx():
		return 0.0
	return velocity.angle()


func life_ratio() -> float:
	if initial_lifetime <= 0.0:
		return 0.0
	return clampf(lifetime_remaining / initial_lifetime, 0.0, 1.0)


func trail_capacity() -> int:
	return TRAIL_CAPACITY


func trail_sample_count() -> int:
	return _trail_sample_count


func trail_position_from_head(sample_index: int) -> Vector2:
	if sample_index < 0 or sample_index >= _trail_sample_count:
		return position
	var buffer_index := posmod(_trail_write_index - 1 - sample_index, TRAIL_CAPACITY)
	return _trail_positions[buffer_index]


func prime_trail(direction: Vector2, spacing: float, sample_count: int = TRAIL_CAPACITY) -> void:
	var safe_direction := direction.normalized()
	if safe_direction.is_zero_approx():
		safe_direction = Vector2.RIGHT
	_trail_write_index = 0
	_trail_sample_count = 0
	var clamped_count := clampi(sample_count, 1, TRAIL_CAPACITY)
	for offset_index in range(clamped_count - 1, -1, -1):
		_record_trail(position - safe_direction * spacing * float(offset_index))


func _reset_trail(sample_position: Vector2) -> void:
	_trail_write_index = 0
	_trail_sample_count = 0
	_record_trail(sample_position)


func _record_trail(sample_position: Vector2) -> void:
	_trail_positions[_trail_write_index] = sample_position
	_trail_write_index = (_trail_write_index + 1) % TRAIL_CAPACITY
	_trail_sample_count = mini(_trail_sample_count + 1, TRAIL_CAPACITY)
