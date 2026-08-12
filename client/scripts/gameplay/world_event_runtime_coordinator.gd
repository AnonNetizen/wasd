# Doc: docs/代码/gameplay_runtime.md
class_name WorldEventRuntimeCoordinator
extends Node


const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const DAMAGE_TARGET_GROUPS := preload(
	"res://scripts/contracts/damage_target_groups.gd"
)
const GOLD_TRANSACTION_REASONS := preload(
	"res://scripts/contracts/gold_transaction_reasons.gd"
)
const MODULE_PLACEMENT_TYPES := preload(
	"res://scripts/contracts/module_placement_types.gd"
)
const WORLD_EVENT_IDS := preload(
	"res://scripts/contracts/world_event_ids.gd"
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
const WORLD_EVENT_DEFENSE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_defense.tscn"
)
const WORLD_EVENT_SURVIVAL_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_survival.tscn"
)
const WORLD_EVENT_CAPTURE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_capture.tscn"
)
const WORLD_EVENT_GOLD_SHRINE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_gold_shrine.tscn"
)
const WORLD_EVENT_BLOOD_SHRINE_SCENE := preload(
	"res://scenes/gameplay/world_events/world_event_blood_shrine.tscn"
)


class Bindings extends RefCounted:
	var player_port: Callable = Callable()
	var module_world_port: Callable = Callable()
	var spawn_port: Callable = Callable()
	var reward_port: Callable = Callable()
	var ui_port: Callable = Callable()
	var record_port: Callable = Callable()
	var chance_roll_port: Callable = Callable()
	var random_index_port: Callable = Callable()
	var weighted_pick_port: Callable = Callable()
	var active_world_port: Callable = Callable()
	var hud_port: Callable = Callable()
	var module_definition_port: Callable = Callable()
	var controller_port: Callable = Callable()
	var difficulty_elapsed_port: Callable = Callable()
	var spawn_difficulty_port: Callable = Callable()
	var eligible_enemy_pool_port: Callable = Callable()
	var spawn_enemy_port: Callable = Callable()
	var module_slot_key_port: Callable = Callable()
	var spawn_gear_mod_port: Callable = Callable()
	var gear_mod_positions_port: Callable = Callable()
	var dictionary_port: Callable = Callable()
	var array_port: Callable = Callable()
	var vector_port: Callable = Callable()
	var vector_dictionary_port: Callable = Callable()
	var dictionary_array_port: Callable = Callable()
	var content_ids_port: Callable = Callable()
	var add_gold_port: Callable = Callable()
	var spend_gold_port: Callable = Callable()


var bindings: Bindings = null
var controller: WorldEventController = null
var host: Node2D = null
var nodes: Dictionary = {}
var module_coords: Dictionary = {}
var wave_plans: Dictionary = {}


func configure(value: Bindings) -> void:
	bindings = value


func clear_state() -> void:
	controller = null
	host = null
	nodes.clear()
	module_coords.clear()
	wave_plans.clear()


var _active_world: Node2D:
	get:
		return bindings.active_world_port.call() as Node2D
var _hud: CanvasLayer:
	get:
		return bindings.hud_port.call() as CanvasLayer
var _module_world_definition: Dictionary:
	get:
		return bindings.module_definition_port.call() as Dictionary
var _module_world_manager: Node2D:
	get:
		return bindings.module_world_port.call() as Node2D
var _player: CharacterBody2D:
	get:
		return bindings.player_port.call() as CharacterBody2D


func _difficulty_elapsed() -> float:
	return float(bindings.difficulty_elapsed_port.call())


func _enemy_spawn_difficulty() -> Dictionary:
	return bindings.spawn_difficulty_port.call() as Dictionary


func _eligible_first_visit_enemy_pool(
	config: Dictionary,
	elapsed_time: float
) -> Dictionary:
	return bindings.eligible_enemy_pool_port.call(config, elapsed_time) as Dictionary


func _spawn_enemy_at(
	enemy_id: String,
	spawn_position: Vector2,
	spawn_key: String,
	module_slot: String = "",
	spawn_context: Dictionary = {},
	fixed_spawn_difficulty: Dictionary = {}
) -> bool:
	return bool(bindings.spawn_enemy_port.call(
		enemy_id,
		spawn_position,
		spawn_key,
		module_slot,
		spawn_context,
		fixed_spawn_difficulty
	))


