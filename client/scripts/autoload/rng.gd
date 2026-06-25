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

	func snapshot() -> Dictionary:
		return {
			"id": id,
			"seed": String.num_int64(int(_generator.seed)),
			"state": String.num_int64(int(_generator.state)),
		}

	func restore_snapshot(snapshot_data: Dictionary) -> void:
		_generator.seed = String(snapshot_data.get("seed", String.num_int64(int(_generator.seed)))).to_int()
		_generator.state = String(snapshot_data.get("state", String.num_int64(int(_generator.state)))).to_int()

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
const STREAM_SEED_DOMAIN: String = "wasd:rng-stream-seed:v2"
const STREAM_SEED_MODULUS: int = 2_147_483_647

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


func set_random_run_seed() -> int:
	var seed_source: RandomNumberGenerator = RandomNumberGenerator.new()
	seed_source.randomize()
	var seed_value: int = int(seed_source.randi() % (STREAM_SEED_MODULUS - 1)) + DEFAULT_RUN_SEED
	if seed_value == _run_seed:
		seed_value += 1
		if seed_value >= STREAM_SEED_MODULUS:
			seed_value = DEFAULT_RUN_SEED
	set_run_seed(seed_value)
	return _run_seed


func run_seed() -> int:
	return _run_seed


func snapshot() -> Dictionary:
	var stream_snapshots: Dictionary = {}
	for stream_id: String in _streams.keys():
		var stream_data: Stream = _streams[stream_id] as Stream
		stream_snapshots[stream_id] = stream_data.snapshot()
	return {
		"run_seed": _run_seed,
		"streams": stream_snapshots,
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	set_run_seed(int(snapshot_data.get("run_seed", DEFAULT_RUN_SEED)))
	var stream_snapshots: Variant = snapshot_data.get("streams", {})
	if not stream_snapshots is Dictionary:
		return
	for stream_id: String in (stream_snapshots as Dictionary).keys():
		if not _streams.has(stream_id):
			continue
		var stream_data: Stream = _streams[stream_id] as Stream
		var raw_stream_snapshot: Variant = (stream_snapshots as Dictionary).get(stream_id, {})
		if raw_stream_snapshot is Dictionary:
			stream_data.restore_snapshot(raw_stream_snapshot as Dictionary)


func stream(stream_id: String) -> Stream:
	if not _streams.has(stream_id):
		push_error("[RNG] unknown RNG stream: %s" % stream_id)
		return spawn
	return _streams[stream_id] as Stream


func _derive_stream_seed(seed_value: int, stream_id: String) -> int:
	var seed_text: String = "%s:%d:%s" % [STREAM_SEED_DOMAIN, seed_value, stream_id]
	var digest_text: String = seed_text.sha256_text()
	var derived_seed: int = 0
	for index: int in range(digest_text.length()):
		derived_seed = (derived_seed * 16 + _hex_value(digest_text.unicode_at(index))) % STREAM_SEED_MODULUS
	return maxi(derived_seed, 1)


func _hex_value(codepoint: int) -> int:
	if codepoint >= 48 and codepoint <= 57:
		return codepoint - 48
	if codepoint >= 97 and codepoint <= 102:
		return codepoint - 87
	if codepoint >= 65 and codepoint <= 70:
		return codepoint - 55
	return 0
