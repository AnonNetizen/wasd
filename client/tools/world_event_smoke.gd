extends SceneTree


const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const COMBAT_SCRIPT := preload("res://scripts/combat/combat.gd")
const ELEMENTS := preload("res://scripts/contracts/elements.gd")
const WORLD_EVENT_REWARD_TYPES := preload(
	"res://scripts/contracts/world_event_reward_types.gd"
)
const WORLD_EVENT_STATES := preload(
	"res://scripts/contracts/world_event_states.gd"
)
const WORLD_EVENT_DATA_PATH: String = "res://data/world_events.json"
const SCENE_PATHS: Dictionary = {
	"world_event_defense": "res://scenes/gameplay/world_events/world_event_defense.tscn",
	"world_event_survival": "res://scenes/gameplay/world_events/world_event_survival.tscn",
	"world_event_capture": "res://scenes/gameplay/world_events/world_event_capture.tscn",
	"world_event_gold_shrine": "res://scenes/gameplay/world_events/world_event_gold_shrine.tscn",
	"world_event_blood_shrine": "res://scenes/gameplay/world_events/world_event_blood_shrine.tscn",
}

var _controller: WorldEventController = null
var _combat: CombatAutoload = null
var _mod_pool: Array[String] = []
var _nodes: Dictionary = {}
var _reward_count: int = 0
var _roll_should_succeed: bool = true
var _wave_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var data: Dictionary = _read_json(WORLD_EVENT_DATA_PATH)
	_require(not data.is_empty(), "world event data loads")
	_controller = WorldEventController.new()
	get_root().add_child(_controller)
	_combat = COMBAT_SCRIPT.new()
	get_root().add_child(_combat)
	_controller.configure(data)
	_mod_pool = _controller.mod_pool("world_event_mod_pool_common")
	_require(_mod_pool.size() == 3, "common Mod pool exposes three entries")
	_controller.wave_requested.connect(_on_wave_requested)
	_controller.reward_requested.connect(_on_reward_requested)

	var player := Node2D.new()
	player.name = "WorldEventSmokePlayer"
	get_root().add_child(player)
	for event_id_raw: Variant in SCENE_PATHS.keys():
		var event_id: String = String(event_id_raw)
		var scene_path: String = String(SCENE_PATHS[event_id])
		var packed: PackedScene = load(scene_path) as PackedScene
		_require(packed != null, "%s loads" % scene_path)
		var node: Node = packed.instantiate()
		_require(
			node is WorldEventInteractable,
			"%s root is WorldEventInteractable" % event_id
		)
		var interactable: WorldEventInteractable = node as WorldEventInteractable
		interactable.global_position = Vector2.ZERO
		get_root().add_child(interactable)
		var defense_target: WorldEventDefenseTarget = interactable.defense_target()
		_require(
			_controller.register_instance(
				"%s_instance" % event_id,
				event_id,
				interactable,
				"slot_%s" % event_id,
				defense_target
			),
			"%s registers" % event_id
		)
		_nodes[event_id] = interactable

	var callbacks: Dictionary = {
		"prepare_world_event_reward": _prepare_reward,
		"try_spend_gold": _try_spend_gold,
		"roll_world_event_chance": _roll_success,
		"choose_world_event_mod": _choose_mod,
		"try_sacrifice_combined_health": _sacrifice_health,
		"player_is_alive": _player_is_alive,
	}
	_test_defense(player, callbacks)
	_test_survival(player, callbacks)
	_test_capture(player, callbacks)
	_test_capture_timeout(player, callbacks)
	_test_gold_shrine(player, callbacks)
	_test_blood_shrine(player, callbacks)
	_test_snapshot_roundtrip()
	_require(_wave_count == 10, "all ten configured waves requested exactly once")
	_require(_reward_count == 8, "completion and shrine rewards requested exactly once")
	print("WORLD EVENT SMOKE ALL PASS")
	quit()


