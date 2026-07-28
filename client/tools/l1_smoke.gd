extends Node


const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const ELEMENT_RESOLVER_SCRIPT := preload("res://scripts/data/element_resolver.gd")
const DIFFICULTY_PROGRESSION_SCRIPT := preload(
	"res://scripts/data/difficulty_progression.gd"
)
const HERO_COMPOSITION_RESOLVER_SCRIPT := preload(
	"res://scripts/data/hero_composition_resolver.gd"
)
const WEAPON_RECOIL_RESOLVER_SCRIPT := preload(
	"res://scripts/data/weapon_recoil_resolver.gd"
)
const SKILL_DESCRIPTION_FORMATTER := preload(
	"res://scripts/data/skill_description_formatter.gd"
)
const BULLET_SCENE := preload("res://scenes/gameplay/bullet.tscn")
const ENERGY_ORB_SCENE := preload("res://scenes/gameplay/energy_orb.tscn")
const ENEMY_SCENE := preload("res://scenes/gameplay/actors/enemies/enemy_chaser.tscn")
const PLAYER_SCENE := preload("res://scenes/gameplay/actors/characters/character_default.tscn")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const PROJECTILE_BARRIER_SCENE := preload("res://scenes/gameplay/projectile_barrier.tscn")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SKILL_EFFECTS := preload("res://scripts/contracts/skill_effects.gd")
const SKILL_IDS := preload("res://scripts/contracts/skill_ids.gd")
const SKILL_RESOURCES := preload("res://scripts/contracts/skill_resources.gd")
const SKILL_SLOTS := preload("res://scripts/contracts/skill_slots.gd")
const SKILL_SYSTEM_SCENE := preload("res://scenes/gameplay/skill_system.tscn")
const SKILL_TARGETING := preload("res://scripts/contracts/skill_targeting.gd")
const STATS := preload("res://scripts/contracts/stats.gd")
const STATUS_EFFECT_SCRIPT := preload("res://scripts/combat/status_effect.gd")
const STATUS_EFFECTS := preload("res://scripts/contracts/status_effects.gd")
const STATUS_STACK_RULES := preload("res://scripts/contracts/status_stack_rules.gd")

const CLOCK_FRAMES: int = 4
const DOT_DAMAGE_FLAG: String = "is_dot"
const MOD_SMOKE_ROOT: String = "user://mods/l1_smoke_mod"
const L1_SLOT: String = "slot_l1_smoke"
const TEAM_ENEMY: String = "team_enemy"
const TEAM_PLAYER: String = "team_player"

var _failures: Array[String] = []


class DamageTarget:
	extends Node

	var life: float = 5.0

	func receive_damage(info: RefCounted) -> Dictionary:
		var amount: float = float(info.get("amount"))
		life -= amount
		return {
			"applied": true,
			"amount": amount,
			"defeated": life <= 0.0,
			"reason": "applied",
		}


class SkillTarget:
	extends Node2D

	var life: float = 10.0

	func is_alive() -> bool:
		return life > 0.0

	func receive_damage(info: RefCounted) -> Dictionary:
		var amount: float = float(info.get("amount"))
		var applied_amount: float = minf(amount, life)
		life = maxf(life - amount, 0.0)
		return {
			"applied": true,
			"amount": applied_amount,
			"defeated": life <= 0.0,
			"reason": "applied",
		}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	_expect_rng_same_seed_stable()
	_expect_rng_snapshot_restore()
	_expect_difficulty_progression_boundaries()
	_expect_enemy_difficulty_spawn_scaling()
	await _expect_game_clock_pause_freezes()
	_expect_game_state_rejects_unknown()
	_expect_save_manager_roundtrip()
	_expect_hero_composition_resolution()
	_expect_config_backed_skill_descriptions()
	_expect_weapon_recoil_resolution()
	_expect_combat_damage_path()
	await _expect_player_defense_layers()
	await _expect_dash_runtime()
	await _expect_player_weapon_recoil()
	await _expect_four_skill_slots_and_efficiency()
	await _expect_skill_system_aoe_damage()
	await _expect_entity_status_components()
	await _expect_status_modifiers_and_vulnerability()
	await _expect_barrier_and_energy_orb()
	await _expect_poison_dot_status()
	_expect_mod_loader_data_patch()
	_expect_platform_services_reserved_interface()

	SaveManager.delete(L1_SLOT, SAVE_KINDS.RUN)
	GameState.change_state(GameState.MAIN_MENU, {"source": "l1_smoke"})
	_finish()


func _expect_rng_same_seed_stable() -> void:
	RNG.set_run_seed(13579)
	var first_spawn_roll: int = RNG.spawn.randi()
	var first_choice_roll: float = RNG.ui_choice.randf()
	RNG.set_run_seed(13579)
	_expect(RNG.spawn.randi() == first_spawn_roll, "RNG.spawn should repeat with the same run seed")
	_expect(is_equal_approx(RNG.ui_choice.randf(), first_choice_roll), "RNG.ui_choice should repeat with the same run seed")
	var random_seed: int = RNG.set_random_run_seed()
	_expect(random_seed >= RNG.DEFAULT_RUN_SEED, "RNG should generate a positive random run seed")
	_expect(random_seed != 13579, "RNG random run seed should differ from the active run seed")
	_expect(RNG.run_seed() == random_seed, "RNG random run seed should become the active run seed")


func _expect_rng_snapshot_restore() -> void:
	RNG.set_run_seed(24680)
	var snapshot: Dictionary = RNG.snapshot()
	var expected_roll: int = RNG.combat.randi()
	RNG.combat.randi()
	RNG.restore_snapshot(snapshot)
	_expect(RNG.combat.randi() == expected_roll, "RNG snapshot should restore stream state")


func _expect_difficulty_progression_boundaries() -> void:
	var profiles_payload: Dictionary = DataLoader.load_json(
		DataLoader.DIFFICULTY_PROFILES_PATH
	) as Dictionary
	var profiles: Array = profiles_payload.get("profiles", []) as Array
	_expect(
		not profiles.is_empty(),
		"difficulty progression smoke requires a configured profile"
	)
	if profiles.is_empty():
		return
	var profile: Dictionary = profiles[0] as Dictionary
	var cases: Array[Dictionary] = [
		{
			"elapsed": 0.0,
			"level": 1,
			"progress": 0.0,
			"health": 1.0,
			"damage": 1.0,
		},
		{
			"elapsed": 89.999,
			"level": 1,
			"progress": 89.999 / 90.0,
			"health": 1.0 + 0.04 * (89.999 / 90.0),
			"damage": 1.0 + 0.48 * 0.04 * (89.999 / 90.0),
		},
		{
			"elapsed": 90.0,
			"level": 2,
			"progress": 0.0,
			"health": 1.13,
			"damage": 1.0 + 0.48 * 0.13,
		},
		{
			"elapsed": 719.999,
			"level": 8,
			"progress": fmod(719.999, 90.0) / 90.0,
			"health": (
				1.0 + 0.04 * (719.999 / 90.0) + 0.09 * 7.0
			),
			"damage": (
				1.0
				+ 0.48
				* (
					0.04 * (719.999 / 90.0)
					+ 0.09 * 7.0
				)
			),
		},
		{
			"elapsed": 720.0,
			"level": 9,
			"progress": 0.0,
			"health": 2.04,
			"damage": 1.4992,
		},
		{
			"elapsed": 1800.0,
			"level": 21,
			"progress": 0.0,
			"health": 3.6,
			"damage": 2.248,
		},
	]
	for test_case: Dictionary in cases:
		var progression: DifficultyProgression = (
			DIFFICULTY_PROGRESSION_SCRIPT.new()
		)
		_expect(
			progression.configure(profile),
			"difficulty progression should accept the standard profile"
		)
		progression.advance(float(test_case.get("elapsed", 0.0)))
		var snapshot: Dictionary = progression.current_snapshot()
		var elapsed: float = float(test_case.get("elapsed", 0.0))
		_expect(
			int(snapshot.get("difficulty_level", 0))
			== int(test_case.get("level", 0)),
			"difficulty level should match at %.3f seconds" % elapsed
		)
		_expect(
			is_equal_approx(
				float(snapshot.get("progress", -1.0)),
				float(test_case.get("progress", -1.0))
			),
			"difficulty tier progress should match at %.3f seconds"
			% elapsed
		)
		_expect(
			is_equal_approx(
				float(snapshot.get("health_multiplier", 0.0)),
				float(test_case.get("health", 0.0))
			),
			"difficulty health multiplier should match at %.3f seconds"
			% elapsed
		)
		_expect(
			is_equal_approx(
				float(snapshot.get("damage_multiplier", 0.0)),
				float(test_case.get("damage", 0.0))
			),
			"difficulty damage multiplier should match at %.3f seconds"
			% elapsed
		)
	var unbounded: DifficultyProgression = DIFFICULTY_PROGRESSION_SCRIPT.new()
	_expect(
		unbounded.configure(profile),
		"unbounded difficulty progression should configure"
	)
	unbounded.advance(1800.0)
	var late_snapshot: Dictionary = unbounded.current_snapshot()
	_expect(
		int(late_snapshot.get("difficulty_level", 0)) > 9
		and float(late_snapshot.get("health_multiplier", 0.0)) > 2.04,
		"difficulty should keep growing after twelve minutes"
	)


func _expect_enemy_difficulty_spawn_scaling() -> void:
	_ensure_l1_combat_pools()
	var world: Node2D = Node2D.new()
	world.name = "L1DifficultyEnemyWorld"
	add_child(world)
	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1DifficultyEnemyPlayer"
	world.add_child(player)
	var player_stats: Dictionary = _l1_player_stats()
	player_stats[STATS.MAX_HP] = 200.0
	player.call("configure", player_stats)
	var enemy: Node2D = ENEMY_SCENE.instantiate() as Node2D
	enemy.name = "L1DifficultyEnemy"
	world.add_child(enemy)
	var enemy_data: Dictionary = _l1_enemy_data()
	enemy_data["max_hp"] = 100.0
	enemy_data["move_speed"] = 84.0
	enemy_data["contact_damage"] = 10.0
	enemy_data["ai_profile"] = {
		"movement": {
			"ranged_projectile_damage": 12.0,
			"ranged_projectile_speed": 600.0,
			"ranged_projectile_range": 500.0,
			"ranged_projectile_hit_radius": 4.0,
			"ranged_projectile_lifetime": 1.0,
			"ranged_projectile_muzzle_distance": 0.0,
		},
	}
	enemy.call(
		"configure",
		enemy_data,
		player,
		null,
		{
			"health_multiplier": 2.04,
			"damage_multiplier": 1.4992,
		}
	)
	var ai_summary: Dictionary = enemy.call("ai_debug_summary")
	_expect(
		is_equal_approx(float(enemy.call("max_life")), 204.0),
		"enemy spawn health multiplier should scale maximum life"
	)
	_expect(
		is_equal_approx(
			float(ai_summary.get("contact_damage", 0.0)),
			14.992
		),
		"enemy spawn damage multiplier should scale contact damage"
	)
	_expect(
		is_equal_approx(
			float(ai_summary.get("ranged_projectile_damage", 0.0)),
			17.9904
		),
		"enemy spawn damage multiplier should scale ranged projectiles"
	)
	_expect(
		is_equal_approx(float(enemy.get("_move_speed")), 84.0),
		"difficulty spawn multipliers should not change move speed"
	)
	player.global_position = Vector2.ZERO
	enemy.global_position = Vector2.ZERO
	var life_before_contact: float = float(player.call("current_life"))
	enemy.call("_check_contact")
	_expect(
		is_equal_approx(
			life_before_contact - float(player.call("current_life")),
			14.992
		),
		"scaled enemy contact damage should pass through the real Combat path"
	)
	player.call("debug_set_life", 200.0)
	player.global_position = Vector2(32.0, 0.0)
	enemy.call("_fire_ranged_projectile", Vector2.RIGHT)
	var enemy_bullet: Node2D = null
	for raw_bullet: Node in get_tree().get_nodes_in_group("active_bullets"):
		if raw_bullet.get("_source") == enemy:
			enemy_bullet = raw_bullet as Node2D
			break
	_expect(
		enemy_bullet != null,
		"scaled enemy ranged attack should create a real projectile"
	)
	if enemy_bullet != null:
		var life_before_projectile: float = float(player.call("current_life"))
		enemy_bullet.call(
			"_check_damage_target_hits",
			enemy.global_position,
			player.global_position
		)
		_expect(
			is_equal_approx(
				life_before_projectile - float(player.call("current_life")),
				17.9904
			),
			"scaled enemy projectile damage should pass through Bullet and Combat"
		)
	var saved_enemy: Dictionary = enemy.call("snapshot")
	enemy.call("configure", enemy_data, player)
	enemy.call("restore_snapshot", saved_enemy)
	_expect(
		enemy.call("enemy_spawn_snapshot") == {
			"health_multiplier": 2.04,
			"damage_multiplier": 1.4992,
		}
		and is_equal_approx(float(enemy.call("max_life")), 204.0),
		"enemy snapshot restore should preserve exact spawn multipliers"
	)
	enemy.remove_from_group("active_enemies")
	player.remove_from_group("active_player")
	world.queue_free()


