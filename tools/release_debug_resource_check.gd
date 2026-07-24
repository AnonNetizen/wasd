extends SceneTree


const FORBIDDEN_DIRECTORIES: Array[String] = [
	"res://scenes/debug",
	"res://scripts/debug",
]
const FORBIDDEN_FILES: Array[String] = [
	"res://tools/debug_test_arena_smoke.gd",
	"res://tools/debug_tools_smoke.gd",
]
const SUCCESS_MARKER: String = "RELEASE DEBUG RESOURCE CHECK PASS"


func _initialize() -> void:
	var failures: Array[String] = []
	for path: String in FORBIDDEN_DIRECTORIES:
		if DirAccess.dir_exists_absolute(path):
			failures.append(path)
	for path: String in FORBIDDEN_FILES:
		if (
			FileAccess.file_exists(path)
			or ResourceLoader.exists(path)
		):
			failures.append(path)
	if failures.is_empty():
		print(SUCCESS_MARKER)
		quit(0)
		return
	for path: String in failures:
		push_error(
			"[ReleaseDebugResourceCheck] exported debug resource: %s"
			% path
		)
	quit(1)
