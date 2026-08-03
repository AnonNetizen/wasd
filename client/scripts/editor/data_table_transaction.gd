# Doc: docs/代码/data_table_editor.md
@tool
class_name DataTableTransaction
extends RefCounted
## Crash-recoverable multi-file transaction for editor-owned data sources.

const VALIDATION_BRIDGE := preload(
	"res://scripts/editor/project_data_validation_bridge.gd"
)
const TRANSACTION_ROOT: String = "user://data_table_editor/transaction"
const BACKUP_DIRECTORY: String = TRANSACTION_ROOT + "/backups"
const JOURNAL_PATH: String = TRANSACTION_ROOT + "/journal.json"
const TEMP_SUFFIX: String = ".data_table_editor.tmp"


static func commit_texts(
	writes: Dictionary,
	expected_hashes: Dictionary = {},
	extra_snapshot_paths: Array[String] = [],
	before_validate: Callable = Callable()
) -> Dictionary:
	if writes.is_empty():
		return _error_result("transaction has no writes")
	var recovery: Dictionary = recover_pending_transaction()
	if not bool(recovery.get("ok", false)):
		return recovery
	for raw_path: Variant in writes.keys():
		var path: String = String(raw_path)
		var expected_hash: String = String(expected_hashes.get(path, ""))
		if not expected_hash.is_empty() and _disk_hash(path) != expected_hash:
			return _error_result(
				"source changed on disk; reload before saving: %s" % path
			)
	var paths: Array[String] = []
	for raw_path: Variant in writes.keys():
		paths.append(String(raw_path))
	for path: String in extra_snapshot_paths:
		if not paths.has(path):
			paths.append(path)
	paths.sort()
	var snapshot_result: Dictionary = _snapshot_paths(paths)
	if not bool(snapshot_result.get("ok", false)):
		return snapshot_result
	var entries: Array = snapshot_result.get("entries", []) as Array
	var stage_error: String = _stage_writes(writes)
	if not stage_error.is_empty():
		_restore_entries(entries)
		_cleanup_transaction(entries)
		return _error_result(stage_error)
	var promote_error: String = _promote_writes(writes)
	if not promote_error.is_empty():
		_restore_entries(entries)
		_cleanup_transaction(entries)
		return _error_result(promote_error)
	if before_validate.is_valid():
		var hook_result: Variant = before_validate.call()
		if not hook_result is Dictionary or not bool(
			(hook_result as Dictionary).get("ok", false)
		):
			_restore_entries(entries)
			_cleanup_transaction(entries)
			if hook_result is Dictionary:
				return hook_result as Dictionary
			return _error_result("pre-validation transaction hook failed")
	var validation: Dictionary = VALIDATION_BRIDGE.validate_project_data(true)
	if not bool(validation.get("ok", false)):
		var restore_errors: PackedStringArray = _restore_entries(entries)
		_cleanup_transaction(entries)
		if not restore_errors.is_empty():
			var errors: PackedStringArray = validation.get(
				"errors", PackedStringArray()
			)
			for error: String in restore_errors:
				errors.append("rollback: %s" % error)
			validation["errors"] = errors
		return validation
	_cleanup_transaction(entries)
	return _success_result()


static func recover_pending_transaction() -> Dictionary:
	if not FileAccess.file_exists(JOURNAL_PATH):
		return _success_result()
	var journal_file: FileAccess = FileAccess.open(JOURNAL_PATH, FileAccess.READ)
	if journal_file == null:
		return _error_result("failed to open pending transaction journal")
	var parsed: Variant = JSON.parse_string(journal_file.get_as_text())
	if not parsed is Dictionary:
		return _error_result("pending transaction journal is invalid")
	var entries_value: Variant = (parsed as Dictionary).get("entries", [])
	if not entries_value is Array:
		return _error_result("pending transaction journal entries are invalid")
	var errors: PackedStringArray = _restore_entries(entries_value as Array)
	_cleanup_transaction(entries_value as Array)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	return _success_result()


static func _snapshot_paths(paths: Array[String]) -> Dictionary:
	var make_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(BACKUP_DIRECTORY)
	)
	if make_error != OK:
		return _error_result("failed to create transaction backup directory")
	var entries: Array[Dictionary] = []
	for path: String in paths:
		var existed: bool = FileAccess.file_exists(path)
		var backup_path: String = BACKUP_DIRECTORY.path_join(
			"%s.bak" % path.sha256_text()
		)
		if existed:
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
			var backup: FileAccess = FileAccess.open(backup_path, FileAccess.WRITE)
			if backup == null:
				_cleanup_transaction(entries)
				return _error_result("failed to back up transaction target: %s" % path)
			backup.store_buffer(bytes)
			backup.close()
		entries.append(
			{
				"path": path,
				"backup_path": backup_path,
				"existed": existed,
			}
		)
	var journal: FileAccess = FileAccess.open(JOURNAL_PATH, FileAccess.WRITE)
	if journal == null:
		_cleanup_transaction(entries)
		return _error_result("failed to write transaction journal")
	journal.store_string(
		JSON.stringify({"schema_version": 1, "entries": entries}, "  ") + "\n"
	)
	journal.close()
	return {"ok": true, "errors": PackedStringArray(), "entries": entries}


static func _stage_writes(writes: Dictionary) -> String:
	for raw_path: Variant in writes.keys():
		var path: String = String(raw_path)
		var temporary_path: String = path + TEMP_SUFFIX
		_remove_if_exists(temporary_path)
		var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
		if file == null:
			_remove_staged_files(writes)
			return "failed to stage transaction target: %s" % path
		file.store_string(String(writes[raw_path]))
		file.close()
	return ""


static func _promote_writes(writes: Dictionary) -> String:
	for raw_path: Variant in writes.keys():
		var path: String = String(raw_path)
		if FileAccess.file_exists(path):
			var remove_error: Error = DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path)
			)
			if remove_error != OK:
				return "failed to replace transaction target %s (error %d)" % [
					path,
					remove_error,
				]
		var rename_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path + TEMP_SUFFIX),
			ProjectSettings.globalize_path(path)
		)
		if rename_error != OK:
			return "failed to promote transaction target %s (error %d)" % [
				path,
				rename_error,
			]
	return ""


static func _restore_entries(entries: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var path: String = String(entry.get("path", ""))
		var backup_path: String = String(entry.get("backup_path", ""))
		var existed: bool = bool(entry.get("existed", false))
		_remove_if_exists(path + TEMP_SUFFIX)
		if FileAccess.file_exists(path):
			var remove_error: Error = DirAccess.remove_absolute(
				ProjectSettings.globalize_path(path)
			)
			if remove_error != OK:
				errors.append("failed to remove %s (error %d)" % [path, remove_error])
				continue
		if not existed:
			continue
		if not FileAccess.file_exists(backup_path):
			errors.append("missing backup for %s" % path)
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(backup_path)
		var restore: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if restore == null:
			errors.append("failed to restore %s" % path)
			continue
		restore.store_buffer(bytes)
		restore.close()
	return errors


static func _cleanup_transaction(entries: Array) -> void:
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		_remove_if_exists(String(entry.get("backup_path", "")))
		_remove_if_exists(String(entry.get("path", "")) + TEMP_SUFFIX)
	_remove_if_exists(JOURNAL_PATH)


static func _remove_staged_files(writes: Dictionary) -> void:
	for raw_path: Variant in writes.keys():
		_remove_if_exists(String(raw_path) + TEMP_SUFFIX)


static func _remove_if_exists(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _disk_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_sha256(path)


static func _success_result() -> Dictionary:
	return {"ok": true, "errors": PackedStringArray()}


static func _error_result(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
