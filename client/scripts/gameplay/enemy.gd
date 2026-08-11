# Doc: docs/代码/enemy_ai.md
# Authority: docs/游戏设计文档.md §5.3, docs/词表与契约.md §12-B
class_name Enemy
extends CharacterBody2D


signal defeated(
	enemy: Node,
	gold_reward: int,
	counts_as_kill: bool,
	drops_rewards: bool,
	cause_id: String
)
signal attack_windup_started(enemy: Node, action_id: String, context: Dictionary)
signal attack_committed(enemy: Node, action_id: String, context: Dictionary)

const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TARGET_GROUPS := preload(
	"res://scripts/contracts/damage_target_groups.gd"
)
const ENEMY_ACTION_RUNTIME_SCRIPT := preload(
	"res://scripts/gameplay/enemy_action_runtime.gd"
)
const ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_charge_attack_handler.gd"
)
const ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_explosion_attack_handler.gd"
)
const ENEMY_BRAIN_SCRIPT := preload("res://scripts/gameplay/enemy_brain.gd")
const ENEMY_MELEE_ATTACK_HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_melee_attack_handler.gd"
)
const ENEMY_PROJECTILE_MATERIALIZER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_projectile_materializer.gd"
)
const ENEMY_RANGED_ATTACK_HANDLER_SCRIPT := preload(
	"res://scripts/gameplay/enemy_ranged_attack_handler.gd"
)
const ENEMY_AI_ACTIONS := preload("res://scripts/contracts/enemy_ai_actions.gd")
const ENEMY_DEFEAT_CAUSES := preload(
	"res://scripts/contracts/enemy_defeat_causes.gd"
)
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

const NAVIGATION_MODE_DIRECT: String = "direct"
const NAVIGATION_MODE_FLOW_FIELD: String = "flow_field"
const NAVIGATION_MODE_LOCAL_ASTAR: String = "local_astar"
const NAVIGATION_MODE_NONE: String = "none"
const NAVIGATION_NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i(1, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]
const PATH_TANGENT_SCORE_WEIGHT: float = 0.2
const SCORE_EPSILON: float = 0.001
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"
const TARGET_MODE_EVENT_PRIMARY: String = "event_primary"
const TARGET_MODE_PLAYER: String = "player"

@export_group("Visual Style")
@export var fill_color: Color = Color(1.0, 0.38, 0.32)
@export var defeat_feedback_color: Color = Color(1.0, 0.62, 0.22)
@export var hit_flash_color: Color = Color(1.0, 0.96, 0.74)

var _action_runtime: ENEMY_ACTION_RUNTIME_SCRIPT = (
	ENEMY_ACTION_RUNTIME_SCRIPT.new()
)
var _brain: EnemyBrain = ENEMY_BRAIN_SCRIPT.new()
var _collision_shape: CollisionShape2D = null
var _base_max_life: float = 1.0
var _debug_ai_enabled: bool = true
var _enemy_id: String = ""
var _event_instance_id: String = ""
var _gold_reward: int = 0
var _reward_snapshot: Dictionary = {}
var _facing_sign: float = 1.0
var _focus_target: Node2D = null
var _hit_radius: float = 0.0
var _home_position: Vector2 = Vector2.ZERO
var _life_points: float = 1.0
var _max_life: float = 1.0
var _has_movement_bounds: bool = false
var _movement_bounds: Rect2 = Rect2()
var _move_speed: float = 0.0
var _navigation_mode: String = NAVIGATION_MODE_NONE
var _navigation_provider: Node = null
var _owned_tag_counts: Dictionary = {}
var _player_target: Node2D = null
var _primary_target: Node2D = null
var _charge_attack_ports: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Ports = null
var _explosion_attack_ports: ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Ports = null
var _melee_attack_ports: ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Ports = null
var _projectile_materializer_ports: ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.Ports = null
var _ranged_attack_ports: ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Ports = null
var _damage_target_groups: Array[String] = []
var _runtime_spawn_serial: int = 0
var _separation_radius: float = 0.0
var _cached_navigation_waypoint: Vector2 = Vector2.ZERO
var _has_cached_navigation_waypoint: bool = false
var _status_effect_component: Node = null
var _presentation: ActorPresentationController = null
var _spawn_damage_multiplier: float = 1.0
var _spawn_health_multiplier: float = 1.0


func _physics_process(delta: float) -> void:
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if is_defeat_feedback_active():
		return
	if not GameState.is_state(GameState.PLAYING):
		return
	if scaled_delta <= 0.0:
		return
	if _action_runtime.is_armed():
		_update_armed_state(scaled_delta)
		return
	if _primary_target == null or not is_instance_valid(_primary_target):
		return
	if not _debug_ai_enabled:
		velocity = Vector2.ZERO
		return

	_update_ai_timers(scaled_delta)

	if _is_attack_state_active():
		_update_attack_state(scaled_delta)
	else:
		_brain.advance_decision(scaled_delta)
		if (
			_action_runtime.current_action().is_empty()
			or _brain.is_decision_due()
		):
			_choose_action()
		_apply_current_action(scaled_delta)

	if not _is_attack_state_active():
		_apply_center_separation()


func configure(
	enemy_data: Dictionary,
	target: Node2D,
	navigation_provider: Node = null,
	spawn_difficulty: Dictionary = {},
	spawn_context: Dictionary = {}
) -> void:
	velocity = Vector2.ZERO
	_clear_status_effects_for_reuse()
	_ensure_presentation()
	if _presentation != null:
		_presentation.configure_profile_id(
			String(enemy_data.get("presentation_profile_id", ""))
		)
		_presentation.reset_presentation()
	_player_target = target
	_primary_target = _node2d_or_null(
		spawn_context.get("primary_target", target)
	)
	if _primary_target == null:
		_primary_target = target
	_focus_target = _primary_target
	_event_instance_id = String(
		spawn_context.get("event_instance_id", "")
	)
	_damage_target_groups = _string_array(
		spawn_context.get("damage_target_groups", [])
	)
	if _damage_target_groups.is_empty():
		_damage_target_groups = [
			DAMAGE_TARGET_GROUPS.ACTIVE_PROJECTILE_BLOCKERS,
			DAMAGE_TARGET_GROUPS.ACTIVE_PLAYER,
		]
	_navigation_provider = navigation_provider
	_home_position = global_position
	_enemy_id = String(enemy_data.get("id", ""))
	_brain.configure(
		String(enemy_data.get("ai_profile_id", "")),
		_dictionary_or_empty(enemy_data.get("ai_profile", {}))
	)
	_action_runtime.configure(_brain.initial_attack_cooldown())
	_debug_ai_enabled = true
	_navigation_mode = NAVIGATION_MODE_NONE
	_has_cached_navigation_waypoint = false
	_cached_navigation_waypoint = Vector2.ZERO
	_spawn_health_multiplier = maxf(
		float(spawn_difficulty.get("health_multiplier", 1.0)),
		0.0
	)
	_spawn_damage_multiplier = maxf(
		float(spawn_difficulty.get("damage_multiplier", 1.0)),
		0.0
	)
	_base_max_life = float(enemy_data.get("max_hp", 1))
	_max_life = _base_max_life * _spawn_health_multiplier
	_life_points = _max_life
	_move_speed = float(enemy_data.get("move_speed", 0.0))
	_reward_snapshot = _canonical_reward_snapshot(
		spawn_context.get("reward_snapshot", {})
	)
	_gold_reward = (
		maxi(int(_reward_snapshot.get("gold_reward", 0)), 0)
		if bool(_reward_snapshot.get("valid", false))
		else 0
	)
	_hit_radius = float(enemy_data.get("hit_radius", 0.0))
	_separation_radius = float(enemy_data.get("separation_radius", 0.0))
	_configure_collision_shape()
	if _primary_target != null and is_instance_valid(_primary_target):
		_update_facing(_primary_target.global_position - global_position)
	_home_position = _clamp_to_movement_bounds(_home_position)
	_apply_movement_bounds()
	add_to_group("active_enemies")
	_refresh_visuals()


func hit_radius() -> float:
	return _hit_radius


func separation_radius() -> float:
	return _separation_radius


func visual_color() -> Color:
	return fill_color


func ai_debug_summary() -> Dictionary:
	var action_values: ENEMY_ACTION_RUNTIME_SCRIPT.SnapshotValues = (
		_action_runtime.snapshot_values()
	)
	return {
		"profile_id": _brain.profile_id(),
		"action": action_values.current_action,
		"action_state": action_values.action_state,
		"focus_target": _focus_target.name if _focus_target != null and is_instance_valid(_focus_target) else "",
		"primary_target": _primary_target.name if _primary_target != null and is_instance_valid(_primary_target) else "",
		"event_instance_id": _event_instance_id,
		"target_mode": _target_mode(),
		"damage_target_groups": _damage_target_groups.duplicate(),
		"perception_state": _brain.perception_state(),
		"path_distance": _brain.path_distance(),
		"last_known_position": (
			_vector_to_dict(_brain.last_known_position())
			if _brain.has_last_known_position()
			else {}
		),
		"memory_remaining": _brain.memory_remaining(),
		"navigation_mode": _navigation_mode,
		"attack_time_remaining": action_values.action_timer,
		"attack_cooldown_remaining": (
			action_values.attack_cooldown_remaining
		),
		"burst_shots_remaining": action_values.burst_shots_remaining,
		"armed": action_values.armed,
		"locked_direction": _vector_to_dict(
			action_values.locked_direction
		),
		"scaled_damage": _scaled_attack_damage(_current_attack()),
		"attack_range": _attack_display_range(_current_attack()),
		"release_hit": action_values.attack_hit_committed,
		"runtime_spawn_serial": _runtime_spawn_serial,
		"reward_snapshot": _reward_snapshot.duplicate(true),
		"scores": _brain.last_scores(),
	}


