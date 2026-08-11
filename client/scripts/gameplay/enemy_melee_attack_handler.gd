# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyMeleeAttackHandler
extends RefCounted
## Stateless melee windup and commit transitions over typed Actor ports.


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
	var attack_range: float = 0.0
	var arc_degrees: float = 0.0
	var base_damage: float = 0.0
	var element_id: String = ""


class StartRequest:
	extends RefCounted

	var focus_target_available: bool = false
	var target_direction: Vector2 = Vector2.ZERO


class DamageResult:
	extends RefCounted

	var applied: bool = false
	var amount: float = 0.0
	var defeated: bool = false
	var reason: String = ""


class TargetPort:
	extends RefCounted

	var _available_handler: Callable = Callable()
	var _relative_position_handler: Callable = Callable()
	var _terrain_los_handler: Callable = Callable()
	var _damage_handler: Callable = Callable()


	func _init(
		available_handler: Callable = Callable(),
		relative_position_handler: Callable = Callable(),
		terrain_los_handler: Callable = Callable(),
		damage_handler: Callable = Callable()
	) -> void:
		_available_handler = available_handler
		_relative_position_handler = relative_position_handler
		_terrain_los_handler = terrain_los_handler
		_damage_handler = damage_handler


	func is_valid() -> bool:
		return (
			_available_handler.is_valid()
			and _relative_position_handler.is_valid()
			and _terrain_los_handler.is_valid()
			and _damage_handler.is_valid()
		)


	func is_available() -> bool:
		return is_valid() and bool(_available_handler.call())


	func relative_position() -> Vector2:
		var raw_position: Variant = _relative_position_handler.call()
		return (
			raw_position as Vector2
			if raw_position is Vector2
			else Vector2.ZERO
		)


	func has_terrain_line_of_sight() -> bool:
		return bool(_terrain_los_handler.call())


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


class Ports:
	extends RefCounted

	var _windup_handler: Callable = Callable()
	var _targets_handler: Callable = Callable()
	var _committed_handler: Callable = Callable()
	var _finished_handler: Callable = Callable()


	func _init(
		windup_handler: Callable = Callable(),
		targets_handler: Callable = Callable(),
		committed_handler: Callable = Callable(),
		finished_handler: Callable = Callable()
	) -> void:
		_windup_handler = windup_handler
		_targets_handler = targets_handler
		_committed_handler = committed_handler
		_finished_handler = finished_handler


	func is_valid() -> bool:
		return (
			_windup_handler.is_valid()
			and _targets_handler.is_valid()
			and _committed_handler.is_valid()
			and _finished_handler.is_valid()
		)


	func emit_windup(duration: float) -> void:
		_windup_handler.call(duration)


	func targets() -> Array[TargetPort]:
		var targets: Array[TargetPort] = []
		var raw_targets: Variant = _targets_handler.call()
		if not raw_targets is Array:
			return targets
		for raw_target: Variant in raw_targets as Array:
			if raw_target is TargetPort:
				targets.append(raw_target as TargetPort)
		return targets


	func emit_committed(attack_range: float) -> void:
		_committed_handler.call(attack_range)


	func finish_attack() -> void:
		_finished_handler.call()


class Result:
	extends RefCounted

	var handled: bool = false
	var started: bool = false
	var windup_started: bool = false
	var committed: bool = false
	var damage_attempts: int = 0
	var applied_hits: int = 0
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
	runtime.set_action_state(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	)
	runtime.set_action_timer(config.windup)
	ports.emit_windup(config.windup)
	result.started = true
	result.windup_started = true
	if config.windup <= 0.0:
		_commit(runtime, config, ports, result)
	return result


static func advance(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	delta: float,
	ports: Ports
) -> Result:
	var result: Result = _validated_result(
		runtime,
		config,
		StartRequest.new(),
		ports
	)
	if not result.reason.is_empty():
		return result
	if (
		runtime.action_state()
		!= ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_MELEE_WINDUP
	):
		return result

	result.handled = true
	runtime.advance_action_timer(delta)
	if runtime.action_timer() <= 0.0:
		_commit(runtime, config, ports, result)
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


static func _commit(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports,
	result: Result
) -> void:
	for target: TargetPort in ports.targets():
		if not _target_in_arc(runtime, config, target):
			continue
		result.damage_attempts += 1
		var damage_result: DamageResult = target.apply_damage(
			config.base_damage,
			config.element_id
		)
		if damage_result.applied:
			runtime.set_attack_hit_committed(true)
			result.applied_hits += 1

	ports.emit_committed(config.attack_range)
	result.committed = true
	runtime.set_attack_cooldown_remaining(config.cooldown)
	runtime.set_action_state("")
	runtime.set_action_timer(0.0)
	runtime.set_current_action("")
	ports.finish_attack()
	result.finished = true


static func _target_in_arc(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	target: TargetPort
) -> bool:
	if target == null or not target.is_available():
		return false
	var to_target: Vector2 = target.relative_position()
	if to_target.length_squared() <= 0.0:
		return true
	if to_target.length() > config.attack_range:
		return false
	var half_arc: float = deg_to_rad(config.arc_degrees * 0.5)
	var angle: float = runtime.locked_direction().angle_to(
		to_target.normalized()
	)
	if absf(angle) > half_arc:
		return false
	return target.has_terrain_line_of_sight()
