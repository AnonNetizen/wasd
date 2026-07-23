# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §3, docs/决策记录.md ADR #125
class_name WorldBackground
extends Node2D


const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 160.0)

@export_group("Visual Style")
@export var grid_color: Color = Color(0.18, 0.23, 0.26, 0.42)
@export var axis_color: Color = Color(0.35, 0.40, 0.43, 0.58)
@export_range(0.5, 6.0, 0.1) var grid_width: float = 1.0
@export_range(0.5, 8.0, 0.1) var axis_width: float = 2.0
@export_range(4, 64, 1) var grid_extent: int = 26
@export_range(2.0, 64.0, 1.0) var origin_marker_size: float = 14.0

var _grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE
var _target: Node2D = null


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return

	global_position = _snap_to_grid(_target.global_position)


func configure(target: Node2D, grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE) -> void:
	_target = target
	_grid_cell_size = Vector2(maxf(grid_cell_size.x, 1.0), maxf(grid_cell_size.y, 1.0))
	queue_redraw()


func _draw() -> void:
	var extent_x: float = _grid_cell_size.x * float(grid_extent)
	var extent_y: float = _grid_cell_size.y * float(grid_extent)
	for index: int in range(-grid_extent, grid_extent + 1):
		var x_offset: float = float(index) * _grid_cell_size.x
		var y_offset: float = float(index) * _grid_cell_size.y
		draw_line(Vector2(x_offset, -extent_y), Vector2(x_offset, extent_y), grid_color, grid_width)
		draw_line(Vector2(-extent_x, y_offset), Vector2(extent_x, y_offset), grid_color, grid_width)

	draw_line(Vector2(-origin_marker_size, 0.0), Vector2(origin_marker_size, 0.0), axis_color, axis_width)
	draw_line(Vector2(0.0, -origin_marker_size), Vector2(0.0, origin_marker_size), axis_color, axis_width)


func _snap_to_grid(world_position: Vector2) -> Vector2:
	return Vector2(
		roundf(world_position.x / maxf(_grid_cell_size.x, 1.0)) * _grid_cell_size.x,
		roundf(world_position.y / maxf(_grid_cell_size.y, 1.0)) * _grid_cell_size.y
	)
