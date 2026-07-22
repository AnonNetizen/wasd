@tool
extends VBoxContainer

#region Public Variables

var editor_plugin: EditorPlugin

#endregion

#region Onready

@onready var updater: Control = %UpdateButton
@onready var viewfinder: Control = %ViewfinderPanel

#endregion


#region Private Functions

func _ready() -> void:
	updater.editor_plugin = editor_plugin

#endregion
