# Doc: docs/代码/data_table_editor.md
# Doc: docs/代码/module_authoring_pipeline.md
extends SceneTree
## Headless bridge to the runtime DataLoader validation contract.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader: Node = root.get_node_or_null("DataLoader")
	if loader == null:
		printerr("[project-data-validation] DataLoader autoload is unavailable.")
		quit(2)
		return
	if not loader.has_method("validate_project_data"):
		printerr(
			"[project-data-validation] DataLoader.validate_project_data() is unavailable."
		)
		quit(2)
		return
	var is_valid: bool = bool(loader.call("validate_project_data"))
	print(
		"[project-data-validation] project_data_validation_ok=%s"
		% str(is_valid).to_lower()
	)
	quit(0 if is_valid else 1)
