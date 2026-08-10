extends Node


const GEAR_MOD_IDS := preload("res://scripts/contracts/gear_mod_ids.gd")
const GEAR_MOD_BOARD_SCRIPT := preload(
	"res://scripts/gameplay/gear_mod_board.gd"
)
const EFFECT_ACTIONS := preload("res://scripts/contracts/effect_actions.gd")
const EFFECT_CONDITIONS := preload(
	"res://scripts/contracts/effect_conditions.gd"
)
const EFFECT_TRIGGERS := preload("res://scripts/contracts/effect_triggers.gd")
const GEAR_MOD_BOARD_RULES := preload(
	"res://scripts/contracts/gear_mod_board_rules.gd"
)
const GEAR_MOD_COMPONENT_TYPES := preload(
	"res://scripts/contracts/gear_mod_component_types.gd"
)
const GEAR_MOD_PLACEMENT_OUTCOMES := preload(
	"res://scripts/contracts/gear_mod_placement_outcomes.gd"
)
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
	_expect_fixed_modifiers()
	_expect_preview()
	_expect_drop_rules()
	_expect_board_domain()
	_expect_composite_components()
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
	var payload: Dictionary = DataLoader.load_json(
		DataLoader.GEAR_MODS_PATH
	) as Dictionary
	_expect(
		int(payload.get("schema_version", 0)) == 6
		and not payload.has("overflow_gold"),
		"Gear Mod schema v6 should not expose overflow conversion data"
	)
	var definition: Dictionary = GearModSystem.mod_definition(
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
	)
	var modifier_components: Array[Dictionary] = (
		GearModSystem.modifier_components(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		)
	)
	_expect(
		modifier_components.size() == 1
		and String(modifier_components[0].get("slot", ""))
		== GEAR_MOD_SLOTS.WEAPON,
		"weapon damage Mod should preserve its modifier component slot"
	)
	_expect(
		String(definition.get("rarity", "")) == GEAR_MOD_RARITIES.COMMON,
		"weapon damage Mod should preserve its rarity"
	)
	_expect(
		not definition.has("base_drain")
		and not definition.has("drain_per_rank")
		and not definition.has("dismantle")
		and not definition.has("max_rank")
		and not definition.has("rank_modifiers"),
		"Gear Mod definitions should expose neither retired inventory nor rank fields"
	)
	_expect(
		GearModSystem.has_method("modifiers")
		and GearModSystem.has_method("components")
		and GearModSystem.has_method("modifier_components")
		and GearModSystem.has_method("program_components")
		and GearModSystem.has_method("board_rule_components")
		and not GearModSystem.has_method("rank_modifiers")
		and not GearModSystem.has_method("max_rank")
		and not GearModSystem.has_method("overflow_gold")
		and not GearModSystem.has_method("next_grant_preview"),
		"GearModSystem should expose only fixed modifiers, without rank or upgrade APIs"
	)
	var reward_ids: Array[String] = GearModSystem.reward_pool_ids(
		WORLD_EVENT_MOD_POOL_IDS.WORLD_EVENT_MOD_POOL_COMMON
	)
	_expect(
		reward_ids == [
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER,
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER,
			GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE,
			GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK,
		],
		"common reward pool should list all five Gear Mods at equal weight"
	)
	var map_definition: Dictionary = GearModSystem.mod_definition(
		GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE
	)
	var program_components: Array[Dictionary] = (
		GearModSystem.program_components(
			GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE
		)
	)
	var cage_component: Dictionary = (
		program_components[0] if not program_components.is_empty() else {}
	)
	var cage_program: Dictionary = cage_component.get("program", {}) as Dictionary
	var cage_conditions: Array = _array_or_empty(cage_program.get("conditions", []))
	var cage_actions: Array = _array_or_empty(cage_program.get("actions", []))
	_expect(
		String(cage_component.get("type", ""))
		== GEAR_MOD_COMPONENT_TYPES.PROGRAM
		and String(cage_program.get("trigger", "")) == EFFECT_TRIGGERS.INTERVAL
		and is_equal_approx(
			float(cage_program.get("interval_seconds", 0.0)),
			10.0
		)
		and cage_conditions.size() == 1
		and String((cage_conditions[0] as Dictionary).get("condition", ""))
		== EFFECT_CONDITIONS.MODULE_RELATION
		and String(
			((cage_conditions[0] as Dictionary).get("params", {}) as Dictionary).get(
				"value",
				""
			)
		) == "source_is_current"
		and cage_actions.size() == 1
		and String((cage_actions[0] as Dictionary).get("action", ""))
		== EFFECT_ACTIONS.SPAWN_ENEMY
		and bool(
			((cage_actions[0] as Dictionary).get("params", {}) as Dictionary).get(
				"current_layer_only",
				false
			)
		)
		and bool(
			((cage_actions[0] as Dictionary).get("params", {}) as Dictionary).get(
				"normal_rewards",
				false
			)
		)
		and not map_definition.has("slot")
		and not map_definition.has("modifiers"),
		"spawner cage should expose the strict interval program component"
	)
	var grid_definition: Dictionary = GearModSystem.mod_definition(
		GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK
	)
	var board_components: Array[Dictionary] = (
		GearModSystem.board_rule_components(GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK)
	)
	var rock_component: Dictionary = (
		board_components[0] if not board_components.is_empty() else {}
	)
	_expect(
		String(rock_component.get("type", ""))
		== GEAR_MOD_COMPONENT_TYPES.BOARD_RULE
		and String(rock_component.get("rule_id", ""))
		== GEAR_MOD_BOARD_RULES.OCCUPY_ONLY
		and not grid_definition.has("slot")
		and not grid_definition.has("modifiers"),
		"rock should expose only the occupy-only board rule component"
	)
	var fingerprint: Dictionary = (
		DataLoader.gear_mod_gameplay_fingerprint_payload()
	)
	var fingerprint_board: Dictionary = fingerprint.get("board", {}) as Dictionary
	var fingerprint_map_mod: Dictionary = {}
	for raw_mod: Variant in _array_or_empty(fingerprint.get("mods", [])):
		if (
			raw_mod is Dictionary
			and String((raw_mod as Dictionary).get("id", ""))
			== GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE
		):
			fingerprint_map_mod = raw_mod as Dictionary
			break
	var fingerprint_components: Array = _array_or_empty(
		fingerprint_map_mod.get("components", [])
	)
	_expect(
		int(fingerprint_board.get("width", 0)) == 7
		and _array_or_empty(
			fingerprint_board.get("initial_unlocked_cells", [])
		).size() == 13
		and fingerprint_components == map_definition.get("components", []),
		"gameplay fingerprint should include board topology and components"
	)


