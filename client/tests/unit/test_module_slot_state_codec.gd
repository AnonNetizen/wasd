extends SmokeHarness


const MODULE_SLOT_STATE_CODEC_SCRIPT := preload(
	"res://scripts/gameplay/module_slot_state_codec.gd"
)
const COLUMNS: int = 7
const ROWS: int = 7


func test_slot_state_preserves_unknown_payload_and_deep_copy_boundaries() -> void:
	var source: Dictionary = {
		"initialized": true,
		"enemy_encounter": {
			"state": "telegraphing",
			"future_rule": {"enabled": true},
		},
		"gear_mod_pickup_snapshots": [{"instance_id": 17}],
		"future_payload": {"nested": [1, 2, 3]},
	}
	var typed_state := MODULE_SLOT_STATE_CODEC_SCRIPT.SlotState.new(source)
	source["initialized"] = false
	(source["future_payload"] as Dictionary)["nested"] = [99]

	assert_true(typed_state.initialized())
	assert_eq(
		(typed_state.encounter().get("future_rule", {}) as Dictionary).get(
			"enabled",
			false
		),
		true
	)
	assert_eq(
		int(typed_state.snapshots("gear_mod_pickup_snapshots")[0].get(
			"instance_id",
			0
		)),
		17
	)
	var payload: Dictionary = typed_state.payload()
	assert_eq(payload.get("future_payload"), {"nested": [1, 2, 3]})
	(payload["future_payload"] as Dictionary)["nested"] = []
	assert_eq(
		typed_state.payload().get("future_payload"),
		{"nested": [1, 2, 3]}
	)


func test_slot_store_roundtrip_is_row_major_and_ignores_invalid_slots() -> void:
	var codec := MODULE_SLOT_STATE_CODEC_SCRIPT.new(COLUMNS, ROWS)
	var source: Dictionary = {
		"6,6": {"order": 3, "future": {"value": "last"}},
		"2,0": {"order": 2},
		"0,0": {"order": 1},
		"7,0": {"ignored": true},
		"not-a-slot": {"ignored": true},
		"1,1": ["not-a-dictionary"],
	}
	codec.restore_states(source)
	var ordered: Dictionary = codec.ordered_states()
	var keys: Array[String] = []
	for raw_key: Variant in ordered.keys():
		keys.append(String(raw_key))

	assert_eq(keys, ["0,0", "2,0", "6,6"])
	assert_eq(ordered.get("6,6"), {
		"order": 3,
		"future": {"value": "last"},
	})
	(source["6,6"] as Dictionary)["order"] = 99
	(ordered["6,6"] as Dictionary)["order"] = 100
	assert_eq(int(codec.state(Vector2i(6, 6)).get("order", 0)), 3)


func test_coordinate_collections_encode_in_row_major_order() -> void:
	var codec := MODULE_SLOT_STATE_CODEC_SCRIPT.new(COLUMNS, ROWS)
	var coords: Array[Vector2i] = [
		Vector2i(6, 6),
		Vector2i(4, 1),
		Vector2i(0, 0),
		Vector2i(4, 1),
		Vector2i(-1, 0),
	]

	assert_eq(codec.coords_to_wire(coords), [
		{"x": 0, "y": 0},
		{"x": 4, "y": 1},
		{"x": 6, "y": 6},
	])
	assert_eq(codec.coords_from_set({
		"6,6": true,
		"4,1": true,
		"0,0": true,
		"unknown": true,
	}), [
		Vector2i(0, 0),
		Vector2i(4, 1),
		Vector2i(6, 6),
	])


func test_coordinate_wire_keeps_legacy_coercion_and_set_behavior() -> void:
	var codec := MODULE_SLOT_STATE_CODEC_SCRIPT.new(COLUMNS, ROWS)
	var fallback := Vector2i(-1, -1)

	assert_eq(
		codec.coord_from_wire({"x": 2.0, "y": "3"}, fallback),
		Vector2i(2, 3)
	)
	assert_eq(codec.coord_from_wire([], fallback), fallback)
	assert_eq(codec.set_from_wire([
		{"x": 2, "y": 3},
		{"x": 2, "y": 3},
		{"x": 8, "y": 3},
		"invalid",
	]), {"2,3": true})


func test_pinned_wire_validation_rejects_duplicates_invalid_and_overflow() -> void:
	var codec := MODULE_SLOT_STATE_CODEC_SCRIPT.new(COLUMNS, ROWS)
	var valid: Dictionary = codec.validate_pinned_slots([
		{"x": 6, "y": 6},
		{"x": 0, "y": 0},
	], 3)

	assert_true(bool(valid.get("is_valid", false)))
	assert_eq(valid.get("pinned_slots"), {
		"6,6": true,
		"0,0": true,
	})
	assert_false(bool(codec.validate_pinned_slots([
		{"x": 1, "y": 1},
		{"x": 1, "y": 1},
	], 3).get("is_valid", true)))
	assert_false(bool(codec.validate_pinned_slots([
		{"x": -1, "y": 1},
	], 3).get("is_valid", true)))
	assert_false(bool(codec.validate_pinned_slots([
		{"x": 0, "y": 0},
		{"x": 1, "y": 0},
		{"x": 2, "y": 0},
		{"x": 3, "y": 0},
	], 3).get("is_valid", true)))


func test_set_and_get_state_do_not_alias_callers() -> void:
	var codec := MODULE_SLOT_STATE_CODEC_SCRIPT.new(COLUMNS, ROWS)
	var source: Dictionary = {"nested": {"value": 1}}
	codec.set_state(Vector2i(3, 4), source)
	source["nested"] = {"value": 99}
	var first_read: Dictionary = codec.state(Vector2i(3, 4))
	(first_read["nested"] as Dictionary)["value"] = 100

	assert_eq(codec.state(Vector2i(3, 4)), {"nested": {"value": 1}})
	assert_eq(codec.state(Vector2i(-1, 0)), {})
