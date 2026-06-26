extends Node


const DAMAGE_INFO_SCRIPT := preload("res://scripts/combat/damage_info.gd")
const DAMAGE_TYPES := preload("res://scripts/contracts/damage_types.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const STATS := preload("res://scripts/contracts/stats.gd")

const BULWARK_COLOR: Color = Color(0.690196, 0.490196, 0.321569)
const BULWARK_ID: String = "enemy_bulwark"
const BULWARK_WAVE_ID: String = "wave_standard_mid_bulwarks"
const FAST_FORWARD_SCALE: float = 20.0
const FEA_12_HAZARD_ID: String = "hazard_fea_12_pulse"
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
	await _expect_fea_12_hazard(run_loop, player)

	var previous_time_scale: float = GameClock.time_scale()
	GameClock.set_time_scale(FAST_FORWARD_SCALE)
	var bulwark: Node = await _wait_for_bulwark()
	GameClock.set_time_scale(previous_time_scale)

	_expect(GameClock.now() >= TARGET_BULWARK_TIME, "F9 demo smoke should reach the mid-run bulwark wave time")
	_expect(bulwark != null, "enemy_bulwark should spawn from the 55s mid-run wave")
	if bulwark != null:
		_expect(String(bulwark.get_meta("wave_key", "")) == BULWARK_WAVE_ID, "enemy_bulwark should carry its configured wave key")
		_expect(_bulwark_color_matches(bulwark), "enemy_bulwark should use the F9.1 data-driven placeholder color")
		_expect(_warzone_director_guarded_phase_active(run_loop), "WarzoneDirector should expose the guarded midfield phase for the bulwark wave")

	var snapshot: Dictionary = run_loop.call("create_run_snapshot")
	_expect(_snapshot_has_bulwark(snapshot), "run snapshot should persist active enemy_bulwark entries")
	_expect(_snapshot_has_fea_12_hazard(snapshot), "run snapshot should persist active FEA-12 hazard entries")
	_expect(SaveManager.save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN, snapshot), "F9 demo smoke should save a run snapshot containing F9.1 content")
	var saved_payload: Dictionary = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	_expect(_snapshot_has_bulwark(saved_payload), "saved run payload should roundtrip enemy_bulwark")
	_expect(_snapshot_has_fea_12_hazard(saved_payload), "saved run payload should roundtrip FEA-12 hazards")

	_expect(not _standard_growth_enabled(run_loop), "standard mode should keep level-up growth disabled for short loot runs")

	await _kill_player_for_settlement(run_loop, player)
	_expect(GameState.is_state(GameState.GAME_OVER), "F9 demo smoke death should enter GAME_OVER")
	var meta_profile: Dictionary = {}
	if SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META):
		meta_profile = SaveManager.load(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META)
	_expect(not meta_profile.has("currencies"), "F9 demo smoke death should not grant legacy meta currencies")

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
			"value": 10000.0,
		}, {
			"stat": STATS.HEALTH_REGEN,
			"type": "add",
			"value": 250.0,
		}])
	if player.has_method("debug_heal"):
		player.call("debug_heal", 10000.0)
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


func _expect_fea_12_hazard(run_loop: Node, player: Node2D) -> void:
	_expect(_debug_summary_has_fea_12(run_loop), "MapManager debug summary should include director-sourced hazards")
	var hazard: Node2D = _first_hazard_with_id(FEA_12_HAZARD_ID) as Node2D
	_expect(hazard != null, "FEA-12 hazard should spawn from map generation")
	if hazard == null:
		return
	if player.has_method("debug_clear_invulnerability"):
		player.call("debug_clear_invulnerability")
	var previous_life: float = float(player.call("current_life"))
	player.global_position = hazard.global_position
	for _index: int in range(3):
		await get_tree().physics_frame
	_expect(float(player.call("current_life")) < previous_life, "FEA-12 hazard should apply Combat damage when the player enters its radius")


func _first_hazard_with_id(hazard_id: String) -> Node:
	for hazard: Node in get_tree().get_nodes_in_group("active_hazards"):
		if hazard.has_method("hazard_id") and String(hazard.call("hazard_id")) == hazard_id:
			return hazard
	return null


func _debug_summary_has_fea_12(run_loop: Node) -> bool:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return false
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_map: Variant = summary.get("map", {})
	if not raw_map is Dictionary:
		return false
	var map_summary: Dictionary = raw_map as Dictionary
	var raw_sources: Variant = map_summary.get("hazard_sources", {})
	if not raw_sources is Dictionary:
		return false
	var sources: Dictionary = raw_sources as Dictionary
	return int(summary.get("active_hazards", 0)) > 0 and int(sources.get("director", 0)) > 0


func _warzone_director_guarded_phase_active(run_loop: Node) -> bool:
	if run_loop == null or not run_loop.has_method("debug_summary"):
		return false
	var summary: Dictionary = run_loop.call("debug_summary") as Dictionary
	var raw_director: Variant = summary.get("warzone_director", {})
	if not raw_director is Dictionary:
		return false
	var director: Dictionary = raw_director as Dictionary
	var raw_wave_ids: Variant = director.get("wave_ids", [])
	var raw_encounter_ids: Variant = director.get("encounter_ids", [])
	if not raw_wave_ids is Array or not raw_encounter_ids is Array:
		return false
	var wave_ids: Array = raw_wave_ids as Array
	var encounter_ids: Array = raw_encounter_ids as Array
	return (
		bool(director.get("configured", false))
		and String(director.get("phase_id", "")) == "phase_guarded_midfield"
		and wave_ids.has(BULWARK_WAVE_ID)
		and encounter_ids.has("encounter_territorial_pressure")
	)


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


func _snapshot_has_fea_12_hazard(snapshot: Dictionary) -> bool:
	var hazards: Array = snapshot.get("hazards", []) if snapshot.get("hazards", []) is Array else []
	for raw_hazard: Variant in hazards:
		if not raw_hazard is Dictionary:
			continue
		var hazard: Dictionary = raw_hazard as Dictionary
		if String(hazard.get("hazard_id", "")) == FEA_12_HAZARD_ID:
			return true
	return false


func _standard_growth_enabled(run_loop: Node) -> bool:
	var summary: Dictionary = run_loop.call("debug_summary")
	return bool(summary.get("level_up_growth_enabled", false))


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