func _test_defense(player: Node2D, callbacks: Dictionary) -> void:
	var interactable: WorldEventInteractable = _nodes["world_event_defense"]
	var target: WorldEventDefenseTarget = interactable.defense_target()
	_require(target != null, "defense scene exposes target")
	_require(target.hit_radius() > 0.0, "defense target exposes hit radius")
	_require(target.combat_team_id() == "team_player", "defense target is player allied")
	var inactive_result: Dictionary = _combat.apply_damage(
		target,
		_damage_info(target, "team_enemy", 10.0)
	)
	_require(
		String(inactive_result.get("reason", "")) == "inactive",
		"defense target rejects damage before activation"
	)
	var start: Dictionary = _controller.interact(
		"world_event_defense_instance",
		player,
		callbacks
	)
	_require(bool(start.get("accepted", false)), "defense event starts")
	var busy_result: Dictionary = _controller.interact(
		"world_event_survival_instance",
		player,
		callbacks
	)
	_require(
		String(busy_result.get("reason", "")) == "continuous_event_busy",
		"another continuous event is blocked while defense is active"
	)
	var shrine_callbacks: Dictionary = callbacks.duplicate()
	shrine_callbacks["try_spend_gold"] = _reject_spend
	var shrine_result: Dictionary = _controller.interact(
		"world_event_gold_shrine_instance",
		player,
		shrine_callbacks
	)
	_require(
		String(shrine_result.get("reason", "")) == "insufficient_gold",
		"shrine remains usable while a continuous event is active"
	)
	var player_result: Dictionary = _combat.apply_damage(
		target,
		_damage_info(target, "team_player", 10.0)
	)
	_require(
		String(player_result.get("reason", "")) == "player_team_ignored",
		"defense target rejects player damage"
	)
	var enemy_result: Dictionary = _combat.apply_damage(
		target,
		_damage_info(target, "team_enemy", 10.0)
	)
	_require(bool(enemy_result.get("applied", false)), "defense target accepts enemy damage")
	_controller.tick(45.0, player, callbacks)
	_require(
		interactable.event_state()
		== WORLD_EVENT_STATES.WORLD_EVENT_STATE_SUCCEEDED,
		"defense completes after configured duration"
	)
	_controller.release_background_pin("world_event_defense_instance")


func _test_survival(player: Node2D, callbacks: Dictionary) -> void:
	var start: Dictionary = _controller.interact(
		"world_event_survival_instance",
		player,
		callbacks
	)
	_require(bool(start.get("accepted", false)), "survival event starts")
	_controller.tick(40.0, player, callbacks)
	var interactable: WorldEventInteractable = _nodes["world_event_survival"]
	_require(
		interactable.event_state()
		== WORLD_EVENT_STATES.WORLD_EVENT_STATE_SUCCEEDED,
		"survival completes after configured duration"
	)
	_controller.release_background_pin("world_event_survival_instance")


func _test_capture(player: Node2D, callbacks: Dictionary) -> void:
	var start: Dictionary = _controller.interact(
		"world_event_capture_instance",
		player,
		callbacks
	)
	_require(bool(start.get("accepted", false)), "capture event starts")
	_controller.tick(2.0, player, callbacks)
	player.global_position = Vector2(600.0, 0.0)
	_controller.tick(2.0, player, callbacks)
	var summary: Dictionary = _instance_summary("world_event_capture_instance")
	_require(
		is_equal_approx(float(summary.get("entry_delay_progress", -1.0)), 1.0),
		"capture entry delay decays by configured rate outside"
	)
	player.global_position = Vector2.ZERO
	_controller.tick(20.0, player, callbacks)
	var interactable: WorldEventInteractable = _nodes["world_event_capture"]
	_require(
		interactable.event_state()
		== WORLD_EVENT_STATES.WORLD_EVENT_STATE_SUCCEEDED,
		"capture preserves progress and completes"
	)
	_controller.release_background_pin("world_event_capture_instance")


