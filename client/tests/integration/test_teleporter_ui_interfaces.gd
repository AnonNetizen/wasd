extends SmokeHarness


const CAMERA_SCENE: PackedScene = preload(
	"res://scenes/gameplay/gameplay_camera_controller.tscn"
)
const CHOICE_PANEL_SCENE: PackedScene = preload(
	"res://scenes/ui/teleport_choice_panel.tscn"
)
const FADE_OVERLAY_SCENE: PackedScene = preload(
	"res://scenes/ui/teleport_fade_overlay.tscn"
)
const HAZARD_SCENE: PackedScene = preload(
	"res://scenes/gameplay/hazard.tscn"
)
const INTERACTABLE_SCENE: PackedScene = preload(
	"res://scenes/gameplay/teleporter_interactable.tscn"
)
const PLAYER_SCENE: PackedScene = preload(
	"res://scenes/gameplay/actors/player_base.tscn"
)
const ACTIONS := preload("res://scripts/contracts/actions.gd")
const STATS := preload("res://scripts/contracts/stats.gd")


func test_teleport_choice_keeps_playing_and_game_clock_running() -> void:
	var previous_state: StringName = GameState.current()
	var previous_context: Dictionary = GameState.context()
	GameState.change_state(GameState.PLAYING)
	var probe := SimulationProbe.new()
	add_child_autofree(probe)
	var panel: CanvasLayer = CHOICE_PANEL_SCENE.instantiate() as CanvasLayer
	add_child_autofree(panel)
	await get_tree().process_frame
	var frames_before: int = probe.processed_frames

	assert_true(GameState.is_state(GameState.PLAYING))
	assert_true(InputService.non_pausing_ui_capture_active())
	assert_gt(GameClock.delta_scaled(1.0), 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(probe.processed_frames, frames_before)
	assert_true(GameState.change_state(GameState.PAUSED))
	assert_eq(GameClock.delta_scaled(1.0), 0.0)
	assert_true(GameState.change_state(GameState.PLAYING))

	panel.queue_free()
	await get_tree().process_frame
	GameState.change_state(previous_state, previous_context)
	assert_eq(GameState.current(), previous_state)


func test_teleport_choice_capture_blocks_gameplay_but_allows_pause() -> void:
	var previous_state: StringName = GameState.current()
	var previous_context: Dictionary = GameState.context()
	GameState.change_state(GameState.PLAYING)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.configure({
		STATS.MAX_HP: 100.0,
		STATS.MAX_SHIELD: 0.0,
		STATS.MOVE_SPEED: 300.0,
		STATS.HEALTH_REGEN: 60.0,
	})
	player.debug_set_life(50.0)
	var panel: CanvasLayer = CHOICE_PANEL_SCENE.instantiate() as CanvasLayer
	add_child_autofree(panel)
	InputService.set_playback_active(true)
	assert_true(InputService.inject_playback_value(ACTIONS.MOVE, Vector2.RIGHT))
	assert_true(InputService.inject_playback_value(ACTIONS.FIRE, true))
	assert_true(InputService.inject_playback_value(ACTIONS.PAUSE, true))
	assert_eq(InputService.vector(ACTIONS.MOVE), Vector2.ZERO)
	assert_false(InputService.is_pressed(ACTIONS.FIRE))
	assert_true(InputService.is_pressed(ACTIONS.PAUSE))
	assert_true(GameState.is_state(GameState.PLAYING))
	var position_before: Vector2 = player.global_position
	var life_before: float = player.current_life()

	for _frame: int in range(4):
		await get_tree().physics_frame

	assert_eq(player.global_position, position_before)
	assert_gt(player.current_life(), life_before)
	assert_true(InputService.inject_playback_value(ACTIONS.PAUSE, false))
	InputService.set_playback_active(false)
	panel.queue_free()
	await get_tree().process_frame
	GameState.change_state(previous_state, previous_context)


func test_teleport_choice_keeps_hazard_pressure_active() -> void:
	var previous_state: StringName = GameState.current()
	var previous_context: Dictionary = GameState.context()
	GameState.change_state(GameState.PLAYING)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.configure({
		STATS.MAX_HP: 100.0,
		STATS.MAX_SHIELD: 0.0,
		STATS.MOVE_SPEED: 300.0,
	})
	var hazard: Hazard = HAZARD_SCENE.instantiate() as Hazard
	add_child_autofree(hazard)
	hazard.configure({
		"id": "test_teleport_choice_hazard",
		"damage": 10.0,
		"element_id": "element_neutral",
		"trigger_interval": 1.0,
		"radius_tiles": 1,
		"duration": 0.1,
	}, player, Vector2(160.0, 160.0))
	var panel: CanvasLayer = CHOICE_PANEL_SCENE.instantiate() as CanvasLayer
	add_child_autofree(panel)
	assert_true(GameState.is_state(GameState.PLAYING))
	assert_true(InputService.non_pausing_ui_capture_active())

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_lt(player.current_life(), player.max_life())
	panel.queue_free()
	await get_tree().process_frame
	GameState.change_state(previous_state, previous_context)


func test_player_teleport_clears_transient_movement_but_preserves_cooldown_and_life() -> void:
	var previous_state: StringName = GameState.current()
	var previous_context: Dictionary = GameState.context()
	GameState.change_state(GameState.PLAYING)
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)
	player.configure({
		STATS.MAX_HP: 100.0,
		STATS.MAX_SHIELD: 20.0,
		STATS.MOVE_SPEED: 300.0,
	})
	player.configure_runtime_rules({
		"dash": {
			"speed": 750.0,
			"duration": 0.16,
			"cooldown": 1.25,
			"invulnerability_duration": 0.12,
		},
	})
	player.configure_weapon_recoil({"kickback_velocity_cap": 180.0})
	player.debug_set_life(61.0)
	player.apply_weapon_recoil(Vector2.RIGHT, 120.0, 0.2)
	assert_true(player.apply_external_knockback(Vector2.LEFT, 40.0, 0.2))
	assert_true(bool(player.try_dash(Vector2.RIGHT).get("ok", false)))
	var cooldown_before: float = player.dash_cooldown_remaining()

	assert_true(player.teleport_to(Vector2(640.0, 480.0)))
	assert_eq(player.global_position, Vector2(640.0, 480.0))
	assert_eq(player.velocity, Vector2.ZERO)
	assert_false(player.is_dashing())
	assert_eq(player.weapon_recoil_velocity(), Vector2.ZERO)
	assert_eq(player.weapon_recoil_remaining(), 0.0)
	assert_eq(player.external_knockback_velocity(), Vector2.ZERO)
	assert_eq(player.external_knockback_remaining(), 0.0)
	assert_eq(player.dash_cooldown_remaining(), cooldown_before)
	assert_eq(player.current_life(), 61.0)

	GameState.change_state(previous_state, previous_context)