func _expect_fixed_modifiers() -> void:
	_expect_modifier(
		GearModSystem.modifiers(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		),
		STATS.DAMAGE,
		1.2,
		"fixed damage modifier"
	)
	_expect_modifier(
		GearModSystem.modifiers(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_RECOIL_DAMPER
		),
		STATS.RECOIL,
		0.8,
		"fixed recoil modifier"
	)
	_expect_modifier(
		GearModSystem.modifiers(
			GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER
		),
		STATS.SPREAD_ANGLE_MAX,
		0.8,
		"fixed spread modifier"
	)


func _expect_preview() -> void:
	var preview: Dictionary = GearModSystem.resolve_preview_loadout([
		{"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST},
		{"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST},
		{"mod_id": GEAR_MOD_IDS.GEAR_MOD_WEAPON_SPREAD_STABILIZER},
		{"mod_id": "missing_gear_mod"},
	])
	var selected: Array = _array_or_empty(preview.get("selected", []))
	var diagnostics: Array = _array_or_empty(preview.get("diagnostics", []))
	_expect(
		selected.size() == 3
		and not (selected[0] as Dictionary).has("rank")
		and String((selected[0] as Dictionary).get("mod_id", ""))
		== GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST
		and String((selected[1] as Dictionary).get("mod_id", ""))
		== GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		"preview should preserve repeated independent Mod instances without rank"
	)
	_expect(
		diagnostics.size() == 1
		and _has_reason(diagnostics, "unknown_mod"),
		"preview should reject only the unknown Mod selection"
	)
	var modifiers_by_slot: Dictionary = preview.get(
		"modifiers",
		{}
	) as Dictionary
	var weapon_modifiers: Array = _array_or_empty(
		modifiers_by_slot.get(GEAR_MOD_SLOTS.WEAPON, [])
	)
	_expect(
		_modifier_count(weapon_modifiers, STATS.DAMAGE, 1.2) == 2
		and _has_modifier(
			weapon_modifiers,
			STATS.SPREAD_ANGLE_MAX,
			0.8
		),
		"preview should preserve one fixed modifier per selected instance"
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
	_expect_drop_chance(
		POOL_IDS.ENEMY_STALKER,
		GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE,
		0.025
	)
	_expect_drop_chance(
		POOL_IDS.ENEMY_SWARM,
		GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK,
		0.05
	)


func _expect_board_domain() -> void:
	var board: GearModBoard = GEAR_MOD_BOARD_SCRIPT.new() as GearModBoard
	_expect(
		board.configure(
			GearModSystem.board_config(),
			GearModSystem.mod_definitions()
		),
		"Gear Mod board should configure from the GearModSystem data facade"
	)
	var initial_snapshot: Dictionary = board.snapshot()
	_expect(
		_array_or_empty(initial_snapshot.get("unlocked_cells", [])).size() == 13
		and _array_or_empty(initial_snapshot.get("placements", [])).is_empty()
		and board.center() == Vector2i(3, 3),
		"board should expose the 13-cell mask and implicit center core"
	)
	_expect(
		board.legal_cells(GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK) == [
			Vector2i(3, 2),
			Vector2i(2, 3),
			Vector2i(4, 3),
			Vector2i(3, 4),
		],
		"an empty board should expose the four unlocked cells adjacent to core"
	)
	var rock_result: Dictionary = board.request_placement(
		1,
		GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK,
		Vector2i(3, 2)
	)
	_expect(
		bool(rock_result.get("ok", false))
		and String(rock_result.get("outcome", ""))
		== GEAR_MOD_PLACEMENT_OUTCOMES.PLACED
		and rock_result.get("placement") == {
			"instance_id": 1,
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_GRID_ROCK,
			"x": 3,
			"y": 2,
		},
		"placement should atomically return the flattened Run v19 shape"
	)
	var cage_result: Dictionary = board.request_placement(
		2,
		GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE,
		Vector2i(3, 1)
	)
	_expect(
		bool(cage_result.get("ok", false)),
		"map Mod should place through the existing rock connection"
	)
	var before_rejected_placement: Dictionary = board.snapshot()
	var rejected_result: Dictionary = board.request_placement(
		3,
		GEAR_MOD_IDS.GEAR_MOD_WEAPON_DAMAGE_TEST,
		Vector2i(3, 3)
	)
	_expect(
		not bool(rejected_result.get("ok", true))
		and String(rejected_result.get("outcome", ""))
		== GEAR_MOD_PLACEMENT_OUTCOMES.CANCELLED
		and board.snapshot() == before_rejected_placement,
		"core placement rejection should leave the board unchanged"
	)
	var unlocked_cells: Array[Vector2i] = [Vector2i(0, 3)]
	var unlock_result: Dictionary = board.unlock_cells(
		unlocked_cells,
		"gear_mod_smoke_unlock"
	)
	var repeated_unlock: Dictionary = board.unlock_cells(
		unlocked_cells,
		"gear_mod_smoke_unlock"
	)
	_expect(
		bool(unlock_result.get("ok", false))
		and bool(unlock_result.get("changed", false))
		and unlock_result.get("cells", []) == [{"x": 0, "y": 3}]
		and bool(repeated_unlock.get("ok", false))
		and not bool(repeated_unlock.get("changed", true))
		and (repeated_unlock.get("cells", []) as Array).is_empty(),
		"unlock_cells should return only newly unlocked cells and be source-idempotent"
	)
	var before_conflicting_unlock: Dictionary = board.snapshot()
	var conflicting_cells: Array[Vector2i] = [Vector2i(1, 3)]
	var conflicting_unlock: Dictionary = board.unlock_cells(
		conflicting_cells,
		"gear_mod_smoke_unlock"
	)
	_expect(
		not bool(conflicting_unlock.get("ok", true))
		and board.snapshot() == before_conflicting_unlock,
		"one unlock source should not be rebound to different cells"
	)
	var unavailable_relocation: Dictionary = board.request_relocation(
		2,
		Vector2i(4, 2)
	)
	_expect(
		not bool(unavailable_relocation.get("ok", true))
		and String(unavailable_relocation.get("outcome", ""))
		== GEAR_MOD_PLACEMENT_OUTCOMES.CANCELLED,
		"relocation should be unavailable without a cost authorizer"
	)
	var relocated: Dictionary = board.request_relocation(
		2,
		Vector2i(4, 2),
		Callable(self, "_authorize_board_relocation")
	)
	_expect(
		bool(relocated.get("ok", false))
		and relocated.get("placement") == {
			"instance_id": 2,
			"mod_id": GEAR_MOD_IDS.GEAR_MOD_MAP_SPAWNER_CAGE,
			"x": 4,
			"y": 2,
		},
		"authorized relocation should atomically move a still-connected Mod"
	)
	var before_disconnect: Dictionary = board.snapshot()
	var disconnect_result: Dictionary = board.request_relocation(
		1,
		Vector2i(2, 3),
		Callable(self, "_authorize_board_relocation")
	)
	_expect(
		not bool(disconnect_result.get("ok", true))
		and board.snapshot() == before_disconnect,
		"relocation should reject a move that disconnects a Mod from core"
	)
	var saved: Dictionary = board.snapshot()
	var restored: GearModBoard = GEAR_MOD_BOARD_SCRIPT.new() as GearModBoard
	_expect(
		restored.configure(
			GearModSystem.board_config(),
			GearModSystem.mod_definitions()
		)
		and restored.restore_snapshot(saved)
		and restored.snapshot() == saved
		and not saved.has("map_behavior_states")
		and restored.placements()[0].get("y") == 2
		and restored.placements()[0].get("x") == 3,
		"board snapshot should roundtrip sorted placements without runtime effect state"
	)


func _expect_composite_components() -> void:
	var definitions: Array[Dictionary] = GearModSystem.mod_definitions()
	var composite_id: String = "gear_mod_smoke_composite"
	var composite_definition: Dictionary = {
		"id": composite_id,
		"components": [
			{
				"component_id": "composite_modifier",
				"type": GEAR_MOD_COMPONENT_TYPES.MODIFIER,
				"slot": GEAR_MOD_SLOTS.WEAPON,
				"modifiers": [
					{"stat": STATS.DAMAGE, "type": "mult", "value": 1.1},
				],
			},
			{
				"component_id": "composite_program",
				"type": GEAR_MOD_COMPONENT_TYPES.PROGRAM,
				"program": {
					"program_id": "spawn_on_dash",
					"trigger": EFFECT_TRIGGERS.DASH,
					"conditions": [],
					"actions": [
						{
							"action": EFFECT_ACTIONS.SPAWN_ENEMY,
							"params": {
								"normal_rewards": true,
								"current_layer_only": true,
							},
						},
					],
					"proc_chance": 1.0,
					"internal_cooldown": 0.0,
				},
			},
			{
				"component_id": "composite_board_rule",
				"type": GEAR_MOD_COMPONENT_TYPES.BOARD_RULE,
				"rule_id": GEAR_MOD_BOARD_RULES.OCCUPY_ONLY,
			},
		],
	}
	definitions.append(composite_definition)
	var board: GearModBoard = GEAR_MOD_BOARD_SCRIPT.new() as GearModBoard
	var placement: Dictionary = {}
	if board.configure(GearModSystem.board_config(), definitions):
		placement = board.request_placement(99, composite_id, Vector2i(3, 2))
	_expect(
		bool(placement.get("ok", false))
		and (composite_definition.get("components", []) as Array).size() == 3,
		"one Gear Mod should compose modifier, program, and board rule components"
	)


func _authorize_board_relocation(
	_instance_id: int,
	_target: Vector2i
) -> bool:
	return true


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
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.2},
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.2},
	]
	weapon.set_gear_modifiers(weapon_gear_modifiers)
	weapon.set_gear_modifiers(weapon_gear_modifiers)
	_expect(
		is_equal_approx(weapon.stat_value(STATS.DAMAGE), 34.56),
		"repeated Gear Mod instances should multiply once each and replacement should be idempotent"
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
		is_equal_approx(weapon.stat_value(STATS.DAMAGE), 34.56),
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
		"gear_mod_weapon_damage_test_name"
	)
	var normal_context: Dictionary = hud.get(
		"_last_feedback_context"
	) as Dictionary
	_expect(
		String(hud.get("_last_upgrade_feedback_key"))
		== "ui_gear_mod_drop_obtained"
		and normal_context.is_empty()
		and bool(hud.call("is_gear_mod_drop_feedback_visible")),
		"Gear Mod HUD feedback should expose acquisition without rank or overflow state"
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


func _modifier_count(
	modifiers: Array,
	stat_id: String,
	value: float
) -> int:
	var count: int = 0
	for raw_modifier: Variant in modifiers:
		if not raw_modifier is Dictionary:
			continue
		var modifier: Dictionary = raw_modifier as Dictionary
		if (
			String(modifier.get("stat", "")) == stat_id
			and String(modifier.get("type", "")) == "mult"
			and is_equal_approx(float(modifier.get("value", 0.0)), value)
		):
			count += 1
	return count


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
