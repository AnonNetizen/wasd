# Doc: docs/代码/world_event_system.md
# Authority: docs/游戏设计文档.md §5.3, docs/决策记录.md ADR #173
class_name WorldEventCaptureVisual
extends Node2D


const WORLD_EVENT_STATES := preload(
	"res://scripts/contracts/world_event_states.gd"
)
const STATE_ACTIVE: String = (
	WORLD_EVENT_STATES.WORLD_EVENT_STATE_ACTIVE
)

@export_group("Capture Zone Presentation")
@export var zone_fill_color: Color = Color(0.45, 0.27, 0.82, 0.09)
@export var zone_ring_color: Color = Color(0.68, 0.48, 1.0, 0.38)
@export var entry_progress_color: Color = Color(0.88, 0.76, 1.0, 0.96)
@export var capture_progress_color: Color = Color(0.57, 0.31, 0.96, 0.98)
@export_range(0.5, 8.0, 0.1) var zone_ring_width: float = 2.5
@export_range(0.5, 12.0, 0.1) var entry_ring_width: float = 4.0
@export_range(0.5, 12.0, 0.1) var capture_ring_width: float = 6.0
@export_range(16, 192, 1) var arc_segments: int = 96
@export_range(0.1, 0.95, 0.01) var entry_ring_radius_ratio: float = 0.78

var _active: bool = false
var _capture_ratio: float = 0.0
var _entry_ratio: float = 0.0
var _radius: float = 0.0


func configure_radius(radius: float) -> void:
	_radius = maxf(radius, 0.0)
	queue_redraw()


func set_progress(entry_ratio: float, capture_ratio: float, active: bool) -> void:
	_entry_ratio = clampf(entry_ratio, 0.0, 1.0)
	_capture_ratio = clampf(capture_ratio, 0.0, 1.0)
	_active = active
	queue_redraw()


func set_event_state(state: String) -> void:
	_active = state == STATE_ACTIVE
	queue_redraw()


func _draw() -> void:
	if _radius <= 0.0:
		return
	var fill: Color = zone_fill_color
	var ring: Color = zone_ring_color
	if not _active:
		fill.a *= 0.5
		ring.a *= 0.65
	draw_circle(Vector2.ZERO, _radius, fill)
	draw_arc(
		Vector2.ZERO,
		_radius,
		0.0,
		TAU,
		arc_segments,
		ring,
		zone_ring_width,
		true
	)
	_draw_progress_arc(
		_radius,
		_capture_ratio,
		capture_progress_color,
		capture_ring_width
	)
	_draw_progress_arc(
		_radius * entry_ring_radius_ratio,
		_entry_ratio,
		entry_progress_color,
		entry_ring_width
	)


func _draw_progress_arc(
	radius: float,
	ratio: float,
	color: Color,
	width: float
) -> void:
	if ratio <= 0.0:
		return
	var start_angle: float = -PI * 0.5
	var end_angle: float = start_angle + TAU * ratio
	var segment_count: int = maxi(int(ceilf(float(arc_segments) * ratio)), 2)
	draw_arc(
		Vector2.ZERO,
		radius,
		start_angle,
		end_angle,
		segment_count,
		color,
		width,
		true
	)
