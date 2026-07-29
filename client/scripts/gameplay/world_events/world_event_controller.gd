# Doc: docs/代码/world_event_system.md
# Authority: docs/游戏设计文档.md §5.3, docs/决策记录.md ADR #173
class_name WorldEventController
extends Node


signal instance_registered(instance_id: String, event_id: String)
signal state_changed(
	instance_id: String,
	event_id: String,
	state: String,
	context: Dictionary
)
signal wave_requested(
	instance_id: String,
	event_id: String,
	wave_index: int,
	enemy_count: int,
	world_position: Vector2,
	primary_target: Node,
	context: Dictionary
)
signal reward_plan_requested(
	instance_id: String,
	event_id: String,
	reward_config: Dictionary
)
signal reward_requested(
	instance_id: String,
	event_id: String,
	reward: Dictionary
)
signal prompt_requested(
	instance_id: String,
	event_id: String,
	reason: String,
	context: Dictionary
)
signal module_pin_requested(
	instance_id: String,
	module_slot_id: String,
	pinned: bool
)
signal terminal_cleanup_requested(
	instance_id: String,
	event_id: String,
	context: Dictionary
)

const WORLD_EVENT_KINDS := preload(
	"res://scripts/contracts/world_event_kinds.gd"
)
const WORLD_EVENT_REWARD_TYPES := preload(
	"res://scripts/contracts/world_event_reward_types.gd"
)
const WORLD_EVENT_STATES := preload(
	"res://scripts/contracts/world_event_states.gd"
)

const KIND_DEFENSE: String = (
	WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE
)
const KIND_SURVIVAL: String = (
	WORLD_EVENT_KINDS.WORLD_EVENT_KIND_SURVIVAL
)
const KIND_CAPTURE: String = (
	WORLD_EVENT_KINDS.WORLD_EVENT_KIND_CAPTURE
)
const KIND_GOLD_SHRINE: String = (
	WORLD_EVENT_KINDS.WORLD_EVENT_KIND_GOLD_SHRINE
)
const KIND_BLOOD_SHRINE: String = (
	WORLD_EVENT_KINDS.WORLD_EVENT_KIND_BLOOD_SHRINE
)

const STATE_AVAILABLE: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_INACTIVE
)
const STATE_ACTIVE: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_ACTIVE
)
const STATE_SUCCEEDED: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_SUCCEEDED
)
const STATE_FAILED: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_FAILED
)
const STATE_EXHAUSTED: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_EXHAUSTED
)

const CONTINUOUS_KINDS: Array[String] = [
	KIND_DEFENSE,
	KIND_SURVIVAL,
	KIND_CAPTURE,
]
const MAX_SAFE_COST: int = 9_007_199_254_740_991


class EventRuntime:
	var attempts: int = 0
	var blood_uses: int = 0
	var capture_progress: float = 0.0
	var defense_target: WorldEventDefenseTarget = null
	var elapsed: float = 0.0
	var entry_delay_progress: float = 0.0
	var event_id: String = ""
	var instance_id: String = ""
	var interactable: WorldEventInteractable = null
	var kind: String = ""
	var module_slot_id: String = ""
	var next_cost: int = 0
	var pinned: bool = false
	var prepared_reward: Dictionary = {}
	var reward_committed: bool = false
	var state: String = STATE_AVAILABLE
	var successful_mod_ids: Array[String] = []
	var successes: int = 0
	var wave_cursor: int = 0


var _active_continuous_instance_id: String = ""
var _definitions: Dictionary = {}
var _instances: Dictionary = {}
var _mod_pools: Dictionary = {}


func configure(world_event_data: Dictionary) -> void:
	_instances.clear()
	_active_continuous_instance_id = ""
	_definitions.clear()
	_mod_pools.clear()
	_parse_mod_pools(world_event_data.get("mod_pools", []))
	var events_raw: Variant = world_event_data.get(
		"events",
		world_event_data.get("world_events", [])
	)
	if not events_raw is Array:
		push_error("[WorldEventController] events must be an Array")
		return
	for entry_raw: Variant in events_raw:
		if not entry_raw is Dictionary:
			continue
		var definition: Dictionary = (entry_raw as Dictionary).duplicate(true)
		var event_id: String = String(definition.get("id", ""))
		var kind: String = String(definition.get("kind", ""))
		if event_id.is_empty() or not _is_known_kind(kind):
			push_error(
				"[WorldEventController] invalid world event definition: %s"
				% JSON.stringify(definition)
			)
			continue
		_definitions[event_id] = definition


