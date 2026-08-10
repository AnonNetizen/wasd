# Doc: docs/代码/mod_loader.md
# Authority: docs/决策记录.md ADR #196
class_name ModPanel
extends CanvasLayer


signal closed_requested()

var _title_label: Label = null
var _status_label: RichTextLabel = null
var _reload_button: Button = null
var _back_button: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/TitleLabel"
	) as Label
	_status_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/StatusLabel"
	) as RichTextLabel
	_reload_button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Buttons/ReloadButton"
	) as Button
	_back_button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Buttons/BackButton"
	) as Button
	if (
		_title_label == null
		or _status_label == null
		or _reload_button == null
		or _back_button == null
	):
		push_error("[ModPanel] missing required scene nodes")
		return
	_reload_button.pressed.connect(_on_reload_pressed)
	_back_button.pressed.connect(request_close)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh()
	call_deferred("_grab_default_focus")


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func refresh() -> void:
	if _title_label == null:
		return
	_title_label.text = tr("ui_mod_panel_title")
	_reload_button.text = tr("ui_mod_panel_reload")
	_back_button.text = tr("ui_back")
	var packages: Array[Dictionary] = ModLoader.package_statuses()
	if packages.is_empty():
		_status_label.text = tr("ui_mod_panel_empty")
		return
	var lines: PackedStringArray = []
	for package: Dictionary in packages:
		var status: String = String(package.get("status", "disabled"))
		lines.append(
			"[b]%s[/b]  v%s  [%s]" % [
				_escape_bbcode(String(package.get("name", package.get("id", "")))),
				_escape_bbcode(String(package.get("version", ""))),
				tr("ui_mod_panel_status_%s" % status),
			]
		)
		for raw_diagnostic: Variant in package.get("diagnostics", []):
			lines.append("  • %s" % _escape_bbcode(String(raw_diagnostic)))
	_status_label.text = "\n".join(lines)


func request_close() -> void:
	closed_requested.emit()


func _on_reload_pressed() -> void:
	if not ModLoader.reload_packages():
		refresh()
		return
	DataLoader.reload_contracts()
	DataLoader.validate_project_data()
	refresh()


func _grab_default_focus() -> void:
	UIManager.grab_focus_for_navigation(_reload_button)


func _on_locale_changed(_locale: String) -> void:
	refresh()


func _escape_bbcode(value: String) -> String:
	return _status_label.escape_bbcode(value)
