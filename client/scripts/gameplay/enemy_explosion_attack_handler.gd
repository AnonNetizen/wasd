# Doc: docs/代码/enemy_ai.md
# Authority: docs/决策记录.md ADR #197
class_name EnemyExplosionAttackHandler
extends RefCounted
## Stateless explosion arming, detonation, and armed-restore transitions.


const ENEMY_ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)

const REASON_ACTION_UNAVAILABLE: String = "action_unavailable"
const REASON_ALREADY_ARMED: String = "already_armed"
const REASON_ALREADY_EXPLODED: String = "already_exploded"
const REASON_INVALID_CONFIG: String = "invalid_config"
const REASON_INVALID_PORTS: String = "invalid_ports"
const REASON_INVALID_REQUEST: String = "invalid_request"
const REASON_INVALID_RUNTIME: String = "invalid_runtime"
const REASON_NOT_ARMED: String = "not_armed"


class Config:
	extends RefCounted

	var explode_action_id: String = ""
	var windup: float = 0.0
	var base_damage: float = 0.0
	var element_id: String = ""
	var radius: float = 0.0


class ArmRequest:
	extends RefCounted

	var action_available: bool = false
	var from_chain: bool = false


class DamageResult:
	extends RefCounted

	var applied: bool = false
	var amount: float = 0.0
	var defeated: bool = false
	var reason: String = ""


