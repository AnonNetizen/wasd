# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyActionRuntime
extends RefCounted


const ACTION_STATE_ARMED_WINDUP: String = "armed_windup"
const ACTION_STATE_CHARGE_RELEASE: String = "charge_release"
const ACTION_STATE_CHARGE_WINDUP: String = "charge_windup"
const ACTION_STATE_MELEE_WINDUP: String = "melee_windup"
const ACTION_STATE_RANGED_BURST: String = "ranged_burst"
const ACTION_STATE_RANGED_WINDUP: String = "ranged_windup"


class SnapshotValues:
	extends RefCounted

	var current_action: String = ""
	var action_state: String = ""
	var action_timer: float = 0.0
	var attack_cooldown_remaining: float = 0.0
	var attack_hit_committed: bool = false
	var collateral_player_hit_committed: bool = false
	var burst_shots_remaining: int = 0
	var locked_direction: Vector2 = Vector2.ZERO
	var armed: bool = false
	var armed_from_chain: bool = false
	var has_exploded: bool = false


class RestoreInput:
	extends RefCounted

	var current_action: String = ""
	var action_state: String = ""
	var action_timer: float = 0.0
	var attack_cooldown_remaining: float = 0.0
	var attack_hit_committed: bool = false
	var collateral_player_hit_committed: bool = false
	var burst_shots_remaining: int = 0
	var locked_direction: Vector2 = Vector2.ZERO
	var armed: bool = false
	var armed_from_chain: bool = false
	var has_exploded: bool = false
	var has_saved_burst_state: bool = false
	var has_valid_saved_action_timer: bool = true


class RestoreRules:
	extends RefCounted

	var valid_action_ids: Array[String] = []
	var explode_action_id: String = ""
	var ranged_action_id: String = ""
	var ranged_burst_count: int = 0
	var ranged_windup: float = 0.0
	var ranged_shot_interval: float = 0.0
	var ranged_cooldown: float = 0.0


class RestoreResult:
	extends RefCounted

	var restored_ranged_state: bool = false
	var resume_ranged_windup: bool = false


var _action_state: String = ""
var _action_timer: float = 0.0
var _armed: bool = false
var _armed_from_chain: bool = false
var _attack_cooldown_remaining: float = 0.0
var _attack_hit_committed: bool = false
var _burst_shots_remaining: int = 0
var _collateral_player_hit_committed: bool = false
var _current_action: String = ""
var _has_exploded: bool = false
var _locked_direction: Vector2 = Vector2.ZERO


func configure(initial_attack_cooldown: float) -> void:
	reset()
	_attack_cooldown_remaining = maxf(initial_attack_cooldown, 0.0)


func reset() -> void:
	_action_state = ""
	_action_timer = 0.0
	_armed = false
	_armed_from_chain = false
	_attack_cooldown_remaining = 0.0
	_attack_hit_committed = false
	_burst_shots_remaining = 0
	_collateral_player_hit_committed = false
	_current_action = ""
	_has_exploded = false
	_locked_direction = Vector2.ZERO


func current_action() -> String:
	return _current_action


func set_current_action(action_id: String) -> void:
	_current_action = action_id


func action_state() -> String:
	return _action_state


func set_action_state(state: String) -> void:
	_action_state = state


func action_timer() -> float:
	return _action_timer


func set_action_timer(remaining: float) -> void:
	_action_timer = maxf(remaining, 0.0)


func advance_action_timer(delta: float) -> void:
	_action_timer = maxf(_action_timer - maxf(delta, 0.0), 0.0)


func attack_cooldown_remaining() -> float:
	return _attack_cooldown_remaining


func set_attack_cooldown_remaining(remaining: float) -> void:
	_attack_cooldown_remaining = maxf(remaining, 0.0)


func advance_attack_cooldown(delta: float) -> void:
	_attack_cooldown_remaining = maxf(
		_attack_cooldown_remaining - maxf(delta, 0.0),
		0.0
	)


func attack_hit_committed() -> bool:
	return _attack_hit_committed


func set_attack_hit_committed(committed: bool) -> void:
	_attack_hit_committed = committed


func collateral_player_hit_committed() -> bool:
	return _collateral_player_hit_committed


func set_collateral_player_hit_committed(committed: bool) -> void:
	_collateral_player_hit_committed = committed


func burst_shots_remaining() -> int:
	return _burst_shots_remaining


func set_burst_shots_remaining(remaining: int) -> void:
	_burst_shots_remaining = maxi(remaining, 0)


func locked_direction() -> Vector2:
	return _locked_direction


func set_locked_direction(direction: Vector2) -> void:
	_locked_direction = direction


func is_armed() -> bool:
	return _armed


func set_armed(armed: bool) -> void:
	_armed = armed