func _module_slot_key(module_coord: Vector2i) -> String:
	return String(bindings.module_slot_key_port.call(module_coord))


func _spawn_gear_mod_pickup(
	mod_id: String,
	spawn_position: Vector2
) -> Dictionary:
	return bindings.spawn_gear_mod_port.call(
		mod_id,
		spawn_position
	) as Dictionary


func _gear_mod_reward_positions(
	source_position: Vector2,
	count: int
) -> Array[Vector2]:
	return bindings.gear_mod_positions_port.call(
		source_position,
		count
	) as Array[Vector2]


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	return bindings.dictionary_port.call(raw_value) as Dictionary


func _array_or_empty(raw_value: Variant) -> Array:
	return bindings.array_port.call(raw_value) as Array


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	return bindings.vector_port.call(raw_value, fallback) as Vector2


func _vector_to_dict(value: Vector2) -> Dictionary:
	return bindings.vector_dictionary_port.call(value) as Dictionary


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	return bindings.dictionary_array_port.call(raw_value) as Array[Dictionary]


func _available_content_ids(content_type: String) -> Array[String]:
	return bindings.content_ids_port.call(content_type) as Array[String]


func add_gold(amount: int, reason: String) -> Dictionary:
	return bindings.add_gold_port.call(amount, reason) as Dictionary


func try_spend_gold(amount: int, reason: String) -> Dictionary:
	return bindings.spend_gold_port.call(amount, reason) as Dictionary


func debug_world_event_summary() -> Dictionary:
	if controller == null:
		return {}
	var summary: Dictionary = (
		controller.debug_summary()
	)
	summary["registered_node_count"] = (
		nodes.size()
	)
	summary["wave_plan_count"] = (
		wave_plans.size()
	)
	return summary

func debug_interact_world_event(
	instance_id: String
) -> Dictionary:
	if controller == null:
		return {
			"accepted": false,
			"reason": "controller_unavailable",
		}
	return controller.interact(
		instance_id,
		_player,
		_world_event_context()
	)

func _configure_world_event_controller() -> bool:
	_clear_world_events()
	host = (
		_active_world.get_node_or_null("WorldEventHost") as Node2D
	)
	controller = (
		bindings.controller_port.call()
		as WorldEventController
	)
	if host == null or controller == null:
		return false
	controller.configure(
		_dictionary_or_empty(
			DataLoader.load_json(DataLoader.WORLD_EVENTS_PATH)
		)
	)
	controller.set_reward_delivery_handler(
		_deliver_world_event_reward
	)
	controller.wave_requested.connect(
		_on_world_event_wave_requested
	)
	controller.prompt_requested.connect(
		_on_world_event_prompt_requested
	)
	controller.state_changed.connect(
		_on_world_event_state_changed
	)
	controller.module_pin_requested.connect(
		_on_world_event_module_pin_requested
	)
	controller.terminal_cleanup_requested.connect(
		_on_world_event_terminal_cleanup_requested
	)
	for event_id: String in WORLD_EVENT_IDS.VALUES:
		if controller.definition(event_id).is_empty():
			return false
	return true

func _clear_world_events() -> void:
	nodes.clear()
	module_coords.clear()
	wave_plans.clear()
	if host != null and is_instance_valid(host):
		for child: Node in host.get_children():
			child.queue_free()
	controller = null
	host = null

func _register_all_module_world_events() -> void:
	if (
		_module_world_manager == null
		or controller == null
		or host == null
		or not nodes.is_empty()
	):
		return
	for row_index: int in range(9):
		for column_index: int in range(9):
			var module_coord := Vector2i(
				column_index,
				row_index
			)
			var placements: Array[Dictionary] = (
				_module_world_manager.call(
					"placements_at",
					module_coord
				)
			)
			for placement: Dictionary in placements:
				if (
					String(placement.get("type", ""))
					!= MODULE_PLACEMENT_TYPES
					.MODULE_PLACE_WORLD_EVENT
				):
					continue
				_register_module_world_event(
					module_coord,
					placement
				)

