# Doc: docs/代码/room_manager.md
class_name RoomHazardMarker
extends Marker2D
## 房间陷阱 / 机关摆点。hazard_id 必须存在于 hazards.csv；复用通用 Hazard + 对象池 + Combat。
## enabled_at_start=true 时进房即布置；false 留作后续触发式机关扩展。

@export var hazard_id: String = "hazard_spike_trap"
@export var enabled_at_start: bool = true


func to_data() -> Dictionary:
	return {
		"hazard_id": hazard_id,
		"enabled_at_start": enabled_at_start,
		"position": {"x": global_position.x, "y": global_position.y},
	}
