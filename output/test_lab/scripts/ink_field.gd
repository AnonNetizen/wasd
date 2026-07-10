class_name TestLabInkField
extends Node2D

# 水墨角色场：持一个铺满屏幕、挂 ink_wash.gdshader 的 ColorRect。
# 管理一组抽象墨团角色（1 玩家 + N 敌人），每帧按时间动画各自位置，
# 换算成 UV + 半径写入 shader 的 ink_chars 数组，由 shader 渲成黑墨笔形合成到宣纸底。

const INK_SHADER := preload("res://shaders/ink_wash.gdshader")
const SCREEN := Vector2(1280.0, 760.0)
const MAX_CHARS: int = 12

const PAPER_COLOR := Color(0.918, 0.890, 0.820)
const INK_COLOR := Color(0.060, 0.052, 0.060)

@export var seed: int = 7321
@export_range(2, 9, 1) var enemy_count: int = 5

var _rect: ColorRect
var _material: ShaderMaterial
var _player: InkCharacter
var _enemies: Array[InkCharacter] = []
var _time: float = 0.0


func _ready() -> void:
	_ensure_nodes()
	_generate_characters()
	_update_uniforms()


func _process(delta: float) -> void:
	_time += delta
	_update_uniforms()


func _ensure_nodes() -> void:
	if _rect == null:
		_rect = ColorRect.new()
		_rect.name = "InkSurface"
		_rect.size = SCREEN
		_rect.position = Vector2.ZERO
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_rect)

	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = INK_SHADER
		_rect.material = _material


func _generate_characters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# 玩家：居中、半径大、慢速 lissajous 游移
	_player = InkCharacter.new()
	_player.offset = Vector2.ZERO
	_player.radius = 134.0
	_player.is_player = true
	_player.orbit_speed = 0.0
	_player.drift_amp = Vector2(34.0, 24.0)
	_player.drift_freq = Vector2(0.23, 0.31)
	_player.phase = rng.randf_range(0.0, TAU)

	# 敌人：环绕、半径小、各自相位漂移 + 缓慢绕行
	_enemies.clear()
	for index in range(enemy_count):
		var enemy := InkCharacter.new()
		var base_angle := float(index) / float(enemy_count) * TAU + rng.randf_range(-0.3, 0.3)
		var distance := rng.randf_range(235.0, 330.0)
		enemy.offset = Vector2.from_angle(base_angle) * Vector2(distance * 1.18, distance * 0.82)
		enemy.radius = rng.randf_range(66.0, 96.0)
		enemy.is_player = false
		enemy.orbit_speed = rng.randf_range(-0.085, 0.085)
		enemy.drift_amp = Vector2(rng.randf_range(14.0, 30.0), rng.randf_range(14.0, 30.0))
		enemy.drift_freq = Vector2(rng.randf_range(0.25, 0.6), rng.randf_range(0.25, 0.6))
		enemy.phase = rng.randf_range(0.0, TAU)
		_enemies.append(enemy)


func _update_uniforms() -> void:
	if _material == null:
		return

	var center := SCREEN * 0.5
	var entries: Array = []

	# 玩家
	var player_pos := _player.current_position(_time, center)
	entries.append({"pos": player_pos, "radius": _player.radius, "phase": _player.phase})

	# 玩家拖尾笔锋：沿漂移反方向放一个较小子团，并入墨场成笔锋
	var player_velocity := _player.velocity(_time)
	if player_velocity.length() > 0.5:
		var tail_dir := player_velocity.normalized()
		entries.append({
			"pos": player_pos - tail_dir * _player.radius * 0.75,
			"radius": _player.radius * 0.5,
			"phase": _player.phase + 1.0,
		})

	# 敌人
	for enemy in _enemies:
		entries.append({"pos": enemy.current_position(_time, center), "radius": enemy.radius, "phase": enemy.phase})

	var data := PackedVector4Array()
	for index in range(MAX_CHARS):
		if index < entries.size():
			var entry: Dictionary = entries[index]
			var pos: Vector2 = entry["pos"]
			var radius: float = entry["radius"]
			data.append(Vector4(pos.x / SCREEN.x, pos.y / SCREEN.y, radius / SCREEN.y, float(entry["phase"])))
		else:
			data.append(Vector4(0.5, 0.5, 0.0, 0.0))

	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("aspect", SCREEN.x / SCREEN.y)
	_material.set_shader_parameter("char_count", mini(entries.size(), MAX_CHARS))
	_material.set_shader_parameter("ink_chars", data)
	_material.set_shader_parameter("paper_color", PAPER_COLOR)
	_material.set_shader_parameter("ink_color", INK_COLOR)


class InkCharacter:
	var offset: Vector2 = Vector2.ZERO   # 相对屏幕中心
	var radius: float = 80.0
	var is_player: bool = false
	var orbit_speed: float = 0.0
	var drift_amp: Vector2 = Vector2.ZERO
	var drift_freq: Vector2 = Vector2.ONE
	var phase: float = 0.0

	func current_position(t: float, center: Vector2) -> Vector2:
		var rotated := offset.rotated(t * orbit_speed)
		var wobble := Vector2(
			sin(t * drift_freq.x + phase) * drift_amp.x,
			cos(t * drift_freq.y + phase * 1.3) * drift_amp.y
		)
		return center + rotated + wobble

	func velocity(t: float) -> Vector2:
		return Vector2(
			cos(t * drift_freq.x + phase) * drift_amp.x * drift_freq.x,
			-sin(t * drift_freq.y + phase * 1.3) * drift_amp.y * drift_freq.y
		)
