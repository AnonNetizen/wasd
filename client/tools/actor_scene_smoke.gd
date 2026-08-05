extends Node


const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const ENEMY_BASE_PATH: String = "res://scenes/gameplay/actors/enemy_base.tscn"
const ENEMY_SCRIPT := preload("res://scripts/gameplay/enemy.gd")
const GAMEPLAY_RUN_LOOP_SCENE := preload("res://scenes/gameplay/gameplay_run_loop.tscn")
const PLAYER_BASE_PATH: String = "res://scenes/gameplay/actors/player_base.tscn"
const PLAYER_SCRIPT := preload("res://scripts/gameplay/player.gd")
const PLAYER_RADIUS: float = 25.0
const PLAYER_MUZZLE_DISTANCE: float = 38.0
const CALM_PRIMARY := Color("68bcdd")
const ANGRY_PRIMARY := Color("ed2f72")

var _failures: Array[String] = []
var _restore_failure_observed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var characters: Array[Dictionary] = _dictionary_array(
		DataLoader.load_json(DataLoader.CHARACTERS_PATH).get("characters", [])
	)
	var enemies: Array[Dictionary] = DataLoader.load_csv(DataLoader.ENEMIES_PATH)
	_expect(not characters.is_empty(), "character data should not be empty")
	_expect(enemies.size() == 5, "current enemy data should contain five enemies")

	for character: Dictionary in characters:
		_validate_actor_scene(character, PLAYER_BASE_PATH, PLAYER_SCRIPT, true)
	for enemy: Dictionary in enemies:
		_validate_actor_scene(enemy, ENEMY_BASE_PATH, ENEMY_SCRIPT, false)
		_validate_enemy_configuration(enemy)

	var default_scene_path: String = _character_scene_path(
		characters,
		CHARACTER_IDS.CHARACTER_PRIMARY_A
	)
	_expect(
		not default_scene_path.is_empty(),
		"default new-run character should resolve to a dedicated scene"
	)
	var restored_scene_path: String = _character_scene_path(
		characters,
		CHARACTER_IDS.CHARACTER_PRIMARY_A
	)
	_expect(
		restored_scene_path == default_scene_path,
		"saved character id should resolve through the same data binding"
	)
	_validate_enemy_pools(enemies)
	_validate_enemy_pool_registration_rollback(enemies)
	_validate_run_loop_camera_rig()
	_validate_missing_run_loop_camera_fails_restore()

	if _failures.is_empty():
		print("[actor-scene-smoke] PASS")
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("[actor-scene-smoke] %s" % failure)
	get_tree().quit(1)


func _validate_actor_scene(
	actor_data: Dictionary,
	expected_base_path: String,
	expected_script: Script,
	is_player: bool
) -> void:
	var actor_id: String = String(actor_data.get("id", ""))
	var scene_path: String = String(actor_data.get("scene_path", ""))
	var actor_scene: PackedScene = load(scene_path) as PackedScene
	_expect(actor_scene != null, "%s should load a PackedScene" % actor_id)
	if actor_scene == null:
		return
	var base_state: SceneState = actor_scene.get_state().get_base_scene_state()
	_expect(base_state != null, "%s should be an inherited scene" % actor_id)
	if base_state != null:
		_expect(
			base_state.get_path() == expected_base_path,
			"%s should inherit %s" % [actor_id, expected_base_path]
		)
	var actor: Node = actor_scene.instantiate()
	_expect(actor is CharacterBody2D, "%s root should be CharacterBody2D" % actor_id)
	_expect(actor.get_script() == expected_script, "%s should keep the base actor script" % actor_id)
	_expect(actor.get_node_or_null("CollisionShape2D") is CollisionShape2D, "%s should have CollisionShape2D" % actor_id)
	_expect(actor.get_node_or_null("Visual") is Node2D, "%s should have a Visual subtree" % actor_id)
	_expect(actor.scene_file_path == scene_path, "%s instance should retain its dedicated scene path" % actor_id)
	if is_player:
		_expect(
			actor.get_node_or_null("GameplayCameraController") == null,
			"%s should not own the run-level GameplayCameraController" % actor_id
		)
		_expect(actor.get_node_or_null("WeaponSystem") != null, "%s should have WeaponSystem" % actor_id)
		get_tree().root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		_validate_player_visual(actor, actor_data, actor_scene)
	else:
		_expect(actor.get_node_or_null("StatusEffectComponent") != null, "%s should have StatusEffectComponent" % actor_id)
	actor.free()


