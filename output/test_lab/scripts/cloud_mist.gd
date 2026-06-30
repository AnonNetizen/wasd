class_name TestLabCloudMist
extends Node2D

# 升腾白烟羽：用 CPUParticles2D（gl_compatibility 截图更稳）做向上翻卷、扩张、消散的烟柱。
# 每个粒子贴一张运行时程序生成的"羽化软团 + fbm 不规则"贴图（白色），多个叠出翻卷烟感。
# 分核心烟柱层 + 外缘稀薄烟絮层。贴图运行时生成，不写入 .tscn。

const TEXTURE_SIZE: int = 128
const EMITTER_POSITION := Vector2(640.0, 712.0) # 屏幕底部中心

var _smoke_texture: ImageTexture


func _ready() -> void:
	_smoke_texture = _make_smoke_texture(TEXTURE_SIZE)
	_add_core_layer()
	_add_wisp_layer()


func _add_core_layer() -> void:
	var particles := _new_smoke_particles("SmokeCore")
	particles.amount = 180
	particles.lifetime = 4.2
	particles.preprocess = 4.2
	particles.spread = 17.0
	particles.gravity = Vector2(0.0, -26.0)
	particles.initial_velocity_min = 72.0
	particles.initial_velocity_max = 132.0
	particles.scale_amount_min = 0.80
	particles.scale_amount_max = 1.25
	particles.scale_amount_curve = _scale_curve(0.42, 1.65)
	particles.color_ramp = _color_ramp(0.72)
	add_child(particles)
	particles.emitting = true


func _add_wisp_layer() -> void:
	var particles := _new_smoke_particles("SmokeWisps")
	particles.amount = 90
	particles.lifetime = 5.2
	particles.preprocess = 5.2
	particles.spread = 30.0
	particles.gravity = Vector2(0.0, -34.0)
	particles.initial_velocity_min = 95.0
	particles.initial_velocity_max = 175.0
	particles.scale_amount_min = 1.10
	particles.scale_amount_max = 1.80
	particles.scale_amount_curve = _scale_curve(0.5, 1.9)
	particles.color_ramp = _color_ramp(0.40)
	add_child(particles)
	particles.emitting = true


func _new_smoke_particles(node_name: String) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.name = node_name
	particles.texture = _smoke_texture
	particles.position = EMITTER_POSITION
	particles.local_coords = false
	particles.randomness = 0.6
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(34.0, 8.0)
	particles.direction = Vector2(0.0, -1.0)
	particles.damping_min = 3.0
	particles.damping_max = 9.0
	particles.angle_min = -180.0
	particles.angle_max = 180.0
	particles.angular_velocity_min = -26.0
	particles.angular_velocity_max = 26.0
	return particles


func _scale_curve(start_scale: float, end_scale: float) -> Curve:
	var curve := Curve.new()
	curve.min_value = 0.0
	curve.max_value = 2.5 # 必须先放宽，否则 add_point 的 y 会被默认 max 1.0 截断
	curve.add_point(Vector2(0.0, start_scale))
	curve.add_point(Vector2(0.34, (start_scale + end_scale) * 0.52))
	curve.add_point(Vector2(1.0, end_scale))
	return curve


func _color_ramp(peak_alpha: float) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.85, 0.87, 0.92, 0.0))
	gradient.add_point(0.16, Color(1.0, 1.0, 1.0, peak_alpha))
	gradient.add_point(0.6, Color(0.92, 0.93, 0.97, peak_alpha * 0.6))
	return gradient


func _make_smoke_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.seed = 1337
	noise.frequency = 0.05
	noise.fractal_octaves = 4

	var center := float(size) * 0.5
	var light_dir := Vector3(-0.35, -0.85, 0.42).normalized() # 上偏左、略朝观察者
	var shadow := Color(0.52, 0.55, 0.62)
	for y in range(size):
		for x in range(size):
			var nx := (float(x) - center) / center
			var ny := (float(y) - center) / center
			var radius := sqrt(nx * nx + ny * ny)
			var coverage := smoothstep(1.0, 0.10, radius) # 1 中心 → 0 边缘
			var n := noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5 # 0..1
			var alpha := coverage * (0.5 + 0.7 * n)
			# 球面假光照：把每个烟团做出体积（顶亮底灰），在亮底上有形
			var light01 := 0.6
			if radius < 1.0:
				var nz := sqrt(maxf(0.0, 1.0 - radius * radius))
				var normal := Vector3(nx, ny, nz)
				light01 = clampf(normal.dot(light_dir) * 0.5 + 0.55, 0.32, 1.0)
			var rgb := shadow.lerp(Color(1.0, 1.0, 1.0), light01)
			image.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, clampf(alpha, 0.0, 1.0)))

	return ImageTexture.create_from_image(image)
