# Doc: docs/代码/gameplay_effect_runtime.md
class_name GameplayEffectRuntime
extends RefCounted


const MAX_CHAIN_DEPTH: int = 8
const MAX_ACTIONS_PER_TICK: int = 256

var _registry: EffectPrimitiveRegistry = null
var _gateway: EffectExecutionGateway = null
var _sources: Dictionary = {}
var _event_queue: Array[Dictionary] = []
var _diagnostics: Array[Dictionary] = []
var _dispatching: bool = false
var _action_budget: int = MAX_ACTIONS_PER_TICK
var _current_depth: int = -1


func configure(
	registry: EffectPrimitiveRegistry,
	gateway: EffectExecutionGateway
) -> void:
	_registry = registry
	_gateway = gateway
	_sources.clear()
	_event_queue.clear()
	_diagnostics.clear()
	_dispatching = false
	_action_budget = MAX_ACTIONS_PER_TICK
	_current_depth = -1


func register_source(
	source_type: String,
	content_id: String,
	instance_id: Variant,
	component_order: int,
	programs: Array[Dictionary],
	metadata: Dictionary = {}
) -> bool:
	if (
		_registry == null
		or source_type.is_empty()
		or content_id.is_empty()
		or programs.is_empty()
	):
		return false
	var source_key: String = _source_key(
		source_type,
		content_id,
		instance_id,
		component_order
	)
	var normalized_programs: Array[Dictionary] = []
	var program_ids: Dictionary = {}
	var program_order: int = 0
	for raw_program: Dictionary in programs:
		var program: Dictionary = raw_program.duplicate(true)
		var program_id: String = String(program.get("program_id", "")).strip_edges()
		var trigger_id: String = String(program.get("trigger", ""))
		if (
			program_id.is_empty()
			or program_ids.has(program_id)
			or not _registry.has_trigger(trigger_id)
			or not _is_valid_program(program)
		):
			return false
		program_ids[program_id] = true
		program["_order"] = program_order
		program_order += 1
		normalized_programs.append(program)
	var states: Dictionary = _default_states(normalized_programs)
	if _sources.has(source_key):
		var previous_source: Dictionary = _sources[source_key] as Dictionary
		var previous_states: Dictionary = previous_source.get("states", {}) as Dictionary
		for program_id: Variant in states.keys():
			if previous_states.get(program_id) is Dictionary:
				states[program_id] = (
					previous_states.get(program_id) as Dictionary
				).duplicate(true)
	_sources[source_key] = {
		"source_key": source_key,
		"source_type": source_type,
		"content_id": content_id,
		"instance_id": instance_id,
		"component_order": component_order,
		"programs": normalized_programs,
		"metadata": metadata.duplicate(true),
		"states": states,
	}
	return true


func unregister_source(source_key: String) -> void:
	_sources.erase(source_key)


func unregister_source_type(source_type: String) -> void:
	for source_key: String in _sorted_source_keys():
		var source: Dictionary = _sources[source_key] as Dictionary
		if String(source.get("source_type", "")) == source_type:
			_sources.erase(source_key)


func source_key(
	source_type: String,
	content_id: String,
	instance_id: Variant,
	component_order: int
) -> String:
	return _source_key(source_type, content_id, instance_id, component_order)


func source_keys_for_type(source_type: String) -> Array[String]:
	var result: Array[String] = []
	for source_key_value: String in _sorted_source_keys():
		var source: Dictionary = _sources[source_key_value] as Dictionary
		if String(source.get("source_type", "")) == source_type:
			result.append(source_key_value)
	return result


func emit_event(
	trigger_id: String,
	context: Dictionary = {},
	chain_depth: int = -1
) -> Dictionary:
	if _registry == null or _gateway == null or not _registry.has_trigger(trigger_id):
		return {"ok": false, "reason": "invalid_runtime"}
	var resolved_depth: int = (
		_current_depth + 1 if chain_depth < 0 and _dispatching else maxi(chain_depth, 0)
	)
	if resolved_depth > MAX_CHAIN_DEPTH:
		_record_limit("chain_depth", resolved_depth)
		return {"ok": false, "reason": "chain_depth"}
	_event_queue.append({
		"trigger": trigger_id,
		"context": context.duplicate(true),
		"depth": resolved_depth,
	})
	if _dispatching:
		return {"ok": true, "queued": true, "applied_targets": 0}
	return _drain_queue()


