class_name TestLabMyceliumPatch
extends Node2D

const BASE_STAIN_COLOR := Color(0.145, 0.095, 0.125, 0.56)
const BASE_EDGE_COLOR := Color(0.45, 0.31, 0.25, 0.32)
const STRAND_SHADOW_COLOR := Color(0.025, 0.018, 0.024, 0.42)
const STRAND_DORMANT_COLOR := Color(0.62, 0.49, 0.38, 0.70)
const STRAND_ALIVE_COLOR := Color(0.92, 0.83, 0.58, 0.92)
const STRAND_PULSE_COLOR := Color(0.52, 0.78, 0.82, 0.78)
const SPORE_COLOR := Color(0.78, 0.90, 0.64, 0.74)
const MIN_VISIBLE_SEGMENT_RATIO := 0.015

@export var seed: int = 1739
@export_range(120.0, 520.0, 1.0) var patch_radius: float = 300.0
@export_range(8, 72, 1) var strand_count: int = 34
@export_range(0.0, 1.0, 0.01) var growth_amount: float = 0.76
@export_range(24.0, 260.0, 1.0) var focus_radius: float = 150.0
@export var active: bool = true

var focus_position: Vector2 = Vector2.ZERO

var _strands: Array[MyceliumStrand] = []
var _time: float = 0.0


func _ready() -> void:
	focus_position = Vector2.ZERO
	_generate_network()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func set_focus_position(local_position: Vector2) -> void:
	focus_position = local_position.limit_length(patch_radius * 1.1)


func set_growth_amount(new_growth_amount: float) -> void:
	growth_amount = clampf(new_growth_amount, 0.0, 1.0)


func regenerate(new_seed: int) -> void:
	seed = new_seed
	_generate_network()
	queue_redraw()


func _draw() -> void:
	if _strands.is_empty():
		return

	_draw_substrate()
	_draw_strand_shadows()
	_draw_strands()
	_draw_spores()
	_draw_focus_glow()


func _generate_network() -> void:
	_strands.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	for index in range(strand_count):
		var base_angle: float = TAU * float(index) / float(strand_count)
		base_angle += rng.randf_range(-0.19, 0.19)
		var length := rng.randf_range(patch_radius * 0.58, patch_radius)
		var start := Vector2.from_angle(base_angle + PI) * rng.randf_range(0.0, 22.0)
		var width := rng.randf_range(2.2, 4.4)
		var step_count := rng.randi_range(9, 15)
		var growth_offset := rng.randf_range(0.0, 0.24)
		var strand := _make_strand(rng, start, base_angle, length, step_count, width, growth_offset)
		_strands.append(strand)
		_add_branches(rng, strand, length, width, growth_offset)


func _make_strand(
	rng: RandomNumberGenerator,
	start: Vector2,
	angle: float,
	length: float,
	step_count: int,
	width: float,
	growth_offset: float
) -> MyceliumStrand:
	var strand := MyceliumStrand.new()
	strand.width = width
	strand.phase = rng.randf_range(0.0, TAU)
	strand.flow_speed = rng.randf_range(0.22, 0.54)
	strand.growth_offset = growth_offset
	strand.points.append(start)

	var direction := Vector2.from_angle(angle)
	var current := start
	var bend := rng.randf_range(-0.9, 0.9)
	for step in range(1, step_count + 1):
		var ratio := float(step) / float(step_count)
		var wave_angle := angle + sin(ratio * PI + strand.phase) * bend * 0.28
		wave_angle += rng.randf_range(-0.14, 0.14)
		direction = direction.lerp(Vector2.from_angle(wave_angle), 0.52).normalized()
		current += direction * (length / float(step_count)) * rng.randf_range(0.82, 1.16)
		if current.length() > patch_radius:
			current = current.normalized() * patch_radius
		strand.points.append(current)

	return strand


func _add_branches(
	rng: RandomNumberGenerator,
	parent: MyceliumStrand,
	parent_length: float,
	parent_width: float,
	parent_growth_offset: float
) -> void:
	if parent.points.size() < 5:
		return

	var branch_count := rng.randi_range(1, 3)
	for _branch_index in range(branch_count):
		var start_index := rng.randi_range(2, parent.points.size() - 2)
		var origin := parent.points[start_index]
		var parent_direction := (parent.points[start_index + 1] - parent.points[start_index - 1]).normalized()
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var branch_angle := parent_direction.angle() + side * rng.randf_range(0.48, 1.15)
		var branch_length := parent_length * rng.randf_range(0.16, 0.34)
		var branch_steps := rng.randi_range(4, 7)
		var branch_width := maxf(1.0, parent_width * rng.randf_range(0.34, 0.56))
		var growth_offset := clampf(parent_growth_offset + rng.randf_range(0.12, 0.34), 0.0, 0.82)
		var branch := _make_strand(rng, origin, branch_angle, branch_length, branch_steps, branch_width, growth_offset)
		_strands.append(branch)


