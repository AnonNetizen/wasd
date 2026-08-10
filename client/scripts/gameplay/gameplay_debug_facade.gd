# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/决策记录.md ADR #197
class_name GameplayDebugFacade
extends RefCounted

## Stateless implementation of the standard-run debug surface. GameplayRunLoop
## retains public wrappers, node ownership, source identity, and lifecycle.


const GOLD_TRANSACTION_REASONS := preload(
	"res://scripts/contracts/gold_transaction_reasons.gd"
)
const REWARD_CHOICE_TRIGGERS := preload(
	"res://scripts/contracts/reward_choice_triggers.gd"
)

const ACTIVE_ENEMY_GROUP: String = "active_enemies"
const DEBUG_WAVE_PREFIX: String = "debug_"
const ENEMY_KILL_DAMAGE: float = 999_999.0
const PLAYER_KILL_MULTIPLIER: float = 10.0


class ActiveRunContext:
	extends RefCounted

	## Borrowed values are populated for each call. The facade never stores this
	## context or any replaceable runtime dictionary beyond the current call.
	var owner: Node = null
	var tree: SceneTree = null
	var active_world: Node2D = null
	var player: Node2D = null
	var skill_system: Node = null
	var enemy_rows: Dictionary = {}
	var spawn_states: Dictionary = {}
	var max_spawn_count: int = 1
	var now: Callable = Callable()
	var spawn_enemy: Callable = Callable()
	var add_gold: Callable = Callable()
	var request_reward_choice: Callable = Callable()
	var make_damage_info: Callable = Callable()
	var is_active_world_entity: Callable = Callable()
	var release_entity: Callable = Callable()


class SummaryState:
	extends RefCounted

	var level: int = 0
	var gold_balance: int = 0
	var gold_earned_total: int = 0
	var level_gold: int = 0
	var level_gold_required: int = 0
	var reward_choice_active: bool = false
	var kills: int = 0
	var main_hero_id: String = ""
	var sub_hero_id: String = ""
	var composition_name: String = ""
	var composition_palette: Dictionary = {}
	var passive_id: String = ""
	var player_life: float = 0.0
	var player_max_life: float = 0.0
	var player_shield: float = 0.0
	var player_max_shield: float = 0.0
	var player_overshield: float = 0.0
	var active_enemies: int = 0
	var active_hazards: int = 0
	var interest_points: Dictionary = {}
	var gear_mods: Dictionary = {}
	var difficulty: Dictionary = {}
	var map: Dictionary = {}
	var module_world: Dictionary = {}
	var skills: Dictionary = {}
	var warzone_director: Dictionary = {}


func request_reward_choice(
	context: ActiveRunContext,
	candidate_count: int,
	pool_id: String
) -> Dictionary:
	if context == null or not context.request_reward_choice.is_valid():
		return _result(false, "request_unavailable")
	return context.request_reward_choice.call(
		pool_id,
		REWARD_CHOICE_TRIGGERS.DEBUG_COMMAND,
		candidate_count
	) as Dictionary


func summary(state: SummaryState) -> Dictionary:
	if state == null:
		return {}
	return {
		"level": state.level,
		"gold_balance": state.gold_balance,
		"gold_earned_total": state.gold_earned_total,
		"level_gold": state.level_gold,
		"level_gold_required": state.level_gold_required,
		"reward_choice_active": state.reward_choice_active,
		"kills": state.kills,
		"hero_composition": {
			"main_hero_id": state.main_hero_id,
			"sub_hero_id": state.sub_hero_id,
			"name": state.composition_name,
			"palette": state.composition_palette.duplicate(true),
			"passive_id": state.passive_id,
		},
		"player_life": state.player_life,
		"player_max_life": state.player_max_life,
		"player_shield": state.player_shield,
		"player_max_shield": state.player_max_shield,
		"player_overshield": state.player_overshield,
		"active_enemies": state.active_enemies,
		"active_hazards": state.active_hazards,
		"interest_points": state.interest_points.duplicate(true),
		"gear_mods": state.gear_mods.duplicate(true),
		"difficulty": state.difficulty.duplicate(true),
		"map": state.map.duplicate(true),
		"module_world": state.module_world.duplicate(true),
		"skills": state.skills.duplicate(true),
		"warzone_director": state.warzone_director.duplicate(true),
	}


func spawn_enemy(
	context: ActiveRunContext,
	enemy_id: String,
	count: int = 1
) -> Dictionary:
	if (
		context == null
		or context.active_world == null
		or context.player == null
	):
		return _result(false, "run_not_ready")
	if not context.enemy_rows.has(enemy_id):
		return _result(false, "unknown_enemy")
	if not context.spawn_enemy.is_valid():
		return _result(false, "spawn_unavailable")

	var spawn_count: int = clampi(
		count,
		1,
		maxi(context.max_spawn_count, 1)
	)
	var spawned: int = 0
	var wave_key: String = "%s%s" % [DEBUG_WAVE_PREFIX, enemy_id]
	var default_state: Dictionary = {
		"next_time": _now(context),
		"spawned": 0,
		"alive": 0,
	}
	var raw_state: Variant = context.spawn_states.get(
		wave_key,
		default_state
	)
	var state: Dictionary = (
		raw_state
		if raw_state is Dictionary
		else default_state
	)
	for _index: int in range(spawn_count):
		if bool(context.spawn_enemy.call(
			{"enemy_id": enemy_id},
			wave_key
		)):
			spawned += 1
	state["spawned"] = int(state.get("spawned", 0)) + spawned
	state["alive"] = int(state.get("alive", 0)) + spawned
	state["next_time"] = _now(context)
	context.spawn_states[wave_key] = state
	return {
		"ok": spawned > 0,
		"reason": "" if spawned > 0 else "pool_unavailable",
		"spawned": spawned,
	}


