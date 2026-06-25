extends Node


const GEAR_MOD_PANEL_SCENE := preload("res://scenes/ui/gear_mod_panel.tscn")
const GAMEPLAY_HUD_SCENE := preload("res://scenes/gameplay/gameplay_hud.tscn")
const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const GEAR_MOD_RESOURCES := preload("res://scripts/contracts/gear_mod_resources.gd")
const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

const SMOKE_SLOT: String = "gear_mod_smoke"

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SaveManager.delete(SMOKE_SLOT, SAVE_KINDS.META)
	RNG.set_run_seed(101)

	var initial_profile: Dictionary = GearModSystem.load_or_create_profile(SMOKE_SLOT)
	_expect(initial_profile.has("gear_mods"), "fresh profile should include gear_mods payload")
	var initial_summary: Dictionary = GearModSystem.profile_summary(SMOKE_SLOT)
	_expect(int(initial_summary.get("inventory_count", -1)) == 0, "fresh Gear Mod inventory should start empty")

	var grant: Dictionary = GearModSystem.grant_mod(GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST, 1, SMOKE_SLOT)
	var instance_id: String = _first_instance_id(grant)
	_expect(bool(grant.get("ok", false)) and not instance_id.is_empty(), "grant_mod should create one weapon damage Mod instance")
	_expect(
		not bool(GearModSystem.equip_mod(GEAR_MOD_SLOTS.HERO, instance_id, SMOKE_SLOT).get("ok", false)),
		"weapon Mod should not equip into hero loadout"
	)
	_expect(bool(GearModSystem.equip_mod(GEAR_MOD_SLOTS.WEAPON, instance_id, SMOKE_SLOT).get("ok", false)), "weapon Mod should equip into weapon loadout")
	_expect(_has_modifier(GearModSystem.current_modifiers(GEAR_MOD_SLOTS.WEAPON, SMOKE_SLOT), STATS.DAMAGE, "mult", 1.1), "rank 0 weapon damage Mod should output 1.10x damage")
	_expect(
		String(GearModSystem.upgrade_mod(instance_id, SMOKE_SLOT).get("reason", "")) == "insufficient_resource",
		"upgrade should require gear mod dust"
	)

	var duplicate_grant: Dictionary = GearModSystem.grant_mod(GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST, 3, SMOKE_SLOT)
	var duplicate_ids: Array[String] = _instance_ids(duplicate_grant)
	_expect(duplicate_ids.size() == 3, "grant_mod count should create independent instances")
	_expect(
		String(GearModSystem.equip_mod(GEAR_MOD_SLOTS.WEAPON, duplicate_ids[0], SMOKE_SLOT).get("reason", "")) == "duplicate_mod",
		"unique_by_id should reject duplicate equipped Mod id"
	)
	_expect(bool(GearModSystem.dismantle_mod(duplicate_ids[1], SMOKE_SLOT).get("ok", false)), "dismantling an unequipped duplicate should succeed")
	var second_dismantle: Dictionary = GearModSystem.dismantle_mod(duplicate_ids[2], SMOKE_SLOT)
	_expect(bool(second_dismantle.get("ok", false)), "dismantling a second duplicate should succeed")
	_expect(_resource_balance(second_dismantle, GEAR_MOD_RESOURCES.GEAR_MOD_DUST) == 20, "two dismantles should produce the first upgrade cost")

	_expect(bool(GearModSystem.debug_set_loadout_capacity(GEAR_MOD_SLOTS.WEAPON, 2, SMOKE_SLOT).get("ok", false)), "debug capacity setter should update weapon capacity")
	_expect(
		String(GearModSystem.upgrade_mod(instance_id, SMOKE_SLOT).get("reason", "")) == "capacity_exceeded",
		"upgrading an equipped Mod should fail if rank drain would exceed capacity"
	)
	_expect(bool(GearModSystem.debug_set_loadout_capacity(GEAR_MOD_SLOTS.WEAPON, 8, SMOKE_SLOT).get("ok", false)), "debug capacity setter should restore weapon capacity")
	var upgrade: Dictionary = GearModSystem.upgrade_mod(instance_id, SMOKE_SLOT)
	_expect(bool(upgrade.get("ok", false)), "upgrade should consume dust and increase Mod rank")
	_expect(int(upgrade.get("rank", 0)) == 1, "upgrade should raise Mod to rank 1")
	_expect(_has_modifier(GearModSystem.current_modifiers(GEAR_MOD_SLOTS.WEAPON, SMOKE_SLOT), STATS.DAMAGE, "mult", 1.15), "rank 1 weapon damage Mod should output 1.15x damage")
	_expect(
		String(GearModSystem.dismantle_mod(instance_id, SMOKE_SLOT).get("reason", "")) == "equipped",
		"equipped Mod should not dismantle"
	)
	_expect(bool(GearModSystem.unequip_mod(GEAR_MOD_SLOTS.WEAPON, instance_id, SMOKE_SLOT).get("ok", false)), "unequip should remove Mod from weapon loadout")
	_expect(bool(GearModSystem.dismantle_mod(instance_id, SMOKE_SLOT).get("ok", false)), "unequipped upgraded Mod should dismantle")

	var drop: Dictionary = GearModSystem.roll_drop_for_enemy(POOL_IDS.ENEMY_CHASER, 1, SMOKE_SLOT, 0.0)
	_expect(bool(drop.get("ok", false)) and _array_or_empty(drop.get("drops", [])).size() == 1, "forced enemy_chaser drop should grant the test Mod")
	var drop_rows: Array = _array_or_empty(drop.get("drops", []))
	var first_drop: Dictionary = drop_rows[0] as Dictionary if not drop_rows.is_empty() and drop_rows[0] is Dictionary else {}
	_expect(
		String(first_drop.get("name_key", "")) == "gear_mod_weapon_damage_test_name",
		"forced enemy_chaser drop should include the dropped Mod display key"
	)
	_expect(GearModSystem.current_modifiers(GEAR_MOD_SLOTS.WEAPON, SMOKE_SLOT).is_empty(), "dropped but unequipped Mod should not affect current modifiers")

	await _expect_hud_drop_feedback()
	await _expect_panel_flow()

	SaveManager.delete(SMOKE_SLOT, SAVE_KINDS.META)
	_finish()


