extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const TELEPORT_CHOICE_OUTCOMES := preload(
	"res://scripts/contracts/teleport_choice_outcomes.gd"
)
const GAMEPLAY_RUN_LOOP_SCENE: PackedScene = preload(
	"res://scenes/gameplay/gameplay_run_loop.tscn"
)
const MAX_WAIT_FRAMES: int = 600

var _failures: Array[String] = []
var _boot_fixture_dependency_removed: bool = false
var _boot_fixture_run_loop: Node = null
var _boot_fixture_target_name: String = ""
var _had_run_save: bool = false
var _prepare_failure_count: int = 0
var _prepare_failure_reason: String = ""
var _prepare_failure_restoring: bool = false
var _fixture_weapon_removed: bool = false
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
	var boot: Node = _find_node_by_name(get_tree().root, "FormalClientBoot")
	_expect(
		not get_tree().auto_accept_quit,
		"FormalClientBoot should intercept window close requests"
	)
	var original_quit_locale: String = Localization.current_locale()
	await _expect_application_quit_cancellation(title_menu, boot, false)
	Localization.set_locale("en")
	await get_tree().process_frame
	await _expect_application_quit_cancellation(title_menu, boot, false)
	Localization.set_locale(original_quit_locale)
	await get_tree().process_frame
	_expect(
		UIManager.show_confirmation(
			tr("ui_settings_input_conflict_title"),
			tr("ui_settings_input_conflict_body").format({
				"action": "A",
				"other": "B",
			}),
			tr("ui_settings_input_conflict_replace"),
			tr("ui_cancel"),
			Callable(),
			Callable()
		),
		"window close setup should show an existing confirmation modal"
	)
	await _expect_application_quit_cancellation(title_menu, boot, true)
	var start_button: Button = title_menu.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/StartButton"
	) as Button
	if not _expect_node(start_button, "title menu should expose StartButton"):
		_finish()
		return
	start_button.pressed.emit()
	var composition_panel: Node = UIManager.top()
	_expect(
		composition_panel != null
		and composition_panel.name == "HeroCompositionPanel",
		"start should show HeroCompositionPanel before loading"
	)
	if boot != null:
		boot.call("_on_title_start_requested")
	_expect(
		_count_nodes_by_name(get_tree().root, "HeroCompositionPanel") == 1,
		"duplicate start should keep one composition panel"
	)
	var main_detail: Label = (
		composition_panel.get_node_or_null(
			"Root/Center/Panel/Margin/Layout/Cards/MainCard/Margin/Layout/DetailLabel"
		) as Label
		if composition_panel != null
		else null
	)
	var sub_detail: Label = (
		composition_panel.get_node_or_null(
			"Root/Center/Panel/Margin/Layout/Cards/SubCard/Margin/Layout/DetailLabel"
		) as Label
		if composition_panel != null
		else null
	)
	_expect(
		main_detail != null
		and not main_detail.text.contains("{")
		and main_detail.text.contains(
			tr("skill_deploy_projectile_barrier_name")
		),
		"main hero card should show resolved config-backed descriptions"
	)
	_expect(
		sub_detail != null
		and not sub_detail.text.contains("{")
		and sub_detail.text.contains(
			tr("skill_enemy_haste_vulnerability_name")
		),
		"sub hero card should resolve skills 3/4 using main hero stats"
	)
	var original_composition_locale: String = Localization.current_locale()
	Localization.set_locale("en")
	await get_tree().process_frame
	_expect(
		main_detail != null
		and sub_detail != null
		and not main_detail.text.contains("{")
		and not sub_detail.text.contains("{")
		and main_detail.text.contains(
			tr("skill_deploy_projectile_barrier_name")
		)
		and sub_detail.text.contains(
			tr("skill_enemy_haste_vulnerability_name")
		),
		"English hero cards should refresh with resolved config descriptions"
	)
	var composition_card: Control = (
		composition_panel.get_node_or_null("Root/Center/Panel") as Control
		if composition_panel != null
		else null
	)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_expect(
		composition_card != null
		and composition_card.size.x <= viewport_size.x
		and composition_card.size.y <= viewport_size.y,
		"English hero composition cards should stay inside the viewport; card=%s viewport=%s" % [
			composition_card.size if composition_card != null else Vector2.ZERO,
			viewport_size,
		]
	)
	Localization.set_locale(original_composition_locale)
	var confirm_button: Button = (
		composition_panel.get_node_or_null(
			"Root/Center/Panel/Margin/Layout/Actions/ConfirmButton"
		) as Button
		if composition_panel != null
		else null
	)
	if not _expect_node(
		confirm_button,
		"composition panel should expose ConfirmButton"
	):
		_finish()
		return
	confirm_button.pressed.emit()
	await _expect_loading_visible("start")
	if boot != null:
		boot.call("_request_application_quit")
		_expect(
			bool(boot.get("_application_quit_deferred_for_loading"))
			and _find_node_by_name(get_tree().root, "ApplicationQuitModal") == null,
			"application quit request should wait without covering an active loading screen"
		)
		boot.call("_on_title_continue_requested")
	_expect(
		_count_nodes_by_name(get_tree().root, "LoadingScreen") == 1,
		"duplicate load request should keep one loading screen"
	)
	var deferred_quit_modal: Node = await _wait_for_node("ApplicationQuitModal")
	if not _expect_node(
		deferred_quit_modal,
		"deferred application quit prompt should appear after loading finishes"
	):
		_finish()
		return
	deferred_quit_modal.call("request_cancel")
	_expect(
		await _wait_for_node_absent("ApplicationQuitModal"),
		"cancelling deferred application quit should remove its prompt"
	)
	var first_run: Node = await _wait_for_playing_run()
	if not _expect_node(first_run, "start should finish with one playable run"):
		_finish()
		return
	_expect(_count_nodes_by_name(get_tree().root, "GameplayRunLoop") == 1, "start should mount one GameplayRunLoop")
	await _expect_application_quit_save_failure(boot, first_run)

	var teleport_source_id: String = await _prepare_teleporter_choice(first_run)
	_expect(
		not teleport_source_id.is_empty()
		and GameState.is_state(GameState.PLAYING),
		"loading smoke should prepare a PLAYING teleport choice overlay"
	)
	var first_snapshot: Dictionary = first_run.call("create_run_snapshot")
	_expect(
		boot != null
		and bool(boot.call("_save_active_run_for_application_quit")),
		"application quit save path should persist a valid teleport-choice run"
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
	var continued_run: Node = await _wait_for_teleporter_choice()
	if not _expect_node(continued_run, "continue should restore the teleport choice"):
		_finish()
		return
	var continued_teleport_runtime: Node = continued_run.get_node(
		"TeleportRuntimeCoordinator"
	)
	_expect(
		String(continued_teleport_runtime.get("source_station_id"))
		== teleport_source_id
		and _find_node_by_name(get_tree().root, "TeleportChoicePanel") != null,
		"continue should rebuild the original source station choice panel"
	)
	_expect(
		RNG.run_seed() == int(first_snapshot.get("rng", {}).get("run_seed", 0)),
		"continue should restore the saved run seed"
	)
	continued_run.call("_show_pause_menu")
	var paused_run: Node = await _wait_for_run_state(GameState.PAUSED)
	_expect(paused_run == continued_run, "pause should overlay the restored teleport choice")
	var paused_snapshot: Dictionary = continued_run.call("create_run_snapshot")
	_expect(
		SaveManager.save(
			SaveManager.DEFAULT_SLOT,
			SAVE_KINDS.RUN,
			paused_snapshot
		),
		"loading smoke should save pause over teleport choice"
	)
	continued_run.emit_signal("quit_to_title_requested")
	title_menu = await _wait_for_node("TitleMenu")
	if not _expect_node(title_menu, "paused teleport choice should return to title"):
		_finish()
		return
	continue_button = title_menu.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ContinueRunButton"
	) as Button
	if not _expect_node(continue_button, "paused choice should expose ContinueRunButton"):
		_finish()
		return
	continue_button.pressed.emit()
	await _expect_loading_visible("paused teleport continue")
	continued_run = await _wait_for_run_state(GameState.PAUSED)
	if not _expect_node(continued_run, "continue should restore pause over teleport choice"):
		_finish()
		return
	var restored_ui: Dictionary = continued_run.call("_ui_restore_snapshot")
	_expect(
		String(restored_ui.get("state", "")) == "paused"
		and String(restored_ui.get("underlying_state", ""))
		== "teleport_choice"
		and String(restored_ui.get("source_station_id", ""))
		== teleport_source_id,
		"continued pause should retain the underlying teleport source"
	)
	continued_run.call("_on_pause_resume_requested")
	continued_run = await _wait_for_teleporter_choice()
	_expect(continued_run != null, "resuming continued pause should reveal teleport choice")
	if continued_run != null:
		_expect(
			bool(continued_run.call("apply_replay_teleport_choice", {
				"outcome": TELEPORT_CHOICE_OUTCOMES.CANCELLED,
				"source_station_id": teleport_source_id,
			})),
			"continued teleport choice should remain cancellable"
		)
		continued_run = await _wait_for_playing_run()

	continued_run.emit_signal("restart_requested")
	await _expect_loading_visible("restart")
	var restarted_run: Node = await _wait_for_playing_run()
	if not _expect_node(restarted_run, "restart should finish with one playable run"):
		_finish()
		return
	_expect(_count_nodes_by_name(get_tree().root, "GameplayRunLoop") == 1, "restart should replace the old run")

	var invalid_snapshot: Dictionary = restarted_run.call("create_run_snapshot")
	var invalid_composition: Dictionary = (
		invalid_snapshot.get("hero_composition", {}) as Dictionary
	)
	invalid_composition["main_hero_id"] = "missing_loading_smoke_character"
	invalid_snapshot["hero_composition"] = invalid_composition
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

	await _expect_fatal_prepare_failure_signals_once()
	await _expect_boot_fatal_prepare_failures(boot)

	_finish()


