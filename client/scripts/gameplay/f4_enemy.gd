# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §5.3
class_name F4Enemy
extends Node2D


signal defeated(enemy: Node, exp_reward: int)

const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const HIT_FLASH_DURATION: float = 0.16

var _contact_damage: float = 0.0
var _contact_damage_type: String = ""
var _dealt_contact: bool = false
var _exp_reward: int = 0
var _hit_flash_remaining: float = 0.0
var _hit_radius: float = 0.0
var _life_points: float = 1.0
var _max_life: float = 1.0
var _move_speed: float = 0.0
var _target: Node2D = null


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	_update_hit_flash(scaled_delta)

	var to_target: Vector2 = _target.global_position - global_position
	if to_target.length_squared() > 0.0:
		global_position += to_target.normalized() * _move_speed * scaled_delta
	_check_contact()


func configure(enemy_data: Dictionary, target: Node2D) -> void:
	_target = target
	_max_life = float(enemy_data.get("max_hp", 1))
	_life_points = _max_life
	_move_speed = float(enemy_data.get("move_speed", 0.0))
	_contact_damage = float(enemy_data.get("contact_damage", 0))
	_contact_damage_type = String(enemy_data.get("contact_damage_type", ""))
	_exp_reward = int(enemy_data.get("exp_reward", 0))
	_hit_radius = float(enemy_data.get("hit_radius", 0.0))
	_dealt_contact = false
	add_to_group("f4_enemies")
	queue_redraw()


func hit_radius() -> float:
	return _hit_radius


func is_alive() -> bool:
	return _life_points > 0.0


func receive_damage(info: RefCounted) -> Dictionary:
	var amount: float = float(info.get("amount"))
	var applied_amount: float = minf(amount, _life_points)
	_life_points = maxf(_life_points - amount, 0.0)
	var is_defeated: bool = _life_points <= 0.0
	if is_defeated:
		defeated.emit(self, _exp_reward)
		PoolManager.release(self)
	else:
		_start_hit_flash()
	return {
		"applied": true,
		"amount": applied_amount,
		"defeated": is_defeated,
		"reason": "applied",
	}


func _pool_reset() -> void:
	_contact_damage = 0.0
	_contact_damage_type = ""
	_dealt_contact = false
	_exp_reward = 0
	_hit_flash_remaining = 0.0
	_hit_radius = 0.0
	_life_points = 1.0
	_max_life = 1.0
	_move_speed = 0.0
	_target = null


func _pool_release() -> void:
	remove_from_group("f4_enemies")
	_target = null


func _draw() -> void:
	var radius: float = maxf(_hit_radius, 8.0)
	var color: Color = Color.WHITE if _hit_flash_remaining > 0.0 else Color(1.0, 0.38, 0.32)
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, -radius),
		Vector2(radius * 0.85, radius),
		Vector2(-radius * 0.85, radius),
	])
	draw_colored_polygon(points, color)


func _start_hit_flash() -> void:
	_hit_flash_remaining = HIT_FLASH_DURATION
	queue_redraw()


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_remaining <= 0.0:
		return
	_hit_flash_remaining = maxf(_hit_flash_remaining - delta, 0.0)
	queue_redraw()


func _check_contact() -> void:
	var distance: float = global_position.distance_to(_target.global_position)
	if distance > _hit_radius:
		_dealt_contact = false
		return
	if _dealt_contact:
		return

	_dealt_contact = true
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(_contact_damage, _contact_damage_type, self, _target, "team_enemy", "team_player")
	Combat.apply_damage(_target, info)
