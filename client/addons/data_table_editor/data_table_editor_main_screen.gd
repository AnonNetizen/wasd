# Doc: docs/代码/data_table_editor.md
@tool
extends Control
## Unified editor main screen for catalog-owned JSON, CSV, and locale strings.

const DATA_TABLE_CATALOG := preload("res://scripts/editor/data_table_catalog.gd")
const DATA_TABLE_DOCUMENT := preload("res://scripts/editor/data_table_document.gd")
const DATA_SEARCH_INDEX := preload("res://scripts/editor/data_search_index.gd")
const DATA_TABLE_CONTRACT_BRIDGE := preload(
	"res://scripts/editor/data_table_contract_bridge.gd"
)
const CONTRACTS_PATH: String = "res://data/_contracts.json"
const PROPERTY_EDITOR := preload(
	"res://addons/data_table_editor/data_table_property_editor.gd"
)
const SKILL_DESCRIPTION_FORMATTER := preload(
	"res://scripts/data/skill_description_formatter.gd"
)

const MODULE_SCREEN_NAME: String = "Module JSON"
const VFX_SCREEN_NAME: String = "VFX 效果库"
const MAX_TABLE_COLUMNS: int = 12

var editor_interface: EditorInterface

var _catalog: DataTableCatalog
var _document: DataTableDocument
var _search_index: DataSearchIndex
var _dataset_list: ItemList
var _section_option: OptionButton
var _table_filter: LineEdit
var _table: Tree
var _search_edit: LineEdit
var _dataset_filter: OptionButton
var _format_filter: OptionButton
var _type_filter: OptionButton
var _search_results: Tree
var _data_panel: VBoxContainer
var _search_panel: VBoxContainer
var _property_editor: DataTablePropertyEditor
var _locale_box: VBoxContainer
var _skill_preview: RichTextLabel
var _status_label: Label
var _save_button: Button
var _undo_button: Button
var _redo_button: Button
var _new_button: Button
var _copy_button: Button
var _delete_button: Button
var _id_dialog: ConfirmationDialog
var _id_edit: LineEdit
var _meaning_edit: LineEdit
var _delete_dialog: ConfirmationDialog
var _conflict_dialog: ConfirmationDialog
var _draft_dialog: ConfirmationDialog
var _raw_dialog: AcceptDialog
var _raw_text: TextEdit
var _table_column_paths: Array[Array] = []
var _current_section: String = ""
var _selected_record_index: int = -1
var _pending_create_mode: String = "new"
var _pending_delete_index: int = -1
var _sort_column: int = 0
var _sort_ascending: bool = true
var _initialized: bool = false


func _ready() -> void:
	if _initialized:
		return
	_initialized = true
	_catalog = DATA_TABLE_CATALOG.new() as DataTableCatalog
	_document = DATA_TABLE_DOCUMENT.new() as DataTableDocument
	_search_index = DATA_SEARCH_INDEX.new() as DataSearchIndex
	_build_ui()
	_connect_signals()
	var catalog_result: Dictionary = _catalog.load_catalog()
	if not bool(catalog_result.get("ok", false)):
		_show_errors("数据集目录加载失败", catalog_result)
		return
	_populate_dataset_navigation()
	_populate_search_filters()
	_rebuild_search_index()
	if _dataset_list.item_count > 0:
		_dataset_list.select(0)
		_open_dataset_at(0)


func refresh_from_disk_if_clean() -> void:
	if not _initialized or _document == null:
		return
	if _document.descriptor.is_empty():
		return
	if _document.disk_changed():
		if _document.dirty:
			_set_status("外部文件已变化；当前草稿不会被静默覆盖。")
		else:
			_open_dataset_by_id(_document.dataset_id())
	_rebuild_search_index()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not key_event.ctrl_pressed or key_event.keycode != KEY_V:
		return
	if _table == null or not _table.has_focus() or _selected_record_index < 0:
		return
	var start_column: int = _table.get_selected_column()
	if start_column < 0 or start_column >= _table_column_paths.size():
		return
	var paths: Array[Array] = []
	for index: int in range(start_column, _table_column_paths.size()):
		paths.append(_table_column_paths[index])
	var result: Dictionary = _document.paste_tsv(
		_current_section,
		_selected_record_index,
		paths,
		DisplayServer.clipboard_get()
	)
	if not bool(result.get("ok", false)):
		_show_errors("TSV 粘贴失败", result)
		return
	_refresh_current_view(_selected_record_index)
	get_viewport().set_input_as_handled()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_action_toolbar())
	root.add_child(_build_search_toolbar())
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 238
	root.add_child(split)
	split.add_child(_build_navigation_panel())
	var work_split := HSplitContainer.new()
	work_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work_split.split_offset = 830
	split.add_child(work_split)
	work_split.add_child(_build_center_panel())
	work_split.add_child(_build_inspector_panel())
	_status_label = Label.new()
	_status_label.text = "正在初始化数据配表……"
	_status_label.add_theme_constant_override("outline_size", 2)
	root.add_child(_status_label)
	_build_dialogs()


