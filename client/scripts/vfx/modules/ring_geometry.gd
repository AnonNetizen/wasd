# Doc: docs/代码/visual_effects.md
@tool
class_name VfxRingGeometry
extends Node2D
## Curated ring/tick readability skeleton. Catalog entries may only use it inside composites.


@export_range(1.0, 512.0, 1.0) var radius: float = 24.0:
	set(value):
		radius = value
		queue_redraw()
@export_range(1.0, 32.0, 0.5) var width: float = 3.0:
	set(value):
		width = value
		queue_redraw()
@export_range(3, 96, 1) var segments: int = 32:
	set(value):
		segments = value
		queue_redraw()
@export_range(0, 24, 1) var tick_count: int = 8:
	set(value):
		tick_count = value
		queue_redraw()
@export_range(0.0, 64.0, 0.5) var tick_length: float = 6.0:
	set(value):
		tick_length = value
		queue_redraw()
@export var ring_color: Color = Color(1.0, 0.78, 0.25, 1.0):
	set(value):
		ring_color = value
		queue_redraw()


func _draw() -> void:
	var points := PackedVector2Array()
	var normalized_segments: int = maxi(segments, 3)
	for index: int in range(normalized_segments + 1):
		var angle: float = TAU * float(index) / float(normalized_segments)
		points.append(Vector2.RIGHT.rotated(angle) * radius)
	draw_polyline(points, ring_color, width, true)
	if tick_count <= 0 or tick_length <= 0.0:
		return
	for index: int in range(tick_count):
		var direction: Vector2 = Vector2.RIGHT.rotated(TAU * float(index) / float(tick_count))
		draw_line(
			direction * (radius - tick_length * 0.5),
			direction * (radius + tick_length),
			ring_color,
			width,
			true
		)
