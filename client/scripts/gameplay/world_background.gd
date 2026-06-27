# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §3, docs/决策记录.md ADR #125
class_name WorldBackground
extends Node2D


const AXIS_COLOR: Color = Color(0.35, 0.40, 0.43, 0.58)
const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 160.0)
const GRID_COLOR: Color = Color(0.18, 0.23, 0.26, 0.42)
const GRID_EXTENT: int = 26
const ORIGIN_MARKER_SIZE: float = 14.0

var _grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE
var _target: Node2D = null


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	global_position = _snap_to_grid(_target.global_position)
	queue_redraw()


func configure(target: Node2D, grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE) -> void:
	_target = target
	_grid_cell_size = Vector2(maxf(grid_cell_size.x, 1.0), maxf(grid_cell_size.y, 1.0))
	queue_redraw()


func _draw() -> void:
	var extent_x: float = _grid_cell_size.x * float(GRID_EXTENT)
	var extent_y: float = _grid_cell_size.y * float(GRID_EXTENT)
	for index: int in range(-GRID_EXTENT, GRID_EXTENT + 1):
		var x_offset: float = float(index) * _grid_cell_size.x
		var y_offset: float = float(index) * _grid_cell_size.y
		draw_line(Vector2(x_offset, -extent_y), Vector2(x_offset, extent_y), GRID_COLOR, 1.0)
		draw_line(Vector2(-extent_x, y_offset), Vector2(extent_x, y_offset), GRID_COLOR, 1.0)

	draw_line(Vector2(-ORIGIN_MARKER_SIZE, 0.0), Vector2(ORIGIN_MARKER_SIZE, 0.0), AXIS_COLOR, 2.0)
	draw_line(Vector2(0.0, -ORIGIN_MARKER_SIZE), Vector2(0.0, ORIGIN_MARKER_SIZE), AXIS_COLOR, 2.0)


func _snap_to_grid(world_position: Vector2) -> Vector2:
	return Vector2(
		roundf(world_position.x / maxf(_grid_cell_size.x, 1.0)) * _grid_cell_size.x,
		roundf(world_position.y / maxf(_grid_cell_size.y, 1.0)) * _grid_cell_size.y
	)
