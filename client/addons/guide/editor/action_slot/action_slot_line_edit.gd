@tool
extends LineEdit

signal action_dropped(action:GUIDEAction)


func _can_drop_data(at_position:Vector2, data:Variant) -> bool:
	if not data is Dictionary:
		return false

	if data.has("files"):
		for file in data["files"]:
			if ResourceLoader.load(file) is GUIDEAction:
				return true

	return false


func _drop_data(at_position:Vector2, data:Variant) -> void:
	for file in data["files"]:
		var item:Resource = ResourceLoader.load(file)
		if item is GUIDEAction:
			action_dropped.emit(item)
