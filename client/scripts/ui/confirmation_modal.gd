# Doc: docs/代码/ui_manager.md
class_name ConfirmationModal
extends CanvasLayer


signal cancelled()
signal confirmed()

var pauses_game: bool = false

var _body_label: Label = null
var _cancel_button: Button = null
var _confirm_button: Button = null
var _resolved: bool = false
var _title_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title_label = get_node_or_null("Root/Center/Panel/Margin/Layout/TitleLabel") as Label
	_body_label = get_node_or_null("Root/Center/Panel/Margin/Layout/BodyLabel") as Label
	_confirm_button = get_node_or_null("Root/Center/Panel/Margin/Layout/Buttons/ConfirmButton") as Button
	_cancel_button = get_node_or_null("Root/Center/Panel/Margin/Layout/Buttons/CancelButton") as Button
	if _title_label == null or _body_label == null or _confirm_button == null or _cancel_button == null:
		push_error("[ConfirmationModal] missing required scene nodes")
		return
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)


func configure(
		title: String,
		body: String,
		confirm_text: String,
		cancel_text: String
	) -> void:
	if _title_label != null:
		_title_label.text = title
	if _body_label != null:
		_body_label.text = body
	if _confirm_button != null:
		_confirm_button.text = confirm_text
	if _cancel_button != null:
		_cancel_button.text = cancel_text


func request_close() -> void:
	request_cancel()


func request_cancel() -> void:
	_on_cancel_pressed()


func grab_default_focus() -> void:
	UIManager.grab_focus_for_navigation(_cancel_button)


func _on_confirm_pressed() -> void:
	if _resolved:
		return
	_resolved = true
	confirmed.emit()


func _on_cancel_pressed() -> void:
	if _resolved:
		return
	_resolved = true
	cancelled.emit()