func _expect_game_clock_pause_freezes() -> void:
	GameClock.reset()
	GameState.change_state(GameState.PLAYING, {"source": "l1_smoke"})
	for _index: int in range(CLOCK_FRAMES):
		await get_tree().physics_frame
	var playing_tick: int = GameClock.tick()
	_expect(playing_tick > 0, "GameClock tick should advance in PLAYING")

	GameState.change_state(GameState.PAUSED, {"source": "l1_smoke"})
	var paused_tick: int = GameClock.tick()
	var paused_time: float = GameClock.now()
	for _index: int in range(CLOCK_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame
	_expect(GameClock.tick() == paused_tick, "GameClock tick should freeze in PAUSED")
	_expect(is_equal_approx(GameClock.now(), paused_time), "GameClock time should freeze in PAUSED")

	GameState.change_state(GameState.PLAYING, {"source": "l1_smoke"})


func _expect_game_state_rejects_unknown() -> void:
	var before_state: StringName = GameState.current()
	_expect(not GameState.can_change_to(&"unknown_state_for_l1"), "GameState should reject unknown states")
	_expect(GameState.current() == before_state, "GameState should keep current state after unknown transition")


func _expect_weapon_recoil_resolution() -> void:
	var weapons_payload: Dictionary = DataLoader.load_json(
		DataLoader.WEAPONS_PATH
	) as Dictionary
	var recoil_model: Dictionary = weapons_payload.get(
		"recoil_model",
		{}
	) as Dictionary
	var recoil_values: Array[float] = [
		0.0,
		20.0,
		25.0,
		50.0,
		75.0,
		100.0,
	]
	for recoil: float in recoil_values:
		var stats: Dictionary = {
			STATS.RECOIL: recoil,
			STATS.SPREAD_ANGLE_MAX: 60.0,
		}
		var resolved: Dictionary = WEAPON_RECOIL_RESOLVER_SCRIPT.resolve(
			stats,
			recoil_model
		)
		var ratio: float = recoil / 100.0
		_expect(
			is_equal_approx(
				float(resolved.get("spread_angle_degrees", 0.0)),
				60.0 * pow(ratio, 1.5)
			),
			"recoil %s should resolve the configured spread curve" % recoil
		)
		_expect(
			is_equal_approx(
				float(resolved.get("kickback_distance", 0.0)),
				14.0 * ratio
			),
			"recoil %s should resolve the configured kickback distance" % recoil
		)
		_expect(
			is_equal_approx(
				float(resolved.get("kickback_initial_speed", 0.0)),
				2.0 * 14.0 * ratio / 0.08
			),
			"recoil %s should resolve the configured initial speed" % recoil
		)
	var negative_result: Dictionary = WEAPON_RECOIL_RESOLVER_SCRIPT.resolve(
		{
			STATS.RECOIL: -20.0,
			STATS.SPREAD_ANGLE_MAX: 60.0,
		},
		recoil_model
	)
	_expect(
		is_equal_approx(float(negative_result.get("recoil", -1.0)), 0.0),
		"negative runtime recoil should clamp to zero"
	)
	var saturated_result: Dictionary = WEAPON_RECOIL_RESOLVER_SCRIPT.resolve(
		{
			STATS.RECOIL: 200.0,
			STATS.SPREAD_ANGLE_MAX: 360.0,
		},
		recoil_model
	)
	_expect(
		is_equal_approx(float(saturated_result.get("recoil", 0.0)), 100.0),
		"runtime recoil should saturate at recoil_max"
	)
	_expect(
		is_equal_approx(
			float(saturated_result.get("spread_angle_degrees", 0.0)),
			180.0
		),
		"runtime spread should clamp to the absolute 180 degree cap"
	)


func _expect_save_manager_roundtrip() -> void:
	SaveManager.delete(L1_SLOT, SAVE_KINDS.RUN)
	var payload: Dictionary = {
		"schema_version": 1,
		"level": 2,
		"game_clock": GameClock.snapshot(),
		"rng": RNG.snapshot(),
		"spawn_states": {},
		"player": {},
		"weapon": {},
		"enemies": [],
		"bullets": [],
		"pickups": [],
	}
	_expect(SaveManager.save(L1_SLOT, SAVE_KINDS.RUN, payload), "SaveManager should write a smoke run payload")
	var loaded: Dictionary = SaveManager.load(L1_SLOT, SAVE_KINDS.RUN)
	_expect(int(loaded.get("level", 0)) == 2, "SaveManager should roundtrip a smoke run payload")
	_expect(loaded.get("rng", {}) is Dictionary, "SaveManager should preserve RNG snapshot dictionaries")


func _expect_combat_damage_path() -> void:
	var target := DamageTarget.new()
	target.name = "L1DamageTarget"
	add_child(target)
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		3.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		self,
		target,
		"team_player",
		"team_enemy"
	)
	var result: Dictionary = Combat.apply_damage(target, info)
	_expect(bool(result.get("applied", false)), "Combat should apply registered physical damage")
	_expect(is_equal_approx(target.life, 2.0), "Combat should route damage through receive_damage")
	target.queue_free()


func _expect_hero_composition_resolution() -> void:
	var element_resolver: ElementResolver = ELEMENT_RESOLVER_SCRIPT.new()
	_expect(
		bool(element_resolver.call("load_default")),
		"element resolver should load the formal seven-element table"
	)
	var characters_payload: Variant = DataLoader.load_json(
		DataLoader.CHARACTERS_PATH
	)
	var composition: Dictionary = HERO_COMPOSITION_RESOLVER_SCRIPT.resolve(
		characters_payload,
		CHARACTER_IDS.CHARACTER_PRIMARY_A,
		CHARACTER_IDS.CHARACTER_PRIMARY_B,
		element_resolver,
		false
	)
	_expect(
		not composition.is_empty(),
		"distinct main and sub heroes should resolve"
	)
	_expect(
		is_equal_approx(
			float(
				(composition.get("base_stats", {}) as Dictionary).get(
					STATS.MAX_HP,
					0.0
				)
			),
			500.0
		),
		"only the main hero should provide base stats"
	)
	var resolved_slots: Dictionary = (
		composition.get("skill_slots", {}) as Dictionary
	)
	_expect(
		String(resolved_slots.get(SKILL_SLOTS.SKILL_1, ""))
		== SKILL_IDS.SKILL_DEPLOY_PROJECTILE_BARRIER
		and String(resolved_slots.get(SKILL_SLOTS.SKILL_2, ""))
		== SKILL_IDS.SKILL_AOE_SLOW
		and String(resolved_slots.get(SKILL_SLOTS.SKILL_3, ""))
		== SKILL_IDS.SKILL_SELF_FIRE_MOVE_HASTE
		and String(resolved_slots.get(SKILL_SLOTS.SKILL_4, ""))
		== SKILL_IDS.SKILL_ENEMY_HASTE_VULNERABILITY,
		"main hero should provide slots 1/2 and sub hero slots 3/4"
	)
	_expect(
		HERO_COMPOSITION_RESOLVER_SCRIPT.resolve(
			characters_payload,
			CHARACTER_IDS.CHARACTER_PRIMARY_A,
			CHARACTER_IDS.CHARACTER_PRIMARY_A,
			element_resolver,
			false
		).is_empty(),
		"outside-run composition should reject duplicate heroes"
	)
	var repeated_composition: Dictionary = (
		HERO_COMPOSITION_RESOLVER_SCRIPT.resolve(
			characters_payload,
			CHARACTER_IDS.CHARACTER_PRIMARY_A,
			CHARACTER_IDS.CHARACTER_PRIMARY_A,
			element_resolver,
			true
		)
	)
	var repeated_slots: Array = repeated_composition.get(
		"slot_definitions",
		[]
	)
	_expect(
		repeated_slots.size() == 4
		and is_equal_approx(
			float(
				(repeated_slots[2] as Dictionary).get(
					"energy_cost_multiplier",
					0.0
				)
			),
			1.5
		)
		and is_equal_approx(
			float(
				(repeated_slots[2] as Dictionary).get(
					"cooldown_multiplier",
					0.0
				)
			),
			1.5
		),
		"future duplicate slots should receive 1.5x cost and cooldown"
	)


