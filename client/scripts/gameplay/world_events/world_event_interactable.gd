# Doc: docs/代码/world_event_system.md
# Authority: docs/游戏设计文档.md §5.3, docs/决策记录.md ADR #173
class_name WorldEventInteractable
extends Node2D


signal interaction_requested(instance_id: String, event_id: String)

const WORLD_EVENT_STATES := preload(
	"res://scripts/contracts/world_event_states.gd"
)
const ACTIVE_GROUP: String = "active_world_event_interactables"
const STATE_AVAILABLE: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_INACTIVE
)
const STATE_ACTIVE: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_ACTIVE
)
const STATE_SUCCEEDED: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_SUCCEEDED
)
const STATE_FAILED: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_FAILED
)
const STATE_EXHAUSTED: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_EXHAUSTED
)

@export_group("Stable Node Paths")
@export var body_path: NodePath = NodePath("Body")
@export var ground_visual_path: NodePath = NodePath("GroundVisual")
@export var interaction_ring_path: NodePath = NodePath("InteractionRing")
@export var status_slots_path: NodePath = NodePath("Body/StatusSlots")
@export var capture_visual_path: NodePath = NodePath("CaptureVisual")
@export var defense_target_path: NodePath = NodePath("DefenseTarget")

@export_group("State Presentation")
@export var available_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var active_tint: Color = Color(1.08, 1.08, 1.08, 1.0)
@export var succeeded_tint: Color = Color(0.58, 1.0, 0.72, 1.0)
@export var failed_tint: Color = Color(0.48, 0.32, 0.34, 0.82)
@export var exhausted_tint: Color = Color(0.42, 0.42, 0.46, 0.72)
@export var succeeded_scale: Vector2 = Vector2(1.06, 1.06)
@export var failed_scale: Vector2 = Vector2(1.0, 0.72)
@export var exhausted_scale: Vector2 = Vector2(0.86, 0.86)
@export_range(0.0, 0.2, 0.005) var active_pulse_amount: float = 0.035
@export_range(0.0, 8.0, 0.1) var active_pulse_rate: float = 2.4

var _config: Dictionary = {}
var _event_id: String = ""
var _event_kind: String = ""
var _event_state: String = STATE_AVAILABLE
var _instance_id: String = ""
var _interaction_radius: float = 0.0
var _module_slot_id: String = ""
var _pulse_phase: float = 0.0

@onready var _body: Node2D = get_node_or_null(body_path) as Node2D
@onready var _capture_visual: Node = get_node_or_null(capture_visual_path)
@onready var _ground_visual: CanvasItem = get_node_or_null(ground_visual_path) as CanvasItem
@onready var _interaction_ring: CanvasItem = get_node_or_null(interaction_ring_path) as CanvasItem
@onready var _status_slots: Node = get_node_or_null(status_slots_path)


func _ready() -> void:
	add_to_group(ACTIVE_GROUP)
	_apply_capture_radius()
	_apply_state_visuals()


func _process(delta: float) -> void:
	if _body == null:
		return
	if _event_state != STATE_ACTIVE or active_pulse_amount <= 0.0:
		_body.scale = _state_scale()
		return
	var scaled_delta: float = _scaled_delta(delta)
	if scaled_delta <= 0.0:
		return
	_pulse_phase = fposmod(_pulse_phase + scaled_delta * active_pulse_rate, TAU)
	var pulse_scale: float = 1.0 + sin(_pulse_phase) * active_pulse_amount
	_body.scale = _state_scale() * pulse_scale


func configure(
	instance_id: String,
	event_definition: Dictionary,
	module_slot_id: String = ""
) -> void:
	_instance_id = instance_id
	_event_id = String(event_definition.get("id", ""))
	_event_kind = String(event_definition.get("kind", ""))
	_module_slot_id = module_slot_id
	_config = event_definition.duplicate(true)
	_interaction_radius = maxf(float(event_definition.get("interaction_radius", 0.0)), 0.0)
	_event_state = STATE_AVAILABLE
	_pulse_phase = 0.0
	if not is_in_group(ACTIVE_GROUP):
		add_to_group(ACTIVE_GROUP)
	_apply_capture_radius()
	_apply_state_visuals()


func request_interaction() -> void:
	interaction_requested.emit(_instance_id, _event_id)


func instance_id() -> String:
	return _instance_id


func event_id() -> String:
	return _event_id


