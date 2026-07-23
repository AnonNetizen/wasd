# Doc: docs/代码/module_authoring_pipeline.md
@tool
extends EditorPlugin
## Editor-only JSON module authoring dock. It never touches the edited scene tree.

const MODULE_AUTHORING_DOCK := preload("res://addons/module_authoring/module_authoring_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = MODULE_AUTHORING_DOCK.new() as Control
	_dock.set("editor_interface", get_editor_interface())
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, _dock)


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