func register_instance(
	instance_id: String,
	event_id: String,
	interactable: WorldEventInteractable,
	module_slot_id: String = "",
	defense_target: WorldEventDefenseTarget = null
) -> bool:
	if instance_id.is_empty() or _instances.has(instance_id):
		return false
	if not _definitions.has(event_id):
		push_error("[WorldEventController] unknown event id: %s" % event_id)
		return false
	if interactable == null or not is_instance_valid(interactable):
		return false

	var definition: Dictionary = _definition(event_id)
	var runtime := EventRuntime.new()
	runtime.instance_id = instance_id
	runtime.event_id = event_id
	runtime.kind = String(definition.get("kind", ""))
	runtime.interactable = interactable
	runtime.module_slot_id = module_slot_id
	runtime.defense_target = (
		defense_target
		if defense_target != null
		else interactable.defense_target()
	)
	if runtime.kind == KIND_GOLD_SHRINE:
		runtime.next_cost = _required_positive_int(definition, "base_cost")
	_instances[instance_id] = runtime

	interactable.configure(instance_id, definition, module_slot_id)
	interactable.set_event_state(runtime.state)
	_apply_usage_visual(runtime, definition)
	if runtime.defense_target != null:
		_configure_defense_target(runtime, definition)
	instance_registered.emit(instance_id, event_id)
	return true


func unregister_instance(instance_id: String) -> void:
	var runtime: EventRuntime = _runtime(instance_id)
	if runtime == null:
		return
	if runtime.pinned:
		module_pin_requested.emit(
			runtime.instance_id,
			runtime.module_slot_id,
			false
		)
	if _active_continuous_instance_id == instance_id:
		_active_continuous_instance_id = ""
	_instances.erase(instance_id)


func tick(delta: float, player: Node, context: Dictionary = {}) -> void:
	var scaled_delta: float = _scaled_delta(delta)
	if scaled_delta <= 0.0:
		return
	var active_ids: Array[String] = []
	for instance_id_raw: Variant in _instances.keys():
		var instance_id: String = String(instance_id_raw)
		var runtime: EventRuntime = _runtime(instance_id)
		if runtime != null and runtime.state == STATE_ACTIVE:
			active_ids.append(instance_id)
	active_ids.sort()
	for instance_id: String in active_ids:
		var runtime: EventRuntime = _runtime(instance_id)
		if runtime == null:
			continue
		var definition: Dictionary = _definition(runtime.event_id)
		match runtime.kind:
			KIND_DEFENSE:
				_tick_defense(runtime, definition, scaled_delta, context)
			KIND_SURVIVAL:
				_tick_survival(runtime, definition, scaled_delta, player, context)
			KIND_CAPTURE:
				_tick_capture(runtime, definition, scaled_delta, player, context)
			_:
				pass


func interact(
	instance_id: String,
	player: Node,
	context: Dictionary = {}
) -> Dictionary:
	var runtime: EventRuntime = _runtime(instance_id)
	if runtime == null:
		return _interaction_result(false, "unknown_instance")
	if runtime.interactable == null or not is_instance_valid(runtime.interactable):
		return _interaction_result(false, "missing_interactable")
	if not runtime.interactable.can_player_interact(player):
		_request_prompt(runtime, "out_of_range", {})
		return _interaction_result(false, "out_of_range")
	var definition: Dictionary = _definition(runtime.event_id)
	match runtime.kind:
		KIND_DEFENSE, KIND_SURVIVAL, KIND_CAPTURE:
			return _interact_continuous(runtime, definition, context)
		KIND_GOLD_SHRINE:
			return _interact_gold_shrine(runtime, definition, context)
		KIND_BLOOD_SHRINE:
			return _interact_blood_shrine(runtime, definition, context)
		_:
			return _interaction_result(false, "unsupported_kind")


func set_prepared_reward(instance_id: String, reward: Dictionary) -> bool:
	var runtime: EventRuntime = _runtime(instance_id)
	if runtime == null or runtime.reward_committed:
		return false
	runtime.prepared_reward = reward.duplicate(true)
	return not runtime.prepared_reward.is_empty()


func release_background_pin(instance_id: String) -> bool:
	var runtime: EventRuntime = _runtime(instance_id)
	if runtime == null or not runtime.pinned:
		return false
	runtime.pinned = false
	module_pin_requested.emit(
		runtime.instance_id,
		runtime.module_slot_id,
		false
	)
	return true


func active_continuous_instance_id() -> String:
	return _active_continuous_instance_id


func definition(event_id: String) -> Dictionary:
	return _definition(event_id).duplicate(true)


func mod_pool(mod_pool_id: String) -> Array[String]:
	if not _mod_pools.has(mod_pool_id):
		return []
	var source: Array[String] = _mod_pools[mod_pool_id]
	return source.duplicate()