func _build_action_toolbar() -> HBoxContainer:
	var toolbar := HBoxContainer.new()
	_save_button = _toolbar_button("保存", "Save")
	toolbar.add_child(_save_button)
	toolbar.add_child(_toolbar_button("重新加载", "Reload"))
	toolbar.get_child(toolbar.get_child_count() - 1).pressed.connect(_on_reload_pressed)
	_undo_button = _toolbar_button("撤销", "Undo")
	toolbar.add_child(_undo_button)
	_redo_button = _toolbar_button("重做", "Redo")
	toolbar.add_child(_redo_button)
	toolbar.add_child(VSeparator.new())
	_new_button = _toolbar_button("新增", "Add")
	toolbar.add_child(_new_button)
	_copy_button = _toolbar_button("复制为新 ID", "Duplicate")
	toolbar.add_child(_copy_button)
	_delete_button = _toolbar_button("删除", "Remove")
	toolbar.add_child(_delete_button)
	toolbar.add_child(VSeparator.new())
	var raw_button: Button = _toolbar_button("只读原文 / Diff", "Script")
	raw_button.pressed.connect(_show_raw_and_diff)
	toolbar.add_child(raw_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	return toolbar


func _build_search_toolbar() -> HBoxContainer:
	var toolbar := HBoxContainer.new()
	var label := Label.new()
	label.text = "全局搜索"
	toolbar.add_child(label)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "ID、字段名、中英文、数值；空格表示 AND"
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_search_edit)
	_dataset_filter = OptionButton.new()
	_dataset_filter.custom_minimum_size.x = 150.0
	toolbar.add_child(_dataset_filter)
	_format_filter = OptionButton.new()
	_format_filter.add_item("全部格式")
	_format_filter.set_item_metadata(0, "")
	_format_filter.add_item("JSON")
	_format_filter.set_item_metadata(1, "json")
	_format_filter.add_item("CSV")
	_format_filter.set_item_metadata(2, "csv")
	toolbar.add_child(_format_filter)
	_type_filter = OptionButton.new()
	for item: Array in [
		["全部类型", ""],
		["文本", "string"],
		["数字", "number"],
		["布尔", "boolean"],
		["空值", "null"],
	]:
		_type_filter.add_item(String(item[0]))
		_type_filter.set_item_metadata(_type_filter.item_count - 1, String(item[1]))
	toolbar.add_child(_type_filter)
	return toolbar


func _build_navigation_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = 210.0
	var label := Label.new()
	label.text = "数据集"
	panel.add_child(label)
	_dataset_list = ItemList.new()
	_dataset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dataset_list.select_mode = ItemList.SELECT_SINGLE
	panel.add_child(_dataset_list)
	var module_button := Button.new()
	module_button.text = "打开 Module JSON"
	module_button.tooltip_text = "切换到专用模块编辑器；模块数据不会进入全局搜索。"
	module_button.pressed.connect(_open_module_editor)
	panel.add_child(module_button)
	var vfx_button := Button.new()
	vfx_button.text = "打开 VFX 效果库"
	vfx_button.tooltip_text = "切换到专用 VFX 编辑器；VFX/profile 不会进入全局搜索。"
	vfx_button.pressed.connect(_open_vfx_editor)
	panel.add_child(vfx_button)
	return panel


func _build_center_panel() -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.custom_minimum_size.x = 560.0
	_data_panel = VBoxContainer.new()
	_data_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var section_bar := HBoxContainer.new()
	var section_label := Label.new()
	section_label.text = "分区"
	section_bar.add_child(section_label)
	_section_option = OptionButton.new()
	_section_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_bar.add_child(_section_option)
	_table_filter = LineEdit.new()
	_table_filter.placeholder_text = "筛选当前表格"
	_table_filter.clear_button_enabled = true
	_table_filter.custom_minimum_size.x = 220.0
	section_bar.add_child(_table_filter)
	_data_panel.add_child(section_bar)
	_table = Tree.new()
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table.column_titles_visible = true
	_table.hide_root = true
	_table.select_mode = Tree.SELECT_ROW
	_data_panel.add_child(_table)
	wrapper.add_child(_data_panel)
	_search_panel = VBoxContainer.new()
	_search_panel.visible = false
	_search_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var search_label := Label.new()
	search_label.text = "全局搜索结果（双击或回车定位）"
	_search_panel.add_child(search_label)
	_search_results = Tree.new()
	_search_results.columns = 4
	_search_results.column_titles_visible = true
	_search_results.hide_root = true
	_search_results.set_column_title(0, "来源")
	_search_results.set_column_title(1, "记录 ID")
	_search_results.set_column_title(2, "字段路径")
	_search_results.set_column_title(3, "值")
	_search_results.set_column_expand(0, false)
	_search_results.set_column_custom_minimum_width(0, 150)
	_search_results.set_column_expand(1, false)
	_search_results.set_column_custom_minimum_width(1, 190)
	_search_results.set_column_expand(2, false)
	_search_results.set_column_custom_minimum_width(2, 220)
	_search_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_search_panel.add_child(_search_results)
	wrapper.add_child(_search_panel)
	return wrapper


