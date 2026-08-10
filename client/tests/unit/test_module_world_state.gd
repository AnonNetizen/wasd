extends SmokeHarness


const MODULE_WORLD_STATE_SCRIPT := preload(
	"res://scripts/gameplay/module_world_state.gd"
)
const MODULE_WORLD_MANAGER_SCRIPT := preload(
	"res://scripts/gameplay/module_world_manager.gd"
)
const WORLD_COLUMNS: int = 7
const WORLD_ROWS: int = 7
const MAX_PINNED_SLOTS: int = 3
const INVALID_COORD: Vector2i = Vector2i(-1, -1)


func test_enter_repeat_cross_slot_and_leave_preserve_visit_semantics() -> void:
	var state: MODULE_WORLD_STATE_SCRIPT = _new_state()
	var first: MODULE_WORLD_STATE_SCRIPT.VisitChange = state.enter_module(
		Vector2i(4, 1)
	)

	assert_true(first.entered())
	assert_true(first.revealed_now())
	assert_true(first.visited_now())
	assert_eq(state.current_module_coord(), Vector2i(4, 1))

	var repeated: MODULE_WORLD_STATE_SCRIPT.VisitChange = state.enter_module(
		Vector2i(4, 1)
	)
	assert_false(repeated.entered())
	assert_false(repeated.revealed_now())
	assert_false(repeated.visited_now())

	var crossed: MODULE_WORLD_STATE_SCRIPT.VisitChange = state.enter_module(
		Vector2i(0, 0)
	)
	assert_true(crossed.entered())
	assert_true(crossed.revealed_now())
	assert_true(crossed.visited_now())
	assert_eq(state.revealed_module_coords(), [
		Vector2i(0, 0),
		Vector2i(4, 1),
	])

	state.leave_world()
	assert_eq(state.current_module_coord(), INVALID_COORD)
	var returned: MODULE_WORLD_STATE_SCRIPT.VisitChange = state.enter_module(
		Vector2i(4, 1)
	)
	assert_true(returned.entered())
	assert_false(returned.revealed_now())
	assert_false(returned.visited_now())


func test_snapshot_fields_are_row_major_and_deep_copied() -> void:
	var state: MODULE_WORLD_STATE_SCRIPT = _new_state()
	state.enter_module(Vector2i(6, 6))
	state.enter_module(Vector2i(2, 0))
	assert_eq(
		state.mutate_pin(Vector2i(6, 6), true),
		MODULE_WORLD_STATE_SCRIPT.PinMutationResult.ACCEPTED_REFRESH
	)
	assert_eq(
		state.mutate_pin(Vector2i(0, 0), true),
		MODULE_WORLD_STATE_SCRIPT.PinMutationResult.ACCEPTED_REFRESH
	)
	state.set_slot_state(Vector2i(6, 6), {
		"order": 2,
		"future": {"nested": [1, 2, 3]},
	})
	state.set_slot_state(Vector2i(0, 0), {"order": 1})

	var fields: Dictionary = state.snapshot_fields()
	assert_eq(fields.get("current_module"), {"x": 2, "y": 0})
	assert_eq(fields.get("revealed"), [
		{"x": 2, "y": 0},
		{"x": 6, "y": 6},
	])
	assert_eq(fields.get("visited"), [
		{"x": 2, "y": 0},
		{"x": 6, "y": 6},
	])
	assert_eq(fields.get("pinned_slots"), [
		{"x": 0, "y": 0},
		{"x": 6, "y": 6},
	])
	var slot_states: Dictionary = fields.get("slot_states", {}) as Dictionary
	var state_keys: Array[String] = []
	for raw_key: Variant in slot_states.keys():
		state_keys.append(String(raw_key))
	assert_eq(state_keys, ["0,0", "6,6"])
	(slot_states["6,6"] as Dictionary)["future"] = {"nested": [99]}
	assert_eq(state.slot_state(Vector2i(6, 6)).get("future"), {
		"nested": [1, 2, 3],
	})


func test_pin_mutation_reports_refresh_and_limit_semantics() -> void:
	var state: MODULE_WORLD_STATE_SCRIPT = _new_state()
	assert_eq(
		state.mutate_pin(INVALID_COORD, true),
		MODULE_WORLD_STATE_SCRIPT.PinMutationResult.REJECTED
	)
	for module_coord: Vector2i in [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(2, 0),
	]:
		assert_eq(
			state.mutate_pin(module_coord, true),
			MODULE_WORLD_STATE_SCRIPT.PinMutationResult.ACCEPTED_REFRESH
		)
	assert_eq(
		state.mutate_pin(Vector2i(1, 0), true),
		MODULE_WORLD_STATE_SCRIPT.PinMutationResult.ACCEPTED_NO_REFRESH
	)
	assert_eq(
		state.mutate_pin(Vector2i(3, 0), true),
		MODULE_WORLD_STATE_SCRIPT.PinMutationResult.REJECTED
	)
	assert_eq(
		state.mutate_pin(Vector2i(6, 6), false),
		MODULE_WORLD_STATE_SCRIPT.PinMutationResult.ACCEPTED_REFRESH
	)
	assert_eq(
		state.mutate_pin(Vector2i(1, 0), false),
		MODULE_WORLD_STATE_SCRIPT.PinMutationResult.ACCEPTED_REFRESH
	)
	assert_eq(
		state.mutate_pin(Vector2i(3, 0), true),
		MODULE_WORLD_STATE_SCRIPT.PinMutationResult.ACCEPTED_REFRESH
	)
	assert_eq(state.pinned_module_coords(), [
		Vector2i(0, 0),
		Vector2i(2, 0),
		Vector2i(3, 0),
	])


