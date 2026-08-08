# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §7.2, docs/决策记录.md ADR #191
class_name GearModPickup
extends Node2D


const ACTIVE_GROUP: String = "active_gear_mod_pickups"
const HOVER_AMPLITUDE: float = 3.0
const HOVER_SPEED: float = 2.2

var _interaction_radius: float = 0.0
var _gear_mod_instance_id: int = 0
var _mod_id: String = ""
var _visual_time: float = 0.0

@onready var _visual: Node2D = get_node_or_null("Visual") as Node2D
@onready var _icon: Sprite2D = get_node_or_null("Visual/Icon") as Sprite2D


func _ready() -> void:
	if _icon != null and _icon.material is ShaderMaterial:
		_icon.material = (_icon.material as ShaderMaterial).duplicate(true)
	get_viewport().size_changed.connect(_refresh_viewport_aspect)
	_refresh_viewport_aspect()
	_refresh_visual()


func _process(delta: float) -> void:
	if not is_in_group(ACTIVE_GROUP):
		return
	_visual_time += GameClock.delta_scaled(delta)
	_refresh_visual()


func configure(
	instance_id_value: int,
	mod_id_value: String,
	pickup_config: Dictionary
) -> bool:
	var interaction_radius: float = float(
		pickup_config.get("interaction_radius", 0.0)
	)
	if (
		instance_id_value <= 0
		or mod_id_value.is_empty()
		or interaction_radius <= 0.0
	):
		return false
	if GearModSystem.mod_definition(mod_id_value).is_empty():
		return false
	_gear_mod_instance_id = instance_id_value
	_mod_id = mod_id_value
	_interaction_radius = interaction_radius
	_visual_time = 0.0
	visible = true
	add_to_group(ACTIVE_GROUP)
	_refresh_visual()
	return true


func mod_id() -> String:
	return _mod_id


func gear_mod_instance_id() -> int:
	return _gear_mod_instance_id


func can_player_interact(player: Node2D) -> bool:
	return (
		player != null
		and not _mod_id.is_empty()
		and _interaction_radius > 0.0
		and global_position.distance_squared_to(player.global_position)
		<= _interaction_radius * _interaction_radius
	)


func snapshot() -> Dictionary:
	return {
		"instance_id": _gear_mod_instance_id,
		"position": {
			"x": global_position.x,
			"y": global_position.y,
		},
		"mod_id": _mod_id,
	}


func restore_snapshot(
	snapshot_data: Dictionary,
	pickup_config: Dictionary
) -> bool:
	if (
		snapshot_data.size() != 3
		or not snapshot_data.has("instance_id")
		or not snapshot_data.has("mod_id")
		or not snapshot_data.has("position")
	):
		return false
	var raw_position: Variant = snapshot_data.get("position")
	if not raw_position is Dictionary:
		return false
	var position_data: Dictionary = raw_position as Dictionary
	if (
		position_data.size() != 2
		or not position_data.has("x")
		or not position_data.has("y")
		or not (
			position_data.get("x") is int
			or position_data.get("x") is float
		)
		or not (
			position_data.get("y") is int
			or position_data.get("y") is float
		)
	):
		return false
	var position_x: float = float(position_data.get("x", NAN))
	var position_y: float = float(position_data.get("y", NAN))
	if not is_finite(position_x) or not is_finite(position_y):
		return false
	var raw_instance_id: Variant = snapshot_data.get("instance_id")
	if not raw_instance_id is int or int(raw_instance_id) <= 0:
		return false
	if not configure(
		int(raw_instance_id),
		String(snapshot_data.get("mod_id", "")),
		pickup_config
	):
		return false
	global_position = Vector2(position_x, position_y)
	return true


func _pool_reset() -> void:
	_interaction_radius = 0.0
	_gear_mod_instance_id = 0
	_mod_id = ""
	_visual_time = 0.0
	position = Vector2.ZERO
	visible = true
	_refresh_visual()


func _pool_release() -> void:
	remove_from_group(ACTIVE_GROUP)
	_interaction_radius = 0.0
	_gear_mod_instance_id = 0
	_mod_id = ""
	_visual_time = 0.0


func _refresh_visual() -> void:
	if _visual != null:
		_visual.position = Vector2(
			0.0,
			sin(_visual_time * HOVER_SPEED) * HOVER_AMPLITUDE
		)
	if _icon != null and _icon.material is ShaderMaterial:
		(_icon.material as ShaderMaterial).set_shader_parameter(
			"animation_time",
			_visual_time
		)


func _refresh_viewport_aspect() -> void:
	if _icon == null or not _icon.material is ShaderMaterial:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	(_icon.material as ShaderMaterial).set_shader_parameter(
		"viewport_aspect",
		viewport_aspect
	)
