# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §3
class_name WorldBackground
extends Node2D


const AXIS_COLOR: Color = Color(0.35, 0.40, 0.43, 0.58)
const GRID_COLOR: Color = Color(0.18, 0.23, 0.26, 0.42)
const GRID_SPACING: float = 96.0
const GRID_EXTENT: int = 18
const OBLIQUE_GRID_SLOPE: float = 0.52
const ORIGIN_MARKER_SIZE: float = 14.0

var _target: Node2D = null


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	global_position = _target.global_position.snapped(Vector2(GRID_SPACING, GRID_SPACING))
	queue_redraw()


func configure(target: Node2D) -> void:
	_target = target
	queue_redraw()


func _draw() -> void:
	var extent: float = GRID_SPACING * float(GRID_EXTENT)
	for index: int in range(-GRID_EXTENT, GRID_EXTENT + 1):
		var offset: float = float(index) * GRID_SPACING
		var color: Color = AXIS_COLOR if index == 0 else GRID_COLOR
		var width: float = 2.0 if index == 0 else 1.0
		draw_line(
			Vector2(-extent, offset - extent * OBLIQUE_GRID_SLOPE),
			Vector2(extent, offset + extent * OBLIQUE_GRID_SLOPE),
			color,
			width
		)
		draw_line(
			Vector2(-extent, offset + extent * OBLIQUE_GRID_SLOPE),
			Vector2(extent, offset - extent * OBLIQUE_GRID_SLOPE),
			color,
			width
		)

	draw_line(Vector2(-ORIGIN_MARKER_SIZE, 0.0), Vector2(ORIGIN_MARKER_SIZE, 0.0), AXIS_COLOR, 2.0)
	draw_line(Vector2(0.0, -ORIGIN_MARKER_SIZE), Vector2(0.0, ORIGIN_MARKER_SIZE), AXIS_COLOR, 2.0)