func snapshot() -> Dictionary:
	var instance_snapshots: Array[Dictionary] = []
	var instance_ids: Array[String] = []
	for instance_id_raw: Variant in _instances.keys():
		instance_ids.append(String(instance_id_raw))
	instance_ids.sort()
	for instance_id: String in instance_ids:
		var runtime: EventRuntime = _runtime(instance_id)
		if runtime == null:
			continue
		var item: Dictionary = {
			"instance_id": runtime.instance_id,
			"event_id": runtime.event_id,
			"kind": runtime.kind,
			"module_slot_id": runtime.module_slot_id,
			"state": runtime.state,
			"elapsed": runtime.elapsed,
			"wave_cursor": runtime.wave_cursor,
			"entry_delay_progress": runtime.entry_delay_progress,
			"capture_progress": runtime.capture_progress,
			"attempts": runtime.attempts,
			"successes": runtime.successes,
			"next_cost": runtime.next_cost,
			"successful_mod_ids": runtime.successful_mod_ids.duplicate(),
			"blood_uses": runtime.blood_uses,
			"prepared_reward": runtime.prepared_reward.duplicate(true),
			"reward_committed": runtime.reward_committed,
			"pinned": runtime.pinned,
		}
		if (
			runtime.defense_target != null
			and is_instance_valid(runtime.defense_target)
		):
			item["defense_target"] = runtime.defense_target.snapshot()
		instance_snapshots.append(item)
	return {
		"active_continuous_instance_id": _active_continuous_instance_id,
		"instances": instance_snapshots,
	}


func restore_snapshot(snapshot_data: Dictionary) -> Dictionary:
	var restored: int = 0
	var rejected: Array[String] = []
	var instances_raw: Variant = snapshot_data.get("instances", [])
	if not instances_raw is Array:
		return {
			"restored": 0,
			"rejected": ["instances"],
		}
	_active_continuous_instance_id = ""
	for item_raw: Variant in instances_raw:
		if not item_raw is Dictionary:
			continue
		var item: Dictionary = item_raw as Dictionary
		var instance_id: String = String(item.get("instance_id", ""))
		var runtime: EventRuntime = _runtime(instance_id)
		if runtime == null or String(item.get("event_id", "")) != runtime.event_id:
			rejected.append(instance_id)
			continue
		_restore_runtime(runtime, item)
		restored += 1

	var requested_active_id: String = String(
		snapshot_data.get("active_continuous_instance_id", "")
	)
	var active_ids: Array[String] = []
	for instance_id_raw: Variant in _instances.keys():
		var runtime: EventRuntime = _runtime(String(instance_id_raw))
		if (
			runtime != null
			and runtime.state == STATE_ACTIVE
			and CONTINUOUS_KINDS.has(runtime.kind)
		):
			active_ids.append(runtime.instance_id)
	active_ids.sort()
	var selected_active_id: String = ""
	if active_ids.has(requested_active_id):
		selected_active_id = requested_active_id
	elif active_ids.size() == 1:
		selected_active_id = active_ids[0]
	for active_id: String in active_ids:
		if active_id == selected_active_id:
			continue
		var invalid_runtime: EventRuntime = _runtime(active_id)
		if invalid_runtime != null:
			_fail_event(invalid_runtime, "invalid_restore_concurrency")
	_active_continuous_instance_id = selected_active_id
	var selected_runtime: EventRuntime = _runtime(selected_active_id)
	if selected_runtime != null and not selected_runtime.pinned:
		_set_pin(selected_runtime, true)

	return {
		"restored": restored,
		"rejected": rejected,
	}


func debug_summary() -> Dictionary:
	var summaries: Array[Dictionary] = []
	var ids: Array[String] = []
	for instance_id_raw: Variant in _instances.keys():
		ids.append(String(instance_id_raw))
	ids.sort()
	for instance_id: String in ids:
		var runtime: EventRuntime = _runtime(instance_id)
		if runtime == null:
			continue
		var summary: Dictionary = {
			"instance_id": runtime.instance_id,
			"event_id": runtime.event_id,
			"kind": runtime.kind,
			"state": runtime.state,
			"elapsed": runtime.elapsed,
			"wave_cursor": runtime.wave_cursor,
			"entry_delay_progress": runtime.entry_delay_progress,
			"capture_progress": runtime.capture_progress,
			"attempts": runtime.attempts,
			"successes": runtime.successes,
			"next_cost": runtime.next_cost,
			"successful_mod_ids": runtime.successful_mod_ids.duplicate(),
			"blood_uses": runtime.blood_uses,
			"pinned": runtime.pinned,
			"reward_committed": runtime.reward_committed,
		}
		if (
			runtime.defense_target != null
			and is_instance_valid(runtime.defense_target)
		):
			summary["defense_target"] = runtime.defense_target.debug_summary()
		summaries.append(summary)
	return {
		"active_continuous_instance_id": _active_continuous_instance_id,
		"instances": summaries,
	}


func _interact_continuous(
	runtime: EventRuntime,
	definition: Dictionary,
	context: Dictionary
) -> Dictionary:
	if runtime.state != STATE_AVAILABLE:
		_request_prompt(runtime, "not_available", {"state": runtime.state})
		return _interaction_result(false, "not_available")
	if (
		not _active_continuous_instance_id.is_empty()
		and _active_continuous_instance_id != runtime.instance_id
	):
		_request_prompt(
			runtime,
			"continuous_event_busy",
			{"active_instance_id": _active_continuous_instance_id}
		)
		return _interaction_result(false, "continuous_event_busy")

	runtime.state = STATE_ACTIVE
	runtime.elapsed = 0.0
	runtime.wave_cursor = 0
	runtime.entry_delay_progress = 0.0
	runtime.capture_progress = 0.0
	runtime.reward_committed = false
	runtime.prepared_reward.clear()
	_active_continuous_instance_id = runtime.instance_id
	_set_pin(runtime, true)
	if runtime.defense_target != null:
		runtime.defense_target.activate()
	_prepare_reward(runtime, definition, context)
	_apply_runtime_visuals(runtime, definition)
	_emit_state_changed(runtime, "started", {})
	_emit_due_waves(runtime, definition, context)
	return _interaction_result(true, "started")