func _expect_config_backed_skill_descriptions() -> void:
	var ability_stats: Dictionary = {
		STATS.ABILITY_STRENGTH: 2.0,
		STATS.ABILITY_RANGE: 1.5,
		STATS.ABILITY_EFFICIENCY: 1.5,
		STATS.ABILITY_DURATION: 2.0,
	}
	var barrier: Dictionary = _l1_skill_definition(
		SKILL_IDS.SKILL_DEPLOY_PROJECTILE_BARRIER
	)
	var barrier_values: Dictionary = (
		SKILL_DESCRIPTION_FORMATTER.skill_values(
			barrier,
			ability_stats
		)
	)
	var barrier_cost: Dictionary = (
		(barrier.get("costs", []) as Array)[0] as Dictionary
	)
	var barrier_effect: Dictionary = (
		(barrier.get("effects", []) as Array)[0] as Dictionary
	)
	var barrier_params: Dictionary = (
		barrier_effect.get("params", {}) as Dictionary
	)
	_expect(
		is_equal_approx(
			float(barrier_values.get("cost_energy", 0.0)),
			float(barrier_cost.get("amount", 0.0)) * 0.5
		)
		and is_equal_approx(
			float(barrier_values.get("effect_1_radius", 0.0)),
			float(barrier_params.get("radius", 0.0)) * 1.5
		)
		and is_equal_approx(
			float(barrier_values.get("effect_1_hp", 0.0)),
			float(barrier_params.get("hp", 0.0)) * 2.0
		),
		"skill descriptions should resolve cost, range, and strength from config"
	)
	var barrier_text: String = SKILL_DESCRIPTION_FORMATTER.format_skill(
		"{cost_energy}|{effect_1_radius}|{effect_1_hp}",
		barrier,
		ability_stats
	)
	_expect(
		not barrier_text.contains("{"),
		"skill description formatting should replace every supported token"
	)
	var slow: Dictionary = _l1_skill_definition(SKILL_IDS.SKILL_AOE_SLOW)
	var slow_values: Dictionary = SKILL_DESCRIPTION_FORMATTER.skill_values(
		slow,
		ability_stats
	)
	var slow_targeting: Dictionary = slow.get("targeting", {}) as Dictionary
	var slow_effect: Dictionary = (
		(slow.get("effects", []) as Array)[0] as Dictionary
	)
	var slow_params: Dictionary = slow_effect.get("params", {}) as Dictionary
	var expected_slow_magnitude: float = minf(
		float(slow_params.get("magnitude", 0.0)) * 2.0,
		float(slow_params.get("magnitude_cap", 0.0))
	)
	_expect(
		is_equal_approx(
			float(slow_values.get("target_radius", 0.0)),
			float(slow_targeting.get("radius", 0.0)) * 1.5
		)
		and is_equal_approx(
			float(
				slow_values.get(
					"effect_1_magnitude_percent",
					0.0
				)
			),
			expected_slow_magnitude * 100.0
		)
		and is_equal_approx(
			float(slow_values.get("effect_1_duration", 0.0)),
			float(slow_params.get("duration", 0.0)) * 2.0
		),
		"skill descriptions should apply duration and capped strength scaling"
	)
	var haste: Dictionary = _l1_skill_definition(
		SKILL_IDS.SKILL_SELF_FIRE_MOVE_HASTE
	)
	var haste_values: Dictionary = (
		SKILL_DESCRIPTION_FORMATTER.skill_values(
			haste,
			ability_stats
		)
	)
	var haste_effect: Dictionary = (
		(haste.get("effects", []) as Array)[0] as Dictionary
	)
	var haste_params: Dictionary = haste_effect.get("params", {}) as Dictionary
	var haste_modifiers: Array = haste_params.get("modifiers", []) as Array
	_expect(
		is_equal_approx(
			float(
				haste_values.get(
					"effect_1_modifier_1_value_bonus_percent",
					0.0
				)
			),
			(
				float(
					(haste_modifiers[0] as Dictionary).get(
						"value",
						1.0
					)
				)
				- 1.0
			) * 200.0
		)
		and is_equal_approx(
			float(
				haste_values.get(
					"effect_1_modifier_2_value_bonus_percent",
					0.0
				)
			),
			(
				float(
					(haste_modifiers[1] as Dictionary).get(
						"value",
						1.0
					)
				)
				- 1.0
			) * 200.0
		),
		"skill descriptions should resolve scaled modifier bonuses"
	)
	var haste_text: String = (
		SKILL_DESCRIPTION_FORMATTER.format_skill(
			(
				"{effect_1_modifier_1_value_bonus_percent}|"
				+ "{effect_1_modifier_2_value_bonus_percent}|"
				+ "{effect_1_duration}"
			),
			haste,
			ability_stats
		)
	)
	_expect(
		not haste_text.contains("{"),
		"scaled modifier description tokens should all resolve"
	)
	var passives_payload: Variant = DataLoader.load_json(
		DataLoader.HERO_PASSIVES_PATH
	)
	var passive: Dictionary = {}
	if passives_payload is Dictionary:
		var raw_passives: Variant = (
			(passives_payload as Dictionary).get("passives", [])
		)
		if raw_passives is Array and not (raw_passives as Array).is_empty():
			var raw_passive: Variant = (raw_passives as Array)[0]
			if raw_passive is Dictionary:
				passive = (raw_passive as Dictionary).duplicate(true)
	var passive_text: String = (
		SKILL_DESCRIPTION_FORMATTER.format_passive(
			"{param_multiplier_reduction_percent}",
			passive
		)
	)
	var passive_params: Dictionary = passive.get("params", {}) as Dictionary
	_expect(
		is_equal_approx(
			float(passive_text),
			(
				1.0
				- float(passive_params.get("multiplier", 1.0))
			) * 100.0
		),
		"passive descriptions should resolve configured reduction values"
	)


func _expect_player_defense_layers() -> void:
	var world: Node2D = Node2D.new()
	world.name = "L1DefenseWorld"
	add_child(world)
	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1DefensePlayer"
	world.add_child(player)
	var player_stats: Dictionary = _l1_combat_player_stats()
	player.call("configure", player_stats)
	player.call(
		"configure_runtime_rules",
		DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	)
	GameState.change_state(GameState.PLAYING, {"source": "l1_defense"})

	player.call("debug_set_life", 100.0)
	player.call("debug_set_shield", 50.0, 30.0)
	_apply_damage_to_player(
		player,
		40.0,
		ELEMENTS.ELEMENT_NEUTRAL
	)
	_expect(
		is_equal_approx(float(player.call("current_overshield")), 0.0),
		"overshield should absorb damage before normal shield"
	)
	_expect(
		is_equal_approx(float(player.call("current_shield")), 40.0),
		"normal shield should absorb overflow after overshield"
	)
	_expect(
		is_equal_approx(float(player.call("current_life")), 100.0),
		"shield layers should protect health"
	)

	_apply_damage_to_player(
		player,
		50.0,
		ELEMENTS.ELEMENT_NEUTRAL
	)
	_expect(
		is_equal_approx(float(player.call("current_shield")), 0.0),
		"normal shield should break when incoming damage exceeds it"
	)
	_expect(
		is_equal_approx(float(player.call("current_life")), 100.0),
		"shield gate should swallow the breaking hit overflow"
	)
	_expect(
		absf(
			float(player.call("invulnerability_remaining"))
			- 0.2
		) <= 0.02,
		"shield gate duration should scale from pre-hit shield"
	)

	var gate_expectations: Array[Dictionary] = [
		{"shield": 0.0, "duration": 0.0},
		{"shield": 50.0, "duration": 0.25},
		{"shield": 100.0, "duration": 0.5},
	]
	for expectation: Dictionary in gate_expectations:
		player.call("debug_clear_invulnerability")
		player.call("debug_set_life", 100.0)
		player.call(
			"debug_set_shield",
			float(expectation.get("shield", 0.0)),
			0.0
		)
		_apply_damage_to_player(
			player,
			200.0,
			ELEMENTS.ELEMENT_NEUTRAL
		)
		_expect(
			absf(
				float(player.call("invulnerability_remaining"))
				-
				float(expectation.get("duration", 0.0))
			) <= 0.02,
			"empty/half/full normal shield should produce the configured gate duration"
		)

	player_stats[STATS.ARMOR] = 300.0
	player.call("configure", player_stats)
	player.call(
		"configure_runtime_rules",
		DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	)
	player.call("debug_set_shield", 0.0, 0.0)
	_apply_damage_to_player(
		player,
		100.0,
		ELEMENTS.ELEMENT_NEUTRAL
	)
	_expect(
		absf(float(player.call("current_life")) - 50.0) <= 0.01,
		"300 armor should reduce health damage by 50 percent"
	)

	player_stats[STATS.ARMOR] = 0.0
	player.call("configure", player_stats)
	player.call(
		"configure_runtime_rules",
		DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	)
	player.call(
		"configure_element_damage_taken_multipliers",
		{ELEMENTS.ELEMENT_PRIMARY_A: 0.6}
	)
	player.call("debug_set_shield", 0.0, 0.0)
	_apply_damage_to_player(
		player,
		100.0,
		ELEMENTS.ELEMENT_PRIMARY_A
	)
	_expect(
		absf(float(player.call("current_life")) - 40.0) <= 0.01,
		"pure primary A passive should reduce matching health damage by 40 percent"
	)
	_apply_damage_to_player(
		player,
		10.0,
		ELEMENTS.ELEMENT_COMPOSITE_AB
	)
	_expect(
		absf(float(player.call("current_life")) - 30.0) <= 0.01,
		"composite elements should not inherit pure primary resistance"
	)

	player.call("configure", _l1_combat_player_stats())
	player.call(
		"configure_runtime_rules",
		DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	)
	player.call("debug_set_shield", 100.0, 0.0)
	_apply_damage_to_player(
		player,
		50.0,
		ELEMENTS.ELEMENT_NEUTRAL
	)
	player.call("add_overshield", 100.0)
	await _wait_physics_frames(60)
	_expect(
		absf(float(player.call("current_shield")) - 50.0) <= 0.5,
		"normal shield should not recharge during the four second delay"
	)
	var decayed_overshield: float = float(
		player.call("current_overshield")
	)
	_expect(
		decayed_overshield < 100.0 and decayed_overshield > 94.0,
		"overshield should decay by five percent of current value per second"
	)
	await _wait_physics_frames(200)
	_expect(
		float(player.call("current_shield")) > 50.0,
		"normal shield should recharge after its damage delay"
	)

	world.queue_free()
	await get_tree().process_frame


func _expect_dash_runtime() -> void:
	var world: Node2D = Node2D.new()
	world.name = "L1DashWorld"
	add_child(world)
	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1DashPlayer"
	world.add_child(player)
	var player_stats: Dictionary = _l1_combat_player_stats()
	player_stats[STATS.MAX_SHIELD] = 0.0
	player.call("configure", player_stats)
	player.call(
		"configure_runtime_rules",
		DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	)
	GameState.change_state(GameState.PLAYING, {"source": "l1_dash"})
	var dash_result: Dictionary = player.call("try_dash", Vector2.RIGHT)
	_expect(bool(dash_result.get("ok", false)), "dash should start in an explicit direction")
	var blocked_damage: Dictionary = _apply_damage_to_player(
		player,
		10.0,
		ELEMENTS.ELEMENT_NEUTRAL
	)
	_expect(
		not bool(blocked_damage.get("applied", true)),
		"dash invulnerability should block damage"
	)
	var cooldown_result: Dictionary = player.call("try_dash", Vector2.LEFT)
	_expect(
		not bool(cooldown_result.get("ok", true)),
		"dash should reject recast during cooldown"
	)
	await _wait_physics_frames(12)
	_expect(
		player.global_position.x > 100.0
		and player.global_position.x < 130.0,
		"dash should travel approximately 120 pixels"
	)
	await _wait_physics_frames(70)
	var fallback_dash: Dictionary = player.call("try_dash", Vector2.ZERO)
	_expect(
		bool(fallback_dash.get("ok", false)),
		"dash should fall back to aim direction without movement input"
	)
	world.queue_free()
	await get_tree().process_frame


