class_name TestLabAdvancedCell
extends Node2D

# 骨骼蒙皮细胞：用 Skeleton2D + 一圈径向 Bone2D 作为可动画的骨骼控制结构，
# AnimationPlayer 关键帧驱动各骨的径向位置；膜 Polygon2D 每帧由骨骼半径平滑重建（蒙皮）。
# 4 套动画 idle / pseudopod / divide / engulf 由按键触发，动作结束自动回 idle；
# 核脉动 + 细胞器漂移在 _process 常开（不占骨骼动画轨）。

const BONE_COUNT: int = 14
const MEMBRANE_POINTS: int = 56
const BASE_RADIUS: float = 150.0

const MEMBRANE_FILL := Color(0.36, 0.78, 0.70, 0.60)
const MEMBRANE_EDGE := Color(0.13, 0.46, 0.46, 0.92)
const MEMBRANE_RIM := Color(0.70, 0.95, 0.90, 0.45)
const NUCLEUS_FILL := Color(0.18, 0.44, 0.50, 0.88)
const NUCLEUS_CORE := Color(0.80, 0.97, 0.93, 0.92)
const ORGANELLE_COLOR := Color(0.26, 0.60, 0.58, 0.62)
const FOOD_COLOR := Color(0.86, 0.52, 0.30, 0.95)

signal state_changed(state_name: String)

var _skeleton: Skeleton2D
var _bones: Array[Bone2D] = []
var _bone_dirs: Array[Vector2] = []
var _anim_player: AnimationPlayer
var _membrane: Polygon2D
var _organelles: Array[Dictionary] = []
var _time: float = 0.0
var _current_state: String = "idle"

var _has_obstacle: bool = false
var _obstacle_center: Vector2 = Vector2.ZERO
var _obstacle_radius: float = 0.0
var _contact_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_build_rig()
	_build_membrane()
	_build_organelles()
	_build_animations()
	play_idle()


func _process(delta: float) -> void:
	_time += delta
	_update_membrane()
	queue_redraw()


func play_idle() -> void:
	_set_state("idle")
	_anim_player.play("idle")


func trigger_pseudopod() -> void:
	_play_action("pseudopod")


func trigger_divide() -> void:
	_play_action("divide")


func trigger_engulf() -> void:
	_play_action("engulf")


func current_state() -> String:
	return _current_state


# 设置一个圆形障碍物（全局坐标），膜会在接触处被夹到障碍物表面（软体贴壁）
func set_obstacle_circle(center_global: Vector2, radius: float) -> void:
	_has_obstacle = true
	_obstacle_center = center_global
	_obstacle_radius = radius


func _play_action(action_name: String) -> void:
	_set_state(action_name)
	_anim_player.play(action_name)


func _set_state(state_name: String) -> void:
	_current_state = state_name
	state_changed.emit(state_name)


func _on_animation_finished(anim_name: StringName) -> void:
	if String(anim_name) != "idle":
		play_idle()


# ---- 构建 ----

func _build_rig() -> void:
	_skeleton = Skeleton2D.new()
	_skeleton.name = "Skeleton"
	add_child(_skeleton)

	for index in range(BONE_COUNT):
		var angle := float(index) / float(BONE_COUNT) * TAU
		var direction := Vector2.from_angle(angle)
		_bone_dirs.append(direction)
		var bone := Bone2D.new()
		bone.name = "Bone%d" % index
		bone.position = direction * BASE_RADIUS
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(18.0)
		bone.set_bone_angle(angle)
		bone.rest = Transform2D(angle, direction * BASE_RADIUS)
		_skeleton.add_child(bone)
		_bones.append(bone)


func _build_membrane() -> void:
	_membrane = Polygon2D.new()
	_membrane.name = "Membrane"
	_membrane.color = MEMBRANE_FILL
	_membrane.show_behind_parent = true
	add_child(_membrane)


func _build_organelles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90125
	for index in range(6):
		_organelles.append({
			"angle": rng.randf_range(0.0, TAU),
			"dist": rng.randf_range(0.18, 0.62),
			"radius": rng.randf_range(7.0, 15.0),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.3, 0.7),
			"swing": rng.randf_range(0.1, 0.3),
		})


