# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §4
class_name AmmoMagazinePickup
extends Node2D


signal collected(amount: int)
signal attraction_started()

const ACTIVE_PICKUP_GROUP: String = "active_ammo_magazines"
const COLLECT_DISTANCE: float = 8.0
const DRAW_Z_INDEX: int = -9
const PULSE_SPEED: float = 8.0

@export_group("Visual Style")
@export var idle_color: Color = Color(0.22, 0.72, 0.98, 1.0)
@export var attracting_color: Color = Color(0.48, 0.88, 1.0, 1.0)
@export var accent_color: Color = Color(0.92, 0.98, 1.0, 1.0)
@export var outline_color: Color = Color(0.03, 0.08, 0.12, 0.9)
@export var ring_color: Color = Color(0.36, 0.82, 1.0, 0.6)

var _amount: int = 0
var _attract_blend: float = 0.0
var _pickup_speed: float = 0.0
var _target: Node2D = null
var _weapon_receiver: Node = null
var _visual_time: float = 0.0
var _body_visual: Polygon2D = null
var _accent_visual: Polygon2D = null
var _outline_visual: Polygon2D = null
var _attract_ring: Line2D = null


func _process(delta: float) -> void:
	_visual_time += delta
	if _attract_blend <= 0.0:
		return
	_refresh_visuals()


func _physics_process(delta: float) -> void:
	if not _has_valid_receiver():
		_set_attracting(false)
		return
	if not GameState.is_state(GameState.PLAYING):
		return
	if not bool(_weapon_receiver.call("can_accept_ammo")):
		_set_attracting(false)
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	var distance: float = global_position.distance_to(_target.global_position)
	var pickup_range: float = 0.0
	if _target.has_method("pickup_range"):
		pickup_range = maxf(float(_target.call("pickup_range")), 0.0)
	if distance > pickup_range:
		_set_attracting(false)
		return
	_set_attracting(true)
	if distance <= COLLECT_DISTANCE:
		_collect()
		return

	var direction: Vector2 = (
		_target.global_position - global_position
	).normalized()
	global_position += direction * _pickup_speed * scaled_delta


func configure(
	amount: int,
	target: Node2D,
	weapon_receiver: Node,
	pickup_speed: float
) -> void:
	_amount = maxi(amount, 0)
	_target = target
	_weapon_receiver = weapon_receiver
	_pickup_speed = maxf(pickup_speed, 0.0)
	_attract_blend = 0.0
	_visual_time = 0.0
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE
	z_index = DRAW_Z_INDEX
	add_to_group(ACTIVE_PICKUP_GROUP)
	_refresh_visuals()


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"amount": _amount,
		"pickup_speed": _pickup_speed,
	}


func restore_snapshot(
	snapshot_data: Dictionary,
	target: Node2D,
	weapon_receiver: Node
) -> void:
	_amount = maxi(int(snapshot_data.get("amount", 0)), 0)
	_pickup_speed = maxf(
		float(snapshot_data.get("pickup_speed", 0.0)),
		0.0
	)
	_target = target
	_weapon_receiver = weapon_receiver
	global_position = _dict_to_vector(
		snapshot_data.get("position", {}),
		global_position
	)
	_attract_blend = 0.0
	_visual_time = 0.0
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE
	z_index = DRAW_Z_INDEX
	add_to_group(ACTIVE_PICKUP_GROUP)
	_refresh_visuals()


func _pool_reset() -> void:
	_amount = 0
	_attract_blend = 0.0
	_pickup_speed = 0.0
	_target = null
	_weapon_receiver = null
	_visual_time = 0.0
	global_position = Vector2.ZERO
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE
	z_index = DRAW_Z_INDEX
	visible = true
	remove_from_group(ACTIVE_PICKUP_GROUP)
	_refresh_visuals()


func _pool_release() -> void:
	_amount = 0
	_attract_blend = 0.0
	_pickup_speed = 0.0
	_target = null
	_weapon_receiver = null
	_visual_time = 0.0
	scale = Vector2.ONE
	rotation = 0.0
	modulate = Color.WHITE
	remove_from_group(ACTIVE_PICKUP_GROUP)
	_refresh_visuals()


func _collect() -> void:
	var applied_amount: int = int(_weapon_receiver.call("add_ammo", _amount))
	if applied_amount <= 0:
		_set_attracting(false)
		return
	collected.emit(applied_amount)
	PoolManager.release(self)


func _has_valid_receiver() -> bool:
	return (
		_target != null
		and is_instance_valid(_target)
		and _weapon_receiver != null
		and is_instance_valid(_weapon_receiver)
		and _weapon_receiver.has_method("can_accept_ammo")
		and _weapon_receiver.has_method("add_ammo")
	)


func _set_attracting(enabled: bool) -> void:
	var next_blend: float = 1.0 if enabled else 0.0
	if is_equal_approx(_attract_blend, next_blend):
		return
	var was_attracting: bool = _attract_blend > 0.0
	_attract_blend = next_blend
	if enabled and not was_attracting:
		attraction_started.emit()
	_refresh_visuals()


func _refresh_visuals() -> void:
	if _body_visual == null:
		_body_visual = get_node_or_null("Visual/Body") as Polygon2D
		_accent_visual = get_node_or_null("Visual/Accent") as Polygon2D
		_outline_visual = get_node_or_null("Visual/Outline") as Polygon2D
		_attract_ring = get_node_or_null("Visual/AttractRing") as Line2D
	if _body_visual == null or _outline_visual == null:
		return
	var pulse: float = (sin(_visual_time * PULSE_SPEED) + 1.0) * 0.5
	var attract_scale: float = 1.0 + 0.08 * pulse * _attract_blend
	_body_visual.scale = Vector2.ONE * attract_scale
	_body_visual.color = idle_color.lerp(attracting_color, _attract_blend)
	_outline_visual.scale = Vector2.ONE * attract_scale
	_outline_visual.color = outline_color
	if _accent_visual != null:
		_accent_visual.scale = Vector2.ONE * attract_scale
		_accent_visual.color = accent_color
	if _attract_ring != null:
		_attract_ring.visible = _attract_blend > 0.0
		_attract_ring.scale = Vector2.ONE * (1.0 + 0.1 * pulse)
		var active_ring_color: Color = ring_color
		active_ring_color.a *= _attract_blend
		_attract_ring.default_color = active_ring_color


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
