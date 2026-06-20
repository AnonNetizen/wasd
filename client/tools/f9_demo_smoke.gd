extends Node


const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const META_CURRENCIES := preload("res://scripts/contracts/meta_currencies.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

const BULWARK_COLOR: Color = Color(0.690196, 0.490196, 0.321569)
const BULWARK_ID: String = "enemy_bulwark"
const BULWARK_WAVE_ID: String = "wave_standard_mid_bulwarks"
const FAST_FORWARD_SCALE: float = 20.0
const MAX_WAIT_FRAMES: int = 420
const TARGET_BULWARK_TIME: float = 55.0

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)

	var run_loop: Node = await _wait_for_run_loop()
	_expect(run_loop != null, "F9 demo smoke should run with GameplayRunLoop mounted")
	if run_loop == null:
		_finish()
		return

	var player: Node2D = _find_node_by_name(run_loop, "Player") as Node2D
	_expect(player != null, "F9 demo smoke should find the player")
	if player == null:
		_finish()
		return
	_protect_player(player)

	var previous_time_scale: float = GameClock.time_scale()
	GameClock.set_time_scale(FAST_FORWARD_SCALE)
	var bulwark: Node = await _wait_for_bulwark()
	GameClock.set_time_scale(previous_time_scale)

	_expect(GameClock.now() >= TARGET_BULWARK_TIME, "F9 demo smoke should reach the mid-run bulwark wave time")
	_expect(bulwark != null, "enemy_bulwark should spawn from the 55s mid-run wave")
	if bulwark != null:
		_expect(String(bulwark.get_meta("wave_key", "")) == BULWARK_WAVE_ID, "enemy_bulwark should carry its configured wave key")
		_expect(_bulwark_color_matches(bulwark), "enemy_bulwark should use the F9.1 data-driven placeholder color")

	var snapshot: Dictionary = run_loop.call("create_run_snapshot")
	_expect(_snapshot_has_bulwark(snapshot), "run snapshot should persist active enemy_bulwark entries")
	_expect(SaveManager.save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN, snapshot), "F9 demo smoke should save a run snapshot containing F9.1 content")
	var saved_payload: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	_expect(_snapshot_has_bulwark(saved_payload), "saved run payload should roundtrip enemy_bulwark")

	_expect(_level_three_entries_available(run_loop), "level 3 growth pool should expose the F9.1 move speed and max HP candidates")

	await _kill_player_for_settlement(run_loop, player)
	_expect(GameState.is_state(GameState.GAME_OVER), "F9 demo smoke death should enter GAME_OVER")
	_expect(SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META), "F9 demo smoke death should write meta save")
	var meta_profile: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	var currencies: Dictionary = meta_profile.get("currencies", {}) as Dictionary
	_expect(int(currencies.get(META_CURRENCIES.META_ESSENCE, 0)) >= 8, "F9 demo smoke death should grant Memory Embers")

	_finish()


func _wait_for_run_loop() -> Node:
	for _index: int in range(30):
		await get_tree().process_frame
		var run_loop: Node = _find_node_by_name(get_tree().root, "GameplayRunLoop")
		if run_loop != null:
			return run_loop
	return null


func _protect_player(player: Node) -> void:
	if player.has_method("apply_modifiers"):
		player.call("apply_modifiers", [{
			"stat": STATS.MAX_HP,
			"type": "add",
			"value": 1000.0,
		}])
	if player.has_method("debug_heal"):
		player.call("debug_heal", 1000.0)
	if player.has_method("aim_at_world_position") and player is Node2D:
		var player_2d: Node2D = player as Node2D
		player.call("aim_at_world_position", player_2d.global_position + Vector2.RIGHT * 240.0)


func _wait_for_bulwark() -> Node:
	for _index: int in range(MAX_WAIT_FRAMES):
		await get_tree().process_frame
		await get_tree().physics_frame
		var bulwark: Node = _first_enemy_with_id(BULWARK_ID)
		if bulwark != null:
			return bulwark
	return null


func _first_enemy_with_id(enemy_id: String) -> Node:
	for enemy: Node in get_tree().get_nodes_in_group("active_enemies"):
		if not enemy.has_method("snapshot"):
			continue
		var snapshot: Dictionary = enemy.call("snapshot")
		if String(snapshot.get("enemy_id", "")) == enemy_id:
			return enemy
	return null


func _bulwark_color_matches(enemy: Node) -> bool:
	if not enemy.has_method("visual_color"):
		return false
	var color: Color = enemy.call("visual_color")
	return (
		is_equal_approx(color.r, BULWARK_COLOR.r)
		and is_equal_approx(color.g, BULWARK_COLOR.g)
		and is_equal_approx(color.b, BULWARK_COLOR.b)
	)


func _snapshot_has_bulwark(snapshot: Dictionary) -> bool:
	var enemies: Array = snapshot.get("enemies", []) if snapshot.get("enemies", []) is Array else []
	for raw_enemy: Variant in enemies:
		if not raw_enemy is Dictionary:
			continue
		var enemy: Dictionary = raw_enemy as Dictionary
		if String(enemy.get("enemy_id", "")) == BULWARK_ID and String(enemy.get("wave_key", "")) == BULWARK_WAVE_ID:
			return true
	return false


func _level_three_entries_available(run_loop: Node) -> bool:
	var raw_entries: Variant = run_loop.get("_growth_entries")
	if not raw_entries is Array:
		return false
	var seen_move_speed: bool = false
	var seen_max_hp: bool = false
	for raw_entry: Variant in raw_entries as Array:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry as Dictionary
		if int(entry.get("min_level", 1)) > 3:
			continue
		var entry_id: String = String(entry.get("id", ""))
		seen_move_speed = seen_move_speed or entry_id == "growth_move_speed_small"
		seen_max_hp = seen_max_hp or entry_id == "growth_max_hp_small"
	return seen_move_speed and seen_max_hp


func _kill_player_for_settlement(run_loop: Node, player: Node) -> void:
	if player.has_method("debug_clear_invulnerability"):
		player.call("debug_clear_invulnerability")
	var damage_source: Node = Node.new()
	damage_source.name = "F9DemoSmokeDamageSource"
	run_loop.add_child(damage_source)
	var damage_info: RefCounted = DAMAGE_INFO_SCRIPT.new().setup(
		999999.0,
		DAMAGE_TYPES.PHYSICAL,
		damage_source,
		player,
		"team_enemy",
		"team_player"
	)
	Combat.apply_damage(player, damage_info)
	for _index: int in range(10):
		await get_tree().process_frame
		if GameState.is_state(GameState.GAME_OVER):
			break
	damage_source.queue_free()


func _find_node_by_name(root_node: Node, target_name: String) -> Node:
	if root_node == null:
		return null
	if root_node.name == target_name:
		return root_node
	for child: Node in root_node.get_children():
		var match_node: Node = _find_node_by_name(child, target_name)
		if match_node != null:
			return match_node
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[F9DemoSmoke] %s" % message)


func _finish() -> void:
	GameClock.set_time_scale(1.0)
	if _failures.is_empty():
		print("[F9DemoSmoke] passed; game_time=%.2f" % GameClock.now())
		get_tree().quit(0)
		return
	print("[F9DemoSmoke] failed; failures=%d" % _failures.size())
	for failure: String in _failures:
		print("[F9DemoSmoke] failure: %s" % failure)
	get_tree().quit(1)
