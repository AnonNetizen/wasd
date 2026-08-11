# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyChargeAttackHandler
extends RefCounted
## Stateless charge windup, sweep, and finish transitions over typed Actor ports.


const ENEMY_ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)

const REASON_FOCUS_UNAVAILABLE: String = "focus_unavailable"
const REASON_INVALID_CONFIG: String = "invalid_config"
const REASON_INVALID_DIRECTION: String = "invalid_direction"
const REASON_INVALID_PORTS: String = "invalid_ports"
const REASON_INVALID_REQUEST: String = "invalid_request"
const REASON_INVALID_RUNTIME: String = "invalid_runtime"


class Config:
	extends RefCounted

	var windup: float = 0.0
	var cooldown: float = 0.0
	var release_duration: float = 0.0
	var speed_multiplier: float = 0.0
	var base_damage: float = 0.0
	var element_id: String = ""
	var stop_on_hit: bool = false
	var knockback_distance: float = 0.0
	var knockback_duration: float = 0.0


class StartRequest:
	extends RefCounted

	var focus_target_available: bool = false
	var target_direction: Vector2 = Vector2.ZERO


class StepRequest:
	extends RefCounted

	var delta: float = 0.0
	var move_speed: float = 0.0
	var move_speed_multiplier: float = 0.0


class MovementResult:
	extends RefCounted

	var previous_position: Vector2 = Vector2.ZERO
	var current_position: Vector2 = Vector2.ZERO
	var collided: bool = false


class DamageResult:
	extends RefCounted

	var applied: bool = false
	var amount: float = 0.0
	var defeated: bool = false
	var reason: String = ""


class TargetPort:
	extends RefCounted

	var uses_collateral_flag: bool = false
	var is_player_target: bool = false
	var _sweep_hit_handler: Callable = Callable()
	var _damage_handler: Callable = Callable()
	var _knockback_capability_handler: Callable = Callable()
	var _knockback_handler: Callable = Callable()


	func _init(
		collateral_flag: bool = false,
		player_target: bool = false,
		sweep_hit_handler: Callable = Callable(),
		damage_handler: Callable = Callable(),
		knockback_capability_handler: Callable = Callable(),
		knockback_handler: Callable = Callable()
	) -> void:
		uses_collateral_flag = collateral_flag
		is_player_target = player_target
		_sweep_hit_handler = sweep_hit_handler
		_damage_handler = damage_handler
		_knockback_capability_handler = knockback_capability_handler
		_knockback_handler = knockback_handler


	func is_valid() -> bool:
		return (
			_sweep_hit_handler.is_valid()
			and _damage_handler.is_valid()
			and _knockback_capability_handler.is_valid()
			and _knockback_handler.is_valid()
		)


	func sweep_hits(
		from_position: Vector2,
		to_position: Vector2
	) -> bool:
		return (
			is_valid()
			and bool(_sweep_hit_handler.call(
				from_position,
				to_position
			))
		)


	func apply_damage(
		base_damage: float,
		element_id: String
	) -> DamageResult:
		var raw_result: Variant = _damage_handler.call(
			base_damage,
			element_id
		)
		if raw_result is DamageResult:
			return raw_result as DamageResult
		var result: DamageResult = DamageResult.new()
		result.reason = "invalid_damage_result"
		return result


	func can_apply_knockback() -> bool:
		return is_valid() and bool(_knockback_capability_handler.call())


	func apply_knockback(
		direction: Vector2,
		distance: float,
		duration: float
	) -> void:
		_knockback_handler.call(direction, distance, duration)


class Ports:
	extends RefCounted

	var _windup_handler: Callable = Callable()
	var _committed_handler: Callable = Callable()
	var _movement_handler: Callable = Callable()
	var _targets_handler: Callable = Callable()
	var _finished_handler: Callable = Callable()


	func _init(
		windup_handler: Callable = Callable(),
		committed_handler: Callable = Callable(),
		movement_handler: Callable = Callable(),
		targets_handler: Callable = Callable(),
		finished_handler: Callable = Callable()
	) -> void:
		_windup_handler = windup_handler
		_committed_handler = committed_handler
		_movement_handler = movement_handler
		_targets_handler = targets_handler
		_finished_handler = finished_handler


	func is_valid() -> bool:
		return (
			_windup_handler.is_valid()
			and _committed_handler.is_valid()
			and _movement_handler.is_valid()
			and _targets_handler.is_valid()
			and _finished_handler.is_valid()
		)


	func emit_windup(duration: float) -> void:
		_windup_handler.call(duration)


	func emit_committed() -> void:
		_committed_handler.call()


	func move_charge(
		motion: Vector2,
		locked_direction: Vector2
	) -> MovementResult:
		var raw_result: Variant = _movement_handler.call(
			motion,
			locked_direction
		)
		if raw_result is MovementResult:
			return raw_result as MovementResult
		return MovementResult.new()


	func targets() -> Array[TargetPort]:
		var targets: Array[TargetPort] = []
		var raw_targets: Variant = _targets_handler.call()
		if not raw_targets is Array:
			return targets
		for raw_target: Variant in raw_targets as Array:
			if raw_target is TargetPort:
				targets.append(raw_target as TargetPort)
		return targets


	func finish_charge() -> void:
		_finished_handler.call()


