extends SmokeHarness


const ENEMY_STATUS_HOST_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_status_host_runtime.gd"
)
const ABILITY_TAGS := preload(
	"res://scripts/contracts/ability_tags.gd"
)
const STATUS_EFFECTS := preload(
	"res://scripts/contracts/status_effects.gd"
)


class FakeStatusEffectComponent:
	extends Node

	var active_ids: Array[String] = []
	var apply_inputs: Array = []
	var apply_result: Dictionary = {
		"applied": true,
		"reason": "applied",
	}
	var clear_calls: Array[bool] = []
	var configured_owners: Array[Node] = []
	var incoming_multiplier_value: float = 1.0
	var incoming_sources: Array[String] = []
	var restored_payloads: Array[Dictionary] = []
	var restore_grant_flags: Array[bool] = []
	var snapshot_payload: Dictionary = {"effects": []}
	var stack_count_value: int = 0
	var stat_multiplier_value: float = 1.0

	func configure_ability_tag_owner(owner: Node) -> void:
		configured_owners.append(owner)

	func clear(remove_granted_tags: bool = true) -> void:
		clear_calls.append(remove_granted_tags)

	func apply(effect: Variant) -> Dictionary:
		apply_inputs.append(effect)
		return apply_result.duplicate(true)

	func active_statuses() -> Array[String]:
		var result: Array[String] = []
		for status_id: String in active_ids:
			result.append(status_id)
		return result

	func snapshot() -> Dictionary:
		return snapshot_payload.duplicate(true)

	func stat_multiplier(_stat_id: String) -> float:
		return stat_multiplier_value

	func stack_count(_status_id: String) -> int:
		return stack_count_value

	func incoming_damage_multiplier(source_team: String) -> float:
		incoming_sources.append(source_team)
		return incoming_multiplier_value

	func restore_snapshot(
		data: Dictionary,
		grant_existing_tags: bool = true
	) -> void:
		restored_payloads.append(data.duplicate(true))
		restore_grant_flags.append(grant_existing_tags)


func test_unbound_status_facade_preserves_fallbacks() -> void:
	var runtime: ENEMY_STATUS_HOST_RUNTIME_SCRIPT = (
		ENEMY_STATUS_HOST_RUNTIME_SCRIPT.new()
	)
	var owner := Node.new()
	add_child_autofree(owner)

	assert_false(runtime.refresh(owner))
	assert_eq(runtime.apply_status_effect(null), {
		"applied": false,
		"reason": "status_component_unavailable",
	})
	assert_eq(runtime.active_statuses(), [])
	assert_eq(runtime.status_summary(), [])
	assert_almost_eq(runtime.status_stat_multiplier("stat"), 1.0, 0.0)
	assert_eq(runtime.status_stack_count("status"), 0)
	assert_false(runtime.can_query_incoming_damage_multiplier())
	assert_almost_eq(runtime.incoming_damage_multiplier("team"), 1.0, 0.0)
	assert_eq(runtime.status_effect_snapshot(), {})


