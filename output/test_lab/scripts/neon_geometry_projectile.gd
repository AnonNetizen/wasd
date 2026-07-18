extends RefCounted

## Pooled projectile data for the neon geometry combat experiment.

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
	lifetime_remaining -= delta
	if lifetime_remaining <= 0.0:
		deactivate()


func deactivate() -> void:
	active = false
	lifetime_remaining = 0.0
	velocity = Vector2.ZERO


func facing_angle() -> float:
	if velocity.is_zero_approx():
		return 0.0
	return velocity.angle()


func life_ratio() -> float:
	if initial_lifetime <= 0.0:
		return 0.0
	return clampf(lifetime_remaining / initial_lifetime, 0.0, 1.0)
