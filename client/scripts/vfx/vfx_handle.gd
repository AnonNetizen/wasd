# Doc: docs/代码/visual_effects.md
class_name VfxHandle
extends RefCounted
## Cancellable handle for one visual-effect playback.


signal finished(effect_id: String)
signal cancelled(effect_id: String)

var effect_id: String = ""
var _host_ref: WeakRef = null
var _instance_ref: WeakRef = null
var _active: bool = false


func configure(host: Object, instance: Node, configured_effect_id: String) -> void:
	effect_id = configured_effect_id
	_host_ref = weakref(host)
	_instance_ref = weakref(instance) if instance != null else null
	_active = true


func is_active() -> bool:
	return _active


func instance() -> Node:
	if _instance_ref == null:
		return null
	var raw_instance: Variant = _instance_ref.get_ref()
	return raw_instance as Node


func cancel(immediate: bool = false) -> void:
	if not _active:
		return
	if _host_ref == null:
		mark_cancelled()
		return
	var raw_host: Variant = _host_ref.get_ref()
	if raw_host is Object and (raw_host as Object).has_method("cancel_handle"):
		(raw_host as Object).call("cancel_handle", self, immediate)
		return
	mark_cancelled()


func mark_finished() -> void:
	if not _active:
		return
	_active = false
	finished.emit(effect_id)


func mark_cancelled() -> void:
	if not _active:
		return
	_active = false
	cancelled.emit(effect_id)
