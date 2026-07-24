# Doc: docs/代码/visual_effects.md
@tool
extends SubViewportContainer
## Isolated editor preview surface for formal runtime VFX PackedScenes.

const VIEWPORT_SIZE := Vector2i(720, 430)
const BACKGROUNDS := {
	"dark": Color("121722"),
	"light": Color("d7dde8"),
	"mid": Color("59616d"),
	"checker": Color("303541"),
}
const PREVIEW_TARGETS := {
	"dummy": {"kind": "dummy", "path": ""},
	"player": {
		"kind": "actor",
		"path": "res://scenes/gameplay/actors/characters/character_default.tscn",
	},
	"enemy_chaser": {
		"kind": "actor",
		"path": "res://scenes/gameplay/actors/enemies/enemy_chaser.tscn",
	},
	"enemy_swarm": {
		"kind": "actor",
		"path": "res://scenes/gameplay/actors/enemies/enemy_swarm.tscn",
	},
	"enemy_stalker": {
		"kind": "actor",
		"path": "res://scenes/gameplay/actors/enemies/enemy_stalker.tscn",
	},
	"enemy_bulwark": {
		"kind": "actor",
		"path": "res://scenes/gameplay/actors/enemies/enemy_bulwark.tscn",
	},
	"enemy_spitter": {
		"kind": "actor",
		"path": "res://scenes/gameplay/actors/enemies/enemy_spitter.tscn",
	},
	"ui_container": {"kind": "ui", "path": ""},
}

var _viewport: SubViewport
var _background: ColorRect
var _world_root: Node2D
var _ui_root: Control
var _instances: Array[Node] = []
var _preview_tweens: Array[Tween] = []
var _target_instance: Node
var _entry: Dictionary = {}
var _paused := false
var _speed := 1.0
var _scale := 1.0
var _instance_count := 1
var _quality := "high"
var _reduced_motion := false
var _target_id := "dummy"


func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(480.0, 300.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)

	_background = ColorRect.new()
	_background.name = "Background"
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.color = Color(BACKGROUNDS["dark"])
	_viewport.add_child(_background)

	_world_root = Node2D.new()
	_world_root.name = "WorldPreview"
	_world_root.position = Vector2(VIEWPORT_SIZE) * 0.5
	_viewport.add_child(_world_root)

	_ui_root = Control.new()
	_ui_root.name = "UiPreview"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_ui_root)
	_rebuild_target()


func clear_preview() -> void:
	for tween: Tween in _preview_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_preview_tweens.clear()
	for instance: Node in _instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_instances.clear()
	_entry.clear()


func preview(entry: Dictionary) -> Dictionary:
	clear_preview()
	_entry = entry.duplicate(true)
	var resource_path: String = String(entry.get("resource_path", ""))
	if resource_path.is_empty() or not ResourceLoader.exists(resource_path):
		return _error("无法预览资源：%s" % resource_path)
	var resource: Resource = load(resource_path)
	if String(entry.get("kind", "")) == "target_animation":
		return _preview_target_animation(resource, entry)
	if not resource is PackedScene:
		return _error("预览资源不是 PackedScene：%s" % resource_path)
	var packed_scene: PackedScene = resource as PackedScene
	for index: int in range(_instance_count):
		var instance: Node = packed_scene.instantiate()
		var parent: Node = _ui_root if _uses_ui_space(entry, instance) else _world_root
		parent.add_child(instance)
		_instances.append(instance)
		_place_instance(instance, index, _instance_count)
		_apply_policy(instance)
		_start_instance(instance)
	_apply_paused_state()
	return {"ok": true, "errors": PackedStringArray()}


func replay() -> Dictionary:
	if _entry.is_empty():
		return _error("请先选择一个效果。")
	return preview(_entry)


func set_paused(paused: bool) -> void:
	_paused = paused
	_apply_paused_state()


func set_speed(speed: float) -> void:
	_speed = clampf(speed, 0.05, 4.0)
	for tween: Tween in _preview_tweens:
		if tween != null and tween.is_valid():
			tween.set_speed_scale(_speed)
	for instance: Node in _instances:
		_apply_speed_recursive(instance)


func set_preview_scale(preview_scale: float) -> void:
	_scale = clampf(preview_scale, 0.1, 2.0)
	for instance: Node in _instances:
		if instance is CanvasItem:
			(instance as CanvasItem).scale = Vector2.ONE * _scale


func set_instance_count(instance_count: int) -> Dictionary:
	_instance_count = clampi(instance_count, 1, 64)
	if _entry.is_empty():
		return {"ok": true, "errors": PackedStringArray()}
	return preview(_entry)


