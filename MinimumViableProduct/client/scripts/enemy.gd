extends Area2D

signal killed

@export var move_speed: float = 90.0
@export var hp: int = 1
@export var contact_damage: int = 1
@export var hit_radius: float = 29.0

var target: Node2D


func setup(target_node: Node2D, speed: float) -> void:
	target = target_node
	move_speed = speed


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var direction := global_position.direction_to(target.global_position)
	global_position += direction * move_speed * delta
	rotation = direction.angle()

	if global_position.distance_to(target.global_position) <= hit_radius:
		if target.has_method("take_damage"):
			target.call("take_damage", contact_damage)
		queue_free()


func take_hit(damage: int = 1) -> void:
	hp -= damage
	if hp <= 0:
		killed.emit()
		queue_free()


func _draw() -> void:
	var points := PackedVector2Array([
		Vector2(24.0, 0.0),
		Vector2(-15.0, -15.0),
		Vector2(-9.0, 0.0),
		Vector2(-15.0, 15.0),
	])
	var shadow := PackedVector2Array()
	for point in points:
		shadow.append(point + Vector2(4.0, 5.0))

	draw_colored_polygon(shadow, Color(0.0, 0.0, 0.0, 0.28))
	draw_arc(Vector2.ZERO, 23.0, 0.0, TAU, 48, Color(1.0, 0.18, 0.16, 0.28), 3.0)
	draw_colored_polygon(points, Color(0.92, 0.08, 0.12))
	draw_polyline(points + PackedVector2Array([points[0]]), Color(1.0, 0.72, 0.68), 2.0)
	draw_line(Vector2(-8.0, 0.0), Vector2(17.0, 0.0), Color(1.0, 0.95, 0.82), 3.0)