func _interact_gold_shrine(
	runtime: EventRuntime,
	definition: Dictionary,
	context: Dictionary
) -> Dictionary:
	if runtime.state == STATE_EXHAUSTED:
		_request_prompt(runtime, "exhausted", {})
		return _interaction_result(false, "exhausted")
	if runtime.state != STATE_AVAILABLE:
		return _interaction_result(false, "not_available")

	var spend_callback: Callable = _context_callback(context, "try_spend_gold")
	var chance_callback: Callable = _context_callback(
		context,
		"roll_world_event_chance"
	)
	var mod_callback: Callable = _context_callback(
		context,
		"choose_world_event_mod"
	)
	if (
		not spend_callback.is_valid()
		or not chance_callback.is_valid()
		or not mod_callback.is_valid()
	):
		_request_prompt(runtime, "missing_transaction_callback", {})
		return _interaction_result(false, "missing_transaction_callback")

	var current_cost: int = runtime.next_cost
	if current_cost <= 0:
		return _interaction_result(false, "invalid_cost")
	var spent: bool = bool(
		spend_callback.call(runtime.instance_id, current_cost)
	)
	if not spent:
		_request_prompt(runtime, "insufficient_gold", {"cost": current_cost})
		return _interaction_result(false, "insufficient_gold")

	runtime.attempts += 1
	runtime.next_cost = _next_gold_cost(
		current_cost,
		float(_definition_value(definition, "cost_multiplier", 0.0))
	)
	var success_chance: float = clampf(
		float(_definition_value(definition, "success_chance", 0.0)),
		0.0,
		1.0
	)
	var succeeded: bool = bool(
		chance_callback.call(runtime.instance_id, success_chance)
	)
	if succeeded:
		var pool_id: String = _reward_mod_pool_id(definition)
		var excluded: Array[String] = runtime.successful_mod_ids.duplicate()
		var mod_id: String = String(
			mod_callback.call(runtime.instance_id, pool_id, excluded)
		)
		if mod_id.is_empty() or excluded.has(mod_id):
			succeeded = false
			_request_prompt(runtime, "invalid_mod_selection", {})
		else:
			runtime.successes += 1
			runtime.successful_mod_ids.append(mod_id)
			reward_requested.emit(
				runtime.instance_id,
				runtime.event_id,
				{
					"kind": (
						WORLD_EVENT_REWARD_TYPES
						.WORLD_EVENT_REWARD_GEAR_MOD
					),
					"mod_id": mod_id,
					"pending": true,
					"source": KIND_GOLD_SHRINE,
					"attempt": runtime.attempts,
				}
			)

	var maximum_successes: int = _required_positive_int(
		definition,
		"max_successes"
	)
	if runtime.successes >= maximum_successes:
		runtime.state = STATE_EXHAUSTED
		_emit_state_changed(runtime, "exhausted", {})
	elif runtime.next_cost >= MAX_SAFE_COST:
		runtime.state = STATE_EXHAUSTED
		_emit_state_changed(runtime, "cost_overflow_guard", {})
	else:
		_request_prompt(
			runtime,
			"shrine_success" if succeeded else "shrine_failed",
			{
				"cost": current_cost,
				"next_cost": runtime.next_cost,
				"attempt": runtime.attempts,
				"successes": runtime.successes,
			}
		)
	_apply_runtime_visuals(runtime, definition)
	return {
		"accepted": true,
		"reason": "success" if succeeded else "failed_roll",
		"cost": current_cost,
		"next_cost": runtime.next_cost,
		"successes": runtime.successes,
		"attempts": runtime.attempts,
	}


