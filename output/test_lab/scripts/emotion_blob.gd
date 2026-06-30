class_name TestLabEmotionBlob
extends Node2D

# 发光气态软体情绪团。持一个挂 emotion_blob.gdshader 的 ColorRect，
# 内置四套情绪 profile（喜悦 / 愤怒 / 悲伤 / 平静），切换时把运行时参数 _current
# 向目标 profile 平滑 lerp，再写入 shader uniform，实现配色 / 形变 / 律动的平滑过渡。

const BLOB_SHADER := preload("res://shaders/emotion_blob.gdshader")
const RECT_SIZE: float = 640.0
const MORPH_RATE: float = 6.0

@export var emotion_index: int = 0

var _rect: ColorRect
var _material: ShaderMaterial
var _profiles: Array[EmotionProfile] = []
var _current: EmotionProfile
var _target: EmotionProfile
var _focus: Vector2 = Vector2.ZERO
var _time: float = 0.0


func _ready() -> void:
	_build_profiles()
	_ensure_nodes()
	emotion_index = clampi(emotion_index, 0, _profiles.size() - 1)
	_target = _profiles[emotion_index]
	_current = _target.duplicate_profile()
	_update_uniforms()


func _process(delta: float) -> void:
	_time += delta
	var morph := clampf(delta * MORPH_RATE, 0.0, 1.0)
	_current.lerp_toward(_target, morph)
	_update_uniforms()


func set_emotion(index: int) -> void:
	emotion_index = clampi(index, 0, _profiles.size() - 1)
	_target = _profiles[emotion_index]


func next_emotion() -> void:
	set_emotion((emotion_index + 1) % _profiles.size())


func set_focus(local_position: Vector2) -> void:
	var half := RECT_SIZE * 0.5
	_focus = Vector2(
		clampf(local_position.x / half, -1.2, 1.2),
		clampf(local_position.y / half, -1.2, 1.2)
	)


func emotion_count() -> int:
	return _profiles.size()


func current_emotion_name() -> String:
	if _target == null:
		return ""
	return _target.display_name


func current_glow_color() -> Color:
	if _target == null:
		return Color.WHITE
	return _target.glow_color


func _ensure_nodes() -> void:
	if _rect == null:
		_rect = ColorRect.new()
		_rect.name = "BlobSurface"
		_rect.size = Vector2(RECT_SIZE, RECT_SIZE)
		_rect.position = Vector2(-RECT_SIZE * 0.5, -RECT_SIZE * 0.5)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_rect)

	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = BLOB_SHADER
		_rect.material = _material


func _update_uniforms() -> void:
	if _material == null or _current == null:
		return
	_material.set_shader_parameter("time", _time)
	_material.set_shader_parameter("core_color", _current.core_color)
	_material.set_shader_parameter("mid_color", _current.mid_color)
	_material.set_shader_parameter("edge_color", _current.edge_color)
	_material.set_shader_parameter("glow_color", _current.glow_color)
	_material.set_shader_parameter("base_radius", _current.base_radius)
	_material.set_shader_parameter("shape_scale", _current.shape_scale)
	_material.set_shader_parameter("bob", _current.bob)
	_material.set_shader_parameter("droop", _current.droop)
	_material.set_shader_parameter("wobble_amp", _current.wobble_amp)
	_material.set_shader_parameter("wobble_freq", _current.wobble_freq)
	_material.set_shader_parameter("wobble_speed", _current.wobble_speed)
	_material.set_shader_parameter("spike", _current.spike)
	_material.set_shader_parameter("jitter", _current.jitter)
	_material.set_shader_parameter("gas_scale", _current.gas_scale)
	_material.set_shader_parameter("gas_speed", _current.gas_speed)
	_material.set_shader_parameter("glow_strength", _current.glow_strength)
	_material.set_shader_parameter("pulse_speed", _current.pulse_speed)
	_material.set_shader_parameter("pulse_amount", _current.pulse_amount)
	_material.set_shader_parameter("energy", _current.energy)
	_material.set_shader_parameter("focus_position", _focus)
	_material.set_shader_parameter("focus_strength", _current.focus_strength)