func _expect_fatal_prepare_failure_signals_once() -> void:
	for fixture: Dictionary in _fatal_prepare_fixtures():
		await _expect_one_fatal_prepare_failure(
			String(fixture.get("target", "")),
			String(fixture.get("reason", ""))
		)


func _fatal_prepare_fixtures() -> Array[Dictionary]:
	return [
		{
			"target": "MapManager",
			"reason": "missing MapManager scene node",
		},
		{
			"target": "WorldBackground",
			"reason": "missing WorldBackground scene node",
		},
		{
			"target": "WeaponSystem",
			"reason": "missing WeaponSystem scene node",
		},
		{
			"target": "GameplayHud",
			"reason": "missing GameplayHud scene node",
		},
	]


func _expect_one_fatal_prepare_failure(
	target_name: String,
	expected_reason: String
) -> void:
	_prepare_failure_count = 0
	_prepare_failure_reason = ""
	_prepare_failure_restoring = true
	_fixture_weapon_removed = false
	var run_loop: Node = GAMEPLAY_RUN_LOOP_SCENE.instantiate()
	if target_name != "WeaponSystem":
		var target: Node = _fatal_fixture_node(run_loop, target_name)
		if not _expect_node(
			target,
			"fatal prepare fixture should contain %s" % target_name
		):
			run_loop.free()
			return
		var target_parent: Node = target.get_parent()
		if target_parent != null:
			target_parent.remove_child(target)
		target.free()
	run_loop.call("configure_player_loading_mode", true)
	run_loop.connect(
		"run_prepare_failed",
		Callable(self, "_on_fixture_run_prepare_failed")
	)
	var weapon_remover: Callable = Callable(
		self,
		"_on_fatal_fixture_node_added"
	).bind(run_loop)
	if target_name == "WeaponSystem":
		get_tree().node_added.connect(weapon_remover)
	var print_errors_before_fixture: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	add_child(run_loop)
	for _frame: int in range(MAX_WAIT_FRAMES):
		if _prepare_failure_count > 0:
			break
		await get_tree().process_frame
	Engine.print_error_messages = print_errors_before_fixture
	if get_tree().node_added.is_connected(weapon_remover):
		get_tree().node_added.disconnect(weapon_remover)
	if target_name == "WeaponSystem":
		_expect(
			_fixture_weapon_removed,
			"fatal prepare fixture should remove WeaponSystem as Player enters"
		)
	_expect(
		_prepare_failure_count == 1,
		"%s fatal prepare error should emit run_prepare_failed once" % target_name
	)
	_expect(
		_prepare_failure_reason == expected_reason,
		"%s fatal prepare signal should expose its stable failure reason"
		% target_name
	)
	_expect(
		not _prepare_failure_restoring,
		"a fresh-run fatal prepare signal should not report restoring"
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		_prepare_failure_count == 1,
		"%s stopped failed run should not emit a duplicate prepare failure"
		% target_name
	)
	if is_instance_valid(run_loop):
		run_loop.queue_free()
	await get_tree().process_frame


