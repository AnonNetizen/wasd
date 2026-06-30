class_name TestLabMyceliumPatch
extends Node2D

const SUBSTRATE_SHADER := preload("res://shaders/mycelium_substrate.gdshader")
const STRAND_SHADER := preload("res://shaders/mycelium_strand.gdshader")

const MAX_BLOBS: int = 8
const SUBSTRATE_MARGIN: float = 1.18
const CREEP_DARK := Color(0.070, 0.025, 0.085, 0.94)
const CREEP_MID := Color(0.285, 0.065, 0.270, 0.92)
const CREEP_EDGE := Color(0.620, 0.135, 0.315, 0.86)
const CREEP_GLOSS := Color(0.900, 0.560, 0.980, 0.54)
const TENDRIL_DORMANT := Color(0.265, 0.115, 0.200, 0.58)
const TENDRIL_ACTIVE := Color(0.680, 0.245, 0.410, 0.66)
const TENDRIL_PULSE := Color(0.760, 0.560, 0.860, 0.40)
const PUSTULE_DARK := Color(0.155, 0.030, 0.055, 0.66)
const PUSTULE_CORE := Color(0.880, 0.530, 0.230, 0.76)

@export var seed: int = 1739
@export_range(180.0, 620.0, 1.0) var patch_radius: float = 350.0
@export_range(5, 7, 1) var source_count: int = 6
@export_range(0.4, 1.8, 0.05) var strand_density: float = 1.0
@export_range(0.0, 1.0, 0.01) var growth_amount: float = 0.76
@export_range(48.0, 280.0, 1.0) var focus_radius: float = 150.0
@export var active: bool = true

var focus_position: Vector2 = Vector2.ZERO

var _substrate: Polygon2D
var _substrate_material: ShaderMaterial
var _tendril_root: Node2D
var _tendrils: Array[CreepTendril] = []
var _tendril_lines: Array[Line2D] = []
var _tendril_materials: Array[ShaderMaterial] = []
var _blob_data := PackedVector4Array()
var _blob_local_centers := PackedVector2Array()
var _creep_polygon := PackedVector2Array()
var _pustules: Array[CreepPustule] = []
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
	focus_position = local_position.limit_length(patch_radius * SUBSTRATE_MARGIN)


func set_growth_amount(new_growth_amount: float) -> void:
	growth_amount = clampf(new_growth_amount, 0.0, 1.0)


func regenerate(new_seed: int) -> void:
	seed = new_seed
	_generate_creep()
	queue_redraw()


func _draw() -> void:
	_draw_edge_rim()
	_draw_visible_tendrils()
	_draw_membrane_veins()
	_draw_pustules()
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
	_tendrils.clear()
	_tendril_lines.clear()
	_tendril_materials.clear()
	_blob_data.clear()
	_blob_local_centers.clear()
	_creep_polygon.clear()
	_pustules.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	_generate_blob_field(rng)
	_configure_substrate_polygon(rng)
	_generate_edge_tendrils(rng)
	_generate_pustules(rng)
	_build_tendril_nodes()
	_update_material_uniforms()


func _configure_substrate_polygon(_rng: RandomNumberGenerator) -> void:
	var half_size := patch_radius * SUBSTRATE_MARGIN
	var polygon := PackedVector2Array()
	var uvs := PackedVector2Array()
	var contour_count := 160
	for index in range(contour_count):
		var ratio := float(index) / float(contour_count)
		var angle := ratio * TAU
		var direction := Vector2.from_angle(angle)
		var radius := _radius_for_direction(direction, half_size)
		radius *= 0.96
		radius += sin(angle * 3.0 + float(seed) * 0.013) * patch_radius * 0.030
		radius += sin(angle * 7.0 + float(seed) * 0.021) * patch_radius * 0.018
		radius += sin(angle * 11.0 + float(seed) * 0.034) * patch_radius * 0.010
		var point := direction * radius
		polygon.append(point)
		uvs.append(Vector2(
			(point.x + half_size) / (half_size * 2.0),
			(point.y + half_size) / (half_size * 2.0)
		))

	_substrate.polygon = polygon
	_substrate.uv = uvs
	_substrate.color = Color.WHITE
	_creep_polygon = polygon


func _radius_for_direction(direction: Vector2, half_size: float) -> float:
	var best_radius: float = patch_radius * 0.26
	for blob in _blob_data:
		if blob.z <= 0.0:
			continue
		var center := Vector2(
			blob.x * half_size * 2.0 - half_size,
			blob.y * half_size * 2.0 - half_size
		)
		var local_radius: float = blob.z * half_size * 1.28
		var projection: float = center.dot(direction)
		var perpendicular: float = absf(center.cross(direction))
		if perpendicular > local_radius:
			continue
		var reach: float = projection + sqrt(maxf(0.0, local_radius * local_radius - perpendicular * perpendicular))
		best_radius = maxf(best_radius, reach)
	return clampf(best_radius, patch_radius * 0.28, patch_radius * 0.98)


