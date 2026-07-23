extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const MAX_WAIT_FRAMES: int = 600

var _failures: Array[String] = []
var _had_run_save: bool = false
var _run_save_backup: Dictionary = {}
var _smoke_broken_paths: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SaveManager.save_corrupted.connect(_on_save_corrupted)
	_backup_run_save()

	var title_menu: Node = await _wait_for_node("TitleMenu")
	if not _expect_node(title_menu, "title menu should be visible before loading smoke"):
		_finish()
		return
	var start_button: Button = title_menu.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/StartButton"
	) as Button
	if not _expect_node(start_button, "title menu should expose StartButton"):
		_finish()
		return
	start_button.pressed.emit()
	await _expect_loading_visible("start")
	var boot: Node = _find_node_by_name(get_tree().root, "FormalClientBoot")
	if boot != null:
		boot.call("_on_title_start_requested")
	_expect(_count_nodes_by_name(get_tree().root, "LoadingScreen") == 1, "duplicate start should keep one loading screen")
	var first_run: Node = await _wait_for_playing_run()
	if not _expect_node(first_run, "start should finish with one playable run"):
		_finish()
		return
	_expect(_count_nodes_by_name(get_tree().root, "GameplayRunLoop") == 1, "start should mount one GameplayRunLoop")

	var first_snapshot: Dictionary = first_run.call("create_run_snapshot")
	_expect(
		SaveManager.save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN, first_snapshot),
		"loading smoke should save a valid run for continue"
	)
	first_run.emit_signal("quit_to_title_requested")
	title_menu = await _wait_for_node("TitleMenu")
	if not _expect_node(title_menu, "quit to title should restore TitleMenu"):
		_finish()
		return
	var continue_button: Button = title_menu.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ContinueRunButton"
	) as Button
	if not _expect_node(continue_button, "title menu should expose ContinueRunButton"):
		_finish()
		return
	_expect(continue_button.visible and not continue_button.disabled, "valid run should enable continue")
	continue_button.pressed.emit()
	await _expect_loading_visible("continue")
	var continued_run: Node = await _wait_for_playing_run()
	if not _expect_node(continued_run, "continue should finish with one playable run"):
		_finish()
		return
	_expect(
		RNG.run_seed() == int(first_snapshot.get("rng", {}).get("run_seed", 0)),
		"continue should restore the saved run seed"
	)

	continued_run.emit_signal("restart_requested")
	await _expect_loading_visible("restart")
	var restarted_run: Node = await _wait_for_playing_run()
	if not _expect_node(restarted_run, "restart should finish with one playable run"):
		_finish()
		return
	_expect(_count_nodes_by_name(get_tree().root, "GameplayRunLoop") == 1, "restart should replace the old run")

	var invalid_snapshot: Dictionary = restarted_run.call("create_run_snapshot")
	invalid_snapshot["character"] = "missing_loading_smoke_character"
	_expect(
		SaveManager.save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN, invalid_snapshot),
		"loading smoke should save an invalid character snapshot"
	)
	restarted_run.emit_signal("quit_to_title_requested")
	title_menu = await _wait_for_node("TitleMenu")
	if not _expect_node(title_menu, "invalid restore setup should return to title"):
		_finish()
		return
	continue_button = title_menu.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ContinueRunButton"
	) as Button
	if not _expect_node(continue_button, "invalid restore setup should expose ContinueRunButton"):
		_finish()
		return
	continue_button.pressed.emit()
	await _expect_loading_visible("invalid continue")
	title_menu = await _wait_for_node("TitleMenu")
	_expect(title_menu != null, "prepare failure should return to title")
	_expect(GameState.is_state(GameState.MAIN_MENU), "prepare failure should restore MAIN_MENU")
	_expect(_count_nodes_by_name(get_tree().root, "LoadingScreen") == 0, "prepare failure should remove LoadingScreen")
	_expect(_count_nodes_by_name(get_tree().root, "GameplayRunLoop") == 0, "prepare failure should remove partial run")
	_expect(not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), "prepare failure should delete invalid run")

	_write_corrupt_run_save()
	if boot != null:
		boot.call("_show_title_menu")
	title_menu = await _wait_for_node("TitleMenu")
	if not _expect_node(title_menu, "corrupted restore setup should show TitleMenu"):
		_finish()
		return
	continue_button = title_menu.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ContinueRunButton"
	) as Button
	if not _expect_node(continue_button, "corrupted restore setup should expose ContinueRunButton"):
		_finish()
		return
	_expect(continue_button.visible and not continue_button.disabled, "corrupted run file should offer continue before validation")
	continue_button.pressed.emit()
	await _expect_loading_visible("corrupted continue")
	title_menu = await _wait_for_node("TitleMenu")
	_expect(title_menu != null, "corrupted run should return to title")
	_expect(GameState.is_state(GameState.MAIN_MENU), "corrupted run should restore MAIN_MENU")
	_expect(_count_nodes_by_name(get_tree().root, "LoadingScreen") == 0, "corrupted run should remove LoadingScreen")
	_expect(_count_nodes_by_name(get_tree().root, "GameplayRunLoop") == 0, "corrupted run should not mount GameplayRunLoop")
	_expect(not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), "corrupted run should be isolated from the slot")

	_finish()