func _fatal_fixture_node(run_loop: Node, target_name: String) -> Node:
	match target_name:
		"MapManager", "WorldBackground":
			var active_world: Node = run_loop.get_node_or_null("ActiveWorld")
			return (
				active_world.get_node_or_null(target_name)
				if active_world != null
				else null
			)
		"GameplayHud":
			return run_loop.get_node_or_null("GameplayHud")
		_:
			return null


func _on_fatal_fixture_node_added(node: Node, run_loop: Node) -> void:
	if (
		node.name != &"Player"
		or run_loop == null
		or not is_instance_valid(run_loop)
		or not run_loop.is_ancestor_of(node)
	):
		return
	var weapon_system: Node = node.get_node_or_null("WeaponSystem")
	if weapon_system == null:
		return
	var weapon_parent: Node = weapon_system.get_parent()
	if weapon_parent != null:
		weapon_parent.remove_child(weapon_system)
	weapon_system.free()
	_fixture_weapon_removed = true
	var callback: Callable = Callable(
		self,
		"_on_fatal_fixture_node_added"
	).bind(run_loop)
	if get_tree().node_added.is_connected(callback):
		get_tree().node_added.disconnect(callback)


func _expect_boot_fatal_prepare_failures(boot: Node) -> void:
	if not _expect_node(
		boot,
		"fatal prepare integration fixtures require FormalClientBoot"
	):
		return
	for fixture: Dictionary in _fatal_prepare_fixtures():
		await _expect_one_boot_fatal_prepare_failure(
			boot,
			String(fixture.get("target", "")),
			String(fixture.get("reason", ""))
		)


