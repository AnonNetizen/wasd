extends Node
## Emits a machine-readable marker as soon as the formal module-world run is playable.

const MAX_WAIT_FRAMES: int = 120


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	for _frame: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		if GameState.is_state(GameState.PLAYING) and _find_node_by_name(get_tree().root, "GameplayRunLoop") != null:
			print("[StartupProbe] PLAYABLE")
			get_tree().quit(0)
			return
	push_error("[StartupProbe] formal run did not become playable")
	get_tree().quit(1)


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var result: Node = _find_node_by_name(child, target_name)
		if result != null:
			return result
	return null
