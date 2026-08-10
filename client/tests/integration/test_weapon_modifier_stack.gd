extends SmokeHarness


const STATS := preload("res://scripts/contracts/stats.gd")
const WEAPON_SYSTEM_SCRIPT := preload("res://scripts/gameplay/weapon_system.gd")
const WEAPON_SNAPSHOT_KEYS: Array[String] = [
	"cooldown_remaining",
	"stat_additions",
	"stat_multipliers",
	"temporary_modifiers",
]

var _previous_game_state: StringName = &""
var _previous_game_context: Dictionary = {}


func before_each() -> void:
	super()
	_previous_game_state = GameState.current()
	_previous_game_context = GameState.context()
	GameState.change_state(GameState.PLAYING)


func after_each() -> void:
	GameState.change_state(_previous_game_state, _previous_game_context)
	super()


func test_weapon_combines_three_layers_and_preserves_materialized_keys() -> void:
	var weapon: WeaponSystemProbe = _new_weapon({
		STATS.DAMAGE: 10.0,
		"legacy_missing_value": 2.0,
	})
	weapon.apply_modifiers([
		{"stat": STATS.DAMAGE, "type": "add", "value": 2.0},
		{"stat": STATS.DAMAGE, "type": "mult", "value": 2.0},
		{"stat": "flat_bonus", "type": "add", "value": 5.0},
		{"stat": "scaling_only", "type": "mult", "value": 3.0},
	])
	weapon.set_gear_modifiers([
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.2},
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.2},
	])
	weapon.apply_temporary_modifiers([
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.5},
		{"stat": "legacy_missing_value", "type": "mult"},
	], 5.0, "overdrive")

	assert_almost_eq(weapon.stat_value(STATS.DAMAGE), 51.84, 0.000_001)
	assert_almost_eq(weapon.stat_value("flat_bonus"), 5.0, 0.000_001)
	assert_almost_eq(weapon.stat_value("scaling_only"), 0.0, 0.000_001)
	assert_almost_eq(weapon.stat_value("legacy_missing_value"), 0.0, 0.0)
	var effective_stats: Dictionary = weapon.effective_stats_for_test()
	var actual_keys: Array = effective_stats.keys()
	actual_keys.sort()
	assert_eq(actual_keys, [STATS.DAMAGE, "flat_bonus", "legacy_missing_value"])


func test_temporary_sources_keep_order_and_emit_lifecycle_signals() -> void:
	var weapon: WeaponSystemProbe = _new_weapon({STATS.FIRE_RATE: 1.0})
	var started: Array[Dictionary] = []
	var refreshed: Array[Dictionary] = []
	var expired: Array[Dictionary] = []
	weapon.temporary_modifier_started.connect(
		func(snapshot_data: Dictionary) -> void:
			started.append(snapshot_data)
	)
	weapon.temporary_modifier_refreshed.connect(
		func(snapshot_data: Dictionary) -> void:
			refreshed.append(snapshot_data)
	)
	weapon.temporary_modifier_expired.connect(
		func(snapshot_data: Dictionary) -> void:
			expired.append(snapshot_data)
	)
	var legacy_modifiers: Array[Dictionary] = [
		{"stat": STATS.FIRE_RATE, "type": "add", "value": 1.0},
	]
	weapon.apply_temporary_modifiers(legacy_modifiers, 2.0)
	var legacy_source_id: String = String(
		weapon.active_temporary_modifiers()[0].get("source_id", "")
	)
	weapon.apply_temporary_modifiers([
		{"stat": STATS.FIRE_RATE, "type": "mult", "value": 2.0},
	], 3.0, "second")
	weapon.apply_temporary_modifiers(legacy_modifiers, 4.0)

	assert_true(legacy_source_id.begins_with("legacy:"))
	assert_eq(started.size(), 2)
	assert_eq(refreshed.size(), 1)
	assert_eq(String(refreshed[0].get("source_id", "")), legacy_source_id)
	var active: Array[Dictionary] = weapon.active_temporary_modifiers()
	assert_eq(String(active[0].get("source_id", "")), legacy_source_id)
	assert_eq(String(active[1].get("source_id", "")), "second")
	assert_almost_eq(weapon.stat_value(STATS.FIRE_RATE), 4.0, 0.000_001)

	weapon._process(3.5)
	assert_eq(expired.size(), 1)
	assert_eq(String(expired[0].get("source_id", "")), "second")
	assert_almost_eq(weapon.stat_value(STATS.FIRE_RATE), 2.0, 0.000_001)
	weapon._process(0.5)
	assert_eq(expired.size(), 2)
	assert_eq(String(expired[1].get("source_id", "")), legacy_source_id)
	assert_almost_eq(weapon.stat_value(STATS.FIRE_RATE), 1.0, 0.000_001)


func test_snapshot_restore_preserves_wire_signals_and_excludes_gear() -> void:
	var source: WeaponSystemProbe = _new_weapon({STATS.DAMAGE: 10.0})
	source.apply_modifiers([
		{"stat": STATS.DAMAGE, "type": "add", "value": 2.0},
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.5},
	])
	source.set_gear_modifiers([
		{"stat": STATS.DAMAGE, "type": "mult", "value": 2.0},
	])
	source.apply_temporary_modifiers([
		{"stat": STATS.DAMAGE, "type": "add", "value": 3.0},
	], 6.0, "first")
	source.apply_temporary_modifiers([
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.25},
	], 8.0, "second")
	var snapshot_data: Dictionary = source.snapshot()
	var actual_keys: Array = snapshot_data.keys()
	assert_eq(actual_keys, WEAPON_SNAPSHOT_KEYS)
	assert_false(snapshot_data.has("gear"))
	assert_false(snapshot_data.has("modifier_stack"))
	(snapshot_data["temporary_modifiers"] as Array)[0]["source_id"] = ""
	snapshot_data["cooldown_remaining"] = 0.75

	var restored: WeaponSystemProbe = _new_weapon({STATS.DAMAGE: 10.0})
	var restore_events: Array[Array] = []
	restored.temporary_modifiers_restored.connect(
		func(active: Array[Dictionary]) -> void:
			restore_events.append(active)
	)
	restored.restore_snapshot(snapshot_data)

	assert_eq(restore_events.size(), 1)
	var restored_temporary: Array[Dictionary] = restored.active_temporary_modifiers()
	assert_eq(restore_events[0], restored_temporary)
	assert_true(
		String(restored_temporary[0].get("source_id", "")).begins_with(
			"legacy:"
		)
	)
	assert_eq(String(restored_temporary[1].get("source_id", "")), "second")
	assert_almost_eq(restored.stat_value(STATS.DAMAGE), 28.125, 0.000_001)
	assert_almost_eq(
		float(restored.snapshot().get("cooldown_remaining", 0.0)),
		0.75,
		0.0
	)

	restored.set_gear_modifiers([
		{"stat": STATS.DAMAGE, "type": "mult", "value": 2.0},
	])
	assert_almost_eq(restored.stat_value(STATS.DAMAGE), 56.25, 0.000_001)


func _new_weapon(base_stats: Dictionary) -> WeaponSystemProbe:
	var player := Node2D.new()
	add_child_autofree(player)
	var active_parent := Node2D.new()
	add_child_autofree(active_parent)
	var weapon := WeaponSystemProbe.new()
	add_child_autofree(weapon)
	weapon.configure(
		player,
		active_parent,
		{
			"base_stats": base_stats,
			"projectile": {},
		}
	)
	return weapon


class WeaponSystemProbe:
	extends WeaponSystem


	func effective_stats_for_test() -> Dictionary:
		return _effective_runtime_stats()