func _build_animations() -> void:
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "AnimationPlayer"
	add_child(_anim_player)

	var library := AnimationLibrary.new()
	library.add_animation("idle", _make_anim("idle", 3.0, true, "idle"))
	library.add_animation("pseudopod", _make_anim("pseudopod", 1.8, false, "pseudopod"))
	library.add_animation("divide", _make_anim("divide", 3.2, false, "divide"))
	library.add_animation("engulf", _make_anim("engulf", 2.4, false, "engulf"))
	_anim_player.add_animation_library("", library)
	_anim_player.animation_finished.connect(_on_animation_finished)


func _make_anim(anim_name: String, duration: float, looping: bool, mode: String) -> Animation:
	var animation := Animation.new()
	animation.length = duration
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var key_count := maxi(2, int(round(duration / 0.12)))
	for index in range(BONE_COUNT):
		var track := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, NodePath("Skeleton/Bone%d:position" % index))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
		for key in range(key_count + 1):
			var t := duration * float(key) / float(key_count)
			var radius := _radius_for(mode, index, t / duration)
			animation.track_insert_key(track, t, _bone_dirs[index] * radius)
	return animation


func _radius_for(mode: String, index: int, phase: float) -> float:
	var angle := float(index) / float(BONE_COUNT) * TAU
	match mode:
		"idle":
			return BASE_RADIUS + sin(phase * TAU + angle) * 8.0
		"pseudopod":
			var hump := sin(phase * PI)
			var falloff := _ang_falloff(angle, 0.0, 0.40)
			return BASE_RADIUS + falloff * hump * 128.0
		"divide":
			var progress := sin(phase * PI)
			return BASE_RADIUS + (-cos(2.0 * angle)) * progress * 64.0
		"engulf":
			var reach := sin(phase * PI)
			# 两片相邻膜外伸成"口"包拢右侧食物
			var lobe := _ang_falloff(angle, -0.42, 0.36) + _ang_falloff(angle, 0.42, 0.36)
			return BASE_RADIUS + lobe * reach * 92.0
		_:
			return BASE_RADIUS


func _ang_falloff(angle: float, center: float, sigma: float) -> float:
	var diff := _ang_diff(angle, center)
	return exp(-(diff * diff) / (2.0 * sigma * sigma))


func _ang_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0.0:
		d += TAU
	return d - PI


# ---- 每帧重建膜 ----

func _update_membrane() -> void:
	var radii := PackedFloat32Array()
	for index in range(BONE_COUNT):
		radii.append(_bones[index].position.length())

	var sigma := (TAU / float(BONE_COUNT)) * 0.9
	_contact_points.clear()
	var polygon := PackedVector2Array()
	for point in range(MEMBRANE_POINTS):
		var angle := float(point) / float(MEMBRANE_POINTS) * TAU
		var numerator := 0.0
		var denominator := 0.0
		for index in range(BONE_COUNT):
			var weight := _ang_falloff(angle, float(index) / float(BONE_COUNT) * TAU, sigma)
			numerator += weight * radii[index]
			denominator += weight
		var radius := numerator / denominator
		radius += sin(angle * 7.0 + _time * 1.6) * 2.2 # 表面微波纹（常开生命感）
		radius = _clamp_radius_to_obstacle(angle, radius)
		polygon.append(Vector2.from_angle(angle) * radius)
	_membrane.polygon = polygon


# 射线-圆近交点：把该方向的膜半径截断在障碍物近表面，使膜停在障碍物这一侧（贴壁凹陷），
# 而不是越过障碍物把它包进膜内。记录接触点用于压力高亮。
func _clamp_radius_to_obstacle(angle: float, radius: float) -> float:
	if not _has_obstacle:
		return radius
	var direction := Vector2.from_angle(angle)
	var obstacle_local := to_local(_obstacle_center) # 障碍物中心在细胞局部坐标
	var projection := direction.dot(obstacle_local)
	var discriminant := projection * projection - obstacle_local.length_squared() + _obstacle_radius * _obstacle_radius
	if discriminant <= 0.0:
		return radius # 射线没打中障碍物
	var near := projection - sqrt(discriminant)
	if near <= 0.0:
		return radius # 障碍物不在该方向前方（或已包住中心）
	if near < radius:
		_contact_points.append(direction * near)
		return near
	return radius


