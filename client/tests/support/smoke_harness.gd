class_name SmokeHarness
extends GutTest
## Shared GUT base that restores deterministic global state after every test.


var _rng_snapshot: Dictionary = {}
var _game_clock_snapshot: Dictionary = {}


func before_each() -> void:
	_rng_snapshot = RNG.snapshot()
	_game_clock_snapshot = GameClock.snapshot()


func after_each() -> void:
	RNG.restore_snapshot(_rng_snapshot)
	GameClock.restore_snapshot(_game_clock_snapshot)


func assert_public_api(target: Object, method_name: StringName) -> void:
	if target == null:
		assert_not_null(target, "public API target must exist")
		return
	assert_true(
		target.has_method(method_name),
		"%s must expose public method %s" % [target.get_class(), method_name],
	)
