# Doc: docs/代码/visual_effects.md
class_name VfxRibbonTrail
extends Line2D
## Reusable pooled-projectile trail with bounded world-space history.


@export_range(2, 32, 1) var max_points: int = 8
@export_range(0.5, 16.0, 0.1) var min_sample_distance: float = 5.0

var _history := PackedVector2Array()
var _target: Node2D = null


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var sample: Vector2 = _target.global_position
	if (
		not _history.is_empty()
		and _history[_history.size() - 1].distance_to(sample) < min_sample_distance
	):
		return
	_history.append(sample)
	while _history.size() > max_points:
		_history.remove_at(0)
	points = _history
	visible = _history.size() >= 2


func configure(target: Node2D) -> void:
	reset_trail()
	_target = target
	top_level = true
	global_position = Vector2.ZERO
	_history.append(target.global_position)


func reset_trail() -> void:
	_target = null
	_history = PackedVector2Array()
	points = _history
	visible = false
	global_position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