func event_kind() -> String:
	return _event_kind


func module_slot_id() -> String:
	return _module_slot_id


func event_state() -> String:
	return _event_state


func event_definition() -> Dictionary:
	return _config.duplicate(true)


func interaction_radius() -> float:
	return _interaction_radius


func can_player_interact(player: Node) -> bool:
	if _event_state not in [STATE_AVAILABLE, STATE_ACTIVE]:
		return false
	if not player is Node2D:
		return false
	var player_node: Node2D = player as Node2D
	return global_position.distance_squared_to(player_node.global_position) <= _interaction_radius * _interaction_radius


func contains_player(player: Node) -> bool:
	if not player is Node2D:
		return false
	var player_node: Node2D = player as Node2D
	var capture_radius: float = maxf(float(_definition_value("capture_radius", 0.0)), 0.0)
	return global_position.distance_squared_to(player_node.global_position) <= capture_radius * capture_radius


func set_event_state(state: String) -> void:
	_event_state = state
	_pulse_phase = 0.0
	_apply_state_visuals()


func set_capture_progress(entry_ratio: float, capture_ratio: float, active: bool) -> void:
	if _capture_visual == null:
		return
	if _capture_visual.has_method("set_progress"):
		_capture_visual.call(
			"set_progress",
			clampf(entry_ratio, 0.0, 1.0),
			clampf(capture_ratio, 0.0, 1.0),
			active
		)


func set_usage_progress(used_count: int, maximum_count: int) -> void:
	if _status_slots == null:
		return
	var safe_maximum: int = maxi(maximum_count, 0)
	for index: int in range(_status_slots.get_child_count()):
		var child: Node = _status_slots.get_child(index)
		if not child is CanvasItem:
			continue
		var slot: CanvasItem = child as CanvasItem
		if index >= safe_maximum:
			slot.visible = false
			continue
		slot.visible = true
		slot.modulate = (
			Color(0.3, 0.3, 0.34, 0.5)
			if index < used_count
			else Color.WHITE
		)


func defense_target() -> WorldEventDefenseTarget:
	return get_node_or_null(defense_target_path) as WorldEventDefenseTarget


func debug_summary() -> Dictionary:
	return {
		"instance_id": _instance_id,
		"event_id": _event_id,
		"kind": _event_kind,
		"state": _event_state,
		"module_slot_id": _module_slot_id,
		"interaction_radius": _interaction_radius,
	}


func _apply_state_visuals() -> void:
	if not is_node_ready():
		return
	if _body != null:
		_body.scale = _state_scale()
		_body.modulate = _state_tint()
	if _ground_visual != null:
		_ground_visual.modulate.a = 1.0 if _event_state == STATE_ACTIVE else 0.72
	if _interaction_ring != null:
		_interaction_ring.visible = _event_state == STATE_AVAILABLE
	if _capture_visual != null and _capture_visual.has_method("set_event_state"):
		_capture_visual.call("set_event_state", _event_state)


func _apply_capture_radius() -> void:
	if not is_node_ready() or _capture_visual == null:
		return
	if not _capture_visual.has_method("configure_radius"):
		return
	_capture_visual.call(
		"configure_radius",
		maxf(float(_definition_value("capture_radius", 0.0)), 0.0)
	)


func _state_tint() -> Color:
	match _event_state:
		STATE_ACTIVE:
			return active_tint
		STATE_SUCCEEDED:
			return succeeded_tint
		STATE_FAILED:
			return failed_tint
		STATE_EXHAUSTED:
			return exhausted_tint
		_:
			return available_tint


func _state_scale() -> Vector2:
	match _event_state:
		STATE_SUCCEEDED:
			return succeeded_scale
		STATE_FAILED:
			return failed_scale
		STATE_EXHAUSTED:
			return exhausted_scale
		_:
			return Vector2.ONE


func _definition_value(key: String, fallback: Variant) -> Variant:
	if _config.has(key):
		return _config[key]
	var rules_raw: Variant = _config.get("rules", {})
	if rules_raw is Dictionary:
		var rules: Dictionary = rules_raw as Dictionary
		if rules.has(key):
			return rules[key]
	return fallback


func _scaled_delta(delta: float) -> float:
	var clock: Node = get_node_or_null("/root/GameClock")
	if clock != null and clock.has_method("delta_scaled"):
		return float(clock.call("delta_scaled", delta))
	return delta
