# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5, docs/决策记录.md ADR #199
class_name TeleporterInteractable
extends Node2D


signal interaction_requested(station_id: String)

const ACTIVE_GROUP: String = "active_teleporter_interactables"
const PLATFORM_RADIUS: float = 64.0
const CORE_RADIUS: float = 26.0
const PLATFORM_COLOR: Color = Color(0.08, 0.18, 0.25, 0.92)
const RING_COLOR: Color = Color(0.25, 0.85, 1.0, 0.92)
const CORE_COLOR: Color = Color(0.72, 0.98, 1.0, 0.95)

var _interaction_radius: float = 0.0
var _station_id: String = ""
var _station_number: int = 0

@onready var _station_label: Label = get_node_or_null("StationLabel") as Label


func _ready() -> void:
	add_to_group(ACTIVE_GROUP)
	_refresh_label()
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, PLATFORM_RADIUS, PLATFORM_COLOR)
	draw_arc(
		Vector2.ZERO,
		PLATFORM_RADIUS - 5.0,
		0.0,
		TAU,
		48,
		RING_COLOR,
		5.0,
		true
	)
	draw_circle(Vector2.ZERO, CORE_RADIUS, CORE_COLOR)
	draw_arc(
		Vector2.ZERO,
		CORE_RADIUS + 8.0,
		0.0,
		TAU,
		32,
		RING_COLOR,
		3.0,
		true
	)


func configure(station_id_value: String, interaction_radius_value: float) -> void:
	_station_id = station_id_value
	_interaction_radius = maxf(interaction_radius_value, 0.0)
	if not is_in_group(ACTIVE_GROUP):
		add_to_group(ACTIVE_GROUP)
	_refresh_label()
	queue_redraw()


func set_station_number(station_number: int) -> void:
	_station_number = maxi(station_number, 0)
	_refresh_label()


func request_interaction() -> void:
	if not _station_id.is_empty():
		interaction_requested.emit(_station_id)


func can_player_interact(player: Node) -> bool:
	if _station_id.is_empty() or not player is Node2D:
		return false
	var player_node: Node2D = player as Node2D
	return (
		global_position.distance_squared_to(player_node.global_position)
		<= _interaction_radius * _interaction_radius
	)


func station_id() -> String:
	return _station_id


func interaction_radius() -> float:
	return _interaction_radius


func _refresh_label() -> void:
	if _station_label == null:
		return
	_station_label.text = str(_station_number) if _station_number > 0 else ""
