extends SmokeHarness


const ENEMY_DEFEAT_CAUSES := preload(
	"res://scripts/contracts/enemy_defeat_causes.gd"
)
const HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_damage_handler.gd"
)

const PUBLIC_RESULT_KEYS: Array[String] = [
	"applied",
	"amount",
	"defeated",
	"reason",
]

var _source_facts: HANDLER_SCRIPT.SourceFacts = null
var _requested_amount: float = 0.0
var _events: Array[String] = []
var _source_fact_reads: int = 0
var _amount_reads: int = 0


func before_each() -> void:
	_source_facts = HANDLER_SCRIPT.SourceFacts.new()
	_requested_amount = 0.0
	_reset_port_observations()


func test_armed_dead_and_feedback_guards_do_not_read_ports() -> void:
	var armed: HANDLER_SCRIPT.Result = _resolve(
		_request(true, true, 0.0, true)
	)
	assert_false(armed.applied)
	assert_false(armed.defeated)
	assert_eq(armed.reason, HANDLER_SCRIPT.REASON_ARMED)
	assert_almost_eq(armed.next_life, 0.0, 0.0)
	_assert_port_counts(0, 0, [])

	_reset_port_observations()
	var defeated: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 0.0, false)
	)
	assert_false(defeated.applied)
	assert_true(defeated.defeated)
	assert_eq(defeated.reason, HANDLER_SCRIPT.REASON_DEFEATED)
	_assert_port_counts(0, 0, [])

	_reset_port_observations()
	var feedback: HANDLER_SCRIPT.Result = _resolve(
		_request(false, true, 25.0, false)
	)
	assert_false(feedback.applied)
	assert_true(feedback.defeated)
	assert_eq(feedback.reason, HANDLER_SCRIPT.REASON_DEFEATED)
	assert_almost_eq(feedback.next_life, 25.0, 0.0)
	_assert_port_counts(0, 0, [])


func test_invalid_request_and_ports_fail_without_reads() -> void:
	var invalid_request: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.resolve(
		null,
		_ports()
	)
	assert_eq(
		invalid_request.reason,
		HANDLER_SCRIPT.REASON_INVALID_REQUEST
	)
	_assert_port_counts(0, 0, [])

	var invalid_ports: HANDLER_SCRIPT.Result = HANDLER_SCRIPT.resolve(
		_request(false, false, 25.0, false),
		HANDLER_SCRIPT.Ports.new()
	)
	assert_eq(invalid_ports.reason, HANDLER_SCRIPT.REASON_INVALID_PORTS)
	assert_almost_eq(invalid_ports.next_life, 25.0, 0.0)
	_assert_port_counts(0, 0, [])


func test_uncommitted_enemy_friendly_fire_does_not_read_amount() -> void:
	_set_source_facts(true, false, false)
	_requested_amount = 999.0
	var result: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 40.0, true)
	)
	assert_false(result.applied)
	assert_false(result.defeated)
	assert_almost_eq(result.next_life, 40.0, 0.0)
	assert_eq(
		result.reason,
		HANDLER_SCRIPT.REASON_FRIENDLY_FIRE_BLOCKED
	)
	assert_eq(result.follow_up, HANDLER_SCRIPT.FollowUp.NONE)
	_assert_port_counts(1, 0, ["source"])


func test_nonlethal_damage_reads_source_then_amount_and_requests_hit() -> void:
	_set_source_facts(false, true, false)
	_requested_amount = 12.5
	var result: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 40.0, false)
	)
	assert_true(result.applied)
	assert_false(result.defeated)
	assert_almost_eq(result.amount, 12.5, 0.0)
	assert_almost_eq(result.next_life, 27.5, 0.0)
	assert_eq(result.reason, HANDLER_SCRIPT.REASON_APPLIED)
	assert_eq(result.follow_up, HANDLER_SCRIPT.FollowUp.HIT_FLASH)
	assert_false(result.counts_as_kill)
	assert_false(result.drops_rewards)
	assert_eq(result.cause_id, "")
	_assert_port_counts(1, 1, ["source", "amount"])


func test_player_overkill_caps_applied_amount_and_requests_defeat() -> void:
	_set_source_facts(false, true, false)
	_requested_amount = 75.0
	var result: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 40.0, false)
	)
	assert_true(result.applied)
	assert_true(result.defeated)
	assert_almost_eq(result.amount, 40.0, 0.0)
	assert_almost_eq(result.next_life, 0.0, 0.0)
	assert_eq(result.reason, HANDLER_SCRIPT.REASON_APPLIED)
	assert_eq(
		result.follow_up,
		HANDLER_SCRIPT.FollowUp.FINISH_DEFEAT
	)
	assert_true(result.counts_as_kill)
	assert_true(result.drops_rewards)
	assert_eq(
		result.cause_id,
		ENEMY_DEFEAT_CAUSES.PLAYER_DAMAGE
	)
	_assert_port_counts(1, 1, ["source", "amount"])