func _expect_player_weapon_recoil() -> void:
	var world: Node2D = Node2D.new()
	world.name = "L1WeaponRecoilWorld"
	add_child(world)
	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1WeaponRecoilPlayer"
	world.add_child(player)
	player.call("configure", _l1_combat_player_stats())
	var weapons_payload: Dictionary = DataLoader.load_json(
		DataLoader.WEAPONS_PATH
	) as Dictionary
	var recoil_model: Dictionary = weapons_payload.get(
		"recoil_model",
		{}
	) as Dictionary
	player.call("configure_weapon_recoil", recoil_model)
	player.call("apply_weapon_recoil", Vector2.RIGHT, 70.0, 0.08)
	_expect(
		(player.call("weapon_recoil_velocity") as Vector2).is_equal_approx(
			Vector2(-70.0, 0.0)
		),
		"weapon recoil should add a backward impulse"
	)
	var active_snapshot: Dictionary = player.call("snapshot")
	player.call("configure", _l1_combat_player_stats())
	player.call("configure_weapon_recoil", recoil_model)
	player.call("restore_snapshot", active_snapshot)
	_expect(
		(player.call("weapon_recoil_velocity") as Vector2).is_equal_approx(
			Vector2(-70.0, 0.0)
		),
		"Player snapshot should restore recoil velocity"
	)
	_expect(
		is_equal_approx(
			float(player.call("weapon_recoil_remaining")),
			0.08
		),
		"Player snapshot should restore recoil remaining time"
	)

	GameState.change_state(GameState.PAUSED, {"source": "l1_recoil_pause"})
	await _wait_physics_frames(3)
	_expect(
		is_equal_approx(
			float(player.call("weapon_recoil_remaining")),
			0.08
		),
		"paused gameplay should freeze weapon recoil"
	)
	GameState.change_state(GameState.PLAYING, {"source": "l1_recoil_resume"})
	var half_step_velocity: Vector2 = player.call(
		"_update_weapon_recoil",
		0.04
	) as Vector2
	_expect(
		half_step_velocity.is_equal_approx(Vector2(-52.5, 0.0)),
		"weapon recoil should use the linear-decay average velocity"
	)
	player.call("apply_weapon_recoil", Vector2.DOWN, 100.0, 0.08)
	var stacked_velocity: Vector2 = player.call(
		"weapon_recoil_velocity"
	) as Vector2
	_expect(
		stacked_velocity.is_equal_approx(Vector2(-35.0, -100.0)),
		"successive shots should stack recoil vectors"
	)
	for _index: int in range(8):
		player.call("apply_weapon_recoil", Vector2.LEFT, 500.0, 0.08)
	_expect(
		(player.call("weapon_recoil_velocity") as Vector2).length() <= 500.001,
		"stacked weapon recoil should obey the configured velocity cap"
	)

	player.call("configure", _l1_combat_player_stats())
	player.call("configure_weapon_recoil", recoil_model)
	player.call("apply_weapon_recoil", Vector2.RIGHT, 70.0, 0.08)
	var dash_result: Dictionary = player.call("try_dash", Vector2.RIGHT)
	_expect(bool(dash_result.get("ok", false)), "recoil dash test should start a dash")
	var suppressed_velocity: Vector2 = player.call(
		"_update_weapon_recoil",
		0.02
	) as Vector2
	_expect(
		suppressed_velocity.is_zero_approx(),
		"active dash should suppress recoil movement"
	)
	var velocity_before_dash_shot: Vector2 = player.call(
		"weapon_recoil_velocity"
	) as Vector2
	player.call("apply_weapon_recoil", Vector2.UP, 100.0, 0.08)
	_expect(
		(player.call("weapon_recoil_velocity") as Vector2).is_equal_approx(
			velocity_before_dash_shot
		),
		"shots fired during dash should not add recoil impulse"
	)
	_expect(
		is_equal_approx(
			float(player.call("weapon_recoil_remaining")),
			0.06
		),
		"dash should keep recoil decay time moving"
	)

	player.call("configure", _l1_combat_player_stats())
	player.call("configure_weapon_recoil", recoil_model)
	player.global_position = Vector2.ZERO
	player.call("apply_weapon_recoil", Vector2.RIGHT, 70.0, 0.08)
	await _wait_physics_frames(8)
	_expect(
		player.global_position.x < -2.4
		and player.global_position.x > -3.2,
		"stationary base recoil should move the player about 2.8 pixels backward"
	)

	player.call("configure", _l1_combat_player_stats())
	player.call("configure_weapon_recoil", recoil_model)
	player.global_position = Vector2.ZERO
	var recoil_wall: StaticBody2D = StaticBody2D.new()
	recoil_wall.position = Vector2(-18.0, 0.0)
	var recoil_wall_shape: CollisionShape2D = CollisionShape2D.new()
	var recoil_wall_rectangle: RectangleShape2D = RectangleShape2D.new()
	recoil_wall_rectangle.size = Vector2(4.0, 200.0)
	recoil_wall_shape.shape = recoil_wall_rectangle
	recoil_wall.add_child(recoil_wall_shape)
	world.add_child(recoil_wall)
	player.call("apply_weapon_recoil", Vector2.RIGHT, 350.0, 0.08)
	await _wait_physics_frames(8)
	_expect(
		player.global_position.x > -6.0,
		"weapon recoil should use CharacterBody2D collision and not cross a wall"
	)
	recoil_wall.queue_free()
	await get_tree().process_frame

	player.call("configure", _l1_combat_player_stats())
	player.call("configure_weapon_recoil", recoil_model)
	player.call("set_movement_bounds", Rect2(-10.0, -10.0, 20.0, 20.0))
	player.global_position = Vector2(-10.0, 0.0)
	player.call("apply_weapon_recoil", Vector2.RIGHT, 350.0, 0.08)
	await _wait_physics_frames(8)
	_expect(
		player.global_position.x >= -10.001,
		"weapon recoil should respect world movement bounds"
	)
	world.queue_free()
	await get_tree().process_frame


func _expect_four_skill_slots_and_efficiency() -> void:
	var world: Node2D = Node2D.new()
	world.name = "L1FourSkillWorld"
	add_child(world)
	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1FourSkillPlayer"
	world.add_child(player)
	var player_stats: Dictionary = _l1_combat_player_stats()
	player_stats[STATS.MAX_SHIELD] = 0.0
	player_stats[STATS.ABILITY_EFFICIENCY] = 1.75
	player.call("configure", player_stats)
	var skill_system: Node = SKILL_SYSTEM_SCENE.instantiate()
	skill_system.name = "L1FourSkillSystem"
	add_child(skill_system)
	var skills: Array[Dictionary] = [
		_l1_self_modifier_skill(SKILL_IDS.SKILL_DEPLOY_PROJECTILE_BARRIER),
		_l1_self_modifier_skill(SKILL_IDS.SKILL_AOE_SLOW),
		_l1_self_modifier_skill(SKILL_IDS.SKILL_SELF_FIRE_MOVE_HASTE),
		_l1_self_modifier_skill(
			SKILL_IDS.SKILL_ENEMY_HASTE_VULNERABILITY
		),
	]
	skill_system.call(
		"configure",
		player,
		world,
		skills,
		[_l1_mana_resource()]
	)
	GameState.change_state(GameState.PLAYING, {"source": "l1_four_skill"})
	var first_result: Dictionary = skill_system.call(
		"cast_slot",
		SKILL_SLOTS.SKILL_1
	)
	_expect(bool(first_result.get("ok", false)), "skill slot 1 should cast")
	_expect(
		is_equal_approx(
			float(
				skill_system.call(
					"resource_amount",
					SKILL_RESOURCES.ENERGY
				)
			),
			95.0
		),
		"175 percent efficiency should reduce a 20 energy cost to 5"
	)
	_expect(
		float(
			skill_system.call(
				"cooldown_remaining",
				SKILL_SLOTS.SKILL_1
			)
		) > 0.0,
		"cast slot should own an independent cooldown"
	)
	_expect(
		is_equal_approx(
			float(
				skill_system.call(
					"cooldown_remaining",
					SKILL_SLOTS.SKILL_2
				)
			),
			0.0
		),
		"casting slot 1 should not start slot 2 cooldown"
	)
	var second_result: Dictionary = skill_system.call(
		"cast_slot",
		SKILL_SLOTS.SKILL_2
	)
	_expect(bool(second_result.get("ok", false)), "skill slot 2 should cast independently")
	_expect(
		(skill_system.call("debug_summary") as Dictionary).get(
			"skill_slots",
			[]
		).size() == 4,
		"SkillSystem should expose four stable skill slots"
	)

	player_stats[STATS.ABILITY_EFFICIENCY] = 0.25
	player.call("configure", player_stats)
	skill_system.call(
		"configure",
		player,
		world,
		skills,
		[_l1_mana_resource()]
	)
	skill_system.call("cast_slot", SKILL_SLOTS.SKILL_1)
	_expect(
		is_equal_approx(
			float(
				skill_system.call(
					"resource_amount",
					SKILL_RESOURCES.ENERGY
				)
			),
			65.0
		),
		"25 percent efficiency should increase a 20 energy cost to 35"
	)
	skill_system.queue_free()
	world.queue_free()
	await get_tree().process_frame


