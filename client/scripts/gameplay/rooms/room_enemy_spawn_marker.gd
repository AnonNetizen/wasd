# Doc: docs/代码/room_manager.md
class_name RoomEnemySpawnMarker
extends Marker2D
## 房间敌人生成点。enemy_id 必须存在于 enemies.csv；RoomManager 读取后由 GameplayRunLoop 走对象池生成。
## 首片 trigger 仅支持 "on_enter"（进房即生成）；delay / 其他触发留作后续扩展。

@export var enemy_id: String = "enemy_chaser"
@export var count: int = 1
@export var delay: float = 0.0
@export var trigger: String = "on_enter"


func to_data() -> Dictionary:
	return {
		"enemy_id": enemy_id,
		"count": maxi(count, 1),
		"delay": maxf(delay, 0.0),
		"trigger": trigger,
		"position": {"x": global_position.x, "y": global_position.y},
	}
