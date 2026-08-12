extends Node


const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const CLOCK_FRAMES: int = 4
const L1_SLOT: String = "slot_l1_smoke"

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame

	_expect_rng_contract()
	await _expect_game_clock_and_state_contract()
	_expect_save_manager_roundtrip()
	_expect_combat_damage_path()
	_expect_platform_services_reserved_interface()

	SaveManager.delete(L1_SLOT, SAVE_KINDS.RUN)
	GameState.change_state(GameState.MAIN_MENU, {"source": "l1_smoke"})
	_finish()


func _expect_rng_contract() -> void:
	RNG.set_run_seed(13_579)
	var first_spawn_roll: int = RNG.spawn.randi()
	var first_choice_roll: float = RNG.ui_choice.randf()
	RNG.set_run_seed(13_579)
	_expect(
		RNG.spawn.randi() == first_spawn_roll,
		"RNG.spawn should repeat with the same run seed"
	)
	_expect(
		is_equal_approx(RNG.ui_choice.randf(), first_choice_roll),
		"RNG.ui_choice should repeat with the same run seed"
	)

	RNG.set_run_seed(24_680)
	var snapshot: Dictionary = RNG.snapshot()
	var expected_roll: int = RNG.combat.randi()
	RNG.combat.randi()
	RNG.restore_snapshot(snapshot)
	_expect(
		RNG.combat.randi() == expected_roll,
		"RNG snapshot should restore stream state"
	)


func _expect_game_clock_and_state_contract() -> void:
	GameClock.reset()
	GameState.change_state(GameState.PLAYING, {"source": "l1_smoke"})
	for _index: int in range(CLOCK_FRAMES):
		await get_tree().physics_frame
	_expect(GameClock.tick() > 0, "GameClock tick should advance in PLAYING")

	var before_state: StringName = GameState.current()
	_expect(
		not GameState.can_change_to(&"unknown_state_for_l1"),
		"GameState should reject unknown states"
	)
	_expect(
		GameState.current() == before_state,
		"GameState should keep current state after unknown transition"
	)

	GameState.change_state(GameState.PAUSED, {"source": "l1_smoke"})
	var paused_tick: int = GameClock.tick()
	var paused_time: float = GameClock.now()
	for _index: int in range(CLOCK_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame
	_expect(GameClock.tick() == paused_tick, "GameClock tick should freeze in PAUSED")
	_expect(
		is_equal_approx(GameClock.now(), paused_time),
		"GameClock time should freeze in PAUSED"
	)
	GameState.change_state(GameState.PLAYING, {"source": "l1_smoke"})


func _expect_save_manager_roundtrip() -> void:
	SaveManager.delete(L1_SLOT, SAVE_KINDS.RUN)
	var payload: Dictionary = {
		"schema_version": 8,
		"gold_progression": {
			"gold_balance": 100,
			"gold_earned_total": 100,
		},
		"game_clock": GameClock.snapshot(),
		"rng": RNG.snapshot(),
		"spawn_states": {},
		"player": {},
		"weapon": {},
		"enemies": [],
		"bullets": [],
		"gold_orbs": [],
		"reward_choice": {},
	}
	_expect(
		SaveManager.save(L1_SLOT, SAVE_KINDS.RUN, payload),
		"SaveManager should write a smoke run payload"
	)
	var loaded: Dictionary = SaveManager.load(L1_SLOT, SAVE_KINDS.RUN)
	var loaded_gold: Dictionary = loaded.get("gold_progression", {}) as Dictionary
	_expect(
		int(loaded_gold.get("gold_earned_total", 0)) == 100,
		"SaveManager should roundtrip a smoke run payload"
	)
	_expect(
		loaded.get("rng", {}) is Dictionary,
		"SaveManager should preserve RNG snapshot dictionaries"
	)


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
	_expect(
		bool(result.get("applied", false)),
		"Combat should apply registered physical damage"
	)
	_expect(
		is_equal_approx(target.life, 2.0),
		"Combat should route damage through receive_damage"
	)
	target.queue_free()


func _expect_platform_services_reserved_interface() -> void:
	PlatformServices.reload_backend()
	_expect(
		PlatformServices.preferred_provider() == PlatformServices.PROVIDER_STEAM,
		"PlatformServices should reserve Steam as the preferred provider"
	)
	_expect(
		PlatformServices.active_provider() == PlatformServices.PROVIDER_NONE,
		"PlatformServices should stay on the none provider without an adapter"
	)
	_expect(
		not PlatformServices.is_available(),
		"PlatformServices should report unavailable without an adapter"
	)
	_expect(
		not PlatformServices.supports(PlatformServices.CAP_ACHIEVEMENTS),
		"PlatformServices should not claim achievements before Steam is connected"
	)
	_expect(
		not PlatformServices.unlock_achievement("achievement_l1_smoke"),
		"PlatformServices should reject achievement unlocks without a backend"
	)
	_expect(
		not PlatformServices.set_rich_presence("status", "l1_smoke"),
		"PlatformServices should not send rich presence without a backend"
	)
	_expect(
		String(PlatformServices.rich_presence().get("status", "")) == "l1_smoke",
		"PlatformServices should retain desired rich presence locally"
	)
	PlatformServices.clear_all_rich_presence()


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