func armed_from_chain() -> bool:
	return _armed_from_chain


func set_armed_from_chain(from_chain: bool) -> void:
	_armed_from_chain = from_chain


func has_exploded() -> bool:
	return _has_exploded


func set_has_exploded(exploded: bool) -> void:
	_has_exploded = exploded


func is_attack_state_active() -> bool:
	return (
		_action_state == ACTION_STATE_MELEE_WINDUP
		or _action_state == ACTION_STATE_CHARGE_WINDUP
		or _action_state == ACTION_STATE_CHARGE_RELEASE
		or _action_state == ACTION_STATE_RANGED_WINDUP
		or _action_state == ACTION_STATE_RANGED_BURST
	)


func snapshot_values() -> SnapshotValues:
	var values: SnapshotValues = SnapshotValues.new()
	values.current_action = _current_action
	values.action_state = _action_state
	values.action_timer = _action_timer
	values.attack_cooldown_remaining = _attack_cooldown_remaining
	values.attack_hit_committed = _attack_hit_committed
	values.collateral_player_hit_committed = (
		_collateral_player_hit_committed
	)
	values.burst_shots_remaining = _burst_shots_remaining
	values.locked_direction = _locked_direction
	values.armed = _armed
	values.armed_from_chain = _armed_from_chain
	values.has_exploded = _has_exploded
	return values


func restore(input: RestoreInput, rules: RestoreRules) -> RestoreResult:
	var result: RestoreResult = RestoreResult.new()
	_current_action = (
		input.current_action
		if rules.valid_action_ids.has(input.current_action)
		else ""
	)
	if _current_action.is_empty():
		_action_state = ""
		_action_timer = 0.0
	else:
		_action_state = input.action_state
		_action_timer = maxf(input.action_timer, 0.0)
	_attack_cooldown_remaining = maxf(
		input.attack_cooldown_remaining,
		0.0
	)
	_attack_hit_committed = input.attack_hit_committed
	_collateral_player_hit_committed = (
		input.collateral_player_hit_committed
	)
	_burst_shots_remaining = maxi(input.burst_shots_remaining, 0)
	_locked_direction = input.locked_direction
	_armed = input.armed
	_armed_from_chain = input.armed_from_chain
	_has_exploded = input.has_exploded

	_restore_ranged_burst_state(input, rules, result)
	return result


func force_armed_restore(explode_action_id: String) -> void:
	_current_action = explode_action_id
	_action_state = ACTION_STATE_ARMED_WINDUP


func _restore_ranged_burst_state(
	input: RestoreInput,
	rules: RestoreRules,
	result: RestoreResult
) -> void:
	var is_ranged_action: bool = _current_action == rules.ranged_action_id
	var is_ranged_phase: bool = (
		_action_state == ACTION_STATE_RANGED_WINDUP
		or _action_state == ACTION_STATE_RANGED_BURST
	)
	if not input.has_saved_burst_state:
		if is_ranged_action or is_ranged_phase:
			_clear_restored_ranged_burst(false, rules.ranged_cooldown)
		return
	if not is_ranged_phase and _burst_shots_remaining <= 0:
		return

	var configured_burst_count: int = (
		rules.ranged_burst_count if is_ranged_action else 0
	)
	var valid_state: bool = (
		is_ranged_action
		and is_ranged_phase
		and configured_burst_count > 0
		and input.has_valid_saved_action_timer
		and _burst_shots_remaining > 0
		and _burst_shots_remaining <= configured_burst_count
		and _locked_direction.length_squared() > 0.0
	)
	if _action_state == ACTION_STATE_RANGED_WINDUP:
		valid_state = (
			valid_state
			and _burst_shots_remaining == configured_burst_count
			and _action_timer <= rules.ranged_windup
		)
	elif _action_state == ACTION_STATE_RANGED_BURST:
		valid_state = (
			valid_state
			and _burst_shots_remaining < configured_burst_count
			and _action_timer <= rules.ranged_shot_interval
		)
	if not valid_state:
		_clear_restored_ranged_burst(true, rules.ranged_cooldown)
		return

	_locked_direction = _locked_direction.normalized()
	result.restored_ranged_state = true
	result.resume_ranged_windup = (
		_action_state == ACTION_STATE_RANGED_WINDUP
	)


func _clear_restored_ranged_burst(
	apply_cooldown: bool,
	ranged_cooldown: float
) -> void:
	if apply_cooldown:
		_attack_cooldown_remaining = maxf(
			_attack_cooldown_remaining,
			maxf(ranged_cooldown, 0.0)
		)
	_current_action = ""
	_action_state = ""
	_action_timer = 0.0
	_burst_shots_remaining = 0
	_locked_direction = Vector2.ZERO
