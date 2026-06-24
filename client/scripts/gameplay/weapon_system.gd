# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §4
class_name WeaponSystem
extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

const REPLAY_PARTICIPANT_ID: String = "player_0"

var _player: Node2D = null
var _active_parent: Node = null
var _base_stats: Dictionary = {}
var _runtime_stats: Dictionary = {}
var _stat_additions: Dictionary = {}
var _stat_multipliers: Dictionary = {}
var _temporary_modifiers: Array[Dictionary] = []
var _weapon_data: Dictionary = {}
var _cooldown_remaining: float = 0.0
var _replay_fire_pressed: bool = false


func _process(delta: float) -> void:
	_record_replay_fire_action_state()
	if _player == null or _weapon_data.is_empty():
		return
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	_update_temporary_modifiers(scaled_delta)
	_cooldown_remaining = maxf(_cooldown_remaining - scaled_delta, 0.0)
	if not _is_fire_action_pressed():
		return
	if _cooldown_remaining > 0.0:
		return

	_fire_once()
	var fire_rate: float = float(_runtime_stats.get(STATS.FIRE_RATE, 1.0))
	_cooldown_remaining = 1.0 / maxf(fire_rate, 0.01)


func configure(player: Node2D, active_parent: Node, weapon_data: Dictionary) -> void:
	_player = player
	_active_parent = active_parent
	_weapon_data = weapon_data.duplicate(true)
	_base_stats = _weapon_data.get("base_stats", {}).duplicate(true)
	_stat_additions.clear()
	_stat_multipliers.clear()
	_temporary_modifiers.clear()
	_rebuild_runtime_stats()
	_cooldown_remaining = 0.0
	_replay_fire_pressed = false


func apply_modifiers(modifiers: Array) -> void:
	for raw_modifier: Variant in modifiers:
		_accumulate_modifier(raw_modifier, _stat_additions, _stat_multipliers)
	_rebuild_runtime_stats()


func apply_temporary_modifiers(modifiers: Array, duration: float) -> void:
	var modifier_list: Array[Dictionary] = _typed_dictionary_array(modifiers)
	var remaining: float = maxf(duration, 0.0)
	if modifier_list.is_empty() or remaining <= 0.0:
		return
	_temporary_modifiers.append({
		"remaining": remaining,
		"modifiers": modifier_list,
	})
	_rebuild_runtime_stats()


func stat_value(stat: String) -> float:
	return float(_runtime_stats.get(stat, 0.0))


func snapshot() -> Dictionary:
	return {
		"cooldown_remaining": _cooldown_remaining,
		"stat_additions": _stat_additions.duplicate(true),
		"stat_multipliers": _stat_multipliers.duplicate(true),
		"temporary_modifiers": _temporary_modifiers.duplicate(true),
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_stat_additions = _dictionary_or_empty(snapshot_data.get("stat_additions", {}))
	_stat_multipliers = _dictionary_or_empty(snapshot_data.get("stat_multipliers", {}))
	_temporary_modifiers = _typed_dictionary_array(snapshot_data.get("temporary_modifiers", []))
	_rebuild_runtime_stats()
	_cooldown_remaining = maxf(float(snapshot_data.get("cooldown_remaining", 0.0)), 0.0)


func _fire_once() -> void:
	var projectile: Dictionary = _weapon_data.get("projectile", {})
	var bullet_count: int = int(_runtime_stats.get(STATS.BULLET_COUNT, 1))
	for _index: int in range(maxi(bullet_count, 1)):
		_spawn_bullet(_runtime_stats, projectile)


func _spawn_bullet(stats: Dictionary, projectile: Dictionary) -> void:
	var pool_id: String = String(projectile.get("pool_id", ""))
	var raw_node: Node = PoolManager.acquire(pool_id)
	if not raw_node is Node2D or not raw_node.has_method("configure"):
		return

	var bullet: Node2D = raw_node as Node2D
	var raw_direction: Variant = _player.get("aim_direction")
	var direction: Vector2 = raw_direction if raw_direction is Vector2 else Vector2.RIGHT
	direction = direction.normalized()
	var muzzle_distance: float = float(projectile.get("muzzle_distance", 0.0))
	bullet.global_position = _player.global_position + direction * muzzle_distance
	_reparent_to_active_world(bullet)
	bullet.call("configure", stats, projectile, direction, _player)


func _reparent_to_active_world(node: Node) -> void:
	if _active_parent == null:
		return
	var old_parent: Node = node.get_parent()
	if old_parent == _active_parent:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	_active_parent.add_child(node)


func _rebuild_runtime_stats() -> void:
	_runtime_stats = _base_stats.duplicate(true)
	var additions: Dictionary = _stat_additions.duplicate(true)
	var multipliers: Dictionary = _stat_multipliers.duplicate(true)
	for entry: Dictionary in _temporary_modifiers:
		for raw_modifier: Variant in _array_or_empty(entry.get("modifiers", [])):
			_accumulate_modifier(raw_modifier, additions, multipliers)

	for stat: String in _base_stats.keys():
		var base_value: float = float(_base_stats.get(stat, 0.0))
		var added_value: float = float(additions.get(stat, 0.0))
		var multiplier: float = float(multipliers.get(stat, 1.0))
		_runtime_stats[stat] = (base_value + added_value) * multiplier
	for stat: String in additions.keys():
		if _runtime_stats.has(stat):
			continue
		_runtime_stats[stat] = float(additions.get(stat, 0.0)) * float(multipliers.get(stat, 1.0))


func _update_temporary_modifiers(delta: float) -> void:
	if _temporary_modifiers.is_empty():
		return
	var active_modifiers: Array[Dictionary] = []
	for entry: Dictionary in _temporary_modifiers:
		var remaining: float = maxf(float(entry.get("remaining", 0.0)) - delta, 0.0)
		if remaining <= 0.0:
			continue
		var updated_entry: Dictionary = entry.duplicate(true)
		updated_entry["remaining"] = remaining
		active_modifiers.append(updated_entry)
	if active_modifiers.size() == _temporary_modifiers.size():
		_temporary_modifiers = active_modifiers
		return
	_temporary_modifiers = active_modifiers
	_rebuild_runtime_stats()


func _record_replay_fire_action_state() -> void:
	if not Replay.is_recording():
		return
	if not InputMap.has_action(ACTIONS.FIRE):
		return
	var strength: float = Input.get_action_strength(ACTIONS.FIRE)
	var pressed: bool = strength > 0.0
	if pressed == _replay_fire_pressed:
		return
	_replay_fire_pressed = pressed
	Replay.record_input_action(ACTIONS.FIRE, pressed, strength, REPLAY_PARTICIPANT_ID)


func _is_fire_action_pressed() -> bool:
	if not InputMap.has_action(ACTIONS.FIRE):
		return false
	return Input.is_action_pressed(ACTIONS.FIRE)


func _accumulate_modifier(raw_modifier: Variant, additions: Dictionary, multipliers: Dictionary) -> void:
	if not raw_modifier is Dictionary:
		return
	var modifier: Dictionary = raw_modifier as Dictionary
	var stat: String = String(modifier.get("stat", ""))
	var modifier_type: String = String(modifier.get("type", ""))
	var value: float = float(modifier.get("value", 0.0))
	if stat.is_empty():
		return
	if modifier_type == "add":
		additions[stat] = float(additions.get(stat, 0.0)) + value
	elif modifier_type == "mult":
		multipliers[stat] = float(multipliers.get(stat, 1.0)) * value


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result