func _test_capture_timeout(player: Node2D, callbacks: Dictionary) -> void:
	var snapshot_data: Dictionary = _controller.snapshot()
	snapshot_data["active_continuous_instance_id"] = (
		"world_event_capture_instance"
	)
	var instances: Array = snapshot_data.get("instances", []) as Array
	for item_raw: Variant in instances:
		if not item_raw is Dictionary:
			continue
		var item: Dictionary = item_raw as Dictionary
		if (
			String(item.get("instance_id", ""))
			!= "world_event_capture_instance"
		):
			continue
		item["state"] = WORLD_EVENT_STATES.WORLD_EVENT_STATE_ACTIVE
		item["elapsed"] = 119.5
		item["wave_cursor"] = 3
		item["entry_delay_progress"] = 0.0
		item["capture_progress"] = 0.0
		item["reward_committed"] = false
		item["pinned"] = true
	var restore_result: Dictionary = _controller.restore_snapshot(
		snapshot_data
	)
	_require(
		int(restore_result.get("restored", 0)) == 5,
		"capture timeout fixture restores"
	)
	player.global_position = Vector2(600.0, 0.0)
	_controller.tick(0.5, player, callbacks)
	var interactable: WorldEventInteractable = _nodes[
		"world_event_capture"
	]
	_require(
		interactable.event_state()
		== WORLD_EVENT_STATES.WORLD_EVENT_STATE_FAILED,
		"capture fails at the configured 120 second timeout"
	)
	_require(
		_controller.active_continuous_instance_id().is_empty(),
		"capture timeout releases the continuous-event slot"
	)
	_controller.release_background_pin("world_event_capture_instance")
	player.global_position = Vector2.ZERO


func _test_gold_shrine(player: Node2D, callbacks: Dictionary) -> void:
	var no_gold_callbacks: Dictionary = callbacks.duplicate()
	no_gold_callbacks["try_spend_gold"] = _reject_spend
	var rejected: Dictionary = _controller.interact(
		"world_event_gold_shrine_instance",
		player,
		no_gold_callbacks
	)
	_require(
		String(rejected.get("reason", "")) == "insufficient_gold",
		"gold shrine rejects insufficient funds without accepting"
	)
	var untouched: Dictionary = _instance_summary(
		"world_event_gold_shrine_instance"
	)
	_require(
		int(untouched.get("attempts", -1)) == 0
		and int(untouched.get("next_cost", 0)) == 30,
		"insufficient funds do not consume an attempt or raise the price"
	)
	_roll_should_succeed = false
	var first: Dictionary = _controller.interact(
		"world_event_gold_shrine_instance",
		player,
		callbacks
	)
	_require(int(first.get("cost", 0)) == 30, "gold shrine first cost is configured")
	_require(int(first.get("next_cost", 0)) == 42, "gold shrine cost grows by ceil 1.4")
	_require(
		String(first.get("reason", "")) == "failed_roll"
		and int(first.get("successes", -1)) == 0,
		"gold shrine failure still spends and increases the next price"
	)
	_roll_should_succeed = true
	var second: Dictionary = _controller.interact(
		"world_event_gold_shrine_instance",
		player,
		callbacks
	)
	_require(bool(second.get("accepted", false)), "gold shrine accepts second use")
	var third: Dictionary = _controller.interact(
		"world_event_gold_shrine_instance",
		player,
		callbacks
	)
	_require(bool(third.get("accepted", false)), "gold shrine accepts third use")
	var interactable: WorldEventInteractable = _nodes["world_event_gold_shrine"]
	_require(
		interactable.event_state()
		== WORLD_EVENT_STATES.WORLD_EVENT_STATE_EXHAUSTED,
		"gold shrine exhausts after two successes"
	)
	var summary: Dictionary = _instance_summary("world_event_gold_shrine_instance")
	var mod_ids: Array[String] = _string_array(summary.get("successful_mod_ids", []))
	_require(mod_ids.size() == 2 and mod_ids[0] != mod_ids[1], "gold shrine Mod rewards differ")