func set_quality(quality: String) -> Dictionary:
	_quality = quality
	return {"ok": true, "errors": PackedStringArray()}


func set_reduced_motion(enabled: bool) -> Dictionary:
	_reduced_motion = enabled
	return {"ok": true, "errors": PackedStringArray()}


func set_background(background_id: String) -> void:
	if not BACKGROUNDS.has(background_id):
		return
	_background.color = Color(BACKGROUNDS[background_id])


func set_preview_target(target_id: String) -> Dictionary:
	if not PREVIEW_TARGETS.has(target_id):
		return _error("未知预览目标：%s" % target_id)
	_target_id = target_id
	_rebuild_target()
	if _entry.is_empty():
		return {"ok": true, "errors": PackedStringArray()}
	return preview(_entry)


func seek_ratio(ratio: float) -> void:
	var clamped_ratio := clampf(ratio, 0.0, 1.0)
	var duration: float = maxf(float(_entry.get("duration", 1.0)), 0.001)
	for instance: Node in _instances:
		if instance.has_method("seek_preview_ratio"):
			instance.call("seek_preview_ratio", clamped_ratio)
			continue
		for player: AnimationPlayer in _animation_players(instance):
			player.seek(duration * clamped_ratio, true, true)


func seek_phase(phase: String) -> void:
	for instance: Node in _instances:
		if instance.has_method("seek_preview_phase"):
			instance.call("seek_preview_phase", phase)
	var phase_ratio := 0.5
	match phase:
		"charge":
			phase_ratio = 0.15
		"contact":
			phase_ratio = 0.5
		"aftermath":
			phase_ratio = 0.85
		_:
			phase_ratio = 0.5
	seek_ratio(phase_ratio)


func _uses_ui_space(entry: Dictionary, instance: Node) -> bool:
	var space: String = String(entry.get("space", ""))
	return space == "ui" or space == "screen" or instance is Control


func _preview_target_animation(resource: Resource, entry: Dictionary) -> Dictionary:
	if resource == null:
		return _error("目标动画资源加载失败。")
	if not is_instance_valid(_target_instance):
		_rebuild_target()
	var target_path: NodePath = resource.get("target_path") as NodePath
	var target: CanvasItem = _target_instance.get_node_or_null(target_path) as CanvasItem
	if target == null:
		target = _find_canvas_item(_target_instance)
	if target == null:
		return _error("预览目标没有兼容的 CanvasItem。")
	var duration: float = maxf(float(resource.get("duration")), 0.001)
	var tint_value: Variant = resource.get("tint")
	var tint: Color = tint_value as Color if tint_value is Color else Color.WHITE
	var start_scale_value: Variant = resource.get("start_scale")
	var end_scale_value: Variant = resource.get("end_scale")
	var start_scale: Vector2 = (
		start_scale_value as Vector2 if start_scale_value is Vector2 else Vector2.ONE
	)
	var end_scale: Vector2 = (
		end_scale_value as Vector2 if end_scale_value is Vector2 else Vector2.ONE
	)
	var end_alpha: float = clampf(float(resource.get("end_alpha")), 0.0, 1.0)
	target.modulate = tint
	target.scale = start_scale * _scale
	var tween: Tween = target.create_tween()
	tween.set_parallel(true)
	tween.set_speed_scale(_speed)
	tween.tween_property(target, "modulate", Color(1.0, 1.0, 1.0, end_alpha), duration)
	tween.tween_property(target, "scale", end_scale * _scale, duration)
	if _paused:
		tween.pause()
	_preview_tweens.append(tween)
	return {"ok": true, "errors": PackedStringArray(), "entry": entry}


func _rebuild_target() -> void:
	if is_instance_valid(_target_instance):
		_target_instance.queue_free()
	_target_instance = null
	var definition: Dictionary = PREVIEW_TARGETS.get(_target_id, {}) as Dictionary
	var kind: String = String(definition.get("kind", "dummy"))
	match kind:
		"actor":
			_target_instance = _instantiate_actor_target(String(definition.get("path", "")))
			if _target_instance != null:
				_world_root.add_child(_target_instance)
		"ui":
			_target_instance = _make_ui_target()
			_ui_root.add_child(_target_instance)
		_:
			_target_instance = _make_dummy_target()
			_world_root.add_child(_target_instance)


func _instantiate_actor_target(resource_path: String) -> Node:
	if not ResourceLoader.exists(resource_path, "PackedScene"):
		return _make_dummy_target()
	var resource: Resource = load(resource_path)
	if not resource is PackedScene:
		return _make_dummy_target()
	return (resource as PackedScene).instantiate()


