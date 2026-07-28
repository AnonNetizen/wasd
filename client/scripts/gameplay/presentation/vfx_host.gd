# Doc: docs/代码/visual_effects.md
class_name VfxHost
extends Node
## Run-scoped owner for spawned world, ground, attached, and screen-space VFX.


signal effect_started(effect_id: String, instance: Node)
signal effect_finished(effect_id: String)

const VFX_KINDS := preload("res://scripts/contracts/vfx_kinds.gd")
const VFX_SPACES := preload("res://scripts/contracts/vfx_spaces.gd")
const VFX_ANCHORS := preload("res://scripts/contracts/vfx_anchors.gd")
const ANCHOR_NODE_NAMES: Dictionary = {
	VFX_ANCHORS.CENTER: "Center",
	VFX_ANCHORS.GROUND: "Ground",
	VFX_ANCHORS.OVERHEAD: "Overhead",
	VFX_ANCHORS.STATUS: "Status",
	VFX_ANCHORS.FORWARD: "Forward",
	VFX_ANCHORS.MUZZLE: "Forward/Muzzle",
}

var _ground_layer: Node2D = null
var _world_layer: Node2D = null
var _screen_layer: CanvasLayer = null
var _screen_root: Control = null
var _active: Dictionary = {}


func _ready() -> void:
	_resolve_layers()


func play(effect_id: String, request: VfxPlayRequest = null) -> VfxHandle:
	var effect_data: Dictionary = VisualEffects.resolved_effect(effect_id)
	if effect_data.is_empty():
		push_error("[VfxHost] unknown or unresolved effect id: %s" % effect_id)
		return null
	if not VisualEffects.allows_effect(effect_data):
		return null

	var resolved_request: VfxPlayRequest = (
		request.clone() if request != null else VfxPlayRequest.new()
	)
	var kind: String = String(effect_data.get("kind", ""))
	if kind == VFX_KINDS.TARGET_ANIMATION:
		return _play_target_animation(effect_data, resolved_request)

	var resource_path: String = String(effect_data.get("resource_path", ""))
	var raw_resource: Resource = load(resource_path)
	if not raw_resource is PackedScene:
		push_error("[VfxHost] effect resource is not a PackedScene: %s" % resource_path)
		return null
	var scene := raw_resource as PackedScene
	var pool_id: String = String(effect_data.get("pool_id", ""))
	var pooled: bool = not pool_id.is_empty()
	var instance: Node = null
	if pooled:
		if not _ensure_pool(pool_id, scene, effect_data):
			return null
		instance = PoolManager.acquire(pool_id)
	else:
		instance = scene.instantiate()
	if instance == null:
		return null

	var space: String = String(effect_data.get("space", VFX_SPACES.WORLD))
	var target_parent: Node = _resolve_parent(space, resolved_request)
	if target_parent == null:
		_release_or_free(instance, pooled)
		push_error("[VfxHost] could not resolve parent for effect: %s" % effect_id)
		return null
	_reparent(instance, target_parent)
	_apply_transform(instance, space, resolved_request)

	var handle := VfxHandle.new()
	handle.configure(self, instance, String(effect_data.get("id", effect_id)))
	_active[instance.get_instance_id()] = {
		"effect_id": String(effect_data.get("id", effect_id)),
		"handle": handle,
		"instance": instance,
		"owner_id": (
			resolved_request.owner.get_instance_id()
			if resolved_request.owner != null
			else 0
		),
		"pooled": pooled,
	}

	if instance is VfxInstance:
		var typed_instance := instance as VfxInstance
		typed_instance.configure(resolved_request)
		typed_instance.finished.connect(
			_on_instance_finished.bind(instance.get_instance_id()),
			CONNECT_ONE_SHOT
		)
		typed_instance.play()
	elif instance is ScreenVfxInstance:
		var screen_instance := instance as ScreenVfxInstance
		screen_instance.configure(resolved_request)
		screen_instance.finished.connect(
			_on_instance_finished.bind(instance.get_instance_id()),
			CONNECT_ONE_SHOT
		)
		screen_instance.play()
	elif instance.has_method("configure_vfx"):
		instance.call("configure_vfx", resolved_request)
		_connect_generic_finished(instance)
		if instance.has_method("play"):
			instance.call("play")
	elif instance.has_method("configure"):
		var configure_args: Array = resolved_request.payload.get("configure_args", []) as Array
		if not configure_args.is_empty():
			instance.callv("configure", configure_args)
		_connect_generic_finished(instance)
		_play_animation_fallback(instance)
	else:
		_connect_generic_finished(instance)
		_play_animation_fallback(instance)

	effect_started.emit(effect_id, instance)
	return handle


