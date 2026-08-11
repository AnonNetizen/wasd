# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyDamageHandler
extends RefCounted
## Stateless enemy damage decisions over lazy source and amount ports.


const ENEMY_DEFEAT_CAUSES := preload(
	"res://scripts/contracts/enemy_defeat_causes.gd"
)

const REASON_APPLIED: String = "applied"
const REASON_ARMED: String = "armed"
const REASON_CHAIN_ARMED: String = "chain_armed"
const REASON_DEFEATED: String = "defeated"
const REASON_FRIENDLY_FIRE_BLOCKED: String = "friendly_fire_blocked"
const REASON_INVALID_PORTS: String = "invalid_ports"
const REASON_INVALID_REQUEST: String = "invalid_request"


enum FollowUp {
	NONE,
	HIT_FLASH,
	FINISH_DEFEAT,
	CHAIN_ARM,
}


class Request:
	extends RefCounted

	var armed: bool = false
	var defeat_feedback_active: bool = false
	var current_life: float = 0.0
	var can_chain_explode: bool = false


class SourceFacts:
	extends RefCounted

	var source_is_enemy: bool = false
	var source_is_player: bool = false
	var source_is_committed_exploder: bool = false


class Ports:
	extends RefCounted

	var _source_facts_handler: Callable = Callable()
	var _amount_handler: Callable = Callable()


	func _init(
		source_facts_handler: Callable = Callable(),
		amount_handler: Callable = Callable()
	) -> void:
		_source_facts_handler = source_facts_handler
		_amount_handler = amount_handler


	func is_valid() -> bool:
		return (
			_source_facts_handler.is_valid()
			and _amount_handler.is_valid()
		)


	func source_facts() -> SourceFacts:
		var raw_facts: Variant = _source_facts_handler.call()
		if raw_facts is SourceFacts:
			return raw_facts as SourceFacts
		return SourceFacts.new()


	func amount() -> float:
		return float(_amount_handler.call())


class Result:
	extends RefCounted

	var next_life: float = 0.0
	var applied: bool = false
	var amount: float = 0.0
	var defeated: bool = false
	var reason: String = ""
	var follow_up: FollowUp = FollowUp.NONE
	var counts_as_kill: bool = false
	var drops_rewards: bool = false
	var cause_id: String = ""


	func public_result() -> Dictionary:
		return {
			"applied": applied,
			"amount": amount,
			"defeated": defeated,
			"reason": reason,
		}


static func resolve(
	request: Request,
	ports: Ports
) -> Result:
	var result: Result = Result.new()
	if request == null:
		result.reason = REASON_INVALID_REQUEST
		return result
	result.next_life = request.current_life

	if request.armed:
		result.reason = REASON_ARMED
		return result
	if request.current_life <= 0.0 or request.defeat_feedback_active:
		result.defeated = true
		result.reason = REASON_DEFEATED
		return result
	if ports == null or not ports.is_valid():
		result.reason = REASON_INVALID_PORTS
		return result

	var source_facts: SourceFacts = ports.source_facts()
	var enemy_explosion: bool = (
		source_facts.source_is_enemy
		and source_facts.source_is_committed_exploder
	)
	if source_facts.source_is_enemy and not enemy_explosion:
		result.reason = REASON_FRIENDLY_FIRE_BLOCKED
		return result

	var requested_amount: float = ports.amount()
	result.applied = true
	result.amount = minf(requested_amount, request.current_life)
	result.next_life = maxf(
		request.current_life - requested_amount,
		0.0
	)
	if result.next_life <= 0.0:
		if enemy_explosion and request.can_chain_explode:
			result.follow_up = FollowUp.CHAIN_ARM
			result.reason = REASON_CHAIN_ARMED
			return result
		result.defeated = true
		result.follow_up = FollowUp.FINISH_DEFEAT
		result.counts_as_kill = (
			source_facts.source_is_player
			or enemy_explosion
		)
		result.drops_rewards = result.counts_as_kill
		result.cause_id = (
			ENEMY_DEFEAT_CAUSES.ENEMY_EXPLOSION
			if enemy_explosion
			else (
				ENEMY_DEFEAT_CAUSES.PLAYER_DAMAGE
				if source_facts.source_is_player
				else ENEMY_DEFEAT_CAUSES.OTHER_CAUSE
			)
		)
	else:
		result.follow_up = FollowUp.HIT_FLASH
	result.reason = REASON_APPLIED
	return result
