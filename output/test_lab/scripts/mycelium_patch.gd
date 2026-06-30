class_name TestLabMyceliumPatch
extends Node2D

const SUBSTRATE_SHADER := preload("res://shaders/mycelium_substrate.gdshader")
const STRAND_SHADER := preload("res://shaders/mycelium_strand.gdshader")

const SUBSTRATE_MARGIN: float = 1.16
const SOURCE_INSET_RATIO: float = 0.88
const BONE_WHITE := Color(0.72, 0.66, 0.52, 0.74)
const WAX_AMBER := Color(0.92, 0.68, 0.36, 0.62)
const TOXIN_BLUE := Color(0.36, 0.62, 0.68, 0.46)

@export var seed: int = 1739
@export_range(160.0, 560.0, 1.0) var patch_radius: float = 340.0
@export_range(4, 6, 1) var source_count: int = 5
@export_range(0.55, 1.75, 0.05) var strand_density: float = 1.0
@export_range(0.0, 1.0, 0.01) var growth_amount: float = 0.76
@export_range(48.0, 260.0, 1.0) var focus_radius: float = 150.0
@export var active: bool = true

var focus_position: Vector2 = Vector2.ZERO

var _substrate: Polygon2D
var _substrate_material: ShaderMaterial
var _strand_root: Node2D
var _strands: Array[MyceliumStrand] = []
var _strand_lines: Array[Line2D] = []
var _strand_materials: Array[ShaderMaterial] = []
var _source_points := PackedVector2Array()
var _spore_points := PackedVector2Array()
var _time: float = 0.0


func _ready() -> void:
	focus_position = Vector2.ZERO
	_ensure_nodes()
	_generate_network()


func _process(delta: float) -> void:
	_time += delta
	_update_material_uniforms()
	queue_redraw()


func set_focus_position(local_position: Vector2) -> void:
	focus_position = local_position.limit_length(patch_radius * SUBSTRATE_MARGIN)


func set_growth_amount(new_growth_amount: float) -> void:
	growth_amount = clampf(new_growth_amount, 0.0, 1.0)


func regenerate(new_seed: int) -> void:
	seed = new_seed
	_generate_network()
	queue_redraw()


func _draw() -> void:
	_draw_source_pores()
	_draw_spore_dust()
	_draw_focus_glow()


func _ensure_nodes() -> void:
	if _substrate == null:
		_substrate = Polygon2D.new()
		_substrate.name = "WetSubstrate"
		_substrate.z_index = 0
		add_child(_substrate)

	if _substrate_material == null:
		_substrate_material = ShaderMaterial.new()
		_substrate_material.shader = SUBSTRATE_SHADER
		_substrate.material = _substrate_material

	if _strand_root == null:
		_strand_root = Node2D.new()
		_strand_root.name = "CreepingStrands"
		_strand_root.z_index = 2
		add_child(_strand_root)


func _generate_network() -> void:
	_ensure_nodes()
	_clear_strand_nodes()
	_strands.clear()
	_strand_lines.clear()
	_strand_materials.clear()
	_source_points.clear()
	_spore_points.clear()
	_configure_substrate_polygon()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_source_points = _make_source_points(rng)

	for source_index in range(_source_points.size()):
		_grow_from_source(rng, source_index, _source_points[source_index])

	_build_strand_nodes()
	_update_material_uniforms()


func _configure_substrate_polygon() -> void:
	var half_size := patch_radius * SUBSTRATE_MARGIN
	_substrate.polygon = PackedVector2Array([
		Vector2(-half_size, -half_size),
		Vector2(half_size, -half_size),
		Vector2(half_size, half_size),
		Vector2(-half_size, half_size),
	])
	_substrate.uv = PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	_substrate.color = Color.WHITE


func _clear_strand_nodes() -> void:
	if _strand_root == null:
		return

	for child in _strand_root.get_children():
		child.queue_free()


func _make_source_points(rng: RandomNumberGenerator) -> PackedVector2Array:
	var points := PackedVector2Array()
	var angle_offset := rng.randf_range(0.0, TAU)
	for index in range(source_count):
		var ratio := float(index) / float(source_count)
		var angle := angle_offset + ratio * TAU + rng.randf_range(-0.22, 0.22)
		var radius := patch_radius * rng.randf_range(0.72, SOURCE_INSET_RATIO)
		points.append(Vector2.from_angle(angle) * radius)
	return points