func _expect_one_boot_fatal_prepare_failure(
	boot: Node,
	target_name: String,
	expected_reason: String
) -> void:
	var title_menu: Node = await _wait_for_node("TitleMenu")
	if not _expect_node(
		title_menu,
		"%s Boot fixture should begin at TitleMenu" % target_name
	):
		return
	var start_button: Button = title_menu.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/StartButton"
	) as Button
	if not _expect_node(
		start_button,
		"%s Boot fixture should expose StartButton" % target_name
	):
		return
	start_button.pressed.emit()
	var composition_panel: Node = await _wait_for_node("HeroCompositionPanel")
	if not _expect_node(
		composition_panel,
		"%s Boot fixture should open HeroCompositionPanel" % target_name
	):
		return
	var confirm_button: Button = composition_panel.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Actions/ConfirmButton"
	) as Button
	if not _expect_node(
		confirm_button,
		"%s Boot fixture should expose ConfirmButton" % target_name
	):
		return

	_prepare_failure_count = 0
	_prepare_failure_reason = ""
	_prepare_failure_restoring = true
	_boot_fixture_target_name = target_name
	_boot_fixture_run_loop = null
	_boot_fixture_dependency_removed = false
	var node_added_callback: Callable = Callable(
		self,
		"_on_boot_fatal_fixture_node_added"
	).bind(boot)
	get_tree().node_added.connect(node_added_callback)
	var print_errors_before_fixture: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	confirm_button.pressed.emit()
	await _expect_loading_visible("%s fatal prepare" % target_name)
	var cleanup_finished: bool = await _wait_for_boot_failure_cleanup()
	Engine.print_error_messages = print_errors_before_fixture
	if get_tree().node_added.is_connected(node_added_callback):
		get_tree().node_added.disconnect(node_added_callback)

	_expect(
		_boot_fixture_dependency_removed,
		"%s Boot fixture should remove its dependency" % target_name
	)
	_expect(
		_prepare_failure_count == 1,
		"%s Boot player loading should emit run_prepare_failed once"
		% target_name
	)
	_expect(
		_prepare_failure_reason == expected_reason
		and not _prepare_failure_restoring,
		(
			"%s Boot failure should preserve reason and fresh-run context "
			+ "(actual reason=%s, restoring=%s, count=%d)"
		)
		% [
			target_name,
			_prepare_failure_reason,
			str(_prepare_failure_restoring),
			_prepare_failure_count,
		]
	)
	_expect(
		cleanup_finished and GameState.is_state(GameState.MAIN_MENU),
		"%s Boot failure should exit LOADING and restore MAIN_MENU"
		% target_name
	)
	_expect(
		_count_nodes_by_name(get_tree().root, "LoadingScreen") == 0,
		"%s Boot failure should remove LoadingScreen" % target_name
	)
	_expect(
		_count_nodes_by_name(get_tree().root, "GameplayRunLoop") == 0,
		"%s Boot failure should remove the partial GameplayRunLoop"
		% target_name
	)
	_expect(
		ModLoader.can_reload_packages(),
		"%s Boot failure should release runtime Mod activity" % target_name
	)
	_expect_boot_failure_pools_cleared(target_name)
	if not cleanup_finished:
		boot.call("_show_title_menu", "ui_loading_failed")
		await get_tree().process_frame
	_boot_fixture_run_loop = null
	_boot_fixture_target_name = ""


