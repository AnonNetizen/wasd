class_name TestLabOrganicVfxCandidate
extends Node2D

## Shared experiment-only interface for the four non-geometric VFX pipelines.

enum Phase {
	CHARGE,
	CONTACT,
	AFTERMATH,
	REST,
}

const LUMA_SHADER: Shader = preload("res://shaders/organic_vfx_luma_atlas.gdshader")
const FLOW_SHADER: Shader = preload("res://shaders/organic_vfx_flow.gdshader")

const PIPELINES: PackedStringArray = ["flipbook", "particles", "shader", "hybrid"]

var _pipeline_id: String = ""
var _display_scale: float = 1.0
var _seed: int = 1
var _core_radius: float = 48.0
var _decorative_radius: float = 72.0
var _preview_time: float = 0.0
var _active_phase: int = Phase.REST
var _charge_end: float = 0.48
var _contact_end: float = 0.64
var _aftermath_end: float = 1.20
var _cycle_end: float = 1.44
var _angry_dominant: bool = false
var _calm_color: Color = Color("68bcdd")
var _angry_color: Color = Color("ed2f72")
var _hot_color: Color = Color.WHITE
var _flipbook_sprite: Sprite2D = null
var _flow_sprite: Sprite2D = null
var _materials: Array[ShaderMaterial] = []
var _particle_emitters: Array[CPUParticles2D] = []


func configure(
	pipeline_id: String,
	assets: Dictionary,
	palette: Dictionary,
	timing: Dictionary,
	display_scale: float,
	seed: int,
	core_radius: float,
	decorative_radius: float
) -> void:
	if not PIPELINES.has(pipeline_id):
		push_error("Unknown organic VFX pipeline: %s" % pipeline_id)
		return
	_pipeline_id = pipeline_id
	_display_scale = maxf(display_scale, 0.1)
	_seed = maxi(seed, 1)
	_core_radius = maxf(core_radius, 1.0)
	_decorative_radius = maxf(decorative_radius, _core_radius)
	_calm_color = palette.get("calm", _calm_color) as Color
	_angry_color = palette.get("angry", _angry_color) as Color
	_hot_color = palette.get("hot", _hot_color) as Color
	_charge_end = float(timing.get("charge_end", _charge_end))
	_contact_end = float(timing.get("contact_end", _contact_end))
	_aftermath_end = float(timing.get("aftermath_end", _aftermath_end))
	_cycle_end = float(timing.get("cycle_end", _cycle_end))
	if not (_charge_end > 0.0 and _contact_end > _charge_end and _aftermath_end > _contact_end and _cycle_end > _aftermath_end):
		push_error("Organic VFX timing must be strictly increasing.")
		return
	scale = Vector2.ONE * _display_scale

	match _pipeline_id:
		"flipbook":
			_build_flipbook(assets, 1.0)
		"particles":
			_build_particle_layers(assets, false)
		"shader":
			_build_flow_mask(assets, 1.0)
		"hybrid":
			_build_flow_mask(assets, 0.46)
			_build_flipbook(assets, 0.82)
			_build_particle_layers(assets, true)
		_:
			return
	set_palette(false)
	reset_preview()


func set_preview_time(value: float, force_seek: bool = true) -> void:
	_preview_time = fposmod(maxf(value, 0.0), _cycle_end)
	var phase: int = _phase_for_time(_preview_time)
	var phase_changed: bool = phase != _active_phase
	_active_phase = phase
	_update_flipbook()
	_update_flow_mask()
	_update_particle_phase(phase_changed or force_seek, force_seek)


func reset_preview() -> void:
	_active_phase = Phase.REST
	for emitter: CPUParticles2D in _particle_emitters:
		emitter.emitting = false
		emitter.visible = false
	set_preview_time(0.0, true)


func set_palette(angry_dominant: bool) -> void:
	_angry_dominant = angry_dominant
	var primary: Color = _angry_color if angry_dominant else _calm_color
	var secondary: Color = _calm_color if angry_dominant else _angry_color
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("primary_color", primary)
		material.set_shader_parameter("secondary_color", secondary)
		material.set_shader_parameter("hot_color", _hot_color)


func debug_state() -> Dictionary:
	var visible_particles: int = 0
	var emitting_particles: int = 0
	for emitter: CPUParticles2D in _particle_emitters:
		if emitter.visible:
			visible_particles += 1
		if emitter.emitting:
			emitting_particles += 1
	return {
		"pipeline_id": _pipeline_id,
		"phase": phase_name(_active_phase),
		"preview_time": _preview_time,
		"node_count": _recursive_node_count(self),
		"material_count": _materials.size(),
		"particle_emitter_count": _particle_emitters.size(),
		"visible_particle_emitters": visible_particles,
		"emitting_particle_emitters": emitting_particles,
		"display_scale": _display_scale,
		"core_radius": _core_radius,
		"decorative_radius": _decorative_radius,
		"palette_signature": "angry-primary" if _angry_dominant else "calm-primary",
		"has_flipbook": _flipbook_sprite != null,
		"has_flow_mask": _flow_sprite != null,
	}