func _test_blood_shrine(player: Node2D, callbacks: Dictionary) -> void:
	for _use_index: int in range(3):
		var result: Dictionary = _controller.interact(
			"world_event_blood_shrine_instance",
			player,
			callbacks
		)
		_require(bool(result.get("accepted", false)), "blood shrine use succeeds")
	var interactable: WorldEventInteractable = _nodes["world_event_blood_shrine"]
	_require(
		interactable.event_state()
		== WORLD_EVENT_STATES.WORLD_EVENT_STATE_EXHAUSTED,
		"blood shrine exhausts after three uses"
	)


func _test_snapshot_roundtrip() -> void:
	var snapshot_data: Dictionary = _controller.snapshot()
	var restore_result: Dictionary = _controller.restore_snapshot(snapshot_data)
	_require(int(restore_result.get("restored", 0)) == 5, "all event snapshots restore")
	var debug: Dictionary = _controller.debug_summary()
	var instances_raw: Variant = debug.get("instances", [])
	_require(instances_raw is Array, "debug summary exposes instances")
	_require((instances_raw as Array).size() == 5, "debug summary includes non-defense events")


func _prepare_reward(
	_instance_id: String,
	_event_id: String,
	reward_config: Dictionary
) -> Dictionary:
	return {
		"kind": WORLD_EVENT_REWARD_TYPES.WORLD_EVENT_REWARD_GOLD,
		"amount": int(reward_config.get("gold_amount", 0)),
		"pending": false,
	}


func _try_spend_gold(_instance_id: String, _cost: int) -> bool:
	return true


func _reject_spend(_instance_id: String, _cost: int) -> bool:
	return false


func _roll_success(_instance_id: String, _chance: float) -> bool:
	return _roll_should_succeed


func _choose_mod(
	_instance_id: String,
	_pool_id: String,
	excluded: Array[String]
) -> String:
	for mod_id: String in _mod_pool:
		if not excluded.has(mod_id):
			return mod_id
	return ""


func _sacrifice_health(_instance_id: String, ratio: float) -> Dictionary:
	return {
		"accepted": true,
		"actual_spent": ratio * 200.0,
	}


func _player_is_alive(_player: Node) -> bool:
	return true


func _on_wave_requested(
	_instance_id: String,
	_event_id: String,
	_wave_index: int,
	_enemy_count: int,
	_world_position: Vector2,
	_primary_target: Node,
	_context: Dictionary
) -> void:
	_wave_count += 1


func _on_reward_requested(
	_instance_id: String,
	_event_id: String,
	_reward: Dictionary
) -> void:
	_reward_count += 1


func _instance_summary(instance_id: String) -> Dictionary:
	var debug: Dictionary = _controller.debug_summary()
	var instances_raw: Variant = debug.get("instances", [])
	if not instances_raw is Array:
		return {}
	for item_raw: Variant in instances_raw:
		if not item_raw is Dictionary:
			continue
		var item: Dictionary = item_raw as Dictionary
		if String(item.get("instance_id", "")) == instance_id:
			return item
	return {}


func _damage_info(
	target: Node,
	source_team: String,
	amount: float
) -> RefCounted:
	return DAMAGE_INFO_SCRIPT.new().setup(
		amount,
		ELEMENTS.ELEMENT_NEUTRAL,
		target,
		target,
		source_team,
		String(target.call("combat_team_id"))
	)


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_require(file != null, "open %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_require(parsed is Dictionary, "%s root is Dictionary" % path)
	return parsed as Dictionary


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value:
		result.append(String(item))
	return result


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("WORLD EVENT SMOKE FAILED: %s" % message)
	quit(1)
