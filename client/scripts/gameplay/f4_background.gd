# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §3
class_name F4Background
extends Node2D


const AXIS_COLOR: Color = Color(0.32, 0.39, 0.44, 0.55)
const GRID_COLOR: Color = Color(0.20, 0.25, 0.29, 0.45)
const GRID_SPACING: float = 96.0
const GRID_EXTENT: int = 18
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
		draw_line(Vector2(offset, -extent), Vector2(offset, extent), color, width)
		draw_line(Vector2(-extent, offset), Vector2(extent, offset), color, width)

	draw_line(Vector2(-ORIGIN_MARKER_SIZE, 0.0), Vector2(ORIGIN_MARKER_SIZE, 0.0), AXIS_COLOR, 2.0)
	draw_line(Vector2(0.0, -ORIGIN_MARKER_SIZE), Vector2(0.0, ORIGIN_MARKER_SIZE), AXIS_COLOR, 2.0)