func tick(delta: float, context: Dictionary = {}) -> void:
	var scaled_delta: float = maxf(GameClock.delta_scaled(delta), 0.0)
	if scaled_delta <= 0.0:
		return
	_action_budget = MAX_ACTIONS_PER_TICK
	for source_key: String in _sorted_source_keys():
		var source: Dictionary = _sources[source_key] as Dictionary
		var states: Dictionary = source.get("states", {}) as Dictionary
		for program: Dictionary in _typed_dictionary_array(source.get("programs", [])):
			var program_id: String = String(program.get("program_id", ""))
			var state: Dictionary = (states.get(program_id, {}) as Dictionary).duplicate(true)
			state["cooldown_remaining"] = maxf(
				float(state.get("cooldown_remaining", 0.0)) - scaled_delta,
				0.0
			)
			if String(program.get("trigger", "")) == EffectPrimitiveRegistry.TRIGGER_INTERVAL:
				var interval: float = maxf(float(program.get("interval_seconds", 0.0)), 0.0)
				if interval > 0.0:
					state["interval_elapsed"] = minf(
						float(state.get("interval_elapsed", 0.0)) + scaled_delta,
						interval
					)
			states[program_id] = state
		source["states"] = states
		_sources[source_key] = source
	var interval_context: Dictionary = context.duplicate(true)
	emit_event(EffectPrimitiveRegistry.TRIGGER_INTERVAL, interval_context)


func snapshot() -> Dictionary:
	var source_states: Array[Dictionary] = []
	for source_key: String in _sorted_source_keys():
		var source: Dictionary = _sources[source_key] as Dictionary
		source_states.append({
			"source_key": source_key,
			"states": (source.get("states", {}) as Dictionary).duplicate(true),
		})
	return {"source_states": source_states}


func restore_snapshot(saved: Dictionary) -> bool:
	var raw_states: Variant = saved.get("source_states", [])
	if not raw_states is Array:
		return false
	var restored_keys: Dictionary = {}
	for raw_source_state: Variant in raw_states as Array:
		if not raw_source_state is Dictionary:
			return false
		var source_state: Dictionary = raw_source_state as Dictionary
		var source_key: String = String(source_state.get("source_key", ""))
		if source_key.is_empty() or restored_keys.has(source_key) or not _sources.has(source_key):
			return false
		var raw_program_states: Variant = source_state.get("states", {})
		if not raw_program_states is Dictionary:
			return false
		var source: Dictionary = _sources[source_key] as Dictionary
		var expected_states: Dictionary = source.get("states", {}) as Dictionary
		var normalized_states: Dictionary = {}
		for raw_program_id: Variant in expected_states.keys():
			var program_id: String = String(raw_program_id)
			var raw_state: Variant = (raw_program_states as Dictionary).get(program_id)
			if not raw_state is Dictionary:
				return false
			var state: Dictionary = raw_state as Dictionary
			var cooldown_remaining: float = float(
				state.get("cooldown_remaining", -1.0)
			)
			var interval_elapsed: float = float(
				state.get("interval_elapsed", -1.0)
			)
			if (
				not is_finite(cooldown_remaining)
				or cooldown_remaining < 0.0
				or not is_finite(interval_elapsed)
				or interval_elapsed < 0.0
				or not state.get("action_state") is Dictionary
			):
				return false
			normalized_states[program_id] = {
				"cooldown_remaining": cooldown_remaining,
				"interval_elapsed": interval_elapsed,
				"action_state": _dictionary_or_empty(state.get("action_state", {})),
			}
		source["states"] = normalized_states
		_sources[source_key] = source
		restored_keys[source_key] = true
	return restored_keys.size() == _sources.size()


func diagnostics() -> Array[Dictionary]:
	return _diagnostics.duplicate(true)


func _drain_queue() -> Dictionary:
	_dispatching = true
	var applied_targets: int = 0
	var executed_actions: int = 0
	while not _event_queue.is_empty():
		var event: Dictionary = _event_queue.pop_front() as Dictionary
		_current_depth = int(event.get("depth", 0))
		if int(event.get("depth", 0)) > MAX_CHAIN_DEPTH:
			_record_limit("chain_depth", int(event.get("depth", 0)))
			continue
		var event_result: Dictionary = _process_event(event)
		applied_targets += int(event_result.get("applied_targets", 0))
		executed_actions += int(event_result.get("executed_actions", 0))
		if _action_budget <= 0:
			_event_queue.clear()
			break
	_dispatching = false
	_current_depth = -1
	return {
		"ok": true,
		"applied_targets": applied_targets,
		"executed_actions": executed_actions,
	}


