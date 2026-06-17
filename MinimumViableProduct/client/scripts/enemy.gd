# Doc: MinimumViableProduct/docs/代码/mvp_client.md
extends Area2D

signal killed

@export var move_speed: float = 90.0
@export var hp: int = 1
@export var contact_damage: int = 1
@export var hit_radius: float = 29.0
@export var collision_radius: float = 14.0

var target: Node2D


func _ready() -> void:
	_set_collision_radius(collision_radius)


func setup(target_node: Node2D, speed: float, config: Dictionary = {}) -> void:
	target = target_node
	move_speed = speed
	apply_config(config)


func apply_config(config: Dictionary) -> void:
	move_speed = max(0.0, _get_number(config, "move_speed", move_speed))
	hp = max(1, _get_int(config, "hp", hp))
	contact_damage = max(0, _get_int(config, "contact_damage", contact_damage))
	hit_radius = max(0.1, _get_number(config, "hit_radius", hit_radius))
	collision_radius = max(0.1, _get_number(config, "collision_radius", collision_radius))
	_set_collision_radius(collision_radius)


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


func take_hit(damage: int) -> void:
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


func _set_collision_radius(radius: float) -> void:
	var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null or not (collision_shape.shape is CircleShape2D):
		return

	var circle_shape: CircleShape2D = collision_shape.shape as CircleShape2D
	circle_shape.radius = radius


func _get_number(section: Dictionary, key: String, default_value: float) -> float:
	var value: Variant = section.get(key, default_value)
	if value is int or value is float:
		return float(value)

	push_warning("[MvpEnemy] config.%s must be a number, using %.2f" % [key, default_value])
	return default_value


func _get_int(section: Dictionary, key: String, default_value: int) -> int:
	var value: Variant = section.get(key, default_value)
	if value is int or value is float:
		return int(value)

	push_warning("[MvpEnemy] config.%s must be a number, using %d" % [key, default_value])
	return default_value
