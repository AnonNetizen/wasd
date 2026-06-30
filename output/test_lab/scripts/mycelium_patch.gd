class_name TestLabMyceliumPatch
extends Node2D

# 星际争霸2 虫族 creep 风格的多源扩散菌毯。
# substrate 是铺满房间矩形的 Polygon2D，shader 从多个 creep 源(菌瘤)算软并集距离场，
# 渲染肉质表面 / 血管 / 湿润高光 / 碎裂须状推进边缘；脚本在源中心叠发光瘤状结节，
# 边缘叠少量须状 runner。源半径随 growth 错峰由 0 长到 max，模拟从结节向外扩散。

const SUBSTRATE_SHADER := preload("res://shaders/mycelium_substrate.gdshader")
const STRAND_SHADER := preload("res://shaders/mycelium_strand.gdshader")

const MAX_SOURCES: int = 16

# 紫 / 品红 creep 调色板：压暗凹坑、提亮边缘 / 高光，拉大明度对比
const CREEP_PIT := Color(0.035, 0.010, 0.055)
const CREEP_DEEP := Color(0.150, 0.035, 0.180)
const CREEP_MID := Color(0.470, 0.090, 0.360)
const CREEP_RIM := Color(0.880, 0.380, 0.700)
const CREEP_SHEEN := Color(0.950, 0.800, 1.000)
const TENDRIL_DORMANT := Color(0.280, 0.070, 0.220, 0.70)
const TENDRIL_ACTIVE := Color(0.620, 0.160, 0.460, 0.80)
const TENDRIL_TIP := Color(0.980, 0.550, 0.850, 0.70)
const NODULE_GLOW := Color(0.760, 0.260, 0.600, 0.16)
const NODULE_DARK := Color(0.100, 0.020, 0.105, 0.86)
const NODULE_CORE := Color(0.980, 0.500, 0.820, 0.88)
const NODULE_RIM := Color(0.950, 0.560, 0.860, 0.32)

@export var seed: int = 1739
@export var field_size: Vector2 = Vector2(1020.0, 560.0)
@export_range(3, 15, 1) var source_count: int = 8
@export_range(0.4, 1.8, 0.05) var strand_density: float = 1.0
@export_range(0.0, 1.0, 0.01) var growth_amount: float = 0.76
@export_range(48.0, 320.0, 1.0) var focus_radius: float = 150.0
@export var active: bool = true

var focus_position: Vector2 = Vector2.ZERO

var _substrate: Polygon2D
var _substrate_material: ShaderMaterial
var _tendril_root: Node2D
var _sources: Array[CreepSource] = []
var _tendrils: Array[CreepTendril] = []
var _tendril_lines: Array[Line2D] = []
var _tendril_materials: Array[ShaderMaterial] = []
var _time: float = 0.0


func _ready() -> void:
	focus_position = Vector2.ZERO
	_ensure_nodes()
	_generate_creep()


func _process(delta: float) -> void:
	_time += delta
	_update_material_uniforms()
	queue_redraw()


func set_focus_position(local_position: Vector2) -> void:
	focus_position = _clamp_to_field(local_position, 0.0)


func set_growth_amount(new_growth_amount: float) -> void:
	growth_amount = clampf(new_growth_amount, 0.0, 1.0)


func regenerate(new_seed: int) -> void:
	seed = new_seed
	_generate_creep()
	queue_redraw()


func _draw() -> void:
	_draw_nodules()
	_draw_focus_glow()


func _ensure_nodes() -> void:
	if _substrate == null:
		_substrate = Polygon2D.new()
		_substrate.name = "CreepSubstrate"
		_substrate.z_index = 0
		add_child(_substrate)

	if _substrate_material == null:
		_substrate_material = ShaderMaterial.new()
		_substrate_material.shader = SUBSTRATE_SHADER
		_substrate.material = _substrate_material

	if _tendril_root == null:
		_tendril_root = Node2D.new()
		_tendril_root.name = "EdgeTendrils"
		_tendril_root.z_index = 2
		add_child(_tendril_root)


func _generate_creep() -> void:
	_ensure_nodes()
	_clear_tendril_nodes()
	_sources.clear()
	_tendrils.clear()
	_tendril_lines.clear()
	_tendril_materials.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_generate_creep_sources(rng)
	_configure_substrate_polygon()
	_generate_edge_tendrils(rng)
	_build_tendril_nodes()
	_update_material_uniforms()


func _generate_creep_sources(rng: RandomNumberGenerator) -> void:
	# 中心主菌瘤：最大、最先长
	var primary := CreepSource.new()
	primary.local_center = Vector2(
		rng.randf_range(-0.06, 0.06) * field_size.x,
		rng.randf_range(-0.05, 0.05) * field_size.y
	)
	primary.max_radius = rng.randf_range(0.30, 0.38) * field_size.y
	primary.phase = rng.randf_range(0.0, TAU)
	primary.bloom_delay = 0.0
	_sources.append(primary)

	# 外围次级菌瘤：按距离错峰扩散
	for index in range(source_count):
		if _sources.size() >= MAX_SOURCES:
			break
		var source := CreepSource.new()
		var angle := rng.randf_range(0.0, TAU)
		var spread := rng.randf_range(0.16, 0.46)
		var center := Vector2.from_angle(angle) * Vector2(field_size.x * spread, field_size.y * spread)
		source.local_center = _clamp_to_field(center, 0.10)
		source.max_radius = rng.randf_range(0.13, 0.24) * field_size.y
		source.phase = rng.randf_range(0.0, TAU)
		source.bloom_delay = clampf(spread * 1.25 + rng.randf_range(-0.08, 0.08), 0.0, 0.72)
		_sources.append(source)


