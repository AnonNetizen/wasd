extends SmokeHarness


const RUN_SNAPSHOT_COORDINATOR_SCRIPT := preload(
	"res://scripts/gameplay/run_snapshot_coordinator.gd"
)

const EXPECTED_RUN_V19_KEYS: Array[String] = [
	"schema_version",
	"mode",
	"character",
	"hero_composition",
	"gold_progression",
	"kills",
	"next_enemy_spawn_serial",
	"game_clock",
	"difficulty",
	"rng",
	"map",
	"interest_points",
	"gear_mods",
	"content_availability",
	"content_progress_delta",
	"spawn_states",
	"player",
	"weapon",
	"skills",
	"effects",
	"hazards",
	"enemies",
	"bullets",
	"gold_orbs",
	"energy_orbs",
	"gear_mod_pickups",
	"module_world",
	"world_events",
	"reward_choice",
	"ui_restore",
]

var _restore_order: Array[String] = []
var _staged_flags: Array[bool] = []


func before_each() -> void:
	super()
	_restore_order.clear()
	_staged_flags.clear()


func test_capture_preserves_run_v19_field_order_and_deep_copies() -> void:
	var coordinator := RUN_SNAPSHOT_COORDINATOR_SCRIPT.new()
	var state: RUN_SNAPSHOT_COORDINATOR_SCRIPT.CaptureState = (
		RUN_SNAPSHOT_COORDINATOR_SCRIPT.CaptureState.new()
	)
	state.mode = "mode_fixture"
	state.character = "character_fixture"
	state.hero_composition = {"nested": {"value": 1}}
	state.gold_progression = {"gold_balance": 2}
	state.kills = 3
	state.next_enemy_spawn_serial = 4
	state.game_clock = {"elapsed": 5.0}
	state.difficulty = {"threat": 6.0}
	state.rng = {"stream": 7}
	state.map = {"layout": 8}
	state.interest_points = {"point": 9}
	state.gear_mods = {"next_instance_id": 10}
	state.content_availability = {"enemies": ["a"]}
	state.content_progress_delta = {"counters": {}}
	state.spawn_states = {"wave": {}}
	state.player = {"life": 11.0}
	state.weapon = {"ammo": 12}
	state.skills = {"energy": 13.0}
	state.effects = {"next_id": 14}
	state.hazards = [{"id": 15}]
	state.enemies = [{"id": 16}]
	state.bullets = [{"id": 17}]
	state.gold_orbs = [{"id": 18}]
	state.energy_orbs = [{"id": 19}]
	state.gear_mod_pickups = [{"id": 20}]
	state.module_world = {"map_hash": "fixture"}
	state.world_events = {"events": []}
	state.reward_choice = {"choices": []}
	state.ui_restore = {"state": "playing"}

	var snapshot: Dictionary = coordinator.capture(state)
	var actual_keys: Array[String] = []
	for raw_key: Variant in snapshot.keys():
		actual_keys.append(String(raw_key))

	assert_eq(actual_keys, EXPECTED_RUN_V19_KEYS)
	assert_eq(snapshot.size(), 30)
	assert_eq(int(snapshot.get("schema_version", -1)), 19)
	assert_false(snapshot.has("mod_environment"))
	(state.hero_composition["nested"] as Dictionary)["value"] = 99
	state.hazards[0]["id"] = 99
	assert_eq(
		int((snapshot["hero_composition"]["nested"] as Dictionary)["value"]),
		1
	)
	assert_eq(int(snapshot["hazards"][0]["id"]), 15)


func test_sync_and_staged_restore_keep_the_same_port_order() -> void:
	var coordinator := RUN_SNAPSHOT_COORDINATOR_SCRIPT.new()
	var snapshot: Dictionary = _valid_snapshot()

	assert_true(await coordinator.restore(
		snapshot.duplicate(true),
		_restore_bindings(),
		false
	))
	var sync_order: Array[String] = _restore_order.duplicate()
	assert_eq(_staged_flags, [false, false, false])

	_restore_order.clear()
	_staged_flags.clear()
	assert_true(await coordinator.restore(
		snapshot.duplicate(true),
		_restore_bindings(),
		true
	))

	assert_eq(_restore_order, sync_order)
	assert_eq(_staged_flags, [true, true, true])
	assert_eq(sync_order, [
		"normalize",
		"validate_pickups",
		"difficulty",
		"module_world",
		"gold_progression",
		"reward_choice",
		"scalar_state",
		"rng",
		"map_and_bounds",
		"player",
		"weapon",
		"gear_mods",
		"apply_gear_modifiers",
		"skills",
		"effect_runtime",
		"hazards_and_interest",
		"entity_batches",
		"game_clock",
		"refresh_hud",
	])


