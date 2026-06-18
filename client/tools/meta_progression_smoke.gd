extends Node


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

	var roundtrip_profile: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	_expect(int(roundtrip_profile.get("account_xp", 0)) == 125, "meta save should roundtrip account XP through SaveManager")
	_expect(_has_unlock(roundtrip_profile, META_UNLOCKS.UNLOCK_RELIC_POOL_BASIC), "meta save should roundtrip unlocks through SaveManager")

	var purchase: Dictionary = MetaProgressionSystem.purchase_upgrade(META_UPGRADES.META_UPGRADE_DAMAGE)
	_expect(bool(purchase.get("ok", false)), "purchase_upgrade should save an affordable upgrade")
	_expect(int(purchase.get("level", 0)) == 1, "purchase_upgrade should increment the purchased level")
	var purchased_profile: Dictionary = purchase.get("profile", {}) as Dictionary
	_expect(int((purchased_profile.get("currencies", {}) as Dictionary).get(META_CURRENCIES.META_ESSENCE, 0)) == 30, "purchase_upgrade should deduct configured cost")

	var modifiers: Array[Dictionary] = MetaProgressionSystem.current_modifiers()
	_expect(_has_modifier(modifiers, STATS.DAMAGE, "add", 0.25), "purchased upgrade should expose next-run damage modifier")
	_expect(not MetaProgressionSystem.first_available_purchase().is_empty(), "remaining balance should expose the next affordable purchase")

	_finish()


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