func _register_module_world_event(
	module_coord: Vector2i,
	placement: Dictionary
) -> void:
	var event_id: String = String(
		placement.get("world_event_id", "")
	)
	var scene: PackedScene = _world_event_scene(event_id)
	if scene == null:
		push_error(
			"[GameplayRunLoop] missing world-event scene: %s"
			% event_id
		)
		return
	var instance_id: String = "world_event_%d_%d_%s" % [
		module_coord.x,
		module_coord.y,
		event_id,
	]
	var raw_node: Node = scene.instantiate()
	if not raw_node is WorldEventInteractable:
		raw_node.queue_free()
		push_error(
			"[GameplayRunLoop] world-event scene root is invalid: %s"
			% event_id
		)
		return
	var interactable: WorldEventInteractable = (
		raw_node as WorldEventInteractable
	)
	host.add_child(interactable)
	interactable.global_position = _dict_to_vector(
		placement.get("world_position", {}),
		Vector2.ZERO
	)
	var slot_key: String = _module_slot_key(module_coord)
	if not controller.register_instance(
		instance_id,
		event_id,
		interactable,
		slot_key,
		interactable.defense_target()
	):
		interactable.queue_free()
		return
	nodes[instance_id] = interactable
	module_coords[instance_id] = module_coord

func _world_event_scene(event_id: String) -> PackedScene:
	match event_id:
		WORLD_EVENT_IDS.WORLD_EVENT_DEFENSE:
			return WORLD_EVENT_DEFENSE_SCENE
		WORLD_EVENT_IDS.WORLD_EVENT_SURVIVAL:
			return WORLD_EVENT_SURVIVAL_SCENE
		WORLD_EVENT_IDS.WORLD_EVENT_CAPTURE:
			return WORLD_EVENT_CAPTURE_SCENE
		WORLD_EVENT_IDS.WORLD_EVENT_GOLD_SHRINE:
			return WORLD_EVENT_GOLD_SHRINE_SCENE
		WORLD_EVENT_IDS.WORLD_EVENT_BLOOD_SHRINE:
			return WORLD_EVENT_BLOOD_SHRINE_SCENE
		_:
			return null

func _world_event_context() -> Dictionary:
	return {
		"try_spend_gold": Callable(
			self,
			"_world_event_try_spend_gold"
		),
		"roll_world_event_chance": Callable(
			self,
			"_roll_world_event_chance"
		),
		"choose_world_event_mod": Callable(
			self,
			"_choose_world_event_mod"
		),
		"try_sacrifice_combined_health": Callable(
			self,
			"_world_event_try_sacrifice"
		),
		"prepare_world_event_reward": Callable(
			self,
			"_prepare_world_event_reward"
		),
		"player_is_alive": Callable(
			self,
			"_world_event_player_is_alive"
		),
	}

func _world_event_try_spend_gold(
	_instance_id: String,
	amount: int
) -> bool:
	return bool(
		try_spend_gold(
			amount,
			GOLD_TRANSACTION_REASONS.EVENT_COST
		).get("ok", false)
	)

func _roll_world_event_chance(
	_instance_id: String,
	chance: float
) -> bool:
	return bool(bindings.chance_roll_port.call(chance))

func _choose_world_event_mod(
	_instance_id: String,
	pool_id: String,
	excluded: Array[String]
) -> String:
	var candidates: Array[String] = []
	for mod_id: String in GearModSystem.reward_pool_ids(
		pool_id,
		_available_content_ids(CONTENT_UNLOCK_TYPES.GEAR_MOD)
	):
		if not excluded.has(mod_id):
			candidates.append(mod_id)
	if candidates.is_empty():
		return ""
	return candidates[int(bindings.random_index_port.call(candidates.size()))]

