# Doc: docs/代码/formal_client_boot.md
# Authority: docs/正式项目工作规划.md F1, docs/游戏设计文档.md §9
extends Node
class_name FormalClientBoot


const BOOT_LOG_PREFIX: String = "[FormalClientBoot]"


func _ready() -> void:
	print("%s formal client boot scene loaded" % BOOT_LOG_PREFIX)
