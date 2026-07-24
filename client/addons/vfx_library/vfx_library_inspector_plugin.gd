# Doc: docs/代码/visual_effects.md
@tool
extends EditorInspectorPlugin
## Adds catalog selectors to VfxEffectRef and PresentationProfileRef resources.

const EFFECT_SCRIPT_SUFFIX := "vfx_effect_ref.gd"
const PROFILE_SCRIPT_SUFFIX := "presentation_profile_ref.gd"
const EFFECT_ID_PROPERTIES := ["effect_id", "vfx_effect_id", "id"]
const PROFILE_ID_PROPERTIES := ["profile_id", "presentation_profile_id", "id"]

var open_picker: Callable
var undo_redo: EditorUndoRedoManager


func _can_handle(object: Object) -> bool:
	return not _reference_kind(object).is_empty()


func _parse_begin(object: Object) -> void:
	var kind: String = _reference_kind(object)
	if kind.is_empty():
		return
	var id_property: String = _id_property(object, kind)
	if id_property.is_empty():
		return
	var row := HBoxContainer.new()
	var current_label := Label.new()
	current_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current_label.text = "Current: %s" % String(object.get(id_property))
	row.add_child(current_label)
	var choose_button := Button.new()
	choose_button.text = "Choose from VFX Library..."
	choose_button.pressed.connect(
		_on_choose_pressed.bind(object, kind, id_property, current_label)
	)
	row.add_child(choose_button)
	add_custom_control(row)


func _on_choose_pressed(
	object: Object,
	kind: String,
	id_property: String,
	current_label: Label
) -> void:
	if not open_picker.is_valid():
		push_error("[vfx-library] Picker is unavailable.")
		return
	var current_id: String = String(object.get(id_property))
	open_picker.call(
		kind,
		current_id,
		Callable(self, "_apply_reference_id").bind(object, id_property, current_label)
	)


func _apply_reference_id(
	selected_id: String,
	object: Object,
	id_property: String,
	current_label: Label
) -> void:
	if not is_instance_valid(object):
		return
	var previous_id: String = String(object.get(id_property))
	if previous_id == selected_id:
		return
	if undo_redo != null:
		undo_redo.create_action("Select VFX Reference")
		undo_redo.add_do_property(object, id_property, selected_id)
		undo_redo.add_undo_property(object, id_property, previous_id)
		undo_redo.commit_action()
	else:
		object.set(id_property, selected_id)
	if object is Resource:
		(object as Resource).emit_changed()
	if is_instance_valid(current_label):
		current_label.text = "Current: %s" % selected_id


func _reference_kind(object: Object) -> String:
	var script: Script = object.get_script() as Script
	if script == null:
		return ""
	var global_name: String = String(script.get_global_name())
	var resource_path: String = script.resource_path
	if global_name == "VfxEffectRef" or resource_path.ends_with(EFFECT_SCRIPT_SUFFIX):
		return "effect"
	if global_name == "PresentationProfileRef" or resource_path.ends_with(PROFILE_SCRIPT_SUFFIX):
		return "profile"
	return ""


func _id_property(object: Object, kind: String) -> String:
	var candidates: Array = (
		EFFECT_ID_PROPERTIES if kind == "effect" else PROFILE_ID_PROPERTIES
	)
	for property: Dictionary in object.get_property_list():
		var property_name: String = String(property.get("name", ""))
		if candidates.has(property_name):
			return property_name
	return ""
