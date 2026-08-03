class_name TestLabGlowOrbBulletSample
extends Node2D

## Textureless gradient-orb projectile used only by the Test Lab.

enum TeamPalette {
	PLAYER_WHITE,
	ENEMY_RED,
}

const TEAM_COUNT: int = 2
const GRADIENT_STEP_COUNT: int = 10
const MAX_TRAIL_SAMPLES: int = 6
const TRAIL_SPACING: float = 7.0
const IMPACT_DURATION: float = 0.24
const POST_IMPACT_HOLD: float = 0.20

const PLAYER_BODY: Color = Color("dceaf2")
const PLAYER_HOT: Color = Color("ffffff")
const ENEMY_BODY: Color = Color("e62935")
const ENEMY_HOT: Color = Color("fff2ed")
const HITBOX_COLOR: Color = Color(0.26, 0.96, 0.78, 0.72)

var _team_palette: TeamPalette = TeamPalette.PLAYER_WHITE
var _hit_radius: float = 8.0
var _preview_scale: float = 1.0
var _speed: float = 0.0
var _lane_length: float = 0.0
var _phase_offset: float = 0.0
var _is_moving: bool = false
var _show_hitbox: bool = false
var _show_trail: bool = true
var _preview_time: float = 0.0
var _projectile_position: Vector2 = Vector2.ZERO
var _impact_progress: float = -1.0
var _trail_positions: Array[Vector2] = []


func configure(
	team_palette: TeamPalette,
	hit_radius: float,
	preview_scale: float,
	speed: float = 0.0,
	lane_length: float = 0.0,
	phase_offset: float = 0.0
) -> void:
	_team_palette = team_palette
	_hit_radius = maxf(hit_radius, 1.0)
	_preview_scale = maxf(preview_scale, 0.1)
	_speed = maxf(speed, 0.0)
	_lane_length = maxf(lane_length, 0.0)
	_phase_offset = phase_offset
	_is_moving = _speed > 0.0 and _lane_length > 0.0
	reset_preview()


func set_preview_time(value: float) -> void:
	_preview_time = maxf(value, 0.0)
	if not _is_moving:
		_projectile_position = Vector2.ZERO
		_impact_progress = -1.0
		_trail_positions.clear()
		queue_redraw()
		return

	var travel_duration: float = _lane_length / _speed
	var cycle_duration: float = travel_duration + IMPACT_DURATION + POST_IMPACT_HOLD
	var cycle_time: float = fposmod(_preview_time + _phase_offset, cycle_duration)
	if cycle_time < travel_duration:
		_projectile_position = Vector2(_speed * cycle_time, 0.0)
		_impact_progress = -1.0
		_rebuild_trail(cycle_time)
	elif cycle_time < travel_duration + IMPACT_DURATION:
		_projectile_position = Vector2(_lane_length, 0.0)
		_impact_progress = (cycle_time - travel_duration) / IMPACT_DURATION
		_trail_positions.clear()
	else:
		_projectile_position = Vector2(_lane_length, 0.0)
		_impact_progress = 2.0
		_trail_positions.clear()
	queue_redraw()


func reset_preview() -> void:
	_preview_time = 0.0
	_projectile_position = Vector2.ZERO
	_impact_progress = -1.0
	_trail_positions.clear()
	queue_redraw()


func set_hitbox_visible(visible: bool) -> void:
	_show_hitbox = visible
	queue_redraw()


func set_trail_visible(visible: bool) -> void:
	_show_trail = visible
	queue_redraw()


func debug_force_impact(progress: float) -> void:
	_projectile_position = Vector2(_lane_length, 0.0)
	_impact_progress = clampf(progress, 0.0, 1.0)
	_trail_positions.clear()
	queue_redraw()


func team_palette() -> int:
	return int(_team_palette)


func geometry_signature() -> String:
	return "circle:r1.0:gradient10:highlight_nw:no_outline:no_glow"


func primary_color() -> Color:
	return ENEMY_BODY if _team_palette == TeamPalette.ENEMY_RED else PLAYER_BODY


func core_visual_extent() -> float:
	return _hit_radius * _preview_scale * 0.98


func visual_body_extent() -> float:
	return core_visual_extent()


func external_glow_extent() -> float:
	return 0.0