func _build_inspector_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size.x = 360.0
	var label := Label.new()
	label.text = "递归属性"
	panel.add_child(label)
	_property_editor = PROPERTY_EDITOR.new() as DataTablePropertyEditor
	_property_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_property_editor)
	var locale_title := Label.new()
	locale_title.text = "关联文案（直接编辑中英文）"
	panel.add_child(locale_title)
	_locale_box = VBoxContainer.new()
	panel.add_child(_locale_box)
	var preview_title := Label.new()
	preview_title.text = "技能描述实时预览"
	panel.add_child(preview_title)
	_skill_preview = RichTextLabel.new()
	_skill_preview.fit_content = true
	_skill_preview.custom_minimum_size.y = 92.0
	_skill_preview.bbcode_enabled = false
	panel.add_child(_skill_preview)
	return panel


func _build_dialogs() -> void:
	_id_dialog = ConfirmationDialog.new()
	_id_dialog.title = "创建数据记录"
	var id_box := VBoxContainer.new()
	var id_label := Label.new()
	id_label.text = "新 ID（已有 ID 不支持直接改名）"
	id_box.add_child(id_label)
	_id_edit = LineEdit.new()
	id_box.add_child(_id_edit)
	var meaning_label := Label.new()
	meaning_label.text = "契约含义（仅需要登记内容契约时使用）"
	id_box.add_child(meaning_label)
	_meaning_edit = LineEdit.new()
	id_box.add_child(_meaning_edit)
	_id_dialog.add_child(id_box)
	add_child(_id_dialog)
	_id_dialog.confirmed.connect(_on_create_confirmed)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "删除记录"
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)

	_conflict_dialog = ConfirmationDialog.new()
	_conflict_dialog.title = "外部文件冲突"
	_conflict_dialog.dialog_text = (
		"磁盘文件已被外部修改。继续会明确使用当前草稿替换磁盘版本；取消可重新加载并放弃草稿。"
	)
	_conflict_dialog.ok_button_text = "以草稿替换"
	add_child(_conflict_dialog)
	_conflict_dialog.confirmed.connect(_save_current.bind(true))

	_draft_dialog = ConfirmationDialog.new()
	_draft_dialog.title = "发现自动草稿"
	_draft_dialog.ok_button_text = "恢复草稿"
	_draft_dialog.get_cancel_button().text = "放弃草稿"
	add_child(_draft_dialog)
	_draft_dialog.confirmed.connect(_restore_current_draft)
	_draft_dialog.canceled.connect(_discard_current_draft)

	_raw_dialog = AcceptDialog.new()
	_raw_dialog.title = "只读原文 / 当前 Diff"
	_raw_dialog.min_size = Vector2i(980, 680)
	_raw_text = TextEdit.new()
	_raw_text.editable = false
	_raw_text.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_raw_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_raw_dialog.add_child(_raw_text)
	add_child(_raw_dialog)


func _connect_signals() -> void:
	_save_button.pressed.connect(_save_current.bind(false))
	_undo_button.pressed.connect(_on_undo_pressed)
	_redo_button.pressed.connect(_on_redo_pressed)
	_new_button.pressed.connect(_show_create_dialog.bind("new"))
	_copy_button.pressed.connect(_show_create_dialog.bind("copy"))
	_delete_button.pressed.connect(_request_delete)
	_dataset_list.item_selected.connect(_open_dataset_at)
	_section_option.item_selected.connect(_on_section_selected)
	_table.item_selected.connect(_on_table_selected)
	_table.item_edited.connect(_on_table_item_edited)
	_table.column_title_clicked.connect(_on_table_sort_requested)
	_table_filter.text_changed.connect(_on_table_filter_changed)
	_property_editor.value_changed.connect(_on_property_value_changed)
	_property_editor.array_value_added.connect(_on_array_add)
	_property_editor.array_value_removed.connect(_on_array_remove)
	_search_edit.text_changed.connect(_refresh_search_results)
	_dataset_filter.item_selected.connect(_on_search_filter_changed)
	_format_filter.item_selected.connect(_on_search_filter_changed)
	_type_filter.item_selected.connect(_on_search_filter_changed)
	_search_results.item_activated.connect(_activate_search_result)
	_document.document_changed.connect(_on_document_changed)
	if editor_interface != null:
		var filesystem: EditorFileSystem = editor_interface.get_resource_filesystem()
		if filesystem != null:
			filesystem.filesystem_changed.connect(_on_filesystem_changed)


func _toolbar_button(text: String, icon_name: StringName) -> Button:
	var button := Button.new()
	button.text = text
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme.has_icon(icon_name, &"EditorIcons"):
		button.icon = editor_theme.get_icon(icon_name, &"EditorIcons")
	return button


