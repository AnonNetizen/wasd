extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const AMMO_PICKUP_SCENE := preload(
	"res://scenes/gameplay/ammo_magazine_pickup.tscn"
)
const WEAPON_SYSTEM_SCRIPT := preload(
	"res://scripts/gameplay/weapon_system.gd"
)

const BULLET_POOL_ID: String = "bullet_basic"
const AMMO_POOL_ID: String = "ammo_magazine"

var _failures: Array[String] = []
var _test_bullets: Array[TestBullet] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	GameState.change_state(GameState.PLAYING, {"source": "ammo_weapon_smoke"})
	GameClock.reset()
	InputService.set_playback_active(true)
	PoolManager.clear_all()

	_expect(
		PoolManager.register_pool(
			BULLET_POOL_ID,
			_create_test_bullet,
			3
		),
		"bullet test pool should register"
	)
	_expect(
		PoolManager.register_pool(
			AMMO_POOL_ID,
			_create_ammo_pickup,
			2
		),
		"ammo pickup test pool should register"
	)

	var player := TestPlayer.new()
	get_tree().root.add_child(player)
	var active_world := Node2D.new()
	get_tree().root.add_child(active_world)
	var weapon: WeaponSystem = WEAPON_SYSTEM_SCRIPT.new() as WeaponSystem
	player.add_child(weapon)
	var weapon_data: Dictionary = _load_weapon_data()
	weapon_data["base_stats"]["bullet_count"] = 3
	weapon.configure(player, active_world, weapon_data)

	_expect_initial_state(weapon)
	_expect_failed_pool_has_no_side_effects(weapon)
	_expect_trigger_spends_one_round(weapon)
	_expect_empty_magazine_requires_new_edge(weapon)
	_expect_reload_snapshot_roundtrip(
		weapon,
		player,
		active_world,
		weapon_data
	)
	_expect_refill_does_not_bypass_trigger_latch(weapon)
	_expect_depleted_fire(weapon)
	_expect_ammo_add_and_pickup(weapon, player)

	InputService.set_playback_active(false)
	PoolManager.clear_all()
	GameState.change_state(GameState.MAIN_MENU, {"source": "ammo_weapon_smoke"})
	player.queue_free()
	active_world.queue_free()
	if _failures.is_empty():
		print("AMMO WEAPON SMOKE ALL PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[ammo-weapon-smoke] %s" % failure)
	get_tree().quit(1)


func _expect_initial_state(weapon: WeaponSystem) -> void:
	var state: Dictionary = weapon.ammo_state()
	_expect(int(state.get("magazine", -1)) == 30, "magazine size should come from weapon data")
	_expect(int(state.get("reserve", -1)) == 150, "starting reserve should come from weapon data")
	_expect(int(state.get("total_capacity", -1)) == 240, "total capacity should come from weapon data")
	_expect(
		is_equal_approx(float(state.get("reload_duration", -1.0)), 1.2),
		"reload duration should come from weapon data"
	)


func _expect_failed_pool_has_no_side_effects(weapon: WeaponSystem) -> void:
	var blockers: Array[Node] = []
	for _index: int in range(3):
		blockers.append(PoolManager.acquire(BULLET_POOL_ID))
	var ammo_before: Dictionary = weapon.ammo_state()
	var combat_before: Dictionary = _combat_rng_snapshot()
	var fired_contexts: Array[Dictionary] = []
	var observer: Callable = func(_context: Dictionary) -> void:
		fired_contexts.append(_context.duplicate(true))
	weapon.weapon_fired.connect(observer)
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	weapon._process(0.016)
	_expect(weapon.ammo_state() == ammo_before, "failed acquisition must not spend ammo")
	_expect(_combat_rng_snapshot() == combat_before, "failed acquisition must not consume combat RNG")
	_expect(fired_contexts.is_empty(), "failed acquisition must not emit weapon_fired")
	weapon.weapon_fired.disconnect(observer)
	for blocker: Node in blockers:
		PoolManager.release(blocker)


