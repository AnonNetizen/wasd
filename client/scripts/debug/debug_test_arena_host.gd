# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159 / #160
class_name DebugTestArenaHost
extends Node


signal debug_exit_completed()

const CONFIG_SCRIPT_PATH: String = (
	"res://scripts/debug/debug_test_arena_config.gd"
)
const RUN_SCENE_PATH: String = (
	"res://scenes/debug/debug_test_arena_run.tscn"
)
const SETUP_SCENE_PATH: String = (
	"res://scenes/debug/debug_test_arena_setup.tscn"
)
const SMOKE_SCRIPT_PATH: String = (
	"res://tools/debug_test_arena_smoke.gd"
)
const SMOKE_ARGUMENT: String = "--debug-test-arena-smoke"

var _analytics_enabled_before: bool = false
var _config_manager: RefCounted = null
var _exit_completed: bool = false
var _replay_enabled_before: bool = false
var _run_loop: Node = null
var _services_suspended: bool = false
var _setup: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _debug_tools_enabled():
		push_error(
			"[DebugTestArenaHost] standalone scene requires a "
			+ "debug or dev_tools build"
		)
		get_tree().quit(1)
		return
	if not DataLoader.validate_project_data():
		push_error(
			"[DebugTestArenaHost] formal project data validation failed"
		)
		get_tree().quit(1)
		return
	var config_script: GDScript = load(CONFIG_SCRIPT_PATH) as GDScript
	if config_script == null:
		push_error(
			"[DebugTestArenaHost] missing configuration script"
		)
		get_tree().quit(1)
		return
	_config_manager = config_script.new() as RefCounted
	if _config_manager == null:
		push_error(
			"[DebugTestArenaHost] invalid configuration manager"
		)
		get_tree().quit(1)
		return
	_suspend_services()
	_show_setup()
	if _is_smoke_enabled():
		_install_smoke_runner()


func _exit_tree() -> void:
	UIManager.clear(true)
	_clear_run_loop()
	_restore_services()


func debug_active_run_loop() -> Node:
	if _run_loop != null and is_instance_valid(_run_loop):
		return _run_loop
	return null


func debug_active_setup() -> CanvasLayer:
	if _setup != null and is_instance_valid(_setup):
		return _setup
	return null


func debug_exit_is_completed() -> bool:
	return _exit_completed


func debug_service_state_before() -> Dictionary:
	return {
		"analytics_enabled": _analytics_enabled_before,
		"replay_enabled": _replay_enabled_before,
	}


func debug_start_test_arena_for_smoke(config: Dictionary) -> bool:
	if not _is_smoke_enabled() or _config_manager == null:
		return false
	_start_run(config)
	return _run_loop != null


func _show_setup() -> void:
	_clear_run_loop()
	UIManager.clear(true)
	GameState.change_state(
		GameState.MAIN_MENU,
		{"source": "debug_test_arena_host"}
	)
	var setup_scene: PackedScene = load(SETUP_SCENE_PATH) as PackedScene
	if setup_scene == null:
		push_error("[DebugTestArenaHost] missing setup scene")
		_request_exit(1)
		return
	_setup = UIManager.push(
		setup_scene,
		{"source": "debug_test_arena_host"}
	) as CanvasLayer
	if _setup == null:
		push_error("[DebugTestArenaHost] failed to open setup scene")
		_request_exit(1)
		return
	_setup.connect(
		"start_requested",
		Callable(self, "_on_setup_start_requested"),
		CONNECT_ONE_SHOT
	)
	_setup.connect(
		"closed_requested",
		Callable(self, "_on_setup_closed_requested"),
		CONNECT_ONE_SHOT
	)


func _start_run(config: Dictionary) -> void:
	if _config_manager == null:
		push_error("[DebugTestArenaHost] configuration is unavailable")
		return
	var normalized: Dictionary = _config_manager.call(
		"normalize_config",
		config
	) as Dictionary
	var run_seed: int = maxi(int(normalized.get("seed", 1)), 1)
	var run_scene: PackedScene = load(RUN_SCENE_PATH) as PackedScene
	if run_scene == null:
		push_error("[DebugTestArenaHost] missing runtime scene")
		return
	var next_run_loop: Node = run_scene.instantiate()
	if next_run_loop == null:
		push_error("[DebugTestArenaHost] failed to instantiate runtime")
		return
	if not next_run_loop.has_method("configure_debug_test_arena"):
		next_run_loop.queue_free()
		push_error(
			"[DebugTestArenaHost] runtime lacks arena configuration API"
		)
		return

	_clear_run_loop()
	UIManager.clear(true)
	_setup = null
	_exit_completed = false
	RNG.set_run_seed(run_seed)
	GameState.change_state(
		GameState.LOADING,
		{"source": "debug_test_arena_host"}
	)
	_run_loop = next_run_loop
	_run_loop.call("configure_debug_test_arena", normalized)
	_run_loop.connect(
		"debug_test_arena_setup_requested",
		Callable(self, "_on_run_setup_requested")
	)
	_run_loop.connect(
		"debug_test_arena_exit_requested",
		Callable(self, "_on_run_exit_requested")
	)
	add_child(_run_loop)
	print(
		"[DebugTestArenaHost] standalone arena started; seed=%d"
		% run_seed
	)


func _clear_run_loop() -> void:
	if _run_loop != null and is_instance_valid(_run_loop):
		var parent: Node = _run_loop.get_parent()
		if parent != null:
			parent.remove_child(_run_loop)
		_run_loop.queue_free()
	_run_loop = null
	PoolManager.clear_all()


func _request_exit(exit_code: int = 0) -> void:
	if _exit_completed:
		return
	UIManager.clear(true)
	_setup = null
	_clear_run_loop()
	_restore_services()
	_exit_completed = true
	debug_exit_completed.emit()
	if _is_smoke_enabled():
		return
	get_tree().quit(exit_code)


func _suspend_services() -> void:
	if _services_suspended:
		return
	_replay_enabled_before = Replay.is_enabled()
	_analytics_enabled_before = Analytics.is_enabled()
	Replay.set_enabled(false)
	Analytics.set_enabled(false)
	_services_suspended = true


func _restore_services() -> void:
	if not _services_suspended:
		return
	Replay.set_enabled(_replay_enabled_before)
	Analytics.set_enabled(_analytics_enabled_before)
	_services_suspended = false


func _install_smoke_runner() -> void:
	var smoke_script: GDScript = load(SMOKE_SCRIPT_PATH) as GDScript
	if smoke_script == null:
		push_error("[DebugTestArenaHost] missing smoke runner")
		_request_exit(1)
		return
	var smoke_runner: Node = smoke_script.new() as Node
	if smoke_runner == null:
		push_error("[DebugTestArenaHost] invalid smoke runner")
		_request_exit(1)
		return
	smoke_runner.name = "DebugTestArenaSmoke"
	add_child(smoke_runner)


func _debug_tools_enabled() -> bool:
	return OS.is_debug_build() or OS.has_feature("dev_tools")


func _is_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has(SMOKE_ARGUMENT)


func _on_setup_start_requested(config: Dictionary) -> void:
	_start_run(config)


func _on_setup_closed_requested() -> void:
	_setup = null
	_request_exit()


func _on_run_setup_requested() -> void:
	call_deferred("_show_setup")


func _on_run_exit_requested() -> void:
	call_deferred("_request_exit")