static func phase_name(phase: int) -> String:
	match phase:
		Phase.CHARGE:
			return "CHARGE"
		Phase.CONTACT:
			return "CONTACT"
		Phase.AFTERMATH:
			return "AFTERMATH"
		_:
			return "REST"


func _build_flipbook(assets: Dictionary, opacity: float) -> void:
	var texture: Texture2D = assets.get("flipbook") as Texture2D
	if texture == null:
		push_error("Organic VFX flipbook texture is missing.")
		return
	_flipbook_sprite = Sprite2D.new()
	_flipbook_sprite.name = "PaintedFlipbook"
	_flipbook_sprite.texture = texture
	_flipbook_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_flipbook_sprite.scale = Vector2.ONE * ((_decorative_radius * 2.0) / float(texture.get_width()))
	var material := ShaderMaterial.new()
	material.shader = LUMA_SHADER
	material.set_shader_parameter("atlas_columns", 4.0)
	material.set_shader_parameter("atlas_rows", 4.0)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("intensity", 1.12)
	_flipbook_sprite.material = material
	_materials.append(material)
	add_child(_flipbook_sprite)


func _build_flow_mask(assets: Dictionary, opacity: float) -> void:
	var texture: Texture2D = assets.get("flow_mask") as Texture2D
	if texture == null:
		push_error("Organic VFX flow-mask texture is missing.")
		return
	_flow_sprite = Sprite2D.new()
	_flow_sprite.name = "PaintedFlowMask"
	_flow_sprite.texture = texture
	_flow_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_flow_sprite.scale = Vector2.ONE * ((_decorative_radius * 2.0) / float(texture.get_width()))
	var material := ShaderMaterial.new()
	material.shader = FLOW_SHADER
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("seed_offset", float(_seed % 97) / 97.0)
	material.set_shader_parameter("flow_texture", texture)
	_flow_sprite.material = material
	_materials.append(material)
	add_child(_flow_sprite)


func _build_particle_layers(assets: Dictionary, compact: bool) -> void:
	var cells_variant: Variant = assets.get("particle_cells")
	if not cells_variant is Array:
		push_error("Organic VFX particle cells are missing.")
		return
	var cells: Array = cells_variant as Array
	var specifications: Array[Dictionary]
	if compact:
		specifications = [
			{"name": "HybridChargeFibers", "cell": 2, "phase": Phase.CHARGE},
			{"name": "HybridContactSplash", "cell": 3, "phase": Phase.CONTACT},
			{"name": "HybridAftermathWisp", "cell": 14, "phase": Phase.AFTERMATH},
		]
	else:
		specifications = [
			{"name": "ChargeFibersA", "cell": 0, "phase": Phase.CHARGE},
			{"name": "ChargeFibersB", "cell": 4, "phase": Phase.CHARGE},
			{"name": "ContactSplashA", "cell": 3, "phase": Phase.CONTACT},
			{"name": "ContactSplashB", "cell": 9, "phase": Phase.CONTACT},
			{"name": "AftermathWispA", "cell": 8, "phase": Phase.AFTERMATH},
			{"name": "AftermathWispB", "cell": 12, "phase": Phase.AFTERMATH},
			{"name": "AftermathWispC", "cell": 15, "phase": Phase.AFTERMATH},
		]
	for index: int in range(specifications.size()):
		var specification: Dictionary = specifications[index]
		var cell_index: int = int(specification["cell"])
		if cell_index < 0 or cell_index >= cells.size() or not cells[cell_index] is Texture2D:
			push_error("Organic VFX particle cell %s is invalid." % cell_index)
			continue
		var emitter := _create_particle_emitter(
			String(specification["name"]),
			cells[cell_index] as Texture2D,
			int(specification["phase"]),
			index,
			compact
		)
		_particle_emitters.append(emitter)
		add_child(emitter)