func _world_event_try_sacrifice(
	_instance_id: String,
	ratio: float
) -> Dictionary:
	if (
		_player == null
		or not _player.has_method(
			"try_sacrifice_combined_health"
		)
	):
		return {
			"accepted": false,
			"reason": "player_unavailable",
		}
	var sacrifice_amount: float = (
		float(_player.call("max_life"))
		+ float(_player.call("max_shield"))
	) * clampf(ratio, 0.0, 1.0)
	var result: Dictionary = _player.call(
		"try_sacrifice_combined_health",
		sacrifice_amount,
		1.0
	) as Dictionary
	return {
		"accepted": bool(result.get("ok", false)),
		"reason": String(
			result.get(
				"reason",
				"insufficient_combined_health"
			)
		),
		"actual_spent": float(result.get("spent", 0.0)),
	}

func _world_event_player_is_alive(_target: Node = null) -> bool:
	return (
		_player != null
		and _player.has_method("is_alive")
		and bool(_player.call("is_alive"))
	)

func _prepare_world_event_reward(
	instance_id: String,
	event_id: String,
	reward_config: Dictionary
) -> Dictionary:
	if not wave_plans.has(instance_id):
		wave_plans[instance_id] = (
			_build_world_event_wave_plan(
				instance_id,
				event_id
			)
		)
	var pool_id: String = String(
		reward_config.get("mod_pool_id", "")
	)
	var mod_id: String = _choose_world_event_mod(
		instance_id,
		pool_id,
		[]
	)
	if mod_id.is_empty():
		return {}
	return {
		"kind": (
			WORLD_EVENT_REWARD_TYPES
			.WORLD_EVENT_REWARD_GEAR_MOD
		),
		"mod_id": mod_id,
		"pending": false,
	}

func _build_world_event_wave_plan(
	instance_id: String,
	event_id: String
) -> Dictionary:
	if (
		controller == null
		or not module_coords.has(instance_id)
	):
		return {}
	var definition: Dictionary = (
		controller.definition(event_id)
	)
	var module_coord: Vector2i = (
		module_coords[instance_id] as Vector2i
	)
	var event_node: Node2D = (
		nodes.get(instance_id) as Node2D
	)
	if event_node == null:
		return {}
	var all_positions: Array[Vector2] = []
	var raw_positions: Variant = _module_world_manager.call(
		"empty_floor_positions_at",
		module_coord
	)
	var exclusion_radius: float = maxf(
		float(definition.get("interaction_radius", 0.0)),
		1.0
	) * 1.5
	if raw_positions is Array:
		for raw_position: Variant in raw_positions as Array:
			if (
				raw_position is Vector2
				and (
					raw_position as Vector2
				).distance_to(event_node.global_position)
				> exclusion_radius
			):
				all_positions.append(raw_position as Vector2)
	var waves: Array[Dictionary] = _typed_dictionary_array(
		definition.get("waves", [])
	)
	var planned_waves: Array[Array] = []
	var enemy_pool: Dictionary = (
		_eligible_first_visit_enemy_pool(
			_dictionary_or_empty(
				_module_world_definition.get(
					"first_visit_enemy_spawn",
					{}
				)
			),
			_difficulty_elapsed()
		)
	)
	var enemy_ids: Array = enemy_pool.get("enemy_ids", []) as Array
	var weights: Array = enemy_pool.get("weights", []) as Array
	for wave: Dictionary in waves:
		var wave_spawns: Array = []
		var count: int = maxi(int(wave.get("count", 0)), 0)
		for _spawn_index: int in range(count):
			if all_positions.is_empty() or enemy_ids.is_empty():
				break
			var position_index: int = int(
				bindings.random_index_port.call(all_positions.size())
			)
			var spawn_position: Vector2 = all_positions[
				position_index
			]
			all_positions.remove_at(position_index)
			var enemy_id: String = String(
				bindings.weighted_pick_port.call(enemy_ids, weights)
			)
			wave_spawns.append({
				"enemy_id": enemy_id,
				"world_position": _vector_to_dict(
					spawn_position
				),
			})
		planned_waves.append(wave_spawns)
	return {
		"event_id": event_id,
		"module_slot": _module_slot_key(module_coord),
		"difficulty": _enemy_spawn_difficulty(),
		"waves": planned_waves,
	}

