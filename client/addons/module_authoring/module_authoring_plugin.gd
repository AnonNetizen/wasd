# Doc: docs/代码/module_authoring_pipeline.md
@tool
extends EditorPlugin
## Editor-only JSON module authoring main screen. It never touches the edited scene tree.

const MODULE_AUTHORING_MAIN_SCREEN := preload(
	"res://addons/module_authoring/module_authoring_main_screen.gd"
)
const MAIN_SCREEN_NAME := "Module JSON"

var _main_screen: Control


func _enter_tree() -> void:
	_main_screen = MODULE_AUTHORING_MAIN_SCREEN.new() as Control
	_main_screen.name = MAIN_SCREEN_NAME
	_main_screen.visible = false
	_main_screen.set("editor_interface", get_editor_interface())
	EditorInterface.get_editor_main_screen().add_child(_main_screen)
	_make_visible(false)


func _exit_tree() -> void:
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
	if editor_theme.has_icon(&"TileMapLayer", &"EditorIcons"):
		return editor_theme.get_icon(&"TileMapLayer", &"EditorIcons")
	return editor_theme.get_icon(&"Tools", &"EditorIcons")


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_main_screen):
		_main_screen.visible = visible
