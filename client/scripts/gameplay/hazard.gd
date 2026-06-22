# Doc: docs/代码/hazard_system.md
# Authority: docs/游戏设计文档.md §5.4, docs/决策记录.md ADR #93
class_name Hazard
extends Node2D


const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")

const ACTIVE_FILL_COLOR: Color = Color(1.0, 0.42, 0.24, 0.34)
const ACTIVE_RING_COLOR: Color = Color(1.0, 0.72, 0.32, 0.88)
const IDLE_FILL_COLOR: Color = Color(0.34, 0.58, 0.78, 0.16)
const IDLE_RING_COLOR: Color = Color(0.65, 0.84, 0.94, 0.78)
const RING_WIDTH: float = 3.0
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

var _active_remaining: float = 0.0
var _cooldown_remaining: float = 0.0
var _damage: float = 0.0
var _damage_type: String = ""
var _duration: float = 0.0
var _hazard_id: String = ""
var _radius: float = 0.0
var _target: Node2D = null
var _trigger_interval: float = 1.0


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return
	_cooldown_remaining = maxf(_cooldown_remaining - scaled_delta, 0.0)
	_active_remaining = maxf(_active_remaining - scaled_delta, 0.0)
	if _target == null or not is_instance_valid(_target):
		queue_redraw()
		return
	if _cooldown_remaining <= 0.0 and global_position.distance_to(_target.global_position) <= _radius:
		_trigger()
	queue_redraw()


func configure(hazard_data: Dictionary, target: Node2D) -> void:
	_hazard_id = String(hazard_data.get("id", ""))
	_damage = float(hazard_data.get("damage", 0.0))
	_damage_type = String(hazard_data.get("damage_type", ""))
	_trigger_interval = maxf(float(hazard_data.get("trigger_interval", 1.0)), 0.01)
	_radius = maxf(float(hazard_data.get("radius", 1.0)), 1.0)
	_duration = maxf(float(hazard_data.get("duration", 0.0)), 0.0)
	_target = target
	_cooldown_remaining = 0.0
	_active_remaining = 0.0
	add_to_group("active_hazards")
	queue_redraw()


func hazard_id() -> String:
	return _hazard_id


func snapshot() -> Dictionary:
	return {
		"hazard_id": _hazard_id,
		"position": _vector_to_dict(global_position),
		"cooldown_remaining": _cooldown_remaining,
		"active_remaining": _active_remaining,
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_cooldown_remaining = maxf(float(snapshot_data.get("cooldown_remaining", 0.0)), 0.0)
	_active_remaining = maxf(float(snapshot_data.get("active_remaining", 0.0)), 0.0)
	queue_redraw()


func _pool_reset() -> void:
	_active_remaining = 0.0
	_cooldown_remaining = 0.0
	_damage = 0.0
	_damage_type = ""
	_duration = 0.0
	_hazard_id = ""
	_radius = 0.0
	_target = null
	_trigger_interval = 1.0
	visible = true


func _pool_release() -> void:
	remove_from_group("active_hazards")
	_target = null


func _draw() -> void:
	var fill_color: Color = ACTIVE_FILL_COLOR if _active_remaining > 0.0 else IDLE_FILL_COLOR
	var ring_color: Color = ACTIVE_RING_COLOR if _active_remaining > 0.0 else IDLE_RING_COLOR
	draw_circle(Vector2.ZERO, _radius, fill_color)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 72, ring_color, RING_WIDTH)
	draw_line(Vector2(-_radius * 0.35, 0.0), Vector2(_radius * 0.35, 0.0), ring_color, RING_WIDTH)
	draw_line(Vector2(0.0, -_radius * 0.35), Vector2(0.0, _radius * 0.35), ring_color, RING_WIDTH)


func _trigger() -> void:
	_cooldown_remaining = _trigger_interval
	_active_remaining = _duration
	if _target == null or not is_instance_valid(_target):
		return
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		_damage,
		_damage_type,
		self,
		_target,
		TEAM_ENEMY,
		TEAM_PLAYER
	)
	Combat.apply_damage(_target, info)


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