func _validate_player_visual(
	actor: Node,
	actor_data: Dictionary,
	actor_scene: PackedScene
) -> void:
	var player_data: Dictionary = DataLoader.load_json(DataLoader.PLAYER_DATA_PATH)
	actor.call("configure", player_data.get("base_stats", {}))
	actor.call("configure_runtime_rules", player_data)
	var actor_id: String = String(actor_data.get("id", ""))
	var visual: PlayerSlimeVisual = (
		actor.get_node_or_null("Visual") as PlayerSlimeVisual
	)
	var collision: CollisionShape2D = (
		actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	)
	var body: Polygon2D = actor.get_node_or_null("Visual/Body") as Polygon2D
	var outline: Line2D = actor.get_node_or_null("Visual/Outline") as Line2D
	var wet_rim: Line2D = actor.get_node_or_null("Visual/WetRim") as Line2D
	var beam: Line2D = (
		actor.get_node_or_null("Visual/Direction/FacingBeam") as Line2D
	)
	_expect(visual != null, "%s Visual should use PlayerSlimeVisual" % actor_id)
	_expect(body != null, "%s should retain Visual/Body Polygon2D" % actor_id)
	_expect(outline != null, "%s should use a Line2D Outline" % actor_id)
	_expect(wet_rim != null, "%s should expose the shared-boundary WetRim" % actor_id)
	_expect(beam != null, "%s should expose Direction/FacingBeam" % actor_id)
	_expect(actor.get_node_or_null("Visual/Direction/FacingLine") == null, "%s should remove FacingLine" % actor_id)
	_expect(actor.get_node_or_null("Visual/Direction/FacingArrow") == null, "%s should remove FacingArrow" % actor_id)
	_expect(actor.get_node_or_null("Visual/Direction/Eye") == null, "%s should remove Eye" % actor_id)
	if collision != null and collision.shape is CircleShape2D:
		_expect(
			is_equal_approx((collision.shape as CircleShape2D).radius, PLAYER_RADIUS),
			"%s collision radius should be 25 px" % actor_id
		)
	_expect(
		is_equal_approx(float(actor.call("hit_radius")), PLAYER_RADIUS),
		"%s hit radius should match player.json body.radius" % actor_id
	)
	if outline != null:
		_expect(is_equal_approx(outline.width, 3.0), "%s Outline should be 3 px" % actor_id)
	if wet_rim != null:
		_expect(is_equal_approx(wet_rim.width, 1.0), "%s WetRim should be 1 px" % actor_id)
	if beam != null and beam.points.size() >= 2:
		_expect(
			beam.points[1].is_equal_approx(Vector2(PLAYER_MUZZLE_DISTANCE, 0.0)),
			"%s facing beam should end at 38 px" % actor_id
		)
	_expect(
		(actor.get_node("VfxAnchors/Ground") as Marker2D).position.is_equal_approx(Vector2(0.0, 25.0)),
		"%s Ground anchor should follow the 25 px body" % actor_id
	)
	_expect(
		(actor.get_node("VfxAnchors/Overhead") as Marker2D).position.is_equal_approx(Vector2(0.0, -36.0)),
		"%s Overhead anchor should be -36 px" % actor_id
	)
	_expect(
		(actor.get_node("VfxAnchors/Forward/Muzzle") as Marker2D).position.is_equal_approx(Vector2(38.0, 0.0)),
		"%s Muzzle anchor should be 38 px" % actor_id
	)
	_expect(
		(actor.get_node("WorldPrompt") as Node2D).position.is_equal_approx(Vector2(0.0, -58.0)),
		"%s world prompt should be -58 px" % actor_id
	)
	if visual == null:
		return

	var main_primary: Color = (
		CALM_PRIMARY
		if actor_id == CHARACTER_IDS.CHARACTER_PRIMARY_A
		else ANGRY_PRIMARY
	)
	var sub_primary: Color = (
		ANGRY_PRIMARY
		if actor_id == CHARACTER_IDS.CHARACTER_PRIMARY_A
		else CALM_PRIMARY
	)
	visual.configure_palette({
		"main_primary": main_primary,
		"sub_primary": sub_primary,
	})
	_expect(visual.control_point_count() == 20, "%s should keep 20 controls" % actor_id)
	_expect(visual.boundary_point_count() == 100, "%s should render 100 boundary points" % actor_id)
	_expect(
		visual.palette_state() == {
			"main_primary": main_primary,
			"sub_primary": sub_primary,
		},
		"%s should expose only main/sub primary" % actor_id
	)
	if outline != null:
		_expect(outline.default_color.is_equal_approx(main_primary), "%s Outline should use main primary" % actor_id)
	if wet_rim != null:
		_expect(
			wet_rim.default_color.is_equal_approx(main_primary.lightened(0.28)),
			"%s WetRim should derive only from main primary" % actor_id
		)
	var material: ShaderMaterial = visual.body_material()
	_expect(material != null, "%s should use a scene-authored ShaderMaterial" % actor_id)
	if material != null:
		_expect(
			(material.get_shader_parameter("main_primary") as Color).is_equal_approx(main_primary)
			and (material.get_shader_parameter("sub_primary") as Color).is_equal_approx(sub_primary),
			"%s Shader should receive both fragment primaries" % actor_id
		)
	var beam_colors: PackedColorArray = visual.beam_gradient_colors()
	_expect(
		beam_colors.size() == 3
		and _color_rgb_close(beam_colors[1], main_primary),
		"%s facing beam should use the main primary" % actor_id
	)
	if actor_id != CHARACTER_IDS.CHARACTER_PRIMARY_A:
		return

	var initial_node_count: int = visual.visual_node_count()
	var initial_resource_ids: PackedInt64Array = visual.material_instance_ids()
	var minimum_area: float = INF
	var maximum_area: float = -INF
	var maximum_extent: float = 0.0
	var maximum_turn: float = 0.0
	var maximum_neighbor_delta: float = 0.0
	for frame: int in range(720):
		var motion := Vector2(
			sin(float(frame) * 0.071),
			cos(float(frame) * 0.053)
		) * (750.0 if frame % 180 < 24 else 240.0)
		var aim := Vector2.RIGHT.rotated(float(frame) * 0.019)
		if frame % 47 == 0:
			visual.apply_fire_impulse(aim)
		visual.advance_visual(1.0 / 60.0, motion, aim)
		minimum_area = minf(minimum_area, visual.current_area_ratio())
		maximum_area = maxf(maximum_area, visual.current_area_ratio())
		if frame % 12 == 0 or frame == 719:
			maximum_extent = maxf(maximum_extent, visual.maximum_render_extent())
			maximum_turn = maxf(
				maximum_turn,
				visual.maximum_render_turn_degrees()
			)
			maximum_neighbor_delta = maxf(
				maximum_neighbor_delta,
				visual.maximum_neighbor_displacement_delta()
			)
	_expect(minimum_area >= 0.82 and maximum_area <= 1.18, "%s soft body area should remain bounded" % actor_id)
	_expect(maximum_extent <= PLAYER_RADIUS + 0.001, "%s rendered extent should remain inside 25 px" % actor_id)
	_expect(maximum_turn <= 18.0, "%s boundary turn should remain bounded" % actor_id)
	_expect(maximum_neighbor_delta <= 2.8, "%s neighboring displacement should remain bounded" % actor_id)
	_expect(visual.last_impulse_control_count() == 5, "%s fire should affect five controls" % actor_id)
	_expect(visual.last_impulse_controls_are_contiguous(), "%s fire controls should be contiguous" % actor_id)
	_expect(visual.visual_node_count() == initial_node_count, "%s simulation should not create nodes" % actor_id)
	_expect(visual.material_instance_ids() == initial_resource_ids, "%s simulation should not replace materials" % actor_id)

	var presentation: ActorPresentationController = (
		actor.get_node_or_null("Presentation") as ActorPresentationController
	)
	if presentation != null and material != null:
		presentation.configure_visual(Color.WHITE, Color("ff574f"), Color("7d4cff"), 1.0)
		presentation.set("hit_progress", 0.5)
		_expect(
			(material.get_shader_parameter("presentation_tint") as Color).is_equal_approx(Color("ff574f")),
			"%s hit presentation should tint the Shader visual" % actor_id
		)
		presentation.set("hit_progress", -1.0)
		presentation.set("defeat_progress", 0.5)
		_expect(visual.scale.x > 1.0 and visual.scale.y > 1.0, "%s defeat should scale the Shader visual" % actor_id)
		_expect(outline != null and outline.modulate.a < 1.0, "%s defeat should fade Line2D rims" % actor_id)
		presentation.reset_presentation()

	var peer: Node = actor_scene.instantiate()
	get_tree().root.add_child(peer)
	peer.process_mode = Node.PROCESS_MODE_DISABLED
	peer.call("configure", player_data.get("base_stats", {}))
	peer.call("configure_runtime_rules", player_data)
	var peer_visual: PlayerSlimeVisual = (
		peer.get_node_or_null("Visual") as PlayerSlimeVisual
	)
	var peer_collision: CollisionShape2D = (
		peer.get_node_or_null("CollisionShape2D") as CollisionShape2D
	)
	_expect(
		peer_visual != null
		and peer_visual.material_instance_ids() != initial_resource_ids,
		"%s instances should not share ShaderMaterial or Gradient state" % actor_id
	)
	_expect(
		collision != null
		and peer_collision != null
		and collision.shape.get_instance_id() != peer_collision.shape.get_instance_id(),
		"%s instances should not share collision Shape state" % actor_id
	)
	peer.free()


