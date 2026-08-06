extends Node


const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const GEAR_MOD_RARITIES := preload(
	"res://scripts/contracts/gear_mod_rarities.gd"
)
const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")
const GAMEPLAY_HUD_SCENE := preload(
	"res://scenes/gameplay/gameplay_hud.tscn"
)
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const PLAYER_SCENE := preload(
	"res://scenes/gameplay/actors/player_base.tscn"
)
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const WEAPON_SYSTEM_SCRIPT := preload(
	"res://scripts/gameplay/weapon_system.gd"
)
const WORLD_EVENT_MOD_POOL_IDS := preload(
	"res://scripts/contracts/world_event_mod_pool_ids.gd"
)

const SMOKE_SLOT: String = "gear_mod_smoke"

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SaveManager.delete(SMOKE_SLOT, SAVE_KINDS.META)
	var sentinel: Dictionary = {
		"sentinel": "gear_mod_rules_must_not_write_meta",
		"gear_mods": {"legacy": true},
	}
	_expect(
		SaveManager.save(SMOKE_SLOT, SAVE_KINDS.META, sentinel),
		"smoke sentinel meta should save"
	)
	RNG.set_run_seed(101)

	_expect_data_contract()
	_expect_rank_curves()
	_expect_preview()
	_expect_drop_rules()
	_expect_modifier_layers()
	_expect_hud_feedback()

	var unchanged_meta: Dictionary = SaveManager.load(
		SMOKE_SLOT,
		SAVE_KINDS.META
	)
	_expect(
		unchanged_meta == sentinel,
		"Gear Mod rule queries and rolls must not mutate meta saves"
	)
	SaveManager.delete(SMOKE_SLOT, SAVE_KINDS.META)
	_finish()


func _expect_data_contract() -> void:
	var definition: Dictionary = GearModSystem.mod_definition(
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
	)
	_expect(
		String(definition.get("slot", "")) == GEAR_MOD_SLOTS.WEAPON,
		"weapon damage Mod should preserve its weapon slot"
	)
	_expect(
		String(definition.get("rarity", "")) == GEAR_MOD_RARITIES.COMMON,
		"weapon damage Mod should preserve its rarity"
	)
	_expect(
		not definition.has("base_drain")
		and not definition.has("drain_per_rank")
		and not definition.has("dismantle"),
		"Gear Mod v2 definitions should not expose drain or dismantle"
	)
	_expect(
		GearModSystem.max_rank(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		) == 5,
		"weapon damage Mod should expose max rank 5"
	)
	_expect(
		GearModSystem.overflow_gold() == 75,
		"overflow duplicate conversion should be 75 gold"
	)
	var reward_ids: Array[String] = GearModSystem.reward_pool_ids(
		WORLD_EVENT_MOD_POOL_IDS.WORLD_EVENT_MOD_POOL_COMMON
	)
	_expect(
		reward_ids == [
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
		],
		"common reward pool should list all three Gear Mods at equal weight"
	)


func _expect_rank_curves() -> void:
	_expect_modifier(
		GearModSystem.rank_modifiers(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			0
		),
		STATS.DAMAGE,
		1.1,
		"rank 0 damage curve"
	)
	_expect_modifier(
		GearModSystem.rank_modifiers(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			5
		),
		STATS.DAMAGE,
		1.35,
		"rank 5 damage curve"
	)
	for rank: int in range(6):
		var expected_value: float = 0.9 - float(rank) * 0.05
		_expect_modifier(
			GearModSystem.rank_modifiers(
				GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER,
				rank
			),
			STATS.RECOIL,
			expected_value,
			"recoil rank %d curve" % rank
		)
		_expect_modifier(
			GearModSystem.rank_modifiers(
				GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
				rank
			),
			STATS.SPREAD_ANGLE_MAX,
			expected_value,
			"spread rank %d curve" % rank
		)