func test_committed_enemy_explosion_uses_enemy_cause_or_chain() -> void:
	_set_source_facts(true, false, true)
	_requested_amount = 50.0
	var defeated: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 40.0, false)
	)
	assert_true(defeated.applied)
	assert_true(defeated.defeated)
	assert_eq(
		defeated.follow_up,
		HANDLER_SCRIPT.FollowUp.FINISH_DEFEAT
	)
	assert_true(defeated.counts_as_kill)
	assert_true(defeated.drops_rewards)
	assert_eq(
		defeated.cause_id,
		ENEMY_DEFEAT_CAUSES.ENEMY_EXPLOSION
	)
	_assert_port_counts(1, 1, ["source", "amount"])

	_reset_port_observations()
	var chained: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 40.0, true)
	)
	assert_true(chained.applied)
	assert_false(chained.defeated)
	assert_almost_eq(chained.amount, 40.0, 0.0)
	assert_almost_eq(chained.next_life, 0.0, 0.0)
	assert_eq(chained.reason, HANDLER_SCRIPT.REASON_CHAIN_ARMED)
	assert_eq(chained.follow_up, HANDLER_SCRIPT.FollowUp.CHAIN_ARM)
	assert_false(chained.counts_as_kill)
	assert_false(chained.drops_rewards)
	assert_eq(chained.cause_id, "")
	_assert_port_counts(1, 1, ["source", "amount"])


func test_other_lethal_source_does_not_count_or_drop_rewards() -> void:
	_set_source_facts(false, false, false)
	_requested_amount = 40.0
	var result: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 40.0, true)
	)
	assert_true(result.applied)
	assert_true(result.defeated)
	assert_eq(
		result.follow_up,
		HANDLER_SCRIPT.FollowUp.FINISH_DEFEAT
	)
	assert_false(result.counts_as_kill)
	assert_false(result.drops_rewards)
	assert_eq(result.cause_id, ENEMY_DEFEAT_CAUSES.OTHER_CAUSE)
	_assert_port_counts(1, 1, ["source", "amount"])


func test_zero_and_negative_direct_amount_keep_legacy_semantics() -> void:
	_set_source_facts(false, false, false)
	_requested_amount = 0.0
	var zero: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 10.0, false)
	)
	assert_true(zero.applied)
	assert_false(zero.defeated)
	assert_almost_eq(zero.amount, 0.0, 0.0)
	assert_almost_eq(zero.next_life, 10.0, 0.0)
	assert_eq(zero.follow_up, HANDLER_SCRIPT.FollowUp.HIT_FLASH)
	_assert_port_counts(1, 1, ["source", "amount"])

	_reset_port_observations()
	_requested_amount = -4.0
	var negative: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 10.0, false)
	)
	assert_true(negative.applied)
	assert_false(negative.defeated)
	assert_almost_eq(negative.amount, -4.0, 0.0)
	assert_almost_eq(negative.next_life, 14.0, 0.0)
	assert_eq(
		negative.follow_up,
		HANDLER_SCRIPT.FollowUp.HIT_FLASH
	)
	_assert_port_counts(1, 1, ["source", "amount"])


func test_public_result_order_and_repeated_calls_are_independent() -> void:
	_set_source_facts(false, true, false)
	_requested_amount = 5.0
	var first: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 20.0, false)
	)
	var first_public: Dictionary = first.public_result()
	assert_eq(first_public.keys(), PUBLIC_RESULT_KEYS)
	assert_eq(first_public, {
		"applied": true,
		"amount": 5.0,
		"defeated": false,
		"reason": HANDLER_SCRIPT.REASON_APPLIED,
	})
	first.reason = "mutated"
	first_public["reason"] = "mutated_public"

	_reset_port_observations()
	var second: HANDLER_SCRIPT.Result = _resolve(
		_request(false, false, 20.0, false)
	)
	assert_false(first == second)
	assert_eq(second.reason, HANDLER_SCRIPT.REASON_APPLIED)
	assert_eq(second.public_result().keys(), PUBLIC_RESULT_KEYS)
	assert_eq(
		String(second.public_result().get("reason", "")),
		HANDLER_SCRIPT.REASON_APPLIED
	)
	_assert_port_counts(1, 1, ["source", "amount"])


func _resolve(
	request: HANDLER_SCRIPT.Request
) -> HANDLER_SCRIPT.Result:
	return HANDLER_SCRIPT.resolve(request, _ports())


func _request(
	armed: bool,
	defeat_feedback_active: bool,
	current_life: float,
	can_chain_explode: bool
) -> HANDLER_SCRIPT.Request:
	var request: HANDLER_SCRIPT.Request = HANDLER_SCRIPT.Request.new()
	request.armed = armed
	request.defeat_feedback_active = defeat_feedback_active
	request.current_life = current_life
	request.can_chain_explode = can_chain_explode
	return request


func _ports() -> HANDLER_SCRIPT.Ports:
	return HANDLER_SCRIPT.Ports.new(
		Callable(self, "_read_source_facts"),
		Callable(self, "_read_amount")
	)


func _read_source_facts() -> HANDLER_SCRIPT.SourceFacts:
	_source_fact_reads += 1
	_events.append("source")
	return _source_facts


func _read_amount() -> float:
	_amount_reads += 1
	_events.append("amount")
	return _requested_amount


func _set_source_facts(
	source_is_enemy: bool,
	source_is_player: bool,
	source_is_committed_exploder: bool
) -> void:
	_source_facts.source_is_enemy = source_is_enemy
	_source_facts.source_is_player = source_is_player
	_source_facts.source_is_committed_exploder = (
		source_is_committed_exploder
	)


func _reset_port_observations() -> void:
	_events.clear()
	_source_fact_reads = 0
	_amount_reads = 0


func _assert_port_counts(
	source_fact_reads: int,
	amount_reads: int,
	events: Array[String]
) -> void:
	assert_eq(_source_fact_reads, source_fact_reads)
	assert_eq(_amount_reads, amount_reads)
	assert_eq(_events, events)
