extends Node


const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const ABILITY_TAGS := preload("res://scripts/contracts/ability_tags.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const ENEMY_SCENE := preload("res://scenes/gameplay/enemy.tscn")
const PLAYER_SCENE := preload("res://scenes/gameplay/player.tscn")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SKILL_EFFECTS := preload("res://scripts/contracts/skill_effects.gd")
const SKILL_IDS := preload("res://scripts/contracts/skill_ids.gd")
const SKILL_RESOURCES := preload("res://scripts/contracts/skill_resources.gd")
const SKILL_SYSTEM_SCRIPT := preload("res://scripts/gameplay/skill_system.gd")
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
	await _expect_game_clock_pause_freezes()
	_expect_game_state_rejects_unknown()
	_expect_save_manager_roundtrip()
	_expect_combat_damage_path()
	await _expect_skill_system_aoe_damage()
	await _expect_entity_status_components()
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
		DAMAGE_TYPES.PHYSICAL,
		self,
		target,
		"team_player",
		"team_enemy"
	)
	var result: Dictionary = Combat.apply_damage(target, info)
	_expect(bool(result.get("applied", false)), "Combat should apply registered physical damage")
	_expect(is_equal_approx(target.life, 2.0), "Combat should route damage through receive_damage")
	target.queue_free()


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
	var skill_system: Node = SKILL_SYSTEM_SCRIPT.new()
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
	var mana: Dictionary = resource_snapshot[SKILL_RESOURCES.MANA] as Dictionary
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

	var skill_system: Node = SKILL_SYSTEM_SCRIPT.new()
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

	var skill_system: Node = SKILL_SYSTEM_SCRIPT.new()
	skill_system.name = "L1PoisonSkillSystem"
	add_child(skill_system)
	skill_system.call("configure", player, world, [_l1_poison_dot_skill()], [_l1_mana_resource()])

	var dot_events: Array[Dictionary] = []
	var dot_event_sink: Callable = func(target: Node, info: RefCounted, result: Dictionary) -> void:
		var flags: PackedStringArray = info.get("flags")
		if target != enemy or not flags.has(DOT_DAMAGE_FLAG):
			return
		dot_events.append({
			"damage_type": String(info.get("damage_type")),
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
		_expect(String(first_event.get("damage_type", "")) == DAMAGE_TYPES.POISON, "Poison DoT should use poison damage type")
		_expect(String(first_event.get("source_team", "")) == TEAM_PLAYER, "Poison DoT should preserve player source team")
		_expect(String(first_event.get("target_team", "")) == TEAM_ENEMY, "Poison DoT should preserve enemy target team")
		_expect(bool(first_event.get("applied", false)), "Poison DoT Combat result should apply")

	var poison_snapshot: Dictionary = enemy.call("snapshot")
	var poison_effects: Array = (poison_snapshot.get("status_effects", {}) as Dictionary).get("effects", []) as Array
	_expect(not poison_effects.is_empty(), "Poison should enter Enemy status snapshots")
	if not poison_effects.is_empty():
		var poison_effect: Dictionary = poison_effects[0] as Dictionary
		_expect(String(poison_effect.get("damage_type", "")) == DAMAGE_TYPES.POISON, "Poison snapshot should preserve damage_type")
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


func _l1_damage_skill() -> Dictionary:
	return {
		"id": SKILL_IDS.SKILL_OVERDRIVE_ROUNDS,
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
			{"resource": SKILL_RESOURCES.MANA, "amount": 25.0},
		],
		"targeting": {
			"type": SKILL_TARGETING.AOE_ENEMIES_AROUND_CASTER,
			"radius": 120.0,
			"max_targets": 0,
		},
		"effects": [
			{
				"effect": SKILL_EFFECTS.SKILL_EFFECT_DAMAGE,
				"params": {"amount": 4.0, "damage_type": DAMAGE_TYPES.PHYSICAL},
			},
		],
	}


func _l1_self_silence_skill() -> Dictionary:
	return {
		"id": SKILL_IDS.SKILL_OVERDRIVE_ROUNDS,
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
		"id": SKILL_IDS.SKILL_OVERDRIVE_ROUNDS,
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
					"damage_type": DAMAGE_TYPES.POISON,
				},
			},
		],
	}


func _l1_enemy_silence_skill() -> Dictionary:
	return {
		"id": SKILL_IDS.SKILL_OVERDRIVE_ROUNDS,
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
		"id": SKILL_RESOURCES.MANA,
		"max": 100.0,
		"start": 100.0,
		"regen_per_second": 0.0,
	}


func _l1_player_stats() -> Dictionary:
	return {
		STATS.MAX_HP: 10.0,
		STATS.MOVE_SPEED: 0.0,
		STATS.DAMAGE_INVULNERABILITY_DURATION: 0.0,
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
		"contact_damage_type": DAMAGE_TYPES.PHYSICAL,
		"exp_reward": 0,
		"hit_radius": 10.0,
		"separation_radius": 0.0,
		"visual_color": "#ff6152",
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
