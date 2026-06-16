# Doc: docs/代码/formal_client_boot.md
# Authority: docs/正式项目工作规划.md F1, docs/游戏设计文档.md §9
extends Node
class_name FormalClientBoot


const BOOT_LOG_PREFIX: String = "[FormalClientBoot]"


func _ready() -> void:
	var contract_count: int = DataLoader.contracts().size()
	var stream_count: int = DataLoader.contract_values("rng_streams").size()
	var state_name: StringName = GameState.current()
	print("%s formal client boot scene loaded; contracts=%d rng_streams=%d state=%s seed=%d" % [
		BOOT_LOG_PREFIX,
		contract_count,
		stream_count,
		String(state_name),
		RNG.run_seed(),
	])
