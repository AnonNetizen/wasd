# Doc: docs/代码/module_authoring_pipeline.md
extends SceneTree
## Editor-only headless bridge to the runtime DataLoader validation contract.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader: Node = root.get_node_or_null("DataLoader")
	if loader == null:
		printerr(
			"[module-authoring] DataLoader autoload is unavailable in "
			+ "the headless validation process."
		)
		quit(2)
		return
	if not loader.has_method("validate_project_data"):
		printerr(
			"[module-authoring] DataLoader.validate_project_data() is unavailable."
		)
		quit(2)
		return
	var is_valid: bool = bool(loader.call("validate_project_data"))
	print(
		"[module-authoring] project_data_validation_ok=%s"
		% str(is_valid).to_lower()
	)
	quit(0 if is_valid else 1)
