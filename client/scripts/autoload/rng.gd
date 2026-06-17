# Doc: docs/代码/rng.md
# Authority: docs/游戏设计文档.md §9.18.1, docs/词表与契约.md §11
class_name RngAutoload
extends Node


class Stream:
	extends RefCounted

	var id: String = ""
	var _generator: RandomNumberGenerator = RandomNumberGenerator.new()

	func configure(stream_id: String, seed_value: int) -> void:
		id = stream_id
		_generator.seed = seed_value

	func randi() -> int:
		return _generator.randi()

	func randf() -> float:
		return _generator.randf()

	func randf_range(from: float, to: float) -> float:
		return _generator.randf_range(from, to)

	func pick(values: Array) -> Variant:
		if values.is_empty():
			return null
		return values[randi() % values.size()]

	func weighted_pick(values: Array, weights: Array, luck_bias: float = 0.0) -> Variant:
		if values.is_empty() or values.size() != weights.size():
			return null

		var total_weight: float = 0.0
		for raw_weight: Variant in weights:
			total_weight += maxf(float(raw_weight) + luck_bias, 0.0)

		if total_weight <= 0.0:
			return values[0]

		var roll: float = randf_range(0.0, total_weight)
		var cursor: float = 0.0
		for index: int in range(values.size()):
			cursor += maxf(float(weights[index]) + luck_bias, 0.0)
			if roll <= cursor:
				return values[index]

		return values[values.size() - 1]


const DEFAULT_RUN_SEED: int = 1

var spawn: Stream = Stream.new()
var drop: Stream = Stream.new()
var combat: Stream = Stream.new()
var ui_choice: Stream = Stream.new()
var world: Stream = Stream.new()
var meta: Stream = Stream.new()

var _run_seed: int = DEFAULT_RUN_SEED
var _streams: Dictionary = {}


func _ready() -> void:
	_streams = {
		"spawn": spawn,
		"drop": drop,
		"combat": combat,
		"ui_choice": ui_choice,
		"world": world,
		"meta": meta,
	}
	set_run_seed(DEFAULT_RUN_SEED)


func set_run_seed(seed_value: int) -> void:
	_run_seed = seed_value
	for stream_id: String in _streams.keys():
		var stream: Stream = _streams[stream_id] as Stream
		stream.configure(stream_id, _derive_stream_seed(seed_value, stream_id))


func run_seed() -> int:
	return _run_seed


func stream(stream_id: String) -> Stream:
	if not _streams.has(stream_id):
		push_error("[RNG] unknown RNG stream: %s" % stream_id)
		return spawn
	return _streams[stream_id] as Stream


func _derive_stream_seed(seed_value: int, stream_id: String) -> int:
	return abs(hash("%d:%s" % [seed_value, stream_id]))
