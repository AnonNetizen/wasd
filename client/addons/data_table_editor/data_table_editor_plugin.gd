# Doc: docs/代码/data_table_editor.md
@tool
extends EditorPlugin
## Editor-only data-table main screen. Runtime code never depends on this plugin.

const DATA_TABLE_MAIN_SCREEN := preload(
	"res://addons/data_table_editor/data_table_editor_main_screen.gd"
)
const MAIN_SCREEN_NAME := "数据配表"

var _main_screen: Control


func _enter_tree() -> void:
	_main_screen = DATA_TABLE_MAIN_SCREEN.new() as Control
	_main_screen.name = MAIN_SCREEN_NAME
	_main_screen.visible = false
	_main_screen.set("editor_interface", get_editor_interface())
	EditorInterface.get_editor_main_screen().add_child(_main_screen)
	_main_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	if editor_theme.has_icon(&"Database", &"EditorIcons"):
		return editor_theme.get_icon(&"Database", &"EditorIcons")
	return editor_theme.get_icon(&"Grid", &"EditorIcons")


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if not is_instance_valid(_main_screen):
		return
	_main_screen.visible = visible
	if visible:
		_main_screen.call("refresh_from_disk_if_clean")
