extends Node


const META_PROGRESSION_PANEL_SCENE := preload("res://scenes/ui/meta_progression_panel.tscn")
const TITLE_MENU_SCENE := preload("res://scenes/ui/title_menu.tscn")
const META_CURRENCIES := preload("res://scripts/contracts/meta_currencies.gd")
const META_UNLOCKS := preload("res://scripts/contracts/meta_unlocks.gd")
const META_UPGRADES := preload("res://scripts/contracts/meta_upgrades.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)

	var initial_profile: Dictionary = MetaProgressionSystem.load_or_create_profile()
	_expect(SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META), "load_or_create_profile should create a meta save")
	_expect(int(initial_profile.get("account_level", 0)) == 1, "fresh meta profile should start at account level 1")
	_expect(int((initial_profile.get("currencies", {}) as Dictionary).get(META_CURRENCIES.META_ESSENCE, -1)) == 0, "fresh meta profile should start with default currency")
	_expect(_has_unlock(initial_profile, META_UNLOCKS.UNLOCK_CHARACTER_DEFAULT), "fresh meta profile should include default unlocks")

	var settlement: Dictionary = MetaProgressionSystem.apply_run_settlement({
		"run_time": 600.0,
		"kills": 250,
		"first_boss_defeated": true,
	})
	_expect(bool(settlement.get("ok", false)), "settlement should save the meta profile")
	_expect(int(settlement.get("currency_amount", 0)) == 48, "settlement should apply configured currency formula")
	_expect(int(settlement.get("account_xp", 0)) == 125, "settlement should apply configured account XP formula")
	_expect(int(settlement.get("account_level", 0)) == 2, "settlement should raise account level from thresholds")
	var settled_profile: Dictionary = settlement.get("profile", {}) as Dictionary
	_expect(_has_unlock(settled_profile, META_UNLOCKS.UNLOCK_RELIC_POOL_BASIC), "level rewards should grant configured unlocks")
	_expect(int((settled_profile.get("currencies", {}) as Dictionary).get(META_CURRENCIES.META_ESSENCE, 0)) == 48, "settlement should persist currency balance")
	_expect(_profile_summary_matches_settlement(), "profile_summary should expose the title-menu balance")
	_expect(_has_affordable_upgrade_summary(META_UPGRADES.META_UPGRADE_DAMAGE, 18), "upgrade_summaries should expose affordable upgrade rows")
	_expect(_has_affordable_upgrade_summary(META_UPGRADES.META_UPGRADE_FIRE_RATE, 22), "upgrade_summaries should expose the new fire-rate upgrade row")
	_expect(_title_menu_shows_meta_summary(true, 48), "title menu should show meta summary and available upgrade affordance")
	_expect(_meta_panel_builds_upgrade_list(), "meta progression panel should build the visible upgrade list")

	var roundtrip_profile: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	_expect(int(roundtrip_profile.get("account_xp", 0)) == 125, "meta save should roundtrip account XP through SaveManager")
	_expect(_has_unlock(roundtrip_profile, META_UNLOCKS.UNLOCK_RELIC_POOL_BASIC), "meta save should roundtrip unlocks through SaveManager")

	var purchased_profile: Dictionary = _purchase_damage_upgrade_through_panel()
	_expect(int((purchased_profile.get("currencies", {}) as Dictionary).get(META_CURRENCIES.META_ESSENCE, 0)) == 30, "purchase_upgrade should deduct configured cost")
	_expect(_title_menu_shows_meta_summary(true, 30), "title menu meta summary should refresh after purchases leave affordable upgrades")
	_expect(not MetaProgressionSystem.first_available_purchase().is_empty(), "remaining balance should expose the next affordable purchase")

	var fire_rate_result: Dictionary = MetaProgressionSystem.purchase_upgrade(META_UPGRADES.META_UPGRADE_FIRE_RATE)
	_expect(bool(fire_rate_result.get("ok", false)), "new fire-rate upgrade should be purchasable from data")
	var fire_rate_profile: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	_expect(int((fire_rate_profile.get("currencies", {}) as Dictionary).get(META_CURRENCIES.META_ESSENCE, 0)) == 8, "fire-rate upgrade should deduct configured cost")
	_expect(int((fire_rate_profile.get("purchased_upgrades", {}) as Dictionary).get(META_UPGRADES.META_UPGRADE_FIRE_RATE, 0)) == 1, "fire-rate purchase should persist the purchased level")

	var modifiers: Array[Dictionary] = MetaProgressionSystem.current_modifiers()
	_expect(_has_modifier(modifiers, STATS.DAMAGE, "add", 0.25), "purchased upgrade should expose next-run damage modifier")
	_expect(_has_modifier(modifiers, STATS.FIRE_RATE, "add", 0.12), "new fire-rate upgrade should expose next-run weapon modifier")

	_finish()


func _profile_summary_matches_settlement() -> bool:
	var summary: Dictionary = MetaProgressionSystem.profile_summary()
	return (
		int(summary.get("account_level", 0)) == 2
		and String(summary.get("currency_id", "")) == META_CURRENCIES.META_ESSENCE
		and int(summary.get("currency_amount", -1)) == 48
	)