func _build_profiles() -> void:
	_profiles.clear()

	# 喜悦 Joy：暖金、圆润饱满、上浮、明快弹跳
	var joy := EmotionProfile.new()
	joy.display_name = "Joy"
	joy.core_color = Color(1.000, 0.970, 0.800)
	joy.mid_color = Color(1.000, 0.780, 0.280)
	joy.edge_color = Color(1.000, 0.500, 0.120)
	joy.glow_color = Color(1.000, 0.660, 0.220)
	joy.base_radius = 0.46
	joy.shape_scale = Vector2(1.06, 0.96)
	joy.bob = 0.05
	joy.droop = 0.0
	joy.wobble_amp = 0.038
	joy.wobble_freq = 4.0
	joy.wobble_speed = 3.2
	joy.spike = 0.0
	joy.jitter = 0.0
	joy.gas_scale = 4.0
	joy.gas_speed = 0.4
	joy.glow_strength = 1.15
	joy.pulse_speed = 4.5
	joy.pulse_amount = 0.05
	joy.energy = 1.2
	joy.focus_strength = 0.25
	_profiles.append(joy)

	# 愤怒 Anger：炽红、尖刺、高频颤抖、急促脉冲
	var anger := EmotionProfile.new()
	anger.display_name = "Anger"
	anger.core_color = Color(1.000, 0.850, 0.550)
	anger.mid_color = Color(0.950, 0.180, 0.100)
	anger.edge_color = Color(0.550, 0.040, 0.050)
	anger.glow_color = Color(1.000, 0.250, 0.120)
	anger.base_radius = 0.44
	anger.shape_scale = Vector2(1.0, 1.0)
	anger.bob = 0.0
	anger.droop = 0.0
	anger.wobble_amp = 0.06
	anger.wobble_freq = 8.0
	anger.wobble_speed = 6.0
	anger.spike = 0.85
	anger.jitter = 0.8
	anger.gas_scale = 5.5
	anger.gas_speed = 0.9
	anger.glow_strength = 1.3
	anger.pulse_speed = 9.0
	anger.pulse_amount = 0.05
	anger.energy = 1.3
	anger.focus_strength = 0.3
	_profiles.append(anger)

	# 悲伤 Sadness：冷蓝、下垂泪滴、下沉、缓慢沉重、暗
	var sadness := EmotionProfile.new()
	sadness.display_name = "Sadness"
	sadness.core_color = Color(0.720, 0.860, 1.000)
	sadness.mid_color = Color(0.240, 0.460, 0.850)
	sadness.edge_color = Color(0.070, 0.140, 0.400)
	sadness.glow_color = Color(0.300, 0.450, 0.850)
	sadness.base_radius = 0.42
	sadness.shape_scale = Vector2(0.82, 1.18)
	sadness.bob = 0.0
	sadness.droop = 0.75
	sadness.wobble_amp = 0.03
	sadness.wobble_freq = 3.0
	sadness.wobble_speed = 0.9
	sadness.spike = 0.0
	sadness.jitter = 0.0
	sadness.gas_scale = 3.6
	sadness.gas_speed = 0.15
	sadness.glow_strength = 0.7
	sadness.pulse_speed = 1.4
	sadness.pulse_amount = 0.03
	sadness.energy = 0.7
	sadness.focus_strength = 0.2
	_profiles.append(sadness)

	# 平静 Calm：青绿、匀称圆、柔和慢呼吸、稳定辉光
	var calm := EmotionProfile.new()
	calm.display_name = "Calm"
	calm.core_color = Color(0.860, 1.000, 0.930)
	calm.mid_color = Color(0.280, 0.740, 0.620)
	calm.edge_color = Color(0.080, 0.340, 0.340)
	calm.glow_color = Color(0.300, 0.800, 0.700)
	calm.base_radius = 0.45
	calm.shape_scale = Vector2(1.0, 1.0)
	calm.bob = 0.0
	calm.droop = 0.0
	calm.wobble_amp = 0.028
	calm.wobble_freq = 4.0
	calm.wobble_speed = 1.3
	calm.spike = 0.0
	calm.jitter = 0.0
	calm.gas_scale = 3.8
	calm.gas_speed = 0.2
	calm.glow_strength = 0.95
	calm.pulse_speed = 1.8
	calm.pulse_amount = 0.035
	calm.energy = 0.95
	calm.focus_strength = 0.22
	_profiles.append(calm)


