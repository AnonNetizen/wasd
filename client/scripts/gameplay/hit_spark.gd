# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F9-ContentDemoPolish.md
class_name HitSpark
extends Node2D


const DURATION: float = 0.16
const RAY_COUNT: int = 6

var _remaining: float = 0.0
var _visual: Node2D = null


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(_remaining - GameClock.delta_scaled(delta), 0.0)
	if _remaining <= 0.0:
		PoolManager.release(self)
		return
	_refresh_visuals()


func configure(spawn_position: Vector2) -> void:
	global_position = spawn_position
	_remaining = DURATION
	visible = true
	_refresh_visuals()


func _pool_reset() -> void:
	_remaining = 0.0
	rotation = 0.0
	scale = Vector2.ONE
	visible = true
	_refresh_visuals()


func _pool_release() -> void:
	_remaining = 0.0
	visible = false
	if _visual != null:
		_visual.hide()


func _refresh_visuals() -> void:
	if _visual == null:
		_visual = get_node_or_null("Visual") as Node2D
	if _visual == null:
		return
	_visual.visible = _remaining > 0.0
	if _remaining <= 0.0:
		return
	var elapsed_ratio: float = 1.0 - (_remaining / DURATION)
	var alpha: float = 1.0 - elapsed_ratio
	var inner_radius: float = lerpf(2.0, 5.0, elapsed_ratio)
	var outer_radius: float = lerpf(7.0, 16.0, elapsed_ratio)
	_visual.modulate = Color(1.0, 1.0, 1.0, alpha)
	for index: int in range(RAY_COUNT):
		var ray: Node2D = _visual.get_node_or_null("Rays/Ray%02d" % index) as Node2D
		if ray == null:
			continue
		var ray_points := PackedVector2Array([Vector2(inner_radius, 0.0), Vector2(outer_radius, 0.0)])
		var outline: Line2D = ray.get_node_or_null("Outline") as Line2D
		var fill: Line2D = ray.get_node_or_null("Fill") as Line2D
		if outline != null:
			outline.points = ray_points
		if fill != null:
			fill.points = ray_points
	var ring: Line2D = _visual.get_node_or_null("Ring") as Line2D
	if ring != null:
		ring.points = _circle_points(inner_radius + 2.0, 18)


func _circle_points(radius: float, point_count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index: int in range(point_count):
		result.append(Vector2.RIGHT.rotated(TAU * float(index) / float(point_count)) * radius)
	return result
