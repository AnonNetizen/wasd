class_name TestLabUndergroundSpawnBeacon
extends Node2D

## Experiment-only, absolute-time enemy spawn warning assembled from external textures.

enum Phase {
	CHARGE,
	ERUPTION,
	BREAKOUT,
	REST,
}

const LUMA_SHADER: Shader = preload("res://shaders/underground_spawn_luma.gdshader")
const DARK_SHADER: Shader = preload("res://shaders/underground_spawn_dark.gdshader")
const BEAM_SHADER: Shader = preload("res://shaders/underground_spawn_beam.gdshader")
const BASE_DURATION: float = 1.5
const REST_DURATION: float = 0.25
const PARTICLE_COUNT: int = 5

var _duration: float = BASE_DURATION
var _charge_end: float = 0.45
var _eruption_end: float = 1.25
var _breakout_end: float = BASE_DURATION
var _cycle_end: float = BASE_DURATION + REST_DURATION
var _preview_time: float = 0.0
var _active_phase: int = Phase.REST
var _display_scale: float = 1.0
var _seed: int = 1
var _deep_color: Color = Color("5a0b20")
var _danger_color: Color = Color("ed2f72")
var _hot_color: Color = Color.WHITE
var _well_diameter: float = 16.0
var _inner_radius_base: float = 18.0
var _outer_radius_base: float = 26.0
var _beam_height: float = 64.0
var _beam_width: float = 22.0
var _breakout_beam_width: float = 30.0
var _current_inner_radius: float = 18.0
var _current_outer_radius: float = 26.0
var _beam_reveal: float = 0.0
var _beam_anchor_y: float = 0.0
var _particle_sprites: Array[Sprite2D] = []
var _particle_specs: Array[Dictionary] = []
var _materials: Array[ShaderMaterial] = []
var _ground_glow: Sprite2D = null
var _dark_well: Sprite2D = null
var _outer_ring: Sprite2D = null
var _inner_ring: Sprite2D = null
var _hot_core: Sprite2D = null
var _breakout_splat: Sprite2D = null
var _beam: Sprite2D = null
var _ground_glow_material: ShaderMaterial = null
var _dark_well_material: ShaderMaterial = null
var _outer_ring_material: ShaderMaterial = null
var _inner_ring_material: ShaderMaterial = null
var _hot_core_material: ShaderMaterial = null
var _breakout_splat_material: ShaderMaterial = null
var _beam_material: ShaderMaterial = null


func configure(
	assets: Dictionary,
	palette: Dictionary,
	timing: Dictionary,
	geometry: Dictionary,
	display_scale: float,
	seed: int,
	duration: float = BASE_DURATION
) -> void:
	_display_scale = maxf(display_scale, 0.1)
	_seed = maxi(seed, 1)
	_duration = maxf(duration, 0.15)
	_deep_color = palette.get("deep", _deep_color) as Color
	_danger_color = palette.get("danger", _danger_color) as Color
	_hot_color = palette.get("hot", _hot_color) as Color
	_well_diameter = float(geometry.get("well_diameter", _well_diameter))
	_inner_radius_base = float(geometry.get("inner_ring_radius", _inner_radius_base))
	_outer_radius_base = float(geometry.get("outer_ring_radius", _outer_radius_base))
	_beam_height = float(geometry.get("beam_height", _beam_height))
	_beam_width = float(geometry.get("beam_width", _beam_width))
	_breakout_beam_width = float(geometry.get("breakout_beam_width", _breakout_beam_width))
	var base_breakout_end: float = float(timing.get("breakout_end", BASE_DURATION))
	var duration_ratio: float = _duration / maxf(base_breakout_end, 0.001)
	_charge_end = float(timing.get("charge_end", 0.45)) * duration_ratio
	_eruption_end = float(timing.get("eruption_end", 1.25)) * duration_ratio
	_breakout_end = _duration
	_cycle_end = _duration + REST_DURATION
	if not (_charge_end > 0.0 and _eruption_end > _charge_end and _breakout_end > _eruption_end):
		push_error("Underground spawn beacon timing must be strictly increasing.")
		return
	scale = Vector2.ONE * _display_scale
	_build_visuals(assets)
	_build_particle_sprites(assets)
	reset_preview()


