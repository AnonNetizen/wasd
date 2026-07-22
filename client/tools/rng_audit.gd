extends Node


const SAMPLE_COUNT: int = 10_000
const ROLLS_PER_STREAM: int = 4
const FIRST_RUN_SEED: int = 1
const MAX_ABS_CORRELATION: float = 0.06
const RNG_STREAMS := preload("res://scripts/contracts/rng_streams.gd")
const STREAM_IDS: Array[String] = [
	"spawn",
	"drop",
	"combat",
	RNG_STREAMS.CAMERA_FX,
	"ui_choice",
	"world",
	"meta",
]

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	var rolls_by_stream: Dictionary = _new_roll_buckets()
	for offset: int in range(SAMPLE_COUNT):
		RNG.set_run_seed(FIRST_RUN_SEED + offset)
		for stream_id: String in STREAM_IDS:
			var stream: RngAutoload.Stream = RNG.stream(stream_id)
			var buckets: Array = rolls_by_stream[stream_id] as Array
			for roll_index: int in range(ROLLS_PER_STREAM):
				(buckets[roll_index] as Array[float]).append(stream.randf())

	var max_abs_correlation: float = 0.0
	var max_pair: String = ""
	for left_index: int in range(STREAM_IDS.size()):
		for right_index: int in range(left_index + 1, STREAM_IDS.size()):
			var left_stream: String = STREAM_IDS[left_index]
			var right_stream: String = STREAM_IDS[right_index]
			for left_roll_index: int in range(ROLLS_PER_STREAM):
				for right_roll_index: int in range(ROLLS_PER_STREAM):
					var left_values: Array[float] = (rolls_by_stream[left_stream] as Array)[left_roll_index] as Array[float]
					var right_values: Array[float] = (rolls_by_stream[right_stream] as Array)[right_roll_index] as Array[float]
					var correlation: float = _pearson_correlation(left_values, right_values)
					var abs_correlation: float = absf(correlation)
					if abs_correlation > max_abs_correlation:
						max_abs_correlation = abs_correlation
						max_pair = "%s[%d] vs %s[%d]" % [left_stream, left_roll_index, right_stream, right_roll_index]
					if abs_correlation > MAX_ABS_CORRELATION:
						_failures.append(
							"%s[%d] vs %s[%d] correlation %.5f exceeds %.5f"
							% [left_stream, left_roll_index, right_stream, right_roll_index, correlation, MAX_ABS_CORRELATION]
						)

	RNG.set_run_seed(RNG.DEFAULT_RUN_SEED)
	if _failures.is_empty():
		print(
			"[RNGAudit] passed; sample_count=%d streams=%d rolls_per_stream=%d max_abs_correlation=%.5f pair=%s"
			% [SAMPLE_COUNT, STREAM_IDS.size(), ROLLS_PER_STREAM, max_abs_correlation, max_pair]
		)
		get_tree().quit(0)
		return

	for failure: String in _failures:
		push_error("[RNGAudit] %s" % failure)
	print("[RNGAudit] failed; failures=%d" % _failures.size())
	get_tree().quit(1)


func _new_roll_buckets() -> Dictionary:
	var result: Dictionary = {}
	for stream_id: String in STREAM_IDS:
		var buckets: Array = []
		for _roll_index: int in range(ROLLS_PER_STREAM):
			buckets.append([] as Array[float])
		result[stream_id] = buckets
	return result


func _pearson_correlation(left_values: Array[float], right_values: Array[float]) -> float:
	if left_values.size() != right_values.size() or left_values.is_empty():
		return 0.0

	var count: int = left_values.size()
	var left_mean: float = _mean(left_values)
	var right_mean: float = _mean(right_values)
	var covariance: float = 0.0
	var left_variance: float = 0.0
	var right_variance: float = 0.0
	for index: int in range(count):
		var left_delta: float = left_values[index] - left_mean
		var right_delta: float = right_values[index] - right_mean
		covariance += left_delta * right_delta
		left_variance += left_delta * left_delta
		right_variance += right_delta * right_delta

	if left_variance <= 0.0 or right_variance <= 0.0:
		return 0.0
	return covariance / sqrt(left_variance * right_variance)


func _mean(values: Array[float]) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())
