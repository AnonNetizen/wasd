extends SmokeHarness


const RNG_STREAMS := preload("res://scripts/contracts/rng_streams.gd")
const TEST_SEED: int = 912_345


func test_same_seed_replays_spawn_sequence() -> void:
	assert_public_api(RNG, &"set_run_seed")
	assert_public_api(RNG, &"stream")
	RNG.set_run_seed(TEST_SEED)
	var first_sequence: Array[int] = _take_spawn_sequence()

	RNG.set_run_seed(TEST_SEED)
	var replayed_sequence: Array[int] = _take_spawn_sequence()

	assert_eq(RNG.run_seed(), TEST_SEED)
	assert_eq(replayed_sequence, first_sequence)


func test_snapshot_restore_replays_next_combat_value() -> void:
	assert_public_api(RNG, &"snapshot")
	assert_public_api(RNG, &"restore_snapshot")
	RNG.set_run_seed(TEST_SEED)
	var checkpoint: Dictionary = RNG.snapshot()
	var expected_next_value: int = RNG.stream(RNG_STREAMS.COMBAT).randi()
	RNG.stream(RNG_STREAMS.COMBAT).randi()

	RNG.restore_snapshot(checkpoint)

	assert_eq(RNG.stream(RNG_STREAMS.COMBAT).randi(), expected_next_value)


func _take_spawn_sequence() -> Array[int]:
	return [
		RNG.stream(RNG_STREAMS.SPAWN).randi(),
		RNG.stream(RNG_STREAMS.SPAWN).randi(),
		RNG.stream(RNG_STREAMS.SPAWN).randi(),
	]