func _make_dummy_target() -> Node2D:
	var root := Node2D.new()
	root.name = "Dummy"
	var visual := Node2D.new()
	visual.name = "Visual"
	root.add_child(visual)
	var body := Polygon2D.new()
	body.name = "Body"
	body.polygon = PackedVector2Array(
		[
			Vector2(0.0, -30.0),
			Vector2(25.0, -10.0),
			Vector2(20.0, 24.0),
			Vector2(-20.0, 24.0),
			Vector2(-25.0, -10.0),
		]
	)
	body.color = Color(0.22, 0.72, 0.9, 0.9)
	visual.add_child(body)
	var eye := Polygon2D.new()
	eye.name = "Eye"
	eye.polygon = PackedVector2Array(
		[
			Vector2(-8.0, -5.0),
			Vector2(8.0, -5.0),
			Vector2(8.0, 5.0),
			Vector2(-8.0, 5.0),
		]
	)
	eye.color = Color.WHITE
	visual.add_child(eye)
	return root


func _make_ui_target() -> Control:
	var panel := Panel.new()
	panel.name = "UiContainer"
	panel.position = Vector2(170.0, 90.0)
	panel.size = Vector2(380.0, 250.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _find_canvas_item(root: Node) -> CanvasItem:
	if root is CanvasItem and root != _target_instance:
		return root as CanvasItem
	for child: Node in root.get_children():
		var result: CanvasItem = _find_canvas_item(child)
		if result != null:
			return result
	return null


func _place_instance(instance: Node, index: int, count: int) -> void:
	var grid_width: int = ceili(sqrt(float(count)))
	var grid_height: int = ceili(float(count) / float(grid_width))
	var column: int = index % grid_width
	var row: int = index / grid_width
	var spacing := Vector2(88.0, 72.0)
	var offset := Vector2(
		(float(column) - float(grid_width - 1) * 0.5) * spacing.x,
		(float(row) - float(grid_height - 1) * 0.5) * spacing.y
	)
	if instance is Control:
		var control := instance as Control
		control.position = Vector2(VIEWPORT_SIZE) * 0.5 + offset
		control.pivot_offset = control.size * 0.5
		control.scale = Vector2.ONE * _scale
	elif instance is Node2D:
		var node_2d := instance as Node2D
		node_2d.position = offset
		node_2d.scale = Vector2.ONE * _scale


func _apply_policy(instance: Node) -> void:
	instance.set_meta("vfx_preview", true)
	instance.set_meta("vfx_quality", _quality)
	instance.set_meta("vfx_reduced_motion", _reduced_motion)
	if instance.has_method("configure_preview"):
		instance.call(
			"configure_preview",
			{
				"quality": _quality,
				"reduced_motion": _reduced_motion,
				"editor_preview": true,
			}
		)
	_apply_speed_recursive(instance)


func _start_instance(instance: Node) -> void:
	if instance.has_method("play_preview"):
		instance.call("play_preview")
	elif instance.has_method("play"):
		instance.call("play")
	else:
		for player: AnimationPlayer in _animation_players(instance):
			var animation_name: StringName = _default_animation(player)
			if not animation_name.is_empty():
				player.play(animation_name)


func _apply_paused_state() -> void:
	for tween: Tween in _preview_tweens:
		if tween == null or not tween.is_valid():
			continue
		if _paused:
			tween.pause()
		else:
			tween.play()
	for instance: Node in _instances:
		instance.process_mode = (
			Node.PROCESS_MODE_DISABLED if _paused else Node.PROCESS_MODE_INHERIT
		)
		for player: AnimationPlayer in _animation_players(instance):
			if _paused:
				player.pause()
			elif player.is_playing():
				player.play()


func _apply_speed_recursive(node: Node) -> void:
	if node is AnimationPlayer:
		(node as AnimationPlayer).speed_scale = _speed
	elif node is GPUParticles2D:
		(node as GPUParticles2D).speed_scale = _speed
	elif node is CPUParticles2D:
		(node as CPUParticles2D).speed_scale = _speed
	for child: Node in node.get_children():
		_apply_speed_recursive(child)


func _animation_players(root: Node) -> Array[AnimationPlayer]:
	var players: Array[AnimationPlayer] = []
	_collect_animation_players(root, players)
	return players


func _collect_animation_players(root: Node, players: Array[AnimationPlayer]) -> void:
	if root is AnimationPlayer:
		players.append(root as AnimationPlayer)
	for child: Node in root.get_children():
		_collect_animation_players(child, players)


func _default_animation(player: AnimationPlayer) -> StringName:
	if player.has_animation(&"play"):
		return &"play"
	for animation_name: StringName in player.get_animation_list():
		if animation_name != &"RESET":
			return animation_name
	return &""


func _error(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