func _expect_loading_visible(source: String) -> void:
	var loading_screen: Node = UIManager.top()
	_expect(
		loading_screen != null and loading_screen.name == "LoadingScreen",
		"%s should show LoadingScreen immediately" % source
	)
	_expect(GameState.is_state(GameState.LOADING), "%s should enter LOADING" % source)
	_expect(
		_count_nodes_by_name(get_tree().root, "LoadingScreen") == 1,
		"%s should mount exactly one LoadingScreen" % source
	)
	if loading_screen == null:
		return
	var root_control: Control = loading_screen.get_node_or_null("Root") as Control
	_expect(
		root_control != null and root_control.mouse_filter == Control.MOUSE_FILTER_STOP,
		"%s should block pointer input" % source
	)
	_expect(
		bool(loading_screen.call("animation_is_playing")),
		"%s spinner animation should be playing" % source
	)
	if source == "start":
		var loading_label: Label = loading_screen.get_node_or_null(
			"Root/Center/Layout/LoadingLabel"
		) as Label
		var original_locale: String = Localization.current_locale()
		Localization.set_locale("en")
		_expect(
			loading_label != null and loading_label.text == "Loading…",
			"loading text should refresh in English"
		)
		Localization.set_locale("zh_CN")
		_expect(
			loading_label != null and loading_label.text == tr("ui_loading"),
			"loading text should refresh in Simplified Chinese"
		)
		Localization.set_locale(original_locale)
	var spinner_arc: Line2D = loading_screen.get_node_or_null(
		"Root/Center/Layout/Spinner/Arc"
	) as Line2D
	var rotation_before: float = spinner_arc.rotation if spinner_arc != null else -1.0
	InputService.action_pressed.emit(
		StringName(ACTIONS.UI_BACK),
		InputService.DEFAULT_PARTICIPANT_ID
	)
	_expect(
		UIManager.top() == loading_screen and GameState.is_state(GameState.LOADING),
		"%s should ignore menu close input while loading" % source
	)
	await get_tree().process_frame
	await get_tree().process_frame
	if spinner_arc != null and is_instance_valid(spinner_arc):
		_expect(
			not is_equal_approx(spinner_arc.rotation, rotation_before),
			"%s spinner animation should advance across frames" % source
		)
	if GameState.is_state(GameState.LOADING):
		var clock_before: float = GameClock.now()
		var tick_before: int = GameClock.tick()
		await get_tree().process_frame
		_expect(
			not GameState.is_state(GameState.LOADING)
			or (
				is_equal_approx(GameClock.now(), clock_before)
				and GameClock.tick() == tick_before
			),
			"%s should not advance GameClock while LOADING" % source
		)


func _wait_for_playing_run() -> Node:
	for _frame: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if (
			run_loop != null
			and GameState.is_state(GameState.PLAYING)
			and _count_nodes_by_name(get_tree().root, "LoadingScreen") == 0
		):
			return run_loop
	return null


func _wait_for_node(node_name: String) -> Node:
	for _frame: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		var found: Node = _find_node_by_name(get_tree().root, node_name)
		if found != null:
			return found
	return null


func _find_node_by_name(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, node_name)
		if found != null:
			return found
	return null


func _count_nodes_by_name(root: Node, node_name: String) -> int:
	var count: int = 1 if root.name == node_name else 0
	for child: Node in root.get_children():
		count += _count_nodes_by_name(child, node_name)
	return count


func _expect_node(node: Node, message: String) -> bool:
	_expect(node != null, message)
	return node != null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _backup_run_save() -> void:
	_had_run_save = SaveManager.has_save(
		SaveManager.DEFAULT_SLOT,
		SAVE_KINDS.RUN
	)
	if _had_run_save:
		_run_save_backup = SaveManager.load_envelope(
			SaveManager.DEFAULT_SLOT,
			SAVE_KINDS.RUN
		)


func _restore_run_save() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	for broken_path: String in _smoke_broken_paths:
		if FileAccess.file_exists(broken_path):
			DirAccess.remove_absolute(broken_path)
	if not _had_run_save:
		return
	var payload: Variant = _run_save_backup.get("payload", {})
	if payload is Dictionary:
		SaveManager.save(
			SaveManager.DEFAULT_SLOT,
			SAVE_KINDS.RUN,
			payload as Dictionary
		)


func _write_corrupt_run_save() -> void:
	var save_path: String = SaveManager.save_root().path_join(
		SaveManager.DEFAULT_SLOT
	).path_join("%s.save" % SAVE_KINDS.RUN)
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(
		save_path.get_base_dir()
	)
	if make_dir_error != OK:
		_expect(false, "loading smoke should create the default save directory")
		return
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_expect(false, "loading smoke should open the run save for corruption")
		return
	file.store_string("{broken")
	file.flush()


func _on_save_corrupted(slot: String, kind: String, path: String, _error: String) -> void:
	if slot == SaveManager.DEFAULT_SLOT and kind == SAVE_KINDS.RUN:
		_smoke_broken_paths.append(path)


func _finish() -> void:
	if SaveManager.save_corrupted.is_connected(_on_save_corrupted):
		SaveManager.save_corrupted.disconnect(_on_save_corrupted)
	_restore_run_save()
	if _failures.is_empty():
		print("[loading-smoke] PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[loading-smoke] %s" % failure)
	get_tree().quit(1)