class DirectTargetPort:
	extends RefCounted

	var _valid_handler: Callable = Callable()
	var _position_handler: Callable = Callable()
	var _damage_handler: Callable = Callable()


	func _init(
		valid_handler: Callable = Callable(),
		position_handler: Callable = Callable(),
		damage_handler: Callable = Callable()
	) -> void:
		_valid_handler = valid_handler
		_position_handler = position_handler
		_damage_handler = damage_handler


	func is_valid() -> bool:
		return (
			_valid_handler.is_valid()
			and _position_handler.is_valid()
			and _damage_handler.is_valid()
			and bool(_valid_handler.call())
		)


	func position() -> Vector2:
		var raw_position: Variant = _position_handler.call()
		return (
			raw_position as Vector2
			if raw_position is Vector2
			else Vector2.ZERO
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


class EnemyTargetPort:
	extends RefCounted

	var _valid_handler: Callable = Callable()
	var _source_handler: Callable = Callable()
	var _armed_handler: Callable = Callable()
	var _alive_handler: Callable = Callable()
	var _position_handler: Callable = Callable()
	var _spawn_serial_handler: Callable = Callable()
	var _damage_handler: Callable = Callable()


	func _init(
		valid_handler: Callable = Callable(),
		source_handler: Callable = Callable(),
		armed_handler: Callable = Callable(),
		alive_handler: Callable = Callable(),
		position_handler: Callable = Callable(),
		spawn_serial_handler: Callable = Callable(),
		damage_handler: Callable = Callable()
	) -> void:
		_valid_handler = valid_handler
		_source_handler = source_handler
		_armed_handler = armed_handler
		_alive_handler = alive_handler
		_position_handler = position_handler
		_spawn_serial_handler = spawn_serial_handler
		_damage_handler = damage_handler


	func is_valid() -> bool:
		return (
			_valid_handler.is_valid()
			and _source_handler.is_valid()
			and _armed_handler.is_valid()
			and _alive_handler.is_valid()
			and _position_handler.is_valid()
			and _spawn_serial_handler.is_valid()
			and _damage_handler.is_valid()
			and bool(_valid_handler.call())
		)


	func is_source() -> bool:
		return bool(_source_handler.call())


	func is_armed() -> bool:
		return bool(_armed_handler.call())


	func is_alive() -> bool:
		return bool(_alive_handler.call())


	func position() -> Vector2:
		var raw_position: Variant = _position_handler.call()
		return (
			raw_position as Vector2
			if raw_position is Vector2
			else Vector2.ZERO
		)


	func spawn_serial() -> int:
		return int(_spawn_serial_handler.call())


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

	var _clear_focus_handler: Callable = Callable()
	var _stop_movement_handler: Callable = Callable()
	var _collision_handler: Callable = Callable()
	var _windup_handler: Callable = Callable()
	var _refresh_handler: Callable = Callable()
	var _source_position_handler: Callable = Callable()
	var _committed_handler: Callable = Callable()
	var _direct_targets_handler: Callable = Callable()
	var _enemy_targets_handler: Callable = Callable()
	var _line_of_sight_handler: Callable = Callable()
	var _finished_handler: Callable = Callable()


	func _init(
		clear_focus_handler: Callable = Callable(),
		stop_movement_handler: Callable = Callable(),
		collision_handler: Callable = Callable(),
		windup_handler: Callable = Callable(),
		refresh_handler: Callable = Callable(),
		source_position_handler: Callable = Callable(),
		committed_handler: Callable = Callable(),
		direct_targets_handler: Callable = Callable(),
		enemy_targets_handler: Callable = Callable(),
		line_of_sight_handler: Callable = Callable(),
		finished_handler: Callable = Callable()
	) -> void:
		_clear_focus_handler = clear_focus_handler
		_stop_movement_handler = stop_movement_handler
		_collision_handler = collision_handler
		_windup_handler = windup_handler
		_refresh_handler = refresh_handler
		_source_position_handler = source_position_handler
		_committed_handler = committed_handler
		_direct_targets_handler = direct_targets_handler
		_enemy_targets_handler = enemy_targets_handler
		_line_of_sight_handler = line_of_sight_handler
		_finished_handler = finished_handler


	func is_valid() -> bool:
		return (
			_clear_focus_handler.is_valid()
			and _stop_movement_handler.is_valid()
			and _collision_handler.is_valid()
			and _windup_handler.is_valid()
			and _refresh_handler.is_valid()
			and _source_position_handler.is_valid()
			and _committed_handler.is_valid()
			and _direct_targets_handler.is_valid()
			and _enemy_targets_handler.is_valid()
			and _line_of_sight_handler.is_valid()
			and _finished_handler.is_valid()
		)


	func clear_focus() -> void:
		_clear_focus_handler.call()


	func stop_movement() -> void:
		_stop_movement_handler.call()


	func set_collision_enabled(enabled: bool) -> void:
		_collision_handler.call(enabled)


	func emit_windup(duration: float) -> void:
		_windup_handler.call(duration)


	func refresh_visuals() -> void:
		_refresh_handler.call()


	func source_position() -> Vector2:
		var raw_position: Variant = _source_position_handler.call()
		return (
			raw_position as Vector2
			if raw_position is Vector2
			else Vector2.ZERO
		)


	func emit_committed() -> void:
		_committed_handler.call()


	func direct_targets() -> Array[DirectTargetPort]:
		var targets: Array[DirectTargetPort] = []
		var raw_targets: Variant = _direct_targets_handler.call()
		if not raw_targets is Array:
			return targets
		for raw_target: Variant in raw_targets as Array:
			if raw_target is DirectTargetPort:
				targets.append(raw_target as DirectTargetPort)
		return targets


	func enemy_targets() -> Array[EnemyTargetPort]:
		var targets: Array[EnemyTargetPort] = []
		var raw_targets: Variant = _enemy_targets_handler.call()
		if not raw_targets is Array:
			return targets
		for raw_target: Variant in raw_targets as Array:
			if raw_target is EnemyTargetPort:
				targets.append(raw_target as EnemyTargetPort)
		return targets


	func has_line_of_sight(
		from_position: Vector2,
		to_position: Vector2
	) -> bool:
		return bool(_line_of_sight_handler.call(
			from_position,
			to_position
		))


	func finish_explosion() -> void:
		_finished_handler.call()


class Result:
	extends RefCounted

	var handled: bool = false
	var armed: bool = false
	var restored: bool = false
	var windup_emitted: bool = false
	var detonated: bool = false
	var direct_damage_attempts: int = 0
	var enemy_damage_attempts: int = 0
	var finished: bool = false
	var reason: String = ""


static func arm(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	request: ArmRequest,
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
	if runtime.is_armed():
		result.reason = REASON_ALREADY_ARMED
		return result
	if runtime.has_exploded():
		result.reason = REASON_ALREADY_EXPLODED
		return result
	if not request.action_available:
		result.reason = REASON_ACTION_UNAVAILABLE
		return result

	runtime.set_current_action(config.explode_action_id)
	ports.clear_focus()
	runtime.set_armed(true)
	runtime.set_armed_from_chain(request.from_chain)
	runtime.set_attack_hit_committed(false)
	runtime.set_collateral_player_hit_committed(false)
	runtime.set_locked_direction(Vector2.ZERO)
	runtime.set_action_state(
		ENEMY_ACTION_RUNTIME_SCRIPT.ACTION_STATE_ARMED_WINDUP
	)
	runtime.set_action_timer(config.windup)
	ports.stop_movement()
	ports.set_collision_enabled(false)
	ports.emit_windup(runtime.action_timer())
	result.windup_emitted = true
	ports.refresh_visuals()
	result.armed = true
	if runtime.action_timer() <= 0.0:
		_detonate(runtime, config, ports, result)
	return result


static func advance(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	delta: float,
	ports: Ports
) -> Result:
	var result: Result = _validated_advance_result(
		runtime,
		config,
		ports
	)
	if not result.reason.is_empty():
		return result
	if not runtime.is_armed():
		result.reason = REASON_NOT_ARMED
		return result
	result.handled = true
	if runtime.has_exploded():
		result.reason = REASON_ALREADY_EXPLODED
		return result
	runtime.advance_action_timer(delta)
	if runtime.action_timer() <= 0.0:
		_detonate(runtime, config, ports, result)
	return result


static func restore_armed(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	explode_action_id: String,
	ports: Ports
) -> Result:
	var result: Result = Result.new()
	if runtime == null:
		result.reason = REASON_INVALID_RUNTIME
		return result
	if ports == null or not ports.is_valid():
		result.reason = REASON_INVALID_PORTS
		return result
	if not runtime.is_armed():
		result.reason = REASON_NOT_ARMED
		return result

	result.handled = true
	runtime.force_armed_restore(explode_action_id)
	ports.set_collision_enabled(false)
	ports.emit_windup(runtime.action_timer())
	result.restored = true
	result.windup_emitted = true
	return result


static func _validated_result(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	request: ArmRequest,
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


static func _validated_advance_result(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports
) -> Result:
	var result: Result = Result.new()
	if runtime == null:
		result.reason = REASON_INVALID_RUNTIME
	elif config == null:
		result.reason = REASON_INVALID_CONFIG
	elif ports == null or not ports.is_valid():
		result.reason = REASON_INVALID_PORTS
	return result


static func _detonate(
	runtime: ENEMY_ACTION_RUNTIME_SCRIPT,
	config: Config,
	ports: Ports,
	result: Result
) -> void:
	if not runtime.is_armed() or runtime.has_exploded():
		return
	runtime.set_has_exploded(true)
	runtime.set_attack_hit_committed(true)
	var blast_position: Vector2 = ports.source_position()
	ports.emit_committed()
	result.detonated = true

	for target: DirectTargetPort in ports.direct_targets():
		if target == null or not target.is_valid():
			continue
		var live_source_position: Vector2 = ports.source_position()
		var target_position: Vector2 = target.position()
		if (
			live_source_position.distance_to(target_position)
			> config.radius
			or not ports.has_line_of_sight(
				live_source_position,
				target_position
			)
		):
			continue
		target.apply_damage(config.base_damage, config.element_id)
		result.direct_damage_attempts += 1

	var enemy_targets: Array[EnemyTargetPort] = []
	for target: EnemyTargetPort in ports.enemy_targets():
		if target == null or not target.is_valid():
			continue
		if target.is_source() or target.is_armed() or not target.is_alive():
			continue
		var target_position: Vector2 = target.position()
		if (
			blast_position.distance_to(target_position) > config.radius
			or not ports.has_line_of_sight(
				blast_position,
				target_position
			)
		):
			continue
		enemy_targets.append(target)
	enemy_targets.sort_custom(_spawn_serial_less)
	for target: EnemyTargetPort in enemy_targets:
		if target == null or not target.is_valid():
			continue
		target.apply_damage(config.base_damage, config.element_id)
		result.enemy_damage_attempts += 1

	ports.finish_explosion()
	result.finished = true


static func _spawn_serial_less(
	left: EnemyTargetPort,
	right: EnemyTargetPort
) -> bool:
	return left.spawn_serial() < right.spawn_serial()