class EmotionProfile:
	var display_name: String = ""
	var core_color: Color = Color.WHITE
	var mid_color: Color = Color.WHITE
	var edge_color: Color = Color.WHITE
	var glow_color: Color = Color.WHITE
	var base_radius: float = 0.46
	var shape_scale: Vector2 = Vector2.ONE
	var bob: float = 0.0
	var droop: float = 0.0
	var wobble_amp: float = 0.05
	var wobble_freq: float = 5.0
	var wobble_speed: float = 2.0
	var spike: float = 0.0
	var jitter: float = 0.0
	var gas_scale: float = 3.0
	var gas_speed: float = 0.3
	var glow_strength: float = 1.0
	var pulse_speed: float = 3.0
	var pulse_amount: float = 0.04
	var energy: float = 1.0
	var focus_strength: float = 0.3

	func duplicate_profile() -> EmotionProfile:
		var copy := EmotionProfile.new()
		copy.display_name = display_name
		copy.core_color = core_color
		copy.mid_color = mid_color
		copy.edge_color = edge_color
		copy.glow_color = glow_color
		copy.base_radius = base_radius
		copy.shape_scale = shape_scale
		copy.bob = bob
		copy.droop = droop
		copy.wobble_amp = wobble_amp
		copy.wobble_freq = wobble_freq
		copy.wobble_speed = wobble_speed
		copy.spike = spike
		copy.jitter = jitter
		copy.gas_scale = gas_scale
		copy.gas_speed = gas_speed
		copy.glow_strength = glow_strength
		copy.pulse_speed = pulse_speed
		copy.pulse_amount = pulse_amount
		copy.energy = energy
		copy.focus_strength = focus_strength
		return copy

	func lerp_toward(target: EmotionProfile, weight: float) -> void:
		core_color = core_color.lerp(target.core_color, weight)
		mid_color = mid_color.lerp(target.mid_color, weight)
		edge_color = edge_color.lerp(target.edge_color, weight)
		glow_color = glow_color.lerp(target.glow_color, weight)
		base_radius = lerpf(base_radius, target.base_radius, weight)
		shape_scale = shape_scale.lerp(target.shape_scale, weight)
		bob = lerpf(bob, target.bob, weight)
		droop = lerpf(droop, target.droop, weight)
		wobble_amp = lerpf(wobble_amp, target.wobble_amp, weight)
		wobble_freq = lerpf(wobble_freq, target.wobble_freq, weight)
		wobble_speed = lerpf(wobble_speed, target.wobble_speed, weight)
		spike = lerpf(spike, target.spike, weight)
		jitter = lerpf(jitter, target.jitter, weight)
		gas_scale = lerpf(gas_scale, target.gas_scale, weight)
		gas_speed = lerpf(gas_speed, target.gas_speed, weight)
		glow_strength = lerpf(glow_strength, target.glow_strength, weight)
		pulse_speed = lerpf(pulse_speed, target.pulse_speed, weight)
		pulse_amount = lerpf(pulse_amount, target.pulse_amount, weight)
		energy = lerpf(energy, target.energy, weight)
		focus_strength = lerpf(focus_strength, target.focus_strength, weight)
