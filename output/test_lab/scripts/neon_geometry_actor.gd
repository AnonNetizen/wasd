extends RefCounted

## Fixed-data actor used by the neon geometry combat experiment.
## The root scene owns simulation and drawing so no actor nodes are created.

enum ActorKind {
	PLAYER,
	RING_HUNTER,
	TRI_AXIS_GUNNER,
}

var kind: ActorKind = ActorKind.PLAYER
var position: Vector2 = Vector2.ZERO
var spawn_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var aim_direction: Vector2 = Vector2.RIGHT
var hit_radius: float = 20.0
var max_hp: int = 1
var hp: int = 1
var alive: bool = true
var respawn_remaining: float = 0.0
var invulnerability_remaining: float = 0.0
var hit_flash_remaining: float = 0.0
var attack_cooldown: float = 0.0
var warning_remaining: float = 0.0
var attack_pending: bool = false
var motion_phase: float = 0.0
var spawn_motion_phase: float = 0.0
var recoil_strength: float = 0.0
var spawn_flash_remaining: float = 0.0


func configure(
	actor_kind: ActorKind,
	actor_spawn_position: Vector2,
	actor_max_hp: int,
	actor_hit_radius: float,
	phase: float = 0.0
) -> void:
	kind = actor_kind
	spawn_position = actor_spawn_position
	max_hp = actor_max_hp
	hit_radius = actor_hit_radius
	spawn_motion_phase = phase
	reset_actor()


func reset_actor(invulnerability_seconds: float = 0.0) -> void:
	position = spawn_position
	velocity = Vector2.ZERO
	aim_direction = Vector2.RIGHT
	hp = max_hp
	alive = true
	respawn_remaining = 0.0
	invulnerability_remaining = maxf(invulnerability_seconds, 0.0)
	hit_flash_remaining = 0.0
	attack_cooldown = 0.0
	warning_remaining = 0.0
	attack_pending = false
	motion_phase = spawn_motion_phase
	recoil_strength = 0.0
	spawn_flash_remaining = 0.0


func tick_timers(delta: float) -> void:
	if alive:
		invulnerability_remaining = maxf(invulnerability_remaining - delta, 0.0)
		hit_flash_remaining = maxf(hit_flash_remaining - delta, 0.0)
		attack_cooldown = maxf(attack_cooldown - delta, 0.0)
		warning_remaining = maxf(warning_remaining - delta, 0.0)
		recoil_strength *= pow(0.025, delta)
		spawn_flash_remaining = maxf(spawn_flash_remaining - delta, 0.0)
	else:
		respawn_remaining = maxf(respawn_remaining - delta, 0.0)


func apply_damage(amount: int) -> bool:
	if not alive or invulnerability_remaining > 0.0 or amount <= 0:
		return false
	hp = maxi(hp - amount, 0)
	hit_flash_remaining = 0.11
	return hp <= 0


func defeat(respawn_delay: float) -> void:
	hp = 0
	alive = false
	velocity = Vector2.ZERO
	respawn_remaining = maxf(respawn_delay, 0.0)
	invulnerability_remaining = 0.0
	hit_flash_remaining = 0.0
	warning_remaining = 0.0
	attack_pending = false
	recoil_strength = 0.0
	spawn_flash_remaining = 0.0


func aim_toward(target_position: Vector2) -> void:
	var direction := position.direction_to(target_position)
	if not direction.is_zero_approx():
		aim_direction = direction
