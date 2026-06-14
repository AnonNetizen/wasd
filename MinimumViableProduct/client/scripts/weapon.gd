# Doc: MinimumViableProduct/docs/代码/mvp_client.md
extends Node2D
class_name MvpWeapon

@export var bullet_scene: PackedScene
@export var fire_interval: float = 0.35
@export var bullet_speed: float = 520.0
@export var bullet_lifetime: float = 1.2
@export var bullet_damage: int = 1
@export var bullet_hitbox_radius: float = 5.0
@export var muzzle_distance: float = 34.0

var aim_direction: Vector2 = Vector2.UP
var cooldown: float = 0.0
var is_active: bool = true


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	cooldown -= delta
	if cooldown <= 0.0:
		_fire()
		cooldown += fire_interval


func set_aim_direction(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return

	aim_direction = direction.normalized()


func set_active(active: bool) -> void:
	is_active = active


func apply_config(config: Dictionary) -> void:
	fire_interval = max(0.01, _get_number(config, "fire_interval", fire_interval))
	bullet_speed = max(0.0, _get_number(config, "bullet_speed", bullet_speed))
	bullet_lifetime = max(0.01, _get_number(config, "bullet_lifetime", bullet_lifetime))
	bullet_damage = max(0, _get_int(config, "bullet_damage", bullet_damage))
	bullet_hitbox_radius = max(0.1, _get_number(config, "bullet_hitbox_radius", bullet_hitbox_radius))
	muzzle_distance = max(0.0, _get_number(config, "muzzle_distance", muzzle_distance))


func _fire() -> void:
	if bullet_scene == null:
		push_warning("[MvpWeapon] bullet_scene is not assigned")
		return

	var bullet := bullet_scene.instantiate()
	if not bullet is Node2D:
		push_warning("[MvpWeapon] bullet_scene root must be Node2D")
		return
	if not bullet.has_method("setup"):
		push_warning("[MvpWeapon] bullet_scene root must expose setup")
		return

	var bullet_parent: Node = get_tree().current_scene
	if bullet_parent == null:
		bullet_parent = get_tree().root

	var bullet_node := bullet as Node2D
	bullet_parent.add_child(bullet_node)
	bullet_node.global_position = global_position + aim_direction * muzzle_distance
	bullet_node.call("setup", aim_direction, bullet_speed, bullet_lifetime, bullet_damage, bullet_hitbox_radius)


func _get_number(section: Dictionary, key: String, default_value: float) -> float:
	var value: Variant = section.get(key, default_value)
	if value is int or value is float:
		return float(value)

	push_warning("[MvpWeapon] config.%s must be a number, using %.2f" % [key, default_value])
	return default_value


func _get_int(section: Dictionary, key: String, default_value: int) -> int:
	var value: Variant = section.get(key, default_value)
	if value is int or value is float:
		return int(value)

	push_warning("[MvpWeapon] config.%s must be a number, using %d" % [key, default_value])
	return default_value