func _avg_radius() -> float:
	if _membrane.polygon.is_empty():
		return BASE_RADIUS
	var total := 0.0
	for point in _membrane.polygon:
		total += point.length()
	return total / float(_membrane.polygon.size())


func _anim_progress() -> float:
	var length := _anim_player.current_animation_length
	if length <= 0.0:
		return 0.0
	return clampf(_anim_player.current_animation_position / length, 0.0, 1.0)


# ---- 绘制（膜 fill 在 show_behind_parent 的 Polygon2D，这里画描边 + 细胞器 + 核 + 食物，在膜之上）----

func _draw() -> void:
	_draw_membrane_edge()
	_draw_contact()
	_draw_organelles()
	_draw_nuclei()
	_draw_food()


func _draw_contact() -> void:
	if _contact_points.size() < 2:
		return
	# 接触障碍物处的膜被压平，叠一条亮的"压力"线表现挤压张力
	var pulse := 0.6 + sin(_time * 6.0) * 0.2
	draw_polyline(_contact_points, Color(0.92, 1.0, 0.96, 0.55 * pulse), 5.0, true)
	draw_polyline(_contact_points, Color(0.60, 0.96, 0.88, 0.7), 2.0, true)


func _draw_membrane_edge() -> void:
	var polygon := _membrane.polygon
	if polygon.size() < 3:
		return
	var closed := PackedVector2Array(polygon)
	closed.append(polygon[0])
	draw_polyline(closed, MEMBRANE_RIM, 6.0, true)
	draw_polyline(closed, MEMBRANE_EDGE, 2.5, true)


func _draw_organelles() -> void:
	var avg := _avg_radius()
	for organelle in _organelles:
		var swing: float = organelle["swing"]
		var drift_angle: float = organelle["angle"] + sin(_time * organelle["speed"] + organelle["phase"]) * swing
		var drift_dist: float = organelle["dist"] * avg * (0.92 + sin(_time * 0.8 + organelle["phase"]) * 0.08)
		var position := Vector2.from_angle(drift_angle) * drift_dist
		draw_circle(position, organelle["radius"], ORGANELLE_COLOR)
		draw_circle(position, organelle["radius"] * 0.45, Color(NUCLEUS_CORE, 0.35))


func _draw_nuclei() -> void:
	var avg := _avg_radius()
	var pulse := 1.0 + sin(_time * 2.2) * 0.08
	var nucleus_radius := avg * 0.20 * pulse

	if _current_state == "divide":
		var progress := _anim_progress()
		var separation := progress * avg * 0.46
		var shrink := 1.0 - progress * 0.22
		_draw_single_nucleus(Vector2(0.0, -separation), nucleus_radius * shrink)
		_draw_single_nucleus(Vector2(0.0, separation), nucleus_radius * shrink)
	else:
		var drift := Vector2(sin(_time * 0.6) * 6.0, cos(_time * 0.5) * 5.0)
		_draw_single_nucleus(drift, nucleus_radius)


func _draw_single_nucleus(position: Vector2, radius: float) -> void:
	draw_circle(position, radius, NUCLEUS_FILL)
	draw_circle(position, radius * 0.5, NUCLEUS_CORE)


func _draw_food() -> void:
	if _current_state != "engulf":
		return
	var avg := _avg_radius()
	var progress := _anim_progress()
	var start := Vector2.RIGHT * (avg + 70.0)
	var travel := smoothstep(0.0, 1.0, progress)
	var position := start.lerp(Vector2.ZERO, travel)
	var fade := 1.0 - smoothstep(0.7, 1.0, progress)
	var radius := lerpf(16.0, 6.0, progress)
	draw_circle(position, radius, Color(FOOD_COLOR, FOOD_COLOR.a * fade))
	draw_circle(position, radius * 0.5, Color(1.0, 0.85, 0.7, 0.8 * fade))
