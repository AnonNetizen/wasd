extends SmokeHarness


const MODIFIER_STACK_SCRIPT := preload("res://scripts/data/modifier_stack.gd")


func test_fixed_layers_apply_additions_then_multipliers() -> void:
	var stack := MODIFIER_STACK_SCRIPT.new()
	stack.configure({"damage": 10.0})
	stack.append_modifiers(MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT, [
		{"stat": "damage", "type": "add", "value": 2.0},
		{"stat": "damage", "type": "mult", "value": 2.0},
	])
	stack.replace_layer(MODIFIER_STACK_SCRIPT.LAYER_GEAR, [
		{"stat": "damage", "type": "mult", "value": 1.2},
		{"stat": "damage", "type": "mult", "value": 1.2},
	])

	assert_almost_eq(stack.value("damage"), 34.56, 0.000_001)


func test_replacing_gear_layer_is_idempotent() -> void:
	var stack := MODIFIER_STACK_SCRIPT.new()
	var gear_modifiers: Array[Dictionary] = [
		{"stat": "damage", "type": "mult", "value": 1.2},
		{"stat": "damage", "type": "mult", "value": 1.2},
	]
	stack.configure({"damage": 10.0})
	stack.replace_layer(MODIFIER_STACK_SCRIPT.LAYER_GEAR, gear_modifiers)
	var first_value: float = stack.value("damage")

	stack.replace_layer(MODIFIER_STACK_SCRIPT.LAYER_GEAR, gear_modifiers)

	assert_almost_eq(first_value, 14.4, 0.000_001)
	assert_almost_eq(stack.value("damage"), first_value, 0.000_001)


func test_appending_existing_source_accumulates_without_aliasing_input() -> void:
	var stack := MODIFIER_STACK_SCRIPT.new()
	var second_batch: Array[Dictionary] = [
		{"stat": "damage", "type": "mult", "value": 2.0},
	]
	stack.configure({"damage": 5.0})
	stack.append_modifiers(MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT, [
		{"stat": "damage", "type": "add", "value": 2.0},
	], "reward")
	stack.append_modifiers(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT,
		second_batch,
		"reward"
	)
	second_batch[0]["value"] = 10.0

	assert_almost_eq(stack.value("damage"), 14.0, 0.000_001)


func test_temporary_sources_refresh_stack_and_remove_independently() -> void:
	var stack := MODIFIER_STACK_SCRIPT.new()
	stack.configure({"damage": 10.0})
	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "boost", [
		{"stat": "damage", "type": "add", "value": 2.0},
	])
	assert_almost_eq(stack.value("damage"), 12.0, 0.000_001)

	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "boost", [
		{"stat": "damage", "type": "add", "value": 4.0},
	])
	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "aura", [
		{"stat": "damage", "type": "mult", "value": 2.0},
	])
	assert_almost_eq(stack.value("damage"), 28.0, 0.000_001)

	assert_true(stack.remove_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "boost"))
	assert_almost_eq(stack.value("damage"), 20.0, 0.000_001)
	assert_false(stack.remove_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "boost"))
	assert_true(stack.remove_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "aura"))
	assert_almost_eq(stack.value("damage"), 10.0, 0.000_001)


func test_absent_base_supports_addition_only_and_multiplier_only_stats() -> void:
	var stack := MODIFIER_STACK_SCRIPT.new()
	stack.configure({})
	stack.append_modifiers(MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT, [
		{"stat": "flat_bonus", "type": "add", "value": 5.0},
		{"stat": "scaling_only", "type": "mult", "value": 3.0},
	])

	assert_almost_eq(stack.value("flat_bonus"), 5.0, 0.000_001)
	assert_almost_eq(stack.value("scaling_only"), 0.0, 0.000_001)
	assert_eq(stack.materialized_values(), {
		"flat_bonus": 5.0,
	})


