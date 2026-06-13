extends Node2D
class_name MvpPlayer

signal aim_changed(direction_name: String)
signal damage_taken(amount: int)

@onready var aim_input: Node = $AimInput
@onready var weapon: Node2D = $Weapon

var aim_direction: Vector2 = Vector2.UP
var aim_direction_name: String = "上"
var is_active: bool = true
var damage_flash_seconds: float = 0.0


func _ready() -> void:
	aim_direction = aim_input.call("get_current_direction")
	aim_direction_name = aim_input.call("get_current_direction_name")
	weapon.call("set_aim_direction", aim_direction)
	aim_input.connect("aim_changed", Callable(self, "_on_aim_changed"))
	queue_redraw()


func _process(delta: float) -> void:
	if damage_flash_seconds <= 0.0:
		return

	damage_flash_seconds = max(0.0, damage_flash_seconds - delta)
	queue_redraw()


func get_aim_direction_name() -> String:
	return aim_direction_name


func set_active(active: bool) -> void:
	is_active = active
	weapon.call("set_active", active)


func take_damage(amount: int = 1) -> void:
	if not is_active:
		return

	damage_flash_seconds = 0.18
	damage_taken.emit(amount)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(4.0, 6.0), 28.0, Color(0.0, 0.0, 0.0, 0.32))
	draw_circle(Vector2.ZERO, 28.0, Color(0.04, 0.12, 0.24))
	draw_circle(Vector2.ZERO, 21.0, Color(0.12, 0.58, 0.95))
	draw_circle(Vector2.ZERO, 11.0, Color(0.85, 0.97, 1.0))
	if damage_flash_seconds > 0.0:
		draw_arc(Vector2.ZERO, 48.0, 0.0, TAU, 64, Color(1.0, 0.25, 0.2, 0.85), 5.0)
	draw_arc(Vector2.ZERO, 33.0, 0.0, TAU, 64, Color(0.35, 0.95, 1.0, 0.75), 3.0)
	draw_arc(Vector2.ZERO, 42.0, -0.7, 0.7, 24, Color(1.0, 0.9, 0.25, 0.65), 3.0)
	draw_arc(Vector2.ZERO, 42.0, PI - 0.7, PI + 0.7, 24, Color(1.0, 0.9, 0.25, 0.65), 3.0)
	draw_line(Vector2.ZERO, aim_direction * 54.0, Color(0.0, 0.0, 0.0, 0.45), 9.0)
	draw_line(Vector2.ZERO, aim_direction * 54.0, Color(1.0, 0.88, 0.18), 5.0)
	draw_circle(aim_direction * 63.0, 8.0, Color(1.0, 0.88, 0.18))
	draw_arc(aim_direction * 63.0, 13.0, 0.0, TAU, 32, Color(1.0, 0.98, 0.55, 0.6), 2.0)


func _on_aim_changed(direction: Vector2, direction_name: String) -> void:
	if not is_active:
		return

	aim_direction = direction
	aim_direction_name = direction_name
	weapon.call("set_aim_direction", aim_direction)
	aim_changed.emit(aim_direction_name)
	queue_redraw()