func test_invalid_pin_restore_candidates_do_not_mutate_live_state() -> void:
	var state: MODULE_WORLD_STATE_SCRIPT = _new_state()
	state.enter_module(Vector2i(4, 4))
	state.mutate_pin(Vector2i(1, 1), true)
	state.set_slot_state(Vector2i(4, 4), {"stable": true})
	var before: Dictionary = state.snapshot_fields()
	var invalid_pin_sets: Array = [
		"not-an-array",
		[Vector2i(0, 0)],
		[{"x": 0, "y": 0}, {"x": 0, "y": 0}],
		[{"x": 7, "y": 0}],
		[
			{"x": 0, "y": 0},
			{"x": 1, "y": 0},
			{"x": 2, "y": 0},
			{"x": 3, "y": 0},
		],
	]
	for invalid_pins: Variant in invalid_pin_sets:
		var candidate: MODULE_WORLD_STATE_SCRIPT.RestoreCandidate = (
			state.prepare_restore({"pinned_slots": invalid_pins})
		)
		assert_false(candidate.is_valid())
		assert_eq(state.snapshot_fields(), before)


func test_restore_candidate_is_fail_soft_deep_copied_and_atomic() -> void:
	var state: MODULE_WORLD_STATE_SCRIPT = _new_state()
	state.enter_module(Vector2i(4, 4))
	state.mutate_pin(Vector2i(1, 1), true)
	state.set_slot_state(Vector2i(4, 4), {"live": true})
	var before: Dictionary = state.snapshot_fields()
	var raw_state: Dictionary = {
		"current_module": {"x": "6", "y": 6.0},
		"revealed": [
			{"x": 6, "y": 6},
			{"x": 0, "y": 0},
			{"x": 6, "y": 6},
			{"x": 9, "y": 0},
			"invalid",
		],
		"visited": "not-an-array",
		"pinned_slots": [
			{"x": 6, "y": 6},
			{"x": 0, "y": 0},
		],
		"slot_states": {
			"6,6": {
				"initialized": true,
				"future": {"nested": [1, 2, 3]},
			},
			"9,0": {"ignored": true},
			"1,1": ["ignored"],
		},
	}
	var candidate: MODULE_WORLD_STATE_SCRIPT.RestoreCandidate = (
		state.prepare_restore(raw_state)
	)

	assert_true(candidate.is_valid())
	assert_eq(state.snapshot_fields(), before)
	((raw_state["slot_states"] as Dictionary)["6,6"] as Dictionary)[
		"future"
	] = {"nested": [99]}
	(raw_state["pinned_slots"] as Array).clear()
	state.commit_restore(candidate)

	assert_eq(state.current_module_coord(), Vector2i(6, 6))
	assert_eq(state.revealed_module_coords(), [
		Vector2i(0, 0),
		Vector2i(6, 6),
	])
	assert_eq(state.visited_module_coords(), [])
	assert_eq(state.pinned_module_coords(), [
		Vector2i(0, 0),
		Vector2i(6, 6),
	])
	assert_eq(state.slot_state(Vector2i(6, 6)), {
		"initialized": true,
		"future": {"nested": [1, 2, 3]},
	})


func test_reset_clears_all_dynamic_state() -> void:
	var state: MODULE_WORLD_STATE_SCRIPT = _new_state()
	state.enter_module(Vector2i(2, 3))
	state.mutate_pin(Vector2i(4, 5), true)
	state.set_slot_state(Vector2i(2, 3), {"initialized": true})

	state.reset()

	assert_eq(state.current_module_coord(), INVALID_COORD)
	assert_eq(state.revealed_module_coords(), [])
	assert_eq(state.visited_module_coords(), [])
	assert_eq(state.pinned_module_coords(), [])
	assert_eq(state.slot_state(Vector2i(2, 3)), {})


func test_manager_snapshot_keeps_run_v19_module_key_order() -> void:
	var manager: MODULE_WORLD_MANAGER_SCRIPT = MODULE_WORLD_MANAGER_SCRIPT.new()
	var snapshot_state: Dictionary = manager.snapshot()
	manager.free()
	var keys: Array[String] = []
	for raw_key: Variant in snapshot_state.keys():
		keys.append(String(raw_key))

	assert_eq(keys, [
		"world_id",
		"run_seed",
		"assignment",
		"map_hash",
		"current_module",
		"revealed",
		"visited",
		"pinned_slots",
		"slot_states",
	])


func _new_state() -> MODULE_WORLD_STATE_SCRIPT:
	return MODULE_WORLD_STATE_SCRIPT.new(
		WORLD_COLUMNS,
		WORLD_ROWS,
		MAX_PINNED_SLOTS,
		INVALID_COORD
	)