func _on_world_event_wave_requested(
	instance_id: String,
	_event_id: String,
	wave_index: int,
	_enemy_count: int,
	_world_position: Vector2,
	_primary_target: Node,
	_context: Dictionary
) -> void:
	var plan: Dictionary = _dictionary_or_empty(
		wave_plans.get(instance_id, {})
	)
	var planned_waves: Array = _array_or_empty(
		plan.get("waves", [])
	)
	if wave_index < 0 or wave_index >= planned_waves.size():
		return
	var module_slot: String = String(
		plan.get("module_slot", "")
	)
	var spawn_context: Dictionary = (
		_world_event_spawn_context(instance_id)
	)
	var fixed_difficulty: Dictionary = _dictionary_or_empty(
		plan.get("difficulty", {})
	)
	var wave_key: String = "world_event_%s_%d" % [
		instance_id,
		wave_index,
	]
	for raw_spawn: Variant in _array_or_empty(
		planned_waves[wave_index]
	):
		if not raw_spawn is Dictionary:
			continue
		var spawn: Dictionary = raw_spawn as Dictionary
		_spawn_enemy_at(
			String(spawn.get("enemy_id", "")),
			_dict_to_vector(
				spawn.get("world_position", {}),
				Vector2.ZERO
			),
			wave_key,
			module_slot,
			spawn_context,
			fixed_difficulty
		)

func _world_event_spawn_context(
	instance_id: String,
	use_event_primary: bool = true
) -> Dictionary:
	if instance_id.is_empty():
		return {}
	var result: Dictionary = {
		"event_instance_id": instance_id,
		"reward_specialization_multiplier": 1.0,
		"primary_target": _player,
		"damage_target_groups": [
			DAMAGE_TARGET_GROUPS
			.ACTIVE_PROJECTILE_BLOCKERS,
			DAMAGE_TARGET_GROUPS.ACTIVE_PLAYER,
		],
	}
	if controller == null or not use_event_primary:
		return result
	var event_node: WorldEventInteractable = (
		nodes.get(instance_id)
		as WorldEventInteractable
	)
	if event_node == null:
		return result
	var definition: Dictionary = (
		controller.definition(
			event_node.event_id()
		)
	)
	if (
		String(definition.get("kind", ""))
		== WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE
	):
		var defense_target: WorldEventDefenseTarget = (
			event_node.defense_target()
		)
		if (
			defense_target != null
			and is_instance_valid(defense_target)
		):
			result["primary_target"] = defense_target
			result["damage_target_groups"] = [
				DAMAGE_TARGET_GROUPS
				.ACTIVE_PROJECTILE_BLOCKERS,
				DAMAGE_TARGET_GROUPS
				.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS,
				DAMAGE_TARGET_GROUPS.ACTIVE_PLAYER,
			]
	return result

func _deliver_world_event_reward(
	instance_id: String,
	event_id: String,
	reward: Dictionary
) -> Dictionary:
	var reward_kind: String = String(reward.get("kind", ""))
	var source_kind: String = String(reward.get("source", ""))
	var feedback_key: String = ""
	var feedback_context: Dictionary = {
		"name": tr(_world_event_name_key(event_id)),
	}
	if (
		reward_kind
		== WORLD_EVENT_REWARD_TYPES.WORLD_EVENT_REWARD_GOLD
	):
		var amount: int = maxi(
			int(reward.get("amount", 0)),
			0
		)
		if amount <= 0:
			return {
				"ok": false,
				"reason": "invalid_gold_amount",
			}
		var gold_result: Dictionary = add_gold(
			amount,
			GOLD_TRANSACTION_REASONS.EVENT_REWARD
		)
		if not bool(gold_result.get("ok", false)):
			return {
				"ok": false,
				"reason": String(gold_result.get(
					"reason",
					"gold_delivery_failed"
				)),
			}
		feedback_context["amount"] = amount
		feedback_key = (
			"ui_world_event_blood_shrine_success"
			if source_kind
			== WORLD_EVENT_KINDS
			.WORLD_EVENT_KIND_BLOOD_SHRINE
			else "ui_world_event_completed_gold"
		)
	elif (
		reward_kind
		== WORLD_EVENT_REWARD_TYPES
		.WORLD_EVENT_REWARD_GEAR_MOD
	):
		var mod_id: String = String(reward.get("mod_id", ""))
		if mod_id.is_empty():
			return {
				"ok": false,
				"reason": "missing_gear_mod_id",
			}
		var spawn_result: Dictionary = _spawn_gear_mod_pickup(
			mod_id,
			_world_event_gear_mod_drop_position(
				instance_id,
				source_kind,
				int(reward.get("success_index", 0))
			)
		)
		if not bool(spawn_result.get("ok", false)):
			push_error(
				"[GameplayRunLoop] world-event Gear Mod pickup spawn failed: %s"
				% String(spawn_result.get("reason", "unknown"))
			)
			return {
				"ok": false,
				"reason": String(spawn_result.get(
					"reason",
					"gear_mod_pickup_spawn_failed"
				)),
			}
		feedback_key = (
			"ui_world_event_gold_shrine_success"
			if source_kind
			== WORLD_EVENT_KINDS
			.WORLD_EVENT_KIND_GOLD_SHRINE
			else "ui_world_event_completed_mod"
		)
	else:
		return {
			"ok": false,
			"reason": "unsupported_reward_kind:%s" % reward_kind,
		}
	if (
		not feedback_key.is_empty()
		and _hud != null
		and _hud.has_method("show_world_event_feedback")
	):
		_hud.call(
			"show_world_event_feedback",
			feedback_key,
			feedback_context
		)
	return {
		"ok": true,
		"reason": "delivered",
	}

