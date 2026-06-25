extends Node


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
	_expect(GearModSystem.current_modifiers(GEAR_MOD_SLOTS.WEAPON, SMOKE_SLOT).is_empty(), "dropped but unequipped Mod should not affect current modifiers")

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


func _array_or_empty(raw_value: Variant) -> Array:
	if raw_value is Array:
		return (raw_value as Array).duplicate(true)
	return []


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
