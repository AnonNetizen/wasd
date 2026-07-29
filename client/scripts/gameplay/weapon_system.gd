# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md, docs/游戏设计文档.md §4
class_name WeaponSystem
extends Node


signal temporary_modifier_started(snapshot: Dictionary)
signal temporary_modifier_refreshed(snapshot: Dictionary)
signal temporary_modifier_expired(snapshot: Dictionary)
signal temporary_modifiers_restored(active: Array[Dictionary])
signal weapon_fired(context: Dictionary)
signal ammo_changed(state: Dictionary)
signal reload_started(state: Dictionary)
signal reload_completed(state: Dictionary)

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const RECOIL_RESOLVER := preload("res://scripts/data/weapon_recoil_resolver.gd")

var _player: Node2D = null
var _active_parent: Node = null
var _base_stats: Dictionary = {}
var _combat_gate: Callable = Callable()
var _runtime_stats: Dictionary = {}
var _stat_additions: Dictionary = {}
var _stat_multipliers: Dictionary = {}
var _temporary_modifiers: Array[Dictionary] = []
var _weapon_data: Dictionary = {}
var _recoil_model: Dictionary = {}
var _cooldown_remaining: float = 0.0
var _magazine_size: int = 0
var _magazine_ammo: int = 0
var _reserve_ammo: int = 0
var _starting_reserve: int = 0
var _total_capacity: int = 0
var _reload_duration: float = 0.0
var _reload_remaining: float = 0.0
var _is_reloading: bool = false
var _depleted_mode: bool = false
var _depleted_fire_rate_multiplier: float = 1.0
var _depleted_bullet_speed_multiplier: float = 1.0
var _fire_was_pressed: bool = false
var _reload_was_pressed: bool = false
var _empty_trigger_latched: bool = false


func _process(delta: float) -> void:
	var fire_pressed: bool = _is_fire_action_pressed()
	var reload_pressed: bool = _is_reload_action_pressed()
	var fire_pressed_fresh: bool = fire_pressed and not _fire_was_pressed
	var fire_released: bool = not fire_pressed and _fire_was_pressed
	var reload_pressed_fresh: bool = reload_pressed and not _reload_was_pressed
	_fire_was_pressed = fire_pressed
	_reload_was_pressed = reload_pressed
	if fire_released:
		_empty_trigger_latched = false

	if _player == null or _weapon_data.is_empty():
		return
	if not GameState.is_state(GameState.PLAYING):
		return

	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return

	_update_temporary_modifiers(scaled_delta)
	_cooldown_remaining = maxf(_cooldown_remaining - scaled_delta, 0.0)
	if _is_reloading:
		_advance_reload(scaled_delta)
		return

	if reload_pressed_fresh:
		if request_reload():
			_empty_trigger_latched = false
		if _is_reloading:
			return

	if fire_pressed_fresh:
		_empty_trigger_latched = false
		if _magazine_ammo <= 0:
			if _reserve_ammo > 0:
				request_reload()
				return
			if _magazine_ammo + _reserve_ammo <= 0:
				if _set_depleted_mode(true):
					ammo_changed.emit(ammo_state())

	if not fire_pressed:
		return
	if not _is_combat_allowed():
		return
	if _cooldown_remaining > 0.0:
		return
	if _empty_trigger_latched:
		return
	if _magazine_ammo <= 0 and not _depleted_mode:
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
	var ammo_data: Dictionary = _dictionary_or_empty(_weapon_data.get("ammo", {}))
	_magazine_size = maxi(int(ammo_data.get("magazine_size", 0)), 0)
	_starting_reserve = maxi(int(ammo_data.get("starting_reserve", 0)), 0)
	_total_capacity = maxi(int(ammo_data.get("total_capacity", 0)), 0)
	_reload_duration = maxf(float(ammo_data.get("reload_duration", 0.0)), 0.0)
	_depleted_fire_rate_multiplier = maxf(
		float(ammo_data.get("depleted_fire_rate_multiplier", 0.0)),
		0.0
	)
	_depleted_bullet_speed_multiplier = maxf(
		float(ammo_data.get("depleted_bullet_speed_multiplier", 0.0)),
		0.0
	)
	_magazine_ammo = mini(_magazine_size, _total_capacity)
	_reserve_ammo = mini(
		_starting_reserve,
		maxi(_total_capacity - _magazine_ammo, 0)
	)
	_reload_remaining = 0.0
	_is_reloading = false
	_depleted_mode = false
	_empty_trigger_latched = false
	_stat_additions.clear()
	_stat_multipliers.clear()
	_temporary_modifiers.clear()
	_rebuild_runtime_stats()
	_cooldown_remaining = 0.0
	_fire_was_pressed = _is_fire_action_pressed()
	_reload_was_pressed = _is_reload_action_pressed()
	ammo_changed.emit(ammo_state())


