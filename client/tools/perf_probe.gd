extends Node


const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")

const SAMPLE_FRAMES: int = 180

var _delta_samples: Array[float] = []
var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _process(delta: float) -> void:
	if _delta_samples.size() >= SAMPLE_FRAMES:
		return
	_delta_samples.append(delta)


func _run() -> void:
	var run_loop: Node = null
	for _index: int in range(30):
		await get_tree().process_frame
		run_loop = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if run_loop != null:
			break
	_expect(run_loop != null, "PerfProbe should run with GameplayRunLoop mounted")
	if run_loop == null:
		_finish({})
		return

	while _delta_samples.size() < SAMPLE_FRAMES:
		await get_tree().process_frame

	var snapshot: Dictionary = {}
	if run_loop.has_method("create_run_snapshot"):
		snapshot = run_loop.call("create_run_snapshot") as Dictionary
	var report: Dictionary = {
		"schema_version": 1,
		"sample_frames": _delta_samples.size(),
		"avg_frame_ms": _average_delta() * 1000.0,
		"max_frame_ms": _max_delta() * 1000.0,
		"game_time": GameClock.now(),
		"game_tick": GameClock.tick(),
		"kills": int(snapshot.get("kills", 0)),
		"level": int(snapshot.get("level", 1)),
		"pool_stats": {
			POOL_IDS.BULLET_BASIC: PoolManager.stats(POOL_IDS.BULLET_BASIC),
			POOL_IDS.ENEMY_CHASER: PoolManager.stats(POOL_IDS.ENEMY_CHASER),
			POOL_IDS.ENEMY_SWARM: PoolManager.stats(POOL_IDS.ENEMY_SWARM),
			POOL_IDS.PICKUP_ORB: PoolManager.stats(POOL_IDS.PICKUP_ORB),
		},
		"state": String(GameState.current()),
	}
	_finish(report)


func _average_delta() -> float:
	if _delta_samples.is_empty():
		return 0.0
	var total: float = 0.0
	for delta: float in _delta_samples:
		total += delta
	return total / float(_delta_samples.size())


func _max_delta() -> float:
	var result: float = 0.0
	for delta: float in _delta_samples:
		result = maxf(result, delta)
	return result


func _find_node_by_name(root_node: Node, target_name: String) -> Node:
	if root_node == null:
		return null
	if root_node.name == target_name:
		return root_node
	for child: Node in root_node.get_children():
		var match_node: Node = _find_node_by_name(child, target_name)
		if match_node != null:
			return match_node
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[PerfProbe] %s" % message)


func _finish(report: Dictionary) -> void:
	if _failures.is_empty():
		print("[PerfProbe] %s" % JSON.stringify(report))
		get_tree().quit(0)
		return

	print("[PerfProbe] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