func _on_boot_fatal_fixture_node_added(node: Node, boot: Node) -> void:
	if node.name == &"GameplayRunLoop" and node.get_parent() == boot:
		_boot_fixture_run_loop = node
		var failure_callback: Callable = Callable(
			self,
			"_on_fixture_run_prepare_failed"
		)
		if not node.is_connected("run_prepare_failed", failure_callback):
			node.connect(
				"run_prepare_failed",
				failure_callback,
				CONNECT_ONE_SHOT
			)
		if _boot_fixture_target_name != "WeaponSystem":
			_boot_fixture_dependency_removed = _remove_fatal_fixture_node(
				node,
				_boot_fixture_target_name
			)
		return
	if (
		_boot_fixture_target_name != "WeaponSystem"
		or node.name != &"Player"
		or _boot_fixture_run_loop == null
		or not is_instance_valid(_boot_fixture_run_loop)
	):
		return
	_boot_fixture_dependency_removed = _remove_child_by_name(
		node,
		"WeaponSystem"
	)


func _remove_fatal_fixture_node(run_loop: Node, target_name: String) -> bool:
	var target: Node = _fatal_fixture_node(run_loop, target_name)
	if target == null:
		return false
	var target_parent: Node = target.get_parent()
	if target_parent != null:
		target_parent.remove_child(target)
	target.free()
	return true


func _remove_child_by_name(parent: Node, child_name: String) -> bool:
	var child: Node = parent.get_node_or_null(child_name)
	if child == null:
		return false
	parent.remove_child(child)
	child.free()
	return true


func _wait_for_boot_failure_cleanup() -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		if (
			GameState.is_state(GameState.MAIN_MENU)
			and _count_nodes_by_name(get_tree().root, "TitleMenu") == 1
			and _count_nodes_by_name(get_tree().root, "LoadingScreen") == 0
			and _count_nodes_by_name(get_tree().root, "GameplayRunLoop") == 0
		):
			return true
	return false


func _expect_boot_failure_pools_cleared(source: String) -> void:
	for pool_id: String in POOL_IDS.VALUES:
		_expect(
			PoolManager.active_count(pool_id) == 0,
			"%s Boot failure should leave pool %s with zero active nodes"
			% [source, pool_id]
		)
	for pool_id: String in _run_owned_pool_ids():
		_expect(
			not PoolManager.has_pool(pool_id),
			"%s Boot failure should clear run-owned pool %s"
			% [source, pool_id]
		)