func _grow_from_source(rng: RandomNumberGenerator, source_index: int, source_point: Vector2) -> void:
	var main_count := maxi(5, int(round(7.0 * strand_density)))
	var inward := (-source_point).normalized()
	var tangent := inward.rotated(PI * 0.5)

	for index in range(main_count):
		var fan_ratio := 0.0
		if main_count > 1:
			fan_ratio = float(index) / float(main_count - 1) - 0.5

		var start := source_point + tangent * fan_ratio * 44.0
		var direction := inward.rotated(fan_ratio * 1.08 + rng.randf_range(-0.28, 0.28))
		var step_count := rng.randi_range(9, 15)
		var step_length := rng.randf_range(12.0, 19.0)
		var phase := rng.randf_range(0.0, TAU)
		var points := _walk_path(source_index, start, direction, step_count, step_length, phase)
		if points.size() < 4:
			continue

		var strand := MyceliumStrand.new()
		strand.points = points
		strand.width = rng.randf_range(0.92, 1.55)
		strand.phase = phase
		strand.flow_speed = rng.randf_range(0.08, 0.22)
		strand.growth_start = rng.randf_range(0.0, 0.16)
		strand.growth_end = rng.randf_range(0.66, 0.98)
		strand.gap_phase = rng.randf_range(0.0, 1.0)
		strand.activation_bias = rng.randf_range(0.0, 0.22)
		_strands.append(strand)
		_add_capillaries(rng, source_index, strand)