func _interact_blood_shrine(
	runtime: EventRuntime,
	definition: Dictionary,
	context: Dictionary
) -> Dictionary:
	if runtime.state == STATE_EXHAUSTED:
		_request_prompt(runtime, "exhausted", {})
		return _interaction_result(false, "exhausted")
	if runtime.state != STATE_AVAILABLE:
		return _interaction_result(false, "not_available")
	var ratios: Array[float] = _float_array(
		_definition_value(definition, "sacrifice_ratios", [])
	)
	if runtime.blood_uses < 0 or runtime.blood_uses >= ratios.size():
		runtime.state = STATE_EXHAUSTED
		_apply_runtime_visuals(runtime, definition)
		return _interaction_result(false, "exhausted")
	var sacrifice_callback: Callable = _context_callback(
		context,
		"try_sacrifice_combined_health"
	)
	if not sacrifice_callback.is_valid():
		_request_prompt(runtime, "missing_transaction_callback", {})
		return _interaction_result(false, "missing_transaction_callback")

	var ratio: float = ratios[runtime.blood_uses]
	var result_raw: Variant = sacrifice_callback.call(runtime.instance_id, ratio)
	if not result_raw is Dictionary:
		return _interaction_result(false, "invalid_transaction_result")
	var transaction: Dictionary = result_raw as Dictionary
	if not bool(transaction.get("accepted", false)):
		_request_prompt(
			runtime,
			String(transaction.get("reason", "insufficient_combined_health")),
			{"ratio": ratio}
		)
		return _interaction_result(false, String(
			transaction.get("reason", "insufficient_combined_health")
		))
	var actual_spent: float = maxf(
		float(transaction.get("actual_spent", 0.0)),
		0.0
	)
	if actual_spent <= 0.0:
		return _interaction_result(false, "invalid_spent_amount")

	runtime.blood_uses += 1
	var gold_ratio: float = maxf(
		float(_definition_value(definition, "gold_ratio", 0.0)),
		0.0
	)
	var gold_amount: int = maxi(int(floor(actual_spent * gold_ratio)), 0)
	reward_requested.emit(
		runtime.instance_id,
		runtime.event_id,
		{
			"kind": WORLD_EVENT_REWARD_TYPES.WORLD_EVENT_REWARD_GOLD,
			"amount": gold_amount,
			"pending": false,
			"source": KIND_BLOOD_SHRINE,
			"use_index": runtime.blood_uses,
		}
	)
	if runtime.blood_uses >= ratios.size():
		runtime.state = STATE_EXHAUSTED
		_emit_state_changed(runtime, "exhausted", {})
	else:
		_request_prompt(
			runtime,
			"sacrifice_completed",
			{
				"ratio": ratio,
				"actual_spent": actual_spent,
				"gold_amount": gold_amount,
			}
		)
	_apply_runtime_visuals(runtime, definition)
	return {
		"accepted": true,
		"reason": "sacrifice_completed",
		"ratio": ratio,
		"actual_spent": actual_spent,
		"gold_amount": gold_amount,
		"uses": runtime.blood_uses,
	}


func _tick_defense(
	runtime: EventRuntime,
	definition: Dictionary,
	delta: float,
	context: Dictionary
) -> void:
	if (
		runtime.defense_target == null
		or not is_instance_valid(runtime.defense_target)
		or not runtime.defense_target.is_alive()
	):
		_fail_event(runtime, "defense_target_defeated")
		return
	runtime.elapsed += delta
	_emit_due_waves(runtime, definition, context)
	var duration: float = _required_positive_float(definition, "duration")
	if duration > 0.0 and runtime.elapsed >= duration:
		_succeed_event(runtime)


func _tick_survival(
	runtime: EventRuntime,
	definition: Dictionary,
	delta: float,
	player: Node,
	context: Dictionary
) -> void:
	if not _player_is_alive(player, context):
		_fail_event(runtime, "player_defeated")
		return
	runtime.elapsed += delta
	_emit_due_waves(runtime, definition, context)
	var duration: float = _required_positive_float(definition, "duration")
	if duration > 0.0 and runtime.elapsed >= duration:
		_succeed_event(runtime)


func _tick_capture(
	runtime: EventRuntime,
	definition: Dictionary,
	delta: float,
	player: Node,
	context: Dictionary
) -> void:
	runtime.elapsed += delta
	var timeout: float = _required_positive_float(definition, "timeout")
	if timeout > 0.0 and runtime.elapsed >= timeout:
		_fail_event(runtime, "capture_timeout")
		return

	var entry_delay: float = _required_positive_float(definition, "entry_delay")
	var capture_duration: float = _required_positive_float(
		definition,
		"capture_duration"
	)
	var inside: bool = (
		runtime.interactable != null
		and is_instance_valid(runtime.interactable)
		and runtime.interactable.contains_player(player)
	)
	if inside:
		var remaining_delta: float = delta
		if runtime.entry_delay_progress < entry_delay:
			var delay_delta: float = minf(
				remaining_delta,
				entry_delay - runtime.entry_delay_progress
			)
			runtime.entry_delay_progress += delay_delta
			remaining_delta -= delay_delta
		if (
			runtime.entry_delay_progress >= entry_delay
			and remaining_delta > 0.0
		):
			runtime.capture_progress = minf(
				runtime.capture_progress + remaining_delta,
				capture_duration
			)
	else:
		var decay_rate: float = maxf(
			float(_definition_value(definition, "entry_delay_decay", 0.0)),
			0.0
		)
		runtime.entry_delay_progress = maxf(
			runtime.entry_delay_progress - delta * decay_rate,
			0.0
		)

	_emit_due_waves(runtime, definition, context)
	_apply_runtime_visuals(runtime, definition)
	if capture_duration > 0.0 and runtime.capture_progress >= capture_duration:
		_succeed_event(runtime)