func _configure_substrate_polygon() -> void:
	var half := field_size * 0.5
	_substrate.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])
	_substrate.uv = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	_substrate.color = Color.WHITE


func _clear_tendril_nodes() -> void:
	if _tendril_root == null:
		return

	for child in _tendril_root.get_children():
		child.queue_free()


func _generate_edge_tendrils(rng: RandomNumberGenerator) -> void:
	var per_source := maxi(1, int(round(2.0 * strand_density)))
	for source in _sources:
		var count := rng.randi_range(maxi(1, per_source - 1), per_source + 1)
		for index in range(count):
			var base_direction: Vector2
			if source.local_center.length() > 1.0:
				base_direction = source.local_center.normalized()
			else:
				base_direction = Vector2.from_angle(rng.randf_range(0.0, TAU))
			var direction := base_direction.rotated(rng.randf_range(-1.0, 1.0))
			var origin := source.local_center + direction * source.max_radius * rng.randf_range(0.72, 0.96)
			var length := rng.randf_range(26.0, 66.0)
			var points := _make_tendril_points(rng, origin, direction, length)
			if points.size() < 3:
				continue

			var tendril := CreepTendril.new()
			tendril.points = points
			tendril.width = rng.randf_range(1.2, 2.8)
			tendril.phase = rng.randf_range(0.0, TAU)
			tendril.flow_speed = rng.randf_range(0.10, 0.24)
			tendril.growth_start = clampf(source.bloom_delay + 0.12, 0.0, 0.85)
			tendril.growth_end = minf(1.0, tendril.growth_start + 0.40)
			_tendrils.append(tendril)