func _populate_dataset_navigation() -> void:
	_dataset_list.clear()
	for descriptor: Dictionary in _catalog.datasets():
		var label: String = "%s / %s" % [
			String(descriptor.get("group", "其他")),
			String(descriptor.get("label", descriptor.get("id", ""))),
		]
		_dataset_list.add_item(label)
		_dataset_list.set_item_metadata(
			_dataset_list.item_count - 1,
			String(descriptor.get("id", ""))
		)


func _populate_search_filters() -> void:
	_dataset_filter.clear()
	_dataset_filter.add_item("全部数据集")
	_dataset_filter.set_item_metadata(0, "")
	for descriptor: Dictionary in _catalog.datasets():
		_dataset_filter.add_item(String(descriptor.get("label", descriptor.get("id", ""))))
		_dataset_filter.set_item_metadata(
			_dataset_filter.item_count - 1,
			String(descriptor.get("id", ""))
		)


func _open_dataset_at(index: int) -> void:
	if index < 0 or index >= _dataset_list.item_count:
		return
	_open_dataset_by_id(String(_dataset_list.get_item_metadata(index)))


func _open_dataset_by_id(dataset_id: String) -> void:
	var descriptor: Dictionary = _catalog.dataset_by_id(dataset_id)
	if descriptor.is_empty():
		return
	var result: Dictionary = _document.open_dataset(descriptor)
	if not bool(result.get("ok", false)):
		_show_errors("打开数据集失败", result)
		return
	_select_dataset_navigation(dataset_id)
	_section_option.clear()
	for section: Dictionary in _document.section_descriptors():
		_section_option.add_item(String(section.get("label", section.get("path", ""))))
		_section_option.set_item_metadata(
			_section_option.item_count - 1,
			String(section.get("path", ""))
		)
	if _section_option.item_count > 0:
		_section_option.select(0)
		_current_section = String(_section_option.get_item_metadata(0))
	_refresh_current_view()
	var draft_status: String = String(result.get("draft_status", "none"))
	if draft_status == "matching" or draft_status == "conflict":
		_draft_dialog.dialog_text = (
			"发现与当前磁盘版本匹配的自动草稿。是否恢复？"
			if draft_status == "matching"
			else "发现草稿，但源文件已发生外部变化。恢复后保存仍需明确确认覆盖。"
		)
		_draft_dialog.set_meta("allow_conflict", draft_status == "conflict")
		_draft_dialog.popup_centered(Vector2i(620, 180))


func _select_dataset_navigation(dataset_id: String) -> void:
	for index: int in range(_dataset_list.item_count):
		if String(_dataset_list.get_item_metadata(index)) == dataset_id:
			_dataset_list.select(index)
			_dataset_list.ensure_current_is_visible()
			return


func _on_section_selected(index: int) -> void:
	if index < 0:
		return
	_current_section = String(_section_option.get_item_metadata(index))
	_refresh_current_view()


func _refresh_current_view(select_record_index: int = -1) -> void:
	_build_table(select_record_index)
	_update_inspector(select_record_index)
	_update_action_state()


func _build_table(select_record_index: int = -1) -> void:
	_table.clear()
	_table_column_paths.clear()
	var rows: Array = _document.records(_current_section)
	var scalar_keys: Array[String] = _table_scalar_keys(rows)
	if scalar_keys.is_empty():
		scalar_keys.append("记录")
	_table.columns = mini(scalar_keys.size(), MAX_TABLE_COLUMNS)
	for column: int in range(_table.columns):
		var key: String = scalar_keys[column]
		_table.set_column_title(column, key)
		_table.set_column_expand(column, column > 0)
		_table_column_paths.append([key] if key != "记录" else [])
	var root: TreeItem = _table.create_item()
	var filter_text: String = _table_filter.text.strip_edges().to_lower()
	var view_rows: Array[Dictionary] = []
	for index: int in range(rows.size()):
		if not rows[index] is Dictionary:
			continue
		var row: Dictionary = rows[index] as Dictionary
		if not filter_text.is_empty() and not JSON.stringify(row).to_lower().contains(filter_text):
			continue
		view_rows.append({"index": index, "record": row})
	view_rows.sort_custom(_sort_view_rows)
	var primary_keys: Array[String] = _document.primary_keys(_current_section)
	for view_row: Dictionary in view_rows:
		var record_index: int = int(view_row.get("index", -1))
		var record_data: Dictionary = view_row.get("record", {}) as Dictionary
		var item: TreeItem = _table.create_item(root)
		item.set_metadata(0, record_index)
		for column: int in range(_table.columns):
			var key: String = scalar_keys[column]
			var text: String = (
				_document.record_identity(_current_section, record_index)
				if key == "记录"
				else _scalar_text(record_data.get(key))
			)
			item.set_text(column, text)
			if key != "记录" and not primary_keys.has(key):
				item.set_editable(column, true)
		if record_index == select_record_index:
			item.select(0)
			_table.scroll_to_item(item, true)
	_selected_record_index = select_record_index


