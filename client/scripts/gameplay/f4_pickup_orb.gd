# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §7.1
class_name F4PickupOrb
extends Node2D


signal collected(amount: int)

const DRAW_RADIUS: float = 5.0
const COLLECT_DISTANCE: float = 8.0

var _amount: int = 0
var _pickup_speed: float = 0.0
var _target: Node2D = null


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	var distance: float = global_position.distance_to(_target.global_position)
	var pickup_range: float = 0.0
	if _target.has_method("pickup_range"):
		pickup_range = float(_target.call("pickup_range"))
	if distance > pickup_range:
		return
	if distance <= COLLECT_DISTANCE:
		collected.emit(_amount)
		PoolManager.release(self)
		return

	var direction: Vector2 = (_target.global_position - global_position).normalized()
	global_position += direction * _pickup_speed * scaled_delta


func configure(amount: int, target: Node2D, pickup_speed: float) -> void:
	_amount = maxi(amount, 0)
	_target = target
	_pickup_speed = pickup_speed
	queue_redraw()


func _pool_reset() -> void:
	_amount = 0
	_pickup_speed = 0.0
	_target = null
	visible = true


func _pool_release() -> void:
	_target = null


func _draw() -> void:
	draw_circle(Vector2.ZERO, DRAW_RADIUS, Color(0.45, 1.0, 0.62))