func _process_event(event: Dictionary) -> Dictionary:
	var trigger_id: String = String(event.get("trigger", ""))
	var base_context: Dictionary = _dictionary_or_empty(event.get("context", {}))
	var applied_targets: int = 0
	var executed_actions: int = 0
	for source_key: String in _sorted_source_keys():
		var requested_source_key: String = String(
			base_context.get("effect_source_key", "")
		)
		if not requested_source_key.is_empty() and requested_source_key != source_key:
			continue
		var source: Dictionary = _sources[source_key] as Dictionary
		var source_metadata: Dictionary = _dictionary_or_empty(source.get("metadata", {}))
		var states: Dictionary = source.get("states", {}) as Dictionary
		for program: Dictionary in _typed_dictionary_array(source.get("programs", [])):
			if String(program.get("trigger", "")) != trigger_id:
				continue
			var program_id: String = String(program.get("program_id", ""))
			var state: Dictionary = (states.get(program_id, {}) as Dictionary).duplicate(true)
			var interval: float = 0.0
			if trigger_id == EffectPrimitiveRegistry.TRIGGER_INTERVAL:
				interval = maxf(float(program.get("interval_seconds", 0.0)), 0.0)
				if interval <= 0.0:
					continue
			var context: Dictionary = base_context.duplicate(true)
			context.merge(source_metadata, false)
			context["source_key"] = source_key
			context["source_type"] = String(source.get("source_type", ""))
			context["content_id"] = String(source.get("content_id", ""))
			context["source_instance_id"] = source.get("instance_id")
			context["component_order"] = int(source.get("component_order", 0))
			context["program_id"] = program_id
			context["program_state"] = _dictionary_or_empty(state.get("action_state", {}))
			var retain_interval: bool = false
			var conditions: Array[Dictionary] = _typed_dictionary_array(
				program.get("conditions", [])
			)
			if not _registry.conditions_met(conditions, context):
				if trigger_id == EffectPrimitiveRegistry.TRIGGER_INTERVAL and bool(
					program.get("reset_on_condition_fail", false)
				):
					state["interval_elapsed"] = 0.0
					state["action_state"] = {}
					states[program_id] = state
				continue
			if float(state.get("cooldown_remaining", 0.0)) > 0.0:
				continue
			if (
				trigger_id == EffectPrimitiveRegistry.TRIGGER_INTERVAL
				and float(state.get("interval_elapsed", 0.0)) < interval
			):
				continue
			var proc_chance: float = clampf(float(program.get("proc_chance", 1.0)), 0.0, 1.0)
			if proc_chance < 1.0 and RNG.combat.randf() >= proc_chance:
				if trigger_id == EffectPrimitiveRegistry.TRIGGER_INTERVAL:
					state["interval_elapsed"] = 0.0
					states[program_id] = state
				continue
			for action: Dictionary in _typed_dictionary_array(program.get("actions", [])):
				if _action_budget <= 0:
					_record_limit("action_budget", MAX_ACTIONS_PER_TICK)
					break
				_action_budget -= 1
				executed_actions += 1
				var result: Dictionary = _registry.execute_action(action, context, _gateway)
				applied_targets += int(result.get("applied_targets", 0))
				retain_interval = retain_interval or bool(result.get("retain_interval", false))
				if result.get("action_state") is Dictionary:
					state["action_state"] = (
						result.get("action_state") as Dictionary
					).duplicate(true)
				context["program_state"] = _dictionary_or_empty(state.get("action_state", {}))
			state["cooldown_remaining"] = maxf(
				float(program.get("internal_cooldown", 0.0)),
				0.0
			)
			if trigger_id == EffectPrimitiveRegistry.TRIGGER_INTERVAL and not retain_interval:
				state["interval_elapsed"] = 0.0
			states[program_id] = state
		source["states"] = states
		_sources[source_key] = source
		if _action_budget <= 0:
			break
	return {"applied_targets": applied_targets, "executed_actions": executed_actions}