func _expect_preview() -> void:
	var preview: Dictionary = GearModSystem.resolve_preview_loadout([
		{
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"rank": 99,
		},
		{
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			"rank": 1,
		},
		{
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
			"rank": 3,
		},
	])
	var selected: Array = _array_or_empty(preview.get("selected", []))
	var diagnostics: Array = _array_or_empty(preview.get("diagnostics", []))
	_expect(
		selected.size() == 2
		and int((selected[0] as Dictionary).get("rank", -1)) == 5,
		"preview should clamp rank and omit duplicate selections"
	)
	_expect(
		_has_reason(diagnostics, "rank_clamped")
		and _has_reason(diagnostics, "duplicate_unique_mod"),
		"preview should diagnose clamped rank and duplicate Mod"
	)
	var modifiers_by_slot: Dictionary = preview.get(
		"modifiers",
		{}
	) as Dictionary
	var weapon_modifiers: Array = _array_or_empty(
		modifiers_by_slot.get(GEAR_MOD_SLOTS.WEAPON, [])
	)
	_expect(
		_has_modifier(weapon_modifiers, STATS.DAMAGE, 1.35)
		and _has_modifier(
			weapon_modifiers,
			STATS.SPREAD_ANGLE_MAX,
			0.75
		),
		"preview should resolve selected rank modifiers without capacity"
	)
	_expect(
		not preview.has("capacity") and not preview.has("used_drain"),
		"preview should not expose retired capacity or drain fields"
	)


func _expect_drop_rules() -> void:
	_expect_drop_chance(
		POOL_IDS.ENEMY_CHASER,
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		0.05
	)
	_expect_drop_chance(
		POOL_IDS.ENEMY_BULWARK,
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER,
		0.15
	)
	_expect_drop_chance(
		POOL_IDS.ENEMY_SPITTER,
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
		0.025
	)


func _expect_modifier_layers() -> void:
	var weapon: WeaponSystem = WEAPON_SYSTEM_SCRIPT.new() as WeaponSystem
	weapon.configure(
		null,
		null,
		{"base_stats": {STATS.DAMAGE: 10.0}}
	)
	weapon.apply_modifiers([
		{"stat": STATS.DAMAGE, "type": "add", "value": 2.0},
		{"stat": STATS.DAMAGE, "type": "mult", "value": 2.0},
	])
	var weapon_gear_modifiers: Array = [
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.5},
	]
	weapon.set_gear_modifiers(weapon_gear_modifiers)
	weapon.set_gear_modifiers(weapon_gear_modifiers)
	_expect(
		is_equal_approx(weapon.stat_value(STATS.DAMAGE), 36.0),
		"weapon Gear modifier replacement should be idempotent"
	)
	var weapon_snapshot: Dictionary = weapon.snapshot()
	_expect(
		not weapon_snapshot.has("gear_stat_additions")
		and not weapon_snapshot.has("gear_stat_multipliers"),
		"weapon snapshot should keep Gear modifiers run-owned"
	)
	weapon.apply_modifiers([
		{"stat": STATS.DAMAGE, "type": "add", "value": 10.0},
	])
	weapon.restore_snapshot(weapon_snapshot)
	_expect(
		is_equal_approx(weapon.stat_value(STATS.DAMAGE), 36.0),
		"weapon restore should restore ordinary modifiers and preserve Gear layer"
	)
	weapon.free()

	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.configure({STATS.MAX_HP: 100.0})
	player.apply_modifiers([
		{"stat": STATS.MAX_HP, "type": "add", "value": 20.0},
		{"stat": STATS.MAX_HP, "type": "mult", "value": 1.1},
	])
	var player_gear_modifiers: Array = [
		{"stat": STATS.MAX_HP, "type": "mult", "value": 1.5},
	]
	player.set_gear_modifiers(player_gear_modifiers)
	player.set_gear_modifiers(player_gear_modifiers)
	_expect(
		is_equal_approx(player.max_life(), 198.0),
		"player Gear modifier replacement should be idempotent"
	)
	var player_snapshot: Dictionary = player.snapshot()
	_expect(
		not player_snapshot.has("gear_stat_additions")
		and not player_snapshot.has("gear_stat_multipliers"),
		"player snapshot should keep Gear modifiers run-owned"
	)
	player.apply_modifiers([
		{"stat": STATS.MAX_HP, "type": "add", "value": 10.0},
	])
	player.restore_snapshot(player_snapshot)
	_expect(
		is_equal_approx(player.max_life(), 198.0),
		"player restore should restore ordinary modifiers and preserve Gear layer"
	)
	remove_child(player)
	player.free()


