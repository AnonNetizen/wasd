# Doc: docs/代码/world_event_system.md
# Authority: docs/游戏设计文档.md §5.3, docs/决策记录.md ADR #173
class_name WorldEventDefenseTarget
extends Node2D


signal health_changed(current_health: float, max_health: float)
signal defeated(target: WorldEventDefenseTarget)

const DAMAGE_TARGET_GROUPS := preload(
	"res://scripts/contracts/damage_target_groups.gd"
)
const DEFAULT_ACTIVE_GROUP: String = (
	DAMAGE_TARGET_GROUPS.ACTIVE_WORLD_EVENT_DEFENSE_TARGETS
)
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

@export_group("Stable Node Paths")
@export var core_visual_path: NodePath = NodePath("CoreVisual")

@export_group("Defense Target Presentation")
@export var inactive_color: Color = Color(0.36, 0.48, 0.52, 0.78)
@export var active_color: Color = Color(0.28, 0.88, 0.95, 1.0)
@export var hit_flash_color: Color = Color(1.0, 0.92, 0.58, 1.0)
@export var defeated_color: Color = Color(0.24, 0.18, 0.2, 0.72)
@export var health_ring_color: Color = Color(0.4, 0.94, 1.0, 0.94)
@export var health_ring_background_color: Color = Color(0.05, 0.08, 0.1, 0.72)
@export_range(0.5, 12.0, 0.1) var health_ring_width: float = 4.0
@export_range(0.0, 48.0, 1.0) var health_ring_padding: float = 10.0
@export_range(0.0, 1.0, 0.01) var hit_flash_duration: float = 0.14

var _active_group: String = DEFAULT_ACTIVE_GROUP
var _current_health: float = 0.0
var _defeated: bool = false
var _hit_flash_remaining: float = 0.0
var _hit_radius: float = 0.0
var _instance_id: String = ""
var _max_health: float = 0.0
var _vulnerable: bool = false

@onready var _core_visual: CanvasItem = get_node_or_null(core_visual_path) as CanvasItem


func _ready() -> void:
	_apply_visual_state()


func _process(delta: float) -> void:
	if _hit_flash_remaining <= 0.0:
		return
	var scaled_delta: float = _scaled_delta(delta)
	if scaled_delta <= 0.0:
		return
	_hit_flash_remaining = maxf(_hit_flash_remaining - scaled_delta, 0.0)
	_apply_visual_state()


func configure(
	instance_id: String,
	max_health: float,
	hit_radius: float,
	active_group: String = DEFAULT_ACTIVE_GROUP
) -> void:
	if is_in_group(_active_group):
		remove_from_group(_active_group)
	_instance_id = instance_id
	_max_health = maxf(max_health, 1.0)
	_current_health = _max_health
	_hit_radius = maxf(hit_radius, 1.0)
	_active_group = active_group if not active_group.is_empty() else DEFAULT_ACTIVE_GROUP
	_vulnerable = false
	_defeated = false
	_hit_flash_remaining = 0.0
	_apply_visual_state()
	health_changed.emit(_current_health, _max_health)


func activate() -> void:
	if _defeated:
		return
	_vulnerable = true
	if not is_in_group(_active_group):
		add_to_group(_active_group)
	_apply_visual_state()


func deactivate() -> void:
	_vulnerable = false
	if is_in_group(_active_group):
		remove_from_group(_active_group)
	_apply_visual_state()


func instance_id() -> String:
	return _instance_id


func active_group() -> String:
	return _active_group


func hit_radius() -> float:
	return _hit_radius


func combat_team_id() -> String:
	return TEAM_PLAYER


func current_health() -> float:
	return _current_health


func max_health() -> float:
	return _max_health


func is_alive() -> bool:
	return not _defeated and _current_health > 0.0


func is_vulnerable() -> bool:
	return _vulnerable and is_alive()