func _expect_trigger_spends_one_round(weapon: WeaponSystem) -> void:
	var fired_contexts: Array[Dictionary] = []
	var observer: Callable = func(context: Dictionary) -> void:
		fired_contexts.append(context.duplicate(true))
	weapon.weapon_fired.connect(observer)
	weapon._process(0.016)
	_expect(
		int(weapon.ammo_state().get("magazine", -1)) == 29,
		"one trigger should spend one round regardless of bullet_count"
	)
	_expect(
		fired_contexts.size() == 1
		and int(fired_contexts[0].get("bullet_count", 0)) == 3,
		"one trigger should emit one context for all acquired bullets"
	)
	weapon.weapon_fired.disconnect(observer)
	_release_active_test_bullets()


func _expect_empty_magazine_requires_new_edge(weapon: WeaponSystem) -> void:
	var attention_requests: Array[int] = []
	var attention_observer: Callable = func(reserve_remaining: int) -> void:
		attention_requests.append(reserve_remaining)
	weapon.ammo_attention_requested.connect(attention_observer)
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	weapon._process(0.016)
	weapon.restore_snapshot({
		"magazine_ammo": 1,
		"reserve_ammo": 2,
		"cooldown_remaining": 0.0,
	})
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	weapon._process(0.016)
	_release_active_test_bullets()
	weapon._process(1.0)
	var held_empty_state: Dictionary = weapon.ammo_state()
	_expect(
		int(held_empty_state.get("magazine", -1)) == 0
		and int(held_empty_state.get("reserve", -1)) == 2,
		"held fire should not spend reserve ammo"
	)
	_expect(
		not bool(held_empty_state.get("is_reloading", true)),
		"held fire after emptying should not auto-reload"
	)
	_expect(
		attention_requests == [2],
		"emptying the magazine should request one world prompt without held-fire spam"
	)
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	weapon._process(0.016)
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	weapon._process(0.016)
	var reload_state: Dictionary = weapon.ammo_state()
	_expect(bool(reload_state.get("is_reloading", false)), "fresh fire edge should start reload")
	var remaining_before: float = float(reload_state.get("reload_remaining", 0.0))
	InputService.inject_playback_value(ACTIONS.RELOAD, true)
	weapon._process(0.2)
	var remaining_after: float = float(weapon.ammo_state().get("reload_remaining", 0.0))
	_expect(
		remaining_after < remaining_before and remaining_after > 0.0,
		"reload and fire input must not interrupt or restart an active reload"
	)
	weapon._process(1.0)
	var completed_state: Dictionary = weapon.ammo_state()
	_expect(
		int(completed_state.get("magazine", -1)) == 2
		and int(completed_state.get("reserve", -1)) == 0,
		"reload should transfer only available reserve rounds"
	)
	InputService.inject_playback_value(ACTIONS.RELOAD, false)
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	weapon._process(0.016)
	weapon.ammo_attention_requested.disconnect(attention_observer)


func _expect_reload_snapshot_roundtrip(
	weapon: WeaponSystem,
	player: TestPlayer,
	active_world: Node2D,
	weapon_data: Dictionary
) -> void:
	weapon.restore_snapshot({
		"magazine_ammo": 10,
		"reserve_ammo": 20,
		"cooldown_remaining": 0.0,
	})
	_expect(weapon.request_reload(), "manual reload should start with a partial magazine")
	weapon._process(0.2)
	var reload_snapshot: Dictionary = weapon.snapshot()
	var restored_weapon: WeaponSystem = WEAPON_SYSTEM_SCRIPT.new() as WeaponSystem
	player.add_child(restored_weapon)
	restored_weapon.configure(player, active_world, weapon_data)
	restored_weapon.restore_snapshot(reload_snapshot)
	var restored_state: Dictionary = restored_weapon.ammo_state()
	_expect(
		int(restored_state.get("magazine", -1)) == 10
		and int(restored_state.get("reserve", -1)) == 20,
		"snapshot should restore magazine and reserve"
	)
	_expect(
		bool(restored_state.get("is_reloading", false))
		and is_equal_approx(
			float(restored_state.get("reload_remaining", 0.0)),
			1.0
		),
		"snapshot should restore active reload time"
	)
	restored_weapon.queue_free()
	weapon.restore_snapshot({
		"magazine_ammo": 0,
		"reserve_ammo": 0,
		"cooldown_remaining": 0.0,
	})


