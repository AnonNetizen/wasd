# Doc: docs/代码/debug_tools.md
# Authority: docs/游戏设计文档.md §9.20, docs/测试策略.md §5.10
extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")

const BOOT_FRAMES: int = 12
const RELEASE_SIM_FLAG: String = "--force-release-debug-tools-off"

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var release_sim: bool = OS.get_cmdline_user_args().has(RELEASE_SIM_FLAG)
	if release_sim:
		await _run_release_sim_smoke()
	else:
		await _run_debug_smoke()
	_finish(release_sim)


func _run_debug_smoke() -> void:
	var boot: Node = await _wait_for_node("FormalClientBoot")
	var run_loop: Node = await _wait_for_node("GameplayRunLoop")
	var console: Node = await _wait_for_node("DebugConsole")
	var registry: Node = await _wait_for_node("GMCommandRegistry")

	_expect(boot != null, "FormalClientBoot should exist")
	_expect(run_loop != null, "debug smoke should mount GameplayRunLoop")
	_expect(console != null, "debug smoke should mount DebugConsole")
	_expect(registry != null, "debug smoke should mount GMCommandRegistry")
	if boot == null or run_loop == null or console == null:
		return

	_expect(bool(boot.call("debug_tools_enabled")), "debug tools should be enabled in debug/dev_tools builds")
	_expect(console.has_method("execute_command_for_test"), "DebugConsole should expose test command execution")
	_expect(bool(console.call("has_registry_for_test")), "DebugConsole should own a GMCommandRegistry")
	_expect(InputService.action_resource(ACTIONS.DEBUG_TOGGLE_CONSOLE) != null, "InputService should expose debug_toggle_console")
	_expect(InputService.action_resource(ACTIONS.DEBUG_CLOSE_CONSOLE) != null, "InputService should expose debug_close_console")

	await _push_key_once(KEY_F1)
	_expect(bool(console.call("is_console_visible_for_test")), "DebugConsole should open from the GUIDE F1 binding")
	await _push_key_once(KEY_ESCAPE)
	_expect(not bool(console.call("is_console_visible_for_test")), "DebugConsole should close from the GUIDE Escape fallback")
	await _push_key_once(KEY_QUOTELEFT)
	_expect(bool(console.call("is_console_visible_for_test")), "DebugConsole should open from the GUIDE backquote binding")
	await _push_key_once(KEY_QUOTELEFT)
	_expect(not bool(console.call("is_console_visible_for_test")), "DebugConsole should toggle closed from the GUIDE backquote binding")

	var help_result: Dictionary = console.call("execute_command_for_test", "help")
	_expect(bool(help_result.get("ok", false)), "help command should succeed")
	_expect(String(help_result.get("message", "")).find("spawn") >= 0, "help should list spawn")
	_expect(bool(console.call("execute_command_for_test", "stats").get("ok", false)), "stats command should succeed")

	var before_spawn_summary: Dictionary = run_loop.call("debug_summary")
	var spawn_result: Dictionary = console.call("execute_command_for_test", "spawn enemy_chaser 2")
	await get_tree().process_frame
	var after_spawn_summary: Dictionary = run_loop.call("debug_summary")
	_expect(bool(spawn_result.get("ok", false)), "spawn command should succeed")
	_expect(
		int(after_spawn_summary.get("active_enemies", 0)) >= int(before_spawn_summary.get("active_enemies", 0)) + 2,
		"spawn command should add active enemies"
	)

	var before_gold: int = int(run_loop.call("gold_balance"))
	var gold_result: Dictionary = console.call("execute_command_for_test", "gold 5")
	_expect(bool(gold_result.get("ok", false)), "gold command should succeed")
	_expect(
		int(run_loop.call("gold_balance")) == before_gold + 5,
		"gold command should use runtime gold flow"
	)

	var before_damage_defense: float = _player_defense_total(run_loop)
	var damage_result: Dictionary = console.call("execute_command_for_test", "damage 1")
	_expect(bool(damage_result.get("ok", false)), "damage command should succeed")
	_expect(
		_player_defense_total(run_loop) < before_damage_defense,
		"damage command should reduce a player defense layer"
	)

	_expect(
		bool(console.call("execute_command_for_test", "hp 1").get("ok", false)),
		"hp command should prepare heal coverage"
	)
	var before_heal_life: float = _player_life(run_loop)
	var heal_result: Dictionary = console.call("execute_command_for_test", "heal 1")
	_expect(bool(heal_result.get("ok", false)), "heal command should succeed")
	_expect(_player_life(run_loop) > before_heal_life, "heal command should increase player life")

	var hp_result: Dictionary = console.call("execute_command_for_test", "hp 2")
	_expect(bool(hp_result.get("ok", false)), "hp command should succeed")
	_expect(is_equal_approx(_player_life(run_loop), 2.0), "hp command should set player life")

	var kill_result: Dictionary = console.call("execute_command_for_test", "kill_enemies")
	_expect(bool(kill_result.get("ok", false)), "kill_enemies command should succeed")
	var clear_result: Dictionary = console.call("execute_command_for_test", "clear_enemies")
	_expect(bool(clear_result.get("ok", false)), "clear_enemies command should succeed")


func _run_release_sim_smoke() -> void:
	var boot: Node = await _wait_for_node("FormalClientBoot")
	var run_loop: Node = await _wait_for_node("GameplayRunLoop")
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
	_expect(boot != null, "FormalClientBoot should exist in release simulation")
	_expect(run_loop != null, "release simulation should still mount GameplayRunLoop")
	if boot != null:
		_expect(not bool(boot.call("debug_tools_enabled")), "debug tools should be disabled by release simulation")
	_expect(_find_node_by_name(get_tree().root, "DebugConsole") == null, "release simulation should not mount DebugConsole")
	_expect(_find_node_by_name(get_tree().root, "GMCommandRegistry") == null, "release simulation should not mount GMCommandRegistry")
	_expect(not InputMap.has_action(ACTIONS.DEBUG_TOGGLE_CONSOLE), "release simulation should not add debug_toggle_console")


func _player_life(run_loop: Node) -> float:
	var summary: Dictionary = run_loop.call("debug_summary")
	return float(summary.get("player_life", 0.0))


func _player_defense_total(run_loop: Node) -> float:
	var summary: Dictionary = run_loop.call("debug_summary")
	return (
		float(summary.get("player_life", 0.0))
		+ float(summary.get("player_shield", 0.0))
		+ float(summary.get("player_overshield", 0.0))
	)


func _wait_for_node(target_name: String) -> Node:
	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame
		var node: Node = _find_node_by_name(get_tree().root, target_name)
		if node != null:
			return node
	return null


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _push_key_once(keycode: Key) -> void:
	var pressed: InputEventKey = InputEventKey.new()
	pressed.keycode = keycode
	pressed.physical_keycode = keycode
	pressed.pressed = true
	InputService.debug_inject_input(pressed)
	await get_tree().process_frame
	await get_tree().physics_frame
	var released: InputEventKey = InputEventKey.new()
	released.keycode = keycode
	released.physical_keycode = keycode
	released.pressed = false
	InputService.debug_inject_input(released)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[DebugToolsSmoke] %s" % message)


func _finish(release_sim: bool) -> void:
	if _failures.is_empty():
		print("[DebugToolsSmoke] passed; release_sim=%s" % str(release_sim))
		get_tree().quit(0)
		return
	print("[DebugToolsSmoke] failed; release_sim=%s failures=%d" % [str(release_sim), _failures.size()])
	get_tree().quit(1)