func configure_combat_gate(combat_gate: Callable) -> void:
	_combat_gate = combat_gate


func apply_modifiers(modifiers: Array) -> void:
	for raw_modifier: Variant in modifiers:
		_accumulate_modifier(raw_modifier, _stat_additions, _stat_multipliers)
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
	_rebuild_runtime_stats()
	if is_refresh:
		temporary_modifier_refreshed.emit(added_entry.duplicate(true))
	else:
		temporary_modifier_started.emit(added_entry.duplicate(true))


func stat_value(stat: String) -> float:
	return float(_effective_runtime_stats().get(stat, 0.0))


func ammo_state() -> Dictionary:
	return {
		"magazine": _magazine_ammo,
		"reserve": _reserve_ammo,
		"magazine_size": _magazine_size,
		"total": _magazine_ammo + _reserve_ammo,
		"total_capacity": _total_capacity,
		"is_reloading": _is_reloading,
		"reload_remaining": _reload_remaining,
		"reload_duration": _reload_duration,
		"is_depleted": _magazine_ammo + _reserve_ammo <= 0,
		"depleted_fire_armed": _depleted_mode,
	}


func can_accept_ammo() -> bool:
	return _magazine_ammo + _reserve_ammo < _total_capacity


func add_ammo(amount: int) -> int:
	var available_capacity: int = maxi(
		_total_capacity - _magazine_ammo - _reserve_ammo,
		0
	)
	var applied_amount: int = mini(maxi(amount, 0), available_capacity)
	if applied_amount <= 0:
		return 0

	if _magazine_ammo <= 0:
		var loaded_amount: int = mini(applied_amount, _magazine_size)
		_magazine_ammo = loaded_amount
		_reserve_ammo += applied_amount - loaded_amount
	else:
		_reserve_ammo += applied_amount
	_set_depleted_mode(false)
	ammo_changed.emit(ammo_state())
	return applied_amount


func request_reload() -> bool:
	if _is_reloading:
		return false
	if not GameState.is_state(GameState.PLAYING):
		return false
	if _magazine_ammo >= _magazine_size or _reserve_ammo <= 0:
		return false
	if _reload_duration <= 0.0:
		_complete_reload()
		return true
	_is_reloading = true
	_reload_remaining = _reload_duration
	reload_started.emit(ammo_state())
	ammo_changed.emit(ammo_state())
	return true


func active_temporary_modifiers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in _temporary_modifiers:
		result.append(entry.duplicate(true))
	return result


func debug_refresh() -> void:
	_cooldown_remaining = 0.0
	_temporary_modifiers.clear()
	_rebuild_runtime_stats()