func _table_scalar_keys(rows: Array) -> Array[String]:
	var keys: Array[String] = _document.primary_keys(_current_section)
	for raw_row: Variant in rows:
		if not raw_row is Dictionary:
			continue
		for raw_key: Variant in (raw_row as Dictionary).keys():
			var key: String = String(raw_key)
			var value: Variant = (raw_row as Dictionary)[raw_key]
			if (value is Dictionary or value is Array) or keys.has(key):
				continue
			keys.append(key)
		if keys.size() >= MAX_TABLE_COLUMNS:
			break
	return keys.slice(0, MAX_TABLE_COLUMNS)


func _sort_view_rows(left: Dictionary, right: Dictionary) -> bool:
	var column: int = clampi(_sort_column, 0, maxi(_table_column_paths.size() - 1, 0))
	var path: Array = _table_column_paths[column] if column < _table_column_paths.size() else []
	var left_value: String = _document.record_identity(_current_section, int(left.get("index", -1)))
	var right_value: String = _document.record_identity(_current_section, int(right.get("index", -1)))
	if not path.is_empty():
		left_value = _scalar_text((left.get("record", {}) as Dictionary).get(String(path[0])))
		right_value = _scalar_text((right.get("record", {}) as Dictionary).get(String(path[0])))
	return left_value.naturalnocasecmp_to(right_value) < 0 if _sort_ascending else left_value.naturalnocasecmp_to(right_value) > 0


func _on_table_selected() -> void:
	var item: TreeItem = _table.get_selected()
	if item == null:
		return
	_selected_record_index = int(item.get_metadata(0))
	_update_inspector(_selected_record_index)
	_update_action_state()


func _on_table_item_edited() -> void:
	var item: TreeItem = _table.get_edited()
	var column: int = _table.get_edited_column()
	if item == null or column < 0 or column >= _table_column_paths.size():
		return
	var path: Array = _table_column_paths[column]
	if path.is_empty():
		return
	var record_index: int = int(item.get_metadata(0))
	if not _document.set_record_value(
		_current_section,
		record_index,
		path,
		item.get_text(column)
	):
		_refresh_current_view(record_index)
		return
	_refresh_current_view(record_index)


func _on_table_sort_requested(column: int, _mouse_button: int) -> void:
	if _sort_column == column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = column
		_sort_ascending = true
	_build_table(_selected_record_index)


func _on_table_filter_changed(_text: String) -> void:
	_build_table(_selected_record_index)


func _update_inspector(record_index: int) -> void:
	var record_data: Dictionary = _document.record(_current_section, record_index)
	_property_editor.refresh(_inspector_record(record_data), _property_field_options())
	_rebuild_locale_fields(record_data)
	_rebuild_skill_preview(record_data)


func _inspector_record(record_data: Dictionary) -> Dictionary:
	if _current_section != "$root" or record_data.is_empty():
		return record_data
	var root_view: Dictionary = record_data.duplicate(false)
	for section: Dictionary in _document.section_descriptors():
		var section_path: String = String(section.get("path", ""))
		if section_path != "$root" and section_path != "$rows":
			root_view.erase(section_path)
	return root_view


func _property_field_options() -> Dictionary:
	var output: Dictionary = {}
	var raw_rules: Variant = _document.descriptor.get("field_rules", [])
	if raw_rules is Array:
		for raw_rule: Variant in raw_rules as Array:
			if not raw_rule is Dictionary:
				continue
			var rule: Dictionary = raw_rule as Dictionary
			var values: Variant = rule.get("values", [])
			if values is Array and not (values as Array).is_empty():
				output[String(rule.get("path", ""))] = PackedStringArray(values)
	var contracts: Dictionary = _load_contract_values()
	var raw_references: Variant = _document.descriptor.get("references", [])
	if raw_references is Array:
		for raw_reference: Variant in raw_references as Array:
			if not raw_reference is Dictionary:
				continue
			var reference: Dictionary = raw_reference as Dictionary
			var target: String = String(reference.get("target", ""))
			if not target.begins_with("contract:"):
				continue
			var contract_key: String = target.trim_prefix("contract:")
			var values: Variant = contracts.get(contract_key, [])
			if values is Array:
				output[String(reference.get("path", ""))] = PackedStringArray(values)
	return output