func _validate_run_loop_camera_rig() -> void:
	var run_loop: Node = GAMEPLAY_RUN_LOOP_SCENE.instantiate()
	var active_world: Node = run_loop.get_node_or_null("ActiveWorld")
	var camera_controller: Node = run_loop.get_node_or_null(
		"ActiveWorld/GameplayCameraController"
	)
	_expect(active_world != null, "GameplayRunLoop should own ActiveWorld")
	_expect(
		camera_controller is Node2D,
		"ActiveWorld should own one GameplayCameraController rig"
	)
	_expect(
		camera_controller != null and camera_controller.get_parent() == active_world,
		"GameplayCameraController should be a direct ActiveWorld child"
	)
	_expect(
		run_loop.find_children("GameplayCameraController", "", true, false).size() == 1,
		"GameplayRunLoop should contain exactly one GameplayCameraController"
	)
	if camera_controller != null:
		_expect(
			camera_controller.get_node_or_null("CenteredCamera") is Camera2D,
			"camera rig should retain CenteredCamera"
		)
		_expect(
			camera_controller.get_node_or_null("CenteredCamera/PhantomCameraHost") != null,
			"camera rig should retain PhantomCameraHost"
		)
		_expect(
			camera_controller.get_node_or_null("PlayerCamera") is Node2D,
			"camera rig should retain PlayerCamera"
		)
		_expect(
			camera_controller.get_node_or_null("PlayerDamageShake") != null,
			"camera rig should retain PlayerDamageShake"
		)
	run_loop.free()