func _world_event_gear_mod_drop_position(
	instance_id: String,
	source_kind: String,
	success_index: int = 0
) -> Vector2:
	var event_node: Node2D = nodes.get(
		instance_id,
		null
	) as Node2D
	var source_position: Vector2 = (
		event_node.global_position
		if event_node != null and is_instance_valid(event_node)
		else Vector2.ZERO
	)
	if (
		source_kind
		!= WORLD_EVENT_KINDS.WORLD_EVENT_KIND_GOLD_SHRINE
	):
		return _gear_mod_reward_positions(source_position, 1)[0]
	var positions: Array[Vector2] = _gear_mod_reward_positions(
		source_position,
		2
	)
	var successes: int = success_index
	if successes <= 0:
		successes = int(
			_world_event_runtime_summary(instance_id).get("successes", 0)
		) + 1
	return positions[clampi(successes - 1, 0, positions.size() - 1)]

func _on_world_event_prompt_requested(
	_instance_id: String,
	_event_id: String,
	reason: String,
	context: Dictionary
) -> void:
	var feedback_key: String = ""
	match reason:
		"continuous_event_busy":
			feedback_key = "ui_world_event_busy"
		"exhausted", "not_available":
			feedback_key = "ui_world_event_exhausted"
		"insufficient_gold":
			feedback_key = "ui_world_event_insufficient_gold"
		"shrine_failed":
			feedback_key = (
				"ui_world_event_gold_shrine_failure"
			)
		"insufficient_combined_health", "not_alive":
			feedback_key = (
				"ui_world_event_insufficient_health"
			)
		_:
			pass
	if (
		not feedback_key.is_empty()
		and _hud != null
		and _hud.has_method("show_world_event_feedback")
	):
		_hud.call(
			"show_world_event_feedback",
			feedback_key,
			context
		)

func _on_world_event_state_changed(
	_instance_id: String,
	event_id: String,
	state: String,
	_context: Dictionary
) -> void:
	if (
		state == WORLD_EVENT_STATES.WORLD_EVENT_STATE_FAILED
		and _hud != null
		and _hud.has_method("show_world_event_feedback")
	):
		_hud.call(
			"show_world_event_feedback",
			"ui_world_event_failed",
			{
				"name": tr(
					_world_event_name_key(event_id)
				),
			}
		)

func _on_world_event_module_pin_requested(
	instance_id: String,
	_module_slot_id: String,
	pinned: bool
) -> void:
	if (
		_module_world_manager == null
		or not module_coords.has(instance_id)
		or not _module_world_manager.has_method(
			"set_slot_pinned"
		)
	):
		return
	_module_world_manager.call(
		"set_slot_pinned",
		module_coords[instance_id]
		as Vector2i,
		pinned
	)

