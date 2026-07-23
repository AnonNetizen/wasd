# Doc: docs/代码/gameplay_loading.md
class_name LoadingScreen
extends CanvasLayer


@onready var _loading_label: Label = get_node_or_null("Root/Center/Layout/LoadingLabel") as Label
@onready var _spinner_animation: AnimationPlayer = get_node_or_null("SpinnerAnimation") as AnimationPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _loading_label == null or _spinner_animation == null:
		push_error("[LoadingScreen] missing required scene nodes")
		return
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh_texts()
	_spinner_animation.call("play", &"spin")


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func refresh_texts() -> void:
	if _loading_label != null:
		_loading_label.text = tr("ui_loading")


func animation_is_playing() -> bool:
	return _spinner_animation != null and _spinner_animation.is_playing()


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()