func _prepare_reward(
	runtime: EventRuntime,
	definition: Dictionary,
	context: Dictionary
) -> void:
	var reward_config: Dictionary = _reward_config(definition)
	var callback: Callable = _context_callback(
		context,
		"prepare_world_event_reward"
	)
	if callback.is_valid():
		var reward_raw: Variant = callback.call(
			runtime.instance_id,
			runtime.event_id,
			reward_config.duplicate(true)
		)
		if reward_raw is Dictionary:
			runtime.prepared_reward = (reward_raw as Dictionary).duplicate(true)
	if runtime.prepared_reward.is_empty():
		reward_plan_requested.emit(
			runtime.instance_id,
			runtime.event_id,
			reward_config.duplicate(true)
		)
	if runtime.prepared_reward.is_empty():
		runtime.prepared_reward = {
			"kind": "unresolved",
			"config": reward_config.duplicate(true),
		}


func _succeed_event(runtime: EventRuntime) -> void:
	if runtime.state != STATE_ACTIVE:
		return
	runtime.state = STATE_SUCCEEDED
	if runtime.defense_target != null:
		runtime.defense_target.deactivate()
	_release_continuous_slot(runtime)
	_commit_prepared_reward(runtime)
	_apply_runtime_visuals(runtime, _definition(runtime.event_id))
	_emit_state_changed(runtime, "completed", {})
	terminal_cleanup_requested.emit(
		runtime.instance_id,
		runtime.event_id,
		{"state": runtime.state}
	)


func _fail_event(runtime: EventRuntime, reason: String) -> void:
	if runtime.state != STATE_ACTIVE:
		return
	runtime.state = STATE_FAILED
	if runtime.defense_target != null:
		runtime.defense_target.deactivate()
	_release_continuous_slot(runtime)
	_apply_runtime_visuals(runtime, _definition(runtime.event_id))
	_emit_state_changed(runtime, reason, {})
	terminal_cleanup_requested.emit(
		runtime.instance_id,
		runtime.event_id,
		{
			"state": runtime.state,
			"reason": reason,
		}
	)


func _release_continuous_slot(runtime: EventRuntime) -> void:
	if _active_continuous_instance_id == runtime.instance_id:
		_active_continuous_instance_id = ""


func _commit_prepared_reward(runtime: EventRuntime) -> void:
	if runtime.reward_committed:
		return
	runtime.reward_committed = true
	var reward: Dictionary = runtime.prepared_reward.duplicate(true)
	reward["source"] = runtime.kind
	reward["event_id"] = runtime.event_id
	reward_requested.emit(runtime.instance_id, runtime.event_id, reward)


func _emit_due_waves(
	runtime: EventRuntime,
	definition: Dictionary,
	context: Dictionary
) -> void:
	var waves: Array[Dictionary] = _waves(definition)
	while runtime.wave_cursor < waves.size():
		var wave: Dictionary = waves[runtime.wave_cursor]
		var trigger: float = maxf(float(wave.get("trigger", 0.0)), 0.0)
		var progress: float = (
			runtime.capture_progress
			if runtime.kind == KIND_CAPTURE
			else runtime.elapsed
		)
		if progress + 0.000001 < trigger:
			break
		var count: int = maxi(int(wave.get("count", 0)), 0)
		var target: Node = (
			runtime.defense_target
			if runtime.kind == KIND_DEFENSE
			else null
		)
		var wave_index: int = runtime.wave_cursor
		runtime.wave_cursor += 1
		wave_requested.emit(
			runtime.instance_id,
			runtime.event_id,
			wave_index,
			count,
			_runtime_world_position(runtime),
			target,
			{
				"kind": runtime.kind,
				"module_slot_id": runtime.module_slot_id,
				"definition": definition.duplicate(true),
				"wave": wave.duplicate(true),
				"tick_context": context,
			}
		)


func _configure_defense_target(
	runtime: EventRuntime,
	definition: Dictionary
) -> void:
	if runtime.defense_target == null:
		return
	var target_max_health: float = _required_positive_float(
		definition,
		"target_max_health"
	)
	var target_hit_radius: float = _required_positive_float(
		definition,
		"target_hit_radius"
	)
	var target_group: String = String(
		_definition_value(
			definition,
			"target_group",
			WorldEventDefenseTarget.DEFAULT_ACTIVE_GROUP
		)
	)
	runtime.defense_target.configure(
		runtime.instance_id,
		target_max_health,
		target_hit_radius,
		target_group
	)
	var defeated_callback: Callable = _on_defense_target_defeated.bind(
		runtime.instance_id
	)
	if not runtime.defense_target.defeated.is_connected(defeated_callback):
		runtime.defense_target.defeated.connect(defeated_callback)


func _on_defense_target_defeated(
	_target: WorldEventDefenseTarget,
	instance_id: String
) -> void:
	var runtime: EventRuntime = _runtime(instance_id)
	if runtime != null:
		_fail_event(runtime, "defense_target_defeated")