func collision_radius() -> float:
	return _hit_radius * _preview_scale


func configured_hit_radius() -> float:
	return _hit_radius


func preview_speed() -> float:
	return _speed


func gradient_step_count() -> int:
	return GRADIENT_STEP_COUNT


func trail_sample_count() -> int:
	return _trail_positions.size()


func effect_child_count() -> int:
	return get_child_count()


func is_impact_active() -> bool:
	return _impact_progress >= 0.0 and _impact_progress <= 1.0


func _draw() -> void:
	var radius: float = _hit_radius * _preview_scale
	if _show_trail and _impact_progress < 0.0:
		_draw_trail(radius)
	if _show_hitbox and _impact_progress <= 1.0:
		draw_arc(
			_projectile_position,
			radius,
			0.0,
			TAU,
			32,
			HITBOX_COLOR,
			1.0,
			true
		)
	if _impact_progress >= 0.0:
		if _impact_progress <= 1.0:
			_draw_hit_effect(radius, _impact_progress)
		return
	_draw_body(_projectile_position, radius)


func _draw_body(center: Vector2, radius: float) -> void:
	draw_circle(center, radius * 0.98, _color("body", 1.0))
	for index in range(GRADIENT_STEP_COUNT):
		var ratio: float = float(index) / float(GRADIENT_STEP_COUNT - 1)
		var ring_radius: float = radius * lerpf(0.98, 0.12, ratio)
		var ring_center: Vector2 = center + Vector2(-0.11, -0.10) * radius * ratio
		var ring_color: Color = _color("body", 1.0).lerp(
			_color("hot", 1.0),
			pow(ratio, 1.55)
		)
		draw_circle(ring_center, ring_radius, ring_color)

	var highlight_center: Vector2 = center + Vector2(-radius * 0.31, -radius * 0.29)
	draw_circle(highlight_center, radius * 0.24, _color("hot", 0.24))
	draw_circle(highlight_center, radius * 0.15, _color("hot", 0.72))
	draw_circle(highlight_center, maxf(radius * 0.065, 1.0), _color("hot", 1.0))


func _draw_trail(radius: float) -> void:
	for index in range(_trail_positions.size()):
		var ratio: float = float(index + 1) / float(_trail_positions.size() + 1)
		var marker_radius: float = radius * lerpf(0.12, 0.34, ratio)
		var marker_position: Vector2 = _trail_positions[index]
		draw_circle(marker_position, marker_radius, _color("body", ratio * 0.30))
		draw_circle(
			marker_position + Vector2(-marker_radius * 0.20, -marker_radius * 0.20),
			maxf(marker_radius * 0.28, 0.7),
			_color("hot", ratio * 0.38)
		)


func _draw_hit_effect(radius: float, progress: float) -> void:
	var fade: float = 1.0 - progress
	var center: Vector2 = _projectile_position
	draw_arc(
		center,
		radius * lerpf(0.58, 2.05, progress),
		0.0,
		TAU,
		32,
		_color("hot", fade * 0.92),
		maxf(radius * lerpf(0.16, 0.04, progress), 1.0),
		true
	)
	for index in range(6):
		var angle: float = float(index) * TAU / 6.0
		var spark_center: Vector2 = center + Vector2.from_angle(angle) * radius * lerpf(0.34, 1.65, progress)
		draw_circle(
			spark_center,
			radius * lerpf(0.11, 0.025, progress),
			_color("body", fade * 0.85)
		)


func _rebuild_trail(travel_time: float) -> void:
	_trail_positions.clear()
	var travelled: float = _speed * travel_time
	var sample_count: int = mini(
		MAX_TRAIL_SAMPLES,
		int(floor(travelled / TRAIL_SPACING))
	)
	for sample_index in range(sample_count, 0, -1):
		_trail_positions.append(
			_projectile_position - Vector2(TRAIL_SPACING * float(sample_index), 0.0)
		)


func _color(role: String, alpha: float) -> Color:
	var color: Color
	if _team_palette == TeamPalette.ENEMY_RED:
		match role:
			"hot":
				color = ENEMY_HOT
			_:
				color = ENEMY_BODY
	else:
		match role:
			"hot":
				color = PLAYER_HOT
			_:
				color = PLAYER_BODY
	color.a *= clampf(alpha, 0.0, 1.0)
	return color
