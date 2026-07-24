# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §7.1
class_name PickupOrb
extends Node2D


signal collected(amount: int)
signal attraction_started()

const DRAW_RADIUS: float = 5.0
const COLLECT_DISTANCE: float = 8.0
const COLLECT_FEEDBACK_DURATION: float = 0.14
const DRAW_Z_INDEX: int = -10
const PLACEHOLDER_OUTLINE_SCALE: float = 1.36
const PULSE_SPEED: float = 10.0

@export_group("Visual Style")
@export var idle_fill_color: Color = Color(0.45, 1.0, 0.62)
@export var attracting_fill_color: Color = Color(0.65, 1.0, 0.80)
@export var collect_fill_color: Color = Color(0.82, 1.0, 0.68)
@export var outline_color: Color = Color(0.07, 0.06, 0.05, 0.82)
@export var attracting_ring_color: Color = Color(0.8, 1.0, 0.88, 0.45)
@export_range(0.5, 6.0, 0.1) var attracting_ring_width: float = 1.5

var _attract_blend: float = 0.0
var _amount: int = 0
var _collect_feedback_remaining: float = 0.0
var _pickup_speed: float = 0.0
var _target: Node2D = null
var _visual_time: float = 0.0
var _body_visual: Polygon2D = null
var _outline_visual: Polygon2D = null
var _attract_ring: Line2D = null


func _process(delta: float) -> void:
	_visual_time += delta
	if _collect_feedback_remaining > 0.0:
		_update_collect_feedback(GameClock.delta_scaled(delta))
		return
	if _attract_blend > 0.0:
		_attract_blend = maxf(_attract_blend - delta * 4.0, 0.0)
		_refresh_visuals()


func _physics_process(delta: float) -> void:
	if _collect_feedback_remaining > 0.0:
		return
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
		_attract_blend = 0.0
		return
	var was_attracting: bool = _attract_blend > 0.0
	_attract_blend = 1.0
	if not was_attracting:
		attraction_started.emit()
	if distance <= COLLECT_DISTANCE:
		_start_collect_feedback()
		return

	var direction: Vector2 = (_target.global_position - global_position).normalized()
	global_position += direction * _pickup_speed * scaled_delta


func configure(amount: int, target: Node2D, pickup_speed: float) -> void:
	_amount = maxi(amount, 0)
	_attract_blend = 0.0
	_collect_feedback_remaining = 0.0
	_target = target
	_pickup_speed = pickup_speed
	scale = Vector2.ONE
	z_index = DRAW_Z_INDEX
	add_to_group("active_pickups")
	_refresh_visuals()


func snapshot() -> Dictionary:
	return {
		"position": _vector_to_dict(global_position),
		"amount": _amount,
		"pickup_speed": _pickup_speed,
	}


func restore_snapshot(snapshot_data: Dictionary, target: Node2D) -> void:
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_amount = maxi(int(snapshot_data.get("amount", 0)), 0)
	_attract_blend = 0.0
	_collect_feedback_remaining = 0.0
	_target = target
	_pickup_speed = float(snapshot_data.get("pickup_speed", _pickup_speed))
	scale = Vector2.ONE
	z_index = DRAW_Z_INDEX
	add_to_group("active_pickups")
	_refresh_visuals()


func _pool_reset() -> void:
	_attract_blend = 0.0
	_amount = 0
	_collect_feedback_remaining = 0.0
	_pickup_speed = 0.0
	_target = null
	scale = Vector2.ONE
	z_index = DRAW_Z_INDEX
	visible = true
	_refresh_visuals()


func _pool_release() -> void:
	remove_from_group("active_pickups")
	_collect_feedback_remaining = 0.0
	_target = null


func is_collect_feedback_active() -> bool:
	return _collect_feedback_remaining > 0.0


func is_attracting() -> bool:
	return _attract_blend > 0.0


func _start_collect_feedback() -> void:
	var collected_amount: int = _amount
	_amount = 0
	_target = null
	_attract_blend = 1.0
	_collect_feedback_remaining = COLLECT_FEEDBACK_DURATION
	remove_from_group("active_pickups")
	collected.emit(collected_amount)
	_refresh_visuals()


func _update_collect_feedback(delta: float) -> void:
	_collect_feedback_remaining = maxf(_collect_feedback_remaining - delta, 0.0)
	if _collect_feedback_remaining <= 0.0:
		PoolManager.release(self)
		return
	_refresh_visuals()


func _draw_radius() -> float:
	if _collect_feedback_remaining > 0.0:
		var collect_elapsed: float = 1.0 - (_collect_feedback_remaining / COLLECT_FEEDBACK_DURATION)
		return DRAW_RADIUS * lerpf(1.0, 2.2, collect_elapsed)
	var pulse: float = (sin(_visual_time * PULSE_SPEED) + 1.0) * 0.5
	return DRAW_RADIUS * (1.0 + 0.35 * _attract_blend + 0.12 * pulse * _attract_blend)


func _draw_color() -> Color:
	if _collect_feedback_remaining > 0.0:
		var remaining_ratio: float = _collect_feedback_remaining / COLLECT_FEEDBACK_DURATION
		var collect_color: Color = collect_fill_color
		collect_color.a *= remaining_ratio
		return collect_color
	return idle_fill_color.lerp(attracting_fill_color, _attract_blend)


func _outline_color(fill_color: Color) -> Color:
	var result: Color = outline_color
	result.a *= fill_color.a
	return result


func _refresh_visuals() -> void:
	if _body_visual == null:
		_body_visual = get_node_or_null("Visual/Body") as Polygon2D
		_outline_visual = get_node_or_null("Visual/Outline") as Polygon2D
		_attract_ring = get_node_or_null("Visual/AttractRing") as Line2D
	if _body_visual == null or _outline_visual == null:
		return
	var radius: float = _draw_radius()
	var color: Color = _draw_color()
	_body_visual.scale = Vector2(radius, radius)
	_body_visual.color = color
	_outline_visual.scale = Vector2(radius * PLACEHOLDER_OUTLINE_SCALE, radius * PLACEHOLDER_OUTLINE_SCALE)
	_outline_visual.color = _outline_color(color)
	if _attract_ring != null:
		_attract_ring.visible = _attract_blend > 0.0 and _collect_feedback_remaining <= 0.0
		var ring_radius: float = radius + 3.0
		_attract_ring.scale = Vector2(ring_radius, ring_radius)
		_attract_ring.width = attracting_ring_width / ring_radius
		var ring_color: Color = attracting_ring_color
		ring_color.a *= _attract_blend
		_attract_ring.default_color = ring_color


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
