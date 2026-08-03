# Doc: docs/代码/data_table_editor.md
@tool
class_name DataTableContractBridge
extends RefCounted
## Restricted bridge for content-id registration through tools/sync_contracts.py.

const CONTRACT_DOC_RELATIVE: String = "docs/词表与契约.md"
const CONTRACTS_JSON: String = "res://data/_contracts.json"
const CONTRACTS_DIRECTORY: String = "res://scripts/contracts"
const SYNC_TOOL_RELATIVE: String = "tools/sync_contracts.py"


static func validate_changes(changes: Array[Dictionary]) -> Dictionary:
	for change: Dictionary in changes:
		var result: Dictionary = _run_change(change, true)
		if not bool(result.get("ok", false)):
			return result
	return _success_result()


static func apply_changes(changes: Array[Dictionary]) -> Dictionary:
	for change: Dictionary in changes:
		var result: Dictionary = _run_change(change, false)
		if not bool(result.get("ok", false)):
			return result
	return _success_result()


static func transaction_snapshot_paths() -> Array[String]:
	var paths: Array[String] = [_repository_path(CONTRACT_DOC_RELATIVE), CONTRACTS_JSON]
	var directory: DirAccess = DirAccess.open(CONTRACTS_DIRECTORY)
	if directory == null:
		return paths
	directory.list_dir_begin()
	var file_name: String = directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(".gd"):
			paths.append(CONTRACTS_DIRECTORY.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	return paths


static func _run_change(change: Dictionary, dry_run: bool) -> Dictionary:
	var action: String = String(change.get("action", ""))
	var contract_key: String = String(change.get("contract_key", ""))
	var content_id: String = String(change.get("id", ""))
	if action != "register" and action != "unregister":
		return _error_result("unsupported contract action: %s" % action)
	if contract_key.is_empty() or content_id.is_empty():
		return _error_result("contract key and id are required")
	var tool_path: String = _repository_path(SYNC_TOOL_RELATIVE)
	if not FileAccess.file_exists(tool_path):
		return _error_result("missing contract sync tool: %s" % tool_path)
	var arguments := PackedStringArray()
	if action == "register":
		arguments.append_array(
			[
				tool_path,
				"--register",
				contract_key,
				content_id,
				"--meaning",
				String(change.get("meaning", content_id)),
			]
		)
	else:
		arguments.append_array([tool_path, "--unregister", contract_key, content_id])
	if dry_run:
		arguments.append("--dry-run")
	var execution: Dictionary = _execute_python(arguments)
	if bool(execution.get("ok", false)):
		return execution
	return _error_result(String(execution.get("output", "contract sync failed")))


static func _execute_python(arguments: PackedStringArray) -> Dictionary:
	var candidates: Array[Dictionary] = [
		{"executable": "py", "prefix": PackedStringArray(["-3"])},
		{"executable": "python", "prefix": PackedStringArray()},
		{"executable": "python3", "prefix": PackedStringArray()},
	]
	var last_output: String = "Python 3 was not found"
	for candidate: Dictionary in candidates:
		var process_arguments: PackedStringArray = candidate.get(
			"prefix", PackedStringArray()
		) as PackedStringArray
		process_arguments.append_array(arguments)
		var output: Array = []
		var exit_code: int = OS.execute(
			String(candidate.get("executable", "")),
			process_arguments,
			output,
			true,
			false
		)
		last_output = "\n".join(PackedStringArray(output)).strip_edges()
		if exit_code == 0:
			return {
				"ok": true,
				"errors": PackedStringArray(),
				"output": last_output,
			}
		if exit_code != -1:
			return {"ok": false, "output": last_output}
	return {"ok": false, "output": last_output}


static func _repository_path(relative_path: String) -> String:
	var client_path: String = ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	return client_path.get_base_dir().path_join(relative_path).simplify_path()


static func _success_result() -> Dictionary:
	return {"ok": true, "errors": PackedStringArray()}


static func _error_result(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