func event_instance_id() -> String:
	return _event_instance_id


func convert_to_player_target(target: Node2D) -> void:
	var preserve_committed_attack: bool = (
		_action_runtime.is_armed()
		or _is_attack_state_active()
	)
	_player_target = target
	_primary_target = target
	_focus_target = target
	_damage_target_groups = [
		DAMAGE_TARGET_GROUPS.ACTIVE_PROJECTILE_BLOCKERS,
		DAMAGE_TARGET_GROUPS.ACTIVE_PLAYER,
	]
	if preserve_committed_attack:
		return
	_action_runtime.set_current_action("")
	_action_runtime.set_action_state("")
	_action_runtime.set_action_timer(0.0)
	_action_runtime.set_burst_shots_remaining(0)
	_action_runtime.set_locked_direction(Vector2.ZERO)
	_action_runtime.set_attack_hit_committed(false)
	_action_runtime.set_collateral_player_hit_committed(false)
	_brain.request_decision_now()


func is_alive() -> bool:
	return (
		_life_points > 0.0
		and not _action_runtime.is_armed()
		and not is_defeat_feedback_active()
	)


func current_life() -> float:
	return _life_points


func max_life() -> float:
	return _max_life


func heal(amount: float) -> float:
	var requested_amount: float = maxf(amount, 0.0)
	if requested_amount <= 0.0 or not is_alive():
		return 0.0
	var previous_life: float = _life_points
	_life_points = minf(_life_points + requested_amount, _max_life)
	var applied_amount: float = _life_points - previous_life
	if applied_amount > 0.0:
		_refresh_visuals()
	return applied_amount


func enemy_spawn_snapshot() -> Dictionary:
	return {
		"health_multiplier": _spawn_health_multiplier,
		"damage_multiplier": _spawn_damage_multiplier,
	}


func enemy_id() -> String:
	return _enemy_id


func set_runtime_spawn_serial(serial: int) -> void:
	_runtime_spawn_serial = maxi(serial, 0)


func runtime_spawn_serial() -> int:
	return _runtime_spawn_serial


func is_armed() -> bool:
	return _action_runtime.is_armed()


func is_committed_exploder() -> bool:
	return (
		_action_runtime.is_armed()
		and _action_runtime.has_exploded()
		and _has_action(ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET)
	)


func is_defeat_feedback_active() -> bool:
	return _presentation != null and _presentation.is_defeat_active()


func combat_team_id() -> String:
	return TEAM_ENEMY


func debug_configure_training_target(max_life: float, home_position: Vector2) -> void:
	_debug_ai_enabled = false
	_spawn_health_multiplier = 1.0
	_spawn_damage_multiplier = 1.0
	_base_max_life = maxf(max_life, 1.0)
	_max_life = _base_max_life
	_life_points = _max_life
	_action_runtime.set_armed(false)
	_action_runtime.set_has_exploded(false)
	_set_collision_enabled(true)
	_home_position = home_position
	global_position = home_position
	velocity = Vector2.ZERO
	set_meta("debug_test_arena_home", home_position)
	_clear_status_effects_for_reuse()
	_refresh_visuals()


func debug_reset_training_target() -> void:
	if _debug_ai_enabled:
		return
	var home_position: Variant = get_meta(
		"debug_test_arena_home",
		_home_position
	)
	if home_position is Vector2:
		global_position = home_position as Vector2
	velocity = Vector2.ZERO
	_life_points = _max_life
	_clear_status_effects_for_reuse()
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()
	_refresh_visuals()


func debug_ai_enabled() -> bool:
	return _debug_ai_enabled


## Debug-build-only seam for deterministic attack handler smoke coverage.
func debug_force_action_for_test(action_id: String) -> bool:
	if not OS.is_debug_build() or not _brain.has_action(action_id):
		return false
	_action_runtime.set_current_action(action_id)
	return true


## Debug-build-only seam for deterministic melee windup startup.
func debug_start_melee_attack_for_test() -> bool:
	if not _can_debug_drive_melee_attack():
		return false
	var result: ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Result = (
		_start_melee_attack()
	)
	return result.started


## Debug-build-only seam for deterministic melee phase advancement.
func debug_advance_melee_attack_for_test(delta: float) -> bool:
	if not _can_debug_drive_melee_attack():
		return false
	var result: ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Result = (
		_advance_melee_attack(delta)
	)
	return result.handled


## Debug-build-only seam for deterministic charge windup startup.
func debug_start_charge_for_test() -> bool:
	if not _can_debug_drive_charge_attack():
		return false
	var result: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Result = (
		_start_charge()
	)
	return result.started


## Debug-build-only seam for deterministic charge phase advancement.
func debug_advance_charge_for_test(delta: float) -> bool:
	if not _can_debug_drive_charge_attack():
		return false
	var result: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Result = (
		_advance_charge_attack(delta)
	)
	return result.handled


## Debug-build-only seam for deterministic explosion arming.
func debug_arm_explosion_for_test(from_chain: bool = false) -> bool:
	if not _can_debug_drive_explosion_attack():
		return false
	var result: ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Result = (
		_arm_explosion(from_chain)
	)
	return result.armed


## Debug-build-only seam for deterministic armed-phase advancement.
func debug_advance_explosion_for_test(delta: float) -> bool:
	if (
		not _can_debug_drive_explosion_attack()
		or not _action_runtime.is_armed()
	):
		return false
	var result: ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Result = (
		_update_armed_state(delta)
	)
	return result.handled


## Debug-build-only seam for the real ranged projectile adapter.
func debug_materialize_ranged_projectile_for_test(
	target_direction: Vector2
) -> bool:
	if not _can_debug_drive_ranged_attack():
		return false
	var result: ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.Result = (
		_materialize_ranged_projectile(
			_ranged_attack_config(_current_attack()).projectile,
			target_direction
		)
	)
	return result.ok


## Debug-build-only seam for deterministic ranged burst startup.
func debug_start_ranged_burst_for_test(
	target_direction: Vector2
) -> bool:
	if not _can_debug_drive_ranged_attack():
		return false
	var result: ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Result = (
		_start_ranged_burst(target_direction)
	)
	return result.started


## Debug-build-only seam for deterministic ranged phase advancement.
func debug_advance_ranged_attack_for_test(delta: float) -> bool:
	if not _can_debug_drive_ranged_attack():
		return false
	var result: ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Result = (
		_advance_ranged_attack(delta)
	)
	return result.handled


func add_owned_tag(tag_id: String) -> bool:
	return _add_owned_tag_count(tag_id)


func remove_owned_tag(tag_id: String) -> bool:
	return _remove_owned_tag_count(tag_id)


func has_owned_tag(tag_id: String) -> bool:
	return int(_owned_tag_counts.get(tag_id, 0)) > 0


func owned_tags() -> Array[String]:
	return _sorted_string_keys(_owned_tag_counts)


func apply_status_effect(status_effect: Variant) -> Dictionary:
	_ensure_status_effect_component()
	if _status_effect_component == null:
		return {
			"applied": false,
			"reason": "status_component_unavailable",
		}
	return _status_effect_component.call("apply", status_effect) as Dictionary


func active_statuses() -> Array[String]:
	_ensure_status_effect_component()
	if _status_effect_component == null:
		return []
	return _status_effect_component.call("active_statuses") as Array[String]


func status_summary() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_effects: Variant = _status_effect_snapshot().get("effects", [])
	if not raw_effects is Array:
		return result
	for raw_effect: Variant in raw_effects as Array:
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect as Dictionary
		var status_id: String = String(effect.get("status", ""))
		if status_id.is_empty():
			continue
		result.append({
			"id": status_id,
			"name_key": "status_%s_name" % status_id,
			"stacks": maxi(int(effect.get("stack_count", 1)), 1),
			"remaining": maxf(float(effect.get("remaining", 0.0)), 0.0),
		})
	return result


func status_stat_multiplier(stat_id: String) -> float:
	_ensure_status_effect_component()
	if (
		_status_effect_component == null
		or not _status_effect_component.has_method("stat_multiplier")
	):
		return 1.0
	return maxf(
		float(
			_status_effect_component.call(
				"stat_multiplier",
				stat_id
			)
		),
		0.0
	)


func status_stack_count(status_id: String) -> int:
	_ensure_status_effect_component()
	if (
		_status_effect_component == null
		or not _status_effect_component.has_method("stack_count")
	):
		return 0
	return int(_status_effect_component.call("stack_count", status_id))


func incoming_damage_multiplier(info: RefCounted) -> float:
	_ensure_status_effect_component()
	if (
		_status_effect_component == null
		or not _status_effect_component.has_method(
			"incoming_damage_multiplier"
		)
	):
		return 1.0
	return maxf(
		float(
			_status_effect_component.call(
				"incoming_damage_multiplier",
				String(info.get("source_team"))
			)
		),
		0.0
	)


func set_movement_bounds(bounds: Rect2) -> void:
	_movement_bounds = bounds
	_has_movement_bounds = bounds.size.x > 0.0 and bounds.size.y > 0.0
	_home_position = _clamp_to_movement_bounds(_home_position)
	_apply_movement_bounds()


func clear_movement_bounds() -> void:
	_has_movement_bounds = false
	_movement_bounds = Rect2()


