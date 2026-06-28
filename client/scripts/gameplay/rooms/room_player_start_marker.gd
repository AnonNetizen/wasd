# Doc: docs/代码/room_manager.md
class_name RoomPlayerStartMarker
extends Marker2D
## 玩家进入房间后的出生 / 入口点。entry_id 与门的 target_entry_id 对应，决定切房后玩家落点。

@export var entry_id: String = "entry_main"


func to_data() -> Dictionary:
	return {
		"entry_id": entry_id,
		"position": {"x": global_position.x, "y": global_position.y},
	}
