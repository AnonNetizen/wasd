# Doc: docs/代码/skill_system.md
# Authority: docs/游戏设计文档.md §9.15
class_name EnergyOrb
extends Node2D


signal collected(amount: float)

const ACTIVE_ENERGY_ORB_GROUP: String = "active_energy_orbs"
const COLLECT_DISTANCE: float = 8.0
const DRAW_RADIUS: float = 6.0
const SKILL_RESOURCES := preload(
	"res://scripts/contracts/skill_resources.gd"
)

@export_group("Visual Style")
@export var fill_color: Color = Color(0.95, 0.63, 0.18, 1.0)
@export var outline_color: Color = Color(0.15, 0.08, 0.03, 0.9)

var _amount: float = 0.0
var _pickup_speed: float = 0.0
var _resource_id: String = SKILL_RESOURCES.ENERGY
var _resource_receiver: Node = null
var _target: Node2D = null


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _resource_receiver == null or not is_instance_valid(_resource_receiver):
		return
	if not GameState.is_gameplay_simulation_active():
		return
	if not _can_collect():
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
		_collect()
		return
	var direction: Vector2 = (
		_target.global_position - global_position
	).normalized()
	global_position += direction * _pickup_speed * scaled_delta


func configure(
	amount: float,
	target: Node2D,
	resource_receiver: Node,
	pickup_speed: float,
	resource_id: String = SKILL_RESOURCES.ENERGY
) -> void:
	_amount = maxf(amount, 0.0)
	_target = target
	_resource_receiver = resource_receiver
	_pickup_speed = maxf(pickup_speed, 0.0)
	_resource_id = resource_id
	add_to_group(ACTIVE_ENERGY_ORB_GROUP)
	queue_redraw()


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"amount": _amount,
		"pickup_speed": _pickup_speed,
		"resource_id": _resource_id,
	}


func restore_snapshot(
	snapshot_data: Dictionary,
	target: Node2D,
	resource_receiver: Node
) -> void:
	global_position = _dict_to_vector(
		snapshot_data.get("position", {}),
		global_position
	)
	_amount = maxf(float(snapshot_data.get("amount", 0.0)), 0.0)
	_pickup_speed = maxf(
		float(snapshot_data.get("pickup_speed", 0.0)),
		0.0
	)
	_resource_id = String(
		snapshot_data.get("resource_id", SKILL_RESOURCES.ENERGY)
	)
	_target = target
	_resource_receiver = resource_receiver
	add_to_group(ACTIVE_ENERGY_ORB_GROUP)
	queue_redraw()


func _pool_reset() -> void:
	_amount = 0.0
	_pickup_speed = 0.0
	_resource_id = SKILL_RESOURCES.ENERGY
	_resource_receiver = null
	_target = null
	visible = true
	queue_redraw()


func _pool_release() -> void:
	remove_from_group(ACTIVE_ENERGY_ORB_GROUP)
	_resource_receiver = null
	_target = null


func _can_collect() -> bool:
	if not _resource_receiver.has_method("resource_amount"):
		return false
	if not _resource_receiver.has_method("resource_maximum"):
		return false
	return (
		float(_resource_receiver.call("resource_amount", _resource_id))
		< float(_resource_receiver.call("resource_maximum", _resource_id))
	)


func _collect() -> void:
	if not _resource_receiver.has_method("add_resource"):
		return
	var result: Variant = _resource_receiver.call(
		"add_resource",
		_resource_id,
		_amount
	)
	if not result is Dictionary:
		return
	var applied_amount: float = float(
		(result as Dictionary).get("applied_amount", 0.0)
	)
	if applied_amount <= 0.0:
		return
	collected.emit(applied_amount)
	PoolManager.release(self)


func _draw() -> void:
	draw_circle(Vector2.ZERO, DRAW_RADIUS * 1.35, outline_color)
	draw_circle(Vector2.ZERO, DRAW_RADIUS, fill_color)


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