func receive_damage(info: RefCounted) -> Dictionary:
	if _action_runtime.is_armed():
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": false,
			"reason": "armed",
		}
	if _life_points <= 0.0 or is_defeat_feedback_active():
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": true,
			"reason": "defeated",
		}
	var source_team: String = String(info.get("source_team"))
	var source: Node = info.get("source") as Node
	var enemy_explosion: bool = (
		source_team == TEAM_ENEMY
		and source != null
		and is_instance_valid(source)
		and source.has_method("is_committed_exploder")
		and bool(source.call("is_committed_exploder"))
	)
	if source_team == TEAM_ENEMY and not enemy_explosion:
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": false,
			"reason": "friendly_fire_blocked",
		}

	var amount: float = float(info.get("amount"))
	var applied_amount: float = minf(amount, _life_points)
	_life_points = maxf(_life_points - amount, 0.0)
	var is_defeated: bool = _life_points <= 0.0
	if is_defeated:
		if (
			enemy_explosion
			and _has_action(ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET)
		):
			_arm_explosion(true)
			return {
				"applied": true,
				"amount": applied_amount,
				"defeated": false,
				"reason": "chain_armed",
			}
		var counts_as_kill: bool = source_team == TEAM_PLAYER or enemy_explosion
		var cause_id: String = (
			ENEMY_DEFEAT_CAUSES.ENEMY_EXPLOSION
			if enemy_explosion
			else (
				ENEMY_DEFEAT_CAUSES.PLAYER_DAMAGE
				if source_team == TEAM_PLAYER
				else ENEMY_DEFEAT_CAUSES.OTHER_CAUSE
			)
		)
		_finish_defeat(counts_as_kill, counts_as_kill, cause_id)
	else:
		_start_hit_flash()
	return {
		"applied": true,
		"amount": applied_amount,
		"defeated": is_defeated,
		"reason": "applied",
	}