func test_owned_tag_counts_validate_sort_decrement_and_deep_copy() -> void:
	var runtime: ENEMY_STATUS_HOST_RUNTIME_SCRIPT = (
		ENEMY_STATUS_HOST_RUNTIME_SCRIPT.new()
	)

	assert_false(runtime.add_owned_tag(""))
	assert_false(runtime.add_owned_tag("ability_tag_unknown"))
	assert_true(runtime.add_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_true(runtime.add_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_PRIMARY
	))
	assert_true(runtime.add_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_eq(runtime.owned_tags(), [
		ABILITY_TAGS.ABILITY_TAG_PRIMARY,
		ABILITY_TAGS.ABILITY_TAG_SILENCED,
	])
	assert_true(runtime.has_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))

	var counts: Dictionary = runtime.owned_tag_counts_snapshot()
	counts[ABILITY_TAGS.ABILITY_TAG_SILENCED] = 99
	assert_eq(
		int(runtime.owned_tag_counts_snapshot().get(
			ABILITY_TAGS.ABILITY_TAG_SILENCED,
			0
		)),
		2
	)
	assert_true(runtime.remove_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_true(runtime.has_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_true(runtime.remove_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_false(runtime.has_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	assert_false(runtime.remove_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))


func test_bind_refresh_rebind_and_status_forwards_use_current_component() -> void:
	var runtime: ENEMY_STATUS_HOST_RUNTIME_SCRIPT = (
		ENEMY_STATUS_HOST_RUNTIME_SCRIPT.new()
	)
	var first := FakeStatusEffectComponent.new()
	var second := FakeStatusEffectComponent.new()
	var first_owner := Node.new()
	var second_owner := Node.new()
	add_child_autofree(first)
	add_child_autofree(second)
	add_child_autofree(first_owner)
	add_child_autofree(second_owner)
	first.active_ids = [STATUS_EFFECTS.SILENCE]
	first.stat_multiplier_value = 0.65
	first.stack_count_value = 3
	first.incoming_multiplier_value = 1.4

	assert_true(runtime.bind(first, first_owner))
	assert_eq(first.configured_owners, [first_owner])
	var status_token := RefCounted.new()
	assert_true(bool(
		runtime.apply_status_effect(status_token).get("applied", false)
	))
	assert_same(first.apply_inputs[0], status_token)
	assert_eq(runtime.active_statuses(), [STATUS_EFFECTS.SILENCE])
	assert_almost_eq(runtime.status_stat_multiplier("move_speed"), 0.65, 0.0)
	assert_eq(runtime.status_stack_count(STATUS_EFFECTS.SILENCE), 3)
	assert_true(runtime.can_query_incoming_damage_multiplier())
	assert_almost_eq(
		runtime.incoming_damage_multiplier("team_player"),
		1.4,
		0.0
	)
	assert_eq(first.incoming_sources, ["team_player"])

	assert_true(runtime.refresh(second_owner))
	assert_eq(first.configured_owners, [first_owner, second_owner])
	second.active_ids = [STATUS_EFFECTS.BURN]
	assert_true(runtime.bind(second, second_owner))
	assert_eq(second.configured_owners, [second_owner])
	assert_eq(runtime.active_statuses(), [STATUS_EFFECTS.BURN])
	assert_eq(first.apply_inputs.size(), 1)


func test_status_summary_keeps_effect_source_order_and_normalizes_values() -> void:
	var runtime: ENEMY_STATUS_HOST_RUNTIME_SCRIPT = (
		ENEMY_STATUS_HOST_RUNTIME_SCRIPT.new()
	)
	var component := FakeStatusEffectComponent.new()
	var owner := Node.new()
	add_child_autofree(component)
	add_child_autofree(owner)
	component.snapshot_payload = {
		"effects": [
			"bad",
			{},
			{
				"status": STATUS_EFFECTS.SLOW,
				"stack_count": 0,
				"remaining": -4.0,
			},
			{
				"status": STATUS_EFFECTS.BURN,
				"stack_count": 3,
				"remaining": 2.5,
			},
		],
	}
	assert_true(runtime.bind(component, owner))

	assert_eq(runtime.status_summary(), [
		{
			"id": STATUS_EFFECTS.SLOW,
			"name_key": "status_slow_name",
			"stacks": 1,
			"remaining": 0.0,
		},
		{
			"id": STATUS_EFFECTS.BURN,
			"name_key": "status_burn_name",
			"stacks": 3,
			"remaining": 2.5,
		},
	])


func test_current_tag_snapshot_restores_positive_registered_counts() -> void:
	var runtime: ENEMY_STATUS_HOST_RUNTIME_SCRIPT = (
		ENEMY_STATUS_HOST_RUNTIME_SCRIPT.new()
	)
	var component := FakeStatusEffectComponent.new()
	var owner := Node.new()
	add_child_autofree(component)
	add_child_autofree(owner)
	assert_true(runtime.bind(component, owner))
	var status_payload: Dictionary = {"effects": []}

	runtime.restore_from_actor_snapshot({
		"owned_tag_counts": {
			ABILITY_TAGS.ABILITY_TAG_SILENCED: 2,
			ABILITY_TAGS.ABILITY_TAG_PRIMARY: 0,
			"ability_tag_unknown": 8,
		},
		"status_effects": status_payload,
	})
	assert_eq(runtime.owned_tag_counts_snapshot(), {
		ABILITY_TAGS.ABILITY_TAG_SILENCED: 2,
	})
	assert_eq(component.restored_payloads, [status_payload])
	assert_eq(component.restore_grant_flags, [false])


func test_legacy_missing_and_malformed_tag_snapshots_keep_grant_flag() -> void:
	var runtime: ENEMY_STATUS_HOST_RUNTIME_SCRIPT = (
		ENEMY_STATUS_HOST_RUNTIME_SCRIPT.new()
	)
	var component := FakeStatusEffectComponent.new()
	var owner := Node.new()
	add_child_autofree(component)
	add_child_autofree(owner)
	assert_true(runtime.bind(component, owner))
	var status_payload: Dictionary = {"effects": []}

	runtime.restore_from_actor_snapshot({
		"owned_tags": [
			ABILITY_TAGS.ABILITY_TAG_SILENCED,
			ABILITY_TAGS.ABILITY_TAG_SILENCED,
			"ability_tag_unknown",
		],
		"status_effects": status_payload,
	})
	assert_eq(runtime.owned_tag_counts_snapshot(), {
		ABILITY_TAGS.ABILITY_TAG_SILENCED: 2,
	})
	assert_false(component.restore_grant_flags.back())

	runtime.restore_from_actor_snapshot({
		"status_effects": status_payload,
	})
	assert_eq(runtime.owned_tags(), [])
	assert_false(component.restore_grant_flags.back())

	runtime.restore_from_actor_snapshot({
		"owned_tag_counts": "bad",
		"owned_tags": "bad",
		"status_effects": status_payload,
	})
	assert_eq(runtime.owned_tags(), [])
	assert_true(component.restore_grant_flags.back())
	var restore_count: int = component.restored_payloads.size()
	runtime.restore_from_actor_snapshot({
		"owned_tags": "bad",
		"status_effects": [],
	})
	assert_eq(component.restored_payloads.size(), restore_count)


func test_restore_clear_and_reuse_clear_keep_historical_tag_order() -> void:
	var runtime: ENEMY_STATUS_HOST_RUNTIME_SCRIPT = (
		ENEMY_STATUS_HOST_RUNTIME_SCRIPT.new()
	)
	var component := FakeStatusEffectComponent.new()
	var owner := Node.new()
	add_child_autofree(component)
	add_child_autofree(owner)
	assert_true(runtime.bind(component, owner))
	assert_true(runtime.add_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))

	runtime.clear_effects_before_restore()
	assert_eq(component.clear_calls, [false])
	assert_true(runtime.has_owned_tag(
		ABILITY_TAGS.ABILITY_TAG_SILENCED
	))
	runtime.clear_for_reuse()
	assert_eq(component.clear_calls, [false, false])
	assert_eq(runtime.owned_tags(), [])

	var unbound_runtime: ENEMY_STATUS_HOST_RUNTIME_SCRIPT = (
		ENEMY_STATUS_HOST_RUNTIME_SCRIPT.new()
	)
	unbound_runtime.clear_for_reuse()
	assert_eq(unbound_runtime.owned_tags(), [])