func _draw_substrate() -> void:
	var points := PackedVector2Array()
	for index in range(72):
		var angle := TAU * float(index) / 72.0
		var radius := patch_radius * 0.76
		radius += sin(angle * 3.0 + _time * 0.18) * patch_radius * 0.045
		radius += sin(angle * 7.0 - _time * 0.11) * patch_radius * 0.025
		points.append(Vector2.from_angle(angle) * radius)

	var alpha_scale := smoothstep(0.05, 0.64, growth_amount)
	draw_colored_polygon(points, Color(BASE_STAIN_COLOR, BASE_STAIN_COLOR.a * alpha_scale))

	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, Color(BASE_EDGE_COLOR, BASE_EDGE_COLOR.a * alpha_scale), 2.0, true)


func _draw_strand_shadows() -> void:
	for strand in _strands:
		var partial_points := _partial_points(strand.points, _strand_visibility(strand))
		if partial_points.size() < 2:
			continue
		draw_polyline(partial_points, STRAND_SHADOW_COLOR, strand.width + 4.0, true)


func _draw_strands() -> void:
	for strand in _strands:
		var visibility := _strand_visibility(strand)
		var partial_points := _partial_points(strand.points, visibility)
		if partial_points.size() < 2:
			continue

		var activation := _activation_for_strand(strand)
		var pulse := (sin(_time * 3.4 + strand.phase) + 1.0) * 0.5
		var color := STRAND_DORMANT_COLOR.lerp(STRAND_ALIVE_COLOR, activation)
		color.a *= 0.56 + pulse * 0.18 + activation * 0.24
		draw_polyline(partial_points, color, strand.width, true)

		var highlight := Color(STRAND_PULSE_COLOR, STRAND_PULSE_COLOR.a * activation * (0.45 + pulse * 0.42))
		if activation > 0.05:
			draw_polyline(partial_points, highlight, maxf(1.0, strand.width * 0.36), true)
			_draw_flow_pulse(strand, visibility, activation)


func _draw_spores() -> void:
	for index in range(_strands.size()):
		if index % 3 != 0:
			continue
		var strand := _strands[index]
		var visibility := _strand_visibility(strand)
		if visibility < 0.92 or strand.points.is_empty():
			continue

		var activation := _activation_for_strand(strand)
		var end_point := strand.points[strand.points.size() - 1]
		var spore_radius := 2.4 + sin(_time * 4.2 + strand.phase) * 0.8
		var spore_color := Color(SPORE_COLOR, SPORE_COLOR.a * (0.35 + activation * 0.58))
		draw_circle(end_point, maxf(1.0, spore_radius), spore_color)


func _draw_focus_glow() -> void:
	if not active:
		return

	var pulse := (sin(_time * 4.8) + 1.0) * 0.5
	draw_circle(focus_position, focus_radius * (0.25 + pulse * 0.04), Color(0.42, 0.64, 0.62, 0.08))
	draw_arc(
		focus_position,
		focus_radius * 0.31,
		0.0,
		TAU,
		48,
		Color(0.74, 0.90, 0.78, 0.22 + pulse * 0.14),
		1.5,
		true
	)


func _draw_flow_pulse(strand: MyceliumStrand, visibility: float, activation: float) -> void:
	var pulse_ratio := fposmod(_time * strand.flow_speed + strand.phase / TAU, 1.0)
	if pulse_ratio > visibility:
		return

	var pulse_point := _point_at_ratio(strand.points, pulse_ratio)
	var pulse_radius := maxf(2.0, strand.width * 0.85)
	draw_circle(pulse_point, pulse_radius, Color(STRAND_PULSE_COLOR, STRAND_PULSE_COLOR.a * activation))


func _strand_visibility(strand: MyceliumStrand) -> float:
	var visible := (growth_amount - strand.growth_offset) / maxf(MIN_VISIBLE_SEGMENT_RATIO, 1.0 - strand.growth_offset)
	return smoothstep(0.0, 1.0, clampf(visible, 0.0, 1.0))


func _activation_for_strand(strand: MyceliumStrand) -> float:
	if not active or strand.points.is_empty():
		return 0.0

	var tip := strand.points[strand.points.size() - 1]
	var distance := tip.distance_to(focus_position)
	return 1.0 - clampf((distance - focus_radius * 0.25) / focus_radius, 0.0, 1.0)


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


func _point_at_ratio(points: PackedVector2Array, ratio: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]

	var segment_count := points.size() - 1
	var segment_position := clampf(ratio, 0.0, 1.0) * float(segment_count)
	var segment_index := mini(int(floor(segment_position)), segment_count - 1)
	var local_ratio := segment_position - float(segment_index)
	return points[segment_index].lerp(points[segment_index + 1], local_ratio)


class MyceliumStrand:
	var points := PackedVector2Array()
	var width: float = 2.0
	var phase: float = 0.0
	var flow_speed: float = 0.35
	var growth_offset: float = 0.0
