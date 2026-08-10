extends SmokeHarness


const MODIFIER_STACK_SCRIPT := preload("res://scripts/data/modifier_stack.gd")
const PLAYER_SCENE := preload("res://scenes/gameplay/actors/player_base.tscn")
const STATS := preload("res://scripts/contracts/stats.gd")
const PLAYER_SNAPSHOT_KEYS: Array[String] = [
	"aim_direction",
	"current_shield",
	"dash_cooldown_remaining",
	"dash_direction",
	"dash_invulnerability_remaining",
	"dash_remaining",
	"element_damage_taken_multipliers",
	"external_knockback_duration",
	"external_knockback_remaining",
	"external_knockback_velocity",
	"life_points",
	"overshield",
	"owned_tag_counts",
	"position",
	"shield_gate_remaining",
	"shield_recharge_delay_remaining",
	"stat_additions",
	"stat_multipliers",
	"status_effects",
	"temporary_modifiers",
	"weapon_recoil_duration",
	"weapon_recoil_remaining",
	"weapon_recoil_velocity",
]


func test_player_combines_three_layers_and_normalizes_anonymous_source() -> void:
	var player: Player = _new_player({STATS.DAMAGE: 10.0})
	player.apply_modifiers([
		{"stat": STATS.DAMAGE, "type": "add", "value": 2.0},
		{"stat": STATS.DAMAGE, "type": "mult", "value": 2.0},
	])
	player.set_gear_modifiers([
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.2},
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.2},
	])
	player.apply_temporary_modifiers([
		{"stat": STATS.DAMAGE, "type": "mult", "value": 1.5},
	], 5.0, "")

	assert_almost_eq(player.stat_value(STATS.DAMAGE), 51.84, 0.000_001)
	var snapshot_data: Dictionary = player.snapshot()
	var temporary_modifiers: Dictionary = snapshot_data.get(
		"temporary_modifiers",
		{}
	) as Dictionary
	assert_true(temporary_modifiers.has(MODIFIER_STACK_SCRIPT.ANONYMOUS_SOURCE))


func test_player_snapshot_restore_preserves_wire_and_rebuild_side_effects() -> void:
	var source: Player = _new_player({
		STATS.MAX_HP: 100.0,
		STATS.MAX_SHIELD: 20.0,
	})
	source.apply_modifiers([
		{"stat": STATS.MAX_HP, "type": "add", "value": 10.0},
		{"stat": STATS.MAX_SHIELD, "type": "add", "value": 5.0},
	])
	source.set_gear_modifiers([
		{"stat": STATS.MAX_HP, "type": "add", "value": 20.0},
		{"stat": STATS.MAX_SHIELD, "type": "add", "value": 10.0},
	])
	source.apply_temporary_modifiers([
		{"stat": STATS.MAX_HP, "type": "add", "value": 30.0},
		{"stat": STATS.MAX_SHIELD, "type": "add", "value": 15.0},
	], 10.0, "temporary_boost")
	var snapshot_data: Dictionary = source.snapshot()
	var actual_keys: Array = snapshot_data.keys()
	actual_keys.sort()
	assert_eq(actual_keys, PLAYER_SNAPSHOT_KEYS)
	assert_false(snapshot_data.has("gear"))
	assert_false(snapshot_data.has("modifier_stack"))
	snapshot_data["life_points"] = 40.0
	snapshot_data["current_shield"] = 7.0

	var restored: Player = _new_player({
		STATS.MAX_HP: 100.0,
		STATS.MAX_SHIELD: 20.0,
	})
	var life_events: Array[Dictionary] = []
	var shield_events: Array[Dictionary] = []
	restored.life_changed.connect(
		func(current_life: float, maximum_life: float) -> void:
			life_events.append({
				"current": current_life,
				"maximum": maximum_life,
			})
	)
	restored.shield_changed.connect(
		func(
			current_shield: float,
			maximum_shield: float,
			overshield: float
		) -> void:
			shield_events.append({
				"current": current_shield,
				"maximum": maximum_shield,
				"overshield": overshield,
			})
	)

	restored.restore_snapshot(snapshot_data)
	restored.set_gear_modifiers([
		{"stat": STATS.MAX_HP, "type": "add", "value": 20.0},
		{"stat": STATS.MAX_SHIELD, "type": "add", "value": 10.0},
	])

	assert_almost_eq(restored.current_life(), 90.0, 0.0)
	assert_almost_eq(restored.max_life(), 160.0, 0.0)
	assert_almost_eq(restored.current_shield(), 32.0, 0.0)
	assert_almost_eq(restored.max_shield(), 50.0, 0.0)
	assert_eq(life_events, [
		{"current": 110.0, "maximum": 110.0},
		{"current": 70.0, "maximum": 140.0},
		{"current": 70.0, "maximum": 140.0},
		{"current": 90.0, "maximum": 160.0},
	])
	assert_eq(shield_events, [
		{"current": 25.0, "maximum": 25.0, "overshield": 0.0},
		{"current": 22.0, "maximum": 40.0, "overshield": 0.0},
		{"current": 22.0, "maximum": 40.0, "overshield": 0.0},
		{"current": 32.0, "maximum": 50.0, "overshield": 0.0},
	])


func _new_player(base_stats: Dictionary) -> Player:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	assert_not_null(player)
	add_child_autofree(player)
	player.configure(base_stats)
	return player