func cancel_owner(owner: Node) -> void:
	if owner == null:
		return
	var owner_id: int = owner.get_instance_id()
	for raw_instance_id: Variant in _active.keys():
		var record: Dictionary = _active.get(raw_instance_id, {}) as Dictionary
		if int(record.get("owner_id", 0)) != owner_id:
			continue
		_cancel_instance(int(raw_instance_id), true)


func cancel_all() -> void:
	for raw_instance_id: Variant in _active.keys():
		_cancel_instance(int(raw_instance_id), true)


func cancel_handle(handle: VfxHandle, immediate: bool = false) -> void:
	if handle == null:
		return
	var instance: Node = handle.instance()
	if instance == null:
		handle.mark_cancelled()
		return
	_cancel_instance(instance.get_instance_id(), immediate)


func register_declared_pools() -> bool:
	for request: Dictionary in declared_pool_requests():
		var effect_id: String = String(request.get("effect_id", ""))
		var effect_data: Dictionary = VisualEffects.effect(effect_id)
		var raw_resource: Resource = load(String(effect_data.get("resource_path", "")))
		if not raw_resource is PackedScene:
			push_error("[VfxHost] pooled effect is not a PackedScene: %s" % effect_id)
			return false
		if not _ensure_pool(
			String(request.get("pool_id", "")),
			raw_resource as PackedScene,
			effect_data
		):
			return false
	return true


func declared_pool_requests() -> Array[Dictionary]:
	var requests_by_pool: Dictionary = {}
	for effect_id: String in VisualEffects.effect_ids():
		var effect_data: Dictionary = VisualEffects.effect(effect_id)
		var pool_id: String = String(effect_data.get("pool_id", ""))
		if pool_id.is_empty():
			continue
		var prewarm: int = maxi(int(effect_data.get("prewarm", 0)), 0)
		var existing: Dictionary = requests_by_pool.get(pool_id, {}) as Dictionary
		if existing.is_empty() or prewarm > int(existing.get("count", 0)):
			requests_by_pool[pool_id] = {
				"effect_id": effect_id,
				"pool_id": pool_id,
				"count": prewarm,
			}
	var result: Array[Dictionary] = []
	for raw_pool_id: Variant in requests_by_pool.keys():
		result.append(requests_by_pool[raw_pool_id] as Dictionary)
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return String(a.get("pool_id", "")) < String(b.get("pool_id", ""))
	)
	return result


func _resolve_layers() -> void:
	_ground_layer = get_node_or_null("GroundVfxLayer") as Node2D
	_world_layer = get_node_or_null("WorldVfxLayer") as Node2D
	_screen_layer = get_node_or_null("ScreenFeedbackLayer") as CanvasLayer
	if _screen_layer != null:
		_screen_root = _screen_layer.get_node_or_null("Root") as Control
	if (
		_ground_layer == null
		or _world_layer == null
		or _screen_layer == null
		or _screen_root == null
	):
		push_error("[VfxHost] scene-authored VFX layers are incomplete")


func _resolve_parent(space: String, request: VfxPlayRequest) -> Node:
	match space:
		VFX_SPACES.GROUND:
			return _ground_layer
		VFX_SPACES.SCREEN:
			return _screen_root
		VFX_SPACES.ATTACHED:
			return _resolve_anchor(request.owner, request.anchor)
		VFX_SPACES.UI:
			return request.owner
		_:
			return _world_layer


func _resolve_anchor(owner: Node, anchor: String) -> Node:
	if owner == null or not is_instance_valid(owner):
		return null
	var anchors: Node = owner.get_node_or_null("VfxAnchors")
	if anchors == null:
		return owner
	var relative_path: String = String(ANCHOR_NODE_NAMES.get(anchor, "Center"))
	var target: Node = anchors.get_node_or_null(relative_path)
	return target if target != null else owner