func give_gold(context: ActiveRunContext, amount: int) -> Dictionary:
	if context == null or not context.add_gold.is_valid():
		return _result(false, "gold_unavailable")
	return context.add_gold.call(
		amount,
		GOLD_TRANSACTION_REASONS.DEBUG_COMMAND
	) as Dictionary


func heal_player(context: ActiveRunContext, amount: float) -> Dictionary:
	if (
		context == null
		or context.player == null
		or not context.player.has_method("debug_heal")
	):
		return _result(false, "player_unavailable")
	var result: Dictionary = context.player.call("debug_heal", amount)
	result["ok"] = true
	return result


func set_player_hp(context: ActiveRunContext, amount: float) -> Dictionary:
	if (
		context == null
		or context.player == null
		or not context.player.has_method("debug_set_life")
	):
		return _result(false, "player_unavailable")
	var result: Dictionary = context.player.call("debug_set_life", amount)
	result["ok"] = true
	return result


func damage_player(context: ActiveRunContext, amount: float) -> Dictionary:
	if context == null or context.player == null:
		return _result(false, "player_unavailable")
	var applied_amount: float = maxf(amount, 0.0)
	if applied_amount <= 0.0:
		return _result(false, "non_positive_amount")
	if not context.make_damage_info.is_valid():
		return _result(false, "damage_info_unavailable")
	if context.player.has_method("debug_clear_invulnerability"):
		context.player.call("debug_clear_invulnerability")
	var raw_info: Variant = context.make_damage_info.call(
		applied_amount,
		context.player
	)
	if not raw_info is RefCounted:
		return _result(false, "damage_info_unavailable")
	var combat_result: Dictionary = Combat.apply_damage(
		context.player,
		raw_info as RefCounted
	)
	return {
		"ok": bool(combat_result.get("applied", false)),
		"reason": String(combat_result.get("reason", "")),
		"life": (
			float(context.player.call("current_life"))
			if context.player.has_method("current_life")
			else 0.0
		),
		"max_life": (
			float(context.player.call("max_life"))
			if context.player.has_method("max_life")
			else 0.0
		),
		"combat_result": combat_result.duplicate(true),
	}


func kill_player(context: ActiveRunContext) -> Dictionary:
	if (
		context == null
		or context.player == null
		or not context.player.has_method("max_life")
	):
		return _result(false, "player_unavailable")
	if context.player.has_method("debug_set_shield"):
		context.player.call("debug_set_shield", 0.0, 0.0)
	if context.player.has_method("debug_clear_invulnerability"):
		context.player.call("debug_clear_invulnerability")
	return damage_player(
		context,
		float(context.player.call("max_life")) * PLAYER_KILL_MULTIPLIER
	)


func kill_enemies(context: ActiveRunContext) -> Dictionary:
	var killed: int = 0
	if context == null or context.tree == null:
		return {"ok": true, "count": killed}
	for enemy: Node in context.tree.get_nodes_in_group(ACTIVE_ENEMY_GROUP):
		if not _is_active_entity(context, enemy):
			continue
		if not context.make_damage_info.is_valid():
			continue
		var raw_info: Variant = context.make_damage_info.call(
			ENEMY_KILL_DAMAGE,
			enemy
		)
		if not raw_info is RefCounted:
			continue
		var result: Dictionary = Combat.apply_damage(
			enemy,
			raw_info as RefCounted
		)
		if bool(result.get("applied", false)):
			killed += 1
	return {
		"ok": true,
		"count": killed,
	}


func clear_enemies(context: ActiveRunContext) -> Dictionary:
	var cleared: int = 0
	if context != null and context.tree != null:
		for enemy: Node in context.tree.get_nodes_in_group(
			ACTIVE_ENEMY_GROUP
		):
			if not _is_active_entity(context, enemy):
				continue
			if (
				context.release_entity.is_valid()
				and bool(context.release_entity.call(enemy))
			):
				cleared += 1
	if context != null:
		for wave_key: String in context.spawn_states.keys():
			if String(wave_key).begins_with(DEBUG_WAVE_PREFIX):
				var state: Dictionary = context.spawn_states[wave_key]
				state["alive"] = 0
				context.spawn_states[wave_key] = state
	return {
		"ok": true,
		"count": cleared,
	}


func difficulty_snapshot(snapshot_data: Dictionary) -> Dictionary:
	return snapshot_data.duplicate(true)


func set_player_position(
	context: ActiveRunContext,
	world_position: Vector2
) -> void:
	if (
		context != null
		and context.player != null
		and is_instance_valid(context.player)
	):
		context.player.global_position = world_position


func cast_primary_skill(context: ActiveRunContext) -> Dictionary:
	if (
		context == null
		or context.skill_system == null
		or not context.skill_system.has_method("cast_primary_skill")
	):
		return _result(false, "skill_system_unavailable")
	return context.skill_system.call("cast_primary_skill") as Dictionary


func _now(context: ActiveRunContext) -> float:
	if context.now.is_valid():
		return float(context.now.call())
	return 0.0


func _is_active_entity(
	context: ActiveRunContext,
	entity: Node
) -> bool:
	if not context.is_active_world_entity.is_valid():
		return false
	return bool(context.is_active_world_entity.call(entity))


func _result(ok: bool, reason: String) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
	}