func _first_instance_id(result: Dictionary) -> String:
	var ids: Array = _array_or_empty(result.get("instance_ids", []))
	return String(ids[0]) if not ids.is_empty() else ""


func _instance_ids(result: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in _array_or_empty(result.get("instance_ids", [])):
		ids.append(String(raw_id))
	return ids


func _resource_balance(result: Dictionary, resource_id: String) -> int:
	var profile: Dictionary = result.get("profile", {}) as Dictionary
	var gear_state: Dictionary = profile.get("gear_mods", {}) as Dictionary
	var resources: Dictionary = gear_state.get("resources", {}) as Dictionary
	return int(resources.get(resource_id, 0))


func _has_modifier(modifiers: Array[Dictionary], stat_id: String, modifier_type: String, value: float) -> bool:
	for modifier: Dictionary in modifiers:
		if String(modifier.get("stat", "")) != stat_id:
			continue
		if String(modifier.get("type", "")) != modifier_type:
			continue
		if is_equal_approx(float(modifier.get("value", 0.0)), value):
			return true
	return false


func _expect_panel_flow() -> void:
	SaveManager.delete(SMOKE_SLOT, SAVE_KINDS.META)
	var grant: Dictionary = GearModSystem.grant_mod(GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST, 1, SMOKE_SLOT)
	var instance_id: String = _first_instance_id(grant)
	GearModSystem.debug_grant_resource(GEAR_MOD_RESOURCES.GEAR_MOD_DUST, 20, SMOKE_SLOT)

	var panel: CanvasLayer = GEAR_MOD_PANEL_SCENE.instantiate() as CanvasLayer
	panel.name = "GearModPanel"
	add_child(panel)
	panel.configure(SMOKE_SLOT)
	await get_tree().process_frame

	var title_label: Label = _find_node_by_name(panel, "TitleLabel") as Label
	var resource_label: Label = _find_node_by_name(panel, "ResourceLabel") as Label
	var row: Button = _find_node_by_name(panel, "GearModRow_%s" % instance_id) as Button
	var details_label: Label = _find_node_by_name(panel, "DetailsLabel") as Label
	var equip_button: Button = _find_node_by_name(panel, "EquipButton") as Button
	var upgrade_button: Button = _find_node_by_name(panel, "UpgradeButton") as Button
	var dismantle_button: Button = _find_node_by_name(panel, "DismantleButton") as Button
	var feedback_label: Label = _find_node_by_name(panel, "FeedbackLabel") as Label
	_expect(title_label != null and String(title_label.text) == tr("ui_gear_mod_title"), "GearModPanel should show localized title")
	Localization.set_locale("en")
	await get_tree().process_frame
	_expect(title_label != null and String(title_label.text) == "Gear Mods", "GearModPanel should refresh title after locale change")
	Localization.set_locale("zh_CN")
	await get_tree().process_frame
	row = _find_node_by_name(panel, "GearModRow_%s" % instance_id) as Button
	_expect(
		resource_label != null and String(resource_label.text).find("20") >= 0,
		"GearModPanel should show gear mod resource balance; text=%s" % [
			String(resource_label.text) if resource_label != null else "<missing>",
		]
	)
	_expect(row != null and String(row.text).find(tr("gear_mod_weapon_damage_test_name")) >= 0, "GearModPanel should build a row for the granted weapon Mod")
	_expect(
		details_label != null and String(details_label.text).find("+10%") >= 0,
		"GearModPanel should show rank 0 damage effect; text=%s" % [
			String(details_label.text) if details_label != null else "<missing>",
		]
	)

	if equip_button != null:
		equip_button.pressed.emit()
	_expect(_has_modifier(GearModSystem.current_modifiers(GEAR_MOD_SLOTS.WEAPON, SMOKE_SLOT), STATS.DAMAGE, "mult", 1.1), "GearModPanel equip button should equip the selected Mod")
	_expect(dismantle_button != null and dismantle_button.disabled, "GearModPanel should disable dismantle for equipped Mods")

	if upgrade_button != null:
		upgrade_button.pressed.emit()
	_expect(_has_modifier(GearModSystem.current_modifiers(GEAR_MOD_SLOTS.WEAPON, SMOKE_SLOT), STATS.DAMAGE, "mult", 1.15), "GearModPanel upgrade button should raise the selected Mod rank")
	_expect(
		feedback_label != null and feedback_label.visible and String(feedback_label.text).find(tr("gear_mod_weapon_damage_test_name")) >= 0,
		"GearModPanel should show action feedback with the Mod name; text=%s" % [
			String(feedback_label.text) if feedback_label != null else "<missing>",
		]
	)

	if equip_button != null:
		equip_button.pressed.emit()
	if dismantle_button != null:
		dismantle_button.pressed.emit()
	_expect(int(GearModSystem.profile_summary(SMOKE_SLOT).get("inventory_count", -1)) == 0, "GearModPanel dismantle button should remove an unequipped Mod")

	remove_child(panel)
	panel.queue_free()


func _expect_hud_drop_feedback() -> void:
	var hud: CanvasLayer = GAMEPLAY_HUD_SCENE.instantiate() as CanvasLayer
	hud.name = "GameplayHud"
	add_child(hud)
	await get_tree().process_frame

	hud.call("show_gear_mod_drop_feedback", "gear_mod_weapon_damage_test_name")
	await get_tree().process_frame
	var feedback_label: Label = _find_node_by_name(hud, "UpgradeFeedbackLabel") as Label
	_expect(
		tr("ui_gear_mod_drop_obtained") != "ui_gear_mod_drop_obtained"
		and tr("gear_mod_weapon_damage_test_name") != "gear_mod_weapon_damage_test_name",
		"Gear Mod drop feedback keys should resolve through imported translations"
	)
	var expected_text: String = tr("ui_gear_mod_drop_obtained").format({
		"name": tr("gear_mod_weapon_damage_test_name"),
	})
	_expect(
		feedback_label != null
		and feedback_label.visible
		and String(feedback_label.text) == expected_text,
		"GameplayHud should show localized Gear Mod drop feedback; text=%s expected=%s" % [
			String(feedback_label.text) if feedback_label != null else "<missing>",
			expected_text,
		]
	)

	Localization.set_locale("en")
	await get_tree().process_frame
	expected_text = tr("ui_gear_mod_drop_obtained").format({
		"name": tr("gear_mod_weapon_damage_test_name"),
	})
	_expect(
		feedback_label != null
		and String(feedback_label.text) == expected_text,
		"GameplayHud Gear Mod drop feedback should refresh after locale change; text=%s expected=%s" % [
			String(feedback_label.text) if feedback_label != null else "<missing>",
			expected_text,
		]
	)

	Localization.set_locale("zh_CN")
	remove_child(hud)
	hud.queue_free()


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


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
	push_error("[GearModSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[GearModSmoke] passed")
		get_tree().quit(0)
		return
	print("[GearModSmoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