func _on_world_event_terminal_cleanup_requested(
	instance_id: String,
	_event_id: String,
	_context: Dictionary
) -> void:
	for raw_enemy: Node in get_tree().get_nodes_in_group(
		"active_enemies"
	):
		if (
			not raw_enemy.has_method("event_instance_id")
			or String(raw_enemy.call("event_instance_id"))
			!= instance_id
		):
			continue
		if raw_enemy.has_method("convert_to_player_target"):
			raw_enemy.call(
				"convert_to_player_target",
				_player
			)
	_try_release_world_event_background_pin(instance_id)

func _world_event_name_key(event_id: String) -> String:
	if controller == null:
		return ""
	return String(
		controller.definition(event_id).get(
			"name_key",
			""
		)
	)

func _update_world_event_background_pins() -> void:
	if controller == null:
		return
	for summary: Dictionary in _typed_dictionary_array(
		controller.debug_summary().get(
			"instances",
			[]
		)
	):
		if not bool(summary.get("pinned", false)):
			continue
		var state: String = String(summary.get("state", ""))
		if state not in [
			WORLD_EVENT_STATES.WORLD_EVENT_STATE_SUCCEEDED,
			WORLD_EVENT_STATES.WORLD_EVENT_STATE_FAILED,
		]:
			continue
		_try_release_world_event_background_pin(
			String(summary.get("instance_id", ""))
		)

func _try_release_world_event_background_pin(
	instance_id: String
) -> void:
	if (
		instance_id.is_empty()
		or controller == null
		or _module_world_manager == null
		or not module_coords.has(instance_id)
	):
		return
	var origin_coord: Vector2i = (
		module_coords[instance_id] as Vector2i
	)
	var has_enemy_inside_origin: bool = false
	for raw_enemy: Node in get_tree().get_nodes_in_group(
		"active_enemies"
	):
		if (
			not raw_enemy.has_method("event_instance_id")
			or String(raw_enemy.call("event_instance_id"))
			!= instance_id
			or not raw_enemy is Node2D
		):
			continue
		var enemy_coord: Vector2i = (
			_world_event_module_coord_for_position(
				(raw_enemy as Node2D).global_position
			)
		)
		if enemy_coord == origin_coord:
			has_enemy_inside_origin = true
			continue
		if raw_enemy.has_meta("module_slot"):
			raw_enemy.remove_meta("module_slot")
	if not has_enemy_inside_origin:
		controller.release_background_pin(instance_id)

func _world_event_module_coord_for_position(
	world_position: Vector2
) -> Vector2i:
	if _module_world_manager == null:
		return Vector2i(-1, -1)
	var global_cell: Vector2i = _module_world_manager.call(
		"world_to_global_cell",
		world_position
	) as Vector2i
	var module_and_local: Dictionary = (
		_module_world_manager.call(
			"global_cell_to_module_and_local",
			global_cell
		) as Dictionary
	)
	return module_and_local.get(
		"module_coord",
		Vector2i(-1, -1)
	) as Vector2i

func _world_events_snapshot() -> Dictionary:
	if controller == null:
		return {}
	return {
		"controller": controller.snapshot(),
		"wave_plans": wave_plans.duplicate(true),
	}

func _restore_world_events(snapshot_data: Dictionary) -> bool:
	if (
		controller == null
		or snapshot_data.is_empty()
	):
		return false
	wave_plans = _dictionary_or_empty(
		snapshot_data.get("wave_plans", {})
	).duplicate(true)
	var result: Dictionary = (
		controller.restore_snapshot(
			_dictionary_or_empty(
				snapshot_data.get("controller", {})
			)
		)
	)
	if not _array_or_empty(result.get("rejected", [])).is_empty():
		return false
	var active_instance_id: String = (
		controller
		.active_continuous_instance_id()
	)
	return (
		active_instance_id.is_empty()
		or wave_plans.has(active_instance_id)
	)

func _world_event_runtime_summary(
	instance_id: String
) -> Dictionary:
	if controller == null:
		return {}
	for summary: Dictionary in _typed_dictionary_array(
		controller.debug_summary().get(
			"instances",
			[]
		)
	):
		if String(summary.get("instance_id", "")) == instance_id:
			return summary
	return {}

