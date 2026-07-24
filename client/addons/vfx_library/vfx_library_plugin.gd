# Doc: docs/代码/visual_effects.md
@tool
extends EditorPlugin
## Editor-only visual-effects catalog main screen and Inspector integration.

const VFX_LIBRARY_MAIN_SCREEN := preload(
	"res://addons/vfx_library/vfx_library_main_screen.gd"
)
const VFX_LIBRARY_INSPECTOR_PLUGIN := preload(
	"res://addons/vfx_library/vfx_library_inspector_plugin.gd"
)
const MAIN_SCREEN_NAME := "VFX 效果库"

var _main_screen: Control
var _inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	_main_screen = VFX_LIBRARY_MAIN_SCREEN.new() as Control
	_main_screen.name = MAIN_SCREEN_NAME
	_main_screen.visible = false
	_main_screen.set("editor_interface", get_editor_interface())
	_main_screen.set("undo_redo", get_undo_redo())
	EditorInterface.get_editor_main_screen().add_child(_main_screen)

	_inspector_plugin = VFX_LIBRARY_INSPECTOR_PLUGIN.new() as EditorInspectorPlugin
	_inspector_plugin.set("open_picker", Callable(_main_screen, "open_picker"))
	_inspector_plugin.set("undo_redo", get_undo_redo())
	add_inspector_plugin(_inspector_plugin)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(_inspector_plugin):
		remove_inspector_plugin(_inspector_plugin)
	_inspector_plugin = null
	if is_instance_valid(_main_screen):
		var parent: Node = _main_screen.get_parent()
		if parent != null:
			parent.remove_child(_main_screen)
		_main_screen.queue_free()
	_main_screen = null


func _get_plugin_name() -> String:
	return MAIN_SCREEN_NAME


func _get_plugin_icon() -> Texture2D:
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(&"GPUParticles2D", &"EditorIcons"):
		return editor_theme.get_icon(&"GPUParticles2D", &"EditorIcons")
	return editor_theme.get_icon(&"AnimationPlayer", &"EditorIcons")


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_main_screen):
		_main_screen.visible = visible
		if visible:
			_main_screen.call("refresh_library")