func _validate_missing_run_loop_camera_fails_restore() -> void:
	var run_loop: Node = GAMEPLAY_RUN_LOOP_SCENE.instantiate()
	var camera_controller: Node = run_loop.get_node_or_null(
		"ActiveWorld/GameplayCameraController"
	)
	if camera_controller != null:
		camera_controller.free()
	_restore_failure_observed = false
	run_loop.connect("restore_failed", _on_restore_failure_observed)
	run_loop.call("configure_restore_snapshot", {
		"character": CHARACTER_IDS.CHARACTER_PRIMARY_A,
	})
	get_tree().root.add_child(run_loop)
	_expect(
		_restore_failure_observed,
		"missing run-level camera rig should fail closed during restore"
	)
	run_loop.free()


func _on_restore_failure_observed() -> void:
	_restore_failure_observed = true


func _validate_enemy_configuration(enemy_row: Dictionary) -> void:
	var scene_path: String = String(enemy_row.get("scene_path", ""))
	var enemy_scene: PackedScene = load(scene_path) as PackedScene
	if enemy_scene == null:
		return
	var enemy: CharacterBody2D = enemy_scene.instantiate() as CharacterBody2D
	if enemy == null:
		return
	var target := Node2D.new()
	get_tree().root.add_child(target)
	get_tree().root.add_child(enemy)
	enemy.process_mode = Node.PROCESS_MODE_DISABLED
	var body: Polygon2D = enemy.get_node_or_null("Visual/Body") as Polygon2D
	var collision: CollisionShape2D = enemy.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var original_color: Color = enemy.call("visual_color")
	var original_polygon: PackedVector2Array = body.polygon.duplicate() if body != null else PackedVector2Array()
	enemy.call("configure", _runtime_enemy_data(enemy_row), target, null)
	var configured_color: Color = enemy.call("visual_color")
	var exploder_core: Polygon2D = enemy.get_node_or_null(
		"Visual/ExploderCore"
	) as Polygon2D
	var bulwark_armor: Polygon2D = enemy.get_node_or_null(
		"Visual/BulwarkArmor"
	) as Polygon2D
	_expect(
		configured_color.is_equal_approx(original_color),
		"%s configure should not override scene-authored color" % enemy_row.get("id", "")
	)
	_expect(
		exploder_core != null
		and exploder_core.visible
		== (String(enemy_row.get("id", "")) == "enemy_chaser"),
		"%s should expose the correct exploder-core silhouette"
		% enemy_row.get("id", "")
	)
	_expect(
		bulwark_armor != null
		and bulwark_armor.visible
		== (String(enemy_row.get("id", "")) == "enemy_bulwark"),
		"%s should expose the correct frontal-armor silhouette"
		% enemy_row.get("id", "")
	)
	if body != null:
		_expect(
			body.polygon == original_polygon,
			"%s configure should not replace normalized scene geometry" % enemy_row.get("id", "")
		)
	if collision != null and collision.shape is CircleShape2D:
		_expect(
			is_equal_approx(
				(collision.shape as CircleShape2D).radius,
				String(enemy_row.get("hit_radius", "0")).to_float()
			),
			"%s collision radius should remain data-driven" % enemy_row.get("id", "")
		)
	var presentation: ActorPresentationController = (
		enemy.get_node_or_null("Presentation") as ActorPresentationController
	)
	if presentation != null and body != null:
		var fallback_hit := Color("ff574f")
		presentation.configure_visual(original_color, fallback_hit, fallback_hit, 1.0)
		presentation.set("hit_progress", 0.5)
		_expect(
			body.color.is_equal_approx(fallback_hit),
			"%s non-Shader presentation fallback should remain intact" % enemy_row.get("id", "")
		)
		presentation.reset_presentation()
	enemy.free()
	target.free()