func _restore_runtime(runtime: EventRuntime, item: Dictionary) -> void:
	var definition: Dictionary = _definition(runtime.event_id)
	runtime.state = String(item.get("state", STATE_AVAILABLE))
	if runtime.state not in [
		STATE_AVAILABLE,
		STATE_ACTIVE,
		STATE_SUCCEEDED,
		STATE_FAILED,
		STATE_EXHAUSTED,
	]:
		runtime.state = STATE_FAILED
	runtime.elapsed = maxf(float(item.get("elapsed", 0.0)), 0.0)
	runtime.wave_cursor = clampi(
		int(item.get("wave_cursor", 0)),
		0,
		_waves(definition).size()
	)
	runtime.entry_delay_progress = clampf(
		float(item.get("entry_delay_progress", 0.0)),
		0.0,
		_required_positive_float(definition, "entry_delay")
	)
	runtime.capture_progress = clampf(
		float(item.get("capture_progress", 0.0)),
		0.0,
		_required_positive_float(definition, "capture_duration")
	)
	runtime.attempts = maxi(int(item.get("attempts", 0)), 0)
	runtime.successes = maxi(int(item.get("successes", 0)), 0)
	runtime.next_cost = clampi(
		int(item.get("next_cost", runtime.next_cost)),
		0,
		MAX_SAFE_COST
	)
	runtime.successful_mod_ids = _string_array(
		item.get("successful_mod_ids", [])
	)
	runtime.blood_uses = maxi(int(item.get("blood_uses", 0)), 0)
	runtime.prepared_reward = _dictionary(
		item.get("prepared_reward", {})
	).duplicate(true)
	runtime.reward_committed = bool(item.get("reward_committed", false))
	runtime.pinned = bool(item.get("pinned", false))
	if runtime.kind == KIND_GOLD_SHRINE:
		var maximum_successes: int = _required_positive_int(
			definition,
			"max_successes"
		)
		runtime.successes = mini(runtime.successes, maximum_successes)
		runtime.attempts = maxi(runtime.attempts, runtime.successes)
		if runtime.successful_mod_ids.size() > runtime.successes:
			runtime.successful_mod_ids.resize(runtime.successes)
		if runtime.successes >= maximum_successes:
			runtime.state = STATE_EXHAUSTED
	elif runtime.kind == KIND_BLOOD_SHRINE:
		var maximum_uses: int = _float_array(
			_definition_value(definition, "sacrifice_ratios", [])
		).size()
		runtime.blood_uses = mini(runtime.blood_uses, maximum_uses)
		if runtime.blood_uses >= maximum_uses:
			runtime.state = STATE_EXHAUSTED
	elif runtime.reward_committed and runtime.state == STATE_ACTIVE:
		runtime.state = STATE_FAILED
	if not CONTINUOUS_KINDS.has(runtime.kind):
		runtime.pinned = false
	if (
		runtime.defense_target != null
		and item.get("defense_target", {}) is Dictionary
	):
		runtime.defense_target.restore_snapshot(
			item.get("defense_target", {}) as Dictionary
		)
		if (
			runtime.state == STATE_ACTIVE
			and runtime.defense_target.is_alive()
		):
			runtime.defense_target.activate()
		else:
			runtime.defense_target.deactivate()
	_apply_runtime_visuals(runtime, definition)
	if runtime.pinned:
		module_pin_requested.emit(
			runtime.instance_id,
			runtime.module_slot_id,
			true
		)


func _apply_runtime_visuals(
	runtime: EventRuntime,
	definition: Dictionary
) -> void:
	if runtime.interactable == null or not is_instance_valid(runtime.interactable):
		return
	runtime.interactable.set_event_state(runtime.state)
	var entry_delay: float = _required_positive_float(definition, "entry_delay")
	var capture_duration: float = _required_positive_float(
		definition,
		"capture_duration"
	)
	runtime.interactable.set_capture_progress(
		runtime.entry_delay_progress / entry_delay if entry_delay > 0.0 else 0.0,
		runtime.capture_progress / capture_duration if capture_duration > 0.0 else 0.0,
		runtime.state == STATE_ACTIVE
	)
	_apply_usage_visual(runtime, definition)


func _apply_usage_visual(
	runtime: EventRuntime,
	definition: Dictionary
) -> void:
	if runtime.interactable == null or not is_instance_valid(runtime.interactable):
		return
	match runtime.kind:
		KIND_GOLD_SHRINE:
			runtime.interactable.set_usage_progress(
				runtime.successes,
				_required_positive_int(definition, "max_successes")
			)
		KIND_BLOOD_SHRINE:
			runtime.interactable.set_usage_progress(
				runtime.blood_uses,
				_float_array(
					_definition_value(definition, "sacrifice_ratios", [])
				).size()
			)


func _set_pin(runtime: EventRuntime, pinned: bool) -> void:
	if runtime.pinned == pinned:
		return
	runtime.pinned = pinned
	module_pin_requested.emit(
		runtime.instance_id,
		runtime.module_slot_id,
		pinned
	)


func _emit_state_changed(
	runtime: EventRuntime,
	reason: String,
	extra: Dictionary
) -> void:
	var context: Dictionary = extra.duplicate(true)
	context["reason"] = reason
	context["kind"] = runtime.kind
	context["module_slot_id"] = runtime.module_slot_id
	state_changed.emit(
		runtime.instance_id,
		runtime.event_id,
		runtime.state,
		context
	)


