# Doc: docs/代码/data_table_editor.md
@tool
class_name DataTablePropertyEditor
extends VBoxContainer
## Recursive fallback editor for nested dictionaries, arrays, and scalar values.

signal value_changed(path: Array, value: Variant)
signal array_value_added(path: Array)
signal array_value_removed(path: Array, index: int)

const ADD_BUTTON_ID: int = 1
const REMOVE_BUTTON_ID: int = 2

var _tree: Tree
var _record: Dictionary = {}
var _options_by_path: Dictionary = {}
var _updating: bool = false


func _ready() -> void:
	if _tree != null:
		return
	_tree = Tree.new()
	_tree.name = "PropertyTree"
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "字段")
	_tree.set_column_title(1, "类型")
	_tree.set_column_title(2, "值")
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 72)
	_tree.set_column_expand(2, true)
	_tree.item_edited.connect(_on_item_edited)
	_tree.button_clicked.connect(_on_button_clicked)
	add_child(_tree)
	refresh({})


func refresh(record_data: Dictionary, options_by_path: Dictionary = {}) -> void:
	_record = record_data
	_options_by_path = options_by_path.duplicate(true)
	if _tree == null:
		return
	_updating = true
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	root.set_text(0, "记录")
	root.set_metadata(0, [])
	var keys: Array = record_data.keys()
	keys.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
	for key: Variant in keys:
		_add_value(root, String(key), record_data[key], [String(key)])
	root.set_collapsed(false)
	_updating = false


func focus_path(path: Array) -> bool:
	if _tree == null:
		return false
	var item: TreeItem = _tree.get_root()
	if item == null:
		return false
	return _focus_path_recursive(item, path)


func _add_value(parent: TreeItem, label: String, value: Variant, path: Array) -> void:
	var item: TreeItem = _tree.create_item(parent)
	item.set_text(0, label)
	item.set_metadata(0, path.duplicate())
	item.set_text(1, _type_name(value))
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array = dictionary.keys()
		keys.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
		for key: Variant in keys:
			var child_path: Array = path.duplicate()
			child_path.append(String(key))
			_add_value(item, String(key), dictionary[key], child_path)
		return
	if value is Array:
		var values: Array = value as Array
		item.set_text(2, "%d 项" % values.size())
		item.add_button(2, get_theme_icon(&"Add", &"EditorIcons"), ADD_BUTTON_ID, false, "新增数组项")
		for index: int in range(values.size()):
			var child_path: Array = path.duplicate()
			child_path.append(index)
			_add_value(item, "[%d]" % index, values[index], child_path)
			var child: TreeItem = item.get_child(index)
			if child != null:
				var child_metadata: Dictionary = {}
				var raw_metadata: Variant = child.get_metadata(2)
				if raw_metadata is Dictionary:
					child_metadata = (raw_metadata as Dictionary).duplicate(true)
				child_metadata["array_path"] = path.duplicate()
				child_metadata["array_index"] = index
				child.set_metadata(2, child_metadata)
				child.add_button(
					2,
					get_theme_icon(&"Remove", &"EditorIcons"),
					REMOVE_BUTTON_ID,
					false,
					"删除数组项"
				)
		return
	item.set_text(2, _scalar_text(value))
	var metadata: Dictionary = {"path": path.duplicate(), "original": value}
	var options: PackedStringArray = _options_for_path(path)
	if not options.is_empty():
		var selected_index: int = options.find(String(value))
		if selected_index < 0:
			options.append(String(value))
			selected_index = options.size() - 1
		metadata["options"] = options
		item.set_cell_mode(2, TreeItem.CELL_MODE_RANGE)
		item.set_text(2, ",".join(options))
		item.set_range_config(2, 0.0, float(options.size() - 1), 1.0)
		item.set_range(2, selected_index)
	item.set_metadata(2, metadata)
	item.set_editable(2, true)
	if options.is_empty() and value is bool:
		item.set_cell_mode(2, TreeItem.CELL_MODE_CHECK)
		item.set_checked(2, value)


func _on_item_edited() -> void:
	if _updating or _tree == null:
		return
	var item: TreeItem = _tree.get_edited()
	if item == null or _tree.get_edited_column() != 2:
		return
	var metadata: Variant = item.get_metadata(2)
	if not metadata is Dictionary:
		return
	var details: Dictionary = metadata as Dictionary
	if not details.has("path"):
		return
	var original: Variant = details.get("original")
	var value: Variant
	var raw_options: Variant = details.get("options", PackedStringArray())
	if raw_options is PackedStringArray and not (raw_options as PackedStringArray).is_empty():
		var options: PackedStringArray = raw_options as PackedStringArray
		var selected_index: int = clampi(int(item.get_range(2)), 0, options.size() - 1)
		value = options[selected_index]
	else:
		value = item.is_checked(2) if original is bool else item.get_text(2)
	value_changed.emit((details.get("path", []) as Array).duplicate(), value)


func _on_button_clicked(item: TreeItem, column: int, id: int, _mouse_button: int) -> void:
	if column != 2:
		return
	if id == ADD_BUTTON_ID:
		var path: Variant = item.get_metadata(0)
		if path is Array:
			array_value_added.emit((path as Array).duplicate())
		return
	if id != REMOVE_BUTTON_ID:
		return
	var metadata: Variant = item.get_metadata(2)
	if not metadata is Dictionary:
		return
	var details: Dictionary = metadata as Dictionary
	array_value_removed.emit(
		(details.get("array_path", []) as Array).duplicate(),
		int(details.get("array_index", -1))
	)


func _focus_path_recursive(item: TreeItem, path: Array) -> bool:
	var metadata: Variant = item.get_metadata(0)
	if metadata is Array and metadata == path:
		_tree.set_selected(item, 2)
		item.select(2)
		item.set_collapsed(false)
		_tree.scroll_to_item(item, true)
		return true
	var child: TreeItem = item.get_first_child()
	while child != null:
		if _focus_path_recursive(child, path):
			item.set_collapsed(false)
			return true
		child = child.get_next()
	return false


func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			return "对象"
		TYPE_ARRAY:
			return "数组"
		TYPE_BOOL:
			return "布尔"
		TYPE_INT:
			return "整数"
		TYPE_FLOAT:
			return "小数"
		TYPE_STRING:
			return "文本"
		TYPE_NIL:
			return "空值"
		_:
			return type_string(typeof(value))


func _options_for_path(path: Array) -> PackedStringArray:
	var normalized: String = ""
	for segment: Variant in path:
		if segment is int:
			normalized += "[]"
		elif normalized.is_empty():
			normalized = String(segment)
		else:
			normalized += ".%s" % String(segment)
	var raw_options: Variant = _options_by_path.get(normalized, PackedStringArray())
	if raw_options is PackedStringArray:
		return (raw_options as PackedStringArray).duplicate()
	if raw_options is Array:
		return PackedStringArray(raw_options)
	return PackedStringArray()


func _scalar_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	return str(value)