func test_inputs_and_materialized_outputs_are_deep_copied() -> void:
	var stack := MODIFIER_STACK_SCRIPT.new()
	var base_values: Dictionary = {"damage": 10.0}
	var modifiers: Array[Dictionary] = [{
		"stat": "damage",
		"type": "add",
		"value": 2.0,
		"metadata": {"labels": ["original"]},
	}]
	stack.configure(base_values)
	stack.replace_source(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT,
		"reward",
		modifiers
	)
	base_values["damage"] = 100.0
	modifiers[0]["value"] = 20.0
	(modifiers[0]["metadata"] as Dictionary)["labels"] = ["changed"]

	var totals: Dictionary = stack.layer_totals(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT
	)
	(totals[MODIFIER_STACK_SCRIPT.TOTAL_ADDITIONS] as Dictionary)["damage"] = 99.0
	var materialized: Dictionary = stack.materialized_values()
	materialized["damage"] = -1.0

	assert_almost_eq(stack.value("damage"), 12.0, 0.000_001)
	var current_totals: Dictionary = stack.layer_totals(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT
	)
	var current_additions: Dictionary = current_totals.get(
		MODIFIER_STACK_SCRIPT.TOTAL_ADDITIONS,
		{}
	) as Dictionary
	assert_almost_eq(float(current_additions.get("damage", 0.0)), 2.0, 0.000_001)


func test_replacing_existing_source_preserves_floating_traversal_order() -> void:
	var stack := MODIFIER_STACK_SCRIPT.new()
	stack.configure({"damage": 0.0})
	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "first", [
		{"stat": "damage", "type": "add", "value": 1.0e16},
	])
	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "second", [
		{"stat": "damage", "type": "add", "value": -1.0e16},
	])
	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "third", [
		{"stat": "damage", "type": "add", "value": 1.0},
	])
	assert_almost_eq(stack.value("damage"), 1.0, 0.0)

	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "second", [
		{"stat": "damage", "type": "add", "value": -1.0e16},
	])
	assert_almost_eq(stack.value("damage"), 1.0, 0.0)

	stack.remove_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "second")
	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "second", [
		{"stat": "damage", "type": "add", "value": -1.0e16},
	])
	assert_almost_eq(stack.value("damage"), 0.0, 0.0)


func test_layers_preserve_legacy_grouped_floating_order() -> void:
	var stack := MODIFIER_STACK_SCRIPT.new()
	stack.configure({"damage": 0.0})
	stack.append_modifiers(MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT, [
		{"stat": "damage", "type": "add", "value": 1.0e16},
	])
	stack.replace_layer(MODIFIER_STACK_SCRIPT.LAYER_GEAR, [
		{"stat": "damage", "type": "add", "value": -1.0e16},
		{"stat": "damage", "type": "add", "value": 1.0},
	])
	assert_almost_eq(stack.value("damage"), 0.0, 0.0)

	stack.replace_source(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY, "late", [
		{"stat": "damage", "type": "add", "value": 1.0},
	])
	assert_almost_eq(stack.value("damage"), 1.0, 0.0)


func test_layer_totals_restore_roundtrip_preserves_values() -> void:
	var source := MODIFIER_STACK_SCRIPT.new()
	source.configure({"damage": 10.0, "move_speed": 8.0})
	source.append_modifiers(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT,
		[
			{"stat": "damage", "type": "add", "value": 2.0},
			{"stat": "damage", "type": "mult", "value": 1.5},
		],
		"reward_a"
	)
	source.append_modifiers(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT,
		[
			{"stat": "damage", "type": "add", "value": 3.0},
			{"stat": "move_speed", "type": "mult", "value": 1.25},
		],
		"reward_b"
	)
	var totals: Dictionary = source.layer_totals(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT
	)
	var restored := MODIFIER_STACK_SCRIPT.new()
	restored.configure({"damage": 10.0, "move_speed": 8.0})
	restored.restore_layer_totals(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT,
		totals
	)

	assert_eq(
		restored.layer_totals(MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT),
		totals
	)
	assert_almost_eq(restored.value("damage"), source.value("damage"), 0.0)
	assert_almost_eq(
		restored.value("move_speed"),
		source.value("move_speed"),
		0.0
	)
