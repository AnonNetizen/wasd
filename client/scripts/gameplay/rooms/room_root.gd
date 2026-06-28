# Doc: docs/代码/room_manager.md
class_name RoomRoot
extends Node2D
## 手工房间根节点：声明房间矩形俯视边界与格尺寸，供 RoomManager 复用 MapManager 几何能力。
## 房间内容（出生点 / 门 / 敌人 / 陷阱）由子节点 marker 表达，玩家出生点取 RoomPlayerStartMarker。

@export var bounds_width: float = 1280.0
@export var bounds_height: float = 1280.0
@export var grid_cell_width: float = 160.0
@export var grid_cell_height: float = 160.0


func to_bounds_data() -> Dictionary:
	return {
		"bounds": {"width": bounds_width, "height": bounds_height},
		"grid": {"cell_width": grid_cell_width, "cell_height": grid_cell_height},
	}