func _run_owned_pool_ids() -> Array[String]:
	var result: Array[String] = [
		POOL_IDS.BULLET_BASIC,
		POOL_IDS.HAZARD_SPIKE,
		POOL_IDS.HIT_SPARK,
		POOL_IDS.DAMAGE_NUMBER,
		POOL_IDS.GOLD_ORB,
		POOL_IDS.ENERGY_ORB,
		POOL_IDS.GEAR_MOD_PICKUP,
		POOL_IDS.PROJECTILE_BARRIER,
		POOL_IDS.VFX_ENEMY_EXPLOSION_TELEGRAPH,
		POOL_IDS.VFX_ENEMY_MELEE_TELEGRAPH,
		POOL_IDS.VFX_ENEMY_CHARGE_TELEGRAPH,
		POOL_IDS.VFX_ENEMY_EXPLOSION_IMPACT,
	]
	for enemy_row: Dictionary in DataLoader.load_csv(DataLoader.ENEMIES_PATH):
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		if not pool_id.is_empty() and not result.has(pool_id):
			result.append(pool_id)
	return result


func _on_fixture_run_prepare_failed(reason: String, restoring: bool) -> void:
	_prepare_failure_count += 1
	_prepare_failure_reason = reason
	_prepare_failure_restoring = restoring


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
	return await _wait_for_run_state(GameState.PLAYING)


func _wait_for_teleporter_choice() -> Node:
	for _frame: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(
			get_tree().root,
			"GameplayRunLoop"
		)
		var teleport_runtime: Node = (
			run_loop.get_node("TeleportRuntimeCoordinator")
			if run_loop != null
			else null
		)
		if (
			run_loop != null
			and GameState.is_state(GameState.PLAYING)
			and not String(
				teleport_runtime.get("source_station_id")
			).is_empty()
			and teleport_runtime.get("choice_panel") != null
			and _count_nodes_by_name(
				get_tree().root,
				"LoadingScreen"
			) == 0
		):
			return run_loop
	return null


func _wait_for_run_state(state: StringName) -> Node:
	for _frame: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if (
			run_loop != null
			and GameState.is_state(state)
			and _count_nodes_by_name(get_tree().root, "LoadingScreen") == 0
		):
			return run_loop
	return null


func _prepare_teleporter_choice(run_loop: Node) -> String:
	var manager: Node = _find_node_by_name(run_loop, "ModuleWorldManager")
	var player: Node2D = _find_node_by_name(run_loop, "Player") as Node2D
	if manager == null or player == null:
		return ""
	var stations: Array[Dictionary] = []
	var teleport_runtime: Node = run_loop.get_node(
		"TeleportRuntimeCoordinator"
	)
	var raw_stations: Dictionary = teleport_runtime.get("stations") as Dictionary
	for raw_station: Variant in raw_stations.values():
		if raw_station is Dictionary:
			stations.append((raw_station as Dictionary).duplicate(true))
	stations.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("station_number", 0)) < int(right.get("station_number", 0))
	)
	if stations.size() != 3:
		return ""
	for station_index: int in [0, 1, 0]:
		var station: Dictionary = stations[station_index]
		var position_data: Dictionary = station.get("world_position", {}) as Dictionary
		var position := Vector2(
			float(position_data.get("x", 0.0)),
			float(position_data.get("y", 0.0))
		)
		player.call("teleport_to", position)
		var stream_change: Dictionary = manager.call("tick", position)
		run_loop.call("_handle_module_stream_change", stream_change)
		var coord_data: Dictionary = station.get("module_coord", {}) as Dictionary
		var module_coord := Vector2i(
			int(coord_data.get("x", -1)),
			int(coord_data.get("y", -1))
		)
		var state: Dictionary = manager.call("slot_state", module_coord)
		state["enemy_snapshots"] = []
		state["enemy_encounter"] = {"state": "cleared"}
		manager.call("set_slot_state", module_coord, state)
		await get_tree().process_frame
	var source_id: String = String(stations[0].get("station_id", ""))
	if not bool(run_loop.call("_show_teleport_choice_panel", source_id)):
		return ""
	return source_id


