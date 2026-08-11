# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyRangedAttackHandler
extends RefCounted
## Stateless ranged burst scheduling over EnemyActionRuntime and typed ports.


const ENEMY_ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)
const PROJECTILE_MATERIALIZER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_projectile_materializer.gd"
)

const REASON_INVALID_CONFIG: String = "invalid_config"
const REASON_INVALID_DIRECTION: String = "invalid_direction"
const REASON_INVALID_PORTS: String = "invalid_ports"
const REASON_INVALID_RUNTIME: String = "invalid_runtime"


class Config:
	extends RefCounted

	var windup: float = 0.0
	var burst_count: int = 0
	var shot_interval: float = 0.0
	var cooldown: float = 0.0
	var projectile: PROJECTILE_MATERIALIZER_SCRIPT.Spec = (
		PROJECTILE_MATERIALIZER_SCRIPT.Spec.new()
	)


class Ports:
	extends RefCounted

	var _stop_and_face_handler: Callable = Callable()
	var _windup_handler: Callable = Callable()
	var _materialize_handler: Callable = Callable()
	var _committed_handler: Callable = Callable()
	var _finished_handler: Callable = Callable()


	func _init(
		stop_and_face_handler: Callable = Callable(),
		windup_handler: Callable = Callable(),
		materialize_handler: Callable = Callable(),
		committed_handler: Callable = Callable(),
		finished_handler: Callable = Callable()
	) -> void:
		_stop_and_face_handler = stop_and_face_handler
		_windup_handler = windup_handler
		_materialize_handler = materialize_handler
		_committed_handler = committed_handler
		_finished_handler = finished_handler


	func is_valid() -> bool:
		return (
			_stop_and_face_handler.is_valid()
			and _windup_handler.is_valid()
			and _materialize_handler.is_valid()
			and _committed_handler.is_valid()
			and _finished_handler.is_valid()
		)


	func stop_and_face(direction: Vector2) -> void:
		_stop_and_face_handler.call(direction)


	func emit_windup(duration: float) -> void:
		_windup_handler.call(duration)


	func materialize(
		projectile: PROJECTILE_MATERIALIZER_SCRIPT.Spec,
		direction: Vector2
	) -> PROJECTILE_MATERIALIZER_SCRIPT.Result:
		var raw_result: Variant = _materialize_handler.call(
			projectile,
			direction
		)
		if raw_result is PROJECTILE_MATERIALIZER_SCRIPT.Result:
			return raw_result as PROJECTILE_MATERIALIZER_SCRIPT.Result
		return PROJECTILE_MATERIALIZER_SCRIPT.failed_result(
			"invalid_materializer_result"
		)


	func emit_committed() -> void:
		_committed_handler.call()


	func finish_burst() -> void:
		_finished_handler.call()


class Result:
	extends RefCounted

	var handled: bool = false
	var started: bool = false
	var windup_started: bool = false
	var burst_started: bool = false
	var scheduled_shot_committed: bool = false
	var projectile_materialized: bool = false
	var projectile_reason: String = ""
	var finished: bool = false
	var reason: String = ""


static func start_burst(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	target_direction: Vector2,
	ports: Ports
) -> Result:
	var result: Result = _validated_result(runtime, config, ports)
	if not result.reason.is_empty():
		return result
	result.handled = true
	if target_direction.length_squared() <= 0.0:
		result.reason = REASON_INVALID_DIRECTION
		return result

	runtime.set_locked_direction(target_direction.normalized())
	runtime.set_burst_shots_remaining(config.burst_count)
	if runtime.burst_shots_remaining() <= 0:
		_finish_burst(runtime, config, ports, result)
		return result

	ports.stop_and_face(runtime.locked_direction())
	runtime.set_action_state(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP
	)
	runtime.set_action_timer(config.windup)
	ports.emit_windup(config.windup)
	result.started = true
	result.windup_started = true
	if config.windup <= 0.0:
		_begin_burst(runtime, config, ports, result)
	return result


static func advance(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	delta: float,
	ports: Ports
) -> Result:
	var result: Result = _validated_result(runtime, config, ports)
	if not result.reason.is_empty():
		return result
	var action_state: String = runtime.action_state()
	if (
		action_state
		!= ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP
		and action_state
		!= ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST
	):
		return result

	result.handled = true
	runtime.advance_action_timer(delta)
	if (
		action_state
		== ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_WINDUP
	):
		if runtime.action_timer() <= 0.0:
			_begin_burst(runtime, config, ports, result)
		return result
	if runtime.action_timer() <= 0.0:
		_fire_scheduled_shot(runtime, config, ports, result)
	return result


static func _validated_result(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports
) -> Result:
	var result: Result = Result.new()
	if runtime == null:
		result.reason = REASON_INVALID_RUNTIME
	elif config == null or config.projectile == null:
		result.reason = REASON_INVALID_CONFIG
	elif ports == null or not ports.is_valid():
		result.reason = REASON_INVALID_PORTS
	return result


static func _begin_burst(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports,
	result: Result
) -> void:
	runtime.set_action_state(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_RANGED_BURST
	)
	runtime.set_action_timer(0.0)
	result.burst_started = true
	_fire_scheduled_shot(runtime, config, ports, result)


static func _fire_scheduled_shot(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports,
	result: Result
) -> void:
	if (
		runtime.burst_shots_remaining() <= 0
		or runtime.locked_direction().length_squared() <= 0.0
	):
		_finish_burst(runtime, config, ports, result)
		return

	var materialization: PROJECTILE_MATERIALIZER_SCRIPT.Result = (
		ports.materialize(
			config.projectile,
			runtime.locked_direction()
		)
	)
	result.projectile_materialized = materialization.ok
	result.projectile_reason = materialization.reason
	ports.emit_committed()
	result.scheduled_shot_committed = true
	runtime.set_burst_shots_remaining(
		runtime.burst_shots_remaining() - 1
	)
	if runtime.burst_shots_remaining() <= 0:
		_finish_burst(runtime, config, ports, result)
		return
	runtime.set_action_timer(config.shot_interval)


static func _finish_burst(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports,
	result: Result
) -> void:
	runtime.set_burst_shots_remaining(0)
	runtime.set_attack_cooldown_remaining(config.cooldown)
	runtime.set_action_state("")
	runtime.set_action_timer(0.0)
	runtime.set_current_action("")
	ports.finish_burst()
	result.finished = true