func _default_states(programs: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for program: Dictionary in programs:
		result[String(program.get("program_id", ""))] = {
			"cooldown_remaining": 0.0,
			"interval_elapsed": 0.0,
			"action_state": {},
		}
	return result


func _is_valid_program(program: Dictionary) -> bool:
	if not _has_valid_program_keys(program):
		return false
	if not _is_snake_case_identifier(program.get("program_id")):
		return false
	if not program.get("trigger") is String:
		return false
	if (
		not _is_finite_number(program.get("proc_chance"))
		or not _is_finite_number(program.get("internal_cooldown"))
	):
		return false
	var proc_chance: float = float(program.get("proc_chance"))
	var internal_cooldown: float = float(program.get("internal_cooldown"))
	if (
		proc_chance < 0.0
		or proc_chance > 1.0
		or internal_cooldown < 0.0
	):
		return false
	var trigger_id: String = String(program.get("trigger"))
	if trigger_id == EffectPrimitiveRegistry.TRIGGER_INTERVAL:
		if (
			not _is_finite_number(program.get("interval_seconds"))
			or float(program.get("interval_seconds")) <= 0.0
		):
			return false
		if (
			program.has("reset_on_condition_fail")
			and not program.get("reset_on_condition_fail") is bool
		):
			return false
	elif (
		program.has("interval_seconds")
		or program.has("reset_on_condition_fail")
	):
		return false
	var conditions: Array[Dictionary] = _typed_dictionary_array(
		program.get("conditions", [])
	)
	if conditions.size() != _array_size(program.get("conditions")):
		return false
	for condition: Dictionary in conditions:
		if not _registry.validate_condition(condition):
			return false
	var actions: Array[Dictionary] = _typed_dictionary_array(program.get("actions", []))
	if actions.is_empty() or actions.size() != _array_size(program.get("actions")):
		return false
	for action: Dictionary in actions:
		if not _registry.validate_action(action):
			return false
	return true


func _has_valid_program_keys(program: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"program_id",
		"trigger",
		"conditions",
		"actions",
		"proc_chance",
		"internal_cooldown",
	]
	var optional_keys: Array[String] = [
		"interval_seconds",
		"reset_on_condition_fail",
	]
	for required_key: String in required_keys:
		if not program.has(required_key):
			return false
	for raw_key: Variant in program.keys():
		if not raw_key is String:
			return false
		var key: String = String(raw_key)
		if not required_keys.has(key) and not optional_keys.has(key):
			return false
	return true


func _is_snake_case_identifier(value: Variant) -> bool:
	if not value is String:
		return false
	var identifier: String = String(value)
	if identifier.is_empty():
		return false
	var pattern: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return pattern.search(identifier) != null


func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _array_size(raw_value: Variant) -> int:
	return (raw_value as Array).size() if raw_value is Array else -1


func _record_limit(limit_id: String, value: int) -> void:
	_diagnostics.append({"reason": "effect_limit", "limit": limit_id, "value": value})
	push_warning("[GameplayEffectRuntime] %s limit reached: %d" % [limit_id, value])


func _source_key(
	source_type: String,
	content_id: String,
	instance_id: Variant,
	component_order: int
) -> String:
	return "%s|%s|%s|%08d" % [source_type, content_id, str(instance_id), component_order]


func _sorted_source_keys() -> Array[String]:
	var result: Array[String] = []
	for raw_key: Variant in _sources.keys():
		result.append(String(raw_key))
	result.sort_custom(_source_less)
	return result


func _source_less(left_key: String, right_key: String) -> bool:
	var left: Dictionary = _sources[left_key] as Dictionary
	var right: Dictionary = _sources[right_key] as Dictionary
	var left_type: String = String(left.get("source_type", ""))
	var right_type: String = String(right.get("source_type", ""))
	if left_type != right_type:
		return left_type < right_type
	var left_content: String = String(left.get("content_id", ""))
	var right_content: String = String(right.get("content_id", ""))
	if left_content != right_content:
		return left_content < right_content
	var left_instance: Variant = left.get("instance_id")
	var right_instance: Variant = right.get("instance_id")
	if left_instance is int and right_instance is int:
		if int(left_instance) != int(right_instance):
			return int(left_instance) < int(right_instance)
	else:
		var left_instance_text: String = str(left_instance)
		var right_instance_text: String = str(right_instance)
		if left_instance_text != right_instance_text:
			return left_instance_text < right_instance_text
	return int(left.get("component_order", 0)) < int(
		right.get("component_order", 0)
	)


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if raw_value is Array:
		for item: Variant in raw_value as Array:
			if item is Dictionary:
				result.append((item as Dictionary).duplicate(true))
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	return (raw_value as Dictionary).duplicate(true) if raw_value is Dictionary else {}