func _walk_path(
	source_index: int,
	start: Vector2,
	initial_direction: Vector2,
	step_count: int,
	step_length: float,
	phase: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var current := start
	var direction := initial_direction.normalized()
	points.append(current)

	for step in range(step_count):
		var ratio := float(step) / float(maxi(1, step_count - 1))
		var flow_bend := _flow_bend(current, source_index, phase, ratio)
		var flow_direction := direction.rotated(flow_bend)
		var center_pressure := _center_avoidance_direction(current, flow_direction)
		direction = direction.lerp(flow_direction, 0.34).lerp(center_pressure, 0.11).normalized()
		current += direction * step_length * (0.84 + sin(ratio * TAU + phase) * 0.12)
		current = _clamp_to_patch(current)
		points.append(current)

	return _simplify_short_steps(points)


func _add_capillaries(rng: RandomNumberGenerator, source_index: int, parent: MyceliumStrand) -> void:
	if parent.points.size() < 7:
		return

	var branch_count := maxi(3, int(round(5.0 * strand_density)))
	for _index in range(branch_count):
		var origin_index := rng.randi_range(2, parent.points.size() - 3)
		var origin := parent.points[origin_index]
		var parent_direction := (parent.points[origin_index + 1] - parent.points[origin_index - 1]).normalized()
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var direction := parent_direction.rotated(side * rng.randf_range(0.36, 1.05))
		var step_count := rng.randi_range(4, 8)
		var step_length := rng.randf_range(5.5, 11.5)
		var phase := rng.randf_range(0.0, TAU)
		var points := _walk_path(source_index, origin, direction, step_count, step_length, phase)
		if points.size() < 3:
			continue

		var branch := MyceliumStrand.new()
		branch.points = points
		branch.width = rng.randf_range(0.42, 0.92)
		branch.phase = phase
		branch.flow_speed = rng.randf_range(0.12, 0.28)
		branch.growth_start = clampf(parent.growth_start + rng.randf_range(0.08, 0.26), 0.0, 0.82)
		branch.growth_end = clampf(parent.growth_end + rng.randf_range(-0.05, 0.08), branch.growth_start + 0.08, 1.0)
		branch.gap_phase = rng.randf_range(0.0, 1.0)
		branch.activation_bias = rng.randf_range(0.08, 0.34)
		_strands.append(branch)


func _flow_bend(point: Vector2, source_index: int, phase: float, ratio: float) -> float:
	var scale := 0.0065
	var low_frequency := sin(point.x * scale + phase + float(source_index) * 1.7)
	var cross_frequency := cos(point.y * scale * 1.28 - phase * 0.63)
	var crawl_frequency := sin(ratio * TAU * 1.7 + phase)
	return low_frequency * 0.34 + cross_frequency * 0.22 + crawl_frequency * 0.18


func _center_avoidance_direction(point: Vector2, fallback: Vector2) -> Vector2:
	var distance := point.length()
	if distance > patch_radius * 0.28:
		return fallback
	if distance <= 0.001:
		return fallback.rotated(PI * 0.5)

	var push := point.normalized().rotated(sin(distance * 0.01) * 0.42)
	return fallback.lerp(push, 0.68).normalized()


func _clamp_to_patch(point: Vector2) -> Vector2:
	var distance := point.length()
	var max_radius := patch_radius * 0.96
	if distance <= max_radius:
		return point
	return point.normalized() * max_radius


func _simplify_short_steps(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 2:
		return points

	var simplified := PackedVector2Array()
	simplified.append(points[0])
	for index in range(1, points.size()):
		if points[index].distance_to(simplified[simplified.size() - 1]) >= 5.0:
			simplified.append(points[index])
	return simplified


func _build_strand_nodes() -> void:
	for index in range(_strands.size()):
		var strand := _strands[index]
		var line := Line2D.new()
		line.name = "Strand%03d" % index
		line.points = strand.points
		line.width = strand.width
		line.default_color = Color.WHITE
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true

		var material := ShaderMaterial.new()
		material.shader = STRAND_SHADER
		material.set_shader_parameter("line_phase", strand.phase)
		material.set_shader_parameter("flow_speed", strand.flow_speed)
		material.set_shader_parameter("growth_start", strand.growth_start)
		material.set_shader_parameter("growth_end", strand.growth_end)
		material.set_shader_parameter("gap_phase", strand.gap_phase)
		material.set_shader_parameter("strand_width", strand.width)
		line.material = material

		_strand_root.add_child(line)
		_strand_lines.append(line)
		_strand_materials.append(material)

		if index % 5 == 0 and strand.points.size() > 2:
			_spore_points.append(strand.points[strand.points.size() - 1])


func _update_material_uniforms() -> void:
	var decay_amount := 1.0 - growth_amount
	var focus_uv := _focus_uv()
	var normalized_focus_radius := clampf(focus_radius / (patch_radius * SUBSTRATE_MARGIN * 2.0), 0.02, 0.48)

	if _substrate_material != null:
		_substrate_material.set_shader_parameter("time", _time)
		_substrate_material.set_shader_parameter("growth_amount", growth_amount)
		_substrate_material.set_shader_parameter("decay_amount", decay_amount)
		_substrate_material.set_shader_parameter("focus_position", focus_uv)
		_substrate_material.set_shader_parameter("focus_radius", normalized_focus_radius)

	for index in range(_strand_materials.size()):
		var material := _strand_materials[index]
		var strand := _strands[index]
		var line := _strand_lines[index]
		var reveal := _strand_reveal(strand)
		line.points = _partial_points(strand.points, reveal)
		line.visible = line.points.size() >= 2
		material.set_shader_parameter("time", _time)
		material.set_shader_parameter("growth_amount", growth_amount)
		material.set_shader_parameter("decay_amount", decay_amount)
		material.set_shader_parameter("activation", _activation_for_strand(strand))
		material.set_shader_parameter("focus_position", focus_uv)
		material.set_shader_parameter("focus_radius", normalized_focus_radius)
		material.set_shader_parameter("dormant_color", BONE_WHITE)
		material.set_shader_parameter("active_color", WAX_AMBER)
		material.set_shader_parameter("pulse_color", TOXIN_BLUE)


func _strand_reveal(strand: MyceliumStrand) -> float:
	return smoothstep(strand.growth_start, strand.growth_end, growth_amount)


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


func _focus_uv() -> Vector2:
	var half_size := patch_radius * SUBSTRATE_MARGIN
	return Vector2(
		(focus_position.x + half_size) / (half_size * 2.0),
		(focus_position.y + half_size) / (half_size * 2.0)
	)


func _activation_for_strand(strand: MyceliumStrand) -> float:
	if not active or strand.points.is_empty():
		return 0.0

	var best_distance := INF
	for point in strand.points:
		best_distance = minf(best_distance, point.distance_to(focus_position))

	var activation := 1.0 - clampf((best_distance - focus_radius * 0.18) / focus_radius, 0.0, 1.0)
	return clampf(activation + strand.activation_bias * 0.18, 0.0, 1.0)


func _draw_source_pores() -> void:
	for index in range(_source_points.size()):
		var source_point := _source_points[index]
		var pulse := (sin(_time * 1.8 + float(index) * 1.3) + 1.0) * 0.5
		var reveal := smoothstep(0.0, 0.35, growth_amount)
		draw_circle(source_point, 21.0 + pulse * 2.5, Color(0.22, 0.10, 0.12, 0.22 * reveal))
		draw_circle(source_point, 5.5 + pulse * 1.1, Color(0.67, 0.50, 0.30, 0.46 * reveal))


func _draw_spore_dust() -> void:
	for index in range(_spore_points.size()):
		var point := _spore_points[index]
		var pulse := (sin(_time * 2.5 + float(index) * 0.9) + 1.0) * 0.5
		draw_circle(point, 1.5 + pulse * 0.8, Color(0.63, 0.69, 0.47, 0.20 + pulse * 0.16))


func _draw_focus_glow() -> void:
	if not active:
		return

	var pulse := (sin(_time * 3.8) + 1.0) * 0.5
	draw_circle(focus_position, focus_radius * (0.18 + pulse * 0.025), Color(0.44, 0.63, 0.58, 0.045))
	draw_arc(
		focus_position,
		focus_radius * 0.26,
		0.0,
		TAU,
		48,
		Color(0.62, 0.78, 0.65, 0.12 + pulse * 0.08),
		1.0,
		true
	)


class MyceliumStrand:
	var points := PackedVector2Array()
	var width: float = 1.0
	var phase: float = 0.0
	var flow_speed: float = 0.16
	var growth_start: float = 0.0
	var growth_end: float = 1.0
	var gap_phase: float = 0.0
	var activation_bias: float = 0.0
