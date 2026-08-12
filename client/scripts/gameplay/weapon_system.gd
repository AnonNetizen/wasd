# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §4
class_name WeaponSystem
extends Node


signal temporary_modifier_started(snapshot: Dictionary)
signal temporary_modifier_refreshed(snapshot: Dictionary)
signal temporary_modifier_expired(snapshot: Dictionary)
signal temporary_modifiers_restored(active: Array[Dictionary])
signal weapon_fired(context: Dictionary)

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const MODIFIER_STACK_SCRIPT := preload("res://scripts/data/modifier_stack.gd")
const RECOIL_RESOLVER := preload("res://scripts/data/weapon_recoil_resolver.gd")

var _player: Node2D = null
var _active_parent: Node = null
var _base_stats: Dictionary = {}
var _combat_gate: Callable = Callable()
var _modifier_stack := MODIFIER_STACK_SCRIPT.new()
var _runtime_stats: Dictionary = {}
var _temporary_modifiers: Array[Dictionary] = []
var _weapon_data: Dictionary = {}
var _recoil_model: Dictionary = {}
var _cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	var fire_pressed: bool = _is_fire_action_pressed()
	if _player == null or _weapon_data.is_empty():
		return
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	_update_temporary_modifiers(scaled_delta)
	_cooldown_remaining = maxf(_cooldown_remaining - scaled_delta, 0.0)
	if not fire_pressed:
		return
	if not _is_combat_allowed():
		return
	if _cooldown_remaining > 0.0:
		return

	var effective_stats: Dictionary = _effective_runtime_stats()
	if not _fire_once(effective_stats):
		return
	var fire_rate: float = float(effective_stats.get(STATS.FIRE_RATE, 0.0))
	_cooldown_remaining = 1.0 / maxf(fire_rate, 0.01)


func configure(
	player: Node2D,
	active_parent: Node,
	weapon_data: Dictionary,
	recoil_model: Dictionary = {}
) -> void:
	_player = player
	_active_parent = active_parent
	_weapon_data = weapon_data.duplicate(true)
	_recoil_model = recoil_model.duplicate(true)
	_base_stats = _weapon_data.get("base_stats", {}).duplicate(true)
	_modifier_stack.configure(_base_stats)
	_temporary_modifiers.clear()
	_rebuild_runtime_stats()
	_cooldown_remaining = 0.0


func configure_combat_gate(combat_gate: Callable) -> void:
	_combat_gate = combat_gate


func apply_modifiers(modifiers: Array) -> void:
	_modifier_stack.append_modifiers(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT,
		_normalized_accumulated_modifiers(modifiers)
	)
	_rebuild_runtime_stats()


## Replaces the run-owned Gear Mod layer. Reapplying the same list is idempotent.
func set_gear_modifiers(modifiers: Array) -> void:
	_modifier_stack.replace_layer(
		MODIFIER_STACK_SCRIPT.LAYER_GEAR,
		_normalized_accumulated_modifiers(modifiers)
	)
	_rebuild_runtime_stats()


func apply_temporary_modifiers(
	modifiers: Array,
	duration: float,
	source_id: String = ""
) -> void:
	var modifier_list: Array[Dictionary] = _typed_dictionary_array(modifiers)
	var remaining: float = maxf(duration, 0.0)
	if modifier_list.is_empty() or remaining <= 0.0:
		return
	var normalized_source_id: String = source_id
	if normalized_source_id.is_empty():
		normalized_source_id = "legacy:%s" % str(modifier_list)
	var existing_index: int = _temporary_modifier_index(normalized_source_id)
	var is_refresh: bool = existing_index >= 0
	var added_entry: Dictionary = {
		"source_id": normalized_source_id,
		"remaining": remaining,
		"modifiers": modifier_list,
	}
	if is_refresh:
		_temporary_modifiers[existing_index] = added_entry
	else:
		_temporary_modifiers.append(added_entry)
	_sync_temporary_modifier_layer()
	_rebuild_runtime_stats()
	if is_refresh:
		temporary_modifier_refreshed.emit(added_entry.duplicate(true))
	else:
		temporary_modifier_started.emit(added_entry.duplicate(true))


func stat_value(stat: String) -> float:
	return float(_effective_runtime_stats().get(stat, 0.0))


func active_temporary_modifiers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _temporary_modifiers:
		result.append(entry.duplicate(true))
	return result


func debug_refresh() -> void:
	_cooldown_remaining = 0.0
	_temporary_modifiers.clear()
	_modifier_stack.clear_layer(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY)
	_rebuild_runtime_stats()


