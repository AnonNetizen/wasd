# Doc: docs/代码/skill_system.md
# Authority: docs/游戏设计文档.md §9.15
class_name ProjectileBarrier
extends Node2D


signal health_changed(current_health: float, max_health: float)
signal defeated(barrier: Node)

const ACTIVE_BARRIER_GROUP: String = "active_projectile_blockers"
const ACTIVE_DEPLOYABLE_GROUP: String = "active_deployables"
const BOUNDARY_EPSILON: float = 0.000001
const TEAM_ENEMY: String = "team_enemy"

@export_group("Visual Style")
@export var fill_color: Color = Color(0.49, 0.39, 0.85, 0.12)
@export var outline_color: Color = Color(0.68, 0.57, 1.0, 0.92)
@export_range(0.5, 8.0, 0.1) var outline_width: float = 3.0

var _caster: Node = null
var _active: bool = false
var _current_health: float = 0.0
var _max_health: float = 0.0
var _pooled: bool = false
var _radius: float = 0.0
var _slot_id: String = ""


func configure(
	max_health: float,
	radius: float,
	caster: Node,
	slot_id: String,
	pooled: bool = true
) -> void:
	_max_health = maxf(max_health, 0.0)
	_current_health = _max_health
	_radius = maxf(radius, 0.0)
	_caster = caster
	_slot_id = slot_id
	_pooled = pooled
	_active = true
	add_to_group(ACTIVE_BARRIER_GROUP)
	add_to_group(ACTIVE_DEPLOYABLE_GROUP)
	queue_redraw()
	health_changed.emit(_current_health, _max_health)


func restore_snapshot(
	snapshot_data: Dictionary,
	caster: Node,
	pooled: bool = true
) -> void:
	global_position = _dict_to_vector(
		snapshot_data.get("position", {}),
		global_position
	)
	_max_health = maxf(float(snapshot_data.get("max_health", 0.0)), 0.0)
	_current_health = clampf(
		float(snapshot_data.get("current_health", _max_health)),
		0.0,
		_max_health
	)
	_radius = maxf(float(snapshot_data.get("radius", 0.0)), 0.0)
	_slot_id = String(snapshot_data.get("slot_id", ""))
	_caster = caster
	_pooled = pooled
	_active = true
	add_to_group(ACTIVE_BARRIER_GROUP)
	add_to_group(ACTIVE_DEPLOYABLE_GROUP)
	queue_redraw()
	health_changed.emit(_current_health, _max_health)


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"current_health": _current_health,
		"max_health": _max_health,
		"radius": _radius,
		"slot_id": _slot_id,
	}


func is_alive() -> bool:
	return _active and _current_health > 0.0


func hit_radius() -> float:
	return _radius


func projectile_boundary_hit_fraction(
	step_start: Vector2,
	step_end: Vector2,
	projectile_radius: float
) -> float:
	var collision_radius: float = (
		_radius
		+ maxf(projectile_radius, 0.0)
	)
	if collision_radius <= 0.0:
		return -1.0

	var segment: Vector2 = step_end - step_start
	var segment_length_squared: float = segment.length_squared()
	if segment_length_squared <= BOUNDARY_EPSILON:
		return -1.0

	var radius_squared: float = collision_radius * collision_radius
	var start_offset: Vector2 = step_start - global_position
	var end_offset: Vector2 = step_end - global_position
	var starts_inside: bool = (
		start_offset.length_squared()
		< radius_squared
	)
	var ends_inside: bool = end_offset.length_squared() < radius_squared
	if starts_inside and ends_inside:
		return -1.0

	var linear_term: float = 2.0 * start_offset.dot(segment)
	var constant_term: float = (
		start_offset.length_squared()
		- radius_squared
	)
	var discriminant: float = (
		linear_term * linear_term
		- 4.0 * segment_length_squared * constant_term
	)
	if discriminant < 0.0:
		return -1.0

	var denominator: float = 2.0 * segment_length_squared
	var root_offset: float = sqrt(maxf(discriminant, 0.0))
	var entry_fraction: float = (
		(-linear_term - root_offset)
		/ denominator
	)
	var exit_fraction: float = (
		(-linear_term + root_offset)
		/ denominator
	)
	if starts_inside:
		return (
			exit_fraction
			if _is_segment_fraction(exit_fraction)
			else -1.0
		)
	if _is_segment_fraction(entry_fraction):
		return entry_fraction
	return (
		exit_fraction
		if _is_segment_fraction(exit_fraction)
		else -1.0
	)


func current_health() -> float:
	return _current_health


func max_health() -> float:
	return _max_health


func slot_id() -> String:
	return _slot_id


func receive_damage(info: RefCounted) -> Dictionary:
	if not is_alive():
		return _damage_result(false, 0.0, true, "defeated")
	if String(info.get("source_team")) != TEAM_ENEMY:
		return _damage_result(false, 0.0, false, "team_ignored")
	var amount: float = maxf(float(info.get("amount")), 0.0)
	if amount <= 0.0:
		return _damage_result(false, 0.0, false, "non_positive_amount")
	var applied_amount: float = minf(amount, _current_health)
	_current_health = maxf(_current_health - amount, 0.0)
	health_changed.emit(_current_health, _max_health)
	queue_redraw()
	var was_defeated: bool = _current_health <= 0.0
	if was_defeated:
		defeated.emit(self)
		_release_or_free()
	return _damage_result(true, applied_amount, was_defeated, "applied")


func receive_projectile_damage(info: RefCounted) -> Dictionary:
	return receive_damage(info)


func dismiss() -> void:
	if not _active or not is_inside_tree():
		return
	_release_or_free()


func _pool_reset() -> void:
	_caster = null
	_active = false
	_current_health = 0.0
	_max_health = 0.0
	_pooled = true
	_radius = 0.0
	_slot_id = ""
	visible = true
	queue_redraw()


func _pool_release() -> void:
	remove_from_group(ACTIVE_BARRIER_GROUP)
	remove_from_group(ACTIVE_DEPLOYABLE_GROUP)
	_caster = null
	_active = false


func _draw() -> void:
	if _radius <= 0.0:
		return
	var health_ratio: float = (
		clampf(_current_health / _max_health, 0.0, 1.0)
		if _max_health > 0.0
		else 0.0
	)
	var current_fill: Color = fill_color
	current_fill.a *= lerpf(0.35, 1.0, health_ratio)
	var current_outline: Color = outline_color
	current_outline.a *= lerpf(0.3, 1.0, health_ratio)
	draw_circle(Vector2.ZERO, _radius, current_fill)
	draw_arc(
		Vector2.ZERO,
		_radius,
		0.0,
		TAU,
		64,
		current_outline,
		outline_width,
		true
	)


func _release_or_free() -> void:
	if not _active:
		return
	_active = false
	remove_from_group(ACTIVE_BARRIER_GROUP)
	remove_from_group(ACTIVE_DEPLOYABLE_GROUP)
	if _pooled:
		PoolManager.release(self)
	else:
		queue_free()


func _damage_result(
	applied: bool,
	amount: float,
	was_defeated: bool,
	reason: String
) -> Dictionary:
	return {
		"applied": applied,
		"amount": amount,
		"defeated": was_defeated,
		"reason": reason,
	}


func _is_segment_fraction(value: float) -> bool:
	return value >= 0.0 and value <= 1.0


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(
		float(value.get("x", fallback.x)),
		float(value.get("y", fallback.y))
	)