func _apply_transform(instance: Node, space: String, request: VfxPlayRequest) -> void:
	if instance is Node2D:
		var node_2d := instance as Node2D
		if space == VFX_SPACES.ATTACHED:
			node_2d.position = Vector2.ZERO
		elif request.use_world_position:
			node_2d.global_position = request.world_position
		node_2d.rotation = request.rotation
		node_2d.scale = request.scale_value
	elif instance is Control and space == VFX_SPACES.SCREEN:
		var control := instance as Control
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _play_target_animation(
		effect_data: Dictionary,
		request: VfxPlayRequest
	) -> VfxHandle:
	var target: Node = request.owner
	if target == null or not is_instance_valid(target):
		return null
	var presenter: Node = target
	if not presenter.has_method("play_target_effect"):
		presenter = target.get_node_or_null("Presentation")
	if presenter == null or not presenter.has_method("play_target_effect"):
		push_warning(
			"[VfxHost] target lacks play_target_effect for %s"
			% String(effect_data.get("id", ""))
		)
		return null
	var raw_instance: Variant = presenter.call("play_target_effect", effect_data, request)
	var visual_node: Node = raw_instance as Node
	var handle := VfxHandle.new()
	handle.configure(self, visual_node, String(effect_data.get("id", "")))
	if visual_node == null:
		handle.mark_finished()
		return handle
	var instance_id: int = visual_node.get_instance_id()
	if _active.has(instance_id):
		_cancel_instance(instance_id, true)
		raw_instance = presenter.call("play_target_effect", effect_data, request)
		visual_node = raw_instance as Node
		if visual_node == null:
			handle.mark_finished()
			return handle
		handle.configure(self, visual_node, String(effect_data.get("id", "")))
		instance_id = visual_node.get_instance_id()
	var callback := Callable(self, "_on_target_effect_finished").bind(instance_id)
	if visual_node.has_signal("target_effect_finished"):
		visual_node.connect("target_effect_finished", callback, CONNECT_ONE_SHOT)
	_active[instance_id] = {
		"effect_id": String(effect_data.get("id", "")),
		"handle": handle,
		"instance": visual_node,
		"owner_id": target.get_instance_id(),
		"pooled": false,
		"external": true,
		"finished_callback": callback,
	}
	effect_started.emit(String(effect_data.get("id", "")), visual_node)
	return handle


func _ensure_pool(pool_id: String, scene: PackedScene, effect_data: Dictionary) -> bool:
	if PoolManager.has_pool(pool_id):
		return true
	var factory := func() -> Node:
		return scene.instantiate()
	var max_size: int = maxi(int(effect_data.get("max_size", 128)), 1)
	if not PoolManager.register_pool(pool_id, factory, max_size):
		return false
	return true


func _reparent(instance: Node, target_parent: Node) -> void:
	var current_parent: Node = instance.get_parent()
	if current_parent == target_parent:
		return
	if current_parent != null:
		current_parent.remove_child(instance)
	target_parent.add_child(instance)


func _connect_generic_finished(instance: Node) -> void:
	if not instance.has_signal("finished"):
		return
	var callback := Callable(self, "_on_generic_finished").bind(instance.get_instance_id())
	if not instance.is_connected("finished", callback):
		instance.connect("finished", callback, CONNECT_ONE_SHOT)


func _play_animation_fallback(instance: Node) -> void:
	var animation_player: AnimationPlayer = instance.get_node_or_null(
		"AnimationPlayer"
	) as AnimationPlayer
	if animation_player == null:
		return
	if animation_player.has_animation(&"RESET"):
		animation_player.play(&"RESET")
		animation_player.advance(0.0)
	if animation_player.has_animation(&"play"):
		animation_player.play(&"play")


func _on_instance_finished(_instance: Node, instance_id: int) -> void:
	_finish_instance(instance_id)


func _on_generic_finished(instance_id: int) -> void:
	_finish_instance(instance_id)


func _on_target_effect_finished(instance_id: int) -> void:
	_finish_instance(instance_id)


func _finish_instance(instance_id: int) -> void:
	if not _active.has(instance_id):
		return
	var record: Dictionary = _active[instance_id] as Dictionary
	_active.erase(instance_id)
	var effect_id: String = String(record.get("effect_id", ""))
	var handle: VfxHandle = record.get("handle") as VfxHandle
	var instance: Node = record.get("instance") as Node
	if handle != null:
		handle.mark_finished()
	if not bool(record.get("external", false)):
		_release_or_free(instance, bool(record.get("pooled", false)))
	effect_finished.emit(effect_id)


func _cancel_instance(instance_id: int, immediate: bool) -> void:
	if not _active.has(instance_id):
		return
	var record: Dictionary = _active[instance_id] as Dictionary
	var instance: Node = record.get("instance") as Node
	var callback: Callable = record.get("finished_callback", Callable()) as Callable
	if (
		callback.is_valid()
		and instance != null
		and is_instance_valid(instance)
		and instance.has_signal("target_effect_finished")
		and instance.is_connected("target_effect_finished", callback)
	):
		instance.disconnect("target_effect_finished", callback)
	if instance != null and is_instance_valid(instance) and instance.has_method("cancel"):
		instance.call("cancel", immediate)
	if not _active.has(instance_id):
		return
	_active.erase(instance_id)
	var handle: VfxHandle = record.get("handle") as VfxHandle
	if handle != null:
		handle.mark_cancelled()
	if not bool(record.get("external", false)):
		_release_or_free(instance, bool(record.get("pooled", false)))


func _release_or_free(instance: Node, pooled: bool) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	if pooled:
		PoolManager.release(instance)
	else:
		instance.queue_free()