func _wait_for_node(node_name: String) -> Node:
	for _frame: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		var found: Node = _find_node_by_name(get_tree().root, node_name)
		if found != null:
			return found
	return null


func _wait_for_node_absent(node_name: String) -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		if _find_node_by_name(get_tree().root, node_name) == null:
			return true
	return false


func _expect_application_quit_cancellation(
		title_menu: Node,
		boot: Node,
		use_window_notification: bool
	) -> void:
	if not _expect_node(boot, "application quit prompt requires FormalClientBoot"):
		return
	if use_window_notification:
		boot.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		var quit_button: Button = title_menu.get_node_or_null(
			"Root/Center/Panel/Margin/Layout/QuitButton"
		) as Button
		if not _expect_node(quit_button, "title menu should expose QuitButton"):
			return
		quit_button.pressed.emit()
	var modal: Node = await _wait_for_node("ApplicationQuitModal")
	if not _expect_node(modal, "application quit should show a confirmation modal"):
		return
	_expect(
		GameState.is_state(GameState.PAUSED),
		"application quit confirmation should pause the current state"
	)
	var confirm_button: Button = modal.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Buttons/ConfirmButton"
	) as Button
	var cancel_button: Button = modal.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Buttons/CancelButton"
	) as Button
	var title_label: Label = modal.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/TitleLabel"
	) as Label
	var body_label: Label = modal.get_node_or_null(
		"Root/Center/Panel/Margin/Layout/BodyLabel"
	) as Label
	_expect(
		title_label != null and title_label.text == tr("ui_quit_confirm_title"),
		"application quit confirmation should localize its title"
	)
	_expect(
		body_label != null and body_label.text == tr("ui_quit_confirm_body"),
		"application quit confirmation should localize its body"
	)
	_expect(
		confirm_button != null and confirm_button.text == tr("ui_save_and_quit"),
		"application quit confirmation should expose Save and Quit"
	)
	_expect(
		cancel_button != null and cancel_button.text == tr("ui_cancel"),
		"application quit confirmation should expose Cancel"
	)
	modal.call("request_cancel")
	_expect(
		await _wait_for_node_absent("ApplicationQuitModal"),
		"cancelling application quit should remove the confirmation modal"
	)
	_expect(
		GameState.is_state(GameState.MAIN_MENU),
		"cancelling application quit should restore MAIN_MENU"
	)


func _expect_application_quit_save_failure(
		boot: Node,
		active_run: Node
	) -> void:
	var failing_run: Node = FailingQuitSaveRun.new()
	add_child(failing_run)
	boot.set("_run_loop", failing_run)
	boot.call("_request_application_quit")
	var original_modal: Node = await _wait_for_node("ApplicationQuitModal")
	if not _expect_node(
		original_modal,
		"save failure setup should show application quit confirmation"
	):
		boot.set("_run_loop", active_run)
		failing_run.queue_free()
		return
	original_modal.call("_on_confirm_pressed")
	await get_tree().process_frame
	var retry_modal: Node = _find_node_by_name(
		get_tree().root,
		"ApplicationQuitModal"
	)
	_expect(
		retry_modal != null and retry_modal != original_modal,
		"save failure should keep the game open and show a fresh confirmation"
	)
	var body_label: Label = (
		retry_modal.get_node_or_null(
			"Root/Center/Panel/Margin/Layout/BodyLabel"
		) as Label
		if retry_modal != null
		else null
	)
	_expect(
		body_label != null and body_label.text == tr("ui_quit_save_failed_body"),
		"save failure should explain that the game was not closed"
	)
	if retry_modal != null:
		retry_modal.call("request_cancel")
		await _wait_for_node_absent("ApplicationQuitModal")
	_expect(
		GameState.is_state(GameState.PLAYING),
		"cancelling after save failure should restore PLAYING"
	)
	boot.set("_run_loop", active_run)
	failing_run.queue_free()


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


class FailingQuitSaveRun:
	extends Node

	func save_run_snapshot() -> bool:
		return false
