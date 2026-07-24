# Doc: docs/代码/hazard_system.md
# Authority: docs/游戏设计文档.md §5.4, docs/决策记录.md ADR #93 / ADR #125
class_name Hazard
extends Node2D


signal activated(context: Dictionary)

const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")

const DEFAULT_GRID_CELL_SIZE: Vector2 = Vector2(160.0, 160.0)
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

@export_group("Visual Style")
@export var active_fill_color: Color = Color(1.0, 0.42, 0.24, 0.34)
@export var active_ring_color: Color = Color(1.0, 0.72, 0.32, 0.88)
@export var idle_fill_color: Color = Color(0.34, 0.58, 0.78, 0.16)
@export var idle_ring_color: Color = Color(0.65, 0.84, 0.94, 0.78)
@export_range(0.5, 8.0, 0.1) var ring_width: float = 3.0
@export_range(0.5, 8.0, 0.1) var inner_ring_width: float = 1.5
@export_range(0.1, 0.95, 0.01) var inner_rect_scale: float = 0.58
@export_range(0.05, 0.5, 0.01) var center_rect_scale: float = 0.16

var _active_remaining: float = 0.0
var _cooldown_remaining: float = 0.0
var _damage: float = 0.0
var _damage_type: String = ""
var _duration: float = 0.0
var _grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE
var _hazard_id: String = ""
var _radius_tiles: int = 1
var _presentation_profile_id: String = ""
var _target: Node2D = null
var _trigger_interval: float = 1.0


func _physics_process(delta: float) -> void:
	if not GameState.is_state(GameState.PLAYING):
		return
	var scaled_delta: float = GameClock.delta_scaled(delta)
	if scaled_delta <= 0.0:
		return
	_cooldown_remaining = maxf(_cooldown_remaining - scaled_delta, 0.0)
	_active_remaining = maxf(_active_remaining - scaled_delta, 0.0)
	if _target == null or not is_instance_valid(_target):
		queue_redraw()
		return
	if _cooldown_remaining <= 0.0 and _is_target_inside_trigger():
		_trigger()
	queue_redraw()


func configure(hazard_data: Dictionary, target: Node2D, grid_cell_size: Vector2 = DEFAULT_GRID_CELL_SIZE) -> void:
	_hazard_id = String(hazard_data.get("id", ""))
	_damage = float(hazard_data.get("damage", 0.0))
	_damage_type = String(hazard_data.get("damage_type", ""))
	_trigger_interval = maxf(float(hazard_data.get("trigger_interval", 1.0)), 0.01)
	_radius_tiles = maxi(int(hazard_data.get("radius_tiles", 1)), 1)
	_presentation_profile_id = String(
		hazard_data.get("presentation_profile_id", "")
	)
	_grid_cell_size = Vector2(maxf(grid_cell_size.x, 1.0), maxf(grid_cell_size.y, 1.0))
	_duration = maxf(float(hazard_data.get("duration", 0.0)), 0.0)
	_target = target
	_cooldown_remaining = 0.0
	_active_remaining = 0.0
	add_to_group("active_hazards")
	queue_redraw()


func hazard_id() -> String:
	return _hazard_id


func snapshot() -> Dictionary:
	return {
		"hazard_id": _hazard_id,
		"position": _vector_to_dict(global_position),
		"cooldown_remaining": _cooldown_remaining,
		"active_remaining": _active_remaining,
	}


func restore_snapshot(snapshot_data: Dictionary) -> void:
	global_position = _dict_to_vector(snapshot_data.get("position", {}), global_position)
	_cooldown_remaining = maxf(float(snapshot_data.get("cooldown_remaining", 0.0)), 0.0)
	_active_remaining = maxf(float(snapshot_data.get("active_remaining", 0.0)), 0.0)
	queue_redraw()


func _pool_reset() -> void:
	_active_remaining = 0.0
	_cooldown_remaining = 0.0
	_damage = 0.0
	_damage_type = ""
	_duration = 0.0
	_grid_cell_size = DEFAULT_GRID_CELL_SIZE
	_hazard_id = ""
	_radius_tiles = 1
	_presentation_profile_id = ""
	_target = null
	_trigger_interval = 1.0
	visible = true


func _pool_release() -> void:
	remove_from_group("active_hazards")
	_target = null


func _draw() -> void:
	var half_extents: Vector2 = _half_extents()
	var fill_color: Color = active_fill_color if _active_remaining > 0.0 else idle_fill_color
	var ring_color: Color = active_ring_color if _active_remaining > 0.0 else idle_ring_color
	var outer_points: PackedVector2Array = _rect_points(half_extents)
	var inner_points: PackedVector2Array = _rect_points(half_extents * inner_rect_scale)
	var center_points: PackedVector2Array = _rect_points(half_extents * center_rect_scale)
	draw_colored_polygon(outer_points, fill_color)
	_draw_outline(outer_points, ring_color, ring_width)
	_draw_outline(inner_points, ring_color, inner_ring_width)
	draw_colored_polygon(center_points, ring_color)


func _trigger() -> void:
	_cooldown_remaining = _trigger_interval
	_active_remaining = _duration
	activated.emit({
		"owner": self,
		"world_position": global_position,
		"footprint": Rect2(global_position - _half_extents(), _half_extents() * 2.0),
		"hazard_id": _hazard_id,
		"presentation_profile_id": _presentation_profile_id,
	})
	if _target == null or not is_instance_valid(_target):
		return
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		_damage,
		_damage_type,
		self,
		_target,
		TEAM_ENEMY,
		TEAM_PLAYER
	)
	Combat.apply_damage(_target, info)


func _is_target_inside_trigger() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var offset: Vector2 = _target.global_position - global_position
	var half_extents: Vector2 = _half_extents()
	return absf(offset.x) <= half_extents.x and absf(offset.y) <= half_extents.y


func _half_extents() -> Vector2:
	return _grid_cell_size * 0.5 * float(maxi(_radius_tiles, 1))


func _rect_points(half_extents: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half_extents.x, -half_extents.y),
		Vector2(half_extents.x, -half_extents.y),
		Vector2(half_extents.x, half_extents.y),
		Vector2(-half_extents.x, half_extents.y),
	])


func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index: int in range(points.size()):
		draw_line(points[index], points[(index + 1) % points.size()], color, width)


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