func _clear_tendril_nodes() -> void:
	if _tendril_root == null:
		return

	for child in _tendril_root.get_children():
		child.queue_free()


func _generate_blob_field(rng: RandomNumberGenerator) -> void:
	var half_size := patch_radius * SUBSTRATE_MARGIN
	var primary_angle := rng.randf_range(0.0, TAU)
	var primary_radius := patch_radius * rng.randf_range(0.08, 0.18)
	var primary_center := Vector2.from_angle(primary_angle) * primary_radius
	_add_blob(primary_center, rng.randf_range(0.27, 0.34), rng.randf_range(0.0, TAU), half_size)

	for index in range(source_count - 1):
		var ratio := float(index) / float(maxi(1, source_count - 1))
		var angle := primary_angle + ratio * TAU + rng.randf_range(-0.36, 0.36)
		var radius := patch_radius * rng.randf_range(0.25, 0.70)
		var center := Vector2.from_angle(angle) * radius
		var blob_radius := rng.randf_range(0.18, 0.27)
		_add_blob(center, blob_radius, rng.randf_range(0.0, TAU), half_size)

	while _blob_data.size() < MAX_BLOBS:
		_blob_data.append(Vector4(0.5, 0.5, 0.0, 0.0))


func _add_blob(local_center: Vector2, normalized_radius: float, phase: float, half_size: float) -> void:
	var clamped_center := local_center.limit_length(patch_radius * 0.82)
	_blob_local_centers.append(clamped_center)
	_blob_data.append(Vector4(
		(clamped_center.x + half_size) / (half_size * 2.0),
		(clamped_center.y + half_size) / (half_size * 2.0),
		normalized_radius,
		phase
	))


func _generate_edge_tendrils(rng: RandomNumberGenerator) -> void:
	var tendril_count := maxi(9, int(round(13.0 * strand_density)))
	for index in range(tendril_count):
		var blob_index := rng.randi_range(0, _blob_local_centers.size() - 1)
		var blob_center := _blob_local_centers[blob_index]
		var direction := _edge_direction_for_blob(blob_center, rng)
		var origin := blob_center + direction * patch_radius * rng.randf_range(0.18, 0.34)
		var length := rng.randf_range(34.0, 82.0)
		var points := _make_tendril_points(rng, origin, direction, length)
		if points.size() < 3:
			continue

		var tendril := CreepTendril.new()
		tendril.points = points
		tendril.width = rng.randf_range(1.4, 3.2)
		tendril.phase = rng.randf_range(0.0, TAU)
		tendril.flow_speed = rng.randf_range(0.10, 0.24)
		tendril.growth_start = rng.randf_range(0.18, 0.58)
		tendril.growth_end = rng.randf_range(0.62, 1.0)
		_tendrils.append(tendril)


func _edge_direction_for_blob(blob_center: Vector2, rng: RandomNumberGenerator) -> Vector2:
	if blob_center.length_squared() <= 1.0:
		return Vector2.from_angle(rng.randf_range(0.0, TAU))
	return blob_center.normalized().rotated(rng.randf_range(-0.85, 0.85))


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
		current = current.limit_length(patch_radius * 1.06)
		points.append(current)

	return points


func _generate_pustules(rng: RandomNumberGenerator) -> void:
	var pustule_count := rng.randi_range(10, 18)
	for index in range(pustule_count):
		var blob_index := rng.randi_range(0, _blob_local_centers.size() - 1)
		var base := _blob_local_centers[blob_index]
		var offset := Vector2.from_angle(rng.randf_range(0.0, TAU)) * patch_radius * rng.randf_range(0.02, 0.20)
		var pustule := CreepPustule.new()
		pustule.position = (base + offset).limit_length(patch_radius * 0.88)
		pustule.radius = rng.randf_range(5.0, 15.0)
		pustule.phase = rng.randf_range(0.0, TAU)
		pustule.core_ratio = rng.randf_range(0.32, 0.55)
		_pustules.append(pustule)


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
	var focus_uv := _focus_uv()
	var normalized_focus_radius := clampf(focus_radius / (patch_radius * SUBSTRATE_MARGIN * 2.0), 0.02, 0.48)

	if _substrate_material != null:
		_substrate_material.set_shader_parameter("time", _time)
		_substrate_material.set_shader_parameter("growth_amount", growth_amount)
		_substrate_material.set_shader_parameter("decay_amount", decay_amount)
		_substrate_material.set_shader_parameter("focus_position", focus_uv)
		_substrate_material.set_shader_parameter("focus_radius", normalized_focus_radius)
		_substrate_material.set_shader_parameter("blob_count", mini(source_count, MAX_BLOBS))
		_substrate_material.set_shader_parameter("blob_data", _blob_data)
		for index in range(MAX_BLOBS):
			var blob := _blob_data[index]
			_substrate_material.set_shader_parameter("blob_%d" % index, Color(blob.x, blob.y, blob.z, blob.w))
		_substrate_material.set_shader_parameter("dark_color", CREEP_DARK)
		_substrate_material.set_shader_parameter("mid_color", CREEP_MID)
		_substrate_material.set_shader_parameter("edge_color", CREEP_EDGE)
		_substrate_material.set_shader_parameter("gloss_color", CREEP_GLOSS)

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
		material.set_shader_parameter("pulse_color", TENDRIL_PULSE)