func _has_affordable_upgrade_summary(upgrade_id: String, expected_cost: int) -> bool:
	for summary: Dictionary in MetaProgressionSystem.upgrade_summaries():
		if String(summary.get("upgrade_id", "")) != upgrade_id:
			continue
		return (
			bool(summary.get("can_purchase", false))
			and int(summary.get("current_level", -1)) == 0
			and int(summary.get("cost", 0)) == expected_cost
		)
	return false


func _title_menu_shows_meta_summary(expect_available: bool, expected_balance: int) -> bool:
	var menu: CanvasLayer = TITLE_MENU_SCENE.instantiate() as CanvasLayer
	menu.name = "TitleMenu"
	add_child(menu)
	menu.call("configure", false, "")
	var summary_label: Label = _find_node_by_name(menu, "MetaProfileSummaryLabel") as Label
	var meta_button: Button = _find_node_by_name(menu, "MetaProgressionButton") as Button
	var expected_currency_name: String = tr("meta_currency_essence_name")
	var expected_summary_text: String = tr("ui_meta_title_summary").format({
		"level": 2,
		"currency": expected_currency_name,
		"amount": expected_balance,
	})
	var expected_button_text: String = (
		tr("ui_meta_progression_available") if expect_available else tr("ui_meta_progression")
	)
	var result: bool = (
		summary_label != null
		and String(summary_label.text) == expected_summary_text
		and meta_button != null
		and String(meta_button.text) == expected_button_text
	)
	remove_child(menu)
	menu.queue_free()
	return result


func _meta_panel_builds_upgrade_list() -> bool:
	var panel: CanvasLayer = META_PROGRESSION_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "MetaProgressionPanel"
	add_child(panel)
	var currency_label: Node = _find_node_by_name(panel, "MetaCurrencyLabel")
	var upgrade_list: Node = _find_node_by_name(panel, "MetaUpgradeList")
	var status_label: Label = _find_node_by_name(panel, "MetaUpgradeStatus_%s" % META_UPGRADES.META_UPGRADE_DAMAGE) as Label
	var row_count: int = upgrade_list.get_child_count() if upgrade_list != null else 0
	var expected_currency_name: String = tr("meta_currency_essence_name")
	var expected_balance_text: String = tr("ui_meta_balance").format({
		"currency": expected_currency_name,
		"amount": 48,
	})
	var expected_cost_text: String = tr("ui_meta_upgrade_cost").format({
		"currency": expected_currency_name,
		"cost": 18,
	})
	var status_text: String = String(status_label.text) if status_label != null else ""
	remove_child(panel)
	panel.queue_free()
	return (
		currency_label != null
		and row_count >= MetaProgressionSystem.upgrade_summaries().size()
		and status_label != null
		and status_text.find(expected_balance_text) >= 0
		and status_text.find(expected_cost_text) >= 0
	)


func _purchase_damage_upgrade_through_panel() -> Dictionary:
	var panel: CanvasLayer = META_PROGRESSION_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "MetaProgressionPanel"
	add_child(panel)

	var purchase_button: Button = _find_node_by_name(panel, "Purchase_%s" % META_UPGRADES.META_UPGRADE_DAMAGE) as Button
	_expect(purchase_button != null and not purchase_button.disabled, "MetaProgressionPanel should expose an enabled damage purchase button")
	if purchase_button != null:
		purchase_button.pressed.emit()

	var feedback_label: Label = _find_node_by_name(panel, "MetaPurchaseFeedbackLabel") as Label
	_expect(
		feedback_label != null
		and feedback_label.visible
		and String(feedback_label.text).find(tr("meta_upgrade_damage_name")) >= 0,
		"MetaProgressionPanel should show purchase feedback with the bought upgrade name; text=%s expected_name=%s visible=%s" % [
			String(feedback_label.text) if feedback_label != null else "<missing>",
			tr("meta_upgrade_damage_name"),
			str(feedback_label != null and feedback_label.visible),
		]
	)
	var purchased_profile: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	_expect(int((purchased_profile.get("purchased_upgrades", {}) as Dictionary).get(META_UPGRADES.META_UPGRADE_DAMAGE, 0)) == 1, "panel purchase should persist the purchased level")

	remove_child(panel)
	panel.queue_free()
	return purchased_profile


func _has_unlock(profile: Dictionary, unlock_id: String) -> bool:
	var unlocked_ids: Array = profile.get("unlocked_ids", []) as Array
	return unlocked_ids.has(unlock_id)


func _has_modifier(modifiers: Array[Dictionary], stat_id: String, modifier_type: String, value: float) -> bool:
	for modifier: Dictionary in modifiers:
		if String(modifier.get("stat", "")) != stat_id:
			continue
		if String(modifier.get("type", "")) != modifier_type:
			continue
		if is_equal_approx(float(modifier.get("value", 0.0)), value):
			return true
	return false


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child: Node in root.get_children():
		var found: Node = _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[MetaProgressionSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[MetaProgressionSmoke] passed; modifiers=%d" % MetaProgressionSystem.current_modifiers().size())
		get_tree().quit(0)
		return
	print("[MetaProgressionSmoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