func _request_prompt(
	runtime: EventRuntime,
	reason: String,
	extra: Dictionary
) -> void:
	var context: Dictionary = extra.duplicate(true)
	context["state"] = runtime.state
	context["kind"] = runtime.kind
	context["name_key"] = String(
		_definition(runtime.event_id).get("name_key", "")
	)
	prompt_requested.emit(
		runtime.instance_id,
		runtime.event_id,
		reason,
		context
	)


func _runtime(instance_id: String) -> EventRuntime:
	if not _instances.has(instance_id):
		return null
	var value: Variant = _instances[instance_id]
	return value as EventRuntime


func _definition(event_id: String) -> Dictionary:
	if not _definitions.has(event_id):
		return {}
	var value: Variant = _definitions[event_id]
	return value as Dictionary


func _definition_value(
	definition: Dictionary,
	key: String,
	fallback: Variant
) -> Variant:
	if definition.has(key):
		return definition[key]
	var rules_raw: Variant = definition.get("rules", {})
	if rules_raw is Dictionary:
		var rules: Dictionary = rules_raw as Dictionary
		if rules.has(key):
			return rules[key]
	return fallback


func _reward_config(definition: Dictionary) -> Dictionary:
	var raw: Variant = definition.get(
		"completion_reward",
		definition.get("reward", {})
	)
	return _dictionary(raw).duplicate(true)


func _reward_mod_pool_id(definition: Dictionary) -> String:
	var reward: Dictionary = _reward_config(definition)
	if reward.has("mod_pool_id"):
		return String(reward.get("mod_pool_id", ""))
	return String(_definition_value(definition, "mod_pool_id", ""))


func _waves(definition: Dictionary) -> Array[Dictionary]:
	var waves_raw: Variant = _definition_value(definition, "waves", [])
	var result: Array[Dictionary] = []
	if not waves_raw is Array:
		return result
	for wave_raw: Variant in waves_raw:
		if wave_raw is Dictionary:
			result.append((wave_raw as Dictionary).duplicate(true))
	result.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return float(left.get("trigger", 0.0)) < float(right.get("trigger", 0.0))
	)
	return result


func _parse_mod_pools(raw_pools: Variant) -> void:
	if not raw_pools is Array:
		return
	for pool_raw: Variant in raw_pools:
		if not pool_raw is Dictionary:
			continue
		var pool: Dictionary = pool_raw as Dictionary
		var pool_id: String = String(pool.get("id", ""))
		if pool_id.is_empty():
			continue
		_mod_pools[pool_id] = _string_array(pool.get("mod_ids", []))


func _player_is_alive(player: Node, context: Dictionary) -> bool:
	var callback: Callable = _context_callback(context, "player_is_alive")
	if callback.is_valid():
		return bool(callback.call(player))
	if player == null or not is_instance_valid(player):
		return false
	if player.has_method("is_alive"):
		return bool(player.call("is_alive"))
	if player.has_method("current_life"):
		return float(player.call("current_life")) > 0.0
	return true


func _runtime_world_position(runtime: EventRuntime) -> Vector2:
	if runtime.interactable == null or not is_instance_valid(runtime.interactable):
		return Vector2.ZERO
	return runtime.interactable.global_position


func _next_gold_cost(current_cost: int, multiplier: float) -> int:
	if current_cost <= 0 or multiplier <= 1.0:
		return MAX_SAFE_COST
	var next_value: float = ceil(float(current_cost) * multiplier)
	if not is_finite(next_value) or next_value >= float(MAX_SAFE_COST):
		return MAX_SAFE_COST
	return maxi(int(next_value), current_cost + 1)


func _required_positive_float(
	definition: Dictionary,
	key: String
) -> float:
	return maxf(float(_definition_value(definition, key, 0.0)), 0.0)


func _required_positive_int(
	definition: Dictionary,
	key: String
) -> int:
	return maxi(int(_definition_value(definition, key, 0)), 0)


func _context_callback(context: Dictionary, key: String) -> Callable:
	var value: Variant = context.get(key)
	if value is Callable:
		return value
	return Callable()


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value:
		var text: String = String(item)
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


func _float_array(value: Variant) -> Array[float]:
	var result: Array[float] = []
	if not value is Array:
		return result
	for item: Variant in value:
		result.append(float(item))
	return result


func _is_known_kind(kind: String) -> bool:
	return kind in [
		KIND_DEFENSE,
		KIND_SURVIVAL,
		KIND_CAPTURE,
		KIND_GOLD_SHRINE,
		KIND_BLOOD_SHRINE,
	]


func _interaction_result(accepted: bool, reason: String) -> Dictionary:
	return {
		"accepted": accepted,
		"reason": reason,
	}


func _scaled_delta(delta: float) -> float:
	var clock: Node = get_node_or_null("/root/GameClock")
	if clock != null and clock.has_method("delta_scaled"):
		return float(clock.call("delta_scaled", delta))
	return delta