func test_choice_panel_sorts_destinations_and_only_maps_supplied_valid_stations() -> void:
	var panel: CanvasLayer = CHOICE_PANEL_SCENE.instantiate() as CanvasLayer
	add_child_autofree(panel)
	var stations: Array[Dictionary] = [
		_station("station_current", 2, 3, 3, true),
		_station("station_three", 3, 6, 4, false),
		_station("station_one", 1, 0, 2, false),
		_station("invalid_hidden", 4, 9, 9, false),
	]

	assert_true(bool(panel.call("configure", "station_current", stations)))
	assert_eq(panel.call("destination_ids"), ["station_one", "station_three"])
	assert_eq(
		panel.call("minimap_station_ids"),
		["station_current", "station_three", "station_one"]
	)
	panel.call("show_feedback", "ui_teleport_failed")
	var description: Label = panel.get_node(
		"Root/Center/TeleportChoicePanelFrame/Margin/Layout/DescriptionLabel"
	) as Label
	assert_eq(description.text, tr("ui_teleport_failed"))
	panel.call("set_input_locked", true)
	panel.call("request_close")
	assert_true(panel.has_signal("destination_selected"))


func test_choice_panel_rejects_open_when_only_source_is_discovered() -> void:
	var panel: CanvasLayer = CHOICE_PANEL_SCENE.instantiate() as CanvasLayer
	add_child_autofree(panel)
	var stations: Array[Dictionary] = [
		_station("station_current", 1, 0, 2, true),
	]
	assert_false(bool(panel.call("configure", "station_current", stations)))
	assert_true((panel.call("destination_ids") as Array).is_empty())


func test_interactable_and_camera_expose_teleport_interfaces() -> void:
	var interactable: Node2D = INTERACTABLE_SCENE.instantiate() as Node2D
	add_child_autofree(interactable)
	interactable.call("configure", "teleporter_0_2_5_5", 180.0)
	interactable.call("set_station_number", 1)
	var player_node := Node2D.new()
	add_child_autofree(player_node)
	player_node.global_position = Vector2(179.0, 0.0)
	assert_true(bool(interactable.call("can_player_interact", player_node)))
	player_node.global_position = Vector2(181.0, 0.0)
	assert_false(bool(interactable.call("can_player_interact", player_node)))
	assert_eq(interactable.call("station_id"), "teleporter_0_2_5_5")

	var camera_controller: GameplayCameraController = (
		CAMERA_SCENE.instantiate() as GameplayCameraController
	)
	add_child_autofree(camera_controller)
	assert_public_api(camera_controller, &"snap_to_target")


func test_fade_transition_commits_at_black_and_returns_result() -> void:
	var overlay: CanvasLayer = FADE_OVERLAY_SCENE.instantiate() as CanvasLayer
	add_child_autofree(overlay)
	var commit_calls: Array[bool] = []
	var succeeded: bool = await overlay.call(
		"transition",
		func() -> bool:
			commit_calls.append(true)
			return true,
		0.0,
		0.0
	)
	assert_true(succeeded)
	assert_eq(commit_calls.size(), 1)
	assert_false(bool(overlay.call("is_transitioning")))


func _station(
	station_id: String,
	station_number: int,
	module_x: int,
	module_y: int,
	is_current: bool
) -> Dictionary:
	return {
		"station_id": station_id,
		"station_number": station_number,
		"module_coord": {"x": module_x, "y": module_y},
		"is_current": is_current,
	}


class SimulationProbe extends Node:
	var processed_frames: int = 0


	func _process(_delta: float) -> void:
		processed_frames += 1