func snapshot() -> Dictionary:
	var persistent_totals: Dictionary = _modifier_stack.layer_totals(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT
	)
	return {
		"cooldown_remaining": _cooldown_remaining,
		"stat_additions": _dictionary_or_empty(
			persistent_totals.get(MODIFIER_STACK_SCRIPT.TOTAL_ADDITIONS, {})
		),
		"stat_multipliers": _dictionary_or_empty(
			persistent_totals.get(MODIFIER_STACK_SCRIPT.TOTAL_MULTIPLIERS, {})
		),
		"temporary_modifiers": _temporary_modifiers.duplicate(true),
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_modifier_stack.restore_layer_totals(
		MODIFIER_STACK_SCRIPT.LAYER_PERSISTENT,
		{
			MODIFIER_STACK_SCRIPT.TOTAL_ADDITIONS: _dictionary_or_empty(
				snapshot_data.get("stat_additions", {})
			),
			MODIFIER_STACK_SCRIPT.TOTAL_MULTIPLIERS: _dictionary_or_empty(
				snapshot_data.get("stat_multipliers", {})
			),
		}
	)
	_temporary_modifiers = _typed_dictionary_array(snapshot_data.get("temporary_modifiers", []))
	for index: int in range(_temporary_modifiers.size()):
		var entry: Dictionary = _temporary_modifiers[index]
		if String(entry.get("source_id", "")).is_empty():
			entry["source_id"] = "legacy:%s" % str(
				_typed_dictionary_array(entry.get("modifiers", []))
			)
			_temporary_modifiers[index] = entry
	_sync_temporary_modifier_layer()
	_rebuild_runtime_stats()
	_cooldown_remaining = maxf(float(snapshot_data.get("cooldown_remaining", 0.0)), 0.0)
	temporary_modifiers_restored.emit(active_temporary_modifiers())


func _fire_once(effective_stats: Dictionary) -> bool:
	var projectile: Dictionary = _weapon_data.get("projectile", {})
	var bullet_count: int = maxi(
		int(effective_stats.get(STATS.BULLET_COUNT, 1)),
		1
	)
	var bullets: Array[Node2D] = _acquire_bullets(
		String(projectile.get("pool_id", "")),
		bullet_count
	)
	if bullets.is_empty():
		return false

	var center_direction: Vector2 = _center_aim_direction()
	var recoil_snapshot: Dictionary = RECOIL_RESOLVER.resolve(
		effective_stats,
		_recoil_model
	)
	var half_spread_degrees: float = (
		float(recoil_snapshot.get("spread_angle_degrees", 0.0)) * 0.5
	)
	var effective_projectile: Dictionary = projectile.duplicate(true)
	for bullet: Node2D in bullets:
		var spread_roll: float = RNG.combat.randf()
		var spread_offset_degrees: float = lerpf(
			-half_spread_degrees,
			half_spread_degrees,
			spread_roll
		)
		var bullet_direction: Vector2 = center_direction.rotated(
			deg_to_rad(spread_offset_degrees)
		)
		_configure_bullet(
			bullet,
			effective_stats,
			effective_projectile,
			center_direction,
			bullet_direction
		)
	var context: Dictionary = {
		"owner": _player,
		"world_position": _player.global_position if _player != null else Vector2.ZERO,
		"direction": center_direction,
		"bullet_count": bullets.size(),
		"recoil": float(recoil_snapshot.get("recoil", 0.0)),
		"recoil_ratio": float(recoil_snapshot.get("recoil_ratio", 0.0)),
		"spread_angle_degrees": float(
			recoil_snapshot.get("spread_angle_degrees", 0.0)
		),
		"kickback_initial_speed": float(
			recoil_snapshot.get("kickback_initial_speed", 0.0)
		),
		"kickback_duration": float(
			recoil_snapshot.get("kickback_duration", 0.0)
		),
		"presentation_profile_id": String(
			_weapon_data.get("presentation_profile_id", "")
		),
	}
	weapon_fired.emit(context)
	return true


func _acquire_bullets(pool_id: String, bullet_count: int) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for _index: int in range(bullet_count):
		var raw_node: Node = PoolManager.acquire(pool_id)
		if raw_node is Node2D and raw_node.has_method("configure"):
			result.append(raw_node as Node2D)
			continue
		if raw_node != null:
			PoolManager.release(raw_node)
	return result


func _configure_bullet(
	bullet: Node2D,
	stats: Dictionary,
	projectile: Dictionary,
	center_direction: Vector2,
	bullet_direction: Vector2
) -> void:
	var muzzle_distance: float = float(projectile.get("muzzle_distance", 0.0))
	bullet.global_position = (
		_player.global_position + center_direction * muzzle_distance
	)
	_reparent_to_active_world(bullet)
	bullet.call("configure", stats, projectile, bullet_direction, _player)


func _effective_runtime_stats() -> Dictionary:
	return _runtime_stats.duplicate(true)


func _center_aim_direction() -> Vector2:
	if _player == null:
		return Vector2.RIGHT
	var raw_direction: Variant = _player.get("aim_direction")
	if raw_direction is Vector2 and (raw_direction as Vector2).length_squared() > 0.0:
		return (raw_direction as Vector2).normalized()
	return Vector2.RIGHT


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
	_runtime_stats = _modifier_stack.materialized_values()


func _update_temporary_modifiers(delta: float) -> void:
	if _temporary_modifiers.is_empty():
		return
	var active_modifiers: Array[Dictionary] = []
	var expired_modifiers: Array[Dictionary] = []
	for entry: Dictionary in _temporary_modifiers:
		var remaining: float = maxf(float(entry.get("remaining", 0.0)) - delta, 0.0)
		if remaining <= 0.0:
			expired_modifiers.append(entry.duplicate(true))
			continue
		var updated_entry: Dictionary = entry.duplicate(true)
		updated_entry["remaining"] = remaining
		active_modifiers.append(updated_entry)
	if active_modifiers.size() == _temporary_modifiers.size():
		_temporary_modifiers = active_modifiers
		return
	_temporary_modifiers = active_modifiers
	_sync_temporary_modifier_layer()
	_rebuild_runtime_stats()
	var emitted_modifier_groups: Array = []
	for expired: Dictionary in expired_modifiers:
		var expired_group: Array[Dictionary] = _typed_dictionary_array(
			expired.get("modifiers", [])
		)
		if (
			_has_matching_temporary_modifier(active_modifiers, expired_group)
			or _contains_modifier_group(emitted_modifier_groups, expired_group)
		):
			continue
		emitted_modifier_groups.append(expired_group)
		temporary_modifier_expired.emit(expired)


func _has_matching_temporary_modifier(
		entries: Array[Dictionary],
		modifiers: Array[Dictionary]
	) -> bool:
	for entry: Dictionary in entries:
		if _typed_dictionary_array(entry.get("modifiers", [])) == modifiers:
			return true
	return false


func _contains_modifier_group(
		groups: Array,
		modifiers: Array[Dictionary]
	) -> bool:
	for raw_group: Variant in groups:
		if _typed_dictionary_array(raw_group) == modifiers:
			return true
	return false


func _temporary_modifier_index(source_id: String) -> int:
	for index: int in range(_temporary_modifiers.size()):
		if String(_temporary_modifiers[index].get("source_id", "")) == source_id:
			return index
	return -1


func _is_fire_action_pressed() -> bool:
	return InputService.is_pressed(ACTIONS.FIRE)


func _is_combat_allowed() -> bool:
	if not _combat_gate.is_valid():
		return true
	return bool(_combat_gate.call())


func _sync_temporary_modifier_layer() -> void:
	_modifier_stack.clear_layer(MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY)
	for index: int in range(_temporary_modifiers.size()):
		var entry: Dictionary = _temporary_modifiers[index]
		_modifier_stack.replace_source(
			MODIFIER_STACK_SCRIPT.LAYER_TEMPORARY,
			str(index),
			_normalized_accumulated_modifiers(entry.get("modifiers", []))
		)


func _normalized_accumulated_modifiers(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for raw_modifier: Variant in raw_value as Array:
		if not raw_modifier is Dictionary:
			continue
		var modifier: Dictionary = raw_modifier as Dictionary
		var stat_id: String = String(modifier.get("stat", ""))
		if stat_id.is_empty():
			continue
		var modifier_type: String = String(modifier.get("type", ""))
		if modifier_type != "add" and modifier_type != "mult":
			continue
		result.append({
			"stat": stat_id,
			"type": modifier_type,
			"value": float(modifier.get("value", 0.0)),
		})
	return result


func _dictionary_or_empty(raw_value: Variant) -> Dictionary:
	if raw_value is Dictionary:
		return (raw_value as Dictionary).duplicate(true)
	return {}


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result