func _expect_depleted_fire(weapon: WeaponSystem) -> void:
	var fired_contexts: Array[Dictionary] = []
	var attention_requests: Array[int] = []
	var observer: Callable = func(context: Dictionary) -> void:
		fired_contexts.append(context.duplicate(true))
	var attention_observer: Callable = func(reserve_remaining: int) -> void:
		attention_requests.append(reserve_remaining)
	weapon.weapon_fired.connect(observer)
	weapon.ammo_attention_requested.connect(attention_observer)
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	weapon._process(0.016)
	var state: Dictionary = weapon.ammo_state()
	_expect(
		bool(state.get("is_depleted", false)),
		"total zero should be exposed as depleted for HUD warning"
	)
	_expect(
		bool(state.get("depleted_fire_armed", false)),
		"fresh fire at total zero should arm depleted fire"
	)
	_expect(
		attention_requests == [0],
		"fresh fire at total zero should request one depleted world prompt"
	)
	_expect(int(state.get("total", -1)) == 0, "depleted fire should use infinite fallback ammo")
	_expect(
		is_equal_approx(weapon.stat_value("fire_rate"), 1.25),
		"depleted fire rate should apply the data multiplier"
	)
	_expect(
		is_equal_approx(weapon.stat_value("bullet_speed"), 260.0),
		"depleted bullet speed should apply the data multiplier"
	)
	_expect(fired_contexts.size() == 1, "fresh depleted fire should emit one weapon_fired context")
	for bullet: TestBullet in _test_bullets:
		if not bullet.active:
			continue
		_expect(
			is_equal_approx(float(bullet.configured_stats.get("bullet_speed", 0.0)), 260.0),
			"depleted bullets should receive reduced speed"
		)
		_expect(
			is_equal_approx(float(bullet.configured_projectile.get("lifetime", 0.0)), 2.5),
			"depleted bullet lifetime should compensate to preserve range"
		)
	weapon.weapon_fired.disconnect(observer)
	weapon.ammo_attention_requested.disconnect(attention_observer)
	_release_active_test_bullets()


func _expect_ammo_add_and_pickup(weapon: WeaponSystem, player: TestPlayer) -> void:
	_expect(weapon.add_ammo(40) == 40, "adding ammo at total zero should accept the requested amount")
	var zero_refill_state: Dictionary = weapon.ammo_state()
	_expect(
		int(zero_refill_state.get("magazine", -1)) == 30
		and int(zero_refill_state.get("reserve", -1)) == 10,
		"refill from total zero should fill the magazine before reserve"
	)
	weapon._process(1.0)
	_expect(
		int(weapon.ammo_state().get("magazine", -1)) == 29,
		"pickup after armed depleted fire should transition held fire back to normal ammo"
	)
	_release_active_test_bullets()
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	weapon._process(0.016)
	weapon.restore_snapshot({
		"magazine_ammo": 0,
		"reserve_ammo": 10,
		"cooldown_remaining": 0.0,
	})
	_expect(
		weapon.add_ammo(30) == 30,
		"pickup should accept one magazine when reserve ammo already exists"
	)
	var empty_magazine_refill_state: Dictionary = weapon.ammo_state()
	_expect(
		int(empty_magazine_refill_state.get("magazine", -1)) == 30
		and int(empty_magazine_refill_state.get("reserve", -1)) == 10,
		"pickup should fill an empty magazine before adding to an existing reserve"
	)
	_expect(weapon.add_ammo(1000) == 200, "ammo add should clamp to total capacity")
	_expect(not weapon.can_accept_ammo(), "full ammo capacity should reject pickups")

	weapon.restore_snapshot({
		"magazine_ammo": 30,
		"reserve_ammo": 200,
		"cooldown_remaining": 0.0,
	})
	var pickup: AmmoMagazinePickup = PoolManager.acquire(AMMO_POOL_ID) as AmmoMagazinePickup
	var collected_amounts: Array[int] = []
	pickup.collected.connect(func(amount: int) -> void: collected_amounts.append(amount))
	pickup.global_position = player.global_position
	pickup.configure(50, player, weapon, 240.0)
	pickup._physics_process(0.016)
	_expect(
		collected_amounts == [10],
		"pickup should report only the capacity-clamped amount"
	)
	_expect(int(weapon.ammo_state().get("total", -1)) == 240, "pickup should clamp total ammo at capacity")
	_expect(PoolManager.active_count(AMMO_POOL_ID) == 0, "collected pickup should return to its pool")

	var full_pickup: AmmoMagazinePickup = PoolManager.acquire(AMMO_POOL_ID) as AmmoMagazinePickup
	var origin := Vector2(32.0, 0.0)
	full_pickup.global_position = origin
	full_pickup.configure(50, player, weapon, 240.0)
	full_pickup._physics_process(0.016)
	_expect(
		full_pickup.global_position == origin,
		"pickup should not attract while ammo capacity is full"
	)
	PoolManager.release(full_pickup)
	var reset_pickup: AmmoMagazinePickup = PoolManager.acquire(AMMO_POOL_ID) as AmmoMagazinePickup
	_expect(
		int(reset_pickup.snapshot().get("amount", -1)) == 0
		and is_equal_approx(float(reset_pickup.snapshot().get("pickup_speed", -1.0)), 0.0)
		and reset_pickup.get("_target") == null
		and reset_pickup.get("_weapon_receiver") == null,
		"pooled pickup should completely reset transient collection state"
	)
	PoolManager.release(reset_pickup)