func set_preview_time(value: float, _force_seek: bool = true) -> void:
	_preview_time = fposmod(maxf(value, 0.0), _cycle_end)
	_active_phase = _phase_for_time(_preview_time)
	_update_ground_and_beam()
	_update_particle_sprites()


func reset_preview() -> void:
	_active_phase = Phase.REST
	for particle: Sprite2D in _particle_sprites:
		particle.visible = false
	set_preview_time(0.0, true)


func debug_state() -> Dictionary:
	var active_particles: int = 0
	var all_particles_at_or_above_ground: bool = true
	for particle: Sprite2D in _particle_sprites:
		if particle.visible:
			active_particles += 1
			all_particles_at_or_above_ground = all_particles_at_or_above_ground and particle.position.y <= 0.001
	return {
		"phase": phase_name(_active_phase),
		"preview_time": _preview_time,
		"duration": _duration,
		"cycle_end": _cycle_end,
		"display_scale": _display_scale,
		"seed": _seed,
		"inner_ring_radius": _current_inner_radius,
		"outer_ring_radius": _current_outer_radius,
		"beam_reveal": _beam_reveal,
		"beam_height": _beam_height,
		"beam_visible_height": _beam_height * _beam_reveal,
		"beam_width": _beam_width,
		"beam_anchor_y": _beam_anchor_y,
		"beam_sprite_y": _beam.position.y if _beam != null else 0.0,
		"beam_node_visible": _beam.visible if _beam != null else false,
		"beam_direction": "UPWARD_FROM_FIXED_BASE",
		"particle_count": _particle_sprites.size(),
		"active_particles": active_particles,
		"particles_at_or_above_ground": all_particles_at_or_above_ground,
		"particle_vertical_velocity_max": -28.0,
		"node_count": _recursive_node_count(self),
		"material_count": _materials.size(),
	}


static func phase_name(phase: int) -> String:
	match phase:
		Phase.CHARGE:
			return "CHARGE"
		Phase.ERUPTION:
			return "ERUPTION"
		Phase.BREAKOUT:
			return "BREAKOUT"
		_:
			return "REST"


func _build_visuals(assets: Dictionary) -> void:
	var ground_cells: Array = assets.get("ground_cells", []) as Array
	var particle_cells: Array = assets.get("particle_cells", []) as Array
	var beam_texture: Texture2D = assets.get("upward_beam") as Texture2D
	if ground_cells.size() < 16 or particle_cells.size() < 16 or beam_texture == null:
		push_error("Underground spawn beacon visual assets are incomplete.")
		return
	_ground_glow = _create_luma_sprite("GroundGlow", ground_cells[6] as Texture2D, -2)
	_ground_glow_material = _ground_glow.material as ShaderMaterial
	_dark_well = _create_dark_sprite("DarkWell", ground_cells[5] as Texture2D, -1)
	_dark_well_material = _dark_well.material as ShaderMaterial
	_outer_ring = _create_luma_sprite("OuterOrganicRing", ground_cells[2] as Texture2D, 1)
	_outer_ring_material = _outer_ring.material as ShaderMaterial
	_inner_ring = _create_luma_sprite("InnerOrganicRing", ground_cells[10] as Texture2D, 2)
	_inner_ring_material = _inner_ring.material as ShaderMaterial
	_hot_core = _create_luma_sprite("WhiteHotCore", particle_cells[5] as Texture2D, 5)
	_hot_core_material = _hot_core.material as ShaderMaterial
	_breakout_splat = _create_luma_sprite("BreakoutSlimeRipple", ground_cells[13] as Texture2D, 0)
	_breakout_splat_material = _breakout_splat.material as ShaderMaterial

	_beam = Sprite2D.new()
	_beam.name = "BottomAnchoredUpwardBeam"
	_beam.texture = beam_texture
	_beam.centered = true
	_beam.position = Vector2(0.0, -_beam_height * 0.5)
	_beam_anchor_y = 0.0
	_beam.z_index = 3
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = BEAM_SHADER
	_beam_material.set_shader_parameter("deep_color", _deep_color)
	_beam_material.set_shader_parameter("danger_color", _danger_color)
	_beam_material.set_shader_parameter("hot_color", _hot_color)
	_beam.material = _beam_material
	_materials.append(_beam_material)
	add_child(_beam)
	_set_sprite_size(_beam, Vector2(_beam_height * 1.28, _beam_height))


