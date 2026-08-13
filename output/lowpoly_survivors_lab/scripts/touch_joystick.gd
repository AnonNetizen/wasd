class_name LowpolyTouchJoystick
extends Control

signal vector_changed(value: Vector2)

@export var radius: float = 82.0
@export var knob_radius: float = 34.0

var _touch_index: int = -1
var _value: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.0, radius * 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index < 0:
			_touch_index = touch.index
			_update_value(touch.position)
		elif not touch.pressed and touch.index == _touch_index:
			_touch_index = -1
			_set_value(Vector2.ZERO)
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
		_update_value((event as InputEventScreenDrag).position)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				_touch_index = -2
				_update_value(mouse_button.position)
			elif _touch_index == -2:
				_touch_index = -1
				_set_value(Vector2.ZERO)
	elif event is InputEventMouseMotion and _touch_index == -2:
		_update_value((event as InputEventMouseMotion).position)


func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius, Color(0.04, 0.10, 0.14, 0.48))
	draw_arc(center, radius - 2.0, 0.0, TAU, 64, Color(0.26, 0.86, 0.78, 0.72), 4.0)
	draw_circle(center + _value * (radius - knob_radius), knob_radius, Color(0.42, 1.0, 0.76, 0.78))


func _update_value(local_position: Vector2) -> void:
	var offset := local_position - size * 0.5
	_set_value(offset / maxf(radius - knob_radius, 1.0))


func _set_value(next: Vector2) -> void:
	next = next.limit_length(1.0)
	if _value.is_equal_approx(next):
		return
	_value = next
	vector_changed.emit(_value)
	queue_redraw()