func _load_contract_values() -> Dictionary:
	if not FileAccess.file_exists(CONTRACTS_PATH):
		return {}
	var file: FileAccess = FileAccess.open(CONTRACTS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var raw_contracts: Variant = (parsed as Dictionary).get("contracts", {})
	return raw_contracts as Dictionary if raw_contracts is Dictionary else {}


func _rebuild_locale_fields(record_data: Dictionary) -> void:
	for child: Node in _locale_box.get_children():
		child.queue_free()
	var raw_fields: Variant = _document.descriptor.get("locale_fields", [])
	if not raw_fields is Array:
		return
	for raw_field: Variant in raw_fields as Array:
		var field: String = String(raw_field)
		var locale_key: String = String(record_data.get(field, ""))
		if locale_key.is_empty():
			continue
		var title := Label.new()
		title.text = "%s · %s" % [field, locale_key]
		_locale_box.add_child(title)
		var row := HBoxContainer.new()
		var zh := LineEdit.new()
		zh.placeholder_text = "中文"
		zh.text = _document.locale_value(locale_key, "zh_CN")
		zh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		zh.text_submitted.connect(_on_locale_submitted.bind(locale_key, "zh_CN"))
		zh.focus_exited.connect(_on_locale_focus_exited.bind(zh, locale_key, "zh_CN"))
		row.add_child(zh)
		var en := LineEdit.new()
		en.placeholder_text = "English"
		en.text = _document.locale_value(locale_key, "en")
		en.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		en.text_submitted.connect(_on_locale_submitted.bind(locale_key, "en"))
		en.focus_exited.connect(_on_locale_focus_exited.bind(en, locale_key, "en"))
		row.add_child(en)
		_locale_box.add_child(row)


func _rebuild_skill_preview(record_data: Dictionary) -> void:
	_skill_preview.visible = String(_document.descriptor.get("preview", "")) == "skill"
	if not _skill_preview.visible or record_data.is_empty():
		_skill_preview.text = ""
		return
	var desc_key: String = String(record_data.get("desc_key", ""))
	var ability_stats: Dictionary = {
		"ability_strength": 1.0,
		"ability_range": 1.0,
		"ability_duration": 1.0,
		"ability_efficiency": 1.0,
	}
	var zh: String = SKILL_DESCRIPTION_FORMATTER.format_skill(
		_document.locale_value(desc_key, "zh_CN"), record_data, ability_stats
	)
	var en: String = SKILL_DESCRIPTION_FORMATTER.format_skill(
		_document.locale_value(desc_key, "en"), record_data, ability_stats
	)
	_skill_preview.text = "中文：%s\nEnglish: %s" % [zh, en]


func _on_property_value_changed(path: Array, value: Variant) -> void:
	if _document.set_record_value(_current_section, _selected_record_index, path, value):
		_refresh_current_view(_selected_record_index)
	else:
		_update_inspector(_selected_record_index)
		_set_status("该字段修改被主键或字段规则拒绝。")


func _on_array_add(path: Array) -> void:
	if _document.append_array_value(_current_section, _selected_record_index, path):
		_refresh_current_view(_selected_record_index)


func _on_array_remove(path: Array, index: int) -> void:
	if _document.remove_array_value(_current_section, _selected_record_index, path, index):
		_refresh_current_view(_selected_record_index)


func _on_locale_submitted(text: String, locale_key: String, language: String) -> void:
	if _document.set_locale_value(locale_key, language, text):
		_update_inspector(_selected_record_index)


func _on_locale_focus_exited(editor: LineEdit, locale_key: String, language: String) -> void:
	if not is_instance_valid(editor):
		return
	var current: String = _document.locale_value(locale_key, language)
	if editor.text != current and _document.set_locale_value(locale_key, language, editor.text):
		_update_inspector(_selected_record_index)


func _show_create_dialog(mode: String) -> void:
	if _current_section == "$root":
		return
	_pending_create_mode = mode
	_id_edit.clear()
	_id_edit.placeholder_text = (
		"新 ID"
		if _document.primary_keys(_current_section).size() <= 1
		else "按主键顺序输入，使用 / 分隔"
	)
	_meaning_edit.clear()
	_id_dialog.dialog_text = ""
	_id_dialog.popup_centered(Vector2i(520, 220))
	_id_edit.grab_focus()


func _on_create_confirmed() -> void:
	var id_value: String = _id_edit.text.strip_edges()
	var primary_keys: Array[String] = _document.primary_keys(_current_section)
	if not primary_keys.is_empty() and id_value.is_empty():
		_show_errors("创建失败", {"errors": PackedStringArray(["必须填写主键。"])})
		return
	var copy_index: int = _selected_record_index if _pending_create_mode == "copy" else -1
	var new_index: int = _document.append_record(
		_current_section,
		id_value,
		copy_index,
		_meaning_edit.text.strip_edges()
	)
	if new_index < 0:
		_show_errors(
			"创建失败",
			{
				"errors": PackedStringArray(
					["主键格式不正确或已存在；复合键请按顺序使用 / 分隔。"]
				)
			}
		)
		return
	var preflight: Dictionary = DATA_TABLE_CONTRACT_BRIDGE.validate_changes(
		_document.pending_contract_changes
	)
	if not bool(preflight.get("ok", false)):
		_document.undo()
		_show_errors("契约登记预检失败", preflight)
		return
	_refresh_current_view(new_index)


func _request_delete() -> void:
	if _selected_record_index < 0:
		return
	var record_id: String = _document.record_identity(_current_section, _selected_record_index)
	var references: Array[Dictionary] = _search_index.references_to(
		record_id,
		_document.dataset_id(),
		_current_section,
		_selected_record_index
	)
	if not references.is_empty():
		var first: Dictionary = references[0]
		_show_errors(
			"无法删除：仍有跨表引用",
			{
				"errors": PackedStringArray(
					[
						"%s 被 %s / %s / %s 引用（共 %d 处）。" % [
							record_id,
							String(first.get("dataset_label", "")),
							String(first.get("record_id", "")),
							String(first.get("field_path_text", "")),
							references.size(),
						]
					]
				),
			}
		)
		return
	_pending_delete_index = _selected_record_index
	_delete_dialog.dialog_text = "确认删除记录 %s？专属文案与内容契约会在同一事务中清理。" % record_id
	_delete_dialog.popup_centered(Vector2i(580, 160))


func _on_delete_confirmed() -> void:
	var locale_keys: PackedStringArray = _unreferenced_locale_keys(
		_pending_delete_index
	)
	if _document.delete_record(_current_section, _pending_delete_index, locale_keys):
		_refresh_current_view(mini(_pending_delete_index, _document.records(_current_section).size() - 1))
	_pending_delete_index = -1


func _unreferenced_locale_keys(record_index: int) -> PackedStringArray:
	var output := PackedStringArray()
	var record_data: Dictionary = _document.record(_current_section, record_index)
	var raw_fields: Variant = _document.descriptor.get("locale_fields", [])
	if not raw_fields is Array:
		return output
	for raw_field: Variant in raw_fields as Array:
		var locale_key: String = String(record_data.get(String(raw_field), ""))
		if locale_key.is_empty():
			continue
		var used_by_open_document: bool = false
		for section: Dictionary in _document.section_descriptors():
			var section_path: String = String(section.get("path", ""))
			for other_index: int in range(_document.records(section_path).size()):
				if section_path == _current_section and other_index == record_index:
					continue
				var other_record: Dictionary = _document.record(section_path, other_index)
				for other_field: Variant in raw_fields as Array:
					if String(other_record.get(String(other_field), "")) == locale_key:
						used_by_open_document = true
						break
				if used_by_open_document:
					break
			if used_by_open_document:
				break
		if used_by_open_document:
			continue
		var references: Array[Dictionary] = _search_index.references_to(
			locale_key,
			_document.dataset_id(),
			_current_section,
			record_index
		)
		var has_other_content_reference: bool = false
		for reference: Dictionary in references:
			if (
				String(reference.get("dataset_id", "")) == "locale_strings"
				and String(reference.get("field_name", "")) == "keys"
			):
				continue
			has_other_content_reference = true
			break
		if not has_other_content_reference:
			output.append(locale_key)
	return output


func _save_current(allow_external_override: bool = false) -> void:
	if not _document.dirty:
		_set_status("没有需要保存的修改。")
		return
	if _document.disk_changed() and not allow_external_override:
		_conflict_dialog.popup_centered(Vector2i(680, 210))
		return
	var changes: Array[Dictionary] = _document.pending_contract_changes.duplicate(true)
	var preflight: Dictionary = DATA_TABLE_CONTRACT_BRIDGE.validate_changes(changes)
	if not bool(preflight.get("ok", false)):
		_show_errors("契约登记预检失败", preflight)
		return
	var extra_paths: Array[String] = []
	var hook := Callable()
	if not changes.is_empty():
		extra_paths = DATA_TABLE_CONTRACT_BRIDGE.transaction_snapshot_paths()
		hook = _apply_contract_changes.bind(changes)
	_set_status("正在执行可恢复保存与 headless 数据校验……")
	var result: Dictionary = _document.save_project(
		hook,
		extra_paths,
		allow_external_override
	)
	if not bool(result.get("ok", false)):
		_show_errors("保存失败，项目文件已回滚，草稿已保留", result)
		return
	_rebuild_search_index()
	_refresh_current_view(_selected_record_index)
	_set_status("保存成功；JSON/CSV、文案与契约已通过项目数据校验。")
	if editor_interface != null:
		editor_interface.get_resource_filesystem().scan()


func _apply_contract_changes(changes: Array[Dictionary]) -> Dictionary:
	return DATA_TABLE_CONTRACT_BRIDGE.apply_changes(changes)


func _on_reload_pressed() -> void:
	if _document.dirty:
		_document.discard_draft()
	_open_dataset_by_id(_document.dataset_id())


func _on_undo_pressed() -> void:
	if _document.undo():
		_refresh_current_view(_selected_record_index)


func _on_redo_pressed() -> void:
	if _document.redo():
		_refresh_current_view(_selected_record_index)


func _restore_current_draft() -> void:
	var allow_conflict: bool = bool(_draft_dialog.get_meta("allow_conflict", false))
	var result: Dictionary = _document.restore_draft(allow_conflict)
	if not bool(result.get("ok", false)):
		_show_errors("恢复草稿失败", result)
		return
	_refresh_current_view()
	_set_status("已恢复自动草稿；尚未写入项目文件。")


func _discard_current_draft() -> void:
	_document.discard_draft()
	_set_status("已放弃该数据集的自动草稿。")


func _on_document_changed() -> void:
	_update_action_state()
	_set_status("存在未保存修改；自动草稿已写入 user://data_table_editor/。")


func _update_action_state() -> void:
	_save_button.disabled = not _document.dirty
	_undo_button.disabled = not _document.has_undo()
	_redo_button.disabled = not _document.has_redo()
	var root_section: bool = _current_section == "$root"
	_new_button.disabled = root_section
	_copy_button.disabled = root_section or _selected_record_index < 0
	_delete_button.disabled = root_section or _selected_record_index < 0


func _rebuild_search_index() -> void:
	if _catalog == null or _search_index == null:
		return
	var result: Dictionary = _search_index.rebuild(_catalog)
	if not bool(result.get("ok", false)):
		_show_errors("全局搜索索引构建失败", result)
		return
	if _search_edit != null and not _search_edit.text.strip_edges().is_empty():
		_refresh_search_results(_search_edit.text)


func _refresh_search_results(text: String) -> void:
	var has_query: bool = not text.strip_edges().is_empty()
	_search_panel.visible = has_query
	_data_panel.visible = not has_query
	_search_results.clear()
	if not has_query:
		return
	var dataset_id: String = String(_dataset_filter.get_selected_metadata())
	var format_filter: String = String(_format_filter.get_selected_metadata())
	var type_filter: String = String(_type_filter.get_selected_metadata())
	var results: Array[Dictionary] = _search_index.query(
		text, dataset_id, format_filter, type_filter
	)
	var root: TreeItem = _search_results.create_item()
	for result: Dictionary in results:
		var item: TreeItem = _search_results.create_item(root)
		item.set_text(0, "%s (%s)" % [result.get("dataset_label", ""), result.get("format", "")])
		item.set_text(1, String(result.get("record_id", "")))
		item.set_text(2, String(result.get("field_path_text", "")))
		item.set_text(3, String(result.get("value_summary", "")))
		item.set_metadata(0, result)
	_set_status("全局搜索命中 %d 条字段。" % results.size())


func _on_search_filter_changed(_index: int) -> void:
	_refresh_search_results(_search_edit.text)


func _activate_search_result() -> void:
	var item: TreeItem = _search_results.get_selected()
	if item == null:
		return
	var metadata: Variant = item.get_metadata(0)
	if not metadata is Dictionary:
		return
	var result: Dictionary = metadata as Dictionary
	_search_edit.clear()
	_open_dataset_by_id(String(result.get("dataset_id", "")))
	_select_section(String(result.get("section_path", "")))
	var record_index: int = int(result.get("record_index", -1))
	_refresh_current_view(record_index)
	_property_editor.focus_path(result.get("field_path", []) as Array)


func _select_section(section_path: String) -> void:
	for index: int in range(_section_option.item_count):
		if String(_section_option.get_item_metadata(index)) == section_path:
			_section_option.select(index)
			_current_section = section_path
			return


func _show_raw_and_diff() -> void:
	var disk_text: String = ""
	var source_path: String = _document.source_path()
	if FileAccess.file_exists(source_path):
		var file: FileAccess = FileAccess.open(source_path, FileAccess.READ)
		if file != null:
			disk_text = file.get_as_text()
	var current_text: String = _document.source_text()
	_raw_text.text = "===== 磁盘原文（只读） =====\n%s\n===== 当前草稿 Diff（只读） =====\n%s" % [
		disk_text,
		_line_diff(disk_text, current_text),
	]
	_raw_dialog.popup_centered_ratio(0.86)


func _line_diff(before: String, after: String) -> String:
	if before == after:
		return "（无差异）"
	var before_lines: PackedStringArray = before.split("\n")
	var after_lines: PackedStringArray = after.split("\n")
	var output := PackedStringArray()
	var count: int = maxi(before_lines.size(), after_lines.size())
	for index: int in range(count):
		var old_line: String = before_lines[index] if index < before_lines.size() else ""
		var new_line: String = after_lines[index] if index < after_lines.size() else ""
		if old_line == new_line:
			continue
		output.append("- %4d | %s" % [index + 1, old_line])
		output.append("+ %4d | %s" % [index + 1, new_line])
		if output.size() >= 400:
			output.append("… Diff 过长，已截断 …")
			break
	return "\n".join(output)


func _on_filesystem_changed() -> void:
	refresh_from_disk_if_clean()


func _open_module_editor() -> void:
	if editor_interface != null:
		editor_interface.set_main_screen_editor(MODULE_SCREEN_NAME)


func _open_vfx_editor() -> void:
	if editor_interface != null:
		editor_interface.set_main_screen_editor(VFX_SCREEN_NAME)


func _show_errors(title: String, result: Dictionary) -> void:
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = "\n".join(errors) if not errors.is_empty() else title
	add_child(dialog)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(760, 260))
	_set_status(dialog.dialog_text)


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _scalar_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is bool:
		return "true" if value else "false"
	return str(value)
