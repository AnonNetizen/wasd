extends SmokeHarness


const VFX_CUES := preload("res://scripts/contracts/vfx_cues.gd")
const PRESENTATION_ENEMY_DEFAULT: String = "presentation_enemy_default"
const PRESENTATION_PLAYER_DEFAULT: String = "presentation_player_default"


func test_actor_profile_resolution_uses_profile_then_fallbacks() -> void:
	var controller := GameplayFeedbackController.new()
	var actor := Node2D.new()
	var presentation := FakePresentation.new()
	presentation.name = "Presentation"
	presentation.profile_id = PRESENTATION_ENEMY_DEFAULT
	actor.add_child(presentation)

	assert_eq(
		controller.resolve_actor_profile_id(actor, PRESENTATION_PLAYER_DEFAULT),
		PRESENTATION_ENEMY_DEFAULT
	)
	presentation.profile_id = ""
	assert_eq(
		controller.resolve_actor_profile_id(actor, PRESENTATION_PLAYER_DEFAULT),
		PRESENTATION_PLAYER_DEFAULT
	)

	var actor_without_presentation := Node2D.new()
	assert_eq(
		controller.resolve_actor_profile_id(
			actor_without_presentation,
			PRESENTATION_PLAYER_DEFAULT
		),
		PRESENTATION_PLAYER_DEFAULT
	)
	assert_eq(
		controller.resolve_actor_profile_id(null, PRESENTATION_PLAYER_DEFAULT),
		PRESENTATION_PLAYER_DEFAULT
	)

	actor_without_presentation.free()
	actor.free()
	controller.free()


func test_actor_profile_configuration_uses_public_presentation_interface() -> void:
	var controller := GameplayFeedbackController.new()
	var actor := Node2D.new()
	var presentation := FakePresentation.new()
	presentation.name = "Presentation"
	actor.add_child(presentation)

	assert_public_api(controller, &"configure_host")
	assert_public_api(controller, &"play")
	assert_public_api(controller, &"configure_actor_profile")
	assert_true(
		controller.configure_actor_profile(actor, PRESENTATION_ENEMY_DEFAULT)
	)
	assert_eq(presentation.profile_id, PRESENTATION_ENEMY_DEFAULT)

	var actor_without_presentation := Node2D.new()
	assert_false(
		controller.configure_actor_profile(
			actor_without_presentation,
			PRESENTATION_PLAYER_DEFAULT
		)
	)

	actor_without_presentation.free()
	actor.free()
	controller.free()


func test_play_actor_resolves_profile_and_adds_non_aliasing_context() -> void:
	var controller := RecordingFeedbackController.new()
	var actor := Node2D.new()
	actor.position = Vector2(120.0, 80.0)
	var presentation := FakePresentation.new()
	presentation.name = "Presentation"
	presentation.profile_id = PRESENTATION_ENEMY_DEFAULT
	actor.add_child(presentation)
	var source_context: Dictionary = {
		"payload": {"amount": 5.0},
	}

	var handles: Array[VfxHandle] = controller.play_actor(
		actor,
		PRESENTATION_PLAYER_DEFAULT,
		VFX_CUES.HIT,
		source_context
	)

	assert_true(handles.is_empty())
	assert_eq(controller.captured_profile_id, PRESENTATION_ENEMY_DEFAULT)
	assert_eq(controller.captured_cue, VFX_CUES.HIT)
	assert_eq(controller.captured_context.get("owner"), actor)
	assert_eq(
		controller.captured_context.get("world_position"),
		Vector2(120.0, 80.0)
	)
	assert_false(source_context.has("owner"))
	assert_false(source_context.has("world_position"))
	(controller.captured_context["payload"] as Dictionary)["amount"] = 9.0
	assert_eq(source_context.get("payload"), {"amount": 5.0})

	var explicit_context: Dictionary = {
		"owner": null,
		"world_position": Vector2(-40.0, 24.0),
	}
	controller.play_actor(
		actor,
		PRESENTATION_PLAYER_DEFAULT,
		VFX_CUES.HURT,
		explicit_context
	)
	assert_true(controller.captured_context.has("owner"))
	assert_null(controller.captured_context.get("owner"))
	assert_eq(
		controller.captured_context.get("world_position"),
		Vector2(-40.0, 24.0)
	)

	actor.free()
	controller.free()


func test_player_visual_facades_forward_palette_and_fire_impulse() -> void:
	var player := Player.new()
	var visual := FakeSlimeVisual.new()
	visual.name = "Visual"
	player.add_child(visual)
	var palette: Dictionary = {
		"main_primary": Color("68bcdd"),
		"sub_primary": Color("ed2f72"),
	}
	var shot_direction := Vector2(0.6, -0.8)

	assert_true(player.configure_visual_palette(palette))
	assert_true(player.apply_weapon_fire_visual_impulse(shot_direction))
	assert_eq(visual.configured_palette, palette)
	assert_eq(visual.fire_direction, shot_direction)

	player.free()


func test_player_visual_facades_return_false_without_visual() -> void:
	var player := Player.new()

	assert_false(player.configure_visual_palette({}))
	assert_false(player.apply_weapon_fire_visual_impulse(Vector2.RIGHT))

	player.free()


class FakePresentation:
	extends Node

	var profile_id: String = ""


	func resolved_profile_id(fallback_profile_id: String) -> String:
		return fallback_profile_id if profile_id.is_empty() else profile_id


	func configure_profile_id(next_profile_id: String) -> void:
		profile_id = next_profile_id.strip_edges()


class RecordingFeedbackController:
	extends GameplayFeedbackController

	var captured_profile_id: String = ""
	var captured_cue: String = ""
	var captured_context: Dictionary = {}


	func play(
		profile_id: String,
		cue: String,
		context: Dictionary = {}
	) -> Array[VfxHandle]:
		captured_profile_id = profile_id
		captured_cue = cue
		captured_context = context
		var handles: Array[VfxHandle] = []
		return handles


class FakeSlimeVisual:
	extends Node2D

	var configured_palette: Dictionary = {}
	var fire_direction: Vector2 = Vector2.ZERO


	func configure_palette(palette: Dictionary) -> void:
		configured_palette = palette.duplicate(true)


	func configure_radius(_radius: float) -> void:
		pass


	func advance_visual(
		_delta: float,
		_motion_velocity: Vector2,
		_aim_direction: Vector2
	) -> void:
		pass


	func apply_fire_impulse(direction: Vector2) -> void:
		fire_direction = direction