func snapshot() -> Dictionary:
	var action_values: ENEMY_ACTION_RUNTIME_SCRIPT.SnapshotValues = (
		_action_runtime.snapshot_values()
	)
	return {
		"enemy_id": _enemy_id,
		"position": _vector_to_dict(global_position),
		"life_points": _life_points,
		"spawn_health_multiplier": _spawn_health_multiplier,
		"spawn_damage_multiplier": _spawn_damage_multiplier,
		"reward_snapshot": _reward_snapshot.duplicate(true),
		"home_position": _vector_to_dict(_home_position),
		"current_action": action_values.current_action,
		"action_state": action_values.action_state,
		"action_timer": action_values.action_timer,
		"attack_cooldown_remaining": (
			action_values.attack_cooldown_remaining
		),
		"attack_hit_committed": action_values.attack_hit_committed,
		"collateral_player_hit_committed": (
			action_values.collateral_player_hit_committed
		),
		"burst_shots_remaining": action_values.burst_shots_remaining,
		"locked_direction": _vector_to_dict(
			action_values.locked_direction
		),
		"armed": action_values.armed,
		"armed_from_chain": action_values.armed_from_chain,
		"has_exploded": action_values.has_exploded,
		"runtime_spawn_serial": _runtime_spawn_serial,
		"event_instance_id": _event_instance_id,
		"target_mode": _target_mode(),
		"owned_tag_counts": _owned_tag_counts.duplicate(true),
		"status_effects": _status_effect_snapshot(),
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_ensure_status_effect_component()
	if _status_effect_component != null:
		_status_effect_component.call("clear", false)
	_spawn_health_multiplier = maxf(
		float(snapshot_data.get("spawn_health_multiplier", 1.0)),
		0.0
	)
	_spawn_damage_multiplier = maxf(
		float(snapshot_data.get("spawn_damage_multiplier", 1.0)),
		0.0
	)
	_reward_snapshot = _canonical_reward_snapshot(
		snapshot_data.get("reward_snapshot", _reward_snapshot)
	)
	_gold_reward = (
		maxi(int(_reward_snapshot.get("gold_reward", 0)), 0)
		if bool(_reward_snapshot.get("valid", false))
		else 0
	)
	_max_life = _base_max_life * _spawn_health_multiplier
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_home_position = _dict_to_vector(snapshot_data.get("home_position", {}), global_position)
	_home_position = _clamp_to_movement_bounds(_home_position)
	_apply_movement_bounds()
	_life_points = clampf(float(snapshot_data.get("life_points", _max_life)), 0.0, _max_life)
	var action_input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = (
		_action_restore_input(snapshot_data)
	)
	var action_result: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreResult = (
		_action_runtime.restore(
			action_input,
			_action_restore_rules(action_input.current_action)
		)
	)
	_runtime_spawn_serial = maxi(
		int(snapshot_data.get("runtime_spawn_serial", _runtime_spawn_serial)),
		0
	)
	_event_instance_id = String(
		snapshot_data.get("event_instance_id", _event_instance_id)
	)
	_restore_status_snapshot(snapshot_data)
	if action_result.restored_ranged_state:
		velocity = Vector2.ZERO
		_update_facing(_action_runtime.locked_direction())
		if action_result.resume_ranged_windup:
			_emit_attack_windup(_action_runtime.action_timer())
	if _action_runtime.is_armed():
		_restore_armed_explosion()
	elif _life_points <= 0.0:
		remove_from_group("active_enemies")
	_refresh_visuals()


func _action_restore_input(
	snapshot_data: Dictionary
) -> ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput:
	var input: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput = (
		ENEMY_ACTION_RUNTIME_SCRIPT.RestoreInput.new()
	)
	input.current_action = String(
		snapshot_data.get("current_action", "")
	)
	input.action_state = String(snapshot_data.get("action_state", ""))
	input.action_timer = float(snapshot_data.get("action_timer", 0.0))
	input.attack_cooldown_remaining = float(
		snapshot_data.get("attack_cooldown_remaining", 0.0)
	)
	input.attack_hit_committed = bool(
		snapshot_data.get("attack_hit_committed", false)
	)
	input.collateral_player_hit_committed = bool(
		snapshot_data.get(
			"collateral_player_hit_committed",
			false
		)
	)
	input.burst_shots_remaining = int(
		snapshot_data.get("burst_shots_remaining", 0)
	)
	input.locked_direction = _dict_to_vector(
		snapshot_data.get("locked_direction", {}),
		Vector2.ZERO
	)
	input.armed = bool(snapshot_data.get("armed", false))
	input.armed_from_chain = bool(
		snapshot_data.get("armed_from_chain", false)
	)
	input.has_exploded = bool(
		snapshot_data.get("has_exploded", false)
	)
	input.has_saved_burst_state = snapshot_data.has(
		"burst_shots_remaining"
	)
	input.has_valid_saved_action_timer = input.action_timer >= 0.0
	return input


func _action_restore_rules(
	requested_action_id: String
) -> ENEMY_ACTION_RUNTIME_SCRIPT.RestoreRules:
	var rules: ENEMY_ACTION_RUNTIME_SCRIPT.RestoreRules = (
		ENEMY_ACTION_RUNTIME_SCRIPT.RestoreRules.new()
	)
	if _brain.has_action(requested_action_id):
		rules.valid_action_ids.append(requested_action_id)
	rules.explode_action_id = ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	rules.ranged_action_id = ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
	var ranged_attack: Dictionary = _ranged_attack()
	rules.ranged_burst_count = int(ranged_attack.get("burst_count", 0))
	rules.ranged_windup = float(ranged_attack.get("windup", 0.0))
	rules.ranged_shot_interval = float(
		ranged_attack.get("shot_interval", 0.0)
	)
	rules.ranged_cooldown = float(ranged_attack.get("cooldown", 0.0))
	return rules


func _pool_reset() -> void:
	velocity = Vector2.ZERO
	_brain.reset()
	_action_runtime.reset()
	_base_max_life = 1.0
	_debug_ai_enabled = true
	_enemy_id = ""
	_event_instance_id = ""
	_gold_reward = 0
	_reward_snapshot.clear()
	_facing_sign = 1.0
	_focus_target = null
	_hit_radius = 0.0
	_home_position = Vector2.ZERO
	_life_points = 1.0
	_max_life = 1.0
	clear_movement_bounds()
	_move_speed = 0.0
	_navigation_mode = NAVIGATION_MODE_NONE
	_navigation_provider = null
	_clear_status_effects_for_reuse()
	_player_target = null
	_primary_target = null
	_damage_target_groups.clear()
	_runtime_spawn_serial = 0
	_separation_radius = 0.0
	_spawn_damage_multiplier = 1.0
	_spawn_health_multiplier = 1.0
	_cached_navigation_waypoint = Vector2.ZERO
	_has_cached_navigation_waypoint = false
	visible = true
	_set_collision_enabled(false)
	if has_meta("debug_test_arena_kind"):
		remove_meta("debug_test_arena_kind")
	if has_meta("debug_test_arena_home"):
		remove_meta("debug_test_arena_home")
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()
	_refresh_visuals()


func _pool_release() -> void:
	velocity = Vector2.ZERO
	_action_runtime.reset()
	remove_from_group("active_enemies")
	_clear_status_effects_for_reuse()
	clear_movement_bounds()
	_focus_target = null
	_brain.clear_runtime_state()
	_navigation_mode = NAVIGATION_MODE_NONE
	_navigation_provider = null
	_player_target = null
	_primary_target = null
	_damage_target_groups.clear()
	_gold_reward = 0
	_reward_snapshot.clear()
	_has_cached_navigation_waypoint = false
	_set_collision_enabled(false)
	if has_meta("debug_test_arena_kind"):
		remove_meta("debug_test_arena_kind")
	if has_meta("debug_test_arena_home"):
		remove_meta("debug_test_arena_home")
	_ensure_presentation()
	if _presentation != null:
		_presentation.reset_presentation()


func _choose_action() -> void:
	var decision: EnemyBrain.Decision = _brain.decide(
		_brain_sense_input(),
		_action_runtime.attack_cooldown_remaining()
	)
	_action_runtime.set_current_action(decision.action_id)
	_focus_target = _primary_target if decision.focus_primary_target else null
	_refresh_cached_navigation_waypoint()


func _brain_sense_input() -> EnemyBrain.SenseInput:
	var input: EnemyBrain.SenseInput = EnemyBrain.SenseInput.new()
	input.self_position = global_position
	input.home_position = _home_position
	if _primary_target == null or not is_instance_valid(_primary_target):
		return input
	input.target_available = true
	input.target_position = _primary_target.global_position
	input.direct_distance = global_position.distance_to(input.target_position)
	if _brain.player_weight() <= 0.0:
		return input
	var route_query: Dictionary = _active_navigation_query()
	input.route_reachable = bool(route_query.get("reachable", false))
	input.path_distance = (
		float(route_query.get("distance", INF))
		if input.route_reachable
		else INF
	)
	input.has_line_of_sight = _has_terrain_line_of_sight(
		global_position,
		input.target_position
	)
	input.has_clear_corridor = _has_clear_corridor(
		global_position,
		input.target_position,
		_hit_radius
	)
	return input


func _apply_current_action(delta: float) -> void:
	var current_action: String = _action_runtime.current_action()
	if current_action == ENEMY_AI_ACTIONS.AI_ACTION_ORBIT_TARGET:
		_move_in_direction(
			_path_band_direction(_movement_value("orbit_radius")),
			_action_speed_scale(current_action),
			delta
		)
		return
	if current_action == ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET:
		_arm_explosion(false)
		return
	if current_action == ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK:
		_start_melee_attack()
		return
	if current_action == ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET:
		_start_charge()
		return
	if current_action == ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK:
		_apply_ranged_attack(delta)
		return
	if current_action == ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME:
		_move_in_direction(
			_direction_to_cached_target(_home_position),
			_action_speed_scale(current_action),
			delta
		)
		return
	_move_in_direction(
		_movement_target_direction(),
		_action_speed_scale(current_action),
		delta
	)


func _apply_ranged_attack(delta: float) -> void:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return
	var target_direction: Vector2 = _focus_target.global_position - global_position
	if target_direction.length_squared() > 0.0:
		_update_facing(target_direction)
	var distance: float = target_direction.length()
	var attack: Dictionary = _current_attack()
	var keep_distance: float = float(attack.get("keep_distance", 0.0))
	var attack_range: float = float(attack.get("attack_range", 0.0))
	var route_query: Dictionary = _active_navigation_query()
	var route_distance: float = float(route_query.get("distance", distance)) if bool(route_query.get("reachable", false)) else distance
	if keep_distance > 0.0 and route_distance < keep_distance:
		_move_in_direction(
			_path_band_direction(keep_distance),
			_action_speed_scale(_action_runtime.current_action()),
			delta
		)
	elif attack_range > 0.0 and route_distance > attack_range * 0.82:
		_move_in_direction(
			_movement_direction_to(_focus_target.global_position, true),
			_action_speed_scale(_action_runtime.current_action()),
			delta
		)
	else:
		_move_in_direction(
			_path_band_direction(maxf(keep_distance, 1.0)),
			_action_speed_scale(_action_runtime.current_action()),
			delta
		)
	if (
		distance <= attack_range
		and _action_runtime.attack_cooldown_remaining() <= 0.0
		and _has_terrain_line_of_sight(global_position, _focus_target.global_position)
	):
		_start_ranged_burst(target_direction)


func _start_ranged_burst(
	target_direction: Vector2
) -> ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Result:
	return ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.start_burst(
		_action_runtime,
		_ranged_attack_config(_current_attack()),
		target_direction,
		_ranged_attack_ports_value()
	)


func _advance_ranged_attack(
	delta: float
) -> ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Result:
	return ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.advance(
		_action_runtime,
		_ranged_attack_config(_current_attack()),
		delta,
		_ranged_attack_ports_value()
	)


func _ranged_attack_config(
	attack: Dictionary
) -> ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Config:
	var config: ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Config = (
		ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Config.new()
	)
	config.windup = float(attack.get("windup", 0.0))
	config.burst_count = int(attack.get("burst_count", 0))
	config.shot_interval = float(attack.get("shot_interval", 0.0))
	config.cooldown = float(attack.get("cooldown", 0.0))
	var projectile: Dictionary = _dictionary_or_empty(
		attack.get("projectile", {})
	)
	config.projectile.pool_id = String(
		projectile.get("pool_id", POOL_IDS.BULLET_BASIC)
	)
	config.projectile.muzzle_distance = float(
		projectile.get("muzzle_distance", 0.0)
	)
	config.projectile.damage = (
		float(attack.get("damage", 0.0))
		* _spawn_damage_multiplier
	)
	config.projectile.speed = float(projectile.get("speed", 0.0))
	config.projectile.max_range = float(projectile.get("range", 0.0))
	config.projectile.element_id = String(attack.get("element_id", ""))
	config.projectile.damage_target_groups = (
		_damage_target_groups.duplicate()
	)
	config.projectile.hit_radius = float(
		projectile.get("hit_radius", 0.0)
	)
	config.projectile.lifetime = float(
		projectile.get("lifetime", 0.0)
	)
	config.projectile.source_team = TEAM_ENEMY
	config.projectile.target_team = TEAM_PLAYER
	return config


func _ranged_attack_ports_value(
) -> ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Ports:
	if _ranged_attack_ports == null:
		_ranged_attack_ports = (
			ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Ports.new(
				Callable(self, "_stop_ranged_attack_and_face"),
				Callable(self, "_emit_attack_windup"),
				Callable(self, "_materialize_ranged_projectile"),
				Callable(self, "_emit_ranged_attack_committed"),
				Callable(self, "_finish_ranged_attack")
			)
		)
	return _ranged_attack_ports


func _projectile_materializer_ports_value(
) -> ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.Ports:
	if _projectile_materializer_ports == null:
		_projectile_materializer_ports = (
			ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.Ports.new(
				Callable(PoolManager, "acquire"),
				Callable(self, "_configure_ranged_projectile")
			)
		)
	return _projectile_materializer_ports


func _stop_ranged_attack_and_face(direction: Vector2) -> void:
	velocity = Vector2.ZERO
	_update_facing(direction)


func _materialize_ranged_projectile(
	projectile: ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.Spec,
	target_direction: Vector2
) -> ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.Result:
	var request: ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.Request = (
		ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.Request.new()
	)
	request.spec = projectile
	request.source = self
	request.active_parent = get_parent()
	request.source_position = global_position
	request.target_direction = target_direction
	return ENEMY_PROJECTILE_MATERIALIZER_SCRIPT.materialize(
		request,
		_projectile_materializer_ports_value()
	)


func _configure_ranged_projectile(
	projectile: Node2D,
	stats: Dictionary,
	projectile_data: Dictionary,
	direction: Vector2,
	source: Node
) -> bool:
	projectile.call(
		"configure",
		stats,
		projectile_data,
		direction,
		source
	)
	return true


func _emit_ranged_attack_committed() -> void:
	var attack: Dictionary = _current_attack()
	attack_committed.emit(
		self,
		_action_runtime.current_action(),
		_attack_feedback_context(attack, 0.0, false)
	)


func _finish_ranged_attack() -> void:
	_focus_target = _primary_target


func _can_debug_drive_ranged_attack() -> bool:
	return (
		OS.is_debug_build()
		and _brain.has_action(
			ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
		)
		and (
			_action_runtime.current_action()
			== ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK
		)
	)


func _update_attack_state(delta: float) -> void:
	var ranged_result: ENEMY_RANGED_ATTACK_HANDLER_SCRIPT.Result = (
		_advance_ranged_attack(delta)
	)
	if ranged_result.handled:
		return
	var melee_result: ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Result = (
		_advance_melee_attack(delta)
	)
	if melee_result.handled:
		return
	var charge_result: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Result = (
		_advance_charge_attack(delta)
	)
	if charge_result.handled:
		return
	_action_runtime.advance_action_timer(delta)


func _start_melee_attack(
) -> ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Result:
	var request: ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.StartRequest = (
		ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.StartRequest.new()
	)
	request.focus_target_available = (
		_focus_target != null and is_instance_valid(_focus_target)
	)
	if request.focus_target_available:
		request.target_direction = (
			_focus_target.global_position - global_position
		)
	return ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.start(
		_action_runtime,
		_melee_attack_config(_current_attack()),
		request,
		_melee_attack_ports_value()
	)


func _advance_melee_attack(
	delta: float
) -> ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Result:
	return ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.advance(
		_action_runtime,
		_melee_attack_config(_current_attack()),
		delta,
		_melee_attack_ports_value()
	)


func _melee_attack_config(
	attack: Dictionary
) -> ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Config:
	var config: ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Config = (
		ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Config.new()
	)
	config.windup = float(attack.get("windup", 0.0))
	config.cooldown = float(attack.get("cooldown", 0.0))
	config.attack_range = float(attack.get("range", 0.0))
	config.arc_degrees = float(attack.get("arc_degrees", 0.0))
	config.base_damage = float(attack.get("damage", 0.0))
	config.element_id = String(attack.get("element_id", ""))
	return config


func _melee_attack_ports_value(
) -> ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Ports:
	if _melee_attack_ports == null:
		_melee_attack_ports = ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.Ports.new(
			Callable(self, "_emit_attack_windup"),
			Callable(self, "_melee_target_ports"),
			Callable(self, "_emit_melee_attack_committed"),
			Callable(self, "_finish_melee_attack")
		)
	return _melee_attack_ports


func _melee_target_ports(
) -> Array[ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.TargetPort]:
	var ports: Array[ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.TargetPort] = []
	for target: Node2D in _attack_targets():
		ports.append(ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.TargetPort.new(
			Callable(self, "_melee_target_available").bind(target),
			Callable(self, "_melee_target_relative_position").bind(target),
			Callable(self, "_melee_target_has_terrain_los").bind(target),
			Callable(self, "_apply_melee_damage").bind(target)
		))
	return ports


func _melee_target_available(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return not target.has_method("is_alive") or bool(target.call("is_alive"))


func _melee_target_relative_position(target: Node2D) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	return target.global_position - global_position


func _melee_target_has_terrain_los(target: Node2D) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and _has_terrain_line_of_sight(
			global_position,
			target.global_position
		)
	)


func _apply_melee_damage(
	base_damage: float,
	element_id: String,
	target: Node2D
) -> ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.DamageResult:
	var damage: Dictionary = _apply_attack_damage_values_to_target(
		target,
		base_damage,
		element_id
	)
	var result: ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.DamageResult = (
		ENEMY_MELEE_ATTACK_HANDLER_SCRIPT.DamageResult.new()
	)
	result.applied = bool(damage.get("applied", false))
	result.amount = float(damage.get("amount", 0.0))
	result.defeated = bool(damage.get("defeated", false))
	result.reason = String(damage.get("reason", ""))
	return result


func _emit_melee_attack_committed(attack_range: float) -> void:
	attack_committed.emit(
		self,
		_action_runtime.current_action(),
		_attack_feedback_context(
			{"range": attack_range},
			0.0,
			false
		)
	)


func _finish_melee_attack() -> void:
	_focus_target = _primary_target


func _can_debug_drive_melee_attack() -> bool:
	return (
		OS.is_debug_build()
		and _brain.has_action(ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK)
		and (
			_action_runtime.current_action()
			== ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK
		)
	)


func _start_charge() -> ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Result:
	var request: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.StartRequest = (
		ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.StartRequest.new()
	)
	request.focus_target_available = (
		_focus_target != null and is_instance_valid(_focus_target)
	)
	if request.focus_target_available:
		request.target_direction = (
			_focus_target.global_position - global_position
		)
	return ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.start(
		_action_runtime,
		_charge_attack_config(_current_attack()),
		request,
		_charge_attack_ports_value()
	)


func _advance_charge_attack(
	delta: float
) -> ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Result:
	var request: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.StepRequest = (
		ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.StepRequest.new()
	)
	request.delta = delta
	request.move_speed = _move_speed
	request.move_speed_multiplier = _status_move_speed_multiplier()
	return ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.advance(
		_action_runtime,
		_charge_attack_config(_current_attack()),
		request,
		_charge_attack_ports_value()
	)


func _charge_attack_config(
	attack: Dictionary
) -> ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Config:
	var config: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Config = (
		ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Config.new()
	)
	config.windup = float(attack.get("windup", 0.0))
	config.cooldown = float(attack.get("cooldown", 0.0))
	config.release_duration = float(
		attack.get("release_duration", 0.0)
	)
	config.speed_multiplier = float(
		attack.get("speed_multiplier", 0.0)
	)
	config.base_damage = float(attack.get("damage", 0.0))
	config.element_id = String(attack.get("element_id", ""))
	config.stop_on_hit = bool(attack.get("stop_on_hit", false))
	config.knockback_distance = float(
		attack.get("knockback_distance", 0.0)
	)
	config.knockback_duration = float(
		attack.get("knockback_duration", 0.0)
	)
	return config


func _charge_attack_ports_value(
) -> ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Ports:
	if _charge_attack_ports == null:
		_charge_attack_ports = ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.Ports.new(
			Callable(self, "_emit_attack_windup"),
			Callable(self, "_emit_charge_attack_committed"),
			Callable(self, "_move_charge_step"),
			Callable(self, "_charge_target_ports"),
			Callable(self, "_finish_charge_attack")
		)
	return _charge_attack_ports


func _emit_charge_attack_committed() -> void:
	var attack: Dictionary = _current_attack()
	attack_committed.emit(
		self,
		_action_runtime.current_action(),
		_attack_feedback_context(attack, 0.0, false)
	)


func _move_charge_step(
	motion: Vector2,
	locked_direction: Vector2
) -> ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.MovementResult:
	var result: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.MovementResult = (
		ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.MovementResult.new()
	)
	result.previous_position = global_position
	_update_facing(locked_direction)
	result.collided = _move_with_collision(motion, false)
	var before_bounds: Vector2 = global_position
	_apply_movement_bounds()
	if not global_position.is_equal_approx(before_bounds):
		result.collided = true
	result.current_position = global_position
	return result


func _charge_target_ports(
) -> Array[ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.TargetPort]:
	var ports: Array[ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.TargetPort] = [
		_charge_target_port(_primary_target, false),
	]
	if _player_target != _primary_target:
		ports.append(_charge_target_port(_player_target, true))
	return ports


func _charge_target_port(
	target: Node2D,
	uses_collateral_flag: bool
) -> ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.TargetPort:
	return ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.TargetPort.new(
		uses_collateral_flag,
		target == _player_target,
		Callable(self, "_charge_sweep_hits_target").bind(target),
		Callable(self, "_apply_charge_damage").bind(target),
		Callable(self, "_charge_target_can_knockback").bind(target),
		Callable(self, "_apply_charge_knockback").bind(target)
	)


func _finish_charge_attack() -> void:
	_focus_target = _primary_target


func _can_debug_drive_charge_attack() -> bool:
	return (
		OS.is_debug_build()
		and _brain.has_action(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
		and (
			_action_runtime.current_action()
			== ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
		)
	)


func _attack_targets() -> Array[Node2D]:
	var targets: Array[Node2D] = []
	if _primary_target != null and is_instance_valid(_primary_target):
		targets.append(_primary_target)
	if (
		_player_target != null
		and is_instance_valid(_player_target)
		and _player_target != _primary_target
	):
		targets.append(_player_target)
	return targets


func _charge_sweep_hits_target(
	from_position: Vector2,
	to_position: Vector2,
	target: Node2D
) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if (
		target.has_method("is_alive")
		and not bool(target.call("is_alive"))
	):
		return false
	var target_radius: float = (
		float(target.call("hit_radius"))
		if target.has_method("hit_radius")
		else 0.0
	)
	var hit_distance: float = maxf(_hit_radius + target_radius, 1.0)
	return (
		_distance_to_segment(
			target.global_position,
			from_position,
			to_position
		)
		<= hit_distance
	)


func _apply_charge_damage(
	base_damage: float,
	element_id: String,
	target: Node2D
) -> ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.DamageResult:
	var damage: Dictionary = _apply_attack_damage_values_to_target(
		target,
		base_damage,
		element_id
	)
	var result: ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.DamageResult = (
		ENEMY_CHARGE_ATTACK_HANDLER_SCRIPT.DamageResult.new()
	)
	result.applied = bool(damage.get("applied", false))
	result.amount = float(damage.get("amount", 0.0))
	result.defeated = bool(damage.get("defeated", false))
	result.reason = String(damage.get("reason", ""))
	return result


func _charge_target_can_knockback(target: Node2D) -> bool:
	return (
		target != null
		and is_instance_valid(target)
		and target.has_method("apply_external_knockback")
	)


func _apply_charge_knockback(
	direction: Vector2,
	distance: float,
	duration: float,
	target: Node2D
) -> void:
	if not _charge_target_can_knockback(target):
		return
	target.call(
		"apply_external_knockback",
		direction,
		distance,
		duration
	)


func _apply_attack_damage_to_target(
	target: Node2D,
	attack: Dictionary
) -> Dictionary:
	return _apply_attack_damage_values_to_target(
		target,
		float(attack.get("damage", 0.0)),
		String(attack.get("element_id", ""))
	)


func _apply_attack_damage_values_to_target(
	target: Node2D,
	base_damage: float,
	element_id: String
) -> Dictionary:
	if target == null or not is_instance_valid(target):
		return {
			"applied": false,
			"amount": 0.0,
			"defeated": false,
			"reason": "invalid_target",
		}
	var target_team: String = TEAM_PLAYER
	if target.has_method("combat_team_id"):
		target_team = String(target.call("combat_team_id"))
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		maxf(base_damage, 0.0) * _spawn_damage_multiplier,
		element_id,
		self,
		target,
		TEAM_ENEMY,
		target_team
	)
	return Combat.apply_damage(target, info)


func _arm_explosion(
	from_chain: bool
) -> ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Result:
	var action: Dictionary = _action_by_id(
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)
	var request: ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.ArmRequest = (
		ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.ArmRequest.new()
	)
	request.action_available = not action.is_empty()
	request.from_chain = from_chain
	return ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.arm(
		_action_runtime,
		_explosion_attack_config(action),
		request,
		_explosion_attack_ports_value()
	)


func _update_armed_state(
	delta: float
) -> ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Result:
	return ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.advance(
		_action_runtime,
		_explosion_attack_config(_action_by_id(
			ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
		)),
		delta,
		_explosion_attack_ports_value()
	)


func _restore_armed_explosion(
) -> ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Result:
	return ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.restore_armed(
		_action_runtime,
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET,
		_explosion_attack_ports_value()
	)


func _explosion_attack_config(
	action: Dictionary
) -> ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Config:
	var attack: Dictionary = _attack_from_action(action)
	var config: ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Config = (
		ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Config.new()
	)
	config.explode_action_id = ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	config.windup = float(attack.get("windup", 0.0))
	config.base_damage = float(attack.get("damage", 0.0))
	config.element_id = String(attack.get("element_id", ""))
	config.radius = float(attack.get("radius", 0.0))
	return config


func _explosion_attack_ports_value(
) -> ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Ports:
	if _explosion_attack_ports == null:
		_explosion_attack_ports = (
			ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.Ports.new(
				Callable(self, "_clear_explosion_focus"),
				Callable(self, "_stop_explosion_movement"),
				Callable(self, "_set_collision_enabled"),
				Callable(self, "_emit_attack_windup"),
				Callable(self, "_refresh_visuals"),
				Callable(self, "_explosion_source_position"),
				Callable(self, "_emit_explosion_committed"),
				Callable(self, "_explosion_direct_target_ports"),
				Callable(self, "_explosion_enemy_target_ports"),
				Callable(self, "_has_terrain_line_of_sight"),
				Callable(self, "_finish_explosion")
			)
		)
	return _explosion_attack_ports


func _clear_explosion_focus() -> void:
	_focus_target = null


func _stop_explosion_movement() -> void:
	velocity = Vector2.ZERO


func _explosion_source_position() -> Vector2:
	return global_position


func _emit_explosion_committed() -> void:
	var attack: Dictionary = _current_attack()
	attack_committed.emit(
		self,
		_action_runtime.current_action(),
		_attack_feedback_context(attack, 0.0, true)
	)


func _explosion_direct_target_ports(
) -> Array[ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.DirectTargetPort]:
	var ports: Array[ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.DirectTargetPort] = []
	for target: Node2D in _attack_targets():
		ports.append(
			ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.DirectTargetPort.new(
				Callable(self, "_explosion_target_is_valid").bind(target),
				Callable(self, "_explosion_target_position").bind(target),
				Callable(self, "_apply_explosion_damage").bind(target)
			)
		)
	return ports


func _explosion_enemy_target_ports(
) -> Array[ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.EnemyTargetPort]:
	var ports: Array[ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.EnemyTargetPort] = []
	for node: Node in get_tree().get_nodes_in_group("active_enemies"):
		if not node is Enemy:
			continue
		var target: Enemy = node as Enemy
		ports.append(
			ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.EnemyTargetPort.new(
				Callable(self, "_explosion_target_is_valid").bind(target),
				Callable(self, "_explosion_target_is_source").bind(target),
				Callable(self, "_explosion_target_is_armed").bind(target),
				Callable(self, "_explosion_target_is_alive").bind(target),
				Callable(self, "_explosion_target_position").bind(target),
				Callable(self, "_explosion_target_spawn_serial").bind(target),
				Callable(self, "_apply_explosion_damage").bind(target)
			)
		)
	return ports


func _explosion_target_is_valid(target: Node2D) -> bool:
	return target != null and is_instance_valid(target)


func _explosion_target_is_source(target: Enemy) -> bool:
	return target == self


func _explosion_target_is_armed(target: Enemy) -> bool:
	return target != null and is_instance_valid(target) and target.is_armed()


func _explosion_target_is_alive(target: Enemy) -> bool:
	return target != null and is_instance_valid(target) and target.is_alive()


func _explosion_target_position(target: Node2D) -> Vector2:
	if not _explosion_target_is_valid(target):
		return Vector2.ZERO
	return target.global_position


func _explosion_target_spawn_serial(target: Enemy) -> int:
	return (
		target.runtime_spawn_serial()
		if target != null and is_instance_valid(target)
		else 0
	)


func _apply_explosion_damage(
	base_damage: float,
	element_id: String,
	target: Node2D
) -> ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.DamageResult:
	var damage: Dictionary = _apply_attack_damage_values_to_target(
		target,
		base_damage,
		element_id
	)
	var result: ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.DamageResult = (
		ENEMY_EXPLOSION_ATTACK_HANDLER_SCRIPT.DamageResult.new()
	)
	result.applied = bool(damage.get("applied", false))
	result.amount = float(damage.get("amount", 0.0))
	result.defeated = bool(damage.get("defeated", false))
	result.reason = String(damage.get("reason", ""))
	return result


func _finish_explosion() -> void:
	_life_points = 0.0
	_finish_defeat(
		false,
		false,
		ENEMY_DEFEAT_CAUSES.EXPLODER_DETONATION
	)


func _can_debug_drive_explosion_attack() -> bool:
	return (
		OS.is_debug_build()
		and _brain.has_action(
			ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
		)
	)


func _emit_attack_windup(remaining: float) -> void:
	var attack: Dictionary = _current_attack()
	attack_windup_started.emit(
		self,
		_action_runtime.current_action(),
		_attack_feedback_context(attack, remaining, false)
	)


func _attack_feedback_context(
	attack: Dictionary,
	duration: float,
	detached: bool
) -> Dictionary:
	var context: Dictionary = {
		"owner": null if detached else self,
		"world_position": global_position,
		"follow_owner": false,
		"duration": duration,
		"rotation": _action_runtime.locked_direction().angle()
			if _action_runtime.locked_direction().length_squared() > 0.0
			else 0.0,
	}
	if (
		_action_runtime.current_action()
		== ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	):
		var radius: float = float(attack.get("radius", 0.0))
		context["scale"] = (
			Vector2.ONE * radius / (23.0 if detached else 36.0)
		)
	elif (
		_action_runtime.current_action()
		== ENEMY_AI_ACTIONS.AI_ACTION_MELEE_ATTACK
	):
		var melee_range: float = float(attack.get("range", 0.0))
		context["scale"] = Vector2.ONE * melee_range
	elif (
		_action_runtime.current_action()
		== ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET
	):
		var lane_length: float = float(attack.get("trigger_range", 0.0))
		var target_radius: float = (
			float(_primary_target.call("hit_radius"))
			if (
				_primary_target != null
				and is_instance_valid(_primary_target)
				and _primary_target.has_method("hit_radius")
			)
			else 0.0
		)
		context["scale"] = Vector2(
			lane_length,
			maxf(_hit_radius + target_radius, 1.0)
		)
	return context


func _finish_defeat(
	counts_as_kill: bool,
	drops_rewards: bool,
	cause_id: String
) -> void:
	remove_from_group("active_enemies")
	defeated.emit(
		self,
		_gold_reward,
		counts_as_kill,
		drops_rewards,
		cause_id
	)
	_ensure_presentation()
	if _presentation != null:
		_presentation.play_defeat()
	else:
		PoolManager.release(self)


func _distance_to_segment(
	point: Vector2,
	segment_start: Vector2,
	segment_end: Vector2
) -> float:
	var segment: Vector2 = segment_end - segment_start
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(segment_start)
	var ratio: float = clampf(
		(point - segment_start).dot(segment) / length_squared,
		0.0,
		1.0
	)
	return point.distance_to(segment_start + segment * ratio)


func _move_in_direction(direction: Vector2, speed_scale: float, delta: float) -> void:
	if direction.length_squared() <= 0.0:
		return
	var normalized: Vector2 = direction.normalized()
	_update_facing(normalized)
	_move_with_collision(
		normalized
		* _move_speed
		* _status_move_speed_multiplier()
		* maxf(speed_scale, 0.0)
		* delta
	)
	_apply_movement_bounds()


func _movement_target_direction() -> Vector2:
	if not _brain.has_movement_target():
		return Vector2.ZERO
	if _brain.perception_state() == EnemyBrain.PERCEPTION_MEMORY:
		return _direction_to_cached_target(
			_brain.movement_target_position()
		)
	if _focus_target != null and is_instance_valid(_focus_target):
		return _movement_direction_to(_focus_target.global_position, true)
	return _direction_to_cached_target(_brain.movement_target_position())


func _orbit_direction() -> Vector2:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return Vector2.ZERO
	var from_target: Vector2 = global_position - _focus_target.global_position
	if from_target.length_squared() <= 0.0:
		from_target = Vector2.RIGHT
	var radial: Vector2 = from_target.normalized()
	var tangent: Vector2 = Vector2(-radial.y, radial.x) * _orbit_sign()
	var orbit_radius: float = maxf(_movement_value("orbit_radius"), 1.0)
	var distance: float = global_position.distance_to(_focus_target.global_position)
	if distance > orbit_radius:
		return (_focus_target.global_position - global_position).normalized() + tangent * 0.7
	return radial + tangent * 0.85


func _movement_direction_to(target_position: Vector2, use_active_field: bool) -> Vector2:
	var direct_direction: Vector2 = target_position - global_position
	if _navigation_provider == null or not is_instance_valid(_navigation_provider):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if _has_clear_corridor(global_position, target_position, _hit_radius):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	var use_player_flow_field: bool = (
		use_active_field
		and _player_target != null
		and is_instance_valid(_player_target)
		and target_position.is_equal_approx(
			_player_target.global_position
		)
	)
	var query: Dictionary = (
		_active_navigation_query()
		if use_player_flow_field
		else _navigation_query(global_position, target_position)
	)
	if not bool(query.get("reachable", false)):
		_navigation_mode = NAVIGATION_MODE_NONE
		return Vector2.ZERO
	_navigation_mode = (
		NAVIGATION_MODE_FLOW_FIELD
		if use_player_flow_field
		else NAVIGATION_MODE_LOCAL_ASTAR
	)
	return (query.get("next_position", global_position) as Vector2) - global_position


func _direction_to_cached_target(target_position: Vector2) -> Vector2:
	var direct_direction: Vector2 = target_position - global_position
	if _navigation_provider == null or not is_instance_valid(_navigation_provider):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if _has_clear_corridor(global_position, target_position, _hit_radius):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return direct_direction
	if not _has_cached_navigation_waypoint:
		_navigation_mode = NAVIGATION_MODE_NONE
		return Vector2.ZERO
	_navigation_mode = NAVIGATION_MODE_LOCAL_ASTAR
	return _cached_navigation_waypoint - global_position


func _path_band_direction(desired_distance: float) -> Vector2:
	if _focus_target == null or not is_instance_valid(_focus_target):
		return Vector2.ZERO
	if _focus_target != _player_target:
		if _has_clear_corridor(
			global_position,
			_focus_target.global_position,
			_hit_radius
		):
			_navigation_mode = NAVIGATION_MODE_DIRECT
			return _orbit_direction()
		return _movement_direction_to(
			_focus_target.global_position,
			false
		)
	if _navigation_provider == null or not is_instance_valid(_navigation_provider):
		_navigation_mode = NAVIGATION_MODE_DIRECT
		return _orbit_direction()
	if not (
		_navigation_provider.has_method("world_to_global_cell")
		and _navigation_provider.has_method("global_cell_to_world")
	):
		return _movement_direction_to(_focus_target.global_position, true)
	var current_cell: Vector2i = _navigation_provider.call("world_to_global_cell", global_position) as Vector2i
	var from_target: Vector2 = global_position - _focus_target.global_position
	if from_target.length_squared() <= 0.0:
		from_target = Vector2.RIGHT
	var tangent: Vector2 = Vector2(-from_target.y, from_target.x).normalized() * _orbit_sign()
	var best_direction: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var safe_desired_distance: float = maxf(desired_distance, 1.0)
	for offset: Vector2i in NAVIGATION_NEIGHBOR_OFFSETS:
		var candidate_cell: Vector2i = current_cell + offset
		var candidate_position: Vector2 = _navigation_provider.call("global_cell_to_world", candidate_cell) as Vector2
		if not _has_clear_corridor(global_position, candidate_position, _hit_radius):
			continue
		var query: Dictionary = _navigation_provider.call("navigation_query_to_active_target", candidate_position) as Dictionary
		if not bool(query.get("reachable", false)):
			continue
		var route_distance: float = float(query.get("distance", INF))
		var direction: Vector2 = (candidate_position - global_position).normalized()
		var distance_score: float = -absf(route_distance - safe_desired_distance) / safe_desired_distance
		var tangent_score: float = direction.dot(tangent) * PATH_TANGENT_SCORE_WEIGHT
		var score: float = distance_score + tangent_score
		if score > best_score + SCORE_EPSILON:
			best_score = score
			best_direction = candidate_position - global_position
	if best_direction.length_squared() <= 0.0:
		return _movement_direction_to(_focus_target.global_position, true)
	_navigation_mode = NAVIGATION_MODE_FLOW_FIELD
	return best_direction


func _refresh_cached_navigation_waypoint() -> void:
	_has_cached_navigation_waypoint = false
	_cached_navigation_waypoint = Vector2.ZERO
	if _navigation_provider == null or not is_instance_valid(_navigation_provider):
		return
	var target_position: Vector2 = Vector2.ZERO
	if (
		_action_runtime.current_action()
		== ENEMY_AI_ACTIONS.AI_ACTION_GUARD_HOME
	):
		target_position = _home_position
	elif (
		_brain.perception_state() == EnemyBrain.PERCEPTION_MEMORY
		and _brain.has_movement_target()
	):
		target_position = _brain.movement_target_position()
	else:
		return
	var query: Dictionary = _navigation_query(global_position, target_position)
	if not bool(query.get("reachable", false)):
		return
	_cached_navigation_waypoint = query.get("next_position", Vector2.ZERO) as Vector2
	_has_cached_navigation_waypoint = true


func _update_ai_timers(delta: float) -> void:
	_action_runtime.advance_attack_cooldown(delta)
	_brain.advance_memory(delta)


func _is_attack_state_active() -> bool:
	return _action_runtime.is_attack_state_active()


func _start_hit_flash() -> void:
	_ensure_presentation()
	if _presentation != null:
		_presentation.play_hit()


func _update_facing(direction: Vector2) -> void:
	var previous_sign: float = _facing_sign
	if direction.x > 0.01:
		_facing_sign = 1.0
	elif direction.x < -0.01:
		_facing_sign = -1.0
	if not is_equal_approx(previous_sign, _facing_sign):
		_refresh_visuals()


func _refresh_visuals() -> void:
	_ensure_presentation()
	if _presentation == null:
		return
	var radius: float = maxf(_hit_radius, 8.0)
	_presentation.configure_visual(
		fill_color,
		hit_flash_color,
		defeat_feedback_color,
		Vector2(radius * _facing_sign, radius)
	)
	_refresh_attack_visuals()


func _refresh_attack_visuals() -> void:
	var exploder_core_outline: Polygon2D = get_node_or_null(
		"Visual/ExploderCoreOutline"
	) as Polygon2D
	var exploder_core: Polygon2D = get_node_or_null(
		"Visual/ExploderCore"
	) as Polygon2D
	var bulwark_armor_outline: Polygon2D = get_node_or_null(
		"Visual/BulwarkArmorOutline"
	) as Polygon2D
	var bulwark_armor: Polygon2D = get_node_or_null(
		"Visual/BulwarkArmor"
	) as Polygon2D
	var is_exploder: bool = _has_action(
		ENEMY_AI_ACTIONS.AI_ACTION_EXPLODE_TARGET
	)
	var charge_attack: Dictionary = _attack_from_action(
		_action_by_id(ENEMY_AI_ACTIONS.AI_ACTION_CHARGE_TARGET)
	)
	var is_ram_bulwark: bool = (
		bool(charge_attack.get("stop_on_hit", false))
		and float(charge_attack.get("knockback_distance", 0.0)) > 0.0
	)
	if exploder_core_outline != null:
		exploder_core_outline.visible = is_exploder
		exploder_core_outline.color = Color(0.12, 0.02, 0.01, 0.96)
	if exploder_core != null:
		exploder_core.visible = is_exploder
		exploder_core.color = (
			Color(1.0, 0.16, 0.04, 1.0)
			if _action_runtime.is_armed()
			else Color(1.0, 0.68, 0.12, 1.0)
		)
	if bulwark_armor_outline != null:
		bulwark_armor_outline.visible = is_ram_bulwark
		bulwark_armor_outline.color = Color(0.08, 0.055, 0.035, 0.98)
	if bulwark_armor != null:
		bulwark_armor.visible = is_ram_bulwark
		bulwark_armor.color = Color(0.94, 0.72, 0.35, 1.0)


func _ensure_presentation() -> void:
	if _presentation != null and is_instance_valid(_presentation):
		return
	_presentation = get_node_or_null("Presentation") as ActorPresentationController
	if _presentation == null:
		push_error("[Enemy] missing scene-authored Presentation")
		return
	if not _presentation.defeat_finished.is_connected(_on_defeat_presentation_finished):
		_presentation.defeat_finished.connect(_on_defeat_presentation_finished)


func _on_defeat_presentation_finished() -> void:
	if is_inside_tree() and is_defeat_feedback_active():
		PoolManager.release(self)


func _status_move_speed_multiplier() -> float:
	return status_stat_multiplier(STATS.MOVE_SPEED)


func _apply_center_separation() -> void:
	var offset: Vector2 = Vector2.ZERO
	if _separation_radius > 0.0:
		for other: Node in get_tree().get_nodes_in_group("active_enemies"):
			offset += _enemy_separation_offset(other)
	offset += _target_separation_offset()

	if offset.length_squared() > 0.0:
		_move_with_collision(offset)
		_apply_movement_bounds()


func _enemy_separation_offset(other: Node) -> Vector2:
	if other == self or not other is Node2D or not other.has_method("separation_radius"):
		return Vector2.ZERO
	if other.has_method("is_alive") and not bool(other.call("is_alive")):
		return Vector2.ZERO

	var other_enemy: Node2D = other as Node2D
	var minimum_distance: float = _separation_radius + float(other.call("separation_radius"))
	return _separation_offset_from(other_enemy.global_position, minimum_distance, 0.5)


func _target_separation_offset() -> Vector2:
	if (
		_primary_target == null
		or not is_instance_valid(_primary_target)
		or not _primary_target.has_method("separation_radius")
	):
		return Vector2.ZERO

	var target_separation_radius: float = float(
		_primary_target.call("separation_radius")
	)
	var minimum_distance: float = _separation_radius + target_separation_radius
	return _separation_offset_from(
		_primary_target.global_position,
		minimum_distance,
		1.0
	)


func _separation_offset_from(other_position: Vector2, minimum_distance: float, strength: float) -> Vector2:
	if minimum_distance <= 0.0:
		return Vector2.ZERO

	var to_self: Vector2 = global_position - other_position
	var current_distance: float = to_self.length()
	if current_distance >= minimum_distance:
		return Vector2.ZERO

	var direction: Vector2 = _separation_direction(to_self)
	return direction * (minimum_distance - current_distance) * strength


func _separation_direction(to_self: Vector2) -> Vector2:
	if to_self.length_squared() > 0.0:
		return to_self.normalized()
	var angle: float = float(int(get_instance_id()) % 360) * TAU / 360.0
	return Vector2.RIGHT.rotated(angle)


func _movement_value(key: String) -> float:
	return _brain.movement_value(key)


func _active_navigation_query() -> Dictionary:
	if (
		_primary_target != null
		and is_instance_valid(_primary_target)
		and _primary_target != _player_target
	):
		return _navigation_query(
			global_position,
			_primary_target.global_position
		)
	if (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
		and _navigation_provider.has_method("navigation_query_to_active_target")
	):
		return _navigation_provider.call("navigation_query_to_active_target", global_position) as Dictionary
	if _primary_target == null or not is_instance_valid(_primary_target):
		return {"reachable": false, "distance": INF}
	return {
		"reachable": true,
		"distance": global_position.distance_to(_primary_target.global_position),
		"next_position": _primary_target.global_position,
		"target_position": _primary_target.global_position,
	}


func _navigation_query(from_position: Vector2, target_position: Vector2) -> Dictionary:
	if (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
		and _navigation_provider.has_method("navigation_query")
	):
		return _navigation_provider.call("navigation_query", from_position, target_position) as Dictionary
	return {
		"reachable": true,
		"distance": from_position.distance_to(target_position),
		"next_position": target_position,
		"target_position": target_position,
	}


func _has_terrain_line_of_sight(from_position: Vector2, target_position: Vector2) -> bool:
	if (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
		and _navigation_provider.has_method("has_terrain_line_of_sight")
	):
		return bool(_navigation_provider.call("has_terrain_line_of_sight", from_position, target_position))
	return true


func _has_clear_corridor(from_position: Vector2, target_position: Vector2, clearance: float) -> bool:
	if (
		_navigation_provider != null
		and is_instance_valid(_navigation_provider)
		and _navigation_provider.has_method("has_clear_corridor")
	):
		return bool(_navigation_provider.call("has_clear_corridor", from_position, target_position, clearance))
	return true


func _action_speed_scale(action_id: String) -> float:
	return _brain.action_speed_scale(action_id)


func _action_by_id(action_id: String) -> Dictionary:
	return _brain.action(action_id)


func _has_action(action_id: String) -> bool:
	return _brain.has_action(action_id)


func _attack_from_action(action: Dictionary) -> Dictionary:
	return _dictionary_or_empty(action.get("attack", {}))


func _current_attack() -> Dictionary:
	return _attack_from_action(
		_action_by_id(_action_runtime.current_action())
	)


func _ranged_attack() -> Dictionary:
	return _attack_from_action(
		_brain.action(ENEMY_AI_ACTIONS.AI_ACTION_RANGED_ATTACK)
	)


func _scaled_attack_damage(attack: Dictionary) -> float:
	return (
		maxf(float(attack.get("damage", 0.0)), 0.0)
		* _spawn_damage_multiplier
	)


func _attack_display_range(attack: Dictionary) -> float:
	for key: String in ["radius", "range", "trigger_range", "attack_range"]:
		if attack.has(key):
			return maxf(float(attack.get(key, 0.0)), 0.0)
	return 0.0


func _orbit_sign() -> float:
	return 1.0 if int(get_instance_id()) % 2 == 0 else -1.0


## Compatibility test seam for the pre-event player-only attack path.
func _apply_attack_damage_to_player(
	attack: Dictionary
) -> Dictionary:
	return _apply_attack_damage_to_target(
		_player_target,
		attack
	)


func _target_mode() -> String:
	return (
		TARGET_MODE_EVENT_PRIMARY
		if _primary_target != null
		and is_instance_valid(_primary_target)
		and _primary_target != _player_target
		else TARGET_MODE_PLAYER
	)


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _canonical_reward_snapshot(raw_value: Variant) -> Dictionary:
	var reward_snapshot: Dictionary = _dictionary_or_empty(raw_value)
	if reward_snapshot.is_empty():
		return {}
	if reward_snapshot.has("valid"):
		reward_snapshot["valid"] = bool(reward_snapshot["valid"])
	if reward_snapshot.has("gold_reward"):
		reward_snapshot["gold_reward"] = int(reward_snapshot["gold_reward"])
	if reward_snapshot.has("spawn_tier"):
		reward_snapshot["spawn_tier"] = int(reward_snapshot["spawn_tier"])
	for field_name: String in [
		"base_coefficient",
		"difficulty_coefficient",
		"monster_value_multiplier",
		"specialization_multiplier",
		"time_multiplier",
		"random_multiplier",
	]:
		if reward_snapshot.has(field_name):
			reward_snapshot[field_name] = float(reward_snapshot[field_name])
	return reward_snapshot


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _node2d_or_null(raw_value: Variant) -> Node2D:
	if raw_value is Node2D and is_instance_valid(raw_value):
		return raw_value as Node2D
	return null


func _string_array(raw_value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		var value: String = String(item)
		if not value.is_empty():
			result.append(value)
	return result


func _vector_to_dict(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _dict_to_vector(raw_value: Variant, fallback: Vector2) -> Vector2:
	if not raw_value is Dictionary:
		return fallback
	var value: Dictionary = raw_value as Dictionary
	return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))


func _apply_movement_bounds() -> void:
	if not _has_movement_bounds:
		return
	global_position = _clamp_to_movement_bounds(global_position)


func _clamp_to_movement_bounds(world_position: Vector2) -> Vector2:
	if not _has_movement_bounds:
		return world_position
	return Vector2(
		clampf(world_position.x, _movement_bounds.position.x, _movement_bounds.end.x),
		clampf(world_position.y, _movement_bounds.position.y, _movement_bounds.end.y)
	)


func _move_with_collision(
	motion: Vector2,
	allow_slide: bool = true
) -> bool:
	if motion.length_squared() <= 0.0:
		return false
	var collision: KinematicCollision2D = move_and_collide(motion)
	if collision == null:
		return false
	if not allow_slide:
		return true
	var slide_motion: Vector2 = collision.get_remainder().slide(collision.get_normal())
	if slide_motion.length_squared() > 0.0:
		move_and_collide(slide_motion)
	return true


func _configure_collision_shape() -> void:
	var collision_shape: CollisionShape2D = _collision_shape_node()
	if collision_shape == null:
		push_error("[Enemy] missing CollisionShape2D scene node")
		return
	var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
	if circle_shape == null:
		circle_shape = CircleShape2D.new()
		collision_shape.shape = circle_shape
	circle_shape.radius = maxf(_hit_radius, 1.0)
	collision_shape.disabled = false


func _set_collision_enabled(enabled: bool) -> void:
	var collision_shape: CollisionShape2D = _collision_shape_node()
	if collision_shape != null:
		collision_shape.disabled = not enabled


func _collision_shape_node() -> CollisionShape2D:
	if _collision_shape == null or not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	return _collision_shape


func _ensure_status_effect_component() -> void:
	if _status_effect_component != null and is_instance_valid(_status_effect_component):
		_status_effect_component.call("configure_ability_tag_owner", self)
		return
	_status_effect_component = get_node_or_null("StatusEffectComponent")
	if _status_effect_component == null:
		push_error("[Enemy] missing scene-authored StatusEffectComponent")
		return
	_status_effect_component.call("configure_ability_tag_owner", self)


func _status_effect_snapshot() -> Dictionary:
	_ensure_status_effect_component()
	if _status_effect_component == null:
		return {}
	return _status_effect_component.call("snapshot") as Dictionary


func _restore_status_snapshot(snapshot_data: Dictionary) -> void:
	_owned_tag_counts.clear()
	var raw_tag_counts: Variant = snapshot_data.get("owned_tag_counts", {})
	var has_owned_tag_snapshot: bool = snapshot_data.has("owned_tag_counts") and raw_tag_counts is Dictionary
	if has_owned_tag_snapshot:
		for tag_id: Variant in (raw_tag_counts as Dictionary).keys():
			var count: int = maxi(int((raw_tag_counts as Dictionary)[tag_id]), 0)
			if count <= 0:
				continue
			var tag: String = String(tag_id)
			if _is_valid_ability_tag(tag):
				_owned_tag_counts[tag] = count
	else:
		var raw_owned_tags: Variant = snapshot_data.get("owned_tags", [])
		has_owned_tag_snapshot = raw_owned_tags is Array
		if raw_owned_tags is Array:
			for tag_id: Variant in raw_owned_tags as Array:
				_add_owned_tag_count(String(tag_id))

	var raw_status_effects: Variant = snapshot_data.get("status_effects", {})
	if _status_effect_component != null and raw_status_effects is Dictionary:
		_status_effect_component.call("restore_snapshot", raw_status_effects, not has_owned_tag_snapshot)


func _clear_status_effects_for_reuse() -> void:
	if _status_effect_component != null and is_instance_valid(_status_effect_component):
		_status_effect_component.call("clear", false)
	_owned_tag_counts.clear()


func _add_owned_tag_count(tag_id: String) -> bool:
	if not _is_valid_ability_tag(tag_id):
		return false
	_owned_tag_counts[tag_id] = int(_owned_tag_counts.get(tag_id, 0)) + 1
	return true


func _remove_owned_tag_count(tag_id: String) -> bool:
	if not _owned_tag_counts.has(tag_id):
		return false
	var next_count: int = int(_owned_tag_counts[tag_id]) - 1
	if next_count <= 0:
		_owned_tag_counts.erase(tag_id)
	else:
		_owned_tag_counts[tag_id] = next_count
	return true


func _is_valid_ability_tag(tag_id: String) -> bool:
	if tag_id.is_empty():
		return false
	return ABILITY_TAGS.VALUES.has(tag_id)


func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source.keys():
		result.append(String(key))
	result.sort()
	return result