func _validate_enemy_pools(enemies: Array[Dictionary]) -> void:
	var acquired: Dictionary = {}
	for enemy_row: Dictionary in enemies:
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		var scene_path: String = String(enemy_row.get("scene_path", ""))
		PoolManager.clear_pool(pool_id)
		_expect(
			PoolManager.register_pool(
				pool_id,
				Callable(self, "_instantiate_scene").bind(scene_path),
				4
			),
			"%s pool should register from its dedicated PackedScene" % pool_id
		)
		PoolManager.prewarm(pool_id, 1)
	for enemy_row: Dictionary in enemies:
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		var expected_path: String = String(enemy_row.get("scene_path", ""))
		var enemy: Node = PoolManager.acquire(pool_id)
		_expect(enemy != null, "%s pool should acquire an enemy" % pool_id)
		if enemy == null:
			continue
		_expect(
			enemy.scene_file_path == expected_path,
			"%s pool should not return another enemy scene" % pool_id
		)
		acquired[pool_id] = enemy.get_instance_id()
		PoolManager.release(enemy)
	for enemy_row: Dictionary in enemies:
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		var expected_path: String = String(enemy_row.get("scene_path", ""))
		var enemy: Node = PoolManager.acquire(pool_id)
		_expect(enemy != null, "%s pool should reacquire an enemy" % pool_id)
		if enemy == null:
			continue
		_expect(
			enemy.get_instance_id() == int(acquired.get(pool_id, 0)),
			"%s pool should reuse its own instance" % pool_id
		)
		_expect(
			enemy.scene_file_path == expected_path,
			"%s reused instance should keep its dedicated scene" % pool_id
		)
		PoolManager.release(enemy)
		PoolManager.clear_pool(pool_id)