func _build_particle_sprites(assets: Dictionary) -> void:
	var cells: Array = assets.get("particle_cells", []) as Array
	if cells.size() < 16:
		push_error("Underground spawn beacon particle atlas did not provide 16 cells.")
		return
	var random := RandomNumberGenerator.new()
	random.seed = _seed
	for index: int in range(PARTICLE_COUNT):
		var particle := _create_luma_sprite("UpwardParticle%02d" % index, cells[(index * 5 + 1) % 16] as Texture2D, 4)
		particle.visible = false
		_particle_sprites.append(particle)
		var side: float = -1.0 if index % 2 == 0 else 1.0
		_particle_specs.append({
			"start": random.randf_range(0.0, 0.62),
			"life": random.randf_range(0.24, 0.48),
			"origin_x": random.randf_range(-8.0, 8.0),
			"drift": side * random.randf_range(3.0, 12.0),
			"rise": random.randf_range(28.0, 52.0),
			"scale": random.randf_range(9.0, 16.0),
			"breakout_delay": random.randf_range(0.0, 0.065),
			"breakout_x": side * random.randf_range(18.0, 42.0),
			"breakout_rise": random.randf_range(30.0, 54.0),
		})


func _create_luma_sprite(node_name: String, texture: Texture2D, z_index_value: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = true
	sprite.z_index = z_index_value
	var shader_material := ShaderMaterial.new()
	shader_material.shader = LUMA_SHADER
	shader_material.set_shader_parameter("deep_color", _deep_color)
	shader_material.set_shader_parameter("primary_color", _danger_color)
	shader_material.set_shader_parameter("hot_color", _hot_color)
	sprite.material = shader_material
	_materials.append(shader_material)
	add_child(sprite)
	return sprite


func _create_dark_sprite(node_name: String, texture: Texture2D, z_index_value: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = texture
	sprite.centered = true
	sprite.z_index = z_index_value
	var shader_material := ShaderMaterial.new()
	shader_material.shader = DARK_SHADER
	shader_material.set_shader_parameter("dark_color", Color(0.008, 0.001, 0.004, 1.0))
	sprite.material = shader_material
	_materials.append(shader_material)
	add_child(sprite)
	return sprite


func _update_ground_and_beam() -> void:
	_hide_visuals()
	match _active_phase:
		Phase.CHARGE:
			_update_charge(_preview_time / _charge_end)
		Phase.ERUPTION:
			_update_eruption((_preview_time - _charge_end) / (_eruption_end - _charge_end))
		Phase.BREAKOUT:
			_update_breakout((_preview_time - _eruption_end) / (_breakout_end - _eruption_end))
		_:
			_current_inner_radius = 0.0
			_current_outer_radius = 0.0
			_beam_reveal = 0.0


func _update_charge(progress: float) -> void:
	var eased: float = _smooth(progress)
	_current_inner_radius = lerpf(_inner_radius_base, _inner_radius_base * 0.82, eased)
	_current_outer_radius = lerpf(_outer_radius_base, _outer_radius_base * 0.84, eased)
	_beam_reveal = 0.0
	_show_ground_base(eased)
	_inner_ring.visible = true
	_outer_ring.visible = true
	_set_ring_radius(_inner_ring, _current_inner_radius)
	_set_ring_radius(_outer_ring, _current_outer_radius)
	_inner_ring_material.set_shader_parameter("opacity", lerpf(0.35, 1.35, eased))
	_outer_ring_material.set_shader_parameter("opacity", lerpf(0.25, 1.0, eased))
	_hot_core.visible = true
	_set_sprite_size(_hot_core, Vector2.ONE * lerpf(7.0, 12.0, eased))
	_hot_core_material.set_shader_parameter("opacity", lerpf(0.06, 0.36, eased))
	_hot_core_material.set_shader_parameter("hot_mix", 0.0)


func _update_eruption(progress: float) -> void:
	var eased: float = _smooth(progress)
	_current_inner_radius = lerpf(_inner_radius_base * 0.82, _inner_radius_base * 0.64, eased)
	_current_outer_radius = lerpf(_outer_radius_base * 0.84, _outer_radius_base * 0.69, eased)
	_beam_reveal = pow(progress, 0.72)
	_show_ground_base(1.0)
	_inner_ring.visible = true
	_outer_ring.visible = true
	_set_ring_radius(_inner_ring, _current_inner_radius)
	_set_ring_radius(_outer_ring, _current_outer_radius)
	_inner_ring_material.set_shader_parameter("opacity", lerpf(1.25, 1.55, eased))
	_outer_ring_material.set_shader_parameter("opacity", lerpf(0.92, 1.28, eased))
	_hot_core.visible = true
	_set_sprite_size(_hot_core, Vector2.ONE * lerpf(12.0, 20.0, eased))
	_hot_core_material.set_shader_parameter("opacity", lerpf(0.38, 1.35, eased))
	_hot_core_material.set_shader_parameter("hot_mix", lerpf(0.0, 0.08, eased))
	_beam.visible = true
	_beam_material.set_shader_parameter("reveal_progress", _beam_reveal)
	_beam_material.set_shader_parameter("opacity", lerpf(0.42, 1.12, eased))
	_beam_material.set_shader_parameter("flash", 0.0)
	_set_beam_width(lerpf(_beam_width * 0.76, _beam_width, eased))


func _update_breakout(progress: float) -> void:
	var eased: float = _smooth(progress)
	var fade: float = 1.0 - smoothstep(0.72, 1.0, progress)
	var flash_window: float = (
		smoothstep(0.64, 0.72, progress)
		* (1.0 - smoothstep(0.82, 0.92, progress))
	)
	_current_inner_radius = 0.0
	_current_outer_radius = lerpf(_outer_radius_base * 0.69, _outer_radius_base * 1.25, eased)
	_beam_reveal = 1.0
	_ground_glow.visible = true
	_set_sprite_size(_ground_glow, Vector2.ONE * lerpf(_outer_radius_base * 2.0, _outer_radius_base * 2.45, eased))
	_ground_glow_material.set_shader_parameter("opacity", fade * 1.2)
	_breakout_splat.visible = true
	_set_sprite_size(_breakout_splat, Vector2.ONE * lerpf(_outer_radius_base * 1.9, _outer_radius_base * 2.55, eased))
	_breakout_splat_material.set_shader_parameter("opacity", fade * 0.72)
	_breakout_splat_material.set_shader_parameter("hot_mix", 0.08)
	_outer_ring.visible = true
	_set_ring_radius(_outer_ring, _current_outer_radius)
	_outer_ring_material.set_shader_parameter("opacity", fade * 1.55)
	_hot_core.visible = true
	_set_sprite_size(_hot_core, Vector2.ONE * lerpf(8.0, 14.0, eased))
	_hot_core_material.set_shader_parameter("opacity", fade * 1.8)
	_hot_core_material.set_shader_parameter("hot_mix", 1.0)
	_beam.visible = true
	_beam_material.set_shader_parameter("reveal_progress", 1.0)
	_beam_material.set_shader_parameter("opacity", fade * 1.45)
	_beam_material.set_shader_parameter("flash", flash_window * 0.72)
	_set_beam_width(lerpf(_beam_width, _breakout_beam_width, sin(progress * PI)))


func _show_ground_base(progress: float) -> void:
	_ground_glow.visible = true
	_set_sprite_size(_ground_glow, Vector2.ONE * lerpf(_outer_radius_base * 1.65, _outer_radius_base * 2.0, progress))
	_ground_glow_material.set_shader_parameter("opacity", lerpf(0.12, 0.72, progress))
	_ground_glow_material.set_shader_parameter("hot_mix", 0.0)
	_dark_well.visible = true
	_set_sprite_size(_dark_well, Vector2.ONE * lerpf(_well_diameter * 0.72, _well_diameter, progress))
	_dark_well_material.set_shader_parameter("opacity", lerpf(0.35, 0.9, progress))


func _hide_visuals() -> void:
	for sprite: Sprite2D in [_ground_glow, _dark_well, _outer_ring, _inner_ring, _hot_core, _breakout_splat, _beam]:
		if sprite != null:
			sprite.visible = false


func _update_particle_sprites() -> void:
	for index: int in range(_particle_sprites.size()):
		var particle: Sprite2D = _particle_sprites[index]
		var spec: Dictionary = _particle_specs[index]
		particle.visible = false
		if _active_phase == Phase.ERUPTION:
			_update_rising_particle(particle, spec)
		elif _active_phase == Phase.BREAKOUT:
			_update_breakout_particle(particle, spec)


func _update_rising_particle(particle: Sprite2D, spec: Dictionary) -> void:
	var phase_duration: float = _eruption_end - _charge_end
	var elapsed: float = _preview_time - _charge_end
	var start: float = float(spec["start"]) * phase_duration
	var life: float = minf(float(spec["life"]), phase_duration - start + 0.01)
	var age: float = elapsed - start
	if age < 0.0 or age > life:
		return
	var progress: float = clampf(age / life, 0.0, 1.0)
	particle.visible = true
	particle.position = Vector2(
		float(spec["origin_x"]) + float(spec["drift"]) * progress,
		-float(spec["rise"]) * _smooth(progress)
	)
	var size: float = float(spec["scale"]) * lerpf(0.72, 1.0, sin(progress * PI))
	_set_sprite_size(particle, Vector2.ONE * size)
	particle.modulate.a = sin(progress * PI)


func _update_breakout_particle(particle: Sprite2D, spec: Dictionary) -> void:
	var elapsed: float = _preview_time - _eruption_end
	var delay: float = float(spec["breakout_delay"])
	var life: float = _breakout_end - _eruption_end - delay + 0.01
	var age: float = elapsed - delay
	if age < 0.0 or age > life:
		return
	var progress: float = clampf(age / life, 0.0, 1.0)
	particle.visible = true
	particle.position = Vector2(
		float(spec["breakout_x"]) * _smooth(progress),
		-float(spec["breakout_rise"]) * _smooth(progress)
	)
	var size: float = float(spec["scale"]) * lerpf(1.18, 0.64, progress)
	_set_sprite_size(particle, Vector2.ONE * size)
	particle.modulate.a = 1.0 - progress


func _set_ring_radius(sprite: Sprite2D, radius: float) -> void:
	_set_sprite_size(sprite, Vector2.ONE * radius * 2.0)


func _set_beam_width(logical_width: float) -> void:
	if _beam == null or _beam.texture == null:
		return
	var texture_size: Vector2 = _beam.texture.get_size()
	var source_bounds_width: float = logical_width * 4.2
	_beam.scale = Vector2(source_bounds_width / texture_size.x, _beam_height / texture_size.y)


func _set_sprite_size(sprite: Sprite2D, target_size: Vector2) -> void:
	if sprite == null or sprite.texture == null:
		return
	var texture_size: Vector2 = sprite.texture.get_size()
	sprite.scale = Vector2(target_size.x / texture_size.x, target_size.y / texture_size.y)


func _phase_for_time(value: float) -> int:
	if value < _charge_end:
		return Phase.CHARGE
	if value < _eruption_end:
		return Phase.ERUPTION
	if value < _breakout_end:
		return Phase.BREAKOUT
	return Phase.REST


func _smooth(value: float) -> float:
	var clamped: float = clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


func _recursive_node_count(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _recursive_node_count(child)
	return count
