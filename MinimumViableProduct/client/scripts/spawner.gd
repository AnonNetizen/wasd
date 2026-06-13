extends Node2D

signal enemy_spawned(enemy: Node)

@export var enemy_scene: PackedScene
@export var target_path: NodePath
@export var spawn_parent_path: NodePath
@export var spawn_interval: float = 1.1
@export var spawn_margin: float = 64.0
@export var enemy_speed: float = 90.0

var spawn_index: int = 0
var cooldown: float = 0.2
var target: Node2D
var spawn_parent: Node
var spawning_enabled: bool = true


func _ready() -> void:
	target = get_node_or_null(target_path) as Node2D
	spawn_parent = get_node_or_null(spawn_parent_path)
	if spawn_parent == null:
		spawn_parent = get_tree().current_scene


func _physics_process(delta: float) -> void:
	if not spawning_enabled:
		return

	cooldown -= delta
	if cooldown <= 0.0:
		_spawn_enemy()
		cooldown += spawn_interval


func _spawn_enemy() -> void:
	if enemy_scene == null:
		push_warning("[MvpSpawner] enemy_scene is not assigned")
		return
	if target == null:
		push_warning("[MvpSpawner] target is not assigned")
		return

	var enemy := enemy_scene.instantiate()
	if not enemy is Node2D:
		push_warning("[MvpSpawner] enemy_scene root must be Node2D")
		return
	if not enemy.has_method("setup"):
		push_warning("[MvpSpawner] enemy_scene root must expose setup")
		return

	var enemy_node := enemy as Node2D
	spawn_parent.add_child(enemy_node)
	enemy_node.global_position = _next_spawn_position()
	enemy_node.call("setup", target, enemy_speed)
	enemy_spawned.emit(enemy_node)


func set_spawning_enabled(enabled: bool) -> void:
	spawning_enabled = enabled


func _next_spawn_position() -> Vector2:
	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5
	var positions: Array[Vector2] = [
		Vector2(center.x, -spawn_margin),
		Vector2(viewport_size.x + spawn_margin, center.y),
		Vector2(center.x, viewport_size.y + spawn_margin),
		Vector2(-spawn_margin, center.y),
	]
	var position: Vector2 = positions[spawn_index % positions.size()]
	spawn_index += 1
	return position
