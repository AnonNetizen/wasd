# Doc: docs/代码/room_manager.md
class_name RoomDoorMarker
extends Marker2D
## 房间出入口门。direction / unlock_rule 走契约常量；target_entry_id 指向下一房间入口 marker。
## 首片为线性序列：清房后 unlock_on_clear 解锁，玩家进入 trigger_radius 即切到序列下一房间。

const DOOR_DIRECTIONS := preload("res://scripts/contracts/door_directions.gd")
const DOOR_UNLOCK_RULES := preload("res://scripts/contracts/door_unlock_rules.gd")

@export var door_id: String = "door_exit"
@export var target_entry_id: String = "entry_main"
@export var direction: String = DOOR_DIRECTIONS.DIR_EAST
@export var unlock_rule: String = DOOR_UNLOCK_RULES.UNLOCK_ON_CLEAR
@export var trigger_radius: float = 96.0


func to_data() -> Dictionary:
	return {
		"door_id": door_id,
		"target_entry_id": target_entry_id,
		"direction": direction,
		"unlock_rule": unlock_rule,
		"trigger_radius": maxf(trigger_radius, 1.0),
		"position": {"x": global_position.x, "y": global_position.y},
	}
