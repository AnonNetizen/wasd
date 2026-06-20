# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F9-ContentDemoPolish.md
class_name HitSpark
extends Node2D


const DURATION: float = 0.16
const LINE_COLOR: Color = Color(1.0, 0.88, 0.34, 0.95)
const OUTLINE_COLOR: Color = Color(0.07, 0.06, 0.05, 0.78)
const RAY_COUNT: int = 6

var _remaining: float = 0.0


func _process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	_remaining = maxf(_remaining - GameClock.delta_scaled(delta), 0.0)
	if _remaining <= 0.0:
		PoolManager.release(self)
		return
	queue_redraw()


func configure(spawn_position: Vector2) -> void:
	global_position = spawn_position
	_remaining = DURATION
	visible = true
	queue_redraw()


func _pool_reset() -> void:
	_remaining = 0.0
	rotation = 0.0
	scale = Vector2.ONE
	visible = true
	queue_redraw()


func _pool_release() -> void:
	_remaining = 0.0
	visible = false


func _draw() -> void:
	if _remaining <= 0.0:
		return
	var elapsed_ratio: float = 1.0 - (_remaining / DURATION)
	var alpha: float = 1.0 - elapsed_ratio
	var inner_radius: float = lerpf(2.0, 5.0, elapsed_ratio)
	var outer_radius: float = lerpf(7.0, 16.0, elapsed_ratio)
	var line_color: Color = LINE_COLOR
	line_color.a *= alpha
	var outline_color: Color = OUTLINE_COLOR
	outline_color.a *= alpha
	for index: int in range(RAY_COUNT):
		var direction: Vector2 = Vector2.RIGHT.rotated(TAU * float(index) / float(RAY_COUNT))
		var start: Vector2 = direction * inner_radius
		var end: Vector2 = direction * outer_radius
		draw_line(start, end, outline_color, 4.0)
		draw_line(start, end, line_color, 2.0)
	draw_arc(Vector2.ZERO, inner_radius + 2.0, 0.0, TAU, 18, line_color, 1.5)