func snapshot() -> Dictionary:
	return {
		"cooldown_remaining": _cooldown_remaining,
		"stat_additions": _stat_additions.duplicate(true),
		"stat_multipliers": _stat_multipliers.duplicate(true),
		"temporary_modifiers": _temporary_modifiers.duplicate(true),
		"magazine_ammo": _magazine_ammo,
		"reserve_ammo": _reserve_ammo,
		"is_reloading": _is_reloading,
		"reload_remaining": _reload_remaining,
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	_stat_additions = _dictionary_or_empty(snapshot_data.get("stat_additions", {}))
	_stat_multipliers = _dictionary_or_empty(snapshot_data.get("stat_multipliers", {}))
	_temporary_modifiers = _typed_dictionary_array(snapshot_data.get("temporary_modifiers", []))
	for index: int in range(_temporary_modifiers.size()):
		var entry: Dictionary = _temporary_modifiers[index]
		if String(entry.get("source_id", "")).is_empty():
			entry["source_id"] = "legacy:%s" % str(
				_typed_dictionary_array(entry.get("modifiers", []))
			)
			_temporary_modifiers[index] = entry
	_rebuild_runtime_stats()
	_cooldown_remaining = maxf(float(snapshot_data.get("cooldown_remaining", 0.0)), 0.0)
	_magazine_ammo = clampi(
		int(snapshot_data.get("magazine_ammo", _magazine_ammo)),
		0,
		mini(_magazine_size, _total_capacity)
	)
	_reserve_ammo = clampi(
		int(snapshot_data.get("reserve_ammo", _reserve_ammo)),
		0,
		maxi(_total_capacity - _magazine_ammo, 0)
	)
	_reload_remaining = clampf(
		float(snapshot_data.get("reload_remaining", 0.0)),
		0.0,
		_reload_duration
	)
	_is_reloading = (
		bool(snapshot_data.get("is_reloading", false))
		and _reload_remaining > 0.0
		and _magazine_ammo < _magazine_size
		and _reserve_ammo > 0
	)
	if not _is_reloading:
		_reload_remaining = 0.0
	_depleted_mode = false
	_empty_trigger_latched = false
	_fire_was_pressed = _is_fire_action_pressed()
	_reload_was_pressed = _is_reload_action_pressed()
	temporary_modifiers_restored.emit(active_temporary_modifiers())
	ammo_changed.emit(ammo_state())


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
	var effective_projectile: Dictionary = _effective_projectile(projectile)
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
	if not _depleted_mode:
		_magazine_ammo = maxi(_magazine_ammo - 1, 0)
		if _magazine_ammo <= 0:
			_empty_trigger_latched = true
		ammo_changed.emit(ammo_state())
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
	var result: Dictionary = _runtime_stats.duplicate(true)
	if not _depleted_mode:
		return result
	result[STATS.FIRE_RATE] = (
		float(result.get(STATS.FIRE_RATE, 0.0))
		* _depleted_fire_rate_multiplier
	)
	result[STATS.BULLET_SPEED] = (
		float(result.get(STATS.BULLET_SPEED, 0.0))
		* _depleted_bullet_speed_multiplier
	)
	return result


func _effective_projectile(projectile: Dictionary) -> Dictionary:
	var result: Dictionary = projectile.duplicate(true)
	if not _depleted_mode:
		return result
	if _depleted_bullet_speed_multiplier <= 0.0:
		return result
	result["lifetime"] = (
		float(result.get("lifetime", 0.0))
		/ _depleted_bullet_speed_multiplier
	)
	return result


func _advance_reload(delta: float) -> void:
	_reload_remaining = maxf(_reload_remaining - delta, 0.0)
	if _reload_remaining > 0.0:
		return
	_complete_reload()


func _complete_reload() -> void:
	var loaded_amount: int = mini(
		maxi(_magazine_size - _magazine_ammo, 0),
		_reserve_ammo
	)
	_magazine_ammo += loaded_amount
	_reserve_ammo -= loaded_amount
	_is_reloading = false
	_reload_remaining = 0.0
	_set_depleted_mode(false)
	reload_completed.emit(ammo_state())
	ammo_changed.emit(ammo_state())


func _set_depleted_mode(enabled: bool) -> bool:
	var next_mode: bool = enabled and _magazine_ammo + _reserve_ammo <= 0
	if _depleted_mode == next_mode:
		return false
	_depleted_mode = next_mode
	return true


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


func _is_reload_action_pressed() -> bool:
	return InputService.is_pressed(ACTIONS.RELOAD)


func _is_combat_allowed() -> bool:
	if not _combat_gate.is_valid():
		return true
	return bool(_combat_gate.call())


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
