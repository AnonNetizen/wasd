extends Node
## Focused Codex scene, privacy, localization, focus, and close coverage.


const CODEX_PANEL_SCENE := preload("res://scenes/ui/codex_panel.tscn")
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const CONTENT_UNLOCK_PROGRESS_COUNTERS := preload(
	"res://scripts/contracts/content_unlock_progress_counters.gd"
)
const CONTENT_UNLOCK_RULE_MODES := preload(
	"res://scripts/contracts/content_unlock_rule_modes.gd"
)
const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const GAME_OVER_PANEL_SCENE := preload("res://scenes/ui/game_over_panel.tscn")
const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const HERO_COMPOSITION_PANEL_SCENE := preload(
	"res://scenes/ui/hero_composition_panel.tscn"
)
const MAX_WAIT_FRAMES: int = 240
const TITLE_MENU_SCENE := preload("res://scenes/ui/title_menu.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	var content_source: MockContentSource = MockContentSource.new()
	content_source.name = "MockContentSource"
	add_child(content_source)
	var panel: CanvasLayer = CODEX_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "CodexPanelUnderTest"
	panel.call("configure_content_source", content_source)
	add_child(panel)
	await get_tree().process_frame

	_expect_scene_nodes(panel)
	_expect_three_categories(panel)
	_expect_locked_entries_do_not_leak(panel)
	await _expect_locale_refresh(panel)
	_expect_focus(panel)
	_expect_request_close(panel)
	await _expect_ui_back_close()
	await _expect_title_entry()
	await _expect_hero_availability_filter()
	await _expect_result_unlock_summary()

	remove_child(panel)
	panel.queue_free()
	remove_child(content_source)
	content_source.queue_free()
	UIManager.call("_set_navigation_focus_visible", false)
	UIManager.clear(true)
	await get_tree().process_frame
	_finish()


func _expect_scene_nodes(panel: Node) -> void:
	for node_name: String in [
		"CharacterButton",
		"GearModButton",
		"EnemyButton",
		"EntryList",
		"DetailNameLabel",
		"IconTexture",
		"IconPlaceholder",
		"PendingPreviewLabel",
		"CloseButton",
	]:
		_expect(
			_find_node_by_name(panel, node_name) != null,
			"Codex scene should contain %s" % node_name
		)
	var pending_label: Label = _find_node_by_name(
		panel,
		"PendingPreviewLabel"
	) as Label
	_expect(
		pending_label != null
		and pending_label.visible
		and pending_label.text.contains("1"),
		"Codex should show the saved-Run pending unlock preview"
	)


func _expect_three_categories(panel: Node) -> void:
	for entry_type: String in CONTENT_UNLOCK_TYPES.VALUES:
		panel.call("select_category", entry_type)
		_expect(
			String(panel.call("selected_type")) == entry_type,
			"Codex should select the %s category" % entry_type
		)
		_expect(
			int(panel.call("displayed_entry_count")) == 2,
			"Codex %s category should list locked and unlocked entries"
			% entry_type
		)


func _expect_locked_entries_do_not_leak(panel: Node) -> void:
	for entry_type: String in CONTENT_UNLOCK_TYPES.VALUES:
		panel.call("select_category", entry_type)
		panel.call("select_entry", 1)
		var detail_name: Label = _find_node_by_name(
			panel,
			"DetailNameLabel"
		) as Label
		var icon_texture: TextureRect = _find_node_by_name(
			panel,
			"IconTexture"
		) as TextureRect
		var placeholder: ColorRect = _find_node_by_name(
			panel,
			"IconPlaceholder"
		) as ColorRect
		var visible_text: String = _visible_text(panel)
		_expect(
			detail_name != null and detail_name.text == "???",
			"locked %s detail should use the anonymous title" % entry_type
		)
		_expect(
			not visible_text.contains("secret_locked")
			and not visible_text.contains("987654")
			and not visible_text.contains("res://secret"),
			"locked %s detail must not leak name, description, stats, or icon path"
			% entry_type
		)
		_expect(
			icon_texture != null
			and not icon_texture.visible
			and icon_texture.texture == null,
			"locked %s icon texture should stay hidden" % entry_type
		)
		_expect(
			placeholder != null and placeholder.visible,
			"locked %s entry should show the generic silhouette" % entry_type
		)
		var status_label: Label = _find_node_by_name(
			panel,
			"DetailStatusLabel"
		) as Label
		_expect(
			status_label != null
			and status_label.text.contains("1")
			and status_label.text.contains("5")
			and status_label.text.contains("2"),
			"locked %s detail should show current, target, and pending progress: %s"
			% [entry_type, status_label.text if status_label != null else "<missing>"]
		)


func _expect_locale_refresh(panel: Node) -> void:
	Localization.set_locale("zh_CN")
	panel.call("select_category", CONTENT_UNLOCK_TYPES.CHARACTER)
	panel.call("select_entry", 0)
	await get_tree().process_frame
	var name_label: Label = _find_node_by_name(
		panel,
		"DetailNameLabel"
	) as Label
	var zh_name: String = tr("character_primary_a_name")
	_expect(
		name_label != null and name_label.text == zh_name,
		"Codex unlocked name should start in zh_CN"
	)
	Localization.set_locale("en")
	await get_tree().process_frame
	var en_name: String = tr("character_primary_a_name")
	_expect(
		name_label != null
		and name_label.text == en_name
		and en_name != zh_name,
		"Codex unlocked name should refresh after locale_changed"
	)
	Localization.set_locale("zh_CN")
	await get_tree().process_frame


func _expect_focus(panel: Node) -> void:
	UIManager.call("_set_navigation_focus_visible", true, false)
	panel.call("select_category", CONTENT_UNLOCK_TYPES.CHARACTER)
	panel.call("grab_default_focus")
	var character_button: Button = _find_node_by_name(
		panel,
		"CharacterButton"
	) as Button
	_expect(
		character_button != null
		and character_button.focus_mode != Control.FOCUS_NONE
		and get_viewport().gui_get_focus_owner() == character_button,
		"Codex should expose and restore category focus"
	)


func _expect_request_close(panel: Node) -> void:
	var close_count: Array[int] = [0]
	panel.connect("closed_requested", func() -> void:
		close_count[0] += 1
	)
	panel.call("request_close")
	_expect(
		close_count[0] == 1,
		"Codex request_close should emit closed_requested once"
	)


func _expect_ui_back_close() -> void:
	UIManager.clear(true)
	var panel: Node = UIManager.push(
		CODEX_PANEL_SCENE,
		{"source": "codex_smoke", "immediate": true}
	)
	_expect(panel != null, "UIManager should push Codex for ui_back coverage")
	if panel == null:
		return
	panel.connect("closed_requested", func() -> void:
		UIManager.pop_expected(panel, true)
	)
	_expect(
		await _wait_for_ui_state(panel, UIManager.UIState.ACTIVE),
		"Codex should become ACTIVE before ui_back"
	)
	_expect(
		bool(UIManager.call("_request_top_close")),
		"ui_back close routing should call Codex request_close"
	)
	_expect(
		await _wait_for_ui_state(panel, UIManager.UIState.REMOVED),
		"Codex should be removed after ui_back close routing"
	)


func _expect_title_entry() -> void:
	var title_menu: CanvasLayer = TITLE_MENU_SCENE.instantiate() as CanvasLayer
	title_menu.name = "TitleMenuUnderTest"
	add_child(title_menu)
	await get_tree().process_frame
	var settings_button: Button = _find_node_by_name(
		title_menu,
		"SettingsButton"
	) as Button
	var codex_button: Button = _find_node_by_name(
		title_menu,
		"CodexButton"
	) as Button
	var quit_button: Button = _find_node_by_name(
		title_menu,
		"QuitButton"
	) as Button
	_expect(
		settings_button != null
		and codex_button != null
		and quit_button != null
		and settings_button.get_index() < codex_button.get_index()
		and codex_button.get_index() < quit_button.get_index(),
		"title Codex entry should sit between settings and quit"
	)
	_expect(
		codex_button != null and codex_button.text == tr("ui_codex"),
		"title Codex entry should use localized text"
	)
	var requested: Array[bool] = [false]
	title_menu.connect("codex_requested", func() -> void:
		requested[0] = true
	)
	if codex_button != null:
		codex_button.pressed.emit()
	_expect(requested[0], "title Codex entry should emit codex_requested")
	remove_child(title_menu)
	title_menu.queue_free()


func _expect_hero_availability_filter() -> void:
	var panel: CanvasLayer = (
		HERO_COMPOSITION_PANEL_SCENE.instantiate() as CanvasLayer
	)
	panel.name = "HeroCompositionPanelUnderTest"
	add_child(panel)
	await get_tree().process_frame
	var payload: Dictionary = DataLoader.load_json(
		DataLoader.CHARACTERS_PATH
	) as Dictionary
	var hero_rows: Array[Dictionary] = []
	for raw_row: Variant in payload.get("characters", []):
		if raw_row is Dictionary:
			hero_rows.append((raw_row as Dictionary).duplicate(true))
	var unavailable_row: Dictionary = hero_rows[0].duplicate(true)
	unavailable_row["id"] = "smoke_character_not_available"
	hero_rows.append(unavailable_row)
	panel.call(
		"configure",
		hero_rows,
		CHARACTER_IDS.CHARACTER_PRIMARY_A,
		CHARACTER_IDS.CHARACTER_PRIMARY_B
	)
	var main_selector: OptionButton = _find_node_by_name(
		panel,
		"MainHeroSelector"
	) as OptionButton
	var confirm_button: Button = _find_node_by_name(
		panel,
		"ConfirmButton"
	) as Button
	_expect(
		main_selector != null and main_selector.item_count == 2,
		"hero composition should exclude characters outside the run availability snapshot"
	)
	if main_selector != null and main_selector.item_count == 2:
		_expect(
			String(main_selector.get_item_metadata(0))
			== CHARACTER_IDS.CHARACTER_PRIMARY_A
			and String(main_selector.get_item_metadata(1))
			== CHARACTER_IDS.CHARACTER_PRIMARY_B,
			"hero availability filtering should preserve source data order"
		)
	var single_hero_rows: Array[Dictionary] = [hero_rows[0]]
	panel.call(
		"configure",
		single_hero_rows,
		CHARACTER_IDS.CHARACTER_PRIMARY_A,
		""
	)
	_expect(
		confirm_button != null and confirm_button.disabled,
		"hero composition should require at least two unlocked characters"
	)
	remove_child(panel)
	panel.queue_free()


func _expect_result_unlock_summary() -> void:
	var panel: CanvasLayer = GAME_OVER_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "GameOverPanelUnderTest"
	add_child(panel)
	await get_tree().process_frame
	panel.call(
		"configure",
		3,
		20.0,
		true,
		{},
		{CONTENT_UNLOCK_TYPES.CHARACTER: [CHARACTER_IDS.CHARACTER_PRIMARY_A]}
	)
	var unlocks_label: Label = _find_node_by_name(
		panel,
		"NewUnlocksLabel"
	) as Label
	_expect(
		unlocks_label != null
		and unlocks_label.visible
		and unlocks_label.text.contains(tr("ui_result_new_unlocks_header"))
		and unlocks_label.text.contains(tr("character_primary_a_name")),
		"result panel should show a localized non-empty unlock summary"
	)
	panel.call("configure", 3, 20.0, true, {}, {})
	_expect(
		unlocks_label != null and not unlocks_label.visible,
		"result panel should hide an empty unlock summary"
	)
	remove_child(panel)
	panel.queue_free()


func _wait_for_ui_state(node: Node, target_state: int) -> bool:
	for _frame: int in range(MAX_WAIT_FRAMES):
		if not is_instance_valid(node):
			return target_state == UIManager.UIState.REMOVED
		if UIManager.ui_state(node) == target_state:
			return true
		await get_tree().process_frame
	return false


func _visible_text(root_node: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	_collect_visible_text(root_node, parts)
	return "\n".join(parts)


func _collect_visible_text(node: Node, parts: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	elif node is ItemList:
		var item_list: ItemList = node as ItemList
		for index: int in range(item_list.item_count):
			parts.append(item_list.get_item_text(index))
	for child: Node in node.get_children():
		_collect_visible_text(child, parts)


func _find_node_by_name(root_node: Node, requested_name: String) -> Node:
	if root_node == null:
		return null
	if root_node.name == requested_name:
		return root_node
	for child: Node in root_node.get_children():
		var found: Node = _find_node_by_name(child, requested_name)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[codex-smoke] ALL PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[codex-smoke] %s" % failure)
	get_tree().quit(1)


class MockContentSource:
	extends Node


	func codex_entries(entry_type: String) -> Array[Dictionary]:
		match entry_type:
			CONTENT_UNLOCK_TYPES.CHARACTER:
				return [
					{
						"id": CHARACTER_IDS.CHARACTER_PRIMARY_A,
						"name_key": "character_primary_a_name",
						"desc_key": "character_primary_a_desc",
						"unlocked": true,
						"details": {
							"base_stats": {
								"max_hp": 500.0,
								"move_speed": 230.0,
							},
							"passive_id": "passive_primary_a_guard",
							"hero_skill_ids": [
								"skill_deploy_projectile_barrier",
								"skill_aoe_slow",
							],
						},
					},
					_locked_entry(CONTENT_UNLOCK_TYPES.CHARACTER),
				]
			CONTENT_UNLOCK_TYPES.GEAR_MOD:
				return [
					{
						"id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
						"name_key": "gear_mod_weapon_damage_test_name",
						"desc_key": "gear_mod_weapon_damage_test_desc",
						"unlocked": true,
						"details": {
							"slot": "weapon",
							"rarity": "common",
							"max_rank": 5,
						},
					},
					_locked_entry(CONTENT_UNLOCK_TYPES.GEAR_MOD),
				]
			CONTENT_UNLOCK_TYPES.ENEMY:
				return [
					{
						"id": "enemy_chaser",
						"name_key": "enemy_chaser_name",
						"desc_key": "enemy_chaser_name",
						"unlocked": true,
						"details": {
							"max_hp": 12,
							"move_speed": 110.0,
							"gold_value_multiplier": 1.0,
						},
					},
					_locked_entry(CONTENT_UNLOCK_TYPES.ENEMY),
				]
			_:
				return []


	func requirement_status(
		_entry_type: String,
		entry_id: String
	) -> Dictionary:
		if not entry_id.contains("locked"):
			return {
				"complete": true,
				"conditions": [],
			}
		return {
			"complete": false,
			"mode": CONTENT_UNLOCK_RULE_MODES.ALL,
			"conditions": [
				{
					"counter_id": CONTENT_UNLOCK_PROGRESS_COUNTERS.RUNS_COMPLETED,
					"current": 1,
					"pending": 2,
					"target": 5,
				},
			],
		}


	func pending_run_preview() -> Dictionary:
		return {
			CONTENT_UNLOCK_TYPES.CHARACTER: ["character_locked"],
			CONTENT_UNLOCK_TYPES.GEAR_MOD: [],
			CONTENT_UNLOCK_TYPES.ENEMY: [],
		}


	func _locked_entry(entry_type: String) -> Dictionary:
		return {
			"id": "%s_locked" % entry_type,
			"name_key": "secret_locked_name",
			"desc_key": "secret_locked_description",
			"icon_path": "res://secret_locked_icon.png",
			"unlocked": false,
			"details": {
				"max_hp": 987654,
				"slot": "secret_locked_slot",
			},
		}