func _create_particle_emitter(
	emitter_name: String,
	texture: Texture2D,
	phase: int,
	index: int,
	compact: bool
) -> CPUParticles2D:
	var emitter := CPUParticles2D.new()
	emitter.name = emitter_name
	emitter.texture = texture
	emitter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	emitter.one_shot = false
	emitter.explosiveness = 1.0 if phase == Phase.CONTACT else 0.56
	emitter.randomness = 0.08
	emitter.lifetime_randomness = 0.06
	emitter.direction = Vector2.RIGHT.rotated(float(index) * 0.73)
	emitter.spread = 180.0
	emitter.gravity = Vector2.ZERO
	emitter.use_fixed_seed = true
	emitter.seed = _seed + index * 101
	emitter.visible = false
	emitter.emitting = false
	emitter.set_meta("phase", int(phase))

	match phase:
		Phase.CHARGE:
			emitter.amount = 9 if compact else 13
			emitter.lifetime = _charge_end
			emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			emitter.emission_sphere_radius = _decorative_radius * 0.78
			emitter.initial_velocity_min = 2.0
			emitter.initial_velocity_max = 8.0
			emitter.radial_accel_min = -310.0
			emitter.radial_accel_max = -230.0
			emitter.scale_amount_min = 0.07
			emitter.scale_amount_max = 0.13
			emitter.preprocess = 0.20
		Phase.CONTACT:
			emitter.amount = 8 if compact else 12
			emitter.lifetime = 0.26
			emitter.initial_velocity_min = 74.0
			emitter.initial_velocity_max = 128.0
			emitter.angular_velocity_min = -130.0
			emitter.angular_velocity_max = 130.0
			emitter.scale_amount_min = 0.08
			emitter.scale_amount_max = 0.16
			emitter.preprocess = 0.04
		Phase.AFTERMATH:
			emitter.amount = 7 if compact else 10
			emitter.lifetime = 0.62
			emitter.initial_velocity_min = 22.0
			emitter.initial_velocity_max = 54.0
			emitter.gravity = Vector2(0.0, -18.0)
			emitter.angular_velocity_min = -42.0
			emitter.angular_velocity_max = 42.0
			emitter.scale_amount_min = 0.08
			emitter.scale_amount_max = 0.15
			emitter.preprocess = 0.16
		_:
			pass
	emitter.set_meta("base_preprocess", emitter.preprocess)

	var material := ShaderMaterial.new()
	material.shader = LUMA_SHADER
	material.set_shader_parameter("atlas_columns", 1.0)
	material.set_shader_parameter("atlas_rows", 1.0)
	material.set_shader_parameter("opacity", 0.72 if compact else 0.92)
	material.set_shader_parameter("intensity", 1.18)
	emitter.material = material
	_materials.append(material)
	return emitter


func _update_flipbook() -> void:
	if _flipbook_sprite == null:
		return
	var material := _flipbook_sprite.material as ShaderMaterial
	if material == null:
		return
	var frame: int = 0
	var opacity: float = 1.0
	match _active_phase:
		Phase.CHARGE:
			frame = mini(int(floor(_phase_progress() * 6.0)), 5)
		Phase.CONTACT:
			frame = 6 + mini(int(floor(_phase_progress() * 2.0)), 1)
		Phase.AFTERMATH:
			frame = 8 + mini(int(floor(_phase_progress() * 8.0)), 7)
		_:
			frame = 15
			opacity = 0.0
	material.set_shader_parameter("frame_index", float(frame))
	var base_opacity: float = 0.82 if _pipeline_id == "hybrid" else 1.0
	material.set_shader_parameter("opacity", opacity * base_opacity)


func _update_flow_mask() -> void:
	if _flow_sprite == null:
		return
	var material := _flow_sprite.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("animation_time", _preview_time)
	material.set_shader_parameter("phase_index", float(_active_phase))
	material.set_shader_parameter("phase_progress", _phase_progress())
	var base_opacity: float = 0.46 if _pipeline_id == "hybrid" else 1.0
	material.set_shader_parameter("opacity", 0.0 if _active_phase == Phase.REST else base_opacity)
	var pulse_scale: float = 1.0
	match _active_phase:
		Phase.CHARGE:
			pulse_scale = lerpf(1.08, 0.72, _phase_progress())
		Phase.CONTACT:
			pulse_scale = lerpf(0.86, 1.18, _phase_progress())
		Phase.AFTERMATH:
			pulse_scale = lerpf(1.05, 1.32, _phase_progress())
		_:
			pulse_scale = 1.0
	var texture: Texture2D = _flow_sprite.texture
	if texture != null:
		var base_scale: float = (_decorative_radius * 2.0) / float(texture.get_width())
		_flow_sprite.scale = Vector2.ONE * base_scale * pulse_scale


func _update_particle_phase(restart_requested: bool, force_seek: bool) -> void:
	if _particle_emitters.is_empty():
		return
	for emitter: CPUParticles2D in _particle_emitters:
		var emitter_phase: int = int(emitter.get_meta("phase", int(Phase.REST)))
		var should_show: bool = emitter_phase == int(_active_phase)
		emitter.visible = should_show
		if not should_show:
			emitter.emitting = false
			continue
		if restart_requested:
			var base_preprocess: float = float(emitter.get_meta("base_preprocess", 0.0))
			emitter.preprocess = base_preprocess + (_phase_elapsed() if force_seek else 0.0)
			emitter.restart()
			emitter.emitting = true


func _phase_for_time(value: float) -> int:
	if value < _charge_end:
		return Phase.CHARGE
	if value < _contact_end:
		return Phase.CONTACT
	if value < _aftermath_end:
		return Phase.AFTERMATH
	return Phase.REST


func _phase_progress() -> float:
	match _active_phase:
		Phase.CHARGE:
			return clampf(_preview_time / _charge_end, 0.0, 1.0)
		Phase.CONTACT:
			return clampf((_preview_time - _charge_end) / (_contact_end - _charge_end), 0.0, 1.0)
		Phase.AFTERMATH:
			return clampf((_preview_time - _contact_end) / (_aftermath_end - _contact_end), 0.0, 1.0)
		_:
			return 1.0


func _phase_elapsed() -> float:
	match _active_phase:
		Phase.CHARGE:
			return _preview_time
		Phase.CONTACT:
			return _preview_time - _charge_end
		Phase.AFTERMATH:
			return _preview_time - _contact_end
		_:
			return 0.0


func _recursive_node_count(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _recursive_node_count(child)
	return count