func _expect_skill_system_aoe_damage() -> void:
	var world: Node2D = Node2D.new()
	world.name = "L1SkillWorld"
	add_child(world)
	var caster: Node2D = Node2D.new()
	caster.name = "L1SkillCaster"
	world.add_child(caster)
	var target: SkillTarget = SkillTarget.new()
	target.name = "L1SkillTarget"
	target.global_position = Vector2(60.0, 0.0)
	target.add_to_group("active_enemies")
	world.add_child(target)
	var far_target: SkillTarget = SkillTarget.new()
	far_target.name = "L1FarSkillTarget"
	far_target.global_position = Vector2(260.0, 0.0)
	far_target.add_to_group("active_enemies")
	world.add_child(far_target)
	var skill_system: Node = SKILL_SYSTEM_SCENE.instantiate()
	skill_system.name = "L1SkillSystem"
	add_child(skill_system)
	var skills: Array[Dictionary] = [_l1_damage_skill()]
	var resources: Array[Dictionary] = [_l1_mana_resource()]
	skill_system.call("configure", caster, world, [_l1_self_silence_skill()], resources)
	GameState.change_state(GameState.PLAYING, {"source": "l1_skill_status_smoke"})
	var status_result: Dictionary = skill_system.call("cast_primary_skill")
	_expect(bool(status_result.get("ok", false)), "SkillSystem should apply status effects through a skill primitive")
	_expect(bool(skill_system.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "StatusEffectComponent should grant ability tags")
	var status_blocked_result: Dictionary = skill_system.call("cast_primary_skill")
	_expect(not bool(status_blocked_result.get("ok", true)), "StatusEffect granted tags should block ability activation")
	_expect(String(status_blocked_result.get("reason", "")) == "blocked_by_tag", "StatusEffect block should report blocked_by_tag")
	var status_snapshot: Dictionary = skill_system.call("snapshot")
	skill_system.call("configure", caster, world, [_l1_self_silence_skill()], resources)
	skill_system.call("restore_snapshot", status_snapshot)
	_expect(bool(skill_system.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "SkillSystem should restore active status ability tags")
	await _wait_physics_frames(8)
	_expect(not bool(skill_system.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "StatusEffectComponent should remove ability tags when the status expires after restore")
	var status_after_expire: Dictionary = skill_system.call("cast_primary_skill")
	_expect(bool(status_after_expire.get("ok", false)), "SkillSystem should cast again after silence expires")
	skill_system.call("apply_status_effect", _l1_silence_status(0.05))
	skill_system.call("apply_status_effect", _l1_silence_status(0.20))
	var refreshed_status_snapshot: Dictionary = skill_system.call("snapshot")
	var refreshed_effects: Array = (refreshed_status_snapshot.get("status_effects", {}) as Dictionary).get("effects", []) as Array
	_expect(not refreshed_effects.is_empty(), "StatusEffectComponent should snapshot refreshed statuses")
	if not refreshed_effects.is_empty():
		var refreshed_effect: Dictionary = refreshed_effects[0] as Dictionary
		_expect(float(refreshed_effect.get("duration", 0.0)) >= 0.19, "StatusEffect refresh should preserve longer duration for restore")

	skill_system.call("configure", caster, world, skills, resources)
	skill_system.call("restore_snapshot", {"owned_tags": [ABILITY_TAGS.ABILITY_TAG_SILENCED]})
	_expect(bool(skill_system.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "SkillSystem should restore legacy owned ability tags")
	var counted_tag_snapshot: Dictionary = {"owned_tag_counts": {}}
	(counted_tag_snapshot["owned_tag_counts"] as Dictionary)[ABILITY_TAGS.ABILITY_TAG_SILENCED] = 2
	skill_system.call("restore_snapshot", counted_tag_snapshot)
	_expect(bool(skill_system.call("remove_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "SkillSystem should decrement counted ability tags")
	_expect(bool(skill_system.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "SkillSystem should keep counted ability tags until count reaches zero")
	_expect(bool(skill_system.call("remove_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "SkillSystem should remove counted ability tags at zero")
	_expect(not bool(skill_system.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "SkillSystem should clear counted ability tags after the final remove")

	GameState.change_state(GameState.PLAYING, {"source": "l1_skill_smoke"})
	_expect(bool(skill_system.call("add_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "SkillSystem should accept registered ability tags")
	var blocked_result: Dictionary = skill_system.call("cast_primary_skill")
	_expect(not bool(blocked_result.get("ok", true)), "SkillSystem should block silenced ability activation")
	_expect(String(blocked_result.get("reason", "")) == "blocked_by_tag", "SkillSystem should report blocked tag reason")
	_expect(String(blocked_result.get("tag", "")) == ABILITY_TAGS.ABILITY_TAG_SILENCED, "SkillSystem should report the blocking tag")
	_expect(bool(skill_system.call("remove_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "SkillSystem should remove owned ability tags")
	var result: Dictionary = skill_system.call("cast_primary_skill")
	_expect(bool(result.get("ok", false)), "SkillSystem should cast an AOE skill")
	_expect(int(result.get("applied_targets", 0)) == 1, "SkillSystem should damage one target in radius")
	_expect(is_equal_approx(target.life, 6.0), "SkillSystem should route skill damage through Combat")
	_expect(is_equal_approx(far_target.life, 10.0), "SkillSystem should ignore targets outside radius")
	var resource_snapshot: Dictionary = skill_system.call("resource_snapshot")
	var mana: Dictionary = resource_snapshot[SKILL_RESOURCES.ENERGY] as Dictionary
	_expect(is_equal_approx(float(mana.get("current", 0.0)), 75.0), "SkillSystem should spend mana")
	var cooldown_result: Dictionary = skill_system.call("cast_primary_skill")
	_expect(not bool(cooldown_result.get("ok", true)), "SkillSystem should block immediate recast while on cooldown")
	_expect(String(cooldown_result.get("reason", "")) == "cooldown", "SkillSystem should report cooldown reason")
	var debug_summary: Dictionary = skill_system.call("debug_summary")
	var owned_tags: Array = debug_summary.get("owned_tags", []) as Array
	_expect(not owned_tags.has(ABILITY_TAGS.ABILITY_TAG_ACTIVATING), "SkillSystem should release transient activation tags after instant effects")

	target.remove_from_group("active_enemies")
	far_target.remove_from_group("active_enemies")
	skill_system.queue_free()
	world.queue_free()


func _expect_entity_status_components() -> void:
	var world: Node2D = Node2D.new()
	world.name = "L1EntityStatusWorld"
	add_child(world)

	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1StatusPlayer"
	world.add_child(player)
	player.call("configure", _l1_player_stats())

	var enemy: Node2D = ENEMY_SCENE.instantiate() as Node2D
	enemy.name = "L1StatusEnemy"
	enemy.global_position = Vector2(48.0, 0.0)
	world.add_child(enemy)
	enemy.call("configure", _l1_enemy_data(), player)

	var skill_system: Node = SKILL_SYSTEM_SCENE.instantiate()
	skill_system.name = "L1EntityStatusSkillSystem"
	add_child(skill_system)
	skill_system.call("configure", player, world, [_l1_enemy_silence_skill()], [])
	GameState.change_state(GameState.PLAYING, {"source": "l1_entity_status_smoke"})

	var enemy_status_result: Dictionary = skill_system.call("cast_primary_skill")
	_expect(bool(enemy_status_result.get("ok", false)), "SkillSystem should apply status effects to real Enemy targets")
	_expect(bool(enemy.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "Enemy should own status-granted ability tags")
	_expect((enemy.call("active_statuses") as Array).has(STATUS_EFFECTS.SILENCE), "Enemy should report active status ids")
	var enemy_snapshot: Dictionary = enemy.call("snapshot")
	enemy.call("configure", _l1_enemy_data(), player)
	_expect(not bool(enemy.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "Enemy configure should clear pooled status tags")
	_expect((enemy.call("active_statuses") as Array).is_empty(), "Enemy configure should clear pooled active statuses")
	enemy.call("restore_snapshot", enemy_snapshot)
	_expect(bool(enemy.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "Enemy should restore status-granted ability tags")

	var player_status_result: Dictionary = player.call("apply_status_effect", _l1_silence_status(0.06))
	_expect(bool(player_status_result.get("applied", false)), "Player should accept direct status effects")
	_expect(bool(player.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "Player should own status-granted ability tags")
	var player_snapshot: Dictionary = player.call("snapshot")
	player.call("configure", _l1_player_stats())
	_expect(not bool(player.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "Player configure should clear status tags for a new run")
	_expect((player.call("active_statuses") as Array).is_empty(), "Player configure should clear active statuses for a new run")
	player.call("restore_snapshot", player_snapshot)
	_expect(bool(player.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "Player should restore status-granted ability tags")

	await _wait_physics_frames(8)
	_expect(not bool(enemy.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "Enemy should remove status-granted tags on expiration")
	_expect(not bool(player.call("has_owned_tag", ABILITY_TAGS.ABILITY_TAG_SILENCED)), "Player should remove status-granted tags on expiration")

	enemy.remove_from_group("active_enemies")
	skill_system.queue_free()
	world.queue_free()


func _expect_status_modifiers_and_vulnerability() -> void:
	var world: Node2D = Node2D.new()
	world.name = "L1StatusModifierWorld"
	add_child(world)
	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1StatusModifierPlayer"
	world.add_child(player)
	player.call("configure", _l1_combat_player_stats())
	var enemy: Node2D = ENEMY_SCENE.instantiate() as Node2D
	enemy.name = "L1StatusModifierEnemy"
	world.add_child(enemy)
	var enemy_data: Dictionary = _l1_enemy_data()
	enemy_data["max_hp"] = 500.0
	enemy.call("configure", enemy_data, player)
	GameState.change_state(
		GameState.PLAYING,
		{"source": "l1_status_modifiers"}
	)

	var slow: Resource = STATUS_EFFECT_SCRIPT.new().setup(
		STATUS_EFFECTS.SLOW,
		{
			"duration": 2.0,
			"stack_rule": STATUS_STACK_RULES.MAX_MAGNITUDE,
			"magnitude": 0.35,
			"modifiers": [
				{
					"stat": STATS.MOVE_SPEED,
					"type": "mult",
					"value": 0.65,
				},
			],
		},
		player
	)
	var haste: Resource = STATUS_EFFECT_SCRIPT.new().setup(
		STATUS_EFFECTS.HASTE,
		{
			"duration": 2.0,
			"stack_rule": STATUS_STACK_RULES.REFRESH,
			"magnitude": 0.1,
			"modifiers": [
				{
					"stat": STATS.MOVE_SPEED,
					"type": "mult",
					"value": 1.1,
				},
			],
		},
		player
	)
	enemy.call("apply_status_effect", slow)
	enemy.call("apply_status_effect", haste)
	_expect(
		absf(
			float(enemy.call(
				"status_stat_multiplier",
				STATS.MOVE_SPEED
			))
			- 0.715
		) <= 0.001,
		"slow and enemy haste should multiply together"
	)

	for _stack_index: int in range(5):
		enemy.call(
			"apply_status_effect",
			_l1_vulnerability_status(player)
		)
	_expect(
		int(enemy.call(
			"status_stack_count",
			STATUS_EFFECTS.VULNERABLE
		)) == 5,
		"vulnerability should stack to five"
	)
	await _wait_physics_frames(8)
	var remaining_before_refresh: float = _status_remaining(
		enemy,
		STATUS_EFFECTS.VULNERABLE
	)
	enemy.call(
		"apply_status_effect",
		_l1_vulnerability_status(player)
	)
	_expect(
		int(enemy.call(
			"status_stack_count",
			STATUS_EFFECTS.VULNERABLE
		)) == 5,
		"vulnerability should stay capped at five stacks"
	)
	_expect(
		_status_remaining(enemy, STATUS_EFFECTS.VULNERABLE)
		> remaining_before_refresh,
		"full vulnerability stacks should refresh their duration"
	)

	var life_before_player_hit: float = _enemy_life(enemy)
	_apply_damage_to_enemy(
		enemy,
		10.0,
		TEAM_PLAYER
	)
	_expect(
		absf(
			(life_before_player_hit - _enemy_life(enemy))
			- 15.0
		) <= 0.01,
		"five vulnerability stacks should amplify player damage by 50 percent"
	)
	var life_before_environment_hit: float = _enemy_life(enemy)
	_apply_damage_to_enemy(enemy, 10.0, "")
	_expect(
		absf(
			(life_before_environment_hit - _enemy_life(enemy))
			- 10.0
		) <= 0.01,
		"vulnerability should ignore environment damage"
	)
	var life_before_dot_hit: float = _enemy_life(enemy)
	_apply_damage_to_enemy(
		enemy,
		10.0,
		TEAM_PLAYER,
		PackedStringArray([DOT_DAMAGE_FLAG])
	)
	_expect(
		absf(
			(life_before_dot_hit - _enemy_life(enemy))
			- 15.0
		) <= 0.01,
		"vulnerability should amplify player-attributed damage over time"
	)

	enemy.remove_from_group("active_enemies")
	world.queue_free()
	await get_tree().process_frame


func _expect_barrier_and_energy_orb() -> void:
	_ensure_l1_combat_pools()
	var world: Node2D = Node2D.new()
	world.name = "L1BarrierEnergyWorld"
	add_child(world)
	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1BarrierEnergyPlayer"
	world.add_child(player)
	player.call("configure", _l1_combat_player_stats())
	var skill_system: Node = SKILL_SYSTEM_SCENE.instantiate()
	skill_system.name = "L1BarrierEnergySkillSystem"
	add_child(skill_system)
	var barrier_skill_1: Dictionary = _l1_skill_definition(
		SKILL_IDS.SKILL_DEPLOY_PROJECTILE_BARRIER
	)
	barrier_skill_1["slot_id"] = SKILL_SLOTS.SKILL_1
	var barrier_skill_3: Dictionary = barrier_skill_1.duplicate(true)
	barrier_skill_3["slot_id"] = SKILL_SLOTS.SKILL_3
	barrier_skill_3["cost_multiplier"] = 1.5
	barrier_skill_3["cooldown_multiplier"] = 1.5
	skill_system.call(
		"configure",
		player,
		world,
		[
			barrier_skill_1,
			barrier_skill_3,
		],
		[_l1_mana_resource()]
	)
	GameState.change_state(
		GameState.PLAYING,
		{"source": "l1_barrier_energy"}
	)
	var cast_result: Dictionary = skill_system.call(
		"cast_slot",
		SKILL_SLOTS.SKILL_1
	)
	_expect(
		bool(cast_result.get("ok", false)),
		"barrier skill should deploy from its stable slot"
	)
	var barriers: Array[Node] = get_tree().get_nodes_in_group(
		"active_deployables"
	)
	_expect(
		barriers.size() == 1,
		"barrier skill should allow only one active deployment"
	)
	if barriers.is_empty():
		skill_system.queue_free()
		world.queue_free()
		await get_tree().process_frame
		return
	var barrier: Node = barriers[0]
	var barrier_max_health: float = float(
		barrier.call("current_health")
	)
	var friendly_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		10.0,
		ELEMENTS.ELEMENT_NEUTRAL,
		player,
		barrier,
		TEAM_PLAYER,
		TEAM_ENEMY
	)
	barrier.call("receive_projectile_damage", friendly_info)
	_expect(
		is_equal_approx(
			float(barrier.call("current_health")),
			barrier_max_health
		),
		"barrier should ignore player projectile damage"
	)

	var barrier_position: Vector2 = (barrier as Node2D).global_position
	_expect(
		float(
			barrier.call(
				"projectile_boundary_hit_fraction",
				barrier_position + Vector2(-80.0, 0.0),
				barrier_position + Vector2(80.0, 0.0),
				0.0
			)
		) < 0.0,
		"enemy projectiles should remain unblocked while staying inside a barrier"
	)
	_expect(
		float(
			barrier.call(
				"projectile_boundary_hit_fraction",
				barrier_position + Vector2(-220.0, 220.0),
				barrier_position + Vector2(220.0, 220.0),
				0.0
			)
		) < 0.0,
		"enemy projectiles should remain unblocked while staying outside a barrier"
	)
	_expect(
		float(
			barrier.call(
				"projectile_boundary_hit_fraction",
				barrier_position + Vector2(-220.0, 0.0),
				barrier_position + Vector2(-80.0, 0.0),
				0.0
			)
		) >= 0.0,
		"enemy projectiles should be blocked when entering a barrier"
	)
	_expect(
		float(
			barrier.call(
				"projectile_boundary_hit_fraction",
				barrier_position + Vector2(80.0, 0.0),
				barrier_position + Vector2(220.0, 0.0),
				0.0
			)
		) >= 0.0,
		"enemy projectiles should be blocked when leaving a barrier"
	)
	_expect(
		float(
			barrier.call(
				"projectile_boundary_hit_fraction",
				barrier_position + Vector2(-220.0, 0.0),
				barrier_position + Vector2(220.0, 0.0),
				0.0
			)
		) >= 0.0,
		"enemy projectiles should be blocked when crossing an entire barrier"
	)

	var inside_source: Node2D = Node2D.new()
	world.add_child(inside_source)
	inside_source.global_position = Vector2(-100.0, 0.0)
	var player_shield_before_inside_hit: float = float(
		player.call("current_shield")
	)
	var inside_bullet: Node2D = PoolManager.acquire(
		POOL_IDS.BULLET_BASIC
	) as Node2D
	_reparent_l1_node(inside_bullet, world)
	inside_bullet.global_position = Vector2(-80.0, 0.0)
	inside_bullet.call(
		"configure",
		_l1_bullet_stats(),
		_l1_projectile_data(
			TEAM_ENEMY,
			TEAM_PLAYER,
			[
				"active_projectile_blockers",
				"active_player",
			]
		),
		Vector2.RIGHT,
		inside_source
	)
	await _wait_physics_frames(12)
	_expect(
		float(player.call("current_shield"))
		< player_shield_before_inside_hit,
		"an enemy inside a barrier should be able to shoot a target inside it"
	)
	_expect(
		is_equal_approx(
			float(barrier.call("current_health")),
			barrier_max_health
		),
		"inside-to-inside enemy fire should not damage the barrier"
	)

	inside_source.global_position = Vector2(150.0, 0.0)
	var inside_exit_bullet: Node2D = PoolManager.acquire(
		POOL_IDS.BULLET_BASIC
	) as Node2D
	_reparent_l1_node(inside_exit_bullet, world)
	inside_exit_bullet.global_position = Vector2(170.0, 0.0)
	inside_exit_bullet.call(
		"configure",
		_l1_bullet_stats(),
		_l1_projectile_data(
			TEAM_ENEMY,
			TEAM_PLAYER,
			["missing_l1_targets"]
		),
		Vector2.RIGHT,
		inside_source
	)
	var inside_exit_snapshot: Dictionary = inside_exit_bullet.call(
		"snapshot"
	)
	_expect(
		bool(
			inside_exit_snapshot.get(
				"initial_deployable_sweep_pending",
				false
			)
		),
		"enemy projectile snapshot should retain its initial barrier sweep"
	)
	var inside_exit_sweep_start: Dictionary = inside_exit_snapshot.get(
		"initial_deployable_sweep_start",
		{}
	) as Dictionary
	_expect(
		is_equal_approx(
			float(inside_exit_sweep_start.get("x", 0.0)),
			inside_source.global_position.x
		),
		"enemy projectile snapshot should retain the shooter firing position"
	)
	PoolManager.release(inside_exit_bullet)
	inside_exit_bullet = PoolManager.acquire(
		POOL_IDS.BULLET_BASIC
	) as Node2D
	_reparent_l1_node(inside_exit_bullet, world)
	inside_exit_bullet.call(
		"restore_snapshot",
		inside_exit_snapshot,
		inside_source
	)
	await _wait_physics_frames(2)
	_expect(
		float(barrier.call("current_health"))
		< barrier_max_health,
		"an inside enemy muzzle should not skip the barrier when firing outside"
	)
	_expect(
		PoolManager.active_count(POOL_IDS.BULLET_BASIC) == 0,
		"an inside-to-outside enemy projectile should release at the barrier"
	)

	skill_system.call("debug_refresh")
	skill_system.call(
		"cast_slot",
		SKILL_SLOTS.SKILL_3
	)
	barriers = get_tree().get_nodes_in_group("active_deployables")
	_expect(
		barriers.size() == 1,
		"barrier recast should replace the boundary test deployment"
	)
	if not barriers.is_empty():
		barrier = barriers[0]

	var outside_source: Node2D = Node2D.new()
	world.add_child(outside_source)
	outside_source.global_position = Vector2(-170.0, 0.0)
	var enemy_bullet: Node2D = PoolManager.acquire(
		POOL_IDS.BULLET_BASIC
	) as Node2D
	_reparent_l1_node(enemy_bullet, world)
	enemy_bullet.global_position = Vector2(-150.0, 0.0)
	enemy_bullet.call(
		"configure",
		_l1_bullet_stats(),
		_l1_projectile_data(
			TEAM_ENEMY,
			TEAM_PLAYER,
			["active_player"]
		),
		Vector2.RIGHT,
		outside_source
	)
	await _wait_physics_frames(2)
	_expect(
		float(barrier.call("current_health"))
		< barrier_max_health,
		"an outside enemy muzzle should not skip the barrier when firing inside"
	)
	_expect(
		PoolManager.active_count(POOL_IDS.BULLET_BASIC) == 0,
		"enemy projectile should release after hitting a barrier"
	)

	skill_system.call("debug_refresh")
	skill_system.call(
		"cast_slot",
		SKILL_SLOTS.SKILL_3
	)
	barriers = get_tree().get_nodes_in_group("active_deployables")
	_expect(
		barriers.size() == 1,
		"barrier recast from a duplicate slot should replace the previous deployment"
	)
	if not barriers.is_empty():
		barrier = barriers[0]
	_expect(
		is_equal_approx(
			float(barrier.call("current_health")),
			barrier_max_health
		),
		"replacement barrier should start at full health"
	)

	var player_bullet: Node2D = PoolManager.acquire(
		POOL_IDS.BULLET_BASIC
	) as Node2D
	_reparent_l1_node(player_bullet, world)
	player_bullet.global_position = Vector2(-220.0, 0.0)
	player_bullet.call(
		"configure",
		_l1_bullet_stats(),
		_l1_projectile_data(
			TEAM_PLAYER,
			TEAM_ENEMY,
			["active_deployables"]
		),
		Vector2.RIGHT,
		player
	)
	await _wait_physics_frames(60)
	_expect(
		is_equal_approx(
			float(barrier.call("current_health")),
			barrier_max_health
		),
		"player projectiles should pass through deployable barriers"
	)

	skill_system.call("debug_refresh")
	var full_orb: Node2D = PoolManager.acquire(
		POOL_IDS.ENERGY_ORB
	) as Node2D
	_reparent_l1_node(full_orb, world)
	full_orb.global_position = player.global_position
	full_orb.call(
		"configure",
		25.0,
		player,
		skill_system,
		360.0,
		SKILL_RESOURCES.ENERGY
	)
	await _wait_physics_frames(3)
	_expect(
		PoolManager.active_count(POOL_IDS.ENERGY_ORB) == 1,
		"full energy should not collect a nearby energy orb"
	)
	PoolManager.release(full_orb)

	skill_system.call(
		"cast_slot",
		SKILL_SLOTS.SKILL_1
	)
	var partial_orb: Node2D = PoolManager.acquire(
		POOL_IDS.ENERGY_ORB
	) as Node2D
	_reparent_l1_node(partial_orb, world)
	partial_orb.global_position = player.global_position
	partial_orb.call(
		"configure",
		25.0,
		player,
		skill_system,
		360.0,
		SKILL_RESOURCES.ENERGY
	)
	await _wait_physics_frames(3)
	_expect(
		is_equal_approx(
			float(skill_system.call(
				"resource_amount",
				SKILL_RESOURCES.ENERGY
			)),
			85.0
		),
		"energy orb should restore 25 energy when the resource is not full"
	)
	_expect(
		PoolManager.active_count(POOL_IDS.ENERGY_ORB) == 0,
		"collected energy orb should return to its pool"
	)

	skill_system.queue_free()
	await get_tree().process_frame
	world.queue_free()
	await get_tree().process_frame


func _expect_poison_dot_status() -> void:
	var world: Node2D = Node2D.new()
	world.name = "L1PoisonWorld"
	add_child(world)

	var player: Node2D = PLAYER_SCENE.instantiate() as Node2D
	player.name = "L1PoisonPlayer"
	world.add_child(player)
	player.call("configure", _l1_player_stats())

	var enemy: Node2D = ENEMY_SCENE.instantiate() as Node2D
	enemy.name = "L1PoisonEnemy"
	enemy.global_position = Vector2(48.0, 0.0)
	world.add_child(enemy)
	var enemy_data: Dictionary = _l1_enemy_data()
	enemy_data["max_hp"] = 20.0
	enemy.call("configure", enemy_data, player)

	var skill_system: Node = SKILL_SYSTEM_SCENE.instantiate()
	skill_system.name = "L1PoisonSkillSystem"
	add_child(skill_system)
	skill_system.call("configure", player, world, [_l1_poison_dot_skill()], [_l1_mana_resource()])

	var dot_events: Array[Dictionary] = []
	var dot_event_sink: Callable = func(target: Node, info: RefCounted, result: Dictionary) -> void:
		var flags: PackedStringArray = info.get("flags")
		if target != enemy or not flags.has(DOT_DAMAGE_FLAG):
			return
		dot_events.append({
			"element_id": String(info.get("element_id")),
			"source_team": String(info.get("source_team")),
			"target_team": String(info.get("target_team")),
			"applied": bool(result.get("applied", false)),
		})
	Combat.damage_applied.connect(dot_event_sink)

	GameState.change_state(GameState.PLAYING, {"source": "l1_poison_smoke"})
	var poison_result: Dictionary = skill_system.call("cast_primary_skill")
	_expect(bool(poison_result.get("ok", false)), "SkillSystem should apply poison through skill_effect_apply_status")
	_expect((enemy.call("active_statuses") as Array).has(STATUS_EFFECTS.POISON), "Enemy should report poison as an active status")
	var starting_life: float = _enemy_life(enemy)
	await _wait_physics_frames(16)
	var poisoned_life: float = _enemy_life(enemy)
	_expect(poisoned_life < starting_life, "Poison should damage an Enemy over time")
	_expect(not dot_events.is_empty(), "Poison DoT should route damage through Combat")
	if not dot_events.is_empty():
		var first_event: Dictionary = dot_events[0]
		_expect(String(first_event.get("element_id", "")) == ELEMENTS.ELEMENT_PRIMARY_C, "Poison DoT should use its configured element")
		_expect(String(first_event.get("source_team", "")) == TEAM_PLAYER, "Poison DoT should preserve player source team")
		_expect(String(first_event.get("target_team", "")) == TEAM_ENEMY, "Poison DoT should preserve enemy target team")
		_expect(bool(first_event.get("applied", false)), "Poison DoT Combat result should apply")

	var poison_snapshot: Dictionary = enemy.call("snapshot")
	var poison_effects: Array = (poison_snapshot.get("status_effects", {}) as Dictionary).get("effects", []) as Array
	_expect(not poison_effects.is_empty(), "Poison should enter Enemy status snapshots")
	if not poison_effects.is_empty():
		var poison_effect: Dictionary = poison_effects[0] as Dictionary
		_expect(String(poison_effect.get("element_id", "")) == ELEMENTS.ELEMENT_PRIMARY_C, "Poison snapshot should preserve element_id")
		_expect(float(poison_effect.get("tick_remaining", 0.0)) > 0.0, "Poison snapshot should preserve tick_remaining")
		_expect(String(poison_effect.get("source_team", "")) == TEAM_PLAYER, "Poison snapshot should preserve source_team")
		_expect(String(poison_effect.get("target_team", "")) == TEAM_ENEMY, "Poison snapshot should preserve target_team")

	GameState.change_state(GameState.PAUSED, {"source": "l1_poison_pause"})
	var paused_life: float = _enemy_life(enemy)
	await _wait_physics_frames(6)
	_expect(is_equal_approx(_enemy_life(enemy), paused_life), "Poison should not tick while GameState is paused")

	enemy.call("configure", enemy_data, player)
	enemy.call("restore_snapshot", poison_snapshot)
	_expect((enemy.call("active_statuses") as Array).has(STATUS_EFFECTS.POISON), "Enemy should restore active poison from snapshot")
	GameState.change_state(GameState.PLAYING, {"source": "l1_poison_restore"})
	var restored_life: float = _enemy_life(enemy)
	await _wait_physics_frames(16)
	_expect(_enemy_life(enemy) < restored_life, "Restored poison should resume ticking")
	await _wait_physics_frames(80)
	_expect(not (enemy.call("active_statuses") as Array).has(STATUS_EFFECTS.POISON), "Poison should expire through StatusEffectComponent")

	if Combat.damage_applied.is_connected(dot_event_sink):
		Combat.damage_applied.disconnect(dot_event_sink)
	enemy.remove_from_group("active_enemies")
	skill_system.queue_free()
	world.queue_free()


func _l1_combat_player_stats() -> Dictionary:
	return {
		STATS.MAX_HP: 100.0,
		STATS.MAX_SHIELD: 100.0,
		STATS.MAX_ENERGY: 100.0,
		STATS.ARMOR: 0.0,
		STATS.MOVE_SPEED: 240.0,
		STATS.HEALTH_REGEN: 0.0,
		STATS.ABILITY_STRENGTH: 1.0,
		STATS.ABILITY_RANGE: 1.0,
		STATS.ABILITY_EFFICIENCY: 1.0,
		STATS.ABILITY_DURATION: 1.0,
		STATS.PLAYER_SEPARATION_RADIUS: 0.0,
		STATS.PICKUP_RANGE: 96.0,
		STATS.PICKUP_ORB_SPEED: 360.0,
		STATS.LUCK: 0.0,
	}


func _apply_damage_to_player(
	player: Node,
	amount: float,
	element_id: String,
	source_team: String = TEAM_ENEMY,
	flags: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		amount,
		element_id,
		self,
		player,
		source_team,
		TEAM_PLAYER,
		flags
	)
	return Combat.apply_damage(player, info)


func _apply_damage_to_enemy(
	enemy: Node,
	amount: float,
	source_team: String,
	flags: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		amount,
		ELEMENTS.ELEMENT_NEUTRAL,
		self,
		enemy,
		source_team,
		TEAM_ENEMY,
		flags
	)
	return Combat.apply_damage(enemy, info)


func _l1_self_modifier_skill(skill_id: String) -> Dictionary:
	return {
		"id": skill_id,
		"ability_tags": [
			ABILITY_TAGS.ABILITY_TAG_SKILL,
			ABILITY_TAGS.ABILITY_TAG_PRIMARY,
		],
		"activation": {
			"required_tags": [],
			"blocked_tags": [],
			"granted_tags": [],
		},
		"cooldown": 5.0,
		"costs": [
			{
				"resource": SKILL_RESOURCES.ENERGY,
				"amount": 20.0,
			},
		],
		"targeting": {
			"type": SKILL_TARGETING.TARGET_SELF,
			"radius": 0.0,
			"max_targets": 1,
		},
		"scaling": {
			"cost_stat": STATS.ABILITY_EFFICIENCY,
		},
		"effects": [
			{
				"effect":
					SKILL_EFFECTS.SKILL_EFFECT_ACTOR_MODIFIERS,
				"params": {
					"duration": 1.0,
					"modifiers": [
						{
							"stat": STATS.MOVE_SPEED,
							"type": "mult",
							"value": 1.0,
						},
					],
				},
			},
		],
	}


func _l1_vulnerability_status(source: Node) -> Resource:
	return STATUS_EFFECT_SCRIPT.new().setup(
		STATUS_EFFECTS.VULNERABLE,
		{
			"duration": 0.5,
			"stack_rule": STATUS_STACK_RULES.ADD_STACK_REFRESH,
			"magnitude": 0.1,
			"max_stacks": 5,
			"incoming_damage_per_stack": 0.1,
			"incoming_damage_source_team": TEAM_PLAYER,
		},
		source
	)


func _status_remaining(owner: Node, status_id: String) -> float:
	var summaries: Array = owner.call("status_summary") as Array
	for raw_summary: Variant in summaries:
		if not raw_summary is Dictionary:
			continue
		var summary: Dictionary = raw_summary as Dictionary
		if String(summary.get("id", "")) == status_id:
			return float(summary.get("remaining", 0.0))
	return 0.0


func _l1_bullet_stats() -> Dictionary:
	return {
		STATS.DAMAGE: 10.0,
		STATS.BULLET_SPEED: 600.0,
		STATS.BULLET_RANGE: 500.0,
		STATS.PIERCE_COUNT: 0,
	}


func _l1_projectile_data(
	source_team: String,
	target_team: String,
	damage_target_groups: Array[String]
) -> Dictionary:
	return {
		"element_id": ELEMENTS.ELEMENT_NEUTRAL,
		"damage_target_groups": damage_target_groups,
		"hit_radius": 4.0,
		"lifetime": 1.0,
		"source_team": source_team,
		"target_team": target_team,
	}


func _ensure_l1_combat_pools() -> void:
	if not PoolManager.has_pool(POOL_IDS.BULLET_BASIC):
		PoolManager.register_pool(
			POOL_IDS.BULLET_BASIC,
			Callable(self, "_instantiate_l1_scene").bind(
				BULLET_SCENE
			),
			8
		)
	if not PoolManager.has_pool(POOL_IDS.PROJECTILE_BARRIER):
		PoolManager.register_pool(
			POOL_IDS.PROJECTILE_BARRIER,
			Callable(self, "_instantiate_l1_scene").bind(
				PROJECTILE_BARRIER_SCENE
			),
			4
		)
	if not PoolManager.has_pool(POOL_IDS.ENERGY_ORB):
		PoolManager.register_pool(
			POOL_IDS.ENERGY_ORB,
			Callable(self, "_instantiate_l1_scene").bind(
				ENERGY_ORB_SCENE
			),
			4
		)


func _instantiate_l1_scene(scene: PackedScene) -> Node:
	return scene.instantiate()


func _reparent_l1_node(node: Node, target_parent: Node) -> void:
	if node == null or target_parent == null:
		return
	var old_parent: Node = node.get_parent()
	if old_parent == target_parent:
		return
	if old_parent != null:
		old_parent.remove_child(node)
	target_parent.add_child(node)


func _l1_damage_skill() -> Dictionary:
	return {
		"id": SKILL_IDS.SKILL_AOE_SLOW,
		"ability_tags": [
			ABILITY_TAGS.ABILITY_TAG_SKILL,
			ABILITY_TAGS.ABILITY_TAG_PRIMARY,
			ABILITY_TAGS.ABILITY_TAG_DAMAGE,
		],
		"activation": {
			"required_tags": [],
			"blocked_tags": [ABILITY_TAGS.ABILITY_TAG_SILENCED],
			"granted_tags": [ABILITY_TAGS.ABILITY_TAG_ACTIVATING],
		},
		"cooldown": 3.0,
		"costs": [
			{"resource": SKILL_RESOURCES.ENERGY, "amount": 25.0},
		],
		"targeting": {
			"type": SKILL_TARGETING.AOE_ENEMIES_AROUND_CASTER,
			"radius": 120.0,
			"max_targets": 0,
		},
		"effects": [
			{
				"effect": SKILL_EFFECTS.SKILL_EFFECT_DAMAGE,
				"params": {"amount": 4.0, "element_id": ELEMENTS.ELEMENT_NEUTRAL},
			},
		],
	}


func _l1_self_silence_skill() -> Dictionary:
	return {
		"id": SKILL_IDS.SKILL_SELF_FIRE_MOVE_HASTE,
		"ability_tags": [
			ABILITY_TAGS.ABILITY_TAG_SKILL,
			ABILITY_TAGS.ABILITY_TAG_PRIMARY,
		],
		"activation": {
			"required_tags": [],
			"blocked_tags": [ABILITY_TAGS.ABILITY_TAG_SILENCED],
			"granted_tags": [ABILITY_TAGS.ABILITY_TAG_ACTIVATING],
		},
		"cooldown": 0.0,
		"costs": [],
		"targeting": {
			"type": SKILL_TARGETING.TARGET_ALLY,
			"radius": 0.0,
			"max_targets": 1,
		},
		"effects": [
			{
				"effect": SKILL_EFFECTS.SKILL_EFFECT_APPLY_STATUS,
				"params": {
					"status": STATUS_EFFECTS.SILENCE,
					"duration": 0.06,
					"stack_rule": STATUS_STACK_RULES.REFRESH,
					"granted_ability_tags": [ABILITY_TAGS.ABILITY_TAG_SILENCED],
				},
			},
		],
	}


func _l1_poison_dot_skill() -> Dictionary:
	return {
		"id": SKILL_IDS.SKILL_ENEMY_HASTE_VULNERABILITY,
		"ability_tags": [
			ABILITY_TAGS.ABILITY_TAG_SKILL,
			ABILITY_TAGS.ABILITY_TAG_PRIMARY,
			ABILITY_TAGS.ABILITY_TAG_DAMAGE,
		],
		"activation": {
			"required_tags": [],
			"blocked_tags": [ABILITY_TAGS.ABILITY_TAG_SILENCED],
			"granted_tags": [ABILITY_TAGS.ABILITY_TAG_ACTIVATING],
		},
		"cooldown": 0.0,
		"costs": [],
		"targeting": {
			"type": SKILL_TARGETING.TARGET_ENEMY,
			"radius": 180.0,
			"max_targets": 1,
		},
		"effects": [
			{
				"effect": SKILL_EFFECTS.SKILL_EFFECT_APPLY_STATUS,
				"params": {
					"status": STATUS_EFFECTS.POISON,
					"duration": 1.2,
					"stack_rule": STATUS_STACK_RULES.REFRESH,
					"granted_ability_tags": [],
					"magnitude": 1.5,
					"tick_interval": 0.2,
					"element_id": ELEMENTS.ELEMENT_PRIMARY_C,
				},
			},
		],
	}


func _l1_enemy_silence_skill() -> Dictionary:
	return {
		"id": SKILL_IDS.SKILL_DEPLOY_PROJECTILE_BARRIER,
		"ability_tags": [
			ABILITY_TAGS.ABILITY_TAG_SKILL,
			ABILITY_TAGS.ABILITY_TAG_PRIMARY,
		],
		"activation": {
			"required_tags": [],
			"blocked_tags": [],
			"granted_tags": [],
		},
		"cooldown": 0.0,
		"costs": [],
		"targeting": {
			"type": SKILL_TARGETING.TARGET_ENEMY,
			"radius": 120.0,
			"max_targets": 1,
		},
		"effects": [
			{
				"effect": SKILL_EFFECTS.SKILL_EFFECT_APPLY_STATUS,
				"params": {
					"status": STATUS_EFFECTS.SILENCE,
					"duration": 0.06,
					"stack_rule": STATUS_STACK_RULES.REFRESH,
					"granted_ability_tags": [ABILITY_TAGS.ABILITY_TAG_SILENCED],
				},
			},
		],
	}


func _l1_silence_status(duration: float) -> Resource:
	return STATUS_EFFECT_SCRIPT.new().setup(
		STATUS_EFFECTS.SILENCE,
		{
			"duration": duration,
			"stack_rule": STATUS_STACK_RULES.REFRESH,
			"granted_ability_tags": [ABILITY_TAGS.ABILITY_TAG_SILENCED],
		},
		null
	)


func _l1_skill_definition(skill_id: String) -> Dictionary:
	var payload: Variant = DataLoader.load_json(DataLoader.SKILLS_PATH)
	if not payload is Dictionary:
		return {}
	for skill: Variant in (payload as Dictionary).get("skills", []):
		if skill is Dictionary and String((skill as Dictionary).get("id", "")) == skill_id:
			return (skill as Dictionary).duplicate(true)
	return {}


func _l1_mana_resource() -> Dictionary:
	return {
		"id": SKILL_RESOURCES.ENERGY,
		"max": 100.0,
		"start": 100.0,
		"regen_per_second": 0.0,
	}


func _l1_player_stats() -> Dictionary:
	return {
		STATS.MAX_HP: 10.0,
		STATS.MOVE_SPEED: 0.0,
		STATS.PLAYER_SEPARATION_RADIUS: 0.0,
		STATS.PICKUP_RANGE: 0.0,
		STATS.PICKUP_ORB_SPEED: 0.0,
		STATS.LUCK: 0.0,
	}


func _l1_enemy_data() -> Dictionary:
	return {
		"id": "enemy_l1_status",
		"tags": [],
		"pool_id": POOL_IDS.ENEMY_CHASER,
		"ai_profile_id": "enemy_ai_chase_contact",
		"ai_profile": {},
		"max_hp": 10.0,
		"move_speed": 0.0,
		"contact_damage": 0.0,
		"element_id": ELEMENTS.ELEMENT_NEUTRAL,
		"exp_reward": 0,
		"hit_radius": 10.0,
		"separation_radius": 0.0,
	}


func _enemy_life(enemy: Node) -> float:
	var enemy_snapshot: Dictionary = enemy.call("snapshot") as Dictionary
	return float(enemy_snapshot.get("life_points", 0.0))


func _wait_physics_frames(frame_count: int) -> void:
	for _index: int in range(frame_count):
		await get_tree().physics_frame


func _expect_mod_loader_data_patch() -> void:
	_remove_l1_mod()
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(MOD_SMOKE_ROOT.path_join("data"))
	_expect(make_dir_error == OK, "ModLoader smoke should create temporary mod data directory")
	if make_dir_error != OK:
		return

	var manifest: Dictionary = {
		"schema_version": 1,
		"id": "l1_smoke_mod",
		"name": "L1 Smoke Mod",
		"version": "0.0.1",
		"enabled": true,
		"load_order": 0,
		"contract_extensions": {
			"content_tags": ["mod_l1_smoke_mod_tag"],
			"locale_prefixes": ["mod_l1_smoke_mod_"],
		},
		"data_patches": [
			{
				"type": "json_array_append",
				"target": "relics.json",
				"path": "data/relics_patch.json",
				"array_key": "relics",
			},
			{
				"type": "csv_append",
				"target": "strings.csv",
				"path": "data/strings_patch.csv",
			},
		],
	}
	var relic_patch: Dictionary = {
		"relics": [
			{
				"id": "relic_l1_smoke_mod",
				"name_key": "mod_l1_smoke_mod_relic_name",
				"desc_key": "mod_l1_smoke_mod_relic_desc",
				"default_unlocked": true,
				"tags": ["tag_relic", "mod_l1_smoke_mod_tag"],
				"modifiers": [
					{"stat": "damage", "type": "add", "value": 0.1},
				],
				"behaviors": [],
			},
		],
	}
	_write_text(MOD_SMOKE_ROOT.path_join("mod.json"), JSON.stringify(manifest, "\t"))
	_write_text(MOD_SMOKE_ROOT.path_join("data/relics_patch.json"), JSON.stringify(relic_patch, "\t"))
	_write_text(
		MOD_SMOKE_ROOT.path_join("data/strings_patch.csv"),
		"keys,zh_CN,en\nmod_l1_smoke_mod_relic_name,Smoke Relic,Smoke Relic\nmod_l1_smoke_mod_relic_desc,Smoke Relic Desc,Smoke Relic Desc\n"
	)

	ModLoader.reload_mods()
	_expect(ModLoader.enabled_mod_count() >= 1, "ModLoader should enable the temporary smoke mod")
	_expect(DataLoader.has_contract_value("content_tags", "mod_l1_smoke_mod_tag"), "DataLoader should include mod contract extensions")
	_expect(DataLoader.has_contract_value("locale_prefixes", "mod_l1_smoke_mod_"), "DataLoader should include mod locale prefix extensions")
	var relics_payload: Variant = DataLoader.load_json(DataLoader.RELICS_PATH)
	var found_relic: bool = false
	if relics_payload is Dictionary:
		for relic: Variant in (relics_payload as Dictionary).get("relics", []):
			if relic is Dictionary and String((relic as Dictionary).get("id", "")) == "relic_l1_smoke_mod":
				found_relic = true
				break
	_expect(found_relic, "DataLoader should expose mod JSON array append entries")
	var found_locale_key: bool = false
	for row: Dictionary in DataLoader.load_csv(DataLoader.LOCALE_STRINGS_PATH):
		if String(row.get("keys", "")) == "mod_l1_smoke_mod_relic_name":
			found_locale_key = true
			break
	_expect(found_locale_key, "DataLoader should expose mod CSV append entries")
	_expect(DataLoader.validate_project_data(), "DataLoader should validate merged mod data")

	_remove_l1_mod()
	ModLoader.reload_mods()


func _expect_platform_services_reserved_interface() -> void:
	PlatformServices.reload_backend()
	_expect(PlatformServices.preferred_provider() == PlatformServices.PROVIDER_STEAM, "PlatformServices should reserve Steam as the preferred provider")
	_expect(PlatformServices.active_provider() == PlatformServices.PROVIDER_NONE, "PlatformServices should stay on the none provider until a platform adapter is connected")
	_expect(not PlatformServices.is_available(), "PlatformServices should report unavailable without a platform adapter")
	_expect(not PlatformServices.supports(PlatformServices.CAP_ACHIEVEMENTS), "PlatformServices should not claim achievements before Steam is connected")
	_expect(not PlatformServices.supports(PlatformServices.CAP_LOBBIES), "PlatformServices should not claim lobbies before Steam is connected")
	_expect(not PlatformServices.unlock_achievement("achievement_l1_smoke"), "PlatformServices should safely reject achievement unlocks without a backend")
	_expect(PlatformServices.achievement_requests().size() >= 1, "PlatformServices should record achievement requests for diagnostics")
	_expect(not PlatformServices.set_rich_presence("status", "l1_smoke"), "PlatformServices should store rich presence locally but not send it without a backend")
	_expect(String(PlatformServices.rich_presence().get("status", "")) == "l1_smoke", "PlatformServices should keep desired rich presence locally")
	_expect(not PlatformServices.show_overlay("friends"), "PlatformServices should safely reject overlay requests without a backend")
	_expect(not PlatformServices.create_lobby(4, {"mode": "l1_smoke"}), "PlatformServices should safely reject lobby creation without a backend")
	_expect(PlatformServices.multiplayer_requests().size() >= 1, "PlatformServices should record multiplayer requests for diagnostics")
	PlatformServices.clear_all_rich_presence()


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("L1 smoke failed to write %s" % path)
		push_error("[L1Smoke] failed to write %s" % path)
		return
	file.store_string(text)


func _remove_l1_mod() -> void:
	DirAccess.remove_absolute(MOD_SMOKE_ROOT.path_join("data/strings_patch.csv"))
	DirAccess.remove_absolute(MOD_SMOKE_ROOT.path_join("data/relics_patch.json"))
	DirAccess.remove_absolute(MOD_SMOKE_ROOT.path_join("data"))
	DirAccess.remove_absolute(MOD_SMOKE_ROOT.path_join("mod.json"))
	DirAccess.remove_absolute(MOD_SMOKE_ROOT)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[L1Smoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[L1Smoke] passed")
		get_tree().quit(0)
		return

	print("[L1Smoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