func _expect_refill_does_not_bypass_trigger_latch(weapon: WeaponSystem) -> void:
	weapon.restore_snapshot({
		"magazine_ammo": 1,
		"reserve_ammo": 0,
		"cooldown_remaining": 0.0,
	})
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	weapon._process(0.016)
	_release_active_test_bullets()
	_expect(int(weapon.ammo_state().get("total", -1)) == 0, "last normal round should deplete total ammo")
	_expect(weapon.add_ammo(40) == 40, "pickup should refill an empty weapon")
	weapon._process(1.0)
	_expect(
		int(weapon.ammo_state().get("magazine", -1)) == 30,
		"refill while fire remains held must not bypass the empty-trigger latch"
	)
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	weapon._process(0.016)
	InputService.inject_playback_value(ACTIONS.FIRE, true)
	weapon._process(0.016)
	_expect(
		int(weapon.ammo_state().get("magazine", -1)) == 29,
		"release and fresh fire should clear the empty-trigger latch"
	)
	_release_active_test_bullets()
	InputService.inject_playback_value(ACTIONS.FIRE, false)
	weapon._process(0.016)
	weapon.restore_snapshot({
		"magazine_ammo": 0,
		"reserve_ammo": 0,
		"cooldown_remaining": 0.0,
		"depleted_mode": true,
	})
	_expect(
		not bool(weapon.ammo_state().get("depleted_fire_armed", true)),
		"restore at total zero must require a new fire edge"
	)


func _load_weapon_data() -> Dictionary:
	var raw_data: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/weapons.json")
	)
	if not raw_data is Dictionary:
		_expect(false, "weapons.json should parse")
		return {}
	var weapons: Array = (raw_data as Dictionary).get("weapons", []) as Array
	if weapons.is_empty() or not weapons[0] is Dictionary:
		_expect(false, "weapons.json should contain a weapon")
		return {}
	return (weapons[0] as Dictionary).duplicate(true)


func _create_test_bullet() -> Node:
	var bullet := TestBullet.new()
	_test_bullets.append(bullet)
	return bullet


func _create_ammo_pickup() -> Node:
	return AMMO_PICKUP_SCENE.instantiate()


func _release_active_test_bullets() -> void:
	for bullet: TestBullet in _test_bullets:
		if bullet.active:
			PoolManager.release(bullet)


func _combat_rng_snapshot() -> Dictionary:
	var streams: Dictionary = RNG.snapshot().get("streams", {})
	return (streams.get("combat", {}) as Dictionary).duplicate(true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


class TestPlayer:
	extends Node2D

	var aim_direction: Vector2 = Vector2.RIGHT

	func pickup_range() -> float:
		return 100.0


class TestBullet:
	extends Node2D

	var active: bool = false
	var configured_projectile: Dictionary = {}
	var configured_stats: Dictionary = {}

	func configure(
		stats: Dictionary,
		projectile: Dictionary,
		_direction: Vector2,
		_source: Node
	) -> void:
		active = true
		configured_stats = stats.duplicate(true)
		configured_projectile = projectile.duplicate(true)

	func _pool_reset() -> void:
		active = false
		configured_stats.clear()
		configured_projectile.clear()

	func _pool_release() -> void:
		active = false
