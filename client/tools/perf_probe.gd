extends Node


const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")

const BASELINE_ID: String = "f8_perf_probe_standard_180f"
const SAMPLE_FRAMES: int = 180
const WARMUP_FRAMES: int = 30
const TARGET_FRAME_MS: float = 20.0
const WARNING_FRAME_MS: float = 33.0
const WARNING_BULLET_PEAK: int = 800
const WARNING_ENEMY_PEAK: int = 300

var _delta_samples: Array[float] = []
var _entity_peak_counts: Dictionary = {
	"active_bullets": 0,
	"active_enemies": 0,
	"active_hazards": 0,
	"active_pickups": 0,
}
var _failures: Array[String] = []
var _pool_peak_active: Dictionary = {}
var _run_loop: Node = null
var _sampling_enabled: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for pool_id: String in _pool_ids():
		_pool_peak_active[pool_id] = 0
	call_deferred("_run")


func _process(delta: float) -> void:
	if not _sampling_enabled:
		return
	if _delta_samples.size() >= SAMPLE_FRAMES:
		return
	_delta_samples.append(delta)
	if _run_loop != null:
		_sample_runtime_metrics()


func _run() -> void:
	for _index: int in range(30):
		await get_tree().process_frame
		_run_loop = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if _run_loop != null:
			break
	_expect(_run_loop != null, "PerfProbe should run with GameplayRunLoop mounted")
	if _run_loop == null:
		_finish({})
		return

	for _index: int in range(WARMUP_FRAMES):
		await get_tree().process_frame
	_reset_samples()
	_sampling_enabled = true
	while _delta_samples.size() < SAMPLE_FRAMES:
		await get_tree().process_frame
	_sampling_enabled = false

	_sample_runtime_metrics()
	var snapshot: Dictionary = _run_snapshot()
	var frame_time_ms: Dictionary = _frame_time_report()
	var report: Dictionary = {
		"schema_version": 2,
		"baseline_id": BASELINE_ID,
		"scenario": "standard_survival_default",
		"run_seed": RNG.run_seed(),
		"sample_frames": _delta_samples.size(),
		"warmup_frames": WARMUP_FRAMES,
		"target_frame_ms": TARGET_FRAME_MS,
		"warning_frame_ms": WARNING_FRAME_MS,
		"avg_frame_ms": frame_time_ms["avg"],
		"max_frame_ms": frame_time_ms["max"],
		"frame_time_ms": frame_time_ms,
		"game_time": GameClock.now(),
		"game_tick": GameClock.tick(),
		"kills": int(snapshot.get("kills", 0)),
		"level": int(snapshot.get("level", 1)),
		"active_counts": _active_counts(snapshot),
		"peak_counts": _entity_peak_counts.duplicate(true),
		"pool_peak_active": _pool_peak_active.duplicate(true),
		"pool_stats": _pool_stats(),
		"state": String(GameState.current()),
	}
	report["budget_status"] = _budget_status(report)
	_finish(report)


func _reset_samples() -> void:
	_delta_samples.clear()
	_entity_peak_counts = {
		"active_bullets": 0,
		"active_enemies": 0,
		"active_hazards": 0,
		"active_pickups": 0,
	}
	for pool_id: String in _pool_ids():
		_pool_peak_active[pool_id] = 0


func _frame_time_report() -> Dictionary:
	return {
		"avg": _average_delta() * 1000.0,
		"p95": _percentile_delta(0.95) * 1000.0,
		"p99": _percentile_delta(0.99) * 1000.0,
		"max": _max_delta() * 1000.0,
	}


func _average_delta() -> float:
	if _delta_samples.is_empty():
		return 0.0
	var total: float = 0.0
	for delta: float in _delta_samples:
		total += delta
	return total / float(_delta_samples.size())


func _percentile_delta(percentile: float) -> float:
	if _delta_samples.is_empty():
		return 0.0
	var sorted_samples: Array[float] = _delta_samples.duplicate()
	sorted_samples.sort()
	var clamped_percentile: float = clampf(percentile, 0.0, 1.0)
	var index: int = int(ceil(clamped_percentile * float(sorted_samples.size() - 1)))
	return sorted_samples[index]


func _max_delta() -> float:
	var result: float = 0.0
	for delta: float in _delta_samples:
		result = maxf(result, delta)
	return result


func _sample_runtime_metrics() -> void:
	var snapshot: Dictionary = _run_snapshot()
	var active_counts: Dictionary = _active_counts(snapshot)
	for key: String in active_counts.keys():
		_entity_peak_counts[key] = maxi(int(_entity_peak_counts.get(key, 0)), int(active_counts[key]))
	for pool_id: String in _pool_ids():
		var stats: Dictionary = PoolManager.stats(pool_id)
		_pool_peak_active[pool_id] = maxi(int(_pool_peak_active.get(pool_id, 0)), int(stats.get("active", 0)))


func _run_snapshot() -> Dictionary:
	if _run_loop != null and _run_loop.has_method("create_run_snapshot"):
		return _run_loop.call("create_run_snapshot") as Dictionary
	return {}


func _active_counts(snapshot: Dictionary) -> Dictionary:
	return {
		"active_bullets": _array_size(snapshot.get("bullets", [])),
		"active_enemies": _array_size(snapshot.get("enemies", [])),
		"active_hazards": _array_size(snapshot.get("hazards", [])),
		"active_pickups": _array_size(snapshot.get("pickups", [])),
	}


func _pool_stats() -> Dictionary:
	var result: Dictionary = {}
	for pool_id: String in _pool_ids():
		result[pool_id] = PoolManager.stats(pool_id)
	return result


func _pool_ids() -> Array[String]:
	return [
		POOL_IDS.BULLET_BASIC,
		POOL_IDS.ENEMY_CHASER,
		POOL_IDS.ENEMY_SWARM,
		POOL_IDS.HAZARD_SPIKE,
		POOL_IDS.PICKUP_ORB,
	]


func _budget_status(report: Dictionary) -> Dictionary:
	var frame_time_ms: Dictionary = report.get("frame_time_ms", {}) as Dictionary
	var peak_counts: Dictionary = report.get("peak_counts", {}) as Dictionary
	var warnings: Array[String] = []
	if float(frame_time_ms.get("p99", 0.0)) > WARNING_FRAME_MS:
		warnings.append("frame_time_p99")
	if int(peak_counts.get("active_bullets", 0)) > WARNING_BULLET_PEAK:
		warnings.append("bullet_peak")
	if int(peak_counts.get("active_enemies", 0)) > WARNING_ENEMY_PEAK:
		warnings.append("enemy_peak")
	return {
		"status": "warn" if not warnings.is_empty() else "pass",
		"warnings": warnings,
		"targets": {
			"frame_time_p99_ms": TARGET_FRAME_MS,
			"frame_time_warning_ms": WARNING_FRAME_MS,
			"bullet_peak_warning": WARNING_BULLET_PEAK,
			"enemy_peak_warning": WARNING_ENEMY_PEAK,
		},
	}


func _array_size(value: Variant) -> int:
	if value is Array:
		return (value as Array).size()
	return 0


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