func _validate_enemy_pool_registration_rollback(enemies: Array[Dictionary]) -> void:
	if enemies.size() < 2:
		return
	var first_enemy: Dictionary = enemies[0].duplicate(true)
	var duplicate_pool_enemy: Dictionary = enemies[1].duplicate(true)
	var pool_id: String = String(first_enemy.get("pool_id", ""))
	duplicate_pool_enemy["pool_id"] = pool_id
	PoolManager.clear_pool(pool_id)
	var run_loop: Node = GAMEPLAY_RUN_LOOP_SCENE.instantiate()
	run_loop.set("_enemy_rows", {
		String(first_enemy.get("id", "first")): first_enemy,
		String(duplicate_pool_enemy.get("id", "duplicate")): duplicate_pool_enemy,
	})
	_expect(
		bool(run_loop.call("_cache_actor_scene", String(first_enemy.get("scene_path", "")))),
		"rollback fixture should cache the first enemy scene"
	)
	_expect(
		not bool(run_loop.call("_register_enemy_pools")),
		"duplicate enemy pool registration should fail"
	)
	_expect(
		not PoolManager.has_pool(pool_id),
		"failed enemy pool registration should roll back earlier pools"
	)
	run_loop.free()


func _instantiate_scene(scene_path: String) -> Node:
	var actor_scene: PackedScene = load(scene_path) as PackedScene
	return actor_scene.instantiate() if actor_scene != null else null


func _runtime_enemy_data(enemy_row: Dictionary) -> Dictionary:
	var ai_profile_id: String = String(enemy_row.get("ai_profile_id", ""))
	var ai_profile: Dictionary = {}
	var profile_data: Variant = DataLoader.load_json(DataLoader.ENEMY_AI_PROFILES_PATH)
	if profile_data is Dictionary:
		for raw_profile: Variant in (profile_data as Dictionary).get("profiles", []):
			if raw_profile is Dictionary and String((raw_profile as Dictionary).get("id", "")) == ai_profile_id:
				ai_profile = (raw_profile as Dictionary).duplicate(true)
				break
	return {
		"id": String(enemy_row.get("id", "")),
		"pool_id": String(enemy_row.get("pool_id", "")),
		"ai_profile_id": ai_profile_id,
		"ai_profile": ai_profile,
		"presentation_profile_id": String(
			enemy_row.get("presentation_profile_id", "")
		),
		"max_hp": String(enemy_row.get("max_hp", "1")).to_int(),
		"move_speed": String(enemy_row.get("move_speed", "0")).to_float(),
		"gold_value_multiplier": String(
			enemy_row.get("gold_value_multiplier", "0")
		).to_float(),
		"hit_radius": String(enemy_row.get("hit_radius", "1")).to_float(),
		"separation_radius": String(enemy_row.get("separation_radius", "0")).to_float(),
	}


func _character_scene_path(
	characters: Array[Dictionary],
	character_id: String
) -> String:
	for character: Dictionary in characters:
		if String(character.get("id", "")) == character_id:
			return String(character.get("scene_path", ""))
	return ""


func _dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for raw_item: Variant in raw_value as Array:
		if raw_item is Dictionary:
			result.append((raw_item as Dictionary).duplicate(true))
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _color_rgb_close(left: Color, right: Color) -> bool:
	return (
		absf(left.r - right.r) <= 0.001
		and absf(left.g - right.g) <= 0.001
		and absf(left.b - right.b) <= 0.001
	)
