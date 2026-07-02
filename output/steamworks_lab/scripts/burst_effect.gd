class_name SteamLabBurstEffect
extends Node2D

const LIFETIME: float = 0.5

var _shards: Array[Dictionary] = []
var _age: float = 0.0
var _color: Color = Color(1.0, 0.7, 0.4, 1.0)


func configure(origin: Vector2, color: Color, shard_count: int, shard_speed: float) -> void:
	global_position = origin
	_color = color
	_age = 0.0
	_shards.clear()
	var shard_rng := RandomNumberGenerator.new()
	shard_rng.randomize()
	for index in range(maxi(3, shard_count)):
		var angle := shard_rng.randf_range(0.0, TAU)
		_shards.append({
			"direction": Vector2(cos(angle), sin(angle)),
			"speed": shard_speed * shard_rng.randf_range(0.45, 1.15),
			"size": shard_rng.randf_range(2.0, 5.0),
		})
	queue_redraw()


func set_battle_frozen(frozen: bool) -> void:
	set_physics_process(not frozen)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var life_ratio := clampf(1.0 - _age / LIFETIME, 0.0, 1.0)
	var travel_ease := 1.0 - pow(life_ratio, 2.2)
	for shard in _shards:
		var shard_data: Dictionary = shard
		var direction: Vector2 = shard_data.get("direction", Vector2.RIGHT)
		var speed := float(shard_data.get("speed", 80.0))
		var size := float(shard_data.get("size", 3.0))
		var offset: Vector2 = direction * speed * LIFETIME * travel_ease
		draw_circle(offset, size * life_ratio, Color(_color, _color.a * life_ratio))