func receive_damage(info: RefCounted) -> Dictionary:
	if _defeated or _current_health <= 0.0:
		return _damage_result(false, 0.0, true, "defeated")
	if not _vulnerable:
		return _damage_result(false, 0.0, false, "inactive")
	var source_team: String = String(info.get("source_team"))
	if source_team == TEAM_PLAYER:
		return _damage_result(false, 0.0, false, "player_team_ignored")
	if source_team != TEAM_ENEMY:
		return _damage_result(false, 0.0, false, "team_ignored")
	var amount: float = maxf(float(info.get("amount")), 0.0)
	if amount <= 0.0:
		return _damage_result(false, 0.0, false, "non_positive_amount")

	var applied_amount: float = minf(amount, _current_health)
	_current_health = maxf(_current_health - amount, 0.0)
	_hit_flash_remaining = hit_flash_duration
	health_changed.emit(_current_health, _max_health)
	if _current_health <= 0.0:
		_defeated = true
		_vulnerable = false
		if is_in_group(_active_group):
			remove_from_group(_active_group)
		defeated.emit(self)
	_apply_visual_state()
	return _damage_result(true, applied_amount, _defeated, "applied")


func receive_projectile_damage(info: RefCounted) -> Dictionary:
	return receive_damage(info)


func snapshot() -> Dictionary:
	return {
		"current_health": _current_health,
		"max_health": _max_health,
		"hit_radius": _hit_radius,
		"vulnerable": _vulnerable,
		"defeated": _defeated,
		"active_group": _active_group,
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	if is_in_group(_active_group):
		remove_from_group(_active_group)
	_max_health = maxf(float(snapshot_data.get("max_health", _max_health)), 1.0)
	_current_health = clampf(
		float(snapshot_data.get("current_health", _max_health)),
		0.0,
		_max_health
	)
	_hit_radius = maxf(float(snapshot_data.get("hit_radius", _hit_radius)), 1.0)
	_active_group = String(snapshot_data.get("active_group", _active_group))
	if _active_group.is_empty():
		_active_group = DEFAULT_ACTIVE_GROUP
	_defeated = bool(snapshot_data.get("defeated", _current_health <= 0.0))
	_vulnerable = bool(snapshot_data.get("vulnerable", false)) and not _defeated
	_hit_flash_remaining = 0.0
	if _vulnerable:
		add_to_group(_active_group)
	_apply_visual_state()
	health_changed.emit(_current_health, _max_health)


func debug_summary() -> Dictionary:
	return {
		"instance_id": _instance_id,
		"current_health": _current_health,
		"max_health": _max_health,
		"hit_radius": _hit_radius,
		"vulnerable": _vulnerable,
		"defeated": _defeated,
		"active_group": _active_group,
	}


func _draw() -> void:
	if _hit_radius <= 0.0 or _max_health <= 0.0:
		return
	var ring_radius: float = _hit_radius + health_ring_padding
	draw_arc(
		Vector2.ZERO,
		ring_radius,
		0.0,
		TAU,
		64,
		health_ring_background_color,
		health_ring_width,
		true
	)
	var health_ratio: float = clampf(_current_health / _max_health, 0.0, 1.0)
	if health_ratio <= 0.0:
		return
	draw_arc(
		Vector2.ZERO,
		ring_radius,
		-PI * 0.5,
		-PI * 0.5 + TAU * health_ratio,
		maxi(int(ceilf(64.0 * health_ratio)), 2),
		health_ring_color,
		health_ring_width,
		true
	)


func _apply_visual_state() -> void:
	if is_node_ready() and _core_visual != null:
		if _defeated:
			_core_visual.modulate = defeated_color
		elif _hit_flash_remaining > 0.0:
			_core_visual.modulate = hit_flash_color
		elif _vulnerable:
			_core_visual.modulate = active_color
		else:
			_core_visual.modulate = inactive_color
	queue_redraw()


func _damage_result(
	applied: bool,
	amount: float,
	was_defeated: bool,
	reason: String
) -> Dictionary:
	return {
		"applied": applied,
		"amount": amount,
		"defeated": was_defeated,
		"reason": reason,
	}


func _scaled_delta(delta: float) -> float:
	var clock: Node = get_node_or_null("/root/GameClock")
	if clock != null and clock.has_method("delta_scaled"):
		return float(clock.call("delta_scaled", delta))
	return delta