func test_leaf_failure_stops_before_later_restore_ports() -> void:
	var coordinator := RUN_SNAPSHOT_COORDINATOR_SCRIPT.new()
	var bindings: RUN_SNAPSHOT_COORDINATOR_SCRIPT.RestoreBindings = (
		_restore_bindings()
	)
	bindings.restore_module_world = Callable(
		self,
		"_record_staged_false"
	).bind("module_world")

	assert_false(await coordinator.restore(
		_valid_snapshot(),
		bindings,
		false
	))
	assert_eq(_restore_order[-1], "module_world")
	assert_eq(_staged_flags, [false])
	assert_false(_restore_order.has("gold_progression"))
	assert_false(_restore_order.has("reward_choice"))
	assert_false(_restore_order.has("hazards_and_interest"))
	assert_false(_restore_order.has("entity_batches"))
	assert_false(_restore_order.has("game_clock"))
	assert_false(_restore_order.has("refresh_hud"))


func _valid_snapshot() -> Dictionary:
	return {
		"schema_version": 19,
		"content_availability": {},
		"content_progress_delta": {},
	}


func _restore_bindings() -> RUN_SNAPSHOT_COORDINATOR_SCRIPT.RestoreBindings:
	var bindings: RUN_SNAPSHOT_COORDINATOR_SCRIPT.RestoreBindings = (
		RUN_SNAPSHOT_COORDINATOR_SCRIPT.RestoreBindings.new()
	)
	bindings.normalize_persisted_numbers = Callable(
		self,
		"_record_true"
	).bind("normalize")
	bindings.validate_gear_mod_pickups = Callable(
		self,
		"_record_true"
	).bind("validate_pickups")
	bindings.restore_difficulty = Callable(
		self,
		"_record_true"
	).bind("difficulty")
	bindings.restore_module_world = Callable(
		self,
		"_record_staged_true"
	).bind("module_world")
	bindings.restore_gold_progression = Callable(
		self,
		"_record_true"
	).bind("gold_progression")
	bindings.restore_reward_choice = Callable(
		self,
		"_record_true"
	).bind("reward_choice")
	bindings.restore_scalar_state = Callable(
		self,
		"_record_void"
	).bind("scalar_state")
	bindings.restore_rng = Callable(self, "_record_void").bind("rng")
	bindings.restore_map_and_bounds = Callable(
		self,
		"_record_void"
	).bind("map_and_bounds")
	bindings.restore_player = Callable(self, "_record_void").bind("player")
	bindings.restore_weapon = Callable(self, "_record_void").bind("weapon")
	bindings.restore_gear_mods = Callable(
		self,
		"_record_true"
	).bind("gear_mods")
	bindings.apply_gear_modifiers = Callable(
		self,
		"_record_no_arg"
	).bind("apply_gear_modifiers")
	bindings.restore_skills = Callable(self, "_record_void").bind("skills")
	bindings.restore_effect_runtime = Callable(
		self,
		"_record_true"
	).bind("effect_runtime")
	bindings.restore_hazards_and_interest = Callable(
		self,
		"_record_staged_true"
	).bind("hazards_and_interest")
	bindings.restore_entity_batches = Callable(
		self,
		"_record_staged_true"
	).bind("entity_batches")
	bindings.restore_game_clock = Callable(
		self,
		"_record_void"
	).bind("game_clock")
	bindings.refresh_hud = Callable(
		self,
		"_record_no_arg"
	).bind("refresh_hud")
	return bindings


func _record_true(_snapshot: Dictionary, label: String) -> bool:
	_restore_order.append(label)
	return true


func _record_staged_true(
	_snapshot: Dictionary,
	staged_loading: bool,
	label: String
) -> bool:
	_restore_order.append(label)
	_staged_flags.append(staged_loading)
	return true


func _record_staged_false(
	_snapshot: Dictionary,
	staged_loading: bool,
	label: String
) -> bool:
	_restore_order.append(label)
	_staged_flags.append(staged_loading)
	return false


func _record_void(_snapshot: Dictionary, label: String) -> void:
	_restore_order.append(label)


func _record_no_arg(label: String) -> void:
	_restore_order.append(label)