func _expect_drop_chance(
	enemy_id: String,
	mod_id: String,
	chance: float
) -> void:
	var hit: Dictionary = GearModSystem.roll_drop_for_enemy(
		enemy_id,
		1,
		chance
	)
	var miss: Dictionary = GearModSystem.roll_drop_for_enemy(
		enemy_id,
		1,
		chance + 0.0001
	)
	var drops: Array = _array_or_empty(hit.get("drops", []))
	_expect(
		drops.size() == 1
		and String((drops[0] as Dictionary).get("mod_id", "")) == mod_id
		and is_equal_approx(
			float((drops[0] as Dictionary).get("chance", -1.0)),
			chance
		),
		"%s should drop %s at configured boundary %.3f"
		% [enemy_id, mod_id, chance]
	)
	_expect(
		_array_or_empty(miss.get("drops", [])).is_empty(),
		"%s should miss immediately above configured chance" % enemy_id
	)


func _expect_hud_feedback() -> void:
	var hud: CanvasLayer = GAMEPLAY_HUD_SCENE.instantiate() as CanvasLayer
	add_child(hud)
	hud.call(
		"show_gear_mod_drop_feedback",
		"gear_mod_weapon_damage_test_name",
		3,
		0
	)
	var normal_context: Dictionary = hud.get(
		"_last_feedback_context"
	) as Dictionary
	_expect(
		String(hud.get("_last_upgrade_feedback_key"))
		== "ui_gear_mod_drop_obtained"
		and int(normal_context.get("rank", 0)) == 3,
		"Gear Mod HUD feedback should expose the acquired display rank"
	)
	hud.call(
		"show_gear_mod_drop_feedback",
		"gear_mod_weapon_damage_test_name",
		6,
		75
	)
	var overflow_context: Dictionary = hud.get(
		"_last_feedback_context"
	) as Dictionary
	_expect(
		String(hud.get("_last_upgrade_feedback_key"))
		== "ui_gear_mod_overflow_gold"
		and int(overflow_context.get("rank", 0)) == 6
		and int(overflow_context.get("gold", 0)) == 75
		and bool(hud.call("is_gear_mod_drop_feedback_visible")),
		"max-rank HUD feedback should expose the 75-gold overflow"
	)
	remove_child(hud)
	hud.free()


func _expect_modifier(
	modifiers: Array,
	stat_id: String,
	value: float,
	label: String
) -> void:
	_expect(
		_has_modifier(modifiers, stat_id, value),
		"%s should resolve %s=%.3f" % [label, stat_id, value]
	)


func _has_modifier(
	modifiers: Array,
	stat_id: String,
	value: float
) -> bool:
	for raw_modifier: Variant in modifiers:
		if not raw_modifier is Dictionary:
			continue
		var modifier: Dictionary = raw_modifier as Dictionary
		if (
			String(modifier.get("stat", "")) == stat_id
			and String(modifier.get("type", "")) == "mult"
			and is_equal_approx(float(modifier.get("value", 0.0)), value)
		):
			return true
	return false


func _has_reason(diagnostics: Array, reason: String) -> bool:
	for raw_diagnostic: Variant in diagnostics:
		if (
			raw_diagnostic is Dictionary
			and String((raw_diagnostic as Dictionary).get("reason", ""))
			== reason
		):
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