func _make_tendril_points(
	rng: RandomNumberGenerator,
	origin: Vector2,
	direction: Vector2,
	length: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var current := origin
	var current_direction := direction.normalized()
	var segment_count := rng.randi_range(4, 7)
	points.append(current)

	for index in range(segment_count):
		var ratio := float(index) / float(maxi(1, segment_count - 1))
		current_direction = current_direction.rotated(sin(ratio * PI + length * 0.01) * 0.16 + rng.randf_range(-0.16, 0.16))
		current += current_direction * length / float(segment_count)
		current = _clamp_to_field(current, 0.0)
		points.append(current)

	return points


func _build_tendril_nodes() -> void:
	for index in range(_tendrils.size()):
		var tendril := _tendrils[index]
		var line := Line2D.new()
		line.name = "EdgeTendril%02d" % index
		line.points = tendril.points
		line.width = tendril.width
		line.default_color = Color.WHITE
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true

		var material := ShaderMaterial.new()
		material.shader = STRAND_SHADER
		material.set_shader_parameter("line_phase", tendril.phase)
		material.set_shader_parameter("flow_speed", tendril.flow_speed)
		material.set_shader_parameter("growth_start", tendril.growth_start)
		material.set_shader_parameter("growth_end", tendril.growth_end)
		material.set_shader_parameter("strand_width", tendril.width)
		line.material = material

		_tendril_root.add_child(line)
		_tendril_lines.append(line)
		_tendril_materials.append(material)


func _update_material_uniforms() -> void:
	var decay_amount := 1.0 - growth_amount

	if _substrate_material != null:
		_substrate_material.set_shader_parameter("time", _time)
		_substrate_material.set_shader_parameter("growth_amount", growth_amount)
		_substrate_material.set_shader_parameter("decay_amount", decay_amount)
		_substrate_material.set_shader_parameter("aspect", field_size.x / maxf(1.0, field_size.y))
		_substrate_material.set_shader_parameter("field_extent", field_size)
		_substrate_material.set_shader_parameter("focus_position", _focus_uv())
		_substrate_material.set_shader_parameter("focus_radius", clampf(focus_radius / maxf(1.0, field_size.y), 0.02, 0.6))
		_substrate_material.set_shader_parameter("source_count", mini(_sources.size(), MAX_SOURCES))
		_substrate_material.set_shader_parameter("creep_sources", _build_source_uniform())
		_substrate_material.set_shader_parameter("pit_color", CREEP_PIT)
		_substrate_material.set_shader_parameter("deep_color", CREEP_DEEP)
		_substrate_material.set_shader_parameter("mid_color", CREEP_MID)
		_substrate_material.set_shader_parameter("rim_color", CREEP_RIM)
		_substrate_material.set_shader_parameter("sheen_color", CREEP_SHEEN)

	for index in range(_tendril_materials.size()):
		var material := _tendril_materials[index]
		var tendril := _tendrils[index]
		var line := _tendril_lines[index]
		var reveal := smoothstep(tendril.growth_start, tendril.growth_end, growth_amount)
		line.points = _partial_points(tendril.points, reveal)
		line.visible = line.points.size() >= 2
		material.set_shader_parameter("time", _time)
		material.set_shader_parameter("growth_amount", growth_amount)
		material.set_shader_parameter("decay_amount", decay_amount)
		material.set_shader_parameter("activation", _activation_for_points(tendril.points))
		material.set_shader_parameter("dormant_color", TENDRIL_DORMANT)
		material.set_shader_parameter("active_color", TENDRIL_ACTIVE)
		material.set_shader_parameter("pulse_color", TENDRIL_TIP)


func _build_source_uniform() -> PackedVector4Array:
	var data := PackedVector4Array()
	var half := field_size * 0.5
	for index in range(MAX_SOURCES):
		if index < _sources.size():
			var source := _sources[index]
			var radius_uv := _source_current_radius(source) / maxf(1.0, field_size.y)
			data.append(Vector4(
				(source.local_center.x + half.x) / field_size.x,
				(source.local_center.y + half.y) / field_size.y,
				radius_uv,
				source.phase
			))
		else:
			data.append(Vector4(0.5, 0.5, 0.0, 0.0))
	return data


func _source_current_radius(source: CreepSource) -> float:
	var bloom := smoothstep(source.bloom_delay, minf(1.0, source.bloom_delay + 0.40), growth_amount)
	return source.max_radius * bloom


func _focus_uv() -> Vector2:
	var half := field_size * 0.5
	return Vector2(
		(focus_position.x + half.x) / field_size.x,
		(focus_position.y + half.y) / field_size.y
	)


func _clamp_to_field(point: Vector2, margin_ratio: float) -> Vector2:
	var half := field_size * 0.5
	var margin := field_size * margin_ratio
	return Vector2(
		clampf(point.x, -half.x + margin.x, half.x - margin.x),
		clampf(point.y, -half.y + margin.y, half.y - margin.y)
	)


func _activation_for_points(points: PackedVector2Array) -> float:
	if not active or points.is_empty():
		return 0.0

	var best_distance := INF
	for point in points:
		best_distance = minf(best_distance, point.distance_to(focus_position))
	return 1.0 - clampf((best_distance - focus_radius * 0.15) / focus_radius, 0.0, 1.0)


func _partial_points(points: PackedVector2Array, ratio: float) -> PackedVector2Array:
	var partial := PackedVector2Array()
	if points.size() < 2 or ratio <= 0.0:
		return partial

	var segment_count := points.size() - 1
	var segment_position := clampf(ratio, 0.0, 1.0) * float(segment_count)
	var full_segments := mini(int(floor(segment_position)), segment_count)
	for index in range(full_segments + 1):
		partial.append(points[index])

	if full_segments < segment_count:
		var local_ratio := segment_position - float(full_segments)
		partial.append(points[full_segments].lerp(points[full_segments + 1], local_ratio))

	return partial


func _draw_nodules() -> void:
	for source in _sources:
		var radius := _source_current_radius(source)
		if radius <= source.max_radius * 0.18:
			continue
		var reveal := clampf((radius / source.max_radius - 0.18) / 0.4, 0.0, 1.0)
		var pulse := (sin(_time * 2.0 + source.phase) + 1.0) * 0.5
		var nodule_radius := clampf(source.max_radius * 0.10, 6.0, 22.0) * (0.85 + pulse * 0.18)
		var center := source.local_center
		draw_circle(center, nodule_radius * 2.4, Color(NODULE_GLOW, NODULE_GLOW.a * reveal))
		draw_circle(center, nodule_radius, Color(NODULE_DARK, NODULE_DARK.a * reveal))
		draw_circle(center, nodule_radius * 0.5, Color(NODULE_CORE, NODULE_CORE.a * reveal * (0.7 + pulse * 0.3)))
		draw_arc(center, nodule_radius * 1.3, 0.0, TAU, 28, Color(NODULE_RIM, NODULE_RIM.a * reveal), 1.5, true)


func _draw_focus_glow() -> void:
	if not active:
		return

	var pulse := (sin(_time * 3.6) + 1.0) * 0.5
	draw_circle(focus_position, focus_radius * (0.22 + pulse * 0.03), Color(0.62, 0.30, 0.62, 0.05))
	draw_arc(
		focus_position,
		focus_radius * 0.30,
		0.0,
		TAU,
		48,
		Color(0.88, 0.50, 0.82, 0.13 + pulse * 0.08),
		1.5,
		true
	)


class CreepSource:
	var local_center: Vector2 = Vector2.ZERO
	var max_radius: float = 120.0
	var phase: float = 0.0
	var bloom_delay: float = 0.0


class CreepTendril:
	var points := PackedVector2Array()
	var width: float = 2.0
	var phase: float = 0.0
	var flow_speed: float = 0.16
	var growth_start: float = 0.0
	var growth_end: float = 1.0