class Result:
	extends RefCounted

	var handled: bool = false
	var started: bool = false
	var windup_started: bool = false
	var committed: bool = false
	var moved: bool = false
	var sweep_hits: int = 0
	var applied_hits: int = 0
	var knockbacks: int = 0
	var finished: bool = false
	var reason: String = ""


static func start(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	request: StartRequest,
	ports: Ports
) -> Result:
	var result: Result = _validated_result(
		runtime,
		config,
		request,
		ports
	)
	if not result.reason.is_empty():
		return result
	result.handled = true
	if not request.focus_target_available:
		result.reason = REASON_FOCUS_UNAVAILABLE
		return result

	runtime.set_locked_direction(request.target_direction.normalized())
	if runtime.locked_direction().length_squared() <= 0.0:
		result.reason = REASON_INVALID_DIRECTION
		return result

	runtime.set_attack_hit_committed(false)
	runtime.set_collateral_player_hit_committed(false)
	result.started = true
	if config.windup > 0.0:
		runtime.set_action_state(
			ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_WINDUP
		)
		runtime.set_action_timer(config.windup)
		ports.emit_windup(config.windup)
		result.windup_started = true
	else:
		_begin_release(runtime, config, ports, result)
	return result


static func advance(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	request: StepRequest,
	ports: Ports
) -> Result:
	var result: Result = _validated_step_result(
		runtime,
		config,
		request,
		ports
	)
	if not result.reason.is_empty():
		return result
	var action_state: String = runtime.action_state()
	if (
		action_state
		!= ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_WINDUP
		and action_state
		!= ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE
	):
		return result

	result.handled = true
	runtime.advance_action_timer(request.delta)
	if (
		action_state
		== ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_WINDUP
	):
		if runtime.action_timer() <= 0.0:
			_begin_release(runtime, config, ports, result)
		return result

	var motion: Vector2 = (
		runtime.locked_direction()
		* request.move_speed
		* request.move_speed_multiplier
		* config.speed_multiplier
		* request.delta
	)
	var movement: MovementResult = ports.move_charge(
		motion,
		runtime.locked_direction()
	)
	result.moved = true
	var hit_during_step: bool = _commit_sweep_hits(
		runtime,
		config,
		movement,
		ports,
		result
	)
	if hit_during_step and config.stop_on_hit:
		_finish(runtime, config, ports, result)
		return result
	if movement.collided or runtime.action_timer() <= 0.0:
		_finish(runtime, config, ports, result)
	return result


static func _validated_result(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	request: StartRequest,
	ports: Ports
) -> Result:
	var result: Result = Result.new()
	if runtime == null:
		result.reason = REASON_INVALID_RUNTIME
	elif config == null:
		result.reason = REASON_INVALID_CONFIG
	elif request == null:
		result.reason = REASON_INVALID_REQUEST
	elif ports == null or not ports.is_valid():
		result.reason = REASON_INVALID_PORTS
	return result


static func _validated_step_result(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	request: StepRequest,
	ports: Ports
) -> Result:
	var result: Result = Result.new()
	if runtime == null:
		result.reason = REASON_INVALID_RUNTIME
	elif config == null:
		result.reason = REASON_INVALID_CONFIG
	elif request == null:
		result.reason = REASON_INVALID_REQUEST
	elif ports == null or not ports.is_valid():
		result.reason = REASON_INVALID_PORTS
	return result


static func _begin_release(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports,
	result: Result
) -> void:
	runtime.set_action_state(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_CHARGE_RELEASE
	)
	runtime.set_action_timer(config.release_duration)
	ports.emit_committed()
	result.committed = true


static func _commit_sweep_hits(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	movement: MovementResult,
	ports: Ports,
	result: Result
) -> bool:
	var hit_during_step: bool = false
	for target: TargetPort in ports.targets():
		if target == null or not target.is_valid():
			continue
		var already_hit: bool = (
			runtime.collateral_player_hit_committed()
			if target.uses_collateral_flag
			else runtime.attack_hit_committed()
		)
		if already_hit or not target.sweep_hits(
			movement.previous_position,
			movement.current_position
		):
			continue
		if target.uses_collateral_flag:
			runtime.set_collateral_player_hit_committed(true)
		else:
			runtime.set_attack_hit_committed(true)
		hit_during_step = true
		result.sweep_hits += 1
		var damage_result: DamageResult = target.apply_damage(
			config.base_damage,
			config.element_id
		)
		if not damage_result.applied:
			continue
		result.applied_hits += 1
		if (
			target.is_player_target
			and damage_result.amount > 0.0
			and config.knockback_distance > 0.0
			and config.knockback_duration > 0.0
			and target.can_apply_knockback()
		):
			target.apply_knockback(
				runtime.locked_direction(),
				config.knockback_distance,
				config.knockback_duration
			)
			result.knockbacks += 1
	return hit_during_step


static func _finish(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports,
	result: Result
) -> void:
	runtime.set_action_state("")
	runtime.set_action_timer(0.0)
	runtime.set_current_action("")
	runtime.set_attack_cooldown_remaining(config.cooldown)
	ports.finish_charge()
	result.finished = true