func _refresh_world_event_hud() -> void:
	if (
		_hud == null
		or not _hud.has_method("set_world_event_status")
	):
		return
	if controller == null:
		_hud.call("set_world_event_status", {"visible": false})
		return
	var active_instance_id: String = (
		controller
		.active_continuous_instance_id()
	)
	if active_instance_id.is_empty():
		_hud.call("set_world_event_status", {"visible": false})
		return
	var runtime: Dictionary = _world_event_runtime_summary(
		active_instance_id
	)
	var event_id: String = String(runtime.get("event_id", ""))
	var definition: Dictionary = (
		controller.definition(event_id)
	)
	var kind: String = String(definition.get("kind", ""))
	var elapsed: float = maxf(
		float(runtime.get("elapsed", 0.0)),
		0.0
	)
	var status: Dictionary = {
		"visible": true,
		"name_key": String(definition.get("name_key", "")),
		"values": {},
	}
	var values: Dictionary = {}
	match kind:
		WORLD_EVENT_KINDS.WORLD_EVENT_KIND_DEFENSE:
			status["detail_key"] = (
				"ui_world_event_status_defense"
			)
			var defense: Dictionary = _dictionary_or_empty(
				runtime.get("defense_target", {})
			)
			values = {
				"time": _display_event_number(
					maxf(
						float(definition.get("duration", 0.0))
						- elapsed,
						0.0
					)
				),
				"health": _display_event_number(
					float(defense.get("current_health", 0.0))
				),
				"max_health": _display_event_number(
					float(defense.get("max_health", 0.0))
				),
			}
		WORLD_EVENT_KINDS.WORLD_EVENT_KIND_SURVIVAL:
			status["detail_key"] = (
				"ui_world_event_status_survival"
			)
			var wave_total: int = _array_or_empty(
				definition.get("waves", [])
			).size()
			values = {
				"time": _display_event_number(
					maxf(
						float(definition.get("duration", 0.0))
						- elapsed,
						0.0
					)
				),
				"wave": mini(
					int(runtime.get("wave_cursor", 0)),
					wave_total
				),
				"wave_total": wave_total,
			}
		WORLD_EVENT_KINDS.WORLD_EVENT_KIND_CAPTURE:
			status["detail_key"] = (
				"ui_world_event_status_capture"
			)
			values = {
				"progress": _display_event_number(
					float(runtime.get("capture_progress", 0.0))
				),
				"required": _display_event_number(
					float(
						definition.get(
							"capture_duration",
							0.0
						)
					)
				),
				"entry": _display_event_number(
					float(
						runtime.get(
							"entry_delay_progress",
							0.0
						)
					)
				),
				"entry_required": _display_event_number(
					float(definition.get("entry_delay", 0.0))
				),
				"timeout": _display_event_number(
					maxf(
						float(definition.get("timeout", 0.0))
						- elapsed,
						0.0
					)
				),
			}
		_:
			status["visible"] = false
	status["values"] = values
	_hud.call("set_world_event_status", status)

func _display_event_number(value: float) -> String:
	return "%.1f" % maxf(value, 0.0)


func _nearest_world_event_candidate() -> Dictionary:
	if _player == null or controller == null:
		return {}
	var best: Dictionary = {}
	for instance_id_raw: Variant in nodes.keys():
		var instance_id: String = String(instance_id_raw)
		var interactable: WorldEventInteractable = (
			nodes.get(instance_id)
			as WorldEventInteractable
		)
		if (
			interactable == null
			or not is_instance_valid(interactable)
			or interactable.event_state()
			!= WORLD_EVENT_STATES
			.WORLD_EVENT_STATE_INACTIVE
			or not interactable.can_player_interact(_player)
		):
			continue
		var distance: float = (
			_player.global_position.distance_to(
				interactable.global_position
			)
		)
		if (
			not best.is_empty()
			and distance >= float(best.get("distance", INF))
		):
			continue
		best = {
			"kind": "world_event",
			"id": instance_id,
			"distance": distance,
			"event_id": interactable.event_id(),
		}
	return best
