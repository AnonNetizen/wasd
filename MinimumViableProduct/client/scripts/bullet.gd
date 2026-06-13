extends Area2D
class_name MvpBullet

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 1.2


func _ready() -> void:
	area_entered.connect(_on_area_entered)


func setup(direction: Vector2, speed: float, life_seconds: float) -> void:
	velocity = direction.normalized() * speed
	lifetime = life_seconds
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _draw() -> void:
	draw_line(Vector2(-22.0, 0.0), Vector2(-6.0, 0.0), Color(1.0, 0.32, 0.08, 0.28), 8.0)
	draw_line(Vector2(-16.0, 0.0), Vector2(5.0, 0.0), Color(1.0, 0.72, 0.12, 0.75), 4.0)
	draw_circle(Vector2(6.0, 0.0), 6.0, Color(1.0, 0.9, 0.25))
	draw_circle(Vector2(6.0, 0.0), 2.5, Color.WHITE)


func _on_area_entered(area: Area2D) -> void:
	if not area.has_method("take_hit"):
		return

	area.call("take_hit", 1)
	queue_free()