func _focus_uv() -> Vector2:
	var half_size := patch_radius * SUBSTRATE_MARGIN
	return Vector2(
		(focus_position.x + half_size) / (half_size * 2.0),
		(focus_position.y + half_size) / (half_size * 2.0)
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


func _draw_pustules() -> void:
	var reveal := smoothstep(0.18, 0.62, growth_amount)
	for pustule in _pustules:
		var pulse := (sin(_time * 2.0 + pustule.phase) + 1.0) * 0.5
		var radius := pustule.radius * (0.88 + pulse * 0.14)
		draw_circle(pustule.position, radius * 1.72, Color(0.060, 0.015, 0.036, 0.30 * reveal))
		draw_circle(pustule.position, radius, Color(PUSTULE_DARK, PUSTULE_DARK.a * reveal))
		draw_circle(pustule.position, radius * pustule.core_ratio, Color(PUSTULE_CORE, PUSTULE_CORE.a * reveal * (0.72 + pulse * 0.20)))
		draw_arc(
			pustule.position,
			radius * 1.18,
			0.0,
			TAU,
			24,
			Color(0.86, 0.34, 0.58, 0.18 * reveal),
			1.0,
			true
		)


func _draw_edge_rim() -> void:
	if _creep_polygon.size() < 3:
		return

	var closed_polygon := PackedVector2Array(_creep_polygon)
	closed_polygon.append(_creep_polygon[0])
	var reveal := smoothstep(0.08, 0.50, growth_amount)
	draw_polyline(closed_polygon, Color(0.040, 0.005, 0.030, 0.52 * reveal), 8.0, true)
	draw_polyline(closed_polygon, Color(0.56, 0.11, 0.30, 0.34 * reveal), 3.0, true)
	draw_polyline(closed_polygon, Color(0.98, 0.50, 0.82, 0.12 * reveal), 1.0, true)


func _draw_visible_tendrils() -> void:
	var reveal := smoothstep(0.38, 0.86, growth_amount)
	if reveal <= 0.0:
		return

	for index in range(_tendrils.size()):
		if index % 2 != 0:
			continue
		var tendril := _tendrils[index]
		var partial := _partial_points(tendril.points, smoothstep(tendril.growth_start, tendril.growth_end, growth_amount))
		if partial.size() < 2:
			continue
		var pulse := (sin(_time * tendril.flow_speed * 5.0 + tendril.phase) + 1.0) * 0.5
		draw_polyline(partial, Color(0.10, 0.015, 0.075, 0.32 * reveal), tendril.width + 2.0, true)
		draw_polyline(partial, Color(0.72, 0.20, 0.48, (0.14 + pulse * 0.05) * reveal), maxf(1.0, tendril.width * 0.72), true)


func _draw_membrane_veins() -> void:
	var reveal := smoothstep(0.24, 0.68, growth_amount)
	if reveal <= 0.0:
		return

	for index in range(_blob_local_centers.size()):
		var center := _blob_local_centers[index]
		var next_center := _blob_local_centers[(index + 1) % _blob_local_centers.size()]
		var midpoint := center.lerp(next_center, 0.5)
		var pulse := (sin(_time * 1.25 + float(index) * 1.7) + 1.0) * 0.5
		draw_line(center, midpoint, Color(0.50, 0.13, 0.42, (0.10 + pulse * 0.05) * reveal), 2.0)
		draw_line(midpoint, next_center, Color(0.11, 0.02, 0.10, 0.16 * reveal), 1.5)


func _draw_focus_glow() -> void:
	if not active:
		return

	var pulse := (sin(_time * 3.6) + 1.0) * 0.5
	draw_circle(focus_position, focus_radius * (0.22 + pulse * 0.03), Color(0.62, 0.38, 0.70, 0.050))
	draw_arc(
		focus_position,
		focus_radius * 0.30,
		0.0,
		TAU,
		48,
		Color(0.78, 0.54, 0.86, 0.13 + pulse * 0.08),
		1.0,
		true
	)


class CreepTendril:
	var points := PackedVector2Array()
	var width: float = 2.0
	var phase: float = 0.0
	var flow_speed: float = 0.16
	var growth_start: float = 0.0
	var growth_end: float = 1.0


class CreepPustule:
	var position: Vector2 = Vector2.ZERO
	var radius: float = 8.0
	var phase: float = 0.0
	var core_ratio: float = 0.42
